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
-- bugfix session 07/08.Feb.2013
-- movem ,-(an)
-- movem (an)+,          - thanks  Gerhard Suttner
-- btst dn,#data         - thanks  Peter Graf
-- movep                 - thanks  Till Harbaum
-- IPL vector            - thanks  Till Harbaum
--  

-- optimize Register file

-- to do 68010:
-- (MOVEC)
-- BKPT
-- RTD
-- MOVES
--
-- to do 68020:
-- (CALLM)
-- (RETM)

-- CAS, CAS2
-- CHK2
-- CMP2
-- cpXXX Coprozessor stuff
-- PACK
-- TRAPcc
-- UNPK

-- done 020:
-- Bitfields
-- address modes
-- long bra
-- DIVS.L, DIVU.L
-- LINK long
-- MULS.L, MULU.L
-- extb.l

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use work.TG68K_Pack.all;

entity TG68KdotC_Kernel is
	generic(
		SR_Read : integer:= 0;         --0=>user,   1=>privileged,      2=>switchable with CPU(0)
		VBR_Stackframe : integer:= 0;  --0=>no,     1=>yes/extended,    2=>switchable with CPU(0)
		extAddr_Mode : integer:= 0;    --0=>no,     1=>yes,    2=>switchable with CPU(1)
		MUL_Mode : integer := 0;	   --0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no MUL,  
		DIV_Mode : integer := 0;	   --0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no DIV,  
		BitField : integer := 0		   --0=>no,     1=>yes,    2=>switchable with CPU(1)  
		);
   port(clk               	: in std_logic;
        nReset             	: in std_logic;			--low active
        clkena_in         	: in std_logic:='1';
        data_in          	: in std_logic_vector(15 downto 0);
		IPL				  	: in std_logic_vector(2 downto 0):="111";
		IPL_autovector   	: in std_logic:='0';
		CPU             	: in std_logic_vector(1 downto 0):="00";  -- 00->68000  01->68010  11->68020(only some parts - yet)
        addr           		: buffer std_logic_vector(31 downto 0);
        data_write        	: out std_logic_vector(15 downto 0);
		nWr			  		: out std_logic;
		nUDS, nLDS	  		: out std_logic;
		busstate	  	  	: out std_logic_vector(1 downto 0);	-- 00-> fetch code 10->read data 11->write data 01->no memaccess
		nResetOut	  		: out std_logic;
        FC              	: out std_logic_vector(2 downto 0);
-- for debug		
		skipFetch	  		: out std_logic;
        regin          		: buffer std_logic_vector(31 downto 0)
        );
end TG68KdotC_Kernel;

architecture logic of TG68KdotC_Kernel is


	signal syncReset       	: std_logic_vector(3 downto 0);
	signal Reset		  	: std_logic;
	signal clkena_lw	  	: std_logic;
	signal TG68_PC       	: std_logic_vector(31 downto 0);
	signal tmp_TG68_PC     	: std_logic_vector(31 downto 0);
	signal TG68_PC_add     	: std_logic_vector(31 downto 0);
	signal PC_dataa         : std_logic_vector(31 downto 0);
	signal PC_datab         : std_logic_vector(31 downto 0);
	signal memaddr        	: std_logic_vector(31 downto 0);
    signal state		  	: std_logic_vector(1 downto 0);
    signal datatype		  	: std_logic_vector(1 downto 0);
    signal set_datatype		: std_logic_vector(1 downto 0);
    signal exe_datatype		: std_logic_vector(1 downto 0);
	signal setstate	      	: std_logic_vector(1 downto 0);

	signal opcode     		: std_logic_vector(15 downto 0);
	signal exe_opcode     	: std_logic_vector(15 downto 0);
	signal sndOPC     		: std_logic_vector(15 downto 0);

	signal last_opc_read    : std_logic_vector(15 downto 0);
	signal registerin     	: std_logic_vector(31 downto 0);
	signal reg_QA         	: std_logic_vector(31 downto 0);
	signal reg_QB         	: std_logic_vector(31 downto 0);
	signal Wwrena,Lwrena  	: bit;
	signal Bwrena		  	: bit;
	signal Regwrena_now	  	: bit;
	signal rf_dest_addr		: std_logic_vector(3 downto 0);
	signal rf_source_addr	: std_logic_vector(3 downto 0);
	signal rf_source_addrd	: std_logic_vector(3 downto 0);
   
	type regfile_t is array(0 to 15) of std_logic_vector(31 downto 0);
	signal regfile	  		: regfile_t;
 	signal RDindex_A	  	: integer range 0 to 15;
 	signal RDindex_B	  	: integer range 0 to 15;
	signal WR_AReg		  	: std_logic;


    signal memaddr_reg      : std_logic_vector(31 downto 0);
    signal memaddr_delta    : std_logic_vector(31 downto 0);
	signal use_base 	 	: bit;
	
   signal ea_data         : std_logic_vector(31 downto 0);
   signal OP1out, OP2out  : std_logic_vector(31 downto 0);
   signal OP1outbrief     : std_logic_vector(15 downto 0);
   signal OP1in           : std_logic_vector(31 downto 0);
   signal ALUout           : std_logic_vector(31 downto 0);
   signal data_write_tmp  : std_logic_vector(31 downto 0);
   signal data_write_muxin  : std_logic_vector(31 downto 0);
   signal data_write_mux  : std_logic_vector(47 downto 0);
   signal nextpass	      : bit;
   signal setnextpass	  : bit;
   signal setdispbyte	  : bit;
   signal setdisp	      : bit;
   signal regdirectsource :bit;		-- checken !!!
   signal addsub_q        : std_logic_vector(31 downto 0);
   signal briefdata       : std_logic_vector(31 downto 0);
--   signal c_in	          : std_logic_vector(3 downto 0);
   signal c_out	          : std_logic_vector(2 downto 0);

   signal mem_address     : std_logic_vector(31 downto 0);
   signal memaddr_a       : std_logic_vector(31 downto 0);

	signal TG68_PC_brw    : bit;
	signal TG68_PC_word   : bit;
	signal getbrief       : bit;
	signal brief          : std_logic_vector(15 downto 0);
	signal dest_areg      : std_logic;
	signal source_areg    : std_logic;
	signal data_is_source : bit;
	signal store_in_tmp   : bit;
	signal write_back     : bit;
	signal exec_write_back: bit;
	signal setstackaddr   : bit;
	signal writePC        : bit;
	signal writePCbig     : bit;
	signal set_writePCbig : bit;
	signal setopcode      : bit;
	signal decodeOPC      : bit;
	signal execOPC        : bit;
	signal setexecOPC     : bit;
	signal endOPC         : bit;
	signal setendOPC      : bit;
	signal Flags          : std_logic_vector(7 downto 0);	-- ...XNZVC
	signal FlagsSR        : std_logic_vector(7 downto 0);	-- T.S..III
	signal SRin           : std_logic_vector(7 downto 0);
	signal exec_DIRECT    : bit;
	signal exec_tas       : std_logic;
	signal set_exec_tas   : std_logic;

	signal exe_condition  : std_logic;
	signal ea_only        : bit;
	signal source_lowbits : bit;
	signal source_2ndHbits : bit;
	signal source_2ndLbits : bit;
	signal dest_2ndHbits  : bit;
	signal dest_hbits     : bit;
    signal rot_bits       : std_logic_vector(1 downto 0);
    signal set_rot_bits   : std_logic_vector(1 downto 0);
    signal rot_cnt        : std_logic_vector(5 downto 0);
    signal set_rot_cnt    : std_logic_vector(5 downto 0);
	signal movem_actiond  : bit;
	signal movem_regaddr  : std_logic_vector(3 downto 0);
	signal movem_mux      : std_logic_vector(3 downto 0);
    signal movem_presub	  : bit;
	signal movem_run      : bit;
    signal ea_calc_b      : std_logic_vector(31 downto 0);
	signal set_direct_data: bit;
	signal use_direct_data: bit;
	signal direct_data	  : bit;

    signal set_V_Flag	  : bit;
    signal set_vectoraddr : bit;
    signal writeSR	      : bit;
	signal trap_illegal   : bit;
	signal trap_addr_error   : bit;
	signal trap_priv      : bit;
	signal trap_trace     : bit;
	signal trap_1010      : bit;
	signal trap_1111      : bit;
	signal trap_trap      : bit;
	signal trap_trapv     : bit;
	signal trap_interrupt : bit;
	signal trapmake       : bit;
	signal trapd          : bit;
    signal trap_SR        : std_logic_vector(7 downto 0);
	signal make_trace     : std_logic;
	
    signal set_stop	      : bit;
    signal stop	          : bit;
    signal trap_vector    : std_logic_vector(31 downto 0);
    signal trap_vector_vbr    : std_logic_vector(31 downto 0);
	signal USP            : std_logic_vector(31 downto 0);
    signal illegal_write_mode   : bit;
    signal illegal_read_mode    : bit;
    signal illegal_byteaddr	    : bit;

	signal IPL_nr		  : std_logic_vector(2 downto 0);
	signal rIPL_nr		  : std_logic_vector(2 downto 0);
	signal IPL_vec	      : std_logic_vector(7 downto 0);
    signal interrupt	  : bit;
    signal setinterrupt	  : bit;
    signal SVmode	      : std_logic;
    signal preSVmode      : std_logic;
	signal Suppress_Base  : bit;
	signal set_Suppress_Base : bit;
	signal set_Z_error 	  : bit;
	signal Z_error 	      : bit;
	signal ea_build_now   : bit;	
	signal build_logical  : bit;	
	signal build_bcd      : bit;	
	
	signal data_read       	: std_logic_vector(31 downto 0);
	signal bf_ext_in	 	: std_logic_vector(7 downto 0);
	signal bf_ext_out	 	: std_logic_vector(7 downto 0);
	signal byte        	    : bit;
	signal long_start  		: bit;
	signal long_start_alu	: bit;
	signal long_done	    : bit;
	signal memmask          : std_logic_vector(5 downto 0);
	signal set_memmask      : std_logic_vector(5 downto 0);
	signal memread          : std_logic_vector(3 downto 0);
	signal wbmemmask        : std_logic_vector(5 downto 0);
	signal memmaskmux       : std_logic_vector(5 downto 0);
	signal oddout       	: std_logic;
	signal set_oddout      	: std_logic;
	signal PCbase       	: std_logic;
	signal set_PCbase       : std_logic;
		
	signal last_data_read  	: std_logic_vector(31 downto 0);
	signal last_data_in  	: std_logic_vector(31 downto 0);

    signal bf_offset        : std_logic_vector(5 downto 0);
    signal bf_width         : std_logic_vector(5 downto 0);
    signal bf_bhits         : std_logic_vector(5 downto 0);
    signal bf_shift        : std_logic_vector(5 downto 0);
    signal alu_width         : std_logic_vector(5 downto 0);
    signal alu_bf_shift        : std_logic_vector(5 downto 0);
	signal bf_loffset        	: std_logic_vector(5 downto 0);
	signal alu_bf_loffset        	: std_logic_vector(5 downto 0);

	signal movec_data       : std_logic_vector(31 downto 0);
	signal VBR          	: std_logic_vector(31 downto 0);
	signal CACR          	: std_logic_vector(3 downto 0);
	signal DFC          	: std_logic_vector(2 downto 0);
	signal SFC          	: std_logic_vector(2 downto 0);
	

	signal set              : bit_vector(lastOpcBit downto 0);
	signal set_exec         : bit_vector(lastOpcBit downto 0);
	signal exec             : bit_vector(lastOpcBit downto 0);

	signal micro_state		: micro_states;
	signal next_micro_state	: micro_states;
	


BEGIN  
ALU: TG68K_ALU   
	generic map(
		MUL_Mode => MUL_Mode,		--0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no MUL,
		DIV_Mode => DIV_Mode		--0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no DIV,
		)
    port map(
        clk  => clk,            		--: in std_logic;
        Reset => Reset,	         		--: in std_logic;
        clkena_lw => clkena_lw,        	--: in std_logic:='1';
        execOPC => execOPC,         	--: in bit;
        exe_condition => exe_condition, --: in std_logic;
        exec_tas => exec_tas,		   	--: in std_logic;
        long_start => long_start_alu,	--: in bit;
        movem_presub => movem_presub,	--: in bit;
        set_stop => set_stop,	   		--: in bit;
        Z_error => Z_error, 	        --: in bit;

        rot_bits => rot_bits, 	      	--: in std_logic_vector(1 downto 0);
		exec => exec,                	--: in bit_vector(lastOpcBit downto 0);
        OP1out => OP1out,          		--: in std_logic_vector(31 downto 0);
        OP2out => OP2out,          		--: in std_logic_vector(31 downto 0);
        reg_QA => reg_QA,          		--: in std_logic_vector(31 downto 0);
        reg_QB => reg_QB,          		--: in std_logic_vector(31 downto 0);
        opcode => opcode,          		--: in std_logic_vector(15 downto 0);
        datatype => datatype, 	      	--: in std_logic_vector(1 downto 0);
        exe_opcode => exe_opcode,       --: in std_logic_vector(15 downto 0);
        exe_datatype => exe_datatype,   --: in std_logic_vector(1 downto 0);
        sndOPC => sndOPC,          		--: in std_logic_vector(15 downto 0);
        last_data_read => last_data_read(15 downto 0),	--: in std_logic_vector(31 downto 0);
        data_read => data_read(15 downto 0),		 	--: in std_logic_vector(31 downto 0);
        FlagsSR => FlagsSR,         	--: in std_logic_vector(7 downto 0);
		micro_state => micro_state,		--: in micro_states;  
		bf_ext_in => bf_ext_in,
		bf_ext_out => bf_ext_out,
		bf_shift => alu_bf_shift,
		bf_width => alu_width,
		bf_loffset => alu_bf_loffset(4 downto 0),
      
        set_V_Flag => set_V_Flag,	    --: buffer bit;
        Flags => Flags,         	 	--: buffer std_logic_vector(8 downto 0);
        c_out => c_out,         	 	--: buffer std_logic_vector(2 downto 0);
        addsub_q => addsub_q,       	--: buffer std_logic_vector(31 downto 0);
        ALUout => ALUout	        	--: buffer std_logic_vector(31 downto 0)
    );
    
	long_start_alu <= to_bit(NOT memmaskmux(3));
-----------------------------------------------------------------------------
-- Bus control
-----------------------------------------------------------------------------
	nWr <= '0' WHEN state="11" ELSE '1';
	busstate <= state;
	nResetOut <= '0' WHEN exec(opcRESET)='1' ELSE '1';
	memmaskmux <= memmask WHEN addr(0)='1' ELSE memmask(4 downto 0)&'1';
	nUDS <= memmaskmux(5);
	nLDS <= memmaskmux(4);
	clkena_lw <= '1' WHEN clkena_in='1' AND memmaskmux(3)='1' ELSE '0';
	
	PROCESS (clk, nReset)
	BEGIN
		IF nReset='0' THEN
			syncReset <= "0000";
			Reset <= '1'; 
	  	ELSIF rising_edge(clk) THEN
			IF clkena_in='1' THEN
				syncReset <= syncReset(2 downto 0)&'1';
				Reset <= NOT syncReset(3);	
			END IF;
		END IF;
	END PROCESS;
			
