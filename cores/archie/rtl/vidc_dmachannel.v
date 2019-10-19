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
	input           rst,

	// dma bus
	input           clkcpu,
	input           ak,
	output reg      rq,
	input [31:0]    cpu_data,

	output			busy,
	input 			stall, // dont start another request with this high.

	// device bus
	input			clkdev,
	input			cedev,
	input			dev_ak,
	output	[7:0]	dev_data
);

// 8 or 4 words fifo
parameter  FIFO4WORDS = 1'b0;

reg  [1:0] dma_count = 2'd0;
reg        load      = 1'b0;
wire       fifo_can_load;
wire [3:0] wrusedw;

initial begin 

	rq	= 1'b0;
	
end

vidc_dcfifo VIDEO_FIFO(

	.aclr   ( rst       ),
	.data   ( cpu_data  ),
	.rdclk  ( clkdev    ),
	.rdreq  ( cedev & dev_ak ),
	.wrclk  ( clkcpu    ),
	.wrreq  ( ak & load ),
	.q      ( dev_data  ),
	.wrusedw( wrusedw   )
);

// DMA interface control
// this is in the cpu clock domain. 
always @(posedge clkcpu) begin
	reg rstD, rstD2;
	rstD <= rst;
	rstD2 <= rstD;
	if (rstD2 == 1'b1) begin

		// do reset logic 
		dma_count 	<= 2'd0;	
		load 		<= 1'b0;
		rq 			<= 1'b0;

	end else begin

		// if the load is in progress
		if (ak & load) begin

			// are we done?
			if (dma_count == 2'd3) load 	<= 1'b0;
			// clear the request on the first ack. 
			// the dma action will continue until 4 words are read.
			rq	 	<= 1'b0;

			// count the ack pulses
			dma_count <= dma_count + 2'd1;

		end else if (~load) begin

			// possibly unnecessary?
			dma_count 	<= 2'd0;
			// if the fifo can load and its our slot then go.
			if (fifo_can_load === 1'b1) begin 
				load <= 1'b1;
				rq	 <= 1'b1;
			end 
		end
	end

end

// TODO: use bits 4 and 5 of fifo control register for requesting new data to the video fifo.
// But the RAM timing is so different from the original machine that it won't be useful
assign fifo_can_load = ~stall && ((!FIFO4WORDS && wrusedw <= 4) || (FIFO4WORDS && wrusedw == 0));
assign busy = load;

endmodule
