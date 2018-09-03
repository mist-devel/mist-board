library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

--use work.platform_pkg.all;
--use work.project_pkg.all;

--
-- Model 1541B
--

entity c1541_logic is
  generic
  (
    DEVICE_SELECT   : std_logic_vector(1 downto 0)
  );
  port
  (
    clk_32M         : in std_logic;
    reset           : in std_logic;

    -- serial bus
    sb_data_oe      : out std_logic;
    sb_data_in      : in std_logic;
    sb_clk_oe       : out std_logic;
    sb_clk_in       : in std_logic;
    sb_atn_oe       : out std_logic;
    sb_atn_in       : in std_logic;
    
    -- drive-side interface
    ds              : in std_logic_vector(1 downto 0);    -- device select
    di              : in std_logic_vector(7 downto 0);    -- disk read data
    do              : out std_logic_vector(7 downto 0);   -- disk data to write
    mode            : out std_logic;                      -- read/write
    stp             : out std_logic_vector(1 downto 0);   -- stepper motor control
    mtr             : out std_logic;                      -- stepper motor on/off
    freq            : out std_logic_vector(1 downto 0);   -- motor frequency
    sync_n          : in std_logic;                       -- reading SYNC bytes
    byte_n          : in std_logic;                       -- byte ready
    wps_n           : in std_logic;                       -- write-protect sense
    tr00_sense_n    : in std_logic;                       -- track 0 sense (unused?)
    act             : out std_logic;                       -- activity LED

    c1541rom_clk    : in std_logic;
    c1541rom_addr   : in std_logic_vector(13 downto 0);
    c1541rom_data   : in std_logic_vector(7 downto 0);
    c1541rom_wr     : in std_logic;
		
		dbg_adr_fetch : out std_logic_vector(15 downto 0);  -- dbg DAR
		dbg_cpu_irq   : out std_logic                       -- dbg DAR
  );
end c1541_logic;

