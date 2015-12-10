-- ZX Spectrum for MiST board
--
-- Copyright (c) 2009-2011 Mike Stirling
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- * Redistributions of source code must retain the above copyright notice,
--   this list of conditionand the following disclaimer.
--
-- * Redistributions in synthesized form must reproduce the above copyright
--   notice, this list of conditions and the following disclaimer in the
--   documentation and/or other materials provided with the distribution.
--
-- * Neither the name of the author nor the names of other contributors may
--   be used to endorse or promote products derived from this software without
--   specific prior written agreement from the author.T
--
-- * License is granted for non-commercial use only.  A fee may not be charged
--   for redistributions as source code or in synthesized/hardware form without 
--   specific prior written agreement from the author.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- Sinclair ZX Spectrum
--
-- Terasic DE1 top-level
--
-- (C) 2011 Mike Stirling

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Generic top-level entity for Altera DE1 board
entity spectrum_mist is
generic (
	-- Model to generate
	-- 0 = 48 K
	-- 1 = 128 K
	-- 2 = +2A/+3
	MODEL				:	integer := 1
); 

port (
	-- Clocks
	CLOCK_27	:	in	std_logic_vector(1 downto 0);
		
	-- LED
	LED		:	out	std_logic;
	
	-- VGA
	VGA_R		:	out	std_logic_vector(5 downto 0);
	VGA_G		:	out	std_logic_vector(5 downto 0);
	VGA_B		:	out	std_logic_vector(5 downto 0);
	VGA_HS		:	out	std_logic;
	VGA_VS		:	out	std_logic;
	
	-- Serial
--	UART_RXD	:	in	std_logic;
--	UART_TXD	:	out	std_logic;
	
	-- SDRAM
	SDRAM_A		:	out		std_logic_vector(12 downto 0);
	SDRAM_DQ		:	inout		std_logic_vector(15 downto 0);
	SDRAM_DQML	:  out 		std_logic;
	SDRAM_DQMH	:  out 		std_logic;
	SDRAM_nWE	:  out 		std_logic;
	SDRAM_nCAS	:  out 		std_logic;
	SDRAM_nRAS	:  out 		std_logic;
	SDRAM_nCS	:  out 		std_logic;
	SDRAM_BA		:  out 		std_logic_vector(1 downto 0);
	SDRAM_CLK	:  out 		std_logic;
	SDRAM_CKE	:  out 		std_logic;

   -- AUDIO
   AUDIO_L         : out std_logic;
   AUDIO_R         : out std_logic;

   -- SPI interface to io controller
   SPI_SCK         : in std_logic;
   SPI_DO          : inout std_logic;
   SPI_DI          : in std_logic;
   SPI_SS2         : in std_logic;
   SPI_SS3         : in std_logic;
	SPI_SS4         : in std_logic;
   CONF_DATA0      : in std_logic
);
end entity;
architecture rtl of spectrum_mist is

--------------------------------
-- PLL
-- 27 MHz input
-- 56 MHz sdram controller clock
-- 56 MHz sdram clock (-2.5 ns phase shifted)
--------------------------------

component pll_main IS
	PORT
	(
		areset		: IN STD_LOGIC  := '0';
		inclk0		: IN STD_LOGIC  := '0';
		c0				: OUT STD_LOGIC ;
		c1				: OUT STD_LOGIC ;
		locked		: OUT STD_LOGIC 
	);
end component;

-------------------
-- Clock enables
-------------------

component clocks is
port (
	-- 28 MHz master clock
	CLK				:	in std_logic;
	-- Master reset
	nRESET			:	in std_logic;
	-- CPU requests bus
	MREQ				:	in std_logic;

	-- 1.75 MHz clock enable for sound
	CLKEN_PSG		:	out	std_logic;
	-- 3.5 MHz clock enable (1 in 8)
	CLKEN_CPU		:	out std_logic;
	-- 1.75 MHz clock enable (1 in 8)
	CLKEN_MEM		:	out std_logic;
	-- 1.75 MHz clock enable (1 in 8)
	CLKEN_DIO		:	out std_logic;
	-- 14 MHz clock enable (out of phase with CPU)
	CLKEN_VID		:	out std_logic;
	-- reference signal to sync video memory access to
	VID_MEM_SYNC	:	out std_logic;
	-- SDRAM reference clock to sync onto
	CLK_REF		   :	out std_logic
	);
end component;

---------
-- SDRAM controller
---------

component sdram is
port (
   -- interface to the MT48LC16M16 chip
   sd_data		: 	inout std_logic_vector(15 downto 0);
   sd_addr  	: 	out 	std_logic_vector(12 downto 0);
   sd_dqm  		: 	out 	std_logic_vector(1 downto 0);
   sd_cs      	: 	out 	std_logic;
   sd_ba  		: 	out 	std_logic_vector(1 downto 0);
   sd_we      	: 	out 	std_logic;
   sd_ras     	: 	out 	std_logic;
   sd_cas     	: 	out 	std_logic;
	
   -- system interface
   clk         :  in 	std_logic;
   clkref      :  in 	std_logic;
	init       	:  in		std_logic;
	
   -- cpu/chipset interface
   din         : 	in		std_logic_vector(7 downto 0);
   dout        : 	out	std_logic_vector(7 downto 0);
   addr        : 	in		std_logic_vector(24 downto 0);
	we       	:  in		std_logic;
	oe       	:  in		std_logic
	);
end component;

---------
-- embedded ROM
---------

component rom128 is
port (
	address    	: 	in		std_logic_vector(14 downto 0);
	clock			: 	in 	std_logic;
	q        	: 	out	std_logic_vector(7 downto 0)
	);
end component;

---------
-- User IO
---------

-- config string used by the io controller to fill the OSD
constant CONF_STR : string := "SPECTRUM;CSW;T1,Reset;T2,Trigger NMI;O3,Scanlines,Off,On";

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

