------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- Copyright (c) 2009-2011 Tobias Gubener                                   -- 
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

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;

entity TG68K_ALU is
generic(
		MUL_Mode : integer := 0;	--0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no MUL,  
		DIV_Mode : integer := 0		--0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no DIV,  
		);
	   port(clk               	: in std_logic;
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
		bf_shift      	 	: in std_logic_vector(5 downto 0);
		bf_width        	: in std_logic_vector(5 downto 0);
		bf_loffset        	: in std_logic_vector(4 downto 0);
		      
        set_V_Flag	        : buffer bit;
        Flags         	 	: buffer std_logic_vector(7 downto 0);
        c_out         	 	: buffer std_logic_vector(2 downto 0);
        addsub_q       		: buffer std_logic_vector(31 downto 0);
        ALUout	        	: out std_logic_vector(31 downto 0)
        );
end TG68K_ALU;

architecture logic of TG68K_ALU is
-----------------------------------------------------------------------------
-----------------------------------------------------------------------------
-- ALU and more
-----------------------------------------------------------------------------
-----------------------------------------------------------------------------
    signal OP1in          : std_logic_vector(31 downto 0);
    signal addsub_a       : std_logic_vector(31 downto 0);
    signal addsub_b       : std_logic_vector(31 downto 0);
    signal notaddsub_b    : std_logic_vector(33 downto 0);
    signal add_result     : std_logic_vector(33 downto 0);
    signal addsub_ofl     : std_logic_vector(2 downto 0);
    signal opaddsub	      : bit;
    signal c_in	          : std_logic_vector(3 downto 0);
    signal flag_z         : std_logic_vector(2 downto 0);
	signal set_Flags      : std_logic_vector(3 downto 0);	--NZVC
	signal CCRin          : std_logic_vector(7 downto 0);
    
    signal niba_l		  : std_logic_vector(5 downto 0);
    signal niba_h		  : std_logic_vector(5 downto 0);
    signal niba_lc		  : std_logic;
    signal niba_hc		  : std_logic;
    signal bcda_lc		  : std_logic;
    signal bcda_hc		  : std_logic;
    signal nibs_l		  : std_logic_vector(5 downto 0);
    signal nibs_h		  : std_logic_vector(5 downto 0);
    signal nibs_lc		  : std_logic;
    signal nibs_hc		  : std_logic;
	
    signal bcd_a		  : std_logic_vector(8 downto 0);
    signal bcd_s		  : std_logic_vector(8 downto 0);
    signal result_mulu    : std_logic_vector(63 downto 0);
    signal result_div     : std_logic_vector(63 downto 0);
    signal set_mV_Flag	  : std_logic;
    signal V_Flag	      : bit;
    
	signal rot_rot        : std_logic;
	signal rot_lsb        : std_logic;
	signal rot_msb        : std_logic;
	signal rot_X          : std_logic;
	signal rot_C          : std_logic;
    signal rot_out        : std_logic_vector(31 downto 0);
	signal asl_VFlag      : std_logic;
    signal bit_bits       : std_logic_vector(1 downto 0);
    signal bit_number     : std_logic_vector(4 downto 0);
    signal bits_out       : std_logic_vector(31 downto 0);
    signal one_bit_in	  : std_logic;
    signal bchg			  : std_logic;
    signal bset			  : std_logic;
    
    signal mulu_sign	  : std_logic;
    signal mulu_signext	  : std_logic_vector(16 downto 0);
    signal muls_msb		  : std_logic;
    signal mulu_reg       : std_logic_vector(63 downto 0);
    signal FAsign		  : std_logic;
    signal faktorA  	  : std_logic_vector(31 downto 0);
    signal faktorB  	  : std_logic_vector(31 downto 0);
    
    signal div_reg        : std_logic_vector(63 downto 0);
    signal div_quot       : std_logic_vector(63 downto 0);
    signal div_ovl	      : std_logic;
    signal div_neg	      : std_logic;
    signal div_bit	      : std_logic;
    signal div_sub        : std_logic_vector(32 downto 0);
    signal div_over       : std_logic_vector(32 downto 0);
    signal nozero         : std_logic;
    signal div_qsign	  : std_logic;
    signal divisor        : std_logic_vector(63 downto 0);
    signal divs	  		  : std_logic;
    signal signedOP  	  : std_logic;
    signal OP1_sign		  : std_logic;
    signal OP2_sign  	  : std_logic;
    signal OP2outext      : std_logic_vector(15 downto 0);
    
    signal in_offset        : std_logic_vector(5 downto 0);
--    signal in_width         : std_logic_vector(5 downto 0);
    signal datareg       : std_logic_vector(31 downto 0);
    signal insert       : std_logic_vector(31 downto 0);
--    signal bf_result        : std_logic_vector(31 downto 0);
--    signal bf_offset        : std_logic_vector(5 downto 0);
--    signal bf_width         : std_logic_vector(5 downto 0);
--    signal bf_firstbit      : std_logic_vector(5 downto 0);
    signal bf_datareg       : std_logic_vector(31 downto 0);
