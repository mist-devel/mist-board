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

// clocks on real sts:
// PAL  32084988 Hz
// NTSC 32042400 Hz
// MIST 31875000 Hz

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
// scan doubled modes a multiple of 8

// ---------------------------------------------------------------------------
// -----------------------------  pal56 timing -------------------------------
// ---------------------------------------------------------------------------

// 56Hz replacement for Atari 50Hz low and medium resolution video mode scan doubled:
// total: 1024x626, active incl border: 800x560, displayed: 640x400
// horizontal scan rate: 17.27 kHz, vertical scan rate: 56.34 hz


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

// Atari 50Hz low and medium resolution video mode scan doubled:
// total: 1024x626, active incl border: 800x560, displayed: 640x400
// horizontal scan rate: 15.625 kHz, vertical scan rate: 49.92 hz

wire [121:0] pal50_config_str;
conf pal50_conf(
// front porch      sync width      back porch       border width    sync polarity
	.h_fp ( 10'd80), .h_s ( 10'd64), .h_bp ( 10'd80), .h_bd (10'd80), .h_sp (1'b1),
	.v_fp ( 10'd30), .v_s (  10'd6), .v_bp ( 10'd30), .v_bd (10'd80), .v_sp (1'b1),
	.str  (pal50_config_str)
);

// ---------------------------------------------------------------------------
// ------------------------------  ntsc timing -------------------------------
// ---------------------------------------------------------------------------

// Atari 60Hz low and medium resolution video mode scan doubled:
// total: 1016x526, active incl border: 800x480, displayed: 640x400
// horizontal scan rate: 15.748 kHz, vertical scan rate: 59.88 hz

wire [121:0] ntsc_config_str;
conf ntsc_conf(
// front porch      sync width      back porch       border width    sync polarity
	.h_fp ( 10'd76), .h_s ( 10'd64), .h_bp ( 10'd76), .h_bd (10'd80), .h_sp (1'b1),
	.v_fp ( 10'd20), .v_s (  10'd6), .v_bp ( 10'd20), .v_bd (10'd40), .v_sp (1'b0),
	.str  (ntsc_config_str)
);

// ---------------------------------------------------------------------------
// ------------------------------  mono timing -------------------------------
// ---------------------------------------------------------------------------

// Atari 71Hz high resolution video mode:
// total: 896x501, displayed: 640x400
// horizontal scan rate: 35.714 kHz, vertical scan rate: 71.286 hz

wire [121:0] mono_config_str;

conf mono_conf(
// front porch      sync width      back porch       border width    sync polarity
	.h_fp (10'd108), .h_s ( 10'd40), .h_bp (10'd108), .h_bd ( 10'd0), .h_sp (1'b0),
	.v_fp ( 10'd48), .v_s (  10'd5), .v_bp ( 10'd48), .v_bd ( 10'd0), .v_sp (1'b0),
	.str  (mono_config_str)
);


// this is the video mode multiplexer ...
assign mode_str = mono?mono_config_str:(pal?(pal56?pal56_config_str:pal50_config_str):ntsc_config_str);

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