component user_io
generic ( STRLEN : integer := 0 );
port (
      SPI_CLK, SPI_SS_IO, SPI_MOSI :in std_logic;
      SPI_MISO : out std_logic;
      conf_str : in std_logic_vector(8*STRLEN-1 downto 0);

      switches : out std_logic_vector(1 downto 0);
      buttons : out std_logic_vector(1 downto 0);
      scandoubler_disable : out std_logic;

      joystick_0 : out std_logic_vector(7 downto 0);
      joystick_1 : out std_logic_vector(7 downto 0);
      joystick_analog_0 : out std_logic_vector(15 downto 0);
      joystick_analog_1 : out std_logic_vector(15 downto 0);
      status : out std_logic_vector(7 downto 0);

		sd_lba : in std_logic_vector(31 downto 0);
		sd_rd : in std_logic;
		sd_wr : in std_logic;
		sd_ack : out std_logic;
		sd_conf : in std_logic;
		sd_sdhc : in std_logic;
		sd_dout : out std_logic_vector(7 downto 0);
		sd_dout_strobe : out std_logic;
		sd_din : in std_logic_vector(7 downto 0);
		sd_din_strobe : out std_logic;

      ps2_clk : in std_logic;
      ps2_kbd_clk : out std_logic;
      ps2_kbd_data : out std_logic
);
end component user_io;

---------
-- sd card
---------

component sd_card
   port (  io_lba       : out std_logic_vector(31 downto 0);
           io_rd         : out std_logic;
           io_wr         : out std_logic;
           io_ack        : in std_logic;
           io_sdhc       : out std_logic;
           io_conf       : out std_logic;
           io_din        : in std_logic_vector(7 downto 0);
           io_din_strobe : in std_logic;
           io_dout       : out std_logic_vector(7 downto 0);
           io_dout_strobe : in std_logic;
           allow_sdhc    : in std_logic;
                          
           sd_cs                :       in std_logic;
           sd_sck       :       in std_logic;
           sd_sdi       :       in std_logic;
           sd_sdo       :       out std_logic
  );
  end component sd_card;

---------
-- Data IO
---------

component data_io
  port ( sck, ss, sdi 	:	in std_logic;

			-- download info
			downloading  	:  out std_logic;
			size				:  out std_logic_vector(24 downto 0);
			index				:  out std_logic_vector(4 downto 0);
  
			-- external ram interface
			clk				:	in std_logic;
			wr					:  out std_logic;
			a					:  out std_logic_vector(24 downto 0);
			d					:  out std_logic_vector(7 downto 0)
);
end component data_io;

---------
-- Tape
---------

component tape
  generic ( ADDR_WIDTH : integer := 16);
  port (
			clk				:	in std_logic;
			reset				:	in std_logic;
			iocycle			:	in std_logic;
			audio_out  		:  out std_logic;
			downloading  	:  in std_logic;
			size				:  in std_logic_vector(ADDR_WIDTH-1 downto 0);
			
			-- external ram interface
			rd					:  out std_logic;
			a					:  out std_logic_vector(ADDR_WIDTH-1 downto 0);
			d					:  in std_logic_vector(7 downto 0)
);
end component tape;

---------
-- OSD
---------

component osd
  generic ( OSD_COLOR : integer );
  port ( pclk 			: in std_logic;
		sck, sdi, ss 	: in std_logic;

		-- VGA signals coming from core
      red_in 			: in std_logic_vector(5 downto 0);
      green_in 		: in std_logic_vector(5 downto 0);
      blue_in 			: in std_logic_vector(5 downto 0);
      hs_in 			: in std_logic;
      vs_in 			: in std_logic;

      -- VGA signals going to video connector
      red_out		 	: out std_logic_vector(5 downto 0);
      green_out 		: out std_logic_vector(5 downto 0);
      blue_out 		: out std_logic_vector(5 downto 0);
      hs_out 			: out std_logic;
      vs_out 			: out std_logic
	);
end component osd;

---------
-- CPU
---------

component T80se is
	generic(
		Mode : integer := 0;    -- 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
		T2Write : integer := 0;  -- 0 => WR_n active in T3, /=0 => WR_n active in T2
		IOWait : integer := 1   -- 0 => Single cycle I/O, 1 => Std I/O cycle
	);
	port(
		RESET_n         : in  std_logic;
		CLK_n           : in  std_logic;
		CLKEN           : in  std_logic;
		WAIT_n          : in  std_logic;
		INT_n           : in  std_logic;
		NMI_n           : in  std_logic;
		BUSRQ_n         : in  std_logic;
		M1_n            : out std_logic;
		MREQ_n          : out std_logic;
		IORQ_n          : out std_logic;
		RD_n            : out std_logic;
		WR_n            : out std_logic;
		RFSH_n          : out std_logic;
		HALT_n          : out std_logic;
		BUSAK_n         : out std_logic;
		A               : out std_logic_vector(15 downto 0);
		DI              : in  std_logic_vector(7 downto 0);
		DO              : out std_logic_vector(7 downto 0)
	);
end component;

--------------
-- ULA port
--------------

component ula_port is
port (
	CLK		:	in	std_logic;
	nRESET	:	in	std_logic;
	
	-- CPU interface with separate read/write buses
	D_IN	:	in	std_logic_vector(7 downto 0);
	D_OUT	:	out	std_logic_vector(7 downto 0);
	ENABLE	:	in	std_logic;
	nWR		:	in	std_logic;
	
	BORDER_OUT	:	out	std_logic_vector(2 downto 0);
	EAR_OUT		:	out	std_logic;
	MIC_OUT		:	out std_logic;
	
	KEYB_IN		:	in 	std_logic_vector(4 downto 0);
	EAR_IN		:	in	std_logic	
	);
end component;

---------------
-- ULA video
---------------

