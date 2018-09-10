// A simple system-on-a-chip (SoC) for the MiST
// (c) 2015 Till Harbaum
									  
module soc (
   input [1:0] CLOCK_27,
   output 		SDRAM_nCS,
	
   // SPI interface to arm io controller
   output      SPI_DO,
   input       SPI_DI,
   input       SPI_SCK,
   input       SPI_SS2,
   input       SPI_SS3,
   input       SPI_SS4,
   input       CONF_DATA0, 

	output 		VGA_HS,
   output 	 	VGA_VS,
   output [5:0] VGA_R,
   output [5:0] VGA_G,
   output [5:0] VGA_B
);

// de-activate unused SDRAM
assign SDRAM_nCS = 1;

// the configuration string is returned to the io controller to allow
// it to control the menu on the OSD 
parameter CONF_STR = {
        "VID_TEST;;",
        "O1,Scanlines,On,Off;",
        "O2,Video Mode,NTSC,PAL"
};

wire scanlines_ena = !status[1];
wire pal_ena       =  status[2];

parameter CONF_STR_LEN = 10+20+22;

// the status register is controlled by the on screen display (OSD)
wire scandoubler_disable;
wire ypbpr;
wire [7:0] status;

// include user_io module for arm controller communication
user_io #(.STRLEN(CONF_STR_LEN)) user_io ( 
      .conf_str   ( CONF_STR   ),
      .SPI_CLK    ( SPI_SCK    ),
      .SPI_SS_IO  ( CONF_DATA0 ),
      .SPI_MISO   ( SPI_DO     ),
      .SPI_MOSI   ( SPI_DI     ),
      .scandoubler_disable    ( scandoubler_disable ),
      .ypbpr      ( ypbpr      ),
      .status     ( status     )
);

wire [5:0] video_r, video_g, video_b;
wire video_hs, video_vs;

// include VGA controller
video video (
	.pclk  	 ( pixel_clock			),
	 
	.cpu_clk  ( pixel_clock      	),
	.cpu_wr   ( copy_in_progress 	),
	.cpu_addr ( addr - 14'd1     	),
	.cpu_data ( data             	),
	.pal      ( pal_ena           ),
	
	.hs       ( video_hs 			),
	.vs       ( video_vs 			),
	.r        ( video_r  			),
	.g        ( video_g  			),
	.b        ( video_b  			)
);

wire [5:0] sd_r, sd_g, sd_b;
wire sd_hs, sd_vs;

scandoubler scandoubler (
	.clk_in        ( pixel_clock   ),
	.clk_out       ( vga_clock     ),
   .scanlines     ( scanlines_ena ),
  
	// 
	.hs_in          ( video_hs     ),
	.vs_in          ( video_vs     ),
	.r_in           ( video_r      ),
	.g_in           ( video_g      ),
	.b_in           ( video_b      ),

	.hs_out         ( sd_hs        ),
	.vs_out         ( sd_vs        ),
	.r_out          ( sd_r         ),
	.g_out          ( sd_g         ),
	.b_out          ( sd_b         )
);

// In TV (15khz) mode the composite sync signal required by TVs is output on
// the VGA_HS output. The VGA_VS is driven to high and can be used e.g. to switch
// a scart tv into RGBS mode. See https://github.com/mist-devel/mist-board/wiki/ScartCable
assign VGA_HS = (scandoubler_disable || ypbpr)?!(video_hs^video_vs):sd_hs;
assign VGA_VS = (scandoubler_disable || ypbpr)?1'b1:sd_vs;
assign VGA_R  = ypbpr?pr:out_r;
assign VGA_G  = ypbpr? y:out_g;
assign VGA_B  = ypbpr?pb:out_b;

wire [5:0] y, pb, pr;

// include the rgb to ypbpr colorspace converter
rgb2ypbpr rgb2ypbpr (
	.red   ( out_r ),
	.green ( out_g ),
	.blue  ( out_b ),

	.y     ( y     ),
	.pb    ( pb    ),
	.pr    ( pr    )
);

wire [5:0] out_r, out_g, out_b;

// Make sure OSD scales horizontally to double size on TV as it also scales
// vertically since the scandoubler is disabled and thus only half the number of lines
// is being displayed making every line twice as high
wire osd_clk = scandoubler_disable?pixel_clock:vga_clock;

// Feed scnadoubled or normal signal into OSD
wire osd_hs = scandoubler_disable?video_hs:sd_hs;
wire osd_vs = scandoubler_disable?video_vs:sd_vs;
wire [5:0] osd_r = scandoubler_disable?video_r:sd_r;
wire [5:0] osd_g = scandoubler_disable?video_g:sd_g;
wire [5:0] osd_b = scandoubler_disable?video_b:sd_b;

// include the on screen display
osd #(10,0,4) osd (
   .pclk       ( osd_clk      ),

   // spi for OSD
   .sdi        ( SPI_DI       ),
   .sck        ( SPI_SCK      ),
   .ss         ( SPI_SS3      ),

   .red_in     ( osd_r        ),
   .green_in   ( osd_g        ),
   .blue_in    ( osd_b        ),
   .hs_in      ( osd_hs       ),
   .vs_in      ( osd_vs       ),

   .red_out    ( out_r        ),
   .green_out  ( out_g        ),
   .blue_out   ( out_b        )
);

// include ROM containing the demo image
image image (
	.clock   ( pixel_clock ),
	.address ( addr ),
	.q       ( data )
);

reg reset = 1'b1;
reg [13:0] addr;
wire [7:0] data;
reg copy_in_progress;

// A small state machine which copies image data from ROM into VRAM
// of the video controller. The state machines runs directly after power
// on and works on the falling clock edge since ROM and VRAM operate
// in the rising edge. The VRAM address is dereased by 1 since the ROM
// delivers it's data with one clock delay due to its internal registers.
always @(negedge pixel_clock) begin
	if(reset) begin
		reset <= 1'b0;
		addr <= 14'd0;
		copy_in_progress <= 1'b1;
	end else begin
		if(copy_in_progress) begin
			addr <= addr + 14'd1;
			if(addr == 15999)
				copy_in_progress <= 1'b0;
		end
	end
end
	
reg pixel_clock;
always @(posedge vga_clock)
	pixel_clock <= !pixel_clock;
	
// The pixel clock we use for our TV video modes is 13.5 Mhz. Thus the VGA pixel
// clock is exactly the 27 Mhz MIST board clock. No pll needed ...
wire vga_clock = CLOCK_27[0];

endmodule
