//
// scandoubler.v
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
// Copyright (c) 2017 Sorgelig
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

// TODO: Delay vsync one line

module scandoubler #(parameter LENGTH, parameter HALF_DEPTH)
(
	// system interface
	input             clk_sys,
	input             ce_pix,
	input             ce_pix_actual,

	input             hq2x,

	// shifter video interface
	input             hs_in,
	input             vs_in,
	input             line_start,

	input  [DWIDTH:0] r_in,
	input  [DWIDTH:0] g_in,
	input  [DWIDTH:0] b_in,
	input             mono,

	// output interface
	output reg        hs_out,
	output            vs_out,
	output [DWIDTH:0] r_out,
	output [DWIDTH:0] g_out,
	output [DWIDTH:0] b_out
);


localparam DWIDTH = HALF_DEPTH ? 2 : 5;

assign vs_out = vs_in;

reg  [2:0] phase;
reg  [2:0] ce_div;
reg  [7:0] pix_len = 0;
wire [7:0] pl = pix_len + 1'b1;

reg ce_x1, ce_x4;
reg req_line_reset;
wire ls_in = hs_in | line_start;
always @(negedge clk_sys) begin
	reg old_ce;
	reg [2:0] ce_cnt;

	reg [7:0] pixsz2, pixsz4 = 0;

	old_ce <= ce_pix;
	if(~&pix_len) pix_len <= pix_len + 1'd1;

	ce_x4 <= 0;
	ce_x1 <= 0;

	// use such odd comparison to place c_x4 evenly if master clock isn't multiple 4.
	if((pl == pixsz4) || (pl == pixsz2) || (pl == (pixsz2+pixsz4))) begin
		phase <= phase + 1'd1;
		ce_x4 <= 1;
	end

	if(~old_ce & ce_pix) begin
		pixsz2 <= {1'b0,  pl[7:1]};
		pixsz4 <= {2'b00, pl[7:2]};
		ce_x1 <= 1;
		ce_x4 <= 1;
		pix_len <= 0;
		phase <= phase + 1'd1;

		ce_cnt <= ce_cnt + 1'd1;
		if(ce_pix_actual) begin
			phase <= 0;
			ce_div <= ce_cnt + 1'd1;
			ce_cnt <= 0;
			req_line_reset <= 0;
		end

		if(ls_in) req_line_reset <= 1;
	end
end

reg ce_sd;
always @(*) begin
	case(ce_div)
		2: ce_sd = !phase[0];
		4: ce_sd = !phase[1:0];
		default: ce_sd <= 1;
	endcase
end

localparam AWIDTH = `BITS_TO_FIT(LENGTH);
Hq2x #(.LENGTH(LENGTH), .HALF_DEPTH(HALF_DEPTH)) Hq2x
(
	.clk(clk_sys),
	.ce_x4(ce_x4 & ce_sd),
	.inputpixel({b_in,g_in,r_in}),
	.mono(mono),
	.disable_hq2x(~hq2x),
	.reset_frame(vs_in),
	.reset_line(req_line_reset),
	.read_y(sd_line),
	.read_x(sd_h_actual),
	.outpixel({b_out,g_out,r_out})
);

reg [10:0] sd_h_actual;
always @(*) begin
	case(ce_div)
		2: sd_h_actual = sd_h[10:1];
		4: sd_h_actual = sd_h[10:2];
		default: sd_h_actual = sd_h;
	endcase
end

reg [10:0] sd_h;
reg  [1:0] sd_line;
always @(posedge clk_sys) begin

	reg [11:0] hs_max,hs_rise,hs_ls;
	reg [10:0] hcnt;
	reg [11:0] sd_hcnt;

	reg hs, hs2, vs, ls;

	if(ce_x1) begin
		hs <= hs_in;
		ls <= ls_in;

		if(ls && !ls_in) hs_ls <= {hcnt,1'b1};

		// falling edge of hsync indicates start of line
		if(hs && !hs_in) begin
			hs_max <= {hcnt,1'b1};
			hcnt <= 0;
			if(ls && !ls_in) hs_ls <= {10'd0,1'b1};
		end else begin
			hcnt <= hcnt + 1'd1;
		end

		// save position of rising edge
		if(!hs && hs_in) hs_rise <= {hcnt,1'b1};

		vs <= vs_in;
		if(vs && ~vs_in) sd_line <= 0;
	end

	if(ce_x4) begin
		hs2 <= hs_in;

		// output counter synchronous to input and at twice the rate
		sd_hcnt <= sd_hcnt + 1'd1;
		sd_h    <= sd_h    + 1'd1;
		if(hs2 && !hs_in)     sd_hcnt <= hs_max;
		if(sd_hcnt == hs_max) sd_hcnt <= 0;

		// replicate horizontal sync at twice the speed
		if(sd_hcnt == hs_max)  hs_out <= 0;
		if(sd_hcnt == hs_rise) hs_out <= 1;

		if(sd_hcnt == hs_ls)   sd_h    <= 0;
		if(sd_hcnt == hs_ls)   sd_line <= sd_line + 1'd1;
	end
end

endmodule
