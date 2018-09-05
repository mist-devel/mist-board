-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------
--
-- 6526 Complex Interface Adapter
--
-- rev 1 - june17 / TOD alarms
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

-- -----------------------------------------------------------------------

entity cia6526 is
	generic (
		todEnabled : std_logic := '1'
	);
	port (
		clk: in std_logic;
		todClk: in std_logic;
		reset: in std_logic;
		enable: in std_logic;
		cs: in std_logic;
		we: in std_logic; -- Write strobe
		rd: in std_logic; -- Read strobe

		addr: in unsigned(3 downto 0);
		di: in unsigned(7 downto 0);
		do: out unsigned(7 downto 0);

		ppai: in unsigned(7 downto 0);
		ppao: out unsigned(7 downto 0);
		ppad: out unsigned(7 downto 0);

		ppbi: in unsigned(7 downto 0);
		ppbo: out unsigned(7 downto 0);
		ppbd: out unsigned(7 downto 0);

		flag_n: in std_logic;

		irq_n: out std_logic
	);
end cia6526;

-- -----------------------------------------------------------------------

architecture Behavioral of cia6526 is
	-- IO ports
	signal pra: unsigned(7 downto 0);
	signal prb: unsigned(7 downto 0);
	signal ddra: unsigned(7 downto 0);
	signal ddrb: unsigned(7 downto 0);
	
	-- Timer to IO ports
	signal timerAPulse : std_logic;
	signal timerAToggle : std_logic;
	signal timerBPulse : std_logic;
	signal timerBToggle : std_logic;

	-- Timer A reload registers
	signal talo: unsigned(7 downto 0) := (others => '1');
	signal tahi: unsigned(7 downto 0) := (others => '1');

	-- Timer B reload registers
	signal tblo: unsigned(7 downto 0) := (others => '1');
	signal tbhi: unsigned(7 downto 0) := (others => '1');

	-- Timer A and B internal registers
	signal timerA : unsigned(15 downto 0);
	signal forceTimerA : std_logic;
	signal loadTimerA : std_logic;
	signal clkTimerA : std_logic; -- internal timer clock

	signal timerB: unsigned(15 downto 0);
	signal forceTimerB : std_logic;
	signal loadTimerB : std_logic;
	signal clkTimerB : std_logic; -- internal timer clock
	
	signal WR_Delay_offset : std_logic; -- adjustable WR signal delay - LCA jun17

	-- Config register A
	signal cra_start : std_logic;
	signal cra_pbon : std_logic;
	signal cra_outmode : std_logic;
	signal cra_runmode : std_logic;
	signal cra_runmode_reg : std_logic;
	signal cra_inmode : std_logic;
	signal cra_spmode : std_logic;
	signal cra_todin : std_logic;
	
	-- Config register B
	signal crb_start : std_logic;
	signal crb_pbon : std_logic;
	signal crb_outmode : std_logic;
	signal crb_runmode : std_logic;
	signal crb_runmode_reg : std_logic;
	signal crb_inmode5 : std_logic;
	signal crb_inmode6 : std_logic;
	signal crb_alarm : std_logic;

	-- TOD 50/60 hz clock
	signal todTick : std_logic;
	signal oldTodClk : std_logic;
	signal tod_clkcnt: unsigned(2 downto 0);

	-- TOD counters
	signal tod_running: std_logic;
	signal tod_10ths: unsigned(3 downto 0);
	signal tod_secs: unsigned(6 downto 0);
	signal tod_mins: unsigned(6 downto 0);
	signal tod_hrs: unsigned(7 downto 0);
	signal tod_pm: std_logic;
	
	-- TOD latches
	signal tod_latched: std_logic;
	signal tod_latch_10ths: unsigned(3 downto 0);
	signal tod_latch_secs: unsigned(6 downto 0);
	signal tod_latch_mins: unsigned(6 downto 0);
	signal tod_latch_hrs: unsigned(7 downto 0);
	constant tod_latch_pm: std_logic := '0';

	-- TOD alarms - LCA
	signal tod_10ths_alarm: unsigned(3 downto 0);
	signal tod_secs_alarm: unsigned(6 downto 0);
	signal tod_mins_alarm: unsigned(6 downto 0);
	signal tod_hrs_alarm: unsigned(7 downto 0);
	signal tod_pm_alarm: std_logic;
	
	-- Interrupt processing
	signal resetIrq : boolean;
	signal intr_flagn : std_logic;
	signal intr_serial : std_logic;
	signal intr_alarm : std_logic; -- LCA
	signal intr_timerA : std_logic;
	signal intr_timerB : std_logic;
	signal mask_timerA : std_logic;
	signal mask_timerB : std_logic;
	signal mask_alarm : std_logic; -- LCA
	signal mask_serial : std_logic;
	signal mask_flagn : std_logic;
	signal ir: std_logic;

	signal prevFlag_n: std_logic;

	signal myWr : std_logic;
	signal myRd : std_logic;
