//
// ipc.v
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

module ipc (
	input 		reset,
	input 		clk_bus,

	input 		ipc_bit_strobe,
	input 		ipc_bit,
	output reg 	ipc_reply_bit,
	output 		ipc_busy,
	
	input 		ps2_kbd_clk,
	input 		ps2_kbd_data
);

assign ipc_busy = 1'b0;

// ---------------------------------------------------------------------------------
// -------------------------------------- KBD --------------------------------------
// ---------------------------------------------------------------------------------

reg key_strobe;
wire [8:0] key;
wire key_available, key_pressed;

keyboard keyboard (
        .reset    ( reset        ),
        .clk      ( clk_bus      ),

        .ps2_clk  ( ps2_kbd_clk  ),
        .ps2_data ( ps2_kbd_data ),

		  .keycode_available ( key_available ),
		  .keycode           ( key           ),
		  .strobe            ( key_strobe    ),
		  .pressed           ( key_pressed   )
);

// ---------------------------------------------------------------------------------
// ----------------------------------- simple IPC ----------------------------------
// ---------------------------------------------------------------------------------

reg [15:0] ipc_reply;
reg [3:0] ipc_unexpected /* synthesis noprune */;
reg [7:0] ipc_reply_len;
reg [3:0] ipc_cmd;
reg [31:0] ipc_len /* synthesis noprune */;

always @(posedge ipc_bit_strobe or posedge reset) begin
	if(reset) begin
		ipc_len <= 32'd0;
		ipc_reply_len <= 8'h00;
		ipc_reply <= 8'h00; 
		ipc_reply_bit <= 1'b0; 
		ipc_unexpected <= 4'h0;
		key_strobe <= 1'b0;
	end else begin
		key_strobe <= 1'b0;

		if(ipc_reply_len == 0) begin
			ipc_cmd <= { ipc_cmd[2:0], ipc_bit};
			ipc_len <= ipc_len + 32'd1;
		
			// last bit of a 4 bit command being written?
			if(ipc_len[1:0] == 2'b11) begin
				case({ ipc_cmd[2:0], ipc_bit }) 
					// request status 
					1: begin	
						// send 8 bit ipc status reply, bit 0 -> 1=kbd data available
						ipc_reply_len <= 8'd8;
						ipc_reply_bit <= 1'b0;
						ipc_reply <= { 7'b0000000, key_available, 8'h00 };
					end
					
					// keyboard
					// nibble: PNNN   N = chars in buffer, P = last key still pressed
					// N*(
					//   nibble: ctrl/alt/shift
					//   byte:   keycode
					// )
					8: begin
						if(key_available) begin
							// currently we can only report one key at once ...
							ipc_reply_len <= 8'd16;
							ipc_reply_bit <= 1'b0;
							ipc_reply <= { 1'b0, 3'd1, 1'b0, key[8:6], 2'b00, key[5:0]};
							key_strobe <= 1'b1;
						end else begin
							// no key to report
							ipc_reply_len <= 8'd4;
							ipc_reply_bit <= 1'b0;
							ipc_reply <= { 1'b0, 3'd0, 12'h000};
						end
					end
					
					default: begin
						if(ipc_unexpected == 0)
							ipc_unexpected <= { ipc_cmd[2:0], ipc_bit };
					end
				endcase;
			end
		end else begin
			// sending reply: shift it out through the ipc_reply_bit register
			ipc_reply_len <= ipc_reply_len - 8'd1;
			ipc_reply_bit <= ipc_reply[15];
			ipc_reply <= { ipc_reply[14:0], 1'b0 }; 
		end
	end
end

endmodule
