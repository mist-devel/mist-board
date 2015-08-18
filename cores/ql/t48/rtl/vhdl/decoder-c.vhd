-------------------------------------------------------------------------------
--
-- The Decoder unit.
-- It decodes the instruction opcodes and executes them.
--
-- $Id: decoder-c.vhd,v 1.2 2005/06/11 10:08:43 arniml Exp $
--
-- Copyright (c) 2004, Arnim Laeuger (arniml@opencores.org)
--
-- All rights reserved
--
-------------------------------------------------------------------------------

configuration t48_decoder_rtl_c0 of t48_decoder is

  for rtl

    for opc_decoder_b: t48_opc_decoder
      use configuration work.t48_opc_decoder_rtl_c0;
    end for;

    for int_b: t48_int
      use configuration work.t48_int_rtl_c0;
    end for;

  end for;

end t48_decoder_rtl_c0;