component video is
port(
	-- Master clock (28 MHz)
	CLK			:	in std_logic;
	-- Video domain clock enable (14 MHz)
	CLKEN		:	in std_logic;
   -- Video memory cycle
	MEM_CYC	:	in std_logic;
	-- Master reset
	nRESET 		: 	in std_logic;

	-- Mode
	VGA			:	in std_logic;

	-- Memory interface
	VID_A		:	out	std_logic_vector(12 downto 0);
	VID_D_IN	:	in	std_logic_vector(7 downto 0);
	nVID_RD	:	out	std_logic;
	nWAIT		:	out	std_logic;
	
	-- IO interface
	BORDER_IN	:	in	std_logic_vector(2 downto 0);

	-- Video outputs
	R			:	out	std_logic_vector(3 downto 0);
	G			:	out	std_logic_vector(3 downto 0);
	B			:	out	std_logic_vector(3 downto 0);
	nVSYNC	:	out std_logic;
	nHSYNC	:	out std_logic;
	nCSYNC	:	out std_logic;
	nHCSYNC	:	out std_logic;
	SCANLINE	:	out std_logic;
	
	-- Interrupt to CPU (asserted for 32 T-states, 64 ticks)
	nIRQ		:	out	std_logic
);
end component;

--------------
-- Keyboard
--------------

component keyboard is
port (
	CLK			:	in	std_logic;
	nRESET		:	in	std_logic;

	-- PS/2 interface
	PS2_CLK		:	in	std_logic;
	PS2_DATA	:	in	std_logic;
	
	-- CPU address bus (row)
	A			:	in	std_logic_vector(15 downto 0);
	-- Column outputs to ULA
	KEYB		:	out	std_logic_vector(4 downto 0);
	
	F11 : out std_logic
	);
end component;

-----------
-- Sound
-----------

component YM2149 is
  port (
  -- data bus
  I_DA                : in  std_logic_vector(7 downto 0);
  O_DA                : out std_logic_vector(7 downto 0);
  O_DA_OE_L           : out std_logic;
  -- control
  I_A9_L              : in  std_logic;
  I_A8                : in  std_logic;
  I_BDIR              : in  std_logic;
  I_BC2               : in  std_logic;
  I_BC1               : in  std_logic;
  I_SEL_L             : in  std_logic;

  O_AUDIO             : out std_logic_vector(7 downto 0);
  -- port a
  I_IOA               : in  std_logic_vector(7 downto 0);
  O_IOA               : out std_logic_vector(7 downto 0);
  O_IOA_OE_L          : out std_logic;
  -- port b
  I_IOB               : in  std_logic_vector(7 downto 0);
  O_IOB               : out std_logic_vector(7 downto 0);
  O_IOB_OE_L          : out std_logic;
  --
  ENA                 : in  std_logic;
  RESET_L             : in  std_logic;
  CLK                 : in  std_logic
  );
end component;

component sigma_delta_dac is
  port (
	CLK			: in std_logic;
	RESET			: in std_logic;
   DACin			: in std_logic_vector(7 downto 0);
	DACout		: out std_logic
  );
end component;


-------------------
-- DIVMMC interface
-------------------

component divmmc is
port (
	clk		: in std_logic;
	reset_n	: in std_logic;
	clken		: in std_logic;

	-- Bus interface
	enable   : in std_logic;
	a			: in std_logic_vector(15 downto 0); 
	wr_n     : in std_logic;
	rd_n     : in std_logic;
	mreq_n   : in std_logic;
	m1_n     : in std_logic;
	din		: in std_logic_vector(7 downto 0);
	dout		: out std_logic_vector(7 downto 0);

	-- memory paging info
	paged_in : out std_logic;
	sram_page: out std_logic_vector(3 downto 0);
	mapram   : out std_logic;
	conmem   : out std_logic;
	
	-- SD card interface
	sd_cs		:	out	std_logic;
	sd_sck	:	out	std_logic;
	sd_mosi	:	out	std_logic;
	sd_miso	:	in		std_logic
	);
end component;
			
-------------
-- Signals
-------------

-- SDRAM interface
signal sdram_dqm     :  std_logic_vector(1 downto 0);
signal sdram_di		:	std_logic_vector(7 downto 0);
signal sdram_do		:	std_logic_vector(7 downto 0);
signal sdram_addr		:  std_logic_vector(24 downto 0);
signal sdram_we      :  std_logic;
signal sdram_oe      :  std_logic;

-- ZX spectrum video signals
signal zx_red : std_logic_vector(5 downto 0);
signal zx_green : std_logic_vector(5 downto 0);
signal zx_blue : std_logic_vector(5 downto 0);

-- signals from user_io
signal switches: std_logic_vector(1 downto 0);
signal buttons: std_logic_vector(1 downto 0);
signal joystickA: std_logic_vector(7 downto 0);
signal joystickB: std_logic_vector(7 downto 0);
signal status: std_logic_vector(7 downto 0);

-- TH extra
signal divmmc_lo_addr	:	std_logic_vector(18 downto 0);
signal divmmc_hi_addr	:	std_logic_vector(18 downto 0);
signal divmmc_addr	:	std_logic_vector(18 downto 0);
signal rom_addr		:	std_logic_vector(19 downto 0);
signal ram_addr		:	std_logic_vector(19 downto 0);
signal cpu_addr		:	std_logic_vector(20 downto 0);
signal vid_addr		:	std_logic_vector(18 downto 0);
signal cpu_cycle     :  std_logic;
signal rom_do        :  std_logic_vector(7 downto 0);
signal mem_do        :  std_logic_vector(7 downto 0);
signal ps2_clk       :  std_logic;
signal ps2_data      :  std_logic;
signal ioctl_wr		:  std_logic;
signal ioctl_addr		:  std_logic_vector(24 downto 0);
signal ioctl_data		:  std_logic_vector(7 downto 0);
signal ioctl_ram_wr  :  std_logic;
signal ioctl_cycle   :  std_logic;
signal ioctl_used    :  std_logic;
signal ioctl_ram_addr : std_logic_vector(24 downto 0);
signal ioctl_ram_data :  std_logic_vector(7 downto 0);
signal ioctl_size     : std_logic_vector(24 downto 0);
signal ioctl_index    : std_logic_vector(4 downto 0);
signal ioctl_download : std_logic;
signal tape_rd			:  std_logic;
signal tape_addr		:  std_logic_vector(24 downto 0);
signal tape_download : std_logic;
signal io_addr			:  std_logic_vector(24 downto 0);
signal audio			:  std_logic;
signal scandoubler_disable	: std_logic;
signal esxdos_downloaded : std_logic_vector(1 downto 0) := "00";
signal sd_lba 			: std_logic_vector(31 downto 0);
signal sd_rd 			: std_logic;
signal sd_wr 			: std_logic;
signal sd_ack 			: std_logic;
signal sd_conf 		: std_logic;
signal sd_sdhc 		: std_logic;
signal sd_dout 		: std_logic_vector(7 downto 0);
signal sd_dout_strobe : std_logic;
signal sd_din 			: std_logic_vector(7 downto 0);
signal sd_din_strobe : std_logic;
signal divmmc_paged_in : std_logic;
signal divmmc_sram_page: std_logic_vector(3 downto 0);
signal divmmc_mapram   : std_logic;
signal divmmc_conmem   : std_logic;
signal key_f11         : std_logic;

