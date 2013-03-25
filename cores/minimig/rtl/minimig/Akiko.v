// Copyright 2012 by Alastair M. Robinson
//
// This file is part of Minimig
//
// Minimig is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Minimig is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
// A minimal implementation of the Akiko C2P register - 16-bit for now, worry about 32-bit
// width later.
//
// -- AMR --
//
// 2012-03-23  - initial version

module akiko
(
	input	clk,
	input	reset,
	input	[23:1] address_in,
	input	[15:0] data_in,
	output	[15:0] data_out,
	input	rd,
	input	sel_akiko	// $B8xxxx
);

//0xb80038 - just the one register, but 32-bits wide.
reg [127:0] shifter;
reg [6:0] wrpointer;
wire sel;

// address decoding
assign sel = sel_akiko && address_in[7:1]==8'b0011_100; // 0x38

always @(posedge clk)
	if (reset)
		wrpointer <= 0;
	else if (!rd && sel)	// write to C2P reg...
	begin
		case(wrpointer)
			0	: shifter[127:112] <= data_in[15:0];
			1	: shifter[111:96] <= data_in[15:0];
			2	: shifter[95:80] <= data_in[15:0];
			3	: shifter[79:64] <= data_in[15:0];
			4	: shifter[63:48] <= data_in[15:0];
			5	: shifter[47:32] <= data_in[15:0];
			6	: shifter[31:16] <= data_in[15:0];
			7  : shifter[15:0] <= data_in[15:0];
		endcase
		wrpointer <= wrpointer + 1;
	end
   else if (rd && sel)	// read from C2P reg
	begin
		shifter[127:0] <= {shifter[126:0],1'b0};
		wrpointer <= 0;
	end

	assign data_out[15:0] = sel_akiko && rd ? {shifter[127],shifter[119],shifter[111],shifter[103],shifter[95],shifter[87],
		shifter[79],shifter[71],shifter[63],shifter[55],shifter[47],shifter[39],shifter[31],
		shifter[23],shifter[15],shifter[7]} : 16'b0 ;

endmodule