PROCESS (clk, long_done, last_data_in, data_in, byte, addr, long_start, memmaskmux, memread, memmask, data_read)
	BEGIN
		IF memmaskmux(4)='0' THEN
			data_read <= last_data_in(15 downto 0)&data_in;
		ELSE
			data_read <= last_data_in(23 downto 0)&data_in(15 downto 8);
		END IF;
		IF memread(0)='1' OR (memread(1 downto 0)="10" AND memmaskmux(4)='1')THEN
			data_read(31 downto 16) <= (OTHERS=>data_read(15));
		END IF;	
		
		IF rising_edge(clk) THEN	
			IF clkena_lw='1' AND state="10" THEN
				IF memmaskmux(4)='0' THEN
					bf_ext_in <= last_data_in(23 downto 16);
				ELSE
					bf_ext_in <= last_data_in(31 downto 24);
				END IF;
			END IF;	
			IF Reset='1' THEN
				last_data_read <= (OTHERS => '0');
			ELSIF clkena_in='1' THEN
				IF state="00" OR exec(update_ld)='1' THEN 
					last_data_read <= data_read;
					IF state(1)='0' AND memmask(1)='0' THEN
						last_data_read(31 downto 16) <= last_opc_read;
					ELSIF state(1)='0' OR memread(1)='1' THEN
						last_data_read(31 downto 16) <= (OTHERS=>data_in(15));
					END IF;
				END IF;
				last_data_in <= last_data_in(15 downto 0)&data_in(15 downto 0);
				
			END IF;
		END IF;
				long_start <= to_bit(NOT memmask(1));
				long_done <= to_bit(NOT memread(1));
	END PROCESS;
	
PROCESS (byte, long_start, reg_QB, data_write_tmp, exec, data_read, data_write_mux, memmaskmux, bf_ext_out, 
		 data_write_muxin, memmask, oddout, addr)
	BEGIN
		IF exec(write_reg)='1' THEN
			data_write_muxin <= reg_QB;
		ELSE
			data_write_muxin <= data_write_tmp;
		END IF;
		
		IF BitField=0 THEN
			IF oddout=addr(0) THEN
				data_write_mux <= "XXXXXXXX"&"XXXXXXXX"&data_write_muxin;
			ELSE
				data_write_mux <= "XXXXXXXX"&data_write_muxin&"XXXXXXXX";
			END IF;
		ELSE
			IF oddout=addr(0) THEN
				data_write_mux <= "XXXXXXXX"&bf_ext_out&data_write_muxin;
			ELSE
				data_write_mux <= bf_ext_out&data_write_muxin&"XXXXXXXX";
			END IF;
		END IF;
		
		IF memmaskmux(1)='0' THEN
			data_write <= data_write_mux(47 downto 32);
		ELSIF memmaskmux(3)='0' THEN	
			data_write <= data_write_mux(31 downto 16);
		ELSE
			data_write <= data_write_mux(15 downto 0);
		END IF;
		IF exec(mem_byte)='1' THEN	--movep
			data_write(7 downto 0) <= data_write_tmp(15 downto 8);
		END IF;
	END PROCESS;
	
-----------------------------------------------------------------------------
-- Registerfile
-----------------------------------------------------------------------------
PROCESS (clk, regfile, RDindex_A, RDindex_B, exec)
	BEGIN
		reg_QA <= regfile(RDindex_A);
		reg_QB <= regfile(RDindex_B);
		IF rising_edge(clk) THEN
		    IF clkena_lw='1' THEN
				rf_source_addrd <= rf_source_addr;
				WR_AReg <= rf_dest_addr(3);
				RDindex_A <= conv_integer(rf_dest_addr(3 downto 0));
				RDindex_B <= conv_integer(rf_source_addr(3 downto 0));
				IF Wwrena='1' THEN
					regfile(RDindex_A) <= regin;
				END IF;
				
				IF exec(to_USP)='1' THEN
					USP <= reg_QA;
				END IF;	
			END IF;
		END IF;
	END PROCESS;

-----------------------------------------------------------------------------
-- Write Reg
-----------------------------------------------------------------------------
PROCESS (OP1in, reg_QA, Regwrena_now, Bwrena, Lwrena, exe_datatype, WR_AReg, movem_actiond, exec, ALUout, memaddr, memaddr_a, ea_only, USP, movec_data)
	BEGIN
		regin <= ALUout;
		IF exec(save_memaddr)='1' THEN
			regin <= memaddr;	
		ELSIF exec(get_ea_now)='1' AND ea_only='1' THEN
			regin <= memaddr_a;	
		ELSIF exec(from_USP)='1' THEN
			regin <= USP;	
		ELSIF exec(movec_rd)='1' THEN
			regin <= movec_data;
		END IF;
		
		IF Bwrena='1' THEN
			regin(15 downto 8) <= reg_QA(15 downto 8);
		END IF;
		IF Lwrena='0' THEN
			regin(31 downto 16) <= reg_QA(31 downto 16);
		END IF;

		Bwrena <= '0';
		Wwrena <= '0';
		Lwrena <= '0';
		IF exec(presub)='1' OR exec(postadd)='1' OR exec(changeMode)='1' THEN		-- -(An)+
			Wwrena <= '1';
			Lwrena <= '1';
		ELSIF Regwrena_now='1' THEN		--dbcc	
			Wwrena <= '1';
		ELSIF exec(Regwrena)='1' THEN		--read (mem)
			Wwrena <= '1';
			CASE exe_datatype IS
				WHEN "00" =>		--BYTE
					Bwrena <= '1';
				WHEN "01" =>		--WORD
					IF WR_AReg='1' OR movem_actiond='1' THEN
						Lwrena <='1';
					END IF;
				WHEN OTHERS =>		--LONG
					Lwrena <= '1';
			END CASE;
		END IF;	
	END PROCESS;
	
-----------------------------------------------------------------------------
-- set dest regaddr
-----------------------------------------------------------------------------
PROCESS (opcode, rf_source_addrd, brief, setstackaddr, dest_hbits, dest_areg, data_is_source, sndOPC, exec, set, dest_2ndHbits)
	BEGIN
		IF exec(movem_action) ='1' THEN
			rf_dest_addr <= rf_source_addrd;
		ELSIF set(briefext)='1' THEN
			rf_dest_addr <= brief(15 downto 12);
		ELSIF set(get_bfoffset)='1' THEN
			rf_dest_addr <= sndOPC(9 downto 6);
		ELSIF dest_2ndHbits='1' THEN
			rf_dest_addr <= sndOPC(15 downto 12);
		ELSIF set(write_reminder)='1' THEN
			rf_dest_addr <= sndOPC(3 downto 0);
		ELSIF setstackaddr='1' THEN	
			rf_dest_addr <= "1111";
		ELSIF dest_hbits='1' THEN	
			rf_dest_addr <= dest_areg&opcode(11 downto 9);
		ELSE
			IF opcode(5 downto 3)="000" OR data_is_source='1' THEN 			
				rf_dest_addr <= dest_areg&opcode(2 downto 0);
			ELSE
				rf_dest_addr <= '1'&opcode(2 downto 0);
			END IF;
		END IF;	
	END PROCESS;
	
-----------------------------------------------------------------------------
-- set source regaddr
-----------------------------------------------------------------------------
PROCESS (opcode, movem_presub, movem_regaddr, source_lowbits, source_areg, sndOPC, exec, set, source_2ndLbits, source_2ndHbits)
	BEGIN
		IF exec(movem_action)='1' OR set(movem_action) ='1' THEN
			IF movem_presub='1' THEN
				rf_source_addr <= movem_regaddr XOR "1111";
			ELSE
				rf_source_addr <= movem_regaddr;
			END IF; 
		ELSIF source_2ndLbits='1' THEN
			rf_source_addr <= sndOPC(3 downto 0);
		ELSIF source_2ndHbits='1' THEN
			rf_source_addr <= sndOPC(15 downto 12);
		ELSIF source_lowbits='1' THEN
			rf_source_addr <= source_areg&opcode(2 downto 0);
		ELSIF exec(linksp)='1' THEN
			rf_source_addr <= "1111";
		ELSE
			rf_source_addr <= source_areg&opcode(11 downto 9);
		END IF;	
	END PROCESS;
	
-----------------------------------------------------------------------------
-- set OP1out
-----------------------------------------------------------------------------
PROCESS (reg_QA, store_in_tmp, ea_data, long_start, addr, exec, memmaskmux)
	BEGIN
		OP1out <= reg_QA;
		IF exec(OP1out_zero)='1' THEN
			OP1out <= (OTHERS => '0');	
		ELSIF exec(ea_data_OP1)='1' AND store_in_tmp='1' THEN
			OP1out <= ea_data;
		ELSIF exec(movem_action)='1' OR memmaskmux(3)='0' OR exec(OP1addr)='1' THEN 
			OP1out <= addr;
		END IF;
	END PROCESS;
	
-----------------------------------------------------------------------------
-- set OP2out
-----------------------------------------------------------------------------
PROCESS (OP2out, reg_QB, exe_opcode, exe_datatype, execOPC, exec, use_direct_data, 
	     store_in_tmp, data_write_tmp, ea_data)
	BEGIN
		OP2out(15 downto 0) <= reg_QB(15 downto 0);
		OP2out(31 downto 16) <= (OTHERS => OP2out(15));
		IF exec(OP2out_one)='1' THEN
			OP2out(15 downto 0) <= "1111111111111111";
		ELSIF exec(opcEXT)='1' THEN
			IF exe_opcode(6)='0' OR exe_opcode(8)='1' THEN	--ext.w
				OP2out(15 downto 8) <= (OTHERS => OP2out(7));		
			END IF;	
		ELSIF use_direct_data='1' OR (exec(exg)='1' AND execOPC='1') OR exec(get_bfoffset)='1' THEN	
			OP2out <= data_write_tmp;	
		ELSIF (exec(ea_data_OP1)='0' AND store_in_tmp='1') OR exec(ea_data_OP2)='1' THEN
			OP2out <= ea_data;	
		ELSIF exec(opcMOVEQ)='1' THEN
			OP2out(7 downto 0) <= exe_opcode(7 downto 0);
			OP2out(15 downto 8) <= (OTHERS => exe_opcode(7));
		ELSIF exec(opcADDQ)='1' THEN
			OP2out(2 downto 0) <= exe_opcode(11 downto 9);
			IF exe_opcode(11 downto 9)="000" THEN
				OP2out(3) <='1';
			ELSE
				OP2out(3) <='0';
			END IF;
			OP2out(15 downto 4) <= (OTHERS => '0');
		ELSIF exe_datatype="10" THEN 
			OP2out(31 downto 16) <= reg_QB(31 downto 16);
		END IF;
	END PROCESS;
	

-----------------------------------------------------------------------------
-- handle EA_data, data_write
-----------------------------------------------------------------------------
PROCESS (clk)
	BEGIN
     	IF rising_edge(clk) THEN
			IF Reset = '1' THEN
				store_in_tmp <='0';
				exec_write_back <= '0';
				direct_data <= '0';
				use_direct_data <= '0';
				Z_error <= '0';
			ELSIF clkena_lw='1' THEN
				direct_data <= '0';
				IF state="11" THEN
					exec_write_back <= '0';
				ELSIF setstate="10" AND write_back='1' THEN
					exec_write_back <= '1';
				END IF;	

					
				IF set_direct_data='1' THEN
					direct_data <= '1';
					use_direct_data <= '1';
				ELSIF endOPC='1' THEN	
					use_direct_data <= '0';
				END IF;	
				exec_DIRECT <= set_exec(opcMOVE);
				
				IF endOPC='1' THEN
					store_in_tmp <='0';
					Z_error <= '0';
				ELSE
					IF set_Z_error='1'  THEN
						Z_error <= '1';
					END IF;	
					IF set_exec(opcMOVE)='1' AND state="11" THEN
						use_direct_data <= '1';
					END IF;

					IF state="10" THEN
						store_in_tmp <= '1'; 
					END IF;
					IF direct_data='1' AND state="00" THEN
						store_in_tmp <= '1'; 
					END IF;	
				END IF;
				IF state="10" THEN
					ea_data <= data_read;
				ELSIF exec(get_2ndOPC)='1' THEN
					ea_data <= addr;
				ELSIF exec(store_ea_data)='1' OR (direct_data='1' AND state="00") THEN
					ea_data <= last_data_read;
				END IF;	
				
				IF writePC='1' THEN
					data_write_tmp <= TG68_PC;
				ELSIF exec(writePC_add)='1' THEN
					data_write_tmp <= TG68_PC_add;
				ELSIF micro_state=trap0 THEN	
					data_write_tmp(15 downto 0) <= trap_vector(15 downto 0);
				ELSIF exec(hold_dwr)='1' THEN	
					data_write_tmp <= data_write_tmp;
				ELSIF exec(exg)='1' THEN	
					data_write_tmp <= OP1out;
				ELSIF exec(get_ea_now)='1' AND ea_only='1' THEN		-- ist for pea
					data_write_tmp <= addr;
				ELSIF execOPC='1' THEN
					data_write_tmp <= ALUout;
				ELSIF (exec_DIRECT='1' AND state="10") THEN
					data_write_tmp <= data_read;
					IF  exec(movepl)='1' THEN
						data_write_tmp(31 downto 8) <= data_write_tmp(23 downto 0);
					END IF;
				ELSIF exec(movepl)='1' THEN
					data_write_tmp(15 downto 0) <= reg_QB(31 downto 16);
				ELSIF direct_data='1' THEN
					data_write_tmp <= last_data_read;
				ELSIF writeSR='1'THEN
					data_write_tmp(15 downto 0) <= trap_SR(7 downto 0)& Flags(7 downto 0);
				ELSE	
					data_write_tmp <= OP2out;
				END IF;
			END IF;	
		END IF;	
	END PROCESS;
	
-----------------------------------------------------------------------------
-- brief
-----------------------------------------------------------------------------
PROCESS (brief, OP1out, OP1outbrief, cpu)
	BEGIN
		IF brief(11)='1' THEN
			OP1outbrief <= OP1out(31 downto 16);
		ELSE
			OP1outbrief <= (OTHERS=>OP1out(15));
		END IF;
		briefdata <= OP1outbrief&OP1out(15 downto 0);
		IF extAddr_Mode=1 OR (cpu(1)='1' AND extAddr_Mode=2) THEN
			CASE brief(10 downto 9) IS
				WHEN "00" => briefdata <= OP1outbrief&OP1out(15 downto 0);
				WHEN "01" => briefdata <= OP1outbrief(14 downto 0)&OP1out(15 downto 0)&'0';
				WHEN "10" => briefdata <= OP1outbrief(13 downto 0)&OP1out(15 downto 0)&"00";
				WHEN "11" => briefdata <= OP1outbrief(12 downto 0)&OP1out(15 downto 0)&"000";
				WHEN OTHERS => NULL;
			END CASE;
		END IF;
	END PROCESS;