begin
-- -----------------------------------------------------------------------
-- chip-select signals
-- -----------------------------------------------------------------------
	myWr <= cs and we;
	myRd <= cs and rd;

-- -----------------------------------------------------------------------
-- I/O ports
-- -----------------------------------------------------------------------
	-- Port A
	process(pra, ddra)
	begin
		ppad <= ddra;
		ppao <= pra or (not ddra);
	end process;

	-- Port B
	process(prb, ddrb, cra_pbon, cra_outmode, crb_pbon, crb_outmode, timerAPulse, timerAToggle, timerBPulse, timerBToggle)
	begin
		ppbd <= ddrb;
		ppbo <= prb or (not ddrb);
		if cra_pbon = '1' then
			ppbo(6) <= timerAPulse or (not ddrb(6));
			if cra_outmode = '1' then
				ppbo(6) <= timerAToggle or (not ddrb(6));
			end if;
		end if;
		if crb_pbon = '1' then
			ppbo(7) <= timerBPulse or (not ddrb(7));
			if crb_outmode = '1' then
				ppbo(7) <= timerBToggle or (not ddrb(7));
			end if;
		end if;
	end process;
	
	-- I/O port registers
	process(clk)
	begin
		if rising_edge(clk) then
			if myWr = '1' then
				case addr is
				when X"0" => pra <= di;
				when X"1" => prb <= di;
				when X"2" => ddra <= di;
				when X"3" => ddrb <= di;
				when others => null;
				end case;
			end if;
			if reset = '1' then
				pra <= (others => '0');
				prb <= (others => '0');
				ddra <= (others => '0');
				ddrb <= (others => '0');
			end if;
		end if;	
	end process;

-- -----------------------------------------------------------------------
-- TOD - time of day
-- -----------------------------------------------------------------------
	process(clk)
	begin
		-- Process rising edge on the todClk.
		-- There is a prescaler of 5 or 6 to get 10ths of seconds from
		-- 50 Hz or 60 Hz line frequency.
		--
		-- Output is a 'todTick' signal synchronished with enable signal (@ 1Mhz).
		if rising_edge(clk) then			
			if todEnabled = '1' then
				if enable = '1' then
					todTick <= '0';
				end if;

				if todClk = '1' and oldTodClk = '0' then
					-- Divide by 5 or 6 dependng on 50/60 Hz flag.
					if tod_clkcnt /= "000" then
						tod_clkcnt <= tod_clkcnt - 1;
					else
						todTick <= tod_running;
						tod_clkcnt <= "101"; -- 60 Hz
						if cra_todin = '1' then
							tod_clkcnt <= "100"; -- 50 Hz
						end if;
					end if;
				end if;
				oldTodClk <= todClk;
			else
				todTick <= '0';
			end if;
		end if;
	end process;

	process(clk)
		variable new_10ths : unsigned(3 downto 0);
		variable new_secsL : unsigned(3 downto 0);
		variable new_secsH : unsigned(2 downto 0);
		variable new_minsL : unsigned(3 downto 0);
		variable new_minsH : unsigned(2 downto 0);
		variable new_hrsL : unsigned(3 downto 0);
		variable new_hrsH : std_logic;
		variable new_hrs_byte : unsigned(7 downto 0); -- LCA am/pm and hours
	begin
		if rising_edge(clk) then
			new_10ths := tod_10ths;
			new_secsL := tod_secs(3 downto 0);
			new_secsH := tod_secs(6 downto 4);
			new_minsL := tod_mins(3 downto 0);
			new_minsH := tod_mins(6 downto 4);
