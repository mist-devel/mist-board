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
        
entity sid_mixer is
port (
    clock       : in  std_logic;
    reset       : in  std_logic;
    
    valid_in    : in  std_logic := '0';
     
    direct_out  : in  signed(17 downto 0);
    high_pass   : in  signed(17 downto 0);
    band_pass   : in  signed(17 downto 0);
    low_pass    : in  signed(17 downto 0);

    filter_hp   : in  std_logic;
    filter_bp   : in  std_logic;
    filter_lp   : in  std_logic;
    
    volume      : in  unsigned(3 downto 0);

    mixed_out   : out signed(17 downto 0);
    valid_out   : out std_logic );
end sid_mixer;

architecture arith of sid_mixer is
    signal mix_i    : signed(17 downto 0);    
    signal mix_uns  : unsigned(16 downto 0);    
    signal vol_uns  : unsigned(16 downto 0);
    signal vol_s    : signed(16 downto 0);
    signal state    : integer range 0 to 7;
    signal p_mul    : unsigned(33 downto 0);
    signal p_mul_s  : signed(34 downto 0);
    
    type t_volume_lut is array(natural range <>) of unsigned(15 downto 0);
    constant c_volume_lut : t_volume_lut(0 to 15) := (
        X"0000", X"0EEF", X"1DDE", X"2CCD", X"3BBC", X"4AAA", X"5999", X"6888",
        X"7777", X"8666", X"9555", X"A444", X"B333", X"C221", X"D110", X"DFFF" );


begin
    process(clock)
        variable mix_total : signed(17 downto 0);
    begin
        if rising_edge(clock) then
            valid_out <= '0';
            
            state <= state + 1;
            case state is
            when 0 =>
                if valid_in = '1' then
                    mix_i <= sum_limit(direct_out, to_signed(16384, 18));
                else
                    state <= 0;
                end if;
            
            when 1 =>
                if filter_hp='1' then
                    mix_i <= sum_limit(mix_i, high_pass); 
                end if;
                
            when 2 =>
                if filter_bp='1' then
                    mix_i <= sum_limit(mix_i, band_pass); 
                end if;

            when 3 =>
                if filter_lp='1' then
                    mix_i <= sum_limit(mix_i, low_pass); 
                end if;

            when 4 =>
--                p_mul <= mix_uns * vol_uns;
                p_mul_s <= mix_i * vol_s;
                valid_out <= '1';
                state <= 0;

            when others =>
                state <= 0;
                
            end case;

--            mix_total := not(p_mul(32)) & signed(p_mul(31 downto 15));
--            mixed_out <= mix_total; -- + to_signed(16384, 18);
            mixed_out <= p_mul_s(33 downto 16);

            if reset='1' then
                mix_i <= (others => '0');
                state <= 0;
            end if;
        end if;
    end process;

--    vol_uns   <= "0" & volume & volume & volume & volume;
--    vol_uns   <= '0' & c_volume_lut(to_integer(volume));
--    mix_uns   <= not mix_i(17) & unsigned(mix_i(16 downto 1));

    vol_s   <= '0' & signed(c_volume_lut(to_integer(volume)));
end arith;
