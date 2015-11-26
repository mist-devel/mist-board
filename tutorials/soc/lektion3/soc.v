// Ein einfaches System-on-a-chip (SOC)
// (c) 2015 Till Harbaum
									  
module soc (
   input [1:0] CLOCK_27,
   output 		SDRAM_nCS,
   output 		VGA_HS,
   output 	 	VGA_VS,
   output [5:0] VGA_R,
   output [5:0] VGA_G,
   output [5:0] VGA_B
);

// Deaktivieren des unbenutzten SDRAMs
assign SDRAM_nCS = 1;

wire pixel_clock;

// Einbinden des VGA-Controllers
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

// CPU bekommt die ersten 256 CPU-Taktzyklen einen Reset
reg [7:0] cpu_reset_cnt = 8'h00;
wire cpu_reset = (cpu_reset_cnt != 255);
always @(posedge cpu_clock)
	if(cpu_reset_cnt != 255)
		cpu_reset_cnt <= cpu_reset_cnt + 8'd1;

// CPU-Steuersignale
wire cpu_clock;
wire [15:0] cpu_addr;
wire [7:0] cpu_din;
wire [7:0] cpu_dout;
wire cpu_rd_n;
wire cpu_wr_n;
wire cpu_mreq_n;

// Einbinden der Z80-CPU
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

// RAM wird in oberer Haelfte des Adressraums gelesen (A15=1),
// ROM in unserer (A15=0)
wire [7:0] ram_data_out, rom_data_out;
assign cpu_din = cpu_addr[15]?ram_data_out:rom_data_out;

// Einbinden des 4k Programmcodes im boot_rom
boot_rom boot_rom (
	.clock   ( cpu_clock      ),
	.address ( cpu_addr[11:0] ),
	.q       ( rom_data_out   )
);

// Einbinden des 4k RAM
ram4k ram4k (
	.clock   ( cpu_clock                 ),
	.address ( cpu_addr[11:0]            ),
	.wren    ( !cpu_wr_n && cpu_addr[15] ),
	.data    ( cpu_dout                  ),
	.q       ( ram_data_out              )
);
	
// PLL, um aus den 27MHz den VGA-Pixeltakt und den CPU-Takt zu erzeugen
pll pll (
	 .inclk0 ( CLOCK_27[0]   ),
	 .c0     ( pixel_clock   ),        // 25.175 MHz
	 .c1     ( cpu_clock     )         // 4 MHz
);

endmodule
