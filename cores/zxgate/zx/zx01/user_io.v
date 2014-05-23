// MiST user_io

module user_io(
	input      		SPI_CLK,
	input      		SPI_SS_IO,
	output     		reg SPI_MISO,
	input      		SPI_MOSI,
	
	input [7:0] 	CORE_TYPE,
	
	output [5:0] 	JOY0,
	output [5:0] 	JOY1,
	output [1:0] 	BUTTONS,
	output [1:0] 	SWITCHES,
	
	input 	  		clk,
	output	 		ps2_clk,
	output reg 		ps2_data
);

reg [6:0]         sbuf;
reg [7:0]         cmd;
reg [4:0] 	      cnt;
reg [5:0]         joystick0;
reg [5:0]         joystick1;
reg [3:0] 	      but_sw;

assign JOY0 = joystick0;
assign JOY1 = joystick1;
assign BUTTONS = but_sw[1:0];
assign SWITCHES = but_sw[3:2];
   
// drive MISO only when transmitting core id
always@(negedge SPI_CLK or posedge SPI_SS_IO) begin
	if(SPI_SS_IO == 1) begin
	   SPI_MISO <= 1'bZ;
	end else begin
      if(cnt < 8) begin
		  SPI_MISO <= CORE_TYPE[7-cnt];
		end else begin
	     SPI_MISO <= 1'bZ;
		end
   end
end

// 8 byte fifo to store ps2 bytes
localparam PS2_FIFO_BITS = 3;
reg [7:0] ps2_fifo [(2**PS2_FIFO_BITS)-1:0];
reg [PS2_FIFO_BITS-1:0] ps2_wptr;
reg [PS2_FIFO_BITS-1:0] ps2_rptr;

// ps2 transmitter state machine
reg [3:0] ps2_tx_state;
reg [7:0] ps2_tx_byte;
reg ps2_parity;

assign ps2_clk = clk || (ps2_tx_state == 0);

// ps2 transmitter
// Takes a byte from the FIFO and sends it in a ps2 compliant serial format.
always@(posedge clk) begin
	// transmitter is idle?
	if(ps2_tx_state == 0) begin
		// data in fifo present?
		if(ps2_wptr != ps2_rptr) begin
			// load tx register from fifo
			ps2_tx_byte <= ps2_fifo[ps2_rptr];
			ps2_rptr <= ps2_rptr + 1;
			
			// reset parity
			ps2_parity <= 1'b1;
			
			// start transmitter
			ps2_tx_state <= 4'd1;

			// put start bit on data line
			ps2_data <= 1'b0;			// start bit is 0
		end
	end else begin
	
		// transmission of 8 data bits
		if((ps2_tx_state >= 1)&&(ps2_tx_state < 9)) begin
			ps2_data <= ps2_tx_byte[0];			  // data bits
			ps2_tx_byte[6:0] <= ps2_tx_byte[7:1]; // shift down
			if(ps2_tx_byte[0]) 
				ps2_parity <= !ps2_parity;
		end

		// transmission of parity
		if(ps2_tx_state == 9)
			ps2_data <= ps2_parity;
			
		// transmission of stop bit
		if(ps2_tx_state == 10)
			ps2_data <= 1'b1;			// stop bit is 1

		// advance state machine
		if(ps2_tx_state < 11)
			ps2_tx_state <= ps2_tx_state + 4'd1;
		else	
			ps2_tx_state <= 4'd0;
	
	end
end

// SPI receiver
always@(posedge SPI_CLK or posedge SPI_SS_IO) begin
	if(SPI_SS_IO == 1) begin
	   cnt <= 1'b0;
	end else begin
		sbuf[6:0] <= { sbuf[5:0], SPI_MOSI };
		// counter counts 0-7, 8-15, 8-15 ...
		// 0-7 is command, 8-15 is payload
		if(cnt != 15)  cnt <= cnt + 4'd1;
		else				cnt <= 4'd8;

		// finished reading command byte
      if(cnt == 7)
		   cmd <= { sbuf, SPI_MOSI};

      if(cnt == 15) begin
		   if(cmd == 1)
				but_sw <= { sbuf[2:0], SPI_MOSI }; 

			if(cmd == 2)
				joystick0 <= { sbuf[4:0], SPI_MOSI };
				 
			if(cmd == 3)
				joystick1 <= { sbuf[4:0], SPI_MOSI };
				 
		   if(cmd == 5) begin
				// store incoming keyboard bytes in 
				ps2_fifo[ps2_wptr] <= { sbuf, SPI_MOSI }; 
				ps2_wptr <= ps2_wptr + 1;
			end
				
		end	
	end
end
   
endmodule
