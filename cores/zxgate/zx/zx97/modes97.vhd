----------------------------------------------------------
--  modes97.vhd
--			Modes for ZX97
--			==============
--
--  04/29/97	Bodo Wenzel	Got from old top.vhd
--  11/14/97	Bodo Wenzel	Changed to POKE
--  11/26/97	Bodo Wenzel	ROM select
--  03/20/98	Bodo Wenzel	Paging of memory
--				and reading initial modes
--  03/23/98	Bodo Wenzel	Video inversion
--  01/28/99	Bodo Wenzel	New modes
----------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

-- the inputs and outputs --------------------------------

entity modes97 is
  port (n_reset:    in  std_ulogic;
        n_modes:    in  std_ulogic;
        phi:        in  std_ulogic;
        kbd_col:    in  std_ulogic_vector(4 downto 0);
        addr:       in  std_ulogic_vector(15 downto 0);
        data:       in  std_ulogic_vector(7 downto 0);
        n_mreq:     in  std_ulogic;
        n_wr:       in  std_ulogic;
        mode_reset: out boolean;
        mode_v_inv: out boolean;
        mode_chr13: out std_ulogic;
        mode_rom0:  out boolean;
        mode_romp:  out std_ulogic_vector(1 downto 0);
        mode_ram:   out std_ulogic_vector(1 downto 0));
end;

-- the description of the logic --------------------------

architecture beh of modes97 is
  constant POKE: std_ulogic_vector(15 downto 0)
                 := "0000000000000111";

  signal poke7: boolean;
begin
  poke7 <= n_mreq='0' and n_wr='0' and addr=POKE;

  process (n_reset,phi)
  begin
    if n_reset='0' then
      mode_reset <= FALSE;
    elsif rising_edge(phi) then
      if poke7 then
        mode_reset <= data(7)='1';
      end if;
    end if;
  end process;

  process (n_modes,phi)
  begin
    if n_modes='0' then
      mode_chr13 <= '0';
      mode_rom0  <= TRUE;
    elsif rising_edge(phi) then
      if poke7 then
        mode_chr13 <= data(2);
        mode_rom0  <= data(6)='1';
      end if;
    end if;
  end process;

  process (phi)
  begin
    if rising_edge(phi) then
      if n_modes='0' then
        mode_romp  <= kbd_col(3 downto 2);
        mode_v_inv <= kbd_col(4)='0';
        mode_ram   <= kbd_col(1 downto 0);
      elsif poke7 then
        mode_romp  <= data(5 downto 4);
        mode_v_inv <= data(3)='0';
        mode_ram   <= data(1 downto 0);
      end if;
    end if;
  end process;
end;

-- end ---------------------------------------------------
