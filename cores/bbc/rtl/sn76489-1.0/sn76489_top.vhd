-------------------------------------------------------------------------------
--
-- Synthesizable model of TI's SN76489AN.
--
-- $Id: sn76489_top.vhd,v 1.9 2006/02/27 20:30:10 arnim Exp $
--
-- Chip Toplevel
--
-- References:
--
--   * TI Data sheet SN76489.pdf
--     ftp://ftp.whtech.com/datasheets%20&%20manuals/SN76489.pdf
--
--   * John Kortink's article on the SN76489:
--     http://web.inter.nl.net/users/J.Kortink/home/articles/sn76489/
--
--   * Maxim's "SN76489 notes" in
--     http://www.smspower.org/maxim/docs/SN76489.txt
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
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL; 

entity sn76489_top is

  generic (
    clock_div_16_g : integer := 1
  );
  port (
    clock_i    : in  std_logic;
    clock_en_i : in  std_logic;
    res_n_i    : in  std_logic;
    ce_n_i     : in  std_logic;
    we_n_i     : in  std_logic;
    ready_o    : out std_logic;
    d_i        : in  std_logic_vector(0 to 7);
    aout_o     : out std_logic_vector(0 to 7)
  );

end sn76489_top;


library ieee;
use ieee.numeric_std.all;

architecture struct of sn76489_top is

  signal clk_en_s    : boolean;

  signal tone1_we_s,
         tone2_we_s,
         tone3_we_s,
         noise_we_s  : boolean;
  signal r2_s        : std_logic;

  signal tone1_s,
         tone2_s,
         tone3_s,
         noise_s     : std_logic_vector(0 to 7);

  signal tone3_ff_s  : std_logic;

begin

  -----------------------------------------------------------------------------
  -- Clock Divider
  -----------------------------------------------------------------------------
  clock_div_b : entity work.sn76489_clock_div
    generic map (
      clock_div_16_g => clock_div_16_g
    )
    port map (
      clock_i    => clock_i,
      clock_en_i => clock_en_i,
      res_n_i    => res_n_i,
      clk_en_o   => clk_en_s
    );


  -----------------------------------------------------------------------------
  -- Latch Control = CPU Interface
  -----------------------------------------------------------------------------
  latch_ctrl_b : entity work.sn76489_latch_ctrl
    port map (
      clock_i    => clock_i,
      clk_en_i   => clk_en_s,
      res_n_i    => res_n_i,
      ce_n_i     => ce_n_i,
      we_n_i     => we_n_i,
      d_i        => d_i,
      ready_o    => ready_o,
      tone1_we_o => tone1_we_s,
      tone2_we_o => tone2_we_s,
      tone3_we_o => tone3_we_s,
      noise_we_o => noise_we_s,
      r2_o       => r2_s
    );


  -----------------------------------------------------------------------------
  -- Tone Channel 1
  -----------------------------------------------------------------------------
  tone1_b : entity work.sn76489_tone
    port map (
      clock_i  => clock_i,
      clk_en_i => clk_en_s,
      res_n_i  => res_n_i,
      we_i     => tone1_we_s,
      d_i      => d_i,
      r2_i     => r2_s,
      ff_o     => open,
      tone_o   => tone1_s
    );

  -----------------------------------------------------------------------------
  -- Tone Channel 2
  -----------------------------------------------------------------------------
  tone2_b : entity work.sn76489_tone
    port map (
      clock_i  => clock_i,
      clk_en_i => clk_en_s,
      res_n_i  => res_n_i,
      we_i     => tone2_we_s,
      d_i      => d_i,
      r2_i     => r2_s,
      ff_o     => open,
      tone_o   => tone2_s
    );

  -----------------------------------------------------------------------------
  -- Tone Channel 3
  -----------------------------------------------------------------------------
  tone3_b : entity work.sn76489_tone
    port map (
      clock_i  => clock_i,
      clk_en_i => clk_en_s,
      res_n_i  => res_n_i,
      we_i     => tone3_we_s,
      d_i      => d_i,
      r2_i     => r2_s,
      ff_o     => tone3_ff_s,
      tone_o   => tone3_s
    );

  -----------------------------------------------------------------------------
  -- Noise Channel
  -----------------------------------------------------------------------------
  noise_b : entity work.sn76489_noise
    port map (
      clock_i    => clock_i,
      clk_en_i   => clk_en_s,
      res_n_i    => res_n_i,
      we_i       => noise_we_s,
      d_i        => d_i,
      r2_i       => r2_s,
      tone3_ff_i => tone3_ff_s,
      noise_o    => noise_s
    );


  aout_o <= tone1_s + tone2_s + tone3_s + noise_s;

end struct;
