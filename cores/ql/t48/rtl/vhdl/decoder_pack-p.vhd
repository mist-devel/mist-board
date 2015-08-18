-------------------------------------------------------------------------------
--
-- $Id: decoder_pack-p.vhd,v 1.3 2005/06/11 10:08:43 arniml Exp $
--
-- Copyright (c) 2004, Arnim Laeuger (arniml@opencores.org)
--
-- All rights reserved
--
-------------------------------------------------------------------------------

package t48_decoder_pack is

  -----------------------------------------------------------------------------
  -- The Mnemonics.
  -----------------------------------------------------------------------------
  type mnemonic_t is (MN_ADD,
                      MN_ADD_A_DATA,
                      MN_ANL,
                      MN_ANL_A_DATA,
                      MN_ANL_EXT,
                      MN_CALL,
                      MN_CLR_A,
                      MN_CLR_C,
                      MN_CLR_F,
                      MN_CPL_A,
                      MN_CPL_C,
                      MN_CPL_F,
                      MN_DA,
                      MN_DEC,
                      MN_DIS_EN_I,
                      MN_DIS_EN_TCNTI,
                      MN_DJNZ,
                      MN_ENT0_CLK,
                      MN_IN,
                      MN_INC,
                      MN_INS,
                      MN_JBB,
                      MN_JC,
                      MN_JF,
                      MN_JMP,
                      MN_JMPP,
                      MN_JNI,
                      MN_JT,
                      MN_JTF,
                      MN_JZ,
                      MN_MOV_A_DATA,
                      MN_MOV_A_PSW,
                      MN_MOV_A_RR,
                      MN_MOV_PSW_A,
                      MN_MOV_RR,
                      MN_MOV_RR_DATA,
                      MN_MOV_T,
                      MN_MOVD_A_PP,
                      MN_MOVP,
                      MN_MOVX,
                      MN_NOP,
                      MN_ORL,
                      MN_ORL_A_DATA,
                      MN_ORL_EXT,
                      MN_OUTD_PP_A,
                      MN_OUTL_EXT,
                      MN_RET,
                      MN_RL,
                      MN_RR,
                      MN_SEL_MB,
                      MN_SEL_RB,
                      MN_STOP_TCNT,
                      MN_STRT,
                      MN_SWAP,
                      MN_XCH,
                      MN_XRL,
                      MN_XRL_A_DATA);

end t48_decoder_pack;


-------------------------------------------------------------------------------
-- File History:
--
-- $Log: decoder_pack-p.vhd,v $
-- Revision 1.3  2005/06/11 10:08:43  arniml
-- introduce prefix 't48_' for all packages, entities and configurations
--
-- Revision 1.2  2004/03/28 13:09:53  arniml
-- merge MN_ANLD, MN_MOVD_PP_A and MN_ORLD_PP_A to OUTLD_PP_A
--
-- Revision 1.1  2004/03/23 21:31:52  arniml
-- initial check-in
--
-------------------------------------------------------------------------------
