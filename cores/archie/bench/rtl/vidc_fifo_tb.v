`timescale 1ns / 1ps
/* vidc_fifo_tb.v

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
 
module vidc_fifo_tb;

	// Inputs
	reg CLK32M;
	reg CLK25M;
	reg reset;
	reg wr_en;
	reg	rd_en;
	
	reg	[31:0] din;
	wire [7:0] dout;
	
	wire [2:0] wr_ptr;
	wire [4:0] rd_ptr;
	
	// Instantiate the Unit Under Test (UUT)
    vidc_fifo UUT (
		.rst(rst),
		.wr_clk(CLK32M),
		.rd_clk(CLK25M),
		
		.wr_en(wr_en),
		.rd_en(rd_en),
		
		.din(din),
		.dout(dout),
		
		.wr_ptr(wr_ptr),
		.rd_ptr(rd_ptr)
		
	);
	
	initial begin

	   $dumpfile("vidc_fifo.vcd");
	   $dumpvars(0, UUT);
	   
	   $display ("ticks:");
	   $monitor ("%g %b %b %h %h %h", $time, CLK32M, rd_en, rd_ptr, wr_ptr, dout);
	   
	   // Initialize Inputs
	   CLK32M = 0;
	   CLK25M = 0;
	   reset = 1;
	   wr_en = 0;
	   rd_en = 0;
	   din = 32'h00AA_00FF;
	   #150;
	   reset = 0;
	   #135;
	   wr_en = 1;
	   #30;
	   wr_en = 0;
	   #120;
	   din = 32'h0000_0000;
	   wr_en = 1;
	   #30;
	   wr_en = 0;
	   #120;
	   wr_en = 1;
	   #30;
	   wr_en = 0;
	   #120;
	   din = 32'h0000_0000;
	   wr_en = 1;
	   #30;
	   wr_en = 0;
	   #120;
	    wr_en = 1;
	   #30;
	   wr_en = 0;
	   #120;
	   din = 32'h0000_0000;
	   wr_en = 1;
	   #30;
	   wr_en = 0;
	   #120;
	   wait(CLK25M);
	   #35;
	   rd_en = 1;  
	   #40;
	   rd_en = 0; 
	   #40;
   	   rd_en = 1;  
	   #40;
	   rd_en = 0; 
	   #400;
	   
	   #40;
   	   rd_en = 1;  
	   #40;
	   rd_en = 0; 
	   #400;
	   
	   #40;
   	   rd_en = 1;  
	   #40;
	   rd_en = 0; 
	   #400;
	   
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

