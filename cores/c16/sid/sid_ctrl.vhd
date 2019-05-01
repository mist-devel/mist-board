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

entity sid_ctrl is
generic (
    g_num_voices  : natural := 8 );
port (
    clock       : in  std_logic;
    reset       : in  std_logic;

    start_iter  : in  std_logic;

    voice_osc   : out unsigned(3 downto 0);
    enable_osc  : out std_logic );

end sid_ctrl;

architecture gideon of sid_ctrl is

    signal voice_cnt   : unsigned(3 downto 0);
    signal enable      : std_logic;

begin
    process(clock)
    begin
        if rising_edge(clock) then
            if reset='1' then
                voice_cnt <= X"0";
                enable <= '0';
            elsif start_iter='1' then
                voice_cnt <= X"0";
                enable <= '1';
            elsif voice_cnt = g_num_voices-1 then
                voice_cnt <= X"0";
                enable <= '0';
            elsif enable='1' then
                voice_cnt <= voice_cnt + 1;
                enable <= '1';
            end if;
        end if;
    end process;
    
    voice_osc  <= voice_cnt;
    enable_osc <= enable;
end gideon;
