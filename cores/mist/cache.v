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
	      
		input			 strobe,
      input [22:0] addr, // cpu word address
      input [1:0]	 ds,   // upper (0) and lower (1) data strobe

      output [15:0] dout,
      output        hit,

		// interface to store entire cache lines when read from ram
		input [63:0]  din64,
		input         store,
		
		// interface to update existing cache lines on cpu ram write
		input [15:0]  din16,
		input         update
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

// cache size configuration
// the cache size in bytes is 8*(2^BITS), e.g. 2kBytes if BITS == 8
localparam BITS = 8;	
								
// _word_ address mapping example with 16 cache lines (BITS == 4)
// 22 21 20 19 18 17 16 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
//  T  T  T  T  T  T  T  T  T  T  T  T  T  L  L  L  L  L  L  L  L  W  W
// T = stored in tag RAM
// L = cache line
// W = 16 bit word select 
wire [21-BITS-1:0] tag = addr[22:2+BITS];
wire [BITS-1:0] line = addr[2+BITS-1:2];

/* ------------------------------------------------------------------------------ */
/* --------------------------------- cache memory ------------------------------- */
/* ------------------------------------------------------------------------------ */

// 8 bytes wide storage
parameter ENTRIES = 2 ** BITS;
reg [7:0] data_latch_7 [ENTRIES-1:0];
reg [7:0] data_latch_6 [ENTRIES-1:0];
reg [7:0] data_latch_5 [ENTRIES-1:0];
reg [7:0] data_latch_4 [ENTRIES-1:0];
reg [7:0] data_latch_3 [ENTRIES-1:0];
reg [7:0] data_latch_2 [ENTRIES-1:0];
reg [7:0] data_latch_1 [ENTRIES-1:0];
reg [7:0] data_latch_0 [ENTRIES-1:0];
 
reg [21-BITS-1:0] tag_latch [ENTRIES-1:0];
reg [ENTRIES-1:0] valid;

reg [21-BITS-1:0] current_tag;

// signal indicating the currently selected cache line is valid and matches the
// address the cpu is currently requesting
// assign hit = valid[line] && (tag_latch[line] == tag);
assign hit = valid[line] && (current_tag == tag);

reg [15:0] dout_latch_0;
reg [15:0] dout_latch_1;
reg [15:0] dout_latch_2;
reg [15:0] dout_latch_3;

// permanently output data according to current line
// de-multiplex 64 bit data into word requested by cpu
assign dout = 	(addr[1:0] == 0)?dout_latch_0:
					(addr[1:0] == 1)?dout_latch_1:
					(addr[1:0] == 2)?dout_latch_2:
					dout_latch_3;

always @(posedge clk_128) begin
	dout_latch_0 <= {data_latch_1[line], data_latch_0[line]};
	dout_latch_1 <= {data_latch_3[line], data_latch_2[line]};
	dout_latch_2 <= {data_latch_5[line], data_latch_4[line]};
	dout_latch_3 <= {data_latch_7[line], data_latch_6[line]};
	current_tag <= tag_latch[line];
end

always @(posedge clk_128) begin
   if(reset || flush) begin
		valid <= { ENTRIES {1'b0} };
   end else begin
		// the store and update signals are valid in the last cycle only. The cpu runs
		// at 32MHz and is valid if t=14,15,0,1
		if(t==15) begin

			// store indicates that a whole cache line is to be stored
			if(store) begin
				data_latch_7[line] <= din64[63:56];
				data_latch_6[line] <= din64[55:48];
				data_latch_5[line] <= din64[47:40];
				data_latch_4[line] <= din64[39:32];
				data_latch_3[line] <= din64[31:24];
				data_latch_2[line] <= din64[23:16];
				data_latch_1[line] <= din64[15: 8];
				data_latch_0[line] <= din64[ 7: 0];
			
				tag_latch[line] <= tag;
				valid[line] <= 1'b1;
			end
		
			// cpu (or other bus master!) writes to ram, so update cache contents if necessary
			else if(update && hit) begin
				// no need to care for "tag_latch" or "valid" as they simply stay the same

				case(addr[1:0]) 
					0: begin
							if(ds[1]) data_latch_0[line] <= din16[7:0];
							if(ds[0]) data_latch_1[line] <= din16[15:8];
						end
			
					1: begin
							if(ds[1]) data_latch_2[line] <= din16[7:0];
							if(ds[0]) data_latch_3[line] <= din16[15:8];
						end

					2: begin
							if(ds[1]) data_latch_4[line] <= din16[7:0];
							if(ds[0]) data_latch_5[line] <= din16[15:8];
						end

					3:  begin
							if(ds[1]) data_latch_6[line] <= din16[7:0];
							if(ds[0]) data_latch_7[line] <= din16[15:8];
						end
				endcase
			end
		end
   end
end
  
endmodule
