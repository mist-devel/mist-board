----------------------------------------------------------
--  zx97.vhd
--		Pad bindings of the ZX97 FPGA
--		=============================
--
--  04/25/97	Bodo Wenzel	Creation
--  11/17/97	Bodo Wenzel	Some polish
--  11/25/97	Bodo Wenzel	Single video output
--  12/03/97	Bodo Wenzel	Additional LCD output
--  03/20/98	Bodo Wenzel	Reading of initial modes
--  02/08/99	Bodo Wenzel	Improvements
----------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
library UNISIM;
use UNISIM.vcomponents.all;

-- the pads ----------------------------------------------

entity zx97 is
  port (n_reset: out   std_ulogic;
        phi:     out   std_ulogic;
        n_modes: out   std_ulogic;
        a_mem_h: out   std_ulogic_vector(14 downto 13);
        a_mem_l: out   std_ulogic_vector(8 downto 0);
        d_mem:   inout std_logic_vector(7 downto 0);
        a_cpu:   in    std_ulogic_vector(15 downto 0);
        d_cpu:   inout std_logic_vector(7 downto 0);
        n_m1:    in    std_ulogic;
        n_mreq:  in    std_ulogic;
        n_iorq:  in    std_ulogic;
        n_wr:    in    std_ulogic;
        n_rd:    in    std_ulogic;
        n_rfsh:  in    std_ulogic;
        n_nmi:   out   std_ulogic;
        n_halt:  in    std_ulogic;
        n_wait:  out   std_ulogic;
        n_romcs: out   std_ulogic;
        n_ramcs: out   std_ulogic;
        kbd_col: inout std_logic_vector(4 downto 0);
        usa_uk:  inout std_logic;
        video:   out   std_ulogic;
        tape_in: in    std_ulogic;
        d_lcd:   out   std_ulogic_vector(3 downto 0);
        s:       out   std_ulogic;
        cp1:     out   std_ulogic;
        cp2:     out   std_ulogic);
end;

-- the input/output-buffers ------------------------------

architecture iopads of zx97 is
  component gxtl
  port (o: out std_ulogic);
  end component;

  component gclk
  port (i: in  std_logic;
        o: out std_ulogic);
  end component;

  component pullup
  port (o: out std_logic);
  end component;

  component ibuf
  port (i: inout std_logic;
        o: out   std_ulogic);
  end component;

  component top
  port (clock:   in  std_ulogic;
        clock_2: out std_ulogic;
        phi:     in  std_ulogic;
        n_reset: out std_ulogic;
        n_modes: out std_ulogic;
        a_mem_h: out std_ulogic_vector(14 downto 13);
        a_mem_l: out std_ulogic_vector(8 downto 0);
        d_mem_i: in  std_ulogic_vector(7 downto 0);
        a_cpu:   in  std_ulogic_vector(15 downto 0);
        d_cpu_i: in  std_ulogic_vector(7 downto 0);
        d_cpu_o: out std_ulogic_vector(7 downto 0);
        oe_cpu:  out boolean;
        oe_mem:  out boolean;
        n_m1:    in  std_ulogic;
        n_mreq:  in  std_ulogic;
        n_iorq:  in  std_ulogic;
        n_wr:    in  std_ulogic;
        n_rd:    in  std_ulogic;
        n_rfsh:  in  std_ulogic;
        n_nmi:   out std_ulogic;
        n_halt:  in  std_ulogic;
        n_wait:  out std_ulogic;
        n_romcs: out std_ulogic;
        n_ramcs: out std_ulogic;
        kbd_col: in  std_ulogic_vector(4 downto 0);
        usa_uk:  in  std_ulogic;
        video:   out std_ulogic;
        n_sync:  out std_ulogic;
        tape_in: in  std_ulogic;
        d_lcd:   out std_ulogic_vector(3 downto 0);
        s:       out std_ulogic;
        cp1:     out std_ulogic;
        cp2:     out std_ulogic);
  end component;

  signal clock:     std_ulogic;
  signal clock_2:   std_ulogic;
  signal i_phi:     std_ulogic;
  signal i_n_modes: std_ulogic;
  signal oe_cpu:    boolean;
  signal oe_mem:    boolean;
  signal d_mem_i:   std_ulogic_vector(7 downto 0);
  signal d_cpu_i:   std_ulogic_vector(7 downto 0);
  signal d_cpu_o:   std_ulogic_vector(7 downto 0);
  signal i_kbd_col: std_ulogic_vector(4 downto 0);
  signal i_usa_uk:  std_ulogic;
  signal i_video:   std_ulogic;
  signal i_n_sync:  std_ulogic;
begin
  c_top: top
    port map (clock,clock_2,i_phi,
              n_reset,i_n_modes,
              a_mem_h,a_mem_l,d_mem_i,
              a_cpu,d_cpu_i,d_cpu_o,
              oe_cpu,oe_mem,
              n_m1,n_mreq,n_iorq,n_wr,n_rd,n_rfsh,
              n_nmi,n_halt,n_wait,n_romcs,n_ramcs,
              i_kbd_col,i_usa_uk,
              i_video,i_n_sync,tape_in,
              d_lcd,s,cp1,cp2);

  c_clock: gxtl port map (o=>clock);

  c_clock2: gclk port map (i=>clock_2,o=>i_phi);

  phi <= clock_2;

  n_modes <= '0' when i_n_modes='0'
        else 'Z';

  d_mem_i <= std_ulogic_vector(d_mem);
  d_mem   <= std_logic_vector(d_cpu_i) when oe_mem
        else (others => 'Z');

  d_cpu_i <= std_ulogic_vector(d_cpu);
  d_cpu   <= std_logic_vector(d_cpu_o) when oe_cpu
        else (others => 'Z');

  g_kbd_col:
  for i in kbd_col'range generate
    r_kbd_col: pullup port map (o=>kbd_col(i));
    p_kbd_col: ibuf port map (i=>kbd_col(i),
                              o=>i_kbd_col(i));
  end generate;

  r_usa_uk: pullup port map (o=>usa_uk);
  p_usa_uk: ibuf port map (i=>usa_uk,o=>i_usa_uk);

  video <= '0' when i_n_sync='0'
      else 'Z' when i_video='0'
      else '1';
end;

-- end ---------------------------------------------------
