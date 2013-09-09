module user_io( 
	   input      SPI_CLK,
	   input      SPI_SS_IO,
	   output     reg SPI_MISO,
	   input      SPI_MOSI,
	   input [7:0] CORE_TYPE,

		// ikbd tdata from io controller to acia
		output reg       ikbd_strobe_in,
		output reg [7:0] ikbd_data_in,
		
		// ikbd data from acia to io controller
		output reg       ikbd_strobe_out,
		input            ikbd_data_out_available,
		input [7:0]      ikbd_data_out,

		// serial data from mfp to io controller
		output reg       serial_strobe_out,
		input            serial_data_out_available,
		input [7:0]       serial_data_out,

		output [1:0] BUTTONS,
		output [1:0] SWITCHES
	   );

	reg 					toggle;
   reg [6:0]         sbuf;
   reg [7:0]         cmd;
   reg [5:0] 	      cnt;
   reg [3:0] 	      but_sw;

	assign BUTTONS = but_sw[1:0];
	assign SWITCHES = but_sw[3:2];
   
   always@(negedge SPI_CLK) begin
      if(cnt <= 7)
		  SPI_MISO <= CORE_TYPE[7-cnt];
		else begin
			// ikbd acia->io controller
			if(cmd == 3) begin
				if(!toggle)
					SPI_MISO <= ikbd_data_out_available;
				else
					SPI_MISO <= ikbd_data_out[15-cnt];
			end
			
			// serial mfp->io controller
			if(cmd == 5) begin
				if(!toggle)
					SPI_MISO <= serial_data_out_available;
				else
					SPI_MISO <= serial_data_out[15-cnt];
			end
		end
	end
		
   always@(posedge SPI_CLK, posedge SPI_SS_IO) begin
		if(SPI_SS_IO == 1) begin
        cnt <= 0;
		  toggle <= 1'b0;
		  ikbd_strobe_in <= 1'b0;
		  ikbd_strobe_out <= 1'b0;
		  serial_strobe_out <= 1'b0;
		end else begin
			sbuf[6:1] <= sbuf[5:0];
			sbuf[0] <= SPI_MOSI;

			// count 0-7 8-15 8-15 8-15
			if(cnt != 6'd15)
				cnt <= cnt + 6'd1;
			else begin
				cnt <= 6'd8;
				toggle <= !toggle;
			end

			// assemble command
	      if(cnt == 7) begin
			   cmd[7:1] <= sbuf; 
				cmd[0] <= SPI_MOSI;
		   end	

			if(cnt == 9) begin
				ikbd_strobe_in <= 1'b0;
				ikbd_strobe_out <= 1'b0;
				serial_strobe_out <= 1'b0;
			end
			
			// payload byte
	      if(cnt == 15) begin
				if(cmd == 1) begin
					 but_sw[3:1] <= sbuf[2:0]; 
					 but_sw[0] <= SPI_MOSI; 
				end

			   if(cmd == 2) begin
					 ikbd_data_in[7:1] <= sbuf; 
					 ikbd_data_in[0] <= SPI_MOSI; 
					 ikbd_strobe_in <= 1'b1;
				end
				
				// give strobe after second ikbd byte (toggle ==1)
			   if((cmd == 3) && toggle)
					 ikbd_strobe_out <= 1'b1;
				
				// give strobe after second serial byte (toggle ==1)
			   if((cmd == 5) && toggle)
					 serial_strobe_out <= 1'b1;
			end
		end
	end
      
endmodule
