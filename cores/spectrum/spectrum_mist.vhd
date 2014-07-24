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
--   this list of conditions and the following disclaimer.
--
-- * Redistributions in synthesized form must reproduce the above copyright
--   notice, this list of conditions and the following disclaimer in the
--   documentation and/or other materials provided with the distribution.
--
-- * Neither the name of the author nor the names of other contributors may
--   be used to endorse or promote products derived from this software without
--   specific prior written agreement from the author.
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
	MODEL				:	integer := 0
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
-- 24 MHz input
-- 28 MHz master clock output
-- 120 MHz sdram controller clock
-- 120 MHz sdram clock (-2.5 ns phase shifted)
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
	
	-- 1.75 MHz clock enable for sound
	CLKEN_PSG		:	out	std_logic;
	-- 3.5 MHz clock enable (1 in 8)
	CLKEN_CPU		:	out std_logic;
	-- 3.5 MHz clock enable (1 in 8)
	CLKEN_MEM		:	out std_logic;
	-- 14 MHz clock enable (out of phase with CPU)
	CLKEN_VID		:	out std_logic
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

component rom48 is
port (
	address    	: 	in		std_logic_vector(13 downto 0);
	clock			: 	in 	std_logic;
	q        	: 	out	std_logic_vector(7 downto 0)
	);
end component;

---------
-- User IO
---------

-- config string used by the io controller to fill the OSD
constant CONF_STR : string := "Spectrum;;";

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
  port ( SPI_CLK, SPI_SS_IO, SPI_MOSI :in std_logic;
         SPI_MISO : out std_logic;
         conf_str : in std_logic_vector(8*STRLEN-1 downto 0);
         JOY0 :     out std_logic_vector(5 downto 0);
         JOY1 :     out std_logic_vector(5 downto 0);
         status:    out std_logic_vector(7 downto 0);
         SWITCHES : out std_logic_vector(1 downto 0);
         BUTTONS : out std_logic_vector(1 downto 0);
			clk		: in std_logic;
			ps2_clk	: out std_logic;
			ps2_data : out std_logic
       );
end component user_io;

---------
-- OSD
---------

