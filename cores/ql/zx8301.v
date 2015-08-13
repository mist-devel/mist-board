//
// zx8301.v
//
// ZX8301 ULA for Sinclair QL for the MiST
// https://github.com/mist-devel
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
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

module zx8301 (
	input  reset,

   // clock
   input  clk_vga,        // 21 Mhz VGA pixel clock
   input  clk_video,      // 10.5 MHz QL pixel clock
	input  video_cycle,
	
	// config options
	input  ntsc,
	input  scandoubler,
	input  scanlines,

	// CPU interface to access $18063
	input  clk_bus,
	input  cpu_cs,
	input  [7:0] cpu_data,

	// sdram interface
	output reg [18:0] addr,
	output rd,
	input [15:0] din,
	
	// signal telling mdv emulation that it may use the video
	output reg mdv_men,
	
   // VIDEO output
   output hs,
   output reg 	vs,
   output [5:0] r,
   output [5:0] g,
   output [5:0] b
);

assign rd = me;

/* ----------------------------------------------------------------- */
/* -------------------------- CPU register ------------------------- */
/* ----------------------------------------------------------------- */
// [6] -> NTSC?

wire membase = mc_stat[7];      // 0 = $20000, 1 = $28000
wire mode = mc_stat[3];         // 0 = 512*256*2bpp, 1=256*256*4bpp
wire blank = mc_stat[1];        // 0 = normal video, 1 = blanked video

reg [7:0] mc_stat;

always @(negedge clk_bus) begin
	if(reset)   
		mc_stat <= 8'h00;
	else if(cpu_cs)	
		mc_stat <= cpu_data;
end
	
/* ----------------------------------------------------------------- */
/* ---------------------- video timing values ---------------------- */
/* ----------------------------------------------------------------- */

// PAL video parameters					
parameter H   = 512;        // width of visible area
//parameter PAL_HFP = 112;    // unused time before hsync
//parameter PAL_HSW = 96;     // width of hsync
//parameter PAL_HBP = 176;    // unused time after hsync
//// PAL total: 896
//parameter NTSC_HFP = 112;   // unused time before hsync
//parameter NTSC_HSW = 88;    // width of hsync
//parameter NTSC_HBP = 176;   // unused time after hsync
//// NTSC total: 888
parameter PAL_HFP = 34;     // unused time before hsync
parameter PAL_HSW = 72;     // width of hsync
parameter PAL_HBP = 54;     // unused time after hsync
// PAL total: 672
parameter NTSC_HFP = 34;    // unused time before hsync
parameter NTSC_HSW = 64;    // width of hsync
parameter NTSC_HBP = 54;    // unused time after hsync
// NTSC total: 664
   
parameter V   = 256;        // height of visible area
parameter PAL_VFP = 15;     // unused time before vsync
parameter PAL_VSW =  6;     // width of vsync
parameter PAL_VBP = 35;     // unused time after vsync
// PAL total: 312
parameter NTSC_VFP = 2;     // unused time before vsync
parameter NTSC_VSW = 2;     // width of vsync
parameter NTSC_VBP = 2;     // unused time after vsync
// NTSC total: 262
   
// both counters count from the begin of the visibla area
reg [9:0] h_cnt;        // horizontal pixel counter
reg [9:0] sd_h_cnt;     // scandoubler horizontal pixel counter
reg [9:0] v_cnt;        // vertical pixel counter

// swtich between ntsc and pal values
wire [9:0] hfp = ntsc?NTSC_HFP:PAL_HFP;
wire [9:0] hsw = ntsc?NTSC_HSW:PAL_HSW;
wire [9:0] hbp = ntsc?NTSC_HBP:PAL_HBP;
wire [9:0] vfp = ntsc?NTSC_VFP:PAL_VFP;
wire [9:0] vsw = ntsc?NTSC_VSW:PAL_VSW;
wire [9:0] vbp = ntsc?NTSC_VBP:PAL_VBP;

// QL colors
localparam BLACK   = 3'b000;
localparam BLUE    = 3'b001;
localparam GREEN   = 3'b010;
localparam CYAN    = 3'b011;
localparam RED     = 3'b100;
localparam MAGENTA = 3'b101;
localparam YELLOW  = 3'b110;
localparam WHITE   = 3'b111;

/* ----------------------------------------------------------------- */
/* ------------------------ VGA scandoubler ------------------------ */
/* ----------------------------------------------------------------- */

