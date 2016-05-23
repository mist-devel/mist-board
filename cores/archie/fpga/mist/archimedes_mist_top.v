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
  input wire [1:0] 	CLOCK_27, // 27 MHz
  // LED outputs
  output wire	LED, // LED Yellow
  // UART
  //output wire	UART_TX, // UART Transmitter
  //input 	wire 	UART_RX, // UART Receiver
  
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
	output[12:0]		DRAM_A,
	output[1:0]			DRAM_BA,
	output 				DRAM_CAS_N,
	output 				DRAM_CKE,
	output 				DRAM_CLK,
	output 				DRAM_CS_N,
	inout[15:0]			DRAM_DQ,
	output[1:0]			DRAM_DQM,
	output 				DRAM_RAS_N,
	output 				DRAM_WE_N,
  
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
        "ARCHIE;ARCH;",
		  "O1,MODE,8bbp,4bbp,2bbp,1bbp;",
        "T2,Start;",
        "T3,Select;",
        "T4,Reset;"
};

parameter CONF_STR_LEN = 12+28+9+10+9;

wire [7:0] kbd_out_data;
wire kbd_out_strobe;
wire [7:0] kbd_in_data;
wire kbd_in_strobe;

// generated clocks
wire clk_pix;
wire clk_pix2x;
wire clk_32m /* synthesis keep */ ;
wire clk_128m /* synthesis keep */ ;
wire clk_24m /* synthesis keep */ ;
wire clk_25m /* synthesis keep */ ;
wire clk_36m /* synthesis keep */ ;
//wire clk_8m  /* synthesis keep */ ;

wire pll_ready;
wire ram_ready;

// core's raw video 
wire [3:0]	core_r, core_g, core_b;
wire			core_hs, core_vs;

// core's raw audio 
wire [15:0]	coreaud_l, coreaud_r;

// data loading 
wire 			loader_active /* synthesis keep */ ;
wire 			loader_we /* synthesis keep */ ;
reg			loader_stb = 1'b0 /* synthesis keep */ ;
(*KEEP="TRUE"*)wire [3:0]	loader_sel /* synthesis keep */ ;
(*KEEP="TRUE"*)wire [23:0]	loader_addr /* synthesis keep */ ;
(*KEEP="TRUE"*)wire [31:0]	loader_data /* synthesis keep */ ;
          
// user io

wire [7:0] joyA;
wire [7:0] joyB;
wire [1:0] buttons;
wire [1:0] switches;


// the top file should generate the correct clocks for the machine

clockgen CLOCKS(
	.inclk0	(CLOCK_27[0]),
	.c0		(clk_32m),
	.c1		(clk_128m), 
	.c2 		(clk_24m), 
	.c3    	(clk_25m),
	.c4		(clk_36m),
	.locked	(pll_ready)  // pll locked output
);