--    signal bf_out       : std_logic_vector(31 downto 0);
    signal result           : std_logic_vector(39 downto 0);
    signal result_tmp           : std_logic_vector(39 downto 0);
    signal sign             : std_logic_vector(31 downto 0);
    signal bf_set1          : std_logic_vector(39 downto 0);
    signal inmux0           : std_logic_vector(39 downto 0);
    signal inmux1           : std_logic_vector(39 downto 0);
    signal inmux2           : std_logic_vector(39 downto 0);
    signal inmux3           : std_logic_vector(31 downto 0);
    signal copymux0           : std_logic_vector(39 downto 0);
    signal copymux1           : std_logic_vector(39 downto 0);
    signal copymux2           : std_logic_vector(39 downto 0);
    signal copymux3           : std_logic_vector(31 downto 0);
    signal bf_set2          : std_logic_vector(31 downto 0);
--    signal bf_set3          : std_logic_vector(31 downto 0);
    signal shift            : std_logic_vector(39 downto 0);
    signal copy            : std_logic_vector(39 downto 0);
--    signal offset       	: std_logic_vector(5 downto 0);
--    signal width            : std_logic_vector(5 downto 0);
    signal bf_firstbit      : std_logic_vector(5 downto 0);
	signal mux     : std_logic_vector(3 downto 0);
    signal bitnr  : std_logic_vector(4 downto 0);
    signal mask     : std_logic_vector(31 downto 0);
    signal bf_bset  : std_logic;
    signal bf_NFlag  : std_logic;
    signal bf_bchg  : std_logic;
    signal bf_ins  : std_logic;
    signal bf_exts  : std_logic;
    signal bf_fffo  : std_logic;
    signal bf_d32  : std_logic;
    signal bf_s32  : std_logic;
    signal index  : std_logic_vector(4 downto 0);
--    signal i  : integer range 0 to 31;
--    signal i  : integer range 0 to 31;
--    signal i  : std_logic_vector(5 downto 0);
BEGIN
-----------------------------------------------------------------------------
-- set OP1in
-----------------------------------------------------------------------------
PROCESS (OP2out, reg_QB, opcode, OP1out, OP1in, exe_datatype, addsub_q, execOPC, exec,
	     bcd_a, bcd_s, result_mulu, result_div, exe_condition, bf_shift,
	     Flags, FlagsSR, bits_out, exec_tas, rot_out, exe_opcode, result, bf_fffo, bf_firstbit, bf_datareg)
	BEGIN
		ALUout <= OP1in;
		ALUout(7) <= OP1in(7) OR exec_tas;
		IF exec(opcBFwb)='1' THEN
			ALUout <= result(31 downto 0);
			IF bf_fffo='1' THEN
				ALUout <= (OTHERS =>'0');
				ALUout(5 downto 0) <= bf_firstbit + bf_shift;
			END IF;
		END IF;
		
		OP1in <= addsub_q;
		IF exec(opcABCD)='1' THEN	
			OP1in(7 downto 0) <= bcd_a(7 downto 0);
		ELSIF exec(opcSBCD)='1' THEN	
			OP1in(7 downto 0) <= bcd_s(7 downto 0);
		ELSIF exec(opcMULU)='1' AND MUL_Mode/=3 THEN
			IF exec(write_lowlong)='1' AND (MUL_Mode=1 OR MUL_Mode=2) THEN
				OP1in <= result_mulu(31 downto 0);	
			ELSE	
				OP1in <= result_mulu(63 downto 32);
			END IF;		
		ELSIF exec(opcDIVU)='1' AND DIV_Mode/=3 THEN
			IF exe_opcode(15)='1' OR DIV_Mode=0 THEN
--			IF exe_opcode(15)='1' THEN
				OP1in <= result_div(47 downto 32)&result_div(15 downto 0);	
			ELSE		--64bit
				IF exec(write_reminder)='1' THEN
					OP1in <= result_div(63 downto 32);
				ELSE	
					OP1in <= result_div(31 downto 0);	
				END IF;
			END IF;
		ELSIF exec(opcOR)='1' THEN
			OP1in <= OP2out OR OP1out;
		ELSIF exec(opcAND)='1' THEN
			OP1in <= OP2out AND OP1out;
		ELSIF exec(opcScc)='1' THEN
			OP1in(7 downto 0) <= (others=>exe_condition); 
		ELSIF exec(opcEOR)='1' THEN
			OP1in <= OP2out XOR OP1out;
		ELSIF exec(opcMOVE)='1' OR exec(exg)='1' THEN
