/********************************************/
/* minimig_de1_top.v                        */
/* Altera DE1 FPGA Top File                 */
/*                                          */
/* 2012, rok.krajnc@gmail.com               */
/********************************************/


`define MINIMIG_DE1
//`define SOC_SIM


module minimig_de1_top (
  // clock inputs
  input  wire [  2-1:0] CLOCK_32,     // 32 MHz
  input  wire [  2-1:0] CLOCK_27,     // 27 MHz
  input  wire [  2-1:0] CLOCK_50,     // 50 MHz
  // LED outputs
  output wire           LED,          // LED Yellow
  // UART
  output wire           UART_TX,      // UART Transmitter
  input  wire           UART_RX,      // UART Receiver
  // VGA
  output wire           VGA_HS,       // VGA H_SYNC
  output wire           VGA_VS,       // VGA V_SYNC
  output wire [  6-1:0] VGA_R,        // VGA Red[3:0]
  output wire [  6-1:0] VGA_G,        // VGA Green[3:0]
  output wire [  6-1:0] VGA_B,        // VGA Blue[3:0]
  // SDRAM
  inout  wire [ 16-1:0] SDRAM_DQ,     // SDRAM Data bus 16 Bits
  output wire [ 13-1:0] SDRAM_A,      // SDRAM Address bus 13 Bits
  output wire           SDRAM_DQML,   // SDRAM Low-byte Data Mask
  output wire           SDRAM_DQMH,   // SDRAM High-byte Data Mask
  output wire           SDRAM_nWE,    // SDRAM Write Enable
  output wire           SDRAM_nCAS,   // SDRAM Column Address Strobe
  output wire           SDRAM_nRAS,   // SDRAM Row Address Strobe
  output wire           SDRAM_nCS,    // SDRAM Chip Select
  output wire  [ 2-1:0] SDRAM_BA,     // SDRAM Bank Address
  output wire           SDRAM_CLK,    // SDRAM Clock
  output wire           SDRAM_CKE,    // SDRAM Clock Enable
  // MINIMIG specific
  output wire           AUDIO_L,      // sigma-delta DAC output left
  output wire           AUDIO_R       // sigma-delta DAC output right
);



////////////////////////////////////////
// internal signals                   //
////////////////////////////////////////

// clock
wire           pll_in_clk;
wire           clk_114;
wire           clk_28;
wire           clk_sdram;
wire           pll_locked;
wire           clk_7;
wire           clk_50;

// reset
wire           pll_rst;
wire           sdctl_rst;
wire           rst_50;
wire           rst_minimig;

// ctrl
wire           rom_status;
wire           ram_status;
wire           reg_status;

// tg68
wire           tg68_rst;
wire [ 16-1:0] tg68_dat_in;
wire [ 16-1:0] tg68_dat_out;
wire [ 32-1:0] tg68_adr;
wire [  3-1:0] tg68_IPL;
wire           tg68_dtack;
wire           tg68_as;
wire           tg68_uds;
wire           tg68_lds;
wire           tg68_rw;
wire           tg68_ena7RD;
wire           tg68_ena7WR;
wire           tg68_enaWR;
wire [ 16-1:0] tg68_cout;
wire           tg68_cpuena;
wire [  2-1:0] cpu_config;
wire [  6-1:0] memcfg;
wire [ 32-1:0] tg68_cad;
wire [  6-1:0] tg68_cpustate;
wire           tg68_cdma;
wire           tg68_clds;
wire           tg68_cuds;

// minimig
wire [ 16-1:0] ram_data;      // sram data bus
wire [ 16-1:0] ramdata_in;    // sram data bus in
wire [ 22-1:1] ram_address;   // sram address bus
wire           _ram_bhe;      // sram upper byte select
wire           _ram_ble;      // sram lower byte select
wire           _ram_we;       // sram write enable
wire           _ram_oe;       // sram output enable
wire           _15khz;        // scandoubler disable
wire           joy_emu_en;    // joystick emulation enable
wire           sdo;           // SPI data output
wire [ 15-1:0] ldata;         // left DAC data
wire [ 15-1:0] rdata;         // right DAC data
wire           audio_left;
wire           audio_right;
wire           floppy_fwr;
wire           floppy_frd;
wire           hd_fwr;
wire           hd_frd;

