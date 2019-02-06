library IEEE;
use IEEE.std_logic_1164.all;

package mos6526 is
component mos6526
    PORT (
	mode     : in  std_logic; -- '0' - 6256, '1' - 8521
	clk      : in  std_logic;
	phi2_p   : in  std_logic;
	phi2_n   : in  std_logic;
	res_n    : in  std_logic;
	cs_n     : in  std_logic;
	rw       : in  std_logic; -- '1' - read, '0' - write
	rs       : in  std_logic_vector(3 downto 0);
	db_in    : in  std_logic_vector(7 downto 0);
	db_out   : out std_logic_vector(7 downto 0);
	pa_in    : in  std_logic_vector(7 downto 0);
	pa_out   : out std_logic_vector(7 downto 0);
	pb_in    : in  std_logic_vector(7 downto 0);
	pb_out   : out std_logic_vector(7 downto 0);
	flag_n   : in  std_logic;
	pc_n     : out std_logic;
	tod      : in  std_logic;
	sp_in    : in  std_logic;
	sp_out   : out std_logic;
	cnt_in   : in  std_logic;
	cnt_out  : out std_logic;
	irq_n    : out std_logic
    );
end component;
end package;