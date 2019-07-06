-------------------------------------------------------------------------------
--
-- Delta-Sigma DAC
--
-- $Id: dac.vhd,v 1.1 2006/05/10 20:57:06 arnim Exp $
--
-- Refer to Xilinx Application Note XAPP154.
--
-- This DAC requires an external RC low-pass filter:
--
--   dac_o 0---XXXXX---+---0 analog audio
--              3k3    |
--                    === 4n7
--                     |
--                    GND
--
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity dac is

  generic (
    msbi_g : integer := 7
  );
  port (
    clk_i   : in  std_logic;
    res_n_i : in  std_logic;
    dac_i   : in  std_logic_vector(msbi_g downto 0);
    dac_o   : out std_logic
  );

end dac;

library ieee;
use ieee.numeric_std.all;

architecture rtl of dac is

  signal DACout_q      : std_logic;
  signal DeltaAdder_s,
         SigmaAdder_s,
         SigmaLatch_q,
         DeltaB_s      : unsigned(msbi_g+2 downto 0);

begin

  DeltaB_s(msbi_g+2 downto msbi_g+1) <= SigmaLatch_q(msbi_g+2) &
                                        SigmaLatch_q(msbi_g+2);
  DeltaB_s(msbi_g   downto        0) <= (others => '0');

  DeltaAdder_s <= unsigned('0' & '0' & dac_i) + DeltaB_s;

  SigmaAdder_s <= DeltaAdder_s + SigmaLatch_q;

  seq: process (clk_i, res_n_i)
  begin
    if res_n_i = '0' then
      SigmaLatch_q <= to_unsigned(2**(msbi_g+1), SigmaLatch_q'length);
      DACout_q     <= '0';

    elsif clk_i'event and clk_i = '1' then
      SigmaLatch_q <= SigmaAdder_s;
      DACout_q     <= SigmaLatch_q(msbi_g+2);
    end if;
  end process seq;

  dac_o <= DACout_q;

end rtl;
