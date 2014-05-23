--
-- ZX81 PS2 to keyboard matrix encoder
-- Author : Daniel Wallner
-- http://www.beyondlogic.org/keyboard/keybrd.htm
--

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity PS2_MatrixEncoder is
	port(
		Clk							: in std_logic;
		Reset_n						: in std_logic;
		Tick1us						: in std_logic;
		PS2_Clk						: in std_logic;
		PS2_Data					: in std_logic;
		Key_Addr					: in std_logic_vector(7 downto 0);
		Key_Data					: out std_logic_vector(4 downto 0)
	);
end PS2_MatrixEncoder;

architecture rtl of PS2_MatrixEncoder is

	signal	PS2_Sample		: std_logic;
	signal	PS2_Data_s		: std_logic;

	signal	RX_Bit_Cnt		: unsigned(3 downto 0);
	signal	RX_Byte			: unsigned(2 downto 0);
	signal	RX_ShiftReg		: std_logic_vector(7 downto 0);
	signal	RX_Release		: std_logic;
	signal	RX_Received		: std_logic;

	signal	LookUp			: std_logic_vector(7 downto 0);

	signal	Matrix_Set		: std_logic;
	signal	Matrix_Clear	: std_logic;
	signal	Matrix_Wr_Addr	: unsigned(7 downto 0);

	type Matrix_Image is array (natural range <>) of std_logic_vector(4 downto 0);
	signal	Matrix			: Matrix_Image(0 to 7);

