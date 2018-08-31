
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity shifter is
port (
    operation       : in  std_logic_vector(2 downto 0);
    enable          : in  std_logic := '1'; -- instruction(1)
    
    c_in            : in  std_logic;
    n_in            : in  std_logic;
    z_in            : in  std_logic;
    
    data_in         : in  std_logic_vector(7 downto 0);
    
    c_out           : out std_logic;
    n_out           : out std_logic;
    z_out           : out std_logic;
    
    data_out        : out std_logic_vector(7 downto 0) := X"00");

end shifter;

architecture gideon of shifter is
    signal data_out_i   : std_logic_vector(7 downto 0) := X"00";
    signal zero         : std_logic := '0';
    signal oper4        : std_logic_vector(3 downto 0) := X"0";
begin
-- ASL $nn	ROL $nn	LSR $nn	ROR $nn	STX $nn	LDX $nn	DEC $nn	INC $nn

    with operation select data_out_i <= 
        data_in(6 downto 0) & '0'   when "000",
        data_in(6 downto 0) & c_in  when "001",
        '0' & data_in(7 downto 1)   when "010",
        c_in & data_in(7 downto 1)  when "011",
        data_in - 1                 when "110",
        data_in + 1                 when "111",
        data_in                     when others;
        
    zero <= '1' when data_out_i = X"00" else '0';
    
    oper4 <= enable & operation;

    with oper4 select c_out <=
        data_in(7)  when "1000" | "1001",
        data_in(0)  when "1010" | "1011",
        c_in        when others;

    with oper4 select z_out <=
        zero        when "1000" | "1001" | "1010" | "1011" | "1101" | "1110" | "1111",
        z_in        when others;

    with oper4 select n_out <=
        data_out_i(7) when "1000" | "1001" | "1010" | "1011" | "1101" | "1110" | "1111",
        n_in          when others;
    
    data_out <= data_out_i when enable='1' else data_in;

end gideon;