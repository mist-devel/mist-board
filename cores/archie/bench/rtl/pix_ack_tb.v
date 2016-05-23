`timescale 1ns / 1ps
/* pix_ack_tb.v

 Copyright (c) 2012-2014, Stephen J. Leary
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the <organization> nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
 
module pix_ack_tb;

	wire pix_ack;
	reg			CLK = 0;
	reg	 [4:0]	counter = 0;
	wire [2:0] 	pix_shift_count;
	wire [3:2]  vidc_cr;
	
	initial begin	   
	   $display ("ticks: vidc_cr pix_shift_count pix_ack");
	   $monitor ("%b %b %b",vidc_cr, pix_shift_count, pix_ack);
	   
	   // Initialize Inputs
	   CLK = 0;
	   
	   #315;
	   
	   $finish();
	   
	end
	
	always 
	begin
	   #5; CLK = ~CLK;
	end

	always @(posedge CLK) begin

		counter <= counter + 4'd1;
		
	end

assign  vidc_cr[3:2] = counter[4:3];
assign  pix_shift_count[2:0] = counter[2:0];
assign  pix_ack = ((pix_shift_count[2] & vidc_cr[3]) | ( vidc_cr[2] & vidc_cr[3]) | (pix_shift_count[0] & pix_shift_count[1] & pix_shift_count[2]) | (pix_shift_count[1] & pix_shift_count[2] &  vidc_cr[2]));


endmodule

