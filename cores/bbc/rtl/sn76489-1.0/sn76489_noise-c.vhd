-------------------------------------------------------------------------------
--
-- Synthesizable model of TI's SN76489AN.
--
-- $Id: sn76489_noise-c.vhd,v 1.2 2005/10/10 22:12:38 arnim Exp $
--
-------------------------------------------------------------------------------

configuration sn76489_noise_rtl_c0 of sn76489_noise is

  for rtl

    for attenuator_b : sn76489_attenuator
      use configuration work.sn76489_attenuator_rtl_c0;
    end for;

  end for;

end sn76489_noise_rtl_c0;
