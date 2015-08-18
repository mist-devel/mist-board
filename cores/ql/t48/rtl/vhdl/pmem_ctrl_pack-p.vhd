-------------------------------------------------------------------------------
--
-- $Id: pmem_ctrl_pack-p.vhd,v 1.2 2005/06/11 10:08:43 arniml Exp $
--
-- Copyright (c) 2004, Arnim Laeuger (arniml@opencores.org)
--
-- All rights reserved
--
-------------------------------------------------------------------------------

package t48_pmem_ctrl_pack is

  -----------------------------------------------------------------------------
  -- Address Type Identifier
  -----------------------------------------------------------------------------
  type pmem_addr_ident_t is (PM_PC,
                             PM_PAGE,
                             PM_PAGE3);

end t48_pmem_ctrl_pack;


-------------------------------------------------------------------------------
-- File History:
--
-- $Log: pmem_ctrl_pack-p.vhd,v $
-- Revision 1.2  2005/06/11 10:08:43  arniml
-- introduce prefix 't48_' for all packages, entities and configurations
--
-- Revision 1.1  2004/03/23 21:31:53  arniml
-- initial check-in
--
-------------------------------------------------------------------------------
