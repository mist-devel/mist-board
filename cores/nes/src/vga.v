// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

module VgaDriver(input clk,
                 output reg vga_h, output reg vga_v,
                 output reg [4:0] vga_r, output reg[4:0] vga_g, output reg[4:0] vga_b,
                 output [9:0] vga_hcounter,
                 output [9:0] vga_vcounter,
                 output [9:0] next_pixel_x, // The pixel we need NEXT cycle.
                 input [14:0] pixel,        // Pixel for current cycle.
                 input sync,
                 input border);
// Horizontal and vertical counters
reg [9:0] h, v;
wire hpicture = (h < 512);                    // 512 lines of picture
wire hsync_on = (h == 512 + 23 + 35);         // HSync ON, 23+35 pixels front porch
wire hsync_off = (h == 512 + 23 + 35 + 82);   // Hsync off, 82 pixels sync
wire hend = (h == 681);                       // End of line, 682 pixels.

wire vpicture = (v < 480);                    // 480 lines of picture
wire vsync_on  = hsync_on && (v == 480 + 10); // Vsync ON, 10 lines front porch.
wire vsync_off = hsync_on && (v == 480 + 12); // Vsync OFF, 2 lines sync signal
wire vend = (v == 523);                       // End of picture, 524 lines. (Should really be 525 according to NTSC spec)
wire inpicture = hpicture && vpicture;
assign vga_hcounter = h;
assign vga_vcounter = v;
wire [9:0] new_h = (hend || sync) ? 0 : h + 1;
assign next_pixel_x = {sync ? 1'b0 : hend ? !v[0] : v[0], new_h[8:0]};

always @(posedge clk) begin
  h <= new_h;
  if (sync) begin
    vga_v <= 1;
    vga_h <= 1;
    v <= 0;
  end else begin
    vga_h <= hsync_on ? 0 : hsync_off ? 1 : vga_h;
    if (hend)
      v <= vend ? 0 : v + 1;
    vga_v <= vsync_on ? 0 : vsync_off ? 1 : vga_v;
    vga_r <= pixel[4:0];
    vga_g <= pixel[9:5];
    vga_b <= pixel[14:10];
    if (border && (h == 0 || h == 511 || v == 0 || v == 479)) begin
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
