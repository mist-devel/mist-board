`timescale 1ns / 1ps
/* sdram_interface.v

 Copyright (c) 2015, Stephen J. Leary
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the <organization> nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
 
module sdram_interface(

	// Inputs
	input	 	DRAM_CLK,
	input 		RESET,
	
	// cpu/chipset interface
	input          	wb_clk,     // 32MHz chipset clock to which sdram state machine is synchonized	
	input	[31:0]	wb_dat_i,	// data input from chipset/cpu
	output  [31:0]	wb_dat_o,	// data output to chipset/cpu
	output			wb_ack, 
	input	[23:0]	wb_adr,		// lower 2 bits are ignored.
	input	[3:0]	wb_sel,		// 
	input	[2:0]	wb_cti,		// cycle type. 
	input			wb_stb, 	//	
	input			wb_cyc, 	// cpu/chipset requests cycle
	input			wb_we,   	// cpu/chipset requests write
	output			wb_ready
);
   

sdram_top uut(
		
	// wishbone interface
	.wb_clk		( wb_clk		),
	.wb_stb		( wb_stb		),
	.wb_cyc		( wb_cyc		),
	.wb_we		( wb_we			),
	.wb_ack		( wb_ack		),
	.wb_sel		( wb_sel		),
	.wb_adr		( wb_adr		),
	.wb_dat_i	( wb_dat_i		),
	.wb_dat_o	( wb_dat_o		),
	.wb_cti	        ( wb_cti		),
			
	// SDRAM Interface
	.sd_clk		( DRAM_CLK		),
	.sd_rst		( RESET			),
	.sd_cke		( DRAM_CKE		),
	.sd_dq   	( DRAM_DQ  		),
	.sd_addr 	( DRAM_A    	),
	.sd_dqm     ( DRAM_DQM 		),
	.sd_cs_n    ( DRAM_CS_N   	),
	.sd_ba      ( DRAM_BA  		),
	.sd_we_n    ( DRAM_WE_N    	),
	.sd_ras_n   ( DRAM_RAS_N   	),
	.sd_cas_n   ( DRAM_CAS_N  	),
	.sd_ready	( wb_ready		)

);

 // SDRAM
wire [15:0] 	DRAM_DQ; // SDRAM Data bus 16 Bits
wire [12:0] 	DRAM_A; // SDRAM Address bus 13 Bits
wire [1:0]		DRAM_DQM; // SDRAM Low-byte Data Mask
wire 			DRAM_WE_N; // SDRAM Write Enable
wire 			DRAM_CAS_N; // SDRAM Column Address Strobe
wire 			DRAM_RAS_N; // SDRAM Row Address Strobe
wire 			DRAM_CS_N; // SDRAM Chip Select
wire [1:0] 		DRAM_BA; // SDRAM Bank Address
wire 			DRAM_CLK; // SDRAM Clock
wire 			DRAM_CKE; // SDRAM Clock Enable
	
mt48lc16m16a2 SDRAM(
	
	.Dq			( DRAM_DQ	), 
	.Addr		( DRAM_A	), 
	.Ba			( DRAM_BA	), 
	.Clk		( DRAM_CLK 	), 
	.Cke		( DRAM_CKE	), 
	.Cs_n		( DRAM_CS_N	), 
	.Ras_n		( DRAM_RAS_N), 
	.Cas_n		( DRAM_CAS_N), 
	.We_n		( DRAM_WE_N	), 
	.Dqm		( DRAM_DQM	)
	
);
	
endmodule

