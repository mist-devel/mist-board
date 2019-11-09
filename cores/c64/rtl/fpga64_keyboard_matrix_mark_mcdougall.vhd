-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Copyright 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------
-- 'Joystick emulation on keypad' additions by
-- Mark McDougall (msmcdoug@iinet.net.au)
-- -----------------------------------------------------------------------
--
-- VIC20/C64 Keyboard matrix
--
-- Hardware huh?
--	In original machine if a key is pressed a contact is made.
--	Bidirectional reading is possible on real hardware, which is difficult
--	to emulate. (set backwardsReadingEnabled to '1' if you want this enabled).
--	Then we have the joysticks, one of which is normally connected
--	to a OUTPUT pin.
--
-- Emulation:
--	All pins are high except when one is driven low and there is a
--	connection. This is consistent with joysticks that force a line
--	low too. CIA will put '1's when set to input to help this emulation.
--
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.ALL;

entity fpga64_keyboard_matrix is
	port (
		clk: in std_logic;
		theScanCode: in unsigned(7 downto 0);
		newScanCode: in std_logic;

		joyA: in unsigned(4 downto 0);
		joyB: in unsigned(4 downto 0);

		pai: in unsigned(7 downto 0);
		pbi: in unsigned(7 downto 0);
		pao: out unsigned(7 downto 0);
		pbo: out unsigned(7 downto 0);
		
		reset_key : out std_logic;
		restore_key : out std_logic;
		videoKey : out std_logic;
		traceKey : out std_logic;
		trace2Key : out std_logic;
		disk_num : out std_logic_vector(7 downto 0);
		
		tapPlayStopKey: out std_logic;
		
		-- Config
		-- backwardsReadingEnabled = 1 allows reversal of PIA registers to still work.
		-- not needed for kernel/normal operation only for some specific programs.
		-- set to 0 to save some hardware.
		backwardsReadingEnabled : in std_logic
	);
end fpga64_keyboard_matrix;

