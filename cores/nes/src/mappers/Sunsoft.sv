// 69 - Sunsoft FME-7
module Mapper69(
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
reg vram_a10;
wire vram_ce;
reg irq;
reg [15:0] flags_out = 0;
wire [15:0] audio;

reg [7:0] chr_bank[0:7];
reg [4:0] prg_bank[0:3];
reg [1:0] mirroring;
reg irq_countdown, irq_trigger;
reg [15:0] irq_counter;
reg [3:0] addr;
reg ram_enable, ram_select;
wire [16:0] new_irq_counter = irq_counter - {15'b0, irq_countdown};

always @(posedge clk)
if (~enable) begin
	chr_bank[0] <= 0;
	chr_bank[1] <= 0;
	chr_bank[2] <= 0;
	chr_bank[3] <= 0;
	chr_bank[4] <= 0;
	chr_bank[5] <= 0;
	chr_bank[6] <= 0;
	chr_bank[7] <= 0;
	prg_bank[0] <= 0;
	prg_bank[1] <= 0;
	prg_bank[2] <= 0;
	prg_bank[3] <= 0;
	mirroring <= 0;
	irq_countdown <= 0;
	irq_trigger <= 0;
	irq_counter <= 0;
	addr <= 0;
	ram_enable <= 0;
	ram_select <= 0;
	irq <= 0;
end else if (ce) begin
	irq_counter <= new_irq_counter[15:0];
	if (irq_trigger && new_irq_counter[16]) irq <= 1;
	if (!irq_trigger) irq <= 0;

	if (prg_ain[15] & prg_write) begin
		case (prg_ain[14:13])
			0: addr <= prg_din[3:0];
			1: begin
				case(addr)
					0,1,2,3,4,5,6,7: chr_bank[addr[2:0]] <= prg_din;
					8,9,10,11:       prg_bank[addr[1:0]] <= prg_din[4:0];
					12:              mirroring <= prg_din[1:0];
					13:              {irq_countdown, irq_trigger} <= {prg_din[7], prg_din[0]};
					14:              irq_counter[7:0] <= prg_din;
					15:              irq_counter[15:8] <= prg_din;
				endcase

				if (addr == 8) {ram_enable, ram_select} <= prg_din[7:6];
			end
		endcase
	end
end

always begin
	casez(mirroring[1:0])
		2'b00: vram_a10 = {chr_ain[10]};    // vertical
		2'b01: vram_a10 = {chr_ain[11]};    // horizontal
		2'b1?: vram_a10 = {mirroring[0]};   // 1 screen lower
	endcase
end

reg [4:0] prgout;
reg [7:0] chrout;

always begin
	casez(prg_ain[15:13])
		3'b011: prgout = prg_bank[0];
		3'b100: prgout = prg_bank[1];
		3'b101: prgout = prg_bank[2];
		3'b110: prgout = prg_bank[3];
		3'b111: prgout = 5'b11111;
		default: prgout = 5'bxxxxx;
	endcase

	chrout = chr_bank[chr_ain[12:10]];
end

wire ram_cs = (prg_ain[15:13] == 3'b011 && ram_select);
assign prg_aout = {ram_cs ? 4'b1111 : 4'b0000, prgout[4:0], prg_ain[12:0]};
assign prg_allow = (prg_ain >= 16'h6000) && (ram_cs ? ram_enable : !prg_write);
assign chr_allow = flags[15];
assign chr_aout = {4'b10_00, chrout, chr_ain[9:0]};
assign vram_ce = chr_ain[13];

assign audio = audio_in;

endmodule


module SS5b_mixed (
	input         clk,
	input         ce,    // Negedge M2 (aka CPU ce)
	input         enable,
	input         wren,
	input  [15:0] addr_in,
	input   [7:0] data_in,
	input  [15:0] audio_in,    // Inverted audio from APU
	output [15:0] audio_out
);

SS5b_audio snd_5b (
	.clk(clk),
	.ce(ce),
	.enable(enable),
	.wren(wren),
	.addr_in(addr_in),
	.data_in(data_in),
	.audio_out(exp_out)
);

// Sunsoft 5B audio amplifies each channel logarithmicly before mixing. It's then mixed
// with APU audio (reverse polarity) and then reverses the polarity of the audio again.
// The expansion audio is much louder than APU audio, so we reduce it to 68% prior to
// mixing.

wire [15:0] exp_out;
wire [15:0] exp_adj = (|exp_out[15:14] ? 16'hFFFF : {exp_out[13:0], exp_out[1:0]});
wire [16:0] audio_mix = audio_in + (exp_adj + exp_adj[15:1]);

assign audio_out = 16'hFFFF - audio_mix[16:1];

endmodule

// Sunsoft 5B audio by Kitrinx
module SS5b_audio (
	input         clk,
	input         ce,    // Negedge M2 (aka CPU ce)
	input         enable,
	input         wren,
	input  [15:0] addr_in,
	input   [7:0] data_in,
	output [15:0] audio_out
);

reg [3:0] reg_select;

// Register bank
reg [7:0] internal[0:15];

// Register abstraction to readable wires

// Periods
wire [11:0] period_a     = {internal[1][3:0], internal[0]};
wire [11:0] period_b     = {internal[3][3:0], internal[2]};
wire [11:0] period_c     = {internal[5][3:0], internal[4]};
wire [4:0]  period_n     = internal[6][4:0];

// Enables
wire        tone_dis_a   = internal[7][0];
wire        tone_dis_b   = internal[7][1];
wire        tone_dis_c   = internal[7][2];
wire        noise_dis_a  = internal[7][3];
wire        noise_dis_b  = internal[7][4];
wire        noise_dis_c  = internal[7][5];

// Envelope
// wire        env_enable_a = internal[8][4];
 wire  [3:0] env_vol_a    = internal[8][3:0];
// wire        env_enable_b = internal[9][4];
 wire  [3:0] env_vol_b    = internal[9][3:0];
// wire        env_enable_c = internal[10][4];
 wire  [3:0] env_vol_c    = internal[10][3:0];
// wire [15:0] env_period   = {internal[12], internal[11]};
// wire        env_continue = internal[13][3];
// wire        env_attack   = internal[13][2];
// wire        env_alt      = internal[13][1];
// wire        env_hold     = internal[13][0];

reg [4:0] cycles;
reg [11:0] tone_a_cnt, tone_b_cnt, tone_c_cnt, noise_cnt;

reg [4:0] tone_a, tone_b, tone_c;

wire [12:0] tone_a_next = tone_a_cnt + 1'b1;
wire [12:0] tone_b_next = tone_b_cnt + 1'b1;
wire [12:0] tone_c_next = tone_c_cnt + 1'b1;
wire [12:0] noise_next = noise_cnt + 1'b1;

reg [16:0] noise_lfsr = 17'h1;
reg [5:0] envelope_a, envelope_b, envelope_c;

always_ff @(posedge clk)
if (~enable) begin
	internal <= '{
		8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0,
		8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0};

	{tone_a, tone_b, tone_c, envelope_a, envelope_b, envelope_c, cycles, noise_lfsr} <= 0;
	{tone_a_cnt, tone_b_cnt, tone_c_cnt, noise_cnt} <= 0;
end else if (ce) begin
	cycles <= cycles + 1'b1;

	// Write registers
	if (wren) begin
		if (addr_in[15:13] == 3'b110)  // C000
			reg_select <= data_in[3:0];
		if (addr_in[15:13] == 3'b111)  // E000
			internal[reg_select] <= data_in;
	end

	tone_a_cnt <= tone_a_next[11:0];
	tone_b_cnt <= tone_b_next[11:0];
	tone_c_cnt <= tone_c_next[11:0];

	if (tone_a_next >= period_a) begin
		tone_a_cnt <= 12'd0;
		tone_a <= tone_a + 1'b1;
	end

	if (tone_b_next >= period_b) begin
		tone_b_cnt<= 12'd0;
		tone_b <= tone_b + 1'b1;
	end

	if (tone_c_next >= period_c) begin
		tone_c_cnt <= 12'd0;
		tone_c <= tone_c + 1'b1;
	end

	// XXX: Implement modulation envelope if needed (not used in any games)
	envelope_a <= {env_vol_a, 1'b1};
	envelope_b <= {env_vol_b, 1'b1};
	envelope_c <= {env_vol_c, 1'b1};

	if (&cycles) begin
		// Advance noise LFSR every 32 cycles
		noise_cnt <= noise_next[11:0];

		if (noise_next >= period_n) begin
			noise_lfsr <= {noise_lfsr[15:0], noise_lfsr[16] ^ noise_lfsr[13]};
			noise_cnt <= 12'd0;
		end
	end

end

wire output_a, output_b, output_c;

always_comb begin
	case ({tone_dis_a, noise_dis_a})
		2'b00: output_a = noise_lfsr[0] & tone_a[4];
		2'b01: output_a = tone_a[4];
		2'b10: output_a = noise_lfsr[0];
		2'b11: output_a = 1'b0;
	endcase

	case ({tone_dis_b, noise_dis_b})
		2'b00: output_b = noise_lfsr[0] & tone_b[4];
		2'b01: output_b = tone_b[4];
		2'b10: output_b = noise_lfsr[0];
		2'b11: output_b = 1'b0;
	endcase

	case ({tone_dis_c, noise_dis_c})
		2'b00: output_c = noise_lfsr[0] & tone_c[4];
		2'b01: output_c = tone_c[4];
		2'b10: output_c = noise_lfsr[0];
		2'b11: output_c = 1'b0;
	endcase
end

assign audio_out =
	{output_a ? ss5b_amp_lut[envelope_a] : 8'h0, 5'b0} +
	{output_b ? ss5b_amp_lut[envelope_b] : 8'h0, 5'b0} +
	{output_c ? ss5b_amp_lut[envelope_c] : 8'h0, 5'b0} ;

// Logarithmic amplification table in 1.5db steps
wire [7:0] ss5b_amp_lut[0:31] = '{
	8'd0,  8'd0,  8'd1,  8'd1,  8'd1,   8'd1,   8'd2,   8'd2,
	8'd3,  8'd3,  8'd4,  8'd5,  8'd6,   8'd7,   8'd9,   8'd11,
	8'd13, 8'd15, 8'd18, 8'd22, 8'd26,  8'd31,  8'd37,  8'd44,
	8'd53, 8'd63, 8'd74, 8'd89, 8'd105, 8'd125, 8'd149, 8'd177
};

endmodule

// Mapper 190, Magic Kid GooGoo
// Mapper 67, Sunsoft-3
module Mapper67 (
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

reg [7:0] prg_bank_0;
reg [7:0] chr_bank_0, chr_bank_1, chr_bank_2, chr_bank_3;
reg [1:0] mirroring;
reg irq_ack;
reg irq_enable;
reg irq_low;
reg [15:0] irq_counter;
wire mapper190 = (flags[7:0] == 190);

always @(posedge clk)
if (~enable) begin
	prg_bank_0 <= 0;
	chr_bank_0 <= 0;
	chr_bank_1 <= 0;
	chr_bank_2 <= 0;
	chr_bank_3 <= 0;
	mirroring <= 2'b00; //vertical for mapper190
	irq_counter <= 0;
	irq_enable <= 0;
	irq_low <= 0;
end else if (ce) begin
	irq_ack <= 1'b0;
	if ((prg_write) && (prg_ain[15])) begin// Cover all from $8000 to $FFFF to maximize compatibility
		if (!mapper190)
			casez({prg_ain[14:11],irq_low})
				5'b000_1_?: chr_bank_0 <= prg_din;
				5'b001_1_?: chr_bank_1 <= prg_din;
				5'b010_1_?: chr_bank_2 <= prg_din;
				5'b011_1_?: chr_bank_3 <= prg_din;
				5'b110_1_?: mirroring <= prg_din[1:0];
				5'b111_1_?: prg_bank_0 <= prg_din;
				5'b100_1_0: {irq_low, irq_counter[15:8]} <= {1'b1,prg_din};
				5'b100_1_1: {irq_low, irq_counter[7:0]} <= {1'b0,prg_din};
				5'b101_1_?: {irq_low, irq_ack, irq_enable} <= {2'b01, prg_din[4]};
			endcase
		else
			casez({prg_ain[13],prg_ain[1:0]})
				3'b0_??: prg_bank_0[3:0] <= {prg_ain[14],prg_din[2:0]};
				3'b1_00: chr_bank_0 <= prg_din;
				3'b1_01: chr_bank_1 <= prg_din;
				3'b1_10: chr_bank_2 <= prg_din;
				3'b1_11: chr_bank_3 <= prg_din;
			endcase
	end
	if (irq_enable) begin
		irq_counter <= irq_counter - 16'd1;
		if (irq_counter == 16'h0) begin
			irq <= 1'b1; // IRQ
			irq_enable <= 0;
		end
	end

	if (irq_ack)
		irq <= 1'b0; // IRQ ACK
end

always begin
	casez({mirroring})
		2'b00   :   vram_a10 = {chr_ain[10]};    // vertical
		2'b01   :   vram_a10 = {chr_ain[11]};    // horizontal
		2'b1?   :   vram_a10 = {mirroring[0]};   // 1 screen lower:upper
	endcase
end

reg [7:0] prgsel;
always begin
	case(prg_ain[14])
	1'b0: prgsel = prg_bank_0;                // $8000 is swapable
	1'b1: prgsel = mapper190 ? 8'h00 : 8'hFF; // $C000 is hardwired to first/last bank
	endcase
end

reg [7:0] chrsel;
always begin
	casez(chr_ain[12:11])
		0: chrsel = chr_bank_0;
		1: chrsel = chr_bank_1;
		2: chrsel = chr_bank_2;
		3: chrsel = chr_bank_3;
	endcase
end

assign chr_aout = {3'b10_0, chrsel, chr_ain[10:0]};             //  2kB banks

wire [21:0] prg_aout_tmp = {2'b00, prgsel[5:0], prg_ain[13:0]}; // 16kB banks
wire prg_is_ram = (prg_ain >= 'h6000) && (prg_ain < 'h8000);
wire [21:0] prg_ram = {9'b11_1100_000, prg_ain[12:0]};

assign prg_aout = prg_is_ram ? prg_ram : prg_aout_tmp;

assign prg_allow = (prg_ain[15] && !prg_write) || prg_is_ram;
assign chr_allow = flags[15];
assign vram_ce = chr_ain[13];

endmodule


// #68 - Sunsoft-4 - Game After Burner, and some japanese games. MAX: 128kB PRG, 256kB CHR
module Mapper68(
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
wire ram_enable;
wire chr_allow;
wire vram_a10;
wire vram_ce;
reg [15:0] flags_out = 0;

reg [6:0] chr_bank_0, chr_bank_1, chr_bank_2, chr_bank_3;
reg [6:0] nametable_0, nametable_1;
reg [3:0] prg_bank;
reg use_chr_rom;
reg [1:0] mirroring;

always @(posedge clk)
if (~enable) begin
	chr_bank_0 <= 0;
	chr_bank_1 <= 0;
	chr_bank_2 <= 0;
	chr_bank_3 <= 0;
	nametable_0 <= 0;
	nametable_1 <= 0;
	prg_bank <= 0;
	ram_enable <= 0;
	use_chr_rom <= 0;
	mirroring <= 0;
end else if (ce) begin
	if (prg_ain[15] && prg_write) begin
		case(prg_ain[14:12])
			0: chr_bank_0  <= prg_din[6:0]; // $8000-$8FFF: 2kB CHR bank at $0000
			1: chr_bank_1  <= prg_din[6:0]; // $9000-$9FFF: 2kB CHR bank at $0800
			2: chr_bank_2  <= prg_din[6:0]; // $A000-$AFFF: 2kB CHR bank at $1000
			3: chr_bank_3  <= prg_din[6:0]; // $B000-$BFFF: 2kB CHR bank at $1800
			4: nametable_0 <= prg_din[6:0]; // $C000-$CFFF: 1kB Nametable register 0 at $2000
			5: nametable_1 <= prg_din[6:0]; // $D000-$DFFF: 1kB Nametable register 1 at $2400
			6: {use_chr_rom, mirroring} <= {prg_din[4], prg_din[1:0]}; // $E000-$EFFF: Nametable control
			7: {ram_enable, prg_bank} <= prg_din[4:0]; // $F000-$FFFF: 16kB PRG banks at $8000-$BFFF and WRAM enable
		endcase
	end
end

// $C000-$FFFF wired to last PRG bank
wire [3:0] prgout = ((prg_ain[15:14] == 2'b11) ? 4'b1111 : prg_bank);
wire prg_is_ram = (prg_ain[15:13] == 3'b011);
wire [21:0] prg_ram = {9'b11_1100_000, prg_ain[12:0]};
assign prg_aout = prg_is_ram ? prg_ram : {4'b00_00, prgout, prg_ain[13:0]};
assign prg_allow = (prg_ain[15] && !prg_write) || (prg_is_ram && ram_enable);

reg [6:0] chrout;
always begin
	casez(chr_ain[12:11])
		0: chrout = chr_bank_0;
		1: chrout = chr_bank_1;
		2: chrout = chr_bank_2;
		3: chrout = chr_bank_3;
	endcase
end

always begin
	casez(mirroring[1:0])
		2'b00: vram_a10 = {chr_ain[10]};    // vertical
		2'b01: vram_a10 = {chr_ain[11]};    // horizontal
		2'b1?: vram_a10 = {mirroring[0]};   // 1 screen lower
	endcase
end

wire [6:0] nameout = (vram_a10 == 0) ? nametable_0 : nametable_1;

assign chr_allow = flags[15];
assign chr_aout = (chr_ain[13] == 0) ? {4'b10_00, chrout, chr_ain[10:0]} : {5'b10_001, nameout, chr_ain[9:0]};
assign vram_ce = chr_ain[13] && !use_chr_rom;

endmodule