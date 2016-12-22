library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tv_video is
	Port (
		clk8:				in  STD_LOGIC;
		x: 				out unsigned(8 downto 0);
		y:					out unsigned(7 downto 0);
		color:			in  std_logic_vector(5 downto 0);
		hsync:			out std_logic;
		vsync:			out std_logic;
		red:				out std_logic_vector(1 downto 0);
		green:			out std_logic_vector(1 downto 0);
		blue:				out std_logic_vector(1 downto 0));
end tv_video;

architecture Behavioral of tv_video is

	signal hcount:			unsigned(8 downto 0) := (others => '0');
	signal vcount:			unsigned(8 downto 0) := (others => '0');
	signal y9:				unsigned(8 downto 0);
	
	signal in_vbl:			std_logic;
	signal screen_sync:	std_logic;
	signal vbl_sync:		std_logic;
	
	signal line_visible:	std_logic;
	signal line_even:		std_logic;
	signal hblank:			std_logic;
	signal vblank:			std_logic;
	signal visible:		boolean;
	
begin

	process (clk8)
	begin
		if rising_edge(clk8) then
			if hcount=507 then
				hcount <= (others => '0');
				if vcount=261 then
					vcount <= (others=>'0');
				else
					vcount <= vcount + 1;
				end if;
			else
				hcount <= hcount + 1;
			end if;
		end if;
	end process;
	
	process (hcount)
	begin
		if hcount<38 then
			screen_sync <= '0';
		else
			screen_sync <= '1';
		end if;
	end process;
	
	in_vbl <= '1' when vcount<9 else '0';
	
	x					<= hcount-166;
	y9					<= vcount-40;
	y					<= y9(7 downto 0);
	vblank			<= '1' when hcount=0 and vcount=0 else '0';
	hblank			<= '1' when hcount=0 else '0';
	line_visible	<= not in_vbl;
	line_even		<= not vcount(0);
	
	process (vcount,hcount)
	begin
		if vcount<3 or (vcount>=6 and vcount<9) then
			-- _^^^^^_^^^^^ : low pulse = 2.35us
			if hcount<19 or (hcount>=254 and hcount<254+19) then
				vbl_sync <= '0';
			else
				vbl_sync <= '1';
			end if;
		else
			-- ____^^ : high pulse = 4.7us
			if hcount<(254-38) or (hcount>=254 and hcount<508-38) then
				vbl_sync <= '0';
			else
				vbl_sync <= '1';
			end if;
		end if;
	end process;
	
	--process (in_vbl,screen_sync,vbl_sync)
	--begin
	--	if in_vbl='1' then
	--		hsync <= vbl_sync;
	--	else
	--		hsync <= screen_sync;
	--	end if;
	--end process;

	hsync <= screen_sync;
	vsync <= vbl_sync;
	
	visible <= (line_visible = '1' and vcount>=40 and vcount<467);
	
	process (clk8)
	begin
		if rising_edge(clk8) then
			if visible then
				red	<= color(1 downto 0);
				green	<= color(3 downto 2);
				blue	<= color(5 downto 4);
			else
				red	<= (others=>'0');
				green	<= (others=>'0');
				blue	<= (others=>'0');
			end if;
		end if;
	end process;
	
end Behavioral;

