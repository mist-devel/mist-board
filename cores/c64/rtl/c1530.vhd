---------------------------------------------------------------------------------
-- Commodore 1530 to SD card host (read only) by Dar (darfpga@aol.fr) 25-Mars-2019
-- http://darfpga.blogspot.fr
-- also darfpga on sourceforge
--
-- tap/wav player 
-- Converted to 8 bit FIFO - Slingshot
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity c1530 is
port(
	clk32           : in std_logic;
	restart_tape    : in std_logic; -- keep to 1 to long enough to clear fifo
	                                -- reset tap header bytes skip counter
										  
	wav_mode        : in std_logic;   -- 1 for wav mode, 0 for tap mode 
	tap_version     : in std_logic;   -- tap file version (0 or 1) 

	host_tap_in     : in std_logic_vector(7 downto 0);  -- 8bits fifo input
	host_tap_wrreq  : in std_logic;                     -- set to 1 for 1 clk32 to write 1 word
	tap_fifo_wrfull : out std_logic;                    -- do not write when fifo tap_fifo_full = 1
	tap_fifo_error  : out std_logic;                    -- fifo fall empty (unrecoverable error)

	osd_play_stop_toggle : in  std_logic;  -- PLAY/STOP toggle button from OSD	
	
	cass_sense : out std_logic;   -- 0 = PLAY/REW/FF/REC button is pressed
	cass_read  : out std_logic;   -- tape read signal
	cass_write : in  std_logic;   -- signal to write on tape (not used)
	cass_motor : in  std_logic;   -- 0 = tape motor is powered
	
	ear_input  : in  std_logic    -- tape input from EAR port
);
end c1530;

architecture struct of c1530 is

signal tap_player_tick_cnt : std_logic_vector( 5 downto 0);
signal wav_player_tick_cnt : std_logic_vector(11 downto 0);
signal tap_dword           : std_logic_vector(31 downto 0);
signal wave_cnt            : std_logic_vector(23 downto 0);
signal wave_len            : std_logic_vector(23 downto 0);

signal tap_fifo_do    : std_logic_vector(7 downto 0);
signal tap_fifo_rdreq : std_logic;
signal tap_fifo_empty : std_logic;
signal get_24bits_len : std_logic;
signal start_bytes    : std_logic_vector(7 downto 0);
signal skip_bytes     : std_logic;
signal playing        : std_logic;  -- 1 = tap or wav file is playing

signal osd_play_stop_toggleD : std_logic;  -- for detecting change in the OSD toggle button
signal sense                 : std_logic;  -- status of the PLAY/STOP tape button

signal ear_inputD            : std_logic;                     -- for detecting input from EAR port
signal ear_input_detected    : std_logic;                     -- 1=input from EAR port was detected
signal ear_autostop_counter  : std_logic_vector(28 downto 0); -- counter for stopping after a delay when ear is no longer detected

