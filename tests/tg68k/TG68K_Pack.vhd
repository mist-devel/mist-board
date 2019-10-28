------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- Copyright (c) 2009-2013 Tobias Gubener                                   --
-- Subdesign fAMpIGA by TobiFlex                                            --
--                                                                          --
-- This source file is free software: you can redistribute it and/or modify --
-- it under the terms of the GNU General Public License as published        --
-- by the Free Software Foundation, either version 3 of the License, or     --
-- (at your option) any later version.                                      --
--                                                                          --
-- This source file is distributed in the hope that it will be useful,      --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of           --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            --
-- GNU General Public License for more details.                             --
--                                                                          --
-- You should have received a copy of the GNU General Public License        --
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.    --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;

package TG68K_Pack is

	type micro_states is (idle, nop, ld_nn, st_nn, ld_dAn1, ld_AnXn1, ld_AnXn2, st_dAn1, ld_AnXnbd1, ld_AnXnbd2, ld_AnXnbd3,
						  ld_229_1, ld_229_2, ld_229_3, ld_229_4, st_229_1, st_229_2, st_229_3, st_229_4,
						  st_AnXn1, st_AnXn2, bra1, bsr1, bsr2, nopnop, dbcc1, movem1, movem2, movem3,
						  andi, op_AxAy, cmpm, link1, link2, unlink1, unlink2, int1, int2, int3, int4, rtr1, rte1,
						  rte2, rte3, rte4, rte5, rtd1, rtd2, trap00, trap0, trap1, trap2, trap3,
						  trap4, trap5, trap6, movec1, movep1, movep2, movep3, movep4, movep5, rota1, bf1,
						  mul1, mul2, mul_end1,  mul_end2, div1, div2, div3, div4, div_end1, div_end2, pack1, pack2, pack3);

	constant opcMOVE        : integer := 0; --
	constant opcMOVEQ       : integer := 1; --
	constant opcMOVESR      : integer := 2; --
	constant opcMOVECCR     : integer := 3; --
	constant opcADD         : integer := 4; --
	constant opcADDQ        : integer := 5; --
	constant opcOR          : integer := 6; --
	constant opcAND         : integer := 7; --
	constant opcEOR         : integer := 8; --
	constant opcCMP         : integer := 9; --
	constant opcROT         : integer := 10; --
	constant opcCPMAW       : integer := 11;
	constant opcEXT         : integer := 12; --
	constant opcABCD        : integer := 13; --
	constant opcSBCD        : integer := 14; --
	constant opcBITS        : integer := 15; --
	constant opcSWAP        : integer := 16; --
	constant opcScc         : integer := 17; --
	constant andiSR         : integer := 18; --
	constant eoriSR         : integer := 19; --
	constant oriSR          : integer := 20; --
	constant opcMULU        : integer := 21; --
	constant opcDIVU        : integer := 22; --
	constant dispouter      : integer := 23; --
	constant rot_nop        : integer := 24; --
	constant ld_rot_cnt     : integer := 25; --
	constant writePC_add    : integer := 26; --
	constant ea_data_OP1    : integer := 27; --
	constant ea_data_OP2    : integer := 28; --
	constant use_XZFlag     : integer := 29; --
	constant get_bfoffset   : integer := 30; --
	constant save_memaddr   : integer := 31; --
	constant opcCHK         : integer := 32; --
	constant movec_rd       : integer := 33; --
	constant movec_wr       : integer := 34; --
	constant Regwrena       : integer := 35; --
	constant update_FC      : integer := 36; --
	constant linksp         : integer := 37; --
	constant movepl         : integer := 38; --
	constant update_ld      : integer := 39; --
	constant OP1addr        : integer := 40; --
	constant write_reg      : integer := 41; --
	constant changeMode     : integer := 42; --
	constant ea_build       : integer := 43; --
	constant trap_chk       : integer := 44; --
	constant store_ea_data  : integer := 45; --
	constant addrlong       : integer := 46; --
	constant postadd        : integer := 47; --
	constant presub         : integer := 48; --
	constant subidx         : integer := 49; --
	constant no_Flags       : integer := 50; --
	constant use_SP         : integer := 51; --
	constant to_CCR         : integer := 52; --
	constant to_SR          : integer := 53; --
	constant OP2out_one     : integer := 54; --
	constant OP1out_zero    : integer := 55; --
	constant mem_addsub     : integer := 56; --
	constant addsub         : integer := 57; --
	constant directPC       : integer := 58; --
	constant direct_delta   : integer := 59; --
	constant directSR       : integer := 60; --
	constant directCCR      : integer := 61; --
	constant exg            : integer := 62; --
	constant get_ea_now     : integer := 63; --
	constant ea_to_pc       : integer := 64; --
	constant hold_dwr       : integer := 65; --
	constant to_USP         : integer := 66; --
	constant from_USP       : integer := 67; --
	constant write_lowlong  : integer := 68; --
	constant write_reminder : integer := 69; --
	constant movem_action   : integer := 70; --
	constant briefext       : integer := 71; --
	constant get_2ndOPC     : integer := 72; --
	constant mem_byte       : integer := 73; --
	constant longaktion     : integer := 74; --
	constant opcRESET       : integer := 75; --
	constant opcBF          : integer := 76; --
	constant opcBFwb        : integer := 77; --
	constant opcPACK        : integer := 78; --
	constant opcTRAPV       : integer := 79; --

	constant lastOpcBit     : integer := 79;

	type rTG68K_opc is record
	   opcMOVE        : bit;
	   opcMOVEQ       : bit;
	   opcMOVESR      : bit;
	   opcMOVECCR     : bit;
	   opcADD         : bit;
	   opcADDQ        : bit;
	   opcOR          : bit;
	   opcAND         : bit;
	   opcEOR         : bit;
	   opcCMP         : bit;
	   opcROT         : bit;
	   opcCPMAW       : bit;
	   opcEXT         : bit;
	   opcABCD        : bit;
	   opcSBCD        : bit;
	   opcBITS        : bit;
	   opcSWAP        : bit;
	   opcScc         : bit;
	   andiSR         : bit;
	   eoriSR         : bit;
	   oriSR          : bit;
	   opcMULU        : bit;
	   opcDIVU        : bit;
	   dispouter      : bit;
	   rot_nop        : bit;
	   ld_rot_cnt     : bit;
	   writePC_add    : bit;
	   ea_data_OP1    : bit;
	   ea_data_OP2    : bit;
	   use_XZFlag     : bit;
	   get_bfoffset   : bit;
	   save_memaddr   : bit;
	   opcCHK         : bit;
	   movec_rd       : bit;
	   movec_wr       : bit;
	   Regwrena       : bit;
	   update_FC      : bit;
	   linksp         : bit;
	   movepl         : bit;
	   update_ld      : bit;
	   OP1addr        : bit;
	   write_reg      : bit;
	   changeMode     : bit;
	   ea_build       : bit;
	   trap_chk       : bit;
	   store_ea_data  : bit;
	   addrlong       : bit;
	   postadd        : bit;
	   presub         : bit;
	   subidx         : bit;
	   no_Flags       : bit;
	   use_SP         : bit;
	   to_CCR         : bit;
	   to_SR          : bit;
	   OP2out_one     : bit;
	   OP1out_zero    : bit;
	   mem_addsub     : bit;
	   addsub         : bit;
	   directPC       : bit;
	   direct_delta   : bit;
	   directSR       : bit;
	   directCCR      : bit;
	   exg            : bit;
	   get_ea_now     : bit;
	   ea_to_pc       : bit;
	   hold_dwr       : bit;
	   to_USP         : bit;
	   from_USP       : bit;
	   write_lowlong  : bit;
	   write_reminder : bit;
	   movem_action   : bit;
	   briefext       : bit;
	   get_2ndOPC     : bit;
	   mem_byte       : bit;
	   longaktion     : bit;
	   opcRESET       : bit;
	   opcBF          : bit;
	   opcBFwb        : bit;
	   opcPACK        : bit;
	   opcTRAPV       : bit;
	end record;

	component TG68K_ALU
	generic(
		MUL_Mode : integer := 0;           --0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no MUL,
		DIV_Mode : integer := 0            --0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no DIV,
		);
	port(
		clk                     : in  std_logic;
		Reset                   : in  std_logic;
		clkena_lw               : in  std_logic:='1';
		execOPC                 : in  bit;
		exe_condition           : in  std_logic;
		exec_tas                : in  std_logic;
		long_start              : in  bit;
		non_aligned             : in  std_logic;
		movem_presub            : in  bit;
		set_stop                : in  bit;
		Z_error                 : in  bit;
		rot_bits                : in  std_logic_vector(1 downto 0);
		exec                    : in  bit_vector(lastOpcBit downto 0);
		OP1out                  : in  std_logic_vector(31 downto 0);
		OP2out                  : in  std_logic_vector(31 downto 0);
		reg_QA                  : in  std_logic_vector(31 downto 0);
		reg_QB                  : in  std_logic_vector(31 downto 0);
		opcode                  : in  std_logic_vector(15 downto 0);
		datatype                : in  std_logic_vector(1 downto 0);
		exe_opcode              : in  std_logic_vector(15 downto 0);
		exe_datatype            : in  std_logic_vector(1 downto 0);
		sndOPC                  : in  std_logic_vector(15 downto 0);
		last_data_read          : in  std_logic_vector(15 downto 0);
		data_read               : in  std_logic_vector(15 downto 0);
		FlagsSR                 : in  std_logic_vector(7 downto 0);
		micro_state             : in  micro_states;
		bf_ext_in               : in  std_logic_vector(7 downto 0);
		bf_ext_out              : out std_logic_vector(7 downto 0);
		bf_width                : in  std_logic_vector(4 downto 0);
		bf_loffset              : in  std_logic_vector(4 downto 0);
		bf_offset               : in  std_logic_vector(31 downto 0);
		set_V_Flag_out          : out bit;
		Flags_out               : out std_logic_vector(7 downto 0);
		c_out_out               : out std_logic_vector(2 downto 0);
		addsub_q_out            : out std_logic_vector(31 downto 0);
		ALUout                  : out std_logic_vector(31 downto 0)
	);
	end component;

end;