-----------------------------------------------------------------------------
-- MEM_IO 
-----------------------------------------------------------------------------
PROCESS (clk, setdisp, memaddr_a, briefdata, memaddr_delta, setdispbyte, datatype, interrupt, rIPL_nr, IPL_vec,
         memaddr_reg, reg_QA, use_base, VBR, last_data_read, trap_vector, exec, set, cpu)
	BEGIN
		
		IF rising_edge(clk) THEN
			IF clkena_lw='1' THEN
				trap_vector(31 downto 8) <= (others => '0');
		--		IF trap_addr_fault='1' THEN
		--			trap_vector(7 downto 0) <= X"08";
		--		END IF;	
				IF trap_addr_error='1' THEN
					trap_vector(7 downto 0) <= X"0C";
				END IF;	
				IF trap_illegal='1' THEN
					trap_vector(7 downto 0) <= X"10";
				END IF;	
				IF z_error='1' THEN
					trap_vector(7 downto 0) <= X"14";
				END IF;	
				IF exec(trap_chk)='1' THEN
					trap_vector(7 downto 0) <= X"18";
				END IF;	
				IF trap_trapv='1' THEN
					trap_vector(7 downto 0) <= X"1C";
				END IF;	
				IF trap_priv='1' THEN
					trap_vector(7 downto 0) <= X"20";
				END IF;	
				IF trap_trace='1' THEN
					trap_vector(7 downto 0) <= X"24";
				END IF;	
				IF trap_1010='1' THEN
					trap_vector(7 downto 0) <= X"28";
				END IF;	
				IF trap_1111='1' THEN
					trap_vector(7 downto 0) <= X"2C";
				END IF;	
				IF trap_trap='1' THEN
					trap_vector(7 downto 2) <= "10"&opcode(3 downto 0);
				END IF;	
				IF trap_interrupt='1' THEN
					trap_vector(9 downto 2) <= IPL_vec;      --TH
				END IF;	
                                -- TH TODO: non-autovector IRQs
			END IF;
		END IF;
		IF VBR_Stackframe=0 OR (cpu(0)='0' AND VBR_Stackframe=2) THEN
			trap_vector_vbr <= trap_vector;
		ELSE		
			trap_vector_vbr <= trap_vector+VBR;
		END IF;		
		
		memaddr_a(4 downto 0) <= "00000";
		memaddr_a(7 downto 5) <= (OTHERS=>memaddr_a(4));
		memaddr_a(15 downto 8) <= (OTHERS=>memaddr_a(7));
		memaddr_a(31 downto 16) <= (OTHERS=>memaddr_a(15));
		IF setdisp='1' THEN
			IF exec(briefext)='1' THEN
				memaddr_a <= briefdata+memaddr_delta;
			ELSIF setdispbyte='1' THEN
				memaddr_a(7 downto 0) <= last_data_read(7 downto 0);
			ELSE
				memaddr_a <= last_data_read;
			END IF;	 
		ELSIF set(presub)='1' THEN
			IF set(longaktion)='1' THEN	
				memaddr_a(4 downto 0) <= "11100";
			ELSIF datatype="00" AND set(use_SP)='0' THEN
				memaddr_a(4 downto 0) <= "11111";
			ELSE
				memaddr_a(4 downto 0) <= "11110";
			END IF;	
		ELSIF interrupt='1' THEN
			memaddr_a(4 downto 0) <= '1'&rIPL_nr&'0';	
		END IF;	 
		
		IF rising_edge(clk) THEN
			IF clkena_in='1' THEN
				IF exec(get_2ndOPC)='1' OR (state="10" AND memread(0)='1') THEN
					tmp_TG68_PC <= addr;
				END IF;
				use_base <= '0'; 
				IF memmaskmux(3)='0' OR exec(mem_addsub)='1' THEN
					memaddr_delta <= addsub_q;	
				ELSIF state="01" AND exec_write_back='1' THEN			
					memaddr_delta <= tmp_TG68_PC;
				ELSIF exec(direct_delta)='1' THEN
					memaddr_delta <= data_read;
				ELSIF exec(ea_to_pc)='1' AND setstate="00" THEN
					memaddr_delta <= addr;
				ELSIF set(addrlong)='1' THEN
					memaddr_delta <= last_data_read;
				ELSIF setstate="00" THEN	
					memaddr_delta <= TG68_PC_add;
				ELSIF exec(dispouter)='1' THEN
					memaddr_delta <= ea_data+memaddr_a;
				ELSIF set_vectoraddr='1' THEN	
					memaddr_delta <= trap_vector_vbr;
				ELSE 
					memaddr_delta <= memaddr_a;
					IF interrupt='0' AND Suppress_Base='0' THEN
--					IF interrupt='0' AND Suppress_Base='0' AND setstate(1)='1' THEN
						use_base <= '1';
					END IF;	
				END IF;
					
--				IF clkena_in THEN
					IF (long_done='0' AND state(1)='1') OR movem_presub='0' THEN
						memaddr <= addr;
					END IF;
--				END IF;
			END IF;
		END IF;

		addr <= memaddr_reg+memaddr_delta;
		IF use_base='0' THEN
			memaddr_reg <= (others=>'0');
		ELSE	
			memaddr_reg <= reg_QA;
		END IF;	
    END PROCESS;
    
-----------------------------------------------------------------------------
-- PC Calc + fetch opcode
-----------------------------------------------------------------------------
PROCESS (clk, IPL, setstate, state, exec_write_back, set_direct_data, next_micro_state, stop, make_trace, IPL_nr, FlagsSR, set_rot_cnt, opcode, writePCbig, set_exec, exec,
	     PC_dataa, PC_datab, setnextpass, last_data_read, TG68_PC_brw, TG68_PC_word, Z_error, trap_trap, trap_trapv, interrupt, tmp_TG68_PC, TG68_PC)
	BEGIN
	
		PC_dataa <= TG68_PC;
		IF TG68_PC_brw = '1' THEN
			PC_dataa <= tmp_TG68_PC;
		END IF;
		
		PC_datab(2 downto 0) <= (others => '0');
		PC_datab(3) <= PC_datab(2);
		PC_datab(7 downto 4) <= (others => PC_datab(3));
		PC_datab(15 downto 8) <= (others => PC_datab(7));
		PC_datab(31 downto 16) <= (others => PC_datab(15));
		IF interrupt='1' THEN
			PC_datab(2 downto 1) <= "11";
		END IF;
		IF exec(writePC_add) ='1' THEN
			IF writePCbig='1' THEN
				PC_datab(3) <= '1';
				PC_datab(1) <= '1';
			ELSE	
				PC_datab(2) <= '1';
			END IF;
			IF trap_trap='1' OR trap_trapv='1' OR exec(trap_chk)='1' OR Z_error='1' THEN 
				PC_datab(1) <= '1';
			END IF;
		ELSIF state="00" THEN
			PC_datab(1) <= '1';
		END IF;	
		IF TG68_PC_brw = '1' THEN	
			IF TG68_PC_word='1' THEN
				PC_datab <= last_data_read;
			ELSE
				PC_datab(7 downto 0) <= opcode(7 downto 0);
			END IF;
		END IF;

		TG68_PC_add <= PC_dataa+PC_datab;
		
		setopcode <= '0';
		setendOPC <= '0';
		setinterrupt <= '0';
		IF setstate="00" AND next_micro_state=idle AND setnextpass='0' AND (exec_write_back='0' OR state="11") AND set_rot_cnt="000001" AND set_exec(opcCHK)='0'THEN
			setendOPC <= '1';
			IF FlagsSR(2 downto 0)<IPL_nr OR IPL_nr="111"  OR make_trace='1' THEN
				setinterrupt <= '1';
			ELSIF stop='0' THEN
				setopcode <= '1';
			END IF;
		END IF;	
		setexecOPC <= '0';
		IF setstate="00" AND next_micro_state=idle AND set_direct_data='0' AND (exec_write_back='0' OR state="10") THEN
			setexecOPC <= '1';
		END IF;
		
		IPL_nr <= NOT IPL;
		IF rising_edge(clk) THEN
	      	IF Reset = '1' THEN
				state <= "01";
				opcode <= X"2E79"; 					--move $0,a7
				trap_interrupt <= '0';
				interrupt <= '0';
				last_opc_read  <= X"4EF9";			--jmp nn.l
				TG68_PC <= X"00000004";
				decodeOPC <= '0';
				endOPC <= '0';
				TG68_PC_word <= '0';
				execOPC <= '0';
				stop <= '0';
				rot_cnt <="000001";
				byte <= '0';
--				IPL_nr <= "000";
				trap_trace <= '0';
				writePCbig <= '0';
--				recall_last <= '0';
				Suppress_Base <= '0'; 
				memmask <= "111111";
			ELSE
--				IPL_nr <= NOT IPL;
				IF clkena_in='1' THEN
					memmask <= memmask(3 downto 0)&"11";
					memread <= memread(1 downto 0)&memmaskmux(5 downto 4);
--					IF wbmemmask(5 downto 4)="11" THEN	
--						wbmemmask <= memmask;
--					END IF;
					IF exec(directPC)='1' THEN
						TG68_PC <= data_read;
					ELSIF exec(ea_to_pc)='1' THEN
						TG68_PC <= addr;
					ELSIF (state ="00" OR TG68_PC_brw = '1') AND stop='0'  THEN				
						TG68_PC <= TG68_PC_add;
					END IF;	
				END IF;	
				IF clkena_lw='1' THEN
					interrupt <= setinterrupt;
					decodeOPC <= setopcode;
					endOPC <= setendOPC;
					execOPC <= setexecOPC;
					
					exe_datatype <= set_datatype;
					exe_opcode <= opcode;

					stop <= set_stop OR (stop AND NOT setinterrupt);
					IF setinterrupt='1' THEN
						IF make_trace='1' THEN
							trap_trace <= '1';
						ELSE	
							rIPL_nr <= IPL_nr;
							IPL_vec <= "00011"&IPL_nr;            --	TH		
							trap_interrupt <= '1';
						END IF;
					END IF;	
					IF micro_state=trap0 AND IPL_autovector='0' THEN 			
						IPL_vec <= last_data_read(7 downto 0);    --	TH
					END IF;	
					IF state="00" THEN				
						last_opc_read <= data_read(15 downto 0);
					END IF;	
					IF setopcode='1' THEN
						trap_interrupt <= '0';
						trap_trace <= '0';
						TG68_PC_word <= '0';
					ELSIF opcode(7 downto 0)="00000000" OR opcode(7 downto 0)="11111111" OR data_is_source='1' THEN
						TG68_PC_word <= '1';
					END IF;	
					
					IF exec(get_bfoffset)='1' THEN
						alu_width <= bf_width;
						alu_bf_shift <= bf_shift;
						alu_bf_loffset <= bf_loffset;
					END IF;
					byte <= '0';
					memread <= "1111";
					FC(1) <= NOT setstate(1) OR (PCbase AND NOT setstate(0));
					FC(0) <= setstate(1) AND (NOT PCbase OR setstate(0));
					IF interrupt='1' THEN
						FC(1 downto 0) <= "11";
					END IF;	
					IF (state="10" AND write_back='1' AND setstate/="10") OR set_rot_cnt/="000001" OR (stop='1' AND interrupt='0') OR set_exec(opcCHK)='1' THEN
						state <= "01";
						memmask <= "111111";
					ELSIF execOPC='1' AND exec_write_back='1' THEN
						state <= "11";
						FC(1 downto 0) <= "01";
						memmask <= wbmemmask;
						IF datatype="00" THEN
							byte <= '1';
						END IF;
					ELSE	
						state <= setstate;
						IF setstate="01" THEN
							memmask <= "111111";
							wbmemmask <= "111111";
						ELSIF exec(get_bfoffset)='1' THEN
							memmask <= set_memmask;
							wbmemmask <= set_memmask;
							oddout <= set_oddout;
						ELSIF set(longaktion)='1' THEN
							memmask <= "100001";
							wbmemmask <= "100001";
							oddout <= '0';
						ELSIF set_datatype="00" AND setstate(1)='1' THEN	
							memmask <= "101111";
							wbmemmask <= "101111";
							IF set(mem_byte)='1' THEN
								oddout <= '0';
							ELSE
								oddout <= '1';
							END IF;	
						ELSE	
							memmask <= "100111";
							wbmemmask <= "100111";
							oddout <= '0';
						END IF;	
					END IF;

					IF decodeOPC='1' THEN
						rot_bits <= set_rot_bits;
						writePCbig <= '0';
					ELSE	
						writePCbig <= set_writePCbig OR writePCbig; 
					END IF;
					IF decodeOPC='1' OR exec(ld_rot_cnt)='1' OR rot_cnt/="000001" THEN
						rot_cnt <= set_rot_cnt;
					END IF;
					IF setstate(1)='1' AND set_datatype="00" THEN
						byte <= '1';
					END IF;
					
					IF set_Suppress_Base='1' THEN
						Suppress_Base <= '1';
					ELSIF setstate(1)='1' OR (ea_only='1' AND set(get_ea_now)='1') THEN	
						Suppress_Base <= '0';
					END IF;
					IF getbrief='1' THEN
						IF state(1)='1' THEN
							brief <= last_opc_read(15 downto 0);
						ELSE
							brief <= data_read(15 downto 0);
						END IF;
					END IF;	
					
					IF setopcode='1' THEN
						IF state="00" THEN
							opcode <= data_read(15 downto 0);
						ELSE
							opcode <= last_opc_read(15 downto 0);
						END IF;
						nextpass <= '0';
					ELSIF setinterrupt='1' THEN
						opcode(15 downto 12) <= X"7";		--moveq
						opcode(8 downto 6) <= "001";		--word
						nextpass <= '0';
					ELSE
--						IF setnextpass='1' OR (regdirectsource='1' AND state="00") THEN
						IF setnextpass='1' OR regdirectsource='1' THEN
							nextpass <= '1';	
						END IF;
					END IF;
	
					IF decodeOPC='1' OR interrupt='1' THEN
						trap_SR <= FlagsSR;
					END IF;
				END IF;	
			END IF;	
		END IF;	
	
		IF rising_edge(clk) THEN
	      	IF Reset = '1' THEN
				PCbase <= '1';
			ELSIF clkena_lw='1' THEN
				PCbase <= set_PCbase OR PCbase;
				IF setexecOPC='1' OR (state(1)='1' AND movem_run='0') THEN
					PCbase <= '0';
				END IF;	
			END IF;	
			IF clkena_lw='1' THEN
				exec <= set;
				exec_tas <= '0';
				exec(subidx) <= set(presub) or set(subidx);
				IF setexecOPC='1' THEN
					exec <= set_exec OR set;
					exec_tas <= set_exec_tas;
				END IF;	
				exec(get_2ndOPC) <= set(get_2ndOPC) OR setopcode;
			END IF;	
		END IF;	
	END PROCESS;
	
