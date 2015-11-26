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

vga vga (
	 .pclk  (pixel_clock),
	 .hs    (VGA_HS),
	 .vs    (VGA_VS),
	 .r     (VGA_R),
	 .g     (VGA_G),
	 .b     (VGA_B)
);
					
// PLL, um aus den 27MHz den VGA-Pixeltakt zu erzeugen
pll pll (
	 .inclk0(CLOCK_27[0]),
	 .c0(pixel_clock)        // 25.175 MHz
);

endmodule
