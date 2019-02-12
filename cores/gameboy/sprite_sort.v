//
// sprite_sort.v
//
// Gameboy for the MIST board https://github.com/mist-devel
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

module sprite_sort #(
	parameter WIDTH = 40
)(
  // system signals
   input       clk,
   input       load,
             
   // sort
   input  [8*WIDTH-1:0] x,
   output [6*WIDTH-1:0] idx
);

wire [7:0] in [WIDTH-1:0];

generate
genvar i;

// map 1d input array onto 2d work array
// and 2d result array into 1d output array
for(i=0;i<WIDTH;i=i+1) begin : input_map
	assign in[i] = x[(8*i)+7:8*i];
	assign idx[(6*i)+5:6*i] = index[i];
end
endgenerate
	
reg [5:0]   index [WIDTH-1:0];
reg [7:0]   values [WIDTH-1:0];
wire [WIDTH/2-1:0]   swap0;
wire [7:0]   int_val [WIDTH-1:0];
wire [5:0]   int_idx [WIDTH-1:0];
wire [WIDTH/2-2:0]   swap1;
wire [7:0]   sort_val [WIDTH-1:0];
wire [5:0]   sort_idx [WIDTH-1:0];

// sorting takes 10 clock cycles
reg [3:0] cnt;
always @(posedge clk) begin
	if(load) cnt <= 4'd0;
	if(cnt != 10) cnt <= cnt + 4'd1;
end

generate
   // 1st stage
   for(i=0;i<WIDTH/2;i=i+1) begin : stage1
      assign swap0[i] = values[2*i+0] > values[2*i+1];
      assign int_val[2*i+0] = swap0[i]?values[2*i+1]:values[2*i+0];
      assign int_val[2*i+1] = swap0[i]?values[2*i+0]:values[2*i+1];
      assign int_idx[2*i+0] = swap0[i]?index[2*i+1]:index[2*i+0];
      assign int_idx[2*i+1] = swap0[i]?index[2*i+0]:index[2*i+1];
   end

   // 2nd stage
   assign sort_val[0] = int_val[0];
   assign sort_idx[0] = int_idx[0];
   assign sort_val[WIDTH-1] = int_val[WIDTH-1];
   assign sort_idx[WIDTH-1] = int_idx[WIDTH-1];
   for(i=0;i<WIDTH/2-1;i=i+1) begin : stage4
      assign swap1[i] = int_val[2*i+1] > int_val[2*i+2];
      assign sort_val[2*i+1] = swap1[i]?int_val[2*i+2]:int_val[2*i+1];
      assign sort_val[2*i+2] = swap1[i]?int_val[2*i+1]:int_val[2*i+2];
      assign sort_idx[2*i+1] = swap1[i]?int_idx[2*i+2]:int_idx[2*i+1];
      assign sort_idx[2*i+2] = swap1[i]?int_idx[2*i+1]:int_idx[2*i+2];
   end

   for(i=0;i<WIDTH;i=i+1) begin : advance
		always @(posedge clk) begin
			if(load) begin
				values[i] <= in[i];
				index[i] <= i[5:0];
			end else begin
				values[i] <= sort_val[i];
				index[i] <= sort_idx[i];
			end
		end
	end

endgenerate

endmodule