// sdram
wire           reset_out;
wire [  4-1:0] sdram_cs;
wire [  2-1:0] sdram_dqm;
wire [  2-1:0] sdram_ba;

// audio
wire           audio_lr_switch;
wire           audio_lr_mix;

// ctrl
wire [  4-1:0] SPI_CS_N;
wire           SPI_DI;
wire           rst_ext;
wire           boot_sel;
wire [  4-1:0] ctrl_cfg;
wire [  4-1:0] ctrl_status;

// indicators
wire [  8-1:0] track;


////////////////////////////////////////
// toplevel assignments               //
////////////////////////////////////////

// SD card
//assign SD_DAT3          = SPI_CS_N[0];

// SDRAM
assign SDRAM_CKE         = 1'b1;
assign SDRAM_CLK         = clk_sdram;
assign SDRAM_nCS         = sdram_cs[0];
assign SDRAM_DQML        = sdram_dqm[0];
assign SDRAM_DQMH        = sdram_dqm[1];
assign SDRAM_BA          = sdram_ba;

// AUDIO
//assign AUDIOLEFT        = audio_left;
//assign AUDIORIGHT       = audio_right;
assign AUDIO_L       = 1'b0;
assign AUDIO_R       = 1'b0;

// ctrl
assign SPI_DI           = !SPI_CS_N[0] ? SD_DAT : sdo;
assign rst_ext          = 1'b1; // !KEY[0];
assign boot_sel         = 1'b1; // sw_5;
assign ctrl_cfg         = 1'b1111; // {sw_4, sw_3, sw_2, sw_1};

// clock
assign pll_in_clk       = CLOCK_27[0];

// reset
assign pll_rst          = 1'b0; // !SW[0];
assign sdctl_rst        = pll_locked; // & SW[0];

// audio
assign audio_lr_switch  = 1'b1; // sw_7;
assign audio_lr_mix     = 1'b1; // sw_6;

// minimig
assign _15khz           = 1'b1; // sw_9;
assign joy_emu_en       = 1'b1; // sw_8;

// use pll
amigaclk amigaclk (
  .areset       (pll_rst          ), // async reset input
  .inclk0       (pll_in_clk       ), // input clock (27MHz)
  .c0           (clk_114          ), // output clock c0 (114.750000MHz)
  .c1           (clk_28           ), // output clock c1 (28.687500MHz)
  .c2           (clk_sdram        ), // output clock c2 (114.750000MHz, -146.25 deg)
  .locked       (pll_locked       )  // pll locked output
);


//// 7MHz clock ////
reg [2-1:0] clk7_cnt;
always @ (posedge clk_28, negedge pll_locked) begin
  if (!pll_locked)
    clk7_cnt <= #1 2'b10;
  else
    clk7_cnt <= #1 clk7_cnt + 2'b01;
end

assign clk_7 = clk7_cnt[1];