--			OP1in <= OP2out(31 downto 8)&(OP2out(7)OR exec_tas)&OP2out(6 downto 0);
			OP1in <= OP2out;
		ELSIF exec(opcROT)='1' THEN
			OP1in <= rot_out;
		ELSIF exec(opcSWAP)='1' THEN	
			OP1in <= OP1out(15 downto 0)& OP1out(31 downto 16);
		ELSIF exec(opcBITS)='1' THEN
			OP1in <= bits_out;	
		ELSIF exec(opcBF)='1' THEN
			OP1in <= bf_datareg;
		ELSIF exec(opcMOVESR)='1' THEN
			OP1in(7 downto 0) <= Flags;
			IF exe_datatype="00" THEN
				OP1in(15 downto 8) <= "00000000";
			ELSE	
				OP1in(15 downto 8) <= FlagsSR;
			END IF;
		END IF;
	END PROCESS;
	
-----------------------------------------------------------------------------
-- addsub
-----------------------------------------------------------------------------
PROCESS (OP1out, OP2out, execOPC, datatype, Flags, long_start, movem_presub, exe_datatype, exec, addsub_a, addsub_b, opaddsub,
	     notaddsub_b, add_result, c_in, sndOPC)
	BEGIN
		addsub_a <= OP1out;
		IF exec(get_bfoffset)='1' THEN	
			IF sndOPC(11)='1' THEN
				addsub_a <= OP1out(31)&OP1out(31)&OP1out(31)&OP1out(31 downto 3);
			ELSE
				addsub_a <= "000000000000000000000000000000"&sndOPC(10 downto 9);
			END IF;	
		END IF;
		
		IF exec(subidx)='1' THEN
			opaddsub <= '1';
		ELSE
			opaddsub <= '0';
		END IF;
		
		c_in(0) <='0';
		addsub_b <= OP2out;
		IF execOPC='0' AND exec(OP2out_one)='0' AND exec(get_bfoffset)='0'THEN
			IF long_start='0' AND datatype="00" AND exec(use_SP)='0' THEN
				addsub_b <= "00000000000000000000000000000001";
			ELSIF long_start='0' AND exe_datatype="10" AND (exec(presub) OR exec(postadd) OR movem_presub)='1' THEN
				IF exec(movem_action)='1' THEN
					addsub_b <= "00000000000000000000000000000110";
				ELSE
					addsub_b <= "00000000000000000000000000000100";
				END IF;
			ELSE 
				addsub_b <= "00000000000000000000000000000010";
			END IF;
		ELSE	
			IF (exec(use_XZFlag)='1' AND Flags(4)='1') OR exec(opcCHK)='1' THEN
				c_in(0) <= '1';
			END IF;
			opaddsub <= exec(addsub);
		END IF;

		IF opaddsub='0' OR long_start='1' THEN		--ADD
			notaddsub_b <= '0'&addsub_b&c_in(0);
		ELSE					--SUB
			notaddsub_b <= NOT ('0'&addsub_b&c_in(0));
		END IF;
		add_result <= (('0'&addsub_a&notaddsub_b(0))+notaddsub_b);
		c_in(1) <= add_result(9) XOR addsub_a(8) XOR addsub_b(8);
		c_in(2) <= add_result(17) XOR addsub_a(16) XOR addsub_b(16);
		c_in(3) <= add_result(33);
		addsub_q <= add_result(32 downto 1); 
		addsub_ofl(0) <= (c_in(1) XOR add_result(8) XOR addsub_a(7) XOR addsub_b(7));		--V Byte
		addsub_ofl(1) <= (c_in(2) XOR add_result(16) XOR addsub_a(15) XOR addsub_b(15));	--V Word
		addsub_ofl(2) <= (c_in(3) XOR add_result(32) XOR addsub_a(31) XOR addsub_b(31));	--V Long
		c_out <= c_in(3 downto 1);
	END PROCESS;
	
------------------------------------------------------------------------------
--ALU
------------------------------------------------------------------------------		
PROCESS (OP1out, OP2out, niba_hc, niba_h, niba_l, niba_lc, nibs_hc, nibs_h, nibs_l, nibs_lc, Flags)
	BEGIN
--BCD_ARITH-------------------------------------------------------------------
	--ADC
		bcd_a <= niba_hc&(niba_h(4 downto 1)+('0',niba_hc,niba_hc,'0'))&(niba_l(4 downto 1)+('0',niba_lc,niba_lc,'0'));
		niba_l <= ('0'&OP1out(3 downto 0)&'1') + ('0'&OP2out(3 downto 0)&Flags(4));
		niba_lc <= niba_l(5) OR (niba_l(4) AND niba_l(3)) OR (niba_l(4) AND niba_l(2));

		niba_h <= ('0'&OP1out(7 downto 4)&'1') + ('0'&OP2out(7 downto 4)&niba_lc);
		niba_hc <= niba_h(5) OR (niba_h(4) AND niba_h(3)) OR (niba_h(4) AND niba_h(2));
	--SBC			
		bcd_s <= nibs_hc&(nibs_h(4 downto 1)-('0',nibs_hc,nibs_hc,'0'))&(nibs_l(4 downto 1)-('0',nibs_lc,nibs_lc,'0'));
		nibs_l <= ('0'&OP1out(3 downto 0)&'0') - ('0'&OP2out(3 downto 0)&Flags(4));
		nibs_lc <= nibs_l(5);

		nibs_h <= ('0'&OP1out(7 downto 4)&'0') - ('0'&OP2out(7 downto 4)&nibs_lc);
		nibs_hc <= nibs_h(5);
	END PROCESS;
			
