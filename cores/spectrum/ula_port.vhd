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

entity ula_port is
port (
	CLK		:	in	std_logic;
	nRESET	:	in	std_logic;
	
	-- CPU interface with separate read/write buses
	D_IN	:	in	std_logic_vector(7 downto 0);
	D_OUT	:	out	std_logic_vector(7 downto 0);
	ENABLE	:	in	std_logic;
	nWR		:	in	std_logic;
	
	BORDER_OUT	:	out	std_logic_vector(2 downto 0);
	EAR_OUT		:	out	std_logic;
	MIC_OUT		:	out std_logic;
	
	KEYB_IN		:	in 	std_logic_vector(4 downto 0);
	EAR_IN		:	in	std_logic	
	);
end ula_port;

architecture ula_port_arch of ula_port is
begin	
	process(CLK,nRESET)
	begin
		if nRESET = '0' then
			-- Output register
			-- 7,6,5 = N/C
			-- 4 = EAR
			-- 3 = MIC
			-- 2,1,0 = BORDER (G, R, B)
			EAR_OUT <= '0';
			MIC_OUT <= '0';
			BORDER_OUT <= (others => '0');
			
			-- Input register
			D_OUT <= (others => '0');
		elsif rising_edge(CLK) then
			-- Register inputs
			-- 7 = N/C
			-- 6 = EAR
			-- 5 = N/C
			-- 4-0 = Keyboard
			D_OUT <= '0' & EAR_IN & '0' & KEYB_IN;
			
			if ENABLE = '1' and nWR = '0' then
				-- Latch input data to output register
				EAR_OUT <= D_IN(4);
				MIC_OUT <= D_IN(3);
				BORDER_OUT <= D_IN(2 downto 0);
			end if;
		end if;
	end process;
end ula_port_arch;

