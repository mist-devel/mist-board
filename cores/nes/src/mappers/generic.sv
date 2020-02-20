// These mappers are simple generic mappers which can eventually be combined into a single module with parameters

// No mapper chip
module MMC0(
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
reg [15:0] flags_out = 0;


assign prg_aout = {7'b00_0000_0, prg_ain[14:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign chr_allow = flags[15];
assign chr_aout = {9'b10_0000_000, chr_ain[12:0]};
assign vram_ce = chr_ain[13];
assign vram_a10 = flags[14] ? chr_ain[10] : chr_ain[11];

endmodule

// #13 - CPROM - Used by Videomation
module Mapper13(
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
reg [15:0] flags_out = 0;

reg [1:0] chr_bank;
always @(posedge clk) begin
	if (~enable) begin
		chr_bank <= 0;
	end else if (ce) begin
		if (prg_ain[15] && prg_write)
			chr_bank <= prg_din[1:0];
	end
end

assign prg_aout = {7'b00_0000_0, prg_ain[14:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign chr_allow = flags[15];
assign chr_aout = {8'b01_0000_00, chr_ain[12] ? chr_bank : 2'b00, chr_ain[11:0]};
assign vram_ce = chr_ain[13];
assign vram_a10 = flags[14] ? chr_ain[10] : chr_ain[11];

endmodule

// 30-UNROM512
module Mapper30(
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
reg vram_a10;
wire vram_ce;
reg [15:0] flags_out = 0;


reg [4:0] prgbank;
reg [1:0] chrbank;
reg nametable;
wire four_screen = flags[16] && flags[14];

always @(posedge clk) begin
	if (~enable) begin
		prgbank   <= 0;
		chrbank   <= 0;
		nametable <= 0;
	end else if (ce) begin
		if (prg_ain[15] & prg_write) begin
			{nametable, chrbank, prgbank}   <= prg_din[7:0];
		end
	end
end

always begin
	// mirroring mode
	casez({flags[16], flags[14]})
		3'b00   :   vram_a10 = chr_ain[11];    // horizontal
		3'b01   :   vram_a10 = chr_ain[10];    // vertical
		3'b10   :   vram_a10 = nametable;      // 1 screen
		default :   vram_a10 = chr_ain[10];    // 4 screen
	endcase
end

assign prg_aout = {3'b000, (prg_ain[15:14] == 2'b11) ? 5'b11111 : prgbank, prg_ain[13:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign chr_allow = flags[15];
assign chr_aout = {flags[15] ? 7'b11_1111_1 : 7'b10_0000_0, (four_screen && chr_ain[13]) ? 2'b11 : chrbank, chr_ain[12:0]};
assign vram_ce = chr_ain[13] && !four_screen;

endmodule


// 11  - Color Dreams
// 38  - Bit Corps
// 46  - RumbleStation 15-in-1
// 86  - Jaleco JF-13 -- no audio samples
// 87  - Jaleco JF-11,JF-14
// 101 - Jaleco JF-11,JF-14
// 140 - Jaleco JF-11,JF-14
// 66  - GxROM
// 145 - Sachen
// 149 - Sachen
module Mapper66(
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
wire [15:0] flags_out = {13'h0, prg_conflict, 2'b00};


reg [4:0] prg_bank;
reg [6:0] chr_bank;
wire [7:0] mapper = flags[7:0];
wire GXROM = (mapper == 66);
wire BitCorps = (mapper == 38);
wire Mapper140 = (mapper == 140);
wire Mapper101 = (mapper == 101);
wire Mapper46 = (mapper == 46);
wire Mapper86 = (mapper == 86);
wire Mapper87 = (mapper == 87);
wire Mapper145 = (mapper == 145);
wire Mapper149 = (mapper == 149);

always @(posedge clk)
if (~enable) begin
	prg_bank <= 0;
	chr_bank <= 0;
end else if (ce) begin
	if (prg_ain[15] & prg_write) begin
		if (GXROM)
			{prg_bank, chr_bank} <= {3'b0, prg_din[5:4], 5'b0, prg_din[1:0]};
		else if (Mapper149)
			{chr_bank} <= {6'b0, prg_din[7]};
		else if (Mapper46)
			{chr_bank[2:0], prg_bank[0]} <= {prg_din[6:4], prg_din[0]};
		else // Color Dreams
			{chr_bank, prg_bank} <= {3'b0, prg_din[7:4], 3'b0, prg_din[1:0]};
	end else if ((prg_ain[15:12]==4'h7) & prg_write & BitCorps) begin
		{chr_bank, prg_bank} <= {3'b0, prg_din[3:0]};
	end else if ((prg_ain[15:12]==4'h6) & prg_write) begin
		if (Mapper140) begin
			{prg_bank, chr_bank} <= {3'b0, prg_din[5:4], 3'b0, prg_din[3:0]};
		end else if (Mapper46) begin
			{chr_bank[6:3], prg_bank[4:1]} <= {prg_din[7:4], prg_din[3:0]};
		end else if (Mapper101) begin
			{chr_bank} <= {3'b0, prg_din[3:0]}; // All 8 bits instead?
		end else if (Mapper87) begin
			{chr_bank} <= {5'b00, prg_din[0], prg_din[1]};
		end else if (Mapper86) begin
			{prg_bank, chr_bank} <= {3'b0, prg_din[5:4], 4'b0, prg_din[6], prg_din[1:0]};
		end
	end else if ((prg_ain[15:8]==8'h41) & prg_write) begin
		if (Mapper145)
			{chr_bank} <= {6'b0, prg_din[7]};
	end
end

assign prg_aout = {2'b00, prg_bank, prg_ain[14:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign chr_allow = flags[15];
assign chr_aout = {2'b10, chr_bank, chr_ain[12:0]};
assign vram_ce = chr_ain[13];
assign vram_a10 = flags[14] ? chr_ain[10] : chr_ain[11];
wire prg_conflict = prg_ain[15] && (Mapper149);

endmodule


// 34 - BxROM or NINA-001
module Mapper34(
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
reg [15:0] flags_out = 0;


reg [5:0] prg_bank;
reg [3:0] chr_bank_0, chr_bank_1;

wire NINA = (flags[13:11] != 0); // NINA is used when there is more than 8kb of CHR
always @(posedge clk)
if (~enable) begin
	prg_bank <= 0;
	chr_bank_0 <= 0;
	chr_bank_1 <= 1; // To be compatible with BxROM
end else if (ce && prg_write) begin
	if (!NINA) begin // BxROM
		if (prg_ain[15])
			prg_bank <= prg_din[5:0]; //[1:0] offical, [5:0] oversize
	end else begin // NINA
		if (prg_ain == 16'h7ffd)
			prg_bank <= prg_din[5:0]; //[1:0] offical, [5:0] oversize
		else if (prg_ain == 16'h7ffe)
			chr_bank_0 <= prg_din[3:0];
		else if (prg_ain == 16'h7fff)
			chr_bank_1 <= prg_din[3:0];
	end
end

wire [21:0] prg_aout_tmp = {1'b0, prg_bank, prg_ain[14:0]};
assign chr_allow = flags[15];
assign chr_aout = {6'b10_0000, chr_ain[12] == 0 ? chr_bank_0 : chr_bank_1, chr_ain[11:0]};
assign vram_ce = chr_ain[13];
assign vram_a10 = flags[14] ? chr_ain[10] : chr_ain[11];

wire prg_is_ram = (prg_ain >= 'h6000 && prg_ain < 'h8000) && NINA;
assign prg_allow = prg_ain[15] && !prg_write || prg_is_ram;

wire [21:0] prg_ram = {9'b11_1100_000, prg_ain[12:0]};
assign prg_aout = prg_is_ram ? prg_ram : prg_aout_tmp;

endmodule


// #71,#232 - Camerica
module Mapper71(
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
reg [15:0] flags_out = 0;

reg [3:0] prg_bank;
reg ciram_select;
wire mapper232 = (flags[7:0] == 232);
always @(posedge clk)
if (~enable) begin
	prg_bank <= 0;
	ciram_select <= 0;
end else if (ce) begin
	if (prg_ain[15] && prg_write) begin
		if (!prg_ain[14] && mapper232) // $8000-$BFFF Outer bank select (only on iNES 232)
			prg_bank[3:2] <= prg_din[4:3];
		if (prg_ain[14:13] == 0)       // $8000-$9FFF Fire Hawk Mirroring
			ciram_select <= prg_din[4];
		if (prg_ain[14])               // $C000-$FFFF Bank select
			prg_bank <= {mapper232 ? prg_bank[3:2] : prg_din[3:2], prg_din[1:0]};
	end
end

reg [3:0] prgout;
always begin
	casez({prg_ain[14], mapper232})
		2'b0?: prgout = prg_bank;
		2'b10: prgout = 4'b1111;
		2'b11: prgout = {prg_bank[3:2], 2'b11};
	endcase
end

assign prg_aout = {4'b00_00, prgout, prg_ain[13:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign chr_allow = flags[15];
assign chr_aout = {9'b10_0000_000, chr_ain[12:0]};
assign vram_ce = chr_ain[13];
// XXX(ludde): Fire hawk uses flags[14] == 0 while no other game seems to do that.
// So when flags[14] == 0 we use ciram_select instead.
assign vram_a10 = flags[14] ? chr_ain[10] : ciram_select;

endmodule


// 77-IREM
module Mapper77(
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
reg vram_a10;
wire vram_ce;
reg [15:0] flags_out = 0;


reg [3:0] prgbank;
reg [3:0] chrbank;

always @(posedge clk) begin
	if (~enable) begin
		prgbank <= 0;
		chrbank <= 0;
	end else if (ce) begin
		if (prg_ain[15] & prg_write) begin
			{chrbank, prgbank}   <= prg_din[7:0];
		end
	end
end

always begin
	vram_a10 = {chr_ain[10]};    // four screen (consecutive)
end

assign prg_aout = {3'b000, prgbank, prg_ain[14:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign chr_allow = chrram;
wire chrram = (chr_ain[13:11]!=3'b000);
assign chr_aout[10:0] = {chr_ain[10:0]};
assign chr_aout[21:11] = chrram ? {8'b11_1111_11, chr_ain[13:11]} : {7'b10_0000_0, chrbank};
assign vram_ce = 0;

endmodule

// #78-IREM-HOLYDIVER/JALECO-JF-16
// #70,#152-Bandai
module Mapper78(
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
reg [15:0] flags_out = 0;

reg [3:0] prg_bank;
reg [3:0] chr_bank;
reg mirroring;  // See vram_a10_t
wire mapper70 = (flags[7:0] == 70);
wire mapper152 = (flags[7:0] == 152);
wire onescreen = (flags[22:21] == 1) | mapper152; // default (0 or 3) Holy Diver submapper; (1) JALECO-JF-16
always @(posedge clk) begin
	if (~enable) begin
		prg_bank <= 0;
		chr_bank <= 0;
		mirroring <= flags[14];
	end else if (ce) begin
		if (prg_ain[15] == 1'b1 && prg_write) begin
			if (mapper70)
				{prg_bank, chr_bank} <= prg_din;
			else if (mapper152)
				{mirroring, prg_bank[2:0], chr_bank} <= prg_din;
			else
				{chr_bank, mirroring, prg_bank[2:0]} <= prg_din;
		end
	end
end

assign prg_aout = {4'b00_00, (prg_ain[14] ? 4'b1111 : prg_bank), prg_ain[13:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign chr_allow = flags[15];
assign chr_aout = {5'b10_000, chr_bank, chr_ain[12:0]};
assign vram_ce = chr_ain[13];

// The a10 VRAM address line. (Used for mirroring)
reg vram_a10_t;
always begin
	case({onescreen, mirroring})
		2'b00: vram_a10_t = chr_ain[11];   // One screen, horizontal
		2'b01: vram_a10_t = chr_ain[10];   // One screen, vertical
		2'b10: vram_a10_t = 0;             // One screen, lower bank
		2'b11: vram_a10_t = 1;             // One screen, upper bank
	endcase
end

assign vram_a10 = vram_a10_t;

endmodule

// #79,#113 - NINA-03 / NINA-06
// #133,#146,#148 - Sachen
module Mapper79(
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
wire [15:0] flags_out = {13'h0, prg_conflict, 2'b00};

reg [2:0] prg_bank;
reg [3:0] chr_bank;
reg mirroring;  // 0: Horizontal, 1: Vertical
wire mapper113 = (flags[7:0] == 113); // NINA-06
wire mapper133 = (flags[7:0] == 133);
wire mapper148 = (flags[7:0] == 148);

always @(posedge clk)
if (~enable) begin
	prg_bank <= 0;
	chr_bank <= 0;
	mirroring <= 0;
end else if (ce) begin
	if (prg_ain[15:13] == 3'b010 && prg_ain[8] && prg_write)
		if (mapper133)
			{mirroring, chr_bank[3], prg_bank, chr_bank[2:0]} <= {4'h0,prg_din[2],1'b0,prg_din[1:0]};
		else
			{mirroring, chr_bank[3], prg_bank, chr_bank[2:0]} <= prg_din;
	if (prg_ain[15] == 1'b1 && prg_write)
		if (mapper148)
			{mirroring, chr_bank[3], prg_bank, chr_bank[2:0]} <= prg_din;
end

assign prg_aout = {4'b00_00, prg_bank, prg_ain[14:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign chr_allow = flags[15];
assign chr_aout = {5'b10_000, chr_bank, chr_ain[12:0]};
assign vram_ce = chr_ain[13];
wire mirrconfig = mapper113 ? mirroring : flags[14]; // Mapper #13 has mapper controlled mirroring
assign vram_a10 = mirrconfig ? chr_ain[10] : chr_ain[11]; // 0: horiz, 1: vert
wire prg_conflict = prg_ain[15] && mapper148;

endmodule


// #89,#93,#184 - Sunsoft mappers
module Mapper89(
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
reg vram_a10;
wire vram_ce;
reg [15:0] flags_out = 0;


reg [2:0] prgsel;
reg [3:0] chrsel0;
reg [3:0] chrsel1;
reg [2:0] prg_temp;
reg [4:0] chr_temp;

reg mirror;

wire [7:0] mapper = flags[7:0];
wire mapper89 = (mapper == 8'd89);
wire mapper93 = (mapper == 8'd93);
wire mapper184 = (mapper == 8'd184);

always @(posedge clk)
if (~enable) begin
	prgsel <= 3'b110;
	chrsel0 <= 4'b1111;
	chrsel1 <= 4'b1111;
end else if (ce) begin
	if (prg_ain[15] & prg_write & mapper89) begin
		{chrsel0[3], prgsel, mirror, chrsel0[2:0]} <= prg_din;
	end else if (prg_ain[15] & prg_write & mapper93) begin
		prgsel <= prg_din[6:4];
		// chrrameanble <= prg_din[0];
	end else if ((prg_ain[15:13]==3'b011) & prg_write & mapper184) begin
		{chrsel1[3:0], chrsel0[3:0]}  <= {2'b01,prg_din[5:4],1'b0,prg_din[2:0]};
	end
end

always begin
	// mirroring mode
	casez({mapper89,flags[14]})
		2'b00   :   vram_a10 = {chr_ain[11]};    // horizontal
		2'b01   :   vram_a10 = {chr_ain[10]};    // vertical
		2'b1?   :   vram_a10 = {mirror};         // 1 screen
	endcase

	// PRG ROM bank size select
	casez({mapper184, prg_ain[14]})
		2'b00 :  prg_temp = {prgsel};            // 16K banks
		2'b01 :  prg_temp = {3'b111};            // 16K banks last
		2'b1? :  prg_temp = {2'b0,prg_ain[14]};  // 32K banks pass thru
	endcase

	// CHR ROM bank size select
	casez({mapper184, chr_ain[12]})
		2'b0? :  chr_temp = {chrsel0, chr_ain[12]};// 8K Bank
		2'b10 :  chr_temp = {1'b0,chrsel0};  // 4K Bank
		2'b11 :  chr_temp = {1'b0,chrsel1};  // 4K Bank
	endcase
end

assign vram_ce = chr_ain[13];
assign prg_aout = {5'b0, prg_temp, prg_ain[13:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign chr_allow = flags[15];
assign chr_aout = {5'b10_000, chr_temp, chr_ain[11:0]};

endmodule



// 107 Magicseries Magic Dragon
module Mapper107(
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
reg [15:0] flags_out = 0;


reg [6:0] prg_bank;
reg [7:0] chr_bank;
always @(posedge clk) begin
	if (~enable) begin
		prg_bank <= 0;
		chr_bank <= 0;
	end else if (ce) begin
		if (prg_ain[15] & prg_write) begin
			prg_bank <= prg_din[7:1];
			chr_bank <= prg_din[7:0];
		end
	end
end

assign vram_a10 = flags[14] ? chr_ain[10] : chr_ain[11];
assign prg_aout = {1'b0, prg_bank[5:0], prg_ain[14:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign chr_allow = flags[15];
assign chr_aout = {2'b10, chr_bank[6:0], chr_ain[12:0]};
assign vram_ce = chr_ain[13];

endmodule

// Tepples/Multi-discrete mapper
// This mapper can emulate other mappers,  such as mapper #0, mapper #2
module Mapper28(
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
	inout  [7:0] chr_dout_b,  // chr data (non standard)
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
assign chr_dout_b   = enable ? chr_dout : 8'hZ;
assign chr_allow_b  = enable ? chr_allow : 1'hZ;
assign vram_a10_b   = enable ? vram_a10 : 1'hZ;
assign vram_ce_b    = enable ? vram_ce : 1'hZ;
assign irq_b        = enable ? 1'b0 : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? {1'b0, audio_in[15:1]} : 16'hZ;

wire [21:0] prg_aout, chr_aout;
wire prg_allow;
wire chr_allow;
reg vram_a10;
reg [7:0] chr_dout;
wire vram_ce;
wire [15:0] flags_out = {13'h0, prg_conflict, 1'b0, has_chr_dout};

wire prg_conflict, has_chr_dout;

reg [6:0] a53prg;    // output PRG ROM (A14-A20 on ROM)
reg [1:0] a53chr;    // output CHR RAM (A13-A14 on RAM)

reg [3:0] inner;    // "inner" bank at 01h
reg [5:0] mode;     // mode register at 80h
reg [5:0] outer;    // "outer" bank at 81h
reg [2:0] selreg;   // selector register
reg [3:0] security; // selector register

// Allow writes to 0x5000 only when launching through the proper mapper ID.
wire [7:0] mapper = flags[7:0];
wire allow_select = (mapper == 8'd28);
wire extend_bit = (mapper == 97);

always @(posedge clk)
if (~enable) begin
	mode[5:2] <= 0;         // NROM mode, 32K mode
	outer[5:0] <= 6'h3f;    // last bank
	inner <= 0;
	selreg <= 1;

	// Set value for mirroring
	if (mapper == 2 || mapper == 0 || mapper == 3 || mapper == 94 || mapper == 180 || mapper == 185)
		mode[1:0] <= flags[14] ? 2'b10 : 2'b11;

	// UNROM #2 - Current bank in $8000-$BFFF and fixed top half of outer bank in $C000-$FFFF
	if (mapper == 2) begin
		mode[5:2] <= 4'b1111; // 256K banks, UNROM mode
	end

	// CNROM #3 - Fixed PRG bank, switchable CHR bank.
	if (mapper == 3)
		selreg <= 0;

	// CNROM #185 - Fixed PRG bank, Fixed CHR Bank, Security.
	if (mapper == 185)
		selreg <= 4;

	// UNROM #180 - Fixed first PRG bank, Fixed CHR Bank.
	if (mapper == 180) begin
		selreg <= 1;
		mode[5:2] <= 4'b1110;
		outer[5:0] <= 6'h00;
	end

	// IREM TAM-S1 IC #97 - Fixed first PRG bank, Fixed CHR Bank, Mirroring.
	if (mapper == 97) begin
		selreg <= 6;
		mode[5:2] <= 4'b1110;
		outer[5:0] <= 6'h3F;
	end

	// IREM TAM-S1 IC #94 - Fixed last PRG bank, Fixed CHR Bank
	if (mapper == 94) begin
		selreg <= 7;
		mode[5:2] <= 4'b1111;
	end

	// AxROM #7 - Switch 32kb rom bank + switchable nametables
	if (mapper == 7) begin
		mode[1:0] <= 2'b00;   // Switchable VRAM page.
		mode[5:2] <= 4'b1100; // 256K banks, (B)NROM mode
		outer[5:0] <= 6'h00;
	end
end else if (ce) begin
	if ((prg_ain[15:12] == 4'h5) & prg_write && allow_select)
			selreg <= {1'b0,prg_din[7], prg_din[0]};        // select register
	if (prg_ain[15] & prg_write) begin
		casez (selreg)
			3'b000:  {mode[0], a53chr}  <= {(mode[1] ? mode[0] : prg_din[4]), prg_din[1:0]};     // CHR RAM bank
			3'b001:  {mode[0], inner}   <= {(mode[1] ? mode[0] : prg_din[4]), prg_din[3:0]};     // "inner" bank
			3'b010:  {mode}             <= {prg_din[5:0]};                                       // mode register
			3'b011:  {outer}            <= {prg_din[5:0]};                                       // "outer" bank
			3'b10?:  {security}         <= {prg_din[5:4],prg_din[1:0]};                          // security
			3'b110:  {mode[1:0],inner}  <= {prg_din[7] ^ prg_din[6], prg_din[6], prg_din[3:0]};  // "inner" bank
			3'b111:  {inner}            <= {prg_din[5:2]};                                       // "inner" bank
		endcase
	end
end

always begin
	// mirroring mode
	casez(mode[1:0])
		2'b0? : vram_a10 = {mode[0]};        // 1 screen lower
		2'b10 : vram_a10 = {chr_ain[10]};    // vertical
		2'b11 : vram_a10 = {chr_ain[11]};    // horizontal
	endcase

	// PRG ROM bank size select
	casez({mode[5:2], prg_ain[14]})
		5'b00_0?_?: a53prg = {outer[5:0],             prg_ain[14]};  // 32K banks, (B)NROM mode
		5'b01_0?_?: a53prg = {outer[5:1], inner[0],   prg_ain[14]};  // 64K banks, (B)NROM mode
		5'b10_0?_?: a53prg = {outer[5:2], inner[1:0], prg_ain[14]};  // 128K banks, (B)NROM mode
		5'b11_0?_?: a53prg = {outer[5:3], inner[2:0], prg_ain[14]};  // 256K banks, (B)NROM mode

		5'b00_10_1,
		5'b00_11_0: a53prg = {outer[5:0], inner[0]};                 // 32K banks, UNROM mode
		5'b01_10_1,
		5'b01_11_0: a53prg = {outer[5:1], inner[1:0]};               // 64K banks, UNROM mode
		5'b10_10_1,
		5'b10_11_0: a53prg = {outer[5:2], inner[2:0]};               // 128K banks, UNROM mode
		5'b11_10_1,
		5'b11_11_0: a53prg = {outer[5:3], inner[3:0]};               // 256K banks, UNROM mode

		default: a53prg = {outer[5:0], extend_bit ? outer[0] : prg_ain[14]};  // 16K fixed bank
	endcase

	chr_dout = 8'hFF;//chr_ain[7:0]; // return open bus = LSB of address? below when CHR disabled by security
end

assign vram_ce = chr_ain[13];
assign prg_aout = {1'b0, (a53prg & 7'b0011111), prg_ain[13:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign prg_conflict = prg_ain[15] && (mapper == 3) && (submapper != 1);
assign chr_allow = flags[15];
assign chr_aout = {7'b10_0000_0, a53chr, chr_ain[12:0]};
wire [4:0] submapper = flags[24:21];
assign has_chr_dout = (mapper == 185) && (((submapper == 0) && (security[1:0] == 2'b00))
		|| ((submapper == 4) && (security[1:0] != 2'b00))
		|| ((submapper == 5) && (security[1:0] != 2'b01))
		|| ((submapper == 6) && (security[1:0] != 2'b10))
		|| ((submapper == 7) && (security[1:0] != 2'b11)));

endmodule
