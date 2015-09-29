-------------------------------------------------------------------------------
--
-- Synthesizable model of TI's SN76489AN.
--
-- $Id: sn76489_tone.vhd,v 1.5 2006/02/27 20:30:10 arnim Exp $
--
-- Tone Generator
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
use ieee.numeric_std.all;

entity sn76489_tone is

  port (
    clock_i  : in  std_logic;
    clk_en_i : in  boolean;
    res_n_i  : in  std_logic;
    we_i     : in  boolean;
    d_i      : in  std_logic_vector(0 to 7);
    r2_i     : in  std_logic;
    ff_o     : out std_logic;
    tone_o   : out signed(0 to 7)
  );

end sn76489_tone;


use work.sn76489_comp_pack.sn76489_attenuator;

architecture rtl of sn76489_tone is

  signal f_q        : std_logic_vector(0 to 9);
  signal a_q        : std_logic_vector(0 to 3);
  signal freq_cnt_q : unsigned(0 to 9);
  signal freq_ff_q  : std_logic;

  signal freq_s     : signed(0 to 1);

  function all_zero(a : in std_logic_vector) return boolean is
    variable result_v : boolean;
  begin
    result_v := true;

    for idx in a'low to a'high loop
      if a(idx) /= '0' then
        result_v := false;
      end if;
    end loop;

    return result_v;
  end;

begin

  -----------------------------------------------------------------------------
  -- Process cpu_regs
  --
  -- Purpose:
  --   Implements the registers writable by the CPU.
  --
  cpu_regs: process (clock_i, res_n_i)
  begin
    if res_n_i = '0' then
      f_q <= (others => '0');
      a_q <= (others => '1');

    elsif clock_i'event and clock_i = '1' then
      if clk_en_i and we_i then
        if r2_i = '0' then
          -- access to frequency register
          if d_i(0) = '0' then
            f_q(0 to 5) <= d_i(2 to 7);
          else
            f_q(6 to 9) <= d_i(4 to 7);
          end if;

        else
          -- access to attenuator register
          -- both access types can write to the attenuator register!
          a_q <= d_i(4 to 7);

        end if;
      end if;
    end if;
  end process cpu_regs;
  --
  -----------------------------------------------------------------------------


  -----------------------------------------------------------------------------
  -- Process freq_gen
  --
  -- Purpose:
  --   Implements the frequency generation components.
  --
  freq_gen: process (clock_i, res_n_i)
  begin
    if res_n_i = '0' then
      freq_cnt_q <= (others => '0');
      freq_ff_q  <= '0';

    elsif clock_i'event and clock_i = '1' then
      if clk_en_i then
        if freq_cnt_q = 0 then
          -- update counter from frequency register
          freq_cnt_q <= unsigned(f_q);

          -- and toggle the frequency flip-flop if enabled
          if not all_zero(f_q) then
            freq_ff_q <= not freq_ff_q;
          else
            -- if frequency setting is 0, then keep flip-flop at +1
            freq_ff_q <= '1';
          end if;

        else
          -- decrement frequency counter
          freq_cnt_q <= freq_cnt_q - 1;

        end if;
      end if;
    end if;
  end process freq_gen;
  --
  -----------------------------------------------------------------------------


  -----------------------------------------------------------------------------
  -- Map frequency flip-flop to signed value for attenuator.
  -----------------------------------------------------------------------------
  freq_s <=   to_signed(+1, 2)
            when freq_ff_q = '1' else
              to_signed(-1, 2);


  -----------------------------------------------------------------------------
  -- The attenuator itself
  -----------------------------------------------------------------------------
  attenuator_b : sn76489_attenuator
    port map (
      attenuation_i => a_q,
      factor_i      => freq_s,
      product_o     => tone_o
    );


  -----------------------------------------------------------------------------
  -- Output mapping
  -----------------------------------------------------------------------------
  ff_o <= freq_ff_q;

end rtl;