------------------------------------------------------------------------------
--prepare Bitfield Parameters
------------------------------------------------------------------------------		
PROCESS (clk, Reset, sndOPC, reg_QA, reg_QB, bf_width, bf_offset, bf_bhits, opcode, setstate, bf_shift)
	BEGIN
		IF sndOPC(11)='1' THEN
			bf_offset <= '0'&reg_QA(4 downto 0);
		ELSE
			bf_offset <= '0'&sndOPC(10 downto 6);
		END IF;	
		
		bf_width(5) <= '0';
		IF sndOPC(5)='1' THEN
			bf_width(4 downto 0) <= reg_QB(4 downto 0)-1;
		ELSE
			bf_width(4 downto 0) <= sndOPC(4 downto 0)-1;
		END IF;	
		bf_bhits <= bf_width+bf_offset;
		set_oddout <= NOT bf_bhits(3);
		
		IF opcode(10 downto 8)="111" THEN --INS
			bf_loffset <= 32-bf_shift;
		ELSE
			bf_loffset <= bf_shift;
		END IF;
		bf_loffset(5) <= '0';
		
		IF opcode(4 downto 3)="00" THEN
			IF opcode(10 downto 8)="111" THEN --INS
				bf_shift <= bf_bhits+1;
			ELSE
				bf_shift <= 31-bf_bhits;
			END IF;
			bf_shift(5) <= '0';
		ELSE
			IF opcode(10 downto 8)="111" THEN --INS
				bf_shift <= "011"&("001"+bf_bhits(2 downto 0));
			ELSE
				bf_shift <= "000"&("111"-bf_bhits(2 downto 0));
			END IF;
			bf_offset(4 downto 3) <= "00";
		END IF;
		 	
			CASE bf_bhits(5 downto 3) IS
				WHEN "000" =>
					set_memmask <= "101111";
				WHEN "001" =>
					set_memmask <= "100111";
				WHEN "010" =>
					set_memmask <= "100011";
				WHEN "011" =>
					set_memmask <= "100001";
				WHEN OTHERS =>
					set_memmask <= "100000";
			END CASE;	
			IF setstate="00" THEN
				set_memmask <= "100111";
			END IF;
	END PROCESS;		
	
------------------------------------------------------------------------------
--SR op
------------------------------------------------------------------------------		
PROCESS (clk, Reset, FlagsSR, last_data_read, OP2out, exec)
	BEGIN
		IF exec(andiSR)='1' THEN
			SRin <= FlagsSR AND last_data_read(15 downto 8);
		ELSIF exec(eoriSR)='1' THEN
			SRin <= FlagsSR XOR last_data_read(15 downto 8);
		ELSIF exec(oriSR)='1' THEN
			SRin <= FlagsSR OR last_data_read(15 downto 8);
		ELSE	
			SRin <= OP2out(15 downto 8);
		END IF;	
		
		IF rising_edge(clk) THEN
	        IF Reset='1' THEN
				FlagsSR(5) <= '1';
				FC(2) <= '1';
				SVmode <= '1';
				preSVmode <= '1';
				FlagsSR(2 downto 0) <= "111";
				make_trace <= '0';
			ELSIF clkena_lw = '1' THEN
				IF setopcode='1' THEN
					make_trace <= FlagsSR(7);
					IF set(changeMode)='1' THEN
						SVmode <= NOT SVmode; 
					ELSE
						SVmode <= preSVmode;
					END IF;	
				END IF;	
				IF set(changeMode)='1' THEN
					preSVmode <= NOT preSVmode;
					FlagsSR(5) <= NOT preSVmode;
					FC(2) <= NOT preSVmode;
				END IF;
				IF micro_state=trap3 THEN
					FlagsSR(7) <= '0';
				END IF;
				IF trap_trace='1' AND state="10" THEN
					make_trace <= '0';
				END IF;
				IF exec(directSR)='1' OR set_stop='1' THEN
					FlagsSR <= data_read(15 downto 8);
				END IF;	
				IF interrupt='1' AND trap_interrupt='1' THEN
					FlagsSR(2 downto 0) <=rIPL_nr;
				END IF;	
--				IF exec(to_CCR)='1' AND exec(to_SR)='1' THEN
				IF exec(to_SR)='1' THEN
					FlagsSR(7 downto 0) <= SRin;	--SR
					FC(2) <= SRin(5);
--				END IF;	
				ELSIF exec(update_FC)='1' THEN
					FC(2) <= FlagsSR(5);
				END IF;
				IF interrupt='1' THEN
					FC(2) <= '1';
				END IF;	
			END IF;
		END IF;	
	END PROCESS;

-----------------------------------------------------------------------------
-- decode opcode
-----------------------------------------------------------------------------
PROCESS (clk, cpu, OP1out, OP2out, opcode, exe_condition, nextpass, micro_state, decodeOPC, state, setexecOPC, Flags, FlagsSR, direct_data, build_logical,
		 build_bcd, set_Z_error, trapd, movem_run, last_data_read, set, set_V_Flag, z_error, trap_trace, trap_interrupt,
		 SVmode, preSVmode, stop, long_done, ea_only, setstate, execOPC, exec_write_back, exe_datatype,
		 datatype, interrupt, c_out, trapmake, rot_cnt, brief, addr, 
		 long_start, set_datatype, sndOPC, set_exec, exec, ea_build_now, reg_QA, reg_QB)
	BEGIN
		TG68_PC_brw <= '0';	
		setstate <= "00";
		Regwrena_now <= '0';
		movem_presub <= '0';
		setnextpass <= '0';
		regdirectsource <= '0';
		setdisp <= '0';
		setdispbyte <= '0';
		getbrief <= '0';
		dest_areg <= '0';
		source_areg <= '0';
		data_is_source <= '0';
		write_back <= '0';
		setstackaddr <= '0';
		writePC <= '0';
		ea_build_now <= '0';
		set_rot_bits <= "XX";
		set_rot_cnt <= "000001";
		dest_hbits <= '0';
		source_lowbits <= '0';
		source_2ndHbits <= '0';
		source_2ndLbits <= '0';
		dest_2ndHbits <= '0';
		ea_only <= '0';
		set_direct_data <= '0';
		set_exec_tas <= '0';
		trap_illegal <='0';
		trap_addr_error <= '0';
		trap_priv <='0';
		trap_1010 <='0';
		trap_1111 <='0';
		trap_trap <='0';
		trap_trapv <= '0';
		trapmake <='0';
		set_vectoraddr <='0';
		writeSR <= '0';
		set_stop <= '0';
		illegal_write_mode <= '0';
		illegal_read_mode <= '0';
		illegal_byteaddr <= '0';
		set_Z_error <= '0';

		next_micro_state <= idle;
		build_logical <= '0';
		build_bcd <= '0';
		skipFetch <= '0';
		set_writePCbig <= '0';
--		set_recall_last <= '0';
		set_Suppress_Base <= '0';
		set_PCbase <= '0';
						
		IF rot_cnt/="000001" THEN
			set_rot_cnt <= rot_cnt-1;
		END IF;	
		set_datatype <= datatype;
		
		set <= (OTHERS=>'0');
		set_exec <= (OTHERS=>'0');
		set(update_ld) <= '0';
--		odd_start <= '0';
------------------------------------------------------------------------------
--Sourcepass
------------------------------------------------------------------------------		
		CASE opcode(7 downto 6) IS
			WHEN "00" => datatype <= "00";		--Byte
			WHEN "01" => datatype <= "01";		--Word
			WHEN OTHERS => datatype <= "10";	--Long
		END CASE;
		
		IF trapmake='1' AND trapd='0' THEN
			next_micro_state <= trap0;
			IF VBR_Stackframe=0 OR (cpu(0)='0' AND VBR_Stackframe=2) THEN
				set(writePC_add) <= '1';
--				set_datatype <= "10";
			END IF;
			IF preSVmode='0' THEN
				set(changeMode) <= '1';
			END IF;
			setstate <= "01";
		END IF;	
		IF micro_state=int1 OR (interrupt='1' AND trap_trace='1') THEN
			next_micro_state <= trap0;
--			IF cpu(0)='0' THEN
--				set_datatype <= "10";
--			END IF;
			IF preSVmode='0' THEN
				set(changeMode) <= '1';
			END IF;
			setstate <= "01";
		END IF;	
		
		IF setexecOPC='1' AND FlagsSR(5)/=preSVmode THEN
			set(changeMode) <= '1';
--			setstate <= "01";
--			next_micro_state <= nop;
		END IF;

		IF interrupt='1' AND trap_interrupt='1'THEN
--			skipFetch <= '1';
			next_micro_state <= int1;
			set(update_ld) <= '1';
			setstate <= "10";
		END IF;
			
		IF set(changeMode)='1' THEN		
			set(to_USP) <= '1';
			set(from_USP) <= '1';
			setstackaddr <='1';
		END IF;
			
		IF ea_only='0' AND set(get_ea_now)='1' THEN
			setstate <= "10";
--			set_recall_last <= '1';
--			set(update_ld) <= '0';
		END IF;

		IF setstate(1)='1' AND set_datatype(1)='1' THEN
			set(longaktion) <= '1';
		END IF;

		IF (ea_build_now='1' AND decodeOPC='1') OR exec(ea_build)='1' THEN
			CASE opcode(5 downto 3) IS		--source
				WHEN "010"|"011"|"100" =>						-- -(An)+
					set(get_ea_now) <='1';
					setnextpass <= '1';
					IF opcode(3)='1' THEN	--(An)+
						set(postadd) <= '1';
						IF opcode(2 downto 0)="111" THEN
							set(use_SP) <= '1';
						END IF;
					END IF;	 	
					IF opcode(5)='1' THEN	-- -(An)
						set(presub) <= '1'; 					
						IF opcode(2 downto 0)="111" THEN
							set(use_SP) <= '1';
						END IF;
					END IF;	 	
				WHEN "101" =>				--(d16,An)
					next_micro_state <= ld_dAn1;
				WHEN "110" =>				--(d8,An,Xn)
					next_micro_state <= ld_AnXn1;
					getbrief <='1';
				WHEN "111" =>
					CASE opcode(2 downto 0) IS
						WHEN "000" =>				--(xxxx).w
							next_micro_state <= ld_nn;
						WHEN "001" =>				--(xxxx).l
							set(longaktion) <= '1';
							next_micro_state <= ld_nn;
						WHEN "010" =>				--(d16,PC)
							next_micro_state <= ld_dAn1;
							set(dispouter) <= '1';
							set_Suppress_Base <= '1';
							set_PCbase <= '1';
						WHEN "011" =>				--(d8,PC,Xn)
							next_micro_state <= ld_AnXn1;
							getbrief <= '1';
							set(dispouter) <= '1';
							set_Suppress_Base <= '1';
							set_PCbase <= '1';
						WHEN "100" =>				--#data
							setnextpass <= '1';
							set_direct_data <= '1';
							IF datatype="10" THEN
								set(longaktion) <= '1';
							END IF;
						WHEN OTHERS => NULL;
					END CASE;
				WHEN OTHERS => NULL;
			END CASE;
		END IF;
------------------------------------------------------------------------------
--prepere opcode
------------------------------------------------------------------------------		
		CASE opcode(15 downto 12) IS
-- 0000 ----------------------------------------------------------------------------		
			WHEN "0000" => 
			IF opcode(8)='1' AND opcode(5 downto 3)="001" THEN --movep
				datatype <= "00";				--Byte
				set(use_SP) <= '1';		--addr+2
				set(no_Flags) <='1';
				IF opcode(7)='0' THEN  --to register
					set_exec(Regwrena) <= '1';
					set_exec(opcMOVE) <= '1';
					set(movepl) <= '1';
				END IF;
				IF decodeOPC='1' THEN
					IF opcode(6)='1' THEN
						set(movepl) <= '1';
					END IF;
					IF opcode(7)='0' THEN	
						set_direct_data <= '1';		-- to register
					END IF;
					next_micro_state <= movep1;
				END IF;
				IF setexecOPC='1' THEN  
					dest_hbits <='1';
				END IF;
			ELSE
				IF opcode(8)='1' OR opcode(11 downto 9)="100" THEN		--Bits
					set_exec(opcBITS) <= '1';
					set_exec(ea_data_OP1) <= '1';
					IF opcode(7 downto 6)/="00" THEN 
						IF opcode(5 downto 4)="00" THEN
							set_exec(Regwrena) <= '1';
						END IF;
						write_back <= '1';
					END IF;
					IF opcode(5 downto 4)="00" THEN
						datatype <= "10";			--Long
					ELSE	
						datatype <= "00";			--Byte
					END IF;
					IF opcode(8)='0' THEN
						IF decodeOPC='1' THEN
							next_micro_state <= nop;
							set(get_2ndOPC) <= '1';
							set(ea_build) <= '1';
						END IF;	
					ELSE	
						ea_build_now <= '1';
					END IF;
				ELSIF opcode(11 downto 9)="111" THEN		--MOVES not in 68000
					trap_illegal <= '1';
--					trap_addr_error <= '1';
					trapmake <= '1';
				ELSE								--andi, ...xxxi	
					IF opcode(11 downto 9)="000" THEN	--ORI
						set_exec(opcOR) <= '1';
					END IF;
					IF opcode(11 downto 9)="001" THEN	--ANDI
						set_exec(opcAND) <= '1';
					END IF;
					IF opcode(11 downto 9)="010" OR opcode(11 downto 9)="011" THEN	--SUBI, ADDI
						set_exec(opcADD) <= '1';
					END IF;
					IF opcode(11 downto 9)="101" THEN	--EORI
						set_exec(opcEOR) <= '1';
					END IF;
					IF opcode(11 downto 9)="110" THEN	--CMPI
						set_exec(opcCMP) <= '1';
					END IF;
					IF opcode(7)='0' AND opcode(5 downto 0)="111100" AND (set_exec(opcAND) OR set_exec(opcOR) OR set_exec(opcEOR))='1' THEN		--SR
						IF decodeOPC='1' AND SVmode='0' AND opcode(6)='1' THEN  --SR
							trap_priv <= '1';
							trapmake <= '1';
						ELSE
							set(no_Flags) <= '1';
							IF decodeOPC='1' THEN
								IF opcode(6)='1' THEN
									set(to_SR) <= '1';
								END IF;
								set(to_CCR) <= '1';
								set(andiSR) <= set_exec(opcAND);	
								set(eoriSR) <= set_exec(opcEOR);	
								set(oriSR) <= set_exec(opcOR);
								setstate <= "01";
								next_micro_state <= nopnop;
							END IF;
						END IF;
					ELSE
						IF decodeOPC='1' THEN
							next_micro_state <= andi;
							set(ea_build) <= '1';
							set_direct_data <= '1';
							IF datatype="10" THEN
								set(longaktion) <= '1';
							END IF;
						END IF;	
						IF opcode(5 downto 4)/="00" THEN				
							set_exec(ea_data_OP1) <= '1';
						END IF;
						IF opcode(11 downto 9)/="110" THEN	--CMPI 
							IF opcode(5 downto 4)="00" THEN
								set_exec(Regwrena) <= '1';
							END IF;	
							write_back <= '1';
						END IF;
						IF opcode(10 downto 9)="10" THEN	--CMPI, SUBI
							set(addsub) <= '1';
						END IF;
					END IF;		
				END IF;		
			END IF;		
				
