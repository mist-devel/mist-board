----------------------------------------------------------
--  zx01.vhd
--		ZX01 top level
--		==============
--
--  12/15/01	Daniel Wallner : Rewrite of Bodo Wenzels zx97 to SOC
--  02/23/02	Daniel Wallner : Changed to the synchronous t80s
--  03/04/02	Daniel Wallner : Connected INT_n, synchronized reset and added tape_out
--  08/14/02	Daniel Wallner : Changed for xilinx XST
----------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- the pads ----------------------------------------------

entity zx01 is
  port (n_reset:  in    std_ulogic;
        clock:    in    std_ulogic;
        kbd_clk:  in    std_ulogic;
        kbd_data: in    std_ulogic;
        v_inv:    in    std_ulogic;
        usa_uk:   in   	std_ulogic;
        video:    out   std_ulogic;
        tape_in:  in    std_ulogic;
        tape_out: out   std_ulogic;
        d_lcd:    out   std_ulogic_vector(3 downto 0);
        s:        out   std_ulogic;
        cp1:      out   std_ulogic;
        cp2:      out   std_ulogic);
end;

-- the top level ------------------------------

architecture rtl of zx01 is

  component PS2_MatrixEncoder
  port (Clk:      in std_logic;
        Reset_n:  in std_logic;
        Tick1us:  in std_logic;
        PS2_Clk:  in std_logic;
        PS2_Data: in std_logic;
        Key_Addr: in std_logic_vector(7 downto 0);
        Key_Data: out std_logic_vector(4 downto 0));
  end component;

  component T80s
  generic(
        Mode : integer := 0);
  port (RESET_n		: in std_logic;
        CLK_n		: in std_logic;
        WAIT_n		: in std_logic;
        INT_n		: in std_logic;
        NMI_n		: in std_logic;
        BUSRQ_n		: in std_logic;
        M1_n		: out std_logic;
        MREQ_n		: out std_logic;
        IORQ_n		: out std_logic;
        RD_n		: out std_logic;
        WR_n		: out std_logic;
        RFSH_n		: out std_logic;
        HALT_n		: out std_logic;
        BUSAK_n		: out std_logic;
        A			: out std_logic_vector(15 downto 0);
        DI			: in std_logic_vector(7 downto 0);
        DO			: out std_logic_vector(7 downto 0));
  end component;

  component SSRAM
  generic(
        AddrWidth: integer := 16;
        DataWidth: integer := 8);
  port (Clk:     in std_logic;
        CE_n:    in std_logic;
        WE_n:    in std_logic;
        A:       in std_logic_vector(AddrWidth - 1 downto 0);
        DIn:     in std_logic_vector(DataWidth - 1 downto 0);
        DOut:    out std_logic_vector(DataWidth - 1 downto 0));
  end component;

  component ROM81
  port (clock: in std_logic;
        address:   in std_logic_vector(12 downto 0);
        q:   out std_logic_vector(7 downto 0));
  end component;

  component top
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
  end component;

  signal a_mem_h:   std_ulogic_vector(14 downto 13);
  signal a_mem_l:   std_ulogic_vector(8 downto 0);
  signal a_mem:     std_logic_vector(14 downto 0);
  signal d_ram:     std_logic_vector(7 downto 0);
  signal d_rom:     std_logic_vector(7 downto 0);
  signal n_romcs:   std_ulogic;
  signal n_ramcs:   std_ulogic;
  signal a_cpu:     std_logic_vector(15 downto 0);
  signal n_m1:      std_ulogic;
  signal n_mreq:    std_ulogic;
  signal n_iorq:    std_ulogic;
  signal n_wr:      std_ulogic;
  signal n_rd:      std_ulogic;
  signal n_rfsh:    std_ulogic;
  signal n_nmi:     std_ulogic;
  signal n_halt:    std_ulogic;
  signal n_wait:    std_ulogic;
  signal clock_2:   std_ulogic;
  signal i_phi:     std_ulogic;
  signal i_n_modes: std_ulogic;
  signal d_mem_i:   std_ulogic_vector(7 downto 0);
  signal d_cpu_i:   std_logic_vector(7 downto 0);
  signal d_cpu_o:   std_ulogic_vector(7 downto 0);
  signal Tick1us:   std_logic;
  signal kbd_col:   std_logic_vector(4 downto 0);
  signal kbd_mode:  std_logic_vector(4 downto 0);
  signal i_kbd_col: std_logic_vector(4 downto 0);
  signal i_video:   std_ulogic;
  signal i_n_sync:  std_ulogic;
  signal i_n_reset: std_ulogic;
  signal s_n_reset: std_ulogic;

