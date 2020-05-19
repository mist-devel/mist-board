-- BBC Micro for Altera DE1
--
-- Copyright (c) 2011 Mike Stirling
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- * Redistributions of source code must retain the above copyright notice,
--	 this list of conditions and the following disclaimer.
--
-- * Redistributions in synthesized form must reproduce the above copyright
--	 notice, this list of conditions and the following disclaimer in the
--	 documentation and/or other materials provided with the distribution.
--
-- * Neither the name of the author nor the names of other contributors may
--	 be used to endorse or promote products derived from this software without
--	 specific prior written agreement from the author.
--
-- * License is granted for non-commercial use only.  A fee may not be charged
--	 for redistributions as source code or in synthesized/hardware form without
--	 specific prior written agreement from the author.
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
-- MC6845 CRTC
--
-- Synchronous implementation for FPGA
--
-- (C) 2011 Mike Stirling
--
-- Corrected cursor flash rate
-- Fixed incorrect positioning of cursor when over left most character
-- Fixed timing of VSYNC
-- Fixed interlaced timing (add an extra line)
-- Implemented r05_v_total_adj
-- Implemented delay parts of r08_interlace (see Hitacht HD6845SP datasheet)
--
-- (C) 2015 David Banks
--
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mc6845 is
port (
	CLOCK		:	in	std_logic;
	CLKEN		:	in	std_logic;
	nRESET		:	in	std_logic;

	-- Bus interface
	ENABLE		:	in	std_logic;
	R_nW		:	in	std_logic;
	RS			:	in	std_logic;
	DI			:	in	std_logic_vector(7 downto 0);
	DO			:	out	std_logic_vector(7 downto 0);

	-- Display interface
	VSYNC		:	out	std_logic;
	HSYNC		:	out	std_logic;
	DE			:	out	std_logic;
	CURSOR		:	out	std_logic;
	LPSTB		:	in	std_logic;

	VGA			:	in	std_logic;

	-- Memory interface
	MA			:	out	std_logic_vector(13 downto 0);
	RA			:	out	std_logic_vector(4 downto 0)
	);
end entity;

architecture rtl of mc6845 is

-- Host-accessible registers
signal addr_reg			:	std_logic_vector(4 downto 0);	-- Currently addressed register
-- These are write-only
signal r00_h_total		:	unsigned(7 downto 0);	-- Horizontal total, chars
signal r01_h_displayed	:	unsigned(7 downto 0);	-- Horizontal active, chars
signal r02_h_sync_pos	:	unsigned(7 downto 0);	-- Horizontal sync position, chars
signal r03_v_sync_width :	unsigned(3 downto 0);	-- Vertical sync width, scan lines (0=16 lines)
signal r03_h_sync_width	:	unsigned(3 downto 0);	-- Horizontal sync width, chars (0=no sync)
signal r04_v_total		:	unsigned(6 downto 0);	-- Vertical total, character rows
signal r05_v_total_adj	:	unsigned(4 downto 0);	-- Vertical offset, scan lines
signal r06_v_displayed	:	unsigned(6 downto 0);	-- Vertical active, character rows
signal r07_v_sync_pos	:	unsigned(6 downto 0);	-- Vertical sync position, character rows
signal r08_interlace	:	std_logic_vector(7 downto 0);
signal r09_max_scan_line_addr		:	unsigned(4 downto 0);
signal r10_cursor_mode	:	std_logic_vector(1 downto 0);
signal r10_cursor_start	:	unsigned(4 downto 0);	-- Cursor start, scan lines
signal r11_cursor_end	:	unsigned(4 downto 0);	-- Cursor end, scan lines
signal r12_start_addr_h	:	unsigned(5 downto 0);
signal r13_start_addr_l	:	unsigned(7 downto 0);
-- These are read/write
signal r14_cursor_h		:	unsigned(5 downto 0);
signal r15_cursor_l		:	unsigned(7 downto 0);
-- These are read-only
signal r16_light_pen_h	:	unsigned(5 downto 0);
signal r17_light_pen_l	:	unsigned(7 downto 0);


