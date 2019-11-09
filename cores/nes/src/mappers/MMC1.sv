// MMC1 mapper chip. Maps prg or chr addresses into a linear address.

// If vram_ce is set, {vram_a10, chr_aout[9:0]} are used to access the NES internal VRAM instead.
module MMC1(
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
	inout [15:0] flags_out_b  // flags {0, 0, 0, 0, 0, prg_conflict, prg_bus_write, has_chr_dout}
);

assign prg_aout_b   = enable ? prg_aout : 22'hZ;
assign prg_dout_b   = enable ? 8'hFF : 8'hZ;
assign prg_allow_b  = enable ? prg_allow : 1'hZ;
assign chr_aout_b   = enable ? chr_aout : 22'hZ;
assign chr_allow_b  = enable ? chr_allow : 1'hZ;
assign vram_a10_b   = enable ? vram_a10 : 1'hZ;
assign vram_ce_b    = enable ? vram_ce : 1'hZ;
assign irq_b        = enable ? 1'b0 : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? {1'b0, audio_in[15:1]} : 16'hZ;

wire [21:0] prg_aout, chr_aout;
wire prg_allow;
wire chr_allow;
wire vram_a10;
wire vram_ce;
wire mapper171 = (flags[7:0] == 171); //Mapper 171 has hardwired mirroring
reg [15:0] flags_out = 0;

reg [4:0] shift;

// CPPMM
// |||||
// |||++- Mirroring (0: one-screen, lower bank; 1: one-screen, upper bank;
// |||               2: vertical; 3: horizontal)
// |++--- PRG ROM bank mode (0, 1: switch 32 KB at $8000, ignoring low bit of bank number;
// |                         2: fix first bank at $8000 and switch 16 KB bank at $C000;
// |                         3: fix last bank at $C000 and switch 16 KB bank at $8000)
// +----- CHR ROM bank mode (0: switch 8 KB at a time; 1: switch two separate 4 KB banks)
reg [4:0] control;

// CCCCC
// |||||
// +++++- Select 4 KB or 8 KB CHR bank at PPU $0000 (low bit ignored in 8 KB mode)
reg [4:0] chr_bank_0;

// CCCCC
// |||||
// +++++- Select 4 KB CHR bank at PPU $1000 (ignored in 8 KB mode)
reg [4:0] chr_bank_1;

// RPPPP
// |||||
// |++++- Select 16 KB PRG ROM bank (low bit ignored in 32 KB mode)
// +----- PRG RAM chip enable (0: enabled; 1: disabled; ignored on MMC1A)
reg [4:0] prg_bank;

reg delay_ctrl;	// used to prevent fast-write to the control register

wire [2:0] prg_size = flags[10:8];

// Update shift register
always @(posedge clk) 
	if (~enable) begin
		shift <= 5'b10000;
		control <= 5'b0_11_00;
		chr_bank_0 <= 0;
		chr_bank_1 <= 0;
		prg_bank <= 5'b00000;
		delay_ctrl <= 0;
	end else if (ce) begin
		if (!prg_write)
			delay_ctrl <= 1'b0;
		if (prg_write && prg_ain[15] && !delay_ctrl) begin
			delay_ctrl <= 1'b1;
			if (prg_din[7]) begin
				shift <= 5'b10000;
				control <= control | 5'b0_11_00;
			end else begin
				if (shift[0]) begin
					casez(prg_ain[14:13])
						0: control    <= {prg_din[0], shift[4:1]};
						1: chr_bank_0 <= {prg_din[0], shift[4:1]};
						2: chr_bank_1 <= {prg_din[0], shift[4:1]};
						3: prg_bank   <= {prg_din[0], shift[4:1]};
					endcase
					shift <= 5'b10000;
				end else begin
					shift <= {prg_din[0], shift[4:1]};
				end
			end
		end
	end

// The PRG bank to load. Each increment here is 16kb. So valid values are 0..15.
// prg_ain[14] selects bank0 ($8000) or bank1 ($C000)
reg [3:0] prgsel;
always @* begin
	casez({control[3:2], prg_ain[14]})
		3'b0?_?: prgsel = {prg_bank[3:1], prg_ain[14]}; // Swap 32Kb
		3'b10_0: prgsel = 4'b0000;                      // Swap 16Kb at $C000 with access at $8000, so select page 0 (hardcoded)
		3'b10_1: prgsel = prg_bank[3:0];                // Swap 16Kb at $C000 with $C000 access, so select page based on prg_bank (register 3)
		3'b11_0: prgsel = prg_bank[3:0];                // Swap 16Kb at $8000 with $8000 access, so select page based on prg_bank (register 3)
		3'b11_1: prgsel = 4'b1111;                      // Swap 16Kb at $8000 with $C000 access, so select last page (hardcoded)
	endcase
end

// The CHR bank to load. Each increment here is 4 kb. So valid values are 0..31.
reg [4:0] chrsel;
always @* begin
	casez({control[4], chr_ain[12]})
		2'b0_?: chrsel = {chr_bank_0[4:1], chr_ain[12]};
		2'b1_0: chrsel = chr_bank_0;
		2'b1_1: chrsel = chr_bank_1;
	endcase
end

