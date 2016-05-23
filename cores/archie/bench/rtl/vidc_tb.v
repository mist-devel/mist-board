`timescale 1ns / 1ps
/* archimedes_tb.v

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
 
module vidc_tb;

	// Inputs
	reg CLK32M;
	reg CLK25M;
	reg reset;
	reg vidak;
	reg[31:0] viddat;
	
	wire vidrq;
	wire flybk;
	wire hsync;
	
	// Instantiate the Unit Under Test (UUT)
    vidc UUT (
		.clkcpu(CLK32M),
		.clkpix(CLK25M),
		.rst_i(reset),
		
		.viddat(viddat),
		.vidrq(vidrq),
		.vidak(vidak),
		.flybk(flybk),
		.hsync(hsync)
		
	);
	
	initial begin

	   $dumpfile("vidc.vcd");
	   $dumpvars(0, UUT);
	   
	   $display ("ticks:");
	   
	   // Initialize Inputs
	   CLK32M = 0;
	   CLK25M = 0;
	   reset = 1;
	   vidak = 0;
	   #10;
	   reset = 0;
	   wait(vidrq);
	   $monitor ("%g %b %b %b %b %b %b %b %h %b", $time, CLK32M, vidrq, vidak, hsync, flybk, UUT.cur_load, UUT.vid_load, UUT.dma_count, UUT.vid_fifo_can_load);
	   #120;
	   vidak = 1;
	   #30;
	   vidak = 0;
	   #30;
	   vidak = 1;
	   #30;
	   vidak = 0;
	   #30;
	   vidak = 1;
	   #30;
	   vidak = 0;
	   #30;
	   vidak = 1;
	   #30;
	   vidak = 0;
	   #30;
	   wait(vidrq);
	   viddat = 32'h00AA00FF;
	   #120;
	   vidak = 1;
	   #30;
	   vidak = 0;
	   viddat = 32'h0055_0055;
	   #30;
	   vidak = 1;
	   #30;
	   viddat = 32'h00000000;
	   vidak = 0;
	   #30;
	   vidak = 1;
	   #30;
	   vidak = 0;
	   #30;
	   vidak = 1;
	   #30;
	   vidak = 0;
	   #30;
	   wait(vidrq);
	   #120;
	   vidak = 1;
	   #30;
	   vidak = 0;
	   #30;
	   vidak = 1;
	   #30;
	   vidak = 0;
	   #30;
	   vidak = 1;
	   #30;
	   vidak = 0;
	   #30;
	   vidak = 1;
	   #30;
	   vidak = 0;
	   #30;
	   
	   
	   
	   #60000;
	   $finish();

	end
	
	always 
	begin
	   #20; CLK25M = ~CLK25M;
	end
	
	always 
	begin
	   #15; CLK32M = ~CLK32M;
	end
      
endmodule

