/********************************************/
/* minimig_de1_top.v                        */
/* Altera DE1 FPGA Top File                 */
/*                                          */
/* 2012, rok.krajnc@gmail.com               */
/********************************************/


`define MINIMIG_DE1
//`define SOC_SIM

module minimig_mist_top (
  // clock inputs
  input wire [ 2-1:0] 	CLOCK_32, // 32 MHz
  input wire [ 2-1:0] 	CLOCK_27, // 27 MHz
  input wire [ 2-1:0] 	CLOCK_50, // 50 MHz
  // LED outputs
  output wire 		LED, // LED Yellow
  // UART
  output wire 		UART_TX, // UART Transmitter
  input wire 		UART_RX, // UART Receiver
  // VGA
  output wire 		VGA_HS, // VGA H_SYNC
  output wire 		VGA_VS, // VGA V_SYNC
  output wire [ 6-1:0] 	VGA_R, // VGA Red[5:0]
  output wire [ 6-1:0] 	VGA_G, // VGA Green[5:0]
  output wire [ 6-1:0] 	VGA_B, // VGA Blue[5:0]
  // SDRAM
  inout wire [ 16-1:0] 	SDRAM_DQ, // SDRAM Data bus 16 Bits
  output wire [ 13-1:0] SDRAM_A, // SDRAM Address bus 13 Bits
  output wire 		SDRAM_DQML, // SDRAM Low-byte Data Mask
  output wire 		SDRAM_DQMH, // SDRAM High-byte Data Mask
  output wire 		SDRAM_nWE, // SDRAM Write Enable
  output wire 		SDRAM_nCAS, // SDRAM Column Address Strobe
  output wire 		SDRAM_nRAS, // SDRAM Row Address Strobe
  output wire 		SDRAM_nCS, // SDRAM Chip Select
  output wire [ 2-1:0] 	SDRAM_BA, // SDRAM Bank Address
  output wire 		SDRAM_CLK, // SDRAM Clock
  output wire 		SDRAM_CKE, // SDRAM Clock Enable
  // MINIMIG specific
  output wire 		AUDIO_L, // sigma-delta DAC output left
  output wire 		AUDIO_R, // sigma-delta DAC output right
  // SPI
  inout wire 		SPI_DO,  // inout
  input wire 		SPI_DI,
  input wire 		SPI_SCK,
  input wire 		SPI_SS2,    // fpga
  input wire 		SPI_SS3,    // OSD
  input wire 		SPI_SS4,    // "sniff" mode
  input wire 		CONF_DATA0  // SPI_SS for user_io
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
wire           led;
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

// sdram
wire           reset_out;
wire [  4-1:0] sdram_cs;
wire [  2-1:0] sdram_dqm;
wire [  2-1:0] sdram_ba;


////////////////////////////////////////
// toplevel assignments               //
////////////////////////////////////////

// SDRAM
assign SDRAM_CKE         = 1'b1;
assign SDRAM_CLK         = clk_sdram;
assign SDRAM_nCS         = sdram_cs[0];
assign SDRAM_DQML        = sdram_dqm[0];
assign SDRAM_DQMH        = sdram_dqm[1];
assign SDRAM_BA          = sdram_ba;
// assign SDRAM_A[12]       = 1'b0; // unused SDRAM address bit

// clock
assign pll_in_clk       = CLOCK_27[0];

// reset
assign pll_rst          = 1'b0; // !SW[0];
//assign sdctl_rst        = pll_locked; // & SW[0];
assign sdctl_rst        = 1'b1; // & SW[0];

// minimig
assign _15khz           = 1'b1; // sw_9;
assign joy_emu_en       = 1'b1; // sw_8;

assign LED              = ~led;

// unused VGA pins
assign VGA_R[1:0] = 2'b00;
assign VGA_G[1:0] = 2'b00;
assign VGA_B[1:0] = 2'b00;

    
// use pll
PLLWrapper amigaclk (
  .areset       (pll_rst          ), // async reset input
  .inclk0       (pll_in_clk       ), // input clock (27MHz)
  .eightmhz		 (board_switches[1] ), // For testing, reconfig based on board button[0]
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
  .reset        (tg68_rst & reset_out),
  .clkena_in    (pll_locked       ),
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
  .sdaddr       (SDRAM_A[12:0]    ),
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

// multiplex spi_do, drive it from user_io if that's selected, drive
// it from minimig if it's selected and leave it open else (also
// to be able to monitor sd card data directly)
assign SPI_DO = (CONF_DATA0 == 1'b0)?user_io_sdo:
		(((SPI_SS2 == 1'b0)|| (SPI_SS3 == 1'b0))?minimig_sdo:1'bZ);
  
wire user_io_sdo;
wire minimig_sdo;
   
wire [5:0] joya;
wire [5:0] joyb;

wire [7:0] kbd_mouse_data;
wire       kbd_mouse_strobe;
wire [1:0] kbd_mouse_type;
wire [2:0] mouse_buttons;
wire [1:0] board_buttons;
wire [1:0] board_switches;

	
//// user io has an extra spi channel outside minimig core ////
user_io user_io(
     .SPI_CLK(SPI_SCK),
     .SPI_SS_IO(CONF_DATA0),
     .SPI_MISO(user_io_sdo),
     .SPI_MOSI(SPI_DI),
     .JOY0(joya),
     .JOY1(joyb),
     .MOUSE_BUTTONS(mouse_buttons),
     .KBD_MOUSE_DATA(kbd_mouse_data),
     .KBD_MOUSE_TYPE(kbd_mouse_type),
     .KBD_MOUSE_STROBE(kbd_mouse_strobe),
     .CORE_TYPE(8'ha1),    // minimig core id
	  .BUTTONS(board_buttons),
	  .SWITCHES(board_switches)
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
  .rxd          (UART_RX          ),  // RS232 receive
  .txd          (UART_TX          ),  // RS232 send
  .cts          (1'b0             ),  // RS232 clear to send
  .rts          (                 ),  // RS232 request to send
  //I/O
  ._joy1        (~joya            ),  // joystick 1 [fire2,fire,up,down,left,right] (default mouse port)
  ._joy2        (~joyb            ),  // joystick 2 [fire2,fire,up,down,left,right] (default joystick port)
  .mouse_btn    (mouse_buttons    ),  // mouse buttons
  .kbd_mouse_data (kbd_mouse_data ),  // mouse direction data, keycodes
  .kbd_mouse_type (kbd_mouse_type ),  // type of data
  .kbd_mouse_strobe (kbd_mouse_strobe), // kbd/mouse data strobe
  .joy_emu_en   (joy_emu_en       ),  // enable keyboard joystick emulation
  ._15khz       (_15khz           ),  // scandoubler disable
  .pwrled       (led              ),  // power led
  .msdat        (                 ),  // PS2 mouse data
  .msclk        (                 ),  // PS2 mouse clk
  .kbddat       (                 ),  // PS2 keyboard data
  .kbdclk       (                 ),  // PS2 keyboard clk
  //host controller interface (SPI)
  ._scs         ( {SPI_SS4,SPI_SS3,SPI_SS2}  ),  // SPI chip select
  .direct_sdi   (SPI_DO           ),  // SD Card direct in  SPI_SDO
  .sdi          (SPI_DI           ),  // SPI data input
  .sdo          (minimig_sdo      ),  // SPI data output
  .sck          (SPI_SCK          ),  // SPI clock
  //video
  ._hsync       (VGA_HS           ),  // horizontal sync
  ._vsync       (VGA_VS           ),  // vertical sync
  .red          (VGA_R[5:2]       ),  // red
  .green        (VGA_G[5:2]       ),  // green
  .blue         (VGA_B[5:2]       ),  // blue
  //audio
  .left         (AUDIO_L          ),  // audio bitstream left
  .right        (AUDIO_R          ),  // audio bitstream right
  .ldata        (                 ),  // left DAC data
  .rdata        (                 ),  // right DAC data
  //user i/o
  .gpio         (                 ),  // spare GPIO
  .cpu_config   (cpu_config       ),  // CPU config
  .memcfg       (memcfg           ),  // memory config
  .drv_snd      (                 ),  // drive sound
  .init_b       (                 ),  // vertical sync for MCU (sync OSD update)
  // fifo / track display
  .trackdisp    (                 ),  // floppy track number
  .secdisp      (                 ),  // sector
  .floppy_fwr   (                 ),  // floppy fifo writing
  .floppy_frd   (                 ),  // floppy fifo reading
  .hd_fwr       (                 ),  // hd fifo writing
  .hd_frd       (                 )   // hd fifo  ading
);

endmodule

