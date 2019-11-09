// J. Y. Company mappers

module multiplier (
  input clk,
  input ce,
  input start,
  input [7:0] a,
  input [7:0] b,
  output [15:0] p,
  output done
);

  reg [15:0] shift_a;
  reg [15:0] product;
  reg [8:0] bindex;
  assign p = product;
  assign done = bindex[8];
  

  always @(posedge clk) begin
    if (start && ce) begin
	  bindex <= 9'd1 << 1;
	  product <= {8'h00, b[0] ? a : 8'h00};
	  shift_a <= a << 1;
    end else if (bindex < 9'h100) begin
	  product <= product + ((bindex[7:0] & b) ? shift_a : 16'd0);
	  bindex <= bindex << 1;
	  shift_a <= shift_a << 1;
    end
  end

endmodule


module JYCompany(
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
	input        ppu_ce,
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

wire [21:0] prg_aout;
reg [21:0] chr_aout;
wire prg_allow;
wire chr_allow;
wire vram_a10;
reg [7:0] chr_dout, prg_dout;
wire vram_ce;
wire [15:0] flags_out = {14'h0, prg_bus_write, 1'b0};
wire irq;
reg prg_bus_write;

wire mapper90 = (flags[7:0] == 90);
wire mapper211 = (flags[7:0] == 211);  // Should just be 209 with correct behavior below
wire mapper35 = (flags[7:0] == 35);
wire ram_support = mapper35 || (flags[29:26] == 4'd7); //|| NES2.0 check;

reg [1:0] prg_mode, chr_mode;
reg prg_protect_1, prg_protect_2;
reg [3:0] mirroring;
wire xmirr = ~mapper90;
wire fxmirr = mapper211;
reg [2:0] prg_ram_bank;
reg [7:0] prg_bank [3:0];
reg [15:0] chr_bank [7:0];
reg [15:0] name_bank [3:0];
reg [7:0] outer_bank;
reg [7:0] ppu_conf;
reg [7:0] bank_mode;

wire [1:0] dip = 2'b00;
reg multiply_start;
reg [7:0] multiplier_1;
reg [7:0] multiplier_2;
wire [15:0] multiply_result;
reg [7:0] accum;
reg [7:0] accumtest;

reg old_a12;
reg irq_enable;
wire irq_source;
assign irq = irq_pending && irq_enable;
reg irq_pending;
reg irq_en;
reg irq_dis;
reg [7:0] irq_prescalar;
reg [7:0] irq_count;
reg [7:0] irq_xor;
reg [7:0] irq_mode;

// Handle IO register writes
always @(posedge clk) begin
	if (!enable)
		//Something needs to reset E000-FFFF to last bank
		// Could be bank_mode[2] = 0 or prg_bank[3] = FF
		// Outer bank might be an issue as well...
		// Needed for Tiny Toons 6 and Warioland II.
		bank_mode[2] = 1'b0;
	if (ce && prg_write) begin // $5000-$FFFF
		casez({prg_ain[15:11], prg_ain[2:0]})
			8'b0101_1_?00: multiplier_1 <= prg_din;                                  // $5800
			8'b0101_1_?01: begin multiplier_2 <= prg_din; multiply_start <= 1; end   // $5801
			8'b0101_1_?10: accum <= accum + prg_din;                                 // $5802
			8'b0101_1_?11: begin accum <= 0; accumtest <= prg_din; end               // $5803
			8'b1000_0_???: prg_bank[prg_ain[1:0]] <= prg_din;                        // $8000-3
			8'b1001_0_???: chr_bank[prg_ain[2:0]][7:0] <= prg_din;                   // $9000-7
			8'b1010_0_???: chr_bank[prg_ain[2:0]][15:8] <= prg_din;                  // $A000-7
			8'b1011_0_0??: name_bank[prg_ain[1:0]][7:0] <= prg_din;                  // $B000-3
			8'b1011_0_1??: name_bank[prg_ain[1:0]][15:8] <= prg_din;                 // $B004-7
			8'b1100_0_000: begin irq_en <= prg_din[0]; irq_dis <= !prg_din[0]; end   // $C000
			8'b1100_0_001: irq_mode <= prg_din;                                      // $C001
			8'b1100_0_010: irq_dis <= 1;                                             // $C002
			8'b1100_0_011: irq_en <= 1;                                              // $C003
			8'b1100_0_100: irq_prescalar <= prg_din ^ irq_xor;                       // $C004
			8'b1100_0_101: irq_count <= prg_din ^ irq_xor;                           // $C005
			8'b1100_0_110: irq_xor <= prg_din;                                       // $C006
//			8'b1100_0_111: irq_conf <= prg_din;                                      // $C007
			8'b1101_0_?00: bank_mode <= prg_din;                                     // $D000
			8'b1101_0_?01: mirroring <= prg_din[3:0];                                // $D001
			8'b1101_0_?10: ppu_conf <= prg_din;                                      // $D002
			8'b1101_0_?11: outer_bank <= prg_din;                                    // $D003
		endcase
	end
	
	if (ppu_ce) old_a12 <= chr_ain_o[12];

	if (irq_source && irq_enable && (irq_mode[7] != irq_mode[6])) begin
		irq_prescalar <= irq_mode[6] ? (irq_prescalar + 8'd1) : (irq_prescalar - 8'd1);
		if  (( irq_mode[6] && ((irq_mode[2] && irq_prescalar[2:0] == 3'h7) || (!irq_mode[2] && irq_prescalar == 8'hFF)))
		 ||  (!irq_mode[6] && ((irq_mode[2] && irq_prescalar[2:0] == 3'h0) || (!irq_mode[2] && irq_prescalar == 8'h00)))) begin
			irq_count <= irq_mode[6] ? (irq_count + 8'd1) : (irq_count - 8'd1);
			if  (( irq_mode[6] && irq_count == 8'hFF)
			 ||  (!irq_mode[6] && irq_count == 8'h00))
				irq_pending <= 1;
		end
	end

	if (irq_dis) begin
		irq_pending <= 0;
		irq_prescalar <= 0;
		irq_enable <= 0;
		irq_dis <= 0;
	end else if (irq_en) begin
		irq_en <= 0;
		irq_enable <= 1;
	end
end

// Determine IRQ handling
always @* begin
	case(irq_mode[1:0])
		2'b00: irq_source = ce;
		2'b01: irq_source = ppu_ce && chr_ain_o[12] && !old_a12;
		2'b10: irq_source = ppu_ce && chr_read;
		2'b11: irq_source = ce && prg_write;
	endcase
end


multiplier mp(
  .clk(clk),
  .ce(ce),
  .start(multiply_start),
  .a(multiplier_1),
  .b(multiplier_2),
  .p(multiply_result),
  .done()
  );

wire prg_6xxx = prg_ain[15:13] == 2'b011; // $6000-$7FFF
wire prg_ram = prg_6xxx && !bank_mode[7];

// Read from JYCompany
always @* begin
	prg_bus_write = 1'b1;
	if ((prg_ain == 16'h5000) || (prg_ain == 16'h5400)) begin // || (prg_ain == 16'h5C00)) begin
		prg_dout = {dip, 6'h00};
	end else if (prg_ain == 16'h5800) begin
		prg_dout = multiply_result[7:0];
	end else if (prg_ain == 16'h5801) begin
		prg_dout = multiply_result[15:8];
	end else if (prg_ain == 16'h5802) begin
		prg_dout = accum;
	end else if (prg_ain == 16'h5803) begin
		prg_dout = accumtest;
	end else begin
		prg_dout = 8'hFF; // By default open bus.
		prg_bus_write = 0;
	end
end

// Compute PRG address to read from.
wire [1:0] prg_reg;
always @* begin
	casez({prg_6xxx, bank_mode[1:0]})
		3'b000: prg_reg = {2'b11};                       // $8000-$FFFF
		3'b001: prg_reg = {prg_ain[14], 1'b1};           // $8000-$BFFF + prg_ain*0x4000
		3'b01?: prg_reg = {prg_ain[14:13]};              // $8000-$9FFF + prg_ain*0x2000
		3'b1??: prg_reg = {2'b11};                       // $6000-$7FFF
	endcase
end
wire [7:0] bank_val = (!bank_mode[2] && prg_reg == 2'b11) ? 8'hFF : prg_bank[prg_reg];
wire [6:0] bank_order = bank_mode[1:0] == 2'b11 ? {bank_val[0], bank_val[1], bank_val[2], bank_val[3], bank_val[4], bank_val[5], bank_val[6]} : bank_val[6:0];
wire [5:0] prg_sel;
always @* begin
	casez({prg_6xxx, bank_mode[1:0]})
		3'b000: prg_sel = {bank_order[3:0], prg_ain[14:13]}; //
		3'b001: prg_sel = {bank_order[4:0], prg_ain[13]};    //
		3'b?1?: prg_sel = {bank_order[5:0]};                 //
		3'b100: prg_sel = {bank_order[3:0], 2'b11};          //
		3'b101: prg_sel = {bank_order[4:0], 1'b1};           //
	endcase
end
assign prg_aout = prg_ram && ram_support ? {9'b11_1100_000, prg_ain[12:0]} : {1'b0, outer_bank[2:1], prg_sel, prg_ain[12:0]};
assign prg_allow = (prg_ain >= 16'h6000) && (prg_ram ? ram_support : !prg_write);

reg [1:0] chr_latch;
// latch is set to 0 when the PPU reads from $0FD8-$0FDF/$1FD8-$1FDF and to 1 when the PPU reads from $0FE8-$0FEF/$1FE8-$1FEF.
always @(posedge clk)
if (~enable)
	chr_latch <= 2'b00;
else if (ppu_ce && chr_read) begin
	chr_latch[chr_ain_o[12]] <= outer_bank[7] && (((chr_ain_o & 14'h2ff8) == 14'h0fd8) ? 1'd0 : ((chr_ain_o & 14'h2ff8) == 14'h0fe8) ? 1'd1 : chr_latch[chr_ain_o[12]]);
end
wire [2:0] chr_reg;
always @* begin
	casez(bank_mode[4:3])
		2'b00: chr_reg = {3'b000};                                   // $0000-$1FFF
		2'b01: chr_reg = {chr_ain[12], chr_latch[chr_ain[12]], 1'b0};// $0000-$0FFF + chr_ain*0x1000
		2'b10: chr_reg = {chr_ain[12:11], 1'b0};                     // $0000-$07FF + chr_ain*0x0800
		2'b11: chr_reg = {chr_ain[12:10]};                           // $0000-$03FF + chr_ain*0x0400
	endcase
end
wire [12:0] chr_val = chr_bank[chr_reg][12:0];
wire [12:0] chr_sel;
always @* begin
	casez({romtables, bank_mode[4:3]})
		3'b000: chr_sel = {chr_val[9:0],  chr_ain[12:10]};    //
		3'b001: chr_sel = {chr_val[10:0], chr_ain[11:10]};    //
		3'b010: chr_sel = {chr_val[11:0], chr_ain[10]};       //
		3'b011: chr_sel = {chr_val[12:0]};                    //
		3'b1??: chr_sel = {name_bank[chr_ain[11:10]][12:0]};  //
	endcase
end

assign chr_aout = {2'b10, outer_bank[3], !outer_bank[5] ? outer_bank[0] : chr_sel[8], chr_sel[7:0], chr_ain[9:0]}; //not enough bits for outer_bank[4]
assign chr_allow = flags[15] && ppu_conf[6];

// The a10 VRAM address line. (Used for mirroring)
wire xtend = (mirroring[3] || bank_mode[5]) && xmirr || fxmirr;
wire romtables = chr_ain[13] && xtend && bank_mode[5] && (bank_mode[6] || (ppu_conf[7] ^ name_bank[chr_ain[11:10]][7]));
always @* begin
	casez({xtend, mirroring[1:0]})
		3'b1??: vram_a10 = name_bank[chr_ain[11:10]][0];
		3'b000: vram_a10 = chr_ain[10];
		3'b001: vram_a10 = chr_ain[11];
		3'b010: vram_a10 = 1'b0;
		3'b011: vram_a10 = 1'b1;
	endcase
end
assign vram_ce = chr_ain[13] && (!chr_read || !xtend || !romtables);

endmodule
