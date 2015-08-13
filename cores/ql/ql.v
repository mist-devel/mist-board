//
// ql.v - Sinclair QL for the MiST
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

module ql (
   input [1:0] CLOCK_27,

	// LED outputs
   output          LED,            // LED Yellow
	
   // SDRAM interface
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
  
   // SPI interface to arm io controller
   output      SPI_DO,
   input       SPI_DI,
   input       SPI_SCK,
   input       SPI_SS2,
   input       SPI_SS3,
   input       SPI_SS4,
   input       CONF_DATA0, 

	output 		AUDIO_L, // sigma-delta DAC output left
	output 		AUDIO_R, // sigma-delta DAC output right

   output VGA_HS,
   output VGA_VS,
   output [5:0] VGA_R,
   output [5:0] VGA_G,
   output [5:0] VGA_B
);

// the configuration string is returned to the io controller to allow
// it to control the menu on the OSD 
parameter CONF_STR = {
        "QL;;",
        "F1,MDV;",
        "O2,RAM,128k,640k;",
        "O3,Video mode,PAL,NTSC;",
        "O4,Scanlines,Off,On;",
        "T5,Reset"
};

parameter CONF_STR_LEN = 4+7+17+23+20+8;

// the status register is controlled by the on screen display (OSD)
wire [7:0] status;
wire tv15khz;
wire [1:0] buttons;

wire ps2_kbd_clk, ps2_kbd_data;

// generate ps2_clock
wire ps2_clock = ps2_clk_div[6];  // ~20khz
reg [6:0] ps2_clk_div;
always @(posedge clk2)
	ps2_clk_div <= ps2_clk_div + 7'd1;

// include user_io module for arm controller communication
user_io #(.STRLEN(CONF_STR_LEN)) user_io ( 
      .conf_str       ( CONF_STR       ),

      .SPI_CLK        ( SPI_SCK        ),
      .SPI_SS_IO      ( CONF_DATA0     ),
      .SPI_MISO       ( SPI_DO         ),
      .SPI_MOSI       ( SPI_DI         ),

		.scandoubler_disable ( tv15khz   ),
		.buttons        ( buttons        ),
		
      // ps2 interface
      .ps2_clk        ( ps2_clock      ),
      .ps2_kbd_clk    ( ps2_kbd_clk    ),
      .ps2_kbd_data   ( ps2_kbd_data   ),

      .status         ( status         )
);

// csync for tv15khz
// QLs vsync is positive, QLs hsync is negative
wire vga_csync = !(!vga_hsync ^ vga_vsync);
wire vga_hsync, vga_vsync;

// TV SCART has csync on hsync pin and "high" on vsync pin
assign VGA_VS = tv15khz?1'b1:vga_vsync;
assign VGA_HS = tv15khz?vga_csync:vga_hsync;

// tv15hkz has half the pixel rate		  
wire osd_clk = tv15khz?clk10:clk21;

// include the on screen display
osd #(12,0,5) osd (
   .pclk       ( osd_clk     ),

   // spi for OSD
   .sdi        ( SPI_DI       ),
   .sck        ( SPI_SCK      ),
   .ss         ( SPI_SS3      ),

   .red_in     ( video_r      ),
   .green_in   ( video_g      ),
   .blue_in    ( video_b      ),
   .hs_in      ( video_hs     ),
   .vs_in      ( video_vs     ),

   .red_out    ( VGA_R        ),
   .green_out  ( VGA_G        ),
   .blue_out   ( VGA_B        ),
   .hs_out     ( vga_hsync    ),
   .vs_out     ( vga_vsync    )
);

// SDRAM control signals
assign SDRAM_CKE = 1'b1;


