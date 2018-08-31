
library ieee;
use ieee.std_logic_1164.all;

package pkg_6502_defs is

    subtype t_amux is integer range 0 to 3;
    constant c_amux_vector  : t_amux := 0;
    constant c_amux_addr    : t_amux := 1;
    constant c_amux_stack   : t_amux := 2;
    constant c_amux_pc      : t_amux := 3;
    
    type t_pc_oper is  (keep, increment, copy, from_alu);
    type t_adl_oper is (keep, increment, add_idx, load_bus, copy_dreg);
    type t_adh_oper is (keep, increment, clear, load_bus);
    type t_sp_oper is  (keep, increment, decrement);
    type t_dout_mux is (reg_d, reg_accu, reg_axy, reg_flags, reg_pcl, reg_pch, shift_res);
end;
