//
// gb_mist.v
//
// Gameboy for the MIST board https://github.com/mist-devel
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//

module gb_mist (
   input [1:0] CLOCK_27,
	
 	output LED,
	
   // SPI interface to arm io controller
   output        SPI_DO,
   input         SPI_DI,
   input         SPI_SCK,
   input         SPI_SS2,
   input         SPI_SS3,
   input         SPI_SS4,
   input         CONF_DATA0, 
	
   // SDRAM interface
   inout [15:0]    SDRAM_DQ,       // SDRAM Data bus 16 Bits
   output [12:0]   SDRAM_A,        // SDRAM Address bus 13 Bits
   output          SDRAM_DQML,     // SDRAM Low-byte Data Mask
   output          SDRAM_DQMH,     // SDRAM High-byte Data Mask
   output          SDRAM_nWE,      // SDRAM Write Enable
   output          SDRAM_nCAS,     // SDRAM Column Address Strobe
   output          SDRAM_nRAS,     // SDRAM Row Address Strobe
   output          SDRAM_nCS,      // SDRAM Chip Select
   output [1:0]    SDRAM_BA,       // SDRAM Bank Address
   output          SDRAM_CLK,      // SDRAM Clock
   output          SDRAM_CKE,      // SDRAM Clock Enable

	// audio
   output 			AUDIO_L,
   output 			AUDIO_R,

	// video
   output 			VGA_HS,
   output 			VGA_VS,
   output [5:0] 	VGA_R,
   output [5:0] 	VGA_G,
   output [5:0] 	VGA_B
);

assign LED = ~dio_download;

// mix both joysticks to allow the user to use any
wire [7:0] joystick = joystick_0 | joystick_1;
wire [7:0] joystick_0;
wire [7:0] joystick_1;

// the configuration string is returned to the io controller to allow
// it to control the menu on the OSD 
parameter CONF_STR = {
        "GAMEBOY;;",
        "F,GBCGB ,Load;",
        "O4,Mode,Auto,Color;",
        "O1,LCD color,white,yellow;",
        "O2,Boot,Normal,Fast;",
        "T3,Reset"
};

parameter CONF_STR_LEN = 9+14+19+26+20+8;

// the status register is controlled by the on screen display (OSD)
wire [7:0] status;
wire [1:0] buttons;
wire       isGBC = (dio_index[7:6] == 0) || status[4];

// include user_io module for arm controller communication
user_io #(.STRLEN(CONF_STR_LEN)) user_io ( 
      .conf_str   ( CONF_STR   ),
      .clk_sys    ( clk64      ),
      .SPI_CLK    ( SPI_SCK    ),
      .SPI_SS_IO  ( CONF_DATA0 ),
      .SPI_MISO   ( SPI_DO     ),
      .SPI_MOSI   ( SPI_DI     ),

      .status     ( status     ),
      .buttons    ( buttons    ),

      .joystick_0 ( joystick_0 ),
      .joystick_1 ( joystick_1 )
);

wire reset = (reset_cnt != 0);
reg [9:0] reset_cnt;
always @(posedge clk64) begin
	if(status[0] || status[3] || buttons[1] || !pll_locked || dio_download)
		reset_cnt <= 10'd1023;
	else
		if(reset_cnt != 0)
			reset_cnt <= reset_cnt - 10'd1;
end

assign SDRAM_CKE = 1'b1;

sdram sdram (
   // interface to the MT48LC16M16 chip
   .sd_data        ( SDRAM_DQ                  ),
   .sd_addr        ( SDRAM_A                   ),
   .sd_dqm         ( {SDRAM_DQMH, SDRAM_DQML}  ),
   .sd_cs          ( SDRAM_nCS                 ),
   .sd_ba          ( SDRAM_BA                  ),
   .sd_we          ( SDRAM_nWE                 ),
   .sd_ras         ( SDRAM_nRAS                ),
   .sd_cas         ( SDRAM_nCAS                ),

    // system interface
   .clk            ( clk64                     ),
   .sync           ( clk8                      ),
   .init           ( !pll_locked               ),

   // cpu interface
   .din            ( sdram_di                  ),
   .addr           ( sdram_addr                ),
   .ds             ( sdram_ds                  ),
   .we             ( sdram_we                  ),
   .oe             ( sdram_oe                  ),
   .dout           ( sdram_do                  )
);

