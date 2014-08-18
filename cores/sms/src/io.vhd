library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity io is
    Port(
		clk:		in		STD_LOGIC;
		WR_n:		in		STD_LOGIC;
		RD_n:		in		STD_LOGIC;
		A:			in		STD_LOGIC_VECTOR (7 downto 0);
		D_in:		in		STD_LOGIC_VECTOR (7 downto 0);
		D_out:	out	STD_LOGIC_VECTOR (7 downto 0);
		J1_up:	in 	STD_LOGIC;
		J1_down:	in 	STD_LOGIC;
		J1_left:	in 	STD_LOGIC;
		J1_right:in 	STD_LOGIC;
		J1_tl:	in 	STD_LOGIC;
		J1_tr:	in STD_LOGIC;
		J2_up:	in 	STD_LOGIC;
		J2_down:	in 	STD_LOGIC;
		J2_left:	in 	STD_LOGIC;
		J2_right:in 	STD_LOGIC;
		J2_tl:	in 	STD_LOGIC;
		J2_tr:	in STD_LOGIC;
		RESET:	in 	STD_LOGIC);
end io;

architecture rtl of io is

	signal ctrl:	std_logic_vector(7 downto 0) := (others=>'1');

begin

	process (clk)
	begin
		if rising_edge(clk) then
			if WR_n='0' then
				ctrl <= D_in;
			end if;
		end if;
	end process;
	
--	J1_tr <= ctrl(4) when ctrl(0)='0' else 'Z';
--	J2_tr <= ctrl(6) when ctrl(2)='0' else 'Z';

	process (clk)
	begin
		if rising_edge(clk) then
			if RD_n='0' then
				if A(0)='0' then
					D_out(7) <= J2_down;
					D_out(6) <= J2_up;
					-- 5=j1_tr
					if ctrl(0)='0' then
						D_out(5) <= ctrl(4);
					else
						D_out(5) <= J1_tr;
					end if;
					D_out(4) <= J1_tl;
					D_out(3) <= J1_right;
					D_out(2) <= J1_left;
					D_out(1) <= J1_down;
					D_out(0) <= J1_up;
				else
					-- 7=j2_th
					if ctrl(3)='0' then
						D_out(7) <= ctrl(7);
					else
						D_out(7) <= '1';
					end if;
					-- 6=j1_th
					if ctrl(1)='0' then
						D_out(6) <= ctrl(5);
					else
						D_out(6) <= '1'; 
					end if;
					D_out(5) <= '1';
					D_out(4) <= '1';
					-- 4=j2_tr
					if ctrl(2)='0' then
						D_out(3) <= ctrl(6);
					else
						D_out(3) <= J2_tr;
					end if;
					D_out(2) <= J2_tl;
					D_out(1) <= J2_right;
					D_out(0) <= J2_left;
				end if;
			end if;
		end if;
	end process;
	
end rtl;

