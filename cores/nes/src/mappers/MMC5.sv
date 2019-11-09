// MMC5 Mapper aka "WTF were they thinking?!"

module MMC5(
	input        clk,         // System clock
	input        ce,          // M2 ~cpu_clk
	input        enable,      // Mapper enabled
	input [31:0] flags,       // Cart flags
	input [15:0] prg_ain,     // prg address
	inout [21:0] prg_aout_b,  // prg address out
	input        prg_read,    // prg read
	input        prg_write,   // prg write
	input  [7:0] prg_din,     // prg data in
	inout  [7:0] prg_dout_b,  // prg data out
	inout        prg_allow_b, // Enable access to memory for the specified operation.
	input [13:0] chr_ain,     // chr address in
	inout [21:0] chr_aout_b,  // chr address out
	input        chr_read,    // chr ram read
	inout        chr_allow_b, // chr allow write
	inout        vram_a10_b,  // Value for A10 address line
	inout        vram_ce_b,   // True if the address should be routed to the internal 2kB VRAM.
	inout        irq_b,       // IRQ
	input [15:0] audio_in,    // Inverted audio from APU
	inout [15:0] audio_b,     // Mixed audio output
	inout [15:0] flags_out_b, // flags {0, 0, 0, 0, 0, prg_conflict, prg_bus_write, has_chr_dout}
	// Special ports
	input  [7:0] audio_dout,
	input  [7:0] chr_din,     // CHR Data in
	input        chr_write,   // CHR Write
	inout  [7:0] chr_dout_b,  // chr data (non standard)
	input        ppu_ce,
	input [19:0] ppuflags
);

assign prg_aout_b   = enable ? prg_aout : 22'hZ;
assign prg_dout_b   = enable ? prg_dout : 8'hZ;
assign prg_allow_b  = enable ? prg_allow : 1'hZ;
assign chr_aout_b   = enable ? chr_aout : 22'hZ;
assign chr_dout_b   = enable ? chr_dout : 8'hZ;
assign chr_allow_b  = enable ? chr_allow : 1'hZ;
assign vram_a10_b   = enable ? vram_a10 : 1'hZ;
assign vram_ce_b    = enable ? vram_ce : 1'hZ;
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? audio : 16'hZ;

