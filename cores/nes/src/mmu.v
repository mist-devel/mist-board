// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

// No mapper chip
module MMC0(input clk, input ce,
            input [31:0] flags,
            input [15:0] prg_ain, output [21:0] prg_aout,
            input prg_read, prg_write,                   // Read / write signals
            input [7:0] prg_din,
            output prg_allow,                            // Enable access to memory for the specified operation.
            input [13:0] chr_ain, output [21:0] chr_aout,
            output chr_allow,                      // Allow write
            output vram_a10,                             // Value for A10 address line
            output vram_ce);                             // True if the address should be routed to the internal 2kB VRAM.
  assign prg_aout = {7'b00_0000_0, prg_ain[14:0]};
  assign prg_allow = prg_ain[15] && !prg_write;
  assign chr_allow = flags[15];
  assign chr_aout = {9'b10_0000_000, chr_ain[12:0]};
  assign vram_ce = chr_ain[13];
  assign vram_a10 = flags[14] ? chr_ain[10] : chr_ain[11];
endmodule

// MMC1 mapper chip. Maps prg or chr addresses into a linear address.
// If vram_ce is set, {vram_a10, chr_aout[9:0]} are used to access the NES internal VRAM instead.
module MMC1(input clk, input ce, input reset,
            input [31:0] flags,
            input [15:0] prg_ain, output [21:0] prg_aout,
            input prg_read, prg_write,                   // Read / write signals
            input [7:0] prg_din,
            output prg_allow,                            // Enable access to memory for the specified operation.
            input [13:0] chr_ain, output [21:0] chr_aout,
            output chr_allow,                      // Allow write
            output vram_a10,                             // Value for A10 address line
            output vram_ce);                             // True if the address should be routed to the internal 2kB VRAM.
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
  
  // Update shift register
  always @(posedge clk) if (reset) begin
    shift <= 1;
    control <= 'hC;
  end else if (ce) begin
    if (prg_write && prg_ain[15]) begin
      if (prg_din[7]) begin
        shift <= 5'b10000;
        control <= control | 'hC;
//        $write("MMC1 RESET!\n");
      end else begin
        if (shift[0]) begin
//          $write("MMC1 WRITE %X to %X!\n", {prg_din[0], shift[4:1]}, prg_ain);
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
  reg [3:0] prgsel;
  always @* begin
    casez({control[3:2], prg_ain[14]})
    3'b0?_?: prgsel = {prg_bank[3:1], prg_ain[14]};
    3'b10_0: prgsel = 4'b0000;
    3'b10_1: prgsel = prg_bank[3:0];
    3'b11_0: prgsel = prg_bank[3:0];
    3'b11_1: prgsel = 4'b1111;
    endcase
  end
  wire [21:0] prg_aout_tmp = {4'b00_00,  prgsel, prg_ain[13:0]};

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
  
  // The a10 VRAM address line. (Used for mirroring)
  reg vram_a10_t;
  always @* begin
    casez(control[1:0])
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

// MMC2 mapper chip. PRG ROM: 128kB. Bank Size: 8kB. CHR ROM: 128kB
module MMC2(input clk, input ce, input reset,
            input [31:0] flags,
            input [15:0] prg_ain, output [21:0] prg_aout,
            input prg_read, prg_write,                   // Read / write signals
            input [7:0] prg_din,
            output prg_allow,                            // Enable access to memory for the specified operation.
            input chr_read, input [13:0] chr_ain, output [21:0] chr_aout,
            output chr_allow,                      // Allow write
            output vram_a10,                             // Value for A10 address line
            output vram_ce);                             // True if the address should be routed to the internal 2kB VRAM.

// PRG ROM bank select ($A000-$AFFF)
// 7  bit  0
// ---- ----
// xxxx PPPP
//      ||||
//      ++++- Select 8 KB PRG ROM bank for CPU $8000-$9FFF
  reg [3:0] prg_bank;

// CHR ROM $FD/0000 bank select ($B000-$BFFF)
// 7  bit  0
// ---- ----
// xxxC CCCC
//    | ||||
//    +-++++- Select 4 KB CHR ROM bank for PPU $0000-$0FFF
//            used when latch 0 = $FD
  reg   [4:0] chr_bank_0a;

// CHR ROM $FE/0000 bank select ($C000-$CFFF)
// 7  bit  0
// ---- ----
// xxxC CCCC
//    | ||||
//    +-++++- Select 4 KB CHR ROM bank for PPU $0000-$0FFF
//            used when latch 0 = $FE
   reg [4:0] chr_bank_0b;
   
// CHR ROM $FD/1000 bank select ($D000-$DFFF)
// 7  bit  0
// ---- ----
// xxxC CCCC
//    | ||||
//    +-++++- Select 4 KB CHR ROM bank for PPU $1000-$1FFF
//            used when latch 1 = $FD
  reg [4:0] chr_bank_1a;
   
// CHR ROM $FE/1000 bank select ($E000-$EFFF)
// 7  bit  0
// ---- ----
// xxxC CCCC
//    | ||||
//    +-++++- Select 4 KB CHR ROM bank for PPU $1000-$1FFF
//            used when latch 1 = $FE
  reg [4:0] chr_bank_1b; 
  
// Mirroring ($F000-$FFFF)
// 7  bit  0
// ---- ----
// xxxx xxxM
//         |
//         +- Select nametable mirroring (0: vertical; 1: horizontal)  
  reg mirroring;
  
  reg latch_0, latch_1;
  
  // Update registers
  always @(posedge clk) if (ce) begin
    if (prg_write && prg_ain[15]) begin
      case(prg_ain[14:12])
      2: prg_bank <= prg_din[3:0];     // $A000
      3: chr_bank_0a <= prg_din[4:0];  // $B000
      4: chr_bank_0b <= prg_din[4:0];  // $C000
      5: chr_bank_1a <= prg_din[4:0];  // $D000
      6: chr_bank_1b <= prg_din[4:0];  // $E000
      7: mirroring <=  prg_din[0];     // $F000
      endcase
    end
  end
  
  // Update latches when 0x3D8 or 0x3E8 is accessed.
  always @(posedge clk) if (ce && chr_read) begin
    latch_0 <= (chr_ain & 14'h3ff8) == 14'h0fd8 ? 0 : (chr_ain & 14'h3ff8) == 14'h0fe8 ? 1 : latch_0;
    latch_1 <= (chr_ain & 14'h3ff8) == 14'h1fd8 ? 0 : (chr_ain & 14'h3ff8) == 14'h1fe8 ? 1 : latch_1;
  end
  
  // The PRG bank to load. Each increment here is 8kb. So valid values are 0..15.
  reg [3:0] prgsel;
  always @* begin
    casez(prg_ain[14:13])
    2'b00:   prgsel = prg_bank;
    default: prgsel = {2'b11, prg_ain[14:13]};
    endcase
  end
  assign prg_aout = {5'b00_000, prgsel, prg_ain[12:0]};

  // The CHR bank to load. Each increment here is 4kb. So valid values are 0..31.
  reg [4:0] chrsel;
  always @* begin
    casez({chr_ain[12], latch_0, latch_1})
    3'b00?: chrsel = chr_bank_0a;
    3'b01?: chrsel = chr_bank_0b;
    3'b1?0: chrsel = chr_bank_1a;
    3'b1?1: chrsel = chr_bank_1b;
    endcase
  end
  assign chr_aout = {5'b100_00, chrsel, chr_ain[11:0]};
  
  // The a10 VRAM address line. (Used for mirroring)
  assign vram_a10 = mirroring ? chr_ain[11] : chr_ain[10];
  assign vram_ce = chr_ain[13];
  
  assign prg_allow = prg_ain[15] && !prg_write;
  assign chr_allow = flags[15];
endmodule


// This mapper also handles mapper 119 and 47.
module MMC3(input clk, input ce, input reset,
            input [31:0] flags,
            input [15:0] prg_ain, output [21:0] prg_aout,
            input prg_read, prg_write,                   // Read / write signals
            input [7:0] prg_din,
            output prg_allow,                            // Enable access to memory for the specified operation.
            input [13:0] chr_ain, output [21:0] chr_aout,
            output chr_allow,                            // Allow write
            output vram_a10,                             // Value for A10 address line
            output vram_ce,                              // True if the address should be routed to the internal 2kB VRAM.
            output reg irq);
  reg [2:0] bank_select;             // Register to write to next
  reg prg_rom_bank_mode;             // Mode for PRG banking
  reg chr_a12_invert;                // Mode for CHR banking
  reg mirroring;                     // 0 = vertical, 1 = horizontal
  reg irq_enable, irq_reload;        // IRQ enabled, and IRQ reload requested
  reg [7:0] irq_latch, counter;      // IRQ latch value and current counter
  reg ram_enable, ram_protect;       // RAM protection bits
  reg [6:0] chr_bank_0, chr_bank_1;  // Selected CHR banks
  reg [7:0] chr_bank_2, chr_bank_3, chr_bank_4, chr_bank_5;
  reg [5:0] prg_bank_0, prg_bank_1;  // Selected PRG banks
  wire prg_is_ram;
    
  // The alternative behavior has slightly different IRQ counter semantics.
  wire mmc3_alt_behavior = 0;
  
  // TQROM maps 8kB CHR RAM
  wire TQROM = (flags[7:0] == 119);
  wire TxSROM = (flags[7:0] == 118); // Connects CHR A17 to CIRAM A10
  
  // Mapper 47 is a multicart that has 128k for each game. It has no RAM.
  wire mapper47 = (flags[7:0] == 47);
  reg mapper47_multicart;
    
  wire [7:0] new_counter = (counter == 0 || irq_reload) ? irq_latch : counter - 1;
  reg [3:0] a12_ctr; 
   
  always @(posedge clk) if (reset) begin
    irq <= 0;
    bank_select <= 0;
    prg_rom_bank_mode <= 0;
    chr_a12_invert <= 0;
    mirroring <= 0;
    {irq_enable, irq_reload} <= 0;
    {irq_latch, counter} <= 0;
    {ram_enable, ram_protect} <= 0;
    {chr_bank_0, chr_bank_1} <= 0;
    {chr_bank_2, chr_bank_3, chr_bank_4, chr_bank_5} <= 0;
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
        3: chr_bank_3 <= prg_din;       // Select 1 KB CHR bank at PPU $1400-$17FF (or $0400-$07FF);
        4: chr_bank_4 <= prg_din;       // Select 1 KB CHR bank at PPU $1800-$1BFF (or $0800-$0BFF);
        5: chr_bank_5 <= prg_din;       // Select 1 KB CHR bank at PPU $1C00-$1FFF (or $0C00-$0FFF);
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
    
    // For Mapper 47
    // $6000-7FFF:  [.... ...B]  Block select
    if (prg_write && prg_is_ram)
      mapper47_multicart <= prg_din[0];
        
    // Trigger IRQ counter on rising edge of chr_ain[12]
    // All MMC3A's and non-Sharp MMC3B's will generate only a single IRQ when $C000 is $00.
    // This is because this version of the MMC3 generates IRQs when the scanline counter is decremented to 0.
    // In addition, writing to $C001 with $C000 still at $00 will result in another single IRQ being generated.
    // In the community, this is known as the "alternate" or "old" behavior.
    // All MMC3C's and Sharp MMC3B's will generate an IRQ on each scanline while $C000 is $00.
    // This is because this version of the MMC3 generates IRQs when the scanline counter is equal to 0.
    // In the community, this is known as the "normal" or "new" behavior.
    if (chr_ain[12] && a12_ctr == 0) begin
      counter <= new_counter;
      if ( (!mmc3_alt_behavior  || counter != 0 || irq_reload) && new_counter == 0 && irq_enable) begin
//        $write("MMC3 SCANLINE IRQ!\n");
        irq <= 1;
      end
      irq_reload <= 0;      
    end
    a12_ctr <= chr_ain[12] ? 4'b1111 : (a12_ctr != 0) ? a12_ctr - 4'b0001 : a12_ctr;
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
    // mapper47 is limited to 128k PRG, the top bits are controlled by mapper47_multicart instead.
    if (mapper47) prgsel[5:4] = {1'b0, mapper47_multicart};
  end

  // The CHR bank to load. Each increment here is 1kb. So valid values are 0..255.
  reg [7:0] chrsel;
  always @* begin
    casez({chr_ain[12] ^ chr_a12_invert, chr_ain[11], chr_ain[10]})
    3'b00?: chrsel = {chr_bank_0, chr_ain[10]};
    3'b01?: chrsel = {chr_bank_1, chr_ain[10]};
    3'b100: chrsel = chr_bank_2;
    3'b101: chrsel = chr_bank_3;
    3'b110: chrsel = chr_bank_4;
    3'b111: chrsel = chr_bank_5;
    endcase
    // mapper47 is limited to 128k CHR, the top bit is controlled by mapper47_multicart instead.
    if (mapper47) chrsel[7] = mapper47_multicart;
  end

  wire [21:0] prg_aout_tmp = {3'b00_0,  prgsel, prg_ain[12:0]};

  assign {chr_allow, chr_aout} = 
      (TQROM && chrsel[6]) ? {1'b1,      9'b11_1111_111, chrsel[2:0], chr_ain[9:0]} :   // TQROM 8kb CHR-RAM
                             {flags[15], 4'b10_00, chrsel, chr_ain[9:0]};               // Standard MMC3

  assign prg_is_ram = prg_ain >= 'h6000 && prg_ain < 'h8000 && ram_enable && !(ram_protect && prg_write);
  assign prg_allow = prg_ain[15] && !prg_write || prg_is_ram && !mapper47;
  wire [21:0] prg_ram = {9'b11_1100_000, prg_ain[12:0]};
  assign prg_aout = prg_is_ram  && !mapper47 ? prg_ram : prg_aout_tmp;
  assign vram_a10 = (TxSROM == 0) ? (mirroring ? chr_ain[11] : chr_ain[10]) :
                                    chrsel[7];
  assign vram_ce = chr_ain[13];
endmodule

module MMC5(input clk, input ce, input reset,
            input [31:0] flags,
            input [19:0] ppuflags,
            input [15:0] prg_ain, output [21:0] prg_aout,
            input prg_read, prg_write,                   // Read / write signals
            input [7:0] prg_din, output reg [7:0] prg_dout,
            output prg_allow,                            // Enable access to memory for the specified operation.
            input [13:0] chr_ain, output reg [21:0] chr_aout,
            output reg [7:0] chr_dout, output has_chr_dout,
            output chr_allow,                            // Allow write
            output vram_a10,                             // Value for A10 address line
            output vram_ce,                              // True if the address should be routed to the internal 2kB VRAM.
            output irq);
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
  
  // unpack ppu flags
  wire ppu_in_frame = ppuflags[0];
  wire ppu_sprite16 = ppuflags[1];
  wire [8:0] ppu_cycle = ppuflags[10:2]; 
  wire [8:0] ppu_scanline = ppuflags[19:11];
  
  // Handle IO register writes  
  always @(posedge clk) begin
    if (ce) begin
      if (prg_write && prg_ain[15:10] == 6'b010100) begin // $5000-$53FF
        if (prg_ain <= 16'h5113)
          $write("%X <= %X (%d)\n", prg_ain, prg_din, ppu_scanline);
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
        10'h200: {vsplit_enable, vsplit_side, vsplit_startstop} = {prg_din[7:6], prg_din[4:0]};
        10'h201: vsplit_scroll <= prg_din;
        10'h202: vsplit_bank <= prg_din;
        10'h203: irq_scanline <= prg_din;
        10'h204: irq_enable <= prg_din[7];
        10'h205: multiplier_1 <= prg_din;
        10'h206: multiplier_2 <= prg_din;
        default: begin end
        endcase
        
        // Remember which set of CHR was written to last.
        if (prg_ain[9:0] >= 10'h120 && prg_ain[9:0] < 10'h130)
          chr_last <= prg_ain[3];
      end
      
      // Mode 0/1 - Not readable (returns open bus), can only be written while the PPU is rendering (otherwise, 0 is written)
      // Mode 2 - Readable and writable
      // Mode 3 - Read-only
      if (prg_write && prg_ain[15:10] == 6'b010111) begin // $5C00-$5FFF
        if (extended_ram_mode != 3)
          expansion_ram[prg_ain[9:0]] <= (extended_ram_mode[1] || ppu_in_frame) ? prg_din : 0;
      end
    end
    if (reset) begin
      prg_bank_3 <= 7'h7F;
      prg_mode <= 3;
    end
  end
  
  // Read from MMC5
  always @* begin
    prg_dout = 8'hFF; // By default open bus.
    if (prg_ain[15:10] == 6'b010111 && extended_ram_mode[1]) begin
      prg_dout = last_read_ram;
    end else if (prg_ain == 16'h5204) begin
      prg_dout = {irq_pending, ppu_in_frame, 6'b111111};
    end else if (prg_ain == 16'h5205) begin
      prg_dout = multiply_result[7:0];
    end else if (prg_ain == 16'h5206) begin
      prg_dout = multiply_result[15:8];
    end
  end
  
  // Determine IRQ handling
  reg last_scanline, irq_trig;
  always @(posedge clk) if (ce) begin
    if (prg_read && prg_ain == 16'h5204)
      irq_pending <= 0;
    irq_trig <= (irq_scanline != 0 && irq_scanline < 240 && ppu_scanline == {1'b0, irq_scanline});
    last_scanline <= ppu_scanline[0];
    if (ppu_scanline[0] != last_scanline && irq_trig)
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
    new_cur_tile = (ppu_cycle[8:3] == 40) ? 0 : (cur_tile + 6'b1);
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
  always @(posedge clk) if (ce) begin
    last_in_split_area <= in_split_area;
    if (ppu_cycle[2:0] == 0 && ppu_cycle < 336)
      cur_tile <= new_cur_tile;
  end
  // Keep track of scroll
  always @(posedge clk) if (ce) begin
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
  wire exattr_read = (extended_ram_mode == 1) && ppu_cycle[1];
  
  // If the current chr read should be redirected from |chr_dout| instead.
  assign has_chr_dout = chr_ain[13] && (mirrbits[1] || insplit || exattr_read);
  wire [1:0] override_attr = insplit ? split_attr : (extended_ram_mode == 1) ? last_read_ram[7:6] : fill_attr;
  always @* begin
    if (ppu_cycle[1] == 0) begin
      // Name table fetch
      if (insplit || mirrbits[0] == 0) chr_dout = (extended_ram_mode[1] ? 8'b0 : last_read_ram);
      else begin
        $write("Inserting filltile!\n");
        chr_dout = fill_tile;
      end
    end else begin
      // Attribute table fetch
      if (!insplit && !exattr_read && mirrbits[0] == 0) chr_dout = (extended_ram_mode[1] ? 8'b0 : last_read_ram);
      else chr_dout = {override_attr, override_attr, override_attr, override_attr};
    end
  end

  // Handle reading from the expansion ram.
  // 0 - Use as extra nametable (possibly for split mode)
  // 1 - Use as extended attribute data OR an extra nametable
  // 2 - Use as ordinary RAM
  // 3 - Use as ordinary RAM, write protected
  wire [9:0] exram_read_addr = extended_ram_mode[1] ? prg_ain[9:0] : 
                               insplit              ? split_addr :
                                                      chr_ain[9:0];
  always @(posedge clk)
    last_read_ram <= expansion_ram[exram_read_addr];

  // Compute PRG address to read from.
  reg [7:0] prgsel;
  always @* begin
    casez({prg_mode, prg_ain[15:13]})
    5'b??_0??: prgsel = {5'b1xxxx, prg_ram_bank};                // $6000-$7FFF all modes
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
    prgsel[7] = !prgsel[7]; // 0 means RAM, doh.
    
    // Limit to 64k RAM.
    if (prgsel[7])
      prgsel[6:3] = 0;
  end
  assign prg_aout = {1'b0, prgsel, prg_ain[12:0]};    // 8kB banks

  // Registers $5120-$5127 apply to sprite graphics and $5128-$512B for background graphics, but ONLY when 8x16 sprites are enabled.
  // Otherwise, the last set of registers written to (either $5120-$5127 or $5128-$512B) will be used for all graphics.
  // 0 if using $5120-$5127, 1 if using $5128-$512F
  wire is_bg_fetch = !(ppu_cycle[8] && !ppu_cycle[6]);
  wire chrset = ppu_sprite16 ? is_bg_fetch : chr_last; 
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
    if (insplit) begin
      $write("In vertical split!\n");
      chr_aout = {2'b10, vsplit_bank, chr_ain[11:3], vscroll[2:0]};
    end else if (extended_ram_mode == 1 && is_bg_fetch) begin
      $write("In exram thingy!\n");
      // Extended attribute mode. Replace the page with the page from exram.
      chr_aout = {2'b10, upper_chr_bank_bits, last_read_ram[5:0], chr_ain[11:0]};
    end
      
  end
  
  // The a10 VRAM address line. (Used for mirroring)
  assign vram_a10 = mirrbits[0];
  assign vram_ce = chr_ain[13] && !mirrbits[1];
  
  // Writing to RAM is enabled only when the protect bits say so.  
  wire prg_ram_we = prg_protect_1 && prg_protect_2;
  assign prg_allow = (prg_ain >= 16'h6000) && (!prg_write || prgsel[7] && prg_ram_we);
  
  // MMC5 boards typically have no CHR RAM.
  assign chr_allow = flags[15];
endmodule

// iNES mapper 64 and 158 - Tengen's version of MMC3
module Rambo1(input clk, input ce, input reset,
              input [31:0] flags,
              input [15:0] prg_ain, output [21:0] prg_aout,
              input prg_read, prg_write,                   // Read / write signals
              input [7:0] prg_din,
              output prg_allow,                            // Enable access to memory for the specified operation.
              input [13:0] chr_ain, output [21:0] chr_aout,
              output chr_allow,                            // Allow write
              output vram_a10,                             // Value for A10 address line
              output vram_ce,                              // True if the address should be routed to the internal 2kB VRAM.
              output reg irq);
  reg [3:0] bank_select;             // Register to write to next
  reg prg_rom_bank_mode;             // Mode for PRG banking
  reg chr_K;                         // Mode for CHR banking
  reg chr_a12_invert;                // Mode for CHR banking
  reg mirroring;                     // 0 = vertical, 1 = horizontal
  reg irq_enable, irq_reload;        // IRQ enabled, and IRQ reload requested
  reg [7:0] irq_latch, counter;      // IRQ latch value and current counter
  reg want_irq;
  reg [7:0] chr_bank_0, chr_bank_1;  // Selected CHR banks
  reg [7:0] chr_bank_2, chr_bank_3, chr_bank_4, chr_bank_5;
  reg [7:0] chr_bank_8, chr_bank_9;
  reg [5:0] prg_bank_0, prg_bank_1, prg_bank_2;  // Selected PRG banks
  reg irq_cycle_mode;
  reg [1:0] cycle_counter;
 
  // Mapper has vram_a10 wired to CHR A17
  wire mapper64 = (flags[7:0] == 64);

  reg is_interrupt;  // Not a reg!
  
  // This code detects rising edges on a12.
  reg old_a12_edge;
  reg [1:0] a12_ctr;
  wire a12_edge = (chr_ain[12] && a12_ctr == 0) || old_a12_edge;
  always @(posedge clk) begin
    old_a12_edge <= a12_edge && !ce;
    a12_ctr <= chr_ain[12] ? 2'b11 : (a12_ctr != 0 && ce) ? a12_ctr - 2'b01 : a12_ctr;
  end
  
  always @(posedge clk) if (reset) begin
    bank_select <= 0;
    prg_rom_bank_mode <= 0;
    chr_K <= 0;
    chr_a12_invert <= 0;
    mirroring <= 0;
    {irq_enable, irq_reload} <= 0;
    {irq_latch, counter} <= 0;
    want_irq <= 0;
    {chr_bank_0, chr_bank_1} <= 0;
    {chr_bank_2, chr_bank_3, chr_bank_4, chr_bank_5} <= 0;
    {chr_bank_8, chr_bank_9} <= 0;
    {prg_bank_0, prg_bank_1, prg_bank_2} <= 0;
    irq_cycle_mode <= 0;
    cycle_counter <= 0;
    irq <= 0;
  end else if (ce) begin
    cycle_counter <= cycle_counter + 1;
        
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
                 {irq_reload, irq_cycle_mode} <= {1'b1, prg_din[0]}; // IRQ reload ($C001-$DFFF, odd)
                 cycle_counter <= 0;
               end
      3'b11_0: {irq_enable, irq} <= 2'b0;                 // IRQ disable ($E000-$FFFE, even)
      3'b11_1: irq_enable <= 1;                           // IRQ enable ($E001-$FFFF, odd)
      endcase
    end
    is_interrupt = irq_cycle_mode ? (cycle_counter == 3) : a12_edge;
    if (is_interrupt) begin
      if (irq_reload || counter == 0) begin
        counter <= irq_latch;
        want_irq <= irq_reload;
      end else begin
        counter <= counter - 1;
        want_irq <= 1;
      end
      if (counter == 0 && want_irq && !irq_reload && irq_enable)
        irq <= 1;
      irq_reload <= 0;
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
  assign vram_a10 = mapper64 ? chrsel[7] :  // Mapper 64 controls mirroring by switching the top bits of the CHR address
                    mirroring ? chr_ain[11] : chr_ain[10];
  assign vram_ce = chr_ain[13];
endmodule


// #13 - CPROM - Used by Videomation
module Mapper13(input clk, input ce, input reset,
                input [31:0] flags,
                input [15:0] prg_ain, output [21:0] prg_aout,
                input prg_read, prg_write,                   // Read / write signals
                input [7:0] prg_din,
                output prg_allow,                            // Enable access to memory for the specified operation.
                input [13:0] chr_ain, output [21:0] chr_aout,
                output chr_allow,                      // Allow write
                output vram_a10,                             // Value for A10 address line
                output vram_ce);                             // True if the address should be routed to the internal 2kB VRAM.
  reg [1:0] chr_bank;
  always @(posedge clk) if (reset) begin
    chr_bank <= 0;
  end else if (ce) begin
    if (prg_ain[15] && prg_write)
      chr_bank <= prg_din[1:0];
  end
  assign prg_aout = {7'b00_0000_0, prg_ain[14:0]};
  assign prg_allow = prg_ain[15] && !prg_write;
  assign chr_allow = flags[15];
  assign chr_aout = {8'b01_0000_00, chr_ain[12] ? chr_bank : 2'b00, chr_ain[11:0]};
  assign vram_ce = chr_ain[13];
  assign vram_a10 = flags[14] ? chr_ain[10] : chr_ain[11];
endmodule

// #15 -  100-in-1 Contra Function 16
module Mapper15(input clk, input ce, input reset,
                input [31:0] flags,
                input [15:0] prg_ain, output [21:0] prg_aout,
                input prg_read, prg_write,                   // Read / write signals
                input [7:0] prg_din,
                output prg_allow,                            // Enable access to memory for the specified operation.
                input [13:0] chr_ain, output [21:0] chr_aout,
                output chr_allow,                      // Allow write
                output vram_a10,                             // Value for A10 address line
                output vram_ce);                             // True if the address should be routed to the internal 2kB VRAM.
// 15 bit  8 7  bit  0  Address bus
// ---- ---- ---- ----
// 1xxx xxxx xxxx xxSS
// |                ||
// |                ++- Select PRG ROM bank mode
// |                    0: 32K; 1: 128K (UNROM style); 2: 8K; 3: 16K
// +------------------- Always 1
// 7  bit  0  Data bus
// ---- ----
// bMBB BBBB
// |||| ||||
// ||++-++++- Select 16 KB PRG ROM bank
// |+-------- Select nametable mirroring mode (0=vertical; 1=horizontal)
// +--------- Select 8 KB half of 16 KB PRG ROM bank
//            (should be 0 except in bank mode 0)
  reg [1:0] prg_rom_bank_mode;
  reg prg_rom_bank_lowbit;
  reg mirroring;
  reg [5:0] prg_rom_bank;
  always @(posedge clk) if (reset) begin
    prg_rom_bank_mode <= 0;
    prg_rom_bank_lowbit <= 0;
    mirroring <= 0;
    prg_rom_bank <= 0;
  end else if (ce) begin
    if (prg_ain[15] && prg_write)
      {prg_rom_bank_mode, prg_rom_bank_lowbit, mirroring, prg_rom_bank} <= {prg_ain[1:0], prg_din[7:0]};
  end
  reg [6:0] prg_bank;
  always begin
    casez({prg_rom_bank_mode, prg_ain[14]})
    // Bank mode 0 ( 32K ) / CPU $8000-$BFFF: Bank B / CPU $C000-$FFFF: Bank (B OR 1)
    3'b00_0: prg_bank = {prg_rom_bank, prg_ain[13]};
    3'b00_1: prg_bank = {prg_rom_bank | 6'b1, prg_ain[13]};
    // Bank mode 1 ( 128K ) / CPU $8000-$BFFF: Switchable 16 KB bank B / CPU $C000-$FFFF: Fixed to last bank in the cart
    3'b01_0: prg_bank = {prg_rom_bank, prg_ain[13]};
    3'b01_1: prg_bank = {6'b111111, prg_ain[13]};
    // Bank mode 2 ( 8K ) / CPU $8000-$9FFF: Sub-bank b of 16 KB PRG ROM bank B / CPU $A000-$FFFF: Mirrors of $8000-$9FFF
    3'b10_?: prg_bank = {prg_rom_bank, prg_rom_bank_lowbit};
    // Bank mode 3 ( 16K ) / CPU $8000-$BFFF: 16 KB bank B / CPU $C000-$FFFF: Mirror of $8000-$BFFF
    3'b11_?: prg_bank = {prg_rom_bank, prg_ain[13]};
    endcase
  end
  assign prg_aout = {2'b00, prg_bank, prg_ain[12:0]};
  assign prg_allow = prg_ain[15] && !prg_write;
  assign chr_allow = flags[15]; // CHR RAM?
  assign chr_aout = {9'b10_0000_000, chr_ain[12:0]};
  assign vram_ce = chr_ain[13];
  assign vram_a10 = mirroring ? chr_ain[11] : chr_ain[10];
endmodule

// Tepples/Multi-discrete mapper
// This mapper can emulate other mappers,  such as mapper #0, mapper #2
module Mapper28(input clk, input ce, input reset,
                input [31:0] flags,
                input [15:0] prg_ain, output [21:0] prg_aout,
                input prg_read, prg_write,                   // Read / write signals
                input [7:0] prg_din,
                output prg_allow,                            // Enable access to memory for the specified operation.
                input [13:0] chr_ain, output [21:0] chr_aout,
                output chr_allow,                      // Allow write
                output reg vram_a10,                         // Value for A10 address line
                output vram_ce);                             // True if the address should be routed to the internal 2kB VRAM.
    reg [6:0] a53prg;    // output PRG ROM (A14-A20 on ROM)
    reg [1:0] a53chr;    // output CHR RAM (A13-A14 on RAM)
   
    reg [3:0] inner;    // "inner" bank at 01h
    reg [5:0] mode;     // mode register at 80h
    reg [5:0] outer;    // "outer" bank at 81h  
    reg [1:0] selreg;   // selector register
    
    // Allow writes to 0x5000 only when launching through the proper mapper ID.
    wire [7:0] mapper = flags[7:0];
    wire allow_select = (mapper == 8'd28);
        
    always @(posedge clk) if (reset) begin
      mode[5:2] <= 0;         // NROM mode, 32K mode
      outer[5:0] <= 6'h3f;    // last bank
      inner <= 0;
      selreg <= 1;
      
      // Set value for mirroring
      if (mapper == 2 || mapper == 0 || mapper == 3)
        mode[1:0] <= flags[14] ? 2'b10 : 2'b11;
        
      // UNROM #2 - Current bank in $8000-$BFFF and fixed top half of outer bank in $C000-$FFFF
      if (mapper == 2)
        mode[5:2] <= 4'b1111;
        
      // CNROM #3 - Fixed PRG bank, switchable CHR bank.
      if (mapper == 3)
        selreg <= 0;

      // AxROM #7 - Switch 32kb rom bank + switchable nametables
      if (mapper == 7) begin
        mode[1:0] <= 2'b00;   // Switchable VRAM page.
        mode[5:2] <= 4'b1100; // 256K banks, (B)NROM mode
      end
    end else if (ce) begin
      if ((prg_ain[15:12] == 4'h5) & prg_write && allow_select) selreg <= {prg_din[7], prg_din[0]};        // select register
      if (prg_ain[15] & prg_write) begin
        case (selreg)
        2'h0:  {mode[0], a53chr}  <= {(mode[1] ? mode[0] : prg_din[4]), prg_din[1:0]};  // CHR RAM bank
        2'h1:  {mode[0], inner}   <= {(mode[1] ? mode[0] : prg_din[4]), prg_din[3:0]};  // "inner" bank
        2'h2:  {mode}             <= {prg_din[5:0]};                                    // mode register
        2'h3:  {outer}            <= {prg_din[5:0]};                                    // "outer" bank
        endcase
      end
    end
    
    always begin
      // mirroring mode
      casez(mode[1:0])
      2'b0?   :   vram_a10 = {mode[0]};        // 1 screen lower
      2'b10   :   vram_a10 = {chr_ain[10]};    // vertical
      2'b11   :   vram_a10 = {chr_ain[11]};    // horizontal
      endcase

      // PRG ROM bank size select
      casez({mode[5:2], prg_ain[14]})
      5'b00_0?_?  :  a53prg = {outer[5:0],             prg_ain[14]};  // 32K banks, (B)NROM mode
      5'b01_0?_?  :  a53prg = {outer[5:1], inner[0],   prg_ain[14]};  // 64K banks, (B)NROM mode
      5'b10_0?_?  :  a53prg = {outer[5:2], inner[1:0], prg_ain[14]};  // 128K banks, (B)NROM mode
      5'b11_0?_?  :  a53prg = {outer[5:3], inner[2:0], prg_ain[14]};  // 256K banks, (B)NROM mode
      
      5'b00_10_1,
      5'b00_11_0  :  a53prg = {outer[5:0], inner[0]};             // 32K banks, UNROM mode
      5'b01_10_1,
      5'b01_11_0  :  a53prg = {outer[5:1], inner[1:0]};           // 64K banks, UNROM mode
      5'b10_10_1,
      5'b10_11_0  :  a53prg = {outer[5:2], inner[2:0]};           // 128K banks, UNROM mode
      5'b11_10_1,
      5'b11_11_0  :  a53prg = {outer[5:3], inner[3:0]};           // 256K banks, UNROM mode
      
      default     :  a53prg = {outer[5:0],             prg_ain[14]};  // 16K fixed bank
      endcase
    end

  assign vram_ce = chr_ain[13];
  assign prg_aout = {1'b0, (a53prg & 7'b0011111), prg_ain[13:0]};
  assign prg_allow = prg_ain[15] && !prg_write;
  assign chr_allow = flags[15];
  assign chr_aout = {7'b10_0000_0, a53chr, chr_ain[12:0]};
endmodule

// 11 - Color Dreams
// 66 - GxROM
module Mapper66(input clk, input ce, input reset,
                input [31:0] flags,
                input [15:0] prg_ain, output [21:0] prg_aout,
                input prg_read, prg_write,                   // Read / write signals
                input [7:0] prg_din,
                output prg_allow,                            // Enable access to memory for the specified operation.
                input [13:0] chr_ain, output [21:0] chr_aout,
                output chr_allow,                      // Allow write
                output vram_a10,                             // Value for A10 address line
                output vram_ce);                             // True if the address should be routed to the internal 2kB VRAM.
  reg [1:0] prg_bank;
  reg [3:0] chr_bank;
  wire GXROM = (flags[7:0] == 66);
  always @(posedge clk) if (reset) begin
    prg_bank <= 0;
    chr_bank <= 0;
  end else if (ce) begin
    if (prg_ain[15] & prg_write) begin
      if (GXROM)
        {prg_bank, chr_bank} <= {prg_din[5:4], 2'b0, prg_din[1:0]};
      else // Color Dreams
        {chr_bank, prg_bank} <= {prg_din[7:4], prg_din[1:0]};
    end
  end
  assign prg_aout = {5'b00_000, prg_bank, prg_ain[14:0]};
  assign prg_allow = prg_ain[15] && !prg_write;
  assign chr_allow = flags[15];
  assign chr_aout = {5'b10_000, chr_bank, chr_ain[12:0]};
  assign vram_ce = chr_ain[13];
  assign vram_a10 = flags[14] ? chr_ain[10] : chr_ain[11];
endmodule

// 34 - BxROM or NINA-001
module Mapper34(input clk, input ce, input reset,
                input [31:0] flags,
                input [15:0] prg_ain, output [21:0] prg_aout,
                input prg_read, prg_write,                   // Read / write signals
                input [7:0] prg_din,
                output prg_allow,                            // Enable access to memory for the specified operation.
                input [13:0] chr_ain, output [21:0] chr_aout,
                output chr_allow,                      // Allow write
                output vram_a10,                             // Value for A10 address line
                output vram_ce);                             // True if the address should be routed to the internal 2kB VRAM.
  reg [1:0] prg_bank;
  reg [3:0] chr_bank_0, chr_bank_1;
  
  wire NINA = (flags[13:11] != 0); // NINA is used when there is more than 8kb of CHR
  always @(posedge clk) if (reset) begin
    prg_bank <= 0;
    chr_bank_0 <= 0;
    chr_bank_1 <= 1; // To be compatible with BxROM
  end else if (ce && prg_write) begin
    if (!NINA) begin // BxROM
      if (prg_ain[15])
        prg_bank <= prg_din[1:0];
    end else begin // NINA
      if (prg_ain == 16'h7ffd)
        prg_bank <= prg_din[1:0];
      else if (prg_ain == 16'h7ffe)
        chr_bank_0 <= prg_din[3:0];
      else if (prg_ain == 16'h7fff)
        chr_bank_1 <= prg_din[3:0];
    end
  end

  wire [21:0] prg_aout_tmp = {5'b00_000, prg_bank, prg_ain[14:0]};
  assign chr_allow = flags[15];
  assign chr_aout = {6'b10_0000, chr_ain[12] == 0 ? chr_bank_0 : chr_bank_1, chr_ain[11:0]};
  assign vram_ce = chr_ain[13];
  assign vram_a10 = flags[14] ? chr_ain[10] : chr_ain[11];

  wire prg_is_ram = (prg_ain >= 'h6000 && prg_ain < 'h8000) && NINA;
  assign prg_allow = prg_ain[15] && !prg_write ||
                     prg_is_ram;
  wire [21:0] prg_ram = {9'b11_1100_000, prg_ain[12:0]};
  assign prg_aout = prg_is_ram ? prg_ram : prg_aout_tmp;
endmodule

// 41 - Caltron 6-in-1
module Mapper41(input clk, input ce, input reset,
                input [31:0] flags,
                input [15:0] prg_ain, output [21:0] prg_aout,
                input prg_read, prg_write,                   // Read / write signals
                input [7:0] prg_din,
                output prg_allow,                            // Enable access to memory for the specified operation.
                input [13:0] chr_ain, output [21:0] chr_aout,
                output chr_allow,                      // Allow write
                output vram_a10,                             // Value for A10 address line
                output vram_ce);                             // True if the address should be routed to the internal 2kB VRAM.
  reg [2:0] prg_bank;
  reg [1:0] chr_outer_bank, chr_inner_bank;
  reg mirroring;
  
  always @(posedge clk) if (reset) begin
    prg_bank <= 0;
    chr_outer_bank <= 0;
    chr_inner_bank <= 0;
    mirroring <= 0;
  end else if (ce && prg_write) begin
    if (prg_ain[15:11] == 5'b01100) begin
      {mirroring, chr_outer_bank, prg_bank} <= prg_ain[5:0];
    end else if (prg_ain[15] && prg_bank[2]) begin
      // The Inner CHR Bank Select only can be written while the PRG ROM bank is 4, 5, 6, or 7
      chr_inner_bank <= prg_din[1:0];
    end
  end

  assign prg_aout = {4'b00_00, prg_bank, prg_ain[14:0]};
  assign chr_allow = flags[15];
  assign chr_aout = {5'b10_000, chr_outer_bank, chr_inner_bank, chr_ain[12:0]};
  assign vram_ce = chr_ain[13];
  assign vram_a10 = mirroring ? chr_ain[11] : chr_ain[10];
  assign prg_allow = prg_ain[15] && !prg_write;
endmodule

// #68 - Sunsoft-4 - Game After Burner, and some japanese games. MAX: 128kB PRG, 256kB CHR
module Mapper68(input clk, input ce, input reset,
                input [31:0] flags,
                input [15:0] prg_ain, output [21:0] prg_aout,
                input prg_read, prg_write,                   // Read / write signals
                input [7:0] prg_din,
                output prg_allow,                            // Enable access to memory for the specified operation.
                input [13:0] chr_ain, output [21:0] chr_aout,
                output chr_allow,                      // Allow write
                output vram_a10,                             // Value for A10 address line
                output vram_ce);                             // True if the address should be routed to the internal 2kB VRAM.
  reg [6:0] chr_bank_0, chr_bank_1, chr_bank_2, chr_bank_3;
  reg [6:0] nametable_0, nametable_1;
  reg [2:0] prg_bank;
  reg use_chr_rom;
  reg mirroring;
  always @(posedge clk) if (reset) begin
    chr_bank_0 <= 0;
    chr_bank_1 <= 0;
    chr_bank_2 <= 0;
    chr_bank_3 <= 0;
    nametable_0 <= 0;
    nametable_1 <= 0;
    prg_bank <= 0;
    use_chr_rom <= 0;
    mirroring <= 0;
  end else if (ce) begin
    if (prg_ain[15] && prg_write) begin
//      $write("REG[%d] <= %X\n", prg_ain[14:12], prg_din);
      case(prg_ain[14:12])
      0: chr_bank_0  <= prg_din[6:0]; // $8000-$8FFF: 2kB CHR bank at $0000
      1: chr_bank_1  <= prg_din[6:0]; // $9000-$9FFF: 2kB CHR bank at $0800
      2: chr_bank_2  <= prg_din[6:0]; // $A000-$AFFF: 2kB CHR bank at $1000
      3: chr_bank_3  <= prg_din[6:0]; // $B000-$BFFF: 2kB CHR bank at $1800
      4: nametable_0 <= prg_din[6:0]; // $C000-$CFFF: 1kB Nametable register 0 at $2000
      5: nametable_1 <= prg_din[6:0]; // $D000-$DFFF: 1kB Nametable register 1 at $2400
      6: {use_chr_rom, mirroring} <= {prg_din[4], prg_din[0]};  // $E000-$EFFF: Nametable control
      7: prg_bank <= prg_din[2:0]; 
      endcase
    end
  end
  wire [2:0] prgout = (prg_ain[14] ? 3'b111 : prg_bank);
  assign prg_aout = {5'b00_000, prgout, prg_ain[13:0]};
  assign prg_allow = prg_ain[15] && !prg_write;

  reg [6:0] chrout;  
  always begin
    casez(chr_ain[12:11])
    0: chrout = chr_bank_0;
    1: chrout = chr_bank_1;
    2: chrout = chr_bank_2;
    3: chrout = chr_bank_3;
    endcase
  end
  assign vram_a10 = mirroring ? chr_ain[11] : chr_ain[10];
  wire [6:0] nameout = (vram_a10 == 0) ? nametable_0 : nametable_1;
 
  assign chr_allow = flags[15];
  assign chr_aout = (chr_ain[13] == 0) ? {4'b10_00, chrout, chr_ain[10:0]} : {5'b10_001, nameout, chr_ain[9:0]};
  assign vram_ce = chr_ain[13] && !use_chr_rom;

endmodule



// 69 - Sunsoft FME-7
module Mapper69(input clk, input ce, input reset,
                input [31:0] flags,
                input [15:0] prg_ain, output [21:0] prg_aout,
                input prg_read, prg_write,                   // Read / write signals
                input [7:0] prg_din,
                output prg_allow,                          // Enable access to memory for the specified operation.
                input [13:0] chr_ain, output [21:0] chr_aout,
                output chr_allow,                             // Allow write
                output reg vram_a10,                          // Value for A10 address line
                output vram_ce,                               // True if the address should be routed to the internal 2kB VRAM.
                output reg irq);
  reg [7:0] chr_bank[0:7];
  reg [4:0] prg_bank[0:3];
  reg [1:0] mirroring;
  reg irq_countdown, irq_trigger;
  reg [15:0] irq_counter;
  reg [3:0] addr;
  reg ram_enable, ram_select;
  wire [16:0] new_irq_counter = irq_counter - {15'b0, irq_countdown};
  always @(posedge clk) if (reset) begin
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
    2'b00   :   vram_a10 = {chr_ain[10]};    // vertical
    2'b01   :   vram_a10 = {chr_ain[11]};    // horizontal
    2'b1?   :   vram_a10 = {mirroring[0]};   // 1 screen lower
    endcase
  end
  reg [4:0] prgout;
  reg [7:0] chrout;
  always begin
    casez(prg_ain[15:13])
    3'b011:  prgout = prg_bank[0];
    3'b100:  prgout = prg_bank[1];
    3'b101:  prgout = prg_bank[2];
    3'b110:  prgout = prg_bank[3];
    3'b111:  prgout = 5'b11111;
    default: prgout = 5'bxxxxx;
    endcase
    chrout = chr_bank[chr_ain[12:10]];
  end
  wire ram_cs = (prg_ain[15] == 0 && ram_select);
  assign prg_aout = {1'b0, ram_cs, 2'b00, prgout[4:0], prg_ain[12:0]};
  assign prg_allow = ram_cs ? ram_enable : !prg_write;
  assign chr_allow = flags[15];
  assign chr_aout = {4'b10_00, chrout, chr_ain[9:0]};
  assign vram_ce = chr_ain[13];
endmodule

// #71,#232 - Camerica
module Mapper71(input clk, input ce, input reset,
                input [31:0] flags,
                input [15:0] prg_ain, output [21:0] prg_aout,
                input prg_read, prg_write,                   // Read / write signals
                input [7:0] prg_din,
                output prg_allow,                            // Enable access to memory for the specified operation.
                input [13:0] chr_ain, output [21:0] chr_aout,
                output chr_allow,                      // Allow write
                output vram_a10,                             // Value for A10 address line
                output vram_ce);                             // True if the address should be routed to the internal 2kB VRAM.
  reg [3:0] prg_bank;
  reg ciram_select;
  wire mapper232 = (flags[7:0] == 232);
  always @(posedge clk) if (reset) begin
    prg_bank <= 0;
    ciram_select <= 0;
  end else if (ce) begin
    if (prg_ain[15] && prg_write) begin
      $write("%X <= %X (bank = %x)\n", prg_ain, prg_din, prg_bank);
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

// #79,#113 - NINA-03 / NINA-06
module Mapper79(input clk, input ce, input reset,
                input [31:0] flags,
                input [15:0] prg_ain, output [21:0] prg_aout,
                input prg_read, prg_write,                   // Read / write signals
                input [7:0] prg_din,
                output prg_allow,                            // Enable access to memory for the specified operation.
                input [13:0] chr_ain, output [21:0] chr_aout,
                output chr_allow,                      // Allow write
                output vram_a10,                             // Value for A10 address line
                output vram_ce);                             // True if the address should be routed to the internal 2kB VRAM.
  reg [2:0] prg_bank;
  reg [3:0] chr_bank;
  reg mirroring;  // 0: Horizontal, 1: Vertical
  wire mapper113 = (flags[7:0] == 113); // NINA-06
  always @(posedge clk) if (reset) begin
    prg_bank <= 0;
    chr_bank <= 0;
    mirroring <= 0;
  end else if (ce) begin
    if (prg_ain[15:13] == 3'b010 && prg_ain[8] && prg_write)
      {mirroring, chr_bank[3], prg_bank, chr_bank[2:0]} <= prg_din;
  end
  assign prg_aout = {4'b00_00, prg_bank, prg_ain[14:0]};
  assign prg_allow = prg_ain[15] && !prg_write;
  assign chr_allow = flags[15];
  assign chr_aout = {5'b10_000, chr_bank, chr_ain[12:0]};
  assign vram_ce = chr_ain[13];
  wire mirrconfig = mapper113 ? mirroring : flags[14]; // Mapper #13 has mapper controlled mirroring
  assign vram_a10 = mirrconfig ? chr_ain[10] : chr_ain[11]; // 0: horiz, 1: vert
endmodule

// #105 - NES-EVENT. Retrofits an MMC3 with lots of extra logic.
module NesEvent(input clk, input ce, input reset,
                input [15:0] prg_ain, output reg [21:0] prg_aout,
                input [13:0] chr_ain, output [21:0] chr_aout,
                input [3:0] mmc1_chr,                   // Upper 4 CHR output control bits from MMC chip
                input [21:0] mmc1_aout,                 // PRG output address from MMC chip
                output irq);
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
  always @(posedge clk) if (reset) begin
    old_val <= 0;
    unlocked <= 0;
    counter <= 0;
  end else if (ce) begin
    // Handle unlock.
    if (mmc1_chr[3] && !old_val) unlocked <= 1;
    old_val <= mmc1_chr[3];
    // The 'I' bit in $A000 controls the IRQ counter.  When cleared, the IRQ counter counts up every cycle.  When
    // set, the IRQ counter is reset to 0 and stays there (does not count), and the pending IRQ is acknowledged.
    counter <= mmc1_chr[3] ? 0 : counter + 1;
    
    if (mmc1_chr != oldbits) begin
      $write("NESEV Control Bits: %X => %X (%d)\n", oldbits, mmc1_chr, unlocked);
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
      // O=0:  Use first PRG chip (first 128k), use 'A' PRG Reg, 32k swap
      prg_aout = {5'b00_000, mmc1_chr[1:0], prg_ain[14:0]};
    end else begin
      // O=1:  Use second PRG chip (second 128k), use 'B' PRG Reg, MMC1 style swap
      prg_aout = mmc1_aout;
    end
  end
  // 8kB CHR RAM.
  assign chr_aout = {9'b10_0000_000, chr_ain[12:0]};
endmodule


// iNES Mapper 228 represents the board used by Active Enterprises for Action 52 and Cheetahmen II.
module Mapper228(input clk, input ce, input reset,
                input [31:0] flags,
                input [15:0] prg_ain, output [21:0] prg_aout,
                input prg_read, prg_write,                   // Read / write signals
                input [7:0] prg_din,
                output prg_allow,                          // Enable access to memory for the specified operation.
                input [13:0] chr_ain, output [21:0] chr_aout,
                output chr_allow,                             // Allow write
                output vram_a10,                              // Value for A10 address line
                output vram_ce);                              // True if the address should be routed to the internal 2kB VRAM.
  reg mirroring;
  reg [1:0] prg_chip;
  reg [4:0] prg_bank;
  reg prg_bank_mode;
  reg [5:0] chr_bank;
  always @(posedge clk) if (reset) begin
    {mirroring, prg_chip, prg_bank, prg_bank_mode} <= 0;
    chr_bank <= 0;
  end else if (ce) begin
    if (prg_ain[15] & prg_write) begin
      {mirroring, prg_chip, prg_bank, prg_bank_mode} <= prg_ain[13:5];
      chr_bank <= {prg_ain[3:0], prg_din[1:0]};
    end
  end
  assign vram_a10 = mirroring ? chr_ain[11] : chr_ain[10];
  wire prglow = prg_bank_mode ? prg_bank[0] : prg_ain[14];
  wire [1:0] addrsel = {prg_chip[1], prg_chip[1] ^ prg_chip[0]};
  assign prg_aout = {1'b0, addrsel, prg_bank[4:1], prglow, prg_ain[13:0]};
  assign prg_allow = prg_ain[15] && !prg_write;
  assign chr_allow = flags[15];
  assign chr_aout = {3'b10_0, chr_bank, chr_ain[12:0]};
  assign vram_ce = chr_ain[13];
endmodule

module Mapper234(input clk, input ce, input reset,
                input [31:0] flags,
                input [15:0] prg_ain, output [21:0] prg_aout,
                input prg_read, prg_write,                   // Read / write signals
                input [7:0] prg_din,
                output prg_allow,                          // Enable access to memory for the specified operation.
                input [13:0] chr_ain, output [21:0] chr_aout,
                output chr_allow,                             // Allow write
                output vram_a10,                              // Value for A10 address line
                output vram_ce);                              // True if the address should be routed to the internal 2kB VRAM.
  reg [2:0] block, inner_chr;
  reg mode, mirroring, inner_prg;
  always @(posedge clk) if (reset) begin
    block <= 0;
    {mode, mirroring} <= 0;
    inner_chr <= 0;
    inner_prg <= 0;
  end else if (ce) begin
    if (prg_read && prg_ain[15:7] == 9'b1111_1111_1) begin
      // Outer bank control $FF80 - $FF9F
      if (prg_ain[6:0] < 7'h20 && (block == 0)) begin
        {mirroring, mode} <= prg_din[7:6];
        block <= prg_din[3:1];
        {inner_chr[2], inner_prg} <= {prg_din[0], prg_din[0]};
      end
      // Inner bank control ($FFE8-$FFF7)
      if (prg_ain[6:0] >= 7'h68 && prg_ain[6:0] < 7'h78) begin
        {inner_chr[2], inner_prg} <= mode ? {prg_din[6], prg_din[0]} : {inner_chr[2], inner_prg};
        inner_chr[1:0] <= prg_din[5:4];
      end
    end
  end
  assign vram_a10 = mirroring ? chr_ain[11] : chr_ain[10];
  assign prg_aout = {3'b00_0, block, inner_prg, prg_ain[14:0]};
  assign chr_aout = {3'b10_0, block, inner_chr, chr_ain[12:0]};
  assign prg_allow = prg_ain[15] && !prg_write;
  assign chr_allow = flags[15];
  assign vram_ce = chr_ain[13];
endmodule


// Mapper Status:
// 0 = Working
// 1 = Working
// 2 = Working
// 3 = Working
// 4 = Working
// 5 = Not Implemented (MMC5)
// 7 = Working
// 9 = Working
// 11 = Working
// 13 = Working
// 15 = Works
// 28 = Working
// 34 = Working
// 41 = Working
// 47 = Working
// 64 = Tons of GFX bugs
// 66 = Working
// 68 = Working
// 69 = Working
// 71 = Working
// 79 = Working
// 105 = Working
// 113 = Working
// 118 = Working
// 119 = Working
// 158 = Tons of GFX bugs
// 228 = Working
// 232 = Working
// 232 = Not Tested

module MultiMapper(input clk, input ce, input ppu_ce, input reset,
                   input [19:0] ppuflags,                           // Misc flags from PPU for MMC5 cheating
                   input [31:0] flags,                              // Misc flags from ines header {prg_size(3), chr_size(3), mapper(8)}
                   input [15:0] prg_ain, output reg [21:0] prg_aout,// PRG Input / Output Address Lines
                   input prg_read, prg_write,                       // PRG Read / write signals
                   input [7:0] prg_din, output reg [7:0] prg_dout,  // PRG Data
                   input [7:0] prg_from_ram,                        // PRG Data from RAM
                   output reg prg_allow,                            // PRG Allow write access
                   input chr_read,                                  // Read from CHR
                   input [13:0] chr_ain, output reg [21:0] chr_aout,// CHR Input / Output Address Lines
                   output reg [7:0] chr_dout,                       // Value to override CHR data with
                   output reg has_chr_dout,                         // True if CHR data should be overridden
                   output reg chr_allow,                            // CHR Allow write
                   output reg vram_a10,                             // CHR Value for A10 address line
                   output reg vram_ce,                              // CHR True if the address should be routed to the internal 2kB VRAM.
                   output reg irq);
  wire mmc0_prg_allow, mmc0_vram_a10, mmc0_vram_ce, mmc0_chr_allow;
  wire [21:0] mmc0_prg_addr, mmc0_chr_addr;
  MMC0 mmc0(clk, ce, flags, prg_ain, mmc0_prg_addr, prg_read, prg_write, prg_din, mmc0_prg_allow,
                            chr_ain, mmc0_chr_addr, mmc0_chr_allow, mmc0_vram_a10, mmc0_vram_ce);

  wire mmc1_prg_allow, mmc1_vram_a10, mmc1_vram_ce, mmc1_chr_allow;
  wire [21:0] mmc1_prg_addr, mmc1_chr_addr;
  MMC1 mmc1(clk, ce, reset, flags, prg_ain, mmc1_prg_addr, prg_read, prg_write, prg_din, mmc1_prg_allow,
                                   chr_ain, mmc1_chr_addr, mmc1_chr_allow, mmc1_vram_a10, mmc1_vram_ce);

  wire map28_prg_allow, map28_vram_a10, map28_vram_ce, map28_chr_allow;
  wire [21:0] map28_prg_addr, map28_chr_addr;
  Mapper28 map28(clk, ce, reset, flags, prg_ain, map28_prg_addr, prg_read, prg_write, prg_din, map28_prg_allow,
                                        chr_ain, map28_chr_addr, map28_chr_allow, map28_vram_a10, map28_vram_ce);

  wire mmc2_prg_allow, mmc2_vram_a10, mmc2_vram_ce, mmc2_chr_allow;
  wire [21:0] mmc2_prg_addr, mmc2_chr_addr;
  MMC2 mmc2(clk, ppu_ce, reset, flags, prg_ain, mmc2_prg_addr, prg_read, prg_write, prg_din, mmc2_prg_allow,
                                   chr_read, chr_ain, mmc2_chr_addr, mmc2_chr_allow, mmc2_vram_a10, mmc2_vram_ce);

  wire mmc3_prg_allow, mmc3_vram_a10, mmc3_vram_ce, mmc3_chr_allow, mmc3_irq;
  wire [21:0] mmc3_prg_addr, mmc3_chr_addr;
  MMC3 mmc3(clk, ppu_ce, reset, flags, prg_ain, mmc3_prg_addr, prg_read, prg_write, prg_din, mmc3_prg_allow,
                                   chr_ain, mmc3_chr_addr, mmc3_chr_allow, mmc3_vram_a10, mmc3_vram_ce, mmc3_irq);

  wire mmc5_prg_allow, mmc5_vram_a10, mmc5_vram_ce, mmc5_chr_allow, mmc5_irq;
  wire [21:0] mmc5_prg_addr, mmc5_chr_addr;
  wire [7:0] mmc5_chr_dout, mmc5_prg_dout;
  wire mmc5_has_chr_dout;
  MMC5 mmc5(clk, ppu_ce, reset, flags, ppuflags, prg_ain, mmc5_prg_addr, prg_read, prg_write, prg_din, mmc5_prg_dout, mmc5_prg_allow,
                                   chr_ain, mmc5_chr_addr, mmc5_chr_dout, mmc5_has_chr_dout, 
                                   mmc5_chr_allow, mmc5_vram_a10, mmc5_vram_ce, mmc5_irq);

  wire map13_prg_allow, map13_vram_a10, map13_vram_ce, map13_chr_allow;
  wire [21:0] map13_prg_addr, map13_chr_addr;
  Mapper13 map13(clk, ce, reset, flags, prg_ain, map13_prg_addr, prg_read, prg_write, prg_din, map13_prg_allow,
                                        chr_ain, map13_chr_addr, map13_chr_allow, map13_vram_a10, map13_vram_ce);

  wire map15_prg_allow, map15_vram_a10, map15_vram_ce, map15_chr_allow;
  wire [21:0] map15_prg_addr, map15_chr_addr;
  Mapper15 map15(clk, ce, reset, flags, prg_ain, map15_prg_addr, prg_read, prg_write, prg_din, map15_prg_allow,
                                        chr_ain, map15_chr_addr, map15_chr_allow, map15_vram_a10, map15_vram_ce);

  wire map34_prg_allow, map34_vram_a10, map34_vram_ce, map34_chr_allow;
  wire [21:0] map34_prg_addr, map34_chr_addr;
  Mapper34 map34(clk, ce, reset, flags, prg_ain, map34_prg_addr, prg_read, prg_write, prg_din, map34_prg_allow,
                                        chr_ain, map34_chr_addr, map34_chr_allow, map34_vram_a10, map34_vram_ce);

  wire map41_prg_allow, map41_vram_a10, map41_vram_ce, map41_chr_allow;
  wire [21:0] map41_prg_addr, map41_chr_addr;
  Mapper41 map41(clk, ce, reset, flags, prg_ain, map41_prg_addr, prg_read, prg_write, prg_din, map41_prg_allow,
                                        chr_ain, map41_chr_addr, map41_chr_allow, map41_vram_a10, map41_vram_ce);

  wire map66_prg_allow, map66_vram_a10, map66_vram_ce, map66_chr_allow;
  wire [21:0] map66_prg_addr, map66_chr_addr;
  Mapper66 map66(clk, ce, reset, flags, prg_ain, map66_prg_addr, prg_read, prg_write, prg_din, map66_prg_allow,
                                        chr_ain, map66_chr_addr, map66_chr_allow, map66_vram_a10, map66_vram_ce);

  wire map68_prg_allow, map68_vram_a10, map68_vram_ce, map68_chr_allow;
  wire [21:0] map68_prg_addr, map68_chr_addr;
  Mapper68 map68(clk, ce, reset, flags, prg_ain, map68_prg_addr, prg_read, prg_write, prg_din, map68_prg_allow,
                                        chr_ain, map68_chr_addr, map68_chr_allow, map68_vram_a10, map68_vram_ce);

  wire map69_prg_allow, map69_vram_a10, map69_vram_ce, map69_chr_allow, map69_irq;
  wire [21:0] map69_prg_addr, map69_chr_addr;
  Mapper69 map69(clk, ce, reset, flags, prg_ain, map69_prg_addr, prg_read, prg_write, prg_din, map69_prg_allow,
                                        chr_ain, map69_chr_addr, map69_chr_allow, map69_vram_a10, map69_vram_ce, map69_irq);

  wire map71_prg_allow, map71_vram_a10, map71_vram_ce, map71_chr_allow;
  wire [21:0] map71_prg_addr, map71_chr_addr;
  Mapper71 map71(clk, ce, reset, flags, prg_ain, map71_prg_addr, prg_read, prg_write, prg_din, map71_prg_allow,
                                        chr_ain, map71_chr_addr, map71_chr_allow, map71_vram_a10, map71_vram_ce);

  wire map79_prg_allow, map79_vram_a10, map79_vram_ce, map79_chr_allow;
  wire [21:0] map79_prg_addr, map79_chr_addr;
  Mapper79 map79(clk, ce, reset, flags, prg_ain, map79_prg_addr, prg_read, prg_write, prg_din, map79_prg_allow,
                                        chr_ain, map79_chr_addr, map79_chr_allow, map79_vram_a10, map79_vram_ce);


  wire map228_prg_allow, map228_vram_a10, map228_vram_ce, map228_chr_allow;
  wire [21:0] map228_prg_addr, map228_chr_addr;
  Mapper228 map228(clk, ce, reset, flags, prg_ain, map228_prg_addr, prg_read, prg_write, prg_din, map228_prg_allow,
                                          chr_ain, map228_chr_addr, map228_chr_allow, map228_vram_a10, map228_vram_ce);


  wire map234_prg_allow, map234_vram_a10, map234_vram_ce, map234_chr_allow;
  wire [21:0] map234_prg_addr, map234_chr_addr;
  Mapper234 map234(clk, ce, reset, flags, prg_ain, map234_prg_addr, prg_read, prg_write, prg_from_ram, map234_prg_allow,
                                          chr_ain, map234_chr_addr, map234_chr_allow, map234_vram_a10, map234_vram_ce);

  wire rambo1_prg_allow, rambo1_vram_a10, rambo1_vram_ce, rambo1_chr_allow, rambo1_irq;
  wire [21:0] rambo1_prg_addr, rambo1_chr_addr;
  Rambo1 rambo1(clk, ce, reset, flags, prg_ain, rambo1_prg_addr, prg_read, prg_write, prg_din, rambo1_prg_allow,
                                   chr_ain, rambo1_chr_addr, rambo1_chr_allow, rambo1_vram_a10, rambo1_vram_ce, rambo1_irq);

  wire [21:0] nesev_prg_addr, nesev_chr_addr;
  wire nesev_irq;
  NesEvent nesev(clk, ce, reset, prg_ain, nesev_prg_addr, chr_ain, nesev_chr_addr, mmc1_chr_addr[16:13], mmc1_prg_addr, nesev_irq);
  
  // Mask 
  reg [5:0] prg_mask;
  reg [6:0] chr_mask;

  always @* begin
    case(flags[10:8])
    0: prg_mask = 6'b000000;
    1: prg_mask = 6'b000001;
    2: prg_mask = 6'b000011;
    3: prg_mask = 6'b000111;
    4: prg_mask = 6'b001111;
    5: prg_mask = 6'b011111;
    default: prg_mask = 6'b111111;
    endcase

    case(flags[13:11])
    0: chr_mask = 7'b0000000;
    1: chr_mask = 7'b0000001;
    2: chr_mask = 7'b0000011;
    3: chr_mask = 7'b0000111;
    4: chr_mask = 7'b0001111;
    5: chr_mask = 7'b0011111;
    6: chr_mask = 7'b0111111;
    7: chr_mask = 7'b1111111;
    endcase
    
    irq = 0;
    prg_dout = 8'hff;
    has_chr_dout = 0;
    chr_dout = mmc5_chr_dout;
        
    case(flags[7:0])
    1:  {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow}      = {mmc1_prg_addr, mmc1_prg_allow, mmc1_chr_addr, mmc1_vram_a10, mmc1_vram_ce, mmc1_chr_allow};
    9:  {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow}      = {mmc2_prg_addr, mmc2_prg_allow, mmc2_chr_addr, mmc2_vram_a10, mmc2_vram_ce, mmc2_chr_allow};
    118, // TxSROM connects A17 to CIRAM A10.
    119, // TQROM  uses the Nintendo MMC3 like other TxROM boards but uses the CHR bank number specially.
    47,  // Mapper 047 is a MMC3 multicart
    4:  {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow, irq} = {mmc3_prg_addr, mmc3_prg_allow, mmc3_chr_addr, mmc3_vram_a10, mmc3_vram_ce, mmc3_chr_allow, mmc3_irq};

    5:  {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow, has_chr_dout, prg_dout, irq} = {mmc5_prg_addr, mmc5_prg_allow, mmc5_chr_addr, mmc5_vram_a10, mmc5_vram_ce, mmc5_chr_allow, mmc5_has_chr_dout, mmc5_prg_dout, mmc5_irq};

    0,
    2,
    3,
    7,
    28: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow}      = {map28_prg_addr, map28_prg_allow, map28_chr_addr, map28_vram_a10, map28_vram_ce, map28_chr_allow};

    13: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow}      = {map13_prg_addr, map13_prg_allow, map13_chr_addr, map13_vram_a10, map13_vram_ce, map13_chr_allow};
    15: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow}      = {map15_prg_addr, map15_prg_allow, map15_chr_addr, map15_vram_a10, map15_vram_ce, map15_chr_allow};

    34: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow}      = {map34_prg_addr, map34_prg_allow, map34_chr_addr, map34_vram_a10, map34_vram_ce, map34_chr_allow};
    41: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow}      = {map41_prg_addr, map41_prg_allow, map41_chr_addr, map41_vram_a10, map41_vram_ce, map41_chr_allow};

    64,
    158: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow, irq} = {rambo1_prg_addr, rambo1_prg_allow, rambo1_chr_addr, rambo1_vram_a10, rambo1_vram_ce, rambo1_chr_allow, rambo1_irq};

    11,
    66: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow}      = {map66_prg_addr, map66_prg_allow, map66_chr_addr, map66_vram_a10, map66_vram_ce, map66_chr_allow};
    68: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow}      = {map68_prg_addr, map68_prg_allow, map68_chr_addr, map68_vram_a10, map68_vram_ce, map68_chr_allow};
    69: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow, irq} = {map69_prg_addr, map69_prg_allow, map69_chr_addr, map69_vram_a10, map69_vram_ce, map69_chr_allow, map69_irq};

    71,
    232: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow}     = {map71_prg_addr, map71_prg_allow, map71_chr_addr, map71_vram_a10, map71_vram_ce, map71_chr_allow};

    79,
    113: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow}     = {map79_prg_addr, map79_prg_allow, map79_chr_addr, map79_vram_a10, map79_vram_ce, map79_chr_allow};

    105: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow, irq}= {nesev_prg_addr, mmc1_prg_allow, nesev_chr_addr, mmc1_vram_a10, mmc1_vram_ce, mmc1_chr_allow, nesev_irq};

    228: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow}     = {map228_prg_addr, map228_prg_allow, map228_chr_addr, map228_vram_a10, map228_vram_ce, map228_chr_allow};
    234: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow}     = {map234_prg_addr, map234_prg_allow, map234_chr_addr, map234_vram_a10, map234_vram_ce, map234_chr_allow};
    default: {prg_aout, prg_allow, chr_aout, vram_a10, vram_ce, chr_allow} = {mmc0_prg_addr, mmc0_prg_allow, mmc0_chr_addr, mmc0_vram_a10, mmc0_vram_ce, mmc0_chr_allow};
    endcase
    if (prg_aout[21:20] == 2'b00)
      prg_aout[19:0] = {prg_aout[19:14] & prg_mask, prg_aout[13:0]};
    if (chr_aout[21:20] == 2'b10)
      chr_aout[19:0] = {chr_aout[19:13] & chr_mask, chr_aout[12:0]};
    // Remap the CHR address into VRAM, if needed.
    chr_aout = vram_ce ? {11'b11_0000_0000_0, vram_a10, chr_ain[9:0]} : chr_aout;
    prg_aout = (prg_ain < 'h2000) ? {11'b11_1000_0000_0, prg_ain[10:0]} : prg_aout;
    prg_allow = prg_allow || (prg_ain < 'h2000);
  end
endmodule

// PRG       = 0....
// CHR       = 10...
// CHR-VRAM  = 1100
// CPU-RAM   = 1110
// CARTRAM   = 1111
                 