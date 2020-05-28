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
use work.mist.ALL;

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
   SPI_SS4    : in    std_logic;
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

constant CONF_STR : string := 
	"C64;;"&
	"S,D64,Mount Disk;"&
	"F,PRGTAPCRT,Load;"& --2
	"F,ROM,Load;"& --3
--	"F,T64,Load File;"&--6
	"TH,Play/Stop TAP;"&
	"OI,Tape sound,Off,On;"&
	"OG,Disk Write,Enable,Disable;"&
	"O2,Video standard,PAL,NTSC;"&
	"O89,Scandoubler Fx,None,CRT 25%,CRT 50%,CRT 75%;"&
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

-- constants for ioctl_index 
constant FILE_BOOT : std_logic_vector(7 downto 0) := x"00";      -- ROM files sent at boot time
constant FILE_PRG  : std_logic_vector(7 downto 0) := x"02";
constant FILE_TAP  : std_logic_vector(7 downto 0) := x"42";
constant FILE_CRT  : std_logic_vector(7 downto 0) := x"82";
constant FILE_ROM  : std_logic_vector(7 downto 0) := x"03";

component data_io 
generic
(
	ROM_DIRECT_UPLOAD : boolean := true
);
port
(
	clk_sys			  : in std_logic;
	SPI_SCK, SPI_SS2, SPI_SS4, SPI_DI, SPI_DO :in std_logic;
	clkref_n          : in  std_logic := '0';
	ioctl_download    : out std_logic;
	ioctl_index       : out std_logic_vector(7 downto 0);
	ioctl_wr          : out std_logic;
	ioctl_addr        : out std_logic_vector(24 downto 0);
	ioctl_dout        : out std_logic_vector(7 downto 0)
);
end component data_io;

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
	signal idle0: std_logic;
	signal idle: std_logic;
	signal ces: std_logic_vector(3 downto 0);
	signal mist_cycle: std_logic;
	signal mist_cycle_wr: std_logic;
	signal mist_cycleD: std_logic;
	signal mist_cycle_rD: std_logic;
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
	signal ioctl_download: std_logic;

	signal prg_reg_update: std_logic;
	signal prg_start: std_logic_vector(15 downto 0);
	signal prg_end: std_logic_vector(15 downto 0);
	signal prg_data: std_logic_vector(7 downto 0);

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
	
	signal c64_r  : std_logic_vector(5 downto 0);
	signal c64_g  : std_logic_vector(5 downto 0);
	signal c64_b  : std_logic_vector(5 downto 0);

	signal status         : std_logic_vector(31 downto 0);
  
	-- status(1) and status(12) are not used
	signal st_tape_sound       : std_logic;                    -- status(18)
	signal st_tap_play_btn     : std_logic;                    -- status(17)
	signal st_disk_readonly    : std_logic;                    -- status(16)
	signal st_sid_mode         : std_logic_vector(2 downto 0); -- status(15 downto 13)
	signal st_c64gs            : std_logic;                    -- status(11)
	signal st_scandoubler_fx   : std_logic_vector(1 downto 0); -- status(9 downto 8)
	signal st_user_port_uart   : std_logic;                    -- status(7)
	signal st_audio_filter_off : std_logic;                    -- status(6)
	signal st_detach_cartdrige : std_logic;                    -- status(5)
	signal st_cia_mode         : std_logic;                    -- status(4)
	signal st_swap_joystick    : std_logic;                    -- status(3)
	signal st_ntsc             : std_logic;                    -- status(2)
	signal st_reset            : std_logic;                    -- status(0)

	signal sd_lba         : std_logic_vector(31 downto 0);
	signal sd_rd          : std_logic_vector(1 downto 0);
	signal sd_wr          : std_logic_vector(1 downto 0);
	signal sd_ack         : std_logic;
	signal sd_ack_conf    : std_logic;
	signal sd_conf        : std_logic;
	signal sd_sdhc        : std_logic;
	signal sd_buff_addr   : std_logic_vector(8 downto 0);
	signal sd_buff_dout   : std_logic_vector(7 downto 0);
	signal sd_buff_din    : std_logic_vector(7 downto 0);
	signal sd_buff_wr     : std_logic;
	signal sd_change      : std_logic_vector(1 downto 0);
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
	signal mouse_flags  : std_logic_vector(7 downto 0);
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
	signal no_csync       : std_logic;
	signal ntsc_init_mode : std_logic := '0';
	signal ntsc_init_mode_d: std_logic;
	signal ntsc_init_mode_d2: std_logic;
	signal ntsc_init_mode_d3: std_logic;

	alias  c64_addr_int : unsigned is unsigned(c64_addr);
	alias  c64_data_in_int   : unsigned is unsigned(c64_data_in);
	signal c64_data_in16: std_logic_vector(15 downto 0);
	alias  c64_data_out_int   : unsigned is unsigned(c64_data_out);

	signal rom_ce : std_logic;
	signal c64_rom_addr : unsigned(15 downto 0);

	signal clk_c64 : std_logic;	-- 31.527mhz (PAL), 32.727mhz(NTSC) clock source
	signal clk_ram : std_logic; -- 2 x clk_c64
	signal clk32   : std_logic; -- 32mhz
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
	signal cass_read   : std_logic;
	
	signal tap_mem_ce     : std_logic;
	signal tap_play_addr  : std_logic_vector(24 downto 0);
	signal tap_last_addr  : std_logic_vector(24 downto 0);	
	signal tap_reset      : std_logic;
	signal tap_wrreq      : std_logic;
	signal tap_wrfull     : std_logic;
	signal tap_fifo_error : std_logic;
	signal tap_version    : std_logic;
	signal tap_playstop_key : std_logic;

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
	signal erase_cartram    : std_logic := '0';
	signal force_erase      : std_logic;
	signal mem_ce           : std_logic;
	
	signal uart_rxD         : std_logic;
	signal uart_rxD2        : std_logic;

	-- sdram layout 
	constant C64_MEM_START : std_logic_vector(24 downto 0) := '0' & X"000000"; -- normal C64 RAM
	constant C64_ROM_START : std_logic_vector(24 downto 0) := '0' & X"0F0000"; -- kernal/basic ROM
	constant CRT_MEM_START : std_logic_vector(24 downto 0) := '0' & X"100000"; -- cartridges
	constant TAP_MEM_START : std_logic_vector(24 downto 0) := '0' & X"200000"; -- .tap files 
	