begin

	process (Clk, Reset_n)
		variable PS2_Data_r		: std_logic_vector(1 downto 0);
		variable PS2_Clk_r		: std_logic_vector(1 downto 0);
		variable PS2_Clk_State	: std_logic;
	begin
		if Reset_n = '0' then
			PS2_Sample <= '0';
			PS2_Data_s <= '0';
			PS2_Data_r := "11";
			PS2_Clk_r := "11";
			PS2_Clk_State := '1';
		elsif Clk'event and Clk = '1' then
			if Tick1us = '1' then
				PS2_Sample <= '0';

				-- Deglitch
				if PS2_Data_r = "00" then
					PS2_Data_s <= '0';
				end if;
				if PS2_Data_r = "11" then
					PS2_Data_s <= '1';
				end if;
				if PS2_Clk_r = "00" then
					if PS2_Clk_State = '1' then
						PS2_Sample <= '1';
					end if;
					PS2_Clk_State := '0';
				end if;
				if PS2_Clk_r = "11" then
					PS2_Clk_State := '1';
				end if;

				-- Double synchronise
				PS2_Data_r(1) := PS2_Data_r(0);
				PS2_Clk_r(1) := PS2_Clk_r(0);
				PS2_Data_r(0) := PS2_Data;
				PS2_Clk_r(0) := PS2_Clk;
			end if;
		end if;
	end process;

	process (Clk, Reset_n)
		variable Cnt : integer;
	begin
		if Reset_n = '0' then
			RX_Bit_Cnt <= (others => '0');
			RX_ShiftReg <= (others => '0');
			RX_Received <= '0';
			Cnt := 0;
		elsif Clk'event and Clk = '1' then
			RX_Received <= '0';
			if Tick1us = '1' then

				if PS2_Sample = '1' then
					if RX_Bit_Cnt = "0000" then
						if PS2_Data_s = '0' then -- Start bit
							RX_Bit_Cnt <= RX_Bit_Cnt + 1;
						end if;
					elsif RX_Bit_Cnt = "1001" then -- Parity bit
						RX_Bit_Cnt <= RX_Bit_Cnt + 1;
						-- Ignoring parity
					elsif RX_Bit_Cnt = "1010" then -- Stop bit
						if PS2_Data_s = '1' then
							RX_Received <= '1';
						end if;
						RX_Bit_Cnt <= "0000";
					else
						RX_Bit_Cnt <= RX_Bit_Cnt + 1;
						RX_ShiftReg(6 downto 0) <= RX_ShiftReg(7 downto 1);
						RX_ShiftReg(7) <= PS2_Data_s;
					end if;
				end if;

				-- TimeOut
				if PS2_Sample = '1' then
					Cnt := 0;
				elsif Cnt = 127 then
					RX_Bit_Cnt <= "0000";
					Cnt := 0;
				else
					Cnt := Cnt + 1;
				end if;
			end if;
		end if;
	end process;

	process (Clk, Reset_n)
	begin
		if Reset_n = '0' then
			RX_Byte <= (others => '0');
			RX_Release <= '0';
			Matrix_Set <= '0';
			Matrix_Clear <= '0';
			Matrix_Wr_Addr <= (others => '0');
		elsif Clk'event and Clk = '1' then
			Matrix_Set <= '0';
			Matrix_Clear <= '0';

			if RX_Received = '1' then
				RX_Byte <= RX_Byte + 1;
				if RX_ShiftReg = x"F0" then
					RX_Release <= '1';
				elsif RX_ShiftReg = x"E0" then
				else
					RX_Release <= '0';
					-- Normal key press
					if unsigned(LookUp) /= 0 and RX_Release = '0' then
						Matrix_Wr_Addr <= unsigned(LookUp);
						Matrix_Set <= '1';
					end if;
					-- Normal key release
					if unsigned(LookUp) /= 0 and RX_Release = '1' then
						Matrix_Wr_Addr <= unsigned(LookUp);
						Matrix_Clear <= '1';
					end if;
				end if;
			end if;
		end if;
	end process;

	-- ZX81 keymap:
	-- shift, z, x, c, v
	-- a, s, d, f, g
	-- q, w, e, r, t
	-- 1, 2, 3, 4, 5
	-- 0, 9, 8, 7, 6
	-- p, o, i, u, y
	-- return, l, k, j, h
	-- space, ., m, n, b

	process (RX_ShiftReg)
	begin
		case RX_ShiftReg is
		when x"12" => LookUp <= "00000001"; -- shift
		when x"59" => LookUp <= "00000001"; -- shift
		when x"1a" => LookUp <= "00000010"; -- z
		when x"22" => LookUp <= "00000100"; -- x
		when x"21" => LookUp <= "00001000"; -- c
		when x"2a" => LookUp <= "00010000"; -- v
		when x"1c" => LookUp <= "00100001"; -- a
		when x"1b" => LookUp <= "00100010"; -- s
		when x"23" => LookUp <= "00100100"; -- d
		when x"2b" => LookUp <= "00101000"; -- f
		when x"34" => LookUp <= "00110000"; -- g
		when x"15" => LookUp <= "01000001"; -- q
		when x"1d" => LookUp <= "01000010"; -- w
		when x"24" => LookUp <= "01000100"; -- e
		when x"2d" => LookUp <= "01001000"; -- r
		when x"2c" => LookUp <= "01010000"; -- t
		when x"16" => LookUp <= "01100001"; -- 1
		when x"69" => LookUp <= "01100001"; -- 1
		when x"1e" => LookUp <= "01100010"; -- 2
		when x"72" => LookUp <= "01100010"; -- 2
		when x"26" => LookUp <= "01100100"; -- 3
		when x"7a" => LookUp <= "01100100"; -- 3
		when x"25" => LookUp <= "01101000"; -- 4
		when x"6b" => LookUp <= "01101000"; -- 4
		when x"2e" => LookUp <= "01110000"; -- 5
		when x"73" => LookUp <= "01110000"; -- 5
		when x"45" => LookUp <= "10000001"; -- 0
		when x"70" => LookUp <= "10000001"; -- 0
		when x"46" => LookUp <= "10000010"; -- 9
		when x"7d" => LookUp <= "10000010"; -- 9
		when x"3e" => LookUp <= "10000100"; -- 8
		when x"75" => LookUp <= "10000100"; -- 8
		when x"3d" => LookUp <= "10001000"; -- 7
		when x"6c" => LookUp <= "10001000"; -- 7
		when x"36" => LookUp <= "10010000"; -- 6
		when x"74" => LookUp <= "10010000"; -- 6
		when x"4d" => LookUp <= "10100001"; -- p
		when x"44" => LookUp <= "10100010"; -- o
		when x"43" => LookUp <= "10100100"; -- i
		when x"3c" => LookUp <= "10101000"; -- u
		when x"35" => LookUp <= "10110000"; -- y
		when x"5a" => LookUp <= "11000001"; -- return
		when x"4b" => LookUp <= "11000010"; -- l
		when x"42" => LookUp <= "11000100"; -- k
		when x"3b" => LookUp <= "11001000"; -- j
		when x"33" => LookUp <= "11010000"; -- h
		when x"29" => LookUp <= "11100001"; -- Space
		when x"49" => LookUp <= "11100010"; -- .
		when x"3a" => LookUp <= "11100100"; -- m
		when x"31" => LookUp <= "11101000"; -- n
		when x"32" => LookUp <= "11110000"; -- b
		when others => LookUp <= "00000000";
		end case;
	end process;

	process (Clk, Reset_n)
	begin
		if Reset_n = '0' then
			Matrix <= (others => (others => '0'));
		elsif Clk'event and Clk = '1' then
			if RX_ShiftReg = x"aa" and RX_Received = '1' then
				Matrix <= (others => (others => '0'));
			end if;
			if Matrix_Set = '1' then
				Matrix(to_integer(Matrix_Wr_Addr(7 downto 5))) <=
					Matrix(to_integer(Matrix_Wr_Addr(7 downto 5))) or
					std_logic_vector(Matrix_Wr_Addr(4 downto 0));
			end if;
			if Matrix_Clear = '1' then
				Matrix(to_integer(Matrix_Wr_Addr(7 downto 5))) <=
					Matrix(to_integer(Matrix_Wr_Addr(7 downto 5))) and
					std_logic_vector(not Matrix_Wr_Addr(4 downto 0));
			end if;
		end if;
	end process;

	g_out1 : for i in 0 to 4 generate
		Key_Data(i) <= not ((Matrix(0)(i) and not Key_Addr(0)) or
					(Matrix(1)(i) and not Key_Addr(1)) or
					(Matrix(2)(i) and not Key_Addr(2)) or
					(Matrix(3)(i) and not Key_Addr(3)) or
					(Matrix(4)(i) and not Key_Addr(4)) or
					(Matrix(5)(i) and not Key_Addr(5)) or
					(Matrix(6)(i) and not Key_Addr(6)) or
					(Matrix(7)(i) and not Key_Addr(7)));
	end generate;

end;
