-------------------------------------------------------------------------------
--
-- Synthesizable model of TI's SN76489AN.
--
-- $Id: sn76489_top-c.vhd,v 1.3 2005/10/10 22:12:38 arnim Exp $
--
-------------------------------------------------------------------------------

configuration sn76489_top_struct_c0 of sn76489_top is

  for struct

    for clock_div_b : sn76489_clock_div
      use configuration work.sn76489_clock_div_rtl_c0;
    end for;

    for latch_ctrl_b : sn76489_latch_ctrl
      use configuration work.sn76489_latch_ctrl_rtl_c0;
    end for;

    for all : sn76489_tone
      use configuration work.sn76489_tone_rtl_c0;
    end for;

    for noise_b : sn76489_noise
      use configuration work.sn76489_noise_rtl_c0;
    end for;

  end for;

end sn76489_top_struct_c0;