// scan doubler buffer can hold two lines
reg [2:0] sd_buffer [1023:0];
reg sd_scanline;
reg sd_toggle;

// the scandoubler alternates between two buffers
// one is being written while the other one is being output
always @(posedge clk_video)
	if(h_cnt == H+hfp+hsw+hbp-1)
		sd_toggle = !sd_toggle;

// scandoubler horizontal pixel counter
always@(posedge clk_vga) begin
	// synchronize to 
	if((!clk_video && (h_cnt==H+hfp+hsw+hbp-1)) ||
		(sd_h_cnt==H+hfp+hsw+hbp-1))  sd_h_cnt <= 0;
	else                             sd_h_cnt <= sd_h_cnt + 1;

	// generate negative hsync signal
	if(sd_h_cnt == H+hfp)     sd_hs <= 1'b0;
	if(sd_h_cnt == H+hfp+hsw) begin	
		sd_hs <= 1'b1;
		sd_scanline <= !sd_scanline;
	end
	
	if(v_cnt == V+vfp+vsw+vbp-1)
		sd_scanline <= 1'b0;
end

// write to scandoubler buffer at QL pixel clock
always @(posedge clk_video) begin
	if(h_cnt < H) begin
		if(v_cnt < V)
			sd_buffer[{sd_toggle, h_cnt[8:0]}] <= mode?pixel_color_4bpp:pixel_color_2bpp;
		else
			sd_buffer[{sd_toggle, h_cnt[8:0]}] <= 3'b000;
	end
end

// read from scandoubler buffer at twice QL pixel clock
reg [2:0] sd_pixel;
reg [2:0] sd_buffer_out;
always @(posedge clk_vga) begin
	sd_buffer_out <= sd_buffer[{~sd_toggle, sd_h_cnt[8:0]}];
	if((sd_h_cnt > 1) && (sd_h_cnt <= H)) sd_pixel <= sd_buffer_out;
	else                                  sd_pixel <= 3'b000;
end
//	sd_pixel <= (sd_h_cnt < H)?sd_buffer[{~sd_toggle, sd_h_cnt[8:0]}]:3'b000;
//	sd_buffer_out <= sd_buffer[{~sd_toggle, sd_h_cnt[8:0]}];
	
/* ----------------------------------------------------------------- */
/* -------------------- video timing generation -------------------- */
/* ----------------------------------------------------------------- */

// toggle between scandoubler hsync and ql hsync
reg sd_hs, ql_hs;
assign hs = scandoubler?sd_hs:ql_hs;

reg video_cycleD;
reg [2:0] video_cycle_cnt;

// mode 8 supports hardware flashing
reg flash_state;
reg [5:0] flash_cnt;
always @(posedge vs) begin
	if(flash_cnt == 25) begin
		flash_cnt <= 6'd0;
		flash_state <= !flash_state;
	end else
		flash_cnt <= flash_cnt + 6'd1;
end

// horizontal pixel counter
always@(posedge clk_video) begin
	// video cycle counter runs at pixel clock and 
	// synchronous to video_cycle
	video_cycleD <= video_cycle;
	if(video_cycle && !video_cycleD)
		video_cycle_cnt <= 3'd0;
	else
		video_cycle_cnt <= video_cycle_cnt + 3'd1;
	
	// make sure h counter runs synchronous to bus_cycle
	if(h_cnt==H+hfp+hsw+hbp-1) begin
		if(video_cycle_cnt == 6)
			h_cnt <= 0;
	end else
		h_cnt <= h_cnt + 1;

	// generate negative hsync signal
	if(h_cnt == H+hfp)     ql_hs <= 1'b0;
	if(h_cnt == H+hfp+hsw) ql_hs <= 1'b1;
end


// veritical pixel counter
always@(posedge clk_video) begin
	// the vertical counter is processed at the begin of each hsync
	if(h_cnt == H+hfp) begin
		if(v_cnt==V+vfp+vsw+vbp-1)  v_cnt <= 0; 
		else						       v_cnt <= v_cnt + 1;

      // generate positive vsync signal
		if(v_cnt == V+vfp)     vs <= 1'b1;
		if(v_cnt == V+vfp+vsw) vs <= 1'b0;
	end
end

reg [15:0] video_din;
reg [15:0] video_word;
reg [2:0] ql_pixel;