begin

	-- 1541/tape activity led
	LED <= not ioctl_download and not led_disk and cass_motor;

	-- use iec and the first set of idle cycles for mist access
	mist_cycle <= '1' when ces = "1011" or idle0 = '1' else '0'; 

	sd_sdhc <= '1';
	sd_conf <= '0';
	-- User io
	user_io_d : user_io
	generic map (
		STRLEN => CONF_STR'length,
		ROM_DIRECT_UPLOAD => true,
		PS2DIV => 1000
	)
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
		no_csync => no_csync,

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

	st_tape_sound       <= status(18);
	st_tap_play_btn     <= status(17);
	st_disk_readonly    <= status(16);
	st_sid_mode         <= status(15 downto 13);
	st_c64gs            <= status(11);
	st_scandoubler_fx   <= status(9 downto 8);
	st_user_port_uart   <= status(7);
	st_audio_filter_off <= status(6);
	st_detach_cartdrige <= status(5);
	st_cia_mode         <= status(4);
	st_swap_joystick    <= status(3);
	st_ntsc             <= status(2);
	st_reset            <= status(0);

	data_io_d: data_io
	port map (
		clk_sys => clk_c64,
		SPI_SCK => SPI_SCK,
		SPI_SS2 => SPI_SS2,
		SPI_SS4 => SPI_SS4,
		SPI_DI => SPI_DI,
		SPI_DO => SPI_DO,

		ioctl_download => ioctl_download,
		ioctl_index => ioctl_index,
		ioctl_wr => ioctl_wr,
		ioctl_addr => ioctl_addr,
		ioctl_dout => ioctl_data
	);

	cart_loading <= '1' when ioctl_download = '1' and ioctl_index = FILE_CRT else '0';

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
	joyA_c64 <= joyB_int when st_swap_joystick='1' else joyA_int;
	joyB_c64 <= joyA_int when st_swap_joystick='1' else joyB_int;

	sdram_addr <= std_logic_vector(unsigned(C64_ROM_START) + c64_rom_addr) when mist_cycle = '0' and rom_ce = '0' else
	              c64_addr_temp when mist_cycle='0' else
	              ioctl_ram_addr when prg_reg_update = '1' or ioctl_download = '1' or erasing = '1' else
	              tap_play_addr;
	sdram_data_out <= c64_data_out when mist_cycle='0' else ioctl_ram_data;

	-- ram_we and rom_ce are active low
	sdram_ce <= (mem_ce or not rom_ce) when mist_cycle='0' else mist_cycle_wr or tap_mem_ce;
	sdram_we <= not ram_we when mist_cycle='0' else mist_cycle_wr;

	process(clk_c64)
	begin
		if rising_edge(clk_c64) then

			old_download <= ioctl_download;
			mist_cycleD <= mist_cycle;
			cart_hdr_wr <= '0';

			-- prepare mist cycle write
			if mist_cycle = '0' and mist_cycle_wr = '0' and ioctl_ram_wr = '1' then
				ioctl_ram_wr <= '0';
				ioctl_ram_addr <= ioctl_load_addr;
				ioctl_load_addr <= ioctl_load_addr + 1;
				if erasing = '1' then
					-- fill RAM with 64 bytes 0, 64 bytes ff
					-- same as VICE uses
					-- Freeload and probably some more code depend on some kind of pattern
					ioctl_ram_data  <= (others => ioctl_load_addr(6));
				elsif prg_reg_update = '1' then
					ioctl_ram_data <= prg_data;
				else
					ioctl_ram_data <= ioctl_data;
				end if;
				mist_cycle_wr <= '1';
			end if;
			-- second mist cycle - SDRAM data written, disable WE on the next
			if mist_cycle = '1' and mist_cycleD = '1' and mist_cycle_wr = '1' then
				mist_cycle_wr <= '0';
			end if;

			if ioctl_wr='1' then
				if ioctl_index = FILE_BOOT or ioctl_index = FILE_ROM then
					if ioctl_addr = 0 then
						ioctl_load_addr <= C64_ROM_START;
					end if;
					if ioctl_addr(24 downto 14) = 0 then
						ioctl_ram_wr <= '1';
					end if;
				end if;

				if ioctl_index = FILE_PRG then
					if ioctl_addr = 0 then
						ioctl_load_addr(7 downto 0) <= ioctl_data;
						prg_start(7 downto 0) <= ioctl_data;
					elsif(ioctl_addr = 1) then
						ioctl_load_addr(24 downto 8) <= '0'&x"00"&ioctl_data;
						prg_start(15 downto 8) <= ioctl_data;
					else
						ioctl_ram_wr <= '1';
					end if;
				end if;

				if ioctl_index = FILE_CRT then -- e0(MAX)
					if ioctl_addr = 0 then
						ioctl_load_addr <= CRT_MEM_START;
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

				if ioctl_index = FILE_TAP then
					if ioctl_addr = 0 then
						ioctl_load_addr <= TAP_MEM_START;
						ioctl_ram_data <= ioctl_data;
					end if;
					ioctl_ram_wr <= '1';
				end if;

			end if;

			-- PRG download finished, start updating system variables
			if old_download ='1' and ioctl_download = '0' and ioctl_index = FILE_PRG then
				ioctl_load_addr <= (others => '0');
				prg_end <= ioctl_ram_addr(15 downto 0);
				prg_reg_update <= '1';
			end if;

			-- PRG system variable updating control
			if prg_reg_update = '1' and mist_cycle = '1' and mist_cycleD = '1' then
				case ioctl_load_addr(7 downto 0) is
				when x"2b"|x"ac" => prg_data <= prg_start(7 downto 0); ioctl_ram_wr <= '1';
				when x"2c"|x"ad" => prg_data <= prg_start(15 downto 8); ioctl_ram_wr <= '1';
				when x"2d"|x"2f"|x"31"|x"ae" => prg_data <= prg_end(7 downto 0); ioctl_ram_wr <= '1';
				when x"2e"|x"30"|x"32"|x"af" => prg_data <= prg_end(15 downto 8); ioctl_ram_wr <= '1';
				when others => ioctl_load_addr <= ioctl_load_addr + 1;
				end case;

				-- finish at $100
				if ioctl_load_addr(15 downto 0) = x"0100" then
					prg_reg_update <= '0';
				end if;
			end if;

			-- cart added
			if old_download /= ioctl_download and ioctl_index = FILE_CRT then
				cart_attached <= old_download;
			end if;

			-- cart removed
			if st_detach_cartdrige='1' or buttons(1)='1' then
				cart_attached <= '0';
				erase_cartram <= '1';
			end if;

			-- start RAM erasing
			if erasing='0' and force_erase = '1' then
				erasing <='1';
				ioctl_load_addr <= (others => '0');
			end if;

			-- RAM erasing control
			if erasing = '1' and mist_cycle = '1' and mist_cycleD = '1' then
					-- erase up to 0xFFFF
					if ioctl_load_addr(16 downto 0) = '1'&x"0000" then
						if ioctl_load_addr < CRT_MEM_START and erase_cartram = '1' then
							ioctl_load_addr <= CRT_MEM_START;
							ioctl_ram_wr <= '1';
						else
							erasing <= '0';
							erase_cartram <= '0';
						end if;
					else
						ioctl_ram_wr <= '1';
					end if;
			end if;

		end if;
	end process;

	c1541rom_wr <= ioctl_wr when (ioctl_index = FILE_BOOT or ioctl_index = FILE_ROM) and (ioctl_addr(14) = '1') and (ioctl_download = '1') else '0';

	-- UART_RX synchronizer
	process(clk_c64)
	begin
		if rising_edge(clk_c64) then
			uart_rxD <= UART_RX;
			uart_rxD2 <= uart_rxD;
		end if;
	end process;

	ntsc_init_mode <= st_ntsc;

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
			if st_reset = '1' or pll_locked = '0' then
				reset_counter <= 1000000;
				reset_n <= '0';
			elsif buttons(1)='1' or st_detach_cartdrige='1' or reset_key = '1' or reset_crt='1' or
			(ioctl_download='1' and (ioctl_index = FILE_BOOT or ioctl_index = FILE_ROM or ioctl_index = FILE_CRT)) then 
				reset_counter <= 255;
				reset_n <= '0';
			elsif erasing ='1' then
				force_erase <= '0';
			elsif reset_counter = 0 then
				reset_n <= '1';
			elsif ioctl_download = '0' then
				reset_counter <= reset_counter - 1;
				if reset_counter = 100 then
						force_erase <='1';
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

	audio_data_l_mix <= audio_data_l when st_tape_sound = '0' else
	                    audio_data_l + ((not (not cass_read or cass_write)) & "00000000000000");