-- Master clock - 28 MHz
signal clk56      	:	std_logic;
signal pll_locked		:	std_logic;
signal clock			:	std_logic;
signal audio_clock	:	std_logic;
signal reset_n			:	std_logic;
signal clk14k_div		: 	unsigned(10 downto 0);
signal clk14k			:	std_logic;

-- Clock control
signal psg_clken		:	std_logic;
signal cpu_clken		:	std_logic;
signal mem_clken		:	std_logic;
signal dio_clken		:	std_logic;
signal vid_clken		:	std_logic;
signal clk_ref			:	std_logic;
signal vid_mem_sync	:	std_logic;

-- Address decoding
signal ula_enable		:	std_logic; -- all even IO addresses
signal rom_enable		:	std_logic; -- 0x0000-0x3FFF
signal ram_enable		:	std_logic; -- 0x4000-0xFFFF
-- 128K extensions
signal page_enable	:	std_logic; -- all odd IO addresses with A15 and A1 clear (and A14 set in +3 mode)
signal psg_enable		:	std_logic; -- all odd IO addresses with A15 set and A1 clear
-- +3 extensions
signal plus3_enable	:	std_logic; -- A15, A14, A13, A1 clear, A12 set.
-- MMC
signal divmmc_enable	:	std_logic; -- A7-A4 = "1110"
signal kempston_enable: std_logic; -- A7-A0 = "00011111"

