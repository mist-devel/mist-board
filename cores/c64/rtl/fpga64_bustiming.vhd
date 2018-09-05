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
-- Reset circuit
--
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

entity fpga64_busTiming is
	generic (
		resetCycles: integer := 15;
		noofBusCycles : integer := 52
	);
	port (
		clkIn : in std_logic;
		rstIn : in std_logic;		
		rstOut : out std_logic;
		endOfCycle : out std_logic; -- Signal is 1 on last count of current cycle.
		busCycle : out unsigned(5 downto 0)
	);
end fpga64_busTiming;

-- -----------------------------------------------------------------------

architecture rtl of fpga64_busTiming is
signal clk33 : std_logic;
signal nextCycle : std_logic;
signal resetCycleCounter : integer range 0 to resetCycles := 0;
signal busCycleCounter : unsigned(5 downto 0) := (others => '0');
begin
	clk33 <= clkIn;

	process(clk33)
	begin
		if rising_edge(clk33) then
			if (busCycleCounter = (noofBusCycles - 2) ) then
				nextCycle <= '1';
			else
				nextCycle <= '0';
			end if;
			if nextCycle = '1' then
				busCycleCounter <= (others => '0');
			else
				busCycleCounter <= busCycleCounter + 1;
			end if;
			if resetCycleCounter = resetCycles then
				rstOut <= '0';
			else
				rstOut <= '1';
				if nextCycle = '1' then
					resetCycleCounter <= resetCycleCounter + 1;
				end if;
			end if;
			if rstIn = '1' then
--				nextCycle <= '0';
				resetCycleCounter <= 0;
			end if;
		end if;
	end process;
	busCycle <= busCycleCounter;
	endOfCycle <= nextCycle;
end architecture;
