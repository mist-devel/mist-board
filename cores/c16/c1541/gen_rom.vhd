-- altera message_off 10306

library ieee;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

entity gen_rom is

	generic 
	(
		INIT_FILE  : string  := "";
		ADDR_WIDTH : natural := 14;
		DATA_WIDTH : natural := 8
	);

	port 
	(
		wrclock   : in  std_logic;
		wraddress : in  std_logic_vector((ADDR_WIDTH - 1) downto 0) := (others => '0');
		data	    : in  std_logic_vector((DATA_WIDTH - 1) downto 0) := (others => '0');
		wren      : in  std_logic := '0';

		rdclock   : in  std_logic;
		rdaddress : in  std_logic_vector((ADDR_WIDTH - 1) downto 0);
		q         : out std_logic_vector((DATA_WIDTH - 1) downto 0);
		cs        : in  std_logic := '1'
	);

end gen_rom;

architecture rtl of gen_rom is

	subtype word_t is std_logic_vector((DATA_WIDTH-1) downto 0);
	type memory_t is array(2**ADDR_WIDTH-1 downto 0) of word_t;

	shared variable ram : memory_t;
	
	attribute ram_init_file : string;
	attribute ram_init_file of ram : variable is INIT_FILE;
	
	signal q0 : std_logic_vector((DATA_WIDTH - 1) downto 0);
	

begin

	q<= q0 when cs = '1' else (others => '1');

	-- WR Port
	process(wrclock) begin
		if(rising_edge(wrclock)) then 
			if(wren = '1') then
				ram(to_integer(unsigned(wraddress))) := data;
			end if;
		end if;
	end process;

	-- RD Port
	process(rdclock) begin
		if(rising_edge(rdclock)) then 
			 q0 <= ram(to_integer(unsigned(rdaddress)));
		end if;
	end process;

end rtl;
