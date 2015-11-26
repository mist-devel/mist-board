// A simple system-on-a-chip (SoC) for the MiST
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

// de-activate unused SDRAM
assign SDRAM_nCS = 1;

wire pixel_clock;

// include VGA controller
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

// include ROM containing the demo image
image image (
	.clock   ( pixel_clock ),
	.address ( addr ),
	.q       ( data )
);

reg reset = 1'b1;
reg [13:0] addr;
wire [7:0] data;
reg copy_in_progress;

// A small state machine which copies image data from ROM into VRAM
// of the video controller. The state machines runs directly after power
// on and works on the falling clock edge since ROM and VRAM operate
// in the rising edge. The VRAM address is dereased by 1 since the ROM
// delivers it's data with one clock delay due to its internal registers.
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
	
// A PLL to derive the VGA pixel clocl from the MiSTs 27MHz
pll pll (
	 .inclk0(CLOCK_27[0]),
	 .c0(pixel_clock)        // 25.175 MHz
);

endmodule
