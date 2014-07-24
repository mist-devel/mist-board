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
-- Emulation of ZXMMC+ interface
--
-- (C) 2011 Mike Stirling

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity zxmmc is
port (
	CLOCK		:	in	std_logic;
	nRESET		:	in	std_logic;
	CLKEN		:	in	std_logic;
	
	-- Bus interface
	ENABLE		:	in	std_logic;
	-- 0 - W  - Card chip selects (active low)
	-- 1 - RW - SPI tx/rx data register
	-- 2 - Not used
	-- 3 - RW - Paging control register
	RS			:	in	std_logic_vector(1 downto 0);
	nWR			:	in	std_logic;
	DI			:	in	std_logic_vector(7 downto 0);
	DO			:	out	std_logic_vector(7 downto 0);
	
	-- SD card interface
	SD_CS0		:	out	std_logic;
	SD_CS1		:	out	std_logic;
	SD_CLK		:	out	std_logic;
	SD_MOSI		:	out	std_logic;
	SD_MISO		:	in	std_logic;
	
	-- Paging control for external RAM/ROM banks
	EXT_WR_EN	:	out	std_logic; -- Enable writes to external RAM/ROM
	EXT_RD_EN	:	out	std_logic; -- Enable reads from external RAM/ROM (overlay internal ROM)
	EXT_ROM_nRAM	:	out	std_logic; -- Select external ROM or RAM banks
	EXT_BANK	:	out	std_logic_vector(4 downto 0); -- Selected bank number
	
	-- DIP switches (reset values for corresponding bits above)
	INIT_RD_EN	:	in	std_logic;
	INIT_ROM_nRAM	:	in	std_logic
	);
end entity;

architecture rtl of zxmmc is
signal counter		:	unsigned(3 downto 0);
-- Shift register has an extra bit because we write on the
-- falling edge and read on the rising edge
signal shift_reg	:	std_logic_vector(8 downto 0);
signal in_reg		:	std_logic_vector(7 downto 0);
signal paging_reg	:	std_logic_vector(7 downto 0);
begin
	-- Input register read when RS=1
	DO <= 
		in_reg when RS="01" else 
		paging_reg when RS="11" else
		(others => '1');
		
	-- Paging control outputs from register
	EXT_WR_EN <= paging_reg(7);
	EXT_RD_EN <= paging_reg(6);
	EXT_ROM_nRAM <= paging_reg(5);
	EXT_BANK <= paging_reg(4 downto 0);
	
	-- SD card outputs from clock divider and shift register
	SD_CLK <= counter(0);
	SD_MOSI <= shift_reg(8);

	-- Chip selects
	process(CLOCK,nRESET)
	begin
		if nRESET = '0' then
			SD_CS0 <= '1';
			SD_CS1 <= '1';
		elsif rising_edge(CLOCK) and CLKEN = '1' then
			if ENABLE = '1' and RS = "00" and nWR = '0' then
				-- The two chip select outputs are controlled directly
				-- by writes to the lowest two bits of the control register
				SD_CS0 <= DI(0);
				SD_CS1 <= DI(1);
			end if;
		end if;
	end process;
	
	-- Paging register writes
	process(CLOCK,nRESET)
	begin
		if nRESET = '0' then
			paging_reg <= "0" & INIT_RD_EN & INIT_ROM_nRAM & "00000";
		elsif rising_edge(CLOCK) and CLKEN = '1' then
			if ENABLE = '1' and RS = "11" and nWR = '0' then
				paging_reg <= DI;
			end if;
		end if;
	end process;
	
	-- SPI write
	process(CLOCK,nRESET)
	begin		
		if nRESET = '0' then
			shift_reg <= (others => '1');
			in_reg <= (others => '1');
			counter <= "1111"; -- Idle
		elsif rising_edge(CLOCK) and CLKEN = '1' then
			if counter = "1111" then
				-- Store previous shift register value in input register
				in_reg <= shift_reg(7 downto 0);
				
				-- Idle - check for a bus access
				if ENABLE = '1' and RS = "01" then
					-- Write loads shift register with data
					-- Read loads it with all 1s
					if nWR = '1' then
						shift_reg <= (others => '1');
					else
						shift_reg <= DI & '1';
					end if;
					counter <= "0000"; -- Initiates transfer
				end if;
			else
				-- Transfer in progress
				counter <= counter + 1;
				
				if counter(0) = '0' then
					-- Input next bit on rising edge
					shift_reg(0) <= SD_MISO;
				else
					-- Output next bit on falling edge
					shift_reg <= shift_reg(7 downto 0) & '1';
				end if;
			end if;
		end if;
	end process;
end architecture;
