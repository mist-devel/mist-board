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
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity video is
port(
	-- Master clock (28 MHz)
	CLK			:	in std_logic;
	-- Video domain clock enable (14 MHz)
	CLKEN		:	in std_logic;
	-- Master reset
	nRESET 		: 	in std_logic;

	-- Mode
	VGA			:	in std_logic;

	-- Memory interface
	VID_A		:	out	std_logic_vector(12 downto 0);
	VID_D_IN	:	in	std_logic_vector(7 downto 0);
	nVID_RD	:	out	std_logic;
	nWAIT		:	out	std_logic;
	
	-- IO interface
	BORDER_IN	:	in	std_logic_vector(2 downto 0);

	-- Video outputs
	R			:	out	std_logic_vector(3 downto 0);
	G			:	out	std_logic_vector(3 downto 0);
	B			:	out	std_logic_vector(3 downto 0);
	nVSYNC		:	out std_logic;
	nHSYNC		:	out std_logic;
	nCSYNC		:	out	std_logic;
	nHCSYNC		:	out std_logic;
	IS_BORDER	: 	out std_logic;
	IS_VALID	:	out std_logic;
	
	-- Clock outputs, might be useful
	PIXCLK		:	out std_logic;
	FLASHCLK	: 	out std_logic;
	
	-- Interrupt to CPU (asserted for 32 T-states, 64 ticks)
	nIRQ		:	out	std_logic
);
end video;

architecture video_arch of video is
signal		pixels	:	std_logic_vector(9 downto 0);
signal		attr	:	std_logic_vector(7 downto 0);

-- Video logic runs at 14 MHz so hcounter has an additonal LSb which is
-- skipped if running in VGA scan-doubled mode.  The value of this
-- extra bit is 1/2 for the purposes of timing calculations bit 1 is
-- assumed to have a value of 1.
signal		hcounter	: std_logic_vector(9 downto 0);
-- vcounter has an extra LSb as well except this is skipped if running
-- in PAL mode.  By not skipping it in VGA mode we get the required
-- double-scanning of each line.  This extra bit has a value 1/2 as well.
signal		vcounter	: std_logic_vector(9 downto 0);
signal		flashcounter	: std_logic_vector(4 downto 0);
signal		vblanking	: std_logic;
signal		hblanking	: std_logic;
signal		hpicture	: std_logic;
signal		vpicture	: std_logic;
signal		picture		: std_logic;
signal		blanking	: std_logic;

signal		hsync		: std_logic;
signal		vsync		: std_logic;

