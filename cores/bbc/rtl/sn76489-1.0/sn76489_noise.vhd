-------------------------------------------------------------------------------
--
-- Synthesizable model of TI's SN76489AN.
--
-- $Id: sn76489_noise.vhd,v 1.6 2006/02/27 20:30:10 arnim Exp $
--
-- Noise Generator
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

entity sn76489_noise is

  port (
    clock_i    : in  std_logic;
    clk_en_i   : in  boolean;
    res_n_i    : in  std_logic;
    we_i       : in  boolean;
    d_i        : in  std_logic_vector(0 to 7);
    r2_i       : in  std_logic;
    tone3_ff_i : in  std_logic;
    noise_o    : out signed(0 to 7)
  );

end sn76489_noise;


use work.sn76489_comp_pack.sn76489_attenuator;

architecture rtl of sn76489_noise is

  signal nf_q       : std_logic_vector(0 to 1);
  signal fb_q       : std_logic;
  signal a_q        : std_logic_vector(0 to 3);
  signal freq_cnt_q : unsigned(0 to 6);
  signal freq_ff_q  : std_logic;

  signal shift_source_s,
         shift_source_q    : std_logic;
  signal shift_rise_edge_s : boolean;

  signal lfsr_q            : std_logic_vector(0 to 15);

  signal freq_s      : signed(0 to 1);

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
      nf_q <= (others => '0');
      fb_q <= '0';
      a_q  <= (others => '1');

    elsif clock_i'event and clock_i = '1' then
      if clk_en_i and we_i then
        if r2_i = '0' then
          -- access to control register
          -- both access types can write to the control register!
          nf_q <= d_i(6 to 7);
          fb_q <= d_i(5);

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
          -- reload frequency counter according to NF setting
          case nf_q is
            when "00" =>
              freq_cnt_q <= to_unsigned(16 * 2 - 1, freq_cnt_q'length);
            when "01" =>
              freq_cnt_q <= to_unsigned(16 * 4 - 1, freq_cnt_q'length);
            when "10" =>
              freq_cnt_q <= to_unsigned(16 * 8 - 1, freq_cnt_q'length);
            when others =>
              null;
          end case;

          freq_ff_q <= not freq_ff_q;

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
  -- Multiplex the source of the LFSR's shift enable
  -----------------------------------------------------------------------------
  shift_source_s <=   tone3_ff_i
                    when nf_q = "11" else
                      freq_ff_q;

  -----------------------------------------------------------------------------
  -- Process rise_edge
  --
  -- Purpose:
  --   Detect the rising edge of the selected LFSR shift source.
  --
  rise_edge: process (clock_i, res_n_i)
  begin
    if res_n_i = '0' then
      shift_source_q <= '0';

    elsif clock_i'event and clock_i = '1' then
      if clk_en_i then
        shift_source_q <= shift_source_s;
      end if;
    end if;
  end process rise_edge;
  --
  -----------------------------------------------------------------------------

  -- detect rising edge on shift source
  shift_rise_edge_s <= shift_source_q = '0' and shift_source_s = '1';


  -----------------------------------------------------------------------------
  -- Process lfsr
  --
  -- Purpose:
  --   Implements the LFSR that generates noise.
  --   Note: This implementation shifts the register right, i.e. from index
  --         15 towards 0 => bit 15 is the input, bit 0 is the output
  --
  --   Tapped bits according to MAME's sn76496.c, implemented in function
  --   lfsr_tapped_f.
  --
  lfsr: process (clock_i, res_n_i)

    function lfsr_tapped_f(lfsr : in std_logic_vector) return std_logic is
      constant tapped_bits_c : std_logic_vector(0 to 15)
        -- tapped bits are 0, 2, 15
        := "1010000000000001";
      variable parity_v : std_logic;
    begin
      parity_v := '0';

      for idx in lfsr'low to lfsr'high loop
        parity_v := parity_v xor (lfsr(idx) and tapped_bits_c(idx));
      end loop;

      return parity_v;
    end;

  begin
    if res_n_i = '0' then
      -- reset LFSR to "0000000000000001"
      lfsr_q               <= (others => '0');
      lfsr_q(lfsr_q'right) <= '1';

    elsif clock_i'event and clock_i = '1' then
      if clk_en_i then
        if we_i and r2_i = '0' then
          -- write to noise register
          -- -> reset LFSR
          lfsr_q               <= (others => '0');
          lfsr_q(lfsr_q'right) <= '1';

        elsif shift_rise_edge_s then

          -- shift LFSR left towards MSB
          for idx in lfsr_q'right-1 downto lfsr_q'left loop
            lfsr_q(idx) <= lfsr_q(idx+1);
          end loop;

          -- determine input bit
          if fb_q = '0' then
            -- "Periodic" Noise
            -- -> input to LFSR is output
            lfsr_q(lfsr_q'right) <= lfsr_q(lfsr_q'left);
          else
            -- "White" Noise
            -- -> input to LFSR is parity of tapped bits
            lfsr_q(lfsr_q'right) <= lfsr_tapped_f(lfsr_q);
          end if;

        end if;

      end if;
    end if;
  end process lfsr;
  --
  -----------------------------------------------------------------------------


  -----------------------------------------------------------------------------
  -- Map output of LFSR to signed value for attenuator.
  -----------------------------------------------------------------------------
  freq_s <=   to_signed(+1, 2)
            when lfsr_q(0) = '1' else
              to_signed( 0, 2);


  -----------------------------------------------------------------------------
  -- The attenuator itself
  -----------------------------------------------------------------------------
  attenuator_b : sn76489_attenuator
    port map (
      attenuation_i => a_q,
      factor_i      => freq_s,
      product_o     => noise_o
    );

end rtl;
