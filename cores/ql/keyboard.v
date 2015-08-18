//
// keyboard.v
//
// Sinclair QL for the MiST
// https://github.com/mist-devel
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//

module keyboard ( 
	input clk,
	input reset,

	// ps2 interface	
	input ps2_clk,
	input ps2_data,

	input [4:0] js0,
	input [4:0] js1,
	
	output [63:0] matrix
);

assign matrix = ql_matrix | special_matrix;

// 8x8 ql keyboard matrix
reg [63:0] ql_matrix;

// small matrix for special keys (backspace, ...)
reg [11:0] special;

// check which ql keys are triggered by the special keys
wire x_shift = special[0]  || special[3]  || special[4]   || special[7] ||
			  	   special[8]  || special[9]  || special[10]  || special[11];
wire x_ctrl  = special[1]  || special[2];
wire x_alt   = special[5]  || special[6];

wire x_left  = specialD[1] || specialD[5] || js1[1];
wire x_right = specialD[2] || specialD[6] || js1[0];
wire x_up    = specialD[3] || js1[3];
wire x_down  = specialD[4] || js1[2];
wire x_space = js1[4];

wire x_f1    = specialD[7] || js0[1];
wire x_f2    = specialD[8] || js0[2];
wire x_f3    = specialD[9] || js0[0];
wire x_f4    = specialD[10]|| js0[3];
wire x_f5    = specialD[11]|| js0[4];

// divide 11mhz clock down to ~1khz some delay
wire clk_delay = clk_delay_cnt[9];
reg [9:0] clk_delay_cnt;  // 11mhz/1024
always @(posedge clk)
	clk_delay_cnt <= clk_delay_cnt + 10'd1;

// The "main" key of a combined modifier key needs to be delayed. Otherwise
// the QL will not accept it. E.g. when pressing CTRL-LEFT, the CTRL key needs
// to be pressed first. Pressing both at the same time won't work. We thus delay
// the "other" key like e.g. the LEFT key. Both are released at the same time
wire [11:1] specialD;
delay delay_1( .clk(clk_delay), .reset(reset), .in(special[1]), .out(specialD[1]) );
delay delay_2( .clk(clk_delay), .reset(reset), .in(special[2]), .out(specialD[2]) );
delay delay_3( .clk(clk_delay), .reset(reset), .in(special[3]), .out(specialD[3]) );
delay delay_4( .clk(clk_delay), .reset(reset), .in(special[4]), .out(specialD[4]) );
delay delay_5( .clk(clk_delay), .reset(reset), .in(special[5]), .out(specialD[5]) );
delay delay_6( .clk(clk_delay), .reset(reset), .in(special[6]), .out(specialD[6]) );
delay delay_7( .clk(clk_delay), .reset(reset), .in(special[7]), .out(specialD[7]) );
delay delay_8( .clk(clk_delay), .reset(reset), .in(special[8]), .out(specialD[8]) );
delay delay_9( .clk(clk_delay), .reset(reset), .in(special[9]), .out(specialD[9]) );
delay delay_10(.clk(clk_delay), .reset(reset), .in(special[10]),.out(specialD[10]));
delay delay_11(.clk(clk_delay), .reset(reset), .in(special[11]),.out(specialD[11]));

// map the special keys onto the matrix which is then or'd with the
// normal matrix
wire [63:0] special_matrix = {
   5'b00000, x_alt, x_ctrl, x_shift, 
	8'b00000000,
	8'b00000000,
	8'b00000000,
	8'b00000000,
	8'b00000000,
	x_down, x_space, 1'b0, x_right, 1'b0, x_up, x_left, 1'b0,
	2'b00, x_f5, x_f3, x_f2, 1'b0, x_f1, x_f4
};

// ================================= leyout =============================
// F1     ESC  1   2   3   4   5   6   7   8   9   0   -   =   £   \
// F2     TAB    Q   W   E   R   T   Y   U   I   O   P   [   ]
// F3     CAPS    A   S   D   F   G   H   J   K   L   ;   '      ENTER
// F4     SHIFT     Z   X   C   V   B   N   M   ,   .   /     SHIFT
// F5     CTRL  LEFT RIGHT          SPACE             UP  DOWN   ALT 