architecture SYN of c1541_logic is

  -- clocks, reset
  signal reset_n        : std_logic;
  signal p2_h_r         : std_logic;
  signal p2_h_f         : std_logic;
  signal clk_1M_pulse   : std_logic;
    
  -- cpu signals  
  signal cpu_a          : std_logic_vector(23 downto 0);
  signal cpu_di         : std_logic_vector(7 downto 0);
  signal cpu_do         : std_logic_vector(7 downto 0);
  signal cpu_rw_n       : std_logic;
  signal cpu_irq_n      : std_logic;
  signal cpu_so_n       : std_logic;
  signal cpu_sync       : std_logic;  -- DAR

  -- rom signals
  signal rom_cs         : std_logic;
  signal rom_do         : std_logic_vector(cpu_di'range); 

  -- ram signals
  signal ram_cs         : std_logic;
  signal ram_wr         : std_logic;
  signal ram_do         : std_logic_vector(cpu_di'range);
  
  -- UC1 (VIA6522) signals
  signal uc1_do         : std_logic_vector(7 downto 0);
  signal uc1_do_oe_n    : std_logic;
  signal uc1_cs1        : std_logic;
  signal uc1_cs2_n      : std_logic;
  signal uc1_irq_n      : std_logic;
  signal uc1_ca1_i      : std_logic;
  signal uc1_pa_i       : std_logic_vector(7 downto 0);
  signal uc1_pb_i       : std_logic_vector(7 downto 0);
  signal uc1_pb_o       : std_logic_vector(7 downto 0);
  signal uc1_pb_oe_n    : std_logic_vector(7 downto 0);
    
  -- UC3 (VIA6522) signals
  signal uc3_do         : std_logic_vector(7 downto 0);
  signal uc3_do_oe_n    : std_logic;
  signal uc3_cs1        : std_logic;
  signal uc3_cs2_n      : std_logic;
  signal uc3_irq_n      : std_logic;
  signal uc3_ca1_i      : std_logic;
  signal uc3_ca2_o      : std_logic;
  signal uc3_ca2_oe_n   : std_logic;
  signal uc3_pa_i       : std_logic_vector(7 downto 0);
  signal uc3_pa_o       : std_logic_vector(7 downto 0);
  signal uc3_cb2_o      : std_logic;
  signal uc3_cb2_oe_n   : std_logic;
  signal uc3_pa_oe_n    : std_logic_vector(7 downto 0);
  signal uc3_pb_i       : std_logic_vector(7 downto 0);
  signal uc3_pb_o       : std_logic_vector(7 downto 0);
  signal uc3_pb_oe_n    : std_logic_vector(7 downto 0);

  -- internal signals
  signal atna           : std_logic; -- ATN ACK - input gate array
  signal atn            : std_logic; -- attention
  signal soe            : std_logic; -- set overflow enable
  
  signal uc1_pb_oe      : std_logic_vector(7 downto 0);
  signal uc1_irq        : std_logic;
  signal uc3_irq        : std_logic;
  signal uc3_ca2_oe     : std_logic;
  signal uc3_cb2_oe     : std_logic;
  signal uc3_pa_oe      : std_logic_vector(7 downto 0);
  signal uc3_pb_oe      : std_logic_vector(7 downto 0);

begin

  reset_n <= not reset;
  
  process (clk_32M, reset)
    variable count  : std_logic_vector(4 downto 0) := (others => '0');
  begin
    if rising_edge(clk_32M) then
        count := std_logic_vector(unsigned(count) + 1);
    end if;

    if count = "10000" then clk_1M_pulse <= '1'; else clk_1M_pulse <='0' ; end if;
    if count = "00000" then p2_h_r <= '1'; else p2_h_r <='0' ; end if;
    if count = "10000" then p2_h_f <= '1'; else p2_h_f <='0' ; end if;
  end process;

  -- decode logic
  -- RAM $0000-$07FF (2KB)
  ram_cs <= '1' when STD_MATCH(cpu_a(15 downto 0), "00000-----------") else '0';
  -- UC1 (VIA6522) $1800-$180F
  uc1_cs2_n <= '0' when STD_MATCH(cpu_a(15 downto 0), "000110000000----") else '1';
  -- UC3 (VIA6522) $1C00-$1C0F
  uc3_cs2_n <= '0' when STD_MATCH(cpu_a(15 downto 0), "000111000000----") else '1';
  -- ROM $C000-$FFFF (16KB)
  rom_cs <= '1' when STD_MATCH(cpu_a(15 downto 0), "11--------------") else '0';

  -- qualified write signals
  ram_wr <= '1' when ram_cs = '1' and cpu_rw_n = '0' else '0';

  --
  -- hook up UC1 ports
  --
  
  uc1_cs1 <= '1';
  --uc1_cs2_n: see decode logic above
  -- CA1
  uc1_ca1_i <= not sb_atn_in;
  -- PA
  uc1_pa_i(0) <= tr00_sense_n;
  uc1_pa_i(7 downto 1) <= (others => '0');  -- NC
  -- PB
  uc1_pb_i(0) <=  '1' when sb_data_in = '0' else
                  '1' when (uc1_pb_o(1) = '1' and uc1_pb_oe_n(1) = '0') else  -- DAR comment : external OR wired
                  '1' when atn = '1' else                                     -- DAR comment : external OR wired 
                  '0';
  sb_data_oe <=   '1' when (uc1_pb_o(1) = '1' and uc1_pb_oe_n(1) = '0') else
                  '1' when atn = '1' else
                  '0';
  uc1_pb_i(2) <=  '1' when sb_clk_in = '0' else
                  '1' when (uc1_pb_o(3) = '1' and uc1_pb_oe_n(3) = '0') else  -- DAR comment : external OR wired
                  '0';
  sb_clk_oe <=    '1' when (uc1_pb_o(3) = '1' and uc1_pb_oe_n(3) = '0') else '0';
		
  atna <= uc1_pb_o(4); -- when uc1_pc_oe = '1'
  uc1_pb_i(6 downto 5) <= DEVICE_SELECT xor ds;     -- allows override
  uc1_pb_i(7) <= not sb_atn_in;

  --
  -- hook up UC3 ports
  --
  
  uc3_cs1 <= '1';
  --uc3_cs2_n: see decode logic above
  -- CA1
  uc3_ca1_i <= cpu_so_n; -- byte ready gated with soe
  -- CA2
  soe <= uc3_ca2_o or uc3_ca2_oe_n;
  -- PA
  uc3_pa_i <= di;
  do <= uc3_pa_o or uc3_pa_oe_n;
  -- CB2
  mode <= uc3_cb2_o or uc3_cb2_oe_n;
  -- PB
  stp(1) <= uc3_pb_o(0) or uc3_pb_oe_n(0);
  stp(0) <= uc3_pb_o(1) or uc3_pb_oe_n(1);
  mtr <= uc3_pb_o(2) or uc3_pb_oe_n(2);
  act <= uc3_pb_o(3) or uc3_pb_oe_n(3);
  freq <= uc3_pb_o(6 downto 5) or uc3_pb_oe_n(6 downto 5);
  uc3_pb_i <= sync_n & "11" & wps_n & "1111";
  
  --
  -- CPU connections
  --
  cpu_di <= cpu_do when cpu_rw_n = '0' else
            rom_do when rom_cs = '1' else
            ram_do when ram_cs = '1' else
            uc1_do when (uc1_cs1 = '1' and uc1_cs2_n = '0') else
            uc3_do when (uc3_cs1 = '1' and uc3_cs2_n = '0') else
            (others => '1');
  cpu_irq_n <= uc1_irq_n and uc3_irq_n;
  cpu_so_n <= byte_n or not soe;
  
  -- internal connections
  atn <= atna xor (not sb_atn_in);
  
  -- external connections
  -- ATN never driven by the 1541
  sb_atn_oe <= '0';

  cpu_inst : entity work.T65
    port map
    (
      Mode        => "00",  -- 6502
      Res_n       => reset_n,
      Enable      => clk_1M_pulse,
      Clk         => clk_32M,
      Rdy         => '1',
      Abort_n     => '1',
      IRQ_n       => cpu_irq_n,
      NMI_n       => '1',
      SO_n        => cpu_so_n,
      R_W_n       => cpu_rw_n,
      Sync        => cpu_sync, -- open -- DAR
      EF          => open,
      MF          => open,
      XF          => open,
      ML_n        => open,
      VP_n        => open,
      VDA         => open,
      VPA         => open,
      A           => cpu_a,
      DI          => cpu_di,
      DO          => cpu_do
    );

  rom_inst : entity work.gen_rom
    generic map
    (
--  	 init_file   => "../roms/JiffyDOS_C1541.hex",               -- DAR tested OK
--	 init_file   => "../roms/25196802.hex",             
--	 init_file   => "../roms/25196801.hex",             
      INIT_FILE   => "../roms/325302-1_901229-03.hex",   
--     init_file   => "../roms/1541_c000_01_and_e000_06aa.hex",   -- DAR tested OK


      DATA_WIDTH  => 8,
      ADDR_WIDTH   => 14
    )
    port map
    (
      rdclock     => clk_32M,
      rdaddress   => cpu_a(13 downto 0),
      q           => rom_do,

		wrclock     => c1541rom_clk,
		wraddress   => c1541rom_addr,
		wren        => c1541rom_wr,
		data        => c1541rom_data
    );

  ram_inst : entity work.spram
    generic map
    (
      numwords_a  => 2048,
      widthad_a   => 11
    )
    port map
    (
      clock     => clk_32M,
      address   => cpu_a(10 downto 0),
      wren      => ram_wr,
      data      => cpu_do,
      q         => ram_do
    );

  uc1_pb_oe_n <= not uc1_pb_oe;
  uc1_irq_n   <= not uc1_irq;

  uc1_via6522_inst : entity work.via6522
    port map
    (
      clock           => clk_32M,
      rising          => p2_h_r,
      falling         => p2_h_f,
      reset           => not reset_n,

      addr            => cpu_a(3 downto 0),
      wen             => not cpu_rw_n and not uc1_cs2_n,
      ren             => cpu_rw_n and not uc1_cs2_n,
      data_in         => cpu_do,
      data_out        => uc1_do,

      port_a_i        => uc1_pa_i,

      port_b_o        => uc1_pb_o,
      port_b_t        => uc1_pb_oe,
      port_b_i        => uc1_pb_i,

      ca1_i           => uc1_ca1_i,
      ca2_i           => '0',

      cb1_i           => '0',
      cb2_i           => '0',

      irq             => uc1_irq
    );

  uc3_irq_n    <= not uc3_irq;
  uc3_ca2_oe_n <= not uc3_ca2_oe;
  uc3_cb2_oe_n <= not uc3_cb2_oe;
  uc3_pa_oe_n  <= not uc3_pa_oe;
  uc3_pb_oe_n  <= not uc3_pb_oe;

  uc3_via6522_inst : entity work.via6522
    port map
    (
      clock           => clk_32M,
      rising          => p2_h_r,
      falling         => p2_h_f,
      reset           => not reset_n,

      addr            => cpu_a(3 downto 0),
      wen             => not cpu_rw_n and not uc3_cs2_n,
      ren             => cpu_rw_n and not uc3_cs2_n,
      data_in         => cpu_do,
      data_out        => uc3_do,

      port_a_o        => uc3_pa_o,
      port_a_t        => uc3_pa_oe,
      port_a_i        => uc3_pa_i,

      port_b_o        => uc3_pb_o,
      port_b_t        => uc3_pb_oe,
      port_b_i        => uc3_pb_i,

      ca1_i           => uc3_ca1_i,

      ca2_o           => uc3_ca2_o,
      ca2_i           => '0',
      ca2_t           => uc3_ca2_oe,

      cb1_i           => '0',

      cb2_o           => uc3_cb2_o,
      cb2_i           => '0',
      cb2_t           => uc3_cb2_oe,

      irq             => uc3_irq
    );
end SYN;