--	                    (cass_read & "00000000000000000");

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
		kbd_clk => not ps2_clk,
		kbd_dat => ps2_dat,
		ramAddr => c64_addr_int,
		ramDataOut => c64_data_out_int,
		ramDataIn => c64_data_in_int,
		ramCE => ram_ce,
		ramWe => ram_we,
		romAddr => c64_rom_addr,
		romCE => rom_ce,
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
		idle0 => idle0, -- first set of idle cycles
		idle => idle, -- second set of idle cycles
		audio_data_l => audio_data_l,
		audio_data_r => audio_data_r,
		extfilter_en => not st_audio_filter_off,
		sid_mode => st_sid_mode,
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
		cia_mode => st_cia_mode,
		disk_num => open,

		cass_motor => cass_motor,
		cass_write => cass_write,
		cass_read  => cass_read,
		cass_sense => cass_sense,

		tap_playstop_key => tap_playstop_key,
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
	process (pa2_out, pb_out, joyC_c64, joyD_c64, uart_rxD2, st_user_port_uart, cass_motor)
	begin
		pa2_in <= pa2_out;
		if st_user_port_uart = '0' then
			-- Protovision 4 player interface
			flag2_n <= '1';
			UART_TX <= not cass_motor;
			pb_in(7 downto 6) <= pb_out(7 downto 6);
			if pb_out(7) = '1' then
				pb_in(3 downto 0) <= not joyC_c64(3 downto 0);
			else
				pb_in(3 downto 0) <= not joyD_c64(3 downto 0);
			end if;
			pb_in(4) <= not joyC_c64(4);
			pb_in(5) <= not joyD_c64(4);
		else
			-- UART
			pb_in(7 downto 1) <= pb_out(7 downto 1);
			flag2_n <= uart_rxD2;
			pb_in(0) <= uart_rxD2;
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

	disk_readonly <= st_disk_readonly;

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

	sd_rd(1) <= '0';
	sd_wr(1) <= '0';

	c1541_sd_inst : entity work.c1541_sd
	port map
	(
		clk32 => clk32,
		reset => c1541_reset,

		c1541rom_clk => clk_c64,
		c1541rom_addr => ioctl_addr(13 downto 0),
		c1541rom_data => ioctl_data,
		c1541rom_wr => c1541rom_wr,

		disk_change => sd_change(0),
		disk_num  => (others => '0'), -- always 0 on MiST, the image is selected by the OSD menu
		disk_readonly => disk_readonly,

		iec_atn_i  => c1541_iec_atn_i,
		iec_data_i => c1541_iec_data_i,
		iec_clk_i  => c1541_iec_clk_i,

		--iec_atn_o  => c1541_iec_atn_o,
		iec_data_o => c1541_iec_data_o,
		iec_clk_o  => c1541_iec_clk_o,

		sd_lba => sd_lba,
		sd_rd  => sd_rd(0),
		sd_wr  => sd_wr(0),
		sd_ack => sd_ack,
		sd_buff_addr => sd_buff_addr,
		sd_buff_dout => sd_buff_dout,
		sd_buff_din  => sd_buff_din,
		sd_buff_wr   => sd_buff_wr,

		led => led_disk
	);

	-- TAP playback controller	
	process(clk_c64, reset_n)
	begin
		if reset_n = '0' then
			tap_play_addr <= TAP_MEM_START;
			tap_last_addr <= TAP_MEM_START;			
			tap_reset <= '1';
			tap_mem_ce <= '0';
		elsif rising_edge(clk_c64) then
			tap_reset <= '0';
			if ioctl_download = '1' and ioctl_index = FILE_TAP then				
				tap_play_addr <= TAP_MEM_START;
				tap_last_addr <= ioctl_load_addr;
				tap_reset <= '1';
				if ioctl_addr = x"00000C" and ioctl_wr = '1' then
					tap_version <= ioctl_data(0);
				end if;
			end if;