-- Timing generation
-- Horizontal counter counts position on line
signal h_counter		:	unsigned(7 downto 0);
-- HSYNC counter counts duration of sync pulse
signal h_sync_counter	:	unsigned(3 downto 0);
-- Row counter counts current character row
signal row_counter		:	unsigned(6 downto 0);
-- Line counter counts current line within each character row
signal line_counter		:	unsigned(4 downto 0);
-- VSYNC counter counts duration of sync pulse
signal v_sync_counter	:	unsigned(3 downto 0);
-- Field counter counts number of complete fields for cursor flash
signal field_counter	:	unsigned(4 downto 0);

-- Internal signals
signal h_sync_start		:	std_logic;
signal v_sync_start		:	std_logic;
signal h_display		:	std_logic;
signal h_display_early	:	std_logic;
signal hs				:	std_logic;
signal v_display		:	std_logic;
signal v_display_early	:	std_logic;
signal vs				:	std_logic;
signal odd_field		:	std_logic;
signal ma_i				:	unsigned(13 downto 0);
signal ma_row_start		:	unsigned(13 downto 0); -- Start address of current character row
signal cursor_i			:	std_logic;
signal lpstb_i			:	std_logic;
signal de0				:	std_logic;
signal de1				:	std_logic;
signal de2				:	std_logic;
signal cursor0			:	std_logic;
signal cursor1			:	std_logic;
signal cursor2			:	std_logic;