//// TG68K main CPU ////
TG68K tg68k (
  .clk          (clk_114          ),
  .reset        (tg68_rst         ),
  .clkena_in    (1'b1             ),
  .IPL          (tg68_IPL         ),
  .dtack        (tg68_dtack       ),
  .vpa          (1'b1             ),
  .ein          (1'b1             ),
  .addr         (tg68_adr         ),
  .data_read    (tg68_dat_in      ),
  .data_write   (tg68_dat_out     ),
  .as           (tg68_as          ),
  .uds          (tg68_uds         ),
  .lds          (tg68_lds         ),
  .rw           (tg68_rw          ),
  .e            (                 ),
  .vma          (                 ),
  .wrd          (                 ),
  .ena7RDreg    (tg68_ena7RD      ),
  .ena7WRreg    (tg68_ena7WR      ),
  .enaWRreg     (tg68_enaWR       ),
  .fromram      (tg68_cout        ),
  .ramready     (tg68_cpuena      ),
  .cpu          (cpu_config       ),
  .memcfg       (memcfg           ),
  .ramaddr      (tg68_cad         ),
  .cpustate     (tg68_cpustate    ),
  .nResetOut    (                 ),
  .skipFetch    (                 ),
  .cpuDMA       (tg68_cdma        ),
  .ramlds       (tg68_clds        ),
  .ramuds       (tg68_cuds        )
);


//// sdram ////
sdram sdram (
  .sdata        (SDRAM_DQ         ),
  .sdaddr       (SDRAM_A          ),
  .dqm          (sdram_dqm        ),
  .sd_cs        (sdram_cs         ),
  .ba           (sdram_ba         ),
  .sd_we        (SDRAM_nWE        ),
  .sd_ras       (SDRAM_nRAS       ),
  .sd_cas       (SDRAM_nCAS       ),
  .sysclk       (clk_114          ),
  .reset_in     (sdctl_rst        ),
  .hostWR       (16'h0            ),
  .hostAddr     (24'h0            ),
  .hostState    ({1'b0, 2'b01}    ),
  .hostL        (1'b1             ),
  .hostU        (1'b1             ),
  .cpuWR        (tg68_dat_out     ),
  .cpuAddr      (tg68_cad[24:1]   ),
  .cpuU         (tg68_cuds        ),
  .cpuL         (tg68_clds        ),
  .cpustate     (tg68_cpustate    ),
  .cpu_dma      (tg68_cdma        ),
  .chipWR       (ram_data         ),
  .chipAddr     ({2'b00, ram_address[21:1]}),
  .chipU        (_ram_bhe         ),
  .chipL        (_ram_ble         ),
  .chipRW       (_ram_we          ),
  .chip_dma     (_ram_oe          ),
  .c_7m         (clk_7            ),
  .hostRD       (                 ),
  .hostena      (                 ),
  .cpuRD        (tg68_cout        ),
  .cpuena       (tg68_cpuena      ),
  .chipRD       (ramdata_in       ),
  .reset_out    (reset_out        ),
  .enaRDreg     (                 ),
  .enaWRreg     (tg68_enaWR       ),
  .ena7RDreg    (tg68_ena7RD      ),
  .ena7WRreg    (tg68_ena7WR      )
);


//// audio ////
audio_top audio_top (
  .clk          (clk_28           ),  // 28MHz input clock
  .rst_n        (reset_out        ),  // active low reset (from sdram controller)
  // config
  .exchan       (audio_lr_switch  ),  // switch audio left / right channel
  .mix          (audio_lr_mix     ),  // normal / centered mix (play some left channel on the right channel and vise-versa)
  // audio shifter
  .rdata        (rdata            ),  // right channel sample data
  .ldata        (ldata            ),  // left channel sample data
  .aud_bclk     (AUD_BCLK         ),  // CODEC data clock
  .aud_daclrck  (AUD_DACLRCK      ),  // CODEC data clock
  .aud_dacdat   (AUD_DACDAT       ),  // CODEC data
  .aud_xck      (AUD_XCK          ),  // CODEC data clock
  // I2C audio config
  .i2c_sclk     (I2C_SCLK         ),  // CODEC config clock
  .i2c_sdat     (I2C_SDAT         )   // CODEC config data
);


//// minimig top ////
Minimig1 minimig (
  //m68k pins
  .cpu_address  (tg68_adr[23:1]   ),  // M68K address bus
  .cpu_data     (tg68_dat_in      ),  // M68K data bus
  .cpudata_in   (tg68_dat_out     ),  // M68K data in
  ._cpu_ipl     (tg68_IPL         ),  // M68K interrupt request
  ._cpu_as      (tg68_as          ),  // M68K address strobe
  ._cpu_uds     (tg68_uds         ),  // M68K upper data strobe
  ._cpu_lds     (tg68_lds         ),  // M68K lower data strobe
  .cpu_r_w      (tg68_rw          ),  // M68K read / write
  ._cpu_dtack   (tg68_dtack       ),  // M68K data acknowledge
  ._cpu_reset   (tg68_rst         ),  // M68K reset
  .cpu_clk      (clk_7            ),  // M68K clock
  //sram pins
  .ram_data     (ram_data         ),  // SRAM data bus
  .ramdata_in   (ramdata_in       ),  // SRAM data bus in
  .ram_address  (ram_address[21:1]),  // SRAM address bus
  ._ram_ce      (                 ),  // SRAM chip enable
  ._ram_bhe     (_ram_bhe         ),  // SRAM upper byte select
  ._ram_ble     (_ram_ble         ),  // SRAM lower byte select
  ._ram_we      (_ram_we          ),  // SRAM write enable
  ._ram_oe      (_ram_oe          ),  // SRAM output enable
  //system  pins
  .clk          (clk_7            ),  // system clock (7.09379 MHz)
  .clk28m       (clk_28           ),  // 28.37516 MHz clock
  //rs232 pins
  .rxd          (1'b0             ),  // RS232 receive
  .txd          (                 ),  // RS232 send
  .cts          (1'b0             ),  // RS232 clear to send
  .rts          (                 ),  // RS232 request to send
  //I/O
  ._joy1        (Joya             ),  // joystick 1 [fire2,fire,up,down,left,right] (default mouse port)
  ._joy2        (Joyb             ),  // joystick 2 [fire2,fire,up,down,left,right] (default joystick port)
  .mouse_btn1   (key_3            ),  // mouse button 1
  .mouse_btn2   (key_2            ),  // mouse button 2
  .joy_emu_en   (joy_emu_en       ),  // enable keyboard joystick emulation
  ._15khz       (_15khz           ),  // scandoubler disable
  .pwrled       (                 ),  // power led
  .msdat        (PS2_MDAT         ),  // PS2 mouse data
  .msclk        (PS2_MCLK         ),  // PS2 mouse clk
  .kbddat       (PS2_DAT          ),  // PS2 keyboard data
  .kbdclk       (PS2_CLK          ),  // PS2 keyboard clk
  //host controller interface (SPI)
  ._scs         (SPI_CS_N[3:1]    ),  // SPI chip select
  .direct_sdi   (SD_DAT           ),  // SD Card direct in
  .sdi          (SD_CMD           ),  // SPI data input
  .sdo          (sdo              ),  // SPI data output
  .sck          (SD_CLK           ),  // SPI clock
  //video
  ._hsync       (VGA_HS           ),  // horizontal sync
  ._vsync       (VGA_VS           ),  // vertical sync
  .red          (VGA_R            ),  // red
  .green        (VGA_G            ),  // green
  .blue         (VGA_B            ),  // blue
  //audio
  .left         (audio_left       ),  // audio bitstream left
  .right        (audio_right      ),  // audio bitstream right
  .ldata        (ldata            ),  // left DAC data
  .rdata        (rdata            ),  // right DAC data
  //user i/o
  .gpio         (                 ),  // spare GPIO
  .cpu_config   (cpu_config       ),  // CPU config
  .memcfg       (memcfg           ),  // memory config
  .drv_snd      (                 ),  // drive sound
  .init_b       (                 ),  // vertical sync for MCU (sync OSD update)
  // fifo / track display
  .trackdisp    (track            ),  // floppy track number
  .secdisp      (                 ),  // sector
  .floppy_fwr   (floppy_fwr       ),  // floppy fifo writing
  .floppy_frd   (floppy_frd       ),  // floppy fifo reading
  .hd_fwr       (hd_fwr           ),  // hd fifo writing
  .hd_frd       (hd_frd           )   // hd fifo  ading
);


endmodule

