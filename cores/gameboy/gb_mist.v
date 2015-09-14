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

assign LED = 1'b0;   // light led

// mix both joysticks to allow the user to use any
wire [7:0] joystick = joystick_0 | joystick_1;
wire [7:0] joystick_0;
wire [7:0] joystick_1;

// the configuration string is returned to the io controller to allow
// it to control the menu on the OSD 
parameter CONF_STR = {
        "GAMEBOY;GB;",
        "O1,LCD color,white,yellow;",
        "O2,Boot,Normal,Fast;",
        "T3,Reset"
};

parameter CONF_STR_LEN = 11+26+20+8;  

// the status register is controlled by the on screen display (OSD)
wire [7:0] status;
wire [1:0] buttons;

// include user_io module for arm controller communication
user_io #(.STRLEN(CONF_STR_LEN)) user_io ( 
      .conf_str   ( CONF_STR   ),

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
always @(posedge clk4) begin
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
   .clk            ( clk32                     ),
   .clkref         ( clk4                      ),
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
wire [23:0] sdram_addr = dio_download?dio_addr:{3'b000, mbc_bank, cart_addr[12:1]};
wire sdram_oe = !dio_download && cart_rd;
wire sdram_we = (dio_download && dio_write) || (!dio_download && cart_ram_wr);

wire dio_download;
wire [23:0] dio_addr;
wire [15:0] dio_data;
wire dio_write;

// TODO: RAM bank
// http://fms.komkon.org/GameBoy/Tech/Carts.html

// 32MB SDRAM memory map using word addresses
// 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0 D
// 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 S
// -------------------------------------------------
// 0 0 0 0 X X X X X X X X X X X X X X X X X X X X X up to 2MB used as ROM
// 0 0 0 1 X X X X X X X X X X X X X X X X X X X X X up to 2MB used as RAM
// 0 0 0 0 R R B B B B B C C C C C C C C C C C C C C MBC1 ROM (R=RAM bank in mode 0)
// 0 0 0 1 0 0 0 0 0 0 R R C C C C C C C C C C C C C MBC1 RAM (R=RAM bank in mode 1)

// ---------------------------------------------------------------
// ----------------------------- MBC1 ----------------------------
// ---------------------------------------------------------------

wire [8:0] mbc1_addr = 
	(cart_addr[15:14] == 2'b00)?{8'b000000000, cart_addr[13]}:        // 16k ROM Bank 0
	(cart_addr[15:14] == 2'b01)?{1'b0, mbc1_rom_bank, cart_addr[13]}: // 16k ROM Bank 1-127
	(cart_addr[15:13] == 3'b101)?{7'b1000000, mbc1_ram_bank}:         // 8k RAM Bank 0-3
	9'd0;

// -------------------------- RAM banking ------------------------

// in mode 0 (16/8 mode) the ram is not banked 
// in mode 1 (4/32 mode) four ram banks are used
wire [1:0] mbc1_ram_bank = (mbc1_mode?mbc1_ram_bank_reg:2'b00) & ram_mask;

// -------------------------- ROM banking ------------------------
   
// in mode 0 (16/8 mode) the ram bank select signals are the upper rom address lines 
// in mode 1 (4/32 mode) the upper two rom address lines are 2'b00
wire [6:0] mbc1_rom_bank_mode = { mbc1_mode?2'b00:mbc1_ram_bank_reg, mbc1_rom_bank_reg};
// mask address lines to enable proper mirroring
wire [6:0] mbc1_rom_bank = mbc1_rom_bank_mode & rom_mask;

// --------------------- CPU register interface ------------------
reg mbc1_ram_enable;
reg mbc1_mode;
reg [4:0] mbc1_rom_bank_reg;
reg [1:0] mbc1_ram_bank_reg;
always @(posedge clk4) begin
	if(reset) begin
		mbc1_rom_bank_reg <= 5'd1;
		mbc1_ram_bank_reg <= 2'd0;
      mbc1_ram_enable <= 1'b0;
      mbc1_mode <= 1'b0;
	end else begin
		if(cart_wr && (cart_addr[15:13] == 3'b000))
			mbc1_ram_enable <= (cart_di[3:0] == 4'ha);
		if(cart_wr && (cart_addr[15:13] == 3'b001)) begin
			if(cart_di[4:0]==0) mbc1_rom_bank_reg <= 5'd1;
			else   				  mbc1_rom_bank_reg <= cart_di[4:0];
		end	
		if(cart_wr && (cart_addr[15:13] == 3'b010))
			mbc1_ram_bank_reg <= cart_di[1:0];
		if(cart_wr && (cart_addr[15:13] == 3'b011))
			mbc1_mode <= cart_di[0];
	end
end

// extract header fields extracted from cartridge
// during download
reg [7:0] cart_mbc_type;
reg [7:0] cart_rom_size;
reg [7:0] cart_ram_size;

// only write sdram if the write attept comes from the cart ram area
wire cart_ram_wr = cart_wr && mbc1_ram_enable && (cart_addr[15:13] == 3'b101);
   
// RAM size
wire [1:0] ram_mask =              			// 0 - no ram
	   (cart_ram_size == 1)?2'b00:  			// 1 - 2k, 1 bank
	   (cart_ram_size == 2)?2'b00:  			// 2 - 8k, 1 bank
	   2'b11;                       			// 3 - 32k, 4 banks

// ROM size
wire [6:0] rom_mask =                   	// 0 - 2 banks, 32k direct mapped
	   (cart_rom_size == 1)?7'b0000011:  	// 1 - 4 banks = 64k
	   (cart_rom_size == 2)?7'b0000111:  	// 2 - 8 banks = 128k
	   (cart_rom_size == 3)?7'b0001111:  	// 3 - 16 banks = 256k
	   (cart_rom_size == 4)?7'b0011111:  	// 4 - 32 banks = 512k
	   (cart_rom_size == 5)?7'b0111111:  	// 5 - 64 banks = 1M
	   7'b1111111;                       	// 6 - 128 banks = 2M

// MBC types
// 0 - none
// 1 - mbc1
// 2 - mbc1 + ram
// 3 - mbc1 + ram + bat

// MBC1, MBC1+RAM, MBC1+RAM+BAT
wire mbc1 = (cart_mbc_type == 1) || (cart_mbc_type == 2) || (cart_mbc_type == 3);

wire [8:0] mbc_bank =
	mbc1?mbc1_addr:                  // MBC1, 16k bank 0, 16k bank 1-127 + ram
	{7'b0000000, cart_addr[14:13]};  // no MBC, 32k linear address

always @(posedge clk4) begin
	if(!pll_locked) begin
		cart_mbc_type <= 8'h00;
		cart_rom_size <= 8'h00;
		cart_ram_size <= 8'h00;
	end else begin
		if(dio_download && dio_write) begin
			// cart is stored in 16 bit wide sdram, so addresses are shifted right
			case(dio_addr)
				24'ha3:  cart_mbc_type <= dio_data[7:0];                 // $147
				24'ha4: { cart_rom_size, cart_ram_size } <= dio_data;    // $148/$149
			endcase
		end
	end
end

// include ROM download helper
data_io data_io (
   // io controller spi interface
   .sck ( SPI_SCK ),
   .ss  ( SPI_SS2 ),
   .sdi ( SPI_DI  ),

   .downloading ( dio_download ),  // signal indicating an active rom download
                 
   // external ram interface
   .clk   ( clk4      ),
   .wr    ( dio_write ),
   .addr  ( dio_addr  ),
   .data  ( dio_data  )
);

// select appropriate byte from 16 bit word returned by cart
wire [7:0] cart_di;    // data from cpu to cart
wire [7:0] cart_do = cart_addr[0]?sdram_do[7:0]:sdram_do[15:8];
wire [15:0] cart_addr;
wire cart_rd;
wire cart_wr;

wire lcd_clkena;
wire [1:0] lcd_data;
wire [1:0] lcd_mode;
wire lcd_on;

wire [15:0] audio_left;
wire [15:0] audio_right;

// the gameboy itself
gb gb (
	.reset	    ( reset        ),
	.clk         ( clk4         ),   // the whole gameboy runs on 4mhnz

	.fast_boot   ( status[2]    ),
	.joystick    ( joystick     ),

	// interface to the "external" game cartridge
	.cart_addr   ( cart_addr   ),
	.cart_rd     ( cart_rd     ),
	.cart_wr     ( cart_wr     ),
	.cart_do     ( cart_do     ),
	.cart_di     ( cart_di     ),

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
	.clk			( clk32 					),
	.ldatasum	( audio_left[15:1]	),
	.rdatasum	( audio_right[15:1]	),
	.left			( AUDIO_L				),
	.right		( AUDIO_R				)
);

// the lcd to vga converter
wire [5:0] video_r, video_g, video_b;
wire video_hs, video_vs;

lcd lcd (
	 .pclk   ( clk8       ),
	 .clk    ( clk4       ),

	 .tint   ( status[1]  ),

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
osd #(16,0,4) osd (
   .pclk       ( clk32       ),

   // spi for OSD
   .sdi        ( SPI_DI       ),
   .sck        ( SPI_SCK      ),
   .ss         ( SPI_SS3      ),

   .red_in     ( video_r      ),
   .green_in   ( video_g      ),
   .blue_in    ( video_b      ),
   .hs_in      ( video_hs     ),
   .vs_in      ( video_vs     ),

   .red_out    ( VGA_R        ),
   .green_out  ( VGA_G        ),
   .blue_out   ( VGA_B        ),
   .hs_out     ( VGA_HS       ),
   .vs_out     ( VGA_VS       )
);
				
reg clk4;   // 4.194304 MHz CPU clock and GB pixel clock
always @(posedge clk8) 
	clk4 <= !clk4;

reg clk8;   // 8.388608 MHz VGA pixel clock
always @(posedge clk16) 
	clk8 <= !clk8;

reg clk16;   // 16.777216 MHz
always @(posedge clk32) 
	clk16 <= !clk16;
				
// 32 Mhz SDRAM clk
wire pll_locked;
wire clk32;
pll pll (
	 .inclk0(CLOCK_27[0]),
	 .c0(clk32),        // 2*16.777216 MHz
	 .c1(SDRAM_CLK),    // same phase shifted
	 .locked(pll_locked)
);

endmodule
