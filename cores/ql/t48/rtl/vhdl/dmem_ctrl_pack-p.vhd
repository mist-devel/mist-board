-------------------------------------------------------------------------------
--
-- $Id: dmem_ctrl_pack-p.vhd,v 1.2 2005/06/11 10:08:43 arniml Exp $
--
-- Copyright (c) 2004, Arnim Laeuger (arniml@opencores.org)
--
-- All rights reserved
--
-------------------------------------------------------------------------------

package t48_dmem_ctrl_pack is

  -----------------------------------------------------------------------------
  -- Address Type Identifier
  -----------------------------------------------------------------------------
  type dmem_addr_ident_t is (DM_PLAIN,
                             DM_REG,
                             DM_STACK,
                             DM_STACK_HIGH);

end t48_dmem_ctrl_pack;


-------------------------------------------------------------------------------
-- File History:
--
-- $Log: dmem_ctrl_pack-p.vhd,v $
-- Revision 1.2  2005/06/11 10:08:43  arniml
-- introduce prefix 't48_' for all packages, entities and configurations
--
-- Revision 1.1  2004/03/23 21:31:52  arniml
-- initial check-in
--
-------------------------------------------------------------------------------
