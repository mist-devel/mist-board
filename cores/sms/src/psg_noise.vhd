library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity psg_noise is
port (
	clk		: in  STD_LOGIC;
	style		: in  STD_LOGIC_VECTOR (2 downto 0);
	tone		: in  STD_LOGIC_VECTOR (9 downto 0);
	volume	: in  STD_LOGIC_VECTOR (3 downto 0);
	output	: out STD_LOGIC_VECTOR (3 downto 0));
end psg_noise;

architecture rtl of psg_noise is

	signal counter	: unsigned(9 downto 0);
	signal v			: std_logic;
	signal shift	: std_logic_vector(15 downto 0) := "1000000000000000";

begin

	process (clk, tone)
	begin
		if rising_edge(clk) then
			if counter="000000001" then
				v <= not v;
				case style(1 downto 0) is
					when "00" => counter <= "0000010000";
					when "01" => counter <= "0000100000";
					when "10" => counter <= "0001000000";
					when "11" => counter <= unsigned(tone);
					when others =>
				end case;
			else
				counter <= counter-1;
			end if;
		end if;
	end process;

	process (v)
		variable feedback: std_logic;
	begin
		if rising_edge(v) then
			if (style(2)='1') then
				feedback := shift(0) xor shift(3);
			else
				feedback := shift(0);
			end if;
			shift <= feedback & shift(15 downto 1);
		end if;
	end process;

	output <= (shift(0)&shift(0)&shift(0)&shift(0)) or volume;

end rtl;

