-------------------------------------------------------------------------------
--
-- $Id: cond_branch_pack-p.vhd,v 1.2 2005/06/11 10:08:43 arniml Exp $
--
-- Copyright (c) 2004, Arnim Laeuger (arniml@opencores.org)
--
-- All rights reserved
--
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

package t48_cond_branch_pack is

  -----------------------------------------------------------------------------
  -- The branch conditions.
  -----------------------------------------------------------------------------
  type branch_conditions_t is (COND_ON_BIT, COND_Z,
                               COND_C,
                               COND_F0, COND_F1,
                               COND_INT,
                               COND_T0, COND_T1,
                               COND_TF);

  subtype comp_value_t is std_logic_vector(2 downto 0);

end t48_cond_branch_pack;


-------------------------------------------------------------------------------
-- File History:
--
-- $Log: cond_branch_pack-p.vhd,v $
-- Revision 1.2  2005/06/11 10:08:43  arniml
-- introduce prefix 't48_' for all packages, entities and configurations
--
-- Revision 1.1  2004/03/23 21:31:52  arniml
-- initial check-in
--
-------------------------------------------------------------------------------
