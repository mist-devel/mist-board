
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity alu is
generic (
    support_bcd : boolean := true );
port (
    operation       : in  std_logic_vector(2 downto 0);
    enable          : in  std_logic;

    n_in            : in  std_logic;
    v_in            : in  std_logic;
    z_in            : in  std_logic;
    c_in            : in  std_logic;
    d_in            : in  std_logic;
    
    data_a          : in  std_logic_vector(7 downto 0);
    data_b          : in  std_logic_vector(7 downto 0);
    
    n_out           : out std_logic;
    v_out           : out std_logic;
    z_out           : out std_logic;
    c_out           : out std_logic;
    
    data_out        : out std_logic_vector(7 downto 0));

end alu;

architecture gideon of alu is
    signal data_out_i   : std_logic_vector(7 downto 0) := X"FF";
    signal zero         : std_logic;
    signal sum_c        : std_logic;
    signal sum_n        : std_logic;
    signal sum_z        : std_logic;
    signal sum_v        : std_logic;
    signal sum_result   : std_logic_vector(7 downto 0) := X"FF";    
    signal oper4        : std_logic_vector(3 downto 0);
begin

-- ORA $nn	AND $nn	EOR $nn	ADC $nn	STA $nn	LDA $nn	CMP $nn	SBC $nn

    with oper4 select data_out_i <= 
        data_a or  data_b           when "1000",
        data_a and data_b           when "1001",
        data_a xor data_b           when "1010",
        sum_result                  when "1011" | "1110" | "1111",
        data_b                      when others;

    zero <= '1' when data_out_i = X"00" else '0';
    
    sum: process(data_a, data_b, c_in, operation, d_in)
        variable b     : std_logic_vector(7 downto 0);
        variable sum_l : std_logic_vector(4 downto 0);
        variable sum_h : std_logic_vector(4 downto 0);
    begin
        -- for subtraction invert second operand
        if operation(2)='1' then -- invert b
            b := not data_b;
        else
            b := data_b;
        end if;    

        -- sum_l(4) = carry of lower end, carry in is masked to '1' for CMP
        sum_l := ('0' & data_a(3 downto 0)) + ('0' & b(3 downto 0)) + (c_in or not operation(0));
        sum_h := ('0' & data_a(7 downto 4)) + ('0' & b(7 downto 4)) + sum_l(4);        

        if sum_l(3 downto 0)="0000" and sum_h(3 downto 0)="0000" then
            sum_z <= '1';
        else
            sum_z <= '0';
        end if;

        sum_n  <= sum_h(3);
        sum_c  <= sum_h(4);
        sum_v  <= (sum_h(3) xor data_a(7)) and (sum_h(3) xor data_b(7) xor operation(2)); 

        -- fix up in decimal mode (not for CMP!)
        if d_in='1' and support_bcd then
            if operation(2)='0' then -- ADC
                sum_h := ('0' & data_a(7 downto 4)) + ('0' & b(7 downto 4));
                        
                if sum_l(4) = '1' or sum_l(3 downto 2)="11" or sum_l(3 downto 1)="101" then -- >9 (10-11, 12-15)
                    sum_l := sum_l + ('0' & X"6"); 
                    sum_l(4) := '1';
                end if;

                -- negative when sum_h + sum_l(4) = 8
                sum_h := sum_h + sum_l(4);
                sum_n <= sum_h(3);

                if sum_h(4) = '1' or sum_h(3 downto 2)="11" or sum_h(3 downto 1)="101" then --
                    sum_h := sum_h + 6;
                    sum_c <= '1';
                end if;
                
                -- carry and overflow are output after fix
--                sum_c  <= sum_h(4);
--                sum_v  <= (sum_h(3) xor data_a(7)) and (sum_h(3) xor data_b(7) xor operation(2)); 

            elsif operation(0)='1' then -- SBC
                -- flags are not adjusted in subtract mode
                if sum_l(4) = '0' then
                    sum_l := sum_l - 6;
                end if;
                if sum_h(4) = '0' then
                    sum_h := sum_h - 6;
                end if;
            end if;
        end if;

        sum_result <= sum_h(3 downto 0) & sum_l(3 downto 0);
    end process;

    oper4 <= enable & operation;
    
    with oper4 select c_out <=
        sum_c       when "1011" | "1111" | "1110",
        c_in        when others;

    with oper4 select z_out <=
        sum_z       when "1011" | "1111" | "1110",
        zero        when "1000" | "1001" | "1010" | "1101",
        z_in        when others;

    with oper4 select n_out <=
        sum_n         when "1011" | "1111",
        data_out_i(7) when "1000" | "1001" | "1010" | "1101" | "1110",
        n_in          when others;
    
    with oper4 select v_out <=
        sum_v         when "1011" | "1111",
        v_in          when others;

    data_out <= data_out_i;
end gideon;