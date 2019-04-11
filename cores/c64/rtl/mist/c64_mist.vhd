---------------------------------------------------------------------------------
-- DE2-35 Top level for FPGA64_027 by Dar (darfpga@aol.fr)
-- http://darfpga.blogspot.fr
--
-- FPGA64 is Copyrighted 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
--
-- Main features
--  15KHz(TV) / 31Khz(VGA) : board switch(0)
--  PAL(50Hz) / NTSC(60Hz) : board switch(1) and F12 key
--  PS2 keyboard input with portA / portB joystick emulation : F11 key
--  wm8731 sound output
--  64Ko of board SRAM used
--  External IEC bus available at gpio_1 (for drive 1541 or IEC/SD ...)
--   activated by switch(5) (activated with no hardware will stuck IEC bus)
--
--  Internal emulated 1541 on raw SD card : D64 images start at 25x6KB boundaries
--  Use hexidecimal disk editor such as HxD (www.mh-nexus.de) to build SD card.
--  Cut D64 file and paste at 0x00000 (first), 0x40000 (second), 0x80000 (third),
--  0xC0000(fourth), 0x100000(fith), 0x140000 (sixth) and so on.
--  BE CAREFUL NOT WRITING ON YOUR OWN HARDDRIVE
--
-- Uses only one pll for 32MHz and 18MHz generation from 50MHz
-- DE1 and DE0 nano Top level also available
--     
---------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

entity c64_mist is port
(
	-- Clocks
   CLOCK_27   : in    std_logic;

   -- LED
   LED        : out   std_logic;

   -- VGA
   VGA_R      : out   std_logic_vector(5 downto 0);
   VGA_G      : out   std_logic_vector(5 downto 0);
   VGA_B      : out   std_logic_vector(5 downto 0);
   VGA_HS     : out   std_logic;
   VGA_VS     : out   std_logic;

   -- SDRAM
   SDRAM_A    : out   std_logic_vector(12 downto 0);
   SDRAM_DQ   : inout std_logic_vector(15 downto 0);
   SDRAM_DQML : out   std_logic;
   SDRAM_DQMH : out   std_logic;
   SDRAM_nWE  : out   std_logic;
   SDRAM_nCAS : out   std_logic;
   SDRAM_nRAS : out   std_logic;
   SDRAM_nCS  : out   std_logic;
   SDRAM_BA   : out   std_logic_vector(1 downto 0);
   SDRAM_CLK  : out   std_logic;
   SDRAM_CKE  : out   std_logic;

   -- AUDIO
   AUDIO_L    : out   std_logic;
   AUDIO_R    : out   std_logic;

   -- SPI interface to io controller
   SPI_SCK    : in    std_logic;
   SPI_DO     : inout std_logic;
   SPI_DI     : in    std_logic;
   SPI_SS2    : in    std_logic;
   SPI_SS3    : in    std_logic;
   CONF_DATA0 : in    std_logic;

   UART_RX    : in    std_logic;
   UART_TX    : out   std_logic
);
end c64_mist;

architecture struct of c64_mist is

component sdram is port
(
   -- interface to the MT48LC16M16 chip
   sd_addr    : out   std_logic_vector(12 downto 0);
   sd_data    : inout std_logic_vector(15 downto 0);
   sd_cs      : out   std_logic;
   sd_ba      : out   std_logic_vector(1 downto 0);
   sd_we      : out   std_logic;
   sd_ras     : out   std_logic;
   sd_cas     : out   std_logic;

   -- system interface
   clk        : in    std_logic;
   init       : in    std_logic;

   -- cpu/chipset interface
   addr       : in    std_logic_vector(24 downto 0);
   din        : in    std_logic_vector( 7 downto 0);
   dout       : out   std_logic_vector( 7 downto 0);
   refresh    : in    std_logic;
   we         : in    std_logic;
   ce         : in    std_logic
);
end component;

component sram is port
(
	init       : in    std_logic;
	clk        : in    std_logic;
   SDRAM_DQ   : inout std_logic_vector(15 downto 0);
   SDRAM_A    : out   std_logic_vector(12 downto 0);
   SDRAM_DQML : out   std_logic;
   SDRAM_DQMH : out   std_logic;
   SDRAM_BA   : out   std_logic_vector(1 downto 0);
   SDRAM_nCS  : out   std_logic;
   SDRAM_nWE  : out   std_logic;
   SDRAM_nRAS : out   std_logic;
   SDRAM_nCAS : out   std_logic;
   SDRAM_CKE  : out   std_logic;

   wtbt       : in    std_logic_vector(1 downto 0);
   addr       : in    std_logic_vector(24 downto 0);
   dout       : out   std_logic_vector(15 downto 0);
   din        : in    std_logic_vector(15 downto 0);
   we         : in    std_logic;
   rd         : in    std_logic;
   ready      : out   std_logic
);
end component;

constant CONF_STR : string := 
	"C64;;"&
	"S,D64,Mount Disk;"&
	"F,PRGTAPCRT,Load;"& --2
	"F,ROM,Load Kernal;"& --3
--	"F,T64,Load File;"&--6
	"TH,Play/Stop TAP;"&
	"OI,Tape sound,Off,On;"&
	"OG,Disk Write,Enable,Disable;"&
	"O2,Video standard,PAL,NTSC;"&
	"O8A,Scandoubler Fx,None,HQ2x-320,HQ2x-160,CRT 25%,CRT 50%;"&
	"ODF,SID,6581 Mono,6581 Stereo,8580 Mono,8580 Stereo,Pseudo Stereo;"&
	"O6,Audio filter,On,Off;"&
	"O3,Joysticks,normal,swapped;"&
	"O7,Userport,4-player IF,UART;"&
	"O4,CIA Model,6256,8521;"&
--	"OB,BIOS,C64,C64GS;" &
	"T5,Reset & Detach Cartridge;";

