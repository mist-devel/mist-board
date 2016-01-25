------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- --
-- Copyright (c) 2009-2013 Tobias Gubener --
-- Patches by MikeJ, Till Harbaum, Rok Krajnk, ...                          --
-- Subdesign fAMpIGA by TobiFlex --
-- --
-- This source file is free software: you can redistribute it and/or modify --
-- it under the terms of the GNU General Public License as published --
-- by the Free Software Foundation, either version 3 of the License, or --
-- (at your option) any later version. --
-- --
-- This source file is distributed in the hope that it will be useful, --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of --
-- MERCHANTABILITY or FITNESS For A PARTICULAR PURPOSE. See the --
-- GNU General Public License for more details. --
-- --
-- You should have received a copy of the GNU General Public License --
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.    --
-- --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

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
-- TRAPcc

-- done 020:
-- PACK, UNPK
-- Bitfields
-- address modes
-- long bra
-- DIVS.L, DIVU.L
-- LINK long
-- MULS.L, MULU.L
-- extb.l

library ieee;
use ieee.std_logic_1164.ALL;
use ieee.std_logic_unsigned.ALL;
use work.TG68K_Pack.ALL;

entity TG68KdotC_Kernel is
  generic (
	SR_Read        : integer := 0; --0=>user,  1=>privileged,   2=>switchable with CPU(0)
	VBR_Stackframe : integer := 0; --0=>no,    1=>yes/extended, 2=>switchable with CPU(0)
	extAddr_Mode   : integer := 0; --0=>no,    1=>yes,   2=>switchable with CPU(1)
	MUL_Mode       : integer := 0; --0=>16Bit, 1=>32Bit, 2=>switchable with CPU(1), 3=>no MUL,
	DIV_Mode       : integer := 0; --0=>16Bit, 1=>32Bit, 2=>switchable with CPU(1), 3=>no DIV,
	BitField       : integer := 0  --0=>no,    1=>yes,   2=>switchable with CPU(1)
  );
  port (
	clk            : in  std_logic;
	nReset         : in  std_logic; --low active
	clkena_in      : in  std_logic := '1';
	data_in        : in  std_logic_vector(15 downto 0);
	IPL            : in  std_logic_vector( 2 downto 0) := "111";
	IPL_autovector : in  std_logic := '1'; -- ACTIVE LOW
	berr           : in  std_logic :='0';                       -- only 68000 Stackpointer dummy
	CPU            : in  std_logic_vector( 1 downto 0) := "00"; -- 00->68000 01->68010 11->68020(only some parts - yet)
	addr_out       : out std_logic_vector(31 downto 0);
	data_write     : out std_logic_vector(15 downto 0);
	nWr            : out std_logic;
	nUDS           : out std_logic;
	nLDS           : out std_logic;
	busstate       : out std_logic_vector(1 downto 0); -- 00-> fetch code 10->read data 11->write data 01->no memaccess
	nResetOut      : out std_logic;
	FC             : out std_logic_vector(2 downto 0);
	clr_berr       : out std_logic;
	--  for debug
	skipFetch      : out std_logic;
	regin_out      : out std_logic_vector(31 downto 0);
	CACR_out       : out std_logic_vector( 3 downto 0);
	VBR_out        : out std_logic_vector(31 downto 0)
  );
end TG68KdotC_Kernel;

--nBS : std_logic_vector(3 downto 0); -- nBS0 is 31..24 3 is 7..0, active LOW
--SIZ : std_logic_vector(1 downto 0);
--ACK for 16/32 bit transfer?
architecture logic of TG68KdotC_Kernel is
  signal syncReset              : std_logic_vector(3 downto 0);
  signal Reset                  : std_logic;
  signal clkena_lw              : std_logic;
  signal TG68_PC                : std_logic_vector(31 downto 0);
  signal tmp_TG68_PC            : std_logic_vector(31 downto 0);
  signal TG68_PC_add            : std_logic_vector(31 downto 0);
  signal PC_dataa               : std_logic_vector(31 downto 0);
  signal PC_datab               : std_logic_vector(31 downto 0);
  signal memaddr                : std_logic_vector(31 downto 0);
  signal state                  : std_logic_vector(1 downto 0);
  signal datatype               : std_logic_vector(1 downto 0);
  signal set_datatype           : std_logic_vector(1 downto 0);
  signal exe_datatype           : std_logic_vector(1 downto 0);
  signal setstate               : std_logic_vector(1 downto 0);
  signal opcode                 : std_logic_vector(15 downto 0);
  signal exe_opcode             : std_logic_vector(15 downto 0);
  signal exe_pc                 : std_logic_vector(31 downto 0);
  signal last_opc_pc            : std_logic_vector(31 downto 0);
  signal sndOPC                 : std_logic_vector(15 downto 0);

  signal last_opc_read          : std_logic_vector(15 downto 0);
  signal reg_QA                 : std_logic_vector(31 downto 0);
  signal reg_QB                 : std_logic_vector(31 downto 0);
  signal Wwrena                 : bit;
  signal Lwrena                 : bit;
  signal Bwrena                 : bit;
  signal Regwrena_now           : bit;
  signal rf_dest_addr           : std_logic_vector(3 downto 0);
  signal rf_source_addr         : std_logic_vector(3 downto 0);
  signal rf_source_addrd        : std_logic_vector(3 downto 0);

  type regfile_t is ARRAY(0 TO 15) OF std_logic_vector(31 downto 0);
  signal regfile                : regfile_t := (OTHERS => (OTHERS => '0')); -- mikej stops sim X issues;
  signal RDindex_A              : integer range 0 TO 15;
  signal RDindex_B              : integer range 0 TO 15;

  signal WR_AReg                : std_logic;
  signal addr                   : std_logic_vector(31 downto 0);
  signal memaddr_reg            : std_logic_vector(31 downto 0);
  signal memaddr_delta          : std_logic_vector(31 downto 0);
  signal use_base               : bit;
  signal ea_data                : std_logic_vector(31 downto 0);
  signal OP1out                 : std_logic_vector(31 downto 0);
  signal OP2out                 : std_logic_vector(31 downto 0);
  signal OP1outbrief            : std_logic_vector(15 downto 0);
  signal OP1in                  : std_logic_vector(31 downto 0);
  signal ALUout                 : std_logic_vector(31 downto 0);
  signal data_write_tmp         : std_logic_vector(31 downto 0);
  signal data_write_muxin       : std_logic_vector(31 downto 0);
  signal data_write_mux         : std_logic_vector(47 downto 0);
  signal nextpass               : bit;
  signal setnextpass            : bit;
  signal setdispbyte            : bit;
  signal setdisp                : bit;
  signal regdirectsource        : bit; -- checken !!!
  signal addsub_q               : std_logic_vector(31 downto 0);
  signal briefdata              : std_logic_vector(31 downto 0);

  signal c_out                  : std_logic_vector(2 downto 0);
  signal mem_address            : std_logic_vector(31 downto 0);
  signal memaddr_a              : std_logic_vector(31 downto 0);
  signal TG68_PC_brw            : bit;
  signal TG68_PC_word           : bit;
  signal getbrief               : bit;
  signal brief                  : std_logic_vector(15 downto 0);
  signal dest_areg              : std_logic;
  signal source_areg            : std_logic;
  signal data_is_source         : bit;
  signal store_in_tmp           : bit;
  signal write_back             : bit;
  signal exec_write_back        : bit;
  signal setstackaddr           : bit;
  signal writePC                : bit;
  signal writePCbig             : bit;
  signal set_writePCbig         : bit;
  signal setopcode              : bit;
  signal decodeOPC              : bit;
  signal execOPC                : bit;
  signal setexecOPC             : bit;
  signal endOPC                 : bit;
  signal setendOPC              : bit;
  signal Flags                  : std_logic_vector(7 downto 0); -- ...XNZVC
  signal FlagsSR                : std_logic_vector(7 downto 0) := (others => '0'); -- T.S..III
  signal SRin                   : std_logic_vector(7 downto 0);
  signal exec_DIRECT            : bit;
  signal exec_tas               : std_logic;
  signal set_exec_tas           : std_logic;
  signal exe_condition          : std_logic;
  signal ea_only                : bit;
  signal source_lowbits         : bit;
  signal source_2ndHbits        : bit;
  signal source_2ndLbits        : bit;
  signal dest_2ndHbits          : bit;
  signal dest_hbits             : bit;
  signal rot_bits               : std_logic_vector(1 downto 0);
  signal set_rot_bits           : std_logic_vector(1 downto 0);
  signal rot_cnt                : std_logic_vector(5 downto 0);
  signal set_rot_cnt            : std_logic_vector(5 downto 0);
  signal movem_actiond          : bit;
  signal movem_regaddr          : std_logic_vector(3 downto 0);
  signal movem_mux              : std_logic_vector(3 downto 0);
  signal movem_presub           : bit;
  signal movem_run              : bit;
  signal ea_calc_b              : std_logic_vector(31 downto 0);
  signal set_direct_data        : bit;
  signal use_direct_data        : bit;
  signal direct_data            : bit;

  signal set_V_Flag             : bit;
  signal set_vectoraddr         : bit;
  signal writeSR                : bit;
  signal trap_berr              : bit;
  signal trap_illegal           : bit;
  signal trap_addr_error        : bit;
  signal trap_priv              : bit;
  signal trap_trace             : bit;
  signal trap_1010              : bit;
  signal trap_1111              : bit;
  signal trap_trap              : bit;
  signal trap_trapv             : bit;
  signal trap_interrupt         : bit;
  signal trapmake               : bit;
  signal trapd                  : bit;
  signal trap_SR                : std_logic_vector(7 downto 0);
  signal make_trace             : std_logic;
  signal make_berr              : std_logic;

  signal set_stop               : bit;
  signal stop                   : bit;
  signal trap_vector            : std_logic_vector(31 downto 0);
  signal trap_vector_vbr        : std_logic_vector(31 downto 0);
  signal USP                    : std_logic_vector(31 downto 0);
  signal illegal_write_mode     : bit;
  signal illegal_read_mode      : bit;
  signal illegal_byteaddr       : bit;

  signal IPL_nr                 : std_logic_vector(2 downto 0);
  signal rIPL_nr                : std_logic_vector(2 downto 0);
  signal IPL_vec                : std_logic_vector(7 downto 0);
  signal interrupt              : bit;
  signal setinterrupt           : bit;
  signal SVmode                 : std_logic;
  signal preSVmode              : std_logic;
  signal Suppress_Base          : bit;
  signal set_Suppress_Base      : bit;
  signal set_Z_error            : bit;
  signal Z_error                : bit;
  signal ea_build_now           : bit;
  signal build_logical          : bit;
  signal build_bcd              : bit;

  signal data_read              : std_logic_vector(31 downto 0);
  signal bf_ext_in              : std_logic_vector(7 downto 0);
  signal bf_ext_out             : std_logic_vector(7 downto 0);
  signal byte                   : bit;
  signal long_start             : bit;
  signal long_start_alu         : bit;
  signal non_aligned            : std_logic;
  signal long_done              : bit;
  signal memmask                : std_logic_vector(5 downto 0);
  signal set_memmask            : std_logic_vector(5 downto 0);
  signal memread                : std_logic_vector(3 downto 0);
  signal wbmemmask              : std_logic_vector(5 downto 0);
  signal memmaskmux             : std_logic_vector(5 downto 0);
  signal oddout                 : std_logic;
  signal set_oddout             : std_logic;
  signal PCbase                 : std_logic;
  signal set_PCbase             : std_logic;

  signal last_data_read         : std_logic_vector(31 downto 0);
  signal last_data_in           : std_logic_vector(31 downto 0);

  signal bf_offset              : std_logic_vector(31 downto 0);
  signal bf_offset_l            : std_logic_vector(4 downto 0);
  signal bf_loffset             : std_logic_vector(4 downto 0);
  signal bf_width               : std_logic_vector(4 downto 0);
  signal bf_bhits               : std_logic_vector(5 downto 0);
  signal alu_bf_width           : std_logic_vector(4 downto 0);
  signal alu_bf_offset          : std_logic_vector(31 downto 0);
  signal alu_bf_loffset         : std_logic_vector(4 downto 0);

  signal movec_data             : std_logic_vector(31 downto 0);
  signal VBR                    : std_logic_vector(31 downto 0);
  signal CACR                   : std_logic_vector(3 downto 0);
  signal DFC                    : std_logic_vector(2 downto 0);
  signal SFC                    : std_logic_vector(2 downto 0);
  signal set                    : bit_vector(lastOpcBit downto 0);
  signal set_exec               : bit_vector(lastOpcBit downto 0);
  signal exec                   : bit_vector(lastOpcBit downto 0);
  signal exec_d                 : rTG68K_opc;

  signal micro_state            : micro_states;
  signal next_micro_state       : micro_states;

  signal regin                  : std_logic_vector(31 downto 0);

