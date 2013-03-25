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
						  andi, op_AxAy, cmpm, link1, link2, unlink1, unlink2, int1, int2, int3, int4, rte1, rte2, rte3, trap0, trap1, trap2, trap3,
						  movec1, movep1, movep2, movep3, movep4, movep5, rota1, bf1, 
						  mul1, mul2, mul_end1,  mul_end2, div1, div2, div3, div4, div_end1, div_end2);
	
	constant opcMOVE        : integer := 0; --
	constant opcMOVEQ       : integer := 1; --
	constant opcMOVESR      : integer := 2; --
	constant opcADD         : integer := 3; --
	constant opcADDQ        : integer := 4; --
	constant opcOR          : integer := 5; --
	constant opcAND         : integer := 6; --
	constant opcEOR         : integer := 7;	--
	constant opcCMP         : integer := 8; --
	constant opcROT         : integer := 9; --
	constant opcCPMAW       : integer := 10;
	constant opcEXT         : integer := 11; --
	constant opcABCD        : integer := 12; --
	constant opcSBCD        : integer := 13; --
	constant opcBITS        : integer := 14; --
	constant opcSWAP        : integer := 15; --
	constant opcScc         : integer := 16; --
	constant andiSR         : integer := 17; --
	constant eoriSR         : integer := 18; --
	constant oriSR          : integer := 19; --
	constant opcMULU        : integer := 20; --
	constant opcDIVU        : integer := 21; --
	constant dispouter      : integer := 22; --
	constant rot_nop        : integer := 23; --
	constant ld_rot_cnt     : integer := 24; --
	constant writePC_add    : integer := 25; --
	constant ea_data_OP1    : integer := 26; --
	constant ea_data_OP2    : integer := 27; --
	constant use_XZFlag     : integer := 28; --
	constant get_bfoffset   : integer := 29; --
	constant save_memaddr   : integer := 30; --
	constant opcCHK         : integer := 31; --
	constant movec_rd       : integer := 32; --
	constant movec_wr       : integer := 33; --
	constant Regwrena       : integer := 34; --
	constant update_FC      : integer := 35; --
	constant linksp         : integer := 36; --
	constant movepl         : integer := 37; --
	constant update_ld      : integer := 38; --
	constant OP1addr        : integer := 39; --
	constant write_reg      : integer := 40; --
	constant changeMode     : integer := 41; --
	constant ea_build       : integer := 42; --
	constant trap_chk       : integer := 43; --
	constant store_ea_data  : integer := 44; --
	constant addrlong       : integer := 45; --
	constant postadd        : integer := 46; --
	constant presub         : integer := 47; --
	constant subidx         : integer := 48; --
	constant no_Flags       : integer := 49; --
	constant use_SP         : integer := 50; --
	constant to_CCR         : integer := 51; --
	constant to_SR          : integer := 52; --
	constant OP2out_one     : integer := 53; --
	constant OP1out_zero    : integer := 54; --
	constant mem_addsub     : integer := 55; --
	constant addsub         : integer := 56; --
	constant directPC       : integer := 57; --
	constant direct_delta   : integer := 58; --
	constant directSR       : integer := 59; --
	constant directCCR      : integer := 60; --
	constant exg            : integer := 61; --
	constant get_ea_now     : integer := 62; --
	constant ea_to_pc       : integer := 63; --
	constant hold_dwr       : integer := 64; --
	constant to_USP         : integer := 65; --
	constant from_USP       : integer := 66; --
	constant write_lowlong  : integer := 67; --
	constant write_reminder : integer := 68; --
	constant movem_action   : integer := 69; --
	constant briefext       : integer := 70; --
	constant get_2ndOPC     : integer := 71; --
	constant mem_byte       : integer := 72; --
	constant longaktion     : integer := 73; --
	constant opcRESET	    : integer := 74; --
	constant opcBF  	    : integer := 75; --
	constant opcBFwb	    : integer := 76; --
	constant s2nd_hbits     : integer := 77; --
--	constant    : integer := 75; --
--	constant         : integer := 76; --
--	constant         : integer := 7; --
--	constant         : integer := 7; --
--	constant         : integer := 7; --

	constant lastOpcBit     : integer := 77;

	component TG68K_ALU
	generic(
		MUL_Mode : integer := 0;	   --0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no MUL,  
		DIV_Mode : integer := 0		   --0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no DIV,  
		);
	port(
		clk               	: in std_logic;
        Reset	         	: in std_logic;
        clkena_lw         	: in std_logic:='1';
        execOPC         	: in bit;
        exe_condition      	: in std_logic;
        exec_tas		   	: in std_logic;
        long_start		   	: in bit;
        movem_presub	   	: in bit;
        set_stop	   		: in bit;
        Z_error 	        : in bit;
        rot_bits 	      	: in std_logic_vector(1 downto 0);
		exec                : in bit_vector(lastOpcBit downto 0);
        OP1out          	: in std_logic_vector(31 downto 0);
        OP2out          	: in std_logic_vector(31 downto 0);
        reg_QA          	: in std_logic_vector(31 downto 0);
        reg_QB          	: in std_logic_vector(31 downto 0);
        opcode          	: in std_logic_vector(15 downto 0);
        datatype 	      	: in std_logic_vector(1 downto 0);
        exe_opcode         	: in std_logic_vector(15 downto 0);
        exe_datatype       	: in std_logic_vector(1 downto 0);
        sndOPC          	: in std_logic_vector(15 downto 0);
        last_data_read	 	: in std_logic_vector(15 downto 0);
        data_read		 	: in std_logic_vector(15 downto 0);
        FlagsSR          	: in std_logic_vector(7 downto 0);
		micro_state			: in micro_states;  
		bf_ext_in       	: in std_logic_vector(7 downto 0);
		bf_ext_out       	: out std_logic_vector(7 downto 0);
		bf_shift	       	: in std_logic_vector(5 downto 0);
		bf_width        	: in std_logic_vector(5 downto 0);
		bf_loffset        	: in std_logic_vector(4 downto 0);
		      
        set_V_Flag	        : buffer bit;
        Flags         	 	: buffer std_logic_vector(7 downto 0);
        c_out         	 	: buffer std_logic_vector(2 downto 0);
        addsub_q       		: buffer std_logic_vector(31 downto 0);
        ALUout	        	: out std_logic_vector(31 downto 0)
	);
	end component;

end;