signal		red			: std_logic;
signal		green		: std_logic;
signal		blue		: std_logic;
signal		bright		: std_logic;
signal		dot			: std_logic;
begin
	-- The first 256 pixels of each line are valid picture
	picture <= hpicture and vpicture;
	blanking <= hblanking or vblanking;

	-- Generate clocks and enables from internal signals
	FLASHCLK <= flashcounter(4);
	IS_VALID <= not blanking;
	IS_BORDER <= not picture;
	-- FIXME: This needs to be halved for PAL mode
	PIXCLK <= CLK and CLKEN and nRESET;
	
	-- Output syncs
	nVSYNC <= not vsync;
	nHSYNC <= not hsync;
	nCSYNC <= not (vsync xor hsync);
	-- Combined HSYNC/CSYNC.  Feeds HSYNC to VGA HSYNC in VGA mode,
	-- or CSYNC to the same pin in PAL mode
	nHCSYNC <= not (vsync xor hsync) when VGA = '0' else
		not hsync;
	
	-- Determine the pixel colour
	dot <= pixels(9) xor (flashcounter(4) and attr(7)); -- Combine delayed pixel with FLASH attr and clock state
	red <= attr(1) when picture = '1' and dot = '1' else
		attr(4) when picture = '1' and dot = '0' else
		BORDER_IN(1) when blanking = '0' else
		'0';
	green <= attr(2) when picture = '1' and dot = '1' else
		attr(5) when picture = '1' and dot = '0' else
		BORDER_IN(2) when blanking = '0' else
		'0';
	blue <= attr(0) when picture = '1' and dot = '1' else
		attr(3) when picture = '1' and dot = '0' else
		BORDER_IN(0) when blanking = '0' else
		'0';
	bright <= attr(6) when picture = '1' else
		'0';
	
	-- Re-register video output to DACs to clean up edges
	process(nRESET,CLK)
	begin
		if nRESET = '0' then
			-- Asynchronous clear
			R <= (others => '0');
			G <= (others => '0');
			B <= (others => '0');
		elsif rising_edge(CLK) then
			-- Output video to DACs
			R <= (3 => red, others => bright and red);
			G <= (3 => green, others => bright and green);
			B <= (3 => blue, others => bright and blue);
		end if;
	end process;


	-- This is what the contention model is supposed to look like.
	-- We may need to emulate this to ensure proper compatibility.
	--
	-- At vcounter = 0 and hcounter = 0 we are at
	-- 14336*T since the falling edge of the vsync.
	-- This is where we start contending RAM access.
	-- The contention pattern repeats every 8 T states, with
	-- CPU clock held during the first 6 of every 8 T states
	-- (where one T state is two ticks of the horizontal counter).
	-- Two screen bytes are fetched consecutively, display first
	-- followed by attribute.  The cycle looks like this:
	-- hcounter[3..1] = 000 Fetch data 1  nWAIT = 0
	--                  001 Fetch attr 1          0
	--                  010 Fetch data 2          0
	--                  011 Fetch attr 2          0
	--                  100                       1
	--                  101                       1
	--                  110                       0
	--                  111                       0
	
	-- What we actually do is the following, interleaved with CPU RAM access
	-- so that we don't need any contention:
	-- hcounter[2..0] = 000 Fetch data (LOAD)
	--					001 Fetch data (STORE)
	--					010 Fetch attr (LOAD)
	--					011 Fetch attr (STORE)
	--					100 Idle
	--					101 Idle
	--					110 Idle
	--					111 Idle
	-- The load/store pairs take place over two clock enables.  In VGA mode
	-- there is one picture/attribute pair fetch per CPU clock enable.  In PAL
	-- mode every other tick is ignored, so the picture/attribute fetches occur
	-- on alternate CPU clocks.  At no time must a CPU cycle be allowed to split
	-- a LOAD/STORE pair, as the bus routing logic will disconnect the memory from
	-- the CPU during this time.
	
	-- RAM address is generated continuously from the counter values
	-- Pixel fetch takes place when hcounter(2) = 0, attribute when = 1
	VID_A(12 downto 0) <=
		-- Picture
		vcounter(8 downto 7) & vcounter(3 downto 1) & vcounter(6 downto 4) & hcounter(8 downto 4)
		when hcounter(2) = '0' else
		-- Attribute
		"110" & vcounter(8 downto 7) & vcounter(6 downto 4) & hcounter(8 downto 4);
	
	-- This timing model is completely uncontended.  CPU runs all the time.
	nWAIT <= '1';
	
	-- First 192 lines are picture
	vpicture <= not (vcounter(9) or (vcounter(8) and vcounter(7)));
	
	process(nRESET,CLK,CLKEN,hcounter,vcounter)
	begin	
		if nRESET = '0' then
			-- Asynchronous master reset
			hcounter <= (others => '0');
			vcounter <= (others => '0');
			flashcounter <= (others => '0');
			
			vblanking <= '0';
			hblanking <= '0';
			hpicture <= '1';
			hsync <= '0';
			vsync <= '0';
			nIRQ <= '1';
			nVID_RD <= '1';
			
			pixels <= (others => '0');
			attr <= (others => '0');
		elsif rising_edge(CLK) and CLKEN = '1' then
			-- Most functions are only performed when hcounter(0) is clear.
			-- This is the 'half' bit inserted to allow for scan-doubled VGA output.
			-- In VGA mode the counter will be stepped through the even values only,
			-- so the rest of the logic remains the same.
			if vpicture = '1' and hcounter(0) = '0' then
				-- Pump pixel shift register - this is two pixels longer
				-- than a byte to delay the pixels back into alignment with
				-- the attribute byte, stored two ticks later
				pixels(9 downto 1) <= pixels(8 downto 0);
				
				if hcounter(9) = '0' and hcounter(3) = '0' then
					-- Handle the fetch cycle
					-- 3210
					-- 0000 PICTURE LOAD
					-- 0010 PICTURE STORE
					-- 0100 ATTR LOAD
					-- 0110 ATTR STORE				
					if hcounter(1) = '0' then
						-- LOAD
						-- Assert the read strobe during the active picture in the
						-- first and third pixel of every 8.  This splits a picture/attribute
						-- fetch pair across two CPU cycles in PAL mode, or both in one cycle
						-- in VGA mode
						nVID_RD <= '0';
					else
						-- STORE
						if hcounter(2) = '0' then
							-- PICTURE
							pixels(7 downto 0) <= VID_D_IN;
						else
							-- ATTR
							attr <= VID_D_IN;
						end if;
												
						nVID_RD <= '1';
					end if;
				end if;				
				
				-- Delay horizontal picture enable until the end of the first fetch cycle
				-- This also allows for the re-registration of the outputs
				if hcounter(9) = '0' and hcounter(2 downto 1) = "11" then
					hpicture <= '1';
				end if;
				if hcounter(9) = '1' and hcounter(2 downto 1) = "11" then
					hpicture <= '0';
				end if;
			end if;
	
			-- Step the horizontal counter and check for wrap
			if VGA = '1' then				
				-- Counter wraps after 894 in VGA mode
				if hcounter = "1101111110" then
					hcounter <= (others => '0');
					-- Increment vertical counter by ones for VGA so that
					-- lines are double-scanned
					vcounter <= vcounter + '1';
				else
					-- Increment horizontal counter
					-- Even values only for VGA mode
					hcounter <= hcounter + "10";
					hcounter(0) <= '0';
				end if;
			else			
				-- Counter wraps after 895 in PAL mode
				if hcounter = "1101111111" then
					hcounter <= (others => '0');
					-- Increment vertical counter by even values for PAL
					vcounter <= vcounter + "10";
					vcounter(0) <= '0';
				else
					-- Increment horizontal counter
					-- All values for PAL mode
					hcounter <= hcounter + '1';
				end if;
			end if;
			
	
			--------------------
			-- HORIZONTAL
			--------------------
			
			-- Each line comprises the following:
			-- 256 pixels of active image
			-- 48 pixels right border
			-- 24 pixels front porch
			-- 32 pixels sync
			-- 40 pixels back porch
			-- 48 pixels left border

			-- Generate timing signals during inactive region
			-- (when hcounter(9) = 1)
			case hcounter(9 downto 4) is
			-- Blanking starts at 304
			when "100110" => hblanking <= '1';
			-- Sync starts at 328
			when "101001" => hsync <= '1';
			-- Sync ends at 360
			when "101101" => hsync <= '0';
			-- Blanking ends at 400
			when "110010" => hblanking <= '0';
			when others =>
				null;
			end case;
			
			-- Clear interrupt after 32T
			if hcounter(7) = '1' then
				nIRQ <= '1';
			end if;
			
			----------------
			-- VERTICAL
			----------------

			case vcounter(9 downto 3) is
			when "0111110" =>
				-- Start of blanking and vsync(line 248)
				vblanking <= '1';
				vsync <= '1';
				-- Assert vsync interrupt
				nIRQ <= '0';
			when "0111111" =>
				-- End of vsync after 4 lines (line 252)
				vsync <= '0';					
			when "1000000" =>
				-- End of blanking and start of top border (line 256)
				-- Should be line 264 but this is simpler and doesn't really make
				-- any difference
				vblanking <= '0';
			when others =>
				null;
			end case;

			-- Wrap vertical counter at line 312-1,
			-- Top counter value is 623 for VGA, 622 for PAL
			if vcounter(9 downto 1) = "100110111" then
				if (VGA = '1' and vcounter(0) = '1') or VGA = '0' then
					-- Start of picture area
					vcounter <= (others => '0');
					-- Increment the flash counter once per frame
					flashcounter <= flashcounter + '1';
				end if;
			end if;
		end if;
	end process;
end video_arch;

