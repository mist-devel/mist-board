// A simple system-on-a-chip (SoC) for the MiST
// (c) 2015 Till Harbaum
									  
module soc (
   input [1:0] 	CLOCK_27,
	
	// SDRAM interface
	inout [15:0]  	SDRAM_DQ, 		// SDRAM Data bus 16 Bits
	output [12:0] 	SDRAM_A, 		// SDRAM Address bus 13 Bits
	output        	SDRAM_DQML, 	// SDRAM Low-byte Data Mask
	output        	SDRAM_DQMH, 	// SDRAM High-byte Data Mask
	output        	SDRAM_nWE, 		// SDRAM Write Enable
	output       	SDRAM_nCAS, 	// SDRAM Column Address Strobe
	output        	SDRAM_nRAS, 	// SDRAM Row Address Strobe
	output        	SDRAM_nCS, 		// SDRAM Chip Select
	output [1:0]  	SDRAM_BA, 		// SDRAM Bank Address
	output 			SDRAM_CLK, 		// SDRAM Clock
	output        	SDRAM_CKE, 		// SDRAM Clock Enable

	
	// VGA interface
   output 			VGA_HS,
   output 	 		VGA_VS,
   output [5:0] 	VGA_R,
   output [5:0] 	VGA_G,
   output [5:0] 	VGA_B
);

wire pixel_clock;

// include VGA controller
vga vga (
	.pclk     ( pixel_clock      ),
	 
	.cpu_clk  ( cpu_clock        ),
	.cpu_wr   ( !cpu_wr_n && !cpu_addr[15] ),
	.cpu_addr ( cpu_addr[13:0]   ),
	.cpu_data ( cpu_dout         ),

	.hs    (VGA_HS),
	.vs    (VGA_VS),
	.r     (VGA_R),
	.g     (VGA_G),
	.b     (VGA_B)
);

// The CPU is kept in reset for further 256 cyckes after the PLL is
// generating stable clocks to make sure things like the SDRAM have
// some time to initialize
reg [7:0] cpu_reset_cnt = 8'h00;
wire cpu_reset = (cpu_reset_cnt != 255);
always @(posedge cpu_clock) begin
	if(!pll_locked)
		cpu_reset_cnt <= 8'd0;
	else 
		if(cpu_reset_cnt != 255)
			cpu_reset_cnt <= cpu_reset_cnt + 8'd1;
end
			
// SDRAM control signals
wire ram_clock;
assign SDRAM_CKE = 1'b1;

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
   .clk            ( ram_clock                 ),
   .clkref         ( cpu_clock                 ),
   .init           ( !pll_locked               ),

   // cpu/chipset interface
   .din            ( cpu_dout                  ),
   .addr           ( { 10'd0, cpu_addr[14:0] } ),
   .we             ( !cpu_wr_n && cpu_addr[15] ),
   .oe         	 ( !cpu_rd_n && cpu_addr[15] ),
   .dout           ( ram_data_out              )
);
	
// CPU control signals
wire cpu_clock;
wire [15:0] cpu_addr;
wire [7:0] cpu_din;
wire [7:0] cpu_dout;
wire cpu_rd_n;
wire cpu_wr_n;
wire cpu_mreq_n;

// include Z80 CPU
T80s T80s (
	.RESET_n  ( !cpu_reset    ),
	.CLK_n    ( cpu_clock     ),
	.WAIT_n   ( 1'b1          ),
	.INT_n    ( 1'b1          ),
	.NMI_n    ( 1'b1          ),
	.BUSRQ_n  ( 1'b1          ),
	.MREQ_n   ( cpu_mreq_n    ),
	.RD_n     ( cpu_rd_n      ), 
	.WR_n     ( cpu_wr_n      ),
	.A        ( cpu_addr      ),
	.DI       ( cpu_din       ),
	.DO       ( cpu_dout      )
);

// map 32k SDRAM into upper half od the address space (A15=1)
// and 4k ROM into the lower half (A15=0)
wire [7:0] ram_data_out, rom_data_out;
assign cpu_din = cpu_addr[15]?ram_data_out:rom_data_out;

// include 4k program code from boot_rom
boot_rom boot_rom (
	.clock   ( cpu_clock      ),
	.address ( cpu_addr[11:0] ),
	.q       ( rom_data_out   )
);

// derive 4Mhz cpu clock from 32Mhz sdram clock
assign cpu_clock = clk_div[2];
reg [2:0] clk_div;
always @(posedge ram_clock)
	clk_div <= clk_div + 3'd1;
	
// PLL to generate 32Mhz ram clock and 25Mhz video clock from MiSTs
// 27Mhz on board clock
wire pll_locked;
pll pll (
	 .inclk0 ( CLOCK_27[0]   ),
	 .locked ( pll_locked    ),        // PLL is running stable
	 .c0     ( pixel_clock   ),        // 25.175 MHz
	 .c1     ( ram_clock     ),        // 32 MHz
	 .c2     ( SDRAM_CLK     )         // slightly phase shifted 32 MHz
);

endmodule
