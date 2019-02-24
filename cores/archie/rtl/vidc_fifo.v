`timescale 1ns / 1ps
/* vidc_fifo.v

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
 
module vidc_fifo #(
	parameter FIFO_SIZE = 3
)
(
		input 		rst,
		input 		wr_clk,
		input 		wr_en, 
		input[31:0]	din,
		
		input 		rd_clk,
		input 		rd_ce,
		input 		rd_en,
		output reg [7:0]	dout,
		
		output reg [WORD_WIDTH-1:0] wr_ptr,
		output reg [WORD_WIDTH-1:0] space,
		output reg 		 			full,
		output 						empty
);

localparam MEM_DEPTH = 2**FIFO_SIZE;
localparam WORD_WIDTH = FIFO_SIZE;
localparam BYTE_WIDTH = FIFO_SIZE + 2;

reg [31:0] data[0:MEM_DEPTH-1];
reg [BYTE_WIDTH-1:0]  rd_ptr;
   
integer k;

initial begin

	wr_ptr = 'd0;
	rd_ptr = 'd0;
	full   = 1'b0;
	dout   = 8'd0;
	
	for (k = 0; k < MEM_DEPTH; k = k + 1)
	begin
		data[k] = 32'd0;
	end
	
	$display("FIFO has %x", MEM_DEPTH);

end

reg [BYTE_WIDTH-1:0] rd_ptr_r;

always @(posedge wr_clk) begin
	reg rstD, rstD2;

	rd_ptr_r	<= rd_ptr;
	space 		<= {rd_ptr_r[BYTE_WIDTH-1:2]} - wr_ptr;
	rstD <= rst;
	rstD2 <= rstD;
	
	if (rstD2) begin

		wr_ptr 	<= 'd0;
		full   	<= 1'b0;
	
	end else begin 
	
		if (wr_ptr != {rd_ptr_r[BYTE_WIDTH-1:2]}) begin
		
			full	<=  1'b0;
		
		end 
	
		if (wr_en == 1'b1) begin
		
			data[wr_ptr] <= din;
			wr_ptr 	<= 	 wr_ptr + 2'd1;
			full  	<=  (wr_ptr + 2'd1) == {rd_ptr_r[BYTE_WIDTH-1:2]};
		
		end
		
	end 
	
end 

wire [7:0] q;

always @(posedge rd_clk) begin

    reg rstD, rstD2;

    rstD <= rst;
	rstD2 <= rstD;
	if(rd_ce) begin
		if (rstD2) begin
		
			rd_ptr <= 'd0;
			dout <= 8'd0;

		end else if (rd_en) begin

			if (~empty) begin
				rd_ptr <= rd_ptr + 1'd1;
				dout <= q;
			end else begin
				dout <= 'd0;
			end
		end
	end
end

assign empty = !full & space == 'd0;

// cross the clock domain.
assign q = (rd_ptr[1:0] == 2'b00) ? data[{rd_ptr[BYTE_WIDTH-1:2]}][7:0] :
			  (rd_ptr[1:0] == 2'b01) ? data[{rd_ptr[BYTE_WIDTH-1:2]}][15:8] :
			  (rd_ptr[1:0] == 2'b10) ? data[{rd_ptr[BYTE_WIDTH-1:2]}][23:16] : data[{rd_ptr[BYTE_WIDTH-1:2]}][31:24];
			  
endmodule
