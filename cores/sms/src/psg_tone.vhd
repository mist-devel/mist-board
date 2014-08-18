library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity psg_tone is
    Port (
		clk	: in  STD_LOGIC;
		tone	: in  STD_LOGIC_VECTOR (9 downto 0);
		volume: in  STD_LOGIC_VECTOR (3 downto 0);
		output: out STD_LOGIC_VECTOR (3 downto 0));
end psg_tone;

architecture rtl of psg_tone is

	signal counter	: unsigned(9 downto 0) := (0=>'1', others=>'0');
	signal v			: std_logic := '0';

begin

	process (clk, tone)
	begin
		if rising_edge(clk) then
			if counter="000000000" then
				v <= not v;
				counter <= unsigned(tone);
			else
				counter <= counter-1;
			end if;
		end if;
	end process;

	output <= (v&v&v&v) or volume;
end rtl;