-- 0001, 0010, 0011 -----------------------------------------------------------------		
			WHEN "0001"|"0010"|"0011" =>				--move.b, move.l, move.w
				set_exec(opcMOVE) <= '1';
				ea_build_now <= '1';
				IF opcode(8 downto 6)="001" THEN	
					set(no_Flags) <= '1';
				END IF;
				IF opcode(5 downto 4)="00" THEN	--Dn, An
					IF opcode(8 downto 7)="00" THEN
						set_exec(Regwrena) <= '1';
					END IF;	
				END IF;
				CASE opcode(13 downto 12) IS
					WHEN "01" => datatype <= "00";		--Byte
					WHEN "10" => datatype <= "10";		--Long
					WHEN OTHERS => datatype <= "01";	--Word
				END CASE;
				source_lowbits <= '1';					-- Dn=>  An=>
				IF opcode(3)='1' THEN
					source_areg <= '1';
				END IF;
				
				IF nextpass='1' OR opcode(5 downto 4)="00" THEN	
					dest_hbits <= '1';
					IF opcode(8 downto 6)/="000" THEN
						dest_areg <= '1';
					END IF;
				END IF;
--				IF setstate="10" THEN
--					set(update_ld) <= '0';
--				END IF;
--
				IF micro_state=idle AND (nextpass='1' OR (opcode(5 downto 4)="00" AND decodeOPC='1')) THEN	
					CASE opcode(8 downto 6) IS		--destination
						WHEN "000"|"001" =>						--Dn,An
								set_exec(Regwrena) <= '1';
						WHEN "010"|"011"|"100" =>					--destination -(an)+
							IF opcode(6)='1' THEN	--(An)+
								set(postadd) <= '1';
								IF opcode(11 downto 9)="111" THEN
									set(use_SP) <= '1';
								END IF;
							END IF;	 	
							IF opcode(8)='1' THEN	-- -(An)
								set(presub) <= '1'; 					
								IF opcode(11 downto 9)="111" THEN
									set(use_SP) <= '1';
								END IF;
							END IF;	
							setstate <= "11";
							next_micro_state <= nop;
							IF nextpass='0' THEN
								set(write_reg) <= '1';
							END IF;	
						WHEN "101" =>				--(d16,An)
							next_micro_state <= st_dAn1;
--							getbrief <= '1';
						WHEN "110" =>				--(d8,An,Xn)
							next_micro_state <= st_AnXn1;
							getbrief <= '1';
						WHEN "111" =>
							CASE opcode(11 downto 9) IS
								WHEN "000" =>				--(xxxx).w
									next_micro_state <= st_nn;
								WHEN "001" =>				--(xxxx).l
									set(longaktion) <= '1';
									next_micro_state <= st_nn;
								WHEN OTHERS => NULL;
							END CASE;
						WHEN OTHERS => NULL;
					END CASE;
				END IF;	
---- 0100 ----------------------------------------------------------------------------		
			WHEN "0100" =>				--rts_group
				IF opcode(8)='1' THEN		--lea
					IF opcode(6)='1' THEN		--lea
						IF opcode(7)='1' THEN		
							source_lowbits <= '1';
--							IF opcode(5 downto 3)="000" AND opcode(10)='0' THEN		--ext
							IF opcode(5 downto 4)="00" THEN		--extb.l
								set_exec(opcEXT) <= '1';
								set_exec(opcMOVE) <= '1';
								set_exec(Regwrena) <= '1';	
--								IF opcode(6)='0' THEN
--									datatype <= "01";		--WORD
--								END IF;
							ELSE	
								source_areg <= '1';
								ea_only <= '1';
								set_exec(Regwrena) <= '1';
								set_exec(opcMOVE) <='1';
								set(no_Flags) <='1';
								IF opcode(5 downto 3)="010" THEN  	--lea (Am),An
									dest_areg <= '1';
									dest_hbits <= '1';
								ELSE
									ea_build_now <= '1';
								END IF;	
								IF set(get_ea_now)='1' THEN
									setstate <= "01";
									set_direct_data <= '1';
								END IF;
								IF setexecOPC='1' THEN
									dest_areg <= '1';
									dest_hbits <= '1';
								END IF;
							END IF;	
						ELSE
							trap_illegal <= '1';
							trapmake <= '1';
						END IF;
					ELSE								--chk
						IF opcode(7)='1' THEN
							datatype <= "01";	--Word
								set(trap_chk) <= '1';	
							IF (c_out(1)='0' OR OP1out(15)='1' OR OP2out(15)='1') AND exec(opcCHK)='1' THEN
								trapmake <= '1';
							END IF;
						ELSIF cpu(1)='1' THEN   --chk long for 68020
							datatype <= "10";	--Long
								set(trap_chk) <= '1';	
							IF (c_out(2)='1' OR OP1out(31)='1' OR OP2out(31)='1') AND exec(opcCHK)='1' THEN
								trapmake <= '1';
							END IF;
						ELSE
							trap_illegal <= '1';		-- chk long for 68020
							trapmake <= '1';
						END IF;
						IF opcode(7)='1' OR cpu(1)='1' THEN
							IF (nextpass='1' OR opcode(5 downto 4)="00") AND exec(opcCHK)='0' AND micro_state=idle THEN	
								set_exec(opcCHK) <= '1';
							END IF;
							ea_build_now <= '1';
							set(addsub) <= '1';
							IF setexecOPC='1' THEN
								dest_hbits <= '1';
								source_lowbits <='1';
							END IF;	
						END IF;
					END IF;
				ELSE
					CASE opcode(11 downto 9) IS
						WHEN "000"=>
							IF opcode(7 downto 6)="11" THEN					--move from SR
								IF SR_Read=0 OR (cpu(0)='0' AND SR_Read=2) OR SVmode='1'  THEN
--								IF SVmode='1'  THEN
									ea_build_now <= '1';
									set_exec(opcMOVESR) <= '1';
									datatype <= "01";
									write_back <='1';							-- im 68000 wird auch erst gelesen
									IF cpu(0)='1' AND state="10" THEN
										skipFetch <= '1';
									END IF;
									IF opcode(5 downto 4)="00" THEN
										set_exec(Regwrena) <= '1';
									END IF;
								ELSE
									trap_priv <= '1';
									trapmake <= '1';
								END IF;
							ELSE									--negx
								ea_build_now <= '1';
								set_exec(use_XZFlag) <= '1';
								write_back <='1';
								set_exec(opcADD) <= '1';
								set(addsub) <= '1';
								source_lowbits <= '1';
								IF opcode(5 downto 4)="00" THEN
									set_exec(Regwrena) <= '1';
								END IF;
								IF setexecOPC='1' THEN
									set(OP1out_zero) <= '1';
								END IF;
							END IF;
						WHEN "001"=>
							IF opcode(7 downto 6)="11" THEN					--move from CCR 68010
								IF SR_Read=1 OR (cpu(0)='1' AND SR_Read=2) THEN
									ea_build_now <= '1';
									set_exec(opcMOVESR) <= '1';
									datatype <= "00";
									write_back <='1';							-- im 68000 wird auch erst gelesen
									IF opcode(5 downto 4)="00" THEN
										set_exec(Regwrena) <= '1';
									END IF;
								ELSE
									trap_illegal <= '1';
									trapmake <= '1';
								END IF;
							ELSE											--clr
								ea_build_now <= '1';
								write_back <='1';
								set_exec(opcAND) <= '1';
							IF cpu(0)='1' AND state="10" THEN
								skipFetch <= '1';
							END IF;
								IF setexecOPC='1' THEN
									set(OP1out_zero) <= '1';
								END IF;
								IF opcode(5 downto 4)="00" THEN
									set_exec(Regwrena) <= '1';
								END IF;
							END IF;
						WHEN "010"=>
							ea_build_now <= '1';
							IF opcode(7 downto 6)="11" THEN					--move to CCR
								datatype <= "01";
								source_lowbits <= '1';
								IF (decodeOPC='1' AND opcode(5 downto 4)="00") OR state="10" OR direct_data='1' THEN
									set(to_CCR) <= '1';
								END IF;
							ELSE											--neg
								write_back <='1';
								set_exec(opcADD) <= '1';
								set(addsub) <= '1';
								source_lowbits <= '1';
								IF opcode(5 downto 4)="00" THEN					
									set_exec(Regwrena) <= '1';
								END IF;
								IF setexecOPC='1' THEN
									set(OP1out_zero) <= '1';
								END IF;
							END IF;
						WHEN "011"=>										--not, move toSR
							IF opcode(7 downto 6)="11" THEN					--move to SR
								IF SVmode='1' THEN
									ea_build_now <= '1';
									datatype <= "01";
									source_lowbits <= '1';
									IF (decodeOPC='1' AND opcode(5 downto 4)="00") OR state="10" OR direct_data='1' THEN
										set(to_SR) <= '1';
										set(to_CCR) <= '1';
									END IF;
									IF exec(to_SR)='1' OR (decodeOPC='1' AND opcode(5 downto 4)="00") OR state="10" OR direct_data='1' THEN
										setstate <="01";
									END IF;
								ELSE
									trap_priv <= '1';
									trapmake <= '1';
								END IF;
							ELSE											--not
								ea_build_now <= '1';
								write_back <='1';
								set_exec(opcEOR) <= '1';
								set_exec(ea_data_OP1) <= '1';
								IF opcode(5 downto 3)="000" THEN					
									set_exec(Regwrena) <= '1';
								END IF;
								IF setexecOPC='1' THEN
									set(OP2out_one) <= '1';
								END IF;
							END IF;
						WHEN "100"|"110"=>
							IF opcode(7)='1' THEN			--movem, ext
								IF opcode(5 downto 3)="000" AND opcode(10)='0' THEN		--ext
									source_lowbits <= '1';
									set_exec(opcEXT) <= '1';
									set_exec(opcMOVE) <= '1';
									set_exec(Regwrena) <= '1';	
									IF opcode(6)='0' THEN
										datatype <= "01";		--WORD
									END IF;
								ELSE													--movem
--								IF opcode(11 downto 7)="10001" OR opcode(11 downto 7)="11001" THEN	--MOVEM
									ea_only <= '1';
									set(no_Flags) <= '1';
									IF opcode(6)='0' THEN
										datatype <= "01";		--Word transfer
									END IF;
									IF (opcode(5 downto 3)="100" OR opcode(5 downto 3)="011") AND state="01" THEN	-- -(An), (An)+
										set_exec(save_memaddr) <= '1';
										set_exec(Regwrena) <= '1';
									END IF;
									IF opcode(5 downto 3)="100" THEN	-- -(An)
										movem_presub <= '1';
										set(subidx) <= '1';
									END IF;
									IF state="10" THEN
										set(Regwrena) <= '1';	
										set(opcMOVE) <= '1';
									END IF;	
									IF decodeOPC='1' THEN
										set(get_2ndOPC) <='1';
										IF opcode(5 downto 3)="010" OR opcode(5 downto 3)="011" OR opcode(5 downto 3)="100" THEN
											next_micro_state <= movem1;
										ELSE	
											next_micro_state <= nop;
											set(ea_build) <= '1';
										END IF;	
									END IF;
									IF set(get_ea_now)='1' THEN
										IF movem_run='1' THEN
											set(movem_action) <= '1';
											IF opcode(10)='0' THEN
												setstate <="11";
												set(write_reg) <= '1';
											ELSE
												setstate <="10";
											END IF;
											next_micro_state <= movem2;
											set(mem_addsub) <= '1';
										ELSE	
											setstate <="01";
										END IF;
									END IF;
								END IF;	
							ELSE
								IF opcode(10)='1' THEN						--MUL.L, DIV.L 68020
--									IF cpu(1)='1' THEN
									IF (opcode(6)='1' AND (DIV_Mode=1 OR (cpu(1)='1' AND DIV_Mode=2))) OR
									   (opcode(6)='0' AND (MUL_Mode=1 OR (cpu(1)='1' AND MUL_Mode=2))) THEN
										IF decodeOPC='1' THEN
											next_micro_state <= nop;
											set(get_2ndOPC) <= '1';
											set(ea_build) <= '1';
										END IF;	
										IF (micro_state=idle AND nextpass='1') OR (opcode(5 downto 4)="00" AND exec(ea_build)='1')THEN
											setstate <="01";
											dest_2ndHbits <= '1';
											source_2ndLbits <= '1';
											IF opcode(6)='1' THEN
												next_micro_state <= div1;
											ELSE	
												next_micro_state <= mul1;
												set(ld_rot_cnt) <= '1'; 
											END IF;
										END IF;
										IF z_error='0' AND set_V_Flag='0' AND set(opcDIVU)='1' THEN
											set(Regwrena) <= '1';
										END IF;
										source_lowbits <='1';
										IF nextpass='1' OR (opcode(5 downto 4)="00" AND decodeOPC='1') THEN	
											dest_hbits <= '1';
										END IF;
										datatype <= "10";
									ELSE
										trap_illegal <= '1';
										trapmake <= '1';
									END IF;
					
								ELSE							--pea, swap
									IF opcode(6)='1' THEN
										datatype <= "10";
										IF opcode(5 downto 3)="000" THEN 		--swap
											set_exec(opcSWAP) <= '1';
											set_exec(Regwrena) <= '1';	
										ELSIF opcode(5 downto 3)="001" THEN 		--bkpt
										
										ELSE									--pea
											ea_only <= '1';
											ea_build_now <= '1';
											IF nextpass='1' AND micro_state=idle THEN
												set(presub) <= '1';
												setstackaddr <='1';
												setstate <="11";
												next_micro_state <= nop;
											END IF;
											IF set(get_ea_now)='1' THEN
												setstate <="01";
											END IF;
										END IF;	
									ELSE	
										IF opcode(5 downto 3)="001" THEN --link.l
											datatype <= "10";
											set_exec(opcADD) <= '1';						--for displacement
											set_exec(Regwrena) <= '1';
											set(no_Flags) <= '1';
											IF decodeOPC='1' THEN
												set(linksp) <= '1';
												set(longaktion) <= '1';
												next_micro_state <= link1;
												set(presub) <= '1';
												setstackaddr <='1';
												set(mem_addsub) <= '1';
												source_lowbits <= '1';
												source_areg <= '1';
												set(store_ea_data) <= '1';
											END IF;
										ELSE						--nbcd	
											ea_build_now <= '1';
											set_exec(use_XZFlag) <= '1';
											write_back <='1';
											set_exec(opcADD) <= '1';
											set_exec(opcSBCD) <= '1';
											source_lowbits <= '1';
											IF opcode(5 downto 4)="00" THEN					
												set_exec(Regwrena) <= '1';
											END IF;
											IF setexecOPC='1' THEN
												set(OP1out_zero) <= '1';
											END IF;
										END IF;	
									END IF;
								END IF;
							END IF;
