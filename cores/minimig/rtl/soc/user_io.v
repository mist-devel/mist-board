module user_io( 
	   input      SPI_CLK,
	   input      SPI_SS_IO,
	   output     reg SPI_MISO,
	   input      SPI_MOSI,
	   input [7:0] CORE_TYPE,

		output [5:0] JOY0,
		output [5:0] JOY1,

		output [2:0] MOUSE_BUTTONS,
		output       KBD_MOUSE_STROBE,
		output [1:0] KBD_MOUSE_TYPE,
		output [7:0] KBD_MOUSE_DATA,

		output [1:0] BUTTONS,
		output [1:0] SWITCHES
	   );

   reg [6:0]         sbuf;
   reg [7:0]         cmd;
   reg [5:0] 	      cnt;
   reg [5:0]         joystick0;
   reg [5:0]         joystick1;
   reg [3:0] 	      but_sw;

	reg               kbd_mouse_strobe;
   reg [1:0]         kbd_mouse_type;
   reg [7:0]         kbd_mouse_data;
   reg [2:0]         mouse_buttons;

	assign JOY0 = joystick0;
	assign JOY1 = joystick1;

	assign KBD_MOUSE_DATA = kbd_mouse_data; // 8 bit movement data
	assign KBD_MOUSE_TYPE = kbd_mouse_type; // 0=mouse x,1=mouse y, 2=keycode, 3=OSD kbd
	assign KBD_MOUSE_STROBE = kbd_mouse_strobe; // strobe, data valid on rising edge
	assign MOUSE_BUTTONS = mouse_buttons; // state of the two mouse buttons

	assign BUTTONS = but_sw[1:0];
	assign SWITCHES = but_sw[3:2];
   
   always@(negedge SPI_CLK) begin
      if(cnt < 8)
		  SPI_MISO <= CORE_TYPE[7-cnt];
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

	      if(cnt == 8) begin
				if(cmd == 4)
				  kbd_mouse_type <= 2'b00;  // first mouse axis
				else if(cmd == 5)
				  kbd_mouse_type <= 2'b10;  // keyboard
		 		else if(cmd == 6)
				  kbd_mouse_type <= 2'b11;  // OSD keyboard	
		   end
				
			// strobe is set whenever a valid byte has been received
	      kbd_mouse_strobe <= 0;
	
				// first payload byte
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
		           // mouse, keyboard or OSD
			   if((cmd == 4)||(cmd == 5)||(cmd == 6)) begin
					 kbd_mouse_data[7:1] <= sbuf[6:0]; 
					 kbd_mouse_data[0] <= SPI_MOSI; 
					 kbd_mouse_strobe <= 1;		
				end
			end	
			
			// mouse handling
			if(cmd == 4) begin

				// second byte contains movement data
				if(cnt == 23) begin
					 kbd_mouse_data[7:1] <= sbuf[6:0]; 
					 kbd_mouse_data[0] <= SPI_MOSI; 
					 kbd_mouse_strobe <= 1;		
					 kbd_mouse_type <= 2'b01;
				end
				
				// third byte contains the buttons
				if(cnt == 31) begin
					 mouse_buttons[2:1] <= sbuf[1:0]; 
					 mouse_buttons[0] <= SPI_MOSI; 
				end
			end
		end
	end
      
endmodule
