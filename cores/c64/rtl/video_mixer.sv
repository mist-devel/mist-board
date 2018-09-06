//
//
// Copyright (c) 2017 Sorgelig
//
// This program is GPL Licensed. See COPYING for the full license.
//
//
////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

//
// LINE_LENGTH: Length of  display line in pixels
//              Usually it's length from HSync to HSync.
//              May be less if line_start is used.
//
// HALF_DEPTH:  If =1 then color dept is 3 bits per component
//              For half depth 6 bits monochrome is available with
//              mono signal enabled and color = {G, R}

module video_mixer
#(
	parameter LINE_LENGTH  = 768,
	parameter HALF_DEPTH   = 0,

	parameter OSD_COLOR    = 3'd4,
	parameter OSD_X_OFFSET = 10'd0,
	parameter OSD_Y_OFFSET = 10'd0
)
(
	// master clock
	// it should be multiple by (ce_pix*4).
	input        clk_sys,
	
	// Pixel clock or clock_enable (both are accepted).
	input        ce_pix,

	// Some systems have multiple resolutions.
	// ce_pix_actual should match ce_pix where every second or fourth pulse is enabled,
	// thus half or qurter resolutions can be used without brake video sync while switching resolutions.
	// For fixed single resolution (or when video sync stability isn't required) ce_pix_actual = ce_pix.
	input        ce_pix_actual,

	// OSD SPI interface
	input        SPI_SCK,
	input        SPI_SS3,
	input        SPI_DI,

	// scanlines (00-none 01-25% 10-50% 11-75%)
	input  [1:0] scanlines,

	// 0 = HVSync 31KHz, 1 = CSync 15KHz
	input        scandoubler_disable,

	// High quality 2x scaling
	input        hq2x,

	// YPbPr always uses composite sync
	input        ypbpr,

	// 0 = 16-240 range. 1 = 0-255 range. (only for YPbPr color space)
	input        ypbpr_full,

	// color
	input [DWIDTH:0] R,
	input [DWIDTH:0] G,
	input [DWIDTH:0] B,

	// Monochrome mode (for HALF_DEPTH only)
	input            mono,

	// interlace sync. Positive pulses.
	input        HSync,
	input        VSync,

	// Falling of this signal means start of informative part of line.
	// It can be horizontal blank signal.
	// This signal can be used to reduce amount of required FPGA RAM for HQ2x scan doubler
	// If FPGA RAM is not an issue, then simply set it to 0 for whole line processing.
	// Keep in mind: due to algo first and last pixels of line should be black to avoid side artefacts.
	// Thus, if blank signal is used to reduce the line, make sure to feed at least one black (or paper) pixel 
	// before first informative pixel.
	input        line_start,

	// MiST video output signals
	output [5:0] VGA_R,
	output [5:0] VGA_G,
	output [5:0] VGA_B,
	output       VGA_VS,
	output       VGA_HS
);

localparam DWIDTH = HALF_DEPTH ? 2 : 5;

wire [DWIDTH:0] R_sd;
wire [DWIDTH:0] G_sd;
wire [DWIDTH:0] B_sd;
wire hs_sd, vs_sd;

scandoubler #(.LENGTH(LINE_LENGTH), .HALF_DEPTH(HALF_DEPTH)) scandoubler
(
	.*,
	.hs_in(HSync),
	.vs_in(VSync),
	.r_in(R),
	.g_in(G),
	.b_in(B),

	.hs_out(hs_sd),
	.vs_out(vs_sd),
	.r_out(R_sd),
	.g_out(G_sd),
	.b_out(B_sd)
);

wire [DWIDTH:0] rt  = (scandoubler_disable ? R : R_sd);
wire [DWIDTH:0] gt  = (scandoubler_disable ? G : G_sd);
wire [DWIDTH:0] bt  = (scandoubler_disable ? B : B_sd);