// ================================== matrix ============================
//        0      1      2      3      4      5      6      7
//  +-------------------------------------------------------
// 0|    F4     F1      5     F2     F3     F5      4      7
// 1|   Ret   Left     Up    Esc  Right      \  Space   Down
// 2|     ]      z      .      c      b  Pound      m      '
// 3|     [   Caps      k      s      f      =      g      ;
// 4|     l      3      h      1      a      p      d      j
// 5|     9      w      i    Tab      r      -      y      o
// 6|     8      2      6      q      e      0      t      u
// 7| Shift   Ctrl    Alt      x      v      /      n      ,

wire [7:0] byte;
wire valid;
wire error;

reg key_released;
reg key_extended;

always @(posedge clk) begin
	if(reset) begin
      key_released <= 1'b0;
      key_extended <= 1'b0;
		ql_matrix <= 64'd0;
		special <= 12'd0;
	end else begin

		// ps2 decoder has received a valid byte
		if(valid) begin
			if(byte == 8'he0) 
				// extended key code
            key_extended <= 1'b1;
         else if(byte == 8'hf0)
				// release code
            key_released <= 1'b1;
         else begin
				key_extended <= 1'b0;
				key_released <= 1'b0;

				case(byte)
					// modifier keys
					8'h12:  ql_matrix[8*7+0] <= !key_released; // (left) SHIFT
					8'h14:  ql_matrix[8*7+1] <= !key_released; // CTRL
					8'h11:  ql_matrix[8*7+2] <= !key_released; // ALT
					
					// function keys
					8'h05:  ql_matrix[8*0+1] <= !key_released; // F1
					8'h06:  ql_matrix[8*0+3] <= !key_released; // F2
					8'h04:  ql_matrix[8*0+4] <= !key_released; // F3
					8'h0c:  ql_matrix[8*0+0] <= !key_released; // F4
					8'h03:  ql_matrix[8*0+5] <= !key_released; // F5

					// cursor keys
					8'h75:  ql_matrix[8*1+2] <= !key_released; // Up
					8'h72:  ql_matrix[8*1+7] <= !key_released; // Down
					8'h6b:  ql_matrix[8*1+1] <= !key_released; // Left
					8'h74:  ql_matrix[8*1+4] <= !key_released; // Right
						
					8'h1c:  ql_matrix[8*4+4] <= !key_released; // a
					8'h32:  ql_matrix[8*2+4] <= !key_released; // b
					8'h21:  ql_matrix[8*2+3] <= !key_released; // c
					8'h23:  ql_matrix[8*4+6] <= !key_released; // d
					8'h24:  ql_matrix[8*6+4] <= !key_released; // e
					8'h2b:  ql_matrix[8*3+4] <= !key_released; // f
					8'h34:  ql_matrix[8*3+6] <= !key_released; // g
					8'h33:  ql_matrix[8*4+2] <= !key_released; // h
					8'h43:  ql_matrix[8*5+2] <= !key_released; // i
					8'h3b:  ql_matrix[8*4+7] <= !key_released; // j
					8'h42:  ql_matrix[8*3+2] <= !key_released; // k
					8'h4b:  ql_matrix[8*4+0] <= !key_released; // l
					8'h3a:  ql_matrix[8*2+6] <= !key_released; // m
					8'h31:  ql_matrix[8*7+6] <= !key_released; // n
					8'h44:  ql_matrix[8*5+7] <= !key_released; // o
					8'h4d:  ql_matrix[8*4+5] <= !key_released; // p
					8'h15:  ql_matrix[8*6+3] <= !key_released; // q
					8'h2d:  ql_matrix[8*5+4] <= !key_released; // r
					8'h1b:  ql_matrix[8*3+3] <= !key_released; // s
					8'h2c:  ql_matrix[8*6+6] <= !key_released; // t	
					8'h3c:  ql_matrix[8*6+7] <= !key_released; // u
					8'h2a:  ql_matrix[8*7+4] <= !key_released; // v
					8'h1d:  ql_matrix[8*5+1] <= !key_released; // w
					8'h22:  ql_matrix[8*7+3] <= !key_released; // x
					8'h35:  ql_matrix[8*5+6] <= !key_released; // y
					8'h1a:  ql_matrix[8*2+1] <= !key_released; // z

					8'h45:  ql_matrix[8*6+5] <= !key_released; // 0
					8'h16:  ql_matrix[8*4+3] <= !key_released; // 1
					8'h1e:  ql_matrix[8*6+1] <= !key_released; // 2
					8'h26:  ql_matrix[8*4+1] <= !key_released; // 3
					8'h25:  ql_matrix[8*0+6] <= !key_released; // 4
					8'h2e:  ql_matrix[8*0+2] <= !key_released; // 5
					8'h36:  ql_matrix[8*6+2] <= !key_released; // 6
					8'h3d:  ql_matrix[8*0+7] <= !key_released; // 7
					8'h3e:  ql_matrix[8*6+0] <= !key_released; // 8
					8'h46:  ql_matrix[8*5+0] <= !key_released; // 9
	
					8'h5a:  ql_matrix[8*1+0] <= !key_released; // RET
					8'h29:  ql_matrix[8*1+6] <= !key_released; // SPACE
					8'h0d:  ql_matrix[8*5+3] <= !key_released; // TAB
					8'h76:  ql_matrix[8*1+3] <= !key_released; // ESC	
					8'h58:  ql_matrix[8*3+1] <= !key_released; // CAPS
						
					8'h4e:  ql_matrix[8*5+5] <= !key_released; // -
					8'h55:  ql_matrix[8*3+5] <= !key_released; // =
					8'h61:  ql_matrix[8*2+5] <= !key_released; // Pound
					8'h5d:  ql_matrix[8*1+5] <= !key_released; // \

					8'h54:  ql_matrix[8*3+0] <= !key_released; // [
					8'h5b:  ql_matrix[8*2+0] <= !key_released; // ]

					8'h4c:  ql_matrix[8*3+7] <= !key_released; // ;
					8'h52:  ql_matrix[8*2+7] <= !key_released; // '

					8'h41:  ql_matrix[8*7+7] <= !key_released; // ,
					8'h49:  ql_matrix[8*2+2] <= !key_released; // .
					8'h4a:  ql_matrix[8*7+5] <= !key_released; // /

					// special keys that include modifier
               8'h59:  special[0]  <= !key_released;      // SHIFT
					8'h66:  special[1]  <= !key_released;      // Backspace -> CTRL+LEFT
					8'h71:  special[2]  <= !key_released;      // Delete -> CTRL+RIGHT
					8'h7d:  special[3]  <= !key_released;      // PageUp -> SHIFT+UP
					8'h7a:  special[4]  <= !key_released;      // PageDown -> SHIFT+DOWN
					8'h6c:  special[5]  <= !key_released;      // Home -> ALT+LEFT
					8'h69:  special[6]  <= !key_released;      // End -> ALT+RIGHT
					8'h0b:  special[7]  <= !key_released;      // F6 -> SHIFT+F1
					8'h83:  special[8]  <= !key_released;      // F7 -> SHIFT+F2
					8'h0a:  special[9]  <= !key_released;      // F8 -> SHIFT+F3
					8'h01:  special[10] <= !key_released;      // F9 -> SHIFT+F4
					8'h09:  special[11] <= !key_released;      // F10 -> SHIFT+F5
						
				endcase
			end
		end
	end
end

// the ps2 decoder has been taken from the zx spectrum core
ps2_intf ps2_keyboard (
	.CLK		 ( clk             ),
	.nRESET	 ( !reset          ),
	
	// PS/2 interface
	.PS2_CLK  ( ps2_clk         ),
	.PS2_DATA ( ps2_data        ),
	
	// Byte-wide data interface - only valid for one clock
	// so must be latched externally if required
	.DATA		  ( byte   ),
	.VALID	  ( valid  ),
	.ERROR	  ( error  )
);

endmodule

// add delay to special combo keys
module delay (
	input clk,
	input reset,
	input in,
	output out
);

reg [3:0] delay_cnt;
assign out = (delay_cnt == 15);
wire delay_reset = reset || !in;
always @(posedge clk or posedge delay_reset) begin
	if(delay_reset)          delay_cnt <= 4'd0;
	else if(delay_cnt != 15) delay_cnt <= delay_cnt + 4'd1;
end

endmodule // delay