--			new_hrsL := tod_hrs(3 downto 0);
--			new_hrsH := tod_hrs(4);
			new_hrs_byte := tod_hrs (7 downto 0); -- LCA am/pm and hours
--			new_hrs_byte := new_hrsH & new_hrsL;
			
			if enable = '1'
			and todTick = '1' then
				if new_10ths /= "1001" then
					new_10ths := new_10ths + 1;
				else
					new_10ths := "0000";
					if new_secsL /= "1001" then
						new_secsL := new_secsL + 1;
					else
						new_secsL := "0000";
						if new_secsH /= "101" then
							new_secsH := new_secsH + 1;
						else
							new_secsH := "000";
							if new_minsL /= "1001" then
								new_minsL := new_minsL + 1;
							else
								new_minsL := "0000";
								if new_minsH /= "101" then
									new_minsH := new_minsH + 1;
								else
									new_minsH := "000";
									-- hrs were missing jun17 LCA
									-- I mean completely absent from code :) !!!!!!
									-- case to lookup then handles oddities in others
									-- retarded am/pm flag flip madness handled at register load below (REG B)
									
									case tod_hrs is											-- case state to set hours and am/pm 
										when "00010010" =>
											new_hrs_byte := "00000001";					-- 1 am set
										when "00000001" => 
											new_hrs_byte := "00000010";
										when "00000010" => 
											new_hrs_byte := "00000011";
										when "00000011" => 
											new_hrs_byte := "00000100";
										when "00000100" => 
											new_hrs_byte := "00000101";
										when "00000101" => 
											new_hrs_byte := "00000110";
										when "00000110" => 
											new_hrs_byte := "00000111";
										when "00000111" => 
											new_hrs_byte := "00001000";
										when "00001000" => 
											new_hrs_byte := "00001001";
										when "00001001" => 
											new_hrs_byte := "00010000";
										when "00010000" => 
											new_hrs_byte := "00010001";					-- 11am set
										when "00010001" => 
											new_hrs_byte := "10010010";					-- 12pm set
										when "10010010" => 
											new_hrs_byte := "10000001";					-- 1 pm set
										
										when "10000001" => 
											new_hrs_byte := "10000010";
										when "10000010" => 
											new_hrs_byte := "10000011";
										when "10000011" => 
											new_hrs_byte := "10000100";
										when "10000100" => 
											new_hrs_byte := "10000101";
										when "10000101" => 
											new_hrs_byte := "10000110";
										when "10000110" => 
											new_hrs_byte := "10000111";
										when "10000111" => 
											new_hrs_byte := "10001000";
										when "10001000" => 
											new_hrs_byte := "10001001";
										when "10001001" => 
											new_hrs_byte := "10010000";					-- 10pm set
										when "10010000" => 
											new_hrs_byte := "10010001";					-- 11pm set
										when "10010001" => 
											new_hrs_byte := "00010010";					-- 12am set (midnight)
										when others =>
											new_hrs_byte (3 downto 0) := new_hrs_byte (3 downto 0) + 1;
											--null;
									end case;
										
								end if;
							end if;
						end if;
					end if;
				end if;
			end if;

			if myWr = '1' then
				if crb_alarm = '0' then
					case addr is
					when X"8" =>
						new_10ths := di(3 downto 0);
						tod_running <= '1';
					when X"9" =>
						new_secsL := di(3 downto 0);
						new_secsH := di(6 downto 4);
					when X"A" =>
						new_minsL := di(3 downto 0);
						new_minsH := di(6 downto 4);
					when X"B" =>
						new_hrs_byte := di(7) & "00" & di(4 downto 0); 			-- LCA
						tod_running <= '0';
						if di(7 downto 0) = "10010010" or di(7 downto 0) = "00010010" then  -- super bodge because cbm flips am/pm flag at 12 am or pm (its retarded!!!!!)
							new_hrs_byte(7) := not new_hrs_byte(7);								  -- This P.O.S. now mimics real commodore 64 !!!!! LCA
						end if;
					when others =>
						null;
					end case;
				else -- TOD ALARM UPDATE
					case addr is
					when X"8" =>
						tod_10ths_alarm <= di(3 downto 0);
					when X"9" =>
						tod_secs_alarm <= di(6 downto 0);
					when X"A" =>
						tod_mins_alarm <= di(6 downto 0);
					when X"B" =>
