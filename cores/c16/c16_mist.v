//
// c16_mist.v - C16 for the MiST
//
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

module c16_mist (
   input  	 CLOCK_27,

	// LED outputs
   output 	 LED, // LED Yellow
	
   // SDRAM interface
   inout [15:0]  SDRAM_DQ, // SDRAM Data bus 16 Bits
   output [12:0] SDRAM_A, // SDRAM Address bus 13 Bits
   output 	 SDRAM_DQML, // SDRAM Low-byte Data Mask
   output 	 SDRAM_DQMH, // SDRAM High-byte Data Mask
   output 	 SDRAM_nWE, // SDRAM Write Enable
   output 	 SDRAM_nCAS, // SDRAM Column Address Strobe
   output 	 SDRAM_nRAS, // SDRAM Row Address Strobe
   output 	 SDRAM_nCS, // SDRAM Chip Select
   output [1:0]  SDRAM_BA, // SDRAM Bank Address
   output 	 SDRAM_CLK, // SDRAM Clock
   output 	 SDRAM_CKE, // SDRAM Clock Enable
  
   // SPI interface to arm io controller
   output 	 SPI_DO,
   input 	 SPI_DI,
   input 	 SPI_SCK,
   input 	 SPI_SS2,
   input 	 SPI_SS3,
   input 	 SPI_SS4,
   input 	 CONF_DATA0, 

   output 	 AUDIO_L, // sigma-delta DAC output left
   output 	 AUDIO_R, // sigma-delta DAC output right

   output 	 VGA_HS,
   output 	 VGA_VS,
   output [5:0]  VGA_R,
   output [5:0]  VGA_G,
   output [5:0]  VGA_B
);

// -------------------------------------------------------------------------
// ------------------------------ user_io ----------------------------------
// -------------------------------------------------------------------------

// user_io implements a connection to the io controller and receives various
// kind of user input from there (keyboard, buttons, mouse). It is also used
// by the fake SD card to exchange data with the real sd card connected to the
// io controller

// the configuration string is returned to the io controller to allow
// it to control the menu on the OSD 
parameter CONF_STR = {
        "C16;PRG;",
        "O2,Scanlines,Off,On;",
        "O3,Joysticks,Normal,Swapped;",
		  "O4,Memory,64k,16k;",
        "T5,Reset"
};

parameter CONF_STR_LEN = 8+20+28+18+8;

// the status register is controlled by the on screen display (OSD)
wire [7:0] status;
wire tv15khz;
wire scanlines = status[2];
wire joystick_swap = status[3];
wire memory_16k = status[4];
wire osd_reset = status[5];
wire [1:0] buttons;

wire [7:0] js0, js1;
wire [7:0] jsA = joystick_swap?js1:js0;
wire [7:0] jsB = joystick_swap?js0:js1;

wire ps2_kbd_clk, ps2_kbd_data;
wire ps2_mouse_clk, ps2_mouse_data;

// generate ps2_clock
wire ps2_clock = ps2_clk_div[10];  // ~12khz
reg [10:0] ps2_clk_div;
always @(posedge clk28)
	ps2_clk_div <= ps2_clk_div + 7'd1;

// -------------------------------------------------------------------------
// ---------------- interface to the external sdram ------------------------
// -------------------------------------------------------------------------

// SDRAM control signals
assign SDRAM_CKE = 1'b1;

// ram access signals from c16
wire [15:0] c16_sdram_addr = { c16_a_hi, c16_a_low };
wire [7:0] c16_sdram_data = c16_dout;
wire c16_sdram_wr = !c16_cas && !c16_rw;
wire c16_sdram_oe = !c16_cas &&  c16_rw;

// ram access signals from io controller
// ioctl_sdram_write
// ioctl_sdram_addr
// ioctl_sdram_data

// multiplex c16 and ioctl signals
wire [15:0] mux_sdram_addr = c16_wait?ioctl_sdram_addr:c16_sdram_addr;
wire [7:0] mux_sdram_data = c16_wait?ioctl_sdram_data:c16_sdram_data;
wire mux_sdram_wr = c16_wait?ioctl_sdram_write:c16_sdram_wr;
wire mux_sdram_oe = c16_wait?1'b0:c16_sdram_oe;

