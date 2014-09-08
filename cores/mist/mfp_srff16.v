//
// mfp_srff16.v
//
// 16 bit set/reset flip flop. Each bit is set on the rising edge of set
// and asynchronoulsy cleared by the corresponding reset bit
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

module mfp_srff16 (
        input [15:0] set,
        input [15:0] reset,
        output reg [15:0] out
);

always @(posedge set[0] or posedge reset[0]) begin
	if(reset[0]) out[0] <= 1'b0;
	else         out[0] <= 1'b1;
end
	
always @(posedge set[1] or posedge reset[1]) begin
	if(reset[1]) out[1] <= 1'b0;
	else         out[1] <= 1'b1;
end

always @(posedge set[2] or posedge reset[2]) begin
	if(reset[2]) out[2] <= 1'b0;
	else         out[2] <= 1'b1;
end

always @(posedge set[3] or posedge reset[3]) begin
	if(reset[3]) out[3] <= 1'b0;
	else         out[3] <= 1'b1;
end

always @(posedge set[4] or posedge reset[4]) begin
	if(reset[4]) out[4] <= 1'b0;
	else         out[4] <= 1'b1;
end

always @(posedge set[5] or posedge reset[5]) begin
	if(reset[5]) out[5] <= 1'b0;
	else         out[5] <= 1'b1;
end

always @(posedge set[6] or posedge reset[6]) begin
	if(reset[6]) out[6] <= 1'b0;
	else         out[6] <= 1'b1;
end

always @(posedge set[7] or posedge reset[7]) begin
	if(reset[7]) out[7] <= 1'b0;
	else         out[7] <= 1'b1;
end

always @(posedge set[8] or posedge reset[8]) begin
	if(reset[8]) out[8] <= 1'b0;
	else         out[8] <= 1'b1;
end

always @(posedge set[9] or posedge reset[9]) begin
	if(reset[9]) out[9] <= 1'b0;
	else         out[9] <= 1'b1;
end

always @(posedge set[10] or posedge reset[10]) begin
	if(reset[10]) out[10] <= 1'b0;
	else          out[10] <= 1'b1;
end

always @(posedge set[11] or posedge reset[11]) begin
	if(reset[11]) out[11] <= 1'b0;
	else          out[11] <= 1'b1;
end

always @(posedge set[12] or posedge reset[12]) begin
	if(reset[12]) out[12] <= 1'b0;
	else          out[12] <= 1'b1;
end

always @(posedge set[13] or posedge reset[13]) begin
	if(reset[13]) out[13] <= 1'b0;
	else          out[13] <= 1'b1;
end

always @(posedge set[14] or posedge reset[14]) begin
	if(reset[14]) out[14] <= 1'b0;
	else          out[14] <= 1'b1;
end

always @(posedge set[15] or posedge reset[15]) begin
	if(reset[15]) out[15] <= 1'b0;
	else          out[15] <= 1'b1;
end
 
endmodule
