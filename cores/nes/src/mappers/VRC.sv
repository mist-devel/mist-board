// Konami VRC Mappers

// VRC1 (75)
module VRC1(
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

reg [3:0] prg_bank0, prg_bank1, prg_bank2;
reg [4:0] chr_bank0, chr_bank1;
reg [1:0] mirroring;
reg [3:0] prg_tmp;
reg [4:0] chr_tmp;

always @(posedge clk)
	if (~enable) begin
		// Set value for mirroring
		mirroring[1:0] <= {flags[16], !flags[14]};
	end else if (ce) begin
		if (prg_ain[15] & prg_write) begin
			case (prg_ain[14:12])
			3'b000:  prg_bank0      <= prg_din[3:0];  // PRG bank 0x8000-0x9FFF
			3'b001:  {chr_bank1[4],chr_bank0[4],mirroring[0]} <= prg_din[2:0];
			3'b010:  prg_bank1      <= prg_din[3:0];  // PRG bank 0xA000-0xBFFF
			3'b100:  prg_bank2      <= prg_din[3:0];  // PRG bank 0xC000-0xEFFF
			3'b110:  chr_bank0[3:0] <= prg_din[3:0];  // CHR bank 0x0000-0x0FFF
			3'b111:  chr_bank1[3:0] <= prg_din[3:0];  // CHR bank 0x1000-0x1FFF
			endcase
		end
	end

always begin
	// mirroring mode
	casez(mirroring[1:0])
		2'b00   :   vram_a10 = {chr_ain[10]};    // vertical
		2'b01   :   vram_a10 = {chr_ain[11]};    // horizontal
		2'b1?   :   vram_a10 = {mirroring[0]};   // 4 screen // Not implemented
	endcase

	// PRG ROM bank size select
	casez(prg_ain[14:13])
		2'b00 : prg_tmp = prg_bank0;
		2'b01 : prg_tmp = prg_bank1;
		2'b10 : prg_tmp = prg_bank2;
		2'b11 : prg_tmp = 4'b1111;
	endcase

	// PRG ROM bank size select
	casez(chr_ain[12])
		1'b0 : chr_tmp = chr_bank0;
		1'b1 : chr_tmp = chr_bank1;
	endcase
end

assign vram_ce = chr_ain[13];
assign prg_aout = {5'b00_000, prg_tmp, prg_ain[12:0]};
assign prg_allow = prg_ain[15] && !prg_write;
assign chr_allow = flags[15];
assign chr_aout = {5'b10_000, chr_tmp, chr_ain[11:0]};

endmodule

// VRC3 (73)
module VRC3(
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
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? {1'b0, audio_in[15:1]} : 16'hZ;

wire [21:0] prg_aout, chr_aout;
wire prg_allow;
wire chr_allow;
wire vram_a10;
wire vram_ce;
reg irq;
reg [15:0] flags_out = 0;


reg [2:0] prg_bank;
reg [4:0] irq_enable;
reg [15:0] irq_latch;
reg [15:0] irq_counter;

always @(posedge clk)
if (~enable) begin
	// Set value for mirroring
	irq <= 0;
	prg_bank <= 0;
	irq_enable <= 0;
	irq_latch <= 0;
end else if (ce) begin
	irq_enable[3] <= 1'b0;
	if (prg_ain[15] & prg_write) begin
		case (prg_ain[14:12])
			3'b000:  irq_latch[3:0]   <= prg_din[3:0];
			3'b001:  irq_latch[7:4]   <= prg_din[3:0];
			3'b010:  irq_latch[11:8]  <= prg_din[3:0];
			3'b011:  irq_latch[15:12] <= prg_din[3:0];
			3'b100:  irq_enable[4:0]  <= {2'b11, prg_din[2:0]};
			3'b101:  irq_enable[4:3]  <= 2'b01;
			3'b111:  prg_bank         <= prg_din[2:0];  // PRG bank 0x8000-0xBFFF
		endcase
	end

	if (irq_enable[1]) begin
		irq_counter[7:0] <= irq_counter[7:0] + 8'd1;
		if (irq_counter[7:0] == 8'hFF) begin
			if (irq_enable[2]) begin
				irq <= 1'b1;	// IRQ
			end else begin
				irq_counter[15:8] <= irq_counter[15:8] + 8'd1;
				if (irq_counter[15:8] == 8'hFF) begin
					irq <= 1'b1;	// IRQ
				end
			end
		end
	end

	if (irq_enable[3]) begin
		irq <= 1'b0;	// IRQ ACK
		if (irq_enable[4])
			irq_counter <= irq_latch;
		else
			irq_enable[1] <= irq_enable[0];
	end
end

assign vram_ce = chr_ain[13];
assign vram_a10 = flags[14] ? chr_ain[10] : chr_ain[11];
wire prg_is_ram = (prg_ain[15:13] == 3'b011);//prg_ain >= 'h6000 && prg_ain < 'h8000;
assign prg_aout = prg_is_ram ? {9'b11_1100_000, prg_ain[12:0]} : {5'b00_000, prg_ain[14] ? 3'b111 : prg_bank, prg_ain[13:0]};
assign prg_allow = (prg_ain[15] && !prg_write) || prg_is_ram;
assign chr_allow = flags[15];
assign chr_aout = {8'b10_0000_00, chr_ain[13:0]};

endmodule

// VRC2 and VRC4
module VRC24(
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
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? {1'b0, audio_in[15:1]} : 16'hZ;

wire [21:0] prg_aout, chr_aout;
wire prg_allow;
wire chr_allow;
reg vram_a10;
wire vram_ce;
wire irq;
reg [15:0] flags_out = 0;


reg [4:0] prg_bank0, prg_bank1;
reg [8:0] chr_bank0, chr_bank1, chr_bank2, chr_bank3, chr_bank4, chr_bank5, chr_bank6, chr_bank7;
reg [1:0] mirroring;
reg [4:0] prg_tmp;
reg [8:0] chr_tmp;
reg prg_invert;
wire mapper21 = (flags[7:0] == 21);
wire mapper22 = (flags[7:0] == 22);
wire mapper23 = (flags[7:0] == 23 | flags[7:0] == 27);
//wire mapper25 = (flags[7:0] == 25); //default
wire mapperVRC4 = (flags[7:0] != 22) && (flags[24:21] != 3);
wire [1:0] registers = {mapper21 ?  {(prg_ain[7]|prg_ain[2]),(prg_ain[6]|prg_ain[1])} :
                        mapper22 ?  {(prg_ain[0]),           (prg_ain[1])           } :
                        mapper23 ?  {(prg_ain[3]|prg_ain[1]),(prg_ain[2]|prg_ain[0])} :
                        /*mapper25*/{(prg_ain[2]|prg_ain[0]),(prg_ain[3]|prg_ain[1])}};

always @(posedge clk)
	if (~enable) begin
		// Set value for mirroring
		mirroring[1:0] <= {1'b0, !flags[14]};
		prg_invert <= 0;
		prg_bank0 <= 5'd0;
		prg_bank1 <= 5'd1;
		chr_bank0 <= 9'd0;
		chr_bank1 <= 9'd1;
		chr_bank2 <= 9'd2;
		chr_bank3 <= 9'd3;
		chr_bank4 <= 9'd4;
		chr_bank5 <= 9'd5;
		chr_bank6 <= 9'd6;
		chr_bank7 <= 9'd7;
	end else if (ce) begin
		if (prg_ain[15] & prg_write) begin
			casez ({prg_ain[14:12], registers, mapperVRC4})
				6'b000_??_?:  prg_bank0      <= prg_din[4:0];  // PRG bank 0x8000-0x9FFF or 0xC000-0xDFFF
				6'b001_??_0:  mirroring[0]   <= prg_din[0];
				6'b001_0?_1:  mirroring      <= prg_din[1:0];
				6'b001_1?_1:  prg_invert     <= prg_din[1];
				6'b010_??_?:  prg_bank1      <= prg_din[4:0];  // PRG bank 0xA000-0xBFFF
				6'b011_00_?:  chr_bank0[3:0] <= prg_din[3:0];  // CHR bank 0x0000-0x03FF
				6'b011_01_?:  chr_bank0[8:4] <= prg_din[4:0];  // CHR bank 0x0000-0x03FF
				6'b011_10_?:  chr_bank1[3:0] <= prg_din[3:0];  // CHR bank 0x0400-0x07FF
				6'b011_11_?:  chr_bank1[8:4] <= prg_din[4:0];  // CHR bank 0x0400-0x07FF
				6'b100_00_?:  chr_bank2[3:0] <= prg_din[3:0];  // CHR bank 0x0800-0x0BFF
				6'b100_01_?:  chr_bank2[8:4] <= prg_din[4:0];  // CHR bank 0x0800-0x0BFF
				6'b100_10_?:  chr_bank3[3:0] <= prg_din[3:0];  // CHR bank 0x0C00-0x0FFF
				6'b100_11_?:  chr_bank3[8:4] <= prg_din[4:0];  // CHR bank 0x0C00-0x0FFF
				6'b101_00_?:  chr_bank4[3:0] <= prg_din[3:0];  // CHR bank 0x1000-0x13FF
				6'b101_01_?:  chr_bank4[8:4] <= prg_din[4:0];  // CHR bank 0x1000-0x13FF
				6'b101_10_?:  chr_bank5[3:0] <= prg_din[3:0];  // CHR bank 0x1400-0x17FF
				6'b101_11_?:  chr_bank5[8:4] <= prg_din[4:0];  // CHR bank 0x1400-0x17FF
				6'b110_00_?:  chr_bank6[3:0] <= prg_din[3:0];  // CHR bank 0x1800-0x1BFF
				6'b110_01_?:  chr_bank6[8:4] <= prg_din[4:0];  // CHR bank 0x1800-0x1BFF
				6'b110_10_?:  chr_bank7[3:0] <= prg_din[3:0];  // CHR bank 0x1C00-0x1FFF
				6'b110_11_?:  chr_bank7[8:4] <= prg_din[4:0];  // CHR bank 0x1C00-0x1FFF
				//6'b111_??_1:  IRQ Stuff;  // IRQ
			endcase
		end
	end

always begin
	// mirroring mode
	casez(mirroring[1:0])
		2'b00   :   vram_a10 = {chr_ain[10]};    // vertical
		2'b01   :   vram_a10 = {chr_ain[11]};    // horizontal
		2'b1?   :   vram_a10 = {mirroring[0]};   // 1 screen
	endcase

	// PRG ROM bank size select
	casez({prg_ain[14:13],prg_invert})
		3'b00_0 : prg_tmp = prg_bank0;
		3'b00_1 : prg_tmp = 5'b11110;
		3'b01_? : prg_tmp = prg_bank1;
		3'b10_0 : prg_tmp = 5'b11110;
		3'b10_1 : prg_tmp = prg_bank0;
		3'b11_? : prg_tmp = 5'b11111;
	endcase

	// PRG ROM bank size select
	casez(chr_ain[12:10])
		3'b000 : chr_tmp = chr_bank0;
		3'b001 : chr_tmp = chr_bank1;
		3'b010 : chr_tmp = chr_bank2;
		3'b011 : chr_tmp = chr_bank3;
		3'b100 : chr_tmp = chr_bank4;
		3'b101 : chr_tmp = chr_bank5;
		3'b110 : chr_tmp = chr_bank6;
		3'b111 : chr_tmp = chr_bank7;
	endcase
end

assign vram_ce = chr_ain[13];
wire [21:13] prg_aout_tmp = {4'b00_00, prg_tmp};
wire [21:13] prg_ram = {9'b11_1100_000};
wire prg_is_ram = (prg_ain[15:13] == 3'b011);//prg_ain >= 'h6000 && prg_ain < 'h8000;
assign prg_aout[21:13] = prg_is_ram ? prg_ram : prg_aout_tmp;
assign prg_aout[12:0] = prg_ain[12:0];
assign prg_allow = (prg_ain[15] && !prg_write) || prg_is_ram;
assign chr_allow = flags[15];
assign chr_aout = {3'b10_0, vram_ce ? {5'b00000, chr_ain[13:10]} : mapper22 ? {1'b0, chr_tmp[8:1]} : chr_tmp, chr_ain[9:0]};

wire irqll = {prg_ain[15:12],registers[1:0]}==6'b1111_00; // 0xF000
wire irqlh = {prg_ain[15:12],registers[1:0]}==6'b1111_01; // 0xF001
wire irqc  = {prg_ain[15:12],registers[1:0]}==6'b1111_10; // 0xF002
wire irqa  = {prg_ain[15:12],registers[1:0]}==6'b1111_11; // 0xF003
wire irqout;
assign irq = irqout & mapperVRC4;
vrcIRQ vrc4irq(clk,enable,prg_write,{irqlh,irqll},irqc,irqa,prg_din,irqout,ce);

endmodule

module VRC6(
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
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? audio : 16'hZ;

wire [21:0] prg_aout, chr_aout;
wire [7:0] prg_dout;
wire prg_allow;
wire chr_allow;
wire vram_a10;
wire vram_ce;
wire irq;
wire [15:0] audio = audio_in;
reg [15:0] flags_out = 0;

wire nesprg_oe;
wire [7:0] neschrdout;
wire neschr_oe;
wire wram_oe;
wire wram_we;
wire prgram_we;
wire chrram_oe;
wire prgram_oe;
wire [18:13] ramprgaout;
//wire exp6;
reg [7:0] m2;
wire m2_n = 1;//~ce;  //m2_n not used as clk.  Invert m2 (ce).

always @(posedge clk) begin
	m2[7:1] <= m2[6:0];
	m2[0] <= ce;
end

MAPVRC6 vrc6(m2[7], m2_n, clk, enable, prg_write, nesprg_oe, 0,
	1, prg_ain, chr_ain, prg_din, 8'b0, prg_dout,
	neschrdout, neschr_oe, chr_allow, chrram_oe, wram_oe, wram_we, prgram_we,
	prgram_oe, chr_aout[18:10], ramprgaout, irq, vram_ce,// exp6,
	0, 7'b1111111, 6'b111111, flags[14], flags[16], flags[15],
	ce, flags[1]);

assign chr_aout[21:19] = 3'b100;
assign chr_aout[9:0] = chr_ain[9:0];
assign vram_a10 = chr_aout[10];
wire [21:13] prg_aout_tmp = {3'b00_0, ramprgaout};
wire [21:13] prg_ram = {9'b11_1100_000};
wire prg_is_ram = prg_ain >= 'h6000 && prg_ain < 'h8000;
assign prg_aout[21:13] = prg_is_ram ? prg_ram : prg_aout_tmp;
assign prg_aout[12:0] = prg_ain[12:0];
assign prg_allow = (prg_ain[15] && !prg_write) || prg_is_ram;

endmodule

module VRC7(
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
assign irq_b        = enable ? irq : 1'hZ;
assign flags_out_b  = enable ? flags_out : 16'hZ;
assign audio_b      = enable ? audio : 16'hZ;

wire [21:0] prg_aout, chr_aout;
wire prg_allow;
wire chr_allow;
wire vram_a10;
wire vram_ce;
wire irq;
reg [15:0] flags_out = 0;
wire [15:0] audio = audio_in;

assign chr_aout[21:18] = 4'b1000;
assign chr_aout[9:0] = chr_ain[9:0];
assign chr_aout[17:11] = chrbank[17:11];
assign chr_aout[10]=!chr_ain[13] ? chrbank[10] : ((mirror==0 & chr_ain[10]) | (mirror==1 & chr_ain[11]) | (mirror==3));
assign vram_ce=chr_ain[13];
assign vram_a10=chr_aout[10];
assign chr_allow=!chr_ain[13] & flags[15];

wire [21:13] prg_aout_tmp = {3'b00_0, prgbankin};
wire [21:13] prg_ram = {9'b11_1100_000};
wire prg_is_ram = prg_ain >= 'h6000 && prg_ain < 'h8000;
assign prg_aout[21:13] = prg_is_ram ? prg_ram : prg_aout_tmp;
assign prg_aout[12:0] = prg_ain[12:0];
assign prg_allow = (prg_ain[15] && !prg_write) || (prg_is_ram && (!prg_write || ramw));

reg [7:0] chrbank0, chrbank1, chrbank2, chrbank3, chrbank4, chrbank5, chrbank6, chrbank7;
reg [1:0] mirror;
reg [5:0] prgbank8;
reg [5:0] prgbankA;
reg [5:0] prgbankC;
wire prg_ain43 = prg_ain[4] ^ prg_ain[3];
reg ramw;

always@(posedge clk) begin
	if (~enable) begin
		{chrbank0, chrbank1, chrbank2, chrbank3, chrbank4, chrbank5, chrbank6, chrbank7} <= 0;
		{prgbank8, prgbankA, prgbankC} <= 0;
		ramw <= 0;
	end else if(ce && prg_write) begin
		casex({prg_ain[15:12],prg_ain43})
			5'b10000:prgbank8<=prg_din[5:0]; //8000
			5'b10001:prgbankA<=prg_din[5:0]; //8008/10
			5'b10010:prgbankC<=prg_din[5:0]; //9000
			5'b10100:chrbank0<=prg_din;      //A000
			5'b10101:chrbank1<=prg_din;      //A008/10
			5'b10110:chrbank2<=prg_din;      //B000
			5'b10111:chrbank3<=prg_din;      //B008/10
			5'b11000:chrbank4<=prg_din;      //C000
			5'b11001:chrbank5<=prg_din;      //C008/10
			5'b11010:chrbank6<=prg_din;      //D000
			5'b11011:chrbank7<=prg_din;      //D008/10
			5'b11100:{ramw,mirror}<={prg_din[7],prg_din[1:0]};   //E000
			//5'b11101:irqlatch<=nesprgdin;      //E008/10
			//5'b11110:{irqM,irqA}<={nesprgdin[2],nesprgdin[0]}; //F000
		endcase
	end
end

reg [18:13] prgbankin;
reg [17:10] chrbank;
always@* begin
	casex(prg_ain[15:13])
		3'b100:prgbankin=prgbank8;                  //89
		3'b101:prgbankin=prgbankA;                  //AB
		3'b110:prgbankin=prgbankC;                  //CD
		default:prgbankin=6'b111111;                //EF
	endcase

	case(chr_ain[12:10])
		0:chrbank=chrbank0;
		1:chrbank=chrbank1;
		2:chrbank=chrbank2;
		3:chrbank=chrbank3;
		4:chrbank=chrbank4;
		5:chrbank=chrbank5;
		6:chrbank=chrbank6;
		7:chrbank=chrbank7;
	endcase
end

wire irql = {prg_ain[15:12],prg_ain43}==5'b11101; // 0xE008 or 0xE010
wire irqc = {prg_ain[15:12],prg_ain43}==5'b11110; // 0xF000
wire irqa = {prg_ain[15:12],prg_ain43}==5'b11111; // 0xF008 or 0xF010

vrcIRQ vrc7irq(clk,enable,prg_write,{irql,irql},irqc,irqa,prg_din,irq,ce);

endmodule


//Taken from Loopy's Power Pak mapper source mapVRC6.v
// change ain below to set VRC6 variant
module MAPVRC6(     //signal descriptions in powerpak.v
	input m2,
	input m2_n,
	input clk20,

	input enable,
	input nesprg_we,
	output nesprg_oe,
	input neschr_rd,
	input neschr_wr,
	input [15:0] prgain,
	input [13:0] chrain,
	input [7:0] nesprgdin,
	input [7:0] ramprgdin,
	output [7:0] nesprgdout,

	output [7:0] neschrdout,
	output neschr_oe,

	output chrram_we,
	output chrram_oe,
	output wram_oe,
	output wram_we,
	output prgram_we,
	output prgram_oe,
	output [18:10] ramchraout,
	output [18:13] ramprgaout,
	output irq,
	output ciram_ce,

//	output exp6,

	input cfg_boot,
	input [18:12] cfg_chrmask,
	input [18:13] cfg_prgmask,
	input cfg_vertical,
	input cfg_fourscreen,
	input cfg_chrram,

	input ce,// add
	//output [15:0] audio,
	input mapper26

);
	//wire [15:0] ain=prgain;                             //MAP18
	//wire [15:0] ain={prgain[15:2],prgain[0],prgain[1]}; //MAP1A
	wire [15:0] ain=mapper26 ? {prgain[15:2],prgain[0],prgain[1]} :  prgain; //MAP1A : MAP18

	reg [4:0] prgbank8;
	reg [5:0] prgbankC;
	reg [7:0] chrbank0, chrbank1, chrbank2, chrbank3, chrbank4, chrbank5, chrbank6, chrbank7;
	reg [1:0] mirror;
	//reg [7:0] irqlatch;
	//reg irqM,irqE,irqA;
	wire irql = {ain[15:12],ain[1:0]}==6'b111100;
	wire irqc = {ain[15:12],ain[1:0]}==6'b111101;
	wire irqa = {ain[15:12],ain[1:0]}==6'b111110;
	always@(posedge clk20) begin
		if (~enable)
			{prgbank8, prgbankC, mirror, chrbank0, chrbank1, chrbank2,
				chrbank3, chrbank4, chrbank5, chrbank6, chrbank7} <= 0;
		else if(ce && nesprg_we) begin
			casex({ain[15:12],ain[1:0]})
				6'b1000xx:prgbank8<=nesprgdin[4:0]; //800x
				6'b1100xx:prgbankC<=nesprgdin[5:0]; //C00x
				6'b101111:mirror<=nesprgdin[3:2];   //B003
				6'b110100:chrbank0<=nesprgdin;      //D000
				6'b110101:chrbank1<=nesprgdin;      //D001
				6'b110110:chrbank2<=nesprgdin;      //D002
				6'b110111:chrbank3<=nesprgdin;      //D003
				6'b111000:chrbank4<=nesprgdin;      //E000
				6'b111001:chrbank5<=nesprgdin;      //E001
				6'b111010:chrbank6<=nesprgdin;      //E002
				6'b111011:chrbank7<=nesprgdin;      //E003
				//6'b111100:irqlatch<=nesprgdin;      //F000
				//6'b111101:{irqM,irqA}<={nesprgdin[2],nesprgdin[0]}; //F001
			endcase
		end
	end

	//bankswitch
	reg [18:13] prgbankin;
	reg [17:10] chrbank;
	always@* begin
		casex(prgain[15:13])
			3'b0xx:prgbankin=0;                         //sram
			3'b10x:prgbankin={prgbank8,prgain[13]};     //89AB
			3'b110:prgbankin=prgbankC;                  //CD
			default:prgbankin=6'b111111;                //EF
		endcase
		case(chrain[12:10])
			0:chrbank=chrbank0;
			1:chrbank=chrbank1;
			2:chrbank=chrbank2;
			3:chrbank=chrbank3;
			4:chrbank=chrbank4;
			5:chrbank=chrbank5;
			6:chrbank=chrbank6;
			7:chrbank=chrbank7;
		endcase
		if (~enable) begin
			prgbankin = 0;
			chrbank = 0;
		end
	end

	vrcIRQ vrc6irq(clk20,enable,nesprg_we,{irql,irql},irqc,irqa,nesprgdin,irq,ce);

//mirroring
	assign ramchraout[10]=!chrain[13] ? chrbank[10] : ((mirror==0 & chrain[10]) | (mirror==1 & chrain[11]) | (mirror==3));
	assign ramchraout[11]=chrbank[11];
	assign ciram_ce=chrain[13];

//rom size mask
	assign ramprgaout[18:13]=prgbankin[18:13] & cfg_prgmask;
	assign ramchraout[18:12]={1'b0,chrbank[17:12]} & cfg_chrmask;

//ram control
	assign chrram_we=neschr_wr & !chrain[13] & cfg_chrram;
	assign chrram_oe=neschr_rd & !chrain[13];

	assign neschr_oe=0;
	assign neschrdout=0;

	assign wram_oe=m2_n & ~nesprg_we & prgain[15:13]=='b011;
	assign wram_we=m2_n &  nesprg_we & prgain[15:13]=='b011;

	assign prgram_we=0;
	assign prgram_oe=~cfg_boot & m2_n & ~nesprg_we & prgain[15];

	wire config_rd = 0;
	assign nesprgdout=8'b0;
	assign nesprg_oe=wram_oe | prgram_oe | config_rd;

endmodule

module vrcIRQ(
	input clk20,
	input enable,
	input nesprg_we,
	input [1:0] irqlatch_add,
	input irqctrl_add,
	input irqack_add,
	input [7:0] nesprgdin,
	output irq,
	input ce
);

reg [7:0] irqlatch;
reg irqM,irqE,irqA;
always@(posedge clk20) begin
	if (~enable)
		{irqM, irqA, irqlatch} <= 0;
	else if(ce && nesprg_we) begin
		if (irqlatch_add == 2'b11)
			irqlatch<=nesprgdin;                      //F000
		else if (irqlatch_add == 2'b10)
			irqlatch[7:4]<=nesprgdin[3:0];            //F000h
		else if (irqlatch_add == 2'b01)
			irqlatch[3:0]<=nesprgdin[3:0];            //F000l
		else if (irqctrl_add)
			{irqM,irqA}<={nesprgdin[2],nesprgdin[0]}; //F001
	end
end

//IRQ
reg [7:0] irqcnt;
reg timeout;
reg [6:0] scalar;
reg [1:0] line;
wire irqclk=irqM|(scalar==0);
wire setE=nesprg_we & irqctrl_add & nesprgdin[1];
always@(posedge clk20) begin
	if (~enable)
		{irqcnt, scalar, line} <= 0;
	else if(setE) begin
		scalar<=113;
		line<=0;
		irqcnt<=irqlatch;
	end else if(ce && irqE) begin
		if(scalar!=0)
			scalar<=scalar-1'd1;
		else begin
			scalar<=(~line[1])?7'd113:7'd112;
			line<=line[1]?2'd0:line+1'd1;
		end
		if(irqclk) begin
			if(irqcnt==255)
				irqcnt<=irqlatch;
			else
				irqcnt<=irqcnt+1'd1;
		end
	end
end

always@(posedge clk20) begin
	if(~enable) begin
		irqE<=0;
		timeout<=0;
	end else if (ce) begin
		if(nesprg_we & (irqctrl_add | irqack_add)) //write Fxx1 or Fxx2
			timeout<=0;
		else if(irqclk & irqcnt==255)
			timeout<=1;

		if(nesprg_we & irqctrl_add) //write Fxx1
			irqE<=nesprgdin[1];
		else if(nesprg_we & irqack_add) //write Fxx2
			irqE<=irqA;
	end
end

assign irq=timeout & irqE;

endmodule

module vrc7_mixed (
	input         clk,
	input         ce,    // Negedge M2 (aka CPU ce)
	input         enable,
	input         wren,
	input  [15:0] addr_in,
	input   [7:0] data_in,
	input  [15:0] audio_in,    // Inverted audio from APU
	output [15:0] audio_out
);

reg soff;
wire prg_ain43 = addr_in[4] ^ addr_in[3];

always@(posedge clk) begin
	if (~enable) begin
		soff <= 1'b0;
	end else if(ce && wren && {addr_in[15:12],prg_ain43} == 5'b11100) begin
		soff<=data_in[6];   //E000
	end
end

reg [3:0] ce_count;
always@(posedge clk) begin
	if (~enable)
		ce_count <= 0;
	else if (ce)
		ce_count <= 0;
	else
		ce_count <= ce_count + 4'd1;
end

wire ack;
wire ce_ym2143 = ce | (ce_count==4'd5);
wire signed [13:0] ym2143audio;
wire wr_audio = wren && (addr_in[15:6]==10'b1001_0000_00) && (addr_in[4:0]==5'b1_0000); //0x9010 or 0x9030
eseopll ym2143vrc7 (clk,~enable, ce_ym2143,wr_audio,ce_ym2143,ack,wr_audio,{15'b0,addr_in[5]},data_in,ym2143audio);

// The strategy here:
// VRC7 sound is very low, and the top bit is seldom (if ever) used. It's output as signed with
// an actual used range of 6 * +/-512 = +/-3072.  What we do is convert to unsigned (+2048),
// then clip to 4095. This clips the top 50% of the values, which are unlikely to be needed. This volume
// is low compared to NES audio, so we mix accordingly, again clipping if needed. The result
// is audio mixed more or less correctly and at a similar level to the audio from regular games.

wire [13:0] audio_exp = ym2143audio + 14'h800;
wire [13:0] audio_clip = audio_exp > 14'hFFF ? 14'hFFF : audio_exp;
wire [15:0] audio_boost = {audio_clip[11:0], 4'b0000};
wire [16:0] audio_mixed = audio_in[15:1] + audio_boost[15:1] + audio_boost[15:2] + audio_boost[15:4];
assign audio_out = soff ? audio_in[15:1] : (audio_mixed[16] ? 16'hFFFF : audio_mixed[15:0]);

endmodule

module vrc6_mixed (
	input         clk,
	input         ce,    // Negedge M2 (aka CPU ce)
	input         enable,
	input         wren,
	input         addr_invert,
	input  [15:0] addr_in,
	input   [7:0] data_in,
	input  [15:0] audio_in,    // Inverted audio from APU
	output [15:0] audio_out
);

vrc6sound snd_vrc6 (
	.clk(clk),
	.ce(ce),
	.enable(enable),
	.wr(wren),
	.addr_invert(addr_invert),
	.addr_in(addr_in),
	.din(data_in),
	.outSq1(vrc6sq1_out),
	.outSq2(vrc6sq2_out),
	.outSaw(vrc6saw_out)
);

//sound
//    wire [5:0] vrc6_out;
//	assign exp6 = 0;
	wire [3:0] vrc6sq1_out;
	wire [3:0] vrc6sq2_out;
	wire [4:0] vrc6saw_out;

	// VRC6 sound is mixed before amplification, and them amplified linearly
	wire [5:0] exp_audio = vrc6sq1_out + vrc6sq2_out + vrc6saw_out;
	wire [15:0] audio = {exp_audio, exp_audio, exp_audio[5:2]};

// VRC6 audio is much louder than APU audio, so match the levels we have to reduce it 
// to about 43% to match the audio ratio of the original Famicom with AD3. Note that the
// VRC6 audio is opposite polarity from APU audio.

	wire [16:0] mixed_audio = audio_in + (audio[15:1] + audio[15:3]);
	assign audio_out = mixed_audio[16:1];

endmodule

module vrc6sound(
	input clk,
	input ce,
	input enable,
	input wr,
	input addr_invert,
	input [15:0] addr_in,
	input [7:0] din,
	output [3:0] outSq1,       //range=0..0x0F
	output [3:0] outSq2,       //range=0..0x0F
	output [4:0] outSaw        //range=0..0x1F
);

wire [15:0] ain=addr_invert ? {addr_in[15:2],addr_in[0],addr_in[1]} :  addr_in; //MAP1A : MAP18

reg mode0, mode1;
reg [3:0] vol0, vol1;
reg [5:0] vol2;
reg [2:0] duty0, duty1;
reg [11:0] freq0, freq1, freq2;
reg [11:0] div0, div1;
reg [12:0] div2;
reg en0, en1, en2;

reg [3:0] duty0cnt, duty1cnt;
reg [2:0] duty2cnt;
reg [7:0] acc;

always@(posedge clk) begin
	if(~enable) begin
		en0<=0;
		en1<=0;
		en2<=0;
	end else if(ce) begin
		if(wr) begin
			case(ain)
				16'h9000: {mode0, duty0, vol0}<=din;
				16'h9001: freq0[7:0]<=din;
				16'h9002: {en0, freq0[11:8]} <= {din[7],din[3:0]};

				16'hA000: {mode1, duty1, vol1}<=din;
				16'hA001: freq1[7:0]<=din;
				16'hA002: {en1, freq1[11:8]} <= {din[7],din[3:0]};

				16'hB000: vol2<=din[5:0];
				16'hB001: freq2[7:0]<=din;
				16'hB002: {en2, freq2[11:8]}<={din[7],din[3:0]};
			endcase
		end
		if(en0) begin
			if(div0!=0)
				div0<=div0-1'd1;
			else begin
				div0<=freq0;
				duty0cnt<=duty0cnt+1'd1;
			end
		end
		if(en1) begin
			if(div1!=0)
				div1<=div1-1'd1;
			else begin
				div1<=freq1;
				duty1cnt<=duty1cnt+1'd1;
			end
		end
		if(en2) begin
			if(div2!=0)
				div2<=div2-1'd1;
			else begin
				div2<={freq2,1'b1};
				if(duty2cnt==6) begin
					duty2cnt<=0;
					acc<=0;
				end else begin
					duty2cnt<=duty2cnt+1'd1;
					acc<=acc+vol2;
				end
			end
		end
	end
end

wire [4:0] duty0pos=duty0cnt+{1'b1,~duty0};
wire [4:0] duty1pos=duty1cnt+{1'b1,~duty1};
wire [3:0] ch0=((~duty0pos[4]|mode0)&en0)?vol0:4'd0;
wire [3:0] ch1=((~duty1pos[4]|mode1)&en1)?vol1:4'd0;
wire [4:0] ch2=en2?acc[7:3]:5'd0;

assign outSq1=ch0;
assign outSq2=ch1;
assign outSaw=ch2;

endmodule

