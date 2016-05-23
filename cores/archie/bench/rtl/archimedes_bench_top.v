`timescale 1ns / 1ps
// archimedes_top_tb.v
//
// Archimedes top testbench
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
module archimedes_top_tb();

	wire		O_HSYNC;
	wire		O_VSYNC;
	
	wire [3:0]	O_VIDEO_R;
	wire [3:0]	O_VIDEO_G;
	wire [3:0]	O_VIDEO_B;

	reg [32:0] 	clk_count2 = 0	 ;
	reg [64:0] 	clk_count = 0	 ;
	reg 		testfail = 0;
 				
// generated clocks
reg clk_32m /* synthesis keep */ ;
reg clk_128m /* synthesis keep */ ;
reg clk_24m /* synthesis keep */ ;
reg clk_25m /* synthesis keep */ ;
reg clk_36m /* synthesis keep */ ;

// data loading 
wire 			loader_active /* synthesis keep */ ;
wire 			loader_we /* synthesis keep */ ;
reg			loader_stb = 1'b0 /* synthesis keep */ ;
(*KEEP="TRUE"*)wire [3:0]	loader_sel /* synthesis keep */ ;
(*KEEP="TRUE"*)wire [23:0]	loader_addr /* synthesis keep */ ;
(*KEEP="TRUE"*)wire [31:0]	loader_data /* synthesis keep */ ;

// the top file should generate the correct clocks for the machine

fakedata_io data_io (
	.rst				( ~ram_ready		),
	.sck				( SPI_SCK 			),
	.ss				( SPI_SS2			),
	.sdi				( SPI_DI				),

	.downloading	( loader_active	),
	.size				(						),

   // ram interface
   .clk     		( clk_32m			),
	.wr    			( loader_we			),
	.a					( loader_addr		),
	.sel				( loader_sel		),
	.d					( loader_data 	)
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


mt48lc16m16a2 RAM(
		
		.Dq				(DRAM_DQ), 
		.Addr				(DRAM_A	), 
		.Ba				(DRAM_BA), 
		.Clk				(DRAM_CLK), 
		.Cke				(DRAM_CKE), 
		.Cs_n				(DRAM_CS_N), 
		.Ras_n			(DRAM_RAS_N), 
		.Cas_n			(DRAM_CAS_N), 
		.We_n				(DRAM_WE_N), 
		.Dqm				(DRAM_DQM)
);
	   
   
wire clk_pix;
wire clk_pix2x;

reg pll_ready = 0;
   
reg core_reset = 0;
   
reg [64:0] CLOCK_CYCLES = 64'd0 /* synthesis preserve */;
wire ram_ready;

// core's raw video 
wire [3:0]	core_r, core_g, core_b;
wire			core_hs, core_vs;


// the top file should generate the correct clocks for the machine

wire			core_ack_in    /* synthesis keep */ ; 
wire			core_stb_out 	/* synthesis keep */ ; 
wire 			core_cyc_out   /* synthesis keep */ ;
wire			core_we_o;
wire [2:0]	core_cti_o;
wire [3:0]	core_sel_o;
wire [31:0] core_data_in, core_data_out;
wire [31:0] ram_data_in;
wire [26:2] core_address_out;

wire	[1:0]	pixbaseclk_select;

wire 			i2c_din, i2c_dout, i2c_clock;

archimedes_top ARCHIMEDES(
	
	.CLKCPU_I	( clk_32m			),
	.CLKPIX2X_I	( clk_pix2x			), // pixel clock x 2
	.CLKPIX_O	( clk_pix			), // pixel clock for OSD
	
	.RESET_I		(~ram_ready | loader_active),
	
	.MEM_ACK_I	( core_ack_in		),
	.MEM_DAT_I	( core_data_in		),
	.MEM_DAT_O	( core_data_out	),
	.MEM_ADDR_O	( core_address_out),
	.MEM_STB_O	( core_stb_out		),
	.MEM_CYC_O	( core_cyc_out		),
	.MEM_SEL_O	( core_sel_o		),
	.MEM_WE_O	( core_we_o			),
	.MEM_CTI_O	( core_cti_o		),
	
	.HSYNC		( core_hs			),
	.VSYNC		( core_vs			),
	.VIDEO_R		( core_r				),
	.VIDEO_G		( core_g				),
	.VIDEO_B		( core_b				),
	
	.I2C_DOUT	( i2c_din			),
	.I2C_DIN		( i2c_dout			),
	.I2C_CLOCK	( i2c_clock			),
	
	.DEBUG_LED	( LED					),
	
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
wire [2:0]	ram_cti  /* synthesis keep */ ;
wire [25:0] ram_address/* synthesis keep */ ;

sdram_top SDRAM(
			
		// wishbone interface
		.wb_clk		( clk_32m		),
		.wb_stb		( ram_stb		),
		.wb_cyc		( ram_cyc		),
		.wb_we		( ram_we			),
		.wb_ack		( ram_ack		),

		.wb_sel		( ram_sel		),
		.wb_adr		( ram_address	),
		.wb_dat_i	( ram_data_in	),
		.wb_dat_o	( core_data_in	),
		.wb_cti		( ram_cti		),
				
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
	.sdaIn	( i2c_din		),
	.sdaOut	( i2c_dout		),
	.scl		( i2c_clock		)
);

	
always @(posedge clk_32m) begin 

	if (loader_we) begin 
	
		loader_stb <= 1'b1;
	
	end else if (ram_ack) begin 
	
		loader_stb <= 1'b0;
		
	end

end

assign ram_cti			= loader_active ? 3'b000 : core_cti_o;
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



assign O_HSYNC = core_hs;
assign O_VSYNC = core_vs;

assign O_VIDEO_R = core_r;
assign O_VIDEO_G = core_g;
assign O_VIDEO_B = core_b;

task VSync;
begin 
wait(~O_VSYNC);
$display("VSYNC: %g", $time);
wait(O_VSYNC);
end 
endtask
   
   
initial begin

   $dumpfile("archimedes_top.vcd");
   $dumpvars(0, archimedes_top_tb);
   $monitor ("%b %b %b %b", pll_ready, i2c_clock, i2c_din, i2c_dout);
   //$readmemh("sram.vmem", ram);
   // Initialize Inputs
   clk_32m = 0;
   clk_24m = 0;
   clk_128m = 0;	
   clk_36m = 0;
   clk_25m = 0;
   
   pll_ready = 0;

   #7764;
   pll_ready = 1;
   #500000;
   
   $writememh("bank0.hex", RAM.Bank0);
   
   
   $finish;
end
	
always 
begin
   #16; clk_32m = ~clk_32m;
end
	
always 
begin
   #10; clk_24m = ~clk_24m;
end

always 
begin
   #9; clk_25m = ~clk_25m;
end

always begin
   #7; clk_36m = ~clk_36m;
end

always begin
   #4; clk_128m = ~clk_128m;
end

always @(posedge clk_32m) begin 
   CLOCK_CYCLES <= CLOCK_CYCLES + 63'd1;
   clk_count <= clk_count + 63'd1;
   clk_count2 <= clk_count2 + 1;
   
   if (clk_count2 >= 32'd0009999) begin 
	
	$display("CLOCK_CYCLES: %d", clk_count);
	clk_count2 <= 64'd0;
   end
   
end

endmodule // archimedes_bench_top
