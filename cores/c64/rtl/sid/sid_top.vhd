-------------------------------------------------------------------------------
--
-- (C) COPYRIGHT 2010 Gideon's Logic Architectures'
--
-------------------------------------------------------------------------------
-- 
-- Author: Gideon Zweijtzer (gideon.zweijtzer (at) gmail.com)
--
-- Note that this file is copyrighted, and is not supposed to be used in other
-- projects without written permission from the author.
--
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

entity sid_top is
generic (
    g_filter_div  : natural := 141; --for 32 MHz (221; -- for 50 MHz)
    g_num_voices  : natural := 3 );
port (
    clock         : in  std_logic;
    reset         : in  std_logic;
                  
    addr          : in  unsigned(7 downto 0);
    wren          : in  std_logic;
    wdata         : in  std_logic_vector(7 downto 0);
    rdata         : out std_logic_vector(7 downto 0);

    potx          : in  std_logic_vector(7 downto 0);
    poty          : in  std_logic_vector(7 downto 0);

    comb_wave_l   : in  std_logic := '0';
    comb_wave_r   : in  std_logic := '0';

    start_iter    : in  std_logic;
    sample_left   : out signed(17 downto 0);
    sample_right  : out signed(17 downto 0);
	 
	 extfilter_en  : in  std_logic
);
end sid_top;


architecture structural of sid_top is

    -- Voice index in pipe
    signal voice_osc   : unsigned(3 downto 0);
    signal voice_wave  : unsigned(3 downto 0);
    signal voice_mul   : unsigned(3 downto 0);
    signal enable_osc  : std_logic;
    signal enable_wave : std_logic;
    signal enable_mul  : std_logic;
    
    -- Oscillator parameters
    signal freq        : unsigned(15 downto 0);
    signal test        : std_logic;
    signal sync        : std_logic;

    -- Wave map parameters
    signal msb_other   : std_logic;
    signal comb_mode   : std_logic;
    signal ring_mod    : std_logic;
    signal wave_sel    : std_logic_vector(3 downto 0);
    signal sq_width    : unsigned(11 downto 0);
    
    -- ADSR parameters
    signal gate        : std_logic;
    signal attack      : std_logic_vector(3 downto 0);
    signal decay       : std_logic_vector(3 downto 0);
    signal sustain     : std_logic_vector(3 downto 0);
    signal release     : std_logic_vector(3 downto 0);

    -- Filter enable
    signal filter_en   : std_logic;

    -- globals
    signal volume_l      : unsigned(3 downto 0);
    signal filter_co_l   : unsigned(10 downto 0);
    signal filter_res_l  : unsigned(3 downto 0);
    signal filter_hp_l   : std_logic;    
    signal filter_bp_l   : std_logic;
    signal filter_lp_l   : std_logic;
    signal voice3_off_l  : std_logic;

    signal volume_r      : unsigned(3 downto 0);
    signal filter_co_r   : unsigned(10 downto 0);
    signal filter_res_r  : unsigned(3 downto 0);
    signal filter_hp_r   : std_logic;    
    signal filter_bp_r   : std_logic;
    signal filter_lp_r   : std_logic;
    signal voice3_off_r  : std_logic;

    -- readback
    signal osc3        : std_logic_vector(7 downto 0);
    signal env3        : std_logic_vector(7 downto 0);

    -- intermediate flags and signals
    signal test_wave   : std_logic;
    signal osc_val     : unsigned(23 downto 0);
    signal carry_20    : std_logic;
    signal enveloppe   : unsigned(7 downto 0);
    signal waveform    : unsigned(11 downto 0);

    signal valid_sum   : std_logic;
    signal valid_filt  : std_logic;
    signal valid_mix   : std_logic;

    signal filter_out_l: signed(17 downto 0) := (others => '0');
    signal direct_out_l: signed(17 downto 0) := (others => '0');
    signal high_pass_l : signed(17 downto 0) := (others => '0');
    signal band_pass_l : signed(17 downto 0) := (others => '0');
    signal low_pass_l  : signed(17 downto 0) := (others => '0');
    signal mixed_out_l : signed(17 downto 0) := (others => '0');

    signal filter_out_r: signed(17 downto 0) := (others => '0');
    signal direct_out_r: signed(17 downto 0) := (others => '0');
    signal high_pass_r : signed(17 downto 0) := (others => '0');
    signal band_pass_r : signed(17 downto 0) := (others => '0');
    signal low_pass_r  : signed(17 downto 0) := (others => '0');
    signal mixed_out_r : signed(17 downto 0) := (others => '0');
