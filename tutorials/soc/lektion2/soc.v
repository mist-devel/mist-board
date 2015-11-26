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
	.pclk  (pixel_clock),
	 
	.cpu_clk  ( pixel_clock      ),
	.cpu_wr   ( copy_in_progress ),
	.cpu_addr ( addr - 14'd1     ),
	.cpu_data ( data             ),

	 
	.hs    (VGA_HS),
	.vs    (VGA_VS),
	.r     (VGA_R),
	.g     (VGA_G),
	.b     (VGA_B)
);

// Einbinden des ROM-Abbildes des Demobildes
image image (
	.clock   ( pixel_clock ),
	.address ( addr ),
	.q       ( data )
);

reg reset = 1'b1;
reg [13:0] addr;
wire [7:0] data;
reg copy_in_progress;

// Zustandsautomat, der nach Power-On das Bild aus dem ROM ins VRAM des
// VGA controllers schreibt. Der Automat läuft auf der fallenden Taktflanke,
// ROM und VRAM auf der steigenden. Die Adresse am VRAM is um 1 erniedrigt, da
// die Daten am ROM synchron (mit einem Takt Verzögerung) anstehen
always @(negedge pixel_clock) begin
	if(reset) begin
		reset <= 1'b0;
		addr <= 14'd0;
		copy_in_progress <= 1'b1;
	end else begin
		if(copy_in_progress) begin
			addr <= addr + 14'd1;
			if(addr == 15999)
				copy_in_progress <= 1'b0;
		end
	end
end
	
// PLL, um aus den 27MHz den VGA-Pixeltakt zu erzeugen
pll pll (
	 .inclk0(CLOCK_27[0]),
	 .c0(pixel_clock)        // 25.175 MHz
);

endmodule
