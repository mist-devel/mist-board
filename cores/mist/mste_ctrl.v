//
// mste_ctrl.v
//
// Atari Mega STE cache/cpu controller implementation for the MiST board
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2013 Till Harbaum <till@harbaum.org>
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

module mste_ctrl (
	// cpu register interface
	input 		 clk,
	input 		 reset,
	input [7:0] 	 din,
	input 		 sel,
	input 		 ds,
	input 		 rw,
	output reg [7:0] dout,
	
	output enable_cache,
	output enable_16mhz
);

assign enable_16mhz = mste_config[0];
assign enable_cache = mste_config[1];

reg [7:0] mste_config;

always @(sel, ds, rw, mste_config) begin
	dout = 8'd0;
	if(sel && ~ds && rw)
		dout = mste_config;
end

always @(negedge clk) begin
	if(reset)
		mste_config <= 8'h00;
	else begin
		if(sel && ~ds && ~rw)
			mste_config <= din;
	end
end

endmodule