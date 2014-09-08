//
// mfp_hbit16.v
//
// determines the index of the highest bit set in a 16 bit array
//
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
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

module mfp_hbit16 (
        input [15:0] value,
        output [15:0] mask,		  
        output [3:0] index		  
);

assign index =
	(value[15]    ==  1'b1)?4'd15:
	(value[15:14] ==  2'b1)?4'd14:
	(value[15:13] ==  3'b1)?4'd13:
	(value[15:12] ==  4'b1)?4'd12:
	(value[15:11] ==  5'b1)?4'd11:
	(value[15:10] ==  6'b1)?4'd10:
	(value[15:9]  ==  7'b1)?4'd9:
	(value[15:8]  ==  8'b1)?4'd8:
	(value[15:7]  ==  9'b1)?4'd7:
	(value[15:6]  == 10'b1)?4'd6:
	(value[15:5]  == 11'b1)?4'd5:
	(value[15:4]  == 12'b1)?4'd4:
	(value[15:3]  == 13'b1)?4'd3:
	(value[15:2]  == 14'b1)?4'd2:
	(value[15:1]  == 15'b1)?4'd1:
	(value[15:0]  == 16'b1)?4'd0:
		4'd0;

assign mask =
	(value[15]    ==  1'b1)?16'h8000:
	(value[15:14] ==  2'b1)?16'h4000:
	(value[15:13] ==  3'b1)?16'h2000:
	(value[15:12] ==  4'b1)?16'h1000:
	(value[15:11] ==  5'b1)?16'h0800:
	(value[15:10] ==  6'b1)?16'h0400:
	(value[15:9]  ==  7'b1)?16'h0200:
	(value[15:8]  ==  8'b1)?16'h0100:
	(value[15:7]  ==  9'b1)?16'h0080:
	(value[15:6]  == 10'b1)?16'h0040:
	(value[15:5]  == 11'b1)?16'h0020:
	(value[15:4]  == 12'b1)?16'h0010:
	(value[15:3]  == 13'b1)?16'h0008:
	(value[15:2]  == 14'b1)?16'h0004:
	(value[15:1]  == 15'b1)?16'h0002:
	(value[15:0]  == 16'b1)?16'h0001:
		16'h0000;

endmodule