--						tod_hrs_alarm <= di(4 downto 0);
--						tod_pm_alarm <= di(7);
						tod_hrs_alarm <= di(7) & "00" & di(4 downto 0); 		-- LCA
						if di(7 downto 0) = "10010010" or di(7 downto 0) = "00010010" then  -- super bodge because cbm flips am/pm flag at 12 am or pm (its retarded!!!!!)
							tod_hrs_alarm(7) <= not tod_hrs_alarm(7);								  -- This P.O.S. now mimics real commodore 64 !!!!! LCA
						end if;
					when others =>
						null;
					end case;
				end if;
			end if;
			
			-- Update state
			tod_10ths <= new_10ths;
			tod_secs <= new_secsH & new_secsL;
			tod_mins <= new_minsH & new_minsL;
			tod_hrs <= new_hrs_byte; 								-- LCA
			
			if tod_latched = '0' then
				tod_latch_10ths <= new_10ths;
				tod_latch_secs <= new_secsH & new_secsL;
				tod_latch_mins <= new_minsH & new_minsL;
				tod_latch_hrs <= new_hrs_byte;					-- LCA
			end if;
			
			-- TOD ALARM test for match - LCA
			if (tod_10ths = tod_10ths_alarm) and
				(tod_secs = tod_secs_alarm) and
				(tod_mins = tod_mins_alarm) and
				(tod_hrs = tod_hrs_alarm) and
				(crb_alarm = '1') then
				intr_alarm <= '1' ;
			end if;
			
			if reset = '1' then
				tod_running <= '0';
				tod_10ths_alarm <= "0000" ;
				tod_secs_alarm <= "0000000" ;
				tod_mins_alarm <= "0000000" ;
				tod_hrs_alarm <= "00000000" ;
				tod_pm_alarm <= '0' ;
			end if;
			
			if resetIrq then 
				intr_alarm <= '0' ;
			end if;
		end if;		
	end process;
	
	-- Control TOD output latch
	-- Reading the hours latches the output until
	-- the 10ths of seconds are read. While latched the
	-- clock continues to run in the bankground.
	process(clk)
	begin
		if rising_edge(clk) then
			if myRd = '1' then
				case addr is
				when X"8" => tod_latched <= '0';
				when X"B" => tod_latched <= '1';
				when others => null;
				end case;
			end if;
		end if;		
	end process;


-- -----------------------------------------------------------------------
-- Timer A and B
-- -----------------------------------------------------------------------


-- adjustable time delay jun17 - LCA

-- -----------------------------------------------------------------------
-- -----------------------------------------------------------------------

	process(clk)
		variable WR_delay : unsigned(15 downto 0);
	begin
		if rising_edge(clk) then
			if (myWr = '0' or reset =  '1') then
				WR_delay := "0000000000000000";
				WR_Delay_offset <= '0';
--			end if;
			elsif (myWr = '1' and (WR_delay < 31)) then
				WR_delay := WR_delay + 1;
--			end if;
			elsif (WR_delay > 8) then               -- adds a (1/32mhz * value) qualifier to WR signal in timers - LCA jun17
				WR_Delay_offset <= '1';
				else
				WR_Delay_offset <= '0';
			end if;
		end if;		
	end process;
	
-- -----------------------------------------------------------------------

	process(clk)
		variable newTimerA : unsigned(15 downto 0);
		variable nextClkTimerA : std_logic;
		variable timerBInput : std_logic;
		variable newTimerB : unsigned(15 downto 0);
		variable nextClkTimerB : std_logic;
		variable new_cra_runmode : std_logic;
		variable new_crb_runmode : std_logic;
	begin		
		if rising_edge(clk) then
			loadTimerA <= '0';
			loadTimerB <= '0';
			new_cra_runmode := cra_runmode;
			new_crb_runmode := crb_runmode;
			
			if resetIrq then
				intr_timerA <= '0';
				intr_timerB <= '0';
			end if;

			if myWr = '1' then