-- convert string to std_logic_vector to be given to user_io
function to_slv(s: string) return std_logic_vector is 
  constant ss: string(1 to s'length) := s; 
  variable rval: std_logic_vector(1 to 8 * s'length); 
  variable p: integer; 
  variable c: integer; 
begin 
  for i in ss'range loop
    p := 8 * i;
    c := character'pos(ss(i));
    rval(p - 7 to p) := std_logic_vector(to_unsigned(c,8)); 
  end loop; 
  return rval; 
end function; 

component user_io generic(STRLEN : integer := 0 ); port
(
	clk_sys : in std_logic;
	clk_sd  : in std_logic;
	SPI_CLK, SPI_SS_IO, SPI_MOSI :in std_logic;
	SPI_MISO : out std_logic;
	conf_str : in std_logic_vector(8*STRLEN-1 downto 0);
	joystick_0 : out std_logic_vector(31 downto 0);
	joystick_1 : out std_logic_vector(31 downto 0);
	joystick_2 : out std_logic_vector(31 downto 0);
	joystick_3 : out std_logic_vector(31 downto 0);
	joystick_4 : out std_logic_vector(31 downto 0);
	joystick_analog_0 : out std_logic_vector(15 downto 0);
	joystick_analog_1 : out std_logic_vector(15 downto 0);
	status: out std_logic_vector(31 downto 0);
	switches : out std_logic_vector(1 downto 0);
	buttons : out std_logic_vector(1 downto 0);
	scandoubler_disable : out std_logic;
	ypbpr : out std_logic;

	sd_lba            : in  std_logic_vector(31 downto 0);
	sd_rd             : in  std_logic;
	sd_wr             : in  std_logic;
	sd_ack            : out std_logic;
	sd_ack_conf       : out std_logic;
	sd_conf           : in  std_logic;
	sd_sdhc           : in  std_logic;
	img_mounted       : out std_logic;

	sd_buff_addr      : out std_logic_vector(8 downto 0);
	sd_dout           : out std_logic_vector(7 downto 0);
	sd_din            : in  std_logic_vector(7 downto 0);
	sd_dout_strobe    : out std_logic;
	
	ps2_kbd_clk       : out std_logic;
	ps2_kbd_data      : out std_logic;

	ps2_mouse_clk     : out std_logic;
	ps2_mouse_data    : out std_logic;
	mouse_x           : out signed(8 downto 0);
	mouse_y           : out signed(8 downto 0);
	mouse_flags       : out std_logic_vector(8 downto 0); -- YOvfl, XOvfl, dy8, dx8, 1, mbtn, rbtn, lbtn
	mouse_strobe      : out std_logic
	);
end component user_io;

component data_io port
(
	clk_sys			  : in std_logic;
	SPI_SCK, SPI_SS2, SPI_DI :in std_logic;
	ioctl_force_erase : in  std_logic;
	ioctl_download    : out std_logic;
	ioctl_erasing     : out std_logic;
	ioctl_index       : out std_logic_vector(7 downto 0);
	ioctl_wr          : out std_logic;
	ioctl_addr        : out std_logic_vector(24 downto 0);
	ioctl_dout        : out std_logic_vector(7 downto 0)
	);
end component data_io;

component video_mixer
	generic ( LINE_LENGTH : integer := 512; HALF_DEPTH : integer := 0 );
	port (
			clk_sys, ce_pix, ce_pix_actual : in std_logic;
			SPI_SCK, SPI_SS3, SPI_DI : in std_logic;
			scanlines : in std_logic_vector(1 downto 0);
			scandoubler_disable, hq2x, ypbpr, ypbpr_full : in std_logic;

			R, G, B : in std_logic_vector(5 downto 0);
			HSync, VSync, line_start, mono : in std_logic;

			VGA_R,VGA_G, VGA_B : out std_logic_vector(5 downto 0);
			VGA_VS, VGA_HS : out std_logic
	);
end component video_mixer;

---------
-- audio
--------

component sigma_delta_dac port
(
	clk      : in std_logic;
	ldatasum : in std_logic_vector(14 downto 0);
	rdatasum : in std_logic_vector(14 downto 0);
	aleft     : out std_logic;
	aright    : out std_logic
);

end component sigma_delta_dac;


--------------------------
-- cartridge - LCA mar17 -
--------------------------
component cartridge port
(
	romL			: in  std_logic;									-- romL signal in
	romH			: in  std_logic;									-- romH signal in
	UMAXromH		: in  std_logic;									-- VIC II ultimax read access flag
	mem_write	: in  std_logic;									-- memory write active
	mem_ce		: in  std_logic;
	mem_ce_out  : out std_logic;
	IOE			: in  std_logic;									-- IOE signal &DE00
	IOF			: in  std_logic;									-- IOF signal &DF00

	clk32		: in  std_logic;							-- 32mhz clock source
	reset		: in  std_logic;							-- reset signal
	reset_out	: out std_logic;							-- reset signal

	cart_id		: in  std_logic_vector(15 downto 0);		-- cart ID or cart type
	cart_exrom  : in  std_logic_vector(7 downto 0);			-- CRT file EXROM status
	cart_game   : in  std_logic_vector(7 downto 0);			-- CRT file GAME status

	cart_bank_laddr : in std_logic_vector(15 downto 0);	-- 1st bank loading address
	cart_bank_size  : in std_logic_vector(15 downto 0);	-- length of each bank
	cart_bank_num   : in std_logic_vector(15 downto 0);
	cart_bank_type  : in std_logic_vector(7 downto 0);
	cart_bank_raddr : in std_logic_vector(24 downto 0);	-- chip packet address
	cart_bank_wr    : in std_logic;

	cart_attached: in std_logic;									-- FLAG to say cart has been loaded
	cart_loading : in std_logic;

	c64_mem_address_in: in std_logic_vector(15 downto 0);	-- address from cpu
	c64_data_out: in std_logic_vector(7 downto 0);			-- data from cpu going to sdram

	sdram_address_out: out std_logic_vector(24 downto 0); -- translated address output
	exrom       : out std_logic;									-- exrom line
	game        : out std_logic;									-- game line
	IOE_ena     : out std_logic;
	IOF_ena     : out std_logic;
	max_ram     : out std_logic;
	freeze_key  : in  std_logic;
	nmi         : out std_logic;
	nmi_ack     : in  std_logic
);

end component cartridge;

	signal pll_locked_in : std_logic_vector(1 downto 0);
	signal pll_locked : std_logic;
	signal pll_areset : std_logic;
	signal pll_scanclk : std_logic;
	signal pll_scandata : std_logic;
	signal pll_scanclkena : std_logic;
	signal pll_configupdate : std_logic;
	signal pll_scandataout : std_logic;
	signal pll_scandone : std_logic;
	signal pll_rom_address : std_logic_vector(7 downto 0);
	signal pll_write_rom_ena : std_logic;
	signal pll_write_from_rom : std_logic;
	signal pll_reconfig : std_logic;
	signal pll_reconfig_busy : std_logic;
	signal pll_reconfig_reset : std_logic;
	signal pll_reconfig_state : std_logic_vector(1 downto 0) := "00";
	signal pll_reconfig_timeout : integer;
	signal q_reconfig_pal : std_logic_vector(0 downto 0);
	signal q_reconfig_ntsc : std_logic_vector(0 downto 0);
	signal pll_rom_q : std_logic;

	signal c1541_reset: std_logic;
	signal idle: std_logic;
	signal ces: std_logic_vector(3 downto 0);
	signal iec_cycle: std_logic;
	signal iec_cycleD: std_logic;
	signal iec_cycle_rD: std_logic;
	signal buttons: std_logic_vector(1 downto 0);
	
	-- signals to connect "data_io" for direct PRG injection
	signal ioctl_wr: std_logic;
	signal ioctl_addr: std_logic_vector(24 downto 0);
	signal ioctl_data: std_logic_vector(7 downto 0);
	signal ioctl_index: std_logic_vector(7 downto 0);
	signal ioctl_ram_addr: std_logic_vector(24 downto 0);
	signal ioctl_ram_data: std_logic_vector(7 downto 0);
	signal ioctl_load_addr  : std_logic_vector(24 downto 0);
	signal ioctl_ram_wr: std_logic;
	signal ioctl_iec_cycle_used: std_logic;
	signal ioctl_force_erase: std_logic;
	signal ioctl_erasing: std_logic;
	signal ioctl_download: std_logic;
	signal c64_addr: std_logic_vector(15 downto 0);
	signal c64_data_in: std_logic_vector(7 downto 0);
	signal c64_data_out: std_logic_vector(7 downto 0);
	signal sdram_addr: std_logic_vector(24 downto 0);
	signal sdram_data_out: std_logic_vector(7 downto 0);
	
	

--	cartridge signals LCA
	signal cart_id 			: std_logic_vector(15 downto 0);					-- cart ID or cart type
	signal cart_bank_laddr 	: std_logic_vector(15 downto 0) := (others => '0'); -- 1st bank loading address
	signal cart_bank_size 	: std_logic_vector(15 downto 0) := (others => '0'); -- length of each bank
	signal cart_bank_num 	: std_logic_vector(15 downto 0) := (others => '0'); -- bank number
	signal cart_bank_type 	: std_logic_vector(7 downto 0) := (others => '0');	 -- bank type
	signal cart_exrom			: std_logic_vector(7 downto 0);					-- CRT file EXROM status
	signal cart_game			: std_logic_vector(7 downto 0);					-- CRT file GAME status
	signal cart_attached		: std_logic;
	signal game					: std_logic;											-- game line to cpu
	signal exrom				: std_logic;											-- exrom line to cpu
	signal IOE_rom 			: std_logic;
	signal IOF_rom 			: std_logic;
	signal max_ram 			: std_logic;
	signal cart_loading 			:  std_logic;

	signal cart_hdr_wr	   : std_logic;

	signal IOE					: std_logic;												-- IOE signal
	signal IOF					: std_logic;												-- IOF signal
	signal cartridge_reset	: std_logic;												-- FLAG to reset once cart loaded
	signal reset_crt        : std_logic;	
	signal romL				: std_logic;													-- cart romL from buslogic LCA
	signal romH				: std_logic;													-- cart romH from buslogic LCA
	signal UMAXromH		: std_logic;													-- VIC II Ultimax access - LCA
	
	signal CPU_hasbus		: std_logic;
	
	signal c1541rom_wr   : std_logic;
	signal c64rom_wr     : std_logic;
	signal c64rom_addr   : std_logic_vector(13 downto 0);

	signal joyA : std_logic_vector(31 downto 0);
	signal joyB : std_logic_vector(31 downto 0);
	signal joyC : std_logic_vector(31 downto 0);
	signal joyD : std_logic_vector(31 downto 0);
	signal joyA_int : std_logic_vector(6 downto 0);
	signal joyB_int : std_logic_vector(6 downto 0);
	signal joyA_c64 : std_logic_vector(6 downto 0);
	signal joyB_c64 : std_logic_vector(6 downto 0);
	signal joyC_c64 : std_logic_vector(6 downto 0);
	signal joyD_c64 : std_logic_vector(6 downto 0);
	signal potA_x   : std_logic_vector(7 downto 0);
	signal potA_y   : std_logic_vector(7 downto 0);
	signal potB_x   : std_logic_vector(7 downto 0);
	signal potB_y   : std_logic_vector(7 downto 0);
	signal reset_key : std_logic;
	signal cart_detach_key :std_logic;							-- cartridge detach key CTRL-D - LCA
	
	signal c64_r  : std_logic_vector(5 downto 0);
	signal c64_g  : std_logic_vector(5 downto 0);
	signal c64_b  : std_logic_vector(5 downto 0);

	signal status         : std_logic_vector(31 downto 0);
	signal scanlines      : std_logic_vector(1 downto 0);
	signal hq2x           : std_logic;
	signal ce_pix_actual  : std_logic;
	signal sd_lba         : std_logic_vector(31 downto 0);
	signal sd_rd          : std_logic;
	signal sd_wr          : std_logic;
	signal sd_ack         : std_logic;
	signal sd_ack_conf    : std_logic;
	signal sd_conf        : std_logic;
	signal sd_sdhc        : std_logic;
	signal sd_buff_addr   : std_logic_vector(8 downto 0);
	signal sd_buff_dout   : std_logic_vector(7 downto 0);
	signal sd_buff_din    : std_logic_vector(7 downto 0);
	signal sd_buff_wr     : std_logic;
	signal sd_change      : std_logic;
	signal disk_readonly  : std_logic;
	signal old_download     : std_logic;	
	signal sdram_we : std_logic;
	signal sdram_ce : std_logic;

	signal ps2_clk : std_logic;
	signal ps2_dat : std_logic;
	signal mouse_en     : std_logic;
	signal mouse_x      : signed( 8 downto 0);
	signal mouse_x_pos  : signed(10 downto 0);
	signal mouse_y      : signed( 8 downto 0);
	signal mouse_y_pos  : signed(10 downto 0);
	signal mouse_flags  : std_logic_vector(8 downto 0);
	signal mouse_btns   : std_logic_vector(1 downto 0);
	signal mouse_strobe : std_logic;

	signal c64_iec_atn_i  : std_logic;
	signal c64_iec_clk_o  : std_logic;
	signal c64_iec_data_o : std_logic;
	signal c64_iec_atn_o  : std_logic;
	signal c64_iec_data_i : std_logic;
	signal c64_iec_clk_i  : std_logic;

	signal c1541_iec_atn_i  : std_logic;
	signal c1541_iec_clk_o  : std_logic;
	signal c1541_iec_data_o : std_logic;
	signal c1541_iec_atn_o  : std_logic;
	signal c1541_iec_data_i : std_logic;
	signal c1541_iec_clk_i  : std_logic;

	signal pa2_in	: std_logic;
	signal pa2_out  : std_logic;
	signal pb_in	: std_logic_vector(7 downto 0);
	signal pb_out	: std_logic_vector(7 downto 0);
	signal flag2_n  : std_logic;

	signal tv15Khz_mode   : std_logic;
	signal ypbpr          : std_logic;
	signal ntsc_init_mode : std_logic := '0';
	signal ntsc_init_mode_d: std_logic;
	signal ntsc_init_mode_d2: std_logic;
	signal ntsc_init_mode_d3: std_logic;

	alias  c64_addr_int : unsigned is unsigned(c64_addr);
	alias  c64_data_in_int   : unsigned is unsigned(c64_data_in);
	signal c64_data_in16: std_logic_vector(15 downto 0);
	alias  c64_data_out_int   : unsigned is unsigned(c64_data_out);

	signal clk_c64 : std_logic;	-- 31.527mhz (PAL), 32.727mhz(NTSC) clock source
	signal clk_ram : std_logic; -- 2 x clk_c64
	signal clk32   : std_logic; -- 32mhz
	signal ce_8  : std_logic;
	signal ce_4  : std_logic;
	signal hq2x160 : std_logic;
	signal osdclk : std_logic;
	signal clkdiv : std_logic_vector(9 downto 0);
	signal todclk : std_logic;
	signal toddiv : std_logic_vector(19 downto 0);
	signal toddiv3 : std_logic_vector(1 downto 0);

	signal ram_ce : std_logic;
	signal ram_we : std_logic;
	signal r : unsigned(7 downto 0);
	signal g : unsigned(7 downto 0);
	signal b : unsigned(7 downto 0);
	signal hsync : std_logic;
	signal vsync : std_logic;
	signal blank : std_logic;

	signal old_vsync : std_logic;
	signal hsync_out : std_logic;
	signal vsync_out : std_logic;
	
	signal audio_data_l : std_logic_vector(17 downto 0);
	signal audio_data_r : std_logic_vector(17 downto 0);
	signal audio_data_l_mix : std_logic_vector(17 downto 0);

	signal cass_motor  : std_logic;
	signal cass_write  : std_logic;
	signal cass_sense  : std_logic;
	signal cass_do : std_logic;
	signal tap_mem_ce : std_logic;
	signal tap_play_addr  : std_logic_vector(24 downto 0);
	signal tap_last_addr  : std_logic_vector(24 downto 0);
	signal tap_in : std_logic_vector(7 downto 0);
	signal tap_reset : std_logic;
	signal tap_wrreq : std_logic;
	signal tap_wrfull : std_logic;
	signal tap_fifo_error : std_logic;
	signal tap_mode : std_logic;
	signal tap_play : std_logic;
	signal tap_play_btn: std_logic;
	signal tap_play_btnD: std_logic;

	signal reset_counter    : integer;
	signal reset_n          : std_logic;
	signal led_disk         : std_logic;
	signal freeze_key  :   std_logic;
	signal nmi         :  std_logic;
	signal nmi_ack     :  std_logic;
	signal erasing          : std_logic;
	signal c64_addr_temp : std_logic_vector(24 downto 0);	
	signal cart_blk_len     : std_logic_vector(31 downto 0);	
	signal cart_hdr_cnt     : std_logic_vector(3 downto 0);
	signal erase_cram       : std_logic := '0';
	signal force_erase      : std_logic;
	signal erase_to         : std_logic_vector(4 downto 0) := (others => '0');
	signal mem_ce           : std_logic;
begin

	-- 1541/tape activity led
	LED <= not ioctl_download and not led_disk and cass_motor;

	iec_cycle <= '1' when ces = "1011" else '0';

	sd_sdhc <= '1';
	-- User io
	user_io_d : user_io
	generic map (STRLEN => CONF_STR'length)
	port map (
		clk_sys => clk_c64,
		clk_sd  => clk32,

		SPI_CLK => SPI_SCK,
		SPI_SS_IO => CONF_DATA0,
		SPI_MISO => SPI_DO,
		SPI_MOSI => SPI_DI,

		joystick_0 => joyA,
		joystick_1 => joyB,
		joystick_2 => joyC,
		joystick_3 => joyD,

		conf_str => to_slv(CONF_STR),

		status => status,
		buttons => buttons,
		scandoubler_disable => tv15Khz_mode,
		ypbpr => ypbpr,

		sd_lba => sd_lba,
		sd_rd => sd_rd,
		sd_wr => sd_wr,
		sd_ack => sd_ack,
		sd_ack_conf => sd_ack_conf,
		sd_conf => sd_conf,
		sd_sdhc => sd_sdhc,
		sd_buff_addr => sd_buff_addr,
		sd_dout => sd_buff_dout,
		sd_din => sd_buff_din,
		sd_dout_strobe => sd_buff_wr,
		img_mounted => sd_change,
		ps2_kbd_clk => ps2_clk,
		ps2_kbd_data => ps2_dat,
		mouse_x => mouse_x,
		mouse_y => mouse_y,
		mouse_flags => mouse_flags,
		mouse_strobe => mouse_strobe
	);

	data_io_d: data_io
	port map (
		clk_sys => clk_c64,
		SPI_SCK => SPI_SCK,
		SPI_SS2 => SPI_SS2,
		SPI_DI => SPI_DI,

		ioctl_download => ioctl_download,
		ioctl_force_erase => ioctl_force_erase,
		ioctl_erasing => ioctl_erasing,
		ioctl_index => ioctl_index,
		ioctl_wr => ioctl_wr,
		ioctl_addr => ioctl_addr,
		ioctl_dout => ioctl_data
	);

	cart_loading <= '1' when ioctl_download = '1' and ioctl_index = x"82" else '0';

	cart : cartridge
	port map (
		romL => romL,		
		romH => romH,	
		UMAXromH => UMAXromH,
		IOE => IOE,
		IOF => IOF,
		mem_write => not ram_we,	
		mem_ce => not ram_ce,
		mem_ce_out => mem_ce,

		clk32 => clk_c64,
		reset => reset_n,
		reset_out => reset_crt,
		
		cart_id => cart_id,		
		cart_exrom => cart_exrom,
		cart_game => cart_game,

		cart_bank_laddr => cart_bank_laddr,
		cart_bank_size => cart_bank_size,
		cart_bank_num => cart_bank_num,
		cart_bank_type => cart_bank_type,
		cart_bank_raddr => ioctl_load_addr,
		cart_bank_wr => cart_hdr_wr,
		
	 	cart_attached => cart_attached,
		cart_loading => cart_loading,
		
		c64_mem_address_in => c64_addr,
		c64_data_out => c64_data_out,
		
		sdram_address_out => c64_addr_temp,
		exrom	=> exrom,							
		game => game,
		IOE_ena => ioE_rom,
		IOF_ena => ioF_rom,
		max_ram => max_ram,
		freeze_key => freeze_key,
		nmi => nmi,
		nmi_ack => nmi_ack
	);
	
	-- rearrange joystick contacta for c64
	joyA_int <= joyA(6 downto 5) & (joyA(4) or (mouse_en and mouse_btns(0))) & joyA(0) & joyA(1) & joyA(2) & (joyA(3) or (mouse_en and mouse_btns(1)));
	joyB_int <= joyB(6 downto 5) & (joyB(4) or (mouse_en and mouse_btns(0))) & joyB(0) & joyB(1) & joyB(2) & (joyB(3) or (mouse_en and mouse_btns(1)));
	joyC_c64 <= joyC(6 downto 4) & joyC(0) & joyC(1) & joyC(2) & joyC(3);
	joyD_c64 <= joyD(6 downto 4) & joyD(0) & joyD(1) & joyD(2) & joyD(3);

	-- swap joysticks if requested
	joyA_c64 <= joyB_int when status(3)='1' else joyA_int;
	joyB_c64 <= joyA_int when status(3)='1' else joyB_int;

	sdram_addr <= c64_addr_temp when iec_cycle='0' else ioctl_ram_addr when ioctl_download = '1' else tap_play_addr;
	sdram_data_out <= c64_data_out when iec_cycle='0' else ioctl_ram_data;

	-- ram_we and ce are active low
	sdram_ce <= mem_ce when iec_cycle='0' else ioctl_iec_cycle_used or tap_mem_ce;
	sdram_we <= not ram_we when iec_cycle='0' else ioctl_iec_cycle_used when ioctl_download = '1' else '0';

	process(clk_c64)
	begin
		if falling_edge(clk_c64) then

			old_download <= ioctl_download;
			iec_cycleD <= iec_cycle;
			cart_hdr_wr <= '0';

			if(iec_cycle='1' and iec_cycleD='0' and ioctl_ram_wr='1') then
				ioctl_ram_wr <= '0';
				ioctl_iec_cycle_used <= '1';
				ioctl_ram_addr  <= ioctl_load_addr;
				ioctl_load_addr <= ioctl_load_addr + "1";
				if erasing = '1' then
					ioctl_ram_data  <= (others => '0');
				else
					ioctl_ram_data <= ioctl_data;
				end if;
			else 
				if(iec_cycle='0') then
					ioctl_iec_cycle_used <= '0';
				end if;
			end if;

			if ioctl_wr='1' then
				if ioctl_index = x"02" then--prg
					if ioctl_addr = 0 then
						ioctl_load_addr(7 downto 0) <= ioctl_data;
					elsif(ioctl_addr = 1) then
						ioctl_load_addr(15 downto 8) <= ioctl_data;
					else
						ioctl_ram_wr <= '1';
					end if;
				end if;

				if ioctl_index = x"82" then--CRT, e0(MAX)
					if ioctl_addr = 0 then
						ioctl_load_addr <= '0' & X"100000";
						cart_blk_len <= (others => '0');
						cart_hdr_cnt <= (others => '0');
					end if;

					if(ioctl_addr = X"16") then cart_id(15 downto 8)  <= ioctl_data; end if;
					if(ioctl_addr = X"17") then cart_id(7 downto 0)   <= ioctl_data; end if;
					if(ioctl_addr = X"18") then cart_exrom(7 downto 0)<= ioctl_data; end if;
					if(ioctl_addr = X"19") then cart_game(7 downto 0) <= ioctl_data; end if;

					if(ioctl_addr >= X"40") then
						if cart_blk_len = 0 and cart_hdr_cnt = 0 then
							cart_hdr_cnt <= X"1";
							if ioctl_load_addr(12 downto 0) /= 0 then
							   -- align to 8KB boundary
								ioctl_load_addr(12 downto 0) <= '0' & X"000";
								ioctl_load_addr(24 downto 13) <= ioctl_load_addr(24 downto 13) + "1";
							end if;
						elsif cart_hdr_cnt /= 0 then
							cart_hdr_cnt <= cart_hdr_cnt + "1";
							if(cart_hdr_cnt = 4)  then cart_blk_len(31 downto 24)  <= ioctl_data; end if;
							if(cart_hdr_cnt = 5)  then cart_blk_len(23 downto 16)  <= ioctl_data; end if;
							if(cart_hdr_cnt = 6)  then cart_blk_len(15 downto 8)   <= ioctl_data; end if;
							if(cart_hdr_cnt = 7)  then cart_blk_len(7 downto 0)    <= ioctl_data; end if;
							if(cart_hdr_cnt = 8)  then cart_blk_len <= cart_blk_len - X"10";		 end if;
							if(cart_hdr_cnt = 9)  then cart_bank_type              <= ioctl_data; end if;
							if(cart_hdr_cnt = 10) then cart_bank_num(15 downto 8)  <= ioctl_data; end if;
							if(cart_hdr_cnt = 11) then cart_bank_num(7 downto 0)   <= ioctl_data; end if;
							if(cart_hdr_cnt = 12) then cart_bank_laddr(15 downto 8)<= ioctl_data; end if;
							if(cart_hdr_cnt = 13) then cart_bank_laddr(7 downto 0) <= ioctl_data; end if;
							if(cart_hdr_cnt = 14) then cart_bank_size(15 downto 8) <= ioctl_data; end if;
							if(cart_hdr_cnt = 15) then cart_bank_size(7 downto 0)  <= ioctl_data; end if;
							if(cart_hdr_cnt = 15) then cart_hdr_wr <= '1';                        end if;
						else
							cart_blk_len <= cart_blk_len - "1";
							ioctl_ram_wr <= '1';
						end if;
					end if;
				end if;

				if ioctl_index = x"42" then -- TAP
					if ioctl_addr = 0 then
						ioctl_load_addr <= '0' & X"200000";
						ioctl_ram_data <= ioctl_data;
					else
						ioctl_ram_wr <= '1';
					end if;
				end if;

			end if;
			
			if old_download /= ioctl_download and ioctl_index = x"82" then
				cart_attached <= old_download;
				erase_cram <= '1';
			end if;

			if status(5)='1' or buttons(1)='1' then
				cart_attached <= '0';
			end if;
			
			if erasing='0' and force_erase = '1' then
				erasing <='1';
				ioctl_load_addr <= (others => '0');
			end if;

			if erasing = '1' and ioctl_ram_wr = '0' then
				erase_to <= erase_to + "1";
				if erase_to = "11111" then
					if ioctl_load_addr < (erase_cram & X"FFFF") then 
						ioctl_ram_wr <= '1';
					else
						erasing <= '0';
						erase_cram <= '0';
					end if;
				end if;
			end if;
		end if;
	end process;

	c64rom_wr   <= ioctl_wr when (((ioctl_index = 0) and (ioctl_addr(14) = '0')) or (ioctl_index = 3)) and (ioctl_download = '1') else '0';
	c64rom_addr <= ioctl_addr(13 downto 0) when ioctl_index = 0 else '1' & ioctl_addr(12 downto 0);
	c1541rom_wr <= ioctl_wr when (ioctl_index = 0) and (ioctl_addr(14) = '1') and (ioctl_download = '1') else '0';

	process(clk_c64)
	begin
		if rising_edge(clk_c64) then
			clkdiv <= std_logic_vector(unsigned(clkdiv)+1);
			if(clkdiv(1 downto 0) = "00") then
				ce_8 <= '1';
			else
				ce_8 <= '0';
			end if;
			if(clkdiv(2 downto 0) = "000") then
				ce_4 <= '1';
			else
				ce_4 <= '0';
			end if;
		end if;
	end process;

	ntsc_init_mode <= status(2);

	pll_rom_pal : entity work.rom_reconfig_pal
	port map(
		address => pll_rom_address,
		clock => clk32,
		rden => pll_write_rom_ena,
		q => q_reconfig_pal
	);

	pll_rom_ntsc : entity work.rom_reconfig_ntsc
	port map(
		address => pll_rom_address,
		clock => clk32,
		rden => pll_write_rom_ena,
		q => q_reconfig_ntsc
	);

	pll_rom_q <= q_reconfig_pal(0) when ntsc_init_mode_d2 = '0' else q_reconfig_ntsc(0);

	pll_c64_reconfig : entity work.pll_c64_reconfig
	port map (
		busy => pll_reconfig_busy,
		clock  => clk32,
		counter_param => (others => '0'),
		counter_type => (others => '0'),
		data_in => (others => '0'),
		pll_areset => pll_areset,
		pll_areset_in  => '0',
		pll_configupdate => pll_configupdate,
		pll_scanclk => pll_scanclk,
		pll_scanclkena => pll_scanclkena,
		pll_scandata => pll_scandata,
		pll_scandataout => pll_scandataout,
        pll_scandone => pll_scandone,
		read_param => '0',
        reconfig => pll_reconfig,
		reset => pll_reconfig_reset,
		reset_rom_address => '0',
		rom_address_out => pll_rom_address,
		rom_data_in => pll_rom_q,
		write_from_rom => pll_write_from_rom,
		write_param  => '0',
        write_rom_ena => pll_write_rom_ena
	);

	process(clk32)
	begin
		if rising_edge(clk32) then
			ntsc_init_mode_d <= ntsc_init_mode;
			ntsc_init_mode_d2 <= ntsc_init_mode_d;
			pll_write_from_rom <= '0';
			pll_reconfig <= '0';
			pll_reconfig_reset <= '0';
			case pll_reconfig_state is
			when "00" =>
				ntsc_init_mode_d3 <= ntsc_init_mode_d2;
				if ntsc_init_mode_d3 /= ntsc_init_mode_d2 then
					pll_write_from_rom <= '1';
					pll_reconfig_state <= "01";
				end if;
			when "01" =>
				pll_reconfig_state <= "10";
			when "10" =>
				if pll_reconfig_busy = '0' then
					pll_reconfig <= '1';
					pll_reconfig_state <= "11";
					pll_reconfig_timeout <= 1000;
				end if;
			when "11" =>
				pll_reconfig_timeout <= pll_reconfig_timeout - 1;
				if pll_reconfig_timeout = 1 then
					pll_reconfig_reset <= '1'; -- sometimes pll reconfig stuck in busy state
					pll_reconfig_state <= "00";
				end if;
				if pll_reconfig = '0' and pll_reconfig_busy = '0' then
					pll_reconfig_state <= "00";
				end if;
			when others => null;
			end case;
		end if;
	end process;

	-- clock for C64 and SDRAM
	pll : entity work.pll_c64
	port map(
		inclk0 => CLOCK_27,
		c0 => clk_ram,
		c1 => clk_c64,
		areset => pll_areset,
		scanclk => pll_scanclk,
		scandata => pll_scandata,
		scanclkena => pll_scanclkena,
		configupdate => pll_configupdate,
		scandataout => pll_scandataout,
		scandone => pll_scandone
	);
	SDRAM_CLK <= clk_ram;

	-- clock for 1541
	pll_2 : entity work.pll
	port map(
		inclk0 => CLOCK_27,
		c0 => clk32,
		locked => pll_locked
	);

	process(clk_c64)
	begin
		if rising_edge(clk_c64) then
			-- Reset by:
			-- Button at device, IO controller reboot, OSD or FPGA startup
			if status(0)='1' or pll_locked = '0' then
				reset_counter <= 1000000;
				reset_n <= '0';
			elsif buttons(1)='1' or status(5)='1' or reset_key = '1' or reset_crt='1' or
			(ioctl_download='1' and (ioctl_index = 3 or ioctl_index = x"82")) then -- kernal or crt
				reset_counter <= 255;
				reset_n <= '0';
			elsif ioctl_download ='1' then
			elsif erasing ='1' then
				force_erase <= '0';
			else
				if reset_counter = 0 then
					reset_n <= '1';
				else
					reset_counter <= reset_counter - 1;
					if reset_counter = 100 then
						force_erase <='1';
					end if;
				end if;
			end if;
		end if;
	end process;

	-- clock is always enabled and memory is never masked as we only
	-- use one byte
	SDRAM_CKE <= '1';
	SDRAM_DQML <= '0';
	SDRAM_DQMH <= '0';

	sdr: sdram port map(
		sd_addr => SDRAM_A,
		sd_data => SDRAM_DQ,
		sd_ba => SDRAM_BA,
		sd_cs => SDRAM_nCS,
		sd_we => SDRAM_nWE,
		sd_ras => SDRAM_nRAS,
		sd_cas => SDRAM_nCAS,

		clk => clk_ram,
		addr => sdram_addr,
		din => sdram_data_out,
		dout => c64_data_in,
		init => not pll_locked,
		we => sdram_we,
		refresh => idle,
		ce => sdram_ce
	);

	audio_data_l_mix <= audio_data_l when status(18) = '0' else
	                    audio_data_l + (cass_do & "00000000000000");
--	                    (cass_do & "00000000000000000");

	dac : sigma_delta_dac
	port map (
		clk => clk_c64,
		ldatasum => audio_data_l_mix(17 downto 3),
		rdatasum => audio_data_r(17 downto 3),
		aleft => AUDIO_L,
		aright => AUDIO_R
	);

	fpga64 : entity work.fpga64_sid_iec
	port map(
		clk32 => clk_c64,
		reset_n => reset_n,
		c64gs => status(11),-- not enough BRAM
		kbd_clk => not ps2_clk,
		kbd_dat => ps2_dat,
		ramAddr => c64_addr_int,
		ramDataOut => c64_data_out_int,
		ramDataIn => c64_data_in_int,
		ramCE => ram_ce,
		ramWe => ram_we,
		ntscInitMode => ntsc_init_mode,
		hsync => hsync,
		vsync => vsync,
		r => r,
		g => g,
		b => b,
		game => game,
		exrom => exrom,
		UMAXromH => UMAXromH,
		CPU_hasbus => CPU_hasbus,		
		ioE_rom => ioE_rom,
		ioF_rom => ioF_rom,
		max_ram => max_ram,
		irq_n => '1',
		nmi_n => not nmi,
		nmi_ack => nmi_ack,
		freeze_key => freeze_key,
		dma_n => '1',
		romL => romL,
		romH => romH,
		IOE => IOE,									
		IOF => IOF,
		ba => open,
		joyA => unsigned(joyA_c64),
		joyB => unsigned(joyB_c64),
		potA_x => potA_x,
		potA_y => potA_y,
		potB_x => potB_x,
		potB_y => potB_y,
		serioclk => open,
		ces => ces,
		SIDclk => open,
		still => open,
		idle => idle,
		audio_data_l => audio_data_l,
		audio_data_r => audio_data_r,
		extfilter_en => not status(6),
		sid_mode => status(15 downto 13),
		iec_data_o => c64_iec_data_o,
		iec_atn_o  => c64_iec_atn_o,
		iec_clk_o  => c64_iec_clk_o,
		iec_data_i => c64_iec_data_i,
		iec_clk_i  => c64_iec_clk_i,
--		iec_atn_i  => not c64_iec_atn_i,
		pa2_in => pa2_in,
		pa2_out => pa2_out,
		pb_in => pb_in,
		pb_out => pb_out,
		flag2_n => flag2_n,
		todclk => todclk,
		cia_mode => status(4),
		disk_num => open,

		cass_motor => cass_motor,
		cass_write => cass_write,
		cass_sense => cass_sense,
		cass_do    => cass_do,

		c64rom_addr => c64rom_addr,
		c64rom_data => ioctl_data,
		c64rom_wr => c64rom_wr,
--		cart_detach_key => cart_detach_key,
		reset_key => reset_key
	);

	-- paddle pins - mouse or GS controller
	potA_x <= '0' & std_logic_vector(mouse_x_pos)(6 downto 1) & '0' when mouse_en = '1'
	          else x"00" when joyA_c64(5) = '1' else x"FF";
	potA_y <= '0' & std_logic_vector(mouse_y_pos)(6 downto 1) & '0' when mouse_en = '1'
	          else x"00" when joyA_c64(6) = '1' else x"FF";
	potB_x <= '0' & std_logic_vector(mouse_x_pos)(6 downto 1) & '0' when mouse_en = '1'
	          else x"00" when joyB_c64(5) = '1' else x"FF";
	potB_y <= '0' & std_logic_vector(mouse_y_pos)(6 downto 1) & '0' when mouse_en = '1'
	          else x"00" when joyB_c64(6) = '1' else x"FF";

	process(clk_c64, reset_n)
		variable mov_x: signed(6 downto 0);
		variable mov_y: signed(6 downto 0);
	begin
		if reset_n = '0' then
			mouse_x_pos <= (others => '0');
			mouse_y_pos <= (others => '0');
			mouse_en <= '0';
		elsif rising_edge(clk_c64) then
			if mouse_strobe = '1' then
				mouse_en <= '1';
				-- due to limited resolution on the c64 side, limit the mouse movement speed
				if mouse_x > 40 then mov_x:="0101000"; elsif mouse_x < -40 then mov_x:= "1011000"; else mov_x := mouse_x(6 downto 0); end if;
				if mouse_y > 40 then mov_y:="0101000"; elsif mouse_y < -40 then mov_y:= "1011000"; else mov_y := mouse_y(6 downto 0); end if;
				mouse_x_pos <= mouse_x_pos + mov_x;
				mouse_y_pos <= mouse_y_pos + mov_y;
				mouse_btns <= mouse_flags(1 downto 0);
			elsif joya(7 downto 0) /= 0 or joyb(7 downto 0) /= 0 then
				mouse_en <= '0';
			end if;
		end if;
	end process;

	-- connect user port
	process (pa2_out, pb_out, joyC_c64, joyD_c64, UART_RX, status)
	begin
		pa2_in <= pa2_out;
		if status(7) = '0' then
			-- Protovision 4 player interface
			flag2_n <= '1';
			UART_TX <= '0';
			pb_in(7 downto 6) <= pb_out(7 downto 6);
			if pb_out(7) = '1' then
				pb_in(5 downto 0) <= not joyC_c64(5 downto 0);
			else
				pb_in(5 downto 0) <= not joyD_c64(5 downto 0);
			end if;
		else
			-- UART
			pb_in(7 downto 1) <= pb_out(7 downto 1);
			flag2_n <= UART_RX;
			pb_in(0) <= UART_RX;
			UART_TX <= pa2_out;
		end if;
	end process;

	-- generate TOD clock from stable 32 MHz
	process(clk32, reset_n)
	begin
		if reset_n = '0' then
			todclk <= '0';
			toddiv <= (others => '0');
		elsif rising_edge(clk32) then
			toddiv <= toddiv + 1;
			if (ntsc_init_mode_d2 = '1' and toddiv = 266665 and toddiv3 = "00") or
			   (ntsc_init_mode_d2 = '1' and toddiv = 266666 and toddiv3 /= "00") or
			    toddiv = 319999 then
				toddiv <= (others => '0');
				todclk <= not todclk;
				toddiv3 <= toddiv3 + 1;
				if toddiv3 = "10" then toddiv3 <= "00"; end if;
			end if;
		end if;
	end process;

	disk_readonly <= status(16);

    c64_iec_data_i <= c1541_iec_data_o;
    c64_iec_clk_i <= c1541_iec_clk_o;

	c1541_iec_atn_i  <= c64_iec_atn_o;
	c1541_iec_data_i <= c64_iec_data_o;
	c1541_iec_clk_i  <= c64_iec_clk_o;

	process(clk_c64, reset_n)
		variable reset_cnt : integer range 0 to 32000000;
	begin
		if reset_n = '0' then
			reset_cnt := 100000;
		elsif rising_edge(clk_c64) then
			if reset_cnt /= 0 then
				reset_cnt := reset_cnt - 1;
			end if;
		end if;

		if reset_cnt = 0 then
			c1541_reset <= '0';
		else 
			c1541_reset <= '1';
		end if;
	end process;

	c1541_sd_inst : entity work.c1541_sd
	port map
	(
		clk32 => clk32,
		reset => c1541_reset,

		c1541rom_clk => clk_c64,
		c1541rom_addr => ioctl_addr(13 downto 0),
		c1541rom_data => ioctl_data,
		c1541rom_wr => c1541rom_wr,

		disk_change => sd_change,
		disk_num  => (others => '0'), -- always 0 on MiST, the image is selected by the OSD menu
		disk_readonly => disk_readonly,

		iec_atn_i  => c1541_iec_atn_i,
		iec_data_i => c1541_iec_data_i,
		iec_clk_i  => c1541_iec_clk_i,

		--iec_atn_o  => c1541_iec_atn_o,
		iec_data_o => c1541_iec_data_o,
		iec_clk_o  => c1541_iec_clk_o,

		sd_lba => sd_lba,
		sd_rd  => sd_rd,
		sd_wr  => sd_wr,
		sd_ack => sd_ack,
		sd_buff_addr => sd_buff_addr,
		sd_buff_dout => sd_buff_dout,
		sd_buff_din  => sd_buff_din,
		sd_buff_wr   => sd_buff_wr,

		led => led_disk
	);

	-- TAP playback controller
	cass_sense <= not tap_play;
	tap_play_btn <= status(17);

	process(clk_c64, reset_n)
	begin
		if reset_n = '0' then
			tap_play_addr <= '0' & X"200000";
			tap_last_addr <= '0' & X"200000";
			tap_play <= '0';
			tap_reset <= '1';
			tap_mem_ce <= '0';
		elsif rising_edge(clk_c64) then
			tap_reset <= '0';
			if ioctl_download = '1' and ioctl_index = x"42" then
				tap_play <= '0';
				tap_play_addr <= '0' & X"200000";
				tap_last_addr <= ioctl_load_addr;
				tap_reset <= '1';
				if ioctl_addr = x"00000C" and ioctl_wr = '1' then
					tap_mode <= ioctl_data(0);
				end if;
			end if;

			tap_play_btnD <= tap_play_btn;
			if tap_play_btnD = '0' and tap_play_btn = '1' then
				tap_play <= not tap_play;
			end if;

			if tap_fifo_error = '1' then tap_play <= '0'; end if;

			iec_cycle_rD <= iec_cycle;
			tap_wrreq <= '0';
			if iec_cycle = '0' and iec_cycle_rD = '1' and
			  ioctl_download = '0' and tap_play_addr /= tap_last_addr and tap_wrfull = '0' then
				tap_play_addr <= tap_play_addr + 1;
				tap_mem_ce <= '1';
			end if;
			if iec_cycle = '1' and iec_cycle_rD = '1' and tap_mem_ce = '1' then
				tap_mem_ce <= '0';
				tap_wrreq <= '1';
			end if;
		end if;
	end process;

	c1530 : entity work.c1530
	port map(
		clk32 => clk_c64,
		restart_tape => tap_reset,
		wav_mode => '0',
		tap_mode1 => tap_mode,
		host_tap_in => c64_data_in,
		host_tap_wrreq => tap_wrreq,
		tap_fifo_wrfull => tap_wrfull,
		tap_fifo_error => tap_fifo_error,
		play => not cass_motor and not tap_reset,
		do => cass_do
	);

	comp_sync : entity work.composite_sync
	port map(
		clk32 => clk_c64,
		hsync => hsync,
		vsync => vsync,
		ntsc  => ntsc_init_mode,
		hsync_out => hsync_out,
		vsync_out => vsync_out,
		blank => blank
	);

	c64_r <= (others => '0') when blank = '1' else std_logic_vector(r(7 downto 2));
	c64_g <= (others => '0') when blank = '1' else std_logic_vector(g(7 downto 2));
	c64_b <= (others => '0') when blank = '1' else std_logic_vector(b(7 downto 2));
	
	scanlines <= status(10 downto 9);
	hq2x <= status(9) xor status(8);
	ce_pix_actual <= ce_4 when hq2x160='1' else ce_8;
	
	process(clk_c64)
	begin
		if rising_edge(clk_c64) then
			if((old_vsync = '0') and (vsync_out = '1')) then
				if(status(10 downto 8)="010") then
					hq2x160 <= '1';
				else
					hq2x160 <= '0';
				end if;
			end if;
			old_vsync <= vsync_out;
		end if;
	end process;

	vmixer : video_mixer
	port map (
		clk_sys => clk_ram,
		ce_pix  => ce_8,
		ce_pix_actual => ce_pix_actual,

		SPI_SCK => SPI_SCK, 
		SPI_SS3 => SPI_SS3,
		SPI_DI => SPI_DI,

		scanlines => scanlines,
		scandoubler_disable => tv15Khz_mode,
		hq2x => hq2x,
		ypbpr => ypbpr,
		ypbpr_full => '1',

		R => c64_r,
		G => c64_g,
		B => c64_b,
		HSync => hsync_out,
		VSync => vsync_out,
		line_start => '0',
		mono => '0',

		VGA_R => VGA_R,
		VGA_G => VGA_G,
		VGA_B => VGA_B,
		VGA_VS => VGA_VS,
		VGA_HS => VGA_HS
	);

end struct;