-----------------------------------------------------------------------------
-- Bits
-----------------------------------------------------------------------------
PROCESS (clk, exe_opcode, OP1out, OP2out, one_bit_in, bchg, bset, bit_Number, sndOPC)
	BEGIN
		IF rising_edge(clk) THEN		
	        IF  clkena_lw = '1' THEN
				bchg <= '0';
				bset <= '0';
				CASE opcode(7 downto 6) IS
					WHEN "01" =>					--bchg
						bchg <= '1';
					WHEN "11" =>					--bset
						bset <= '1';
					WHEN OTHERS => NULL;			
				END CASE;
			END IF;
		END IF;		
		
		IF exe_opcode(8)='0' THEN
			IF exe_opcode(5 downto 4)="00" THEN
				bit_number <= sndOPC(4 downto 0);
			ELSE
				bit_number <= "00"&sndOPC(2 downto 0);
			END IF;
		ELSE
			IF exe_opcode(5 downto 4)="00" THEN
				bit_number <= reg_QB(4 downto 0);
			ELSE
				bit_number <= "00"&reg_QB(2 downto 0);
			END IF;
		END IF;
						
		one_bit_in <= OP1out(to_integer(unsigned(bit_Number)));
		bits_out <= OP1out;
		bits_out(to_integer(unsigned(bit_Number))) <= (bchg AND NOT one_bit_in) OR bset ;
	END PROCESS;

-----------------------------------------------------------------------------
-- Bit Field
-----------------------------------------------------------------------------	
PROCESS (clk, mux, mask, bitnr, bf_ins, bf_bchg, bf_bset, bf_exts, bf_shift, inmux0, inmux1, inmux2, inmux3, bf_set2, OP1out, OP2out, result_tmp, bf_ext_in,
	     shift, datareg, bf_NFlag, result, reg_QB, sign, bf_d32, bf_s32, copy, bf_loffset, copymux0, copymux1, copymux2, copymux3, bf_width)
	BEGIN
		IF rising_edge(clk) THEN		
	        IF clkena_lw = '1' THEN
				bf_bset <= '0';
				bf_bchg <= '0';
				bf_ins <= '0';
				bf_exts <= '0';
				bf_fffo <= '0';
				bf_d32 <= '0';
				bf_s32 <= '0';
				CASE opcode(10 downto 8) IS
					WHEN "010" => bf_bchg <= '1';				--BFCHG
					WHEN "011" => bf_exts <= '1';				--BFEXTS
