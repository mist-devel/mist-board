-- ZX Spectrum for Altera DE1
--
-- Copyright (c) 2009-2011 Mike Stirling
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- * Redistributions of source code must retain the above copyright notice,
--   this list of conditions and the following disclaimer.
--
-- * Redistributions in synthesized form must reproduce the above copyright
--   notice, this list of conditions and the following disclaimer in the
--   documentation and/or other materials provided with the distribution.
--
-- * Neither the name of the author nor the names of other contributors may
--   be used to endorse or promote products derived from this software without
--   specific prior written agreement from the author.
--
-- * License is granted for non-commercial use only.  A fee may not be charged
--   for redistributions as source code or in synthesized/hardware form without 
--   specific prior written agreement from the author.
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

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity clocks is
port (
	-- 28 MHz master clock
	CLK				:	in std_logic;
	-- Master reset
	nRESET			:	in std_logic;
	
	-- 1.75 MHz clock enable for sound
	CLKEN_PSG		:	out	std_logic;
	-- 3.5 MHz clock enable (1 in 8)
	CLKEN_CPU		:	out std_logic;
	-- 3.5 MHz clock enable (1 in 8) for cpu memory access
	CLKEN_MEM		:	out std_logic;
	-- 14 MHz clock enable (out of phase with CPU)
	CLKEN_VID		:	out std_logic
	);
end clocks;

-- Clock enables for uncontended VRAM access
-- 0    1    2    3    4    5    6    7    8    9    10   11   12   13   14   15
-- CPU  VID       VID       VID       VID       VID       VID       VID       VID
--                                                                            PSG

architecture clocks_arch of clocks is
signal counter	:	unsigned(3 downto 0);
begin
	-- X000
	CLKEN_CPU <= '1' when counter = "1000" or counter = "1100" else '0';
	-- X011
	CLKEN_MEM <= '1' when counter = "1001" or counter = "1101" else '0';
	-- XXX1
	CLKEN_VID <= '1' when counter(0) = '1' else '0';
	-- 1111
	CLKEN_PSG <= '1' when counter = "1111" else '0';
	
	process(nRESET,CLK)
	begin
		if nRESET = '0' then
			counter <= (others => '0');
		elsif falling_edge(CLK) then
			counter <= counter + 1;
		end if;
	end process;
end clocks_arch;

