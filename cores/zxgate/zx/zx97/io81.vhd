----------------------------------------------------------
--  io81.vhd
--			ZX81 Input and Output
--			=====================
--
--  04/28/97	Bodo Wenzel	Got from old top.vhd
--  11/14/97	Bodo Wenzel	Some polish
--  11/25/97	Bodo Wenzel	Correcting errors
----------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

-- the inputs and outputs --------------------------------

entity io81 is
  port (n_reset:      in  std_ulogic;
        addr:         in  std_ulogic_vector(1 downto 0);
        n_iorq:       in  std_ulogic;
        n_wr:         in  std_ulogic;
        n_rd:         in  std_ulogic;
        vsync:        out boolean;
        nmi_enable:   out boolean;
        kbd_col:      in  std_ulogic_vector(4 downto 0);
        usa_uk:       in  std_ulogic;
        tape_in:      in  std_ulogic;
        d_kbd:        out std_ulogic_vector(7 downto 0);
        d_kbd_enable: out boolean);
end;

-- the description of the logic --------------------------

architecture beh of io81 is
  signal iowr: std_ulogic;
  signal iord: std_ulogic;

  signal i_nmi_enable: boolean;
begin
  iowr <= not n_iorq and not n_wr;
  iord <= not n_iorq and not n_rd;

  process (n_reset,iowr)
  begin
    if n_reset='0' then
      i_nmi_enable <= FALSE;
    elsif rising_edge(iowr) then
      if addr(0)='0' then
        i_nmi_enable <= TRUE;
      elsif addr(1)='0' then
        i_nmi_enable <= FALSE;
      end if;
    end if;
  end process;

  nmi_enable <= i_nmi_enable;

  process (iowr,iord)
  begin
    if iowr='1' then
      vsync <= FALSE;
    elsif rising_edge(iord) then
      if addr(0)='0' and not i_nmi_enable then
        vsync <= TRUE;
      end if;
    end if;
  end process;

  d_kbd        <= tape_in & usa_uk & '0' & kbd_col;
  d_kbd_enable <= n_iorq='0' and n_rd='0' and addr(0)='0';
end;

-- end ---------------------------------------------------