constant autostop_time: std_logic_vector(28 downto 0) := std_logic_vector(to_unsigned(32000000 * 5, ear_autostop_counter'length)); -- about 5 seconds
    
begin

-- for wav mode use large depth fifo (eg 512 x 32bits)
-- for tap mode fifo may be smaller (eg 16 x 32bits)
tap_fifo_inst : entity work.tap_fifo
port map(
	aclr	 => restart_tape,
	data	 => host_tap_in,
	clock	 => clk32,
	rdreq	 => tap_fifo_rdreq,
	wrreq	 => host_tap_wrreq,
	q	     => tap_fifo_do,
	empty	 => tap_fifo_empty,
	full	 => tap_fifo_wrfull
);

process(clk32, restart_tape)
begin

	if restart_tape = '1' then
		
		start_bytes <= X"00";
		skip_bytes <= '1';
		tap_player_tick_cnt <= (others => '0');
		wav_player_tick_cnt <= (others => '0');
		wave_len <= (others => '0');
		wave_cnt <= (others => '0');
		get_24bits_len <= '0';

		tap_fifo_rdreq <='0';
		tap_fifo_error <='0'; -- run out of data
		
		sense <= '1'; -- STOP tape

	elsif rising_edge(clk32) then

		-- detect OSD PLAY/STOP button press
		osd_play_stop_toggleD <= osd_play_stop_toggle;
		if osd_play_stop_toggleD = '0' and osd_play_stop_toggle = '1' then
			sense <= not sense;				
		end if;
		
		-- detect EAR input
		ear_inputD <= ear_input;
		if ear_inputD /= ear_input then
			ear_input_detected <= '1';
			ear_autostop_counter <= autostop_time;
		end if;
	
	  -- EAR input
    if ear_input_detected='1' then 	
			sense <= '0'; -- automatically press PLAY		
			cass_read <= not ear_input;
			
			-- autostop 
		  if ear_autostop_counter = 0 then
				ear_input_detected <= '0';
				sense <= '1'; -- automatically press STOP
			else
				ear_autostop_counter <= ear_autostop_counter - "1";  	
			end if;			
		end if;
		
		playing <= (not cass_motor) and (not sense) and (not ear_input_detected);  -- cass_motor and sense are low active

		tap_fifo_rdreq <= '0';
		if playing = '0' then 
			tap_fifo_error <= '0';
			wave_cnt <= (others => '0');
			wave_len <= (others => '0');
			tap_player_tick_cnt <= (others => '0');
			wav_player_tick_cnt <= (others => '0');
		end if;		

		if (playing = '1') and (wav_mode = '1') then

			-- Wav player required a large depth fifo to give chance
			-- fifo not falling empty while host go reading next sd card sector
			-- (fifo is read every ~22Âµs, host have to be faster than 11ms to read sd sector)

			wav_player_tick_cnt <= wav_player_tick_cnt + '1';
		
			if wav_player_tick_cnt = x"2F0" then -- ~33MHz/44.1KHz
	
				wav_player_tick_cnt <= (others => '0');

				-- check for empty fifo (unrecoverable error)
				if tap_fifo_empty = '1' then
					tap_fifo_error <= '1';
				else
					tap_fifo_rdreq <= '1';
				end if;

			end if;
			cass_read <= not tap_fifo_do(7); -- only use msb (wav data is either xFF or x00/x01)

		end if; -- play wav mode		

		-- tap player

		if (playing = '1') and (wav_mode = '0') then

			tap_player_tick_cnt <= tap_player_tick_cnt + '1';

--			if ((tap_player_tick_cnt = "100000") and (skip_bytes = '0')) then -- divide by 33
			if ((tap_player_tick_cnt = "011111") and (skip_bytes = '0')) then -- divide by 32

				-- square wave period (1/2 duty cycle not mendatory, only falling edge matter)
				if wave_cnt > '0' & wave_len(10 downto 1) then
					cass_read <= '1';
				else
					cass_read <= '0';
				end if;	

				tap_player_tick_cnt <= "000000"; 
				wave_cnt <= wave_cnt + 1;

				if wave_cnt >= wave_len then
					wave_cnt <= (others => '0');
					if tap_fifo_empty = '1' then
						tap_fifo_error <= '1';
					else
						tap_fifo_rdreq <= '1';
						if tap_fifo_do = x"00" then
							wave_len <= x"000100"; -- interpret data x00 for tap version 0
							get_24bits_len <= tap_version;
						else
							wave_len <= '0'&x"000" & tap_fifo_do & "000";
						end if;
					end if;
				end if;
			end if; -- tap_player_tick_cnt = "100000"

			-- catch 24bits wave_len for data x00 in tap version 1
			if (get_24bits_len = '1' ) and (skip_bytes = '0') and (tap_player_tick_cnt(0) = '1') then

				if tap_player_tick_cnt = "000101" then 
					get_24bits_len <= '0';
				end if;

				if tap_fifo_empty = '1' then
					tap_fifo_error <= '1';
				else
					tap_fifo_rdreq <= '1';			
					wave_len <= tap_fifo_do & wave_len(23 downto 8);
				end if;

				cass_read <= '1';
			end if;

			-- skip tap header bytes
			if (skip_bytes = '1' and tap_fifo_empty = '0') then
				tap_fifo_rdreq <= '1';			
				cass_read <= '1';
				if start_bytes < X"1A" then -- little more than x14 
					start_bytes <= start_bytes + X"01";
				else
					skip_bytes <= '0';
				end if;
			end if;

		end if; -- play tap

	end if; -- clk32
end process;

cass_sense <= sense;

end struct;
