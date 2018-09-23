--
-- Z80 compatible microprocessor core, preudo-asynchronous top level (by Sorgelig)
--
-- Copyright (c) 2001-2002 Daniel Wallner (jesus@opencores.org)
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- Redistributions in synthesized form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- Neither the name of the author nor the names of other contributors may
-- be used to endorse or promote products derived from this software without
-- specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- Please report bugs to the author, but before you do so, please
-- make sure that this is not a derivative work and that
-- you have the latest version of this file.
--
-- The latest version of this file can be found at:
--	http://www.opencores.org/cvsweb.shtml/t80/
--
-- File history :
--
-- v1.0: convert to preudo-asynchronous model with original Z80 timings.
--
-- v2.0: rewritten for more precise timings.
--       support for both CEN_n and CEN_p set to 1. Effective clock will be CLK/2.
--
-- v2.1: Output Address 0 during non-bus MCycle (fix ZX contention)
--
-- v2.2: Interrupt acknowledge cycle has been corrected
--       WAIT_n is broken in T80.vhd. Simulate correct WAIT_n locally.
--
-- v2.3: Output last used Address during non-bus MCycle seems more correct.
--

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity T80pa is
	generic(
		Mode : integer := 0	-- 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
	);
	port(
		RESET_n     : in  std_logic;
		CLK	        : in  std_logic;
		CEN_p       : in  std_logic := '1';
		CEN_n       : in  std_logic := '1';
		WAIT_n      : in  std_logic := '1';
		INT_n       : in  std_logic := '1';
		NMI_n       : in  std_logic := '1';
		BUSRQ_n     : in  std_logic := '1';
		M1_n        : out std_logic;
		MREQ_n      : out std_logic;
		IORQ_n      : out std_logic;
		RD_n        : out std_logic;
		WR_n        : out std_logic;
		RFSH_n      : out std_logic;
		HALT_n      : out std_logic;
		BUSAK_n     : out std_logic;
		OUT0        : in  std_logic := '0';  -- 0 => OUT(C),0, 1 => OUT(C),255
		A           : out std_logic_vector(15 downto 0);
		DI          : in  std_logic_vector(7 downto 0);
		DO          : out std_logic_vector(7 downto 0);
		REG         : out std_logic_vector(211 downto 0); -- IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
		DIRSet      : in  std_logic := '0';
		DIR         : in  std_logic_vector(211 downto 0) := (others => '0') -- IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
	);
end T80pa;

architecture rtl of T80pa is

	signal IntCycle_n		: std_logic;
	signal IntCycleD_n	: std_logic_vector(1 downto 0);
	signal IORQ				: std_logic;
	signal NoRead			: std_logic;
	signal Write			: std_logic;
	signal BUSAK			: std_logic;
	signal DI_Reg			: std_logic_vector (7 downto 0);	-- Input synchroniser
	signal MCycle			: std_logic_vector(2 downto 0);
	signal TState			: std_logic_vector(2 downto 0);
	signal CEN_pol			: std_logic;
	signal A_int		   : std_logic_vector(15 downto 0);
	signal A_last		   : std_logic_vector(15 downto 0);

begin

	A <= A_int when NoRead = '0' or Write = '1' else A_last;

	BUSAK_n <= BUSAK;

	u0 : work.T80
		generic map(
			Mode    => Mode,
			IOWait  => 1
		)
		port map(
			CEN     => CEN_p and not CEN_pol,
			M1_n    => M1_n,
			IORQ    => IORQ,
			NoRead  => NoRead,
			Write   => Write,
			RFSH_n  => RFSH_n,
			HALT_n  => HALT_n,
			WAIT_n  => '1',
			INT_n   => INT_n,
			NMI_n   => NMI_n,
			RESET_n => RESET_n,
			BUSRQ_n => BUSRQ_n,
			BUSAK_n => BUSAK,
			CLK_n   => CLK,
			A       => A_int,
			DInst   => DI,     -- valid   at beginning of T3
			DI      => DI_Reg, -- latched at middle    of T3
			DO      => DO,
			REG     => REG,
			MC      => MCycle,
			TS      => TState,
			OUT0    => OUT0,
			IntCycle_n => IntCycle_n,
			DIRSet  => DIRSet,
			DIR     => DIR
		);

	process(CLK)
	begin
		if rising_edge(CLK) then
			if RESET_n = '0' then
				WR_n    <= '1';
				RD_n    <= '1';
				IORQ_n  <= '1';
				MREQ_n  <= '1';
				DI_Reg  <= "00000000";
				CEN_pol <= '0';
			elsif CEN_p = '1' and CEN_pol = '0' then
				CEN_pol <= '1';
				if MCycle = "001" then
					if TState = "010" then
						IORQ_n <= '1';
						MREQ_n <= '1';
						RD_n   <= '1';
					end if;
				else
					if TState = "001" and IORQ = '1' then
						WR_n   <= not Write;
						RD_n   <= Write;
						IORQ_n <= '0';
					end if;
				end if;
			elsif CEN_n = '1' and CEN_pol = '1' then
				if TState = "010" then
					CEN_pol <= not WAIT_n;
				else
					CEN_pol <= '0';
				end if;
				if TState = "011" and BUSAK = '1' then
					DI_Reg <= DI;
				end if;
				if MCycle = "001" then
					if TState = "001" then
						IntCycleD_n <= IntCycleD_n(0) & IntCycle_n;
						RD_n   <= not IntCycle_n;
						MREQ_n <= not IntCycle_n;
						IORQ_n <= IntCycleD_n(1);
						A_last <= A_int;
					end if;
					if TState = "011" then
						IntCycleD_n <= "11";
						RD_n   <= '1';
						MREQ_n <= '0';
					end if;
					if TState = "100" then
						MREQ_n <= '1';
					end if;
				else
					if NoRead = '0' and IORQ = '0' then
						if TState = "001" then
							RD_n   <= Write;
							MREQ_n <= '0';
							A_last <= A_int;
						end if;
					end if;
					if TState = "010" then
						WR_n   <= not Write;
					end if;
					if TState = "011" then
						WR_n   <= '1';
						RD_n   <= '1';
						IORQ_n <= '1';
						MREQ_n <= '1';
					end if;
				end if;
			end if;
		end if;
	end process;
end;
