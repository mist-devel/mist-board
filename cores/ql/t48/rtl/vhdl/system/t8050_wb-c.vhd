-------------------------------------------------------------------------------
--
-- T8048 Microcontroller System
--
-- $Id: t8050_wb-c.vhd,v 1.2 2005/06/11 10:19:14 arniml Exp $
--
-- Copyright (c) 2005, Arnim Laeuger (arniml@opencores.org)
--
-- All rights reserved
--
-------------------------------------------------------------------------------

configuration t8050_wb_struct_c0 of t8050_wb is

  for struct

    for rom_4k_b : syn_rom
      use configuration work.syn_rom_lpm_c0;
    end for;

    for ram_256_b : syn_ram
      use configuration work.syn_ram_lpm_c0;
    end for;

    for wb_master_b : t48_wb_master
      use configuration work.t48_wb_master_rtl_c0;
    end for;

    for t48_core_b : t48_core
      use configuration work.t48_core_struct_c0;
    end for;

  end for;

end t8050_wb_struct_c0;
