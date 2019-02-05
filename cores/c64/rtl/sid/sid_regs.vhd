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

entity sid_regs is
port (
    clock         : in  std_logic;
    reset         : in  std_logic;
                  
    addr          : in  unsigned(7 downto 0);
    wren          : in  std_logic;
    wdata         : in  std_logic_vector(7 downto 0);
    rdata         : out std_logic_vector(7 downto 0);
    
    potx          : in  std_logic_vector(7 downto 0);
    poty          : in  std_logic_vector(7 downto 0);

---
    comb_wave_l   : in  std_logic;
    comb_wave_r   : in  std_logic;
---
    voice_osc     : in  unsigned(3 downto 0);
    voice_wave    : in  unsigned(3 downto 0);
    voice_adsr    : in  unsigned(3 downto 0);
    voice_mul     : in  unsigned(3 downto 0);
    
    -- Oscillator parameters
    freq          : out unsigned(15 downto 0);
    test          : out std_logic;
    sync          : out std_logic;
    
    -- Wave map parameters
    comb_mode     : out std_logic;
    ring_mod      : out std_logic;
    wave_sel      : out std_logic_vector(3 downto 0);
    sq_width      : out unsigned(11 downto 0);
    
    -- ADSR parameters
    gate          : out std_logic;
    attack        : out std_logic_vector(3 downto 0);
    decay         : out std_logic_vector(3 downto 0);
    sustain       : out std_logic_vector(3 downto 0);
    release       : out std_logic_vector(3 downto 0);

    -- mixer 1 parameters
    filter_en     : out std_logic;

    -- globals
    volume_l      : out unsigned(3 downto 0) := (others => '0');
    filter_co_l   : out unsigned(10 downto 0) := (others => '0');
    filter_res_l  : out unsigned(3 downto 0) := (others => '0');
    filter_ex_l   : out std_logic := '0';
    filter_hp_l   : out std_logic := '0';    
    filter_bp_l   : out std_logic := '0';
    filter_lp_l   : out std_logic := '0';
    voice3_off_l  : out std_logic := '0';

    volume_r      : out unsigned(3 downto 0) := (others => '0');
    filter_co_r   : out unsigned(10 downto 0) := (others => '0');
    filter_res_r  : out unsigned(3 downto 0) := (others => '0');
    filter_ex_r   : out std_logic := '0';
    filter_hp_r   : out std_logic := '0';    
    filter_bp_r   : out std_logic := '0';
    filter_lp_r   : out std_logic := '0';
    voice3_off_r  : out std_logic := '0';

    -- readback
    osc3        : in  std_logic_vector(7 downto 0);
    env3        : in  std_logic_vector(7 downto 0) );

	 attribute ramstyle : string;

end sid_regs;

architecture gideon of sid_regs is
	 attribute ramstyle of gideon : architecture is "logic";

    type byte_array_t is array(natural range <>) of std_logic_vector(7 downto 0);
    type nibble_array_t is array(natural range <>) of std_logic_vector(3 downto 0);
    signal freq_lo  : byte_array_t(0 to 15)  := (others => (others => '0'));
    signal freq_hi  : byte_array_t(0 to 15)  := (others => (others => '0'));
    signal phase_lo : byte_array_t(0 to 15)  := (others => (others => '0'));
    signal phase_hi : nibble_array_t(0 to 15):= (others => (others => '0'));
    signal control  : byte_array_t(0 to 15)  := (others => (others => '0'));
    signal att_dec  : byte_array_t(0 to 15)  := (others => (others => '0'));
    signal sust_rel : byte_array_t(0 to 15)  := (others => (others => '0'));
    signal do_write : std_logic;
    signal wdata_d  : std_logic_vector(7 downto 0);
    signal bus_value: std_logic_vector(7 downto 0);
    signal filt_en_i: std_logic_vector(15 downto 0) := (others => '0');
    
    constant address_remap : byte_array_t(0 to 255) := (
        X"00", X"01", X"02", X"03", X"04", X"05", X"06",  -- 00 Voice 1
        X"10", X"11", X"12", X"13", X"14", X"15", X"16",  -- 07 Voice 2
        X"20", X"21", X"22", X"23", X"24", X"25", X"26",  -- 0E Voice 3

        X"08", X"09", X"0A", X"0B",                       -- 15
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- 19

        X"30", X"31", X"32", X"33", X"34", X"35", X"36",  -- 20 Voice 4
        X"40", X"41", X"42", X"43", X"44", X"45", X"46",  -- 27 Voice 5
        X"50", X"51", X"52", X"53", X"54", X"55", X"56",  -- 2E Voice 6
        X"60", X"61", X"62", X"63", X"64", X"65", X"66",  -- 35 Voice 7
        X"70", X"71", X"72", X"73", X"74", X"75", X"76",  -- 3C Voice 8
        X"0C", X"0D", X"0E",                              -- 43

        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- 46
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- 4D
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- 54
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- 5B
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- 62
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- 69
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- 70
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- 77
        X"FF", X"FF",                                     -- 7E
                
        X"80", X"81", X"82", X"83", X"84", X"85", X"86",  -- 80 Voice 9
        X"90", X"91", X"92", X"93", X"94", X"95", X"96",  -- 87 Voice 10
        X"A0", X"A1", X"A2", X"A3", X"A4", X"A5", X"A6",  -- 8E Voice 11

        X"88", X"89", X"8A", X"8B",                       -- 95
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- 99

        X"B0", X"B1", X"B2", X"B3", X"B4", X"B5", X"B6",  -- A0 Voice 12
        X"C0", X"C1", X"C2", X"C3", X"C4", X"C5", X"C6",  -- A7 Voice 13
        X"D0", X"D1", X"D2", X"D3", X"D4", X"D5", X"D6",  -- AE Voice 14
        X"E0", X"E1", X"E2", X"E3", X"E4", X"E5", X"E6",  -- B5 Voice 15
        X"F0", X"F1", X"F2", X"F3", X"F4", X"F5", X"F6",  -- BC Voice 16
        X"8C", X"8D", X"8E",                              -- C3
        
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- C6
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- CD
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- D4
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- DB
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- E2
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- E9
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- F0
        X"FF", X"FF", X"FF", X"FF", X"FF", X"FF", X"FF",  -- F7
        X"FF", X"FF" );                                   -- FE
         