--							
						WHEN "101"=>						--tst, tas  4aFC - illegal
							IF opcode(7 downto 2)="111111" THEN   --illegal
								trap_illegal <= '1';
								trapmake <= '1';
							ELSE
								ea_build_now <= '1';
								IF setexecOPC='1' THEN
									source_lowbits <= '1';
									IF opcode(3)='1' THEN			--MC68020...
										source_areg <= '1';
									END IF;
								END IF;
								set_exec(opcMOVE) <= '1';
								IF opcode(7 downto 6)="11" THEN		--tas
									set_exec_tas <= '1';
									write_back <= '1';
									datatype <= "00";				--Byte
									IF opcode(5 downto 4)="00" THEN					
										set_exec(Regwrena) <= '1';
									END IF;
								END IF;
							END IF;
----						WHEN "110"=>
						WHEN "111"=>					--4EXX
--
--											ea_only <= '1';
--											ea_build_now <= '1';
--											IF nextpass='1' AND micro_state=idle THEN
--												set(presub) <= '1';
--												setstackaddr <='1';
--												set(mem_addsub) <= '1';
--												setstate <="11";
--												next_micro_state <= nop;
--											END IF;
--											IF set(get_ea_now)='1' THEN
--												setstate <="01";
--											END IF;
--								
								
								
								
							IF opcode(7)='1' THEN		--jsr, jmp
								datatype <= "10";
								ea_only <= '1';
								ea_build_now <= '1';
								IF exec(ea_to_pc)='1' THEN
									next_micro_state <= nop;
								END IF;
								IF nextpass='1' AND micro_state=idle AND opcode(6)='0' THEN
									set(presub) <= '1';
									setstackaddr <='1';
									setstate <="11";
									next_micro_state <= nopnop;
								END IF;
-- achtung buggefahr								
								IF micro_state=ld_AnXn1 AND brief(8)='0'THEN			--JMP/JSR n(Ax,Dn)
									skipFetch <= '1';
								END IF;
								IF state="00" THEN
									writePC <= '1';
								END IF;
								set(hold_dwr) <= '1';
								IF set(get_ea_now)='1' THEN					--jsr
									IF exec(longaktion)='0' OR long_done='1' THEN					
										skipFetch <= '1';
									END IF;
									setstate <="01";
									set(ea_to_pc) <= '1';
								END IF;
							ELSE						--
								CASE opcode(6 downto 0) IS
									WHEN "1000000"|"1000001"|"1000010"|"1000011"|"1000100"|"1000101"|"1000110"|"1000111"|		--trap
									     "1001000"|"1001001"|"1001010"|"1001011"|"1001100"|"1001101"|"1001110"|"1001111" =>		--trap
											trap_trap <='1';
											trapmake <= '1';
									WHEN "1010000"|"1010001"|"1010010"|"1010011"|"1010100"|"1010101"|"1010110"|"1010111"=> 		--link
										datatype <= "10";
										set_exec(opcADD) <= '1';						--for displacement
										set_exec(Regwrena) <= '1';
										set(no_Flags) <= '1';
										IF decodeOPC='1' THEN
											next_micro_state <= link1;
											set(presub) <= '1';
											setstackaddr <='1';
											set(mem_addsub) <= '1';
											source_lowbits <= '1';
											source_areg <= '1';
											set(store_ea_data) <= '1';
										END IF;
									
									WHEN "1011000"|"1011001"|"1011010"|"1011011"|"1011100"|"1011101"|"1011110"|"1011111" =>		--unlink
										datatype <= "10";
										set_exec(Regwrena) <= '1';
										set_exec(opcMOVE) <= '1';						
										set(no_Flags) <= '1';
										IF decodeOPC='1' THEN
											setstate <= "01";
											next_micro_state <= unlink1;
											set(opcMOVE) <= '1';
											set(Regwrena) <= '1';
											setstackaddr <='1';
											source_lowbits <= '1';
											source_areg <= '1';
										END IF;
									
									WHEN "1100000"|"1100001"|"1100010"|"1100011"|"1100100"|"1100101"|"1100110"|"1100111" =>		--move An,USP
										IF SVmode='1' THEN
--											set(no_Flags) <= '1';
											set(to_USP) <= '1';
											source_lowbits <= '1';
											source_areg <= '1';
											datatype <= "10";
										ELSE
											trap_priv <= '1';
											trapmake <= '1';
										END IF;
									WHEN "1101000"|"1101001"|"1101010"|"1101011"|"1101100"|"1101101"|"1101110"|"1101111" =>		--move USP,An
										IF SVmode='1' THEN
--											set(no_Flags) <= '1';
											set(from_USP) <= '1';
											datatype <= "10";
											set_exec(Regwrena) <= '1';
										ELSE
											trap_priv <= '1';
											trapmake <= '1';
										END IF;
									
									WHEN "1110000" =>					--reset
										IF SVmode='0' THEN
											trap_priv <= '1';
											trapmake <= '1';
										ELSE
											set(opcRESET) <= '1';
											IF decodeOPC='1' THEN
												set(ld_rot_cnt) <= '1'; 
												set_rot_cnt <= "000000";
											END IF;
										END IF;
										
									WHEN "1110001" =>					--nop
									
									WHEN "1110010" =>					--stop
										IF SVmode='0' THEN
											trap_priv <= '1';
											trapmake <= '1';
										ELSE
											IF decodeOPC='1' THEN
												setnextpass <= '1';
												set_stop <= '1';	
											END IF;
											IF stop='1' THEN
												skipFetch <= '1';
											END IF;		
											
										END IF;
									
									WHEN "1110011"|"1110111" =>  									--rte/rtr
										IF SVmode='1' OR opcode(2)='1' THEN
											IF decodeOPC='1' THEN
												setstate <= "10";
												set(postadd) <= '1';
												setstackaddr <= '1';
												IF opcode(2)='1' THEN
													set(directCCR) <= '1';
												ELSE	
													set(directSR) <= '1';	
												END IF;
												next_micro_state <= rte1;
											END IF;
										ELSE
											trap_priv <= '1';
											trapmake <= '1';
										END IF;
										
									WHEN "1110101" =>  									--rts
										datatype <= "10";
										IF decodeOPC='1' THEN
											setstate <= "10";
											set(postadd) <= '1';
											setstackaddr <= '1';
											set(direct_delta) <= '1';	
											set(directPC) <= '1';
											next_micro_state <= nopnop;
										END IF;
										
									WHEN "1110110" =>  									--trapv
										IF decodeOPC='1' THEN
											setstate <= "01";
										END IF;	
										IF Flags(1)='1' AND state="01" THEN
											trap_trapv <= '1';
											trapmake <= '1';
										END IF;
										
									WHEN "1111010"|"1111011" =>  									--movec
										IF VBR_Stackframe=0 OR (cpu(0)='0' AND VBR_Stackframe=2) THEN
											trap_illegal <= '1';
											trapmake <= '1';
										ELSIF SVmode='0' THEN
											trap_priv <= '1';
											trapmake <= '1';
										ELSE
											datatype <= "10";	--Long
											IF last_data_read(11 downto 0)=X"800" THEN
												set(from_USP) <= '1';
												IF opcode(0)='1' THEN
													set(to_USP) <= '1';
												END IF;
											END IF;
											IF opcode(0)='0' THEN
												set_exec(movec_rd) <= '1';
											ELSE		
												set_exec(movec_wr) <= '1';
											END IF;
											IF decodeOPC='1' THEN
												next_micro_state <= movec1;
												getbrief <='1';
											END IF;
										END IF;
									
									WHEN OTHERS =>	
										trap_illegal <= '1';
										trapmake <= '1';
								END CASE;	
							END IF;
						WHEN OTHERS => NULL;
					END CASE;
				END IF;	
--					
---- 0101 ----------------------------------------------------------------------------		
			WHEN "0101" => 								--subq, addq	
				
					IF opcode(7 downto 6)="11" THEN --dbcc
						IF opcode(5 downto 3)="001" THEN --dbcc
							IF decodeOPC='1' THEN
								next_micro_state <= dbcc1;
								set(OP2out_one) <= '1';
								data_is_source <= '1';
							END IF;
						ELSE				--Scc
							datatype <= "00";			--Byte
							ea_build_now <= '1';
							write_back <= '1';
							set_exec(opcScc) <= '1';
							IF cpu(0)='1' AND state="10" THEN
								skipFetch <= '1';
							END IF;
							IF opcode(5 downto 4)="00" THEN					
								set_exec(Regwrena) <= '1';
							END IF;
						END IF;
					ELSE					--addq, subq
						ea_build_now <= '1';
						IF opcode(5 downto 3)="001" THEN	
							set(no_Flags) <= '1';
						END IF;
						IF opcode(8)='1' THEN
							set(addsub) <= '1';
						END IF;
						write_back <= '1';
						set_exec(opcADDQ) <= '1';
						set_exec(opcADD) <= '1';
						set_exec(ea_data_OP1) <= '1';
						IF opcode(5 downto 4)="00" THEN					
							set_exec(Regwrena) <= '1';
						END IF;
					END IF;	
--				
---- 0110 ----------------------------------------------------------------------------		
			WHEN "0110" =>				--bra,bsr,bcc
				datatype <= "10";
				
				IF micro_state=idle THEN
					IF opcode(11 downto 8)="0001" THEN		--bsr
						set(presub) <= '1';
						setstackaddr <='1';
						IF opcode(7 downto 0)="11111111" THEN
							next_micro_state <= bsr2;
							set(longaktion) <= '1';
						ELSIF opcode(7 downto 0)="00000000" THEN
							next_micro_state <= bsr2;
						ELSE	
							next_micro_state <= bsr1;
							setstate <= "11";
							writePC <= '1';
						END IF;
					ELSE									--bra
						IF opcode(7 downto 0)="11111111" THEN
							next_micro_state <= bra1;
							set(longaktion) <= '1';
						ELSIF opcode(7 downto 0)="00000000" THEN
							next_micro_state <= bra1;
						ELSE
							setstate <= "01";
							next_micro_state <= bra1;
						END IF;
					END IF;
				END IF;	
				
-- 0111 ----------------------------------------------------------------------------		
			WHEN "0111" =>				--moveq
--				IF opcode(8)='0' THEN	-- Cloanto's Amiga Forver ROMs have mangled movq instructions with a 1 here...
					IF trap_interrupt='0' AND trap_trace='0' THEN
						datatype <= "10";		--Long
						set_exec(Regwrena) <= '1';
						set_exec(opcMOVEQ) <= '1';
						set_exec(opcMOVE) <= '1';
						dest_hbits <= '1';
					END IF;	
--				ELSE
--					trap_illegal <= '1';
--					trapmake <= '1';
--				END IF;
				
---- 1000 ----------------------------------------------------------------------------		
			WHEN "1000" => 								--or	
				IF opcode(7 downto 6)="11" THEN	--divu, divs
					IF DIV_Mode/=3 THEN	
						IF opcode(5 downto 4)="00" THEN	--Dn, An
							regdirectsource <= '1';
						END IF;
						IF (micro_state=idle AND nextpass='1') OR (opcode(5 downto 4)="00" AND decodeOPC='1') THEN	
							setstate <="01";
							next_micro_state <= div1;
						END IF;
						ea_build_now <= '1';
						IF z_error='0' AND set_V_Flag='0' THEN
							set_exec(Regwrena) <= '1';
						END IF;
							source_lowbits <='1';
						IF nextpass='1' OR (opcode(5 downto 4)="00" AND decodeOPC='1') THEN	
							dest_hbits <= '1';
						END IF;
						datatype <= "01";
					ELSE
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
			
				ELSIF opcode(8)='1' AND opcode(5 downto 4)="00" THEN	--sbcd, pack , unpack
					IF opcode(7 downto 6)="00" THEN	--sbcd
						build_bcd <= '1';
						set_exec(opcADD) <= '1';
						set_exec(opcSBCD) <= '1';
					ELSE									--pack, unpack
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
				ELSE									--or
					set_exec(opcOR) <= '1';
					build_logical <= '1';
				END IF;
				
---- 1001, 1101 -----------------------------------------------------------------------		
			WHEN "1001"|"1101" => 						--sub, add	
				set_exec(opcADD) <= '1';
				ea_build_now <= '1';
				IF opcode(14)='0' THEN
					set(addsub) <= '1';
				END IF;
				IF opcode(7 downto 6)="11" THEN	--	--adda, suba
					IF opcode(8)='0' THEN	--adda.w, suba.w
						datatype <= "01";	--Word
					END IF;
					set_exec(Regwrena) <= '1';
					source_lowbits <='1';
					IF opcode(3)='1' THEN
						source_areg <= '1';
					END IF;
					set(no_Flags) <= '1';
					IF setexecOPC='1' THEN
						dest_areg <='1';
						dest_hbits <= '1';
					END IF;
				ELSE							
					IF opcode(8)='1' AND opcode(5 downto 4)="00" THEN		--addx, subx
						build_bcd <= '1';
					ELSE							--sub, add
						build_logical <= '1';
					END IF;
				END IF;	

--				
---- 1010 ----------------------------------------------------------------------------		
			WHEN "1010" => 							--Trap 1010
				trap_1010 <= '1';
				trapmake <= '1';
---- 1011 ----------------------------------------------------------------------------		
			WHEN "1011" => 							--eor, cmp
				ea_build_now <= '1';
				IF opcode(7 downto 6)="11" THEN	--CMPA
					IF opcode(8)='0' THEN	--cmpa.w
						datatype <= "01";	--Word
						set_exec(opcCPMAW) <= '1';
					END IF;
					set_exec(opcCMP) <= '1';
					IF setexecOPC='1' THEN
						source_lowbits <='1';
						IF opcode(3)='1' THEN
							source_areg <= '1';
						END IF;
						dest_areg <='1';
						dest_hbits <= '1';
					END IF;	
					set(addsub) <= '1';
				ELSE							
					IF opcode(8)='1' THEN
						IF opcode(5 downto 3)="001" THEN		--cmpm
							set_exec(opcCMP) <= '1';
							IF decodeOPC='1' THEN
								setstate <= "10";
								set(update_ld) <= '1';
								set(postadd) <= '1';
								next_micro_state <= cmpm;
							END IF;
							set_exec(ea_data_OP1) <= '1';
							set(addsub) <= '1';
						ELSE						--EOR
							build_logical <= '1';
							set_exec(opcEOR) <= '1';
						END IF;
					ELSE							--CMP
						build_logical <= '1';
						set_exec(opcCMP) <= '1';
						set(addsub) <= '1';
					END IF;
				END IF;	
