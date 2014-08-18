library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vdp_cram is
	port (
		cpu_clk:	in  STD_LOGIC;
		cpu_WE:	in  STD_LOGIC;
		cpu_A:	in  STD_LOGIC_VECTOR (4 downto 0);
		cpu_D:	in  STD_LOGIC_VECTOR (5 downto 0);
		vdp_clk:	in  STD_LOGIC;
		vdp_A:	in  STD_LOGIC_VECTOR (4 downto 0);
		vdp_D:	out STD_LOGIC_VECTOR (5 downto 0));
end vdp_cram;

architecture Behavioral of vdp_cram is

	type t_ram is array (0 to 31) of std_logic_vector(5 downto 0);
	signal ram : t_ram := (others => "111111");
	
begin

	process (cpu_clk)
		variable i : integer range 0 to 31;
	begin
		if rising_edge(cpu_clk) then
			if cpu_WE='1'then
				i := to_integer(unsigned(cpu_A));
				ram(i) <= cpu_D;
			end if;
		end if;
	end process;

	process (vdp_clk)
		variable i : integer range 0 to 31;
	begin
		if rising_edge(vdp_clk) then
			i := to_integer(unsigned(vdp_A));
			vdp_D <= ram(i);
		end if;
	end process;

end Behavioral;

