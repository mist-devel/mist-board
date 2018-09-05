library ieee;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

entity c1541_rom is
	port 
	(
		wrclock	 : in  std_logic;
		wraddress : in  std_logic_vector(13 downto 0);
		data	    : in  std_logic_vector(7 downto 0);
		wren      : in  std_logic := '0';

		rdclock	 : in  std_logic;
		rdaddress : in  std_logic_vector(13 downto 0);
		q         : out std_logic_vector(7 downto 0)
	);

end;

architecture rtl of c1541_rom is

	subtype word_t is std_logic_vector(7 downto 0);
	type memory_t is array(16383 downto 0) of word_t;

	shared variable ram : memory_t;
	
	attribute ram_init_file : string;
	attribute ram_init_file of ram : variable is "c1541/c1541_rom.mif";	

begin

	-- Port A
	process(wrclock)
	begin
	if(rising_edge(wrclock)) then 
		if(wren = '1') then
			ram(to_integer(unsigned(wraddress))) := data;
		end if;
	end if;
	end process;

	-- Port B 
	process(rdclock)
	begin
	if(rising_edge(rdclock)) then 
  	    q <= ram(to_integer(unsigned(rdaddress)));
	end if;
	end process;

end rtl;
