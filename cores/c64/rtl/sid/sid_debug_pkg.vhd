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

package sid_debug_pkg is

    type t_voice_debug is record
        state           : unsigned(1 downto 0);
        enveloppe       : unsigned(7 downto 0);
        pre15           : unsigned(14 downto 0);
        pre5            : unsigned(4 downto 0);
        presc           : unsigned(14 downto 0);
        gate            : std_logic;
        attack          : std_logic_vector(3 downto 0);
        decay           : std_logic_vector(3 downto 0);
        sustain         : std_logic_vector(3 downto 0);
        release         : std_logic_vector(3 downto 0);
    end record;

    type t_voice_debug_array is array(natural range <>) of t_voice_debug;

end;