always @(negedge video_cycle)
	video_din <= din;

// memory enable is 16 pixels ahead of display
reg meV, me;
always@(posedge clk_video) begin
	// the verical "memory enable" changes
	if(h_cnt == H+hfp+hsw+hbp-1-9) begin
		if(v_cnt == 0)  meV <= 1'b1;
		if(v_cnt == V)  meV <= 1'b0;
	end

	if(meV) begin
		if(h_cnt == H+hfp+hsw+hbp-1-8) me <= 1'b1;
		if(h_cnt == H-1-8)             me <= 1'b0;
	end

	// mdv emulation may use the video bus cycle to read
	// data whenever video is not using the bus
	if(h_cnt == H-1)  mdv_men <= 1'b1;
	if(h_cnt == H+31) mdv_men <= 1'b0;
end

// 2BPP: G0,G1,G2,G3,G4,G5,G6,G7 R0,R1,R2,R3,R4,R5,R6,R7
wire [1:0] pixel_code_2bpp = {video_word[15], video_word[7]};
wire [2:0] pixel_color_2bpp = 
	(pixel_code_2bpp == 0)?BLACK:     // 0=black 
	(pixel_code_2bpp == 1)?RED:       // 1=red 
	(pixel_code_2bpp == 2)?GREEN:     // 2=green 
	WHITE;                            // 3=white
	
// 4BPP: G0,F0,G1,F1,G2,F2,G3,F3 R0,B0,R1,B1,R2,B2,R3,B3
wire [2:0] pixel_code_4bpp = {video_word[15], video_word[7:6]};
wire pixel_flash_toggle = video_word[14];

wire [2:0] pixel_color_4bpp =
	(flash_reg && flash_state)?flash_col: // flash to saved color
	(pixel_code_4bpp == 0)?BLACK:         // 0=black 
	(pixel_code_4bpp == 1)?BLUE:          // 1=blue
	(pixel_code_4bpp == 2)?RED:           // 2=red 
	(pixel_code_4bpp == 3)?MAGENTA:       // 3=magenta 
	(pixel_code_4bpp == 4)?GREEN:         // 4=green
	(pixel_code_4bpp == 5)?CYAN:          // 5=cyan
	(pixel_code_4bpp == 6)?YELLOW:        // 6=yellow 
	WHITE;                                // 7=white

reg flash_reg;
reg [2:0] flash_col;
always@(posedge clk_video) begin
	if(h_cnt == H+1)
		flash_reg <= 1'b0;   // reset flash state at the begin of each line

	if((v_cnt == V+1) && (h_cnt == H+1))
		addr <= membase?19'h14000:19'h10000;  // word! address

	if((me)&&(h_cnt[2:0] == 3'b111)) begin
		addr <= addr + 19'd1;
		video_word <= video_din;
	end else begin
		if(mode) begin 
			// 4bpp: shift rgbf every second pixel clock
			if(h_cnt[0])
				video_word <= { video_word[13:8], 2'b00, video_word[5:0], 2'b00 };
		end else
			// 2bpp, shift green byte and red byte up one pixel
			video_word <= { video_word[14:8], 1'b0, video_word[6:0], 1'b0 };
	end

	// visible area?
	if((v_cnt < V) && (h_cnt < H)) begin
		if(mode) begin
			ql_pixel <= pixel_color_4bpp;
			
			// change state of flash_reg if flasg bit in current pixel is set
			// do this in the second half of the pixel so it's valid afterwards for the
			// next pixels. the current pixel directly honours pixel_flash_toggle
			if(h_cnt[0] && pixel_flash_toggle) begin
				flash_reg <= !flash_reg;
				flash_col <= pixel_color_4bpp;
			end
		end else
			ql_pixel <= pixel_color_2bpp;
	end else
		// black pixel outside active area
		ql_pixel <= 4'h0;
end

wire [2:0] pixel = blank?3'b000:scandoubler?sd_pixel:ql_pixel;

// the current line is a scanline if the scandoubler is being used, if 
// scanlines are emnabled and if it's a scanline 
wire is_scanline = scandoubler && scanlines && sd_scanline;
assign r = {(is_scanline?1'b0:pixel[2]), {5{pixel[2]}}};
assign g = {(is_scanline?1'b0:pixel[1]), {5{pixel[1]}}};
assign b = {(is_scanline?1'b0:pixel[0]), {5{pixel[0]}}};

endmodule
