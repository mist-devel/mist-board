	`timescale 1ns / 1ps
/*
Copyright (c) 2012, Stephen J Leary
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the author nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL STEPHEN J LEARY BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
module clocks(

		input clk_32m,
		input clk_24m,
		
		input reset_n,
		input mhz1_enable,
		
		output wire mhz4_clken,
		output wire mhz2_clken,
		output wire mhz1_clken,
		
		output wire cpu_cycle,
		output wire cpu_clken,
		
		output wire vid_clken,
		output wire ttxt_clken,
		output wire ttxt_clkenx2,
		
		output wire tube_clken
    );

reg     [4:0] clken_counter; 
reg     cpu_cycle_mask; 

//  SAA5050 needs a 6 MHz clock enable relative to a 24 MHz clock
reg     [1:0] ttxt_clken_counter; 

//  Clock enable generation - 32 MHz clock split into 32 cycles^M
//  CPU is on 0 and 16 (but can be masked by 1 MHz bus accesses)^M
//  Video is on all odd cycles (16 MHz)^M
//  1 MHz cycles are on cycle 31 (1 MHz)        ^M
assign vid_clken = clken_counter[0]; // & ~vsync_latch & ~hsync_latch;
//  1,3,5...^M
assign mhz4_clken = clken_counter[0] & clken_counter[1] & clken_counter[2];
//  7/15/23/31^M
assign mhz2_clken = mhz4_clken & clken_counter[3];
// 1/17
assign tube_clken = clken_counter[0] & !clken_counter[1] & !clken_counter[2];
//  15/31^M
assign mhz1_clken = mhz2_clken & clken_counter[4];
//  31^M
assign cpu_cycle = ~(clken_counter[0] | clken_counter[1] | clken_counter[2] | clken_counter[3]);
//  0/16^M
assign cpu_clken = /* reset_n && */ cpu_cycle & ~cpu_cycle_mask;

always @(posedge clk_32m)
   begin : clk_gen
//   if (reset_n === 1'b 0)
//      begin
//      clken_counter <= {5{1'b 0}};   
//      end
//   else
//      begin
      clken_counter <= clken_counter + 5'd1;   
//      end
   end
	
always @(posedge clk_32m)
   begin : cycle_stretch
   if (reset_n === 1'b 0)
      begin
      cpu_cycle_mask <= 1'b 0;   
      end
   else if (mhz2_clken === 1'b 1 )
      begin
      if (cpu_cycle_mask === 1'b 0)
         begin

			//  Block CPU cycles until 1 MHz cycle has completed
         cpu_cycle_mask <= 1'b 1;   
         end
      if (mhz1_clken === 1'b 1)
         begin
			//  CPU can run again
			//  FIXME: This may not be correct in terms of CPU cycles, but it
			//  should work
         cpu_cycle_mask <= 1'b 0;   
         end
      end
   end

always @(posedge clk_24m)
begin : ttxt_clk_gen
   if (reset_n === 1'b 0) begin
		ttxt_clken_counter <= {2{1'b 0}};  
   end else begin
		ttxt_clken_counter <= ttxt_clken_counter + 1;   
   end
end

//  6 MHz clock enable for SAA5050
assign ttxt_clken = ttxt_clken_counter === 0 ? 1'b 1 : 1'b 0; 
assign ttxt_clkenx2 = !ttxt_clken_counter[0]; 

endmodule
