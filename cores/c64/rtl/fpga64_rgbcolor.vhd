-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Copyright 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------
--
-- C64 palette index to 24 bit RGB color
-- 
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

-- -----------------------------------------------------------------------

entity fpga64_rgbcolor is
	port (
		index: in unsigned(3 downto 0);
		r: out unsigned(7 downto 0);
		g: out unsigned(7 downto 0);
		b: out unsigned(7 downto 0)
	);
end fpga64_rgbcolor;

-- -----------------------------------------------------------------------

architecture Behavioral of fpga64_rgbcolor is
begin
	process(index)
	begin
		case index is
		when X"0" => r <= X"00"; g <= X"00"; b <= X"00";
		when X"1" => r <= X"FF"; g <= X"FF"; b <= X"FF";
		when X"2" => r <= X"68"; g <= X"37"; b <= X"2B";
		when X"3" => r <= X"70"; g <= X"A4"; b <= X"B2";
		when X"4" => r <= X"6F"; g <= X"3D"; b <= X"86";
		when X"5" => r <= X"58"; g <= X"8D"; b <= X"43";
		when X"6" => r <= X"35"; g <= X"28"; b <= X"79";
		when X"7" => r <= X"B8"; g <= X"C7"; b <= X"6F";
		when X"8" => r <= X"6F"; g <= X"4F"; b <= X"25";
		when X"9" => r <= X"43"; g <= X"39"; b <= X"00";
		when X"A" => r <= X"9A"; g <= X"67"; b <= X"59";
		when X"B" => r <= X"44"; g <= X"44"; b <= X"44";
		when X"C" => r <= X"6C"; g <= X"6C"; b <= X"6C";
		when X"D" => r <= X"9A"; g <= X"D2"; b <= X"84";
		when X"E" => r <= X"6C"; g <= X"5E"; b <= X"B5";
		when X"F" => r <= X"95"; g <= X"95"; b <= X"95";
		end case;
	end process;
end Behavioral;
