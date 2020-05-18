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
  output         SPI_DO,
  input          SPI_DI,
  input          SPI_SCK,
  input          SPI_SS2,    // data_io
  input          SPI_SS3,    // OSD
  input          CONF_DATA0  // SPI_SS for user_io
);

assign LED = 1'b0;

// the configuration string is returned to the io controller to allow
// it to control the menu on the OSD 
parameter CONF_STR = {
        "BBC;ROM;",
        "O12,Scanlines,Off,25%,50%,75%;",
				"O3,Joystick Swap,Off,On;",
        "O4,ROM mapping,High,Low;",
        "O5,Auto boot,Off,On;",
        "T0,Reset;"
};

wire [1:0] scanlines = status[2:1];
wire       joyswap = status[3];
wire       rommap = status[4];
wire       autoboot = status[5];

// generated clocks
wire clk_32m /* synthesis keep */ ;
wire clk_24m /* synthesis keep */ ;

wire pll_ready;

// core's raw video 
wire 			core_r, core_g, core_b, core_hs, core_vs;   
wire			core_clken;

// memory bus signals.
wire [15:0] mem_adr;
wire [3:0]  mem_romsel;

wire [7:0]  mem_di;
wire [7:0]  rom_do;
wire [7:0]  ram_do;

wire [7:0]  mem_do;
wire        mem_we;
wire        mem_sync;
wire        phi0;

// core's raw audio 
wire [15:0]	coreaud_l, coreaud_r;

// user io
wire [7:0] status;
wire [1:0] buttons;
wire [1:0] switches;

wire        ps2_clk;
wire        ps2_dat;

// the top file should generate the correct clocks for the machine

assign SDRAM_CLK = clk_32m;

clockgen CLOCKS(
	.inclk0	(CLOCK_27[0]),
	.c0		(clk_32m),
	.c1 		(clk_24m),
	.locked	(pll_ready)  // pll locked output
);

// conections between user_io (implementing the SPI communication 
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
wire [8:0] sd_buff_addr;
wire sd_ack_conf;
wire img_mounted;
wire [31:0] img_size;

wire [7:0] joystick_0;
wire [7:0] joystick_1;
wire [15:0] joystick_analog_0;
wire [15:0] joystick_analog_1;

wire scandoubler_disable;
wire ypbpr;
wire no_csync;

user_io #(.STRLEN($size(CONF_STR)>>3)) user_io(
	.conf_str      ( CONF_STR       ),
	.clk_sys       ( clk_32m        ),
	.clk_sd        ( clk_32m        ),

	// the spi interface
	.SPI_CLK        ( SPI_SCK       ),
	.SPI_SS_IO      ( CONF_DATA0    ),
	.SPI_MISO       ( SPI_DO        ),   // tristate handling inside user_io
	.SPI_MOSI       ( SPI_DI        ),
	
	.joystick_0        ( joystick_0 ),
	.joystick_1        ( joystick_1 ),
	.joystick_analog_0 ( joystick_analog_0 ),
	.joystick_analog_1 ( joystick_analog_1 ),

	.status         ( status        ),
	.switches       ( switches      ),
	.buttons        ( buttons       ),
	.scandoubler_disable ( scandoubler_disable ),
	.ypbpr          ( ypbpr         ),
	.no_csync       ( no_csync      ),

   // interface to embedded legacy sd card wrapper
	.sd_lba     	  ( sd_lba        ),
	.sd_rd      	  ( sd_rd         ),
	.sd_wr      	  ( sd_wr         ),
	.sd_ack     	  ( sd_ack        ),
	.sd_conf    	  ( sd_conf       ),
	.sd_sdhc    	  ( sd_sdhc       ),
	.sd_dout    	  ( sd_dout       ),
	.sd_dout_strobe ( sd_dout_strobe),
	.sd_din     	  ( sd_din        ),
	.sd_din_strobe  ( sd_din_strobe ),
	.sd_buff_addr   ( sd_buff_addr  ),
	.sd_ack_conf    ( sd_ack_conf   ),

	.img_mounted    ( img_mounted   ),
	.img_size       ( img_size      ),

	.ps2_kbd_clk	  ( ps2_clk       ), 
	.ps2_kbd_data	  ( ps2_dat       )
);

// wire the sd card to the user port
wire sd_sck;
wire sd_cs;
wire sd_sdi;
wire sd_sdo;

