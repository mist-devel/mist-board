// A simple system-on-a-chip (SoC) for the MiST
// (c) 2016 Till Harbaum

// video controller generating 160x100 pixles. The video mode is based
// upon a non-interlaced PAL or NTSC TV mode.


module video (
   // pixel clock
   input  pclk,
	
	// config input
	input  pal,
	
	// CPU interface (write only!)	
	input  cpu_clk,
	input  cpu_wr,
	input [13:0] cpu_addr,
	input [7:0] cpu_data,

	// output to VGA screen
   output reg	hs,
   output reg 	vs,
   output [5:0] r,
   output [5:0] g,
   output [5:0] b
);

// PAL timing: 
// 864 pixel total horizontal @ 13.5 Mhz = 15.625 kHz
// 312 lines vertically @ 15.625 kHz = 50.08 Hz

// NTSC timing: 
// 858 pixel total horizontal @ 13.5 Mhz = 15.735 kHz
// 262 lines vertically @ 15.735 kHz = 60.05 Hz

parameter H   = 640;         // width of visible area
wire [9:0] hfp = pal?51:56;  // unused time before hsync
wire [9:0] hsw = pal?63:63;  // width of hsync
wire [9:0] hbp = pal?110:99; // unused time after hsync

parameter V   = 200;         // height of visible area
wire [9:0] vfp = pal?46:23;  // unused time before vsync
wire [9:0] vsw = pal?2:3;    // width of vsync
wire [9:0] vbp = pal?64:36;  // unused time after vsync

reg[9:0]  h_cnt;        // horizontal pixel counter
reg[9:0]  v_cnt;        // vertical pixel counter

// horizontal pixel counter
always@(posedge pclk) begin
	if(h_cnt==H+hfp+hsw+hbp-1)  h_cnt <= 10'd0;
	else                        h_cnt <= h_cnt + 10'd1;

        // generate negative hsync signal
	if(h_cnt == H+hfp)     hs <= 1'b0;
	if(h_cnt == H+hfp+hsw) hs <= 1'b1;
end

// veritical pixel counter
always@(posedge pclk) begin
        // the vertical counter is processed at the begin of each hsync
	if(h_cnt == H+hfp) begin
		if(v_cnt==vsw+vbp+V+vfp-1) v_cnt <= 10'd0; 
		else								v_cnt <= v_cnt + 10'd1;

               // generate negative vsync signal
 		if(v_cnt == V+vfp)     vs <= 1'b0;
		if(v_cnt == V+vfp+vsw) vs <= 1'b1;
	end
end

// 16000 bytes of internal video memory for 160x100 pixel at 8 Bit (RGB 332)
reg [7:0] vmem [160*100-1:0];

reg [13:0] video_counter;
reg [7:0] pixel;

// write VRAM via CPU interface
always @(posedge cpu_clk)
	if(cpu_wr) 
		vmem[cpu_addr] <= cpu_data;

// read VRAM for video generation
always@(posedge pclk) begin
       // The video counter is being reset at the begin of each vsync.
        // Otherwise it's increased every fourth pixel in the visible area.
        // At the end of the first three of four lines the counter is
        // decreased by the total line length to display the same contents
        // for four lines so 100 different lines are displayed on the 400
        // VGA lines.

        // visible area?
	if((v_cnt < V) && (h_cnt < H)) begin
		// increase video counter after each pixel
		if(h_cnt[1:0] == 2'd3)
			video_counter <= video_counter + 14'd1;
		
		pixel <= vmem[video_counter];               // read VRAM
	end else begin
	        // video counter is manipulated at the end of a line outside
	        // the visible area
		if(h_cnt == H+hfp) begin
				// the video counter is reset at the begin of the vsync
		      // at the end of every second line it's decremented
		      // one line to repeat the same pixels over two display
		      // lines
			if(v_cnt == V+vfp)
				video_counter <= 14'd0;
			else if((v_cnt < V) && (v_cnt[0] != 2'd1))
				video_counter <= video_counter - 14'd160;
		end
			
		pixel <= 8'h00;   // color outside visible area: black
	end
end

// split the 8 rgb bits into the three base colors. Every second line is
// darker to give some scanlines effect
assign r = { pixel[7:5],  3'b000 };
assign g = { pixel[4:2],  3'b000 };
assign b = { pixel[1:0], 4'b0000 };

endmodule