--			if (myWr = '1' and WR_Delay_offset = '1') then         -- x/32mhz offset to qualify WR signal LCA jun17
				case addr is
				when X"4" =>
					talo <= di;
				when X"5" =>
					tahi <= di;
					if cra_start = '0' then
						loadTimerA <= '1';
					end if;
				when X"6" =>
					tblo <= di;
				when X"7" =>
					tbhi <= di;
					if crb_start = '0' then
						loadTimerB <= '1';
					end if;
				when X"E" =>
					if cra_start = '0' then
						-- Only set on rising edge
						timerAToggle <= timerAToggle or di(0);
					end if;
					cra_start <= di(0);
					new_cra_runmode := di(3);
				when X"F" =>
					if crb_start = '0' then
						-- Only set on rising edge
						timerBToggle <= timerBToggle or di(0);
					end if;
					crb_start <= di(0);
					new_crb_runmode := di(3);
				when others => null;
				end case;
			end if;
			
			if reset = '1' then
				new_cra_runmode := '0';
				new_crb_runmode := '0';
			end if;
			
			cra_runmode <= new_cra_runmode;
			crb_runmode <= new_crb_runmode;

			if enable = '1' then
				--
				-- process timer A
				--
				timerAPulse <= '0';
				newTimerA := timerA;
				
				-- CNT is not emulated so don't count when inmode = 1
				nextClkTimerA := cra_start and (not cra_inmode);
				if clkTimerA = '1' then
					newTimerA := newTimerA - 1;
				end if;
				if nextClkTimerA = '1'
				and newTimerA = 0 then
					intr_timerA <= '1';
					loadTimerA <= '1';
					timerAPulse <= '1';
					timerAToggle <= not timerAToggle;
					if (new_cra_runmode or cra_runmode) = '1' then
						cra_start <= '0';
					end if;
				end if;
				if forceTimerA = '1' then
					loadTimerA <= '1';
				end if;
				clkTimerA <= nextClkTimerA;
				timerA <= newTimerA;
					
				--
				-- process timer B
				--
				timerBPulse <= '0';
				newTimerB := timerB;

				if crb_inmode6 = '1' then
					-- count timerA underflows
					timerBInput := timerAPulse;
				elsif crb_inmode5 = '0' then
					-- count clock pulses
					timerBInput := '1'; 
				else
					-- CNT is not emulated so don't count
					timerBInput := '0';
				end if;
				nextClkTimerB := timerBInput and crb_start;
				if clkTimerB = '1' then
					newTimerB := newTimerB - 1;
				end if;				
				if nextClkTimerB = '1'
				and newTimerB = 0 then
					intr_timerB <= '1';
					loadTimerB <= '1';
					timerBPulse <= '1';
					timerBToggle <= not timerBToggle;
					if (new_crb_runmode or crb_runmode) = '1' then
						crb_start <= '0';
					end if;
				end if;
				if forceTimerB = '1' then
					loadTimerB <= '1';
				end if;
				clkTimerB <= nextClkTimerB;
				timerB <= newTimerB;
			end if;

			if loadTimerA = '1' then
				timerA <= tahi & talo;
				clkTimerA <= '0';
			end if;

			if loadTimerB = '1' then
				timerB <= tbhi & tblo;
				clkTimerB <= '0';
			end if;
		end if;
	end process;


