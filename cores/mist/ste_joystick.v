//
// ste_joystick.v
// 
// Atari STE joystick port implementation for the MiST board
// http://code.google.com/p/mist-board/
// 
// Copyright (c) 2013 Till Harbaum <till@harbaum.org> 
// Modified by Juan Carlos González Amestoy.
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

module ste_joystick (
	// system interface
	input clk,
	input reset,
  
	// cpu register interface
	input [15:0]    din,
	input           sel,
	input [4:0]     addr,
	input           uds,
	input           lds,
	input           rw,
	output reg [15:0] dout 
  );

// no functionality implemented yet  
always @(sel, rw, uds, lds, addr) begin
	dout = 16'h0000;

   if(sel && rw) begin
      if(addr == 5'h00) dout = 16'hffff;   // no fire button pressed
      if(addr == 5'h02) dout = 16'hffff;   // direction set
   end
   
end
	
endmodule