--					WHEN "100" => insert <= (OTHERS =>'0');		--BFCLR
					WHEN "101" => bf_fffo <= '1';				--BFFFO
					WHEN "110" => bf_bset <= '1';				--BFSET
					WHEN "111" => bf_ins <= '1';					--BFINS
								  bf_s32 <= '1';
					WHEN OTHERS => NULL;
				END CASE;	
				IF opcode(4 downto 3)="00" THEN
					bf_d32 <= '1';
				END IF;
				bf_ext_out <= result(39 downto 32);
			END IF;
		END IF;
		shift <= bf_ext_in&OP2out;
		IF bf_s32='1' THEN 
			shift(39 downto 32) <= OP2out(7 downto 0);
		END IF;
			
		IF bf_shift(0)='1' THEN 
			inmux0 <= shift(0)&shift(39 downto 1);
		ELSE	
			inmux0 <= shift;
		END IF;
		IF bf_shift(1)='1' THEN 
			inmux1 <= inmux0(1 downto 0)&inmux0(39 downto 2);
		ELSE
			inmux1 <= inmux0;
		END IF;
		IF bf_shift(2)='1' THEN 
			inmux2 <= inmux1(3 downto 0)&inmux1(39 downto 4);
		ELSE	
			inmux2 <= inmux1;
		END IF;
		IF bf_shift(3)='1' THEN 
			inmux3 <= inmux2(7 downto 0)&inmux2(31 downto 8);
		ELSE	
			inmux3 <= inmux2(31 downto 0);
		END IF;
		IF bf_shift(4)='1' THEN 
			bf_set2(31 downto 0) <= inmux3(15 downto 0)&inmux3(31 downto 16);
		ELSE	
			bf_set2(31 downto 0) <= inmux3;
		END IF;
				
		IF bf_loffset(4)='1' THEN 
			copymux3 <= sign(15 downto 0)&sign(31 downto 16);
		ELSE	
			copymux3 <= sign;
		END IF;
		IF bf_loffset(3)='1' THEN 
			copymux2(31 downto 0) <= copymux3(23 downto 0)&copymux3(31 downto 24);
		ELSE	
			copymux2(31 downto 0) <= copymux3;
		END IF;
		IF bf_d32='1' THEN 
			copymux2(39 downto 32) <= copymux3(7 downto 0);
		ELSE	
			copymux2(39 downto 32) <= "11111111";
		END IF;
		IF bf_loffset(2)='1' THEN 
			copymux1 <= copymux2(35 downto 0)&copymux2(39 downto 36);
		ELSE	
			copymux1 <= copymux2;
		END IF;
		IF bf_loffset(1)='1' THEN 
			copymux0 <= copymux1(37 downto 0)&copymux1(39 downto 38);
		ELSE
			copymux0 <= copymux1;
		END IF;
		IF bf_loffset(0)='1' THEN 
			copy <= copymux0(38 downto 0)&copymux0(39);
		ELSE
			copy <= copymux0;
		END IF;
			
		result_tmp <= bf_ext_in&OP1out;
		IF bf_ins='1' THEN
			datareg <= reg_QB;
		ELSE
			datareg <= bf_set2;
		END IF;
		IF bf_ins='1' THEN
			result(31 downto 0) <= bf_set2;
			result(39 downto 32) <= bf_set2(7 downto 0);
		ELSIF bf_bchg='1' THEN
			result(31 downto 0) <= NOT OP1out;
			result(39 downto 32) <= NOT bf_ext_in;
		ELSE	
			result <= (OTHERS => '0');
		END IF;
		IF bf_bset='1' THEN
			result <= (OTHERS => '1');
		END IF;
		
		sign <= (OTHERS => '0'); 
		bf_NFlag <= datareg(to_integer(unsigned(bf_width)));
		FOR i in 0 to 31 LOOP
			IF i>bf_width(4 downto 0) THEN
				datareg(i) <= '0'; 
				sign(i) <= '1'; 
			END IF;	
		END LOOP;
		
		FOR i in 0 to 39 LOOP
			IF copy(i)='1' THEN
				result(i) <= result_tmp(i);
			END IF;	
		END LOOP;
		
		IF bf_exts='1' AND bf_NFlag='1' THEN
			bf_datareg <= datareg OR sign;
		ELSE	
			bf_datareg <= datareg;
		END IF;	
--	bf_datareg <= copy(31 downto 0);
--	result(31 downto 0)<=datareg;
--BFFFO	
		mask <= datareg;
		bf_firstbit <= '0'&bitnr;
		bitnr <= "11111";
		IF mask(31 downto 28)="0000" THEN
			IF mask(27 downto 24)="0000" THEN
				IF mask(23 downto 20)="0000" THEN
					IF mask(19 downto 16)="0000" THEN
						bitnr(4) <= '0';
						IF mask(15 downto 12)="0000" THEN
							IF mask(11 downto 8)="0000" THEN
								bitnr(3) <= '0';
								IF mask(7 downto 4)="0000" THEN
									bitnr(2) <= '0';
									mux <= mask(3 downto 0);
								ELSE
									mux <= mask(7 downto 4);
								END IF;
							ELSE
								mux <= mask(11 downto 8);
								bitnr(2) <= '0';
							END IF;
						ELSE
							mux <= mask(15 downto 12);
						END IF;
					ELSE
						mux <= mask(19 downto 16);
						bitnr(3) <= '0';
						bitnr(2) <= '0';
					END IF;
				ELSE
					mux <= mask(23 downto 20);
					bitnr(3) <= '0';
				END IF;
			ELSE
				mux <= mask(27 downto 24);
				bitnr(2) <= '0';
			END IF;
		ELSE
			mux <= mask(31 downto 28);
		END IF;
		
		IF mux(3 downto 2)="00" THEN
			bitnr(1) <= '0';
			IF mux(1)='0' THEN
				bitnr(0) <= '0';
			END IF;	
		ELSE		
			IF mux(3)='0' THEN
				bitnr(0) <= '0';
			END IF;	
		END  IF;
	END PROCESS;