// CPU and data_io share the same bus cycle. Thus the CPU cannot run while
// (ROM) data is being downloaded which wouldn't make any sense, anyway
// during ROM download data_io writes the ram. Otherwise the CPU
wire [24:0] sys_addr = dio_download?dio_addr[24:0]:{ 6'b000000, cpu_addr[19:1]};
wire [1:0] sys_ds =    dio_download?2'b11:~cpu_ds;
wire [15:0] sys_dout = dio_download?dio_data:cpu_dout;
wire sys_wr =          dio_download?dio_write:(cpu_wr && cpu_ram);
wire sys_oe =          dio_download?1'b0:(cpu_rd && cpu_mem);

// microdrive emulation and video share the video cycle time slot
wire [24:0] video_cycle_addr = mdv_read?mdv_addr:{6'd0, video_addr};
wire video_cycle_rd = mdv_read?1'b1:video_rd;

// video and CPU/data_io time share the sdram bus
wire [24:0] sdram_addr = video_cycle?video_cycle_addr:sys_addr;
wire sdram_wr = video_cycle?1'b0:sys_wr;
wire sdram_oe = video_cycle?video_cycle_rd:sys_oe;
wire [1:0] sdram_ds = video_cycle?2'b11:sys_ds;
wire [15:0] sdram_dout;
wire [15:0] sdram_din = sys_dout;

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
   .clk            ( clk21                    ),
   .clkref         ( clk2                  ),
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
// ------------------------------------- data io -----------------------------------
// ---------------------------------------------------------------------------------

wire dio_download;
wire [4:0] dio_index;
wire [24:0] dio_addr;
wire [15:0] dio_data;
wire dio_write;

// include ROM download helper
// this receives a byte stream from the arm io controller via spi and 
// writes it into sdram
data_io data_io (
   // io controller spi interface
   .sck ( SPI_SCK ),
   .ss  ( SPI_SS2 ),
   .sdi ( SPI_DI  ),

   .downloading ( dio_download ),  // signal indicating an active rom download
	.index       ( dio_index ),
  
   // external ram interface
   .clk   ( cpu_cycle ),
   .wr    ( dio_write ),
   .addr  ( dio_addr  ),
   .data  ( dio_data  )
);
                   
// ---------------------------------------------------------------------------------
// -------------------------------------- video ------------------------------------
// ---------------------------------------------------------------------------------

wire [5:0] video_r, video_g, video_b;
wire video_hs, video_vs;

wire [18:0] video_addr;
wire video_rd;

// the zx8301 has only one write-only register at $18063
wire zx8301_cs = cpu_cycle && cpu_io && 
	({cpu_addr[6:5], cpu_addr[1]} == 3'b111)&& cpu_wr && !cpu_ds[0];

zx8301 zx8301 (
    .reset        ( reset         ),
 	 .clk_vga		( clk21        ),
	 .clk_video		( clk10      ),
	 .video_cycle  ( video_cycle   ),

	 .ntsc         ( status[3]     ),
	 .scandoubler  ( !tv15khz      ),
	 .scanlines    ( status[4]     ),

	 .clk_bus      ( clk2     ),
	 .cpu_cs       ( zx8301_cs     ),
	 .cpu_data     ( cpu_dout[7:0] ),

	 .mdv_men      ( mdv_men       ),
	 
	 .addr         ( video_addr    ),
	 .din          ( sdram_dout    ),
	 .rd           ( video_rd      ),
	 
	 .hs           ( video_hs      ),
	 .vs           ( video_vs      ),
	 .r            ( video_r       ),
	 .g            ( video_g       ),
	 .b            ( video_b       )
);

// ---------------------------------------------------------------------------------
// -------------------------------------- reset ------------------------------------
// ---------------------------------------------------------------------------------

wire rom_download = dio_download && (dio_index == 0);
reg [11:0] reset_cnt;
wire reset = (reset_cnt != 0);
always @(posedge clk2) begin
	if(buttons[1] || status[0] || status[5] || !pll_locked || rom_download)
		reset_cnt <= 12'hfff;
	else if(reset_cnt != 0)
		reset_cnt <= reset_cnt - 1;
end

// ---------------------------------------------------------------------------------
// --------------------------------------- IO --------------------------------------
// ---------------------------------------------------------------------------------

wire zx8302_sel = cpu_cycle && cpu_io && !cpu_addr[6];
wire [1:0] zx8302_addr = {cpu_addr[5], cpu_addr[1]};
wire [15:0] zx8302_dout;

wire mdv_download = (dio_index == 1) && dio_download;
wire mdv_men;
wire mdv_read;
wire [24:0] mdv_addr;

zx8302 zx8302 (
	.reset        ( reset        ),
	.init         ( !pll_locked  ),
	.clk          ( clk21       ),

	.ipl          ( cpu_ipl      ),
	.led          ( LED          ),
	
	// CPU connection
	.clk_bus      ( clk2    ),
	.cpu_sel      ( zx8302_sel   ),
	.cpu_wr       ( cpu_wr       ),
	.cpu_addr     ( zx8302_addr  ),
	.cpu_ds       ( cpu_ds       ),
	.cpu_din      ( cpu_dout     ),
   .cpu_dout     ( zx8302_dout  ),
	
	.ps2_kbd_clk  ( ps2_kbd_clk  ),
	.ps2_kbd_data ( ps2_kbd_data ),
	
	.vs           ( video_vs     ),

	// microdrive sdram interface
	.mdv_addr     ( mdv_addr     ),
	.mdv_din      ( sdram_dout   ),
	.mdv_read     ( mdv_read     ),
	.mdv_men      ( mdv_men      ),
	.video_cycle  ( video_cycle  ),
	
	.mdv_download ( mdv_download ),
	.mdv_dl_addr  ( dio_addr     )

);
	 
// ---------------------------------------------------------------------------------
// -------------------------------------- CPU --------------------------------------
// ---------------------------------------------------------------------------------

// address decoding
wire cpu_io   = ({cpu_addr[19:14], 2'b00} == 8'h18);   // internal IO $18000-$1bffff
wire cpu_bram = (cpu_addr[19:17] == 3'b001);           // 128k RAM at $20000
wire cpu_xram = status[2] && ((cpu_addr[19:18] == 2'b01) ||
							(cpu_addr[19:18] == 2'b10));      // 512k RAM at $40000 if enabled
wire cpu_ram = cpu_bram || cpu_xram;                   // any RAM
wire cpu_rom  = (cpu_addr[19:16] == 4'h0);             // 64k ROM at $0
wire cpu_mem  = cpu_ram || cpu_rom;                    // any memory mapped to sdram

wire [15:0] io_dout = cpu_addr[6]?16'h0000:zx8302_dout;	

// demultiplex the various data sources
wire [15:0] cpu_din =
	cpu_mem?sdram_dout:
	cpu_io?io_dout:
	16'hffff;

wire [31:0] cpu_addr;
wire [1:0] cpu_ds;
wire [15:0] cpu_dout;
wire [2:0] cpu_ipl;
wire cpu_rw;
wire [1:0] cpu_busstate;
wire cpu_rd = (cpu_busstate == 2'b00) || (cpu_busstate == 2'b10);
wire cpu_wr = (cpu_busstate == 2'b11) && !cpu_rw;
wire cpu_idle = (cpu_busstate == 2'b01);

reg cpu_enable;
always @(negedge clk2)
	cpu_enable <= (cpu_cycle && !dio_download) || cpu_idle;

TG68KdotC_Kernel #(0,0,0,0,0,0) tg68k (
        .clk            ( clk2      ),
        .nReset         ( ~reset         ),
        .clkena_in      ( cpu_enable     ), 
        .data_in        ( cpu_din        ),
        .IPL            ( cpu_ipl        ),
        .IPL_autovector ( 1'b1           ),
        .berr           ( 1'b0           ),
        .clr_berr       ( 1'b0           ),
        .CPU            ( 2'b00          ),   // 00=68000
		  .addr           ( cpu_addr       ),
        .data_write     ( cpu_dout       ),
        .nUDS           ( cpu_ds[1]      ),
        .nLDS           ( cpu_ds[0]      ),
        .nWr            ( cpu_rw         ),
        .busstate       ( cpu_busstate   ), // 00-> fetch code 10->read data 11->write data 01->no memaccess
        .nResetOut      (                ),
        .FC             (                )
);



// -------------------------------------------------------------------------
// -------------------------- clock generation -----------------------------
// -------------------------------------------------------------------------
					
reg clk10;  // 10.5 MHz QL pixel clock
wire clk21;
always @(posedge clk21)
	clk10 <= !clk10;

reg clk5;  // 5.25 MHz CPU clock
always @(posedge clk10)
	clk5 <= !clk5;

reg clk2;  // 2.625 MHz bus clock
always @(posedge clk5)
	clk2 <= !clk2;

// CPU and Video share the bus
reg video_cycle;
wire cpu_cycle = !video_cycle;
always @(posedge clk2)
	video_cycle <= !video_cycle;

wire pll_locked;
	
// A PLL to derive the system clock from the MiSTs 27MHz
pll pll (
	 .inclk0( CLOCK_27[0] ),
	 .c0(     clk21      ),       // 21.000 MHz
	 .c1(     SDRAM_CLK   ),       // 21.000 MHz phase shifted
	 .locked( pll_locked  )
);


endmodule