wire [21:0] prg_aout;
reg [21:0] chr_aout;
wire prg_allow;
wire chr_allow;
wire vram_a10;
reg [7:0] chr_dout, prg_dout;
wire vram_ce;
wire [15:0] flags_out = {14'h0, prg_bus_write, has_chr_dout};
wire irq;
wire prg_bus_write, has_chr_dout;
wire [15:0] audio = audio_in;

reg [1:0] prg_mode, chr_mode;
reg prg_protect_1, prg_protect_2;
reg [1:0] extended_ram_mode;
reg [7:0] mirroring;
reg [7:0] fill_tile;
reg [1:0] fill_attr;
reg [2:0] prg_ram_bank;
reg [7:0] prg_bank_0, prg_bank_1, prg_bank_2;
reg [6:0] prg_bank_3;
reg [9:0] chr_bank_0, chr_bank_1, chr_bank_2, chr_bank_3,
	chr_bank_4, chr_bank_5, chr_bank_6, chr_bank_7,
	chr_bank_8, chr_bank_9, chr_bank_a, chr_bank_b;
reg [1:0] upper_chr_bank_bits;
reg chr_last; // Which CHR set was written to last?

reg [4:0] vsplit_startstop;
reg vsplit_enable, vsplit_side;
reg [7:0] vsplit_scroll, vsplit_bank;

reg [7:0] irq_scanline;
reg irq_enable;
reg irq_pending;

reg [7:0] multiplier_1;
reg [7:0] multiplier_2;
wire [15:0] multiply_result = multiplier_1 * multiplier_2;

reg [7:0] expansion_ram[0:1023]; // Block RAM, otherwise we need to time multiplex..
reg [7:0] last_read_ram;
reg [7:0] last_read_exattr;
reg [7:0] last_read_vram;
reg last_chr_read;

// unpack ppu flags
//reg display_enable;
//wire ppu_in_frame = ppuflags[0] & display_enable;
wire ppu_in_frame = ppuflags[0];
reg old_ppu_sprite16;
wire ppu_sprite16 = ppuflags[1];
//reg ppu_sprite16;
wire [8:0] ppu_cycle = ppuflags[10:2];
wire [8:0] ppu_scanline = ppuflags[19:11];

// Handle IO register writes
always @(posedge clk) begin
	if (ce) begin
	if (prg_write && prg_ain[15:10] == 6'b010100) begin // $5000-$53FF
		//if (prg_ain <= 16'h5113) $write("%X <= %X (%d)\n", prg_ain, prg_din, ppu_scanline);
		casez(prg_ain[9:0])
			10'h100: prg_mode <= prg_din[1:0];
			10'h101: chr_mode <= prg_din[1:0];
			10'h102: prg_protect_1 <= (prg_din[1:0] == 2'b10);
			10'h103: prg_protect_2 <= (prg_din[1:0] == 2'b01);
			10'h104: extended_ram_mode <= prg_din[1:0];
			10'h105: mirroring <= prg_din;
			10'h106: fill_tile <= prg_din;
			10'h107: fill_attr <= prg_din[1:0];
			10'h113: prg_ram_bank <= prg_din[2:0];
			10'h114: prg_bank_0 <= prg_din;
			10'h115: prg_bank_1 <= prg_din;
			10'h116: prg_bank_2 <= prg_din;
			10'h117: prg_bank_3 <= prg_din[6:0];
			10'h120: chr_bank_0 <= {upper_chr_bank_bits, prg_din};
			10'h121: chr_bank_1 <= {upper_chr_bank_bits, prg_din};
			10'h122: chr_bank_2 <= {upper_chr_bank_bits, prg_din};
			10'h123: chr_bank_3 <= {upper_chr_bank_bits, prg_din};
			10'h124: chr_bank_4 <= {upper_chr_bank_bits, prg_din};
			10'h125: chr_bank_5 <= {upper_chr_bank_bits, prg_din};
			10'h126: chr_bank_6 <= {upper_chr_bank_bits, prg_din};
			10'h127: chr_bank_7 <= {upper_chr_bank_bits, prg_din};
			10'h128: chr_bank_8  <= {upper_chr_bank_bits, prg_din};
			10'h129: chr_bank_9  <= {upper_chr_bank_bits, prg_din};
			10'h12a: chr_bank_a  <= {upper_chr_bank_bits, prg_din};
			10'h12b: chr_bank_b  <= {upper_chr_bank_bits, prg_din};
			10'h130: upper_chr_bank_bits <= prg_din[1:0];
			10'h200: {vsplit_enable, vsplit_side, vsplit_startstop} <= {prg_din[7:6], prg_din[4:0]};
			10'h201: vsplit_scroll <= prg_din;
			10'h202: vsplit_bank <= prg_din;
			10'h203: irq_scanline <= prg_din;
			10'h204: irq_enable <= prg_din[7];
			10'h205: multiplier_1 <= prg_din;
			10'h206: multiplier_2 <= prg_din;
			default: begin end
		endcase

		// Remember which set of CHR was written to last.
		// chr_last is set to 0 when changing bank with sprites set to 8x8
		if (prg_ain[9:4] == 6'b010010) //(prg_ain[9:0] >= 10'h120 && prg_ain[9:0] < 10'h130)
			chr_last <= prg_ain[3] & ppu_sprite16;

	end
		//Not currently passing prg_write when ppu_cs
		//if (prg_write && prg_ain == 16'h2000) begin // $2000
		//  ppu_sprite16 <= (prg_din[5]);
		//end
		//if (prg_write && prg_ain == 16'h2001) begin // $2001
		//  display_enable <= (prg_din[4:3] != 2'b0);
		//end

		// chr_last is set to 0 when changing sprite size to 8x8
		old_ppu_sprite16 <= ppu_sprite16;
		if (old_ppu_sprite16 != ppu_sprite16 && ~ppu_sprite16)
			chr_last <= 0;
	end

	// Mode 0/1 - Not readable (returns open bus), can only be written while the PPU is rendering (otherwise, 0 is written)
	// Mode 2 - Readable and writable
	// Mode 3 - Read-only
	if (extended_ram_mode != 3) begin
		if (ppu_ce && !ppu_in_frame && !extended_ram_mode[1] && chr_write && (mirrbits == 2) && chr_ain[13])
			expansion_ram[chr_ain[9:0]] <= chr_din;
		else if (ce && prg_write && prg_ain[15:10] == 6'b010111) // $5C00-$5FFF
			expansion_ram[prg_ain[9:0]] <= (extended_ram_mode[1] || ppu_in_frame) ? prg_din : 8'd0;
	end

	if (~enable) begin
		prg_bank_3 <= 7'h7F;
		prg_mode <= 3;
	end
end

// Read from MMC5
always @* begin
	prg_bus_write = 1'b1;
	if (prg_ain[15:10] == 6'b010111 && extended_ram_mode[1]) begin
		prg_dout = last_read_ram;
	end else if (prg_ain == 16'h5204) begin
		prg_dout = {irq_pending, ppu_in_frame, 6'b111111};
	end else if (prg_ain == 16'h5205) begin
		prg_dout = multiply_result[7:0];
	end else if (prg_ain == 16'h5206) begin
		prg_dout = multiply_result[15:8];
	end else if (prg_ain == 16'h5015) begin
		prg_dout = {6'h00, audio_dout[1:0]};
	// TODO: 5010
	end else begin
		prg_dout = 8'hFF; // By default open bus.
		prg_bus_write = 0;
	end
end

// Determine IRQ handling
reg last_scanline;
wire irq_trig = (irq_scanline != 0 && irq_scanline < 240 && ppu_scanline == {1'b0, irq_scanline});
always @(posedge clk) if (ce || ppu_ce) begin
	last_scanline <= ppu_scanline[0];

	if ((ce && prg_read && prg_ain == 16'h5204) || ~ppu_in_frame)
		irq_pending <= 0;
	else if (ppu_scanline[0] != last_scanline && irq_trig)
		irq_pending <= 1;
end

assign irq = irq_pending && irq_enable;

// Determine if vertical split is active.
reg [5:0] cur_tile;     // Current tile the PPU is fetching
reg [5:0] new_cur_tile; // New value for |cur_tile|
reg [7:0] vscroll;      // Current y scroll for the split region
reg last_in_split_area, in_split_area;

// Compute if we're in the split area right now by counting PPU tiles.
always @* begin
	new_cur_tile = (ppu_cycle[8:3] == 40) ? 6'd0 : (cur_tile + 6'b1);
	in_split_area = last_in_split_area;
	if (ppu_cycle[2:0] == 0 && ppu_cycle < 336) begin
	if (new_cur_tile == 0)
		in_split_area = !vsplit_side;
	else if (new_cur_tile == {1'b0, vsplit_startstop})
		in_split_area = vsplit_side;
	else if (new_cur_tile == 34)
		in_split_area = 0;
	end
end

always @(posedge clk) if (ppu_ce) begin
	last_in_split_area <= in_split_area;
	if (ppu_cycle[2:0] == 0 && ppu_cycle < 336)
		cur_tile <= new_cur_tile;
end

// Keep track of scroll
always @(posedge clk) if (ppu_ce) begin
	if (ppu_cycle == 319)
		vscroll <= ppu_scanline[8] ? vsplit_scroll :
		(vscroll == 239) ? 8'b0 : vscroll + 8'b1;
end

// Mirroring bits
// %00 = NES internal NTA
// %01 = NES internal NTB
// %10 = use ExRAM as NT
// %11 = Fill Mode
wire [1:0] mirrbits = (chr_ain[11:10] == 0) ? mirroring[1:0] :
						(chr_ain[11:10] == 1) ? mirroring[3:2] :
						(chr_ain[11:10] == 2) ? mirroring[5:4] :
												mirroring[7:6];

// Compute the new overriden nametable/attr address the split will read from instead
// when the VSplit is active.
// Cycle 0, 1 = nametable
// Cycle 2, 3 = attribute
// Named it loopy so I can copypaste from PPU code :)
wire [9:0] loopy = {vscroll[7:3], cur_tile[4:0]};
wire [9:0] split_addr = (ppu_cycle[1] == 0) ? loopy :                            // name table
												{4'b1111, loopy[9:7], loopy[4:2]}; // attribute table
// Selects 2 out of the attr bits read from exram.
wire [1:0] split_attr = (!loopy[1] && !loopy[6]) ? last_read_ram[1:0] :
						( loopy[1] && !loopy[6]) ? last_read_ram[3:2] :
						(!loopy[1] &&  loopy[6]) ? last_read_ram[5:4] :
													last_read_ram[7:6];
// If splitting is active or not
wire insplit = in_split_area && vsplit_enable;

// Currently reading the attribute byte?
wire exattr_read = (extended_ram_mode == 1) && (ppu_cycle[2:1]==1) && ppu_in_frame;

// If the current chr read should be redirected from |chr_dout| instead.
assign has_chr_dout = chr_ain[13] && (mirrbits[1] || insplit || exattr_read);
wire [1:0] override_attr = insplit ? split_attr : (extended_ram_mode == 1) ? last_read_exattr[7:6] : fill_attr;
always @* begin
	if (ppu_in_frame) begin
		if (ppu_cycle[1] == 0) begin
			// Name table fetch
			if (insplit || mirrbits[0] == 0)
				chr_dout = (extended_ram_mode[1] ? 8'b0 : last_read_ram);
			else begin
				// Inserting Filltile
				chr_dout = fill_tile;
			end
		end else begin
			// Attribute table fetch
			if (!insplit && !exattr_read && mirrbits[0] == 0)
				chr_dout = (extended_ram_mode[1] ? 8'b0 : last_read_ram);
			else
				chr_dout = {override_attr, override_attr, override_attr, override_attr};
		end
	end else begin
		chr_dout = last_read_vram;
	end
end

// Handle reading from the expansion ram.
// 0 - Use as extra nametable (possibly for split mode)
// 1 - Use as extended attribute data OR an extra nametable
// 2 - Use as ordinary RAM
// 3 - Use as ordinary RAM, write protected
wire [9:0] exram_read_addr = extended_ram_mode[1] ? prg_ain[9:0] : insplit ? split_addr : chr_ain[9:0];

always @(posedge clk) begin
	last_read_ram <= expansion_ram[exram_read_addr];

	if ((ppu_cycle[2] == 0) && (ppu_cycle[1] == 0) && ppu_in_frame) begin
		last_read_exattr <= last_read_ram;
	end

	last_chr_read <= chr_read;

	if (!chr_read && last_chr_read)
		last_read_vram <= extended_ram_mode[1] ? 8'b0 : last_read_ram;
end

// Compute PRG address to read from.
reg [7:0] prgsel;
always @* begin
	casez({prg_mode, prg_ain[15:13]})
		5'b??_0??: prgsel = {5'b0xxxx, prg_ram_bank};                // $6000-$7FFF all modes
		5'b00_1??: prgsel = {1'b1, prg_bank_3[6:2], prg_ain[14:13]}; // $8000-$FFFF mode 0, 32kB (prg_bank_3, skip 2 bits)

		5'b01_10?: prgsel = {      prg_bank_1[7:1], prg_ain[13]};    // $8000-$BFFF mode 1, 16kB (prg_bank_1, skip 1 bit)
		5'b01_11?: prgsel = {1'b1, prg_bank_3[6:1], prg_ain[13]};    // $C000-$FFFF mode 1, 16kB (prg_bank_3, skip 1 bit)

		5'b10_10?: prgsel = {      prg_bank_1[7:1], prg_ain[13]};    // $8000-$BFFF mode 2, 16kB (prg_bank_1, skip 1 bit)
		5'b10_110: prgsel = {      prg_bank_2};                      // $C000-$DFFF mode 2, 8kB  (prg_bank_2)
		5'b10_111: prgsel = {1'b1, prg_bank_3};                      // $E000-$FFFF mode 2, 8kB  (prg_bank_3)

		5'b11_100: prgsel = {      prg_bank_0};                      // $8000-$9FFF mode 3, 8kB (prg_bank_0)
		5'b11_101: prgsel = {      prg_bank_1};                      // $A000-$BFFF mode 3, 8kB (prg_bank_1)
		5'b11_110: prgsel = {      prg_bank_2};                      // $C000-$DFFF mode 3, 8kB (prg_bank_2)
		5'b11_111: prgsel = {1'b1, prg_bank_3};                      // $E000-$FFFF mode 3, 8kB (prg_bank_3)
	endcase
	//Original
	//prgsel[7] = !prgsel[7]; // 0 means RAM, doh.

	//Done below
	//if (prgsel[7])
	//  prgsel[7] = 0;  //ROM
	//else
	//  // Limit to 64k RAM.
	//  prgsel[7:3] = 5'b1_1100;  //RAM location for saves
end

assign prg_aout = {prgsel[7] ? {2'b00, prgsel[6:0]} : {6'b11_1100, prgsel[2:0]}, prg_ain[12:0]};    // 8kB banks

// Registers $5120-$5127 apply to sprite graphics and $5128-$512B for background graphics, but ONLY when 8x16 sprites are enabled.
// Otherwise, the last set of registers written to (either $5120-$5127 or $5128-$512B) will be used for all graphics.
// 0 if using $5120-$5127, 1 if using $5128-$512F

wire is_bg_fetch = !(ppu_cycle[8] && !ppu_cycle[6]);
wire chrset = (ppu_sprite16 && ppu_in_frame) ? is_bg_fetch : chr_last;
reg [9:0] chrsel;

always @* begin
	casez({chr_mode, chr_ain[12:10], chrset})
		6'b00_???_0: chrsel = {chr_bank_7[6:0], chr_ain[12:10]}; // $0000-$1FFF mode 0, 8 kB
		6'b00_???_1: chrsel = {chr_bank_b[6:0], chr_ain[12:10]}; // $0000-$1FFF mode 0, 8 kB

		6'b01_0??_0: chrsel = {chr_bank_3[7:0], chr_ain[11:10]}; // $0000-$0FFF mode 1, 4 kB
		6'b01_1??_0: chrsel = {chr_bank_7[7:0], chr_ain[11:10]}; // $1000-$1FFF mode 1, 4 kB
		6'b01_???_1: chrsel = {chr_bank_b[7:0], chr_ain[11:10]}; // $0000-$0FFF mode 1, 4 kB

		6'b10_00?_0: chrsel = {chr_bank_1[8:0], chr_ain[10]};    // $0000-$07FF mode 2, 2 kB
		6'b10_01?_0: chrsel = {chr_bank_3[8:0], chr_ain[10]};    // $0800-$0FFF mode 2, 2 kB
		6'b10_10?_0: chrsel = {chr_bank_5[8:0], chr_ain[10]};    // $1000-$17FF mode 2, 2 kB
		6'b10_11?_0: chrsel = {chr_bank_7[8:0], chr_ain[10]};    // $1800-$1FFF mode 2, 2 kB
		6'b10_?0?_1: chrsel = {chr_bank_9[8:0], chr_ain[10]};    // $0000-$07FF mode 2, 2 kB
		6'b10_?1?_1: chrsel = {chr_bank_b[8:0], chr_ain[10]};    // $0800-$0FFF mode 2, 2 kB

		6'b11_000_0: chrsel = chr_bank_0;                        // $0000-$03FF mode 3, 1 kB
		6'b11_001_0: chrsel = chr_bank_1;                        // $0400-$07FF mode 3, 1 kB
		6'b11_010_0: chrsel = chr_bank_2;                        // $0800-$0BFF mode 3, 1 kB
		6'b11_011_0: chrsel = chr_bank_3;                        // $0C00-$0FFF mode 3, 1 kB
		6'b11_100_0: chrsel = chr_bank_4;                        // $1000-$13FF mode 3, 1 kB
		6'b11_101_0: chrsel = chr_bank_5;                        // $1400-$17FF mode 3, 1 kB
		6'b11_110_0: chrsel = chr_bank_6;                        // $1800-$1BFF mode 3, 1 kB
		6'b11_111_0: chrsel = chr_bank_7;                        // $1C00-$1FFF mode 3, 1 kB
		6'b11_?00_1: chrsel = chr_bank_8;                        // $0000-$03FF mode 3, 1 kB
		6'b11_?01_1: chrsel = chr_bank_9;                        // $0400-$07FF mode 3, 1 kB
		6'b11_?10_1: chrsel = chr_bank_a;                        // $0800-$0BFF mode 3, 1 kB
		6'b11_?11_1: chrsel = chr_bank_b;                        // $0C00-$0FFF mode 3, 1 kB
	endcase

	chr_aout = {2'b10, chrsel, chr_ain[9:0]};    // 1kB banks

	// Override |chr_aout| if we're in a vertical split.
	if (ppu_in_frame && insplit) begin
		//$write("In vertical split!\n");
//		chr_aout = {2'b10, vsplit_bank, chr_ain[11:3], vscroll[2:0]}; // SL
		chr_aout = {2'b10, vsplit_bank, chr_ain[11:3], chr_ain[2:0]}; // CL
	end else if (ppu_in_frame && extended_ram_mode == 1 && is_bg_fetch && (ppu_cycle[2:1]!=0)) begin
		//$write("In exram thingy!\n");
		// Extended attribute mode. Replace the page with the page from exram.
		chr_aout = {2'b10, upper_chr_bank_bits, last_read_exattr[5:0], chr_ain[11:0]};
	end

end

// The a10 VRAM address line. (Used for mirroring)
assign vram_a10 = mirrbits[0];
assign vram_ce = chr_ain[13] && !mirrbits[1];

// Writing to RAM is enabled only when the protect bits say so.
wire prg_ram_we = prg_protect_1 && prg_protect_2;
assign prg_allow = (prg_ain >= 16'h6000) && (!prg_write || ((!prgsel[7]) && prg_ram_we));

// MMC5 boards typically have no CHR RAM.
assign chr_allow = flags[15];

endmodule

module mmc5_mixed (
	input         clk,
	input         ce,    // Negedge M2 (aka CPU ce)
	input         enable,
	input         wren,
	input         rden,
	input  [15:0] addr_in,
	input   [7:0] data_in,
	output  [7:0] data_out,
	input  [15:0] audio_in,    // Inverted audio from APU
	output [15:0] audio_out
);

// NOTE: The apu volume is 100% of MMC5 and the polarity is reversed.
wire [16:0] audio_o = audio + audio_in;
wire [15:0] audio;
assign audio_out = audio_o[16:1];

wire apu_cs = (addr_in[15:5]==11'b0101_0000_000) && (addr_in[3]==0);
wire DmaReq;          // 1 when DMC wants DMA
wire [15:0] DmaAddr;  // Address DMC wants to read
reg odd_or_even;
wire apu_irq;         // TODO: IRQ asserted

always @(posedge clk) 
if (~enable)
	odd_or_even <= 0;
else if (ce) 
	odd_or_even <= ~odd_or_even;


APU mmc5apu(
	.MMC5           (1),
	.clk            (clk),
	.ce             (ce),
	.reset          (~enable),
	.ADDR           (addr_in[4:0]),
	.DIN            (data_in),
	.DOUT           (data_out),
	.MW             (wren && apu_cs),
	.MR             (rden && apu_cs),
	.audio_channels (5'b10011),
	.Sample         (audio),
	.DmaReq         (DmaReq),
	.DmaAck         (1),
	.DmaAddr        (DmaAddr),
	.DmaData        (0),
	.odd_or_even    (odd_or_even),
	.IRQ            (apu_irq)
);

endmodule
