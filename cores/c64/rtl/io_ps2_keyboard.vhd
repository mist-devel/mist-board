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

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity io_ps2_keyboard is
	port (
		clk: in std_logic;
		kbd_clk: in std_logic;
		kbd_dat: in std_logic;

		interrupt: out std_logic;
		scanCode: out unsigned(7 downto 0)
	);
end io_ps2_keyboard;

architecture Behavioral of io_ps2_keyboard is
	signal clk_reg: std_logic;
	signal clk_waitNextBit: std_logic;
	signal clk_filter: integer range 0 to 15;
	signal shift_reg: unsigned(10 downto 0) := (others => '0');

	signal bitsCount: integer range 0 to 10 := 0;
	signal timeout: integer range 0 to 5000 := 0; -- 2* 50 us at 50 Mhz
begin
	process(clk)
	begin
		if rising_edge(clk) then
			-- Interrupt is edge triggered. Only 1 clock high.
			interrupt <= '0';

			-- Timeout if keyboard does not send anymore.
			if timeout /= 0 then
				timeout <= timeout - 1;
			else
				bitsCount <= 0;
			end if;
			
			-- Filter glitches on the clock
			if (clk_reg /= kbd_clk) then
				clk_filter <= 15; -- Wait 15 ticks 
				clk_reg <= kbd_clk; -- Store clock edge to detect changes
				clk_waitNextBit <= '0'; -- Next bit comming up...
			elsif (clk_filter /= 0) then
				-- Wait for clock to stabilise
				-- Clock must be stable before we sample the data line.
				clk_filter <= clk_filter - 1;
			elsif (clk_reg = '1') and (clk_waitNextBit = '0') then
				-- We have a stable clock, so assume stable data too.
				clk_waitNextBit <= '1';
				
				-- Move data into shift register
				shift_reg <= kbd_dat & shift_reg(10 downto 1);
				timeout <= 5000;
				if bitsCount < 10 then
					bitsCount <= bitsCount + 1;
				else
					-- 10 bits received. Output new scancode
					bitsCount <= 0;
					interrupt <= '1';
					scanCode <= shift_reg(9 downto 2);
				end if;
			end if;
		end if;
	end process;

end Behavioral;
