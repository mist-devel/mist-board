----------------------------------------------------------
--  busses.vhd
--			Switching the busses
--			====================
--
--  04/29/97	Bodo Wenzel	Got from old top.vhd
--  11/17/97	Bodo Wenzel	Cut down to ordinary ZX81
--  12/02/97	Bodo Wenzel	ROM select
--  03/23/98	Bodo Wenzel	Paging of memory
--  01/28/99	Bodo Wenzel	New banking
----------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

-- the inputs and outputs --------------------------------

entity busses is
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
end;

-- the description of the logic --------------------------

architecture beh of busses is
begin
  process (a_cpu,n_mreq,n_m1,n_rd,n_rfsh,
           mode_romp,mode_rom0,mode_ram)
  begin
    n_romcs <= '1';
    n_ramcs <= '1';
    a_mem_h <= a_cpu(14 downto 13);

    if n_mreq='0' then
      case a_cpu(15 downto 13) is
      when "000" =>
        if n_rd='0' or n_rfsh='0' then
          if mode_rom0 then
            n_romcs <= '0';
          else
            n_ramcs <= '0';
          end if;
        end if;
        a_mem_h <= mode_romp;
      when "001" =>
        if mode_ram="01" then
          n_ramcs <= '0';
        end if;
      when "010" =>
        n_ramcs <= '0';
      when "011" =>
        n_ramcs <= '0';
      when "100" =>
        n_ramcs <= '0';
      when "101" =>
        if mode_ram(1)='1' then
          n_ramcs <= '0';
        end if;
      when "110" =>
        if n_m1='0' then
          n_ramcs <= '0';
        elsif mode_ram="11" then
          n_ramcs <= '0';
        end if;
      when "111" =>
        if n_m1='0' then
          n_ramcs <= '0';
        elsif mode_ram="11" then
          n_ramcs <= '0';
        end if;
      when others =>
        null;
      end case;
    end if;
  end process;

  a_mem_l <= video_addr         when video_mem
        else a_cpu(8 downto 0);

  d_cpu_o <= (others => '0') when fake_cpu
        else d_kbd           when d_kbd_enable
        else (others => '1') when n_m1='0' and n_iorq='0'
        else d_mem_i;

  oe_cpu <= n_rd='0' or n_m1='0';

  oe_mem <= n_wr='0';
end;

-- end ---------------------------------------------------