begin

  ALU : TG68K_ALU
  generic map(
	MUL_Mode => MUL_Mode, --0=>16Bit, 1=>32Bit, 2=>switchable with CPU(1), 3=>no MUL,
	DIV_Mode => DIV_Mode  --0=>16Bit, 1=>32Bit, 2=>switchable with CPU(1), 3=>no DIV,
  )
  port map(
	clk            => clk,              --: in std_logic;
	Reset          => Reset,            --: in std_logic;
	clkena_lw      => clkena_lw,        --: in std_logic:='1';
	execOPC        => execOPC,          --: in bit;
	exe_condition  => exe_condition,    --: in std_logic;
	exec_tas       => exec_tas,         --: in std_logic;
	long_start     => long_start_alu,   --: in bit;
	non_aligned    => non_aligned,
	movem_presub   => movem_presub,     --: in bit;
	set_stop       => set_stop,         --: in bit;
	Z_error        => Z_error,          --: in bit;
	rot_bits       => rot_bits,         --: in std_logic_vector(1 downto 0);
	exec           => exec,             --: in bit_vector(lastOpcBit downto 0);
	OP1out         => OP1out,           --: in std_logic_vector(31 downto 0);
	OP2out         => OP2out,           --: in std_logic_vector(31 downto 0);
	reg_QA         => reg_QA,           --: in std_logic_vector(31 downto 0);
	reg_QB         => reg_QB,           --: in std_logic_vector(31 downto 0);
	opcode         => opcode,           --: in std_logic_vector(15 downto 0);
	datatype       => datatype,         --: in std_logic_vector(1 downto 0);
	exe_opcode     => exe_opcode,       --: in std_logic_vector(15 downto 0);
	exe_datatype   => exe_datatype,     --: in std_logic_vector(1 downto 0);
	sndOPC         => sndOPC,           --: in std_logic_vector(15 downto 0);
	last_data_read => last_data_read(15 downto 0), --: in std_logic_vector(31 downto 0);
	data_read      => data_read(15      downto 0), --: in std_logic_vector(31 downto 0);
	FlagsSR        => FlagsSR,          --: in std_logic_vector(7 downto 0);
	micro_state    => micro_state,      --: in micro_states;
	bf_ext_in      => bf_ext_in,
	bf_ext_out     => bf_ext_out,
	bf_width       => alu_bf_width,
	bf_offset      => alu_bf_offset,
	bf_loffset     => alu_bf_loffset,
	set_V_Flag_out => set_V_Flag,       --: buffer bit;
	Flags_out      => Flags,            --: buffer std_logic_vector(8 downto 0);
	c_out_out      => c_out,            --: buffer std_logic_vector(2 downto 0);
	addsub_q_out   => addsub_q,         --: buffer std_logic_vector(31 downto 0);
	ALUout         => ALUout            --: buffer std_logic_vector(31 downto 0)
  );

  long_start_alu <= to_bit(not memmaskmux(3));

  process (memmaskmux)
  begin
	non_aligned <= '0';
	if (memmaskmux(5 downto 4) = "01") or (memmaskmux(5 downto 4) = "10") then
	  non_aligned <= '1';
	end if;
  end process;
  -----------------------------------------------------------------------------
  -- Bus control
  -----------------------------------------------------------------------------
  nWr <= '0' when state = "11" else '1';
  busstate <= state;
  nResetOut <= '0' when exec(opcRESET) = '1' else '1';

  -- does shift for byte access. note active low me
  -- should produce address error on 68000
  memmaskmux <= memmask when addr(0) = '1' else memmask(4 downto 0) & '1';

  nUDS <= memmaskmux(5);
  nLDS <= memmaskmux(4);
  clkena_lw <= '1' when clkena_in = '1' and memmaskmux(3) = '1' else '0'; -- step
  clr_berr  <= '1' WHEN setopcode='1' AND trap_berr='1' ELSE '0';

  process (clk, nReset)
  begin
	if nReset = '0' then
	  syncReset <= "0000";
	  Reset <= '1';
	elsif rising_edge(clk) then
	  if clkena_in = '1' then
		syncReset <= syncReset(2 downto 0) & '1';
		Reset <= not syncReset(3);
	  end if;
	end if;
  end process;

  process (clk, long_done, last_data_in, data_in, byte, addr, long_start, memmaskmux, memread, memmask, data_read)
  begin
	if memmaskmux(4) = '0' then
	  data_read <= last_data_in(15 downto 0) & data_in;
	else
	  data_read <= last_data_in(23 downto 0) & data_in(15 downto 8);
	end if;
	if memread(0) = '1' or (memread(1 downto 0) = "10" and memmaskmux(4) = '1') then
	  data_read(31 downto 16) <= (others => data_read(15));
	end if;

	if rising_edge(clk) then
	  if clkena_lw = '1' and state = "10" then
		if memmaskmux(4) = '0' then
		  bf_ext_in <= last_data_in(23 downto 16);
		else
		  bf_ext_in <= last_data_in(31 downto 24);
		end if;
	  end if;

	  if Reset = '1' then
		last_data_read <= (others => '0');
	  elsif clkena_in = '1' then
		if state = "00" or exec(update_ld) = '1' then
		  last_data_read <= data_read;
		  if state(1) = '0' and memmask(1) = '0' then
			last_data_read(31 downto 16) <= last_opc_read;
		  elsif state(1) = '0' or memread(1) = '1' then
			last_data_read(31 downto 16) <= (others => data_in(15));
		  end if;
		end if;
		last_data_in <= last_data_in(15 downto 0) & data_in(15 downto 0);

	  end if;
	end if;
	long_start <= to_bit(not memmask(1));
	long_done <= to_bit(not memread(1));
  end process;

  process (byte, long_start, reg_QB, data_write_tmp, exec, data_read, data_write_mux, memmaskmux, bf_ext_out,
		   data_write_muxin, memmask, oddout, addr)
  begin
	if exec(write_reg) = '1' then
	  data_write_muxin <= reg_QB; -- 32 bits
	else
	  data_write_muxin <= data_write_tmp;
	end if;

	if BitField = 0 then
	  if oddout = addr(0) then
		data_write_mux <= "XXXXXXXX" & "XXXXXXXX" & data_write_muxin;
	  else
		data_write_mux <= "XXXXXXXX" & data_write_muxin & "XXXXXXXX";
	  end if;
	else
	  if oddout = addr(0) then
		data_write_mux <= "XXXXXXXX" & bf_ext_out & data_write_muxin;
	  else
		data_write_mux <= bf_ext_out & data_write_muxin & "XXXXXXXX";
	  end if;
	end if;

	if memmaskmux(1) = '0' then
	  data_write <= data_write_mux(47 downto 32);
	elsif memmaskmux(3) = '0' then
	  data_write <= data_write_mux(31 downto 16);
	else
	  data_write <= data_write_mux(15 downto 0);
	end if;

	if exec(mem_byte) = '1' then --movep
	  data_write(7 downto 0) <= data_write_tmp(15 downto 8);
	end if;
  end process;

  -----------------------------------------------------------------------------
  -- Registerfile
  -----------------------------------------------------------------------------
  process (clk, regfile, RDindex_A, RDindex_B, exec)
  begin
	reg_QA <= regfile(RDindex_A);
	reg_QB <= regfile(RDindex_B);
	if rising_edge(clk) then
	  if clkena_lw = '1' then
		rf_source_addrd <= rf_source_addr;
		WR_AReg <= rf_dest_addr(3);
		RDindex_A <= conv_integer(rf_dest_addr(3 downto 0));
		RDindex_B <= conv_integer(rf_source_addr(3 downto 0));

		if Wwrena = '1' then
		  regfile(RDindex_A) <= regin;
		end if;

		if exec(to_USP) = '1' then
		  USP <= reg_QA;
		end if;
	  end if;
	end if;
  end process;

  -----------------------------------------------------------------------------
  -- Write Reg
  -----------------------------------------------------------------------------
  process (OP1in, reg_QA, Regwrena_now, Bwrena, Lwrena, exe_datatype, WR_AReg, movem_actiond, exec, ALUout, memaddr, memaddr_a, ea_only, USP, movec_data)
  begin
	regin <= ALUout;
	if exec(save_memaddr) = '1' then -- only used for movem
	  regin <= memaddr;
	elsif exec(get_ea_now) = '1' and ea_only = '1' then
	  regin <= memaddr_a;
	elsif exec(from_USP) = '1' then
	  regin <= USP;
	elsif exec(movec_rd) = '1' then
	  regin <= movec_data;
	end if;

	if Bwrena = '1' then
	  regin(15 downto 8) <= reg_QA(15 downto 8);
	end if;
	if Lwrena = '0' then
	  regin(31 downto 16) <= reg_QA(31 downto 16);
	end if;

	Bwrena <= '0';
	Wwrena <= '0';
	Lwrena <= '0';
	if exec(presub) = '1' or exec(postadd) = '1' or exec(changeMode) = '1' then -- -(An)+
	  Wwrena <= '1';
	  Lwrena <= '1';
	elsif Regwrena_now = '1' then --dbcc
	  Wwrena <= '1';
	elsif exec(Regwrena) = '1' then --read (mem)
	  Wwrena <= '1';
	  case exe_datatype is
		when "00" => --BYTE
		  Bwrena <= '1';
		when "01" => --WorD
		  if WR_AReg = '1' or movem_actiond = '1' then
			Lwrena <= '1';
		  end if;
		when others => --LONG
		  Lwrena <= '1';
	  end case;
	end if;
  end process;

  -----------------------------------------------------------------------------
  -- set dest regaddr
  -----------------------------------------------------------------------------
  process (opcode, rf_source_addrd, brief, setstackaddr, dest_hbits, dest_areg, data_is_source, sndOPC, exec, set, dest_2ndHbits)
  begin
	if exec(movem_action) = '1' then
	  rf_dest_addr <= rf_source_addrd;
	elsif set(briefext) = '1' then
	  rf_dest_addr <= brief(15 downto 12);
	elsif set(get_bfoffset) = '1' then
	  rf_dest_addr <= sndOPC(9 downto 6);
	elsif dest_2ndHbits = '1' then
	  rf_dest_addr <= sndOPC(15 downto 12);
	elsif set(write_reminder) = '1' then
	  rf_dest_addr <= sndOPC(3 downto 0);
	elsif setstackaddr = '1' then
	  rf_dest_addr <= "1111";
	elsif dest_hbits = '1' then
	  rf_dest_addr <= dest_areg & opcode(11 downto 9);
	else
	  if opcode(5 downto 3) = "000" or data_is_source = '1' then
		rf_dest_addr <= dest_areg & opcode(2 downto 0);
	  else
		rf_dest_addr <= '1' & opcode(2 downto 0);
	  end if;
	end if;
  end process;

  -----------------------------------------------------------------------------
  -- set source regaddr
  -----------------------------------------------------------------------------
  process (opcode, movem_presub, movem_regaddr, source_lowbits, source_areg, sndOPC, exec, set, source_2ndLbits, source_2ndHbits)
  begin
	if exec(movem_action) = '1' or set(movem_action) = '1' then
	  if movem_presub = '1' then
		rf_source_addr <= movem_regaddr Xor "1111";
	  else
		rf_source_addr <= movem_regaddr;
	  end if;
	elsif source_2ndLbits = '1' then
	  rf_source_addr <= sndOPC(3 downto 0);
	elsif source_2ndHbits = '1' then
	  rf_source_addr <= sndOPC(15 downto 12);
	elsif source_lowbits = '1' then
	  rf_source_addr <= source_areg & opcode(2 downto 0);
	elsif exec(linksp) = '1' then
	  rf_source_addr <= "1111";
	else
	  rf_source_addr <= source_areg & opcode(11 downto 9);
	end if;
  end process;

  -----------------------------------------------------------------------------
  -- set OP1out
  -----------------------------------------------------------------------------
  process (reg_QA, store_in_tmp, ea_data, long_start, addr, exec, memmaskmux)
  begin
	OP1out <= reg_QA;
	if exec(OP1out_zero) = '1' then
	  OP1out <= (others => '0');
	elsif exec(ea_data_OP1) = '1' and store_in_tmp = '1' then
	  OP1out <= ea_data;
	elsif exec(opcPACK) = '1' then
	  OP1out <= data_write_tmp;
	elsif exec(movem_action) = '1' or memmaskmux(3) = '0' or exec(OP1addr) = '1' then
	  OP1out <= addr;
	end if;
  end process;

  -----------------------------------------------------------------------------
  -- set OP2out
  -----------------------------------------------------------------------------
  process (  OP2out, reg_QB, exe_opcode, exe_datatype, execOPC, exec, use_direct_data, store_in_tmp, data_write_tmp, ea_data)
  begin
	OP2out(15 downto 0) <= reg_QB(15 downto 0);
	OP2out(31 downto 16) <= (others => OP2out(15));

	if exec(OP2out_one) = '1' then
	  OP2out(15 downto 0) <= "1111111111111111";
	elsif exec(opcEXT) = '1' then
	  if exe_opcode(6) = '0' or exe_opcode(8) = '1' then --ext.w
		OP2out(15 downto 8) <= (others => OP2out(7));
	  end if;

	elsif (use_direct_data = '1' and exec(opcPACK) = '0') or (exec(exg) = '1' and execOPC = '1') or exec(get_bfoffset) = '1' then
	  OP2out <= data_write_tmp;

	elsif (exec(ea_data_OP1) = '0' and store_in_tmp = '1') or exec(ea_data_OP2) = '1' then
	  OP2out <= ea_data;

	elsif exec(opcMOVEQ) = '1' then
	  OP2out(7 downto 0) <= exe_opcode(7 downto 0);
	  OP2out(15 downto 8) <= (others => exe_opcode(7));

	elsif exec(opcADDQ) = '1' then
	  OP2out(2 downto 0) <= exe_opcode(11 downto 9);
	  if exe_opcode(11 downto 9) = "000" then
		OP2out(3) <= '1';
	  else
		OP2out(3) <= '0';
	  end if;
	  OP2out(15 downto 4) <= (others => '0');

	elsif exe_datatype = "10" then
	  OP2out(31 downto 16) <= reg_QB(31 downto 16);
	end if;
  end process;

  -----------------------------------------------------------------------------
  -- handle EA_data, data_write
  -----------------------------------------------------------------------------
  process (clk)
  begin
	if rising_edge(clk) then
	  if Reset = '1' then
		store_in_tmp <= '0';
		exec_write_back <= '0';
		direct_data <= '0';
		use_direct_data <= '0';
		Z_error <= '0';
	  elsif clkena_lw = '1' then
		direct_data <= '0';

		if state = "11" then
		  exec_write_back <= '0';
		elsif setstate = "10" and write_back = '1' then
		  exec_write_back <= '1';
		end if;

		if set_direct_data = '1' then
		  direct_data <= '1';
		  if set_exec(opcPACK) = '1' then
			use_direct_data <= '0';
		  else
			use_direct_data <= '1';
		  end if;
		elsif endOPC = '1' then
		  use_direct_data <= '0';
		end if;
		exec_DIRECT <= set_exec(opcMOVE);

		if endOPC = '1' then
		  store_in_tmp <= '0';
		  Z_error <= '0';
		else
		  if set_Z_error = '1' then
			Z_error <= '1';
		  end if;
		  if set_exec(opcMOVE) = '1' and state = "11" then
			use_direct_data <= '1';
		  end if;

		  if state = "10" then
			store_in_tmp <= '1';
		  end if;
		  if direct_data = '1' and state = "00" then
			store_in_tmp <= '1';
		  end if;
		end if;

		if state = "10" then
		  ea_data <= data_read;
				elsif exec(get_2ndOPC)='1' or set_PCbase='1' THEN --TH cmpi (d16,PC) fix
		  ea_data <= addr;
		elsif exec(store_ea_data) = '1' or (direct_data = '1' and state = "00") then
		  ea_data <= last_data_read;
		end if;

		if writePC = '1' then
		  data_write_tmp <= TG68_PC;
		elsif exec(writePC_add) = '1' then
		  data_write_tmp <= TG68_PC_add;
		 elsif micro_state=trap00 THEN
		  data_write_tmp <= exe_pc; --TH
		elsif micro_state = trap0 then
		  -- this is only active for 010+ since in 000 writePC is
		  -- true in state trap0
		  if trap_trace='1' then
			-- stack frame format #2
			data_write_tmp(15 downto 0) <= "0010" & trap_vector(11 downto 0); --TH
		  else
			data_write_tmp(15 downto 0) <= "0000" & trap_vector(11 downto 0);
		  end if;
		elsif exec(hold_dwr) = '1' then
		  data_write_tmp <= data_write_tmp;
		elsif exec(exg) = '1' then
		  data_write_tmp <= OP1out;
		elsif exec(get_ea_now) = '1' and ea_only = '1' then -- ist for pea
		  data_write_tmp <= addr;
		elsif execOPC = '1' or micro_state = pack2 then
		  data_write_tmp <= ALUout;
		elsif (exec_DIRECT = '1' and state = "10") then
		  data_write_tmp <= data_read;
		  if exec(movepl) = '1' then
			data_write_tmp(31 downto 8) <= data_write_tmp(23 downto 0);
		  end if;
		elsif exec(movepl) = '1' then
		  data_write_tmp(15 downto 0) <= reg_QB(31 downto 16);
		elsif direct_data = '1' then
		  data_write_tmp <= last_data_read;
		elsif writeSR = '1' then
		  data_write_tmp(15 downto 0) <= trap_SR(7 downto 0) & Flags(7 downto 0);
		else
		  data_write_tmp <= OP2out;
		end if;

	  end if;
	end if;
  end process;

  -----------------------------------------------------------------------------
  -- brief
  -----------------------------------------------------------------------------
  process (brief, OP1out, OP1outbrief, cpu)
  begin
	if brief(11) = '1' then
	  OP1outbrief <= OP1out(31 downto 16);
	else
	  OP1outbrief <= (others => OP1out(15));
	end if;
	briefdata <= OP1outbrief & OP1out(15 downto 0);
	if extAddr_Mode = 1 or (cpu(1) = '1' and extAddr_Mode = 2) then
	  case brief(10 downto 9) is -- mikej SCALE factor
		when "00" => briefdata <= OP1outbrief & OP1out(15 downto 0);
		when "01" => briefdata <= OP1outbrief(14 downto 0) & OP1out(15 downto 0) & '0';
		when "10" => briefdata <= OP1outbrief(13 downto 0) & OP1out(15 downto 0) & "00";
		when "11" => briefdata <= OP1outbrief(12 downto 0) & OP1out(15 downto 0) & "000";
		when others => NULL;
	  end case;
	end if;
  end process;

  -----------------------------------------------------------------------------
  -- MEM_IO
  -----------------------------------------------------------------------------
  process (clk, setdisp, memaddr_a, briefdata, memaddr_delta, setdispbyte, datatype, interrupt, rIPL_nr, IPL_vec,
		   memaddr_reg, reg_QA, use_base, VBR, last_data_read, trap_vector, exec, set, cpu)
  begin
	if rising_edge(clk) then
	  if clkena_lw = '1' then
		trap_vector(31 downto 12) <= (others => '0');

		if trap_berr='1' then
		  trap_vector(11 downto 0) <= X"008";
		end IF;

		if trap_addr_error = '1' then
		  trap_vector(11 downto 0) <= X"00C";
		end if;

		if trap_illegal = '1' then
		  trap_vector(11 downto 0) <= X"010";
		end if;

		if z_error = '1' then
		  trap_vector(11 downto 0) <= X"014";
		end if;

		if exec(trap_chk) = '1' then
		  trap_vector(11 downto 0) <= X"018";
		end if;

		if trap_trapv = '1' then
		  trap_vector(11 downto 0) <= X"01C";
		end if;

		if trap_priv = '1' then
		  trap_vector(11 downto 0) <= X"020";
		end if;

		if trap_trace = '1' then
		  trap_vector(11 downto 0) <= X"024";
		end if;

		if trap_1010 = '1' then
		  trap_vector(11 downto 0) <= X"028";
		end if;

		if trap_1111 = '1' then
		  trap_vector(11 downto 0) <= X"02C";
		end if;

		if trap_trap = '1' then
		  trap_vector(11 downto 0) <= x"0" & "10" & opcode(3 downto 0) & "00";
		end if;

		if trap_interrupt = '1' then
		  trap_vector(11 downto 0) <= "00" & IPL_vec & "00"; --TH
		end if;
		-- TH TODO: non-autovector IRQs
	  end if;
	end if;
	--
	if VBR_Stackframe = 0 or (cpu(0) = '0' and VBR_Stackframe = 2) then
	  trap_vector_vbr <= trap_vector;
	else
	  trap_vector_vbr <= trap_vector + VBR;
	end if;

	memaddr_a(4 downto 0) <= "00000";
	memaddr_a(7 downto 5) <= (others => memaddr_a(4));
	memaddr_a(15 downto 8) <= (others => memaddr_a(7));
	memaddr_a(31 downto 16) <= (others => memaddr_a(15));
	if setdisp = '1' then
	  if exec(briefext) = '1' then
		memaddr_a <= briefdata + memaddr_delta;
	  elsif setdispbyte = '1' then
		memaddr_a(7 downto 0) <= last_data_read(7 downto 0);
	  else
		memaddr_a <= last_data_read;
	  end if;
	elsif set(presub) = '1' then
	  if set(longaktion) = '1' then
		memaddr_a(4 downto 0) <= "11100";
	  elsif datatype = "00" and set(use_SP) = '0' then
		memaddr_a(4 downto 0) <= "11111";
	  else
		memaddr_a(4 downto 0) <= "11110";
	  end if;
	elsif interrupt = '1' then
	  memaddr_a(4 downto 0) <= '1' & rIPL_nr & '0';
	end if;

	if rising_edge(clk) then
	  if clkena_in = '1' then
		if exec(get_2ndOPC) = '1' or (state = "10" and memread(0) = '1') then
		  tmp_TG68_PC <= addr;
		end if;
		use_base <= '0';

		if memmaskmux(3) = '0' then
		  memaddr_delta <= addsub_q;
		elsif exec(mem_addsub) = '1' then
		  memaddr_delta <= addsub_q;
		elsif state = "01" and exec_write_back = '1' then
		  memaddr_delta <= tmp_TG68_PC;
		elsif exec(direct_delta) = '1' then
		  memaddr_delta <= data_read;
		elsif exec(ea_to_pc) = '1' and setstate = "00" then
		  memaddr_delta <= addr;
		elsif set(addrlong) = '1' then
		  memaddr_delta <= last_data_read;
		elsif setstate = "00" then
		  memaddr_delta <= TG68_PC_add;
		elsif exec(dispouter) = '1' then
		  memaddr_delta <= ea_data + memaddr_a;
		elsif set_vectoraddr = '1' then
		  memaddr_delta <= trap_vector_vbr;
		else
		  memaddr_delta <= memaddr_a;
		  if interrupt = '0' and Suppress_Base = '0' then
			-- if interrupt='0' and Suppress_Base='0' and setstate(1)='1' then
			use_base <= '1';
		  end if;
		end if;

		-- only used for movem address update
		--if (long_done = '0' and state(1) = '1') or movem_presub = '0' then
		if ((memread(0) = '1') and state(1) = '1') or movem_presub = '0' then -- fix for unaligned movem mikej
		  memaddr <= addr;
		end if;
	  end if;
	end if;
	-- if access done, and not aligned, don't increment
	addr <= memaddr_reg + memaddr_delta;
	addr_out <= memaddr_reg + memaddr_delta;

	if use_base = '0' then
	  memaddr_reg <= (others => '0');
	else
	  memaddr_reg <= reg_QA;
	end if;
  end process;

  -----------------------------------------------------------------------------
  -- PC Calc + fetch opcode
  -----------------------------------------------------------------------------
