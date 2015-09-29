-------------------------------------------------------------------------------
--
-- $Id: sn76489_comp_pack-p.vhd,v 1.6 2006/02/27 20:30:10 arnim Exp $
--
-- Copyright (c) 2005, 2006, Arnim Laeuger (arnim.laeuger@gmx.net)
--
-- All rights reserved
--
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package sn76489_comp_pack is

  component sn76489_attenuator
    port (
      attenuation_i : in  std_logic_vector(0 to 3);
      factor_i      : in  signed(0 to 1);
      product_o     : out signed(0 to 7)
    );
  end component;

  component sn76489_tone
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
  end component;

  component sn76489_noise
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
  end component;

  component sn76489_latch_ctrl
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
  end component;

  component sn76489_clock_div
    generic (
      clock_div_16_g : integer := 1
    );
    port (
      clock_i    : in  std_logic;
      clock_en_i : in  std_logic;
      res_n_i    : in  std_logic;
      clk_en_o   : out boolean
    );
  end component;

  component sn76489_top
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
      aout_o     : out signed(0 to 7)
    );
  end component;

end sn76489_comp_pack;