sd_card sd_card (
	// connection to io controller
	.clk_sys(clk_32m),
	.sd_lba (sd_lba ),
	.sd_rd  (sd_rd),
	.sd_wr  (sd_wr),
	.sd_ack (sd_ack),
	.sd_ack_conf (sd_ack_conf      ),
	.sd_conf (sd_conf),
	.sd_sdhc (sd_sdhc),
	.sd_buff_dout (sd_dout),
	.sd_buff_wr (sd_dout_strobe),
	.sd_buff_din (sd_din),
	.sd_buff_addr  (sd_buff_addr     ),
	.img_mounted (img_mounted),
	.img_size (img_size),
	.allow_sdhc ( 1'b1),
 
	// connection to local CPU
	.sd_cs   ( sd_cs          ),
	.sd_sck  ( sd_sck         ),
	.sd_sdi  ( sd_sdi         ),
	.sd_sdo  ( sd_sdo         )
);

// data loading 
wire        loader_active;
wire        loader_we, ioctl_we;
wire [24:0]	loader_addr, ioctl_addr;
wire  [7:0] loader_data, ioctl_data;

always @(posedge clk_32m) begin
	reg we_int = 0;

	if (mem_sync) begin
		we_int <= 0;
		loader_we <= we_int;
		if (we_int) begin
			loader_addr <= ioctl_addr;
			loader_data <= ioctl_data;
		end
	end

	if (ioctl_we) we_int <= 1;
end

data_io #(.START_ADDR({ 7'b0000001, 4'ha, 14'h0 })) DATA_IO  (
	.clk_sys    ( clk_32m ),
	.SPI_SCK    ( SPI_SCK ),
	.SPI_SS2    ( SPI_SS2 ),
	.SPI_DI     ( SPI_DI  ),

	.ioctl_download ( loader_active ),

   // ram interface
	.ioctl_wr   ( ioctl_we     ),
	.ioctl_addr ( ioctl_addr   ),
	.ioctl_dout ( ioctl_data   )
);

wire [7:0] user_via_pb_out;
wire user_via_cb1_in;
wire user_via_cb2_in;

// reset core whenever the user changes the rom mapping
reg last_rom_map;
reg [11:0] rom_map_counter = 12'h0;
always @(posedge clk_32m) begin
	last_rom_map <= rommap;

	if(last_rom_map != rommap)
		rom_map_counter <= 12'hfff;
	else if(rom_map_counter != 0)
		rom_map_counter <= rom_map_counter - 12'd1;
end

wire rom_remap_reset = (rom_map_counter != 0);

// the bbc is being reset of the pll isn't stable, if the ram isn't ready,
// of the arm boots or if the user selects reset from the osd or of the user
// presses the "core" button or the io controller uploads a rom
wire reset_in = ~pll_ready || ~sdram_ready || status[0] ||
		buttons[1] || loader_active || rom_remap_reset;

// synchronize reset with memory state machine
reg reset;
always @(posedge clk_32m)
	if (mem_sync) reset <= reset_in;

// the autoboot feature simply works by pressing shift for 2 seconds after 
// the bbc has been reset
wire autoboot_shift = autoboot && (autoboot_counter != 0 );
reg [24:0] autoboot_counter;
always @(posedge clk_32m) begin
	if(reset) 
		autoboot_counter <= 25'd32000000;
	else if(autoboot_counter != 0)
		autoboot_counter <= autoboot_counter - 25'd1;
end

