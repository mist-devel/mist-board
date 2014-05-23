----------------------------------------------------------
--  lcd97.vhd
--			LCD logic of ZX97
--			=================
--
--  12/03/97	Bodo Wenzel	Creation
--  03/20/98	Bodo Wenzel	Enhanced clocked processes
--  02/08/99	Bodo Wenzel	Reduce needed logic
----------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

-- the inputs and outputs --------------------------------

entity lcd97 is
  port (clock:  in  std_ulogic;
        n_sync: in  std_ulogic;
        video:  in  std_ulogic;
        d_lcd:  out std_ulogic_vector(3 downto 0);
        s:      out std_ulogic;
        cp1:    out std_ulogic;
        cp2:    out std_ulogic);
end;

-- the description of the logic --------------------------

architecture beh of lcd97 is
  constant LINE_VSYNC:   natural := 64;
  constant LINE_PRE:     natural := 48;
  constant LINE_DISPLAY: natural := 80;
  constant LINE_MAX:     natural := 127;
  constant HSYNC_PRE:    natural := 24;

  type LINE_STATE is (SYNC,PRE,DISPLAY,POST);

  signal state:     LINE_STATE;
  signal line_cnt:  natural range 0 to LINE_MAX;
  signal vsync:     boolean;
  signal sync_1:    boolean;
  signal hsync_cnt: natural range 0 to HSYNC_PRE;
  signal hsync_1:   boolean;
  signal pixel:     std_ulogic_vector(4 downto 0);
begin
  process (clock)
  begin
    if rising_edge(clock) then
      case state is
      when SYNC =>
        if n_sync='1' then
          state <= PRE;
          line_cnt <= 0;
        elsif not vsync then
          line_cnt <= line_cnt+1;
        end if;
        vsync <= line_cnt>=LINE_VSYNC;

      when PRE =>
        if n_sync='0' then
          state <= SYNC;
          line_cnt <= 0;
        elsif line_cnt>=LINE_PRE then
          state <= DISPLAY;
          line_cnt <= 0;
        else
          line_cnt <= line_cnt+1;
        end if;

      when DISPLAY =>
        if n_sync='0' then
          state <= SYNC;
          line_cnt <= 0;
        elsif line_cnt>=LINE_DISPLAY then
          state <= POST;
        elsif pixel(4)='0' then
          line_cnt <= line_cnt+1;
        end if;
      when others =>
        if n_sync='0' then
          state <= SYNC;
          line_cnt <= 0;
        end if;
      end case;
    end if;
  end process;

  cp1 <= not n_sync;

  process (vsync,clock)
  begin
    if vsync then
      s         <= '0';
      hsync_cnt <= 0;
      sync_1    <= FALSE;
    elsif rising_edge(clock) then
      if not sync_1 and state=SYNC then
        if (not hsync_1) and hsync_cnt>=HSYNC_PRE then
          s <= '1';
        else
          s <= '0';
        end if;

        if hsync_cnt<HSYNC_PRE then
          hsync_cnt <= hsync_cnt+1;
        end if;

        hsync_1 <= hsync_cnt>=HSYNC_PRE;
      end if;

      sync_1 <= state=SYNC;
    end if;
  end process;

  process (clock)
  begin
    if rising_edge(clock) then
      if pixel(4)='0' or state/=DISPLAY then
        pixel <= "1110" & video;
      else
        pixel <= pixel(3 downto 0) & video;
      end if;
    end if;
  end process;

  d_lcd <= pixel(3 downto 0);

  process (clock)
  begin
    if falling_edge(clock) then
      cp2 <= pixel(4);
    end if;
  end process;
end;

-- end ---------------------------------------------------
