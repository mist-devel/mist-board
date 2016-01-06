// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

module VgaDriver(
	input  clk,
	input [5:0] color,        // Pixel for current cycle.
	input sync_frame,
	input sync_line,
	input mode,
	input vga_smooth,
	input border,
	
	input sck,
	input ss,
	input sdi,

	output reg   vga_h, 
	output reg   vga_v,
	output [5:0] VGA_R, 
	output [5:0] VGA_G, 
	output [5:0] VGA_B
);
 
// NES Palette -> RGB555 conversion
reg [15:0] pallut[0:63];
initial $readmemh("nes_palette.txt", pallut);
wire [14:0] pixel = pallut[color][14:0];

// Horizontal and vertical counters
reg [9:0] h, v;
wire hpicture  = (h < 512);                    // 512 lines of picture
wire hsync_on  = (h == 512 + 23 + (mode ? 18 : 35));         // HSync ON, 23+35 pixels front porch
wire hsync_off = (h == 512 + 23 + (mode ? 18 : 35) + 82);   // Hsync off, 82 pixels sync
wire hend = (h == 681);                       // End of line, 682 pixels.

wire vpicture = (v < (480 >> mode));                    // 480 lines of picture
wire vsync_on  = hsync_on && (v == (mode ? 240 + 5  : 480 + 10)); // Vsync ON, 10 lines front porch.
wire vsync_off = hsync_on && (v == (mode ? 240 + 14 : 480 + 12)); // Vsync OFF, 2 lines sync signal
wire vend = (v == (523 >> mode));                       // End of picture, 524 lines. (Should really be 525 according to NTSC spec)
wire inpicture = hpicture && vpicture;
wire [9:0] new_h = (hend || (mode ? sync_frame : doubler_sync)) ? 10'd0 : h + 10'd1;

wire [14:0] doubler_pixel;
wire doubler_sync;

Hq2x hq2x(clk, pixel, vga_smooth, // enabled 
            sync_frame,       // reset_frame
            sync_line, 			// reset_line
            {doubler_sync ? 1'b0 : hend ? !v[0] : v[0], new_h[8:0]},  // 0-511 for line 1, or 512-1023 for line 2.
            doubler_sync,     // new frame has just started
            doubler_pixel);   // pixel is outputted

reg clk2 = 1'b0;
always @(posedge clk) clk2 <= ~clk2;
wire clkv = mode ? clk2 : clk;

osd #(10'd0,10'd0,3'd4) osd (
   .pclk(clkv),

   .sck(sck),
   .sdi(sdi),
   .ss(ss),

   .red_in  ({vga_r, 1'b0}),
   .green_in({vga_g, 1'b0}),
   .blue_in ({vga_b, 1'b0}),
   .hs_in(vga_h),
   .vs_in(vga_v),

   .red_out(VGA_R),
   .green_out(VGA_G),
   .blue_out(VGA_B)
);

reg [4:0] vga_r;
reg [4:0] vga_g;
reg [4:0] vga_b;

always @(posedge clkv) begin
  h <= new_h;
  if(mode ? sync_frame : doubler_sync) begin
    vga_v <= 1;
    vga_h <= 1;
    v <= 0;
  end else begin
    vga_h <= hsync_on ? 1'b0 : hsync_off ? 1'b1 : vga_h;
    if (hend)
      v <= vend ? 10'd0 : v + 10'd1;
    vga_v <= vsync_on ? 1'b0 : vsync_off ? 1'b1 : vga_v;
    vga_r <= mode ? pixel[4:0]   : doubler_pixel[4:0];
    vga_g <= mode ? pixel[9:5]   : doubler_pixel[9:5];
    vga_b <= mode ? pixel[14:10] : doubler_pixel[14:10];
    if (border && (h == 0 || h == 511 || v == 0 || v == (479 >> mode))) begin
      vga_r <= 4'b1111;
      vga_g <= 4'b1111;
      vga_b <= 4'b1111;
    end
    if (!inpicture) begin
      vga_r <= 4'b0000;
      vga_g <= 4'b0000;
      vga_b <= 4'b0000;
    end
  end
end
endmodule
