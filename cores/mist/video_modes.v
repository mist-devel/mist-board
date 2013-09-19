//
// video_modes.v
// 
// Video modes for Atari ST shifter implementation for the MiST board
// http://code.google.com/p/mist-board/
// 
// Copyright (c) 2013 Till Harbaum <till@harbaum.org> 
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

// video docs: 
// http://martin.hinner.info/vga/timing.html
// http://www.epanorama.net/faq/vga2rgb/calc.html

// original atari video timing 
//         mono     color
// pclk    32MHz    16/8MHz
// hfreq   35.7kHz  15.75kHz
// vfreq   71.2Hz   50/60Hz
//
// avg. values derived from frequencies:
// hdisp   640      640/320
// htot    896      1015/507
// vdisp   400      200
// vtot    501      315/262

module video_modes (
	inout mono,   // select monochrome mode (and not color)
	input pal,    // select pal mode (and not ntsc) if a color mode is selected
	input pal56,  // use a 56 hz mode if pal mode is selected

	output [121:0] mode_str
);

// ---------------------------------------------------------------------------
// ---------------------------- generic timing parameters --------------------
// ---------------------------------------------------------------------------

localparam H_ACT    = 10'd640;
localparam V_ACT    = 10'd400;

// TIMING CONSTRAINTS:
// The total width (act+both blank+2*border+sync) must be a multiple of 16, for
// low rez a multiple of 32
// For modes to be used with the scan doubler the total heigth (act+both blank+
// 2*border+sync) must be a multiple of 4

// ---------------------------------------------------------------------------
// -----------------------------  pal56 timing -------------------------------
// ---------------------------------------------------------------------------

// PAL modes need ~80 pixels vertical border for border removal
// 34.21 kHz / 55.9 Hz

wire [121:0] pal56_config_str;

conf pal56_conf(
// front porch      sync width      back porch       border width    sync polarity
	.h_fp ( 10'd44), .h_s (10'd120), .h_bp ( 10'd44), .h_bd (10'd40), .h_sp (1'b1),
	.v_fp ( 10'd24), .v_s (  10'd4), .v_bp ( 10'd24), .v_bd (10'd80), .v_sp (1'b1),
	.str  (pal56_config_str)
);

// ---------------------------------------------------------------------------
// -----------------------------  pal50 timing -------------------------------
// ---------------------------------------------------------------------------

wire [121:0] pal50_config_str;

conf pal50_conf(
// front porch      sync width      back porch       border width    sync polarity
	.h_fp ( 10'd80), .h_s ( 10'd40), .h_bp (10'd152), .h_bd (10'd40), .h_sp (1'b1),
	.v_fp ( 10'd37), .v_s (  10'd3), .v_bp ( 10'd36), .v_bd (10'd80), .v_sp (1'b1),
	.str  (pal50_config_str)
);

// ---------------------------------------------------------------------------
// ------------------------------  ntsc timing -------------------------------
// ---------------------------------------------------------------------------

// 31.01 kHz / 59.63 Hz

wire [121:0] ntsc_config_str;

conf ntsc_conf(
// front porch      sync width      back porch       border width    sync polarity
	.h_fp ( 10'd88), .h_s (10'd120), .h_bp ( 10'd96), .h_bd (10'd40), .h_sp (1'b0),
	.v_fp ( 10'd18), .v_s (  10'd3), .v_bp ( 10'd19), .v_bd (10'd40), .v_sp (1'b0),
	.str  (ntsc_config_str)
);

// ---------------------------------------------------------------------------
// ------------------------------  mono timing -------------------------------
// ---------------------------------------------------------------------------

wire [121:0] mono_config_str;

conf mono_conf(
// front porch      sync width      back porch       border width    sync polarity
	.h_fp ( 10'd24), .h_s ( 10'd40), .h_bp (10'd128), .h_bd ( 10'd0), .h_sp (1'b0),
	.v_fp ( 10'd55), .v_s (  10'd3), .v_bp ( 10'd74), .v_bd ( 10'd0), .v_sp (1'b0),
	.str  (mono_config_str)
);


// this is the video mode multiplexer ...
assign mode_str = 
	mono?mono_config_str:(pal?(pal56?pal56_config_str:pal50_config_str):ntsc_config_str);

endmodule

// ---------------------------------------------------------------------------
// ------------------ video timing config string generator -------------------
// ---------------------------------------------------------------------------
module conf (
	input [9:0] h_fp, // horizontal front porch width
	input [9:0] h_s,  // horizontal sync width
	input [9:0] h_bp, // horizontal back porch width
	input [9:0] h_bd, // horizontal border width
	input       h_sp, // horizontal sync polarity

	input [9:0] v_fp, // vertical front porch width
	input [9:0] v_s,  // vertical sync width
	input [9:0] v_bp, // vertical back porch width
	input [9:0] v_bd, // vertical border width
	input       v_sp, // vertical sync polarity

	output [121:0] str
);

// all Atari video mods are based on a 640x400 screen
localparam H_ACT = 10'd640;
localparam V_ACT = 10'd400;

// all parameters are assembled into one config string 
wire [60:0] h_str = { h_sp, 
			H_ACT - 10'd1, 
			H_ACT + h_bd - 10'd1, 
			H_ACT + h_bd + h_fp - 10'd1, 
			H_ACT + h_bd + h_fp + h_s - 10'd1, 
			H_ACT + h_bd + h_fp + h_s + h_bp - 10'd1, 
			H_ACT + h_bd + h_fp + h_s + h_bp + h_bd - 10'd1};
			
wire [60:0] v_str = { v_sp, 
			V_ACT - 10'd1, 
			V_ACT + v_bd - 10'd1,
			V_ACT + v_bd + v_fp - 10'd1, 
			V_ACT + v_bd + v_fp + v_s - 10'd1, 
			V_ACT + v_bd + v_fp + v_s + v_bp - 10'd1, 
			V_ACT + v_bd + v_fp + v_s + v_bp + v_bd - 10'd1};
			
assign str = { h_str, v_str };

endmodule