generate
	if(HALF_DEPTH) begin
		wire [5:0] r  = mono ? {gt,rt} : {rt,rt};
		wire [5:0] g  = mono ? {gt,rt} : {gt,gt};
		wire [5:0] b  = mono ? {gt,rt} : {bt,bt};
	end else begin
		wire [5:0] r  = rt;
		wire [5:0] g  = gt;
		wire [5:0] b  = bt;
	end
endgenerate

wire       hs = (scandoubler_disable ? HSync : hs_sd);
wire       vs = (scandoubler_disable ? VSync : vs_sd);

reg scanline = 0;
always @(posedge clk_sys) begin
	reg old_hs, old_vs;
	
	old_hs <= hs;
	old_vs <= vs;
	
	if(old_hs && ~hs) scanline <= ~scanline;
	if(old_vs && ~vs) scanline <= 0;
end

wire [5:0] r_out, g_out, b_out;
always @(*) begin
	case(scanlines & {scanline, scanline})
		1: begin // reduce 25% = 1/2 + 1/4
			r_out = {1'b0, r[5:1]} + {2'b00, r[5:2]};
			g_out = {1'b0, g[5:1]} + {2'b00, g[5:2]};
			b_out = {1'b0, b[5:1]} + {2'b00, b[5:2]};
		end

		2: begin // reduce 50% = 1/2
			r_out = {1'b0, r[5:1]};
			g_out = {1'b0, g[5:1]};
			b_out = {1'b0, b[5:1]};
		end

		3: begin // reduce 75% = 1/4
			r_out = {2'b00, r[5:2]};
			g_out = {2'b00, g[5:2]};
			b_out = {2'b00, b[5:2]};
		end

		default: begin
			r_out = r;
			g_out = g;
			b_out = b;
		end
	endcase
end

wire [5:0] red, green, blue;
osd #(OSD_X_OFFSET, OSD_Y_OFFSET, OSD_COLOR) osd
(
	.*,

	.R_in(r_out),
	.G_in(g_out),
	.B_in(b_out),
	.HSync(hs),
	.VSync(vs),

	.R_out(red),
	.G_out(green),
	.B_out(blue)
);

wire [5:0] yuv_full[225] = '{
  6'd0,   6'd0,  6'd0,  6'd0,  6'd1,  6'd1,  6'd1,  6'd1,
  6'd2,   6'd2,  6'd2,  6'd3,  6'd3,  6'd3,  6'd3,  6'd4,
  6'd4,   6'd4,  6'd5,  6'd5,  6'd5,  6'd5,  6'd6,  6'd6,
  6'd6,   6'd7,  6'd7,  6'd7,  6'd7,  6'd8,  6'd8,  6'd8,
  6'd9,   6'd9,  6'd9,  6'd9, 6'd10, 6'd10, 6'd10, 6'd11,
  6'd11, 6'd11, 6'd11, 6'd12, 6'd12, 6'd12, 6'd13, 6'd13,
  6'd13, 6'd13, 6'd14, 6'd14, 6'd14, 6'd15, 6'd15, 6'd15,
  6'd15, 6'd16, 6'd16, 6'd16, 6'd17, 6'd17, 6'd17, 6'd17,
  6'd18, 6'd18, 6'd18, 6'd19, 6'd19, 6'd19, 6'd19, 6'd20,
  6'd20, 6'd20, 6'd21, 6'd21, 6'd21, 6'd21, 6'd22, 6'd22,
  6'd22, 6'd23, 6'd23, 6'd23, 6'd23, 6'd24, 6'd24, 6'd24,
  6'd25, 6'd25, 6'd25, 6'd25, 6'd26, 6'd26, 6'd26, 6'd27,
  6'd27, 6'd27, 6'd27, 6'd28, 6'd28, 6'd28, 6'd29, 6'd29,
  6'd29, 6'd29, 6'd30, 6'd30, 6'd30, 6'd31, 6'd31, 6'd31,
  6'd31, 6'd32, 6'd32, 6'd32, 6'd33, 6'd33, 6'd33, 6'd33,
  6'd34, 6'd34, 6'd34, 6'd35, 6'd35, 6'd35, 6'd35, 6'd36,
  6'd36, 6'd36, 6'd36, 6'd37, 6'd37, 6'd37, 6'd38, 6'd38,
  6'd38, 6'd38, 6'd39, 6'd39, 6'd39, 6'd40, 6'd40, 6'd40,
  6'd40, 6'd41, 6'd41, 6'd41, 6'd42, 6'd42, 6'd42, 6'd42,
  6'd43, 6'd43, 6'd43, 6'd44, 6'd44, 6'd44, 6'd44, 6'd45,
  6'd45, 6'd45, 6'd46, 6'd46, 6'd46, 6'd46, 6'd47, 6'd47,
  6'd47, 6'd48, 6'd48, 6'd48, 6'd48, 6'd49, 6'd49, 6'd49,
  6'd50, 6'd50, 6'd50, 6'd50, 6'd51, 6'd51, 6'd51, 6'd52,
  6'd52, 6'd52, 6'd52, 6'd53, 6'd53, 6'd53, 6'd54, 6'd54,
  6'd54, 6'd54, 6'd55, 6'd55, 6'd55, 6'd56, 6'd56, 6'd56,
  6'd56, 6'd57, 6'd57, 6'd57, 6'd58, 6'd58, 6'd58, 6'd58,
  6'd59, 6'd59, 6'd59, 6'd60, 6'd60, 6'd60, 6'd60, 6'd61,
  6'd61, 6'd61, 6'd62, 6'd62, 6'd62, 6'd62, 6'd63, 6'd63,
  6'd63
};

// http://marsee101.blog19.fc2.com/blog-entry-2311.html
// Y  =  16 + 0.257*R + 0.504*G + 0.098*B (Y  =  0.299*R + 0.587*G + 0.114*B)
// Pb = 128 - 0.148*R - 0.291*G + 0.439*B (Pb = -0.169*R - 0.331*G + 0.500*B)
// Pr = 128 + 0.439*R - 0.368*G - 0.071*B (Pr =  0.500*R - 0.419*G - 0.081*B)

wire [18:0]  y_8 = 19'd04096 + ({red, 8'd0} + {red, 3'd0}) + ({green, 9'd0} + {green, 2'd0}) + ({blue, 6'd0} + {blue, 5'd0} + {blue, 2'd0});
wire [18:0] pb_8 = 19'd32768 - ({red, 7'd0} + {red, 4'd0} + {red, 3'd0}) - ({green, 8'd0} + {green, 5'd0} + {green, 3'd0}) + ({blue, 8'd0} + {blue, 7'd0} + {blue, 6'd0});
wire [18:0] pr_8 = 19'd32768 + ({red, 8'd0} + {red, 7'd0} + {red, 6'd0}) - ({green, 8'd0} + {green, 6'd0} + {green, 5'd0} + {green, 4'd0} + {green, 3'd0}) - ({blue, 6'd0} + {blue , 3'd0});

wire [7:0] y  = ( y_8[17:8] < 16) ? 8'd16 : ( y_8[17:8] > 235) ? 8'd235 :  y_8[15:8];
wire [7:0] pb = (pb_8[17:8] < 16) ? 8'd16 : (pb_8[17:8] > 240) ? 8'd240 : pb_8[15:8];
wire [7:0] pr = (pr_8[17:8] < 16) ? 8'd16 : (pr_8[17:8] > 240) ? 8'd240 : pr_8[15:8];

assign VGA_R  = ypbpr ? (ypbpr_full ? yuv_full[pr-8'd16] : pr[7:2]) :   red;
assign VGA_G  = ypbpr ? (ypbpr_full ? yuv_full[y -8'd16] :  y[7:2]) : green;
assign VGA_B  = ypbpr ? (ypbpr_full ? yuv_full[pb-8'd16] : pb[7:2]) :  blue;
assign VGA_VS = (scandoubler_disable | ypbpr) ? 1'b1 : ~vs_sd;
assign VGA_HS = scandoubler_disable ? ~(HSync ^ VSync) : ypbpr ? ~(hs_sd ^ vs_sd) : ~hs_sd;

endmodule
