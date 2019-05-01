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
use work.my_math_pkg.all;

entity mult_acc is
port (
    clock           : in  std_logic;
    reset           : in  std_logic;
                    
    voice_i         : in  unsigned(3 downto 0);
    enable_i        : in  std_logic;
    voice3_off_l    : in  std_logic;
    voice3_off_r    : in  std_logic;
                    
    filter_en       : in  std_logic := '0';
                    
    enveloppe       : in  unsigned(7 downto 0);
    waveform        : in  unsigned(11 downto 0);
                    
    --              
    osc3            : out std_logic_vector(7 downto 0);
    env3            : out std_logic_vector(7 downto 0);

    --
    valid_out       : out std_logic;

    direct_out_L    : out signed(17 downto 0);
    direct_out_R    : out signed(17 downto 0);

    filter_out_L    : out signed(17 downto 0);
    filter_out_R    : out signed(17 downto 0) );
end mult_acc;

-- architecture unsigned_wave of mult_acc is
--     signal filter_m : std_logic;
--     signal voice_m  : unsigned(3 downto 0);
--     signal mult_m   : unsigned(19 downto 0);
--     signal accu_f   : unsigned(17 downto 0);
--     signal accu_u   : unsigned(17 downto 0);
--     signal enable_d : std_logic;
--     signal direct_i : unsigned(17 downto 0);
--     signal filter_i : unsigned(17 downto 0);
-- begin
--     process(clock)
--         variable mult_ext   : unsigned(21 downto 0);
--         variable mult_trunc : unsigned(21 downto 4);
--     begin
--         if rising_edge(clock) then
--             -- latch outputs
--             if reset='1' then
--                 osc3 <= (others => '0');
--                 env3 <= (others => '0');
--             elsif voice_i = X"2" then
--                 osc3 <= std_logic_vector(waveform(11 downto 4));
--                 env3 <= std_logic_vector(enveloppe);
--             end if;
-- 
--             mult_ext   := extend(mult_m, mult_ext'length);
--             mult_trunc := mult_ext(mult_trunc'range);
--             filter_m <= filter_en;
--             voice_m  <= voice_i;
--             mult_m   <= enveloppe * waveform; 
--             valid_out <= '0';
--             enable_d  <= enable_i;
-- 
--             if enable_d='1' then
--                 if voice_m = 0 then
--                     valid_out <= '1';
--                     direct_i <= accu_u;
--                     filter_i <= accu_f;
--                     if filter_m='1' then
--                         accu_f <= mult_trunc;
--                         accu_u <= (others => '0');
--                     else
--                         accu_f <= (others => '0');
--                         accu_u <= mult_trunc;
--                     end if;
--                 else
--                     valid_out <= '0';
--                     if filter_m='1' then
--                         accu_f <= sum_limit(accu_f, mult_trunc);
--                     else
--                         if (voice_m /= 2) or (voice3_off = '0') then
--                             accu_u <= sum_limit(accu_u, mult_trunc);
--                         end if;
--                     end if;
--                 end if;
--             end if;
--                         
--             if reset = '1' then
--                 valid_out  <= '0';
--                 accu_u     <= (others => '0');
--                 accu_f     <= (others => '0');
--                 direct_i   <= (others => '0');
--                 filter_i   <= (others => '0');
--             end if;
--         end if;
--     end process;
--     
--     direct_out <= '0' & signed(direct_i(17 downto 1));
--     filter_out <= '0' & signed(filter_i(17 downto 1));
-- end unsigned_wave;
-- 

architecture signed_wave of mult_acc is
    signal filter_m : std_logic;
    signal voice_m  : unsigned(3 downto 0);
    signal mult_m   : signed(20 downto 0);
    signal accu_fl  : signed(17 downto 0);
    signal accu_fr  : signed(17 downto 0);
    signal accu_ul  : signed(17 downto 0);
    signal accu_ur  : signed(17 downto 0);
    signal enable_d : std_logic;
begin
    process(clock)
        variable mult_ext   : signed(21 downto 0);
        variable mult_trunc : signed(21 downto 4);
        variable env_signed : signed(8 downto 0);
        variable wave_signed: signed(11 downto 0);
    begin
        if rising_edge(clock) then
            -- latch outputs
            if reset='1' then
                osc3 <= (others => '0');
                env3 <= (others => '0');
            elsif voice_i = X"2" then
                osc3 <= std_logic_vector(waveform(11 downto 4));
                env3 <= std_logic_vector(enveloppe);
            end if;

            env_signed := '0' & signed(enveloppe);
            wave_signed := not waveform(11) & signed(waveform(10 downto 0));
            
            mult_ext   := extend(mult_m, mult_ext'length);
            mult_trunc := mult_ext(mult_trunc'range);
            filter_m <= filter_en;
            voice_m  <= voice_i;
            mult_m   <= env_signed * wave_signed; 
            valid_out <= '0';
            enable_d  <= enable_i;
            if enable_d='1' then
                if voice_m = 0 then
                    valid_out <= '1';
                    direct_out_l <= accu_ul;
                    direct_out_r <= accu_ur;
                    filter_out_l <= accu_fl;
                    filter_out_r <= accu_fr;
                    accu_fr <= (others => '0');
                    accu_ur <= (others => '0');
                    if filter_m='1' then
                        accu_fl <= mult_trunc;
                        accu_ul <= (others => '0');
                    else
                        accu_fl <= (others => '0');
                        accu_ul <= mult_trunc;
                    end if;
                elsif voice_m(3)='0' then
                    valid_out <= '0';
                    if filter_m='1' then
                        accu_fl <= sum_limit(accu_fl, mult_trunc);
                    else
                        if (voice_m /= 2) or (voice3_off_l = '0') then
                            accu_ul <= sum_limit(accu_ul, mult_trunc);
                        end if;
                    end if;
                else -- upper 8 voices go to right
                    valid_out <= '0';
                    if filter_m='1' then
                        accu_fr <= sum_limit(accu_fr, mult_trunc);
                    else
                        if (voice_m /= 10) or (voice3_off_r = '0') then
                            accu_ur <= sum_limit(accu_ur, mult_trunc);
                        end if;
                    end if;
                end if;

            end if;
                        
            if reset = '1' then
                valid_out    <= '0';
                accu_ul      <= (others => '0');
                accu_fl      <= (others => '0');
                accu_ur      <= (others => '0');
                accu_fr      <= (others => '0');
                direct_out_l <= (others => '0');
                direct_out_r <= (others => '0');
                filter_out_l <= (others => '0');
                filter_out_r <= (others => '0');
            end if;
        end if;
    end process;
    
    
end signed_wave;