assign chr_aout = {5'b100_00, chrsel, chr_ain[11:0]};
wire [21:0] prg_aout_tmp = prg_size == 5 ? {3'b000, chrsel[4], prgsel, prg_ain[13:0]} // for large PRG ROM, CHR A16 selects the 256KB PRG bank
	: {4'b00_00, prgsel, prg_ain[13:0]};

// The a10 VRAM address line. (Used for mirroring)
reg vram_a10_t;
always @* begin
	casez(mapper171 ? 2'b10 : control[1:0])   //if mapper 171 then set to vertical mirroring, else do normal MMC1 mirroring selection.
		2'b00: vram_a10_t = 0;             // One screen, lower bank
		2'b01: vram_a10_t = 1;             // One screen, upper bank
		2'b10: vram_a10_t = chr_ain[10];   // One screen, vertical
		2'b11: vram_a10_t = chr_ain[11];   // One screen, horizontal
	endcase
end

assign vram_a10 = vram_a10_t;
assign vram_ce = chr_ain[13];

wire prg_is_ram = prg_ain >= 'h6000 && prg_ain < 'h8000;
assign prg_allow = prg_ain[15] && !prg_write || prg_is_ram;
wire [21:0] prg_ram = {9'b11_1100_000, prg_ain[12:0]};

assign prg_aout = prg_is_ram ? prg_ram : prg_aout_tmp;
assign chr_allow = flags[15];

endmodule


// #105 - NES-EVENT. Retrofits an MMC1 with lots of extra logic.
module NesEvent(
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
	inout [15:0] flags_out_b  // flags {0, 0, 0, 0, 0, prg_conflict, prg_bus_write, has_chr_dout}
);

assign prg_aout_b   = enable ? prg_aout : 22'hZ;
assign chr_aout_b   = enable ? chr_aout : 22'hZ;
assign irq_b        = enable ? irq : 1'hZ;

wire [21:0] chr_aout;
reg [21:0] prg_aout;
wire [21:0] mmc1_chr_addr;
wire [3:0] mmc1_chr = mmc1_chr_addr[16:13]; // Upper 4 CHR output control bits from MMC chip
wire [21:0] mmc1_aout;                 // PRG output address from MMC chip
wire irq;

MMC1 mmc1_nesevent(
	.clk        (clk),
	.ce         (ce),
	.enable     (enable),
	.flags      (flags),
	.prg_ain    (prg_ain),
	.prg_aout_b (mmc1_aout),
	.prg_read   (prg_read),
	.prg_write  (prg_write),
	.prg_din    (prg_din),
	.prg_dout_b (prg_dout_b),
	.prg_allow_b(prg_allow_b),
	.chr_ain    (chr_ain),
	.chr_aout_b (mmc1_chr_addr),
	.chr_allow_b(chr_allow_b),
	.vram_a10_b (vram_a10_b),
	.vram_ce_b  (vram_ce_b),
	.irq_b      (),
	.flags_out_b(flags_out_b),
	.audio_in   (audio_in),
	.audio_b    (audio_b)
);

// $A000-BFFF:   [...I OAA.]
//      I = IRQ control / initialization toggle
//      O = PRG Mode/Chip select
//      A = PRG Reg 'A'
// Mapper gets "initialized" by setting I bit to 0 then to 1.
// On powerup and reset, the first 32k of PRG (from the first PRG chip) is selected at $8000 *no matter what*.
// PRG cannot be swapped until the mapper has been "initialized" by setting the 'I' bit to 0, then to '1'.  This
// toggling will "unlock" PRG swapping on the mapper.
reg unlocked, old_val;
reg [29:0] counter;

reg [3:0] oldbits;
always @(posedge clk)
if (~enable) begin
	old_val <= 0;
	unlocked <= 0;
	counter <= 0;
end else if (ce) begin
	// Handle unlock.
	if (mmc1_chr[3] && !old_val) unlocked <= 1;
	old_val <= mmc1_chr[3];
	// The 'I' bit in $A000 controls the IRQ counter.  When cleared, the IRQ counter counts up every cycle. When
	// set, the IRQ counter is reset to 0 and stays there (does not count), and the pending IRQ is acknowledged.
	counter <= mmc1_chr[3] ? 1'd0 : counter + 1'd1;

	if (mmc1_chr != oldbits) begin
	oldbits <= mmc1_chr;
	end
end

// In the official tournament, 'C' was closed, and the others were open, so the counter had to reach $2800000.
assign irq = (counter[29:25] == 5'b10100);

always begin
	if (!prg_ain[15]) begin
		// WRAM is always routed as usual.
		prg_aout = mmc1_aout;
	end else if (!unlocked) begin
		// Not initialized yet, mapper switch disabled.
		prg_aout = {7'b00_0000_0, prg_ain[14:0]};
	end else if (mmc1_chr[2] == 0) begin
		// O=0: Use first PRG chip (first 128k), use 'A' PRG Reg, 32k swap
		prg_aout = {5'b00_000, mmc1_chr[1:0], prg_ain[14:0]};
	end else begin
		// O=1: Use second PRG chip (second 128k), use 'B' PRG Reg, MMC1 style swap
		prg_aout = mmc1_aout;
	end
end

// 8kB CHR RAM.
assign chr_aout = {9'b10_0000_000, chr_ain[12:0]};

endmodule