begin
	HSYNC <= hs; -- External HSYNC driven directly from internal signal
	VSYNC <= vs; -- External VSYNC driven directly from internal signal

	de0 <= h_display and v_display;

    -- In Mode 7 DE Delay is set to 01, but in our implementation no delay is needed
    -- TODO: Fix SAA5050
	DE <= de0 when r08_interlace(5 downto 4) = "00" else
		  de0 when r08_interlace(5 downto 4) = "01" else -- not accurate, should be de1
		  de2 when r08_interlace(5 downto 4) = "10" else
		  '0';

	-- Cursor output generated combinatorially from the internal signal in
	-- accordance with the currently selected cursor mode
	cursor0 <=	cursor_i						when r10_cursor_mode = "00" else
				'0'								when r10_cursor_mode = "01" else
				(cursor_i and field_counter(3))	when r10_cursor_mode = "10" else
				(cursor_i and field_counter(4));

    -- In Mode 7 Cursor Delay is set to 10, but in our implementation one one cycle is needed
    -- TODO: Fix SAA5050
	CURSOR <=   cursor0 when r08_interlace(7 downto 6) = "00" else
				cursor1 when r08_interlace(7 downto 6) = "01" else
				cursor1 when r08_interlace(7 downto 6) = "10" else -- not accurate, should be cursor2
			    '0';

	-- Synchronous register access.	 Enabled on every clock.
	process(CLOCK,nRESET)
	begin
		if nRESET = '0' then
			-- Reset registers to defaults
			addr_reg <= (others => '0');
			r00_h_total <= (others => '0');
			r01_h_displayed <= (others => '0');
			r02_h_sync_pos <= (others => '0');
			r03_v_sync_width <= (others => '0');
			r03_h_sync_width <= (others => '0');
			r04_v_total <= (others => '0');
			r05_v_total_adj <= (others => '0');
			r06_v_displayed <= (others => '0');
			r07_v_sync_pos <= (others => '0');
			r08_interlace <= (others => '0');
			r09_max_scan_line_addr <= (others => '0');
			r10_cursor_mode <= (others => '0');
			r10_cursor_start <= (others => '0');
			r11_cursor_end <= (others => '0');
			r12_start_addr_h <= (others => '0');
			r13_start_addr_l <= (others => '0');
			r14_cursor_h <= (others => '0');
			r15_cursor_l <= (others => '0');

			DO <= (others => '0');
		elsif rising_edge(CLOCK) then
			if ENABLE = '1' then
				if R_nW = '1' then
					-- Read
					case addr_reg is
					when "01100" =>
						DO <= "00" & std_logic_vector(r12_start_addr_h);
					when "01101" =>
						DO <= std_logic_vector(r13_start_addr_l);
					when "01110" =>
						DO <= "00" & std_logic_vector(r14_cursor_h);
					when "01111" =>
						DO <= std_logic_vector(r15_cursor_l);
					when "10000" =>
						DO <= "00" & std_logic_vector(r16_light_pen_h);
					when "10001" =>
						DO <= std_logic_vector(r17_light_pen_l);
					when others =>
						DO <= (others => '0');
					end case;
				else
					-- Write
					if RS = '0' then
						addr_reg <= DI(4 downto 0);
					else
						case addr_reg is
						when "00000" =>
							r00_h_total <= unsigned(DI);
						when "00001" =>
							r01_h_displayed <= unsigned(DI);
						when "00010" =>
							r02_h_sync_pos <= unsigned(DI);
						when "00011" =>
							r03_v_sync_width <= unsigned(DI(7 downto 4));
							r03_h_sync_width <= unsigned(DI(3 downto 0));
						when "00100" =>
							r04_v_total <= unsigned(DI(6 downto 0));
						when "00101" =>
							r05_v_total_adj <= unsigned(DI(4 downto 0));
						when "00110" =>
							r06_v_displayed <= unsigned(DI(6 downto 0));
						when "00111" =>
							r07_v_sync_pos <= unsigned(DI(6 downto 0));
						when "01000" =>
							r08_interlace <= DI(7 downto 0);
						when "01001" =>
							r09_max_scan_line_addr <= unsigned(DI(4 downto 0));
						when "01010" =>
							r10_cursor_mode <= DI(6 downto 5);
							r10_cursor_start <= unsigned(DI(4 downto 0));
						when "01011" =>
							r11_cursor_end <= unsigned(DI(4 downto 0));
						when "01100" =>
							r12_start_addr_h <= unsigned(DI(5 downto 0));
						when "01101" =>
							r13_start_addr_l <= unsigned(DI(7 downto 0));
						when "01110" =>
							r14_cursor_h <= unsigned(DI(5 downto 0));
						when "01111" =>
							r15_cursor_l <= unsigned(DI(7 downto 0));
						when others =>
							null;
						end case;
					end if;
				end if;
			end if;
		end if;
	end process; -- registers

	-- Horizontal, vertical and address counters
	process(CLOCK,nRESET)
	variable ma_row_start : unsigned(13 downto 0);
	variable max_scan_line : unsigned(4 downto 0);
	variable adj_scan_line : unsigned(4 downto 0);
	variable in_adj : std_logic;
	variable need_adj : std_logic;
	begin
		if nRESET = '0' then
			-- H
			h_counter <= (others => '0');

			-- V
			line_counter <= (others => '0');
			row_counter <= (others => '0');
			odd_field <= '0';

			-- Fields (cursor flash)
			field_counter <= (others => '0');

			-- Addressing
			ma_row_start := (others => '0');
			ma_i <= (others => '0');

			in_adj := '0';

		elsif rising_edge(CLOCK) then
			if CLKEN = '1' then
				-- Horizontal counter increments on each clock, wrapping at
				-- h_total
				if h_counter = r00_h_total then
					-- h_total reached
					h_counter <= (others => '0');

					-- Compute
					if r05_v_total_adj /= 0 or odd_field = '1' then
						need_adj := '1';
					else
						need_adj := '0';
					end if;

					-- Compute the max scan line for this row
					if in_adj = '0' then
						-- This is a normal row, so use r09_max_scan_line_addr
						if VGA = '1' then
							-- So Mode 7 value of 18 becomes 19 (giving 20 rows per character)
							max_scan_line := r09_max_scan_line_addr + 1;
						else
							max_scan_line := r09_max_scan_line_addr;
						end if;
					else
						-- This is the "adjust" row, so use r05_v_total_adj
						if VGA = '1' then
							-- So Mode7 value of 2 becomes 4 (giving 31 * 20 + 4 = 624 lines)
							max_scan_line := r05_v_total_adj + 1;
						else
							max_scan_line := r05_v_total_adj - 1;
						end if;
						-- If interlaced, the odd field contains an additional scan line
						if odd_field = '1' then
							if r08_interlace(1 downto 0) = "11" then
								max_scan_line := max_scan_line + 2;
							else
								max_scan_line := max_scan_line + 1;
							end if;
						end if;
					end if;

					-- In interlace sync + video mode mask off the LSb of the
					-- max scan line address
					if r08_interlace(1 downto 0) = "11" and VGA = '0' then
						max_scan_line(0) := '0';
					end if;

					if line_counter = max_scan_line and ((need_adj = '0' and row_counter = r04_v_total) or in_adj = '1') then

						line_counter <= (others => '0');

						-- If in interlace mode we toggle to the opposite field.
						-- Save on some logic by doing this here rather than at the
						-- end of v_total_adj - it shouldn't make any difference to the
						-- output
						if r08_interlace(0) = '1' and VGA = '0' then
							odd_field <= not odd_field;
						else
							odd_field <= '0';
						end if;

						-- Address is loaded from start address register at the top of
						-- each field and the row counter is reset
						ma_row_start := r12_start_addr_h & r13_start_addr_l;
						row_counter <= (others => '0');

						-- Increment field counter
						field_counter <= field_counter + 1;

						-- Reset the in extra time flag
						in_adj := '0';

					elsif in_adj = '0' and line_counter = max_scan_line then
						-- Scan line counter increments, wrapping at max_scan_line_addr
						-- Next character row
						line_counter <= (others => '0');
						-- On all other character rows within the field the row start address is
						-- increased by h_displayed and the row counter is incremented
						ma_row_start := ma_row_start + r01_h_displayed;
						row_counter <= row_counter + 1;
						-- Test if we are entering the adjust phase, and set
						-- in_adj accordingly
						if row_counter = r04_v_total and need_adj = '1' then
							in_adj := '1';
						end if;
					else
						-- Next scan line.	Count in twos in interlaced sync+video mode
						if r08_interlace(1 downto 0) = "11" and VGA = '0' then
							line_counter <= line_counter + 2;
							line_counter(0) <= '0'; -- Force to even
						else
							line_counter <= line_counter + 1;
						end if;
					end if;

					-- Memory address preset to row start at the beginning of each
					-- scan line
					ma_i <= ma_row_start;
				else
					-- Increment horizontal counter
					h_counter <= h_counter + 1;
					-- Increment memory address
					ma_i <= ma_i + 1;
				end if;
			end if;
		end if;
	end process;

	-- Signals to mark hsync and and vsync in even and odd fields
	process(h_counter, r00_h_total, r02_h_sync_pos, odd_field)
	begin
		h_sync_start <= '0';
		v_sync_start <= '0';

		if h_counter = r02_h_sync_pos then
			h_sync_start <= '1';
		end if;

		-- dmb: measurements on a real beeb confirm this is the actual
		-- 6845 behaviour. i.e. in non-interlaced mode the start of vsync
		-- coinscides with the start of the active display, and in intelaced
		-- mode the vsync of the odd field is delayed by half a scan line
		if (odd_field = '0' and h_counter = 0) or (odd_field = '1' and h_counter = "0" & r00_h_total(7 downto 1)) then
			v_sync_start <= '1';
		end if;
	end process;

	h_display_early <= '1' when h_counter	< r01_h_displayed else '0';
	v_display_early <= '1' when row_counter < r06_v_displayed else '0';

	-- Video timing and sync counters
	process(CLOCK,nRESET)
	begin
		if nRESET = '0' then
			-- H
			h_display <= '0';
			hs <= '0';
			h_sync_counter <= (others => '0');

			-- V
			v_display <= '0';
			vs <= '0';
			v_sync_counter <= (others => '0');
		elsif rising_edge(CLOCK) then
			if CLKEN = '1' then
				-- Horizontal active video
				h_display <= h_display_early;

				-- Horizontal sync
				if h_sync_start = '1' or hs = '1' then
					-- In horizontal sync
					hs <= '1';
					h_sync_counter <= h_sync_counter + 1;
				else
					h_sync_counter <= (others => '0');
				end if;
				if h_sync_counter = r03_h_sync_width then
					-- Terminate hsync after h_sync_width (0 means no hsync so this
					-- can immediately override the setting above)
					hs <= '0';
				end if;

				-- Vertical active video
				v_display <= v_display_early;

				-- Vertical sync occurs either at the same time as the horizontal sync (even fields)
				-- or half a line later (odd fields)
				if (v_sync_start = '1') then
					if (row_counter = r07_v_sync_pos and line_counter = 0) or vs = '1' then
						-- In vertical sync
						vs <= '1';
						v_sync_counter <= v_sync_counter + 1;
					else
						v_sync_counter <= (others => '0');
					end if;
					if v_sync_counter = r03_v_sync_width and vs = '1' then
						-- Terminate vsync after v_sync_width (0 means 16 lines so this is
						-- masked by 'vs' to ensure a full turn of the counter in this case)
						vs <= '0';
					end if;
				end if;
			end if;
		end if;
	end process;

	-- Address generation
	process(CLOCK,nRESET)
	variable slv_line : std_logic_vector(4 downto 0);
	begin
		if nRESET = '0' then
			RA <= (others => '0');
			MA <= (others => '0');
		elsif rising_edge(CLOCK) then
			if CLKEN = '1' then
				slv_line := std_logic_vector(line_counter);

				-- Character row address is just the scan line counter delayed by
				-- one clock to line up with the syncs.
				if r08_interlace(1 downto 0) = "11" and VGA = '0' then
					RA <= slv_line(4 downto 1) & (slv_line(0) or odd_field);
				else
					RA <= slv_line(4 downto 1) & (slv_line(0) xor VGA);
				end if;
				-- Internal memory address delayed by one cycle as well
				MA <= std_logic_vector(ma_i);
			end if;
		end if;
	end process;

	-- Cursor control
	process(CLOCK,nRESET)
	variable cursor_line : std_logic;
	begin
		-- Internal cursor enable signal delayed by 1 clock to line up
		-- with address outputs
		if nRESET = '0' then
			cursor_i <= '0';
			cursor_line := '0';
		elsif rising_edge(CLOCK) then
			if CLKEN = '1' then
				if h_display_early = '1' and v_display_early = '1' and ma_i = r14_cursor_h & r15_cursor_l then
					if line_counter = 0 then
						-- Suppress wrap around if last line is > max scan line
						cursor_line := '0';
					end if;
					if line_counter = r10_cursor_start then
						-- First cursor scanline
						cursor_line := '1';
					end if;

					-- Cursor output is asserted within the current cursor character
					-- on the selected lines only
					cursor_i <= cursor_line;

					if line_counter = r11_cursor_end then
						-- Last cursor scanline
						cursor_line := '0';
					end if;
				else
					-- Cursor is off in all character positions apart from the
					-- selected one
					cursor_i <= '0';
				end if;
			end if;
		end if;
	end process;

	-- Light pen capture
	process(CLOCK,nRESET)
	begin
		if nRESET = '0' then
			lpstb_i <= '0';
			r16_light_pen_h <= (others => '0');
			r17_light_pen_l <= (others => '0');
		elsif rising_edge(CLOCK) then
			if CLKEN = '1' then
				-- Register light-pen strobe input
				lpstb_i <= LPSTB;

				if LPSTB = '1' and lpstb_i = '0' then
					-- Capture address on rising edge
					r16_light_pen_h <= ma_i(13 downto 8);
					r17_light_pen_l <= ma_i(7 downto 0);
				end if;
			end if;
		end if;
	end process;

	-- Delayed CURSOR and DE (selected by R08)
	process(CLOCK,nRESET)
	begin
		if rising_edge(CLOCK) then
			if CLKEN = '1' then
				de1		<= de0;
				de2		<= de1;
				cursor1 <= cursor0;
				cursor2 <= cursor1;
			end if;
		end if;
	end process;

end architecture;