begin
    process(clock)
        variable address: unsigned(7 downto 0);
    begin
        if rising_edge(clock) then
            address  := unsigned(address_remap(to_integer(addr)));
            do_write <= wren;
            wdata_d  <= wdata;

            if do_write='0' and wren='1' then
                bus_value <= wdata_d;
                if address(3)='0' then -- Voice register
                    case address(2 downto 0) is
                    when "000" =>   freq_lo(to_integer(address(7 downto 4))) <= wdata_d;
                    when "001" =>   freq_hi(to_integer(address(7 downto 4))) <= wdata_d;
                    when "010" =>   phase_lo(to_integer(address(7 downto 4))) <= wdata_d;
                    when "011" =>   phase_hi(to_integer(address(7 downto 4))) <= wdata_d(3 downto 0);
                    when "100" =>   control(to_integer(address(7 downto 4))) <= wdata_d;
                    when "101" =>   att_dec(to_integer(address(7 downto 4))) <= wdata_d;
                    when "110" =>   sust_rel(to_integer(address(7 downto 4))) <= wdata_d;
                    when others => null;
                    end case;
                elsif address(7)='0' then -- Global register for left
                    case address(2 downto 0) is
                    when "000" => filter_co_l(2 downto 0) <= unsigned(wdata_d(2 downto 0));
                    when "001" => filter_co_l(10 downto 3) <= unsigned(wdata_d);
                    when "010" => filter_res_l <= unsigned(wdata_d(7 downto 4));
                                  filter_ex_l <= wdata_d(3);
                                  filt_en_i(2 downto 0) <= wdata_d(2 downto 0);
                    when "011" => voice3_off_l <= wdata_d(7);
                                  filter_hp_l <= wdata_d(6);
                                  filter_bp_l <= wdata_d(5);
                                  filter_lp_l <= wdata_d(4);
                                  volume_l    <= unsigned(wdata_d(3 downto 0));
                    when "100" => filt_en_i(7 downto 0)  <= wdata_d;
                    when others => null;
                    end case;
                else -- Global register for right
                    case address(2 downto 0) is
                    when "000" => filter_co_r(2 downto 0) <= unsigned(wdata_d(2 downto 0));
                    when "001" => filter_co_r(10 downto 3) <= unsigned(wdata_d);
                    when "010" => filter_res_r <= unsigned(wdata_d(7 downto 4));
                                  filter_ex_r  <= wdata_d(3);
                                  filt_en_i(10 downto 8) <= wdata_d(2 downto 0);
                    when "011" => voice3_off_r <= wdata_d(7);
                                  filter_hp_r <= wdata_d(6);
                                  filter_bp_r <= wdata_d(5);
                                  filter_lp_r <= wdata_d(4);
                                  volume_r    <= unsigned(wdata_d(3 downto 0));
                    when "100" => filt_en_i(15 downto 8) <= wdata_d;
                    when others => null;
                    end case;
                end if;
            end if;

            -- Readback (unmapped address)
            case addr is
            when "00011001" => rdata <= potx; bus_value <= potx;
            when "00011010" => rdata <= poty; bus_value <= poty;
            when "00011011" => rdata <= osc3; bus_value <= osc3;
            when "00011100" => rdata <= env3; bus_value <= env3;
            when others     => rdata <= bus_value;
            end case;

            if reset='1' then
					 freq_lo  <= (others => (others => '0'));
					 freq_hi  <= (others => (others => '0'));
					 phase_lo <= (others => (others => '0'));
					 phase_hi <= (others => (others => '0'));
					 control  <= (others => (others => '0'));
					 att_dec  <= (others => (others => '0'));
					 sust_rel <= (others => (others => '0'));

                filt_en_i    <= (others => '0');
                voice3_off_l <= '0';
                voice3_off_r <= '0';
                volume_l     <= X"0";
                volume_r     <= X"0";
            end if;
        end if;
    end process;
    
    freq        <= unsigned(freq_hi(to_integer(voice_osc))) & unsigned(freq_lo(to_integer(voice_osc)));
    test        <= control(to_integer(voice_osc))(3);
    sync        <= control(to_integer(voice_osc))(1);
    
    -- Wave map parameters
    ring_mod    <= control(to_integer(voice_wave))(2);
    wave_sel    <= control(to_integer(voice_wave))(7 downto 4);
    sq_width    <= unsigned(phase_hi(to_integer(voice_wave))) & unsigned(phase_lo(to_integer(voice_wave)));
    comb_mode   <= (voice_wave(3) and comb_wave_r) or (not voice_wave(3) and comb_wave_l);
    
    -- ADSR parameters
    gate        <= control(to_integer(voice_adsr))(0);
    attack      <= att_dec(to_integer(voice_adsr))(7 downto 4);
    decay       <= att_dec(to_integer(voice_adsr))(3 downto 0);
    sustain     <= sust_rel(to_integer(voice_adsr))(7 downto 4);
    release     <= sust_rel(to_integer(voice_adsr))(3 downto 0);

    -- Mixer 1 parameters
    filter_en   <= filt_en_i(to_integer(voice_mul));
        
end gideon;