--				
---- 1100 ----------------------------------------------------------------------------		
			WHEN "1100" => 								--and, exg
				IF opcode(7 downto 6)="11" THEN	--mulu, muls
					IF MUL_Mode/=3 THEN	
						IF opcode(5 downto 4)="00" THEN	--Dn, An
							regdirectsource <= '1';
						END IF;
						IF (micro_state=idle AND nextpass='1') OR (opcode(5 downto 4)="00" AND decodeOPC='1') THEN	
							setstate <="01";
							set(ld_rot_cnt) <= '1'; 
							next_micro_state <= mul1;
						END IF;
						ea_build_now <= '1';
						set_exec(Regwrena) <= '1';
						source_lowbits <='1';
						IF (nextpass='1') OR (opcode(5 downto 4)="00" AND decodeOPC='1') THEN
							dest_hbits <= '1';
						END IF;
						datatype <= "01";
					ELSE
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
			
				ELSIF opcode(8)='1' AND opcode(5 downto 4)="00" THEN	--exg, abcd
					IF opcode(7 downto 6)="00" THEN	--abcd
						build_bcd <= '1';
						set_exec(opcADD) <= '1';
						set_exec(opcABCD) <= '1';
					ELSE									--exg
						datatype <= "10";
						set(Regwrena) <= '1';
						set(exg) <= '1';
						IF opcode(6)='1' AND opcode(3)='1' THEN
							dest_areg <= '1';
							source_areg <= '1';
						END IF;	
						IF decodeOPC='1' THEN
							setstate <= "01";
						ELSE
							dest_hbits <= '1';
						END IF;
					END IF;
				ELSE									--and
					set_exec(opcAND) <= '1';
					build_logical <= '1';
				END IF;	
--				
---- 1110 ----------------------------------------------------------------------------		
			WHEN "1110" => 								--rotation / bitfield
				IF opcode(7 downto 6)="11" THEN
					IF opcode(11)='0' THEN
						set_exec(opcROT) <= '1';
						ea_build_now <= '1';
						datatype <= "01";
						set_rot_bits <= opcode(10 downto 9);
						set_exec(ea_data_OP1) <= '1';
						write_back <= '1';
					ELSE		--bitfield
						IF BitField=0 OR (cpu(1)='0' AND BitField=2) THEN
							trap_illegal <= '1';
							trapmake <= '1';
						ELSE
							IF decodeOPC='1' THEN
								next_micro_state <= nop;
								set(get_2ndOPC) <= '1';
								set(ea_build) <= '1';
							END IF;	
							set_exec(opcBF) <= '1';
							IF opcode(10)='1' OR opcode(8)='0' THEN
								set_exec(opcBFwb) <= '1';
--							END IF;	
--							IF opcode(10 downto 8)="111" THEN
								set_exec(ea_data_OP1) <= '1';
							END IF;	
							IF opcode(10 downto 8)="010" OR opcode(10 downto 8)="100" OR opcode(10 downto 8)="110" OR opcode(10 downto 8)="111" THEN
								write_back <= '1';
							END IF;	
							ea_only <= '1';
							IF opcode(10 downto 8)="001" OR opcode(10 downto 8)="011" OR opcode(10 downto 8)="101" THEN
								set_exec(Regwrena) <= '1';
							END IF;	
							IF opcode(4 downto 3)="00" THEN
								set_exec(Regwrena) <= '1';
								IF exec(ea_build)='1' THEN
									dest_2ndHbits <= '1';
									source_2ndLbits <= '1';
									set(get_bfoffset) <='1';
									setstate <= "01";
								END IF;
							END IF;
							IF set(get_ea_now)='1' THEN
								setstate <= "01";
							END IF;	
							IF exec(get_ea_now)='1' THEN
								dest_2ndHbits <= '1';
								source_2ndLbits <= '1';
								set(get_bfoffset) <='1';
								setstate <= "01";
								set(mem_addsub) <='1';
								next_micro_state <= bf1;
							END IF;
							
-- BFINS  D1,D0		s2ndHbits <<D1 -> D0 
-- BFEXT  D0,D1		sLbits    >>D0 -> D1 d2ndHbits
-- BFINS  D1,(A0)	s2ndHbits <<D1 -> (A0)
-- BFEXT  (A0),D1	        >>(A0) -> D1 d2ndHbits
							IF setexecOPC='1' THEN  
								IF opcode(10 downto 8)="111" THEN	--BFINS
									source_2ndHbits <= '1';
								ELSE	
									source_lowbits <= '1';
									dest_2ndHbits <= '1';
								END IF;	
							END IF;
						END IF;
					END IF;
				ELSE	
					set_exec(opcROT) <= '1';
					set_rot_bits <= opcode(4 downto 3);
					data_is_source <= '1';
					set_exec(Regwrena) <= '1';
					IF decodeOPC='1' THEN
						IF opcode(5)='1' THEN
							next_micro_state <= rota1;
							set(ld_rot_cnt) <= '1';
							setstate <= "01";
						ELSE
							set_rot_cnt(2 downto 0) <= opcode(11 downto 9);
							IF opcode(11 downto 9)="000" THEN
								set_rot_cnt(3) <='1';
							ELSE
								set_rot_cnt(3) <='0';
							END IF;
						END IF;
					END IF;	
				END IF;	
--							
----      ----------------------------------------------------------------------------		
			WHEN OTHERS =>	
				trap_1111 <= '1';
				trapmake <= '1';

		END CASE;		

-- use for AND, OR, EOR, CMP
		IF build_logical='1' THEN
			ea_build_now <= '1';
			IF set_exec(opcCMP)='0' AND (opcode(8)='0' OR opcode(5 downto 4)="00" ) THEN					
				set_exec(Regwrena) <= '1';
			END IF;
			IF opcode(8)='1' THEN
				write_back <= '1';
				set_exec(ea_data_OP1) <= '1';
			ELSE
				source_lowbits <='1';
				IF opcode(3)='1' THEN		--use for cmp
					source_areg <= '1';
				END IF;
				IF setexecOPC='1' THEN
					dest_hbits <= '1';
				END IF;
			END IF;
		END IF;
		
-- use for ABCD, SBCD
		IF build_bcd='1' THEN
			set_exec(use_XZFlag) <= '1';
			set_exec(ea_data_OP1) <= '1';
			write_back <= '1';
			source_lowbits <='1';
			IF opcode(3)='1' THEN
				IF decodeOPC='1' THEN
					setstate <= "10";
					set(update_ld) <= '1';
					set(presub) <= '1';
					next_micro_state <= op_AxAy;
					dest_areg <= '1';				--???
				END IF;
			ELSE
				dest_hbits <= '1';
				set_exec(Regwrena) <= '1';
			END IF;
		END IF;
		

------------------------------------------------------------------------------		
------------------------------------------------------------------------------		
		IF set_Z_error='1'  THEN		-- divu by zero
			trapmake <= '1';			--wichtig for USP
			IF trapd='0' THEN
				writePC <= '1';
			END IF;			
		END IF;	
		
-----------------------------------------------------------------------------
-- execute microcode
-----------------------------------------------------------------------------
		IF rising_edge(clk) THEN
	        IF Reset='1' THEN
				micro_state <= ld_nn;
			ELSIF clkena_lw='1' THEN
				trapd <= trapmake;
				micro_state <= next_micro_state;
			END IF;
		END IF;

			CASE micro_state IS
				WHEN ld_nn =>		-- (nnnn).w/l=>
					set(get_ea_now) <='1';
					setnextpass <= '1';
					set(addrlong) <= '1';
					
				WHEN st_nn =>		-- =>(nnnn).w/l
					setstate <= "11";
					set(addrlong) <= '1';
					next_micro_state <= nop;
					
				WHEN ld_dAn1 =>		-- d(An)=>, --d(PC)=>
					set(get_ea_now) <='1';
					setdisp <= '1';		--word
					setnextpass <= '1';
					
				WHEN ld_AnXn1 =>		-- d(An,Xn)=>, --d(PC,Xn)=>
					IF brief(8)='0' OR extAddr_Mode=0 OR (cpu(1)='0' AND extAddr_Mode=2) THEN
						setdisp <= '1';		--byte	
						setdispbyte <= '1';
						setstate <= "01";
						set(briefext) <= '1';
						next_micro_state <= ld_AnXn2;
					ELSE	
						IF brief(7)='1'THEN		--suppress Base
							set_suppress_base <= '1';
						ELSIF exec(dispouter)='1' THEN
							set(dispouter) <= '1';
						END IF;
						IF brief(5)='0' THEN --NULL Base Displacement
							setstate <= "01";
						ELSE  --WORD Base Displacement
							IF brief(4)='1' THEN
								set(longaktion) <= '1'; --LONG Base Displacement
							END IF;
						END IF;
						next_micro_state <= ld_229_1;
					END IF;
					
				WHEN ld_AnXn2 =>
					set(get_ea_now) <='1';
					setdisp <= '1';		--brief
					setnextpass <= '1';
					
-------------------------------------------------------------------------------------					
					
				WHEN ld_229_1 =>		-- (bd,An,Xn)=>, --(bd,PC,Xn)=>
					IF brief(5)='1' THEN    --Base Displacement
						setdisp <= '1';		--add last_data_read
					END IF;
					IF brief(6)='0' AND brief(2)='0' THEN --Preindex or Index
						set(briefext) <= '1';
						setstate <= "01";
						IF brief(1 downto 0)="00" THEN
							next_micro_state <= ld_AnXn2;
						ELSE	
							next_micro_state <= ld_229_2;
						END IF;	
					ELSE
						IF brief(1 downto 0)="00" THEN
							set(get_ea_now) <='1';
							setnextpass <= '1';
						ELSE
							setstate <= "10";
							set(longaktion) <= '1';
							next_micro_state <= ld_229_3;
						END IF;
					END IF;
					
				WHEN ld_229_2 =>		-- (bd,An,Xn)=>, --(bd,PC,Xn)=>
					setdisp <= '1';		-- add Index
					setstate <= "10";
					set(longaktion) <= '1';
					next_micro_state <= ld_229_3;
				
				WHEN ld_229_3 =>		-- (bd,An,Xn)=>, --(bd,PC,Xn)=>
					set_suppress_base <= '1';
					set(dispouter) <= '1'; 	
					IF brief(1)='0' THEN --NULL Outer Displacement
						setstate <= "01";
					ELSE  --WORD Outer Displacement
						IF brief(0)='1' THEN
							set(longaktion) <= '1'; --LONG Outer Displacement
						END IF;
					END IF;
					next_micro_state <= ld_229_4;
				
				WHEN ld_229_4 =>		-- (bd,An,Xn)=>, --(bd,PC,Xn)=>
					IF brief(1)='1' THEN  -- Outer Displacement
						setdisp <= '1';	  --add last_data_read
					END IF;
					IF brief(6)='0' AND brief(2)='1' THEN --Postindex
						set(briefext) <= '1';
						setstate <= "01";
						next_micro_state <= ld_AnXn2;
					ELSE
						set(get_ea_now) <='1';
						setnextpass <= '1';
					END IF;
					
----------------------------------------------------------------------------------------				
				WHEN st_dAn1 =>		-- =>d(An)
					setstate <= "11";
					setdisp <= '1';		--word
					next_micro_state <= nop;
					
				WHEN st_AnXn1 =>		-- =>d(An,Xn)
					IF brief(8)='0' OR extAddr_Mode=0 OR (cpu(1)='0' AND extAddr_Mode=2) THEN
						setdisp <= '1';		--byte	
						setdispbyte <= '1';
						setstate <= "01";
						set(briefext) <= '1';
						next_micro_state <= st_AnXn2;
					ELSE	
						IF brief(7)='1'THEN		--suppress Base
							set_suppress_base <= '1';
--						ELSIF exec(dispouter)='1' THEN
--							set(dispouter) <= '1';
						END IF;
						IF brief(5)='0' THEN --NULL Base Displacement
							setstate <= "01";
						ELSE  --WORD Base Displacement
							IF brief(4)='1' THEN
								set(longaktion) <= '1'; --LONG Base Displacement
							END IF;
						END IF;
						next_micro_state <= st_229_1;
					END IF;
					
				WHEN st_AnXn2 =>
					setstate <= "11";
					setdisp <= '1';		--brief	
					next_micro_state <= nop;
					
-------------------------------------------------------------------------------------					
					
				WHEN st_229_1 =>		-- (bd,An,Xn)=>, --(bd,PC,Xn)=>
					IF brief(5)='1' THEN    --Base Displacement
						setdisp <= '1';		--add last_data_read
					END IF;
					IF brief(6)='0' AND brief(2)='0' THEN --Preindex or Index
						set(briefext) <= '1';
						setstate <= "01";
						IF brief(1 downto 0)="00" THEN
							next_micro_state <= st_AnXn2;
						ELSE	
							next_micro_state <= st_229_2;
						END IF;	
					ELSE
						IF brief(1 downto 0)="00" THEN
							setstate <= "11";
							next_micro_state <= nop;
						ELSE
							set(hold_dwr) <= '1';
							setstate <= "10";
							set(longaktion) <= '1';
							next_micro_state <= st_229_3;
						END IF;
					END IF;
					
				WHEN st_229_2 =>		-- (bd,An,Xn)=>, --(bd,PC,Xn)=>
					setdisp <= '1';		-- add Index
					set(hold_dwr) <= '1';
					setstate <= "10";
					set(longaktion) <= '1';
					next_micro_state <= st_229_3;
				
				WHEN st_229_3 =>		-- (bd,An,Xn)=>, --(bd,PC,Xn)=>
					set(hold_dwr) <= '1';
					set_suppress_base <= '1';
					set(dispouter) <= '1'; 	
					IF brief(1)='0' THEN --NULL Outer Displacement
						setstate <= "01";
					ELSE  --WORD Outer Displacement
						IF brief(0)='1' THEN
							set(longaktion) <= '1'; --LONG Outer Displacement
						END IF;
					END IF;
					next_micro_state <= st_229_4;
				
				WHEN st_229_4 =>		-- (bd,An,Xn)=>, --(bd,PC,Xn)=>
					set(hold_dwr) <= '1';
					IF brief(1)='1' THEN  -- Outer Displacement
						setdisp <= '1';	  --add last_data_read
					END IF;
					IF brief(6)='0' AND brief(2)='1' THEN --Postindex
						set(briefext) <= '1';
						setstate <= "01";
						next_micro_state <= st_AnXn2;
					ELSE
						setstate <= "11";
						next_micro_state <= nop;
					END IF;
					
