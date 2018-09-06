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

entity wave_map is
generic (
    g_num_voices  : integer := 8;  -- 8 or 16, clock should then be 8 or 16 MHz, too!
    g_sample_bits : integer := 8 );
port (
    clock    : in  std_logic;
    reset    : in  std_logic;
    
    osc_val  : in  unsigned(23 downto 0);
    carry_20 : in  std_logic;

    msb_other: in  std_logic := '0';
    ring_mod : in  std_logic := '0';
    test     : in  std_logic := '0';
       
    voice_i  : in  unsigned(3 downto 0);
    comb_mode: in  std_logic;
    enable_i : in  std_logic;
    wave_sel : in  std_logic_vector(3 downto 0);
    sq_width : in  unsigned(11 downto 0);

    voice_o  : out unsigned(3 downto 0);
    enable_o : out std_logic;
    wave_out : out unsigned(g_sample_bits-1 downto 0) );

end wave_map;


architecture Gideon of wave_map is
    type noise_array_t is array (natural range <>) of unsigned(22 downto 0);
    signal noise_reg : noise_array_t(0 to g_num_voices-1) := (others => (0 => '1', others => '0'));
    type voice_array_t is array (natural range <>) of unsigned(g_sample_bits-1 downto 0);
    signal voice_reg : voice_array_t(0 to g_num_voices-1) := (others => (others => '0'));

    type t_byte_array is array(natural range <>) of unsigned(7 downto 0);
    constant c_wave_TP : t_byte_array(0 to 255) := (
        16#FF# => X"FF", 16#F7# => X"F7", 16#EF# => X"EF", 16#E7# => X"E0", 
        16#FE# => X"FE", 16#F6# => X"F0", 16#EE# => X"E0", 16#E6# => X"00", 
        16#FD# => X"FD", 16#F5# => X"FD", 16#ED# => X"E0", 16#E5# => X"00", 
        16#FC# => X"F8", 16#F4# => X"80", 16#EC# => X"00", 16#E4# => X"00", 
        16#FB# => X"FB", 16#F3# => X"F0", 16#EB# => X"E0", 16#E3# => X"00", 
        16#FA# => X"F8", 16#F2# => X"08", 16#EA# => X"00", 16#E2# => X"00", 
        16#F9# => X"F0", 16#F1# => X"00", 16#E9# => X"00", 16#E1# => X"00", 
        16#F8# => X"80", 16#F0# => X"00", 16#E8# => X"00", 16#E0# => X"00", 
        
        16#DF# => X"DF", 16#DE# => X"D0", 16#DD# => X"C0", 16#DB# => X"C0",
        16#D7# => X"C0", 16#CF# => X"C0", 16#BF# => X"BF", 16#BE# => X"B0",
        16#BD# => X"A0", 16#B9# => X"80", 16#B7# => X"80", 16#AF# => X"80",
        
        16#7F# => X"7F", 16#7E# => X"70", 16#7D# => X"70", 16#7B# => X"60",
        16#77# => X"40", others => X"00" );

    constant c_wave_TS : t_byte_array(0 to 255) := (
        16#7F# => X"1E", 16#FE# => X"18", 16#FF# => X"3E", others => X"00" );

begin
    process(clock)
        variable noise_tmp  : unsigned(22 downto 0);
        variable voice_tmp  : unsigned(g_sample_bits-1 downto 0);
        variable triangle   : unsigned(g_sample_bits-1 downto 0);
        variable square     : unsigned(g_sample_bits-1 downto 0);
        variable sawtooth   : unsigned(g_sample_bits-1 downto 0);
        variable out_tmp    : unsigned(g_sample_bits-1 downto 0);
        variable new_bit    : std_logic;
    begin
        if rising_edge(clock) then
            -- take top of list
            voice_tmp := voice_reg(0);
            noise_tmp := noise_reg(0);

            if reset='1' or test='1' then
                noise_tmp := (others => '1'); -- seed not equal to zero
            elsif carry_20='1' then
                new_bit := noise_tmp(22) xor noise_tmp(21) xor noise_tmp(20) xor noise_tmp(15);
                noise_tmp := noise_tmp(21 downto 0) & new_bit;
            end if;

            if osc_val(23)='1' then
                triangle := not osc_val(22 downto 23-g_sample_bits);
            else
                triangle := osc_val(22 downto 23-g_sample_bits);
            end if;
            if ring_mod='1' and msb_other='0' then
                triangle := not triangle;
            end if;
            
            sawtooth := osc_val(23 downto 24-g_sample_bits);
            if osc_val(23 downto 12) < sq_width then
                square := (others => '0');
            else
                square := (others => '1');
            end if;
            
            out_tmp := (others => '0');
            case wave_sel is
            when X"0" =>
                out_tmp := voice_tmp;
            when X"1" =>
                out_tmp := triangle;
            when X"2" =>
                out_tmp := sawtooth;
            when X"3" =>
                if comb_mode='0' then
                    out_tmp(g_sample_bits-1 downto g_sample_bits-8) := 
                            c_wave_TS(to_integer(osc_val(23 downto 23-g_sample_bits)));
                else -- 8580
                    out_tmp := triangle and sawtooth;
                end if;
            when X"4" =>
                out_tmp := square;
            when X"5" => -- combined triangle and square
                if comb_mode='0' then
                    if square(0)='1' then
                        out_tmp(g_sample_bits-1 downto g_sample_bits-8) := 
                            c_wave_TP(to_integer(triangle(g_sample_bits-1 downto g_sample_bits-8)));
                    end if;
                else -- 8580
                    out_tmp := triangle and square;
                end if;
            when X"6" => -- combined saw and pulse
                if comb_mode='1' then
                    out_tmp := sawtooth and square;
                end if;                   

            when X"7" => -- combined triangle, saw and pulse
                if comb_mode='1' then
                    out_tmp := triangle and sawtooth and square;
                end if;                   

            when X"8" =>
                out_tmp(g_sample_bits-1) := noise_tmp(22); -- unsure.. 21?
                out_tmp(g_sample_bits-2) := noise_tmp(20);
                out_tmp(g_sample_bits-3) := noise_tmp(16);
                out_tmp(g_sample_bits-4) := noise_tmp(13);
                out_tmp(g_sample_bits-5) := noise_tmp(11);
                out_tmp(g_sample_bits-6) := noise_tmp(7);
                out_tmp(g_sample_bits-7) := noise_tmp(4);
                out_tmp(g_sample_bits-8) := noise_tmp(2);
                
--            when X"9"|X"A"|X"B"|X"C"|X"D"|X"E"|X"F" =>
--                out_tmp := noise_tmp(20 downto 21-g_sample_bits);
--                noise_tmp := (others => '0');
            when others =>
                null;
            end case;
                        
            if enable_i='1' then
                noise_reg(g_num_voices-1) <= noise_tmp;
                noise_reg(0 to g_num_voices-2) <= noise_reg(1 to g_num_voices-1);
                voice_reg(g_num_voices-1) <= out_tmp;
                voice_reg(0 to g_num_voices-2) <= voice_reg(1 to g_num_voices-1);
            end if;

            --out_tmp(out_tmp'high) := not out_tmp(out_tmp'high);
            wave_out <= unsigned(out_tmp);

            voice_o <= voice_i;
            enable_o <= enable_i;
        end if;
    end process;

end Gideon;
