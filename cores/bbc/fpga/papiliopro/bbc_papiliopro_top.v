`timescale 1ns / 1ps
// archimedes_top.v
//
// bbc_papiliopro_top
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

module bbc_papiliopro_top(
		
		input  			SYSCLK,
		
		output			VGA_HS,
		output			VGA_VS,
		
		output  [3:0]	VGA_R,
		output  [3:0]	VGA_G,
		output  [3:0]	VGA_B,
		
		// AUDIO
		output   		AUDIO_L, // sigma-delta DAC output left
		output          AUDIO_R, // sigma-delta DAC output right
		
        // FLASH 
        output          FLASH_CS,  
        output          FLASH_CK,
        output          FLASH_MOSI,
        input           FLASH_MISO, 

        // PS2 
        input           PS2_DAT,
        input           PS2_CLK,
		
		// DRAM 
		/*
		output[12:0]DRAM_A,
		output[1:0]	DRAM_BA,
		output 		DRAM_CAS_N,
		output 		DRAM_CKE,
		output 		DRAM_CLK,
		output 		DRAM_CS_N,
		inout[15:0]	DRAM_DQ,
		output[1:0]	DRAM_DQM,
		output 		DRAM_RAS_N,
		output 		DRAM_WE_N,
		*/
		// RESET 
		
		input       RESET 

    );
	 
// generated clocks
wire clk_32m /* synthesis keep */ ;
wire clk_128m /* synthesis keep */ ;
wire clk_24m /* synthesis keep */ ;

wire pll_ready;

// core's raw video 
wire 			core_r, core_g, core_b, core_hs, core_vs;   
wire			core_clken;

// mist's doubled video 
wire 			video_r, video_g, video_b, video_hs, video_vs;

// core's raw audio 
wire [15:0]	coreaud_l, coreaud_r;

// core's cpu memory access

wire [15:0] core_adr_o;
wire [7:0]  core_dat_i, core_dat_o;
wire        core_we_o;


// memory bus signals.
wire [14:0] vid_adr;
wire [7:0]  vid_data;

wire [15:0] mem_adr_i;
wire [7:0]  mem_dat_i;
wire        mem_we_i;

// data loading 
wire 			loader_active  = 1'b0/* synthesis keep */ ;
wire 			loader_we /* synthesis keep */ ;
reg			    loader_stb = 1'b0 /* synthesis keep */ ;
reg             loader_enough = 1'b0;

wire [3:0]	    loader_sel /* synthesis keep */;
wire [15:0]	    loader_adr /* synthesis keep */;
wire [15:0]	    loader_size /* synthesis keep */ ;
wire [7:0]	    loader_data /* synthesis keep */ ;
          
// user io
wire [1:0] buttons;
wire [1:0] switches;

// the top file should generate the correct clocks for the machine

clockgen CLOCKS(
	.inclk0	(SYSCLK),
	.c0		(clk_32m),
	.c1 	(clk_24m),
	.c2		(clk_128m), 	
    .reset  (RESET),
	.locked	(pll_ready)  // pll locked output
);

osd #(0,100,4) OSD (
   .pclk       ( clk_24m    ),

   .red_in     ( video_r    ),
   .green_in   ( video_g    ),
   .blue_in    ( video_b    ),
	
   .hs_in      ( video_hs   ),
   .vs_in      ( video_vs   ),

   .red_out    ( VGA_R      ),
   .green_out  ( VGA_G      ),
   .blue_out   ( VGA_B      ),
   .hs_out     ( VGA_HS     ),
   .vs_out     ( VGA_VS     )
);

data_io # ( .START_ADDR(26'h8000) )
DATA_IO  (

    .reset          ( ~pll_ready    ),
    
	.spi_clk		( FLASH_CK  	),
	.spi_cs			( FLASH_CS		),
	.spi_mosi		( FLASH_MOSI	),
	.spi_miso		( FLASH_MISO    ),

	//.downloading	( loader_active	),
    .enough         ( loader_enough ),
	.size			( loader_size	),
	
    // ram interface
    .clk     		( clk_32m		),
    .clken          ( core_clken    ),
    .wr    			( loader_we		),
	.a				( loader_adr	),
	.sel			( loader_sel	),
	.d				( loader_data 	)
);


bbc BBC(
	
    .RESET_I	( ~pll_ready | loader_active  ),
        
	.CLK32M_I	( clk_32m		),
	.CLK24M_I	( clk_24m		),
	
	.HSYNC		( core_hs		),
	.VSYNC		( core_vs		),
	.VIDEO_CLKEN ( core_clken	),
	
    .VIDEO_R	( core_r		),
	.VIDEO_G	( core_g		),
	.VIDEO_B	( core_b		),
    
    .MEM_ADR    ( core_adr_o    ),
    .MEM_WE     ( core_we_o     ),
    .MEM_DO     ( core_dat_o    ),
    .MEM_DI     ( core_dat_i    ),
    
    .VID_ADR    ( vid_adr       ),
    .VID_DI     ( vid_data      ),
	
	.PS2_CLK	( PS2_CLK		),
	.PS2_DAT	( PS2_DAT		),
	
	.AUDIO_L	( coreaud_l		),
	.AUDIO_R	( coreaud_r		)
	
);

mainram MEMORY(
	.clka		( clk_32m	    ),
    .ena        ( 1'b1          ),
	.wea 		( mem_we_i		),
	.addra		( mem_adr_i	    ),
	.douta 		( core_dat_i	),
	.dina		( mem_dat_i		),
	
    .clkb		( clk_32m	    ),
    .enb        ( 1'b1          ),
	.web 		( 1'b0	    	),
	.dinb		( 8'd0		    ),
	.addrb		( vid_adr       ),
	.doutb		( vid_data		)
);


audio AUDIO (

	.clk		    ( clk_24m		),
	.rst			( ~pll_ready	),
	.audio_data_l 	( coreaud_l		),
	.audio_data_r 	( coreaud_r		),
	.audio_l        ( AUDIO_L		),
	.audio_r		( AUDIO_R		)
    
);

scandoubler SCANDOUBLE(

	.clk_16		( clk_32m		),
	.clk_16_en	( core_clken	),
	
	.vs_in	    ( core_vs		),
	.hs_in	    ( core_hs		),
	
	.r_in		( core_r		),
	.g_in		( core_g		),
	.b_in		( core_b		),
	
	.clk		( clk_32m		),
	
	.vs_out	    ( video_vs		),
	.hs_out	    ( video_hs		),
	
	.r_out		( video_r		),
	.g_out		( video_g		),
	.b_out		( video_b		)

);


initial begin 

    loader_enough <= 1'b0;

end


always @(posedge clk_32m) begin 

	/*if (loader_we) begin 
	
		loader_stb <= 1'b1;
	
	end else if (ram_ack) begin 
	
		loader_stb <= 1'b0;
		
	end*/
    
    if ((loader_active) && (loader_size >= 16'h8000)) begin 
    
        loader_enough <= 1'b1;
        
    end

end


assign mem_we_i			= loader_active ? loader_we		: core_we_o;
assign mem_adr_i        = loader_active ? loader_adr    : core_adr_o;
assign mem_dat_i  		= loader_active ? loader_data   : core_dat_o;

//assign ram_sel			= loader_active ? loader_sel : core_sel_o;
//assign ram_stb			= loader_active ? loader_stb : core_stb_out;
//assign ram_cyc			= loader_active ? loader_stb : core_stb_out;
//assign core_ack_in  	= loader_active ? 1'b0 : ram_ack;

assign DRAM_CLK = clk_128m;

endmodule // bbc_papiliopro_top
