`timescale 1ns / 1ps

// Core should provide as much color resolution as possible with normalized 0-255 range
// this module will reduce color resolution to 6 bits only at final stage.

module video_mixer
(
	// 0 = HVSync 31KHz, 1 = CSync 15KHz
	input        scandoubler_disable,

	// YPbPr always uses composite sync
	input        ypbpr,

	// 0 = 16-240 range. 1 = 0-255 range. (only for YPbPr color space)
	input        ypbpr_full,

	// interlace (15khz) color
	input  [7:0] r_i,
	input  [7:0] g_i,
	input  [7:0] b_i,

	// interlace sync. Positive pulses.
	input        hsync_i,
	input        vsync_i,

	// progressive (31khz) color
	input  [7:0] r_p,
	input  [7:0] g_p,
	input  [7:0] b_p,

	// progressive sync. Positive pulses.
	input        hsync_p,
	input        vsync_p,

	// MiST video output signals
	output [5:0] VGA_R,
	output [5:0] VGA_G,
	output [5:0] VGA_B,
	output       VGA_VS,
	output       VGA_HS
);

wire [7:0] red   = scandoubler_disable ? r_i : r_p;
wire [7:0] green = scandoubler_disable ? g_i : g_p;
wire [7:0] blue  = scandoubler_disable ? b_i : b_p;

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

wire [18:0]  y_8 = 19'd04096 + ({red, 6'd0} + {red, 1'd0}) + ({green, 7'd0} + {green}) + ({blue, 4'd0} + {blue, 3'd0} + {blue});
wire [18:0] pb_8 = 19'd32768 - ({red, 5'd0} + {red, 2'd0} + {red, 1'd0}) - ({green, 6'd0} + {green, 3'd0} + {green, 1'd0}) + ({blue, 6'd0} + {blue, 5'd0} + {blue, 4'd0});
wire [18:0] pr_8 = 19'd32768 + ({red, 6'd0} + {red, 5'd0} + {red, 4'd0}) - ({green, 6'd0} + {green, 4'd0} + {green, 3'd0} + {green, 2'd0} + {green, 1'd0}) - ({blue, 4'd0} + {blue , 1'd0});

wire [7:0] y  = ( y_8[17:8] < 16) ? 8'd16 : ( y_8[17:8] > 235) ? 8'd235 :  y_8[15:8];
wire [7:0] pb = (pb_8[17:8] < 16) ? 8'd16 : (pb_8[17:8] > 240) ? 8'd240 : pb_8[15:8];
wire [7:0] pr = (pr_8[17:8] < 16) ? 8'd16 : (pr_8[17:8] > 240) ? 8'd240 : pr_8[15:8];

assign VGA_R  = ypbpr ? (ypbpr_full ? yuv_full[pr-8'd16] : pr[7:2]) :   red[7:2];
assign VGA_G  = ypbpr ? (ypbpr_full ? yuv_full[y -8'd16] :  y[7:2]) : green[7:2];
assign VGA_B  = ypbpr ? (ypbpr_full ? yuv_full[pb-8'd16] : pb[7:2]) :  blue[7:2];
assign VGA_VS = (scandoubler_disable | ypbpr) ? 1'b1 : ~vsync_p;
assign VGA_HS = scandoubler_disable ? ~(hsync_i ^ vsync_i) : ypbpr ? ~(hsync_p ^ vsync_p) : ~hsync_p;

endmodule
