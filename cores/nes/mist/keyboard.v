

module keyboard
(
	input  clk,
	input  reset,
	input  ps2_kbd_clk,
	input  ps2_kbd_data,

	output [7:0] joystick_0,
	output [7:0] joystick_1,
	
	output reg [11:0] powerpad	
);

reg        pressed;
reg        e0;
wire [7:0] keyb_data;
wire       keyb_valid;

// PS/2 interface
ps2_intf ps2(
	clk,
	!reset,
		
	ps2_kbd_clk,
	ps2_kbd_data,

	// Byte-wide data interface - only valid for one clock
	// so must be latched externally if required
	keyb_data,
	keyb_valid
);

reg joy_num;
reg [7:0] buttons;
assign joystick_0 = joy_num ? 7'b0 : buttons;
assign joystick_1 = joy_num ? buttons : 7'b0;

always @(posedge reset or posedge clk) begin
	
	if(reset) begin
		pressed <= 1'b0;
		e0 <= 1'b0;
		joy_num <= 1'b0;
		buttons <= 8'd0;
	end else begin
		if (keyb_valid) begin
			if (keyb_data == 8'HE0)
				e0 <=1'b1;
			else if (keyb_data == 8'HF0)
				pressed <= 1'b0;
			else begin
				case({e0, keyb_data})
					9'H016: if(pressed) joy_num <= 1'b0; // 1
					9'H01E: if(pressed) joy_num <= 1'b1; // 2

					9'H175: buttons[4] <= pressed; // arrow up
					9'H172: buttons[5] <= pressed; // arrow down
					9'H16B: buttons[6] <= pressed; // arrow left
					9'H174: buttons[7] <= pressed; // arrow right
					
					9'H029: buttons[0] <= pressed; // Space
					9'H011: buttons[1] <= pressed; // Left Alt
					9'H00d: buttons[2] <= pressed; // Tab
					9'H076: buttons[3] <= pressed; // Escape
					
					9'H024: powerpad[0] <= pressed;	// E
					9'H02D: powerpad[1] <= pressed;	// R
					9'H02C: powerpad[2] <= pressed;	// T
					9'H035: powerpad[3] <= pressed;	// Y
					9'H023: powerpad[4] <= pressed;	// D
					9'H02B: powerpad[5] <= pressed;	// F
					9'H034: powerpad[6] <= pressed;	// G
					9'H033: powerpad[7] <= pressed;	// H
					9'H021: powerpad[8] <= pressed;	// C
					9'H02A: powerpad[9] <= pressed;	// V
					9'H032: powerpad[10] <= pressed;	// B
					9'H031: powerpad[11] <= pressed;	// N
				endcase;

				pressed <= 1'b1;
				e0 <= 1'b0;
         end 
      end 
   end 
end	

endmodule
