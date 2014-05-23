----------------------------------------------------------
--  res_clk.vhd
--			Reset and Clock
--			===============
--
--  04/28/97	Bodo Wenzel	Got from old top.vhd
--  11/27/97	Bodo Wenzel	Some polish
--  03/20/98	Bodo Wenzel	Reset per software and
--				reading of initial modes
--  01/26/99	Bodo Wenzel	Reduced clock
----------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

-- the inputs and outputs --------------------------------

entity res_clk is
  port (clock:      in  std_ulogic;
        phi:        in  std_ulogic;
        mode_reset: in  boolean;
        n_reset:    out std_ulogic;
        n_modes:    out std_ulogic;
        clock_2:    out std_ulogic);
end;

-- the description of the logic --------------------------

architecture beh of res_clk is
  constant RES_READ: natural := 4;
  constant RES_MAX:  natural := 8-1;

  signal timer:   natural range 0 to RES_MAX := 0;
                  -- The initialization is important!
  signal i_reset: boolean;
  signal i_phi:   bit;
begin
  n_modes <= '0' when (timer<RES_READ)
        else '1';

  i_reset <= (timer/=RES_MAX);

  process (phi)
  begin
    if rising_edge(phi) then
      if mode_reset then
        timer <= RES_READ;
      elsif i_reset then
        timer <= timer+1;
      end if;
    end if;
  end process;

  n_reset <= '0' when i_reset
        else '1';

  process (clock)
  begin
    if rising_edge(clock) then
      if i_phi='0' then
        i_phi <= '1';
      else
        i_phi <= '0';
      end if;
    end if;
  end process;

  clock_2 <= '1' when i_phi='1'
        else '0';
end;

-- end ---------------------------------------------------
