-------------------------------------------------------------------------------
--
-- The Opcode Decoder.
-- Derives instruction mnemonics and multicycle information
-- using the OPC table unit.
--
-- $Id: opc_decoder.vhd,v 1.3 2005/06/11 10:08:43 arniml Exp $
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

entity t48_opc_decoder is

  generic (
    -- store mnemonic in flip-flops (registered-out)
    register_mnemonic_g : integer := 1
  );

  port (
    -- Global Interface -------------------------------------------------------
    clk_i         : in  std_logic;
    res_i         : in  std_logic;
    en_clk_i      : in  boolean;
    -- T48 Bus Interface ------------------------------------------------------
    data_i        : in  word_t;
    read_bus_i    : in  boolean;
    -- Decoder Interface ------------------------------------------------------
    inj_int_i     : in  boolean;
    opcode_o      : out word_t;
    mnemonic_o    : out mnemonic_t;
    multi_cycle_o : out boolean
  );

end t48_opc_decoder;


use work.t48_pack.clk_active_c;
use work.t48_pack.res_active_c;
use work.t48_pack.to_boolean;
--use work.decoder_pack.MN_NOP;
use work.t48_decoder_pack.all;

use work.t48_comp_pack.t48_opc_table;

architecture rtl of t48_opc_decoder is

  -- the opcode register
  signal opcode_q : word_t;

  -- the mnemonic
  signal mnemonic_s,
         mnemonic_q  : mnemonic_t;

  signal multi_cycle_s : std_logic;

begin

  -----------------------------------------------------------------------------
  -- Verify the generics
  -----------------------------------------------------------------------------

  -- pragma translate_off

  -- Register Mnemonic --------------------------------------------------------
  assert (register_mnemonic_g = 1) or (register_mnemonic_g = 0)
    report "register_mnemonic_g must be either 1 or 0!"
    severity failure;

  -- pragma translate_on


  -----------------------------------------------------------------------------
  -- Opcode Decoder Table
  -----------------------------------------------------------------------------
  opc_table_b : t48_opc_table
    port map (
      opcode_i      => opcode_q,
      multi_cycle_o => multi_cycle_s,
      mnemonic_o    => mnemonic_s
    );


  -----------------------------------------------------------------------------
  -- Process regs
  --
  -- Purpose:
  --   Implements the opcode and mnemonic registers.
  --
  regs: process (res_i, clk_i)
  begin
    if res_i = res_active_c then
      opcode_q     <= (others => '0');      -- NOP
      mnemonic_q   <= MN_NOP;

    elsif clk_i'event and clk_i = clk_active_c then
      if en_clk_i then

        if read_bus_i then
          opcode_q   <= data_i;
        elsif inj_int_i then
          opcode_q   <= "00010100";
        else
          mnemonic_q <= mnemonic_s;
        end if;

      end if;

    end if;

  end process regs;
  --
  -----------------------------------------------------------------------------


  -----------------------------------------------------------------------------
  -- Output Mapping.
  -----------------------------------------------------------------------------
  opcode_o      <= opcode_q;
  multi_cycle_o <= to_boolean(multi_cycle_s);
  mnemonic_o    <=   mnemonic_q
                   when register_mnemonic_g = 1 else
                     mnemonic_s;

end rtl;


-------------------------------------------------------------------------------
-- File History:
--
-- $Log: opc_decoder.vhd,v $
-- Revision 1.3  2005/06/11 10:08:43  arniml
-- introduce prefix 't48_' for all packages, entities and configurations
--
-- Revision 1.2  2004/07/11 16:51:33  arniml
-- cleanup copyright notice
--
-- Revision 1.1  2004/03/23 21:31:52  arniml
-- initial check-in
--
-------------------------------------------------------------------------------
