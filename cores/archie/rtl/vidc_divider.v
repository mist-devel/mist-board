`timescale 1ns / 1ps
/* vidc_divider.v

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

module vidc_divider(
           input                   clkpix2x,
           input   [1:0]           clk_select,
           output                  clkpix
       );

reg clk24_m;
reg clk12_m;
wire clk16_m;
reg clk8_m;

reg [1:0] pos_cnt;
reg [1:0] neg_cnt;


initial begin

    clk24_m = 1'b0;
    clk12_m = 1'b0;
    clk8_m = 1'b0;

    pos_cnt = 'd0;
    neg_cnt = 'd0;

end

always @(posedge clkpix2x) begin

    clk24_m <= ~clk24_m;
    pos_cnt <= (pos_cnt == 2) ? 0 : pos_cnt + 1;

end

always @(negedge clkpix2x) begin

    neg_cnt <= (neg_cnt == 2) ? 0 : neg_cnt + 1;

end

always @(posedge clk24_m) begin

    clk12_m <= ~clk12_m;

end

always @(posedge clk16_m) begin

    clk8_m  <= ~clk8_m;

end

// this is a divide by 3.
assign clk16_m = ((pos_cnt  != 2) && (neg_cnt  != 2));

assign clkpix =         clk_select == 2'b00 ? clk8_m :
       clk_select == 2'b01 ? clk12_m :
       clk_select == 2'b10 ? clk16_m : clk24_m;

endmodule