-----------------------------------------------------------------------------
-- Rotation
-----------------------------------------------------------------------------
PROCESS (exe_opcode, OP1out, Flags, rot_bits, rot_msb, rot_lsb, rot_rot, exec)
	BEGIN
		CASE exe_opcode(7 downto 6) IS
			WHEN "00" =>					--Byte
						rot_rot <= OP1out(7);
			WHEN "01"|"11" =>				--Word
						rot_rot <= OP1out(15);
			WHEN "10" =>					--Long
						rot_rot <= OP1out(31);
			WHEN OTHERS => NULL;
		END CASE;
	
		CASE rot_bits IS
			WHEN "00" =>					--ASL, ASR
						rot_lsb <= '0';
						rot_msb <= rot_rot;
			WHEN "01" =>					--LSL, LSR
						rot_lsb <= '0';
						rot_msb <= '0';
			WHEN "10" =>					--ROXL, ROXR
						rot_lsb <= Flags(4);
						rot_msb <= Flags(4);
			WHEN "11" =>					--ROL, ROR
						rot_lsb <= rot_rot;
						rot_msb <= OP1out(0);
			WHEN OTHERS => NULL;
		END CASE;
	
		IF exec(rot_nop)='1' THEN
			rot_out <= OP1out;
			rot_X <= Flags(4);
			IF rot_bits="10" THEN	--ROXL, ROXR
				rot_C <= Flags(4);
			ELSE	
				rot_C <= '0';
			END IF;
		ELSE
			IF exe_opcode(8)='1' THEN		--left
				rot_out <= OP1out(30 downto 0)&rot_lsb;
				rot_X <= rot_rot;
				rot_C <= rot_rot;
			ELSE						--right
				rot_X <= OP1out(0);
				rot_C <= OP1out(0);
				rot_out <= rot_msb&OP1out(31 downto 1);
				CASE exe_opcode(7 downto 6) IS
					WHEN "00" =>					--Byte
						rot_out(7) <= rot_msb;
					WHEN "01"|"11" =>				--Word
						rot_out(15) <= rot_msb;
					WHEN OTHERS => NULL;	
				END CASE;
			END IF;
		END IF;
	END PROCESS;
		
------------------------------------------------------------------------------
--CCR op
------------------------------------------------------------------------------		
PROCESS (clk, Reset, exe_opcode, exe_datatype, Flags, last_data_read, OP2out, flag_z, OP1IN, c_out, addsub_ofl,
	     bcd_s, bcd_a, exec)
	BEGIN
		IF exec(andiSR)='1' THEN
			CCRin <= Flags AND last_data_read(7 downto 0);
		ELSIF exec(eoriSR)='1' THEN
			CCRin <= Flags XOR last_data_read(7 downto 0);
		ELSIF exec(oriSR)='1' THEN
			CCRin <= Flags OR last_data_read(7 downto 0);
		ELSE	
			CCRin <= OP2out(7 downto 0);
		END IF;	
		
------------------------------------------------------------------------------
--Flags
------------------------------------------------------------------------------		
		flag_z <= "000";
		IF exec(use_XZFlag)='1' AND flags(2)='0' THEN
			flag_z <= "000";
		ELSIF OP1in(7 downto 0)="00000000" THEN
			flag_z(0) <= '1';
			IF OP1in(15 downto 8)="00000000" THEN
				flag_z(1) <= '1';
				IF OP1in(31 downto 16)="0000000000000000" THEN
					flag_z(2) <= '1';	
				END IF;
			END IF;
		END IF;
		
--					--Flags NZVC
		IF exe_datatype="00" THEN 						--Byte
			set_flags <= OP1IN(7)&flag_z(0)&addsub_ofl(0)&c_out(0);
			IF exec(opcABCD)='1' THEN	
				set_flags(0) <= bcd_a(8);
			ELSIF exec(opcSBCD)='1' THEN	
				set_flags(0) <= bcd_s(8);
			END IF;
		ELSIF exe_datatype="10" OR exec(opcCPMAW)='1' THEN 						--Long
			set_flags <= OP1IN(31)&flag_z(2)&addsub_ofl(2)&c_out(2);
		ELSE 						--Word
			set_flags <= OP1IN(15)&flag_z(1)&addsub_ofl(1)&c_out(1);
		END IF;
		
		IF rising_edge(clk) THEN		
	        IF clkena_lw = '1' THEN
				IF exec(directSR)='1' OR set_stop='1' THEN
					Flags(7 downto 0) <= data_read(7 downto 0);
				END IF;	
				IF exec(directCCR)='1' THEN
					Flags(7 downto 0) <= data_read(7 downto 0);
				END IF;	
				
				IF exec(opcROT)='1' THEN
					asl_VFlag <= ((set_flags(3) XOR rot_rot) OR asl_VFlag);	
				ELSE	
					asl_VFlag <= '0';
				END IF;	
				IF exec(to_CCR)='1' THEN
					Flags(7 downto 0) <= CCRin(7 downto 0);			--CCR
				ELSIF Z_error='1' THEN
					IF exe_opcode(8)='0' THEN
						Flags(3 downto 0) <= reg_QA(31)&"000";
					ELSE
						Flags(3 downto 0) <= "0100";
					END IF;		
				ELSIF exec(no_Flags)='0' THEN
					IF exec(opcADD)='1' THEN
						Flags(4) <= set_flags(0);
					ELSIF exec(opcROT)='1' AND rot_bits/="11" AND exec(rot_nop)='0' THEN
						Flags(4) <= rot_X; 	
					END IF;
					
					IF (exec(opcADD) OR exec(opcCMP))='1' THEN
						Flags(3 downto 0) <= set_flags;
					ELSIF exec(opcDIVU)='1' AND DIV_Mode/=3 THEN
						IF V_Flag='1' THEN	
							Flags(3 downto 0) <= "1010";
						ELSE
							Flags(3 downto 0) <= OP1IN(15)&flag_z(1)&"00";
						END IF;
					ELSIF exec(write_reminder)='1' AND MUL_Mode/=3 THEN -- z-flag MULU.l
						Flags(3) <= set_flags(3);
						Flags(2) <= set_flags(2) AND Flags(2);
						Flags(1) <= '0';
						Flags(0) <= '0';
					ELSIF exec(write_lowlong)='1' AND (MUL_Mode=1 OR MUL_Mode=2) THEN  -- flag MULU.l
						Flags(3) <= set_flags(3);
						Flags(2) <= set_flags(2);
						Flags(1) <= set_mV_Flag;	--V
						Flags(0) <= '0';
					ELSIF exec(opcOR)='1' OR exec(opcAND)='1' OR exec(opcEOR)='1' OR exec(opcMOVE)='1' OR exec(opcMOVEQ)='1' OR exec(opcSWAP)='1' OR exec(opcBF)='1' OR (exec(opcMULU)='1' AND MUL_Mode/=3) THEN
						Flags(1 downto 0) <= "00";
						Flags(3 downto 2) <= set_flags(3 downto 2);
						IF exec(opcBF)='1' THEN
							Flags(3) <= bf_NFlag;
						END IF;	
					ELSIF exec(opcROT)='1' THEN
						Flags(3 downto 2) <= set_flags(3 downto 2);
						Flags(0) <= rot_C;
						IF rot_bits="00" AND ((set_flags(3) XOR rot_rot) OR asl_VFlag)='1' THEN		--ASL/ASR
							Flags(1) <= '1';
						ELSE		
							Flags(1) <= '0';
						END IF;	
					ELSIF exec(opcBITS)='1' THEN
						Flags(2) <= NOT one_bit_in;	
					ELSIF exec(opcCHK)='1' THEN
						IF exe_datatype="01" THEN 						--Word
							Flags(3) <= OP1out(15);
						ELSE	
							Flags(3) <= OP1out(31);
						END IF;	
						IF OP1out(15 downto 0)=X"0000" AND (exe_datatype="01" OR OP1out(31 downto 16)=X"0000") THEN
							Flags(2) <='1';
						ELSE	
							Flags(2) <='0';
						END IF;	
						Flags(1 downto 0) <= "00";
					END IF;
				END IF;	
			END IF;	
			Flags(7 downto 5) <= "000";
		END IF;	
	END PROCESS;
	
