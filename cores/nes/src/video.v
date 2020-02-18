// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

module video(
	input  clk,
	input [5:0] color,
	input [8:0] count_h,
	input [8:0] count_v,
  input pal_video,
	input overscan,
	input palette,
	
	output reg   sync_h,
	output reg   sync_v,
	output [4:0] r,
	output [4:0] g,
	output [4:0] b
);

reg vidclk_en;
always @(posedge clk) vidclk_en <= ~vidclk_en;

// NTSC UnsaturatedV6 palette
//see: http://www.firebrandx.com/nespalette.html
reg [15:0] pal_unsat_lut[0:63];
initial $readmemh("nes_palette_unsaturatedv6.txt", pal_unsat_lut);

// FCEUX palette
reg [15:0] pal_fcelut[0:63];
initial $readmemh("nes_palette_fceux.txt", pal_fcelut);

wire [14:0] pixel = palette ?  pixel_unsat[14:0] : pixel_fce[14:0];
reg [15:0] pixel_unsat, pixel_fce;

always @(posedge clk) begin
	pixel_unsat <= pal_unsat_lut[color];
	pixel_fce <= pal_fcelut[color];
end

// Horizontal and vertical counters
reg [9:0] h, v;
wire hpicture  = (h < 512);             // 512 lines of picture
wire hend = (h == 681);                 // End of line, 682 pixels.
wire vpicture = (v < 240);              // 240 lines of picture
wire vend = (v == (pal_video ? 311 : 261)); // End of picture, 262/312 lines.

reg [8:0] old_count_v;
wire sync_frame = (old_count_v == 9'd511) && (count_v == 9'd0);
always @(posedge clk) begin
	if (vidclk_en) begin
		h <= (hend || sync_frame) ? 10'd0 : h + 10'd1;
		if(sync_frame) v <= 0;
		else if (hend) v <= vend ? 10'd0 : v + 10'd1;

		old_count_v <= count_v;
	end
end

wire [14:0] pixel_v = (!hpicture || !vpicture) ? 15'd0 : pixel;

// display overlay to hide overscan area
// based on Mario3, DoubleDragon2, Shadow of the Ninja
wire ol = overscan && ( (h > 512-16) ||
								(h < 20) ||
								(v < 6 ) ||
								(v > (240-10))
							  );

assign      r = ol ? {4'b0, pixel_v[4:4]}   : pixel_v[4:0];
assign      g = ol ? {4'b0, pixel_v[9:9]}   : pixel_v[9:5];
assign      b = ol ? {4'b0, pixel_v[14:14]} : pixel_v[14:10];

always @(posedge clk) begin
	if (vidclk_en) begin
		if (h == 556) begin
			sync_h <= 1;
			sync_v <= (v >= (pal_video ? 270 : 243) && (v < ((pal_video ? 270 : 243) + 3)));
		end
		if (h == 606) sync_h <= 0;
	end
end

endmodule