PROCESS (clk, IPL, setstate, state, exec_write_back, set_direct_data, next_micro_state, stop, make_trace, make_berr, IPL_nr, FlagsSR, set_rot_cnt, opcode, writePCbig, set_exec, exec,
		 PC_dataa, PC_datab, setnextpass, last_data_read, TG68_PC_brw, TG68_PC_word, Z_error, trap_trap, trap_trapv, interrupt, tmp_TG68_PC, TG68_PC)
  begin
	PC_dataa <= TG68_PC;
	if TG68_PC_brw = '1' then
	  PC_dataa <= tmp_TG68_PC;
	end if;

	PC_datab(2 downto 0) <= (others => '0');
	PC_datab(3) <= PC_datab(2);
	PC_datab( 7 downto  4) <= (others => PC_datab(3));
	PC_datab(15 downto  8) <= (others => PC_datab(7));
	PC_datab(31 downto 16) <= (others => PC_datab(15));

	if interrupt = '1' then
	  PC_datab(2 downto 1) <= "11";
	end if;
	if exec(writePC_add) = '1' then
	  if writePCbig = '1' then
		PC_datab(3) <= '1';
		PC_datab(1) <= '1';
	  else
		PC_datab(2) <= '1';
	  end if;
	  if trap_trap = '1' or trap_trapv = '1' or exec(trap_chk) = '1' or Z_error = '1' then
		PC_datab(1) <= '1';
	  end if;
	elsif state = "00" then
	  PC_datab(1) <= '1';
	end if;

	if TG68_PC_brw = '1' then
	  if TG68_PC_word = '1' then
		PC_datab <= last_data_read;
	  else
		PC_datab(7 downto 0) <= opcode(7 downto 0);
	  end if;
	end if;

	TG68_PC_add <= PC_dataa + PC_datab;

	setopcode <= '0';
	setendOPC <= '0';
	setinterrupt <= '0';
	if setstate = "00" and next_micro_state = idle and setnextpass = '0' and (exec_write_back = '0' or state = "11") and set_rot_cnt = "000001" and set_exec(opcCHK) = '0' then
	  setendOPC <= '1';
	  if FlagsSR(2 downto 0)<IPL_nr or IPL_nr="111"  or make_trace='1'  or make_berr='1' then
		setinterrupt <= '1';
	  elsif stop = '0' then
		setopcode <= '1';
	  end if;
	end if;
	setexecOPC <= '0';
	if setstate = "00" and next_micro_state = idle and set_direct_data = '0' and (exec_write_back = '0' or state = "10") then
	  setexecOPC <= '1';
	end if;

	IPL_nr <= not IPL;
	if rising_edge(clk) then
	  if Reset = '1' then
		state <= "01";
		opcode <= X"2E79"; --move $0,a7
		trap_interrupt <= '0';
		interrupt <= '0';
		last_opc_read <= X"4EF9"; --jmp nn.l
		TG68_PC <= X"00000004";
		decodeOPC <= '0';
		endOPC <= '0';
		TG68_PC_word <= '0';
		execOPC <= '0';
		stop <= '0';
		rot_cnt <= "000001";
		byte <= '0';
		-- IPL_nr <= "000";
		trap_trace <= '0';
								trap_berr <= '0';
		writePCbig <= '0';
		-- recall_last <= '0';
		Suppress_Base <= '0';
		memmask <= "111111";
	  else
		-- IPL_nr <= not IPL;
		if clkena_in = '1' then
		  -- MIKEJ
		  memmask <= memmask(3 downto 0) & "11";
		  memread <= memread(1 downto 0) & memmaskmux(5 downto 4);
		  -- if wbmemmask(5 downto 4)="11" then
		  -- wbmemmask <= memmask;
		  -- end if;
		  if exec(directPC) = '1' then
			TG68_PC <= data_read;
		  elsif exec(ea_to_pc) = '1' then
			TG68_PC <= addr;
		  elsif (state = "00" or TG68_PC_brw = '1') and stop = '0' then
			TG68_PC <= TG68_PC_add;
		  end if;
		end if;

		if clkena_lw = '1' then
		  interrupt <= setinterrupt;
		  decodeOPC <= setopcode;
		  endOPC <= setendOPC;
		  execOPC <= setexecOPC;

		  exe_datatype <= set_datatype;
		  exe_opcode <= opcode;

		  if trap_berr = '0' then
			make_berr <= (berr or make_berr);
		  else
			make_berr <= '0';
		  end if;

		  stop <= set_stop or (stop and not setinterrupt);
		  if setinterrupt = '1' then
						make_berr <= '0';
						trap_berr <= '0';
			if make_trace = '1' then
			  trap_trace <= '1';
						elsif make_berr='1' THEN
							trap_berr <= '1';
			else
			  rIPL_nr <= IPL_nr;
			  IPL_vec <= "00011" & IPL_nr; -- TH
			  trap_interrupt <= '1';
			end if;
		  end if;
		  if micro_state = trap0 and IPL_autovector = '0' then
			IPL_vec <= last_data_read(7 downto 0); -- TH
		  end if;
		  if state = "00" then
			last_opc_read <= data_read(15 downto 0);
						last_opc_pc <= tg68_pc;
		  end if;
		  if setopcode = '1' then
			trap_interrupt <= '0';
			trap_trace <= '0';
			TG68_PC_word <= '0';
												trap_berr <= '0';
		  elsif opcode(7 downto 0) = "00000000" or opcode(7 downto 0) = "11111111" or data_is_source = '1' then
			TG68_PC_word <= '1';
		  end if;

		  if exec(get_bfoffset) = '1' then
			alu_bf_width <= bf_width;
			alu_bf_loffset <= bf_loffset;
			alu_bf_offset <= bf_offset;
		  end if;
		  byte <= '0';
		  memread <= "1111";
		  FC(1) <= not setstate(1) or (PCbase and not setstate(0));
		  FC(0) <= setstate(1) and (not PCbase or setstate(0));
		  if interrupt = '1' then
			FC(1 downto 0) <= "11";
		  end if;

		  if (state = "10" and write_back = '1' and setstate /= "10") or set_rot_cnt /= "000001" or (stop = '1' and interrupt = '0') or set_exec(opcCHK) = '1' then
			state <= "01";
			memmask <= "111111";
		  elsif execOPC = '1' and exec_write_back = '1' then
			state <= "11";
			FC(1 downto 0) <= "01";
			memmask <= wbmemmask;
			if datatype = "00" then
			  byte <= '1';
			end if;
		  else
			state <= setstate;
			if setstate = "01" then
			  memmask <= "111111";
			  wbmemmask <= "111111";
			elsif exec(get_bfoffset) = '1' then
			  memmask <= set_memmask;
			  wbmemmask <= set_memmask;
			  oddout <= set_oddout;
			elsif set(longaktion) = '1' then
			  memmask <= "100001";
			  wbmemmask <= "100001";
			  oddout <= '0';
			elsif set_datatype = "00" and setstate(1) = '1' then
			  memmask <= "101111";
			  wbmemmask <= "101111";
			  if set(mem_byte) = '1' then
				oddout <= '0';
			  else
				oddout <= '1';
			  end if;
			else
			  memmask <= "100111";
			  wbmemmask <= "100111";
			  oddout <= '0';
			end if;
		  end if;

		  if decodeOPC = '1' then
			rot_bits <= set_rot_bits;
			writePCbig <= '0';
		  else
			writePCbig <= set_writePCbig or writePCbig;
		  end if;
		  if decodeOPC = '1' or exec(ld_rot_cnt) = '1' or rot_cnt /= "000001" then
			rot_cnt <= set_rot_cnt;
		  end if;
		  if setstate(1) = '1' and set_datatype = "00" then
			byte <= '1';
		  end if;

		  if set_Suppress_Base = '1' then
			Suppress_Base <= '1';
		  elsif setstate(1) = '1' or (ea_only = '1' and set(get_ea_now) = '1') then
			Suppress_Base <= '0';
		  end if;
		  if getbrief = '1' then
			if state(1) = '1' then
			  brief <= last_opc_read(15 downto 0);
			else
			  brief <= data_read(15 downto 0);
			end if;
		  end if;

		  if setopcode='1' and berr='0' then
			if state = "00" then
			  opcode <= data_read(15 downto 0);
														exe_pc <= tg68_pc;
			else
			  opcode <= last_opc_read(15 downto 0);
														exe_pc <= last_opc_pc;
			end if;
			nextpass <= '0';

		  elsif setinterrupt = '1' then
			opcode(15 downto 12) <= X"7"; --moveq
			opcode(8 downto 6) <= "001"; --word
			nextpass <= '0';
		  else
			-- if setnextpass='1' or (regdirectsource='1' and state="00") then
			if setnextpass = '1' or regdirectsource = '1' then
			  nextpass <= '1';
			end if;
		  end if;

		  if decodeOPC = '1' or interrupt = '1' then
			trap_SR <= FlagsSR;
		  end if;
		end if;
	  end if;
	end if;

	if rising_edge(clk) then
	  if Reset = '1' then
		PCbase <= '1';
	  elsif clkena_lw = '1' then
		PCbase <= set_PCbase or PCbase;
		if setexecOPC = '1' or (state(1) = '1' and movem_run = '0') then
		  PCbase <= '0';
		end if;
	  end if;
	  if clkena_lw = '1' then
		exec <= set;
		exec_tas <= '0';
		exec(subidx) <= set(presub) or set(subidx);
		if setexecOPC = '1' then
		  exec <= set_exec or set;
		  exec_tas <= set_exec_tas;
		end if;
		exec(get_2ndOPC) <= set(get_2ndOPC) or setopcode;
	  end if;
	end if;

  end process;

  ------------------------------------------------------------------------------
  --prepare Bitfield Parameters
  ------------------------------------------------------------------------------
  process (clk, Reset, sndOPC, reg_QA, reg_QB, bf_width, bf_offset, bf_offset_l, bf_bhits, opcode, setstate)
  begin
        -- the ALU needs the full real offset to return the correct result for
        -- bfffo
	if sndOPC(11) = '1' then
	  bf_offset <= reg_QA;
	else 
          bf_offset <= (others => '0');
	  bf_offset(4 downto 0) <= sndOPC(10 downto 6);
	end if;
        -- offset within long word
	bf_offset_l <= bf_offset(4 downto 0);

	if sndOPC(5) = '1' then
	  bf_width <= reg_QB(4 downto 0) - 1;
	else
	  bf_width <= sndOPC(4 downto 0) - 1;
	end if;
        
	bf_bhits <= ('0' & bf_width) + ('0' & bf_offset_l);
	set_oddout <= not bf_bhits(3);

        bf_loffset <= 31 - bf_bhits(4 downto 0);
        if opcode(4 downto 3) /= "00" then
          -- memory is being read with byte precision, thus offset
          -- bit 2:0 are only used in the alu
          bf_loffset(4 downto 3) <= "00";
	  bf_offset_l(4 downto 3) <= "00";
        end if;
        
	case bf_bhits(5 downto 3) is
	  when "000" =>
		set_memmask <= "101111";
	  when "001" =>
		set_memmask <= "100111";
	  when "010" =>
		set_memmask <= "100011";
	  when "011" =>
		set_memmask <= "100001";
	  when others =>
		set_memmask <= "100000";
	end case;
	if setstate = "00" then
	  set_memmask <= "100111";
	end if;

  end process;

  ------------------------------------------------------------------------------
  --SR op
  ------------------------------------------------------------------------------
  process (clk, Reset, FlagsSR, last_data_read, OP2out, exec)
  begin
	if exec(andisR) = '1' then
	  SRin <= FlagsSR and last_data_read(15 downto 8);
	elsif exec(eorisR) = '1' then
	  SRin <= FlagsSR Xor last_data_read(15 downto 8);
	elsif exec(orisR) = '1' then
	  SRin <= FlagsSR or last_data_read(15 downto 8);
	else
	  SRin <= OP2out(15 downto 8);
	end if;

	if rising_edge(clk) then
	  if Reset = '1' then
		FlagsSR(5) <= '1';
		FlagsSR(2 downto 0) <= "111";
		FC(2) <= '1';
		SVmode <= '1';
		preSVmode <= '1';
		make_trace <= '0';
	  elsif clkena_lw = '1' then
		if setopcode = '1' then
		  make_trace <= FlagsSR(7);
		  if set(changeMode) = '1' then
			SVmode <= not SVmode;
		  else
			SVmode <= preSVmode;
		  end if;
		end if;
		if set(changeMode) = '1' then
		  preSVmode <= not preSVmode;
		  FlagsSR(5) <= not preSVmode;
		  FC(2) <= not preSVmode;
		end if;
		if micro_state = trap3 then
		  FlagsSR(7) <= '0';
		end if;
		if trap_trace = '1' and state = "10" then
		  make_trace <= '0';
		end if;
		if exec(directSR) = '1' or set_stop = '1' then
		  FlagsSR <= data_read(15 downto 8);
		end if;
		if interrupt = '1' and trap_interrupt = '1' then
		  FlagsSR(2 downto 0) <= rIPL_nr;
		end if;
		-- if exec(to_CCR)='1' and exec(to_SR)='1' then
		if exec(to_SR) = '1' then
		  FlagsSR(7 downto 0) <= SRin; --SR
		  FC(2) <= SRin(5);
		  -- end if;
		elsif exec(update_FC) = '1' then
		  FC(2) <= FlagsSR(5);
		end if;
		if interrupt = '1' then
		  FC(2) <= '1';
		end if;
	  end if;
	end if;
  end process;

  -----------------------------------------------------------------------------
  -- decode opcode
  -----------------------------------------------------------------------------
  process(clk, cpu, OP1out, OP2out, opcode, exe_condition, nextpass, micro_state, decodeOPC, state, setexecOPC, Flags, FlagsSR, direct_data, build_logical,
	build_bcd, set_Z_error, trapd, movem_run, last_data_read, set, set_V_Flag, z_error, trap_trace, trap_interrupt,
	SVmode, preSVmode, stop, long_done, ea_only, setstate, execOPC, exec_write_back, exe_datatype,
	datatype, interrupt, c_out, trapmake, rot_cnt, brief, addr,
	long_start, set_datatype, sndOPC, set_exec, exec, ea_build_now, reg_QA, reg_QB, make_berr, trap_berr)
  begin
	TG68_PC_brw        <= '0';
	setstate           <= "00";
	Regwrena_now       <= '0';
	movem_presub       <= '0';
	setnextpass        <= '0';
	regdirectsource    <= '0';
	setdisp            <= '0';
	setdispbyte        <= '0';
	getbrief           <= '0';
	dest_areg          <= '0';
	source_areg        <= '0';
	data_is_source     <= '0';
	write_back         <= '0';
	setstackaddr       <= '0';
	writePC            <= '0';
	ea_build_now       <= '0';
	set_rot_bits       <= "XX";
	set_rot_cnt        <= "000001";
	dest_hbits         <= '0';
	source_lowbits     <= '0';
	source_2ndHbits    <= '0';
	source_2ndLbits    <= '0';
	dest_2ndHbits      <= '0';
	ea_only            <= '0';
	set_direct_data    <= '0';
	set_exec_tas       <= '0';
	trap_illegal       <= '0';
	trap_addr_error    <= '0';
	trap_priv          <= '0';
	trap_1010          <= '0';
	trap_1111          <= '0';
	trap_trap          <= '0';
	trap_trapv         <= '0';
	trapmake           <= '0';
	set_vectoraddr     <= '0';
	writeSR            <= '0';
	set_stop           <= '0';
	illegal_write_mode <= '0';
	illegal_read_mode  <= '0';
	illegal_byteaddr   <= '0';
	set_Z_error        <= '0';

	next_micro_state   <= idle;
	build_logical      <= '0';
	build_bcd          <= '0';
	skipFetch          <= make_berr;
	set_writePCbig     <= '0';
	--                 set_recall_last <= '0';
	set_Suppress_Base  <= '0';
	set_PCbase         <= '0';

	if rot_cnt /= "000001" then
	  set_rot_cnt <= rot_cnt - 1;
	end if;
	set_datatype <= datatype;

	set <= (others => '0');
	set_exec <= (others => '0');
	set(update_ld) <= '0';
	-- odd_start <= '0';
	------------------------------------------------------------------------------
	--Sourcepass
	------------------------------------------------------------------------------
	case opcode(7 downto 6) is
	  when "00" => datatype <= "00"; --Byte
	  when "01" => datatype <= "01"; --Word
	  when others => datatype <= "10"; --Long
	end case;

	if trapmake = '1' and trapd = '0' then
	  next_micro_state <= trap0;
	  if VBR_Stackframe = 0 or (cpu(0) = '0' and VBR_Stackframe = 2) then
		set(writePC_add) <= '1';
		-- set_datatype <= "10";
	  end if;
	  if preSVmode = '0' then
		set(changeMode) <= '1';
	  end if;
	  setstate <= "01";
	end if;

	if interrupt='1' and trap_berr='1' THEN
	  next_micro_state <= trap0;
	  if preSVmode='0' THEN
		set(changeMode) <= '1';
	  end if;
	  setstate <= "01";
	end if;

	if micro_state = int1 or (interrupt = '1' and trap_trace = '1') then
						if trap_trace='1' AND (VBR_Stackframe=1 or (cpu(0)='1' AND VBR_Stackframe=2)) then
						  next_micro_state <= trap00;  --TH
						else
	  next_micro_state <= trap0;
						end if;
	  -- if cpu(0)='0' then
	  -- set_datatype <= "10";
	  -- end if;
	  if preSVmode = '0' then
		set(changeMode) <= '1';
	  end if;
	  setstate <= "01";
	end if;

	if setexecOPC = '1' and FlagsSR(5) /= preSVmode then
	  set(changeMode) <= '1';
	  -- setstate <= "01";
	  -- next_micro_state <= nop;
	end if;

	if interrupt = '1' and trap_interrupt = '1' then
	  -- skipFetch <= '1';
	  next_micro_state <= int1;
	  set(update_ld) <= '1';
	  setstate <= "10";
	end if;

	if set(changeMode) = '1' then
	  set(to_USP) <= '1';
	  set(from_USP) <= '1';
	  setstackaddr <= '1';
	end if;

	if ea_only = '0' and set(get_ea_now) = '1' then
	  setstate <= "10";
	  -- set_recall_last <= '1';
	  -- set(update_ld) <= '0';
	end if;

	if setstate(1) = '1' and set_datatype(1) = '1' then
	  set(longaktion) <= '1';
	end if;

	if (ea_build_now = '1' and decodeOPC = '1') or exec(ea_build) = '1' then
	  case opcode(5 downto 3) is --source
		when "010" | "011" | "100" => -- -(An)+
		  set(get_ea_now) <= '1';
		  setnextpass <= '1';
		  if opcode(3) = '1' then --(An)+
			set(postadd) <= '1';
			if opcode(2 downto 0) = "111" then
			  set(use_SP) <= '1';
			end if;
		  end if;
		  if opcode(5) = '1' then -- -(An)
			set(presub) <= '1';
			if opcode(2 downto 0) = "111" then
			  set(use_SP) <= '1';
			end if;
		  end if;
		when "101" => --(d16,An)
		  next_micro_state <= ld_dAn1;
		when "110" => --(d8,An,Xn)
		  next_micro_state <= ld_AnXn1;
		  getbrief <= '1';
		when "111" =>
		  case opcode(2 downto 0) is
			when "000" => --(xxxx).w
			  next_micro_state <= ld_nn;
			when "001" => --(xxxx).l
			  set(longaktion) <= '1';
			  next_micro_state <= ld_nn;
			when "010" => --(d16,PC)
			  next_micro_state <= ld_dAn1;
			  set(dispouter) <= '1';
			  set_Suppress_Base <= '1';
			  set_PCbase <= '1';
			when "011" => --(d8,PC,Xn)
			  next_micro_state <= ld_AnXn1;
			  getbrief <= '1';
			  set(dispouter) <= '1';
			  set_Suppress_Base <= '1';
			  set_PCbase <= '1';
			when "100" => --#data
			  setnextpass <= '1';
			  set_direct_data <= '1';
			  if datatype = "10" then
				set(longaktion) <= '1';
			  end if;
			when others => NULL;
		  end case;
		when others => NULL;
	  end case;
	end if;

	------------------------------------------------------------------------------
	--prepere opcode
	------------------------------------------------------------------------------
	case opcode(15 downto 12) is
	  -- 0000 ----------------------------------------------------------------------------
	  when "0000" =>
		if opcode(8) = '1' and opcode(5 downto 3) = "001" then --movep
		  datatype <= "00"; --Byte
		  set(use_SP) <= '1'; --addr+2
		  set(no_Flags) <= '1';
		  if opcode(7) = '0' then --to register
			set_exec(Regwrena) <= '1';
			set_exec(opcMOVE) <= '1';
			set(movepl) <= '1';
		  end if;
		  if decodeOPC = '1' then
			if opcode(6) = '1' then
			  set(movepl) <= '1';
			end if;
			if opcode(7) = '0' then
			  set_direct_data <= '1'; -- to register
			end if;
			next_micro_state <= movep1;
		  end if;
		  if setexecOPC = '1' then
			dest_hbits <= '1';
		  end if;
		else
		  if opcode(8) = '1' or opcode(11 downto 9) = "100" then --Bits
			set_exec(opcBITS) <= '1';
			set_exec(ea_data_OP1) <= '1';
			if opcode(7 downto 6) /= "00" then
			  if opcode(5 downto 4) = "00" then
				set_exec(Regwrena) <= '1';
			  end if;
			  write_back <= '1';
			end if;
			if opcode(5 downto 4) = "00" then
			  datatype <= "10"; --Long
			else
			  datatype <= "00"; --Byte
			end if;
			if opcode(8) = '0' then
			  if decodeOPC = '1' then
				next_micro_state <= nop;
				set(get_2ndOPC) <= '1';
				set(ea_build) <= '1';
			  end if;
			else
			  ea_build_now <= '1';
			end if;
		  elsif opcode(11 downto 9) = "111" then --MOVES not in 68000
			trap_illegal <= '1';
			-- trap_addr_error <= '1';
			trapmake <= '1';
		  else --andi, ...xxxi
			if opcode(11 downto 9) = "000" then --orI
			  set_exec(opcor) <= '1';
			end if;
			if opcode(11 downto 9) = "001" then --andI
			  set_exec(opcand) <= '1';
			end if;
			if opcode(11 downto 9) = "010" or opcode(11 downto 9) = "011" then --SUBI, ADDI
			  set_exec(opcADD) <= '1';
			end if;
			if opcode(11 downto 9) = "101" then --EorI
			  set_exec(opcEor) <= '1';
			end if;
			if opcode(11 downto 9) = "110" then --CMPI
			  set_exec(opcCMP) <= '1';
			end if;
			if opcode(7) = '0' and opcode(5 downto 0) = "111100" and (set_exec(opcand) or set_exec(opcor) or set_exec(opcEor)) = '1' then --SR
			  if decodeOPC = '1' and SVmode = '0' and opcode(6) = '1' then --SR
				trap_priv <= '1';
				trapmake <= '1';
			  else
				set(no_Flags) <= '1';
				if decodeOPC = '1' then
				  if opcode(6) = '1' then
					set(to_SR) <= '1';
				  end if;
				  set(to_CCR) <= '1';
				  set(andisR) <= set_exec(opcand);
				  set(eorisR) <= set_exec(opcEor);
				  set(orisR) <= set_exec(opcor);
				  setstate <= "01";
				  next_micro_state <= nopnop;
				end if;
			  end if;
			else
			  if decodeOPC = '1' then
				next_micro_state <= andi;
				set(ea_build) <= '1';
				set_direct_data <= '1';
				if datatype = "10" then
				  set(longaktion) <= '1';
				end if;
			  end if;
			  if opcode(5 downto 4) /= "00" then
				set_exec(ea_data_OP1) <= '1';
			  end if;
			  if opcode(11 downto 9) /= "110" then --CMPI
				if opcode(5 downto 4) = "00" then
				  set_exec(Regwrena) <= '1';
				end if;
				write_back <= '1';
			  end if;
			  if opcode(10 downto 9) = "10" then --CMPI, SUBI
				set(addsub) <= '1';
			  end if;
			end if;
		  end if;
		end if;

		-- 0001, 0010, 0011 -----------------------------------------------------------------
	  when "0001" | "0010" | "0011" => --move.b, move.l, move.w
		set_exec(opcMOVE) <= '1';
		ea_build_now <= '1';
		if opcode(8 downto 6) = "001" then
		  set(no_Flags) <= '1';
		end if;
		if opcode(5 downto 4) = "00" then --Dn, An
		  if opcode(8 downto 7) = "00" then
			set_exec(Regwrena) <= '1';
		  end if;
		end if;
		case opcode(13 downto 12) is
		  when "01" => datatype <= "00"; --Byte
		  when "10" => datatype <= "10"; --Long
		  when others => datatype <= "01"; --Word
		end case;
		source_lowbits <= '1'; -- Dn=> An=>
		if opcode(3) = '1' then
		  source_areg <= '1';
		end if;

		if nextpass = '1' or opcode(5 downto 4) = "00" then
		  dest_hbits <= '1';
		  if opcode(8 downto 6) /= "000" then
			dest_areg <= '1';
		  end if;
		end if;
		-- if setstate="10" then
		-- set(update_ld) <= '0';
		-- end if;
		--
		if micro_state = idle and (nextpass = '1' or (opcode(5 downto 4) = "00" and decodeOPC = '1')) then
		  case opcode(8 downto 6) is --destination
			when "000" | "001" => --Dn,An
			  set_exec(Regwrena) <= '1';
			when "010" | "011" | "100" => --destination -(an)+
			  if opcode(6) = '1' then --(An)+
				set(postadd) <= '1';
				if opcode(11 downto 9) = "111" then
				  set(use_SP) <= '1';
				end if;
			  end if;
			  if opcode(8) = '1' then -- -(An)
				set(presub) <= '1';
				if opcode(11 downto 9) = "111" then
				  set(use_SP) <= '1';
				end if;
			  end if;
			  setstate <= "11";
			  next_micro_state <= nop;
			  if nextpass = '0' then
				set(write_reg) <= '1';
			  end if;
			when "101" => --(d16,An)
			  next_micro_state <= st_dAn1;
			  -- getbrief <= '1';
			when "110" => --(d8,An,Xn)
			  next_micro_state <= st_AnXn1;
			  getbrief <= '1';
			when "111" =>
			  case opcode(11 downto 9) is
				when "000" => --(xxxx).w
				  next_micro_state <= st_nn;
				when "001" => --(xxxx).l
				  set(longaktion) <= '1';
				  next_micro_state <= st_nn;
				when others => NULL;
			  end case;
			when others => NULL;
		  end case;
		end if;
		---- 0100 ----------------------------------------------------------------------------
	  when "0100" => --rts_group
		if opcode(8) = '1' then --lea
		  if opcode(6) = '1' then --lea
			if opcode(7) = '1' then
			  source_lowbits <= '1';
			  -- if opcode(5 downto 3)="000" and opcode(10)='0' then --ext
			  if opcode(5 downto 4) = "00" then --extb.l
				set_exec(opcEXT) <= '1';
				set_exec(opcMOVE) <= '1';
				set_exec(Regwrena) <= '1';
				-- if opcode(6)='0' then
				-- datatype <= "01"; --WorD
				-- end if;
			  else
				source_areg <= '1';
				ea_only <= '1';
				set_exec(Regwrena) <= '1';
				set_exec(opcMOVE) <= '1';
				set(no_Flags) <= '1';
				if opcode(5 downto 3) = "010" then --lea (Am),An
				  dest_areg <= '1';
				  dest_hbits <= '1';
				else
				  ea_build_now <= '1';
				end if;
				if set(get_ea_now) = '1' then
				  setstate <= "01";
				  set_direct_data <= '1';
				end if;
				if setexecOPC = '1' then
				  dest_areg <= '1';
				  dest_hbits <= '1';
				end if;
			  end if;
			else
			  trap_illegal <= '1';
			  trapmake <= '1';
			end if;
		  else --chk
						IF opcode(7)='1' AND opcode(5 downto 0) /= "111111" THEN
			  datatype <= "01"; --Word
			  set(trap_chk) <= '1';
			  if (c_out(1) = '0' or OP1out(15) = '1' or OP2out(15) = '1') and exec(opcCHK) = '1' then
				trapmake <= '1';
			  end if;
			elsif cpu(1) = '1' then --chk long for 68020
			  datatype <= "10"; --Long
			  set(trap_chk) <= '1';
			  if (c_out(2) = '1' or OP1out(31) = '1' or OP2out(31) = '1') and exec(opcCHK) = '1' then
				trapmake <= '1';
			  end if;
			else
			  trap_illegal <= '1'; -- chk long for 68020
			  trapmake <= '1';
			end if;
			if opcode(7) = '1' or cpu(1) = '1' then
			  if (nextpass = '1' or opcode(5 downto 4) = "00") and exec(opcCHK) = '0' and micro_state = idle then
				set_exec(opcCHK) <= '1';
			  end if;
			  ea_build_now <= '1';
			  set(addsub) <= '1';
			  if setexecOPC = '1' then
				dest_hbits <= '1';
				source_lowbits <= '1';
			  end if;
			end if;
		  end if;
		else
		  case opcode(11 downto 9) is
			when "000" =>
			  if opcode(7 downto 6) = "11" then --move from SR
				if SR_Read = 0 or (cpu(0) = '0' and SR_Read = 2) or SVmode = '1' then
				  -- if SVmode='1' then
				  ea_build_now <= '1';
				  set_exec(opcMOVESR) <= '1';
				  datatype <= "01";
				  write_back <= '1'; -- 68000 also reads first
				  if cpu(0) = '1' and state = "10" then
					skipFetch <= '1';
				  end if;
				  if opcode(5 downto 4) = "00" then
					set_exec(Regwrena) <= '1';
				  end if;
				else
				  trap_priv <= '1';
				  trapmake <= '1';
				end if;
			  else --negx
				ea_build_now <= '1';
				set_exec(use_XZFlag) <= '1';
				write_back <= '1';
				set_exec(opcADD) <= '1';
				set(addsub) <= '1';
				source_lowbits <= '1';
				if opcode(5 downto 4) = "00" then
				  set_exec(Regwrena) <= '1';
				end if;
				if setexecOPC = '1' then
				  set(OP1out_zero) <= '1';
				end if;
			  end if;
			when "001" =>
			  if opcode(7 downto 6) = "11" then --move from CCR 68010
				if SR_Read = 1 or (cpu(0) = '1' and SR_Read = 2) then
				  ea_build_now <= '1';
				  set_exec(opcMOVECCR) <= '1';
				  --datatype <= "00"; -- WRONG, should be WORD zero extended.
				  datatype <= "01"; -- WRONG, should be WORD zero extended.
				  write_back <= '1'; -- 68000 also reads first
				  if opcode(5 downto 4) = "00" then
					set_exec(Regwrena) <= '1';
				  end if;
				else
				  trap_illegal <= '1';
				  trapmake <= '1';
				end if;
			  else --clr
				ea_build_now <= '1';
				write_back <= '1';
				set_exec(opcand) <= '1';
				if cpu(0) = '1' and state = "10" then
				  skipFetch <= '1';
				end if;
				if setexecOPC = '1' then
				  set(OP1out_zero) <= '1';
				end if;
				if opcode(5 downto 4) = "00" then
				  set_exec(Regwrena) <= '1';
				end if;
			  end if;
			when "010" =>
			  ea_build_now <= '1';
			  if opcode(7 downto 6) = "11" then --move to CCR
				datatype <= "01";
				source_lowbits <= '1';
				if (decodeOPC = '1' and opcode(5 downto 4) = "00") or state = "10" or direct_data = '1' then
				  set(to_CCR) <= '1';
				end if;
			  else --neg
				write_back <= '1';
				set_exec(opcADD) <= '1';
				set(addsub) <= '1';
				source_lowbits <= '1';
				if opcode(5 downto 4) = "00" then
				  set_exec(Regwrena) <= '1';
				end if;
				if setexecOPC = '1' then
				  set(OP1out_zero) <= '1';
				end if;
			  end if;
			when "011" => --not, move toSR
			  if opcode(7 downto 6) = "11" then --move to SR
				if SVmode = '1' then
				  ea_build_now <= '1';
				  datatype <= "01";
				  source_lowbits <= '1';
				  if (decodeOPC = '1' and opcode(5 downto 4) = "00") or state = "10" or direct_data = '1' then
					set(to_SR) <= '1';
					set(to_CCR) <= '1';
				  end if;
				  if exec(to_SR) = '1' or (decodeOPC = '1' and opcode(5 downto 4) = "00") or state = "10" or direct_data = '1' then
					setstate <= "01";
				  end if;
				else
				  trap_priv <= '1';
				  trapmake <= '1';
				end if;
			  else --not
				ea_build_now <= '1';
				write_back <= '1';
				set_exec(opcEor) <= '1';
				set_exec(ea_data_OP1) <= '1';
				if opcode(5 downto 3) = "000" then
				  set_exec(Regwrena) <= '1';
				end if;
				if setexecOPC = '1' then
				  set(OP2out_one) <= '1';
				end if;
			  end if;
			when "100" | "110" =>
			  if opcode(7) = '1' then --movem, ext
				if opcode(5 downto 3) = "000" and opcode(10) = '0' then --ext
				  source_lowbits <= '1';
				  set_exec(opcEXT) <= '1';
				  set_exec(opcMOVE) <= '1';
				  set_exec(Regwrena) <= '1';
				  if opcode(6) = '0' then
					datatype <= "01"; --WorD
				  end if;
				else --movem
				  -- if opcode(11 downto 7)="10001" or opcode(11 downto 7)="11001" then --MOVEM
				  ea_only <= '1';
				  set(no_Flags) <= '1';
				  if opcode(6) = '0' then
					datatype <= "01"; --Word transfer
				  end if;
				  if (opcode(5 downto 3) = "100" or opcode(5 downto 3) = "011") and state = "01" then -- -(An), (An)+
					set_exec(save_memaddr) <= '1';
					set_exec(Regwrena) <= '1';
				  end if;
				  if opcode(5 downto 3) = "100" then -- -(An)
					movem_presub <= '1';
					set(subidx) <= '1';
				  end if;
				  if state = "10" then
					set(Regwrena) <= '1';
					set(opcMOVE) <= '1';
				  end if;
				  if decodeOPC = '1' then
					set(get_2ndOPC) <= '1';
					if opcode(5 downto 3) = "010" or opcode(5 downto 3) = "011" or opcode(5 downto 3) = "100" then
					  next_micro_state <= movem1;
					else
					  next_micro_state <= nop;
					  set(ea_build) <= '1';
					end if;
				  end if;
				  if set(get_ea_now) = '1' then
					if movem_run = '1' then
					  set(movem_action) <= '1';
					  if opcode(10) = '0' then
						setstate <= "11";
						set(write_reg) <= '1';
					  else
						setstate <= "10";
					  end if;
					  next_micro_state <= movem2;
					  set(mem_addsub) <= '1';
					else
					  setstate <= "01";
					end if;
				  end if;
				end if;
			  else
				if opcode(10) = '1' then --MUL.L, DIV.L 68020
				  -- if cpu(1)='1' then
				  if (opcode(6) = '1' and (DIV_Mode = 1 or (cpu(1) = '1' and DIV_Mode = 2))) or
				   (opcode(6) = '0' and (MUL_Mode = 1 or (cpu(1) = '1' and MUL_Mode = 2))) then
					if decodeOPC = '1' then
					  next_micro_state <= nop;
					  set(get_2ndOPC) <= '1';
					  set(ea_build) <= '1';
					end if;
					if (micro_state = idle and nextpass = '1') or (opcode(5 downto 4) = "00" and exec(ea_build) = '1') then
					  setstate <= "01";
					  dest_2ndHbits <= '1';
					  source_2ndLbits <= '1';
					  if opcode(6) = '1' then
						next_micro_state <= div1;
					  else
						next_micro_state <= mul1;
						set(ld_rot_cnt) <= '1';
					  end if;
					end if;
					if z_error = '0' and set_V_Flag = '0' and set(opcDIVU) = '1' then
					  set(Regwrena) <= '1';
					end if;
					source_lowbits <= '1';
					if nextpass = '1' or (opcode(5 downto 4) = "00" and decodeOPC = '1') then
					  dest_hbits <= '1';
					end if;
					datatype <= "10";
				  else
					trap_illegal <= '1';
					trapmake <= '1';
				  end if;

				else --pea, swap
				  if opcode(6) = '1' then
					datatype <= "10";
					if opcode(5 downto 3) = "000" then --swap
					  set_exec(opcSWAP) <= '1';
					  set_exec(Regwrena) <= '1';
					elsif opcode(5 downto 3) = "001" then --bkpt

					else --pea
					  ea_only <= '1';
					  ea_build_now <= '1';
					  if nextpass = '1' and micro_state = idle then
						set(presub) <= '1';
						setstackaddr <= '1';
						setstate <= "11";
						next_micro_state <= nop;
					  end if;
					  if set(get_ea_now) = '1' then
						setstate <= "01";
					  end if;
					end if;
				  else
					if opcode(5 downto 3) = "001" then --link.l
					  datatype <= "10";
					  set_exec(opcADD) <= '1'; --for displacement
					  set_exec(Regwrena) <= '1';
					  set(no_Flags) <= '1';
					  if decodeOPC = '1' then
						set(linksp) <= '1';
						set(longaktion) <= '1';
						next_micro_state <= link1;
						set(presub) <= '1';
						setstackaddr <= '1';
						set(mem_addsub) <= '1';
						source_lowbits <= '1';
						source_areg <= '1';
						set(store_ea_data) <= '1';
					  end if;
					else --nbcd
					  ea_build_now <= '1';
					  set_exec(use_XZFlag) <= '1';
					  write_back <= '1';
					  set_exec(opcADD) <= '1';
					  set_exec(opcSBCD) <= '1';
					  source_lowbits <= '1';
					  if opcode(5 downto 4) = "00" then
						set_exec(Regwrena) <= '1';
					  end if;
					  if setexecOPC = '1' then
						set(OP1out_zero) <= '1';
					  end if;
					end if;
				  end if;
				end if;
			  end if;
			  --
			when "101" => --tst, tas 4aFC - illegal
			  if opcode(7 downto 2) = "111111" then --illegal
				trap_illegal <= '1';
				trapmake <= '1';
			  else
				ea_build_now <= '1';
				if setexecOPC = '1' then
				  source_lowbits <= '1';
				  if opcode(3) = '1' then --MC68020...
					source_areg <= '1';
				  end if;
				end if;
				set_exec(opcMOVE) <= '1';
				if opcode(7 downto 6) = "11" then --tas
				  set_exec_tas <= '1';
				  write_back <= '1';
				  datatype <= "00"; --Byte
				  if opcode(5 downto 4) = "00" then
					set_exec(Regwrena) <= '1';
				  end if;
				end if;
			  end if;
			  ---- when "110"=>
			when "111" => --4EXX
			  --
			  -- ea_only <= '1';
			  -- ea_build_now <= '1';
			  -- if nextpass='1' and micro_state=idle then
			  -- set(presub) <= '1';
			  -- setstackaddr <='1';
			  -- set(mem_addsub) <= '1';
			  -- setstate <="11";
			  -- next_micro_state <= nop;
			  -- end if;
			  -- if set(get_ea_now)='1' then
			  -- setstate <="01";
			  -- end if;
			  --

			  if opcode(7) = '1' then --jsr, jmp
				datatype <= "10";
				ea_only <= '1';
				ea_build_now <= '1';
				if exec(ea_to_pc) = '1' then
				  next_micro_state <= nop;
				end if;
				if nextpass = '1' and micro_state = idle and opcode(6) = '0' then
				  set(presub) <= '1';
				  setstackaddr <= '1';
				  setstate <= "11";
				  next_micro_state <= nopnop;
				end if;
				-- achtung buggefahr
				if micro_state = ld_AnXn1 and brief(8) = '0' then --JMP/JSR n(Ax,Dn)
				  skipFetch <= '1';
				end if;
				if state = "00" then
				  writePC <= '1';
				end if;
				set(hold_dwr) <= '1';
				if set(get_ea_now) = '1' then --jsr
				  if exec(longaktion) = '0' or long_done = '1' then
					skipFetch <= '1';
				  end if;
				  setstate <= "01";
				  set(ea_to_pc) <= '1';
				end if;
			  else --
				case opcode(6 downto 0) is
				  when "1000000" | "1000001" | "1000010" | "1000011" | "1000100" | "1000101" | "1000110" | "1000111" | --trap
					  "1001000" | "1001001" | "1001010" | "1001011" | "1001100" | "1001101" | "1001110" | "1001111" => --trap
					  trap_trap <= '1';
					trapmake <= '1';
				  when "1010000" | "1010001" | "1010010" | "1010011" | "1010100" | "1010101" | "1010110" | "1010111" => --link
					datatype <= "10";
					set_exec(opcADD) <= '1'; --for displacement
					set_exec(Regwrena) <= '1';
					set(no_Flags) <= '1';
					if decodeOPC = '1' then
					  next_micro_state <= link1;
					  set(presub) <= '1';
					  setstackaddr <= '1';
					  set(mem_addsub) <= '1';
					  source_lowbits <= '1';
					  source_areg <= '1';
					  set(store_ea_data) <= '1';
					end if;

				  when "1011000" | "1011001" | "1011010" | "1011011" | "1011100" | "1011101" | "1011110" | "1011111" => --unlink
					datatype <= "10";
					set_exec(Regwrena) <= '1';
					set_exec(opcMOVE) <= '1';
					set(no_Flags) <= '1';
					if decodeOPC = '1' then
					  setstate <= "01";
					  next_micro_state <= unlink1;
					  set(opcMOVE) <= '1';
					  set(Regwrena) <= '1';
					  setstackaddr <= '1';
					  source_lowbits <= '1';
					  source_areg <= '1';
					end if;

				  when "1100000" | "1100001" | "1100010" | "1100011" | "1100100" | "1100101" | "1100110" | "1100111" => --move An,USP
					if SVmode = '1' then
					  -- set(no_Flags) <= '1';
					  set(to_USP) <= '1';
					  source_lowbits <= '1';
					  source_areg <= '1';
					  datatype <= "10";
					else
					  trap_priv <= '1';
					  trapmake <= '1';
					end if;
				  when "1101000" | "1101001" | "1101010" | "1101011" | "1101100" | "1101101" | "1101110" | "1101111" => --move USP,An
					if SVmode = '1' then
					  -- set(no_Flags) <= '1';
					  set(from_USP) <= '1';
					  datatype <= "10";
					  set_exec(Regwrena) <= '1';
					else
					  trap_priv <= '1';
					  trapmake <= '1';
					end if;

				  when "1110000" => --reset
					if SVmode = '0' then
					  trap_priv <= '1';
					  trapmake <= '1';
					else
					  set(opcRESET) <= '1';
					  if decodeOPC = '1' then
						set(ld_rot_cnt) <= '1';
						set_rot_cnt <= "000000";
					  end if;
					end if;

				  when "1110001" => --nop

				  when "1110010" => --stop
					if SVmode = '0' then
					  trap_priv <= '1';
					  trapmake <= '1';
					else
					  if decodeOPC = '1' then
						setnextpass <= '1';
						set_stop <= '1';
					  end if;
					  if stop = '1' then
						skipFetch <= '1';
					  end if;

					end if;

				  when "1110011" | "1110111" => --rte/rtr
					if SVmode = '1' or opcode(2) = '1' then
					  if decodeOPC = '1' then
						setstate <= "10";
						set(postadd) <= '1';
						setstackaddr <= '1';
						if opcode(2) = '1' then
						  set(directCCR) <= '1';
						else
						  set(directSR) <= '1';
						end if;
						next_micro_state <= rte1;
					  end if;
					else
					  trap_priv <= '1';
					  trapmake <= '1';
					end if;

				  when "1110101" => --rts
					datatype <= "10";
					if decodeOPC = '1' then
					  setstate <= "10";
					  set(postadd) <= '1';
					  setstackaddr <= '1';
					  set(direct_delta) <= '1';
					  set(directPC) <= '1';
					  next_micro_state <= nopnop;
					end if;

				  when "1110110" => --trapv
					if decodeOPC = '1' then
					  setstate <= "01";
					end if;
					if Flags(1) = '1' and state = "01" then
					  trap_trapv <= '1';
					  trapmake <= '1';
					end if;

				  when "1111010" | "1111011" => --movec
					if VBR_Stackframe = 0 or (cpu(0) = '0' and VBR_Stackframe = 2) then
					  trap_illegal <= '1';
					  trapmake <= '1';
					elsif SVmode = '0' then
					  trap_priv <= '1';
					  trapmake <= '1';
					else
					  datatype <= "10"; --Long
					  if last_data_read(11 downto 0) = X"800" then
						  set(from_USP) <= '1';
						if opcode(0) = '1' then
						  set(to_USP) <= '1';
						end if;
					  end if;
					  if opcode(0) = '0' then
						set_exec(movec_rd) <= '1';
					  else
						set_exec(movec_wr) <= '1';
					  end if;
					  if decodeOPC = '1' then
						next_micro_state <= movec1;
						getbrief <= '1';
					  end if;
					end if;

				  when others =>
					trap_illegal <= '1';
					trapmake <= '1';
				end case;
			  end if;
			when others => NULL;
		  end case;
		end if;
		--
		---- 0101 ----------------------------------------------------------------------------
	  when "0101" => --subq, addq

		if opcode(7 downto 6) = "11" then --dbcc
		  if opcode(5 downto 3) = "001" then --dbcc
			if decodeOPC = '1' then
			  next_micro_state <= dbcc1;
			  set(OP2out_one) <= '1';
			  data_is_source <= '1';
			end if;
		  else --Scc
			datatype <= "00"; --Byte
			ea_build_now <= '1';
			write_back <= '1';
			set_exec(opcScc) <= '1';
			if cpu(0) = '1' and state = "10" then
			  skipFetch <= '1';
			end if;
			if opcode(5 downto 4) = "00" then
			  set_exec(Regwrena) <= '1';
			end if;
		  end if;
		else --addq, subq
		  ea_build_now <= '1';
		  if opcode(5 downto 3) = "001" then
			set(no_Flags) <= '1';
		  end if;
		  if opcode(8) = '1' then
			set(addsub) <= '1';
		  end if;
		  write_back <= '1';
		  set_exec(opcADDQ) <= '1';
		  set_exec(opcADD) <= '1';
		  set_exec(ea_data_OP1) <= '1';
		  if opcode(5 downto 4) = "00" then
			set_exec(Regwrena) <= '1';
		  end if;
		end if;
		--
		---- 0110 ----------------------------------------------------------------------------
	  when "0110" => --bra,bsr,bcc
		datatype <= "10";

		if micro_state = idle then
		  if opcode(11 downto 8) = "0001" then --bsr
			set(presub) <= '1';
			setstackaddr <= '1';
			if opcode(7 downto 0) = "11111111" then
			  next_micro_state <= bsr2;
			  set(longaktion) <= '1';
			elsif opcode(7 downto 0) = "00000000" then
			  next_micro_state <= bsr2;
			else
			  next_micro_state <= bsr1;
			  setstate <= "11";
			  writePC <= '1';
			end if;
		  else --bra
			if opcode(7 downto 0) = "11111111" then
			  next_micro_state <= bra1;
			  set(longaktion) <= '1';
			elsif opcode(7 downto 0) = "00000000" then
			  next_micro_state <= bra1;
			else
			  setstate <= "01";
			  next_micro_state <= bra1;
			end if;
		  end if;
		end if;

		-- 0111 ----------------------------------------------------------------------------
	  when "0111" => --moveq
		-- if opcode(8)='0' then -- Cloanto's Amiga Forver ROMs have mangled movq instructions with a 1 here...
		if trap_interrupt = '0' and trap_trace = '0' then
		  datatype <= "10"; --Long
		  set_exec(Regwrena) <= '1';
		  set_exec(opcMOVEQ) <= '1';
		  set_exec(opcMOVE) <= '1';
		  dest_hbits <= '1';
		end if;
		-- else
		-- trap_illegal <= '1';
		-- trapmake <= '1';
		-- end if;

		---- 1000 ----------------------------------------------------------------------------
	  when "1000" => --or
		if opcode(7 downto 6) = "11" then --divu, divs
		  if DIV_Mode /= 3 then
			if opcode(5 downto 4) = "00" then --Dn, An
			  regdirectsource <= '1';
			end if;
			if (micro_state = idle and nextpass = '1') or (opcode(5 downto 4) = "00" and decodeOPC = '1') then
			  setstate <= "01";
			  next_micro_state <= div1;
			end if;
			ea_build_now <= '1';
			if z_error = '0' and set_V_Flag = '0' then
			  set_exec(Regwrena) <= '1';
			end if;
			source_lowbits <= '1';
			if nextpass = '1' or (opcode(5 downto 4) = "00" and decodeOPC = '1') then
			  dest_hbits <= '1';
			end if;
			datatype <= "01";
		  else
			trap_illegal <= '1';
			trapmake <= '1';
		  end if;

		elsif opcode(8) = '1' and opcode(5 downto 4) = "00" then --sbcd, pack , unpack
		  if opcode(7 downto 6) = "00" then --sbcd
			build_bcd <= '1';
			set_exec(opcADD) <= '1';
			set_exec(opcSBCD) <= '1';
		  elsif cpu(1) = '1' and (opcode(7 downto 6) = "01" or opcode(7 downto 6) = "10") then --pack, unpack
			datatype <= "01"; --Word
			set_exec(opcPACK) <= '1';
			set(no_Flags) <= '1'; -- this command modifies no flags
			-- immediate value is kept in op1
			-- source value is in op2

			if opcode(3) = '0' then -- R/M bit = 0 -> Dy->Dy, 1 -(Ax),-(Ay)
			  dest_hbits <= '1'; -- dest register is encoded in bits 9-11
			  source_lowbits <= '1'; -- source register is encoded in bits 0-2
			  set_exec(Regwrena) <= '1'; -- write result into register
			  set_exec(ea_data_OP1) <= '1'; -- immediate value goes into op2
			  set(hold_dwr) <= '1';
			  -- pack writes a byte only
			  if opcode(7 downto 6) = "01" then
				datatype <= "00"; --Byte
			  else
				datatype <= "01"; --Word
			  end if;
			  if decodeOPC = '1' then
				next_micro_state <= nop;
				set_direct_data <= '1';
			  end if;
			else
			  set_exec(ea_data_OP1) <= '1';
			  source_lowbits <= '1'; -- source register is encoded in bits 0-2
			  if decodeOPC = '1' then
				-- first step: read source value
				if opcode(7 downto 6) = "10" then -- UNPK reads a byte
				  datatype <= "00"; -- Byte
				end if;
				set_direct_data <= '1';
				setstate <= "10";
				set(update_ld) <= '1';
				set(presub) <= '1';
				next_micro_state <= pack1;
				dest_areg <= '1'; --???
			  end if;
			end if;
		  else
			trap_illegal <= '1';
			trapmake <= '1';
		  end if;
		else --or
		  set_exec(opcor) <= '1';
		  build_logical <= '1';
		end if;

		---- 1001, 1101 -----------------------------------------------------------------------
	  when "1001" | "1101" => --sub, add
		set_exec(opcADD) <= '1';
		ea_build_now <= '1';
		if opcode(14) = '0' then
		  set(addsub) <= '1';
		end if;
		if opcode(7 downto 6) = "11" then -- --adda, suba
		  if opcode(8) = '0' then --adda.w, suba.w
			datatype <= "01"; --Word
		  end if;
		  set_exec(Regwrena) <= '1';
		  source_lowbits <= '1';
		  if opcode(3) = '1' then
			source_areg <= '1';
		  end if;
		  set(no_Flags) <= '1';
		  if setexecOPC = '1' then
			dest_areg <= '1';
			dest_hbits <= '1';
		  end if;
		else
		  if opcode(8) = '1' and opcode(5 downto 4) = "00" then --addx, subx
			build_bcd <= '1';
		  else --sub, add
			build_logical <= '1';
		  end if;
		end if;

		--
		---- 1010 ----------------------------------------------------------------------------
	  when "1010" => --Trap 1010
		trap_1010 <= '1';
		trapmake <= '1';
		---- 1011 ----------------------------------------------------------------------------
	  when "1011" => --eor, cmp
		ea_build_now <= '1';
		if opcode(7 downto 6) = "11" then --CMPA
		  if opcode(8) = '0' then --cmpa.w
			datatype <= "01"; --Word
			set_exec(opcCPMAW) <= '1';
		  end if;
		  set_exec(opcCMP) <= '1';
		  if setexecOPC = '1' then
			source_lowbits <= '1';
			if opcode(3) = '1' then
			  source_areg <= '1';
			end if;
			dest_areg <= '1';
			dest_hbits <= '1';
		  end if;
		  set(addsub) <= '1';
		else
		  if opcode(8) = '1' then
			if opcode(5 downto 3) = "001" then --cmpm
			  set_exec(opcCMP) <= '1';
			  if decodeOPC = '1' then
				setstate <= "10";
				set(update_ld) <= '1';
				set(postadd) <= '1';
				next_micro_state <= cmpm;
			  end if;
			  set_exec(ea_data_OP1) <= '1';
			  set(addsub) <= '1';
			else --Eor
			  build_logical <= '1';
			  set_exec(opcEor) <= '1';
			end if;
		  else --CMP
			build_logical <= '1';
			set_exec(opcCMP) <= '1';
			set(addsub) <= '1';
		  end if;
		end if;
		--
		---- 1100 ----------------------------------------------------------------------------
	  when "1100" => --and, exg
		if opcode(7 downto 6) = "11" then --mulu, muls
		  if MUL_Mode /= 3 then
			if opcode(5 downto 4) = "00" then --Dn, An
			  regdirectsource <= '1';
			end if;
			if (micro_state = idle and nextpass = '1') or (opcode(5 downto 4) = "00" and decodeOPC = '1') then
			  setstate <= "01";
			  set(ld_rot_cnt) <= '1';
			  next_micro_state <= mul1;
			end if;
			ea_build_now <= '1';
			set_exec(Regwrena) <= '1';
			source_lowbits <= '1';
			if (nextpass = '1') or (opcode(5 downto 4) = "00" and decodeOPC = '1') then
			  dest_hbits <= '1';
			end if;
			datatype <= "01";
		  else
			trap_illegal <= '1';
			trapmake <= '1';
		  end if;

		elsif opcode(8) = '1' and opcode(5 downto 4) = "00" then --exg, abcd
		  if opcode(7 downto 6) = "00" then --abcd
			build_bcd <= '1';
			set_exec(opcADD) <= '1';
			set_exec(opcABCD) <= '1';
		  else --exg
			datatype <= "10";
			set(Regwrena) <= '1';
			set(exg) <= '1';
			if opcode(6) = '1' and opcode(3) = '1' then
			  dest_areg <= '1';
			  source_areg <= '1';
			end if;
			if decodeOPC = '1' then
			  setstate <= "01";
			else
			  dest_hbits <= '1';
			end if;
		  end if;
		else --and
		  set_exec(opcand) <= '1';
		  build_logical <= '1';
		end if;
		--
		---- 1110 ----------------------------------------------------------------------------
	  when "1110" => --rotation / bitfield
		if opcode(7 downto 6) = "11" then
		  if opcode(11) = '0' then
			set_exec(opcROT) <= '1';
			ea_build_now <= '1';
			datatype <= "01";
			set_rot_bits <= opcode(10 downto 9);
			set_exec(ea_data_OP1) <= '1';
			write_back <= '1';
		  else --bitfield
			if BitField = 0 or (cpu(1) = '0' and BitField = 2) then
			  trap_illegal <= '1';
			  trapmake <= '1';
			else
			  if decodeOPC = '1' then
				next_micro_state <= nop;
				set(get_2ndOPC) <= '1';
				set(ea_build) <= '1';
			  end if;
			  set_exec(opcBF) <= '1';

                          -- BFCLR, BFSET, BFINS, BFCHG, BFFFO, BFTST
			  if opcode(10) = '1' or opcode(8) = '0' then
                              set_exec(opcBFwb) <= '1';
                                -- BFFFO operating on memory
                                if opcode(10 downto 8) = "101" and opcode(4 downto 3) /= "00"  then
                                  set_exec(ea_data_OP2) <= '1';
                              end if;
                              set_exec(ea_data_OP1) <= '1';
                          end if;
                          
                          -- BFCHG, BFCLR, BFSET, BFINS
			  if opcode(10 downto 8) = "010" or opcode(10 downto 8) = "100" or
                             opcode(10 downto 8) = "110" or opcode(10 downto 8) = "111" then
                            write_back <= '1';
			  end if;
                          
			  ea_only <= '1';
                          -- BFEXTU, BFEXTS, BFFFO
			  if opcode(10 downto 8) = "001" or opcode(10 downto 8) = "011" or
                             opcode(10 downto 8) = "101" then
                            set_exec(Regwrena) <= '1';
			  end if;
                          
                          -- register destination
			  if opcode(4 downto 3) = "00" then
                                -- bftst doesn't write
                                if opcode(10 downto 8) /= "000" then
                                  set_exec(Regwrena) <= '1';
                                end if;
                            
				if exec(ea_build) = '1' then
				  dest_2ndHbits <= '1';
				  source_2ndLbits <= '1';
				  set(get_bfoffset) <= '1';
				  setstate <= "01";
				end if;
			  end if;
			  if set(get_ea_now) = '1' then
				setstate <= "01";
			  end if;
			  if exec(get_ea_now) = '1' then
				dest_2ndHbits <= '1';
				source_2ndLbits <= '1';
				set(get_bfoffset) <= '1';
				setstate <= "01";
				set(mem_addsub) <= '1';
				next_micro_state <= bf1;
			  end if;

			  if setexecOPC = '1' then
				if opcode(10 downto 8) = "111" then --BFINS
				  source_2ndHbits <= '1';
				elsif opcode(10 downto 8)="001" or opcode(10 downto 8)="011" or
                                      opcode(10 downto 8)="101" THEN
                                  --BFEXTU, BFEXTS, BFFFO
				  source_lowbits <= '1';
				  dest_2ndHbits <= '1';
				end if;
			  end if;
			end if;
		  end if;
		else
		  set_exec(opcROT) <= '1';
		  set_rot_bits <= opcode(4 downto 3);
		  data_is_source <= '1';
		  set_exec(Regwrena) <= '1';
		  if decodeOPC = '1' then
			if opcode(5) = '1' then
			  next_micro_state <= rota1;
			  set(ld_rot_cnt) <= '1';
			  setstate <= "01";
			else
			  set_rot_cnt(2 downto 0) <= opcode(11 downto 9);
			  if opcode(11 downto 9) = "000" then
				set_rot_cnt(3) <= '1';
			  else
				set_rot_cnt(3) <= '0';
			  end if;
			end if;
		  end if;
		end if;
		--
		---- ----------------------------------------------------------------------------
	  when others =>
		trap_1111 <= '1';
		trapmake <= '1';

	end case;

	-- use for and, or, Eor, CMP
	if build_logical = '1' then
	  ea_build_now <= '1';
	  if set_exec(opcCMP) = '0' and (opcode(8) = '0' or opcode(5 downto 4) = "00" ) then
		set_exec(Regwrena) <= '1';
	  end if;
	  if opcode(8) = '1' then
		write_back <= '1';
		set_exec(ea_data_OP1) <= '1';
	  else
		source_lowbits <= '1';
		if opcode(3) = '1' then --use for cmp
		  source_areg <= '1';
		end if;
		if setexecOPC = '1' then
		  dest_hbits <= '1';
		end if;
	  end if;
	end if;

	-- use for ABCD, SBCD
	if build_bcd = '1' then
	  set_exec(use_XZFlag) <= '1';
	  set_exec(ea_data_OP1) <= '1';
	  write_back <= '1';
	  source_lowbits <= '1';
	  if opcode(3) = '1' then
		if decodeOPC = '1' then
		  setstate <= "10";
		  set(update_ld) <= '1';
		  set(presub) <= '1';
		  next_micro_state <= op_AxAy;
		  dest_areg <= '1'; --???
		end if;
	  else
		dest_hbits <= '1';
		set_exec(Regwrena) <= '1';
	  end if;
	end if;
	------------------------------------------------------------------------------
	------------------------------------------------------------------------------
	if set_Z_error = '1' then -- divu by zero
	  trapmake <= '1'; --wichtig for USP
	  if trapd = '0' then
		writePC <= '1';
	  end if;
	end if;

	-----------------------------------------------------------------------------
	-- execute microcode
	-----------------------------------------------------------------------------
	if rising_edge(clk) THEN
	  if Reset='1' THEN
		micro_state <= ld_nn;
	  elsif clkena_lw='1' THEN
		trapd <= trapmake;
		micro_state <= next_micro_state;
	  end if;
	end if;

	case micro_state is
	  when ld_nn => -- (nnnn).w/l=>
		set(get_ea_now) <= '1';
		setnextpass <= '1';
		set(addrlong) <= '1';

	  when st_nn => -- =>(nnnn).w/l
		setstate <= "11";
		set(addrlong) <= '1';
		next_micro_state <= nop;

	  when ld_dAn1 => -- d(An)=>, --d(PC)=>
		set(get_ea_now) <= '1';
		setdisp <= '1'; --word
		setnextpass <= '1';

	  when ld_AnXn1 => -- d(An,Xn)=>, --d(PC,Xn)=>
		if brief(8) = '0' or extAddr_Mode = 0 or (cpu(1) = '0' and extAddr_Mode = 2) then
		  -- mikej brief extension word only
		  setdisp <= '1'; --byte
		  setdispbyte <= '1';
		  setstate <= "01";
		  set(briefext) <= '1';
		  next_micro_state <= ld_AnXn2;
		else
		  if brief(7) = '1' then --suppress Base
			set_suppress_base <= '1';
		  elsif exec(dispouter) = '1' then
			set(dispouter) <= '1';
		  end if;
		  if brief(5) = '0' then --NULL Base Displacement
			setstate <= "01";
		  else --WorD Base Displacement
			if brief(4) = '1' then
			  set(longaktion) <= '1'; --LONG Base Displacement
			end if;
		  end if;
		  next_micro_state <= ld_229_1;
		end if;

	  when ld_AnXn2 =>
		set(get_ea_now) <= '1';
		setdisp <= '1'; --brief
		setnextpass <= '1';

		-------------------------------------------------------------------------------------

	  when ld_229_1 => -- (bd,An,Xn)=>, --(bd,PC,Xn)=>
		if brief(5) = '1' then --Base Displacement
		  setdisp <= '1'; --add last_data_read
		end if;
		if brief(6) = '0' and brief(2) = '0' then --Preindex or Index
		  set(briefext) <= '1';
		  setstate <= "01";
		  if brief(1 downto 0) = "00" then
			next_micro_state <= ld_AnXn2;
		  else
			next_micro_state <= ld_229_2;
		  end if;
		else
		  if brief(1 downto 0) = "00" then
			set(get_ea_now) <= '1';
			setnextpass <= '1';
		  else
			setstate <= "10";
			set(longaktion) <= '1';
			next_micro_state <= ld_229_3;
		  end if;
		end if;

	  when ld_229_2 => -- (bd,An,Xn)=>, --(bd,PC,Xn)=>
		setdisp <= '1'; -- add Index
		setstate <= "10";
		set(longaktion) <= '1';
		next_micro_state <= ld_229_3;

	  when ld_229_3 => -- (bd,An,Xn)=>, --(bd,PC,Xn)=>
		set_suppress_base <= '1';
		set(dispouter) <= '1';
		if brief(1) = '0' then --NULL Outer Displacement
		  setstate <= "01";
		else --WORD Outer Displacement
		  if brief(0) = '1' then
			set(longaktion) <= '1'; --LONG Outer Displacement
		  end if;
		end if;
		next_micro_state <= ld_229_4;

	  when ld_229_4 => -- (bd,An,Xn)=>, --(bd,PC,Xn)=>
		if brief(1) = '1' then -- Outer Displacement
		  setdisp <= '1'; --add last_data_read
		end if;
		if brief(6) = '0' and brief(2) = '1' then --Postindex
		  set(briefext) <= '1';
		  setstate <= "01";
		  next_micro_state <= ld_AnXn2;
		else
		  set(get_ea_now) <= '1';
		  setnextpass <= '1';
		end if;

		----------------------------------------------------------------------------------------
	  when st_dAn1 => -- =>d(An)
		setstate <= "11";
		setdisp <= '1'; --word
		next_micro_state <= nop;

	  when st_AnXn1 => -- =>d(An,Xn)
		if brief(8) = '0' or extAddr_Mode = 0 or (cpu(1) = '0' and extAddr_Mode = 2) then
		  setdisp <= '1'; --byte
		  setdispbyte <= '1';
		  setstate <= "01";
		  set(briefext) <= '1';
		  next_micro_state <= st_AnXn2;
		else
		  if brief(7) = '1' then --suppress Base
			set_suppress_base <= '1';
			-- elsif exec(dispouter)='1' then
			-- set(dispouter) <= '1';
		  end if;
		  if brief(5) = '0' then --NULL Base Displacement
			setstate <= "01";
		  else --WorD Base Displacement
			if brief(4) = '1' then
			  set(longaktion) <= '1'; --LONG Base Displacement
			end if;
		  end if;
		  next_micro_state <= st_229_1;
		end if;

	  when st_AnXn2 =>
		setstate <= "11";
		setdisp <= '1'; --brief
		next_micro_state <= nop;

		-------------------------------------------------------------------------------------

	  when st_229_1 => -- (bd,An,Xn)=>, --(bd,PC,Xn)=>
		if brief(5) = '1' then --Base Displacement
		  setdisp <= '1'; --add last_data_read
		end if;
		if brief(6) = '0' and brief(2) = '0' then --Preindex or Index
		  set(briefext) <= '1';
		  setstate <= "01";
		  if brief(1 downto 0) = "00" then
			next_micro_state <= st_AnXn2;
		  else
			next_micro_state <= st_229_2;
		  end if;
		else
		  if brief(1 downto 0) = "00" then
			setstate <= "11";
			next_micro_state <= nop;
		  else
			set(hold_dwr) <= '1';
			setstate <= "10";
			set(longaktion) <= '1';
			next_micro_state <= st_229_3;
		  end if;
		end if;

	  when st_229_2 => -- (bd,An,Xn)=>, --(bd,PC,Xn)=>
		setdisp <= '1'; -- add Index
		set(hold_dwr) <= '1';
		setstate <= "10";
		set(longaktion) <= '1';
		next_micro_state <= st_229_3;

	  when st_229_3 => -- (bd,An,Xn)=>, --(bd,PC,Xn)=>
		set(hold_dwr) <= '1';
		set_suppress_base <= '1';
		set(dispouter) <= '1';
		if brief(1) = '0' then --NULL Outer Displacement
		  setstate <= "01";
		else --WorD Outer Displacement
		  if brief(0) = '1' then
			set(longaktion) <= '1'; --LONG Outer Displacement
		  end if;
		end if;
		next_micro_state <= st_229_4;

	  when st_229_4 => -- (bd,An,Xn)=>, --(bd,PC,Xn)=>
		set(hold_dwr) <= '1';
		if brief(1) = '1' then -- Outer Displacement
		  setdisp <= '1'; --add last_data_read
		end if;
		if brief(6) = '0' and brief(2) = '1' then --Postindex
		  set(briefext) <= '1';
		  setstate <= "01";
		  next_micro_state <= st_AnXn2;
		else
		  setstate <= "11";
		  next_micro_state <= nop;
		end if;

		----------------------------------------------------------------------------------------
	  when bra1 => --bra
		if exe_condition = '1' then
		  TG68_PC_brw <= '1'; --pc+0000
		  next_micro_state <= nop;
		  skipFetch <= '1';
		end if;

	  when bsr1 => --bsr short
		TG68_PC_brw <= '1';
		next_micro_state <= nop;

	  when bsr2 => --bsr
		if long_start = '0' then
		  TG68_PC_brw <= '1';
		end if;
		skipFetch <= '1';
		set(longaktion) <= '1';
		writePC <= '1';
		setstate <= "11";
		next_micro_state <= nopnop;
		setstackaddr <= '1';
	  when nopnop => --bsr
		next_micro_state <= nop;

	  when dbcc1 => --dbcc
		if exe_condition = '0' then
		  Regwrena_now <= '1';
		  if c_out(1) = '1' then
			skipFetch <= '1';
			next_micro_state <= nop;
			TG68_PC_brw <= '1';
		  end if;
		end if;

	  when movem1 => --movem
		if last_data_read(15 downto 0) /= X"0000" then
			setstate <= "01";
		  if opcode(5 downto 3) = "100" then
			set(mem_addsub) <= '1';
		  end if;
		  next_micro_state <= movem2;
		end if;

	  when movem2 => --movem
		if movem_run = '0' then
		  setstate <= "01";
		else
		  set(movem_action) <= '1';
		  set(mem_addsub) <= '1';
		  next_micro_state <= movem2;
		  if opcode(10) = '0' then
			setstate <= "11";
			set(write_reg) <= '1';
		  else
			setstate <= "10";
		  end if;
		end if;

	  when andi => --andi
		if opcode(5 downto 4) /= "00" then
		  setnextpass <= '1';
		end if;

	  when op_AxAy => -- op -(Ax),-(Ay)
		set_direct_data <= '1';
		set(presub) <= '1';
		dest_hbits <= '1';
		dest_areg <= '1';
		setstate <= "10";

	  when cmpm => -- cmpm (Ay)+,(Ax)+
		set_direct_data <= '1';
		set(postadd) <= '1';
		dest_hbits <= '1';
		dest_areg <= '1';
		setstate <= "10";

	  when link1 => -- link
		setstate <= "11";
		source_areg <= '1';
		set(opcMOVE) <= '1';
		set(Regwrena) <= '1';
		next_micro_state <= link2;
	  when link2 => -- link
		setstackaddr <= '1';
		set(ea_data_OP2) <= '1';

	  when unlink1 => -- unlink
		setstate <= "10";
		setstackaddr <= '1';
		set(postadd) <= '1';
		next_micro_state <= unlink2;

	  when unlink2 => -- unlink
		set(ea_data_OP2) <= '1';

	  when trap00 =>          -- TRAP format #2
		 next_micro_state <= trap0;
		 set(presub) <= '1';
		 setstackaddr <='1';
		 setstate <= "11";
		 datatype <= "10";

	  when trap0 => -- TRAP
		set(presub) <= '1';
		setstackaddr <= '1';
		setstate <= "11";
		if VBR_Stackframe = 1 or (cpu(0) = '1' and VBR_Stackframe = 2) then --68010
		  set(writePC_add) <= '1';
		  datatype <= "01";
		  -- set_datatype <= "10";
		  next_micro_state <= trap1;
		else
		  if trap_interrupt='1' or trap_trace='1' or trap_berr='1' THEN
			writePC <= '1';
		  end if;
		  datatype <= "10";
		  next_micro_state <= trap2;
		end if;

	  when trap1 => -- TRAP
										-- additional word for 68020
		if trap_interrupt = '1' or trap_trace = '1' then
		  writePC <= '1';
		end if;
		set(presub) <= '1';
		setstackaddr <= '1';
		setstate <= "11";
		datatype <= "10";
		next_micro_state <= trap2;

	  when trap2 => -- TRAP
		set(presub) <= '1';
		setstackaddr <= '1';
		setstate <= "11";
		datatype <= "01";
		writeSR <= '1';
		if trap_berr='1' THEN
		  next_micro_state <= trap4;
		else
		  next_micro_state <= trap3;
		end if;

	  when trap3 => -- TRAP
		set_vectoraddr <= '1';
		datatype <= "10";
		set(direct_delta) <= '1';
		set(directPC) <= '1';
		setstate <= "10";
		next_micro_state <= nopnop;

	  when trap4 =>           -- TRAP
		set(presub) <= '1';
		setstackaddr <='1';
		setstate <= "11";
		datatype <= "01";
		writeSR <= '1';
		next_micro_state <= trap5;

	  when trap5 =>           -- TRAP
		set(presub) <= '1';
		setstackaddr <='1';
		setstate <= "11";
		datatype <= "10";
		writeSR <= '1';
		next_micro_state <= trap6;

	  when trap6 =>           -- TRAP
		set(presub) <= '1';
		setstackaddr <='1';
		setstate <= "11";
		datatype <= "01";
		writeSR <= '1';
		next_micro_state <= trap3;

										-- return from exception - RTE
										-- fetch PC and status register from stack
										-- 010+ fetches another word containing
										-- the 12 bit vector offset and the
										-- frame format. If the frame format is
										-- 2 another two words have to be taken
										-- from the stack
	  when rte1 => -- RTE
		datatype <= "10";
		setstate <= "10";
		set(postadd) <= '1';
		setstackaddr <= '1';
		if VBR_Stackframe = 0 or (cpu(0) = '0' and VBR_Stackframe = 2) then
		  set(direct_delta) <= '1';
		end if;
		set(directPC) <= '1';
		next_micro_state <= rte2;

	  when rte2 => -- RTE
		datatype <= "01";
		set(update_FC) <= '1';
		if VBR_Stackframe = 1 or (cpu(0) = '1' and VBR_Stackframe = 2) then
												-- 010+ reads another word
		  setstate <= "10";
		  set(postadd) <= '1';
		  setstackaddr <= '1';
		  next_micro_state <= rte3;
		else
		  next_micro_state <= nop;
		end if;
	  when rte3 => -- RTE
										setstate <= "01"; -- idle state to wait
														  -- for input data to
														  -- arrive
										next_micro_state <= rte4;
					WHEN rte4 =>            -- RTE
										-- check for stack frame format #2
										if last_data_in(15 downto 12)="0010" then
										  -- read another 32 bits in this case
										 setstate <= "10"; -- read
										  datatype <= "10"; -- long word
										  set(postadd) <= '1';
										  setstackaddr <= '1';
										  next_micro_state <= rte5;
										else
										  datatype <= "01";
		next_micro_state <= nop;
										end if;
					WHEN rte5 =>            -- RTE
					next_micro_state <= nop;
	  when movec1 => -- MOVEC
		set(briefext) <= '1';
		set_writePCbig <= '1';
		if (brief(11 downto 0) = X"000" or brief(11 downto 0) = X"001" or brief(11 downto 0) = X"800" or brief(11 downto 0) = X"801") or
		   (cpu(1) = '1' and (brief(11 downto 0) = X"002" or brief(11 downto 0) = X"802" or brief(11 downto 0) = X"803" or brief(11 downto 0) = X"804")) then
			if opcode(0) = '0' then
			  set(Regwrena) <= '1';
		  end if;
		  -- elsif brief(11 downto 0)=X"800"or brief(11 downto 0)=X"001" or brief(11 downto 0)=X"000" then
		  -- trap_addr_error <= '1';
		  -- trapmake <= '1';
		else
		  trap_illegal <= '1';
		  trapmake <= '1';
		end if;

	  when movep1 => -- MOVEP d(An)
		setdisp <= '1';
		set(mem_addsub) <= '1';
		set(mem_byte) <= '1';
		set(OP1addr) <= '1';
		if opcode(6) = '1' then
		  set(movepl) <= '1';
		end if;
		if opcode(7) = '0' then
		  setstate <= "10";
		else
		  setstate <= "11";
		end if;
		next_micro_state <= movep2;

	  when movep2 =>
		if opcode(6) = '1' then
		  set(mem_addsub) <= '1';
		  set(OP1addr) <= '1';
		end if;
		if opcode(7) = '0' then
		  setstate <= "10";
		else
		  setstate <= "11";
		end if;
		next_micro_state <= movep3;

	  when movep3 =>
		if opcode(6) = '1' then
		  set(mem_addsub) <= '1';
		  set(OP1addr) <= '1';
		  set(mem_byte) <= '1';
		  if opcode(7) = '0' then
			setstate <= "10";
		  else
			setstate <= "11";
		  end if;
		  next_micro_state <= movep4;
		else
		  datatype <= "01"; --Word
		end if;

	  when movep4 =>
		if opcode(7) = '0' then
		  setstate <= "10";
		else
		  setstate <= "11";
		end if;
		next_micro_state <= movep5;
	  when movep5 =>
		datatype <= "10"; --Long

	  when mul1 => -- mulu
		if opcode(15) = '1' or MUL_Mode = 0 then
		  set_rot_cnt <= "001110";
		else
		  set_rot_cnt <= "011110";
		end if;
		setstate <= "01";
		next_micro_state <= mul2;

	  when mul2 => -- mulu
		setstate <= "01";
		if rot_cnt = "00001" then
		  next_micro_state <= mul_end1;
		else
		  next_micro_state <= mul2;
		end if;

	  when mul_end1 => -- mulu
		datatype <= "10";
		set(opcMULU) <= '1';
		if opcode(15) = '0' and (MUL_Mode = 1 or MUL_Mode = 2) then
		  dest_2ndHbits <= '1';
		  source_2ndLbits <= '1';--???
		  set(write_lowlong) <= '1';
		  if sndOPC(10) = '1' then
			setstate <= "01";
			next_micro_state <= mul_end2;
		  end if;
		  set(Regwrena) <= '1';
		end if;
		datatype <= "10";

	  when mul_end2 => -- divu
		set(write_reminder) <= '1';
		set(Regwrena) <= '1';
		set(opcMULU) <= '1';

	  when div1 => -- divu
		setstate <= "01";
		next_micro_state <= div2;

	  when div2 => -- divu
		if (OP2out(31 downto 16) = x"0000" or opcode(15) = '1' or DIV_Mode = 0) and OP2out(15 downto 0) = x"0000" then --div zero
			set_Z_error <= '1';
		else
		  next_micro_state <= div3;
		end if;
		set(ld_rot_cnt) <= '1';
		setstate <= "01";

	  when div3 => -- divu
		if opcode(15) = '1' or DIV_Mode = 0 then
		  set_rot_cnt <= "001101";
		else
		  set_rot_cnt <= "011101";
		end if;
		setstate <= "01";
		next_micro_state <= div4;

	  when div4 => -- divu
		setstate <= "01";
		if rot_cnt = "00001" then
		  next_micro_state <= div_end1;
		else
		  next_micro_state <= div4;
		end if;

	  when div_end1 => -- divu
		if opcode(15) = '0' and (DIV_Mode = 1 or DIV_Mode = 2) then
		  set(write_reminder) <= '1';
		  next_micro_state <= div_end2;
		  setstate <= "01";
		end if;
		set(opcDIVU) <= '1';
		datatype <= "10";

	  when div_end2 => -- divu
		dest_2ndHbits <= '1';
		source_2ndLbits <= '1';--???
		set(opcDIVU) <= '1';

	  when rota1 =>
		if OP2out(5 downto 0) /= "000000" then
		  set_rot_cnt <= OP2out(5 downto 0);
		else
		  set_exec(rot_nop) <= '1';
		end if;

	  when bf1 =>
		setstate <= "10";

	  when pack1 =>
		-- result computation
		if opcode(7 downto 6) = "10" then -- UNPK reads a byte
		  datatype <= "00"; -- Byte
		end if;
		set(ea_data_OP2) <= '1';
		set(opcPACK) <= '1';
		next_micro_state <= pack2;

	  when pack2 =>
		-- write result
		if opcode(7 downto 6) = "01" then -- PACK writes a byte
		  datatype <= "00";
		end if;
		set(presub) <= '1';
		setstate <= "11";
		dest_hbits <= '1';
		dest_areg <= '1';
		next_micro_state <= pack3;

	  when pack3 =>
		-- this is just to keep datatype == 00
		-- for byte writes
		-- write result
		if opcode(7 downto 6) = "01" then -- PACK writes a byte
		  datatype <= "00";
		end if;
	  when others => NULL;
	end case;
  end process;

  -----------------------------------------------------------------------------
  -- MOVEC
  -----------------------------------------------------------------------------
  process (clk, VBR, CACR, brief)
  begin
	-- all other hexa codes should give illegal isntruction exception
	if rising_edge(clk) then
	  if Reset = '1' then
		VBR <= (others => '0');
		CACR <= (others => '0');
	  elsif clkena_lw = '1' and exec(movec_wr) = '1' then
		case brief(11 downto 0) is
		  when X"000" => NULL; -- SFC -- 68010+
		  when X"001" => NULL; -- DFC -- 68010+
		  when X"002" => CACR <= reg_QA(3 downto 0); -- 68020+
		  when X"800" => NULL; -- USP -- 68010+
		  when X"801" => VBR <= reg_QA; -- 68010+
		  when X"802" => NULL; -- CAAR -- 68020+
		  when X"803" => NULL; -- MSP -- 68020+
		  when X"804" => NULL; -- isP -- 68020+
		  when others => NULL;
		end case;
	  end if;
	end if;

	movec_data <= (others => '0');
	case brief(11 downto 0) is
	  when X"002" => movec_data <= "0000000000000000000000000000" & (CACR AND "0011");

	  when X"801" => --if VBR_Stackframe=1 or (cpu(0)='1' and VBR_Stackframe=2) then
		movec_data <= VBR;
		--end if;
	  when others => NULL;
	end case;
  end process;

  CACR_out <= CACR;
  VBR_out <= VBR;

  -----------------------------------------------------------------------------
  -- Conditions
  -----------------------------------------------------------------------------
  process (exe_opcode, Flags)
  begin
	case exe_opcode(11 downto 8) is
	  when X"0" => exe_condition <= '1';
	  when X"1" => exe_condition <= '0';
	  when X"2" => exe_condition <= not Flags(0) and not Flags(2);
	  when X"3" => exe_condition <= Flags(0) or Flags(2);
	  when X"4" => exe_condition <= not Flags(0);
	  when X"5" => exe_condition <= Flags(0);
	  when X"6" => exe_condition <= not Flags(2);
	  when X"7" => exe_condition <= Flags(2);
	  when X"8" => exe_condition <= not Flags(1);
	  when X"9" => exe_condition <= Flags(1);
	  when X"a" => exe_condition <= not Flags(3);
	  when X"b" => exe_condition <= Flags(3);
	  when X"c" => exe_condition <= (Flags(3) and Flags(1)) or (not Flags(3) and not Flags(1));
	  when X"d" => exe_condition <= (Flags(3) and not Flags(1)) or (not Flags(3) and Flags(1));
	  when X"e" => exe_condition <= (Flags(3) and Flags(1) and not Flags(2)) or (not Flags(3) and not Flags(1) and not Flags(2));
	  when X"f" => exe_condition <= (Flags(3) and not Flags(1)) or (not Flags(3) and Flags(1)) or Flags(2);
	  when others => NULL;
	end case;
  end process;

  -----------------------------------------------------------------------------
  -- Movem
  -----------------------------------------------------------------------------
  process (clk)
  begin
	if rising_edge(clk) then
	  if clkena_lw = '1' then
		movem_actiond <= exec(movem_action);
		if decodeOPC = '1' then
		  sndOPC <= data_read(15 downto 0);
		elsif exec(movem_action) = '1' or set(movem_action) = '1' then
		  case movem_regaddr is
			when "0000" => sndOPC(0) <= '0';
			when "0001" => sndOPC(1) <= '0';
			when "0010" => sndOPC(2) <= '0';
			when "0011" => sndOPC(3) <= '0';
			when "0100" => sndOPC(4) <= '0';
			when "0101" => sndOPC(5) <= '0';
			when "0110" => sndOPC(6) <= '0';
			when "0111" => sndOPC(7) <= '0';
			when "1000" => sndOPC(8) <= '0';
			when "1001" => sndOPC(9) <= '0';
			when "1010" => sndOPC(10) <= '0';
			when "1011" => sndOPC(11) <= '0';
			when "1100" => sndOPC(12) <= '0';
			when "1101" => sndOPC(13) <= '0';
			when "1110" => sndOPC(14) <= '0';
			when "1111" => sndOPC(15) <= '0';
			when others => NULL;
		  end case;
		end if;
	  end if;
	end if;
  end process;

  process (sndOPC, movem_mux)
  begin
	movem_regaddr <= "0000";
	movem_run <= '1';
	if sndOPC(3 downto 0) = "0000" then
	  if sndOPC(7 downto 4) = "0000" then
		movem_regaddr(3) <= '1';
		if sndOPC(11 downto 8) = "0000" then
		  if sndOPC(15 downto 12) = "0000" then
			movem_run <= '0';
		  end if;
		  movem_regaddr(2) <= '1';
		  movem_mux <= sndOPC(15 downto 12);
		else
		  movem_mux <= sndOPC(11 downto 8);
		end if;
	  else
		movem_mux <= sndOPC(7 downto 4);
		movem_regaddr(2) <= '1';
	  end if;
	else
	  movem_mux <= sndOPC(3 downto 0);
	end if;

	if movem_mux(1 downto 0) = "00" then
	  movem_regaddr(1) <= '1';
	  if movem_mux(2) = '0' then
		movem_regaddr(0) <= '1';
	  end if;
	else
	  if movem_mux(0) = '0' then
		movem_regaddr(0) <= '1';
	  end if;
	end if;
  end process;

  exec_d.opcMOVE        <= exec(opcMOVE);
  exec_d.opcMOVEQ       <= exec(opcMOVEQ);
  exec_d.opcMOVESR      <= exec(opcMOVESR);
  exec_d.opcMOVECCR     <= exec(opcMOVECCR);
  exec_d.opcADD         <= exec(opcADD);
  exec_d.opcADDQ        <= exec(opcADDQ);
  exec_d.opcor          <= exec(opcor);
  exec_d.opcand         <= exec(opcand);
  exec_d.opcEor         <= exec(opcEor);
  exec_d.opcCMP         <= exec(opcCMP);
  exec_d.opcROT         <= exec(opcROT);
  exec_d.opcCPMAW       <= exec(opcCPMAW);
  exec_d.opcEXT         <= exec(opcEXT);
  exec_d.opcABCD        <= exec(opcABCD);
  exec_d.opcSBCD        <= exec(opcSBCD);
  exec_d.opcBITS        <= exec(opcBITS);
  exec_d.opcSWAP        <= exec(opcSWAP);
  exec_d.opcScc         <= exec(opcScc);
  exec_d.andisR         <= exec(andisR);
  exec_d.eorisR         <= exec(eorisR);
  exec_d.orisR          <= exec(orisR);
  exec_d.opcMULU        <= exec(opcMULU);
  exec_d.opcDIVU        <= exec(opcDIVU);
  exec_d.dispouter      <= exec(dispouter);
  exec_d.rot_nop        <= exec(rot_nop);
  exec_d.ld_rot_cnt     <= exec(ld_rot_cnt);
  exec_d.writePC_add    <= exec(writePC_add);
  exec_d.ea_data_OP1    <= exec(ea_data_OP1);
  exec_d.ea_data_OP2    <= exec(ea_data_OP2);
  exec_d.use_XZFlag     <= exec(use_XZFlag);
  exec_d.get_bfoffset   <= exec(get_bfoffset);
  exec_d.save_memaddr   <= exec(save_memaddr);
  exec_d.opcCHK         <= exec(opcCHK);
  exec_d.movec_rd       <= exec(movec_rd);
  exec_d.movec_wr       <= exec(movec_wr);
  exec_d.Regwrena       <= exec(Regwrena);
  exec_d.update_FC      <= exec(update_FC);
  exec_d.linksp         <= exec(linksp);
  exec_d.movepl         <= exec(movepl);
  exec_d.update_ld      <= exec(update_ld);
  exec_d.OP1addr        <= exec(OP1addr);
  exec_d.write_reg      <= exec(write_reg);
  exec_d.changeMode     <= exec(changeMode);
  exec_d.ea_build       <= exec(ea_build);
  exec_d.trap_chk       <= exec(trap_chk);
  exec_d.store_ea_data  <= exec(store_ea_data);
  exec_d.addrlong       <= exec(addrlong);
  exec_d.postadd        <= exec(postadd);
  exec_d.presub         <= exec(presub);
  exec_d.subidx         <= exec(subidx);
  exec_d.no_Flags       <= exec(no_Flags);
  exec_d.use_SP         <= exec(use_SP);
  exec_d.to_CCR         <= exec(to_CCR);
  exec_d.to_SR          <= exec(to_SR);
  exec_d.OP2out_one     <= exec(OP2out_one);
  exec_d.OP1out_zero    <= exec(OP1out_zero);
  exec_d.mem_addsub     <= exec(mem_addsub);
  exec_d.addsub         <= exec(addsub);
  exec_d.directPC       <= exec(directPC);
  exec_d.direct_delta   <= exec(direct_delta);
  exec_d.directSR       <= exec(directSR);
  exec_d.directCCR      <= exec(directCCR);
  exec_d.exg            <= exec(exg);
  exec_d.get_ea_now     <= exec(get_ea_now);
  exec_d.ea_to_pc       <= exec(ea_to_pc);
  exec_d.hold_dwr       <= exec(hold_dwr);
  exec_d.to_USP         <= exec(to_USP);
  exec_d.from_USP       <= exec(from_USP);
  exec_d.write_lowlong  <= exec(write_lowlong);
  exec_d.write_reminder <= exec(write_reminder);
  exec_d.movem_action   <= exec(movem_action);
  exec_d.briefext       <= exec(briefext);
  exec_d.get_2ndOPC     <= exec(get_2ndOPC);
  exec_d.mem_byte       <= exec(mem_byte);
  exec_d.longaktion     <= exec(longaktion);
  exec_d.opcRESET       <= exec(opcRESET);
  exec_d.opcBF          <= exec(opcBF);
  exec_d.opcBFwb        <= exec(opcBFwb);
  exec_d.opcPACK        <= exec(opcPACK);
  --when the instruction has completed, the decremented address
  --register contains the address of the last operand stored. For
  --the MC68020, MC68030, and MC68040, if the addressing
  --register is also moved to memory, the value written is the
  --initial register value decremented by the size of the oper-
  --ation. The MC68000 writes the initial register value
  --(not decremented).

  regin_out <= regin;
  end;

