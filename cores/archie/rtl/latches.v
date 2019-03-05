`timescale 1ns / 1ps
/* latches.v

 Copyright (c) 2015, Stephen J. Leary
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
 
module latches(

   input	      	clkcpu,	 // system cpu clock.

	// "wishbone bus" the ack is externally generated currently. 
	input				wb_cyc,
	input				wb_stb,
	input				wb_we,
	
	input [15:2]	wb_adr, 	// la
	input [7:0]		wb_dat_i, 	// bd
	output [7:0]		wb_dat_o, 	// bd
	
	// floppy latch signals.
	output  [3:0] floppy_drive,
	output  		  floppy_side, 
	output  		  floppy_motor,
	output 		  floppy_inuse,
	output 		  floppy_density,
	output 		  floppy_reset,
	
	// place any signals that need to be passed up to the top after here. 

	input [4:0]	joy0,
	input [4:0]	joy1,
	
	output [1:0] baseclk,
	output [1:0] syncpol

);

reg [7:0]	printer_data;
reg [7:0]	ext_latch_a;
reg [7:0]	ext_latch_b;
reg [7:0]	ext_latch_c;

wire write_request = wb_stb & wb_cyc & wb_we;

initial begin 

	printer_data 	= 8'd0;
	ext_latch_a 	= 8'hFF;
	ext_latch_b 	= 8'hFF;
	ext_latch_c 	= 8'd0; // A540 only. Used for VIDC enhancer.
	
end

always @(posedge clkcpu) begin 

	if (write_request) begin 
	
		case (wb_adr)  
			
			14'h0004: printer_data<= wb_dat_i; // 0x10
			14'h0010: ext_latch_a <= wb_dat_i; // 0x40
			14'h0006: ext_latch_b <= wb_dat_i; // 0x18
			14'h0012: ext_latch_c <= wb_dat_i; // 0x48
			
		endcase
	
	end

end

assign floppy_drive = ext_latch_a[3:0];
assign floppy_side = ext_latch_a[4];
assign floppy_motor = ext_latch_a[5];
assign floppy_inuse = ext_latch_a[6];
assign floppy_density = ext_latch_b[1];
assign floppy_reset = ext_latch_b[3];

assign wb_dat_o	= wb_adr == 14'h001e ? {3'b011, joy0} :
				  wb_adr == 14'h001f ? {3'b011, joy1} : 8'hFF;

assign baseclk = ext_latch_c[1:0];
assign syncpol = ext_latch_c[3:2];

endmodule
