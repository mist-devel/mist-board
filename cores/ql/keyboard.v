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

	output keycode_available,
	output [8:0] keycode,
	input strobe,
	output reg pressed
);

// F1     ESC  1   2   3   4   5   6   7   8   9   0   -   =   £   \
// F2     TAB    Q   W   E   R   T   Y   U   I   O   P   [   ]
// F3     CAPS    A   S   D   F   G   H   J   K   L   ;   '      ENTER
// F4     SHIFT     Z   X   C   V   B   N   M   ,   .   /     SHIFT
// F5     CTRL  LEFT RIGHT          SPACE             UP  DOWN   ALT 

// buffer to hold up to 8 keys
reg [2:0] modifier;
reg [2:0] key_rptr, key_wptr;
reg [8:0] key_fifo [7:0];

// read from fifo
assign keycode_available = key_rptr != key_wptr;
assign keycode = key_fifo[key_rptr];
always @(posedge strobe or posedge reset) begin
	if(reset) key_rptr <= 3'd0;
	else      key_rptr <= key_rptr + 3'd1;
end
	
// the top most bit is set when the new value is written and cleared
// shortly after when the value itself is stable
always @(negedge ql_key[9] or posedge reset) begin
	if(reset)
		key_wptr <= 3'd0;
	else begin
		if(ql_key[8:6] == 3'b000)
			key_fifo[key_wptr] <= { modifier, ql_key[5:0] };
		else
			key_fifo[key_wptr] <= ql_key[8:0];
			
		key_wptr <= key_wptr + 3'd1;
	end
end

wire released = reset || key_released;
always @(negedge ql_key[9] or posedge released) begin
	if(released)   pressed <= 1'b0;
	else           pressed <= 1'b1;
end

wire [7:0] byte;
wire valid;
wire error;

reg key_released;
reg key_extended;

reg [9:0] ql_key;

always @(posedge clk) begin
	if(reset) begin
		ql_key <= 10'b0;
      key_released <= 1'b0;
      key_extended <= 1'b0;
		modifier <= 3'b000;
	end else begin
		ql_key[9] <= 1'b0;

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

				// SHIFT
				if((byte == 8'h12) || (byte == 8'h59))
					modifier[2] <= !key_released;

				// CTRL
				if(byte == 8'h14)
					modifier[1] <= !key_released;

				// ALT
				if(byte == 8'h11)
					modifier[0] <= !key_released;

				// only key down events are enqueued
				if(!key_released) begin
					case(byte)
						// function keys
						8'h05:  ql_key <= {1'b1, 3'b000, 6'd57};    // F1
						8'h06:  ql_key <= {1'b1, 3'b000, 6'd59};    // F2
						8'h04:  ql_key <= {1'b1, 3'b000, 6'd60};    // F3
						8'h0c:  ql_key <= {1'b1, 3'b000, 6'd56};    // F4
						8'h03:  ql_key <= {1'b1, 3'b000, 6'd61};    // F5

						// cursor keys
						8'h75:  ql_key <= {1'b1, 3'b000, 6'd50};    // Up
						8'h72:  ql_key <= {1'b1, 3'b000, 6'd55};    // Down
						8'h6b:  ql_key <= {1'b1, 3'b000, 6'd49};    // Left
						8'h74:  ql_key <= {1'b1, 3'b000, 6'd52};    // Right
						
						8'h1c:  ql_key <= {1'b1, 3'b000, 6'd28};    // a
						8'h32:  ql_key <= {1'b1, 3'b000, 6'd44};    // b
						8'h21:  ql_key <= {1'b1, 3'b000, 6'd43};    // c
						8'h23:  ql_key <= {1'b1, 3'b000, 6'd30};    // d
						8'h24:  ql_key <= {1'b1, 3'b000, 6'd12};    // e
						8'h2b:  ql_key <= {1'b1, 3'b000, 6'd36};    // f
						8'h34:  ql_key <= {1'b1, 3'b000, 6'd38};    // g
						8'h33:  ql_key <= {1'b1, 3'b000, 6'd26};    // h
						8'h43:  ql_key <= {1'b1, 3'b000, 6'd18};    // i
						8'h3b:  ql_key <= {1'b1, 3'b000, 6'd31};    // j
						8'h42:  ql_key <= {1'b1, 3'b000, 6'd34};    // k
						8'h4b:  ql_key <= {1'b1, 3'b000, 6'd24};    // l
						8'h3a:  ql_key <= {1'b1, 3'b000, 6'd46};    // m
						8'h31:  ql_key <= {1'b1, 3'b000, 6'd06};    // n
						8'h44:  ql_key <= {1'b1, 3'b000, 6'd23};    // o
						8'h4d:  ql_key <= {1'b1, 3'b000, 6'd29};    // p
						8'h15:  ql_key <= {1'b1, 3'b000, 6'd11};    // q
						8'h2d:  ql_key <= {1'b1, 3'b000, 6'd20};    // r
						8'h1b:  ql_key <= {1'b1, 3'b000, 6'd35};    // s
						8'h2c:  ql_key <= {1'b1, 3'b000, 6'd14};    // t
						8'h3c:  ql_key <= {1'b1, 3'b000, 6'd15};    // u
						8'h2a:  ql_key <= {1'b1, 3'b000, 6'd04};    // v
						8'h1d:  ql_key <= {1'b1, 3'b000, 6'd17};    // w
						8'h22:  ql_key <= {1'b1, 3'b000, 6'd03};    // x
						8'h35:  ql_key <= {1'b1, 3'b000, 6'd22};    // y
						8'h1a:  ql_key <= {1'b1, 3'b000, 6'd41};    // z

						8'h45:  ql_key <= {1'b1, 3'b000, 6'd13};    // 0
						8'h16:  ql_key <= {1'b1, 3'b000, 6'd27};    // 1
						8'h1e:  ql_key <= {1'b1, 3'b000, 6'd09};    // 2
						8'h26:  ql_key <= {1'b1, 3'b000, 6'd25};    // 3
						8'h25:  ql_key <= {1'b1, 3'b000, 6'd62};    // 4
						8'h2e:  ql_key <= {1'b1, 3'b000, 6'd58};    // 5
						8'h36:  ql_key <= {1'b1, 3'b000, 6'd10};    // 6
						8'h3d:  ql_key <= {1'b1, 3'b000, 6'd63};    // 7
						8'h3e:  ql_key <= {1'b1, 3'b000, 6'd08};    // 8
						8'h46:  ql_key <= {1'b1, 3'b000, 6'd16};    // 9
	
						8'h5a:  ql_key <= {1'b1, 3'b000, 6'd48};    // RET
						8'h29:  ql_key <= {1'b1, 3'b000, 6'd54};    // SPACE
						8'h0d:  ql_key <= {1'b1, 3'b000, 6'd19};    // TAB
						8'h76:  ql_key <= {1'b1, 3'b000, 6'd51};    // ESC	
						8'h58:  ql_key <= {1'b1, 3'b000, 6'd33};    // CAPS
						
						8'h4e:  ql_key <= {1'b1, 3'b000, 6'd21};    // -
						8'h55:  ql_key <= {1'b1, 3'b000, 6'd37};    // =
						8'h61:  ql_key <= {1'b1, 3'b000, 6'd45};    // Pound
						8'h5d:  ql_key <= {1'b1, 3'b000, 6'd53};    // \

						8'h54:  ql_key <= {1'b1, 3'b000, 6'd32};    // [
						8'h5b:  ql_key <= {1'b1, 3'b000, 6'd40};    // ]

						8'h4c:  ql_key <= {1'b1, 3'b000, 6'd39};    // ;
						8'h52:  ql_key <= {1'b1, 3'b000, 6'd47};    // '

						8'h41:  ql_key <= {1'b1, 3'b000, 6'd07};    // ,
						8'h49:  ql_key <= {1'b1, 3'b000, 6'd42};    // .
						8'h4a:  ql_key <= {1'b1, 3'b000, 6'd05};    // /

						// special keys that include modifier
						8'h66:  ql_key <= {1'b1, 3'b010, 6'd49};    // Backspace -> CTRL+LEFT
						8'h71:  ql_key <= {1'b1, 3'b010, 6'd52};    // Delete -> CTRL+RIGHT
						8'h7d:  ql_key <= {1'b1, 3'b100, 6'd50};    // PageUp -> SHIFT+UP
						8'h7a:  ql_key <= {1'b1, 3'b100, 6'd55};    // PageDown -> SHIFT+DOWN
						8'h6c:  ql_key <= {1'b1, 3'b001, 6'd49};    // Home -> ALT+LEFT
						8'h69:  ql_key <= {1'b1, 3'b001, 6'd52};    // End -> ALT+RIGHT
						8'h0b:  ql_key <= {1'b1, 3'b100, 6'd57};    // F6 -> SHIFT+F1
						8'h83:  ql_key <= {1'b1, 3'b100, 6'd59};    // F7 -> SHIFT+F2
						8'h0a:  ql_key <= {1'b1, 3'b100, 6'd60};    // F8 -> SHIFT+F3
						8'h01:  ql_key <= {1'b1, 3'b100, 6'd56};    // F9 -> SHIFT+F4
						8'h09:  ql_key <= {1'b1, 3'b100, 6'd61};    // F10 -> SHIFT+F5
						
					endcase
				end
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
