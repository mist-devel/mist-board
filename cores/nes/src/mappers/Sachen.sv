// Sachen Mappers

// 137, 138, 139, 141 - Sachen 8259
// 150, 243 - Sachen 74LS374N
module Sachen8259(
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
assign prg_dout_b   = enable ? prg_dout : 8'hZ;
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
wire [15:0] flags_out = {14'd0, prg_bus_write, 1'b0};

// 0x4100
wire [7:0] prg_dout = {5'b00111, (~register)}; // ^ (counter & 0x1)
wire prg_bus_write = ({prg_ain[15:14], prg_ain[8], prg_ain[0]} == 4'b0110);

wire mapper137 = (flags[7:0] == 137);
wire mapper138 = (flags[7:0] == 138);
wire mapper139 = (flags[7:0] == 139);
wire mapper141 = (flags[7:0] == 141);
wire mapper150 = (flags[7:0] == 150);
wire mapper243 = (flags[7:0] == 243);

reg [2:0] register;
reg [2:0] prg_bank;
reg [2:0] chr_bank_0, chr_bank_1, chr_bank_2, chr_bank_3, chr_bank_o, chr_bank_p;
reg [2:0] mirroring;

always @(posedge clk)
if (~enable) begin
	//any resets?
end else if (ce && prg_write) begin
	if ({prg_ain[15:14], prg_ain[8], prg_ain[0]} == 4'b0110) begin
		register <= prg_din[2:0];
	end else if ({prg_ain[15:14], prg_ain[8], prg_ain[0]} == 4'b0111) begin
		case (register)
			0: begin 
			   chr_bank_0 <= prg_din[2:0];  // Select 2 KB CHR bank at PPU $0000-$07FF;
				if (mapper243) {prg_bank, chr_bank_2[0], chr_bank_p[1:0], chr_bank_o[0]} = 7'b000_0011;
				end
			1: chr_bank_1 <= prg_din[2:0];  // Select 2 KB CHR bank at PPU $0800-$0FFF;
			2: begin
			   chr_bank_2 <= prg_din[2:0];  // Select 2 KB CHR bank at PPU $1000-$17FF;
				if (mapper150) prg_bank = {2'b00, prg_din[0]};
				end
			3: chr_bank_3 <= prg_din[2:0];  // Select 2 KB CHR bank at PPU $1800-$1FFF;
			4: chr_bank_o <= prg_din[2:0];  // Outer CHR bank
			5: prg_bank   <= prg_din[2:0];  // Select 32 KB PRG ROM bank at $8000-$FFFF;
			6: chr_bank_p <= prg_din[2:0];  // Outer CHR bank
			7: mirroring  <= prg_din[2:0];  // Select Mirroring
		endcase
	end
end

// The CHR bank to load. Each increment here is 1kb. So valid values are 0..255.
wire [2:0] chr_bank;
wire [2:0] chr_banko;
reg [8:0] chrsel;
always @* begin
	casez({mirroring[0], mapper137 ? chr_ain[11:10] : chr_ain[12:11]})
		3'b000: chr_bank = chr_bank_0;
		3'b001: chr_bank = chr_bank_1;
		3'b010: chr_bank = chr_bank_2;
		3'b011: chr_bank = chr_bank_3;
		3'b1??: chr_bank = chr_bank_0;
	endcase
	casez({mapper137, chr_ain[11:10]})
		3'b0??: chr_banko = chr_bank_o;
		3'b100: chr_banko = 3'b000;
		3'b101: chr_banko = {1'b0, chr_bank_o[0], 1'b0};
		3'b110: chr_banko = {1'b0, chr_bank_o[1], 1'b0};
		3'b111: chr_banko = {1'b0, chr_bank_o[2], chr_bank_p[0]};
	endcase
	if (mapper137)
		chrsel = chr_ain[12] ? {7'h7F, chr_ain[11:10]} : {3'b111, chr_banko, chr_bank};
	else if (mapper138)
		chrsel = {2'b11, chr_banko, chr_bank, chr_ain[10]};
	else if (mapper141)
		chrsel = {1'b1, chr_banko, chr_bank, chr_ain[11:10]};
	else if (mapper139)
		chrsel = {chr_banko, chr_bank, chr_ain[12:10]};
	else if (mapper150)
		chrsel = {2'b00, chr_bank_2[0], chr_bank_o[0], chr_bank_p[1:0], chr_ain[12:10]};
	else if (mapper243)
		chrsel = {2'b00, chr_bank_2[0], chr_bank_p[1:0], chr_bank_o[0], chr_ain[12:10]};
	else
		chrsel = 9'h000;
end

always @* begin
	casez(mapper150 ? {mirroring[2:1], 1'b0} : mapper243 ? {1'b0, mirroring[0], 1'b0} : mirroring)
		3'b??1: vram_a10 = chr_ain[10];
		3'b000: vram_a10 = chr_ain[10];
		3'b010: vram_a10 = chr_ain[11];
		3'b100: vram_a10 = chr_ain[10] | chr_ain[11];
		3'b110: vram_a10 = 1'b0;
	endcase
end

assign prg_aout = {4'b00_00, prg_bank, prg_ain[14:0]};
assign chr_allow = flags[15];
assign chr_aout = {3'b10_0, chrsel, chr_ain[9:0]};
assign vram_ce = chr_ain[13];
//assign vram_a10 = ; //done above
assign prg_allow = prg_ain[15] && !prg_write;

endmodule

// #136,#147 - Sachen JV001
// #36, #132 - TXC
// #173 - Idea-Tek
// #172 - Super Mega P-4070
module SachenJV001(
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
assign prg_dout_b   = enable ? prg_dout : 8'hZ;
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
wire [15:0] flags_out = {14'd0, prg_bus_write, 1'b0};

reg [5:0] input_reg; //s_reg = input_reg[3]
reg [5:0] output_reg;
reg [5:0] register_reg;
reg inc_reg;
reg invert_reg;
reg [3:0] alt_chr;
reg mirroring;

//wire mapper136 = (flags[7:0] == 136); //default
wire mapper132 = (flags[7:0] == 132);
wire mapper147 = (flags[7:0] == 147);
wire mapper173 = (flags[7:0] == 173);
wire mapper172 = (flags[7:0] == 172);
wire mapper36  = (flags[7:0] == 36);

wire [7:0] prg_din_adj = mapper147 ? {2'b00, prg_din[7:2]} :
                         mapper36 ?  {4'b0000, prg_din[7:4]} : 
								 mapper172 ? {2'b00, prg_din[0], prg_din[1], prg_din[2], prg_din[3], prg_din[4], prg_din[5]} :
								             prg_din;

wire prg_bus_write = (prg_ain[15:13] == 3'b010 && prg_ain[8]); //0x4100-3

always @(posedge clk)
if (~enable) begin
	//
end else if (ce) begin
	if (prg_ain[15:13] == 3'b010 && prg_ain[8] && prg_write) //0x4100-3
		case (prg_ain[1:0])
			0: begin
				if (inc_reg)
					register_reg[3:0] <= register_reg[3:0] + 4'b1;
				else
					register_reg <= invert_reg ? {input_reg[5:4], ~input_reg[3:0]} : input_reg;
			   end
			1: invert_reg <= prg_din_adj[0];
			2: input_reg  <= prg_din_adj[5:0];
			3: inc_reg    <= prg_din_adj[0];
		endcase
	if (prg_ain[15:13] == 3'b010 && prg_ain[9] && prg_write) //0x4200
		alt_chr <= prg_din[3:0];
	if (prg_ain[15] == 1'b1 && prg_write) begin
		output_reg <= register_reg;
		mirroring <= invert_reg;
	end
end

// 0x4100-3
wire use_s = mapper132 | mapper173;
wire [5:0] V001_val = (use_s ? {2'b00, input_reg[3], register_reg[2:0]} : register_reg) ^ (invert_reg ? (use_s ? 6'h08 : 6'h30) : 6'h00);

wire [7:0] prg_dout = mapper172 ? {chr_ain[7:6], V001_val[0], V001_val[1], V001_val[2], V001_val[3], V001_val[4], V001_val[5]} :
                      mapper147 ? {V001_val, chr_ain[1:0]} :
							             {chr_ain[7:6], V001_val}; // two bits are open bus

wire [3:0] chr_sel = mapper36 ? alt_chr :
                     mapper173 ? {2'b00, ~invert_reg, output_reg[0]} :
							mapper147 ? {output_reg[4:1]} :
							mapper172 ? {2'b00, output_reg[1:0]} :
							            {2'b00, output_reg[1:0]};

wire [1:0] prg_sel = mapper147 ? {output_reg[5], output_reg[0]} :
                     mapper132 ? {1'b0, output_reg[2]} :
							mapper36  ? {output_reg[1:0]} :
							            2'b00;

assign prg_aout = {5'b00_000, prg_sel, prg_ain[14:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign chr_allow = flags[15];
assign chr_aout = {5'b10_000, chr_sel, chr_ain[12:0]};
assign vram_ce = chr_ain[13];
assign vram_a10 = (mapper172 ? mirroring : flags[14]) ? chr_ain[10] : chr_ain[11]; // 0: horiz, 1: vert

endmodule

// #143 - Sachen NROM with protection
module SachenNROM(
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
assign prg_dout_b   = enable ? prg_dout : 8'hZ;
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
wire prg_bus_write;
wire [15:0] flags_out = {14'h0, prg_bus_write, 1'b0};

// 0x4100
wire [7:0] prg_dout = {2'b01, ~prg_ain[5:0]}; // top 2 bits are actually open bus
assign prg_bus_write = ((prg_ain[15:13] == 3'b010) && prg_ain[8]);

assign prg_aout = {7'b00_0000_0, prg_ain[14:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign chr_allow = flags[15];
assign chr_aout = {9'b10_0000_000, chr_ain[12:0]};
assign vram_ce = chr_ain[13];
assign vram_a10 = flags[14] ? chr_ain[10] : chr_ain[11]; // 0: horiz, 1: vert

endmodule