----------------------------------------------------------------------------------------				
				WHEN bra1 =>		--bra
					IF exe_condition='1' THEN
						TG68_PC_brw <= '1';	--pc+0000
						next_micro_state <= nop;
						skipFetch <= '1';	
					END IF;
					
				WHEN bsr1 =>		--bsr short
					TG68_PC_brw <= '1';	
					next_micro_state <= nop;
					
				WHEN bsr2 =>		--bsr
					IF long_start='0' THEN	
						TG68_PC_brw <= '1';	
					END IF;
					skipFetch <= '1';	
					set(longaktion) <= '1';
					writePC <= '1';
					setstate <= "11";
					next_micro_state <= nopnop;
					setstackaddr <='1';
				WHEN nopnop =>		--bsr
					next_micro_state <= nop;

				WHEN dbcc1 =>		--dbcc
					IF exe_condition='0' THEN
						Regwrena_now <= '1';
						IF c_out(1)='1' THEN
							skipFetch <= '1';				
							next_micro_state <= nop;
							TG68_PC_brw <= '1';	
						END IF;	
					END IF;
				
				WHEN movem1 =>		--movem
					IF last_data_read(15 downto 0)/=X"0000" THEN
						setstate <="01";
						IF opcode(5 downto 3)="100" THEN
							set(mem_addsub) <= '1';
						END IF;
						next_micro_state <= movem2;
					END IF;
				WHEN movem2 =>		--movem
					IF movem_run='0' THEN
						setstate <="01";
					ELSE	
						set(movem_action) <= '1';
						set(mem_addsub) <= '1';
						next_micro_state <= movem2;
						IF opcode(10)='0' THEN
							setstate <="11";
							set(write_reg) <= '1';
						ELSE
							setstate <="10";
						END IF;
					END IF;	

				WHEN andi =>		--andi
					IF opcode(5 downto 4)/="00" THEN
						setnextpass <= '1';
					END IF;

				WHEN op_AxAy =>		-- op -(Ax),-(Ay)
								set_direct_data <= '1';
					set(presub) <= '1';
					dest_hbits <= '1'; 
					dest_areg <= '1';
					setstate <= "10";

				WHEN cmpm =>		-- cmpm (Ay)+,(Ax)+
					set_direct_data <= '1';
					set(postadd) <= '1';
					dest_hbits <= '1'; 
					dest_areg <= '1';
					setstate <= "10";
					
				WHEN link1 =>		-- link
					setstate <="11";
					source_areg <= '1';
					set(opcMOVE) <= '1';
					set(Regwrena) <= '1';
					next_micro_state <= link2;
				WHEN link2 =>		-- link
					setstackaddr <='1';
					set(ea_data_OP2) <= '1';
					
				WHEN unlink1 =>		-- unlink
					setstate <="10";
					setstackaddr <='1';
					set(postadd) <= '1';
					next_micro_state <= unlink2;
				WHEN unlink2 =>		-- unlink
					set(ea_data_OP2) <= '1';
					
				WHEN trap0 =>		-- TRAP
					set(presub) <= '1';
					setstackaddr <='1';
					setstate <= "11";
					IF VBR_Stackframe=1 OR (cpu(0)='1' AND VBR_Stackframe=2) THEN	--68010
						set(writePC_add) <= '1';
						datatype <= "01";
--						set_datatype <= "10";
						next_micro_state <= trap1;
					ELSE
						IF trap_interrupt='1' OR trap_trace='1' THEN
							writePC <= '1';
						END IF;
						datatype <= "10";
						next_micro_state <= trap2;
					END IF;
				WHEN trap1 =>		-- TRAP
					IF trap_interrupt='1' OR trap_trace='1' THEN
						writePC <= '1';
					END IF;
					set(presub) <= '1';
					setstackaddr <='1';
					setstate <= "11";
					datatype <= "10";
					next_micro_state <= trap2;
				WHEN trap2 =>		-- TRAP
					set(presub) <= '1';
					setstackaddr <='1';
					setstate <= "11";
					datatype <= "01";
					writeSR <= '1';
					next_micro_state <= trap3;
				WHEN trap3 =>		-- TRAP
					set_vectoraddr <= '1';
					datatype <= "10";
					set(direct_delta) <= '1';	
					set(directPC) <= '1';
					setstate <= "10";
					next_micro_state <= nopnop;
					
				WHEN rte1 =>		-- RTE
					datatype <= "10";
					setstate <= "10";
					set(postadd) <= '1';
					setstackaddr <= '1';
					IF VBR_Stackframe=0 OR (cpu(0)='0' AND VBR_Stackframe=2) THEN
						set(direct_delta) <= '1';	
					END IF;
					set(directPC) <= '1';	
					next_micro_state <= rte2;
				WHEN rte2 =>		-- RTE
					datatype <= "01";
					set(update_FC) <= '1';
					IF VBR_Stackframe=1 OR (cpu(0)='1' AND VBR_Stackframe=2) THEN
						setstate <= "10";
						set(postadd) <= '1';
						setstackaddr <= '1';
						next_micro_state <= rte3;
					ELSE
						next_micro_state <= nop;
					END IF;
				WHEN rte3 =>		-- RTE
					next_micro_state <= nop;
--					set(update_FC) <= '1';
					
				WHEN movec1 =>		-- MOVEC
					set(briefext) <= '1';
					set_writePCbig <='1';
					IF (brief(11 downto 0)=X"000" OR brief(11 downto 0)=X"001" OR brief(11 downto 0)=X"800" OR brief(11 downto 0)=X"801") OR 
					   (cpu(1)='1' AND (brief(11 downto 0)=X"002" OR brief(11 downto 0)=X"802" OR brief(11 downto 0)=X"803" OR brief(11 downto 0)=X"804")) THEN
						IF opcode(0)='0' THEN
							set(Regwrena) <= '1';
						END IF;
--					ELSIF brief(11 downto 0)=X"800"OR brief(11 downto 0)=X"001" OR brief(11 downto 0)=X"000" THEN
--						trap_addr_error <= '1';
--						trapmake <= '1';
					ELSE
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
					
				WHEN movep1 =>		-- MOVEP d(An)
					setdisp <= '1';	
					set(mem_addsub) <= '1';	
					set(mem_byte) <= '1';
					set(OP1addr) <= '1';		
					IF opcode(6)='1' THEN
						set(movepl) <= '1';
					END IF;
					IF opcode(7)='0' THEN
						setstate <= "10";
					ELSE
						setstate <= "11";
					END IF;
					next_micro_state <= movep2;
				WHEN movep2 =>		
					IF opcode(6)='1' THEN
						set(mem_addsub) <= '1';	
					    set(OP1addr) <= '1';		
					END IF;
					IF opcode(7)='0' THEN
						setstate <= "10";
					ELSE
						setstate <= "11";
					END IF;
					next_micro_state <= movep3;
				WHEN movep3 =>		
					IF opcode(6)='1' THEN
						set(mem_addsub) <= '1';	
					    set(OP1addr) <= '1';		
						set(mem_byte) <= '1';
						IF opcode(7)='0' THEN
							setstate <= "10";
						ELSE
							setstate <= "11";
						END IF;
						next_micro_state <= movep4;
					ELSE	
						datatype <= "01";		--Word
					END IF;
				WHEN movep4 =>		
					IF opcode(7)='0' THEN
						setstate <= "10";
					ELSE
						setstate <= "11";
					END IF;
					next_micro_state <= movep5;
				WHEN movep5 =>		
					datatype <= "10";		--Long
					
				WHEN mul1	=>		-- mulu
					IF opcode(15)='1' OR MUL_Mode=0 THEN
						set_rot_cnt <= "001110";
					ELSE
						set_rot_cnt <= "011110";
					END IF;
					setstate <="01";
					next_micro_state <= mul2;
				WHEN mul2	=>		-- mulu
					setstate <="01";
					IF rot_cnt="00001" THEN
						next_micro_state <= mul_end1;
					ELSE	
						next_micro_state <= mul2;
					END IF;
				WHEN mul_end1	=>		-- mulu
					datatype <= "10";
					set(opcMULU) <= '1';
					IF opcode(15)='0' AND (MUL_Mode=1 OR MUL_Mode=2) THEN
						dest_2ndHbits <= '1';
						source_2ndLbits <= '1';--???
						set(write_lowlong) <= '1';
						IF sndOPC(10)='1' THEN
							setstate <="01";
							next_micro_state <= mul_end2;
						END IF;	
						set(Regwrena) <= '1';
					END IF;
					datatype <= "10";
				WHEN mul_end2	=>		-- divu
					set(write_reminder) <= '1';
					set(Regwrena) <= '1';
					set(opcMULU) <= '1';

				WHEN div1	=>		-- divu
					setstate <="01";
					next_micro_state <= div2;
				WHEN div2	=>		-- divu
					IF (OP2out(31 downto 16)=x"0000" OR opcode(15)='1' OR DIV_Mode=0) AND OP2out(15 downto 0)=x"0000" THEN		--div zero
						set_Z_error <= '1';
					ELSE
						next_micro_state <= div3;
					END IF;
					set(ld_rot_cnt) <= '1'; 
					setstate <="01";
				WHEN div3	=>		-- divu
					IF opcode(15)='1' OR DIV_Mode=0 THEN
						set_rot_cnt <= "001101";
					ELSE
						set_rot_cnt <= "011101";
					END IF;
					setstate <="01";
					next_micro_state <= div4;
				WHEN div4	=>		-- divu
					setstate <="01";
					IF rot_cnt="00001" THEN
						next_micro_state <= div_end1;
					ELSE	
						next_micro_state <= div4;
					END IF;
				WHEN div_end1	=>		-- divu
					IF opcode(15)='0' AND (DIV_Mode=1 OR DIV_Mode=2) THEN
						set(write_reminder) <= '1';
						next_micro_state <= div_end2;
						setstate <="01";
					END IF;
					set(opcDIVU) <= '1';
					datatype <= "10";
				WHEN div_end2	=>		-- divu
					dest_2ndHbits <= '1';
					source_2ndLbits <= '1';--???
					set(opcDIVU) <= '1';
					
				WHEN rota1	=>
					IF OP2out(5 downto 0)/="000000" THEN
						set_rot_cnt <= OP2out(5 downto 0);
					ELSE
						set_exec(rot_nop) <= '1';
					END IF;
					
				WHEN bf1 =>
					setstate <="10";
	
				WHEN OTHERS => NULL;
			END CASE;
	END PROCESS;

-----------------------------------------------------------------------------
-- MOVEC
-----------------------------------------------------------------------------
PROCESS (clk, VBR, CACR, brief)
	BEGIN
		IF rising_edge(clk) THEN
			IF Reset = '1' THEN
				VBR <= (OTHERS => '0');
				CACR <= (OTHERS => '0');
			ELSIF clkena_lw='1' AND exec(movec_wr)='1' THEN
				CASE brief(11 downto 0) IS
					WHEN X"002" => CACR <= reg_QA(3 downto 0);
					WHEN X"801" => VBR <= reg_QA;
					WHEN OTHERS => NULL;
				END CASE;
			END IF;	
		END IF;	
		movec_data <= (OTHERS=>'0');
		CASE brief(11 downto 0) IS
			WHEN X"002" => movec_data(3 downto 0) <= CACR;
			WHEN X"801" => --IF VBR_Stackframe=1 OR (cpu(0)='1' AND VBR_Stackframe=2) THEN
							    movec_data <= VBR;
						   --END IF;		
			WHEN OTHERS => NULL;
		END CASE;
	END PROCESS;
	
-----------------------------------------------------------------------------
-- Conditions
-----------------------------------------------------------------------------
PROCESS (exe_opcode, Flags)
	BEGIN
		CASE exe_opcode(11 downto 8) IS
			WHEN X"0" => exe_condition <= '1';
			WHEN X"1" => exe_condition <= '0';
			WHEN X"2" => exe_condition <=  NOT Flags(0) AND NOT Flags(2);
			WHEN X"3" => exe_condition <= Flags(0) OR Flags(2);
			WHEN X"4" => exe_condition <= NOT Flags(0);
			WHEN X"5" => exe_condition <= Flags(0);
			WHEN X"6" => exe_condition <= NOT Flags(2);
			WHEN X"7" => exe_condition <= Flags(2);
			WHEN X"8" => exe_condition <= NOT Flags(1);
			WHEN X"9" => exe_condition <= Flags(1);
			WHEN X"a" => exe_condition <= NOT Flags(3);
			WHEN X"b" => exe_condition <= Flags(3);
			WHEN X"c" => exe_condition <= (Flags(3) AND Flags(1)) OR (NOT Flags(3) AND NOT Flags(1));
			WHEN X"d" => exe_condition <= (Flags(3) AND NOT Flags(1)) OR (NOT Flags(3) AND Flags(1));
			WHEN X"e" => exe_condition <= (Flags(3) AND Flags(1) AND NOT Flags(2)) OR (NOT Flags(3) AND NOT Flags(1) AND NOT Flags(2));
			WHEN X"f" => exe_condition <= (Flags(3) AND NOT Flags(1)) OR (NOT Flags(3) AND Flags(1)) OR Flags(2);
			WHEN OTHERS => NULL;
		END CASE;
	END PROCESS;
	
-----------------------------------------------------------------------------
-- Movem
-----------------------------------------------------------------------------
PROCESS (clk)
	BEGIN
		IF rising_edge(clk) THEN
			IF clkena_lw='1' THEN
				movem_actiond <= exec(movem_action); 
				IF decodeOPC='1' THEN
					sndOPC <= data_read(15 downto 0);
				ELSIF exec(movem_action)='1' OR set(movem_action) ='1' THEN
					CASE movem_regaddr IS
						WHEN "0000" => sndOPC(0)  <= '0';
						WHEN "0001" => sndOPC(1)  <= '0';
						WHEN "0010" => sndOPC(2)  <= '0';
						WHEN "0011" => sndOPC(3)  <= '0';
						WHEN "0100" => sndOPC(4)  <= '0';
						WHEN "0101" => sndOPC(5)  <= '0';
						WHEN "0110" => sndOPC(6)  <= '0';
						WHEN "0111" => sndOPC(7)  <= '0';
						WHEN "1000" => sndOPC(8)  <= '0';
						WHEN "1001" => sndOPC(9)  <= '0';
						WHEN "1010" => sndOPC(10) <= '0';
						WHEN "1011" => sndOPC(11) <= '0';
						WHEN "1100" => sndOPC(12) <= '0';
						WHEN "1101" => sndOPC(13) <= '0';
						WHEN "1110" => sndOPC(14) <= '0';
						WHEN "1111" => sndOPC(15) <= '0';
						WHEN OTHERS => NULL;
					END CASE;
				END IF;
			END IF;
		END IF;
	END PROCESS;
	
PROCESS (sndOPC, movem_mux)
	BEGIN
		movem_regaddr <="0000";
		movem_run <= '1';
		IF sndOPC(3 downto 0)="0000" THEN
			IF sndOPC(7 downto 4)="0000" THEN
				movem_regaddr(3) <= '1';
				IF sndOPC(11 downto 8)="0000" THEN
					IF sndOPC(15 downto 12)="0000" THEN
						movem_run <= '0';
					END IF;
					movem_regaddr(2) <= '1';
					movem_mux <= sndOPC(15 downto 12);
				ELSE
					movem_mux <= sndOPC(11 downto 8);
				END IF;
			ELSE
				movem_mux <= sndOPC(7 downto 4);
				movem_regaddr(2) <= '1';
			END IF;
		ELSE
			movem_mux <= sndOPC(3 downto 0);
		END IF;
		IF movem_mux(1 downto 0)="00" THEN
			movem_regaddr(1) <= '1';
			IF movem_mux(2)='0' THEN
				movem_regaddr(0) <= '1';
			END IF;	
		ELSE		
			IF movem_mux(0)='0' THEN
				movem_regaddr(0) <= '1';
			END IF;	
		END  IF;
	END PROCESS;
END; 
