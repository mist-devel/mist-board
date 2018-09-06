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

entity oscillator is
generic (
    g_num_voices : integer := 8); 
port (
    clock    : in  std_logic;
    reset    : in  std_logic;
    
    enable_i : in  std_logic;
    voice_i  : in  unsigned(3 downto 0);
    freq     : in  unsigned(15 downto 0);
    test     : in  std_logic := '0';
    sync     : in  std_logic := '0';
    
    voice_o  : out unsigned(3 downto 0);
    enable_o : out std_logic;
    test_o   : out std_logic;
    osc_val  : out unsigned(23 downto 0);
    carry_20 : out std_logic;
    msb_other: out std_logic );

end oscillator;


architecture Gideon of oscillator is
    type accu_array_t is array (natural range <>) of unsigned(23 downto 0);
    signal accu_reg  : accu_array_t(0 to g_num_voices-1) := (others => (others => '0'));

    type int4_array is array (natural range <>) of integer range 0 to 15;

    constant voice_linkage : int4_array(0 to 15) := (  2,  0,  1,  7,  3,  4,  5,  6,
                                                      10,  8,  9, 15, 11, 12, 13, 14 );

    signal ring_index   : integer range 0 to 15;
    signal sync_index   : integer range 0 to 15;
    signal msb_register : std_logic_vector(0 to 15) := (others => '0');
    signal car_register : std_logic_vector(0 to 15) := (others => '0');
    signal do_sync      : std_logic;
begin
    sync_index <= voice_linkage(to_integer(voice_i));
    do_sync    <= sync and car_register(sync_index);
    ring_index <= voice_linkage(to_integer(voice_i));
    
    process(clock)
        variable cur_accu   : unsigned(23 downto 0);
        variable new_accu   : unsigned(24 downto 0);
        variable cur_20     : std_logic;
    begin
        if rising_edge(clock) then
            cur_accu := accu_reg(0);
            cur_20   := cur_accu(20);

            if reset='1' or test='1' or do_sync='1' then
                new_accu := (others => '0');
            else
                new_accu := ('0' & cur_accu) + freq;
            end if;

            osc_val   <= new_accu(23 downto 0);
--            carry     <= new_accu(24);
            carry_20  <= new_accu(20) xor cur_20;
            msb_other <= msb_register(ring_index);
            voice_o   <= voice_i;
            enable_o  <= enable_i;
            test_o    <= test;

            if enable_i='1' then
                accu_reg(0 to g_num_voices-2) <= accu_reg(1 to g_num_voices-1);
                accu_reg(g_num_voices-1) <= new_accu(23 downto 0);

                car_register(to_integer(voice_i)) <= new_accu(24);
                msb_register(to_integer(voice_i)) <= cur_accu(23);
            end if;
        end if;
    end process;

end Gideon;
