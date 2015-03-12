//
// tape.v
//
// tape implementation for the spectrum core for the MiST board
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// This reads a CSW1 file as described here:
// http://ramsoft.bbk.org.omegahg.com/csw.html#CSW1FORMAT
//

// typical header:
// 00000000  43 6f 6d 70 72 65 73 73  65 64 20 53 71 75 61 72  |Compressed Squar|
// 00000010  65 20 57 61 76 65 1a 01  01 44 ac 01 00 00 00 00  |e Wave...D......|

module tape #(parameter ADDR_WIDTH=16) (
        input                   reset,
        input                   clk,
        input                   iocycle,

        input        downloading,   // signal indicating an active download
        input [ADDR_WIDTH-1:0] size,          // number of bytes in input buffer

			output reg audio_out,
		  
        // external ram interface
        output     rd,
        output    [ADDR_WIDTH-1:0] a,
        input [7:0]   d
);

reg downloadingD;

reg [15:0] freq;
reg [5:0] header_cnt;
reg [31:0] clk_play_cnt;
reg [ADDR_WIDTH-1:0] payload_cnt;
reg iocycleD;

reg [31:0] bit_cnt;
reg [2:0] reload32;

assign rd = iocycle && ((header_cnt != 0) || (payload_cnt != 0));
assign a = (header_cnt != 0)?(25'h200000 + 25'd32 - header_cnt):
	(payload_cnt != 0)?(25'h200000 + size - payload_cnt):
	25'h12345;

reg [7:0] din;

// latch data at end of io cycle
always @(negedge iocycle)
	din <= d;

always @(posedge clk) begin
	downloadingD <= downloading;
	iocycleD <= iocycle;

	if(reset || downloading) begin
		freq <= 16'd1234;
		header_cnt <= 6'd0;
		payload_cnt <= 25'd0;
		reload32 <= 3'd0;
	end else begin
	
		// download complete, start parsing
		if(!downloading && downloadingD)
			header_cnt <= 6'd32;

		// read header
		if((header_cnt != 0) && !iocycle && iocycleD ) begin

			// fetch playback frequency from header
			if(header_cnt == 6'h20 - 6'h19) freq[ 7:0] <= din;
			if(header_cnt == 6'h20 - 6'h1a) freq[15:8] <= din;
			
			header_cnt <= header_cnt - 6'd1;

			// start payload transfer as soon as header has been parsed
			if(header_cnt == 1) begin
				payload_cnt <= size - 25'h20;
				bit_cnt <= 32'd1;
			end
		end
			
		// read payload
		if(payload_cnt != 0) begin

			// bit has fully neem semt or reload32 in progress
			if((bit_cnt <= 1) || (reload32 != 0)) begin
			
				if(!iocycle && iocycleD ) begin
					if(reload32 != 0) begin
						bit_cnt <= { din, bit_cnt[31:8] };
						reload32 <= reload32 - 3'd1;
					end else begin
						if(din != 0) begin
							// determine length of next bit
							bit_cnt <= { 24'd0, din};
						end else	
							reload32 <= 3'd4;
							
						// output a bit ...
						audio_out <= !audio_out;
					end

					payload_cnt <= payload_cnt - 25'd1;
				end
			end else begin
				// generate replay clock
				clk_play_cnt <= clk_play_cnt + { 16'h0000, freq};
				// clock is 28MHz
				if(clk_play_cnt > 32'd28000000) begin	
					clk_play_cnt <= clk_play_cnt - 32'd28000000;

					// process bit counter
					bit_cnt <= bit_cnt - 32'd1;
				end
			end
		end
	end
end

endmodule
