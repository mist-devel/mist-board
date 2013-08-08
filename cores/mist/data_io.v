// SPI data client (rom, floppy, harddisk io)
module data_io (
	// clocks
	input clk_8,
	input reset,
	input [1:0] bus_cycle,
	output reg [31:0] ctrl_out,
 
	// spi interface
	input sdi,
	input sck,
	input ss,
	output sdo,
	
	// dma status interface
	output [4:0] dma_idx,
	input [7:0] dma_data,
	output reg dma_ack,

	output reg br,
	
	// ram interface
	output reg [2:0] state, // state bits required to drive the sdram host
	output [22:0] addr,
	output reg [15:0] data_out, // write data register
	input [15:0] data_in,
	input ack
);
  
assign dma_idx = bcnt;
  
reg [4:0] cnt;   // bit counter (counting spi bits, rolling from 23 to 8)
reg [4:0] bcnt;  // payload byte counter
reg [14:0] sbuf; // receive buffer (buffer used to assemble spi bytes/words)
reg [7:0] cmd;   // command byte (first byte of spi transmission)
reg [30:0] addrR;// address register (word address for memory transfers)
reg write;       // write request received via SPI
reg writeD;      // write synchonized to 8Mhz clock
reg writeD2;     // synchronized write delayed by one 8Mhz clock
reg read;        // read request received via SPI
reg readD;       // read synchonized to 8Mhz clock
reg readD2;      // synchronized read delayed by one 8Mhz clock
	
// during write the address needs to be decremented by one as the
// address auto increment takes place at the beginning of each transfer
assign addr = addrR[22:0] - ((cmd == 2)?23'b1:23'b0);

// generate state signals required to control the sdram host interface
always @(posedge clk_8) begin
	// start io transfers clock cycles after bus_cycle 0 
        // (after the cpu cycle)
	writeD <= write && ((bus_cycle == 3) || writeD);
	writeD2 <= writeD;
	readD <= read && ((bus_cycle == 3) || readD);
	readD2 <= readD;

	if(reset)
		state <= 3'b101;
	else begin
		if(writeD && ~writeD2)	
			state <= 3'b011;       // write data
		else if(readD && ~readD2)
			state <= 3'b010;		  // read data
		else
			state <= 3'b001;       // decode (idle)
	end
end

reg [15:0] txData;
assign sdo = txData[15];

always@(negedge sck) begin
	// memory read
	if(cmd == 3) begin
	   if(cnt == 8)
			txData <= data_in;
		else
			txData[15:1] <= txData[14:0];
	end

	// dma status read
	if(cmd == 5) begin
	   if((cnt == 8) || (cnt == 16))
			txData[15:8] <= dma_data;
		else
			txData[15:1] <= txData[14:0];
	end
end

always@(posedge sck, posedge ss) begin
	if(ss == 1'b1) begin
      cnt <= 5'd0;
      bcnt <= 4'd0;
		write <= 1'b0;
		read <= 1'b0;
		dma_ack <= 1'b0;
	end else begin
		dma_ack <= 1'b0;
		sbuf <= { sbuf[13:0], sdi};

		// 0:7 is command, 8:15 and 16:23 is payload bytes
		if(cnt < 5'd23)
			cnt <= cnt + 5'd1;
		else
			cnt <= 5'd8;

		// count payload bytes
		if((cnt == 15) || (cnt == 23))
			bcnt <= bcnt + 4'd1;
			
      if(cnt == 5'd7) begin
		   cmd <= {sbuf[6:0], sdi}; 

			// send ack
			if({sbuf[6:0], sdi } == 8'd6)
				dma_ack <= 1'b1;

			// request bus
			if({sbuf[6:0], sdi } == 8'd7)
				br <= 1'b1;

			// release bus
			if({sbuf[6:0], sdi } == 8'd8)
				br <= 1'b0;

			// if we can see a read coming initiate sdram read transfer asap
			if({sbuf[6:0], sdi } == 8'd3)
				read <= 1;
		end
		
		// handle "payload"
		if(cnt >= 8) begin
		
			// set address
			if(cmd == 1)
				addrR <= { addrR[29:0], sdi};
			
			// write ram
			if(cmd == 2) begin
				if(cnt == 5'd16)
					write <= 1'b0;
				
				if(cnt == 5'd23) begin
					data_out <= { sbuf, sdi };
					addrR <= addrR + 31'b1;				
					write <= 1'b1;
				end
			end

			// read ram
			if(cmd == 3) begin
				if(cnt == 16) 
					read <= 0;
				
				if(cnt == 23) begin
					addrR <= addrR + 31'b1;
					read <= 1;
				end				
			end

			// set control register (32 bits written in 2 * 16 bits)
			if((cmd == 4) && (cnt == 5'd23)) begin
			        if(bcnt < 2)
			                ctrl_out[31:16] <= { sbuf, sdi };
		                else
			                ctrl_out[15:0] <= { sbuf, sdi };
			end
		end
	end
end

endmodule