-- 128K paging register (with default values for systems that don't have it)
signal page_reg_disable	:	std_logic := '1'; -- bit 5
signal page_rom_sel		:	std_logic := '0'; -- bit 4
signal page_shadow_scr	:	std_logic := '0'; -- bit 3
signal page_ram_sel		:	std_logic_vector(2 downto 0) := "000"; -- bits 2:0

-- +3 extensions (with default values for systems that don't have it)
signal plus3_printer_strobe	:	std_logic := '0'; -- bit 4
signal plus3_disk_motor	:	std_logic := '0'; -- bit 3
signal plus3_page		:	std_logic_vector(1 downto 0) := "00"; -- bits 2:1
signal plus3_special	:	std_logic := '0'; -- bit 0

-- RAM bank actually being accessed
signal ram_page			:	std_logic_vector(2 downto 0);

-- CPU signals
signal cpu_wait_n	:	std_logic;
signal cpu_irq_n	:	std_logic;
signal cpu_nmi_n	:	std_logic;
signal cpu_busreq_n	:	std_logic;
signal cpu_m1_n		:	std_logic;
signal cpu_mreq_n	:	std_logic;
signal cpu_ioreq_n	:	std_logic;
signal cpu_rd_n		:	std_logic;
signal cpu_wr_n		:	std_logic;
signal cpu_rfsh_n	:	std_logic;
signal cpu_halt_n	:	std_logic;
signal cpu_busack_n	:	std_logic;
signal cpu_a		:	std_logic_vector(15 downto 0);
signal cpu_di		:	std_logic_vector(7 downto 0);
signal cpu_do		:	std_logic_vector(7 downto 0);

-- ULA port signals
signal ula_do		:	std_logic_vector(7 downto 0);
signal ula_border	:	std_logic_vector(2 downto 0);
signal ula_ear_out	:	std_logic;
signal ula_mic_out	:	std_logic;
signal ula_ear_in	:	std_logic;
signal ula_rom_sel	:	std_logic;
signal ula_shadow_vid	:	std_logic;
signal ula_ram_page	:	std_logic_vector(2 downto 0);

-- ULA video signals
signal vid_a		:	std_logic_vector(12 downto 0);
signal vid_rd_n		:	std_logic;
signal vid_wait_n	:	std_logic;
signal vid_r_out	:	std_logic_vector(3 downto 0);
signal vid_g_out	:	std_logic_vector(3 downto 0);
signal vid_b_out	:	std_logic_vector(3 downto 0);
signal vid_vsync_n	:	std_logic;
signal vid_hsync_n	:	std_logic;
signal vid_csync_n	:	std_logic;
signal vid_hcsync_n	:	std_logic;
signal vid_irq_n	:	std_logic;
signal vid_scanline : std_logic;

-- Keyboard
signal keyb			:	std_logic_vector(4 downto 0);

-- Sound (PSG default values for systems that don't have it)
signal psg_do		:	std_logic_vector(7 downto 0) := "11111111";
signal psg_bdir		:	std_logic;
signal psg_bc1		:	std_logic;
signal psg_aout		:	std_logic_vector(7 downto 0) := "00000000";

-- DIVMMC interface
signal divmmc_do		:	std_logic_vector(7 downto 0);

signal divmmc_sclk	:	std_logic;
signal divmmc_mosi	:	std_logic;
signal divmmc_miso	:	std_logic;
signal divmmc_cs		:	std_logic;

signal esx_request 	:	std_logic := '0';

begin
	-- 28 MHz master clock
	pll: pll_main port map (
		'0',
		CLOCK_27(0),
		clk56,
		SDRAM_CLK,
		pll_locked
		);
		
	-- generate 28Mhz system clock from 56MHz main clock by dividing it by 2
	process(clk56)
	begin
		if rising_edge(clk56) then
			clock <= not clock;
		end if;
	end process;	
	
	-- Clock enable logic
	clken: clocks port map (
		clock,
		pll_locked,
		not cpu_mreq_n or not cpu_ioreq_n,
		psg_clken,
		cpu_clken,
		mem_clken,
		dio_clken,
		vid_clken,
		vid_mem_sync,
		clk_ref
		);
		
	-- SDRAM
	sdr: sdram port map (
		-- RAM chip
		SDRAM_DQ, SDRAM_A, sdram_dqm,
		SDRAM_nCS, SDRAM_BA, SDRAM_nWE, SDRAM_NRAS, SDRAM_nCAS,
		
		-- System
		clk56, clk_ref, not pll_locked,
		
		-- cpu interface
		sdram_di, sdram_do,
		sdram_addr, sdram_we, sdram_oe
	);
	SDRAM_DQMH <= sdram_dqm(1);
	SDRAM_DQML <= sdram_dqm(0);
	-- SDRAM clock always enabled		
	SDRAM_CKE <= '1';
	
	-- embedded rom
	rom: rom128 port map (
		rom_addr(14 downto 0),
		psg_clken,    -- psg_clken is in the middle of a cpu cycle
		rom_do
	);
	
	-- include the io controller. This controller differs from the one
	-- in the zx01 because it does not come with its own embedded dual port ram.
	-- Instead it provides signals to connect to an external ram
	data_io_I: data_io 	
	port map (
		sck 	=> 	SPI_SCK,
		ss    =>  	SPI_SS2,
		sdi	=>		SPI_DI,

		downloading => ioctl_download,
		size        => ioctl_size,
		index       => ioctl_index,

		-- ram interface
		clk 	=> 	clock,
		wr    =>    ioctl_wr,
		a     =>		ioctl_addr,
		d     =>		ioctl_data
	);

	process(ioctl_download)
	begin
		if rising_edge(ioctl_download) then
			if(ioctl_index = "00000") then
				esxdos_downloaded(0) <= '1';
			end if;
		end if;
	end process;	
	

	-- tape download comes from OSD entry 1
	tape_download <= '1' when (ioctl_index = "00001") AND (ioctl_download = '1') else '0';
	tape_I: tape 	
	generic map (ADDR_WIDTH => 25)
	port map (
		clk 		=> 	clock,
		reset    =>    not reset_n,
		iocycle 	=> 	ioctl_cycle,
		
		audio_out => 	ula_ear_in,

		downloading => tape_download,
		size        => ioctl_size,

		-- ram interface
		rd    =>    tape_rd,
		a     =>		tape_addr,
		d     =>		sdram_do
	);

	-- use led as the sd card access led
	LED <= divmmc_cs;
	
	process(clock)
	begin
		if rising_edge(clock) then
			if dio_clken = '1' and ioctl_cycle = '0' then
				if ioctl_ram_wr = '1' then
					ioctl_ram_wr <= '0';
					ioctl_used <= '1';
					ioctl_ram_addr <= ioctl_addr;
					ioctl_ram_data <= ioctl_data;
				else	
					ioctl_used <= '0';
				end if;
			end if;
				
			if ioctl_wr = '1' then
				-- io controller sent a new byte. Store it until it can be
				-- saved in RAM
				ioctl_ram_wr <= '1';
			end if;
		end if;
	end process;	
		
	-- generate ~14Khz ps2 clock from 28MHz
	process(clock)
	begin
		if rising_edge(clock) then
			clk14k_div <= clk14k_div + 1;
		end if;
		
		clk14k <= clk14k_div(10);
	end process;	
	
	-- User io
	user_io_d : user_io
	generic map (STRLEN => CONF_STR'length)
	port map (
		SPI_CLK => SPI_SCK,
		SPI_SS_IO => CONF_DATA0,
		SPI_MISO => SPI_DO,
		SPI_MOSI => SPI_DI,
		
		conf_str => to_slv(CONF_STR),
			
		status => status,
		joystick_0 => joystickA,
		joystick_1 => joystickB,
		switches => switches,
		buttons => buttons,
		scandoubler_disable => scandoubler_disable,

		sd_lba => sd_lba,
		sd_rd => sd_rd,
		sd_wr => sd_wr,
		sd_ack => sd_ack,
		sd_conf => sd_conf,
		sd_sdhc => sd_sdhc,
		sd_dout => sd_dout,
		sd_dout_strobe => sd_dout_strobe,
		sd_din => sd_din,
		sd_din_strobe => sd_din_strobe,
		
		ps2_clk => clk14k,
		ps2_kbd_clk => ps2_clk,
		ps2_kbd_data => ps2_data
	);

	sd_card_d: sd_card
   port map
   (
         -- connection to io controller
         io_lba => sd_lba,
         io_rd  => sd_rd,
         io_wr  => sd_wr,
         io_ack => sd_ack,
         io_conf => sd_conf,
         io_sdhc => sd_sdhc,
         io_din => sd_dout,
         io_din_strobe => sd_dout_strobe,
         io_dout => sd_din,
         io_dout_strobe => sd_din_strobe,
 
         allow_sdhc  => '1',   -- esxdos supports SDHC

         -- connection to host
         sd_cs  => divmmc_cs,
         sd_sck => divmmc_sclk,
         sd_sdi => divmmc_mosi,
         sd_sdo => divmmc_miso
    );
	 
	 esx_request <= '1' when key_f11 = '1' or status(2) = '1'  or joystickA(7) = '1' or joystickB(7) = '1' else '0';

	-- CPU
	cpu: T80se port map (
		reset_n, clock, cpu_clken, --debug_cpu_clken,
		cpu_wait_n, cpu_irq_n, cpu_nmi_n,
		cpu_busreq_n, cpu_m1_n,
		cpu_mreq_n, cpu_ioreq_n,
		cpu_rd_n, cpu_wr_n,
		cpu_rfsh_n, cpu_halt_n, cpu_busack_n,
		cpu_a, cpu_di, cpu_do
		);
	-- VSYNC interrupt routed to CPU
	cpu_irq_n <= vid_irq_n;
	-- Unused CPU input signals
	cpu_wait_n <= '1';
	-- trigger nmi either with F11, the OSD or with the joystick
	cpu_nmi_n <= '0' when (esx_request = '1') and (esxdos_downloaded(1) = '1') else '1';
	cpu_busreq_n <= '1';
		
	-- Keyboard
	kb:	keyboard port map (
		clock, reset_n,
		ps2_clk, ps2_data,
		cpu_a, keyb, key_f11
		);
		
	-- ULA port
	ula: ula_port port map (
		clock, reset_n,
		cpu_do, ula_do,
		ula_enable and psg_clken, cpu_wr_n,
		ula_border,
		ula_ear_out, ula_mic_out,
		keyb,
		ula_ear_in
		);
		
	-- ULA video
	vid: video port map (
		-- use pll_locked to make the hcounter run synchronous to the 
		-- clocks counter
		clock, vid_clken, vid_mem_sync, reset_n,
		not scandoubler_disable,
		vid_a, sdram_do, vid_rd_n, vid_wait_n,
		ula_border,
		vid_r_out, vid_g_out, vid_b_out,
		vid_vsync_n, vid_hsync_n,
		vid_csync_n, vid_hcsync_n,
		vid_scanline,
		vid_irq_n
		);
		
	-- Sound
	sound_128k: if model /= 0 generate
		-- PSG only on 128K and above
		psg : YM2149 port map (
			cpu_do, psg_do, open,
			'0', -- /A9 pulled down internally
			'1', -- A8 pulled up on Spectrum
			psg_bdir,
			'1', -- BC2 pulled up on Spectrum
			psg_bc1,
			'1', -- /SEL is high for AY-3-8912 compatibility
			psg_aout,
			(others => '0'), open, open, -- port A unused (keypad and serial on Spectrum 128K)
			(others => '0'), open, open, -- port B unused (non-existent on AY-3-8912)
			psg_clken,
			reset_n,
			clock
			);
		psg_bdir <= psg_enable and cpu_rd_n;
		psg_bc1 <= psg_enable and cpu_a(14);

		-- map AY sound on left channel
		dac_l : sigma_delta_dac port map (
			CLK		=> clock,
			RESET 	=> not reset_n,
			DACin 	=> psg_aout,
			DACout	=> AUDIO_L
		);
		
		-- and beeper on right channel
		dac_r : sigma_delta_dac port map (
			CLK		=> clock,
			RESET 	=> not reset_n,
			DACin 	=> ula_ear_out & ula_mic_out & ula_ear_in & "00000",
			DACout	=> AUDIO_R
		);

	end generate;
	
		
	-- DIVMMC interface
	dmmc: divmmc port map (
		clock, reset_n, psg_clken,
		divmmc_enable, cpu_a,
		cpu_wr_n, cpu_rd_n, cpu_mreq_n, cpu_m1_n, 
		cpu_do, divmmc_do,
		divmmc_paged_in, divmmc_sram_page, divmmc_mapram, divmmc_conmem,
		divmmc_cs, divmmc_sclk, divmmc_mosi, divmmc_miso
		);
		
	-- Asynchronous reset
	-- System is reset by external reset switch or PLL being out of lock

	-- delay reset so sdram can be initialized etc. especially clearing the
	-- divmmc ram after esxdos upload needs some time (9.3ms)
	process(clock, pll_locked, status, buttons, esx_request)
		variable reset_cnt : integer range 0 to 32000000 := 32000000;
	begin
		if (pll_locked = '0' or status(0) = '1' or status(1) = '1' or buttons(1) = '1') or 
			((esx_request = '1') and (esxdos_downloaded = "01"))
		then
			-- don't clear core coldboot reset time
			if reset_cnt < 280000 then 
				reset_cnt := 280000;
			end if;
		elsif rising_edge(clock) then
			if reset_cnt /= 0 then
				reset_cnt := reset_cnt - 1;
			end if;
		end if;
 
		-- make sure cpu runs synchronous to bus state machine
		if rising_edge(clock) and cpu_clken = '1' then
			if reset_cnt = 0 then
				reset_n <= '1';
			else 
				reset_n <= '0';
			end if;
		end if;
	end process;

	process(esx_request)
	begin
		if rising_edge(esx_request) then
			esxdos_downloaded <= esxdos_downloaded(0) & esxdos_downloaded(0);
		end if;
	end process;
	
	-- Address decoding.  Z80 has separate IO and memory address space
	-- IO ports (nominal addresses - incompletely decoded):
	-- 0xXXFE R/W = ULA
	-- 0x7FFD W   = 128K paging register
	-- 0xFFFD W   = 128K AY-3-8912 register select
	-- 0xFFFD R   = 128K AY-3-8912 register read
	-- 0xBFFD W   = 128K AY-3-8912 register write
	-- 0x1FFD W   = +3 paging and control register
	-- 0x2FFD R   = +3 FDC status register
	-- 0x3FFD R/W = +3 FDC data register
	-- 0xXXEX R/W = DIVMMC interface
	-- FIXME: Revisit this - could be neater
	ula_enable <= (not cpu_ioreq_n) and cpu_m1_n and not cpu_a(0); -- all even IO addresses
	psg_enable <= (not cpu_ioreq_n) and cpu_m1_n and cpu_a(0) and cpu_a(15) and not cpu_a(1);
	kempston_enable <= (not cpu_ioreq_n) and cpu_m1_n and not cpu_a(7) and not cpu_a(6) and not cpu_a(5) and cpu_a(4) and cpu_a(3) and cpu_a(2) and cpu_a(1) and cpu_a(0);
	divmmc_enable <= esxdos_downloaded(1) and (not cpu_ioreq_n) and cpu_m1_n and cpu_a(7) and cpu_a(6) and cpu_a(5) and not cpu_a(4) and cpu_a(0);
	addr_decode_128k: if model /= 2 generate
		page_enable <= (not cpu_ioreq_n) and cpu_m1_n and cpu_a(0) and not (cpu_a(15) or cpu_a(1));
	end generate;
	addr_decode_plus3: if model = 2 generate
		-- Paging register address decoding is slightly stricter on the +3
		page_enable <= (not cpu_ioreq_n) and cpu_a(0) and cpu_a(14) and not (cpu_a(15) or cpu_a(1));
		plus3_enable <= (not cpu_ioreq_n) and cpu_a(0) and cpu_a(12) and not (cpu_a(15) or cpu_a(14) or cpu_a(13) or cpu_a(1));
	end generate;
	
	-- ROM is enabled between 0x0000 and 0x3fff except in +3 special mode
	rom_enable <= (not cpu_mreq_n) and not (plus3_special or cpu_a(15) or cpu_a(14));
	-- RAM is enabled for any memory request when ROM isn't enabled
	ram_enable <= (not cpu_mreq_n and not rom_enable);
	
	ram_page_128k: if model /= 2 generate
		-- 128K has pageable RAM at 0xc000
		ram_page <=
			page_ram_sel when cpu_a(15 downto 14) = "11" else -- Selectable bank at 0xc000
			cpu_a(14) & cpu_a(15 downto 14); -- A=bank: 00=XXX, 01=101, 10=010, 11=XXX
	end generate;
	ram_page_plus3: if model = 2 generate
		-- +3 has various additional modes in addition to "normal" mode, which is
		-- the same as the 128K
		-- Extra modes assign RAM banks as follows:
		-- plus3_page    0000    4000    8000    C000
		-- 00            0       1       2       3
		-- 01            4       5       6       7
		-- 10            4       5       6       3
		-- 11            4       7       6       3
		-- NORMAL        ROM     5       2       PAGED
		ram_page <=
			page_ram_sel when plus3_special = '0' and cpu_a(15 downto 14) = "11" else
			cpu_a(14) & cpu_a(15 downto 14) when plus3_special = '0' else
			"0" & cpu_a(15 downto 14) when plus3_special = '1' and plus3_page = "00" else
			"1" & cpu_a(15 downto 14) when plus3_special = '1' and plus3_page = "01" else
			(not(cpu_a(15) and cpu_a(14))) & cpu_a(15 downto 14) when plus3_special = '1' and plus3_page = "10" else
			(not(cpu_a(15) and cpu_a(14))) & (cpu_a(15) or cpu_a(14)) & cpu_a(14);
	end generate;
		
	process(cpu_cycle)
	begin
		-- latch sdram data at the end of cpus memory cycle
		if falling_edge(cpu_cycle) then
			mem_do <= sdram_do;
		end if;
	end process;
	
	-- CPU data bus mux
	cpu_di <=
		-- System RAM
		mem_do when ram_enable = '1'  else
		-- DIVMMC memory mapped into ROM area
		mem_do when (rom_enable = '1') and (divmmc_paged_in = '1') and (esxdos_downloaded(1) = '1') else
		-- Internal ROM
		rom_do when rom_enable = '1' else
		-- IO ports
		ula_do when ula_enable = '1' else
		psg_do when psg_enable = '1' else
		divmmc_do when divmmc_enable = '1' else
		-- map both joysticks onto the one supported by kempston
		"00" & (joystickA(5 downto 0) or joystickB(5 downto 0)) 
					when kempston_enable = '1' else
		-- Idle bus
		(others => '1');
	
	rom_48k: if model = 0 generate
		-- 48K
		rom_addr <= 
			-- Otherwise access the internal ROM
			"000000" & cpu_a(13 downto 0);
	end generate;
	
	rom_128k: if model = 1 generate
		-- DIVMMC low mapping (0x0000 - 0x1fff)
		divmmc_lo_addr <= "000000" & cpu_a(12 downto 0) when
			divmmc_conmem = '1' or divmmc_mapram = '0' else "010011" & cpu_a(12 downto 0);
		
		-- DIVMMC hi mapping (0x2000 - 0x3fff)
		divmmc_hi_addr <= "01" & divmmc_sram_page & cpu_a(12 downto 0);
	
		-- DIVMMC mapping
		divmmc_addr <= divmmc_lo_addr when cpu_a(13) = '0' else divmmc_hi_addr;
			
		-- 128K
		rom_addr <= 
			-- all DIVMMC mapping (even ram) happens in the ROM
			-- address space (0x0000-0x3fff)
			"1" & divmmc_addr when (esxdos_downloaded(1) = '1') and divmmc_paged_in = '1' else
			-- Otherwise access the internal ROMs
			"00000" & page_rom_sel & cpu_a(13 downto 0);
	end generate;
	
	rom_plus3: if model = 2 generate
		-- DIVMMC low mapping (0x0000 - 0x1fff)
		divmmc_lo_addr <= "000000" & cpu_a(12 downto 0) when
			divmmc_conmem = '1' or divmmc_mapram = '0' else "010011" & cpu_a(12 downto 0);
		
		-- DIVMMC hi mapping (0x2000 - 0x3fff)
		divmmc_hi_addr <= "01" & divmmc_sram_page & cpu_a(12 downto 0);
	
		-- DIVMMC mapping
		divmmc_addr <= divmmc_lo_addr when cpu_a(13) = '0' else divmmc_hi_addr;
			
		-- +3
		rom_addr <= 
			-- all DIVMMC mapping (even ram) happens in the ROM
			-- address space (0x0000-0x3fff)
			"1" & divmmc_addr when (esxdos_downloaded(1) = '1') and divmmc_paged_in = '1' else
		
			-- Otherwise access the internal ROMs		
			"0000" & plus3_page(1) & page_rom_sel & cpu_a(13 downto 0);
	end generate;

	-- first 1MB of sdram are used as ram, second 1MB sdram are used as rom
	-- and after that starts tape buffer
	cpu_addr <= "0" & ram_addr when ram_enable = '1' else "1" & rom_addr;
	 
	-- Video from bank 7 (128K/+3)
	-- Video from bank 5
	-- 16-bit address, LSb selects high/low byte
	vid_addr <= "001110" & vid_a(12 downto 0) when page_shadow_scr = '1' else
					"001010" & vid_a(12 downto 0);

	-- io address is driven by io controller on upload or by tape during replay
	io_addr <= ioctl_ram_addr when ioctl_used='1' else tape_addr;

	-- Synchronous outputs to SRAM
	process(clock,reset_n)
	variable divmmc_lo_write : std_logic;
	variable divmmc_hi_write : std_logic;
	variable divmmc_write : std_logic;
	variable ext_ram_write : std_logic; -- External RAM
	variable int_ram_write : std_logic; -- Internal RAM
	variable ram_write : std_logic;
	begin
		-- never write to lower 8k
		divmmc_lo_write := '0';

		-- write to upper 8k unless comem = 0, mapram = 1 and bank = 3
		divmmc_hi_write := not (divmmc_conmem and divmmc_mapram and 
										 not divmmc_sram_page(3) and not divmmc_sram_page(2) and
										 divmmc_sram_page(1) and divmmc_sram_page(0));

	   -- access to first or second 8k in OS ROM area	
		divmmc_write := (not cpu_a(13) and divmmc_lo_write) or 
							 (    cpu_a(13) and divmmc_hi_write);
		
		ext_ram_write := (rom_enable and esxdos_downloaded(1) and divmmc_paged_in and divmmc_write) and not cpu_wr_n;
		int_ram_write := ram_enable and not cpu_wr_n;
		ram_write := int_ram_write or ext_ram_write;
	
		if rising_edge(clock) then
			-- synchonize cpu memory access to video memory access
			if vid_clken = '1' then
				cpu_cycle <= mem_clken;
				ioctl_cycle <= dio_clken;
			end if;
		
			-- Register SRAM signals to outputs (clock must be at least 2x CPU clock)
			if vid_clken = '1' then
				-- Fetch data from previous CPU cycle
				-- Normal RAM access at 0x4000-0xffff
				-- 16-bit address
				ram_addr <= "000" & ram_page & cpu_a(13 downto 0);
			end if;
		end if;
		
		-- share SDRAM between CPU, Video and the io controller (ROM and tape upload)
		if cpu_cycle = '1' then
			sdram_oe <= not cpu_mreq_n and not cpu_rd_n;  -- any cpu read enables ram
			sdram_we <= ram_write;                        -- write only for memory used as ram
			sdram_di <= cpu_do;
			sdram_addr <= "0000" & cpu_addr;
		elsif ioctl_cycle = '1' then
			sdram_oe <= tape_rd;
			sdram_we <= ioctl_used;
			sdram_di <= ioctl_ram_data;
			sdram_addr <= io_addr;
		else
			-- no cpu sccess. Thus do video access
			sdram_oe <=  not vid_rd_n;
			sdram_we <= '0';    -- video never writes
			sdram_di <= "00000000";
			sdram_addr <= "000000" & vid_addr;
		end if;
	end process;
	
	page_reg_128k: if model /= 0 generate
		-- 128K paging register
		process(clock,reset_n)
		begin
			if reset_n = '0' then
				page_reg_disable <= '0';
				page_rom_sel <= '0';
				page_shadow_scr <= '0';
				page_ram_sel <= (others => '0');
			elsif rising_edge(clock) and psg_clken = '1' then
				if page_enable = '1' and page_reg_disable = '0' and cpu_wr_n = '0' then
					page_reg_disable <= cpu_do(5);
					page_rom_sel <= cpu_do(4);
					page_shadow_scr <= cpu_do(3);
					page_ram_sel <= cpu_do(2 downto 0);
				end if;
			end if;
		end process;
	end generate;
	
	plus3_reg: if model = 2 generate
		-- +3 paging and control register
		process(clock,reset_n)
		begin
			if reset_n = '0' then
				plus3_printer_strobe <= '0';
				plus3_disk_motor <= '0';
				plus3_page <= (others => '0');
				plus3_special <= '0';
			elsif rising_edge(clock) then
				-- FIXME: Does this get disabled by the page_reg_disable bit?
				if plus3_enable = '1' and cpu_wr_n = '0' then
					plus3_printer_strobe <= cpu_do(4);
					plus3_disk_motor <= cpu_do(3);
					plus3_page <= cpu_do(2 downto 1);
					plus3_special <= cpu_do(0);
				end if;
			end if;
		end process;
	end generate;
	
	-- Connect ULA to video output
	zx_red <= '0' & vid_r_out & '0' when vid_scanline = '1' and status(3) = '1' else vid_r_out & "00";
	zx_green <= '0' & vid_g_out & '0' when vid_scanline = '1' and status(3) = '1' else vid_g_out & "00";
	zx_blue <= '0' & vid_b_out & '0' when vid_scanline = '1' and status(3) = '1' else vid_b_out & "00";
	VGA_HS <= vid_hcsync_n;
	-- when scandoubler is disabled a csync is fed into hsync and 
   -- vsync is used as a rgb switch signal
   VGA_VS <= '1' when scandoubler_disable = '1' else vid_vsync_n;

	-- route video through osd
	osd_d : osd
	generic map (OSD_COLOR => 6)
	port map (
		pclk => vid_clken,
      sck => SPI_SCK,
      ss => SPI_SS3,
      sdi => SPI_DI,

      red_in => zx_red,
      green_in => zx_green,
      blue_in => zx_blue,
      hs_in => vid_hsync_n,
      vs_in => vid_vsync_n,

      red_out => VGA_R,
      green_out => VGA_G,
      blue_out => VGA_B
	);
end architecture;
