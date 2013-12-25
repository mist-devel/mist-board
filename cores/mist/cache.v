//
// cache.v
//
// Atari ST CPU cache implementation for the MiST board
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
//

module cache (
      input 	    clk_128,
      input 	    clk_8,
      input 	    reset, 
      input 	    flush, 
	      
      input [22:0] addr, // cpu word address
      input 	    wr,
      input 	    rd,

      output [15:0] dout,
      output        hit,

		// interface to update entire caches when read from ram
		input [63:0]  din64,
		input         update64
);

reg [3:0] t;
always @(posedge clk_128) begin
	// 128Mhz counter synchronous to 8 Mhz clock
   // force counter to pass state 0 exactly after the rising edge of clk_8
   if(((t == 4'd15) && ( clk_8 == 0)) ||
      ((t ==  4'd0) && ( clk_8 == 1)) ||
      ((t != 4'd15) && (t != 4'd0)))
            t <= t + 4'd1;
end

// de-multiplex 64 bit data into word requested by cpu
assign dout = (word == 2'd0)?current_data[15: 0]:
	           (word == 2'd1)?current_data[31:16]:
	           (word == 2'd2)?current_data[47:32]:
	                          current_data[63:48];

// wire entry according to line/address
wire [63:0] current_data = data_latch[line];

// cache size configuration
localparam BITS = 5;	
localparam ENTRIES = 32;     // 2 ** BITS
localparam ALLZERO = 32'd0;  // 2 ** BITS zero bits
								
// _word_ address mapping example with 16 cache lines (BITS == 4)
// 22 21 20 19 18 17 16 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
//  T  T  T  T  T  T  T  T  T  T  T  T  T  T  T  T  T  L  L  L  L  W  W
// T = stored in tag RAM
// L = cache line
// W = 16 bit word select
wire [21-BITS-1:0] tag = addr[22:2+BITS] /* synthesis keep */;
wire [BITS-1:0] line = addr[2+BITS-1:2];
wire [1:0] word = addr[1:0];

/* ------------------------------------------------------------------------------ */
/* --------------------------------- cache memory ------------------------------- */
/* ------------------------------------------------------------------------------ */

reg [63:0]        data_latch [ENTRIES-1:0];
reg [21-BITS-1:0] tag_latch  [ENTRIES-1:0];
reg [ENTRIES-1:0] valid;

// signal indicating the currently selected cache line is valid and matches the
// address the cpu is currently requesting
assign hit = valid[line] && (tag_latch[line] == tag);

always @(posedge clk_128) begin
   if(reset || flush) begin
		valid <= ALLZERO;
   end else begin

		// update64 indicates that a whole cache line is to be updated
		if(update64) begin
			data_latch[line] <= din64;
			tag_latch[line] <= tag;
			valid[line] <= 1'b1;
		end
   end
end
  
endmodule