begin

  process (n_reset, i_phi)
  begin
    if n_reset = '0' then
      s_n_reset <= '0';
    elsif i_phi'event and i_phi = '1' then
      s_n_reset <= '1';
    end if;
  end process;

  process (s_n_reset, i_phi)
    variable cnt : unsigned(1 downto 0);
  begin
    if s_n_reset = '0' then
      cnt := "00";
      Tick1us <= '0';
    elsif i_phi'event and i_phi = '1' then
      if cnt = "00" then
        cnt := "10";
        Tick1us <= '1';
      else
        cnt := cnt - 1;
        Tick1us <= '0';
      end if;
    end if;
  end process;

  c_PS2_MatrixEncoder: PS2_MatrixEncoder
    port map (Clk => i_phi,
              Reset_n => i_n_reset,
              Tick1us => Tick1us,
              PS2_Clk => kbd_clk,
              PS2_Data => kbd_data,
              Key_Addr => a_cpu(15 downto 8),
              Key_Data => kbd_col);

  i_kbd_col <= kbd_mode when i_n_modes = '0' else kbd_col;
  kbd_mode(3 downto 2) <= "00"; -- PAGE
  kbd_mode(4) <= v_inv;
  kbd_mode(1 downto 0) <= "00"; -- RAM

  c_Z80: T80s
    generic map (Mode => 0)
    port map (M1_n => n_m1,
              MREQ_n => n_mreq,
              IORQ_n => n_iorq,
              RD_n => n_rd,
              WR_n => n_wr,
              RFSH_n => n_rfsh,
              HALT_n => n_halt,
              WAIT_n => n_wait,
              INT_n => a_cpu(6),
              NMI_n => n_nmi,
              RESET_n => s_n_reset,
              BUSRQ_n => '1',
              BUSAK_n => open,
              CLK_n => i_phi,
              A => a_cpu,
              DI => std_logic_vector(d_cpu_o),
              DO => d_cpu_i);

  c_SSRAM: SSRAM
    generic map (AddrWidth => 11)
    port map (Clk => i_phi,
              CE_n => n_ramcs,
              WE_n => n_wr,
              A => a_mem(10 downto 0),
              DIn => d_cpu_i,
              DOut => d_ram);

  c_ROM81: ROM81
    port map (clock => i_phi,
              address => a_mem(12 downto 0),
              q => d_rom);

  c_top: top
    generic map (true)
    port map (clock,clock_2,i_phi,
              i_n_reset,i_n_modes,
              a_mem_h,a_mem_l,d_mem_i,
              std_ulogic_vector(a_cpu),std_ulogic_vector(d_cpu_i),d_cpu_o,
              open,open,
              n_m1,n_mreq,n_iorq,n_wr,n_rd,n_rfsh,
              n_nmi,n_halt,n_wait,n_romcs,n_ramcs,
              std_ulogic_vector(i_kbd_col),usa_uk,
              i_video,i_n_sync,tape_in,
              d_lcd,s,cp1,cp2);

  i_phi <= clock_2;

  a_mem(14 downto 13) <= std_logic_vector(a_mem_h);
  a_mem(12 downto 9) <= a_cpu(12 downto 9);
  a_mem(8 downto 0) <= std_logic_vector(a_mem_l);
  d_mem_i <= std_ulogic_vector(d_rom) when n_ramcs = '1'
        else std_ulogic_vector(d_ram);

  tape_out <= i_n_sync;
  video <= i_video;
--  video <= '0' when i_n_sync='0'
--     else 'Z' when i_video='0'
--     else '1';
end;

-- end ---------------------------------------------------
