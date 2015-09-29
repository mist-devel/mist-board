`timescale 1ns / 1ps
// bbc_mist_top.v
module bbc_mist_top(

  // clock inputs
  input wire [1:0] 	CLOCK_27, // 27 MHz
  
  // LED outputs
  output wire	LED, // LED Yellow
  
  // VGA
  output wire	VGA_HS, // VGA H_SYNC
  output wire	VGA_VS, // VGA V_SYNC
  output wire [5:0] 	VGA_R, // VGA Red[5:0]
  output wire [5:0] 	VGA_G, // VGA Green[5:0]
  output wire [5:0] 	VGA_B, // VGA Blue[5:0];
	
	// AUDIO
	output wire 		AUDIO_L, // sigma-delta DAC output left
	output wire 		AUDIO_R, // sigma-delta DAC output right
	
	// SDRAM
   inout [15:0]    SDRAM_DQ,       // SDRAM Data bus 16 Bits
   output [12:0]   SDRAM_A,        // SDRAM Address bus 13 Bits
   output          SDRAM_DQML,     // SDRAM Low-byte Data Mask
   output          SDRAM_DQMH,     // SDRAM High-byte Data Mask
   output          SDRAM_nWE,      // SDRAM Write Enable
   output          SDRAM_nCAS,     // SDRAM Column Address Strobe
   output          SDRAM_nRAS,     // SDRAM Row Address Strobe
   output          SDRAM_nCS,      // SDRAM Chip Select
   output [1:0]    SDRAM_BA,       // SDRAM Bank Address
   output          SDRAM_CLK,      // SDRAM Clock
   output          SDRAM_CKE,      // SDRAM Clock Enable
	
  
  // SPI
  inout          SPI_DO,
  input          SPI_DI,
  input          SPI_SCK,
  input          SPI_SS2,    // data_io
  input          SPI_SS3,    // OSD
  input          CONF_DATA0  // SPI_SS for user_io
);

// the configuration string is returned to the io controller to allow
// it to control the menu on the OSD 
parameter CONF_STR = {
        "BBC;ROM;",
        "T1,Reset;"
};

parameter CONF_STR_LEN = 8+9;

// generated clocks
wire clk_32m /* synthesis keep */ ;
wire clk_24m /* synthesis keep */ ;

wire pll_ready;

// core's raw video 
wire 			core_r, core_g, core_b, core_hs, core_vs;   
wire			core_clken;

// memory bus signals.
wire [14:0] vid_adr;
wire [7:0]  vid_data;

wire [15:0] mem_adr;
assign LED = (mem_romsel == 0) || (loader_addr == 0) || (loader_data == 0) || loader_we;
wire [3:0]  mem_romsel /* synthesis keep */;

wire [7:0]  mem_di;
wire [7:0]  rom_do;
wire [7:0]  ram_do;

wire [7:0]  mem_do;
wire        mem_we;
wire        mem_sync;

// mist's doubled video 
wire 			video_r, video_g, video_b, video_hs, video_vs;

// core's raw audio 
wire [15:0]	coreaud_l, coreaud_r;

// user io
wire [7:0] status;
wire [1:0] buttons;
wire [1:0] switches;

wire        ps2_clk;
wire        ps2_dat;

// ~14khz clock generation
reg [10:0]  clk_14k_div;
wire        clk_14k = clk_14k_div[10] /* synthesis keep */; 

// the top file should generate the correct clocks for the machine

assign SDRAM_CLK = !clk_32m;

clockgen CLOCKS(
	.inclk0	(CLOCK_27[0]),
	.c0		(clk_32m),
	.c1 		(clk_24m),
//	.c2		(SDRAM_CLK), 	
	.locked	(pll_ready)  // pll locked output
);

osd #(0,100,4) OSD (
   .pclk       ( clk_24m          ),

   // spi for OSD
   .sdi        ( SPI_DI       ),
   .sck        ( SPI_SCK      ),
   .ss         ( SPI_SS3      ),

   .red_in     ( video_r      ),
   .green_in   ( video_g      ),
   .blue_in    ( video_b      ),
	
   .hs_in      ( video_hs      ),
   .vs_in      ( video_vs      ),

   .red_out    ( VGA_R        ),
   .green_out  ( VGA_G        ),
   .blue_out   ( VGA_B        ),
   .hs_out     ( VGA_HS       ),
   .vs_out     ( VGA_VS       )
);

// conections between user_io (implementing the SPIU communication 
// to the io controller) and the legacy 
wire [31:0] sd_lba;
wire sd_rd;
wire sd_wr;
wire sd_ack;
wire sd_conf;
wire sd_sdhc; 
wire [7:0] sd_dout;
wire sd_dout_strobe;
wire [7:0] sd_din;
wire sd_din_strobe;

user_io #(.STRLEN(CONF_STR_LEN)) user_io(
   .conf_str      ( CONF_STR        ),
   // the spi interface

   .SPI_CLK     	(SPI_SCK          ),
   .SPI_SS_IO     (CONF_DATA0       ),
   .SPI_MISO      (SPI_DO           ),   // tristate handling inside user_io
   .SPI_MOSI      (SPI_DI           ),
	
   .status        (status           ),
	.switches      (switches         ),
   .buttons       (buttons          ),
	
   // interface to embedded legacy sd card wrapper
   .sd_lba     	( sd_lba				),
   .sd_rd      	( sd_rd				),
   .sd_wr      	( sd_wr				),
   .sd_ack     	( sd_ack				),
   .sd_conf    	( sd_conf			),
   .sd_sdhc    	( sd_sdhc			),
   .sd_dout    	( sd_dout			),
   .sd_dout_strobe(sd_dout_strobe	),
   .sd_din     	( sd_din				),
   .sd_din_strobe (sd_din_strobe		),

	.ps2_clk 		( clk_14k			), 
	.ps2_kbd_clk	( ps2_clk			), 
	.ps2_kbd_data	( ps2_dat			)
);

// wire the sd card to the user port
wire sd_sck = user_via_pb_out[1];
wire sd_cs = 1'b0;
wire sd_sdi = user_via_pb_out[0];
wire sd_sdo = user_via_cb2_in;
assign user_via_cb1_in = user_via_pb_out[1];

sd_card sd_card (
        // connection to io controller
   .io_lba (sd_lba ),
   .io_rd  (sd_rd),
   .io_wr  (sd_wr),
   .io_ack (sd_ack),
   .io_conf (sd_conf),
   .io_sdhc (sd_sdhc),
   .io_din (sd_dout),
   .io_din_strobe (sd_dout_strobe),
   .io_dout (sd_din),
   .io_dout_strobe ( sd_din_strobe),
 
   .allow_sdhc ( 1'b0),   // SDHC not supported

   // connection to local CPU
   .sd_cs   ( sd_cs          ),
   .sd_sck  ( sd_sck         ),
   .sd_sdi  ( sd_sdi         ),
   .sd_sdo  ( sd_sdo         )
);

// data loading 
wire 			loader_active 	/* synthesis keep */ ;
wire 			loader_we 		/* synthesis keep */ ;
wire [24:0]	loader_addr 	/* synthesis keep */ ;
wire [7:0]	loader_data 	/* synthesis keep */ ;

// http://beebwiki.mdfs.net/index.php/Paged_ROM
	 
data_io DATA_IO  (
	.sck				( SPI_SCK 			),
	.ss				( SPI_SS2			),
	.sdi				( SPI_DI				),

	.downloading	( loader_active	),
	.index			(						),
	
   // ram interface
   .clk     		( mem_sync			),
	.wr    			( loader_we			),
	.addr				( loader_addr		),
	.data				( loader_data 		)
);

wire [7:0] user_via_pb_out;
wire user_via_cb1_in;
wire user_via_cb2_in;

// the bbc is being reset of the pll isn't stable, if the ram isn't ready,
// of the arm boots or if the user selects reset from the osd or of the user
// presses the "core" button or the io controller uploads a rom
wire reset = ~pll_ready || ~sdram_ready || status[0] || status[1] ||
		buttons[1] || loader_active;

bbc BBC(
	
	.CLK32M_I	( clk_32m		),
	.CLK24M_I	( clk_24m		),
	.RESET_I	   ( reset        ),
	
	.HSYNC		( core_hs		),
	.VSYNC		( core_vs		),
	
	.VIDEO_CLKEN ( core_clken	),
	
    .VIDEO_R	( core_r		),
	.VIDEO_G	( core_g		),
	.VIDEO_B	( core_b		),
    
    .MEM_ADR    ( mem_adr       ),
    .MEM_WE     ( mem_we        ),
    .MEM_DO     ( mem_do        ),
    .MEM_DI     ( mem_di        ),
	 .MEM_SYNC   ( mem_sync      ),
	 .ROMSEL     ( mem_romsel    ),
    
    .VID_ADR    ( vid_adr       ),
    .VID_DI     ( vid_data      ),
	
	 .user_via_pb_out ( user_via_pb_out   ),
	 .user_via_cb1_in ( user_via_cb1_in   ),
	 .user_via_cb2_in ( user_via_cb2_in   ),

	
	.PS2_CLK	( ps2_clk 		),
	.PS2_DAT	( ps2_dat		),
	
	.AUDIO_L	( coreaud_l		),
	.AUDIO_R	( coreaud_r		)
	
);

assign SDRAM_CKE = 1'b1;
wire sdram_ready;

// cpu is accessing built-in core rom (mos or basic)
wire cpu_ram = (mem_adr[15] == 1'b0);
wire mos_rom = (mem_adr[15:14] == 2'b11);

wire [24:0] sdram_adr =
	loader_active?loader_addr:
	cpu_ram?{ 9'b000000000, mem_adr }:          // ordinary ram access
	{ 7'b0000001, mem_romsel, mem_adr[13:0] };  // sideways ram/rom access

wire sdram_we = 
	loader_active?loader_we:(mem_we && cpu_ram);
	
wire [7:0] sdram_di = 
	loader_active?loader_data:mem_do;

sdram sdram (
   // interface to the MT48LC16M16 chip
   .sd_data        ( SDRAM_DQ                  ),
   .sd_addr        ( SDRAM_A                   ),
   .sd_dqm         ( {SDRAM_DQMH, SDRAM_DQML}  ),
   .sd_cs          ( SDRAM_nCS                 ),
   .sd_ba          ( SDRAM_BA                  ),
   .sd_we          ( SDRAM_nWE                 ),
   .sd_ras         ( SDRAM_nRAS                ),
   .sd_cas         ( SDRAM_nCAS                ),

   // system interface
   .clk            ( clk_32m                   ),
   .sync           ( mem_sync                  ),
   .init           ( !pll_ready                ),
	.ready          ( sdram_ready               ),

   // cpu/video interface
   .cpu_di         ( sdram_di                ),
   .cpu_adr        ( sdram_adr               ),
   .cpu_we         ( sdram_we 					),
   .cpu_do         ( ram_do                  ),

	.vid_blnk       ( loader_active           ),
   .vid_adr        ( { 9'd0, vid_adr }       ),
   .vid_do         ( vid_data                )
);

wire [7:0] os_do;
os12 os12 (
	.clock 	( clk_32m			),
   .address	( mem_adr[13:0]	),
   .q			( os_do				)
);

wire [7:0] basic_do;
basic2 basic2 (
	.clock 	( clk_32m			),
   .address	( mem_adr[13:0]	),
   .q			( basic_do			)
);

wire [7:0] dfs_do;
dfs09 dfs09 (
	.clock 	( clk_32m			),
   .address	( mem_adr[12:0]	),
   .q			( dfs_do			   )
);

wire [7:0] smmc_do;
smmc smmc (
	.clock 	( clk_32m			),
   .address	( mem_adr[13:0]	),
   .q			( smmc_do		   )
);

audio	AUDIO	(
	.clk				( clk_24m		),
	.rst				( ~pll_ready	),
	.audio_data_l 	( coreaud_l		),
	.audio_data_r 	( coreaud_r		),
	.audio_l       ( AUDIO_L		),
	.audio_r			( AUDIO_R		)
);

scandoubler SCANDOUBLE(

	.clk_16		( clk_32m		),
	.clk_16_en	( core_clken	),
	
	.vs_in		( core_vs		),
	.hs_in		( core_hs		),
	
	.r_in			( core_r			),
	.g_in			( core_g			),
	.b_in			( core_b			),
	
	.clk			( clk_32m		),
	
	.vs_out		( video_vs		),
	.hs_out		( video_hs		),
	
	.r_out		( video_r		),
	.g_out		( video_g		),
	.b_out		( video_b		)
);

always @(posedge clk_32m) begin 
	clk_14k_div <= clk_14k_div + 'd1;
end

assign mem_di = 
	(mem_adr[15:14] == 2'b10) && (mem_romsel == 4'hf) ? basic_do : 
//	((mem_adr[15:14] == 2'b10) && (mem_romsel == 4'he)) ? dfs_do :
	((mem_adr[15:14] == 2'b10) && (mem_romsel == 4'he)) ? smmc_do :
	((mem_adr[15:14] == 2'b10) && (mem_romsel == 4'hd)) ? ram_do :
	mos_rom ? os_do : 
	cpu_ram ? ram_do :
	8'hff;

endmodule // bbc_mist_top