-------------------------------------------------------------------------------
---- MULU/MULS
-------------------------------------------------------------------------------	
PROCESS (exe_opcode, OP2out, muls_msb, mulu_reg, FAsign, mulu_sign, reg_QA, faktorB, result_mulu, signedOP)
	BEGIN
		IF (signedOP='1' AND faktorB(31)='1') OR FAsign='1' THEN
			muls_msb <= mulu_reg(63);
		ELSE
			muls_msb <= '0';
		END IF;	
		
		IF signedOP='1' AND faktorB(31)='1' THEN
			mulu_sign <= '1';
		ELSE
			mulu_sign <= '0';
		END IF;	
		
		IF MUL_Mode=0 THEN	-- 16 Bit
			result_mulu(63 downto 32) <= muls_msb&mulu_reg(63 downto 33);	
			result_mulu(15 downto 0) <= 'X'&mulu_reg(15 downto 1);	
			IF mulu_reg(0)='1' THEN
				IF FAsign='1' THEN
					result_mulu(63 downto 47) <= (muls_msb&mulu_reg(63 downto 48)-(mulu_sign&faktorB(31 downto 16)));	
				ELSE
					result_mulu(63 downto 47) <= (muls_msb&mulu_reg(63 downto 48)+(mulu_sign&faktorB(31 downto 16)));	
				END IF;
			END IF;	
		ELSE				-- 32 Bit
			result_mulu <= muls_msb&mulu_reg(63 downto 1);	
			IF mulu_reg(0)='1' THEN
				IF FAsign='1' THEN
					result_mulu(63 downto 31) <= (muls_msb&mulu_reg(63 downto 32)-(mulu_sign&faktorB));	
				ELSE
					result_mulu(63 downto 31) <= (muls_msb&mulu_reg(63 downto 32)+(mulu_sign&faktorB));	
				END IF;
			END IF;	
		END IF;
		IF exe_opcode(15)='1' OR MUL_Mode=0 THEN
			faktorB(31 downto 16) <= OP2out(15 downto 0);
			faktorB(15 downto 0) <= (OTHERS=>'0');
		ELSE	
			faktorB <= OP2out;
		END IF;
		IF (result_mulu(63 downto 32)=X"00000000" AND (signedOP='0' OR result_mulu(31)='0')) OR
			(result_mulu(63 downto 32)=X"FFFFFFFF" AND signedOP='1' AND result_mulu(31)='1') THEN
			set_mV_Flag <= '0';
		ELSE	
			set_mV_Flag <= '1';
		END IF;
	END PROCESS;
	