component osd
  generic ( OSD_COLOR : integer );
  port ( pclk : in std_logic;
		sck, sdi, ss : in std_logic;

		-- VGA signals coming from core
      red_in : in std_logic_vector(5 downto 0);
      green_in : in std_logic_vector(5 downto 0);
      blue_in : in std_logic_vector(5 downto 0);
      hs_in : in std_logic;
      vs_in : in std_logic;

      -- VGA signals going to video connector
      red_out : out std_logic_vector(5 downto 0);
      green_out : out std_logic_vector(5 downto 0);
      blue_out : out std_logic_vector(5 downto 0);
      hs_out : out std_logic;
      vs_out : out std_logic
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
	nVSYNC		:	out std_logic;
	nHSYNC		:	out std_logic;
	nCSYNC		:	out	std_logic;
	nHCSYNC		:	out std_logic;
	IS_BORDER	: 	out std_logic;
	IS_VALID	:	out std_logic;
	
	-- Clock outputs, might be useful
	PIXCLK		:	out std_logic;
	FLASHCLK	: 	out std_logic;
	
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
	KEYB		:	out	std_logic_vector(4 downto 0)
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

-------------------
-- MMC interface
-------------------

component zxmmc is
port (
	CLOCK		:	in	std_logic;
	nRESET		:	in	std_logic;
	CLKEN		:	in	std_logic;
	
	-- Bus interface
	ENABLE		:	in	std_logic;
	-- 0 - W  - Card chip selects (active low)
	-- 1 - RW - SPI tx/rx data register
	-- 2 - Not used
	-- 3 - RW - Paging control register
	RS			:	in	std_logic_vector(1 downto 0);
	nWR			:	in	std_logic;
	DI			:	in	std_logic_vector(7 downto 0);
	DO			:	out	std_logic_vector(7 downto 0);
	
	-- SD card interface
	SD_CS0		:	out	std_logic;
	SD_CS1		:	out	std_logic;
	SD_CLK		:	out	std_logic;
	SD_MOSI		:	out	std_logic;
	SD_MISO		:	in	std_logic;
	
	-- Paging control for external RAM/ROM banks
	EXT_WR_EN	:	out	std_logic; -- Enable writes to external RAM/ROM
	EXT_RD_EN	:	out	std_logic; -- Enable reads from external RAM/ROM (overlay internal ROM)
	EXT_ROM_nRAM	:	out	std_logic; -- Select external ROM or RAM banks
	EXT_BANK	:	out	std_logic_vector(4 downto 0); -- Selected bank number
	
	-- DIP switches (reset values for corresponding bits above)
	INIT_RD_EN	:	in	std_logic;
	INIT_ROM_nRAM	:	in	std_logic
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
signal zx_hs : std_logic;
signal zx_vs : std_logic;

-- signals from user_io
signal switches: std_logic_vector(1 downto 0);
signal buttons: std_logic_vector(1 downto 0);
signal joystickA: std_logic_vector(5 downto 0);
signal joystickB: std_logic_vector(5 downto 0);
signal status: std_logic_vector(7 downto 0);

-- TH extra
signal rom_addr		:	std_logic_vector(18 downto 0);
signal ram_addr		:	std_logic_vector(18 downto 0);
signal cpu_addr		:	std_logic_vector(19 downto 0);
signal vid_addr		:	std_logic_vector(18 downto 0);
signal cpu_cycle     :  std_logic;
signal rom_do        :  std_logic_vector(7 downto 0);
signal mem_do        :  std_logic_vector(7 downto 0);
signal ps2_clk       :  std_logic;
signal ps2_data      :  std_logic;

-- Master clock - 28 MHz
signal clk112      	:	std_logic;
signal clk_div			: 	unsigned(1 downto 0);
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
signal vid_clken		:	std_logic;

-- Address decoding
signal ula_enable		:	std_logic; -- all even IO addresses
signal rom_enable		:	std_logic; -- 0x0000-0x3FFF
signal ram_enable		:	std_logic; -- 0x4000-0xFFFF
-- 128K extensions
signal page_enable		:	std_logic; -- all odd IO addresses with A15 and A1 clear (and A14 set in +3 mode)
signal psg_enable		:	std_logic; -- all odd IO addresses with A15 set and A1 clear
-- +3 extensions
signal plus3_enable		:	std_logic; -- A15, A14, A13, A1 clear, A12 set.
-- ZXMMC
signal zxmmc_enable		:	std_logic; -- A4-A0 set

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

-- Debugger connections
signal debug_cpu_clken	:	std_logic;
signal debug_irq_in_n	:	std_logic;
signal debug_fetch		:	std_logic;
signal debug_aux		:	std_logic_vector(15 downto 0);

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
signal vid_di		:	std_logic_vector(7 downto 0);
signal vid_rd_n		:	std_logic;
signal vid_wait_n	:	std_logic;
signal vid_r_out	:	std_logic_vector(3 downto 0);
signal vid_g_out	:	std_logic_vector(3 downto 0);
signal vid_b_out	:	std_logic_vector(3 downto 0);
signal vid_vsync_n	:	std_logic;
signal vid_hsync_n	:	std_logic;
signal vid_csync_n	:	std_logic;
signal vid_hcsync_n	:	std_logic;
signal vid_is_border	:	std_logic;
signal vid_is_valid	:	std_logic;
signal vid_pixclk	:	std_logic;
signal vid_flashclk	:	std_logic;
signal vid_irq_n	:	std_logic;

-- Keyboard
signal keyb			:	std_logic_vector(4 downto 0);

-- Sound (PSG default values for systems that don't have it)
signal psg_do		:	std_logic_vector(7 downto 0) := "11111111";
signal psg_bdir		:	std_logic;
signal psg_bc1		:	std_logic;
signal psg_aout		:	std_logic_vector(7 downto 0) := "00000000";
signal pcm_lrclk	:	std_logic;
signal pcm_outl		:	std_logic_vector(15 downto 0);
signal pcm_outr		:	std_logic_vector(15 downto 0);
signal pcm_inl		:	std_logic_vector(15 downto 0);
signal pcm_inr		:	std_logic_vector(15 downto 0);

-- ZXMMC interface
signal zxmmc_do		:	std_logic_vector(7 downto 0);

signal zxmmc_sclk	:	std_logic;
signal zxmmc_mosi	:	std_logic;
signal zxmmc_miso	:	std_logic;
signal zxmmc_cs0	:	std_logic;

-- ZXMMC+ external ROM/RAM interface (for ResiDOS)
signal zxmmc_wr_en	:	std_logic;
signal zxmmc_rd_en	:	std_logic;
signal zxmmc_rom_nram	:	std_logic;
signal zxmmc_bank	:	std_logic_vector(4 downto 0);

begin
	-- 28 MHz master clock
	pll: pll_main port map (
		'0',
		CLOCK_27(0),
		clk112,
		SDRAM_CLK,
		pll_locked
		);
		
	-- generate 28Mhz system clock from 112MHz main clock by dividing it by 4
	process(clk112)
	begin
		if rising_edge(clk112) then
			clk_div <= clk_div + 1;
		end if;
		
		clock <= clk_div(1);
	end process;	
	
	-- Clock enable logic
	clken: clocks port map (
		clock,
		reset_n,
		psg_clken,
		cpu_clken,
		mem_clken,
		vid_clken
		);
		
	-- SDRAM
	sdr: sdram port map (
		-- RAM chip
		SDRAM_DQ, SDRAM_A, sdram_dqm,
		SDRAM_nCS, SDRAM_BA, SDRAM_nWE, SDRAM_NRAS, SDRAM_nCAS,
		
		-- System
		clk112, vid_clken, not pll_locked,
		
		-- cpu interface
		sdram_di, sdram_do,
		sdram_addr, sdram_we, sdram_oe
	);
	SDRAM_DQMH <= sdram_dqm(1);
	SDRAM_DQML <= sdram_dqm(0);
	-- SDRAM clock always enabled		
	SDRAM_CKE <= '1';
	
	-- embedded rom
	rom: rom48 port map (
		rom_addr(13 downto 0),
		mem_clken,
		rom_do
	);
	
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
		JOY0 => joystickA,
		JOY1 => joystickB,
		SWITCHES => switches,
		BUTTONS => buttons,
		
		clk => clk14k,
		ps2_clk => ps2_clk,
		ps2_data => ps2_data
	);
		
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
	cpu_nmi_n <= '1';
	cpu_busreq_n <= '1';
		
	-- Keyboard
	kb:	keyboard port map (
		clock, reset_n,
		ps2_clk, ps2_data,
		cpu_a, keyb
		);
		
	-- ULA port
	ula: ula_port port map (
		clock, reset_n,
		cpu_do, ula_do,
		ula_enable, cpu_wr_n,
		ula_border,
		ula_ear_out, ula_mic_out,
		keyb,
		ula_ear_in
		);
		
	-- ULA video
	vid: video port map (
		clock, vid_clken, reset_n,
		'1',  -- VGA SW(7)
		vid_a, vid_di, vid_rd_n, vid_wait_n,
		ula_border,
		vid_r_out, vid_g_out, vid_b_out,
		vid_vsync_n, vid_hsync_n,
		vid_csync_n, vid_hcsync_n,
		vid_is_border, vid_is_valid,
		vid_pixclk, vid_flashclk,
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
	end generate;
	
	-- ZXMMC interface
--	mmc: zxmmc port map (
--		clock, reset_n, cpu_clken,
--		zxmmc_enable, cpu_a(6 downto 5), -- A6/A5 selects register
--		cpu_wr_n, cpu_do, zxmmc_do,
--		zxmmc_cs0, open,
--		zxmmc_sclk, zxmmc_mosi, zxmmc_miso,
--		zxmmc_wr_en, zxmmc_rd_en, zxmmc_rom_nram,
--		zxmmc_bank,
--		SW(1), SW(0)
--		);

	-- TH		
--	SD_nCS <= zxmmc_cs0;
--	SD_SCLK <= zxmmc_sclk;
--	SD_MOSI <= zxmmc_mosi;
--	zxmmc_miso <= SD_MISO;
--	GPIO_0(0) <= zxmmc_cs0;
--	GPIO_0(1) <= zxmmc_sclk;
--	GPIO_0(2) <= zxmmc_mosi;
--	GPIO_0(3) <= zxmmc_miso;
		
	-- Asynchronous reset
	-- System is reset by external reset switch or PLL being out of lock

	-- delay reset so sdram can be initialized etc
	process(clock, pll_locked, status, buttons)
		variable reset_cnt : integer range 0 to 10000;
	begin
		if pll_locked = '0' or status(0) = '1' or buttons(1) = '1' then
			reset_cnt := 10000;
		elsif rising_edge(clock) then
			if reset_cnt /= 0 then
				reset_cnt := reset_cnt - 1;
			end if;
		end if;

		if reset_cnt = 0 then
			reset_n <= '1';
		else 
			reset_n <= '0';
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
	-- 0xXXXF R/W = ZXMMC interface
	-- FIXME: Revisit this - could be neater
	ula_enable <= (not cpu_ioreq_n) and not cpu_a(0); -- all even IO addresses
	psg_enable <= (not cpu_ioreq_n) and cpu_a(0) and cpu_a(15) and not cpu_a(1);
	zxmmc_enable <= (not cpu_ioreq_n) and cpu_a(4) and cpu_a(3) and cpu_a(2) and cpu_a(1) and cpu_a(0);
	addr_decode_128k: if model /= 2 generate
		page_enable <= (not cpu_ioreq_n) and cpu_a(0) and not (cpu_a(15) or cpu_a(1));
	end generate;
	addr_decode_plus3: if model = 2 generate
		-- Paging register address decoding is slightly stricter on the +3
		page_enable <= (not cpu_ioreq_n) and cpu_a(0) and cpu_a(14) and not (cpu_a(15) or cpu_a(1));
		plus3_enable <= (not cpu_ioreq_n) and cpu_a(0) and cpu_a(12) and not (cpu_a(15) or cpu_a(14) or cpu_a(13) or cpu_a(1));
	end generate;
	
	-- ROM is enabled between 0x0000 and 0x3fff except in +3 special mode
	rom_enable <= (not cpu_mreq_n) and not (plus3_special or cpu_a(15) or cpu_a(14));
	-- RAM is enabled for any memory request when ROM isn't enabled
	ram_enable <= not (cpu_mreq_n or rom_enable);
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
		-- latch data at the end of cpus memory cycle
		if falling_edge(cpu_cycle) then
			if rom_enable = '1' then
				mem_do <= rom_do;
			else	
				mem_do <= sdram_do;
			end if;
		end if;
	end process;
	
	-- CPU data bus mux
	cpu_di <=
		-- System RAM
		mem_do when ram_enable = '1' else
		-- External (ZXMMC+) RAM at 0x0000-0x3fff when enabled
		-- This overlays the internal ROM
		mem_do when rom_enable = '1' and zxmmc_rd_en = '1' and zxmmc_rom_nram = '0' else
		-- Internal ROM or external (ZXMMC+) ROM at 0x0000-0x3fff
		mem_do when rom_enable = '1' else
		-- IO ports
		ula_do when ula_enable = '1' else
		psg_do when psg_enable = '1' else
		zxmmc_do when zxmmc_enable = '1' else
		-- Idle bus
		(others => '1');
	
	-- ROMs are in external flash starting at 0x20000
	-- (lower addresses contain the BBC ROMs)
--	FL_RST_N <= reset_n;
--	FL_CE_N <= '0';
--	FL_OE_N <= '0';
--	FL_WE_N <= '1';
	rom_48k: if model = 0 generate
		-- 48K
		rom_addr <= 
			-- Overlay external ROMs when enabled
			"1" & zxmmc_bank(3 downto 0) & cpu_a(13 downto 0)
			when zxmmc_rd_en = '1' else
			-- Otherwise access the internal ROM
			"00000" & cpu_a(13 downto 0);
	end generate;
	rom_128k: if model = 1 generate
		-- 128K
		rom_addr <= 
			-- Overlay external ROMs when enabled
			"1" & zxmmc_bank(3 downto 0) & cpu_a(13 downto 0)
			when zxmmc_rd_en = '1' else
			-- Otherwise access the internal ROMs
			"0000" & page_rom_sel & cpu_a(13 downto 0);
	end generate;
	rom_plus3: if model = 2 generate
		-- +3
		rom_addr <= 
			-- Overlay external ROMs when enabled
			"1" & zxmmc_bank(3 downto 0) & cpu_a(13 downto 0)
			when zxmmc_rd_en = '1' else
			-- Otherwise access the internal ROMs		
			"000" & plus3_page(1) & page_rom_sel & cpu_a(13 downto 0);
	end generate;

	-- SRAM bus
	vid_di <= sdram_do;
	
	-- first 512k of sdram are used as ram, second 512k sdram are used as rom
	cpu_addr <= "0" & ram_addr when ram_enable = '1' or 
				(rom_enable = '1' and zxmmc_rd_en = '1' and zxmmc_rom_nram = '0') else
					"1" & rom_addr;
	
	-- Video from bank 7 (128K/+3)
	-- Video from bank 5
	-- 16-bit address, LSb selects high/low byte
	vid_addr <= "001110" & vid_a(12 downto 0) when page_shadow_scr = '1' else
					"001010" & vid_a(12 downto 0);

	-- map video controller address to sdram when video is active, else cpu
	sdram_addr(24 downto 20) <= "00000";  -- only 1 of 32 MB used
	sdram_addr(19 downto 0) <= "0" & vid_addr when vid_rd_n = '0' else cpu_addr;

	-- Synchronous outputs to SRAM
	process(clock,reset_n)
	variable ext_ram_write : std_logic; -- External RAM (ZXMMC+)
	variable int_ram_write : std_logic; -- Internal RAM
	variable sram_write : std_logic;
	begin
		ext_ram_write := (rom_enable and zxmmc_wr_en and not zxmmc_rom_nram) and not cpu_wr_n;
		int_ram_write := ram_enable and not cpu_wr_n;
		sram_write := int_ram_write or ext_ram_write;
	
		if reset_n = '0' then
		elsif rising_edge(clock) then
			-- synchonize cpu memory access to video memory access
			if vid_clken = '1' then
				cpu_cycle <= mem_clken;
			end if;
		
			-- Default to inputs
--			SRAM_DQ <= (others => 'Z');
			
			-- Register SRAM signals to outputs (clock must be at least 2x CPU clock)
			if vid_clken = '1' then
				-- Fetch data from previous CPU cycle
				if rom_enable = '0' then
					-- Normal RAM access at 0x4000-0xffff
					-- 16-bit address
					ram_addr <= "00" & ram_page & cpu_a(13 downto 0);
				else
					-- ZXMMC+ external RAM access (16 banks of 16KB)
					-- at 0x0000-0x3fff
					-- 16-bit address
					ram_addr <= "1" & zxmmc_bank(3 downto 0) & cpu_a(13 downto 0);
				end if;
				if sram_write = '1' then
					sdram_di <= cpu_do;
				end if;
			end if;
		end if;
		
		if cpu_cycle = '1' then
			sdram_oe <= not cpu_mreq_n and not cpu_rd_n;  -- any cpu read enables ram
			sdram_we <= sram_write;    -- cpu_wr_n incl.  -- write only for memory used as ram
--			sdram_we <= '0';    -- cpu_wr_n incl.  -- write only for memory used as ram
		else
			-- no cpu sccess. Thus do video access
			sdram_oe <=  not vid_rd_n;
			sdram_we <= '0';    -- video never writes
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
			elsif rising_edge(clock) then
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
	
	-- Connect audio to PCM interface
	pcm_outl <= ula_ear_out & psg_aout & ula_mic_out & "000000";
	pcm_outr <= ula_ear_out & psg_aout & ula_mic_out & "000000";
	
	-- Hysteresis for EAR input (should help reliability)
	process(clock)
	variable in_val : integer;
	begin
		in_val := to_integer(signed(pcm_inl));
		
		if rising_edge(clock) then
			if in_val < -15 then
				ula_ear_in <= '0';
			elsif in_val > 15 then
				ula_ear_in <= '1';
			end if;
		end if;
	end process;
	
	-- Connect ULA to video output
	zx_red <= vid_r_out & "00";
	zx_green <= vid_g_out & "00";
	zx_blue <= vid_b_out & "00";
	zx_hs <= vid_hcsync_n;
	zx_vs <= vid_vsync_n;

	-- route video through osd
	osd_d : osd
	generic map (OSD_COLOR => 3)
	port map (
		pclk => vid_clken,
      sck => SPI_SCK,
      ss => SPI_SS3,
      sdi => SPI_DI,

      red_in => zx_red,
      green_in => zx_green,
      blue_in => zx_blue,
      hs_in => zx_hs,
      vs_in => zx_vs,

      red_out => VGA_R,
      green_out => VGA_G,
      blue_out => VGA_B,
      hs_out => VGA_HS,
      vs_out => VGA_VS
	);
end architecture;
