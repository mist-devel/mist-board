-------------------------------------------------------------------------------
--
-- Synthesizable model of TI's SN76489AN.
--
-- $Id: sn76489_latch_ctrl.vhd,v 1.6 2006/02/27 20:30:10 arnim Exp $
--
-- Latch Control Unit
--
-------------------------------------------------------------------------------
--
-- Copyright (c) 2005, 2006, Arnim Laeuger (arnim.laeuger@gmx.net)
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
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity sn76489_latch_ctrl is

  port (
    clock_i    : in  std_logic;
    clk_en_i   : in  boolean;
    res_n_i    : in  std_logic;
    ce_n_i     : in  std_logic;
    we_n_i     : in  std_logic;
    d_i        : in  std_logic_vector(0 to 7);
    ready_o    : out std_logic;
    tone1_we_o : out boolean;
    tone2_we_o : out boolean;
    tone3_we_o : out boolean;
    noise_we_o : out boolean;
    r2_o       : out std_logic
  );

end sn76489_latch_ctrl;


library ieee;
use ieee.numeric_std.all;

architecture rtl of sn76489_latch_ctrl is

  signal reg_q   : std_logic_vector(0 to 2);
  signal we_q    : boolean;
  signal ready_q : std_logic;

begin

  -----------------------------------------------------------------------------
  -- Process seq
  --
  -- Purpose:
  --   Implements the sequential elements.
  --
  seq: process (clock_i, res_n_i)
  begin
    if res_n_i = '0' then
      reg_q     <= (others => '0');
      we_q      <= false;
      ready_q   <= '0';

    elsif clock_i'event and clock_i = '1' then
      -- READY Flag Output ----------------------------------------------------
      if ready_q = '0' and we_q then
        if clk_en_i then
          -- assert READY when write access happened
          ready_q <= '1';
        end if;
      elsif ce_n_i = '1' then
        -- deassert READY when access has finished
        ready_q <= '0';
      end if;

      -- Register Selection ---------------------------------------------------
      if ce_n_i = '0' and we_n_i = '0' then
        if clk_en_i then
          if d_i(0) = '1' then
            reg_q <= d_i(1 to 3);
          end if;
          we_q  <= true;
        end if;
      else
        we_q  <= false;
      end if;

    end if;
  end process seq;
  --
  -----------------------------------------------------------------------------


  -----------------------------------------------------------------------------
  -- Output mapping
  -----------------------------------------------------------------------------
  tone1_we_o <= reg_q(0 to 1) = "00" and we_q;
  tone2_we_o <= reg_q(0 to 1) = "01" and we_q;
  tone3_we_o <= reg_q(0 to 1) = "10" and we_q;
  noise_we_o <= reg_q(0 to 1) = "11" and we_q;

  r2_o       <= reg_q(2);

  ready_o    <=   ready_q
                when ce_n_i = '0' else
                  '1';

end rtl;