// TODO: ds for cart ram write
wire [1:0] sdram_ds = dio_download?2'b11:{!cart_addr[0], cart_addr[0]};
wire [15:0] sdram_do;
wire [15:0] sdram_di = dio_download?dio_data:{cart_di, cart_di};
wire [23:0] sdram_addr = dio_download?dio_addr:{1'b0, mbc_bank, cart_addr[12:1]};
wire sdram_oe = !dio_download && cart_rd;
wire sdram_we = (dio_download && dio_write) || (!dio_download && cart_ram_wr);

wire dio_download;
wire [23:0] dio_addr;
wire [15:0] dio_data;
wire dio_write;
wire [7:0] dio_index;

// TODO: RAM bank
// http://fms.komkon.org/GameBoy/Tech/Carts.html

// 32MB SDRAM memory map using word addresses
// 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0 D
// 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 S
// -------------------------------------------------
// 0 0 X X X X X X X X X X X X X X X X X X X X X X X up to 8MB used as ROM
// 0 1 X X X X X X X X X X X X X X X X X X X X X X X up to 8MB used as RAM
// 0 0 0 0 R R B B B B B C C C C C C C C C C C C C C MBC1 ROM (R=RAM bank in mode 0)
// 0 1 0 0 0 0 0 0 0 0 R R C C C C C C C C C C C C C MBC1 RAM (R=RAM bank in mode 1)
// 0 0 0 0 B B B B B B B C C C C C C C C C C C C C C MBC2 ROM
// 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 C C C C C C C C C MBC2 RAM
// 0 0 0 0 B B B B B B B C C C C C C C C C C C C C C MBC3 ROM
// 0 1 0 0 0 0 0 0 0 R R C C C C C C C C C C C C C C MBC3 RAM
// 0 0 B B B B B B B B B C C C C C C C C C C C C C C MBC5 ROM
// 0 1 0 0 0 0 0 0 R R R R C C C C C C C C C C C C C MBC5 RAM

// ---------------------------------------------------------------

wire [10:0] mbc1_addr =
	(cart_addr[15:14] == 2'b00)?{10'd0, cart_addr[13]}:                 // 16k ROM Bank 0
	(cart_addr[15:14] == 2'b01)?{3'b000, mbc1_rom_bank, cart_addr[13]}: // 16k ROM Bank 1-127
	(cart_addr[15:13] == 3'b101)?{9'b100000000, mbc1_ram_bank}:         // 8k RAM Bank 0-3
	11'd0;

wire [10:0] mbc2_addr =
	(cart_addr[15:14] == 2'b00)?{10'd0, cart_addr[13]}:                 // 16k ROM Bank 0
	(cart_addr[15:14] == 2'b01)?{6'd0, mbc2_rom_bank, cart_addr[13]}:   // 16k ROM Bank 1-15
	(cart_addr[15:9] == 7'b1010000)?(11'b10000000000):                  // 512x4 bit RAM
	11'd0;

wire [10:0] mbc3_addr =
	(cart_addr[15:14] == 2'b00)?{10'd0, cart_addr[13]}:                 // 16k ROM Bank 0
	(cart_addr[15:14] == 2'b01)?{3'b000, mbc3_rom_bank, cart_addr[13]}: // 16k ROM Bank 1-127
	(cart_addr[15:13] == 3'b101)?{9'b100000000, mbc3_ram_bank}:         // 8k RAM Bank 0-3
	11'd0;

wire [10:0] mbc5_addr =
	(cart_addr[15:14] == 2'b00)?{10'd0, cart_addr[13]}:                 // 16k ROM Bank 0
	(cart_addr[15:14] == 2'b01)?{1'b0, mbc5_rom_bank, cart_addr[13]}:   // 16k ROM Bank 0-480 (0h-1E0h)
	(cart_addr[15:13] == 3'b101)?{7'b1000000, mbc5_ram_bank}:           // 8k RAM Bank 0-15
    11'd0;

// -------------------------- RAM banking ------------------------

// in mode 0 (16/8 mode) the ram is not banked 
// in mode 1 (4/32 mode) four ram banks are used
wire [1:0] mbc1_ram_bank = (mbc1_mode?mbc_ram_bank_reg[1:0]:2'b00) & ram_mask[1:0];
wire [1:0] mbc3_ram_bank = mbc_ram_bank_reg[1:0] & ram_mask[1:0];
wire [3:0] mbc5_ram_bank = mbc_ram_bank_reg & ram_mask;

// -------------------------- ROM banking ------------------------

// in mode 0 (16/8 mode) the ram bank select signals are the upper rom address lines 
// in mode 1 (4/32 mode) the upper two rom address lines are 2'b00
wire [6:0] mbc1_rom_bank_mode = { mbc1_mode?2'b00:mbc_ram_bank_reg[1:0], mbc_rom_bank_reg[4:0]};
// mask address lines to enable proper mirroring
wire [6:0] mbc1_rom_bank = mbc1_rom_bank_mode & rom_mask[6:0];
wire [3:0] mbc2_rom_bank = mbc_rom_bank_reg[3:0] & rom_mask[3:0];  //16
wire [6:0] mbc3_rom_bank = mbc_rom_bank_reg[6:0] & rom_mask[6:0];  //128
wire [8:0] mbc5_rom_bank = mbc_rom_bank_reg & rom_mask;  //480

// --------------------- CPU register interface ------------------
reg mbc_ram_enable;
reg mbc1_mode;
reg mbc3_mode;
reg [8:0] mbc_rom_bank_reg;
reg [3:0] mbc_ram_bank_reg;

always @(posedge clk64) begin
	if(reset) begin
		mbc_rom_bank_reg <= 5'd1;
		mbc_ram_bank_reg <= 2'd0;
		mbc_ram_enable <= 1'b0;
		mbc1_mode <= 1'b0;
	end else begin
		//write to ROM bank register
		if(cart_wr && (cart_addr[15:13] == 3'b001)) begin
			if(~mbc5 && cart_di[6:0]==0) //special case mbc1-3 rombank 0=1
				mbc_rom_bank_reg <= 5'd1;
			else if (mbc5) begin
				if (cart_addr[13:12] == 2'b11) //3000-3FFF High bit
					mbc_rom_bank_reg[8] <= cart_di[0];
				else //2000-2FFF low 8 bits
					mbc_rom_bank_reg[7:0] <= cart_di[7:0];
			end else
				mbc_rom_bank_reg <= {2'b00,cart_di[6:0]}; //mbc1-3
		end

		//write to RAM bank register
		if(cart_wr && (cart_addr[15:13] == 3'b010)) begin
			if (mbc3) begin
				if (cart_di[3]==1)
					mbc3_mode <= 1'b1; //enable RTC
				else begin
					mbc3_mode <= 1'b0; //enable RAM
					mbc_ram_bank_reg <= {2'b00,cart_di[1:0]};
				end
			end else
				if (mbc5)//can probably be simplified
					mbc_ram_bank_reg <= cart_di[3:0];
				else
					mbc_ram_bank_reg <= {2'b00,cart_di[1:0]};
		end	

		if(cart_wr && (cart_addr[15:13] == 3'b000))
			mbc_ram_enable <= (cart_di[3:0] == 4'ha);

		if(cart_wr && (cart_addr[15:13] == 3'b011))
			mbc1_mode <= cart_di[0];
	end
end

// extract header fields extracted from cartridge
// during download
reg [7:0] cart_mbc_type;
reg [7:0] cart_rom_size;
reg [7:0] cart_ram_size;
reg [7:0] cart_cgb_flag;
wire      isGBC_game = (cart_cgb_flag == 8'h80 || cart_cgb_flag == 8'hC0);

// only write sdram if the write attept comes from the cart ram area
wire cart_ram_wr = cart_wr && mbc_ram_enable && ((cart_addr[15:13] == 3'b101 && ~mbc2) || (cart_addr[15:9] == 7'b1010000 && mbc2));

// RAM size
wire [3:0] ram_mask =                   // 0 - no ram
	(cart_ram_size == 1)?4'b0000:       // 1 - 2k, 1 bank
	(cart_ram_size == 2)?4'b0000:       // 2 - 8k, 1 bank
	(cart_ram_size == 3)?4'b0011:       // 3 - 32k, 4 banks
	4'b1111;                            // 4 - 128k 16 banks

// ROM size
wire [8:0] rom_mask =                            // 0 - 2 banks, 32k direct mapped
			(cart_rom_size == 1)? 9'b000000011:  // 1 - 4 banks = 64k
			(cart_rom_size == 2)? 9'b000000111:  // 2 - 8 banks = 128k
			(cart_rom_size == 3)? 9'b000001111:  // 3 - 16 banks = 256k
			(cart_rom_size == 4)? 9'b000011111:  // 4 - 32 banks = 512k
			(cart_rom_size == 5)? 9'b000111111:  // 5 - 64 banks = 1M
			(cart_rom_size == 6)? 9'b001111111:  // 6 - 128 banks = 2M
			(cart_rom_size == 7)? 9'b011111111:  // 7 - 256 banks = 4M
			(cart_rom_size == 8)? 9'b111111111:  // 8 - 512 banks = 8M
			(cart_rom_size == 82)?9'b001111111:  //$52 - 72 banks = 1.1M
			(cart_rom_size == 83)?9'b001111111:  //$53 - 80 banks = 1.2M
			(cart_rom_size == 84)?9'b001111111:
                                  9'b001111111;  //$54 - 96 banks = 1.5M// RAM size

// MBC types
// 0 - none
// 1 - mbc1
// 2 - mbc1 + ram
// 3 - mbc1 + ram + bat

// MBC1, MBC1+RAM, MBC1+RAM+BAT
wire mbc1 = (cart_mbc_type == 1) || (cart_mbc_type == 2) || (cart_mbc_type == 3);
wire mbc2 = (cart_mbc_type == 5) || (cart_mbc_type == 6);
//wire mmm01 = (cart_mbc_type == 11) || (cart_mbc_type == 12) || (cart_mbc_type == 13) || (cart_mbc_type == 14);
wire mbc3 = (cart_mbc_type == 15) || (cart_mbc_type == 16) || (cart_mbc_type == 17) || (cart_mbc_type == 18) || (cart_mbc_type == 19);
//wire mbc4 = (cart_mbc_type == 21) || (cart_mbc_type == 22) || (cart_mbc_type == 23);
wire mbc5 = (cart_mbc_type == 25) || (cart_mbc_type == 26) || (cart_mbc_type == 27) || (cart_mbc_type == 28) || (cart_mbc_type == 29) || (cart_mbc_type == 30);

wire [10:0] mbc_bank =
	mbc1?mbc1_addr:                  // MBC1, 16k bank 0, 16k bank 1-127 + ram
	mbc2?mbc2_addr:                  // MBC2, 16k bank 0, 16k bank 1-15 + ram
	mbc3?mbc3_addr:
	mbc5?mbc5_addr:
	{9'd0, cart_addr[14:13]};  // no MBC, 32k linear address

always @(posedge clk64) begin
	if(!pll_locked) begin
		cart_mbc_type <= 8'h00;
		cart_rom_size <= 8'h00;
		cart_ram_size <= 8'h00;
		cart_cgb_flag <= 8'h00;
	end else begin
		if(dio_download && dio_write) begin
			// cart is stored in 16 bit wide sdram, so addresses are shifted right
			case(dio_addr)
				24'h142: cart_cgb_flag <= dio_data[15:8];
				24'ha3:  cart_mbc_type <= dio_data[7:0];                 // $147
				24'ha4: { cart_rom_size, cart_ram_size } <= dio_data;    // $148/$149
			endcase
		end
	end
end

// include ROM download helper
data_io data_io (
   .clk_sys ( clk64     ),
   // io controller spi interface
   .SPI_SCK ( SPI_SCK ),
   .SPI_SS2 ( SPI_SS2 ),
   .SPI_DI  ( SPI_DI  ),

   .ioctl_download ( dio_download ),  // signal indicating an active rom download

   // external ram interface
   .ioctl_clkref ( clk8      ),
   .ioctl_index  ( dio_index ),
   .ioctl_wr     ( dio_write ),
   .ioctl_addr   ( dio_addr  ),
   .ioctl_dout   ( dio_data  )
);

// select appropriate byte from 16 bit word returned by cart
wire [7:0] cart_di;    // data from cpu to cart
wire [7:0] cart_do = cart_addr[0]?sdram_do[7:0]:sdram_do[15:8];
wire [15:0] cart_addr;
wire cart_rd;
wire cart_wr;

wire lcd_clkena;
wire [14:0] lcd_data;
wire [1:0] lcd_mode;
wire lcd_on;

wire [15:0] audio_left;
wire [15:0] audio_right;

wire [11:0] bios_addr;
wire  [7:0] bios_do;

gbc_bios gbc_bios (
	.clock		( clk64        ),
	.address	( bios_addr	   ),
	.q			( bios_do      )
);

// the gameboy itself
gb gb (
	.reset	    ( reset        ),
	.clk        ( clk4         ),   // the whole gameboy runs on 4mhnz
	.clk2x      ( clk8         ),

	.fast_boot   ( status[2]   ),
	.joystick    ( joystick    ),
	.isGBC       ( isGBC       ),
	.isGBC_game  ( isGBC_game  ),

	// interface to the "external" game cartridge
	.cart_addr   ( cart_addr   ),
	.cart_rd     ( cart_rd     ),
	.cart_wr     ( cart_wr     ),
	.cart_do     ( cart_do     ),
	.cart_di     ( cart_di     ),

	//gbc bios interface
	.gbc_bios_addr ( bios_addr  ),
	.gbc_bios_do   ( bios_do    ),

	// audio
	.audio_l 	( audio_left	),
	.audio_r 	( audio_right	),

	// interface to the lcd
	.lcd_clkena   ( lcd_clkena ),
	.lcd_data     ( lcd_data   ),
	.lcd_mode     ( lcd_mode   ),
	.lcd_on       ( lcd_on     )
);

sigma_delta_dac dac (
	.clk		( clk64 			),
	.ldatasum	( {~audio_left[15], audio_left[14:1]} ),
	.rdatasum	( {~audio_right[15], audio_right[14:1]}	),
	.left		( AUDIO_L			),
	.right		( AUDIO_R			)
);

// the lcd to vga converter
wire [5:0] video_r, video_g, video_b;
wire video_hs, video_vs;

lcd lcd (
	 .clk    ( clk64      ),
	 .pclk_en( ce_pix     ),
	 .clk4_en( clk4       ),

	 .tint   ( status[1]  ),
	 .isGBC  ( isGBC      ),

	 // serial interface
	 .clkena ( lcd_clkena ),
	 .data   ( lcd_data   ),
	 .mode   ( lcd_mode   ),  // used to detect begin of new lines and frames
	 .on     ( lcd_on     ),
	 
  	 .hs    ( video_hs    ),
	 .vs    ( video_vs    ),
	 .r     ( video_r     ),
	 .g     ( video_g     ),
	 .b     ( video_b     )
);

// include the on screen display
osd #(10'd16,10'd0,4) osd (
   .clk_sys    ( clk64       ),

   // spi for OSD
   .SPI_DI     ( SPI_DI       ),
   .SPI_SCK    ( SPI_SCK      ),
   .SPI_SS3    ( SPI_SS3      ),

   .R_in       ( video_r      ),
   .G_in       ( video_g      ),
   .B_in       ( video_b      ),
   .HSync      ( video_hs     ),
   .VSync      ( video_vs     ),

   .R_out      ( VGA_R        ),
   .G_out      ( VGA_G        ),
   .B_out      ( VGA_B        )
);

assign VGA_HS = video_hs;
assign VGA_VS = video_vs;

wire clk4 = ce_cpu;
wire clk8 = ce_pix;

reg ce_pix, ce_cpu;
always @(posedge clk64) begin
	reg [3:0] div = 0;
	div <= div + 1'd1;
	ce_pix   <= !div[2:0];
	ce_cpu   <= !div[3:0];
end

wire pll_locked;
wire clk64;
pll pll (
	 .inclk0(CLOCK_27[0]),
	 .c0(clk64),        // 4*16.777216 MHz
	 .locked(pll_locked)
);

assign SDRAM_CLK = clk64;

endmodule
