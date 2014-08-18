library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vpd_sprite_shifter is
	Port( clk	: in  std_logic;
			x		: in  unsigned (7 downto 0);
			spr_x	: in  unsigned (7 downto 0);
			spr_d0: in  std_logic_vector (7 downto 0);
			spr_d1: in  std_logic_vector (7 downto 0);
			spr_d2: in  std_logic_vector (7 downto 0);
			spr_d3: in  std_logic_vector (7 downto 0);
			color : out std_logic_vector (3 downto 0);
			active: out std_logic);
end vpd_sprite_shifter;

architecture Behavioral of vpd_sprite_shifter is

	signal count	: integer range 0 to 8;
	signal shift0	: std_logic_vector (7 downto 0) := (others=>'0');
	signal shift1	: std_logic_vector (7 downto 0) := (others=>'0');
	signal shift2	: std_logic_vector (7 downto 0) := (others=>'0');
	signal shift3	: std_logic_vector (7 downto 0) := (others=>'0');

begin

	process (clk)
	begin
		if rising_edge(clk) then
			if spr_x=x then
				shift0 <= spr_d0;
				shift1 <= spr_d1;
				shift2 <= spr_d2;
				shift3 <= spr_d3;
			else
				shift0 <= shift0(6 downto 0)&"0";
				shift1 <= shift1(6 downto 0)&"0";
				shift2 <= shift2(6 downto 0)&"0";
				shift3 <= shift3(6 downto 0)&"0";
			end if;
		end if;
	end process;
	
	color <= shift3(7)&shift2(7)&shift1(7)&shift0(7);
	active <= shift3(7) or shift2(7) or shift1(7) or shift0(7);
	
end Behavioral;

