`timescale 1ns / 1ps
// archimedes_top.v
//
// Archimedes top
//
// Copyright (c) 2014 Stephen J. Leary <sleary@vavi.co.uk>
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

module archimedes_top(

	// base CPU Clock
	input 			CLKCPU_I,
	input 			CLKPIX2X_I,
	output			CLKPIX_O,
	
	input 			RESET_I, 
	
	// cpu wishbone interface.
	output			MEM_CYC_O,
	output			MEM_STB_O,
	output			MEM_WE_O,
		
	input			MEM_ACK_I,
	input			MEM_ERR_I,
	input			MEM_RTY_I,
	
	output [3:0]	MEM_SEL_O,
	output [2:0]	MEM_CTI_O,
	output [23:2] 	MEM_ADDR_O,
	
	input	 [31:0]	MEM_DAT_I,
	output [31:0]	MEM_DAT_O,

	// video signals (VGA)
	output			HSYNC,
	output			VSYNC,
	
	output  [3:0]	VIDEO_R,
	output  [3:0]	VIDEO_G,
	output  [3:0]	VIDEO_B,
	
	// VIDC Enhancer selection.
	// These are from external latch C
	output [1:0]	VIDBASECLK_O,
	output [1:0]	VIDSYNCPOL_O,
	
	// I2C bus to the CMOS.
	output			I2C_DOUT,
	input				I2C_DIN,
	output			I2C_CLOCK,
	
	// "Floppy" LED
	output			DEBUG_LED,
	
	// floppy connections to external controller
	output [31:0]  FDC_DIO_STATUS_OUT,
	input [31:0]   FDC_DIO_STATUS_IN,
	input [7:0]    FDC_DIN,
	input          FDC_DIN_STROBE,

	// connection to keyboard controller
	output [7:0]   KBD_OUT_DATA,
	output         KBD_OUT_STROBE,
	input [7:0]    KBD_IN_DATA,
	input          KBD_IN_STROBE,
	
	input [4:0]		JOYSTICK0,
	input [4:0]		JOYSTICK1,
	
	// audio signal.
	output [15:0]	AUDIO_L,
	output [15:0]	AUDIO_R
	
);		      

(*KEEP="TRUE"*)wire por_reset; 

// cpu bus
(*KEEP="TRUE"*)wire [31:0] cpu_address /* synthesis keep */;
(*KEEP="TRUE"*)wire [3:0]	cpu_sel /* synthesis keep */ ;


(*KEEP="TRUE"*)wire 	   cpu_spvmd/* synthesis keep */ ;
(*KEEP="TRUE"*)wire [31:0] cpu_dat_o/* synthesis keep */ ;
(*KEEP="TRUE"*)wire [31:0] cpu_dat_i/* synthesis keep */ ;

(*KEEP="TRUE"*)wire			cpu_cyc/* synthesis keep */ ;
(*KEEP="TRUE"*)wire			cpu_stb/* synthesis keep */ ;
(*KEEP="TRUE"*)wire 		cpu_we/* synthesis keep */ ;

(*KEEP="TRUE"*)wire			cpu_ack/* synthesis keep */ ;
(*KEEP="TRUE"*)wire			cpu_err/* synthesis keep */ ;
(*KEEP="TRUE"*)wire			cpu_irq/* synthesis keep */ ;
(*KEEP="TRUE"*)wire			cpu_firq/* synthesis keep */ ;

// video DMA signals.
(*KEEP="TRUE"*)wire [31:0]	vid_address; // VIDC D31-D0
(*KEEP="TRUE"*)wire 			vid_flybk /* synthesis keep */; // VIDC FLYBK 
(*KEEP="TRUE"*)wire 			vid_req; // VIDC REQ
(*KEEP="TRUE"*)wire 			vid_ack; // VIDC ACK 

(*KEEP="TRUE"*)wire			ioc_cs/* synthesis keep */ ;
(*KEEP="TRUE"*)wire			ioc_ack/* synthesis keep */ ;
(*KEEP="TRUE"*)wire [7:0]	ioc_dat_o/* synthesis keep */ ;

(*KEEP="TRUE"*)wire			rom_low_cs/* synthesis keep */ ;
wire [5:0]						ioc_cin, ioc_cout;

a23_core ARM(

	.i_clk		( CLKCPU_I		),
	
	.o_wb_cyc	( cpu_cyc		),
	.o_wb_stb	( cpu_stb		),
	.o_wb_we	( cpu_we			),

	.o_wb_adr	( cpu_address	),
	.o_wb_sel	( cpu_sel		),

	.i_wb_dat	( cpu_dat_i		),
	.o_wb_dat	( cpu_dat_o		),
	

	.i_wb_ack	( cpu_ack		),
	.i_wb_err	( cpu_err		), 
	
	.o_wb_tga	( cpu_spvmd		),
	.i_irq		( cpu_irq		),
	.i_firq		( cpu_firq		),
	
	.i_system_rdy(~por_reset	)
);

memc MEMC(
	
	.clkcpu			( CLKCPU_I		),
	.rst_i			( por_reset		),
	
	.spvmd			(cpu_spvmd),

	// cpu interface
	.cpu_address	( cpu_address[25:0]	),
	.cpu_cyc	    ( cpu_cyc		),
	.cpu_stb		( cpu_stb		),
	.cpu_we			( cpu_we		),
	.cpu_sel		( cpu_sel		),
	.cpu_ack		( cpu_ack		),
	.cpu_err		( cpu_err		),
	
	// memory interface
	.mem_addr_o		( MEM_ADDR_O	),
	.mem_stb_o		( MEM_STB_O		),
	.mem_cyc_o		( MEM_CYC_O		),
	.mem_ack_i		( MEM_ACK_I		),
	.mem_sel_o		( MEM_SEL_O		),
	.mem_we_o		( MEM_WE_O		),
	.mem_cti_o		( MEM_CTI_O		),
	
	// vidc interface
	.hsync			( HSYNC			),
	.flybk			( vid_flybk		),
	.vidrq			( vid_req		),
	.vidak			( vid_ack		),
	.sndak			( snd_ack		),
	.sndrq			( snd_req		),
	.vidw			( vid_we		),
	
	// ioc interface
	.ioc_cs			( ioc_cs			),
	.rom_low_cs		( rom_low_cs	),
	.ram_cs			( ram_cs			),
	
	// irqs
	
	.sirq_n			( sirq_n		)
);

vidc VIDC(

	  .clkpix2x	( CLKPIX2X_I	),
	  .clkpix	( CLKPIX_O		),
	  .clkcpu	( CLKCPU_I		),  
	  
	  .rst_i(por_reset),  
	  
	  .cpu_dat(cpu_dat_o),

	  // memc 
	  .flybk		( vid_flybk	),
	  .vidak		( vid_ack	),
	  .vidrq		( vid_req	),
	  .sndak		( snd_ack	),
	  .sndrq		( snd_req	),
	  
	  .viddat	( MEM_DAT_I	),
	  .vidw		( vid_we		),
	
	  // video signals
	  .hsync		( HSYNC		),
	  .vsync		( VSYNC		),
	  .video_r	( VIDEO_R	),
	  .video_g	( VIDEO_G	),
	  .video_b	( VIDEO_B	),
	  
	  // audio signals
	  .audio_l	( AUDIO_L	),
	  .audio_r	( AUDIO_R	)
);

wire [1:0]	ioc_speed = cpu_address[20:19];
wire [7:1] 	ioc_select;
wire			ioc_sext;
// podule data bus.
wire [15:0]	pod_dat_o;
wire [15:0]	pod_dat_i;

wire floppy_firq;
wire floppy_drq;

ioc IOC(

	.clkcpu		( CLKCPU_I				), 
	.clk2m_en	( ioc_clk2m_en			),
	.clk8m_en	( ioc_clk8m_en			),
	
	.por		( por_reset				),
	.ir			( vid_flybk				),
	
	.fh			( {floppy_firq, floppy_drq}),
	
	.il			( {6'b1111, sirq_n, 1'b1 }),
	
	.c_in		( ioc_cin 				),
	.c_out		( ioc_cout 				),
	
	.select		( ioc_select			),
	.sext		( ioc_sext				),
	
	// wishbone bus
	.wb_adr		( cpu_address[6:2]	),
	.wb_stb		( cpu_stb & cpu_address[21] & ioc_cs ),
	.wb_cyc		( cpu_cyc & cpu_address[21] & ioc_cs ),
	.wb_we		( cpu_we  				),

	.wb_dat_i	( cpu_dat_o[23:16]	),
	.wb_dat_o	( ioc_dat_o				),
	.wb_bank		( cpu_address[18:16]	), 
	
	.irq			( cpu_irq				),
	.firq			( cpu_firq				),
	
	.kbd_out_data   ( KBD_OUT_DATA   ),
	.kbd_out_strobe ( KBD_OUT_STROBE ),
	.kbd_in_data    ( KBD_IN_DATA    ),
	.kbd_in_strobe  ( KBD_IN_STROBE  )
);

wire 	podules_en = ioc_cs & ioc_select[4];

// all podules live in the the podules module.
// this is just to keep things tidy.
podules PODULES(
	// everything is synced to the master 32m clock except the pix clock.
	.clkcpu			( CLKCPU_I				),
	.clk2m_en		( ioc_clk2m_en			),
	.clk8m_en		( ioc_clk8m_en			),
	
	.rst_i			( RESET_I				),

	.speed_i		( ioc_speed				),
	
	.wb_cyc			( cpu_cyc & podules_en),
	.wb_stb			( cpu_stb & podules_en),
	.wb_we			( cpu_we  & podules_en),

	.wb_dat_o		( pod_dat_o				),
	.wb_dat_i		( cpu_dat_o[15:0]		),
	.wb_adr			( cpu_address[15:2]		)
);

wire [7:0]	floppy_dat_o;
wire 		floppy_en = ioc_cs & ioc_select[1];

// floppy drive signals.
wire  [3:0] floppy_drive;
wire  	  	floppy_side;
wire  	  	floppy_motor;
wire 		  	floppy_inuse;
wire 		  	floppy_density;
wire 		  	floppy_reset;

fdc1772 FDC1772 (

	.clkcpu			( CLKCPU_I				),
	.clk8m_en		( ioc_clk8m_en			),

	.wb_cyc			( cpu_cyc & floppy_en	),
	.wb_stb			( cpu_stb & floppy_en	),
	.wb_we			( cpu_we  & floppy_en	),

	.wb_dat_o		( floppy_dat_o			),
	.wb_dat_i		( cpu_dat_o[23:16]		),
	.wb_adr			( cpu_address[15:2]		), 
	
	.floppy_firq	( floppy_firq			),
	.floppy_drq		( floppy_drq			),
	
	.dio_status_out( FDC_DIO_STATUS_OUT ),
	.dio_status_in ( FDC_DIO_STATUS_IN  ),
	.dio_in_strobe ( FDC_DIN_STROBE     ),
	.dio_in        ( FDC_DIN           ),
	
	.floppy_drive	( floppy_drive			),
	.floppy_motor	( floppy_motor			),
	.floppy_inuse	( floppy_inuse			),
	.floppy_side	( floppy_side 			),
	.floppy_density( floppy_density		),
	.floppy_reset	( floppy_reset			)
);

wire [7:0]	latches_dat_o;
wire 	latches_en = ioc_cs & ioc_select[5] & (ioc_speed == 2'd2);

latches LATCHES(

	.clkcpu			( CLKCPU_I				),

	.wb_cyc			( cpu_cyc & latches_en	),
	.wb_stb			( cpu_stb & latches_en	),
	.wb_we			( cpu_we  & latches_en	),

	.wb_dat_i		( cpu_dat_o[23:16]		),
	.wb_dat_o		( latches_dat_o			),
	.wb_adr			( cpu_address[15:2]		),
	
	.floppy_drive	( floppy_drive			),
	.floppy_motor	( floppy_motor			),
	.floppy_inuse	( floppy_inuse			),
	.floppy_side	( floppy_side 			),
	.floppy_density	( floppy_density		),
	.floppy_reset	( floppy_reset			),
	
	.joy0			( JOYSTICK0				),
	.joy1			( JOYSTICK1				),
	
	.baseclk		( VIDBASECLK_O			),
	.syncpol		( VIDSYNCPOL_O			)
);

por POR(
	.clk		( CLKCPU_I				),
	.rst_i		( RESET_I				),
	.rst_o		( por_reset				)
);
	

assign MEM_DAT_O	= 	cpu_dat_o;

assign cpu_dat_i	=	floppy_en				?	{24'd0, floppy_dat_o} :
							latches_en				?	{24'd0, latches_dat_o} :
							podules_en			 	? 	{16'd0, pod_dat_o} :
							ioc_cs & ~ioc_sext 	?  {24'd0, ioc_dat_o} :			
							ram_cs					?	MEM_DAT_I	:
							32'hFFFF_FFFF;
								  
assign I2C_CLOCK	= ioc_cout[1];
assign I2C_DOUT	= ioc_cout[0];
						
assign ioc_cin[5:0] 	= {ioc_cout[5:2], I2C_CLOCK, I2C_DIN};
assign DEBUG_LED 		= ~(~floppy_inuse & ~floppy_drive[0]);

	
endmodule // archimedes_top