-- -----------------------------------------------------------------------
-- Interrupts
-- -----------------------------------------------------------------------
	resetIrq <= ((myRd = '1') and (addr = X"D")) or (reset = '1');
	irq_n <= not(ir);
	intr_serial <= '0';

	process(clk)
	begin
		if rising_edge(clk) then
			if enable = '1' then
				ir <= ir
				or (intr_timerA and mask_timerA)
				or (intr_timerB and mask_timerB)
				or (intr_alarm and mask_alarm)
				or (intr_serial and mask_serial)
				or (intr_flagn and mask_flagn);
			end if;

			if myWr = '1' then
				case addr is
				when X"D" =>
					if di(7) ='0' then
						mask_timerA <= mask_timerA and (not di(0));
						mask_timerB <= mask_timerB and (not di(1));
						mask_alarm <= mask_alarm and (not di(2)); -- LCA
						mask_serial <= mask_serial and (not di(3));
						mask_flagn <= mask_flagn and (not di(4));
					else
						mask_timerA <= mask_timerA or di(0);
						mask_timerB <= mask_timerB or di(1);
						mask_alarm <= mask_alarm or di(2); -- LCA
						mask_serial <= mask_serial or di(3);
						mask_flagn <= mask_flagn or di(4);
					end if;
				when others =>
					null;
				end case;
			end if;

			if resetIrq then
				ir <= '0';
			end if;

			if reset = '1' then
				mask_timerA <= '0';
				mask_timerB <= '0';
				mask_alarm <= '0' ;
				mask_serial <= '0';
				mask_flagn <= '0';
			end if;
		end if;
	end process;




-- -----------------------------------------------------------------------
-- FLAG_N input
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			prevFlag_n <= flag_n;
			if (flag_n = '0') and (prevFlag_n = '1') then
				intr_flagn <= '1';
			end if;
			if resetIrq then
				intr_flagn <= '0';
			end if;
		end if;
	end process;


-- -----------------------------------------------------------------------
-- Write registers
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
--			resetIrq <= '0';
			if enable = '1' then
				forceTimerA <= '0';
				forceTimerB <= '0';
--				cra_runmode_reg <= cra_runmode;
--				crb_runmode_reg <= crb_runmode;
			end if;
			if myWr = '1' then
				case addr is
				when X"E" =>
					cra_pbon <= di(1);
					cra_outmode <= di(2);
--					cra_runmode <= di(3);
					forceTimerA <= di(4);
					cra_inmode <= di(5);
					cra_spmode <= di(6);
					cra_todin <= di(7);
				when X"F" =>
					crb_pbon <= di(1);
					crb_outmode <= di(2);
--					crb_runmode <= di(3);
					forceTimerB <= di(4);
					crb_inmode5 <= di(5);
					crb_inmode6 <= di(6);
					crb_alarm <= di(7);
				when others => null;
				end case;
			end if;
			if reset = '1' then
				cra_pbon <= '0';
				cra_outmode <= '0';
--				cra_runmode <= '0';
				cra_inmode <= '0';
				cra_spmode <= '0';
				cra_todin <= '0';
				crb_pbon <= '0';
				crb_outmode <= '0';
--				crb_runmode <= '0';
				crb_inmode5 <= '0';
				crb_inmode6 <= '0';
				crb_alarm <= '0';
			end if;
		end if;
	end process;


-- -----------------------------------------------------------------------
-- Read registers
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			case addr is
			when X"0" => do <= ppai;
			when X"1" => do <= ppbi;
			when X"2" => do <= DDRA;
			when X"3" => do <= DDRB;
			when X"4" => do <= timera(7 downto 0);
			when X"5" => do <= timera(15 downto 8);
			when X"6" => do <= timerb(7 downto 0);
			when X"7" => do <= timerb(15 downto 8);
			when X"8" => do <= "0000" & tod_latch_10ths;
			when X"9" => do <= "0" & tod_latch_secs;
			when X"A" => do <= "0" & tod_latch_mins;
--			when X"B" => do <= tod_latch_pm & "00" & tod_latch_hrs;
			when X"B" => do <= tod_latch_hrs; -- LCA
			when X"C" => do <= (others => '0');
			when X"D" => do <= ir & "00" & intr_flagn & intr_serial & intr_alarm & intr_timerB & intr_timerA;
			when X"E" => do <= cra_todin & cra_spmode & cra_inmode & '0' & cra_runmode & cra_outmode & cra_pbon & cra_start;
			when X"F" => do <= crb_alarm & crb_inmode6 & crb_inmode5 & '0' & crb_runmode & crb_outmode & crb_pbon & crb_start;
			when others => do <= (others => '-');
			end case;
		end if;
	end process;
end Behavioral;