PROCESS (clk)
	BEGIN
		IF rising_edge(clk) THEN
			IF clkena_lw='1' THEN
				IF micro_state=mul1 THEN
					mulu_reg(63 downto 32) <= (OTHERS=>'0');
					IF divs='1' AND ((exe_opcode(15)='1' AND reg_QA(15)='1') OR (exe_opcode(15)='0' AND reg_QA(31)='1')) THEN				--MULS Neg faktor
						FAsign <= '1';
						mulu_reg(31 downto 0) <= 0-reg_QA;
					ELSE
						FAsign <= '0';
						mulu_reg(31 downto 0) <= reg_QA;
					END IF;	
				ELSIF exec(opcMULU)='0' THEN
					mulu_reg <= result_mulu;	
				END IF;
			END IF;
		END IF;
	END PROCESS;
		
-------------------------------------------------------------------------------
---- DIVU/DIVS
-------------------------------------------------------------------------------
		
PROCESS (execOPC, OP1out, OP2out, div_reg, div_neg, div_bit, div_sub, div_quot, OP1_sign, div_over, result_div, reg_QA, opcode, sndOPC, divs, exe_opcode, reg_QB, 
	     signedOP, nozero, div_qsign, OP2outext)
	BEGIN
		divs <= (opcode(15) AND opcode(8)) OR (NOT opcode(15) AND sndOPC(11));
		divisor(15 downto 0) <= (OTHERS=> '0');
		divisor(63 downto 32) <= (OTHERS=> divs AND reg_QA(31));
		IF exe_opcode(15)='1' OR DIV_Mode=0 THEN
			divisor(47 downto 16) <= reg_QA;
		ELSE		
			divisor(31 downto 0) <= reg_QA;
			IF exe_opcode(14)='1' AND sndOPC(10)='1' THEN
				divisor(63 downto 32) <= reg_QB;
			END IF;
		END IF;
		IF signedOP='1' OR opcode(15)='0' THEN 
			OP2outext <= OP2out(31 downto 16);
		ELSE
			OP2outext <= (OTHERS=> '0');
		END IF;
		IF signedOP='1' AND OP2out(31) ='1' THEN
			div_sub <= (div_reg(63 downto 31))+('1'&OP2out(31 downto 0));
		ELSE
			div_sub <= (div_reg(63 downto 31))-('0'&OP2outext(15 downto 0)&OP2out(15 downto 0));
		END IF;	
		IF DIV_Mode=0 THEN
			div_bit <= div_sub(16);
		ELSE
			div_bit <= div_sub(32);
		END IF;
		IF div_bit='1' THEN
			div_quot(63 downto 32) <= div_reg(62 downto 31);	
		ELSE
			div_quot(63 downto 32) <= div_sub(31 downto 0);	
		END IF;	
		div_quot(31 downto 0) <= div_reg(30 downto 0)&NOT div_bit;
		

		IF ((nozero='1' AND signedOP='1' AND (OP2out(31) XOR OP1_sign XOR div_neg XOR div_qsign)='1' )	--Overflow DIVS
			OR (signedOP='0' AND div_over(32)='0')) AND DIV_Mode/=3 THEN	--Overflow DIVU
			set_V_Flag <= '1';
		ELSE	
			set_V_Flag <= '0';
		END IF;
	END PROCESS;
	
PROCESS (clk)
	BEGIN
		IF rising_edge(clk) THEN
			IF clkena_lw='1' THEN
				V_Flag <= set_V_Flag;
				signedOP <= divs;
				IF micro_state=div1 THEN
					nozero <= '0';
					IF divs='1' AND divisor(63)='1' THEN				-- Neg divisor
						OP1_sign <= '1';
						div_reg <= 0-divisor;
					ELSE
						OP1_sign <= '0';
						div_reg <= divisor;
					END IF;	
				ELSE
					div_reg <= div_quot;	
					nozero <= NOT div_bit OR nozero;
				END IF;
				IF micro_state=div2 THEN
					div_qsign <= NOT div_bit;
					div_neg <= signedOP AND (OP2out(31) XOR OP1_sign);
					IF DIV_Mode=0 THEN
						div_over(32 downto 16) <= ('0'&div_reg(47 downto 32))-('0'&OP2out(15 downto 0));
					ELSE	
						div_over <= ('0'&div_reg(63 downto 32))-('0'&OP2out);
					END IF;	
				END IF;
				IF exec(write_reminder)='0' THEN
--				IF exec_DIVU='0' THEN
					IF div_neg='1' THEN
						result_div(31 downto 0) <= 0-div_quot(31 downto 0);
					ELSE
						result_div(31 downto 0) <= div_quot(31 downto 0);
					END IF;	
					
					IF OP1_sign='1' THEN
						result_div(63 downto 32) <= 0-div_quot(63 downto 32);
					ELSE
						result_div(63 downto 32) <= div_quot(63 downto 32);
					END IF;	
				END IF;
			END IF;
		END IF;
	END PROCESS;
END;