--			if tap_fifo_error = '1' then tap_play <= '0'; end if;

			mist_cycle_rD <= mist_cycle;
			tap_wrreq <= '0';
			if mist_cycle = '0' and mist_cycle_rD = '1' and
			  ioctl_download = '0' and tap_play_addr /= tap_last_addr and tap_wrfull = '0' then
				tap_mem_ce <= '1';
			end if;
			-- second mist cycle - SDRAM data ready on the next
			if mist_cycle = '1' and mist_cycle_rD = '1' and tap_mem_ce = '1' then
				tap_mem_ce <= '0';
				tap_wrreq <= '1';
				tap_play_addr <= tap_play_addr + 1;
			end if;
		end if;
	end process;

	c1530 : entity work.c1530
	port map(
		clk32 => clk_c64,
		restart_tape => tap_reset,
		wav_mode => '0',
		tap_version => tap_version,
		host_tap_in => c64_data_in,
		host_tap_wrreq => tap_wrreq,
		tap_fifo_wrfull => tap_wrfull,
		tap_fifo_error => tap_fifo_error,		
		cass_read  => cass_read,
		cass_write => cass_write,
		cass_motor => cass_motor,
		cass_sense => cass_sense,
		osd_play_stop_toggle => st_tap_play_btn or tap_playstop_key,
		ear_input => uart_rxD2 and not st_user_port_uart
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

	mist_video : work.mist.mist_video
	generic map (
		SD_HCNT_WIDTH => 10,
		COLOR_DEPTH => 6,
		OSD_COLOR => "011",
		OSD_X_OFFSET => "00"&x"10",
		OSD_AUTO_CE => false
	)
	port map (
		clk_sys     => clk_c64,
		scanlines   => st_scandoubler_fx,
		scandoubler_disable => tv15Khz_mode,
		ypbpr       => ypbpr,
		no_csync    => no_csync,
		rotate      => "00",
		blend       => '0',

		SPI_SCK     => SPI_SCK,
		SPI_SS3     => SPI_SS3,
		SPI_DI      => SPI_DI,

		HSync       => not hsync_out,
		VSync       => not vsync_out,
		R           => c64_r,
		G           => c64_g,
		B           => c64_b,

		VGA_HS      => VGA_HS,
		VGA_VS      => VGA_VS,
		VGA_R       => VGA_R,
		VGA_G       => VGA_G,
		VGA_B       => VGA_B
	);

end struct;