wire [15:0] sdram_din = { mux_sdram_data, mux_sdram_data };
wire [14:0] sdram_addr_64k = mux_sdram_addr[15:1];   // 64k mapping
wire [14:0] sdram_addr_16k = { 1'b0, mux_sdram_addr[13:7], 1'b0, mux_sdram_addr[6:1] };   // 16k
wire [24:0] sdram_addr = { 10'h00, memory_16k?sdram_addr_16k:sdram_addr_64k };

wire sdram_wr = mux_sdram_wr;
wire sdram_oe = mux_sdram_oe;
wire [1:0] sdram_ds = { mux_sdram_addr[0], !mux_sdram_addr[0] }; 

// only c16 reads from sdram
wire [15:0] sdram_dout;
wire [7:0] c16_din = zp_overwrite?zp_ovl_dout:
	(c16_a_low[0]?sdram_dout[15:8]:sdram_dout[7:0]);

assign SDRAM_CLK = ~clk28;

// synchronize sdram state machine with the ras/cas phases of the c16
reg last_ras;
reg [3:0] clkdiv;
wire clkref = clkdiv[3];
always @(posedge clk28) begin	
	if(!c16_ras && last_ras) begin
		clkdiv <= 4'd0;
		last_ras <= c16_ras;
	end else
		clkdiv <= clkdiv + 4'd1;
end	

// latch/demultiplex dram address
reg [7:0] c16_a_low;
always @(negedge c16_ras)
	c16_a_low <= c16_a;

reg [7:0] c16_a_hi;
always @(negedge c16_cas)
	c16_a_hi <= c16_a;

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
   .clk            ( clk28                     ),
   .clkref         ( clkref                    ),
   .init           ( !pll_locked               ),

   // cpu interface
   .din            ( sdram_din                 ),
   .addr           ( sdram_addr                ),
   .we             ( sdram_wr                  ),
   .oe             ( sdram_oe                  ),
   .ds             ( sdram_ds                  ),
   .dout           ( sdram_dout                )
);


// ---------------------------------------------------------------------------------
// -------------------------------------- reset ------------------------------------
// ---------------------------------------------------------------------------------

reg last_mem16k;
reg [31:0] reset_cnt;
wire reset = (reset_cnt != 0);
always @(posedge clk28) begin
	last_mem16k <= memory_16k;

	// long reset on startup and when io controller reboots
   if(status[0] || !pll_locked)
		reset_cnt <= 32'd28000000;
	// short reset on reset button, reset osd or when io controller is
	// done downloading or when memory mapping changes
	else if(buttons[1] || osd_reset || rom_download || (memory_16k != last_mem16k))
      reset_cnt <= 32'd65536;
   else if(reset_cnt != 0)
      reset_cnt <= reset_cnt - 32'd1;
end

// include user_io module for arm controller communication
user_io #(.STRLEN(CONF_STR_LEN)) user_io ( 
      .conf_str       ( CONF_STR       ),

      .SPI_CLK        ( SPI_SCK        ),
      .SPI_SS_IO      ( CONF_DATA0     ),
      .SPI_MISO       ( SPI_DO         ),
      .SPI_MOSI       ( SPI_DI         ),

		.scandoubler_disable ( tv15khz   ),
		.buttons        ( buttons        ),

		.joystick_0     ( js0            ),
		.joystick_1     ( js1            ),
		
      // ps2 interface
      .ps2_clk        ( ps2_clock      ),
      .ps2_kbd_clk    ( ps2_kbd_clk    ),
      .ps2_kbd_data   ( ps2_kbd_data   ),
      .ps2_mouse_clk  ( ps2_mouse_clk  ),
      .ps2_mouse_data ( ps2_mouse_data ),

      .status         ( status         )
);


// ---------------------------------------------------------------------------------
// ------------------------------ prg memory injection -----------------------------
// ---------------------------------------------------------------------------------

wire ioctl_wr;
wire [15:0] ioctl_addr;
wire [7:0] ioctl_data;
wire [4:0] ioctl_index;
wire ioctl_downloading;

