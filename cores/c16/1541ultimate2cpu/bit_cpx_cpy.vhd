
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity bit_cpx_cpy is
port (
    operation       : in  std_logic_vector(2 downto 0);
    enable          : in  std_logic := '1'; -- instruction(1 downto 0)="00"
    
    n_in            : in  std_logic;
    v_in            : in  std_logic;
    z_in            : in  std_logic;
    c_in            : in  std_logic;
    
    data_in         : in  std_logic_vector(7 downto 0);
    a_reg           : in  std_logic_vector(7 downto 0);
    x_reg           : in  std_logic_vector(7 downto 0);
    y_reg           : in  std_logic_vector(7 downto 0);
    
    n_out           : out std_logic;
    v_out           : out std_logic;
    z_out           : out std_logic;
    c_out           : out std_logic );
    
end bit_cpx_cpy;

architecture gideon of bit_cpx_cpy is
    signal reg      : std_logic_vector(7 downto 0) := (others => '0');
    signal diff     : std_logic_vector(8 downto 0) := (others => '0');
    signal zero_cmp : std_logic;
    signal zero_ld  : std_logic;
    signal zero_bit : std_logic;

    signal oper4    : std_logic_vector(3 downto 0);
begin
-- *** BIT *** *** STY LDY CPY CPX
    reg <= x_reg when operation(0)='1' else y_reg;

    diff     <= ('1' & reg) - ('0' & data_in);
    zero_cmp <= '1' when diff(7 downto 0)=X"00" else '0';
    zero_ld  <= '1' when data_in=X"00" else '0';
    zero_bit <= '1' when (data_in and a_reg)=X"00" else '0';
    
    oper4 <= enable & operation;

    with oper4 select c_out <=
        diff(8)     when "1110" | "1111", -- CPX / CPY
        c_in        when others;

    with oper4 select z_out <=
        zero_cmp    when "1110" | "1111", -- CPX / CPY
        zero_ld     when "1101",
        zero_bit    when "1001",
        z_in        when others;

    with oper4 select n_out <=
        diff(7)     when "1110" | "1111", -- CPX / CPY
        data_in(7)  when "1101" | "1001", -- LDY / BIT
        n_in        when others;

    with oper4 select v_out <=
        data_in(6)  when "1001", -- BIT
        v_in        when others;

end gideon;