architecture rtl of fpga64_keyboard_matrix is	
	signal extendedFlag: std_logic := '0';
	signal releaseFlag: std_logic := '0';

	signal key_del: std_logic := '0';
	signal key_return: std_logic := '0';
	signal key_left: std_logic := '0';
	signal key_right: std_logic := '0';
	signal key_f1: std_logic := '0';
	signal key_f2: std_logic := '0';
	signal key_f3: std_logic := '0';
	signal key_f4: std_logic := '0';
	signal key_f5: std_logic := '0';
	signal key_f6: std_logic := '0';
	signal key_f7: std_logic := '0';
	signal key_f8: std_logic := '0';
	signal key_up: std_logic := '0';
	signal key_down: std_logic := '0';

	signal key_3: std_logic := '0';
	signal key_W: std_logic := '0';
	signal key_A: std_logic := '0';
	signal key_4: std_logic := '0';
	signal key_Z: std_logic := '0';
	signal key_S: std_logic := '0';
	signal key_E: std_logic := '0';
	signal key_shiftl: std_logic := '0';

	signal key_5: std_logic := '0';
	signal key_R: std_logic := '0';
	signal key_D: std_logic := '0';
	signal key_6: std_logic := '0';
	signal key_C: std_logic := '0';
	signal key_F: std_logic := '0';
	signal key_T: std_logic := '0';
	signal key_X: std_logic := '0';
	
	signal key_7: std_logic := '0';
	signal key_Y: std_logic := '0';
	signal key_G: std_logic := '0';
	signal key_8: std_logic := '0';
	signal key_B: std_logic := '0';
	signal key_H: std_logic := '0';
	signal key_U: std_logic := '0';
	signal key_V: std_logic := '0';

	signal key_9: std_logic := '0';
	signal key_I: std_logic := '0';
	signal key_J: std_logic := '0';
	signal key_0: std_logic := '0';
	signal key_M: std_logic := '0';
	signal key_K: std_logic := '0';
	signal key_O: std_logic := '0';
	signal key_N: std_logic := '0';

	signal key_plus: std_logic := '0';
	signal key_P: std_logic := '0';
	signal key_L: std_logic := '0';
	signal key_minus: std_logic := '0';
	signal key_dot: std_logic := '0';
	signal key_colon: std_logic := '0';
	signal key_at: std_logic := '0';
	signal key_comma: std_logic := '0';

	signal key_pound: std_logic := '0';
	signal key_star: std_logic := '0';
	signal key_semicolon: std_logic := '0';
	signal key_home: std_logic := '0';
	signal key_shiftr: std_logic := '0';
	signal key_equal: std_logic := '0';
	signal key_arrowup: std_logic := '0';
	signal key_slash: std_logic := '0';

	signal key_1: std_logic := '0';
	signal key_arrowleft: std_logic := '0';
	signal key_ctrl: std_logic := '0';
	signal key_2: std_logic := '0';
	signal key_space: std_logic := '0';
	signal key_commodore: std_logic := '0';
	signal key_Q: std_logic := '0';
	signal key_runstop: std_logic := '0';

	-- for joystick emulation on PS2
	signal joySelKey : std_logic;
	signal joyKeys : std_logic_vector(joyA'range) := (others => '0');	-- active high
	signal joyA_s : unsigned(joyA'range);						-- active low
	signal joyB_s : unsigned(joyB'range);						-- active low
	signal joySel : std_logic_vector(1 downto 0) := "00";
	
	-- for disk image selection
	signal diskChgKey : std_logic;
	signal disk_nb : std_logic_vector(7 downto 0);
	
begin

	process (clk)
	begin
		if rising_edge(clk) then
			if diskChgKey = '1' then
				if key_shiftl = '1' then
				  disk_nb <= disk_nb - 1;
				else
				  disk_nb <= disk_nb + 1;					
				end if;
			end if;
		end if;
	end process;

	disk_num <= disk_nb;
	--
	-- cycle though joystick emulation options on <F11>	
	--
	-- "00" - PORTA = JOYA or JOYKEYS, PORTB = JOYB
	-- "01" - PORTA = JOYA, PORTB = JOYB or JOYKEYS
	-- "10" - PORTA = JOYA, PORTB = JOYKEYS
	-- "11" - PORTA = JOYKEYS, PORTB = JOYA
	
	process (clk) --, reset)
	begin
		if rising_edge(clk) then
			if joySelKey = '1' then
				joySel <= joySel + 1;
			end if;
		end if;
	end process;

	joyA_s <= joyA and not unsigned(joyKeys) when joySel = "00" else
						not unsigned(joyKeys) when joySel = "11" else
						joyA;
	joyB_s <= joyB when joySel = "00" else
						joyB and not unsigned(joyKeys) when joySel = "01" else
						not unsigned(joyKeys) when joySel = "10" else
						joyA;

	matrix: process(clk)
	begin
		--if reset = '1' then
		--	joySelKey <= '0';
		--	joyKeys <= (others => '0');
		if rising_edge(clk) then
			-- reading A, scan pattern on B
			pao(0) <= pai(0) and joyA_s(0) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_del) and
				(pbi(1) or not key_return) and
				(pbi(2) or not (key_left or key_right)) and
				(pbi(3) or not (key_f7 or key_f8)) and
				(pbi(4) or not (key_f1 or key_f2)) and
				(pbi(5) or not (key_f3 or key_f4)) and
				(pbi(6) or not (key_f5 or key_f6)) and
				(pbi(7) or not (key_up or key_down))));
			pao(1) <= pai(1) and joyA_s(1) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_3) and
				(pbi(1) or not key_W) and
				(pbi(2) or not key_A) and
				(pbi(3) or not key_4) and
				(pbi(4) or not key_Z) and
				(pbi(5) or not key_S) and
				(pbi(6) or not key_E) and
				(pbi(7) or not (key_left or key_up or key_shiftL or key_f2 or key_f4 or key_f6 or key_f8))));
			pao(2) <= pai(2) and joyA_s(2) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_5) and
				(pbi(1) or not key_R) and
				(pbi(2) or not key_D) and
				(pbi(3) or not key_6) and
				(pbi(4) or not key_C) and
				(pbi(5) or not key_F) and
				(pbi(6) or not key_T) and
				(pbi(7) or not key_X)));
			pao(3) <= pai(3) and joyA_s(3) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_7) and
				(pbi(1) or not key_Y) and
				(pbi(2) or not key_G) and
				(pbi(3) or not key_8) and
				(pbi(4) or not key_B) and
				(pbi(5) or not key_H) and
				(pbi(6) or not key_U) and
				(pbi(7) or not key_V)));
			pao(4) <= pai(4) and joyA_s(4) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_9) and
				(pbi(1) or not key_I) and
				(pbi(2) or not key_J) and
				(pbi(3) or not key_0) and
				(pbi(4) or not key_M) and
				(pbi(5) or not key_K) and
				(pbi(6) or not key_O) and
				(pbi(7) or not key_N)));
			pao(5) <= pai(5) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_plus) and
				(pbi(1) or not key_P) and
				(pbi(2) or not key_L) and
				(pbi(3) or not key_minus) and
				(pbi(4) or not key_dot) and
				(pbi(5) or not key_colon) and
				(pbi(6) or not key_at) and
				(pbi(7) or not key_comma)));
			pao(6) <= pai(6) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_pound) and
				(pbi(1) or not key_star) and
				(pbi(2) or not key_semicolon) and
				(pbi(3) or not key_home) and
				(pbi(4) or not key_shiftr) and
				(pbi(5) or not key_equal) and
				(pbi(6) or not key_arrowup) and
				(pbi(7) or not key_slash)));
			pao(7) <= pai(7) and
				((not backwardsReadingEnabled) or
				((pbi(0) or not key_1) and
				(pbi(1) or not key_arrowleft) and
				(pbi(2) or not key_ctrl) and
				(pbi(3) or not key_2) and
				(pbi(4) or not key_space) and
				(pbi(5) or not key_commodore) and
				(pbi(6) or not key_Q) and
				(pbi(7) or not key_runstop)));

			-- reading B, scan pattern on A
			pbo(0) <= pbi(0) and joyB_s(0) and 
				(pai(0) or not key_del) and
				(pai(1) or not key_3) and
				(pai(2) or not key_5) and
				(pai(3) or not key_7) and
				(pai(4) or not key_9) and
				(pai(5) or not key_plus) and
				(pai(6) or not key_pound) and
				(pai(7) or not key_1);
			pbo(1) <= pbi(1) and joyB_s(1) and
				(pai(0) or not key_return) and
				(pai(1) or not key_W) and
				(pai(2) or not key_R) and
				(pai(3) or not key_Y) and
				(pai(4) or not key_I) and
				(pai(5) or not key_P) and
				(pai(6) or not key_star) and
				(pai(7) or not key_arrowleft);
			pbo(2) <= pbi(2) and joyB_s(2) and
				(pai(0) or not (key_left or key_right)) and
				(pai(1) or not key_A) and
				(pai(2) or not key_D) and
				(pai(3) or not key_G) and
				(pai(4) or not key_J) and
				(pai(5) or not key_L) and
				(pai(6) or not key_semicolon) and
				(pai(7) or not key_ctrl);
			pbo(3) <= pbi(3) and joyB_s(3) and
				(pai(0) or not key_F7) and
				(pai(1) or not key_4) and
				(pai(2) or not key_6) and
				(pai(3) or not key_8) and
				(pai(4) or not key_0) and
				(pai(5) or not key_minus) and
				(pai(6) or not key_home) and
				(pai(7) or not key_2);
			pbo(4) <= pbi(4) and joyB_s(4) and
				(pai(0) or not key_F1) and
				(pai(1) or not key_Z) and
				(pai(2) or not key_C) and
				(pai(3) or not key_B) and
				(pai(4) or not key_M) and
				(pai(5) or not key_dot) and
				(pai(6) or not key_shiftr) and
				(pai(7) or not key_space);
			pbo(5) <= pbi(5) and
				(pai(0) or not key_F3) and
				(pai(1) or not key_S) and
				(pai(2) or not key_F) and
				(pai(3) or not key_H) and
				(pai(4) or not key_K) and
				(pai(5) or not key_colon) and
				(pai(6) or not key_equal) and
				(pai(7) or not key_commodore);
			pbo(6) <= pbi(6) and
				(pai(0) or not key_F5) and
				(pai(1) or not key_E) and
				(pai(2) or not key_T) and
				(pai(3) or not key_U) and
				(pai(4) or not key_O) and
				(pai(5) or not key_at) and
				(pai(6) or not key_arrowup) and
				(pai(7) or not key_Q);
			pbo(7) <= pbi(7) and
				(pai(0) or not (key_up or key_down)) and
				(pai(1) or not (key_left or key_up or key_shiftL or key_f2 or key_f4 or key_f6 or key_f8)) and
				(pai(2) or not key_X) and
				(pai(3) or not key_V) and
				(pai(4) or not key_N) and
				(pai(5) or not key_comma) and
				(pai(6) or not key_slash) and
				(pai(7) or not key_runstop);

			traceKey <= '0';
			trace2Key <= '0';
			videoKey <= '0';
			joySelKey <= '0';
			diskChgKey <= '0';
			tapPlayStopKey <= '0';
			if newScanCode = '1' then
				if theScanCode=X"F0" then
					releaseFlag <= '1';		
				elsif theScanCode=X"E0" then
					extendedFlag <= '1';
				else	
					releaseFlag <= '0';		
					extendedFlag <= '0';
					case theScanCode is
					when X"05" => key_F1 <= not releaseFlag;
					when X"06" => key_F2 <= not releaseFlag;
					when X"04" => key_F3 <= not releaseFlag;
					when X"0C" => key_F4 <= not releaseFlag;
					when X"03" => key_F5 <= not releaseFlag;
					when X"0B" => key_F6 <= not releaseFlag;
					when X"83" => key_F7 <= not releaseFlag;
					when X"0A" => key_F8 <= not releaseFlag;
					when X"01" => key_pound <= not releaseFlag; -- F9
					when X"09" => key_plus <= not releaseFlag; -- F10
					when X"78" => -- F11
						if key_ctrl = '1' then
							reset_key <= not releaseFlag;
						else
							restore_key <= not releaseFlag;
						end if;
					when X"0E" => key_arrowleft <= not releaseFlag;
					when X"11" => key_commodore <= not releaseFlag; 
					when X"12" => if extendedFlag = '0' then key_shiftl <= not releaseFlag; end if;
					when X"14" => key_ctrl <= not releaseFlag; 
					when X"15" => key_Q <= not releaseFlag; 
					when X"16" => key_1 <= not releaseFlag; 
					when X"1A" => key_Z <= not releaseFlag; 
					when X"1B" => key_S <= not releaseFlag; 
					when X"1C" => key_A <= not releaseFlag; 
					when X"1D" => key_W <= not releaseFlag; 
					when X"1E" => key_2 <= not releaseFlag; 
					when X"21" => key_C <= not releaseFlag; 
					when X"22" => key_X <= not releaseFlag; 
					when X"23" => key_D <= not releaseFlag;
					when X"24" => key_E <= not releaseFlag; 
					when X"25" => key_4 <= not releaseFlag; 
					when X"26" => key_3 <= not releaseFlag; 
					when X"29" => key_space <= not releaseFlag; 
					when X"2A" => key_V <= not releaseFlag; 
					when X"2B" => key_F <= not releaseFlag; 
					when X"2C" => key_T <= not releaseFlag; 
					when X"2D" => key_R <= not releaseFlag; 
					when X"2E" => key_5 <= not releaseFlag; 
					when X"31" => key_N <= not releaseFlag; 
					when X"32" => key_B <= not releaseFlag; 
					when X"33" => key_H <= not releaseFlag; 
					when X"34" => key_G <= not releaseFlag; 
					when X"35" => key_Y <= not releaseFlag; 
					when X"36" => key_6 <= not releaseFlag; 
					when X"3A" => key_M <= not releaseFlag; 
					when X"3B" => key_J <= not releaseFlag; 
					when X"3C" => key_U <= not releaseFlag; 
					when X"3D" => key_7 <= not releaseFlag; 
					when X"3E" => key_8 <= not releaseFlag;
					when X"41" => key_comma <= not releaseFlag; 
					when X"42" => key_K <= not releaseFlag;
					when X"43" => key_I <= not releaseFlag; 
					when X"44" => key_O <= not releaseFlag; 
					when X"45" => key_0 <= not releaseFlag; 
					when X"46" => key_9 <= not releaseFlag; 
					when X"49" => key_dot <= not releaseFlag; 
					when X"4A" => key_slash <= not releaseFlag; 
					when X"4B" => key_L <= not releaseFlag; 
					when X"4C" => key_colon <= not releaseFlag; 
					when X"4D" => key_P <= not releaseFlag; 
					when X"4E" => key_minus <= not releaseFlag;
					when X"52" => key_semicolon <= not releaseFlag; 
					when X"54" => key_at <= not releaseFlag; 
					when X"55" => key_equal <= not releaseFlag;
					when X"59" => if extendedFlag = '0' then key_shiftr <= not releaseFlag; end if;
					when X"5A" => key_Return <= not releaseFlag; 
					when X"5B" => key_star <= not releaseFlag; 
					when X"5D" => key_arrowup <= not releaseFlag;
					when X"6B" => if extendedFlag = '0' then joyKeys(2) <= not releaseFlag; else key_left <= not releaseFlag; end if;
					when X"6C" => key_home <= not releaseFlag; 
					when X"66" => key_del <= not releaseFlag; 
					when X"70" => if extendedFlag = '0' then joyKeys(4) <= not releaseFlag; end if;
					when X"72" => if extendedFlag = '0' then joyKeys(1) <= not releaseFlag; else key_down <= not releaseFlag; end if;
					when X"74" => if extendedFlag = '0' then joyKeys(3) <= not releaseFlag; else key_right <= not releaseFlag; end if;
					when X"75" => if extendedFlag = '0' then joyKeys(0) <= not releaseFlag; else key_up <= not releaseFlag; end if;
					when X"76" => key_runstop <= not releaseFlag;
					when X"7D" => if extendedFlag = '1' then tapPlayStopKey <= not releaseFlag; end if; -- pg up
					when others => null;
					end case;
				end if;
			end if;
		end if;
	end process;
end architecture;
