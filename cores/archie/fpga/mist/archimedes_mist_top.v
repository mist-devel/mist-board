`timescale 1ns / 1ps
// archimedes_mist_top.v
//
// Archimedes Mist Support Top
//
// Copyright (c) 2014-2015 Stephen J. Leary <sleary@vavi.co.uk>
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
module archimedes_mist_top(
	// clock inputs
	input   [1:0] CLOCK_27, // 27 MHz
	// LED outputs
	output        LED, // LED Yellow
	// UART
	//output      UART_TX, // UART Transmitter
	//input       UART_RX, // UART Receiver
  
	// VGA
	output        VGA_HS, // VGA H_SYNC
	output        VGA_VS, // VGA V_SYNC
	output  [5:0] VGA_R, // VGA Red[5:0]
	output  [5:0] VGA_G, // VGA Green[5:0]
	output  [5:0] VGA_B, // VGA Blue[5:0];
	
	// AUDIO
	output        AUDIO_L, // sigma-delta DAC output left
	output        AUDIO_R, // sigma-delta DAC output right
	
	// SDRAM
	output [12:0] DRAM_A,
	output  [1:0] DRAM_BA,
	output        DRAM_CAS_N,
	output        DRAM_CKE,
	output        DRAM_CLK,
	output        DRAM_CS_N,
	inout  [15:0] DRAM_DQ,
	output  [1:0] DRAM_DQM,
	output        DRAM_RAS_N,
	output        DRAM_WE_N,
  
	// SPI
	inout         SPI_DO,
	input         SPI_DI,
	input         SPI_SCK,
	input         SPI_SS2,    // data_io
	input         SPI_SS3,    // OSD
	input         SPI_SS4,    // Direct SD
	input         CONF_DATA0  // SPI_SS for user_io
);

wire [7:0] kbd_out_data;
wire kbd_out_strobe;
wire [7:0] kbd_in_data;
wire kbd_in_strobe;

// generated clocks
wire clk_pix;
wire ce_pix;
wire clk_sys /* synthesis keep */ ;
wire clk_mem /* synthesis keep */ ;
//wire clk_8m  /* synthesis keep */ ;

wire pll_ready;
wire pll_vidc_ready;
wire ram_ready;

// core's raw video 
wire [3:0] core_r, core_g, core_b;
wire       core_hs, core_vs;

// core's raw audio 
wire [15:0] coreaud_l, coreaud_r;

// data loading 
wire       downloading;
wire       loader_active = downloading && (dio_index == 1 || dio_index == 2);
wire [7:0] dio_index;
wire       loader_we /* synthesis keep */ ;
reg        loader_stb = 1'b0 /* synthesis keep */ ;
reg        rom_ready = 0;
(*KEEP="TRUE"*)wire [3:0]	loader_sel /* synthesis keep */ ;
(*KEEP="TRUE"*)wire [23:0]	loader_addr /* synthesis keep */ ;
(*KEEP="TRUE"*)wire [31:0]	loader_data /* synthesis keep */ ;
          
// user io

wire [7:0] joyA;
wire [7:0] joyB;
wire [1:0] buttons;
wire [1:0] switches;
wire       scandoubler_disable;
wire       ypbpr;

// the top file should generate the correct clocks for the machine

clockgen CLOCKS(
	.inclk0	(CLOCK_27[0]),
	.c0		(clk_sys), // 40 MHz
	.c1		(clk_mem), // 120 MHz
	.c3		(DRAM_CLK),
	.locked	(pll_ready)  // pll locked output
);

pll_vidc CLOCKS_VIDC(
	.inclk0	(CLOCK_27[0]),
	.c0		(clk_pix),
	.areset(pll_areset),
	.scanclk(pll_scanclk),
	.scandata(pll_scandata),
	.scanclkena(pll_scanclkena),
	.configupdate(pll_configupdate),
	.scandataout(pll_scandataout),
	.scandone(pll_scandone),
	.locked	(pll_vidc_ready)  // pll locked output
);

wire       pll_reconfig_busy;
wire       pll_areset;
wire       pll_configupdate;
wire       pll_scanclk;
wire       pll_scanclkena;
wire       pll_scandata;
wire       pll_scandataout;
wire       pll_scandone;
reg        pll_reconfig_reset;
wire [7:0] pll_rom_address;
wire       pll_rom_q;
reg        pll_write_from_rom;
wire       pll_write_rom_ena;
reg        pll_reconfig;
wire       q_reconfig_25;
wire       q_reconfig_24;
wire       q_reconfig_36;

rom_reconfig_25 rom_reconfig_25
(
	.address(pll_rom_address),
	.clock(clk_sys),
	.rden(pll_write_rom_ena),
	.q(q_reconfig_25)
);

rom_reconfig_24 rom_reconfig_24
(
	.address(pll_rom_address),
	.clock(clk_sys),
	.rden(pll_write_rom_ena),
	.q(q_reconfig_24)
);

rom_reconfig_36 rom_reconfig_36
(
	.address(pll_rom_address),
	.clock(clk_sys),
	.rden(pll_write_rom_ena),
	.q(q_reconfig_36)
);

assign pll_rom_q = pixbaseclk_select == 2'b01 ? q_reconfig_25 :
                   pixbaseclk_select == 2'b10 ? q_reconfig_36 : q_reconfig_24;

pll_reconfig pll_reconfig_inst
(
	.busy(pll_reconfig_busy),
	.clock(clk_sys),
	.counter_param(0),
	.counter_type(0),
	.data_in(0),
	.pll_areset(pll_areset),
	.pll_areset_in(0),
	.pll_configupdate(pll_configupdate),
	.pll_scanclk(pll_scanclk),
	.pll_scanclkena(pll_scanclkena),
	.pll_scandata(pll_scandata),
	.pll_scandataout(pll_scandataout),
	.pll_scandone(pll_scandone),
	.read_param(0),
	.reconfig(pll_reconfig),
	.reset(pll_reconfig_reset),
	.reset_rom_address(0),
	.rom_address_out(pll_rom_address),
	.rom_data_in(pll_rom_q),
	.write_from_rom(pll_write_from_rom),
	.write_param(0),
	.write_rom_ena(pll_write_rom_ena)
);

always @(posedge clk_sys) begin
	reg [1:0] pixbaseclk_select_d;
	reg [1:0] pll_reconfig_state = 0;
	reg [9:0] pll_reconfig_timeout;

	pll_write_from_rom <= 0;
	pll_reconfig <= 0;
	pll_reconfig_reset <= 0;
	case (pll_reconfig_state)
	2'b00:
	begin
		pixbaseclk_select_d <= pixbaseclk_select;
		if (pixbaseclk_select_d != pixbaseclk_select) begin
			pll_write_from_rom <= 1;
			pll_reconfig_state <= 2'b01;
		end
	end
	2'b01: pll_reconfig_state <= 2'b10;
	2'b10:
        if (~pll_reconfig_busy) begin
            pll_reconfig <= 1;
            pll_reconfig_state <= 2'b11;
            pll_reconfig_timeout <= 10'd1000;
        end
	2'b11:
	begin
		pll_reconfig_timeout <= pll_reconfig_timeout - 1'd1;
		if (pll_reconfig_timeout == 10'd1) begin
			// pll_reconfig stuck in busy state
			pll_reconfig_reset <= 1;
			pll_reconfig_state <= 2'b00;
		end
		if (~pll_reconfig & ~pll_reconfig_busy) pll_reconfig_state <= 2'b00;
	end
	default: ;
	endcase
end

// forcibly blank back porch area
reg [3:0] r_adj, g_adj, b_adj;
reg       hs_adj, vs_adj;
reg [7:0] pix_cnt;
// blanking size: 256 cycles @ 24MHz (TV), 64 cycles otherwise (VGA)
wire      back_porch_n =  (pixbaseclk_select[0] == pixbaseclk_select[1]) ? &pix_cnt : &pix_cnt[5:0];

always @(posedge clk_pix) begin

	hs_adj <= core_hs;
	vs_adj <= core_vs;

	if (~back_porch_n) pix_cnt <= pix_cnt + 1'd1;
	if (~hs_adj) pix_cnt <= 0;
	if (back_porch_n) begin
		r_adj <= core_r;
		g_adj <= core_g;
		b_adj <= core_b;
	end else
		{ r_adj, g_adj, b_adj } <= 12'h0;
end

wire [5:0] sd_r, sd_g, sd_b;
wire       sd_hs;
wire       sd_vs;

scandoubler #(11, 4) scandoubler
(
	.clk_sys    ( clk_pix    ),
	.scanlines  ( 2'b00      ),
	.ce_divider ( 1'b1       ),
	.hs_in      ( hs_adj     ),
	.vs_in      ( vs_adj     ),
	.r_in       ( r_adj      ),
	.g_in       ( g_adj      ),
	.b_in       ( b_adj      ),
	.hs_out     ( sd_hs      ),
	.vs_out     ( sd_vs      ),
	.r_out      ( sd_r       ),
	.g_out      ( sd_g       ),
	.b_out      ( sd_b       )
);

wire       vs = scandoubler_en ? sd_vs : core_vs;
wire       hs = scandoubler_en ? sd_hs : core_hs;
wire [5:0] r = scandoubler_en  ? sd_r : { r_adj, r_adj[3:2] };
wire [5:0] g = scandoubler_en  ? sd_g : { g_adj, g_adj[3:2] };
wire [5:0] b = scandoubler_en  ? sd_b : { b_adj, b_adj[3:2] };

wire [5:0] osd_r_o, osd_g_o, osd_b_o;

osd #(10'd0,10'd0,4) OSD (
	.clk_sys    ( clk_pix      ),

	// spi for OSD
	.SPI_DI     ( SPI_DI       ),
	.SPI_SCK    ( SPI_SCK      ),
	.SPI_SS3    ( SPI_SS3      ),

	.R_in       ( r            ),
	.G_in       ( g            ),
	.B_in       ( b            ),
	.HSync      ( hs           ),
	.VSync      ( vs           ),

	.R_out      ( osd_r_o      ),
	.G_out      ( osd_g_o      ),
	.B_out      ( osd_b_o      )
);

wire [5:0] Y, Pb, Pr;

rgb2ypbpr rgb2ypbpr
(
	.red   ( osd_r_o ),
	.green ( osd_g_o ),
	.blue  ( osd_b_o ),
	.y     ( Y       ),
	.pb    ( Pb      ),
	.pr    ( Pr      )
);

wire   scandoubler_en = ~scandoubler_disable && pixbaseclk_select[0] == pixbaseclk_select[1];
assign VGA_R = ypbpr?Pr:osd_r_o;
assign VGA_G = ypbpr? Y:osd_g_o;
assign VGA_B = ypbpr?Pb:osd_b_o;
wire   CSync = ~(hs ^ vs);
//24 MHz modes get composite sync automatically
assign VGA_HS = ((pixbaseclk_select[0] == pixbaseclk_select[1] && scandoubler_disable) | ypbpr) ? CSync : hs;
assign VGA_VS = ((pixbaseclk_select[0] == pixbaseclk_select[1] && scandoubler_disable) | ypbpr) ? 1'b1 : vs;

wire [31:0] sd_lba;
wire  [1:0] sd_rd;
wire  [1:0] sd_wr;
wire        sd_ack;
wire        sd_ack_conf;
wire        sd_conf;
wire        sd_sdhc = 1'b1;
wire  [7:0] sd_dout;
wire        sd_dout_strobe;
wire  [7:0] sd_din;
wire        sd_din_strobe;
wire  [8:0] sd_buff_addr;
wire  [1:0] img_mounted;
wire [31:0] img_size;

// de-multiplex spi outputs from user_io and data_io
assign SPI_DO = (CONF_DATA0==0)?user_io_sdo:(SPI_SS2==0)?data_io_sdo:1'bZ;

wire user_io_sdo;
user_io user_io(
	// the spi interface
	.clk_sys        ( clk_sys        ),
	.SPI_CLK        ( SPI_SCK        ),
	.SPI_SS_IO      ( CONF_DATA0     ),
	.SPI_MISO       ( user_io_sdo    ),   // tristate handling inside user_io
	.SPI_MOSI       ( SPI_DI         ),

	.SWITCHES       ( switches       ),
	.BUTTONS        ( buttons        ),
	.scandoubler_disable(scandoubler_disable),
	.ypbpr          ( ypbpr          ),

	.JOY0           ( joyA           ),
	.JOY1           ( joyB           ),

	.kbd_out_data   ( kbd_out_data   ),
	.kbd_out_strobe ( kbd_out_strobe ),
	.kbd_in_data    ( kbd_in_data    ),
	.kbd_in_strobe  ( kbd_in_strobe  ),

	.sd_lba         ( sd_lba         ),
	.sd_rd          ( sd_rd          ),
	.sd_wr          ( sd_wr          ),
	.sd_ack         ( sd_ack         ),
	.sd_ack_conf    ( sd_ack_conf    ),
	.sd_conf        ( sd_conf        ),
	.sd_sdhc        ( sd_sdhc        ),
	.sd_dout        ( sd_dout        ),
	.sd_dout_strobe ( sd_dout_strobe ),
	.sd_din         ( sd_din         ),
	.sd_din_strobe  ( sd_din_strobe  ),
	.sd_buff_addr   ( sd_buff_addr   ),
	.img_mounted    ( img_mounted    ),
	.img_size       ( img_size       )
);

wire   spi_din = SPI_SS4 ? SPI_DI : SPI_DO;

wire data_io_sdo;
data_io # ( .START_ADDR(24'h40_0000) )
DATA_IO  (
	.sck            ( SPI_SCK        ),
	.ss             ( SPI_SS2        ),
	.ss_sd          ( SPI_SS4        ),
	.sdi            ( spi_din        ),
	.sdo            ( data_io_sdo    ),

	.reset          ( reset          ),
	.ide_req        ( ide_req        ),
	.ide_ack        ( ide_ack        ),
	.ide_err        ( ide_err        ),
	.ide_reg_o_adr  ( ide_reg_i_adr  ),
	.ide_reg_o      ( ide_reg_i      ),
	.ide_reg_we     ( ide_reg_we     ),
	.ide_reg_i_adr  ( ide_reg_o_adr  ),
	.ide_reg_i      ( ide_reg_o      ),
	.ide_data_addr  ( ide_data_addr  ),
	.ide_data_o     ( ide_data_i     ),
	.ide_data_i     ( ide_data_o     ),
	.ide_data_rd    ( ide_data_rd    ),
	.ide_data_we    ( ide_data_we    ),

	.downloading	( downloading	 ),
	.index          ( dio_index      ),

	// ram interface
	.clk           ( clk_sys         ),
	.wr            ( loader_we       ),
	.a             ( loader_addr     ),
	.sel           ( loader_sel      ),
	.d             ( loader_data     )
);

wire        core_ack_in   /* synthesis keep */ ;
wire        core_stb_out  /* synthesis keep */ ;
wire        core_cyc_out  /* synthesis keep */ ;
wire        core_we_o;
wire  [3:0] core_sel_o;
wire  [2:0] core_cti_o;
wire [31:0] core_data_in, core_data_out;
wire [31:0] ram_data_in;
wire [26:2] core_address_out;

wire  [1:0] pixbaseclk_select;

wire        i2c_din, i2c_dout, i2c_clock;

wire        ide_req;
wire        ide_ack;
wire        ide_err;
wire  [2:0] ide_reg_o_adr;
wire  [7:0] ide_reg_o;
wire        ide_reg_we;
wire  [2:0] ide_reg_i_adr;
wire  [7:0] ide_reg_i;
wire  [8:0] ide_data_addr;
wire  [7:0] ide_data_o;
wire  [7:0] ide_data_i;
wire        ide_data_rd;
wire        ide_data_we;

wire        reset = ~ram_ready | ~rom_ready;

archimedes_top ARCHIMEDES(
	
	.CLKCPU_I       ( clk_sys        ),
	.CLKPIX_I       ( clk_pix        ), // pixel clock for OSD
	.CEPIX_O        ( ce_pix         ),

	.RESET_I        ( reset          ),

	.MEM_ACK_I      ( core_ack_in    ),
	.MEM_DAT_I      ( core_data_in   ),
	.MEM_DAT_O      ( core_data_out  ),
	.MEM_ADDR_O     ( core_address_out ),
	.MEM_STB_O      ( core_stb_out   ),
	.MEM_CYC_O      ( core_cyc_out   ),
	.MEM_SEL_O      ( core_sel_o     ),
	.MEM_WE_O       ( core_we_o      ),
	.MEM_CTI_O      ( core_cti_o     ),

	.HSYNC          ( core_hs        ),
	.VSYNC          ( core_vs        ),

	.VIDEO_R        ( core_r         ),
	.VIDEO_G        ( core_g         ),
	.VIDEO_B        ( core_b         ),

	.AUDIO_L        ( coreaud_l      ),
	.AUDIO_R        ( coreaud_r      ),

	.I2C_DOUT       ( i2c_din        ),
	.I2C_DIN        ( i2c_dout       ),
	.I2C_CLOCK      ( i2c_clock      ),

	.DEBUG_LED      ( LED            ),

	// FDC connection
	.img_mounted    ( img_mounted    ),
	.img_size       ( img_size       ),
	.img_wp         ( 0              ),
	.sd_lba         ( sd_lba         ),
	.sd_rd          ( sd_rd          ),
	.sd_wr          ( sd_wr          ),
	.sd_ack         ( sd_ack         ),
	.sd_buff_addr   ( sd_buff_addr   ),
	.sd_dout        ( sd_dout        ),
	.sd_din         ( sd_din         ),
	.sd_dout_strobe ( sd_dout_strobe ),
	.sd_din_strobe  ( sd_din_strobe  ),

	// IDE controller
	.ide_req        ( ide_req        ),
	.ide_ack        ( ide_ack        ),
	.ide_err        ( ide_err        ),
	.ide_reg_o_adr  ( ide_reg_o_adr  ),
	.ide_reg_o      ( ide_reg_o      ),
	.ide_reg_we     ( ide_reg_we     ),
	.ide_reg_i_adr  ( ide_reg_i_adr  ),
	.ide_reg_i      ( ide_reg_i      ),
	.ide_data_addr  ( ide_data_addr  ),
	.ide_data_o     ( ide_data_o     ),
	.ide_data_i     ( ide_data_i     ),
	.ide_data_rd    ( ide_data_rd    ),
	.ide_data_we    ( ide_data_we    ),

	.KBD_OUT_DATA   ( kbd_out_data   ),
	.KBD_OUT_STROBE ( kbd_out_strobe ),
	.KBD_IN_DATA    ( kbd_in_data    ),
	.KBD_IN_STROBE  ( kbd_in_strobe  ),

	.JOYSTICK0      ( ~{joyB[4], joyB[0], joyB[1], joyB[2], joyB[3]} ),
	.JOYSTICK1      ( ~{joyA[4], joyA[0], joyA[1], joyA[2], joyA[3]} ),
	.VIDBASECLK_O	( pixbaseclk_select ),
	.VIDSYNCPOL_O	( )
);

wire        ram_ack     /* synthesis keep */ ;
wire        ram_stb     /* synthesis keep */ ;
wire        ram_cyc     /* synthesis keep */ ;
wire        ram_we      /* synthesis keep */ ;
wire  [3:0] ram_sel     /* synthesis keep */ ;
wire [25:0] ram_address /* synthesis keep */ ;

sdram_top SDRAM(

	// wishbone interface
	.wb_clk         ( clk_sys        ),
	.wb_stb         ( ram_stb        ),
	.wb_cyc         ( ram_cyc        ),
	.wb_we          ( ram_we         ),
	.wb_ack         ( ram_ack        ),

	.wb_sel         ( ram_sel        ),
	.wb_adr         ( ram_address    ),
	.wb_dat_i       ( ram_data_in    ),
	.wb_dat_o       ( core_data_in   ),
	.wb_cti	        ( core_cti_o     ),

	// SDRAM Interface
	.sd_clk         ( clk_mem        ),
	.sd_rst         ( ~pll_ready     ),
	.sd_cke         ( DRAM_CKE       ),

	.sd_dq          ( DRAM_DQ        ),
	.sd_addr        ( DRAM_A         ),
	.sd_dqm         ( DRAM_DQM       ),
	.sd_cs_n        ( DRAM_CS_N      ),
	.sd_ba          ( DRAM_BA        ),
	.sd_we_n        ( DRAM_WE_N      ),
	.sd_ras_n       ( DRAM_RAS_N     ),
	.sd_cas_n       ( DRAM_CAS_N     ),
	.sd_ready	( ram_ready      )
);

i2cSlaveTop CMOS (
	.clk            ( clk_sys        ),
	.rst            ( ~pll_ready     ),
	.sdaIn          ( i2c_din        ),
	.sdaOut	        ( i2c_dout       ),
	.scl            ( i2c_clock      ),
	.we             ( downloading && dio_index == 3 && loader_we ),
	.addr           ( loader_addr[7:0] ),
	.data           ( loader_data[7:0] )
);

audio	AUDIO	(
	.clk            ( clk_pix        ),
	.rst            ( ~pll_ready     ),
	.audio_data_l   ( coreaud_l      ),
	.audio_data_r   ( coreaud_r      ),
	.audio_l        ( AUDIO_L        ),
	.audio_r        ( AUDIO_R        )
);

always @(posedge clk_sys) begin 
	reg loader_active_old;
	loader_active_old <= loader_active;

	if (loader_active_old & ~loader_active) rom_ready <= 1;
	if (loader_we) begin 

		loader_stb <= 1'b1;

	end else if (ram_ack) begin 

		loader_stb <= 1'b0;

	end

end

assign ram_we       = loader_active ? loader_active : core_we_o;
assign ram_sel      = loader_active ? loader_sel : core_sel_o;
assign ram_address  = loader_active ? {loader_addr[23:2],2'b00} : {core_address_out[23:2],2'b00};
assign ram_stb      = loader_active ? loader_stb : core_stb_out;
assign ram_cyc      = loader_active ? loader_stb : core_stb_out;
assign ram_data_in  = loader_active ? loader_data : core_data_out;
assign core_ack_in  = loader_active ? 1'b0 : ram_ack;

endmodule // archimedes_mist_top
