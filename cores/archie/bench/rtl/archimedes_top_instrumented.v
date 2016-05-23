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

/* version for instrumenting against arcem ioc */
module archimedes_top_instrumented(

	// base CPU Clock
	input 			CLKCPU_I,
	input 			CLKPIX_I,
	
	input 			RESET_I, 
	
	// cpu wishbone interface.
	output			MEM_CYC_O,
	output			MEM_STB_O,
	output			MEM_WE_O,
	output			ioc_cs,
	output			iospace,
	
		
	input				MEM_ACK_I,
	input				MEM_ERR_I,
	input				MEM_RTY_I,
	
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
	
	input	use_instrumented,

	input	cpu_irq,
	input	cpu_firq,
	
	
	
	// "Floppy" LED
	output			DEBUG_LED,
	
	// connection to keyboard controller
	output [7:0]   KBD_OUT_DATA,
	output         KBD_OUT_STROBE,
	input [7:0]    KBD_IN_DATA,
	input          KBD_IN_STROBE
	
);		      

(*KEEP="TRUE"*)wire por_reset; 

// cpu bus
(*KEEP="TRUE"*)wire [31:0] cpu_address /* synthesis keep */;
(*KEEP="TRUE"*)wire [3:0]	cpu_sel /* synthesis keep */ ;


(*KEEP="TRUE"*)wire 	   	cpu_spvmd/* synthesis keep */ ;
(*KEEP="TRUE"*)wire [31:0] cpu_dat_o/* synthesis keep */ ;
(*KEEP="TRUE"*)wire [31:0] cpu_dat_i/* synthesis keep */ ;

(*KEEP="TRUE"*)wire			cpu_cyc/* synthesis keep */ ;
(*KEEP="TRUE"*)wire			cpu_stb/* synthesis keep */ ;
(*KEEP="TRUE"*)wire 			cpu_we/* synthesis keep */ ;

(*KEEP="TRUE"*)wire			cpu_ack/* synthesis keep */ ;
(*KEEP="TRUE"*)wire			cpu_err/* synthesis keep */ ;
(*KEEP="TRUE"*)wire			cpu_irq/* synthesis keep */ ;
(*KEEP="TRUE"*)wire			cpu_firq/* synthesis keep */ ;

// video DMA signals.
(*KEEP="TRUE"*)wire [31:0]	vid_address; // VIDC D31-D0
(*KEEP="TRUE"*)wire 			vid_flybk /* synthesis keep */; // VIDC FLYBK 
(*KEEP="TRUE"*)wire 			vid_req; // VIDC REQ
(*KEEP="TRUE"*)wire 			vid_ack; // VIDC ACK 

//(*KEEP="TRUE"*)wire			ioc_cs/* synthesis keep */ ;
//(*KEEP="TRUE"*)wire			ioc_ack/* synthesis keep */ ;
(*KEEP="TRUE"*)wire [7:0]	ioc_dat_o/* synthesis keep */ ;

(*KEEP="TRUE"*)wire			rom_low_cs/* synthesis keep */ ;
wire [5:0]						ioc_cin, ioc_cout;

a23_core ARM(

	.i_clk		( CLKCPU_I		),
	
	.o_wb_cyc	( cpu_cyc		),
	.o_wb_stb	( cpu_stb		),
	.o_wb_we		( cpu_we			),

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
	.cpu_cyc			( cpu_cyc		),
	.cpu_stb			( cpu_stb		),
	.cpu_we			( cpu_we			),
	.cpu_sel			( cpu_sel		),
	.cpu_ack			( cpu_ack		),
	.cpu_err			( cpu_err		),
	
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

i2cSlaveTop CMOS (
	.clk		( CLKCPU_I		),
	.rst		( RESET_I	),
	.sdaIn	( ioc_cout[0]		),
	.sdaOut	( I2C_DIN		),
	.scl		( ioc_cout[1]		)
);


vidc VIDC(
	  .clkpix2x(CLKPIX_I),
     
	  .clkcpu(CLKCPU_I),  
	  
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
	  .video_b	( VIDEO_B	)
);

ioc IOC(

	.clkcpu		( CLKCPU_I				), 
	.por			( por_reset				),
	.ir			( vid_flybk				),
	
	.il			( {6'b1111, 1'b1, 1'b1 }),
	
	.c_in			( ioc_cin 				),
	.c_out		( ioc_cout 				),
	
	// wishbone bus
	.wb_adr		( cpu_address[6:2]	),
	.wb_stb		( cpu_stb & cpu_address[21] & ioc_cs ),
	.wb_cyc		( cpu_cyc & cpu_address[21] & ioc_cs ),
	.wb_we		( cpu_we  				),
	//.wb_ack		( ioc_ack				),

	.wb_dat_i	( cpu_dat_o[23:16]	),
	.wb_dat_o	( ioc_dat_o				),
	.wb_bank		( cpu_address[18:16]	), 
	
	//.irq			( cpu_irq				),
	//.firq			( cpu_firq				),
	
	.kbd_out_data   ( KBD_OUT_DATA   ),
	.kbd_out_strobe ( KBD_OUT_STROBE ),
	.kbd_in_data    ( KBD_IN_DATA    ),
	.kbd_in_strobe  ( KBD_IN_STROBE  )
);

por POR(
	.clk			( CLKCPU_I				),
	.rst_i		( RESET_I				),
	.rst_o		( por_reset				)
);
   
	
reg  [7:0] ext_latcha = 8'hFF;
wire ext_latcha_en = cpu_address == 26'h3350040 /* synthesis keep */ ;

always @(posedge CLKCPU_I) begin 
	
	if (ext_latcha_en & cpu_we & cpu_stb) begin 
	
		ext_latcha <= cpu_dat_o[23:16];
	
	end

end

assign iospace          =       ((cpu_address >= 26'h300_0000) & (cpu_address < 26'h380_0000));   
assign MEM_DAT_O	= 	cpu_dat_o;
assign cpu_dat_i	=	(use_instrumented & iospace) ?  MEM_DAT_I :  
				ioc_cs ? {ioc_dat_o, ioc_dat_o, ioc_dat_o, ioc_dat_o} :
				ram_cs	? MEM_DAT_I :
				32'h0000_0000;							
					       				
assign ioc_cin[1:0] = {ioc_cout[1], I2C_DIN};
assign ioc_cin[5:2] =  ioc_cout[5:2];

assign DEBUG_LED 		= ~(~ext_latcha[6] & ~ext_latcha[0]);

reg [63:0] 	clk_count = 0	 ;

always @(posedge CLKCPU_I) begin 
	
	clk_count <= clk_count + 63'd1;
       
end
	
endmodule // archimedes_top
