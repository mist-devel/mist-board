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
	clk32 : in std_logic;
	restart_tape : in std_logic; -- keep to 1 to long enough to clear fifo
	                             -- reset tap header bytes skip counter
										  
	wav_mode : in std_logic;    -- 1 for wav mode, 0 for tap mode 
	tap_mode1 : in std_logic;   -- 1 for tap version 1, 0 for tap version 0 

	host_tap_in : in std_logic_vector(7 downto 0);  -- 8bits fifo input
	host_tap_wrreq : in std_logic;                      -- set to 1 for 1 clk32 to write 1 word
	tap_fifo_wrfull : out std_logic;                    -- do not write when fifo tap_fifo_full = 1

	tap_fifo_error : out std_logic;                     -- fifo fall empty (unrecoverable error)

	play : in  std_logic;  -- 1 = read tape, 0 = stop reading 
	do   : out std_logic   -- tape signal out 

);
end c1530;

architecture struct of c1530 is

signal tap_player_tick_cnt : std_logic_vector( 5 downto 0);
signal wav_player_tick_cnt : std_logic_vector(11 downto 0);
signal tap_dword : std_logic_vector(31 downto 0);
signal wave_cnt  : std_logic_vector(23 downto 0);
signal wave_len  : std_logic_vector(23 downto 0);

signal tap_fifo_do : std_logic_vector(7 downto 0);
signal tap_fifo_rdreq : std_logic;
signal tap_fifo_empty : std_logic;
signal get_24bits_len : std_logic;
signal start_bytes : std_logic_vector(7 downto 0);
signal skip_bytes : std_logic;
signal playing : std_logic;

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
	q	    => tap_fifo_do,
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
		playing <= '0';

		tap_fifo_rdreq <='0';
		tap_fifo_error <='0'; -- run out of data

	elsif rising_edge(clk32) then

		tap_fifo_rdreq <= '0';
		if playing = '0' then 
			tap_fifo_error <= '0';
			wave_cnt <= (others => '0');
			wave_len <= (others => '0');
			tap_player_tick_cnt <= (others => '0');
			wav_player_tick_cnt <= (others => '0');
		end if;
		if play = '1' then playing <= '1'; end if;

		if ((playing = '1') and (wav_mode = '1')) then

			-- Wav player required a large depth fifo to give chance
			-- fifo not falling empty while host go reading next sd card sector
			-- (fifo is read every ~22µs, host have to be faster than 11ms to read sd sector)

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
			do <= not tap_fifo_do(7); -- only use msb (wav data is either xFF or x00/x01)

		end if; -- play wav mode		

		-- tap player

		if ((playing = '1') and (wav_mode = '0')) then

			tap_player_tick_cnt <= tap_player_tick_cnt + '1';

--			if ((tap_player_tick_cnt = "100000") and (skip_bytes = '0')) then -- divide by 33
			if ((tap_player_tick_cnt = "011111") and (skip_bytes = '0')) then -- divide by 32

				-- square wave period (1/2 duty cycle not mendatory, only falling edge matter)
				if wave_cnt > '0'&wave_len(10 downto 1) then
					do <= '1';
				else
					do <= '0';
				end if;	

				tap_player_tick_cnt <= "000000"; 
				wave_cnt <= wave_cnt + 1;

				if wave_cnt >= wave_len then
					wave_cnt <= (others => '0');
					if play = '0' then
						playing <= '0';
						do <= '0';
					else
						if tap_fifo_empty = '1' then
							tap_fifo_error <= '1';
						else
							tap_fifo_rdreq <= '1';
							if tap_fifo_do = x"00" then
								wave_len <= x"000100"; -- interpret data x00 for mode 0
								get_24bits_len <= tap_mode1;
							else
								wave_len <= '0'&x"000" & tap_fifo_do & "000";
							end if;
						end if;
					end if;
				end if;
			end if; -- tap_player_tick_cnt = "100000"

			-- catch 24bits wave_len for data x00 in tap mode 1
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

				do <= '1';
			end if;

			-- skip tap header bytes
			if (skip_bytes = '1' and tap_fifo_empty = '0') then
				tap_fifo_rdreq <= '1';			
				do <= '1';
				if start_bytes < X"1A" then -- little more than x14 
					start_bytes <= start_bytes + X"01";
				else
					skip_bytes <= '0';
				end if;
			end if;

		end if; -- play tap mode

	end if; -- clk32
end process;

end struct;