wire rom_download = ioctl_downloading && (ioctl_index == 5'd0);
wire prg_download = ioctl_downloading && (ioctl_index == 5'd1);

// halt cpu when it's done with the current cycle
reg c16_wait;
always @(posedge c16_ras) 
	c16_wait <= prg_download;

data_io data_io (
      // SPI interface
      .sck ( SPI_SCK ),
      .ss  ( SPI_SS2 ),
      .sdi ( SPI_DI  ),
			
      // ram interface
		.downloading ( ioctl_downloading ),
      .index ( ioctl_index ),
      .clk   ( clk28 ),
      .wr    ( ioctl_wr ),
      .a     ( ioctl_addr ),
      .d     ( ioctl_data )
);

// magic zero page shadow registers to allow the injector to set the
// basic program end pointers automagically after injection
reg [15:0] reg_2d;
reg [15:0] reg_2f;
reg [15:0] reg_31;
reg [15:0] reg_ae;

wire zp_2d_sel = c16_sdram_addr == 16'h002d;
wire zp_2e_sel = c16_sdram_addr == 16'h002e;
wire zp_2f_sel = c16_sdram_addr == 16'h002f;
wire zp_30_sel = c16_sdram_addr == 16'h0030;
wire zp_31_sel = c16_sdram_addr == 16'h0031;
wire zp_32_sel = c16_sdram_addr == 16'h0032;
wire zp_ae_sel = c16_sdram_addr == 16'h00ae;
wire zp_af_sel = c16_sdram_addr == 16'h00af;

wire zp_overwrite = 
	zp_2d_sel || zp_2e_sel || zp_2f_sel || zp_30_sel ||
	zp_31_sel || zp_32_sel || zp_ae_sel || zp_af_sel;

reg zp_cas_delay, zp_sel;
reg zp_dl_delay, zp_dl;

always @(posedge clk28) begin
	// write pulse one cycle after falling edge of cas to make sure address
	// is stable
	zp_cas_delay <= c16_cas;
	zp_sel <= !c16_cas && zp_cas_delay;
	zp_dl_delay <= prg_download;
	zp_dl <= !prg_download && zp_dl_delay;

	if(zp_dl) begin
		// registers are automatically adjusted at the end of the
		// download/injection
		// the registers to be set have been taken from the vice emulator
		reg_2d <= ioctl_sdram_addr + 16'd1;
		reg_2f <= ioctl_sdram_addr + 16'd1;
		reg_31 <= ioctl_sdram_addr + 16'd1;
		reg_ae <= ioctl_sdram_addr + 16'd1;
	end else	if(zp_sel && !c16_rw) begin
		// cpu writes registers
		if(zp_2d_sel) reg_2d[ 7:0] <= c16_dout;
		if(zp_2e_sel) reg_2d[15:8] <= c16_dout;
		if(zp_2f_sel) reg_2f[ 7:0] <= c16_dout;
		if(zp_30_sel) reg_2f[15:8] <= c16_dout;
		if(zp_31_sel) reg_31[ 7:0] <= c16_dout;
		if(zp_32_sel) reg_31[15:8] <= c16_dout;
		if(zp_ae_sel) reg_ae[ 7:0] <= c16_dout;
		if(zp_af_sel) reg_ae[15:8] <= c16_dout;
	end
end
	
wire [7:0] zp_ovl_dout =
	zp_2d_sel?reg_2d[7:0]:zp_2e_sel?reg_2d[15:8]:
	zp_2f_sel?reg_2f[7:0]:zp_30_sel?reg_2f[15:8]:
	zp_31_sel?reg_31[7:0]:zp_32_sel?reg_31[15:8]:
	zp_ae_sel?reg_ae[7:0]:zp_af_sel?reg_ae[15:8]:
	8'hff;
	
// the address taken from the first to bytes of a prg file tell
// us where the file is to go in memory
reg [15:0] ioctl_load_addr /* synthesis noprune */;
reg 	   ioctl_ram_wr /* synthesis noprune */;
reg 	ioctl_sdram_write /* synthesis noprune */;
reg [15:0] ioctl_sdram_addr /* synthesis noprune */;
reg [7:0] ioctl_sdram_data /* synthesis noprune */;
  
always @(negedge c16_ras) begin
	ioctl_sdram_write <= ioctl_ram_wr;

	if(ioctl_ram_wr) begin
		ioctl_sdram_addr <= ioctl_load_addr + ioctl_addr - 16'd2;
		ioctl_sdram_data <= ioctl_data;
	end
end
		
// address starts counting with 0
always @(negedge clk28) begin
	if(ioctl_sdram_write) 
		ioctl_ram_wr <= 1'b0;

   // data io has a byte for us
   if(ioctl_wr) begin
      if(ioctl_addr == 16'h0000)
			ioctl_load_addr[7:0] <= ioctl_data;
      else if (ioctl_addr == 16'h0001) 
			ioctl_load_addr[15:8] <= ioctl_data;
      else 
			// io controller sent a new byte. Store it until it can be
			// saved in RAM
			ioctl_ram_wr <= 1'b1;
   end
end

	
// ---------------------------------------------------------------------------------
// ------------------------------ the on screen display ----------------------------
// ---------------------------------------------------------------------------------
	
// in 15khz mode feed the c16 video directly into the OSD,
// bypassing the scan doubler
wire [5:0] osd_r_in = tv15khz?{c16_r, 2'b00}:video_r;
wire [5:0] osd_g_in = tv15khz?{c16_g, 2'b00}:video_g;
wire [5:0] osd_b_in = tv15khz?{c16_b, 2'b00}:video_b;
wire osd_hs_in = tv15khz?!c16_hs:video_hs;
wire osd_vs_in = tv15khz?!c16_vs:video_vs;

wire osd_clk = tv15khz?clk7:clk28;

// include the on screen display
osd #(11,0,5) osd (
   .pclk       ( osd_clk     ),

   // spi for OSD
   .sdi        ( SPI_DI       ),
   .sck        ( SPI_SCK      ),
   .ss         ( SPI_SS3      ),

   .red_in     ( osd_r_in     ),
   .green_in   ( osd_g_in     ),
   .blue_in    ( osd_b_in     ),
   .hs_in      ( osd_hs_in    ),
   .vs_in      ( osd_vs_in    ),

   .red_out    ( VGA_R        ),
   .green_out  ( VGA_G        ),
   .blue_out   ( VGA_B        )
);

// in 15khz tv mode directly use the c16's composite sync. Otherwise the VGA
// output is driven from the sync signals generated by the scan doubler. In
// 15khz mode the VS signal is used as the RGB detect signal on the SCART 
// connector and thus needs to be driven to 1
assign VGA_HS = tv15khz?c16_cs:video_hs;
assign VGA_VS = tv15khz?1'b1:video_vs;

wire video_hs, video_vs;
wire [5:0] video_r;
wire [5:0] video_g;
wire [5:0] video_b;

scandoubler scandoubler (
	// system interface
	.clk_sys   ( clk28 ),

   // scanlines (00-none 01-25% 10-50% 11-75%)
   .scanlines ( scanlines?2'b10:2'b00 ),

   // shifter video interface
   .hs_in     ( !c16_hs ),
	.vs_in     ( !c16_vs ),
	.r_in      ( c16_r ),
	.g_in      ( c16_g ),
	.b_in      ( c16_b ),

    // output interface
	.hs_out    ( video_hs ),
   .vs_out    ( video_vs ),
   .r_out     ( video_r  ),
   .g_out     ( video_g  ),
   .b_out     ( video_b  )
);

// ---------------------------------------------------------------------------------
// ------------------------------------ c16 core -----------------------------------
// ---------------------------------------------------------------------------------

// c16 generated video signals
wire c16_hs, c16_vs, c16_cs;
wire [3:0] c16_r;
wire [3:0] c16_g;
wire [3:0] c16_b;
wire c16_pal;

// c16 generated ram access signals
wire c16_ras;
wire c16_cas;
wire c16_rw;
wire [7:0] c16_a;
wire [7:0] c16_dout;

reg kernal_dl_wr;
reg [7:0] kernal_dl_data;
reg [13:0] kernal_dl_addr;

wire ioctl_kernal_wr = rom_download && ioctl_wr;

reg last_ioctl_wr;
always @(negedge clk28) begin
	last_ioctl_wr <= ioctl_kernal_wr;
	if(ioctl_kernal_wr && !last_ioctl_wr) begin
		kernal_dl_data <= ioctl_data;
		kernal_dl_addr <= ioctl_addr[13:0];
		kernal_dl_wr <= 1'b1;
	end else
		kernal_dl_wr <= 1'b0;
end

// include the c16 itself
C16 c16 (
	.CLK28   ( clk28 ),
	.RESET   ( reset ),
	.WAIT    ( c16_wait ),
	.HSYNC   ( c16_hs ),
	.VSYNC   ( c16_vs ),
	.CSYNC   ( c16_cs ),
	.RED     ( c16_r ),
	.GREEN   ( c16_g ),
	.BLUE    ( c16_b ),
	
	.RAS     ( c16_ras ),
	.CAS     ( c16_cas ),
	.RW      ( c16_rw ),
	.A       ( c16_a ),
	.DOUT    ( c16_dout ),
	.DIN     ( c16_din ),

	.JOY0    ( jsB[4:0] ),
	.JOY1    ( jsA[4:0] ),
	
	.PS2DAT  ( ps2_kbd_data ),
	.PS2CLK  ( ps2_kbd_clk  ),

	.kernal_dl_addr  ( kernal_dl_addr ),
	.kernal_dl_data  ( kernal_dl_data ),
	.kernal_dl_write ( kernal_dl_wr),
	
/*	
	.IEC_DATAOUT ( c16_iec_data_o ),
	.IEC_DATAIN  ( c16_iec_data_i ),
	.IEC_CLKOUT  ( c16_iec_clk_o ),
	.IEC_CLKIN   ( c16_iec_clk_i ),
	.IEC_ATNOUT  ( c16_iec_atn_o ),
	// .IEC_ATNIN,
	.IEC_RESET   ( ),
*/
	.IEC_DATAIN  ( 1'b1 ),
	.IEC_CLKIN   ( 1'b1 ),
	
	.AUDIO_L     ( AUDIO_L ),
	.AUDIO_R     ( AUDIO_R ),

	.PAL         ( c16_pal ),
	
	.RS232_TX    (),
	.RGBS        ()
);


// ---------------------------------------------------------------------------------
// ------------------------------- clock generation --------------------------------
// ---------------------------------------------------------------------------------

// the FPGATED uses two different clocks for NTSC and PAL mode.
// Switching the clocks may crash the system. We might need to force a reset it.
wire clk28 = c16_pal?clk28_pal:clk28_ntsc;
wire pll_locked = pll_pal_locked && pll_ntsc_locked;
	
// tv15hkz has quarter the pixel rate, so we need a 7mhz clock for the OSD
reg clk7;
always @(posedge clk14)
	clk7 <= !clk7;

reg clk14;
always @(posedge clk28)
	clk14 <= !clk14;

// A PLL to derive the system clock from the MiSTs 27MHz
wire pll_pal_locked, clk28_pal;
pll_pal pll_pal (
	 .inclk0( CLOCK_27        ),
	 .c0(     clk28_pal       ),
	 .locked( pll_pal_locked  )
);

wire pll_ntsc_locked, clk28_ntsc;
pll_ntsc pll_ntsc (
	 .inclk0( CLOCK_27         ),
	 .c0(     clk28_ntsc       ),
	 .locked( pll_ntsc_locked  )
);



/*
// ---------------------------------------------------------------------------------
// ----------------------------------- floppy 1541 ---------------------------------
// ---------------------------------------------------------------------------------

wire [7:0] led_disk;
assign LED = !led_disk[6];

wire c16_iec_atn_o;
wire c16_iec_data_o;
wire c16_iec_clk_o;

wire c16_iec_atn_i  = !((!c16_iec_atn_o)  & (!c1541_iec_atn_o) );
wire c16_iec_data_i = !((!c16_iec_data_o) & (!c1541_iec_data_o));
wire c16_iec_clk_i  = !((!c16_iec_clk_o)  & (!c1541_iec_clk_o) );

wire c1541_iec_atn_o;
wire c1541_iec_data_o;
wire c1541_iec_clk_o;

wire c1541_iec_atn_i  = c16_iec_atn_i;
wire c1541_iec_data_i = c16_iec_data_i;
wire c1541_iec_clk_i  = c16_iec_clk_i;


c1541_sd c1541_sd (
	.clk32 ( clk32 ),
	.clk18 ( clk28 ),           // MiST uses virtual SPI SD, so any clock can be used.
	.reset ( reset ),

	.c1541rom_addr ( 14'h0000 ),
	.c1541rom_data ( 8'h00 ),
	.c1541rom_wr ( 1'b0 ),
	
   .disk_change (), 
   .disk_num ( 10'd0 ),        // not seletable by f8 or similar

	.iec_atn_i  ( c1541_iec_atn_i  ),
	.iec_data_i ( c1541_iec_data_i ),
	.iec_clk_i  ( c1541_iec_clk_i  ),

	.iec_atn_o  ( c1541_iec_atn_o  ),
	.iec_data_o ( c1541_iec_data_o ),
	.iec_clk_o  ( c1541_iec_clk_o  ),

   .sd_dat ( 1'b1 ),
   .sd_dat3 (),
   .sd_cmd (),
   .sd_clk (),

   .led ( led_disk )
);
*/

endmodule
