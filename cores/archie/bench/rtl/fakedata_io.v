`timescale 1ns / 1ps
/*
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
 
module fakedata_io #(parameter ADDR_WIDTH=24, START_ADDR = 0) (
	// io controller spi interface
	input			  rst,
	input         sck,
	input         ss,
	input         sdi,

	output        downloading,   // signal indicating an active download
	output [ADDR_WIDTH-1:0] size,          // number of bytes in input buffer
	 
	// external ram interface
	input 			clk,
	output reg     wr,
	output reg 		[ADDR_WIDTH-1:0] a,
	output [3:0]	sel, 
	output [31:0]   d
);

   wire [7:0] 		data = 8'd0;
   

assign sel = a[1:0] == 	2'b00 ? 4'b0001 :
								a[1:0] == 	2'b01 ? 4'b0010 :
								a[1:0] == 	2'b10 ? 4'b0100 : 4'b1000;

assign d = {data,data,data,data};
reg	[4:0]	count = 0;
initial begin 
	

  //$readmemh("desktop.mif", mem);

end


always @(posedge clk) begin 

	if (rst) begin 
	
		a <= 0;
		count <= 0;
		wr <= 1'b0;
		
	end else begin 
	
		wr <= 1'b0;
	
		if (downloading) begin 
				
			count <= count + 5'd1;
				
      			if (count == 5'h00) begin 
			   wr <= 1'b1;
			end else if (count == 5'h1f) begin 
				
				
				a <= a + 23'd1;
				
			end
		end
		
	end
	
end

assign downloading = 0;

endmodule
