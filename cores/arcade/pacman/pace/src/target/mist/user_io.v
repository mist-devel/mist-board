module user_io(
	   input      SPI_CLK,
	   input      SPI_SS_IO,
	   output     reg SPI_MISO,
	   input      SPI_MOSI,
	   input [7:0] CORE_TYPE,
		output [5:0] JOY0,
		output [5:0] JOY1,
		output [1:0] BUTTONS,
		output [1:0] SWITCHES
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
   
   always@(negedge SPI_CLK) begin
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
		
   always@(posedge SPI_CLK) begin
		if(SPI_SS_IO == 1) begin
        cnt <= 0;
		end else begin
			sbuf[6:1] <= sbuf[5:0];
			sbuf[0] <= SPI_MOSI;

			cnt <= cnt + 1;

	      if(cnt == 7) begin
			   cmd[7:1] <= sbuf; 
				cmd[0] <= SPI_MOSI;
		   end	

	      if(cnt == 15) begin
			   if(cmd == 1) begin
					 but_sw[3:1] <= sbuf[2:0]; 
					 but_sw[0] <= SPI_MOSI; 
				end
			   if(cmd == 2) begin
					 joystick0[5:1] <= sbuf[4:0]; 
					 joystick0[0] <= SPI_MOSI; 
				end
			   if(cmd == 3) begin
					 joystick1[5:1] <= sbuf[4:0]; 
					 joystick1[0] <= SPI_MOSI; 
				end
			end	
		end
	end
   
//   always@(posedge clk2) begin
//      LED <= ~LED;
//   end
   
endmodule
