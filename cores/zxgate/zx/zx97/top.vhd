----------------------------------------------------------
--  top.vhd
--		Top level of the ZX97
--		=====================
--
--  04/10/97	Bodo Wenzel	Dummy creation
--  04/16/97	Bodo Wenzel	Filling with "life"
--  04/29/97	Bodo Wenzel	Dividing into modules
--  11/14/97	Bodo Wenzel	Knowledge from ZX81VID
--  11/25/97	Bodo Wenzel	Correcting errors
--  12/03/97	Bodo Wenzel	Additional LCD output
--  03/18/98	Bodo Wenzel	HRG
--  03/20/98	Bodo Wenzel	Paging of memory and
--				reading of initial modes
--  01/28/99	Bodo Wenzel	Improvements
--  04/10/02	Daniel Wallner	Added synchronous bus support
----------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

-- the inputs and outputs --------------------------------

entity top is
  generic (synchronous: boolean := false);
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
end;

-- the description of the logic --------------------------

architecture beh of top is
  component res_clk
  port (clock:      in  std_ulogic;
        phi:        in  std_ulogic;
        mode_reset: in  boolean;
        n_reset:    out std_ulogic;
        n_modes:    out std_ulogic;
        clock_2:    out std_ulogic);
  end component;

  component modes97
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
  end component;

  component video81
  generic (synchronous: boolean := false);
  port (clock:      in  std_ulogic;
        phi:        in  std_ulogic;
        nmi_enable: in  boolean;
        n_nmi:      out std_ulogic;
        n_halt:     in  std_ulogic;
        n_wait:     out std_ulogic;
        n_m1:       in  std_ulogic;
        n_mreq:     in  std_ulogic;
        n_iorq:     in  std_ulogic;
        vsync:      in  boolean;
        a_cpu:      in  std_ulogic_vector(15 downto 13);
        d_mem:      in  std_ulogic_vector(7 downto 0);
        fake_cpu:   out boolean;
        mode_chr13: in  std_ulogic;
        video_addr: out std_ulogic_vector(8 downto 0);
        video_mem:  out boolean;
        mode_v_inv: in  boolean;
        video:      out std_ulogic;
        n_sync:     out std_ulogic);
  end component;

  component lcd97
  port (clock:  in  std_ulogic;
        n_sync: in  std_ulogic;
        video:  in  std_ulogic;
        d_lcd:  out std_ulogic_vector(3 downto 0);
        s:      out std_ulogic;
        cp1:    out std_ulogic;
        cp2:    out std_ulogic);
  end component;

  component io81
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
  end component;

  component busses
  port (mode_rom0:    in  boolean;
        mode_romp:    in  std_ulogic_vector(1 downto 0);
        mode_ram:     in  std_ulogic_vector(1 downto 0);
        a_cpu:        in  std_ulogic_vector(15 downto 0);
        video_addr:   in  std_ulogic_vector(8 downto 0);
        video_mem:    in  boolean;
        a_mem_h:      out std_ulogic_vector(14 downto 13);
        a_mem_l:      out std_ulogic_vector(8 downto 0);
        fake_cpu:     in  boolean;
        d_kbd:        in  std_ulogic_vector(7 downto 0);
        d_kbd_enable: in  boolean;
        d_mem_i:      in  std_ulogic_vector(7 downto 0);
        d_cpu_o:      out std_ulogic_vector(7 downto 0);
        oe_cpu:       out boolean;
        oe_mem:       out boolean;
        n_m1:         in  std_ulogic;
        n_mreq:       in  std_ulogic;
        n_iorq:       in  std_ulogic;
        n_wr:         in  std_ulogic;
        n_rd:         in  std_ulogic;
        n_rfsh:       in  std_ulogic;
        n_romcs:      out std_ulogic;
        n_ramcs:      out std_ulogic);
  end component;

  signal i_n_reset:    std_ulogic;
  signal i_n_modes:    std_ulogic;
  signal mode_reset:   boolean;
  signal mode_v_inv:   boolean;
  signal mode_chr13:   std_ulogic;
  signal mode_rom0:    boolean;
  signal mode_romp:    std_ulogic_vector(1 downto 0);
  signal mode_ram:     std_ulogic_vector(1 downto 0);
  signal vsync:        boolean;
  signal nmi_enable:   boolean;
  signal fake_cpu:     boolean;
  signal video_addr:   std_ulogic_vector(8 downto 0);
  signal video_mem:    boolean;
  signal i_video:      std_ulogic;
  signal i_n_sync:     std_ulogic;
  signal d_kbd:        std_ulogic_vector(7 downto 0);
  signal d_kbd_enable: boolean;
begin
  c_res_clk: res_clk
    port map (clock,phi,mode_reset,
              i_n_reset,i_n_modes,clock_2);

  c_modes97: modes97
    port map (i_n_reset,i_n_modes,phi,
              kbd_col,a_cpu,d_cpu_i,n_mreq,n_wr,
              mode_reset,mode_v_inv,mode_chr13,
              mode_rom0,mode_romp,mode_ram);

  c_video81: video81
    generic map (synchronous)
    port map (clock,phi,
              nmi_enable,n_nmi,n_halt,n_wait,
              n_m1,n_mreq,n_iorq,
              vsync,
              a_cpu(15 downto 13),d_mem_i,
              fake_cpu,mode_chr13,
              video_addr,video_mem,
              mode_v_inv,i_video,i_n_sync);

  c_lcd97: lcd97
    port map (clock,
              i_n_sync,i_video,
              d_lcd,s,cp1,cp2);

  c_io81: io81
    port map (i_n_reset,
              a_cpu(1 downto 0),n_iorq,n_wr,n_rd,
              vsync,nmi_enable,
              kbd_col,usa_uk,tape_in,d_kbd,d_kbd_enable);

  c_busses: busses
    port map (mode_rom0,mode_romp,mode_ram,
              a_cpu,video_addr,video_mem,a_mem_h,a_mem_l,
              fake_cpu,d_kbd,d_kbd_enable,d_mem_i,d_cpu_o,
              oe_cpu,oe_mem,
              n_m1,n_mreq,n_iorq,n_wr,n_rd,n_rfsh,
              n_romcs,n_ramcs);

  n_reset <= i_n_reset;
  n_modes <= i_n_modes;

  video  <= i_video;
  n_sync <= i_n_sync;
end;

-- end ---------------------------------------------------
