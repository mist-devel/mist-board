`timescale 1ns / 1ps
/* vidc_dmachannel.v

 Copyright (c) 2012-2015, Stephen J. Leary
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
 
module vidc_dmachannel
(
	input			clkcpu,
	input			clkdev,
	input			cedev,

	input			rst,
		
	// dma bus
	input			ak,
	output reg		rq,
	input [31:0] 	        cpu_data,
	
	output			busy,
	input 			stall, // dont start another request with this high.
	
	// device bus
	input			dev_ak,
	output	[7:0]	dev_data
);

parameter FIFO_SIZE = 3;
localparam MEM_DEPTH = 2**FIFO_SIZE;
localparam WORD_WIDTH = FIFO_SIZE;
localparam BYTE_WIDTH = FIFO_SIZE + 2;
localparam HALF_FULL = 1<<(WORD_WIDTH-1);

reg [1:0]	dma_count	= 2'd0;
reg			load	= 	1'b0;
reg			ak_r	=	1'b0;

// each channel has a fifo of a different size. 
wire [WORD_WIDTH-1:0]	wr_ptr;
wire [WORD_WIDTH-1:0]	space;

wire 		full;

wire 	        fifo_can_load;
	
initial begin 

	rq	= 1'b0;
	
end

vidc_fifo #(.FIFO_SIZE(FIFO_SIZE)) VIDEO_FIFO(
	
	.rst	( rst		),
	.wr_clk	( clkcpu	),
	.rd_clk	( clkdev	),
	.rd_ce	( cedev	),
	.wr_en	( ak & load	), 
	.rd_en	( dev_ak	),

	.din	( cpu_data	),
	.dout	( dev_data	),

	.wr_ptr	( wr_ptr	),

	.space	( space		),
	.full	( full		)
);

// DMA interface control
// this is in the cpu clock domain. 
always @(posedge clkcpu) begin

	ak_r	<=	ak;

	if (rst == 1'b1) begin
	
		// do reset logic 
		dma_count 	<= 2'd0;	
		load 		<= 1'b0;
		rq 			<= 1'b0;
		
	end else begin
	
		// if the load is in progress
		if ((load == 1'b1) & (ak == 1'b1)) begin
			
			// are we done?
			if (dma_count == 2'd3) begin
									
				load 	<= 1'b0;
					
			end
			
			// clear the request on the first ack. 
			// the dma action will continue until 4 words are read.
			rq	 	<= 1'b0;
			
			// count the ack pulses
			dma_count <= dma_count + 2'd1;

		end else if (load == 1'b0) begin
				
			// possibly unnecessary?
			dma_count 	<= 2'd0;
				
		end
		
		// if the fifo can load and its our slot then go.
		if (fifo_can_load === 1'b1) begin 
					
			load <= 1'b1;
			rq	 <= 1'b1;
					
		end 
		
	end
		
end

// TODO: replace 2'b00 with bits 4 and 5 of fifo control register for video fifo.
assign  fifo_can_load = ~stall & ((space > 3'd4) | ((space == 'd0) & (full == 1'b0))) & (wr_ptr[1:0] == 2'b00);
assign	busy = load;

endmodule
