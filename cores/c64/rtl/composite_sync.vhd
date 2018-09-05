---------------------------------------------------------------------------------
-- composite_sync by Dar (darfpga@aol.fr)
-- http://darfpga.blogspot.fr
--
-- Generate composite sync and blank for tv mode from h/v syncs
--
---------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all;

entity composite_sync is
port(
	clk32 : in std_logic;
	hsync : in std_logic;
	vsync : in std_logic;
	ntsc  : in std_logic;
	hsync_out : out std_logic;
	vsync_out : out std_logic;
	blank : out std_logic
);
end composite_sync ;

architecture struct of composite_sync is

	signal clk_cnt : std_logic_vector(1 downto 0);
	signal vsync_r : std_logic;
	signal hsync_r : std_logic;
	signal hsync_r0 : std_logic;
	signal vblank : std_logic;
	signal hblank : std_logic;

begin

blank <= hblank or vblank;

process(clk32)
	variable  dot_count : integer range 0 to 1023 := 0;
	variable line_count : integer range 0 to 511 := 0;
	begin
	if falling_edge(clk32) then
		hsync_r0 <= hsync;
		if hsync_r0 = '0' and hsync = '1' then
			clk_cnt <= "00";
		else
			clk_cnt <= clk_cnt + '1';
		end if;
	end if;

	if rising_edge(clk32) then
		if clk_cnt = "00" then
			vsync_r <= vsync;
			hsync_r <= hsync;

			if hsync_r = '0' and hsync = '1' then
				dot_count := 0;
				line_count := line_count + 1;
			else
				dot_count := dot_count + 1;
			end if;

			if vsync_r = '0' and vsync = '1' then
				line_count := 0;
			end if;
			
			if ntsc = '1' then
				if dot_count  = 510 then    hblank <= '1'; end if;
				if dot_count  = 010 then hsync_out <= '1'; end if;
				if dot_count  = 048 then hsync_out <= '0'; end if;
				if dot_count  = 096 then    hblank <= '0'; end if;

				if line_count = 260 then    vblank <= '1'; end if;
				if line_count = 262 then vsync_out <= '1'; end if;
				if line_count = 008 then vsync_out <= '0'; end if;
				if line_count = 010 then    vblank <= '0'; end if;
			else
				if dot_count  = 495 then    hblank <= '1'; end if;
				if dot_count  = 010 then hsync_out <= '1'; end if;
				if dot_count  = 048 then hsync_out <= '0'; end if;
				if dot_count  = 094 then    hblank <= '0'; end if;

				if line_count = 306 then    vblank <= '1'; end if;
				if line_count = 308 then vsync_out <= '1'; end if;
				if line_count = 004 then vsync_out <= '0'; end if;
				if line_count = 006 then    vblank <= '0'; end if;
			end if;

		end if;
	end if;
end process;



end architecture;