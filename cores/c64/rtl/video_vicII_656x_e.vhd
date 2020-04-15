-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------
--
-- VIC-II - Video Interface Chip no 2
--
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

-- -----------------------------------------------------------------------

entity video_vicii_656x is
	generic (
		registeredAddress : boolean;
		emulateRefresh : boolean := false;
		emulateLightpen : boolean := false;
		emulateGraphics : boolean := true
	);
	port (
		clk: in std_logic;
		-- phi = 0 is VIC cycle
		-- phi = 1 is CPU cycle (only used by VIC when BA is low)
		phi : in std_logic;
		enaData : in std_logic;
		enaPixel : in std_logic;

		baSync : in std_logic;
		ba: out std_logic;

		mode6569 : in std_logic; -- PAL 63 cycles and 312 lines
		mode6567old : in std_logic; -- old NTSC 64 cycles and 262 line
		mode6567R8 : in std_logic; -- new NTSC 65 cycles and 263 line
		mode6572 : in std_logic; -- PAL-N 65 cycles and 312 lines

		reset : in std_logic;
		cs : in std_logic;
		we : in std_logic;
		lp_n : in std_logic;

		aRegisters: in unsigned(5 downto 0);
		diRegisters: in unsigned(7 downto 0);

		di: in unsigned(7 downto 0);
		diColor: in unsigned(3 downto 0);
		do: out unsigned(7 downto 0);

		vicAddr: out unsigned(13 downto 0);
		irq_n: out std_logic;

		-- Video output
		hSync : out std_logic;
		vSync : out std_logic;
		colorIndex : out unsigned(3 downto 0);

		-- Debug outputs
		debugX : out unsigned(9 downto 0);
		debugY : out unsigned(8 downto 0);
		vicRefresh : out std_logic;
		addrValid : out std_logic
	);
end entity;

