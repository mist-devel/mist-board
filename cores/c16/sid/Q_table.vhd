-------------------------------------------------------------------------------
--
-- (C) COPYRIGHT 2010 Gideon's Logic Architectures'
--
-------------------------------------------------------------------------------
-- 
-- Author: Gideon Zweijtzer (gideon.zweijtzer (at) gmail.com)
--
-- Note that this file is copyrighted, and is not supposed to be used in other
-- projects without written permission from the author.
--
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Q_table is
port (
    Q_reg       : in  unsigned(3 downto 0);
    filter_q    : out signed(17 downto 0) );
end Q_table;

architecture Gideon of Q_table is

    type t_18_bit_array is array(natural range <>) of signed(17 downto 0);
    function create_factors(max_Q: real) return t_18_bit_array is
        constant critical : real := 0.70710678; -- no resonance at 0.5*sqrt(2)
        variable q_step   : real;
        variable q        : real;
        variable scaled   : real;
        variable ret      : t_18_bit_array(0 to 15);
    begin
        q_step := (max_Q - critical) / 15.0; -- linear
        for i in 0 to 15 loop
            q := critical + (real(i) * q_step);
            scaled := 65536.0 / q;
            ret(i) := to_signed(integer(scaled), 18);
        end loop;
        return ret;
    end function;

    constant c_table : t_18_bit_array(0 to 15) := create_factors(1.8);
begin
    filter_q <= c_table(to_integer(Q_reg));
end Gideon;
