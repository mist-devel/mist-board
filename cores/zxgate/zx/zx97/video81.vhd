----------------------------------------------------------
--  video81.vhd
--			Videologic of ZX81
--			==================
--
--  04/29/97	Bodo Wenzel	Got from old top.vhd
--  11/18/97	Bodo Wenzel	Knowledge from ZX81VID
--  11/21/97	Bodo Wenzel	Correcting errors
--  12/03/97	Bodo Wenzel	Additional LCD output
--  03/18/98	Bodo Wenzel	HRG, if refresh >= 4000H
--  03/19/98	Bodo Wenzel	Added mode_v_inv
--  03/23/98	Bodo Wenzel	Faking only if >=0C000H
--  01/26/99	Bodo Wenzel	Reduce needed logic
--  04/10/02	Daniel Wallner	Added synchronous bus support
----------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;

-- the inputs and outputs --------------------------------

entity video81 is
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
end;

-- the description of the logic --------------------------

architecture beh of video81 is
  constant HSYNC_BEGIN: natural := 192;
  constant HSYNC_GAP:   natural := 16;
  constant LINE_LEN:    natural := 207-1;

  signal line_cnt:    natural range 0 to LINE_LEN;
  signal hsync:       boolean;
  signal hsync2:      boolean;
  signal nmi_out:     boolean;
  signal faking:      boolean;
  signal row_count:   unsigned(2 downto 0);
  signal chr_inv:     std_ulogic;
  signal chr_addr:    std_ulogic_vector(5 downto 0);
  signal video_pixel: std_ulogic_vector(7 downto 0);

  signal video_read:  boolean;
begin
  process (vsync,phi)
  begin
    if vsync then
      line_cnt <= 0;
    elsif rising_edge(phi) then
      if n_iorq='0' and n_m1='0' then
        line_cnt <= HSYNC_BEGIN-HSYNC_GAP;
      elsif line_cnt>=LINE_LEN then
        line_cnt <= 0;
      else
        line_cnt <= line_cnt+1;
      end if;
    end if;
  end process;

  hsync <= (line_cnt>=HSYNC_BEGIN);

  nmi_out <= (hsync and nmi_enable);
  n_nmi   <= '0' when nmi_out
        else '1';
  n_wait  <= '0' when nmi_out and n_halt='1'
        else '1';

  n_sync <= '0' when hsync or vsync
       else '1';

  process (phi)
  begin
    if falling_edge(phi) then
      if n_m1='0' and n_mreq='0' and
         a_cpu(15)='1' and a_cpu(14)='1' and
         d_mem(6)='0' and n_halt='1' then
        chr_inv  <= d_mem(7);
        chr_addr <= d_mem(5 downto 0);
        faking <= TRUE;
      elsif n_mreq='0' then
        faking <= FALSE;
      end if;
    end if;
  end process;

  fake_cpu <= faking and n_m1='0';

  process (vsync,clock)
  begin
    if vsync then
      row_count <= (others=>'0');
    elsif rising_edge(clock) then
      if hsync and not hsync2 then
        row_count <= row_count+1;
      end if;
      hsync2 <= hsync;
    end if;
  end process;

  video_mem  <= faking and n_m1='1' and
                a_cpu(15)='0' and a_cpu(14)='0' and
                (a_cpu(13)='0' or mode_chr13='1');
  video_addr <= chr_addr & std_ulogic_vector(row_count);

  g_synct : if synchronous generate
    process (clock)
    begin
      if rising_edge(clock) then
        if faking and n_mreq='0' and n_m1='1' and not video_read then
          video_read <= true;
        else
          video_read <= false;
        end if;
      end if;
    end process;
  end generate;

  g_syncf : if not synchronous generate
    process (n_mreq,phi)
    begin
      if n_mreq='1' then
        video_read <= FALSE;
      elsif rising_edge(phi) then
        video_read <= faking;
      end if;
    end process;
  end generate;

  process (clock)
  begin
    if rising_edge(clock) then
      if video_read then
        if chr_inv='0' then
          video_pixel <= d_mem;
        else
          video_pixel <= not d_mem;
        end if;
      else
        for i in 7 downto 1 loop
          video_pixel(i) <= video_pixel(i-1);
        end loop;
        video_pixel(0) <= '0';
      end if;
    end if;
  end process;

  video <=     video_pixel(7) when mode_v_inv
      else not video_pixel(7);
end;

-- end ---------------------------------------------------
