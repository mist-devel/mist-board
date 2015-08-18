-------------------------------------------------------------------------------
--
-- T8x48 ROM
--
-- $Id: t48_rom-struct-c.vhd,v 1.1.1.1 2006/11/26 10:07:52 arnim Exp $
--
-- Copyright (c) 2006, Arnim Laeuger (arniml@opencores.org)
--
-- All rights reserved
--
-------------------------------------------------------------------------------

configuration t48_rom_struct_c0 of t48_rom is

  for struct

    for rom_b: rom_t48
      use configuration work.rom_t48_rtl_c0;
    end for;

  end for;

end t48_rom_struct_c0;
