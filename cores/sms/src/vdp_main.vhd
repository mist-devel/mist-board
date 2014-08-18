library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vdp_main is
	port (
		clk:					in  std_logic;			
		vram_A:				out std_logic_vector(13 downto 0);
		vram_D:				in  std_logic_vector(7 downto 0);
		cram_A:				out std_logic_vector(4 downto 0);
		cram_D:				in  std_logic_vector(5 downto 0);
			
		x:						unsigned(8 downto 0);
		y:						unsigned(7 downto 0);
			
		color:				out std_logic_vector (5 downto 0);
					
		display_on:			in  std_logic;
		mask_column0:		in  std_logic;
		overscan:			in  std_logic_vector (3 downto 0);

		bg_address:			in  std_logic_vector (2 downto 0);
		bg_scroll_x:		in  unsigned(7 downto 0);
		bg_scroll_y:		in  unsigned(7 downto 0);
		disable_hscroll:	in  std_logic;
			
		spr_address:		in  std_logic_vector (5 downto 0);
		spr_high_bit:		in  std_logic;
		spr_shift:			in  std_logic;	
		spr_tall:			in  std_logic);	
end vdp_main;

architecture Behavioral of vdp_main is
	
	component vdp_background is
	port (
		clk:					in  std_logic;
		reset:				in  std_logic;
		table_address:		in  std_logic_vector(13 downto 11);
		scroll_x:			in  unsigned(7 downto 0);
		disable_hscroll:	in  std_logic;
		y:						in  unsigned(7 downto 0);
		vram_A:				out std_logic_vector(13 downto 0);
		vram_D:				in  std_logic_vector(7 downto 0);
		color:				out std_logic_vector(4 downto 0);
		priority:			out std_logic);
	end component;
	
	component vdp_sprites is
	port (
		clk:					in  std_logic;
		table_address:		in  std_logic_vector(13 downto 8);
		char_high_bit:		in  std_logic;
		tall:					in  std_logic;
		x:						in  unsigned(8 downto 0);
		y:						in  unsigned(7 downto 0);
		vram_A:				out std_logic_vector(13 downto 0);
		vram_D:				in  std_logic_vector(7 downto 0);
		color:				out std_logic_vector(3 downto 0));
	end component;

	signal bg_y:			unsigned(7 downto 0);
	signal bg_vram_A:		std_logic_vector(13 downto 0);
	signal bg_color:		std_logic_vector(4 downto 0);
	signal bg_priority:	std_logic;
	
	signal spr_vram_A:	std_logic_vector(13 downto 0);
	signal spr_color:		std_logic_vector(3 downto 0);
	
	signal line_reset:	std_logic;

begin

	process (y,bg_scroll_y)
		variable sum: unsigned(8 downto 0);
	begin
		sum := ('0'&y)+('0'&bg_scroll_y);
		if (sum>=224) then
			sum := sum-224;
		end if;
		bg_y <= sum(7 downto 0);
	end process;
	
	line_reset <= '1' when x=512-16 else '0';
		
	vdp_bg_inst: vdp_background
	port map (
		clk				=> clk,
		table_address	=> bg_address,
		reset				=> line_reset,
		disable_hscroll=> disable_hscroll,
		scroll_x 		=> bg_scroll_x,
		y					=> bg_y,
		
		vram_A			=> bg_vram_A,
		vram_D			=> vram_D,		
		color				=> bg_color,
		priority			=> bg_priority);
		
	vdp_spr_inst: vdp_sprites
	port map (
		clk				=> clk,
		table_address	=> spr_address,
		char_high_bit	=> spr_high_bit,
		tall				=> spr_tall,
		x					=> x,
		y					=> y,
		
		vram_A			=> spr_vram_A,
		vram_D			=> vram_D,		
		color				=> spr_color);

	process (x, y, bg_priority, spr_color, bg_color, overscan)
		variable spr_active	: boolean;
		variable bg_active	: boolean;
	begin
		if x<256 and y<192 and (mask_column0='0' or x>=8) then
			spr_active	:= not (spr_color="0000");
			bg_active	:= not (bg_color(3 downto 0)="0000");
			if (bg_priority='0' and spr_active) or (bg_priority='1' and not bg_active) then
				cram_A <= "1"&spr_color;
			else
				cram_A <= bg_color;
			end if;
		else
			cram_A <= "1"&overscan;
		end if;
	end process;
	
	vram_A <= spr_vram_A when x>=256 and x<384 else bg_vram_A;

	color <= cram_D;

end Behavioral;