osd #(0,100,4) OSD (
   .pclk       ( clk_pix          ),

   // spi for OSD
   .sdi        ( SPI_DI       ),
   .sck        ( SPI_SCK      ),
   .ss         ( SPI_SS3      ),

   .red_in     ( {core_r, 2'b00} ),
   .green_in   ( {core_g, 2'b00} ),
   .blue_in    ( {core_b, 2'b00} ),
   .hs_in      ( core_hs       ),
   .vs_in      ( core_vs       ),

   .red_out    ( VGA_R        ),
   .green_out  ( VGA_G        ),
   .blue_out   ( VGA_B        ),
   .hs_out     ( VGA_HS       ),
   .vs_out     ( VGA_VS       )
);

// de-multiplex spi outputs from user_io and data_io
assign SPI_DO = (CONF_DATA0==0)?user_io_sdo:(SPI_SS2==0)?data_io_sdo:1'bZ;

wire user_io_sdo;
user_io #(.STRLEN(CONF_STR_LEN)) user_io(
   .conf_str      ( CONF_STR        ),
   // the spi interface

   .SPI_CLK     	(SPI_SCK          ),
   .SPI_SS_IO     (CONF_DATA0       ),
   .SPI_MISO      (user_io_sdo           ),   // tristate handling inside user_io
   .SPI_MOSI      (SPI_DI           ),

   .SWITCHES      (switches         ),
   .BUTTONS       (buttons          ),

   .JOY0          (joyA             ),
   .JOY1          (joyB             ),

	.kbd_out_data   ( kbd_out_data   ),
	.kbd_out_strobe ( kbd_out_strobe ),
	.kbd_in_data    ( kbd_in_data    ),
	.kbd_in_strobe  ( kbd_in_strobe  )
);

wire data_io_sdo;
wire [31:0] fdc_status_out;
wire [31:0] fdc_status_in;
wire [7:0] fdc_data_in;
wire fdc_data_in_strobe;
data_io # ( .START_ADDR(26'h40_0000) )
DATA_IO  (
	.sck				( SPI_SCK 			),
	.ss				( SPI_SS2			),
	.sdi				( SPI_DI				),
	.sdo				( data_io_sdo		),

	.downloading	( loader_active	),
	.size				(						),

	.fdc_status_out( fdc_status_out  ),
	.fdc_status_in ( fdc_status_in   ),
	.fdc_data_in_strobe ( fdc_data_in_strobe ),
	.fdc_data_in   ( fdc_data_in     ),
	
   // ram interface
   .clk     		( clk_32m			),
	.wr    			( loader_we			),
	.a					( loader_addr		),
	.sel				( loader_sel		),
	.d					( loader_data 	)
);


wire			core_ack_in    /* synthesis keep */ ; 
wire			core_stb_out 	/* synthesis keep */ ; 
wire 			core_cyc_out   /* synthesis keep */ ;
wire			core_we_o;
wire [3:0]	core_sel_o;
wire [2:0]	core_cti_o;
wire [31:0] core_data_in, core_data_out;
wire [31:0] ram_data_in;
wire [26:2] core_address_out;

wire	[1:0]	pixbaseclk_select;

wire 			i2c_din, i2c_dout, i2c_clock;

archimedes_top ARCHIMEDES(
	
	.CLKCPU_I	( clk_32m			),
	.CLKPIX2X_I	( clk_pix2x			), // pixel clock x 2
	.CLKPIX_O	( clk_pix			), // pixel clock for OSD
	
	.RESET_I	(~ram_ready | loader_active),
	
	.MEM_ACK_I	( core_ack_in		),
	.MEM_DAT_I	( core_data_in		),
	.MEM_DAT_O	( core_data_out	    ),
	.MEM_ADDR_O	( core_address_out  ),
	.MEM_STB_O	( core_stb_out		),
	.MEM_CYC_O	( core_cyc_out		),
	.MEM_SEL_O	( core_sel_o		),
	.MEM_WE_O	( core_we_o			),
	.MEM_CTI_O  ( core_cti_o        ),
    
	.HSYNC		( core_hs			),
	.VSYNC		( core_vs			),
	
    .VIDEO_R		( core_r				),
	.VIDEO_G		( core_g				),
	.VIDEO_B		( core_b				),
	
	.AUDIO_L		( coreaud_l				),
	.AUDIO_R		( coreaud_r				),
	
	.I2C_DOUT	( i2c_din			),
	.I2C_DIN		( i2c_dout			),
	.I2C_CLOCK	( i2c_clock			),
	
	.DEBUG_LED	( LED					),

	.FDC_DIO_STATUS_OUT ( fdc_status_out  ),
	.FDC_DIO_STATUS_IN  ( fdc_status_in  ),
	.FDC_DIN_STROBE ( fdc_data_in_strobe  ),
	.FDC_DIN        ( fdc_data_in  ),
	
	.KBD_OUT_DATA   ( kbd_out_data   ),
	.KBD_OUT_STROBE ( kbd_out_strobe ),
	.KBD_IN_DATA    ( kbd_in_data    ),
	.KBD_IN_STROBE  ( kbd_in_strobe  ),
	
	.JOYSTICK0		( joyA[4:0]		),
	.JOYSTICK1		( joyB[4:0]		),
	.VIDBASECLK_O	( pixbaseclk_select ),
	.VIDSYNCPOL_O	( )
);

wire			ram_ack	/* synthesis keep */ ;
wire			ram_stb	/* synthesis keep */ ;
wire			ram_cyc	/* synthesis keep */ ;
wire			ram_we 	/* synthesis keep */ ;
wire  [3:0]	ram_sel	/* synthesis keep */ ;
wire [25:0] ram_address/* synthesis keep */ ;

sdram_top SDRAM(
			
		// wishbone interface
		.wb_clk		( clk_32m		),
		.wb_stb		( ram_stb		),
		.wb_cyc		( ram_cyc		),
		.wb_we		( ram_we		),
		.wb_ack		( ram_ack		),

		.wb_sel		( ram_sel		),
		.wb_adr		( ram_address	),
		.wb_dat_i	( ram_data_in	),
		.wb_dat_o	( core_data_in	),
		.wb_cti		( core_cti_o	),
				
		// SDRAM Interface
		.sd_clk		( clk_128m		),
		.sd_rst		( ~pll_ready	),
		.sd_cke		( DRAM_CKE		),

		.sd_dq   	( DRAM_DQ  		),
		.sd_addr 	( DRAM_A    	),
		.sd_dqm     ( DRAM_DQM 		),
		.sd_cs_n    ( DRAM_CS_N    ),
		.sd_ba      ( DRAM_BA  		),
		.sd_we_n    ( DRAM_WE_N    ),
		.sd_ras_n   ( DRAM_RAS_N   ),
		.sd_cas_n   ( DRAM_CAS_N  	),
		.sd_ready	( ram_ready		)
);
	
i2cSlaveTop CMOS (
	.clk		( clk_32m		),
	.rst		( ~pll_ready	),
	.sdaIn	    ( i2c_din		),
	.sdaOut	    ( i2c_dout		),
	.scl		( i2c_clock		)
);

audio	AUDIO	(
	.clk			( clk_pix2x		),
	.rst			( ~pll_ready	),
	.audio_data_l 	( coreaud_l		),
	.audio_data_r 	( coreaud_r		),
	.audio_l        ( AUDIO_L		),
	.audio_r		( AUDIO_R		)
);

always @(posedge clk_32m) begin 

	if (loader_we) begin 
	
		loader_stb <= 1'b1;
	
	end else if (ram_ack) begin 
	
		loader_stb <= 1'b0;
		
	end

end

assign ram_we			= loader_active ? loader_active : core_we_o;
assign ram_sel			= loader_active ? loader_sel : core_sel_o;
assign ram_address 	= loader_active ? {loader_addr[23:2],2'b00} : {core_address_out[23:2],2'b00};
assign ram_stb			= loader_active ? loader_stb : core_stb_out;
assign ram_cyc			= loader_active ? loader_stb : core_stb_out;
assign ram_data_in		= loader_active ? loader_data : core_data_out;
assign core_ack_in  	= loader_active ? 1'b0 : ram_ack;

assign DRAM_CLK = clk_128m;

assign clk_pix2x = pixbaseclk_select == 2'b00 ? clk_24m :
					  pixbaseclk_select == 2'b01 ? clk_25m :
					  pixbaseclk_select == 2'b10 ? clk_36m : clk_24m;


endmodule // archimedes_papoliopro_top
