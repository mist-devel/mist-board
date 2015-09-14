library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

library work;


entity gbc_snd is
  generic
  (
    CLK_FREQ      : integer := 100000000
  );
  port
  (
		clk						: in std_logic;
		reset					: in std_logic;
		
		s1_read				: in std_logic;
		s1_write			: in std_logic;
		s1_addr				: in std_logic_vector(5 downto 0);
		s1_readdata		: out std_logic_vector(7 downto 0);
		s1_writedata	: in std_logic_vector(7 downto 0);
		
		snd_left			: out std_logic_vector(15 downto 0);
		snd_right			: out std_logic_vector(15 downto 0)
  );

end gbc_snd;

architecture SYN of gbc_snd is

	subtype wav_t is std_logic_vector(3 downto 0);
	type wav_arr_t is array(0 to 31) of wav_t;

	--constant clk_freq		: integer := 100000000;
	constant snd_freq		: integer := 4194304;

	signal en_snd				: boolean;	-- Enable at base sound frequency (4.19MHz)
	signal en_snd2			: boolean;	-- Enable at clk/2
	signal en_snd4			: boolean;	-- Enable at clk/4
	signal en_512				: boolean;	-- 512Hz enable 

	signal en_snden2		: boolean;	-- Enable at clk/2
	signal en_snden4		: boolean;	-- Enable at clk/4

	signal en_len				: boolean;	-- Sample length
	signal en_env				: boolean;	-- Envelope
	signal en_sweep			: boolean;	-- Sweep

	signal snd_enable		: std_logic;

	signal sq1_swper		: std_logic_vector(2 downto 0);		-- Sq1 sweep period
	signal sq1_swdir		: std_logic;											-- Sq1 sweep direction
	signal sq1_swshift	: std_logic_vector(2 downto 0);		-- Sq1 sweep frequency shift
	signal sq1_duty			: std_logic_vector(1 downto 0);		-- Sq1 duty cycle
	signal sq1_slen			: std_logic_vector(5 downto 0);		-- Sq1 play length
	signal sq1_svol			: std_logic_vector(3 downto 0);		-- Sq1 initial volume
	signal sq1_envsgn		: std_logic;											-- Sq1 envelope sign
	signal sq1_envper		: std_logic_vector(2 downto 0);		-- Sq1 envelope period
	signal sq1_freq			: std_logic_vector(10 downto 0);	-- Sq1 frequency
	signal sq1_trigger	: std_logic;											-- Sq1 trigger play note
	signal sq1_lenchk		: std_logic;											-- Sq1 length check enable

	signal sq1_fr2			: std_logic_vector(10 downto 0);	-- Sq1 frequency (shadow copy)
	signal sq1_vol			: std_logic_vector(3 downto 0);		-- Sq1 initial volume
	signal sq1_playing	: std_logic;											-- Sq1 channel active
	signal sq1_wav			: std_logic_vector(5 downto 0);		-- Sq1 output waveform

	signal sq2_duty			: std_logic_vector(1 downto 0);		-- Sq2 duty cycle
	signal sq2_slen			: std_logic_vector(5 downto 0);		-- Sq2 play length
	signal sq2_svol			: std_logic_vector(3 downto 0);		-- Sq2 initial volume
	signal sq2_envsgn		: std_logic;											-- Sq2 envelope sign
	signal sq2_envper		: std_logic_vector(2 downto 0);		-- Sq2 envelope period
	signal sq2_freq			: std_logic_vector(10 downto 0);	-- Sq2 frequency
	signal sq2_trigger	: std_logic;											-- Sq2 trigger play note
	signal sq2_lenchk		: std_logic;											-- Sq2 length check enable

	signal sq2_fr2			: std_logic_vector(10 downto 0);	-- Sq2 frequency (shadow copy)
	signal sq2_vol			: std_logic_vector(3 downto 0);		-- Sq2 initial volume
	signal sq2_playing	: std_logic;											-- Sq2 channel active
	signal sq2_wav			: std_logic_vector(5 downto 0);		-- Sq2 output waveform

	signal wav_enable		: std_logic;											-- Wave enable
	signal wav_slen			: std_logic_vector(7 downto 0);		-- Wave play length
	signal wav_volsh		: std_logic_vector(1 downto 0);		-- Wave volume shift
	signal wav_freq			: std_logic_vector(10 downto 0);	-- Wave frequency
	signal wav_trigger		: std_logic;											-- Wave trigger play note
	signal wav_lenchk		: std_logic;											-- Wave length check enable

	signal wav_fr2			: std_logic_vector(10 downto 0);	-- Wave frequency (shadow copy)
	signal wav_playing	: std_logic;
	signal wav_wav			: std_logic_vector(5 downto 0);		-- Wave output waveform
	signal wav_ram			: wav_arr_t;											-- Wave table
	signal wav_shift		: boolean;

	signal noi_slen			: std_logic_vector(5 downto 0);
	signal noi_svol			: std_logic_vector(3 downto 0);
	signal noi_envsgn		: std_logic;
	signal noi_envper		: std_logic_vector(2 downto 0);
	signal noi_freqsh		: std_logic_vector(3 downto 0);
	signal noi_short		: std_logic;
	signal noi_div			: std_logic_vector(2 downto 0);
	signal noi_trigger	: std_logic;
	signal noi_lenchk		: std_logic;

	signal noi_fr2			: std_logic_vector(10 downto 0);	-- Noise frequency (shadow copy)
	signal noi_vol			: std_logic_vector(3 downto 0);		-- Noise initial volume
	signal noi_playing	: std_logic;											-- Noise channel active
	signal noi_wav			: std_logic_vector(5 downto 0);		-- Noise output waveform

