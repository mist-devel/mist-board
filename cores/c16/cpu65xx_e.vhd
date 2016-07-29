-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Copyright 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------
--
-- Interface to 6502/6510 core
--
-- -----------------------------------------------------------------------

library IEEE;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;

-- -----------------------------------------------------------------------

entity cpu65xx is
	generic (
		pipelineOpcode : boolean;
		pipelineAluMux : boolean;
		pipelineAluOut : boolean
	);
	port (
		clk : in std_logic;
		enable : in std_logic;
		reset : in std_logic;
		nmi_n : in std_logic;
		irq_n : in std_logic;
		so_n : in std_logic := '1';

		di : in unsigned(7 downto 0);
		do : out unsigned(7 downto 0);
		addr : out unsigned(15 downto 0);
		we : out std_logic;
		
		debugOpcode : out unsigned(7 downto 0);
		debugPc : out unsigned(15 downto 0);
		debugA : out unsigned(7 downto 0);
		debugX : out unsigned(7 downto 0);
		debugY : out unsigned(7 downto 0);
		debugS : out unsigned(7 downto 0)
	);
end cpu65xx;
