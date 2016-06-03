`timescale 1ns / 1ps
/* ioc_irq.v

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
 
 module ioc_irq #(
 parameter ADDRESS=2'b01, 
 parameter CANCLEAR=8'b1111_1111, 
 parameter PERMBITS=8'h00) 
 (
	
		input 	 			clkcpu, // cpu bus clock domain

		input [7:0]			i,
		input [7:0]			c,
		output				irq,
			
		// cpu interface
		input				write,
		
		input [6:2]			addr,			
		input [7:0]			din,
		output [7:0]		dout,
		output				sel
);

reg [7:0]	mask = 8'h00;
reg	[7:0]	status = 8'h00;

wire		selected = ~addr[6] & (addr[5:4] == ADDRESS);

always @(posedge clkcpu) begin

	status <= status & CANCLEAR | status & ~CANCLEAR & ~c | i | PERMBITS;
	
	if (selected & write) begin
		
		if (addr[3:2] == 2'b10)  mask <= din;
		
		if (addr[3:2] == 2'b01) begin
			status <= (status & ~CANCLEAR) | (status & ~din & CANCLEAR) | PERMBITS;
		end
 
	end

end

assign sel = selected;

assign irq =  | (mask & status);

assign dout = 	addr[3:2] == 2'b00 ? status :
				addr[3:2] == 2'b01 ? mask & status :
				addr[3:2] == 2'b10 ? mask : 8'd0;
				
endmodule