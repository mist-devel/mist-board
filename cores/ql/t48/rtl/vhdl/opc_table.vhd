-------------------------------------------------------------------------------
--
-- The Opcode Decoder Table.
-- Decodes the given opcode to instruction mnemonics.
-- Also derives the multicycle information.
--
-- $Id: opc_table.vhd,v 1.4 2005/06/11 10:08:43 arniml Exp $
--
-- Copyright (c) 2004, Arnim Laeuger (arniml@opencores.org)
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- Redistributions in synthesized form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- Neither the name of the author nor the names of other contributors may
-- be used to endorse or promote products derived from this software without
-- specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- Please report bugs to the author, but before you do so, please
-- make sure that this is not a derivative work and that
-- you have the latest version of this file.
--
-- The latest version of this file can be found at:
--      http://www.opencores.org/cvsweb.shtml/t48/
--
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

use work.t48_pack.word_t;
use work.t48_decoder_pack.mnemonic_t;

entity t48_opc_table is

  port (
    opcode_i      : in  word_t;
    multi_cycle_o : out std_logic;
    mnemonic_o    : out mnemonic_t
  );

end t48_opc_table;


use work.t48_decoder_pack.all;

architecture rtl of t48_opc_table is

begin

  -----------------------------------------------------------------------------
  -- Process opc_decode
  --
  -- Purpose:
  --  Decode the opcode to the set of mnemonics.
  --
  opc_decode: process (opcode_i)
  begin
    -- default assignment
    mnemonic_o    <= MN_NOP;
    multi_cycle_o <= '0';

    case opcode_i is
      -- Mnemonic ADD ---------------------------------------------------------
      when "01101000" | "01101001" | "01101010" | "01101011" |  -- ADD A, Rr
           "01101100" | "01101101" | "01101110" | "01101111" |  --
           "01100000" | "01100001" |                            -- ADD A, @ Rr
           "01111000" | "01111001" | "01111010" | "01111011" |  -- ADDC A, Rr
           "01111100" | "01111101" | "01111110" | "01111111" |  --
           "01110000" | "01110001" =>                           -- ADDC A, @ Rr
        mnemonic_o    <= MN_ADD;

      -- Mnemonic ADD_A_DATA --------------------------------------------------
      when "00000011" |                                         -- ADD A, data
           "00010011" =>                                        -- ADDC A, data
        mnemonic_o    <= MN_ADD_A_DATA;
        multi_cycle_o <= '1';

      -- Mnemonic ANL ---------------------------------------------------------
      when "01011000" | "01011001" | "01011010" | "01011011" |  -- ANL A, Rr
           "01011100" | "01011101" | "01011110" | "01011111" |  --
           "01010000" | "01010001" =>                           -- ANL A, @ Rr
        mnemonic_o    <= MN_ANL;

      -- Mnemonic ANL_A_DATA --------------------------------------------------
      when "01010011" =>                                        -- ANL A, data
        mnemonic_o    <= MN_ANL_A_DATA;
        multi_cycle_o <= '1';

      -- Mnemonic ANL_EXT -----------------------------------------------------
      when "10011000" |                                         -- ANL BUS, data
           "10011001" | "10011010" =>                           -- ANL PP, data
        mnemonic_o    <= MN_ANL_EXT;
        multi_cycle_o <= '1';

      -- Mnemonic CALL --------------------------------------------------------
      when "00010100" | "00110100" | "01010100" | "01110100" |  -- CALL addr
           "10010100" | "10110100" | "11010100" | "11110100" => --
        mnemonic_o    <= MN_CALL;
        multi_cycle_o <= '1';

      -- Mnemonic CLR_A -------------------------------------------------------
      when "00100111" =>                                        -- CLR A
        mnemonic_o    <= MN_CLR_A;

      -- Mnemonic CLR_C -------------------------------------------------------
      when "10010111" =>                                        -- CLR C
        mnemonic_o    <= MN_CLR_C;

      -- Mnemonic CLR_F -------------------------------------------------------
      when "10000101" |                                         -- CLR F0
           "10100101" =>
        mnemonic_o    <= MN_CLR_F;

      -- Mnemonic CPL_A -------------------------------------------------------
      when "00110111" =>                                        -- CPL A
        mnemonic_o    <= MN_CPL_A;

      -- Mnemonic CPL_C -------------------------------------------------------
      when "10100111" =>                                        -- CPL C
        mnemonic_o    <= MN_CPL_C;

      -- Mnemonic CPL_F -------------------------------------------------------
      when "10010101" |                                         -- CPL F0
           "10110101" =>                                        -- CPL F1
        mnemonic_o    <= MN_CPL_F;

      -- Mnemonic DA ----------------------------------------------------------
      when "01010111" =>                                        -- DA D
        mnemonic_o    <= MN_DA;

      -- Mnemonic DEC ---------------------------------------------------------
      when "11001000" | "11001001" | "11001010" | "11001011" |  -- DEC Rr
           "11001100" | "11001101" | "11001110" | "11001111" |  --
           "00000111" =>                                        -- DEC A
        mnemonic_o    <= MN_DEC;

      -- Mnemonic DIS_EN_I ----------------------------------------------------
      when "00010101" |                                         -- DIS I
           "00000101" =>                                        -- EN I
        mnemonic_o    <= MN_DIS_EN_I;

      -- Mnemonic DIS_EN_TCNTI ------------------------------------------------
      when "00110101" |                                         -- DIS TCNTI
           "00100101" =>                                        -- EN TCNTI
        mnemonic_o    <= MN_DIS_EN_TCNTI;

      -- Mnemonic DJNZ --------------------------------------------------------
      when "11101000" | "11101001" | "11101010" | "11101011" |  -- DJNZ Rr, addr
           "11101100" | "11101101" | "11101110" | "11101111" => --
        mnemonic_o    <= MN_DJNZ;
        multi_cycle_o <= '1';

      -- Mnemonic ENT0_CLK ----------------------------------------------------
      when "01110101" =>                                        -- ENT0 CLK
        mnemonic_o    <= MN_ENT0_CLK;

      -- Mnemonic IN ----------------------------------------------------------
      when "00001001" | "00001010" =>                           -- IN A, Pp
        mnemonic_o    <= MN_IN;
        multi_cycle_o <= '1';

      -- Mnemonic INC ---------------------------------------------------------
      when "00010111" |                                         -- INC A
           "00011000" | "00011001" | "00011010" | "00011011" |  -- INC Rr
           "00011100" | "00011101" | "00011110" | "00011111" |  --
           "00010000" | "00010001" =>                           -- INC @ Rr
        mnemonic_o    <= MN_INC;

      -- Mnemonic INS ---------------------------------------------------------
      when "00001000" =>                                        -- INS A, BUS
        mnemonic_o    <= MN_INS;
        multi_cycle_o <= '1';

      -- Mnemonic JBB ---------------------------------------------------------
      when "00010010" | "00110010" | "01010010" | "01110010" |  -- JBb addr
           "10010010" | "10110010" | "11010010" | "11110010" => --
        mnemonic_o    <= MN_JBB;
        multi_cycle_o <= '1';

      -- Mnemonic JC ----------------------------------------------------------
      when "11110110" |                                         -- JC addr
           "11100110" =>                                        -- JNC addr
        mnemonic_o    <= MN_JC;
        multi_cycle_o <= '1';

      -- Mnemonic JF ----------------------------------------------------------
      when "10110110" |                                         -- JF0 addr
           "01110110" =>                                        -- JF1 addr
        mnemonic_o    <= MN_JF;
        multi_cycle_o <= '1';

      -- Mnemonic JMP ---------------------------------------------------------
      when "00000100" | "00100100" | "01000100" | "01100100" |  -- JMP addr
           "10000100" | "10100100" | "11000100" | "11100100" => --
        mnemonic_o    <= MN_JMP;
        multi_cycle_o <= '1';

      -- Mnemonic JMPP --------------------------------------------------------
      when "10110011" =>                                        -- JMPP @ A
        mnemonic_o    <= MN_JMPP;
        multi_cycle_o <= '1';

      -- Mnemonic JNI ---------------------------------------------------------
      when "10000110" =>                                        -- JNI addr
        mnemonic_o    <= MN_JNI;
        multi_cycle_o <= '1';

      -- Mnemonic JT ----------------------------------------------------------
      when "00100110" |                                         -- JNT0 addr
           "01000110" |                                         -- JNT1 addr
           "00110110" |                                         -- JT0 addr
           "01010110" =>                                        -- JT1 addr
        mnemonic_o    <= MN_JT;
        multi_cycle_o <= '1';

      -- Mnemonic JTF ---------------------------------------------------------
      when "00010110" =>                                        -- JTF addr
        mnemonic_o    <= MN_JTF;
        multi_cycle_o <= '1';

      -- Mnemonic JZ ----------------------------------------------------------
      when "10010110" |                                         -- JNZ addr
           "11000110" =>                                        -- JZ addr
        mnemonic_o    <= MN_JZ;
        multi_cycle_o <= '1';

      -- Mnemonic MOV_A_DATA --------------------------------------------------
      when "00100011" =>                                        -- MOV A, data
        mnemonic_o    <= MN_MOV_A_DATA;
        multi_cycle_o <= '1';

      -- Mnemonic MOV_A_PSW ---------------------------------------------------
      when "11000111" =>                                        -- MOV A, PSW
        mnemonic_o    <= MN_MOV_A_PSW;

      -- Mnemonic MOV_A_RR ----------------------------------------------------
      when "11111000" | "11111001" | "11111010" | "11111011" |  -- MOV A, Rr
           "11111100" | "11111101" | "11111110" | "11111111" |  --
           "11110000" | "11110001" =>                           -- MOV A, @ Rr
        mnemonic_o    <= MN_MOV_A_RR;

      -- Mnemonic MOV_PSW_A ---------------------------------------------------
      when "11010111" =>                                        -- MOV PSW, A
        mnemonic_o    <= MN_MOV_PSW_A;

      -- Mnemonic MOV_RR ------------------------------------------------------
      when "10101000" | "10101001" | "10101010" | "10101011" |  -- MOV Rr, A
           "10101100" | "10101101" | "10101110" | "10101111" |  --
           "10100000" | "10100001" =>                           -- MOV @ Rr, A
        mnemonic_o    <= MN_MOV_RR;

      -- Mnemonic MOV_RR_DATA -------------------------------------------------
      when "10111000" | "10111001" | "10111010" | "10111011" |  -- MOV Rr, data
           "10111100" | "10111101" | "10111110" | "10111111" |  --
           "10110000" | "10110001" =>                           -- MOV @ Rr, data
        mnemonic_o    <= MN_MOV_RR_DATA;
        multi_cycle_o <= '1';

      -- Mnemonic MOV_T -------------------------------------------------------
      when "01100010" |                                         -- MOV T, A
           "01000010" =>                                        -- MOV A, T
        mnemonic_o    <= MN_MOV_T;

      -- Mnemonic MOVD_A_PP ---------------------------------------------------
      when "00001100" | "00001101" | "00001110" | "00001111" => -- MOVD A, Pp
        mnemonic_o    <= MN_MOVD_A_PP;
        multi_cycle_o <= '1';

      -- Mnemonic MOVP --------------------------------------------------------
      when "10100011" |                                         -- MOVP A, @ A
           "11100011" =>                                        -- MOVP3 A, @ A
        mnemonic_o    <= MN_MOVP;
        multi_cycle_o <= '1';

      -- Mnemonic MOVX --------------------------------------------------------
      when "10000000" | "10000001" |                            -- MOVX A, @ Rr
           "10010000" | "10010001" =>                           -- MOVX @ Rr, A
        mnemonic_o    <= MN_MOVX;
        multi_cycle_o <= '1';

      -- Mnemonic NOP ---------------------------------------------------------
      when "00000000" =>                                        -- NOP
        mnemonic_o    <= MN_NOP;

      -- Mnemonic ORL ---------------------------------------------------------
      when "01001000" | "01001001" | "01001010" | "01001011" |  -- ORL A, Rr
           "01001100" | "01001101" | "01001110" | "01001111" |  --
           "01000000" | "01000001" =>                           -- ORL A, @ Rr
        mnemonic_o    <= MN_ORL;

      -- Mnemonic ORL_A_DATA --------------------------------------------------
      when "01000011" =>                                        -- ORL A, data
        mnemonic_o    <= MN_ORL_A_DATA;
        multi_cycle_o <= '1';

      -- Mnemonic ORL_EXT -----------------------------------------------------
      when "10001000" |                                         -- ORL BUS, data
           "10001001" | "10001010" =>                           -- ORL Pp, data
        mnemonic_o    <= MN_ORL_EXT;
        multi_cycle_o <= '1';

      -- Mnemonic OUTD_PP_A ---------------------------------------------------
      when "00111100" | "00111101" | "00111110" | "00111111" |  -- MOVD Pp, A
           "10011100" | "10011101" | "10011110" | "10011111" |  -- ANLD PP, A
           "10001100" | "10001101" | "10001110" | "10001111" => -- ORLD Pp, A
        mnemonic_o    <= MN_OUTD_PP_A;
        multi_cycle_o <= '1';

      -- Mnemonic OUTL_EXT ----------------------------------------------------
      when "00111001" | "00111010" |                            -- OUTL Pp, A
           "00000010" =>                                        -- OUTL BUS, A
        mnemonic_o    <= MN_OUTL_EXT;
        multi_cycle_o <= '1';

      -- Mnemonic RET ---------------------------------------------------------
      when "10000011" |                                         -- RET
           "10010011" =>                                        -- RETR
        mnemonic_o    <= MN_RET;
        multi_cycle_o <= '1';

      -- Mnemonic RL ----------------------------------------------------------
      when "11100111" |                                         -- RL A
           "11110111" =>                                        -- RLC A
        mnemonic_o    <= MN_RL;

      -- Mnemonic RR ----------------------------------------------------------
      when "01110111" |                                         -- RR A
           "01100111" =>                                        -- RRC A
        mnemonic_o    <= MN_RR;

      -- Mnemonic SEL_MB ------------------------------------------------------
      when "11100101" |                                         -- SEL MB0
           "11110101" =>                                        -- SEL MB1
        mnemonic_o    <= MN_SEL_MB;

      -- Mnemonic SEL_RB ------------------------------------------------------
      when "11000101" |                                         -- SEL RB0
           "11010101" =>                                        -- SEL RB1
        mnemonic_o    <= MN_SEL_RB;

      -- Mnemonic STOP_TCNT ---------------------------------------------------
      when "01100101" =>                                        -- STOP TCNT
        mnemonic_o    <= MN_STOP_TCNT;

      -- Mnemonic START -------------------------------------------------------
      when "01000101" |                                         -- STRT CNT
           "01010101" =>                                        -- STRT T
        mnemonic_o    <= MN_STRT;

      -- Mnemonic SWAP --------------------------------------------------------
      when "01000111" =>                                        -- SWAP A
        mnemonic_o    <= MN_SWAP;

      -- Mnemonic XCH ---------------------------------------------------------
      when "00101000" | "00101001" | "00101010" | "00101011" |  -- XCH A, Rr
           "00101100" | "00101101" | "00101110" | "00101111" |  --
           "00100000" | "00100001" |                            -- XCH A, @ Rr
           "00110000" | "00110001" =>                           -- XCHD A, @ Rr
        mnemonic_o    <= MN_XCH;

      -- Mnemonic XRL ---------------------------------------------------------
      when "11011000" | "11011001" | "11011010" | "11011011" |  -- XRL A, Rr
           "11011100" | "11011101" | "11011110" | "11011111" |  --
           "11010000" | "11010001" =>                           -- XRL A, @ Rr
        mnemonic_o    <= MN_XRL;

      -- Mnemonic XRL_A_DATA --------------------------------------------------
      when "11010011" =>                                        -- XRL A, data
        mnemonic_o    <= MN_XRL_A_DATA;
        multi_cycle_o <= '1';

      when others =>
        -- pragma translate_off
        assert now = 0 ns
          report "Unknown opcode."
          severity warning;
        -- pragma translate_on

    end case;

  end process opc_decode;
  --
  -----------------------------------------------------------------------------

end rtl;


-------------------------------------------------------------------------------
-- File History:
--
-- $Log: opc_table.vhd,v $
-- Revision 1.4  2005/06/11 10:08:43  arniml
-- introduce prefix 't48_' for all packages, entities and configurations
--
-- Revision 1.3  2004/07/11 16:51:33  arniml
-- cleanup copyright notice
--
-- Revision 1.2  2004/03/28 13:10:48  arniml
-- merge MN_ANLD, MN_MOVD_PP_A and MN_ORLD_PP_A to OUTLD_PP_A
--
-- Revision 1.1  2004/03/23 21:31:52  arniml
-- initial check-in
--
-------------------------------------------------------------------------------