begin

	en_snd2 <= en_snd and en_snden2;
	en_snd4 <= en_snd and en_snden4;

	en_snd <= true;
	
	-- Calculate base clock enable (4.194304MHz)
--	process(clk, reset)
--    --to_unsigned(snd_freq * 65536 / clk_freq, 16);
		--constant clk_frac		: unsigned(15 downto 0) := X"0ABD"; -- clk_freq=100MHz
--		constant clk_frac		: unsigned(15 downto 0) := X"1991"; -- clk_freq=42MHz
--		variable divacc			: unsigned(15 downto 0);
--		variable acc				: unsigned(16 downto 0);
--	begin
--		if reset = '1' then
--			divacc := (others => '0');
--		elsif rising_edge(clk) then
			-- Sound base divider clock enable
--			acc := ('0'&divacc) + ('0'&clk_frac);
--			en_snd <= (acc(16) = '1');
--			divacc := acc(15 downto 0);
--		end if;
--	end process;

	-- Calculate divided and frame sequencer clock enables
	process(clk, en_snd, reset)
		variable clkcnt			: unsigned(1 downto 0);
		variable cnt_512		: unsigned(12 downto 0);
		variable temp_512		: unsigned(13 downto 0);
		variable framecnt		: integer range 0 to 7 := 0;
	begin
		if reset = '1' then
			clkcnt := "00";
			cnt_512 := (others => '0');
			framecnt := 0;

		elsif rising_edge(clk) then
			-- Base clock divider
			if en_snd then
				clkcnt := clkcnt + 1;
				if clkcnt(0) = '1' then
					en_snden2 <= true;
				else 
					en_snden2 <= false;
				end if;
				if clkcnt = "11" then
					en_snden4 <= true;
				else
					en_snden4 <= false;
				end if;
			end if;

			-- Frame sequencer (length, envelope, sweep) clock enables
			en_len <= false;
			en_env <= false;
			en_sweep <= false;
			if en_512 then
				if framecnt = 0 or framecnt = 2 or framecnt = 4 or framecnt = 6 then
					en_len <= true;
				end if;
				if framecnt = 2 or framecnt = 6 then
					en_sweep <= true;
				end if;
				if framecnt = 7 then
					en_env <= true;
				end if;

				if framecnt < 7 then
					framecnt := framecnt + 1;
				else
					framecnt := 0;
				end if;
			end if;

			--
			en_512 <= false;
			if en_snd then
				temp_512 := ('0'&cnt_512) + to_unsigned(1, temp_512'length);
				cnt_512 := temp_512(temp_512'high-1 downto temp_512'low);
				en_512 <= (temp_512(13) = '1');
			end if;
		end if;
	end process;

	-- Registers
	registers : process(clk, snd_enable, reset)
		variable wav_shift_r		: boolean;
		variable wav_temp				: wav_t;
	begin

		-- Registers
		if snd_enable = '0' then
			-- Reset register values
			sq1_swper		<= (others => '0');
			sq1_swdir		<= '0';
			sq1_swshift	<= (others => '0');
			sq1_duty		<= (others => '0');
			sq1_slen		<= (others => '0');
			sq1_svol		<= (others => '0');
			sq1_envsgn	<= '0';
			sq1_envper	<= (others => '0');
			sq1_freq		<= (others => '0');
			sq1_lenchk	<= '0';
			sq1_trigger	<= '0';

			sq2_duty		<= (others => '0');
			sq2_slen		<= (others => '0');
			sq2_svol		<= (others => '0');
			sq2_envsgn	<= '0';
			sq2_envper	<= (others => '0');
			sq2_freq		<= (others => '0');
			sq2_lenchk	<= '0';
			sq2_trigger	<= '0';

			wav_enable	<= '0';
			wav_volsh		<= (others => '0');
			wav_freq		<= (others => '0');
			wav_trigger	<= '0';
			wav_lenchk	<= '0';
			wav_shift_r := false;

			noi_slen		<= (others => '0');
			noi_svol		<= (others => '0');
			noi_envsgn	<= '0';
			noi_envper	<= (others => '0');
			noi_freqsh	<= (others => '0');
			noi_short		<= '0';
			noi_div			<= (others => '0');
			noi_trigger	<= '0';
			noi_lenchk	<= '0';

		elsif rising_edge(clk) then
			if en_snd then
				sq1_trigger <= '0';
				sq2_trigger <= '0';
				wav_trigger <= '0';
				noi_trigger <= '0';
			end if;

			-- Rotate wave table on rising edge of wav_shift
			if wav_shift and not wav_shift_r then
				wav_temp := wav_ram(0);
				for I in 0 to 30 loop
					wav_ram(I) <= wav_ram(I+1);
				end loop;
				wav_ram(31) <= wav_temp;
			end if;

			if s1_write = '1' then
				case s1_addr is
		       								-- Square 1
				when "010000" =>	-- NR10 FF10 -PPP NSSS Sweep period, negate, shift
					sq1_swper <= s1_writedata(6 downto 4);
					sq1_swdir <= s1_writedata(3);
					sq1_swshift <= s1_writedata(2 downto 0);
				when "010001" =>	-- NR11 FF11 DDLL LLLL Duty, Length load (64-L)
					sq1_duty <= s1_writedata(7 downto 6);
					sq1_slen <= s1_writedata(5 downto 0);
				when "010010" =>	-- NR12 FF12 VVVV APPP Starting volume, Envelope add mode, period
					sq1_svol <= s1_writedata(7 downto 4);
					sq1_envsgn <= s1_writedata(3);
					sq1_envper <= s1_writedata(2 downto 0);
				when "010011" =>	-- NR13 FF13 FFFF FFFF Frequency LSB
					sq1_freq(7 downto 0) <= s1_writedata;
				when "010100" =>	-- NR14 FF14 TL-- -FFF Trigger, Length enable, Frequency MSB
					sq1_trigger <= s1_writedata(7);
					sq1_lenchk <= s1_writedata(6);
					sq1_freq(10 downto 8) <= s1_writedata(2 downto 0);

													-- Square 2
				when "010110" =>	-- NR21 FF16 DDLL LLLL Duty, Length load (64-L)
					sq2_duty <= s1_writedata(7 downto 6);
					sq2_slen <= s1_writedata(5 downto 0);
				when "010111" =>	-- NR22 FF17 VVVV APPP Starting volume, Envelope add mode, period
					sq2_svol <= s1_writedata(7 downto 4);
					sq2_envsgn <= s1_writedata(3);
					sq2_envper <= s1_writedata(2 downto 0);
				when "011000" =>	-- NR23 FF18 FFFF FFFF Frequency LSB
					sq2_freq(7 downto 0) <= s1_writedata;
				when "011001" =>	-- NR24 FF19 TL-- -FFF Trigger, Length enable, Frequency MSB
					sq2_trigger <= s1_writedata(7);
					sq2_lenchk <= s1_writedata(6);
					sq2_freq(10 downto 8) <= s1_writedata(2 downto 0);

													-- Wave
				when "011010" =>	-- NR30 FF1A E--- ---- DAC power
					wav_enable <= s1_writedata(7);
				when "011011" =>	-- NR31 FF1B LLLL LLLL Length load (256-L)
					wav_slen <= s1_writedata;
				when "011100" =>	-- NR32 FF1C -VV- ---- Volume code (00=0%, 01=100%, 10=50%, 11=25%)
					wav_volsh <= s1_writedata(6 downto 5);
				when "011101" =>	-- NR33 FF1D FFFF FFFF Frequency LSB
					wav_freq(7 downto 0) <= s1_writedata;
				when "011110" =>	-- NR34 FF1E TL-- -FFF Trigger, Length enable, Frequency MSB
					wav_trigger <= s1_writedata(7);
					wav_lenchk <= s1_writedata(6);
					wav_freq(10 downto 8) <= s1_writedata(2 downto 0);

													-- Noise
				when "100000" =>	-- NR41 FF20 --LL LLLL Length load (64-L)
					noi_slen <= s1_writedata(5 downto 0);
				when "100001" =>	-- NR42 FF21 VVVV APPP Starting volume, Envelope add mode, period
					noi_svol <= s1_writedata(7 downto 4);
					noi_envsgn <= s1_writedata(3);
					noi_envper <= s1_writedata(2 downto 0);
				when "100010" =>	-- NR43 FF22 SSSS WDDD Clock shift, Width mode of LFSR, Divisor code
					noi_freqsh <= s1_writedata(7 downto 4);
					noi_short <= s1_writedata(3);
					noi_div <= s1_writedata(2 downto 0);
				when "100011" =>	-- NR44 FF23 TL-- ---- Trigger, Length enable
					noi_trigger <= s1_writedata(7);
					noi_lenchk <= s1_writedata(6);

--									-- Control/Status
--				when "100100" =>	-- NR50 FF24 ALLL BRRR Vin L enable, Left vol, Vin R enable, Right vol
--				when "100101" =>	-- NR51 FF25 NW21 NW21 Left enables, Right enables
--
													-- Wave Table
				when "110000" =>	--      FF30 0000 1111 Samples 0 and 1
					wav_ram(0) <= s1_writedata(7 downto 4);
					wav_ram(1) <= s1_writedata(3 downto 0);
				when "110001" =>	--      FF31 0000 1111 Samples 2 and 3
					wav_ram(2) <= s1_writedata(7 downto 4);
					wav_ram(3) <= s1_writedata(3 downto 0);
				when "110010" =>	--      FF32 0000 1111 Samples 4 and 5
					wav_ram(4) <= s1_writedata(7 downto 4);
					wav_ram(5) <= s1_writedata(3 downto 0);
				when "110011" =>	--      FF33 0000 1111 Samples 6 and 31
					wav_ram(6) <= s1_writedata(7 downto 4);
					wav_ram(7) <= s1_writedata(3 downto 0);
				when "110100" =>	--      FF34 0000 1111 Samples 8 and 31
					wav_ram(8) <= s1_writedata(7 downto 4);
					wav_ram(9) <= s1_writedata(3 downto 0);
				when "110101" =>	--      FF35 0000 1111 Samples 10 and 11
					wav_ram(10) <= s1_writedata(7 downto 4);
					wav_ram(11) <= s1_writedata(3 downto 0);
				when "110110" =>	--      FF36 0000 1111 Samples 12 and 13
					wav_ram(12) <= s1_writedata(7 downto 4);
					wav_ram(13) <= s1_writedata(3 downto 0);
				when "110111" =>	--      FF37 0000 1111 Samples 14 and 15
					wav_ram(14) <= s1_writedata(7 downto 4);
					wav_ram(15) <= s1_writedata(3 downto 0);
				when "111000" =>	--      FF38 0000 1111 Samples 16 and 17
					wav_ram(16) <= s1_writedata(7 downto 4);
					wav_ram(17) <= s1_writedata(3 downto 0);
				when "111001" =>	--      FF39 0000 1111 Samples 18 and 19
					wav_ram(18) <= s1_writedata(7 downto 4);
					wav_ram(19) <= s1_writedata(3 downto 0);
				when "111010" =>	--      FF3A 0000 1111 Samples 20 and 21
					wav_ram(20) <= s1_writedata(7 downto 4);
					wav_ram(21) <= s1_writedata(3 downto 0);
				when "111011" =>	--      FF3B 0000 1111 Samples 22 and 23
					wav_ram(22) <= s1_writedata(7 downto 4);
					wav_ram(23) <= s1_writedata(3 downto 0);
				when "111100" =>	--      FF3C 0000 1111 Samples 24 and 25
					wav_ram(24) <= s1_writedata(7 downto 4);
					wav_ram(25) <= s1_writedata(3 downto 0);
				when "111101" =>	--      FF3D 0000 1111 Samples 26 and 27
					wav_ram(26) <= s1_writedata(7 downto 4);
					wav_ram(27) <= s1_writedata(3 downto 0);
				when "111110" =>	--      FF3E 0000 1111 Samples 28 and 29
					wav_ram(28) <= s1_writedata(7 downto 4);
					wav_ram(29) <= s1_writedata(3 downto 0);
				when "111111" =>	--      FF3F 0000 1111 Samples 30 and 31
					wav_ram(30) <= s1_writedata(7 downto 4);
					wav_ram(31) <= s1_writedata(3 downto 0);

				when others =>
					null;
				end case;
			end if;

			if s1_read = '1' then
				case s1_addr is
       										-- Square 1
				when "010000" =>	-- NR10 FF10 -PPP NSSS Sweep period, negate, shift
					s1_readdata <= '1' & sq1_swper & sq1_swdir & sq1_swshift;
				when "010001" =>	-- NR11 FF11 DDLL LLLL Duty, Length load (64-L)
					s1_readdata <= sq1_duty & "111111";
				when "010010" =>	-- NR12 FF12 VVVV APPP Starting volume, Envelope add mode, period
					s1_readdata <= sq1_vol & sq1_envsgn & sq1_envper;
				when "010011" =>	-- NR13 FF13 FFFF FFFF Frequency LSB
					s1_readdata <= X"FF";
				when "010100" =>	-- NR14 FF14 TL-- -FFF Trigger, Length enable, Frequency MSB
					s1_readdata <= '0' & sq1_lenchk & "111111";

													-- Square 2
				when "010110" =>	-- NR21 FF16 DDLL LLLL Duty, Length load (64-L)
					s1_readdata <= sq2_duty & "111111";
				when "010111" =>	-- NR22 FF17 VVVV APPP Starting volume, Envelope add mode, period
					s1_readdata <= sq2_vol & sq2_envsgn & sq2_envper;
				when "011000" =>	-- NR23 FF18 FFFF FFFF Frequency LSB
					s1_readdata <= X"FF";
				when "011001" =>	-- NR24 FF19 TL-- -FFF Trigger, Length enable, Frequency MSB
					s1_readdata <= '0' & sq2_lenchk & "111111";

				when "100110" =>	-- NR52 FF26 P--- NW21 Power control/status, Channel length statuses
					s1_readdata <= snd_enable & "00000" & sq2_playing & sq1_playing;

													-- Wave
				when "011010" =>	-- NR30 FF1A E--- ---- DAC power
					s1_readdata <= wav_enable & "1111111";
				when "011011" =>	-- NR31 FF1B LLLL LLLL Length load (256-L)
					s1_readdata <= X"FF";
				when "011100" =>	-- NR32 FF1C -VV- ---- Volume code (00=0%, 01=100%, 10=50%, 11=25%)
					s1_readdata <= '1' & wav_volsh & "11111";
				when "011101" =>	-- NR33 FF1D FFFF FFFF Frequency LSB
					s1_readdata <= X"FF";
				when "011110" =>	-- NR34 FF1E TL-- -FFF Trigger, Length enable, Frequency MSB
					s1_readdata <= wav_trigger & wav_lenchk & "111111";

													-- Noise
				when "100000" =>	-- NR41 FF20 --LL LLLL Length load (64-L)
					s1_readdata <= X"FF";
				when "100001" =>	-- NR42 FF21 VVVV APPP Starting volume, Envelope add mode, period
					s1_readdata <= noi_svol & noi_envsgn & noi_envper;
				when "100010" =>	-- NR43 FF22 SSSS WDDD Clock shift, Width mode of LFSR, Divisor code
					s1_readdata <= noi_freqsh & noi_short &	noi_div;
				when "100011" =>	-- NR44 FF23 TL-- ---- Trigger, Length enable
					s1_readdata <= noi_trigger & noi_lenchk & "111111"; 

													-- Wave Table
				when "110000" =>	--      FF30 0000 1111 Samples 0 and 1
					s1_readdata <= wav_ram(0) & wav_ram(1);
				when "110001" =>	--      FF31 0000 1111 Samples 2 and 3
					s1_readdata <= wav_ram(2) & wav_ram(3);
				when "110010" =>	--      FF32 0000 1111 Samples 4 and 5
					s1_readdata <= wav_ram(4) & wav_ram(5);
				when "110011" =>	--      FF33 0000 1111 Samples 6 and 31
					s1_readdata <= wav_ram(6) & wav_ram(7);
				when "110100" =>	--      FF34 0000 1111 Samples 8 and 31
					s1_readdata <= wav_ram(8) & wav_ram(9);
				when "110101" =>	--      FF35 0000 1111 Samples 10 and 11
					s1_readdata <= wav_ram(10) & wav_ram(11);
				when "110110" =>	--      FF36 0000 1111 Samples 12 and 13
					s1_readdata <= wav_ram(12) & wav_ram(13);
				when "110111" =>	--      FF37 0000 1111 Samples 14 and 15
					s1_readdata <= wav_ram(14) & wav_ram(15);
				when "111000" =>	--      FF38 0000 1111 Samples 16 and 17
					s1_readdata <= wav_ram(16) & wav_ram(17);
				when "111001" =>	--      FF39 0000 1111 Samples 18 and 19
					s1_readdata <= wav_ram(18) & wav_ram(19);
				when "111010" =>	--      FF3A 0000 1111 Samples 20 and 21
					s1_readdata <= wav_ram(20) & wav_ram(21);
				when "111011" =>	--      FF3B 0000 1111 Samples 22 and 23
					s1_readdata <= wav_ram(22) & wav_ram(23);
				when "111100" =>	--      FF3C 0000 1111 Samples 24 and 25
					s1_readdata <= wav_ram(24) & wav_ram(25);
				when "111101" =>	--      FF3D 0000 1111 Samples 26 and 27
					s1_readdata <= wav_ram(26) & wav_ram(27);
				when "111110" =>	--      FF3E 0000 1111 Samples 28 and 29
					s1_readdata <= wav_ram(28) & wav_ram(29);
				when "111111" =>	--      FF3F 0000 1111 Samples 30 and 31
					s1_readdata <= wav_ram(30) & wav_ram(31);

				when others =>
					s1_readdata <= X"FF";
				end case;

			end if;

			wav_shift_r := wav_shift;
		end if;

		if reset = '1' then
			snd_enable <= '0';
		elsif rising_edge(clk) then
			if s1_write = '1' and s1_addr = "100110" then
				-- NR52 FF26 P--- NW21 Power control/status, Channel length statuses
				snd_enable <= s1_writedata(7);
			end if;
		end if;
	end process;

	sound : process(clk, snd_enable, en_snd, en_len, en_env, en_sweep)
		constant duty_0			: std_logic_vector(0 to 7) := "00000001";
		constant duty_1			: std_logic_vector(0 to 7) := "10000001";
		constant duty_2			: std_logic_vector(0 to 7) := "10000111";
		constant duty_3			: std_logic_vector(0 to 7) := "01111110";
		variable sq1_fcnt		: unsigned(10 downto 0);
		variable sq1_phase	: integer range 0 to 7;
		variable sq1_len		: std_logic_vector(6 downto 0);
		variable sq1_envcnt	: std_logic_vector(2 downto 0);		-- Sq1 envelope timer count
		variable sq1_swcnt	: std_logic_vector(2 downto 0);		-- Sq1 sweep timer count
		variable sq1_swoffs	: unsigned(11 downto 0);
		variable sq1_swfr		: unsigned(11 downto 0);
		variable sq1_out		: std_logic;
		
		variable sq2_fcnt		: unsigned(10 downto 0);
		variable sq2_phase	: integer range 0 to 7;
		variable sq2_len		: std_logic_vector(6 downto 0);
		variable sq2_envcnt	: std_logic_vector(2 downto 0);		-- Sq2 envelope timer count
		variable sq2_out		: std_logic;
		
		variable wav_fcnt		: unsigned(10 downto 0);
		variable wav_len		: std_logic_vector(8 downto 0);

		variable noi_divisor: unsigned(10 downto 0);	-- Noise frequency divisor
		variable noi_freq		: unsigned(10 downto 0);	-- Noise frequency (calculated)
		variable noi_fcnt		: unsigned(10 downto 0);
		variable noi_lfsr		: unsigned(15 downto 0);
		variable noi_len		: std_logic_vector(6 downto 0);
		variable noi_envcnt	: std_logic_vector(2 downto 0);		-- Noise envelope timer count
		variable noi_out		: std_logic;

		variable acc_fcnt		: unsigned(11 downto 0);
	begin
		-- Sound processing
		if snd_enable = '0' then
			sq1_playing	<= '0';
			sq1_fr2			<= (others => '0');
			sq1_fcnt		:= (others => '0');
			sq1_phase		:= 0;
			sq1_len			:= (others => '0');
			sq1_vol		 	<= "0000";
			sq1_envcnt	:= "000";
			sq1_swcnt		:= "000";
			sq1_swoffs	:= (others => '0');
			sq1_swfr		:= (others => '0');
			sq1_out			:= '0';
			
			sq2_playing	<= '0';
			sq2_fr2			<= (others => '0');
			sq2_fcnt		:= (others => '0');
			sq2_phase		:= 0;
			sq2_len			:= (others => '0');
			sq2_vol		 	<= "0000";
			sq2_envcnt	:= "000";
			sq2_out			:= '0';

			wav_fcnt		:= (others => '0');
			wav_len			:= (others => '0');

			noi_playing	<= '0';
			noi_fr2			<= (others => '0');
			noi_fcnt		:= (others => '0');
			noi_lfsr		:= (others => '1');
			noi_len			:= (others => '0');
			noi_vol		 	<= "0000";
			noi_envcnt	:= "000";
			noi_out			:= '0';

		elsif rising_edge(clk) then
			if en_snd4 then
				-- Sq1 frequency timer
				if sq1_playing = '1' then
					acc_fcnt := ('0'&sq1_fcnt) + to_unsigned(1, acc_fcnt'length);
					if acc_fcnt(acc_fcnt'high) = '1' then
						if sq1_phase < 7 then
							sq1_phase := sq1_phase + 1;
						else
							sq1_phase := 0;
						end if;
						sq1_fcnt := unsigned(sq1_fr2);
					else
						sq1_fcnt := acc_fcnt(sq1_fcnt'range);
					end if;
				end if;

				-- Sq2 frequency timer
				if sq2_playing = '1' then
					acc_fcnt := ('0'&sq2_fcnt) + to_unsigned(1, acc_fcnt'length);
					if acc_fcnt(acc_fcnt'high) = '1' then
						if sq2_phase < 7 then
							sq2_phase := sq2_phase + 1;
						else
							sq2_phase := 0;
						end if;
						sq2_fcnt := unsigned(sq2_fr2);
					else
						sq2_fcnt := acc_fcnt(sq2_fcnt'range);
					end if;
				end if;

				-- Noi frequency timer
				if noi_playing = '1' then
					acc_fcnt := ('0'&noi_fcnt) + to_unsigned(1, acc_fcnt'length);
					if acc_fcnt(acc_fcnt'high) = '1' then
						-- Noise LFSR
						if noi_short = '1' then
							noi_lfsr := (noi_lfsr(0) xor noi_lfsr(1)) & noi_lfsr(15 downto 8) & (noi_lfsr(0) xor noi_lfsr(1)) & noi_lfsr(6 downto 1);
						else
							noi_lfsr := (noi_lfsr(0) xor noi_lfsr(1)) & noi_lfsr(15 downto 1);
						end if;
						
						noi_out := not noi_lfsr(0);
						noi_fcnt := unsigned(noi_fr2);
					else
						noi_fcnt := acc_fcnt(noi_fcnt'range);
					end if;
				end if;

				case sq1_duty is
				when "00" => sq1_out := duty_0(sq1_phase);
				when "01" => sq1_out := duty_1(sq1_phase);
				when "10" => sq1_out := duty_2(sq1_phase);
				when "11" => sq1_out := duty_3(sq1_phase);
				when others => null;
				end case;

				if sq1_out = '1' then
					sq1_wav <= sq1_vol & "00";
				else
					sq1_wav <= "000000";
				end if;

				case sq2_duty is
				when "00" => sq2_out := duty_0(sq2_phase);
				when "01" => sq2_out := duty_1(sq2_phase);
				when "10" => sq2_out := duty_2(sq2_phase);
				when "11" => sq2_out := duty_3(sq2_phase);
				when others => null;
				end case;

				if sq2_out = '1' then
					sq2_wav <= sq2_vol & "00";
				else
					sq2_wav <= "000000";
				end if;

				if noi_out = '1' then
					noi_wav <= noi_vol & "00";
				else
					noi_wav <= "000000";
				end if;

			end if;

			-- Square channel 1
			if sq1_playing = '1' then
				-- Length counter
				if en_len then
					if sq1_len(6) = '0' then
						sq1_len := std_logic_vector(unsigned(sq1_len) + to_unsigned(1, sq1_len'length));
					end if;
				end if;

				-- Envelope counter
				if en_env then
					if sq1_envper /= "000" then
						sq1_envcnt := std_logic_vector(unsigned(sq1_envcnt) + to_unsigned(1, sq1_envcnt'length));
						if sq1_envcnt = sq1_envper then
							if sq1_envsgn = '1' then
								if sq1_vol /= "1111" then 
									sq1_vol <= std_logic_vector(unsigned(sq1_vol) + to_unsigned(1, sq1_vol'length));
								end if;
							else
								if sq1_vol /= "0000" then 
									sq1_vol <= std_logic_vector(unsigned(sq1_vol) - to_unsigned(1, sq1_vol'length));
								end if;
							end if;
							sq1_envcnt := "000";
						end if;
					end if;
				end if;

				-- Sweep processing
				if en_sweep or sq1_trigger = '1' then
					case sq1_swshift is
					when "000" => sq1_swoffs := unsigned('0' & sq1_fr2);
					when "001" => sq1_swoffs := "00" & unsigned(sq1_fr2(10 downto 1));
					when "010" => sq1_swoffs := "000" & unsigned(sq1_fr2(10 downto 2));
					when "011" => sq1_swoffs := "0000" & unsigned(sq1_fr2(10 downto 3));
					when "100" => sq1_swoffs := "00000" & unsigned(sq1_fr2(10 downto 4));
					when "101" => sq1_swoffs := "000000" & unsigned(sq1_fr2(10 downto 5));
					when "110" => sq1_swoffs := "0000000" & unsigned(sq1_fr2(10 downto 6));
					when "111" => sq1_swoffs := "00000000" & unsigned(sq1_fr2(10 downto 7));
					when others => sq1_swoffs := unsigned('0' & sq1_fr2);
					end case;

					-- Calculate next sweep frequency
					if sq1_swper /= "000" then
						if sq1_swdir = '0' then
							sq1_swfr := ('0' & unsigned(sq1_fr2)) - sq1_swoffs;
						else
							sq1_swfr := ('0' & unsigned(sq1_fr2)) + sq1_swoffs;
						end if;
					else -- Sweep disabled
						sq1_swfr := unsigned('0' & sq1_fr2);
					end if;

					-- Sweep counter
					if sq1_swper /= "000" then
						sq1_swcnt := std_logic_vector(unsigned(sq1_swcnt) + to_unsigned(1, sq1_swcnt'length));
						if sq1_swcnt = sq1_swper then
							sq1_fr2 <= std_logic_vector(sq1_swfr(10 downto 0));
							sq1_swcnt := "000";
						end if;
					end if;
				end if;

				-- Check for end of playing conditions
				if sq1_vol = X"0" 																	-- Volume == 0
					or (sq1_lenchk = '1' and sq1_len(6) = '1') 				-- Play length timer overrun
					or (sq1_swper /= "000" and sq1_swfr(11) = '1') 		-- Sweep frequency overrun
				then
					sq1_playing <= '0';
					sq1_envcnt := "000";
					sq1_swcnt := "000";
					--sq1_wav <= "000000";
				end if;
			end if;

			-- Check sample trigger and start playing
			if sq1_trigger = '1' then
				sq1_fr2 <= sq1_freq;
				sq1_fcnt := unsigned(sq1_freq);
				noi_lfsr := (others => '1');
				sq1_playing <= '1';
				sq1_vol <= sq1_svol;
				sq1_envcnt := "000";
				sq1_swcnt := "000";
				sq1_len := '0' & sq1_slen;
				sq1_phase := 0;
			end if;

			-- Square channel 2
			if sq2_playing = '1' then
				-- Length counter
				if en_len then
					if sq2_len(6) = '0' then
						sq2_len := std_logic_vector(unsigned(sq2_len) + to_unsigned(1, sq2_len'length));
					end if;
				end if;

				-- Envelope counter
				if en_env then
					if sq2_envper /= "000" then
						sq2_envcnt := std_logic_vector(unsigned(sq2_envcnt) + to_unsigned(1, sq2_envcnt'length));
						if sq2_envcnt = sq2_envper then
							if sq2_envsgn = '1' then
								if sq2_vol /= "1111" then 
									sq2_vol <= std_logic_vector(unsigned(sq2_vol) + to_unsigned(1, sq2_vol'length));
								end if;
							else
								if sq2_vol /= "0000" then 
									sq2_vol <= std_logic_vector(unsigned(sq2_vol) - to_unsigned(1, sq2_vol'length));
								end if;
							end if;
							sq2_envcnt := "000";
						end if;
					end if;
				end if;

				-- Check for end of playing conditions
				if sq2_vol = X"0" 															-- Volume == 0              	
					or (sq2_lenchk = '1' and sq2_len(6) = '1')		-- Play length timer overrun
				then
					sq2_playing <= '0';
					sq2_envcnt := "000";
					--sq2_wav <= "000000";
				end if;
			end if;

			-- Check sample trigger and start playing
			if sq2_trigger = '1' then
				sq2_fr2 <= sq2_freq;
				sq2_fcnt := unsigned(sq2_freq);
				sq2_playing <= '1';
				sq2_vol <= sq2_svol;
				sq2_envcnt := "000";
				sq2_len := '0' & sq2_slen;
				sq2_phase := 0;
			end if;

			-- Noise channel
			if noi_playing = '1' then
				-- Length counter
				if en_len then
					if noi_len(6) = '0' then
						noi_len := std_logic_vector(unsigned(noi_len) + to_unsigned(1, noi_len'length));
					end if;
				end if;

				-- Envelope counter
				if en_env then
					if noi_envper /= "000" then
						noi_envcnt := std_logic_vector(unsigned(noi_envcnt) + to_unsigned(1, noi_envcnt'length));
						if noi_envcnt = noi_envper then
							if noi_envsgn = '1' then
								if noi_vol /= "1111" then 
									noi_vol <= std_logic_vector(unsigned(noi_vol) + to_unsigned(1, noi_vol'length));
								end if;
							else
								if noi_vol /= "0000" then 
									noi_vol <= std_logic_vector(unsigned(noi_vol) - to_unsigned(1, noi_vol'length));
								end if;
							end if;
							noi_envcnt := "000";
						end if;
					end if;
				end if;

				-- Check for end of playing conditions
				if noi_vol = X"0" 															-- Volume == 0              	
					or (noi_lenchk = '1' and noi_len(6) = '1')		-- Play length timer overrun
				then
					noi_playing <= '0';
					noi_envcnt := "000";
					--sq2_wav <= "000000";
				end if;
			end if;

			-- Check sample trigger and start playing
			if noi_trigger = '1' then
				-- Calculate noise frequency
				case noi_div is 
				when "000" => noi_divisor := to_unsigned(2048 - 8, noi_divisor'length);
				when "001" => noi_divisor := to_unsigned(2048 - 16, noi_divisor'length);
				when "010" => noi_divisor := to_unsigned(2048 - 32, noi_divisor'length);
				when "011" => noi_divisor := to_unsigned(2048 - 48, noi_divisor'length);
				when "100" => noi_divisor := to_unsigned(2048 - 64, noi_divisor'length);
				when "101" => noi_divisor := to_unsigned(2048 - 80, noi_divisor'length);
				when "110" => noi_divisor := to_unsigned(2048 - 96, noi_divisor'length);
				when others => noi_divisor := to_unsigned(2048 - 112, noi_divisor'length);
				end case;

--				case noi_freqsh is
--				when "000" => noi_freq := unsigned(noi_divisor);
--				when "001" => noi_freq := '0' & unsigned(noi_divisor(10 downto 1));
--				when "010" => noi_freq := "00" & unsigned(noi_divisor(10 downto 2));
--				when "011" => noi_freq := "000" & unsigned(noi_divisor(10 downto 3));
--				when "100" => noi_freq := "0000" & unsigned(noi_divisor(10 downto 4));
--				when "101" => noi_freq := "00000" & unsigned(noi_divisor(10 downto 5));
--				when "110" => noi_freq := "000000" & unsigned(noi_divisor(10 downto 6));
--				when "111" => noi_freq := "0000000" & unsigned(noi_divisor(10 downto 7));
--				when others => noi_freq := unsigned(noi_divisor);
--				end case;
				noi_freq := noi_divisor sll to_integer(unsigned(noi_freqsh));

				noi_fr2 <= std_logic_vector(noi_freq);
				noi_fcnt := noi_freq;
				noi_playing <= '1';
				noi_vol <= noi_svol;
				noi_envcnt := "000";
				noi_len := '0' & noi_slen;
			end if;

			if en_snd2 then
				-- Wave frequency timer
				wav_shift <= false;
				if wav_playing = '1' then
					acc_fcnt := ('0'&wav_fcnt) + to_unsigned(1, acc_fcnt'length);
					if acc_fcnt(acc_fcnt'high) = '1' then
						wav_shift <= true;
						wav_fcnt := unsigned(wav_fr2);
					else
						wav_fcnt := acc_fcnt(wav_fcnt'range);
					end if;
				end if;
			end if;

			-- Wave channel
			if wav_playing = '1' then
				-- Length counter
				if en_len then
					if wav_len(8) = '0' then
						wav_len := std_logic_vector(unsigned(wav_len) + to_unsigned(1, wav_len'length));
					end if;
				end if;

				-- Check for end of playing conditions
				if (wav_lenchk = '1' and wav_len(8) = '1') then
					wav_playing <= '0';
					wav_wav <= "000000";
				end if;
			end if;

			-- Check sample trigger and start playing
			if wav_trigger = '1' then
				wav_fr2 <= wav_freq;
				wav_fcnt := unsigned(wav_freq);
				wav_playing <= '1';
				wav_len := '0' & wav_slen;
			end if;

			if wav_enable = '1' and wav_volsh /= "00" then
				case wav_volsh is
				when "01" => wav_wav <= wav_ram(0) & "00";
				when "10" => wav_wav <= '0' & wav_ram(0) & '0';
				when "11" => wav_wav <= "00" & wav_ram(0);
				when others => wav_wav <= (others => 'X');
				end case;
			else
				wav_wav <= "000000";
			end if;

		end if;	-- snd_enable
	end process sound;

	-- Test
	process(clk, en_512, reset)
		variable l : std_logic_vector(15 downto 0);
	begin
		if reset = '1' then
			l := x"4000";

		elsif rising_edge(clk) then
			if en_512 then
				l := not l;
			end if;
--			snd_left <= l;
		end if;
	end process;

	-- Mixer
	mixer : process(sq1_wav, sq2_wav, noi_wav, wav_wav)
		variable snd_left_in		: unsigned(7 downto 0);
		variable snd_right_in		: unsigned(7 downto 0);
	begin
		snd_left_in := (others => '0');
		snd_right_in := (others => '0');

		snd_left_in := snd_left_in + ("00"&unsigned(sq1_wav));
	 	snd_left_in := snd_left_in + ("00"&unsigned(wav_wav));
		snd_right_in := snd_right_in + ("00"&unsigned(sq2_wav));
		snd_right_in := snd_right_in + ("00"&unsigned(noi_wav));

		snd_left <= std_logic_vector(snd_left_in) & X"00";
		snd_right <= std_logic_vector(snd_right_in) & X"00";
	end process;

end SYN;