bbc BBC(

	.CLK32M_I   ( clk_32m       ),
	.CLK24M_I   ( clk_24m       ),
	.RESET_I    ( reset         ),

	.HSYNC      ( core_hs       ),
	.VSYNC      ( core_vs       ),

	.VIDEO_CLKEN( core_clken    ),

	.VIDEO_R    ( core_r        ),
	.VIDEO_G    ( core_g        ),
	.VIDEO_B    ( core_b        ),
	.VIDEO_DE   ( video_de      ),

	.MEM_ADR    ( mem_adr       ),
	.MEM_WE     ( mem_we        ),
	.MEM_DO     ( mem_do        ),
	.MEM_DI     ( mem_di        ),
	.MEM_SYNC   ( mem_sync      ),
	.ROMSEL     ( mem_romsel    ),
	.PHI0       ( phi0          ),

	.SHIFT      ( autoboot_shift ),

	.SDCLK      (sd_sck         ),
	.SDSS       (sd_cs          ),
	.SDMISO     (sd_sdo         ),
	.SDMOSI     (sd_sdi         ),

	.joy_but    ( { joystick_1[4], joystick_0[4] } ),
	.joy0_axis0 ( joyswap ? joystick_analog_1[15:8] : joystick_analog_0[15:8] ),
	.joy0_axis1 ( joyswap ? joystick_analog_1[ 7:0] : joystick_analog_0[ 7:0] ),
	.joy1_axis0 ( joyswap ? joystick_analog_0[15:8] : joystick_analog_1[15:8] ),
	.joy1_axis1 ( joyswap ? joystick_analog_0[15:8] : joystick_analog_1[ 7:0] ),

	.DIP_SWITCH ( 8'b00000000 ),

	.PS2_CLK	( ps2_clk       ),
	.PS2_DAT	( ps2_dat       ),

	.AUDIO_L	( coreaud_l     ),
	.AUDIO_R	( coreaud_r     )
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

wire sdram_we = loader_active?loader_we:(mem_we && (cpu_ram || sideways_ram));
	
wire [7:0] sdram_di = 
	loader_active?loader_data:mem_do;

wire video_de;

sdram sdram (
	// interface to the MT48LC16M16 chip
	.sd_data        ( SDRAM_DQ                 ),
	.sd_addr        ( SDRAM_A                  ),
	.sd_dqm         ( {SDRAM_DQMH, SDRAM_DQML} ),
	.sd_cs          ( SDRAM_nCS                ),
	.sd_ba          ( SDRAM_BA                 ),
	.sd_we          ( SDRAM_nWE                ),
	.sd_ras         ( SDRAM_nRAS               ),
	.sd_cas         ( SDRAM_nCAS               ),

	// system interface
	.clk            ( clk_32m                  ),
	.sync           ( mem_sync                 ),
	.init           ( !pll_ready               ),
	.ready          ( sdram_ready              ),

	// cpu/video interface
	.cpu_di         ( sdram_di                 ),
	.cpu_adr        ( sdram_adr                ),
	.cpu_we         ( sdram_we                 ),
	.cpu_do         ( ram_do                   ),

	.vid_blnk       ( !video_de                ) // for refresh
);

wire [7:0] os_do;
os12 os12 (
	.clock   ( clk_32m       ),
	.address ( mem_adr[13:0] ),
	.q       ( os_do         )
);

wire [7:0] basic_do;
basic2 basic2 (
	.clock   ( clk_32m       ),
	.address ( mem_adr[13:0] ),
	.q       ( basic_do      )
);

wire [7:0] mmfs_do;
mmfs mmfs (
	.clock   ( clk_32m			 ),
	.address ( mem_adr[13:0] ),
	.q       ( mmfs_do       )
);

// map 64k sideways ram to bank 4,5,6 and 7
wire sideways_ram = 
	(mem_adr[15:14] == 2'b10) && (mem_romsel[3:2] == 2'b01);

// rommap is '1' of low mapping is selected in the menu
wire basic_map = rommap?(mem_romsel == 4'h0):(mem_romsel == 4'he);
wire mmfs_map = rommap?(mem_romsel == 4'h2):(mem_romsel == 4'hc);

assign mem_di = 
	~phi0 ? ram_do :
	((mem_adr[15:14] == 2'b10) && basic_map) ? basic_do : 
	((mem_adr[15:14] == 2'b10) && mmfs_map) ? mmfs_do :
	((mem_adr[15:14] == 2'b10) && (mem_romsel == 4'ha)) ? ram_do :
	mos_rom ? os_do : 
	cpu_ram ? ram_do :
	sideways_ram ? ram_do :
	8'hff;

audio	AUDIO	(
	.clk         ( clk_24m    ),
	.rst         ( ~pll_ready ),
	.audio_data_l( coreaud_l  ),
	.audio_data_r( coreaud_r  ),
	.audio_l     ( AUDIO_L    ),
	.audio_r     ( AUDIO_R    )
);

mist_video #(.COLOR_DEPTH(1), .SD_HCNT_WIDTH(10)) mist_video (
	.clk_sys     ( clk_32m    ),

	// OSD SPI interface
	.SPI_SCK     ( SPI_SCK    ),
	.SPI_SS3     ( SPI_SS3    ),
	.SPI_DI      ( SPI_DI     ),

	// scanlines (00-none 01-25% 10-50% 11-75%)
	.scanlines   ( scanlines  ),

	// non-scandoubled pixel clock divider 0 - clk_sys/4, 1 - clk_sys/2
	.ce_divider  ( 1'b0       ),

	// 0 = HVSync 31KHz, 1 = CSync 15KHz
	.scandoubler_disable ( scandoubler_disable ),
	// disable csync without scandoubler
	.no_csync    ( no_csync   ),
	// YPbPr always uses composite sync
	.ypbpr       ( ypbpr      ),
	// Rotate OSD [0] - rotate [1] - left or right
	.rotate      ( 2'b00      ),
	// composite-like blending
	.blend       ( 1'b0       ),

	// video in
	.R           ( core_r     ),
	.G           ( core_g     ),
	.B           ( core_b     ),

	.HSync       ( core_hs    ),
	.VSync       ( core_vs    ),

	// MiST video output signals
	.VGA_R       ( VGA_R      ),
	.VGA_G       ( VGA_G      ),
	.VGA_B       ( VGA_B      ),
	.VGA_VS      ( VGA_VS     ),
	.VGA_HS      ( VGA_HS     )
);

endmodule // bbc_mist_top
