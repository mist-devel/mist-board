// MMC3 style mappers. Some of these can probably be consolidated.

// iNES mapper 64 and 158 - Tengen's version of MMC3
module Rambo1(
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
	input [13:0] chr_ain_o
);

assign prg_aout_b   = enable ? prg_aout : 22'hZ;
assign prg_dout_b   = enable ? prg_dout : 8'hZ;
assign prg_allow_b  = enable ? prg_allow : 1'hZ;
assign chr_aout_b   = enable ? chr_aout : 22'hZ;
assign chr_allow_b  = enable ? chr_allow : 1'hZ;
assign vram_a10_b   = enable ? vram_a10 : 1'hZ;
assign vram_ce_b    = enable ? vram_ce : 1'hZ;
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? {1'b0, audio_in[15:1]} : 16'hZ;


wire [21:0] prg_aout, chr_aout;
wire [7:0] prg_dout = 0;
wire prg_allow;
wire chr_allow;
wire vram_a10;
wire vram_ce;
reg irq;
reg [15:0] flags_out = 0;

reg [3:0] bank_select;             // Register to write to next
reg prg_rom_bank_mode;             // Mode for PRG banking
reg chr_K;                         // Mode for CHR banking
reg chr_a12_invert;                // Mode for CHR banking
reg mirroring;                     // 0 = vertical, 1 = horizontal
reg irq_enable, irq_reload;        // IRQ enabled, and IRQ reload requested
reg [7:0] irq_latch, counter;      // IRQ latch value and current counter
reg [1:0] irq_delay;
wire irq_imm;
reg [7:0] chr_bank_0, chr_bank_1;  // Selected CHR banks
reg [7:0] chr_bank_2, chr_bank_3, chr_bank_4, chr_bank_5;
reg [7:0] chr_bank_8, chr_bank_9;
reg [5:0] prg_bank_0, prg_bank_1, prg_bank_2;  // Selected PRG banks
reg irq_cycle_mode, next_irq_cycle_mode;
reg [1:0] cycle_counter;

// Mapper has vram_a10 wired to CHR A17
//wire mapper64 = (flags[7:0] == 64);//default
wire mapper158 = (flags[7:0] == 158);

// This code detects rising edges on a12.
reg old_a12_edge;
reg [1:0] a12_ctr;
wire a12_edge = (chr_ain_o[12] && a12_ctr == 0) || old_a12_edge;

always @(posedge clk) begin
	old_a12_edge <= a12_edge && !ce;
	a12_ctr <= chr_ain_o[12] ? 2'b11 : (a12_ctr != 0 && ce) ? a12_ctr - 2'b01 : a12_ctr;
end

always @(posedge clk)
if (~enable) begin
	bank_select <= 0;
	prg_rom_bank_mode <= 0;
	chr_K <= 0;
	chr_a12_invert <= 0;
	mirroring <= 0;
	{irq_enable, irq_reload} <= 0;
	{irq_latch, counter} <= 0;
	{chr_bank_0, chr_bank_1} <= 0;
	{chr_bank_2, chr_bank_3, chr_bank_4, chr_bank_5} <= 0;
	{chr_bank_8, chr_bank_9} <= 0;
	{prg_bank_0, prg_bank_1, prg_bank_2} <= 6'b111111;
	irq_cycle_mode <= 0;
	next_irq_cycle_mode <= 0;
	cycle_counter <= 0;
	irq <= 0;
end else if (ce) begin
	// Process these before writes so irq_reload and cycle_counter register writes take precedence.
	cycle_counter <= cycle_counter + 1'd1;
	irq_delay <= {1'b0, irq_delay[1]};
	if ((cycle_counter == 3) || (!irq_cycle_mode))
		irq_cycle_mode <= next_irq_cycle_mode;

	irq_imm = 1'b0;
	if (irq_cycle_mode ? (cycle_counter == 3) : a12_edge) begin
		if (irq_reload || counter == 8'h00) begin
			counter <= irq_latch + ((irq_reload && (|irq_latch[7:1])) ? 1'd1 : 1'd0);
			irq_imm = irq_latch == 0;
		end else begin
			counter <= counter - 1'd1;
		end

		if (((counter == 1) || (irq_imm)) && irq_enable)
			irq_delay <= irq_cycle_mode ? 2'b01 : 2'b10;
		irq_reload <= 0;
	end
	if (irq_delay[0]) begin
		irq <= 1;
		irq_delay <= 2'b00;
	end

	if (prg_write && prg_ain[15]) begin
		case({prg_ain[14:13], prg_ain[0]})
			// Bank select ($8000-$9FFE, even)
			3'b00_0: {chr_a12_invert, prg_rom_bank_mode, chr_K, bank_select} <= {prg_din[7:5], prg_din[3:0]};
			// Bank data ($8001-$9FFF, odd)
			3'b00_1:
				case (bank_select)
					0: chr_bank_0 <= prg_din;       // Select 2 (K=0) or 1 (K=1) KB CHR bank at PPU $0000 (or $1000);
					1: chr_bank_1 <= prg_din;       // Select 2 (K=0) or 1 (K=1) KB CHR bank at PPU $0800 (or $1800);
					2: chr_bank_2 <= prg_din;       // Select 1 KB CHR bank at PPU $1000-$13FF (or $0000-$03FF);
					3: chr_bank_3 <= prg_din;       // Select 1 KB CHR bank at PPU $1400-$17FF (or $0400-$07FF);
					4: chr_bank_4 <= prg_din;       // Select 1 KB CHR bank at PPU $1800-$1BFF (or $0800-$0BFF);
					5: chr_bank_5 <= prg_din;       // Select 1 KB CHR bank at PPU $1C00-$1FFF (or $0C00-$0FFF);
					6: prg_bank_0 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $8000-$9FFF (or $C000-$DFFF);
					7: prg_bank_1 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $A000-$BFFF
					8: chr_bank_8 <= prg_din;       // If K=1, Select 1 KB CHR bank at PPU $0400 (or $1400);
					9: chr_bank_9 <= prg_din;       // If K=1, Select 1 KB CHR bank at PPU $0C00 (or $1C00)
					15: prg_bank_2 <= prg_din[5:0]; // Select 8 KB PRG ROM bank at $C000-$DFFF (or $8000-$9FFF);
				endcase
			3'b01_0: mirroring <= prg_din[0];                   // Mirroring ($A000-$BFFE, even)
			3'b01_1: begin end
			3'b10_0: irq_latch <= prg_din;                      // IRQ latch ($C000-$DFFE, even)
			3'b10_1: begin
						{irq_reload, next_irq_cycle_mode} <= {1'b1, prg_din[0]}; // IRQ reload ($C001-$DFFF, odd)
						cycle_counter <= 0;
					end
			3'b11_0: {irq_enable, irq} <= 2'b00;                 // IRQ disable ($E000-$FFFE, even)
			3'b11_1: {irq_enable, irq} <= 2'b10;                 // IRQ enable ($E001-$FFFF, odd)
		endcase
	end
end

// The PRG bank to load. Each increment here is 8kb. So valid values are 0..63.
reg [5:0] prgsel;
always @* begin
	casez({prg_ain[14:13], prg_rom_bank_mode})
		3'b00_0: prgsel = prg_bank_0;  // $8000 is R:6
		3'b01_0: prgsel = prg_bank_1;  // $A000 is R:7
		3'b10_0: prgsel = prg_bank_2;  // $C000 is R:F
		3'b11_0: prgsel = 6'b111111;   // $E000 fixed to last bank
		3'b00_1: prgsel = prg_bank_2;  // $8000 is R:F
		3'b01_1: prgsel = prg_bank_0;  // $A000 is R:6
		3'b10_1: prgsel = prg_bank_1;  // $C000 is R:7
		3'b11_1: prgsel = 6'b111111;   // $E000 fixed to last bank
	endcase
end

// The CHR bank to load. Each increment here is 1kb. So valid values are 0..255.
reg [7:0] chrsel;

always @* begin
	casez({chr_ain[12] ^ chr_a12_invert, chr_ain[11], chr_ain[10], chr_K})
		4'b00?_0: chrsel = {chr_bank_0[7:1], chr_ain[10]};
		4'b01?_0: chrsel = {chr_bank_1[7:1], chr_ain[10]};
		4'b000_1: chrsel = chr_bank_0;
		4'b001_1: chrsel = chr_bank_8;
		4'b010_1: chrsel = chr_bank_1;
		4'b011_1: chrsel = chr_bank_9;
		4'b100_?: chrsel = chr_bank_2;
		4'b101_?: chrsel = chr_bank_3;
		4'b110_?: chrsel = chr_bank_4;
		4'b111_?: chrsel = chr_bank_5;
	endcase
end

assign prg_aout = {3'b00_0,  prgsel, prg_ain[12:0]};
assign {chr_allow, chr_aout} = {flags[15], 4'b10_00, chrsel, chr_ain[9:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign vram_a10 = mapper158 ? chrsel[7] :  // Mapper 158 controls mirroring by switching the top bits of the CHR address
		mirroring ? chr_ain[11] : chr_ain[10];
assign vram_ce = chr_ain[13];
endmodule

// This mapper also handles mapper 33,47,48,74,76,80,82,88,95,118,119,154,191,192,194,195,206 and 207.
module MMC3 (
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
	input [13:0] chr_ain_o
);

assign prg_aout_b   = enable ? prg_aout : 22'hZ;
assign prg_dout_b   = enable ? prg_dout : 8'hZ;
assign prg_allow_b  = enable ? prg_allow : 1'hZ;
assign chr_aout_b   = enable ? chr_aout : 22'hZ;
assign chr_allow_b  = enable ? chr_allow : 1'hZ;
assign vram_a10_b   = enable ? vram_a10 : 1'hZ;
assign vram_ce_b    = enable ? vram_ce : 1'hZ;
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? {1'b0, audio_in[15:1]} : 16'hZ;

wire [21:0] prg_aout, chr_aout;
wire [7:0] prg_dout = 0;
wire prg_allow;
wire chr_allow;
wire vram_a10;
wire vram_ce;
wire irq;
reg [15:0] flags_out = 0;

reg [2:0] bank_select;             // Register to write to next
reg prg_rom_bank_mode;             // Mode for PRG banking
reg chr_a12_invert;                // Mode for CHR banking
reg mirroring;                     // 0 = vertical, 1 = horizontal
reg irq_enable, irq_reload;        // IRQ enabled, and IRQ reload requested
reg [7:0] irq_latch, counter;      // IRQ latch value and current counter
reg [3:0] ram_enable, ram_protect;       // RAM protection bits
reg ram6_enabled, ram6_enable, ram6_protect; //extra bits for mmc6
reg [7:0] chr_bank_0, chr_bank_1;  // Selected CHR banks
reg [7:0] chr_bank_2, chr_bank_3, chr_bank_4, chr_bank_5;
reg [5:0] prg_bank_0, prg_bank_1, prg_bank_2;  // Selected PRG banks
reg last_a12;
wire prg_is_ram;
reg [4:0] irq_reg;
assign irq = mapper48 ? irq_reg[4] : irq_reg[0];

// The alternative behavior has slightly different IRQ counter semantics.
wire mmc3_alt_behavior = acclaim;

wire TQROM =     (flags[7:0] == 119); 	// TQROM maps 8kB CHR RAM
wire TxSROM =    (flags[7:0] == 118); 	// Connects CHR A17 to CIRAM A10
wire mapper47 =  (flags[7:0] == 47);		// Mapper 47 is a multicart that has 128k for each game. It has no RAM.
wire mapper37 =  (flags[7:0] == 37);    // European Triple Cart (Super Mario, Tetris, Nintendo World Cup)
wire DxROM =     (flags[7:0] == 206);
wire mapper112 = (flags[7:0] == 112);   // Ntdec
wire mapper48 =  (flags[7:0] == 48);    // Taito's TC0690
wire mapper33 =  (flags[7:0] == 33);    // Taito's TC0190 (TC0690-like. No IRQ. Different Mirroring bit)
wire mapper95 =  (flags[7:0] == 95);    // NAMCOT-3425
wire mapper88 =  (flags[7:0] == 88);    // NAMCOT-3433
wire mapper154 = (flags[7:0] == 154);   // NAMCOT-3453
wire mapper76 =  (flags[7:0] == 76);    // NAMCOT-3446
wire mapper80 =  (flags[7:0] == 80);    // Taito's X1-005
wire mapper82 =  (flags[7:0] == 82);    // Taito's X1-017
wire mapper207 = (flags[7:0] == 207);   // Taito's X1-017
wire mapper74 =  (flags[7:0] == 74);    // Has 2KB CHR RAM
wire mapper191 = (flags[7:0] == 191);   // Has 2KB CHR RAM
wire mapper192 = (flags[7:0] == 192);   // Has 4KB CHR RAM
wire mapper194 = (flags[7:0] == 194);   // Has 2KB CHR RAM
wire mapper195 = (flags[7:0] == 195);   // Has 4KB CHR RAM
wire MMC6 = ((flags[7:0] == 4) && (flags[24:21] == 1)); // mapper 4, submapper 1 = MMC6
wire acclaim = ((flags[7:0] == 4) && (flags[24:21] == 3)); // Acclaim mapper

wire four_screen_mirroring = flags[16];// | DxROM; // not all DxROM are 4-screen
reg mapper47_multicart;
reg [2:0] mapper37_multicart;
wire [7:0] new_counter = (counter == 0 || irq_reload) ? irq_latch : counter - 1'd1;
reg [3:0] a12_ctr;
wire irq_support = !DxROM && !mapper33 && !mapper95 && !mapper88 && !mapper154 && !mapper76
	&& !mapper80 && !mapper82 && !mapper207 && !mapper112; //82,207 not needed
wire prg_invert_support = (irq_support && !mapper48);
wire chr_invert_support = (irq_support && !mapper48) || mapper82;
wire regs_7e = mapper80 || mapper82 || mapper207;
wire internal_128 = mapper80 || mapper207;

always @(posedge clk)
if (~enable) begin
	irq_reg <= 5'b00000;
	bank_select <= 0;
	prg_rom_bank_mode <= 0;
	chr_a12_invert <= 0;
	mirroring <= flags[14];
	{irq_enable, irq_reload} <= 0;
	{irq_latch, counter} <= 0;
	ram_enable <= {4{mapper112}};
	ram_protect <= 0;
	{chr_bank_0, chr_bank_1} <= 0;
	{chr_bank_2, chr_bank_3, chr_bank_4, chr_bank_5} <= 0;
	{prg_bank_0, prg_bank_1} <= 0;
	prg_bank_2 <= 6'b111110;
	a12_ctr <= 0;
	last_a12 <= 0;
	mapper37_multicart <= 3'b000;
end else if (ce) begin
	irq_reg[4:1] <= irq_reg[3:0]; // 4 cycle delay
	if (!regs_7e && prg_write && prg_ain[15]) begin
		if (!mapper33 && !mapper48 && !mapper112) begin
			casez({prg_ain[14:13], prg_ain[1:0]})
				4'b00_?0: {chr_a12_invert, prg_rom_bank_mode, ram6_enabled, bank_select} <= {prg_din[7:5], prg_din[2:0]}; // Bank select ($8000-$9FFE, even)
				4'b00_?1: begin // Bank data ($8001-$9FFF, odd)
					case (bank_select)
						0: chr_bank_0 <= {1'b0,prg_din[7:1]};  // Select 2 KB CHR bank at PPU $0000-$07FF (or $1000-$17FF);
						1: chr_bank_1 <= {1'b0,prg_din[7:1]};  // Select 2 KB CHR bank at PPU $0800-$0FFF (or $1800-$1FFF);
						2: chr_bank_2 <= prg_din;       // Select 1 KB CHR bank at PPU $1000-$13FF (or $0000-$03FF);
						3: chr_bank_3 <= prg_din;       // Select 1 KB CHR bank at PPU $1400-$17FF (or $0400-$07FF);
						4: chr_bank_4 <= prg_din;       // Select 1 KB CHR bank at PPU $1800-$1BFF (or $0800-$0BFF);
						5: chr_bank_5 <= prg_din;       // Select 1 KB CHR bank at PPU $1C00-$1FFF (or $0C00-$0FFF);
						6: prg_bank_0 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $8000-$9FFF (or $C000-$DFFF);
						7: prg_bank_1 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $A000-$BFFF
					endcase
				end
				4'b01_?0: mirroring <= !prg_din[0];                   // Mirroring ($A000-$BFFE, even)
				4'b01_?1: {ram_enable, ram_protect, ram6_enable, ram6_protect} <= {{4{prg_din[7]}},{4{prg_din[6]}}, prg_din[5:4]}; // PRG RAM protect ($A001-$BFFF, odd)
				4'b10_?0: irq_latch <= prg_din;                      // IRQ latch ($C000-$DFFE, even)
				4'b10_?1: irq_reload <= 1;                           // IRQ reload ($C001-$DFFF, odd)
				4'b11_?0: begin irq_enable <= 0; irq_reg[0] <= 0; end// IRQ disable ($E000-$FFFE, even)
				4'b11_?1: irq_enable <= 1;                           // IRQ enable ($E001-$FFFF, odd)
			endcase
		end else if (!mapper112) begin
			casez({prg_ain[14:13], prg_ain[1:0], mapper48})
				5'b00_00_0: {mirroring, prg_bank_0} <= prg_din[6:0] ^ 7'h40; // Select 8 KB PRG ROM bank at $8000-$9FFF
				5'b00_00_1: prg_bank_0 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $8000-$9FFF
				5'b00_01_?: prg_bank_1 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $A000-$BFFF
				5'b00_10_?: chr_bank_0 <= prg_din;  // Select 2 KB CHR bank at PPU $0000-$07FF
				5'b00_11_?: chr_bank_1 <= prg_din;  // Select 2 KB CHR bank at PPU $0800-$0FFF
				5'b01_00_?: chr_bank_2 <= prg_din;  // Select 1 KB CHR bank at PPU $1000-$13FF
				5'b01_01_?: chr_bank_3 <= prg_din;  // Select 1 KB CHR bank at PPU $1800-$1BFF
				5'b01_10_?: chr_bank_4 <= prg_din;  // Select 1 KB CHR bank at PPU $1800-$1BFF
				5'b01_11_?: chr_bank_5 <= prg_din;  // Select 1 KB CHR bank at PPU $1C00-$1FFF

				5'b10_00_1: irq_latch <= prg_din ^ 8'hFF;              // IRQ latch ($C000-$DFFC)
				5'b10_01_1: irq_reload <= 1;                           // IRQ reload ($C001-$DFFD)
				5'b10_10_1: irq_enable <= 1;                           // IRQ enable ($C002-$DFFE)
				5'b10_11_1: {irq_enable, irq_reg[0]} <= 2'b00;         // IRQ disable ($C003-$DFFF)

				5'b11_00_1: mirroring <= !prg_din[6];  // Mirroring
			endcase
		end else begin
			casez({prg_ain[14:13], prg_ain[0]})
				3'b00_0: {bank_select} <= {prg_din[2:0]}; // Bank select ($8000-$9FFE)

				3'b01_0: begin // Bank data ($A000-$BFFF)
					case (bank_select)
					0: prg_bank_0 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $8000-$9FFF (or $C000-$DFFF);
					1: prg_bank_1 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $A000-$BFFF
					2: chr_bank_0 <= {1'b0,prg_din[7:1]};  // Select 2 KB CHR bank at PPU $0000-$07FF (or $1000-$17FF);
					3: chr_bank_1 <= {1'b0,prg_din[7:1]};  // Select 2 KB CHR bank at PPU $0800-$0FFF (or $1800-$1FFF);
					4: chr_bank_2 <= prg_din;       // Select 1 KB CHR bank at PPU $1000-$13FF (or $0000-$03FF);
					5: chr_bank_3 <= prg_din;       // Select 1 KB CHR bank at PPU $1400-$17FF (or $0400-$07FF);
					6: chr_bank_4 <= prg_din;       // Select 1 KB CHR bank at PPU $1800-$1BFF (or $0800-$0BFF);
					7: chr_bank_5 <= prg_din;       // Select 1 KB CHR bank at PPU $1C00-$1FFF (or $0C00-$0FFF);
					endcase
				end

				3'b11_0: mirroring <= !prg_din[0];  // Mirroring ($E000-$FFFE)
			endcase
		end

		if (mapper154)
			mirroring <= !prg_din[6];
		if (DxROM || mapper76)
			mirroring <= flags[14]; // Hard-wired mirroring
	end
	else if (regs_7e && prg_write && prg_ain[15:4]==12'h7EF) begin
		casez({prg_ain[3:0], mapper82})
			5'b0000_?: chr_bank_0 <= {1'b0,prg_din[7:1]};  // Select 2 KB CHR bank at PPU $0000-$07FF
			5'b0001_?: chr_bank_1 <= {1'b0,prg_din[7:1]};  // Select 2 KB CHR bank at PPU $0800-$0FFF
			5'b0010_?: chr_bank_2 <= prg_din;  // Select 1 KB CHR bank at PPU $1000-$13FF
			5'b0011_?: chr_bank_3 <= prg_din;  // Select 1 KB CHR bank at PPU $1800-$1BFF
			5'b0100_?: chr_bank_4 <= prg_din;  // Select 1 KB CHR bank at PPU $1800-$1BFF
			5'b0101_?: chr_bank_5 <= prg_din;  // Select 1 KB CHR bank at PPU $1C00-$1FFF
			5'b011?_0: {mirroring} <= prg_din[0]; // Select Mirroing
			5'b100?_0: {ram_enable[3], ram_protect[3]} <= {(prg_din==8'hA3),!(prg_din==8'hA3)};  // Enable RAM at $7F00-$7FFF
			5'b0110_1: {chr_a12_invert,mirroring} <= prg_din[1:0]; // Select Mirroing
			5'b0111_1: {ram_enable[0], ram_protect[0]} <= {(prg_din==8'hCA),!(prg_din==8'hCA)};  // Enable RAM at $6000-$67FF
			5'b1000_1: {ram_enable[1], ram_protect[1]} <= {(prg_din==8'h69),!(prg_din==8'h69)};  // Enable RAM at $6F00-$6FFF
			5'b1001_1: {ram_enable[2], ram_protect[2]} <= {(prg_din==8'h84),!(prg_din==8'h84)};  // Enable RAM at $7000-$73FF  //Using 6K; Require 5K instead?
			5'b101?_0: prg_bank_0 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $8000-$9FFF
			5'b110?_0: prg_bank_1 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $A000-$BFFF
			5'b111?_0: prg_bank_2 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $C000-$DFFF
			5'b1010_1: prg_bank_0 <= prg_din[7:2];  // Select 8 KB PRG ROM bank at $8000-$9FFF
			5'b1011_1: prg_bank_1 <= prg_din[7:2];  // Select 8 KB PRG ROM bank at $A000-$BFFF
			5'b1100_1: prg_bank_2 <= prg_din[7:2];  // Select 8 KB PRG ROM bank at $C000-$DFFF
		endcase
	end

	// For Mapper 47
	// $6000-7FFF:  [.... ...B]  Block select
	if (prg_write && prg_is_ram)
		mapper47_multicart <= prg_din[0];

	// For Mapper 37
	// $6000-7FFF:  [.... .QBB]  Block select
	if (prg_write && prg_is_ram)
		mapper37_multicart <= prg_din[2:0];

	// Trigger IRQ counter on rising edge of chr_ain[12]
	// All MMC3A's and non-Sharp MMC3B's will generate only a single IRQ when $C000 is $00.
	// This is because this version of the MMC3 generates IRQs when the scanline counter is decremented to 0.
	// In addition, writing to $C001 with $C000 still at $00 will result in another single IRQ being generated.
	// In the community, this is known as the "alternate" or "old" behavior.
	// All MMC3C's and Sharp MMC3B's will generate an IRQ on each scanline while $C000 is $00.
	// This is because this version of the MMC3 generates IRQs when the scanline counter is equal to 0.
	// In the community, this is known as the "normal" or "new" behavior.

	last_a12 <= chr_ain_o[12];
	if ((acclaim && (!last_a12 && chr_ain_o[12]) && (a12_ctr == 6)) ||
		(~acclaim && chr_ain_o[12] && (a12_ctr == 0))) begin
		counter <= new_counter;

		// MMC Scanline
		if ( (!mmc3_alt_behavior || counter != 0 || irq_reload) && new_counter == 0 && irq_enable && irq_support) begin
			irq_reg[0] <= 1;
		end
		irq_reload <= 0;
	end

	if (acclaim) begin
		if (!last_a12 && chr_ain_o[12]) // acclaim mapper counts down 8 pulses, or 16 edges total
			a12_ctr <= (a12_ctr != 0) ? a12_ctr - 4'b0001 : 4'b0111;
		if (prg_ain == 16'hC001 && prg_write) a12_ctr <= 4'b0111;
	end else begin // nintendo mapper 'cools down' for 16 low cycles
		a12_ctr <= chr_ain_o[12] ? 4'b1111 : (a12_ctr != 0) ? a12_ctr - 4'b0001 : a12_ctr;
	end
end

// The PRG bank to load. Each increment here is 8kb. So valid values are 0..63.
reg [5:0] prgsel;
always @* begin
	casez({prg_ain[14:13], prg_rom_bank_mode && prg_invert_support})
		3'b00_0: prgsel = prg_bank_0;  // $8000 mode 0
		3'b00_1: prgsel = prg_bank_2;  // $8000 fixed to second last bank
		3'b01_?: prgsel = prg_bank_1;  // $A000 mode 0,1
		3'b10_0: prgsel = prg_bank_2;  // $C000 fixed to second last bank
		3'b10_1: prgsel = prg_bank_0;  // $C000 mode 1
		3'b11_?: prgsel = 6'b111111;   // $E000 fixed to last bank
	endcase

	// mapper47 is limited to 128k PRG, the top bits are controlled by mapper47_multicart instead.
	if (mapper47) prgsel[5:4] = {1'b0, mapper47_multicart};
	if (mapper37) begin
	prgsel[5:4] = {1'b0, mapper37_multicart[2]};
		if (mapper37_multicart[1:0] == 3'd3)
			prgsel[3] = 1'b1;
		else if (mapper37_multicart[2] == 1'b0)
			prgsel[3] = 1'b0;
	end
end

// The CHR bank to load. Each increment here is 1kb. So valid values are 0..255.
reg [8:0] chrsel;
always @* begin
	if (!mapper76) begin
		casez({chr_ain[12] ^ (chr_a12_invert && chr_invert_support), chr_ain[11], chr_ain[10]})
			3'b00?: chrsel = {chr_bank_0, chr_ain[10]};
			3'b01?: chrsel = {chr_bank_1, chr_ain[10]};
			3'b100: chrsel = {1'b0, chr_bank_2};
			3'b101: chrsel = {1'b0, chr_bank_3};
			3'b110: chrsel = {1'b0, chr_bank_4};
			3'b111: chrsel = {1'b0, chr_bank_5};
		endcase
		// mapper47 is limited to 128k CHR, the top bit is controlled by mapper47_multicart instead.
		if (mapper47) chrsel[7] = mapper47_multicart;
		if (mapper37) chrsel[7] = mapper37_multicart[2];
		if ((mapper88) || (mapper154)) chrsel[6] = chr_ain[12];
	end else begin
		case(chr_ain[12:11])
			2'b00: chrsel = {chr_bank_2, chr_ain[10]};
			2'b01: chrsel = {chr_bank_3, chr_ain[10]};
			2'b10: chrsel = {chr_bank_4, chr_ain[10]};
			2'b11: chrsel = {chr_bank_5, chr_ain[10]};
		endcase
	end
end

wire [21:0] prg_aout_tmp = {3'b00_0,  prgsel, prg_ain[12:0]};

wire ram_enable_a = !MMC6 ? (ram_enable[prg_ain[12:11]])
						:   (ram6_enabled && ram6_enable && prg_ain[12] == 1'b1 && prg_ain[9] == 1'b0)
						 || (ram6_enabled && ram_enable[3] && prg_ain[12] == 1'b1 && prg_ain[9] == 1'b1);

wire ram_protect_a = !MMC6 ? (ram_protect[prg_ain[12:11]])
						:   !(ram6_enabled && ram6_enable && ram6_protect && prg_ain[12] == 1'b1 && prg_ain[9] == 1'b0)
						 && !(ram6_enabled && ram_enable[3] && ram_protect[3] && prg_ain[12] == 1'b1 && prg_ain[9] == 1'b1);

assign {chr_allow, chr_aout} =
	(TQROM && chrsel[6])                    ? {1'b1, 9'b11_1111_111,    chrsel[2:0], chr_ain[9:0]} :   // TQROM 8kb CHR-RAM
	(mapper74 && chrsel[7:1]==7'b0000100)   ? {1'b1, 11'b11_1111_1111_1,chrsel[0],   chr_ain[9:0]} :   // 2kb CHR-RAM
	(mapper191 && chrsel[7])                ? {1'b1, 11'b11_1111_1111_1,chrsel[0],   chr_ain[9:0]} :   // 2kb CHR-RAM
	(mapper192 && chrsel[7:2]==6'b000010)   ? {1'b1, 10'b11_1111_1111,  chrsel[1:0], chr_ain[9:0]} :   // 4kb CHR-RAM
	(mapper194 && chrsel[7:1]==7'b0000000)  ? {1'b1, 11'b11_1111_1111_1,chrsel[0],   chr_ain[9:0]} :   // 2kb CHR-RAM
	(mapper195 && chrsel[7:2]==6'b000000)   ? {1'b1, 10'b11_1111_1111,  chrsel[1:0], chr_ain[9:0]} :   // 4kb CHR-RAM
	(four_screen_mirroring && chr_ain[13])  ? {1'b1, 9'b11_1111_111,   chr_ain[13], chr_ain[11:0]} :   // DxROM 8kb CHR-RAM
							{flags[15], 3'b10_0, chrsel, chr_ain[9:0]};               // Standard MMC3

assign prg_is_ram = (prg_ain[15:13] == 3'b011) && ((prg_ain[12:8] == 5'b1_1111) | ~internal_128) //(>= 'h6000 && < 'h8000) && (==7Fxx or external_ram)
					&& ram_enable_a && !(ram_protect_a && prg_write);
assign prg_allow = prg_ain[15] && !prg_write || prg_is_ram && !mapper47;
wire [21:0] prg_ram = {9'b11_1100_000, internal_128 ? 6'b000000 : MMC6 ? {3'b000, prg_ain[9:7]} : prg_ain[12:7], prg_ain[6:0]};
assign prg_aout = prg_is_ram  && !mapper47 && !DxROM && !mapper95 && !mapper88 ? prg_ram : prg_aout_tmp;
assign vram_a10 = TxSROM ? chrsel[7] :              // TxSROM do not support mirroring
					mapper95 ? chrsel[5] :          // mapper95 does not support mirroring
					mapper154 ? mirroring :         // mapper154 does not support mirroring
					mapper207 ? chrsel[7] :         // mapper207 does not support mirroring
					(mirroring ? chr_ain[10] : chr_ain[11]);
assign vram_ce = chr_ain[13] && !four_screen_mirroring;

endmodule


// mapper 165
module Mapper165(
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
	input [13:0] chr_ain_o
);

assign prg_aout_b   = enable ? prg_aout : 22'hZ;
assign prg_dout_b   = enable ? prg_dout : 8'hZ;
assign prg_allow_b  = enable ? prg_allow : 1'hZ;
assign chr_aout_b   = enable ? chr_aout : 22'hZ;
assign chr_allow_b  = enable ? chr_allow : 1'hZ;
assign vram_a10_b   = enable ? vram_a10 : 1'hZ;
assign vram_ce_b    = enable ? vram_ce : 1'hZ;
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? {1'b0, audio_in[15:1]} : 16'hZ;

wire [21:0] prg_aout, chr_aout;
wire [7:0] prg_dout = 0;
wire prg_allow;
wire chr_allow;
wire vram_a10;
wire vram_ce;
reg irq;
reg [15:0] flags_out = 0;

reg [2:0] bank_select;             // Register to write to next
reg prg_rom_bank_mode;             // Mode for PRG banking
reg chr_a12_invert;                // Mode for CHR banking
reg mirroring;                     // 0 = vertical, 1 = horizontal
reg irq_enable, irq_reload;        // IRQ enabled, and IRQ reload requested
reg [7:0] irq_latch, counter;      // IRQ latch value and current counter
reg ram_enable, ram_protect;       // RAM protection bits
reg [5:0] prg_bank_0, prg_bank_1;  // Selected PRG banks
wire prg_is_ram;

reg [6:0] chr_bank_0, chr_bank_1;  // Selected CHR banks
reg [7:0] chr_bank_2, chr_bank_4;
reg latch_0, latch_1;

wire [7:0] new_counter = (counter == 0 || irq_reload) ? irq_latch : counter - 1'd1;
reg [3:0] a12_ctr;

always @(posedge clk)
if (~enable) begin
	irq <= 0;
	bank_select <= 0;
	prg_rom_bank_mode <= 0;
	chr_a12_invert <= 0;
	mirroring <= flags[14];
	{irq_enable, irq_reload} <= 0;
	{irq_latch, counter} <= 0;
	{ram_enable, ram_protect} <= 0;
	{chr_bank_0, chr_bank_1, chr_bank_2, chr_bank_4} <= 0;
	{prg_bank_0, prg_bank_1} <= 0;
	a12_ctr <= 0;
end else if (ce) begin
	if (prg_write && prg_ain[15]) begin
		case({prg_ain[14], prg_ain[13], prg_ain[0]})
			3'b00_0: {chr_a12_invert, prg_rom_bank_mode, bank_select} <= {prg_din[7], prg_din[6], prg_din[2:0]}; // Bank select ($8000-$9FFE, even)
			3'b00_1: begin // Bank data ($8001-$9FFF, odd)
				case (bank_select)
					0: chr_bank_0 <= prg_din[7:1];  // Select 2 KB CHR bank at PPU $0000-$07FF (or $1000-$17FF);
					1: chr_bank_1 <= prg_din[7:1];  // Select 2 KB CHR bank at PPU $0800-$0FFF (or $1800-$1FFF);
					2: chr_bank_2 <= prg_din;       // Select 1 KB CHR bank at PPU $1000-$13FF (or $0000-$03FF);
					3: ;                            // Select 1 KB CHR bank at PPU $1400-$17FF (or $0400-$07FF);
					4: chr_bank_4 <= prg_din;       // Select 1 KB CHR bank at PPU $1800-$1BFF (or $0800-$0BFF);
					5: ;                            // Select 1 KB CHR bank at PPU $1C00-$1FFF (or $0C00-$0FFF);
					6: prg_bank_0 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $8000-$9FFF (or $C000-$DFFF);
					7: prg_bank_1 <= prg_din[5:0];  // Select 8 KB PRG ROM bank at $A000-$BFFF
				endcase
			end
			3'b01_0: mirroring <= prg_din[0];                   // Mirroring ($A000-$BFFE, even)
			3'b01_1: {ram_enable, ram_protect} <= prg_din[7:6]; // PRG RAM protect ($A001-$BFFF, odd)
			3'b10_0: irq_latch <= prg_din;                      // IRQ latch ($C000-$DFFE, even)
			3'b10_1: irq_reload <= 1;                           // IRQ reload ($C001-$DFFF, odd)
			3'b11_0: begin irq_enable <= 0; irq <= 0; end       // IRQ disable ($E000-$FFFE, even)
			3'b11_1: irq_enable <= 1;                           // IRQ enable ($E001-$FFFF, odd)
		endcase
	end

	// Trigger IRQ counter on rising edge of chr_ain[12]
	// All MMC3A's and non-Sharp MMC3B's will generate only a single IRQ when $C000 is $00.
	// This is because this version of the MMC3 generates IRQs when the scanline counter is decremented to 0.
	// In addition, writing to $C001 with $C000 still at $00 will result in another single IRQ being generated.
	// In the community, this is known as the "alternate" or "old" behavior.
	// All MMC3C's and Sharp MMC3B's will generate an IRQ on each scanline while $C000 is $00.
	// This is because this version of the MMC3 generates IRQs when the scanline counter is equal to 0.
	// In the community, this is known as the "normal" or "new" behavior.
	if (chr_ain_o[12] && a12_ctr == 0) begin
		counter <= new_counter;

		if ((counter != 0 || irq_reload) && new_counter == 0 && irq_enable) begin
			irq <= 1;
		end

		irq_reload <= 0;
	end

	a12_ctr <= chr_ain_o[12] ? 4'b1111 : (a12_ctr != 0) ? a12_ctr - 4'b0001 : a12_ctr;
end

// The PRG bank to load. Each increment here is 8kb. So valid values are 0..63.
reg [5:0] prgsel;
always @* begin
	casez({prg_ain[14:13], prg_rom_bank_mode})
		3'b00_0: prgsel = prg_bank_0;  // $8000 mode 0
		3'b00_1: prgsel = 6'b111110;   // $8000 fixed to second last bank
		3'b01_?: prgsel = prg_bank_1;  // $A000 mode 0,1
		3'b10_0: prgsel = 6'b111110;   // $C000 fixed to second last bank
		3'b10_1: prgsel = prg_bank_0;  // $C000 mode 1
		3'b11_?: prgsel = 6'b111111;   // $E000 fixed to last bank
	endcase
end

wire [21:0] prg_aout_tmp = {3'b00_0,  prgsel, prg_ain[12:0]};

// PPU reads $0FD0: latch 0 is set to $FD for subsequent reads
// PPU reads $0FE0: latch 0 is set to $FE for subsequent reads
// PPU reads $1FD0 through $1FDF: latch 1 is set to $FD for subsequent reads
// PPU reads $1FE0 through $1FEF: latch 1 is set to $FE for subsequent reads
always @(posedge clk)
if (ce && chr_read) begin
	latch_0 <= (chr_ain & 14'h3fff) == 14'h0fd0 ? 1'd0 : (chr_ain & 14'h3fff) == 14'h0fe0 ? 1'd1 : latch_0;
	latch_1 <= (chr_ain & 14'h3ff0) == 14'h1fd0 ? 1'd0 : (chr_ain & 14'h3ff0) == 14'h1fe0 ? 1'd1 : latch_1;
end

// The CHR bank to load. Each increment here is 1kb. So valid values are 0..255.
reg [7:0] chrsel;
always @* begin
	casez({chr_ain[12] ^ chr_a12_invert, latch_0, latch_1})
		3'b0_0?: chrsel = {chr_bank_0, chr_ain[10]}; // 2Kb page
		3'b0_1?: chrsel = {chr_bank_1, chr_ain[10]}; // 2Kb page
		3'b1_?0: chrsel = chr_bank_2;
		3'b1_?1: chrsel = chr_bank_4;
	endcase
end

assign {chr_allow, chr_aout} = {flags[15] && (chrsel < 4), 4'b10_00, chrsel, chr_ain[9:0]};

assign prg_is_ram = prg_ain >= 'h6000 && prg_ain < 'h8000 && ram_enable && !(ram_protect && prg_write);
assign prg_allow = prg_ain[15] && !prg_write || prg_is_ram;
wire [21:0] prg_ram = {9'b11_1100_000, prg_ain[12:0]};
assign prg_aout = prg_is_ram ? prg_ram : prg_aout_tmp;
assign vram_a10 = mirroring ? chr_ain[11] : chr_ain[10];
assign vram_ce = chr_ain[13];

endmodule
