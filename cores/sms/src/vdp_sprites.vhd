library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vdp_sprites is
	port (clk				: in  std_logic;
			table_address	: in  STD_LOGIC_VECTOR (13 downto 8);
			char_high_bit	: in  std_logic;
			tall				: in  std_logic;
			vram_A			: out STD_LOGIC_VECTOR (13 downto 0);
			vram_D			: in  STD_LOGIC_VECTOR (7 downto 0);
			x					: in  unsigned (8 downto 0);
			y					: in  unsigned (7 downto 0);
			color				: out STD_LOGIC_VECTOR (3 downto 0));
end vdp_sprites;

architecture Behavioral of vdp_sprites is

	component vpd_sprite_shifter is
	port( clk	: in  std_logic;
			x		: in  unsigned (7 downto 0);
			spr_x	: in  unsigned (7 downto 0);
			spr_d0: in  std_logic_vector (7 downto 0);
			spr_d1: in  std_logic_vector (7 downto 0);
			spr_d2: in  std_logic_vector (7 downto 0);
			spr_d3: in  std_logic_vector (7 downto 0);
			color : out std_logic_vector (3 downto 0);
			active: out std_logic);
	end component;

	constant WAITING:	integer := 0;
	constant COMPARE:	integer := 1;
	constant LOAD_N:	integer := 2;
	constant LOAD_X:	integer := 3;
	constant LOAD_0:	integer := 4;
	constant LOAD_1:	integer := 5;
	constant LOAD_2:	integer := 6;
	constant LOAD_3:	integer := 7;

	signal state:		integer	:= WAITING;
	signal count:		integer range 0 to 7;
	signal index:		unsigned(5 downto 0);
	signal data_address: std_logic_vector(13 downto 2);

	type tenable	is array (0 to 7) of boolean;
	type tx			is array (0 to 7) of unsigned(7 downto 0);
	type tdata		is array (0 to 7) of std_logic_vector(7 downto 0);
	signal enable:	tenable;
	signal spr_x:	tx;
	signal spr_d0:	tdata;
	signal spr_d1:	tdata;
	signal spr_d2:	tdata;
	signal spr_d3:	tdata;

	type tcolor is array (0 to 7) of std_logic_vector(3 downto 0);
	signal spr_color:	tcolor;
	signal active:		std_logic_vector(7 downto 0);
	
begin
	shifters:
	for i in 0 to 7 generate
	begin
		shifter: vpd_sprite_shifter
		port map(clk	=> clk,
					x		=> x(7 downto 0),
					spr_x	=> spr_x(i),
					spr_d0=> spr_d0(i),
					spr_d1=> spr_d1(i),
					spr_d2=> spr_d2(i),
					spr_d3=> spr_d3(i),
					color => spr_color(i),
					active=> active(i));
	end generate;

	with state select
	vram_a <=	table_address&"00"&std_logic_vector(index)		when COMPARE,
					table_address&"1"&std_logic_vector(index)&"1"	when LOAD_N,
					table_address&"1"&std_logic_vector(index)&"0"	when LOAD_X,
					data_address&"00"											when LOAD_0,
					data_address&"01"											when LOAD_1,
					data_address&"10"											when LOAD_2,
					data_address&"11"											when LOAD_3,
					(others=>'0') when others;

	process (clk)
		variable y9 	: unsigned(8 downto 0);
		variable d9		: unsigned(8 downto 0);
		variable delta : unsigned(8 downto 0);
	begin
		if rising_edge(clk) then
			
			if x=255 then
				count <= 0;
				enable <= (others=>false);
				state <= COMPARE;
				index <= (others=>'0');
				
			else
				y9 := "0"&y;
				d9 := "0"&unsigned(vram_D);
				if d9>=240 then
					d9 := d9-256;
				end if;
				delta := y9-d9;
				
				case state is
				when COMPARE =>
					if d9=208 then
						state <= WAITING; -- stop
					elsif 0<=delta and ((delta<8 and tall='0') or (delta<16 and tall='1')) then
						enable(count) <= true;
						data_address(5 downto 2) <= std_logic_vector(delta(3 downto 0));
						state <= LOAD_N;
					else
						if index<63 then
							index <= index+1;
						else
							state <= WAITING;
						end if;
					end if;
					
				when LOAD_N =>
					data_address(13) <= char_high_bit;
					data_address(12 downto 6) <= vram_d(7 downto 1);
					if tall='0' then
						data_address(5) <= vram_d(0);
					end if;
					state <= LOAD_X;
					
				when LOAD_X =>
					spr_x(count)	<= unsigned(vram_d);
					state <= LOAD_0;
					
				when LOAD_0 =>
					spr_d0(count)	<= vram_d;
					state	<= LOAD_1;
					
				when LOAD_1 =>
					spr_d1(count)	<= vram_d;
					state	<= LOAD_2;
					
				when LOAD_2 =>
					spr_d2(count)	<= vram_d;
					state	<= LOAD_3;
					
				when LOAD_3 =>
					spr_d3(count)	<= vram_d;
					if (count<7) then
						state	<= COMPARE;
						index	<= index+1;
						count	<= count+1;
					else
						state <= WAITING;
					end if;
					
				when others =>
				end case;
			end if;
		end if;
	end process;

	process (clk)
	begin
		if rising_edge(clk) then
			if enable(0) and active(0)='1' then
				color <= spr_color(0);
			elsif enable(1) and active(1)='1' then
				color <= spr_color(1);
			elsif enable(2) and active(2)='1' then
				color <= spr_color(2);
			elsif enable(3) and active(3)='1' then
				color <= spr_color(3);
			elsif enable(4) and active(4)='1' then
				color <= spr_color(4);
			elsif enable(5) and active(5)='1' then
				color <= spr_color(5);
			elsif enable(6) and active(6)='1' then
				color <= spr_color(6);
			elsif enable(7) and active(7)='1' then
				color <= spr_color(7);
			else
				color <= (others=>'0');
			end if;
		end if;
	end process;

end Behavioral;

