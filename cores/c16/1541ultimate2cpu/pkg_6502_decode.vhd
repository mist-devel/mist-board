
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

package pkg_6502_decode is

    function is_absolute(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_abs_jump(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_immediate(inst: std_logic_vector(7 downto 0)) return boolean;    
    function is_implied(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_stack(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_push(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_zeropage(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_indirect(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_relative(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_load(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_store(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_shift(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_alu(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_rmw(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_jump(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_postindexed(inst: std_logic_vector(7 downto 0)) return boolean;
    function is_illegal(inst: std_logic_vector(7 downto 0)) return boolean;
    
    function stack_idx(inst: std_logic_vector(7 downto 0)) return std_logic_vector;
    
    constant c_stack_idx_brk : std_logic_vector(1 downto 0) := "00";
    constant c_stack_idx_jsr : std_logic_vector(1 downto 0) := "01";
    constant c_stack_idx_rti : std_logic_vector(1 downto 0) := "10";
    constant c_stack_idx_rts : std_logic_vector(1 downto 0) := "11";

    function select_index_y (inst: std_logic_vector(7 downto 0)) return boolean;
    function store_a_from_alu (inst: std_logic_vector(7 downto 0)) return boolean;
    function load_a (inst: std_logic_vector(7 downto 0)) return boolean;
    function load_x (inst: std_logic_vector(7 downto 0)) return boolean;
    function load_y (inst: std_logic_vector(7 downto 0)) return boolean;
    function shifter_in_select (inst: std_logic_vector(7 downto 0)) return std_logic_vector;
    function x_to_alu (inst: std_logic_vector(7 downto 0)) return boolean;
end;

package body pkg_6502_decode is

    function is_absolute(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        -- 4320 = X11X | 1101
        if inst(3 downto 2)="11" then
            return true;
        elsif inst(4 downto 2)="110" and inst(0)='1' then
            return true;
        end if;
        return false;
    end function;

    function is_jump(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        return inst(7 downto 6)="01" and inst(3 downto 0)=X"C";
    end function;

    function is_immediate(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        -- 76543210 = 1XX000X0
        if inst(7)='1' and inst(4 downto 2)="000" and inst(0)='0' then
            return true;
        -- 76543210 = XXX010X1
        elsif inst(4 downto 2)="010" and inst(0)='1' then
            return true;
        end if;
        return false;
    end function;
    
    function is_implied(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        -- 4320 = X100
        return inst(3 downto 2)="10" and inst(0)='0';
    end function;

    function is_stack(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        -- 76543210
        -- 0xx0x000
        return inst(7)='0' and inst(4)='0' and inst(2 downto 0)="000";
    end function;

    function is_push(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        -- we already know it's a stack operation, so only the direction is important
        return inst(5)='0';
    end function;

    function is_zeropage(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        if inst(3 downto 2)="01" then
            return true;
        elsif inst(3 downto 2)="00" and inst(0)='1' then
            return true;
        end if;
        return false;
    end function;

    function is_indirect(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        return (inst(3 downto 2)="00" and inst(0)='1');
    end function;

    function is_relative(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        return (inst(4 downto 0)="10000");
    end function;

    function is_store(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        return (inst(7 downto 5)="100");
    end function;

    function is_shift(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        if inst(7)='1' and inst(4 downto 2)="010" then
            return false;
        end if;
        return (inst(1)='1');
    end function;

    function is_alu(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        if inst(7)='0' and inst(4 downto 1)="0101" then
            return false;
        end if;
        return (inst(0)='1');
    end function;

    function is_load(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        return not is_store(inst) and not is_rmw(inst);
    end function;

    function is_rmw(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        return inst(1)='1' and inst(7 downto 6)/="10";
    end function;

    function is_abs_jump(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        return is_jump(inst) and inst(5)='0';
    end function;

    function is_postindexed(inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        return inst(4)='1';
    end function;

    function stack_idx(inst: std_logic_vector(7 downto 0)) return std_logic_vector is
    begin
        return inst(6 downto 5);
    end function;

    function select_index_y (inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        if inst(4)='1' and inst(2)='0' and inst(0)='1' then -- XXX1X0X1
            return true;
        elsif inst(7 downto 6)="10" and inst(2 downto 1)="11" then -- 10XXX11X
            return true;
        end if;
        return false;
    end function;        

--    function flags_bit_group (inst: std_logic_vector(7 downto 0)) return boolean is
--    begin
--        return inst(2 downto 0)="100";
--    end function;
--    
--    function flags_alu_group (inst: std_logic_vector(7 downto 0)) return boolean is
--    begin
--        return inst(1 downto 0)="01";  -- could also choose not to look at bit 1 (overlap)
--    end function;
--
--    function flags_shift_group (inst: std_logic_vector(7 downto 0)) return boolean is
--    begin
--        return inst(1 downto 0)="10";  -- could also choose not to look at bit 0 (overlap)
--    end function;

    function load_a (inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        return (inst = X"68");
    end function;
    
    function store_a_from_alu (inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        -- 0XXXXXX1 or alu operations "lo"
        -- 1X100001 or alu operations "hi" (except store and cmp)
        -- 0XX01010 (implied)
        return (inst(7)='0' and inst(4 downto 0)="01010") or
               (inst(7)='0' and inst(0)='1') or
               (inst(7)='1' and inst(0)='1' and inst(5)='1');
    end function;

    function load_x (inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        -- 101XXX1X or 1100101-  (for SAX #)
        if inst(7 downto 1)="1100101" then
            return true;
        end if;
        return inst(7 downto 5)="101" and inst(1)='1' and not is_implied(inst);
    end function;

    function load_y (inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        -- 101XXX00
        return inst(7 downto 5)="101" and inst(1 downto 0)="00" and not is_implied(inst);
    end function;

    function shifter_in_select (inst: std_logic_vector(7 downto 0)) return std_logic_vector is
    begin
        -- 00 = none, 01 = memory, 10 = A, 11 = A & M
        if inst(4 downto 2)="010" and inst(7)='0' then
            return inst(1 downto 0);
        end if;
        return "01";
    end function;

--    function shifter_in_select (inst: std_logic_vector(7 downto 0)) return std_logic_vector is
--    begin
--        -- 0=memory, 1=A
--        if inst(4 downto 1)="0101" and inst(7)='0' then
--            return "01";
--        end if;
--        return "10";
--    end function;
    
    function is_illegal (inst: std_logic_vector(7 downto 0)) return boolean is
        type t_my16bit_array is array(natural range <>) of std_logic_vector(15 downto 0);
        constant c_illegal_map : t_my16bit_array(0 to 15) := (
            X"989C", X"9C9C", X"888C", X"9C9C", X"889C", X"9C9C", X"889C", X"9C9C", 
            X"8A8D", X"D88C", X"8888", X"888C", X"888C", X"9C9C", X"888C", X"9C9C" );
        variable row : std_logic_vector(15 downto 0);
    begin
        row := c_illegal_map(conv_integer(inst(7 downto 4)));
        return (row(conv_integer(inst(3 downto 0))) = '1');
    end function;

    function x_to_alu (inst: std_logic_vector(7 downto 0)) return boolean is
    begin
        -- 1-00101-  8A,8B,CA,CB
        return inst(5 downto 1)="00101" and inst(7)='1';
    end function;
    
end;
