-------------------------------------------------------------------------------
--
-- $Id: t48_tb_pack-p.vhd,v 1.2 2004/04/14 20:53:54 arniml Exp $
--
-- Copyright (c) 2004, Arnim Laeuger (arniml@opencores.org)
--
-- All rights reserved
--
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

package t48_tb_pack is

  -- Instruction strobe visibility
  signal tb_istrobe_s : std_logic;

  -- Accumulator visibilty
  signal tb_accu_s : std_logic_vector(7 downto 0);

end t48_tb_pack;
