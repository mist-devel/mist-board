-------------------------------------------------------------------------------
--
-- The Opcode Decoder.
-- Derives instruction mnemonics and multicycle information
-- using the OPC table unit.
--
-- $Id: opc_decoder-c.vhd,v 1.2 2005/06/11 10:08:43 arniml Exp $
--
-- All rights reserved
--
-------------------------------------------------------------------------------

configuration t48_opc_decoder_rtl_c0 of t48_opc_decoder is

  for rtl

    for opc_table_b: t48_opc_table
      use configuration work.t48_opc_table_rtl_c0;
    end for;

  end for;

end t48_opc_decoder_rtl_c0;