begin
 
	i_regs: entity work.sid_regs
	port map
	(
		clock       => clock,
		reset       => reset,

		addr        => addr,
		wren        => wren,
		wdata       => wdata,
		rdata       => rdata,

		potx        => potx,
		poty        => poty,

		comb_wave_l => comb_wave_l,
		comb_wave_r => comb_wave_r,

		voice_osc   => voice_osc,
		voice_wave  => voice_wave,
		voice_adsr  => voice_wave,
		voice_mul   => voice_mul,

		-- Oscillator parameters
		freq        => freq,
		test        => test,
		sync        => sync,

		-- Wave map parameters
		comb_mode   => comb_mode,
		ring_mod    => ring_mod,
		wave_sel    => wave_sel,
		sq_width    => sq_width,

		-- ADSR parameters
		gate        => gate,
		attack      => attack,
		decay       => decay,
		sustain     => sustain,
		release     => release,

		-- mixer parameters
		filter_en   => filter_en,

		-- globals
		volume_l    => volume_l,
		filter_co_l => filter_co_l,
		filter_res_l=> filter_res_l,
		filter_ex_l => open,
		filter_hp_l => filter_hp_l,    
		filter_bp_l => filter_bp_l,
		filter_lp_l => filter_lp_l,
		voice3_off_l=> voice3_off_l,

		volume_r    => volume_r,
		filter_co_r => filter_co_r,
		filter_res_r=> filter_res_r,
		filter_ex_r => open,
		filter_hp_r => filter_hp_r,    
		filter_bp_r => filter_bp_r,
		filter_lp_r => filter_lp_r,
		voice3_off_r=> voice3_off_r,

		-- readback
		osc3        => osc3,
		env3        => env3
	);

	i_ctrl: entity work.sid_ctrl
	generic map
	(
		g_num_voices  => g_num_voices
	)
	port map
	(
		clock       => clock,
		reset       => reset,
		start_iter  => start_iter,
		voice_osc   => voice_osc,
		enable_osc  => enable_osc
	);
    
    
	osc: entity work.oscillator
	generic map
	(
		g_num_voices
	)
	port map
	(
		clock    => clock,
		reset    => reset,

		voice_i  => voice_osc,
		voice_o  => voice_wave,

		enable_i => enable_osc,
		enable_o => enable_wave,

		freq     => freq,
		test     => test,
		sync     => sync,

		osc_val   => osc_val,
		test_o    => test_wave,
		carry_20  => carry_20,
		msb_other => msb_other
	);
    
	wmap: entity work.wave_map
	generic map
	(
		g_num_voices  => g_num_voices,
		g_sample_bits => 12
	)
	port map
	(
		clock     => clock,
		reset     => reset,
		test      => test_wave,
        
		osc_val   => osc_val,
		carry_20  => carry_20,
		msb_other => msb_other,
        
		voice_i   => voice_wave,
		enable_i  => enable_wave,
		comb_mode => comb_mode,
		wave_sel  => wave_sel,
		ring_mod  => ring_mod,
		sq_width  => sq_width,
    
		voice_o   => voice_mul,
		enable_o  => enable_mul,
		wave_out  => waveform
	);

	adsr: entity work.adsr_multi
	generic map
	(
		g_num_voices => g_num_voices
	)
	port map
	(
		clock    => clock,
		reset    => reset,
    
		voice_i  => voice_wave,
		enable_i => enable_wave,
		voice_o  => open,
		enable_o => open,

		gate     => gate,
		attack   => attack,
		decay    => decay,
		sustain  => sustain,
		release  => release,

		env_state=> open, -- for testing only
		env_out  => enveloppe
	);

	sum: entity work.mult_acc(signed_wave)
	port map
	(
		clock       => clock,
		reset       => reset,

		voice_i     => voice_mul,
		enable_i    => enable_mul,
		voice3_off_l=> voice3_off_l,
		voice3_off_r=> voice3_off_r,

		enveloppe   => enveloppe,
		waveform    => waveform,
		filter_en   => filter_en,

		osc3        => osc3,
		env3        => env3,

		valid_out    => valid_sum,
		filter_out_L => filter_out_L,
		filter_out_R => filter_out_R,
		direct_out_L => direct_out_L,
		direct_out_R => direct_out_R
	);

	i_filt_left: entity work.sid_filter
	generic map
	(
		g_divider   => g_filter_div
	)
	port map
	(
		clock       => clock,
		reset       => reset,
		enable      => extfilter_en,

		filt_co     => filter_co_l,
		filt_res    => filter_res_l,

		valid_in    => valid_sum,

		input       => filter_out_L,
		high_pass   => high_pass_L,
		band_pass   => band_pass_L,
		low_pass    => low_pass_L,

		error_out   => open,
		valid_out   => valid_filt
	);

	mix: entity work.sid_mixer
	port map
	(
		clock       => clock,
		reset       => reset,

		valid_in    => valid_filt,

		direct_out  => direct_out_L,
		high_pass   => high_pass_L,
		band_pass   => band_pass_L,
		low_pass    => low_pass_L,

		filter_hp   => filter_hp_l,
		filter_bp   => filter_bp_l,
		filter_lp   => filter_lp_l,

		volume      => volume_l,

		mixed_out   => mixed_out_L,
		valid_out   => open
	);

	i_filt_right: entity work.sid_filter
	generic map
	(
		g_divider   => g_filter_div
	)
	port map
	(
		clock       => clock,
		reset       => reset,
		enable      => extfilter_en,

		filt_co     => filter_co_r,
		filt_res    => filter_res_r,

		valid_in    => valid_sum,

		input       => filter_out_R,
		high_pass   => high_pass_R,
		band_pass   => band_pass_R,
		low_pass    => low_pass_R,

		error_out   => open,
		valid_out   => open
	);

	mix_right: entity work.sid_mixer
	port map
	(
		clock       => clock,
		reset       => reset,

		valid_in    => valid_filt,

		direct_out  => direct_out_R,
		high_pass   => high_pass_R,
		band_pass   => band_pass_R,
		low_pass    => low_pass_R,

		filter_hp   => filter_hp_r,
		filter_bp   => filter_bp_r,
		filter_lp   => filter_lp_r,

		volume      => volume_r,

		mixed_out   => mixed_out_R,
		valid_out   => open
	);

	sample_left  <= mixed_out_L;
	sample_right <= mixed_out_R;

end structural;
