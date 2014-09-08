//
// io_fifo.v
// 
// Atari ST(E) io controller FIFO for the MiST board
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

module io_fifo #(
 parameter DATA_WIDTH = 8,
 parameter DEPTH = 4
)(
	input reset,
	
	input [DATA_WIDTH-1:0] in,
	input in_clk,
	input in_strobe,
	input in_enable,
	
	input out_clk,
	output [DATA_WIDTH-1:0] out,
	input out_strobe,
	input out_enable,

	output empty,
	output data_available,
	output full
);

localparam FIFO_ADDR_BITS = DEPTH;
localparam FIFO_DEPTH = (1 << FIFO_ADDR_BITS);

reg [DATA_WIDTH-1:0] fifo [FIFO_DEPTH-1:0];
reg [FIFO_ADDR_BITS-1:0] writeP, readP;

assign full = (readP == (writeP + 1));
assign empty = (readP == writeP);
assign data_available = (readP != writeP);

// the strobes may not be in the right clock domain, so bring them into the 
// local clock domain
reg in_strobeD, in_strobeD2;
reg out_strobeD, out_strobeD2;

// present current value. If fifo is empty show last value
assign out = data_available?fifo[readP]:fifo[readP-1];

always @(posedge out_clk) begin
	// bring strobes in local clock domain
	out_strobeD <= out_strobe;
	out_strobeD2 <= out_strobeD;
	
	if(reset)
		readP <= 0;
	else begin
		// rising edge on fifo read strobe from io controller
		if((out_strobeD && !out_strobeD2) || out_enable)
			readP <= readP + 1;
	end
end

always @(posedge in_clk) begin
	// bring strobes in local clock domain
	in_strobeD <= in_strobe;
	in_strobeD2 <= in_strobeD;
	
	if(reset)
		writeP <= 0;
	else begin
		// rising edge on strobe signal causes write
		// or in_enable being true
		if((in_strobeD && !in_strobeD2) || in_enable) begin
			fifo[writeP] <= in;
			writeP <= writeP + 1;
		end
	end
end	

endmodule