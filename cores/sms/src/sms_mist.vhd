library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sms_mist is
	port (
  
    -- Clocks
    
    CLOCK_27    : in std_logic_vector(1 downto 0); -- 27 MHz

    -- SDRAM
    SDRAM_nCS : out std_logic;                     -- Chip Select
    SDRAM_DQ : inout std_logic_vector(15 downto 0); -- SDRAM Data bus 16 Bits
    SDRAM_A : out std_logic_vector(12 downto 0);  -- SDRAM Address bus 13 Bits
    SDRAM_DQMH : out std_logic; -- SDRAM High Data Mask
    SDRAM_DQML : out std_logic; -- SDRAM Low-byte Data Mask
    SDRAM_nWE : out std_logic;  -- SDRAM Write Enable
    SDRAM_nCAS : out std_logic; -- SDRAM Column Address Strobe
    SDRAM_nRAS : out std_logic; -- SDRAM Row Address Strobe
    SDRAM_BA : out std_logic_vector(1 downto 0); -- SDRAM Bank Address
    SDRAM_CLK : out std_logic; -- SDRAM Clock
    SDRAM_CKE: out std_logic; -- SDRAM Clock Enable
    
    -- SPI
    SPI_SCK : in std_logic;
    SPI_DI : in std_logic;
    SPI_DO : out std_logic;
    SPI_SS2 : in std_logic;
    SPI_SS3 : in std_logic;
    CONF_DATA0 : in std_logic;

    -- VGA output
    VGA_HS,                                             -- H_SYNC
    VGA_VS : out std_logic;                             -- V_SYNC
    VGA_R,                                              -- Red[5:0]
    VGA_G,                                              -- Green[5:0]
    VGA_B : out std_logic_vector(5 downto 0);           -- Blue[5:0]
    
    -- Audio
    AUDIO_L,
    AUDIO_R : out std_logic
    

    );
end sms_mist;

architecture Behavioral of sms_mist is
	
	component vga_video is
	port (
		clk16:			in  std_logic;
		pal:				in  std_logic;
		x: 				out unsigned(8 downto 0);
		y:					out unsigned(7 downto 0);
		color:			in  std_logic_vector(5 downto 0);
		hsync:			out std_logic;
		vsync:			out std_logic;
		red:				out std_logic_vector(1 downto 0);
		green:			out std_logic_vector(1 downto 0);
		blue:				out std_logic_vector(1 downto 0));
	end component;
  
  component sdram is
      port( sd_data : inout std_logic_vector(15 downto 0);
            sd_addr : out std_logic_vector(12 downto 0);
            sd_dqm : out std_logic_vector(1 downto 0);
            sd_ba : out std_logic_vector(1 downto 0);
            sd_cs : out std_logic;
            sd_we : out std_logic;
            sd_ras : out std_logic;
            sd_cas : out std_logic;
            init : in std_logic;
            clk : in std_logic;
            clkref : in std_logic;
            din : in std_logic_vector(7 downto 0);
            dout : out std_logic_vector(7 downto 0);
            addr : in std_logic_vector(24 downto 0);
            oe : in std_logic;
            we : in std_logic
      );
  end component;
  
  constant CONF_STR : string := "SMS;SMS;O1,Video,NTSC,PAL;O2,Joysticks,Normal,Swapped;T3,Pause;T4,Reset";

  function to_slv(s: string) return std_logic_vector is
    constant ss: string(1 to s'length) := s;
    variable rval: std_logic_vector(1 to 8 * s'length);
    variable p: integer;
    variable c: integer;
  
  begin
    for i in ss'range loop
      p := 8 * i;
      c := character'pos(ss(i));
      rval(p - 7 to p) := std_logic_vector(to_unsigned(c,8));
    end loop;
    return rval;

  end function;
  
  component user_io
      generic ( STRLEN : integer := 0 );
      port ( SPI_CLK, SPI_SS_IO, SPI_MOSI :in std_logic;
           SPI_MISO : out std_logic;
           conf_str : in std_logic_vector(8*STRLEN-1 downto 0);
           JOY0 : out std_logic_vector(5 downto 0);
           JOY1 : out std_logic_vector(5 downto 0);
           status: out std_logic_vector(7 downto 0);
           SWITCHES : out std_logic_vector(1 downto 0);
           BUTTONS : out std_logic_vector(1 downto 0);
          -- clk : in std_logic;
           ps2_clk : out std_logic;
           ps2_data : out std_logic
      );
  end component user_io;
  
  component data_io is
      port(sck: in std_logic;
           ss: in std_logic;
           sdi: in std_logic;
           downloading: out std_logic;
           size: out std_logic_vector(24 downto 0);
           clk: in std_logic;
           wr: out std_logic;
           a: out std_logic_vector(24 downto 0);
           d: out std_logic_vector(7 downto 0)
           );
  end component data_io;
  
  component osd
    port ( pclk, sck, ss, sdi, hs_in, vs_in : in std_logic;
           red_in, blue_in, green_in : in std_logic_vector(5 downto 0);
           red_out, blue_out, green_out : out std_logic_vector(5 downto 0);
           hs_out, vs_out : out std_logic
         );
  end component osd;
	
  signal clk_64M:     std_logic;
	signal clk_cpu:			std_logic;
	signal clk16:				std_logic;
  signal clk_div : unsigned(1 downto 0);
	
	signal x:					unsigned(8 downto 0);
	signal y:					unsigned(7 downto 0);
	signal color:				std_logic_vector(5 downto 0);	
	signal audio:				std_logic;
  
  signal pll_locked:  std_logic;
  signal ram_oe_n:	STD_LOGIC;
  signal ram_a:		STD_LOGIC_VECTOR(21 downto 0);
  signal sys_a:		STD_LOGIC_VECTOR(21 downto 0);
  signal ram_din: STD_LOGIC_VECTOR(7 downto 0);
  signal ram_dout: STD_LOGIC_VECTOR(7 downto 0);
  signal ram_we: std_logic;
  signal ram_oe: std_logic;
  
  signal sdram_dqm:  std_logic_vector(1 downto 0);
  
  signal switches : std_logic_vector(1 downto 0);
  signal buttons : std_logic_vector(1 downto 0);
  signal joy0 : std_logic_vector(5 downto 0);
  signal joy1 : std_logic_vector(5 downto 0);
  signal joya : std_logic_vector(5 downto 0);
  signal joyb : std_logic_vector(5 downto 0);
  signal status : std_logic_vector(7 downto 0);
  signal j1_tr : std_logic;
  signal j2_tr : std_logic;
  
  signal r : std_logic_vector(1 downto 0);
  signal g : std_logic_vector(1 downto 0);
  signal b : std_logic_vector(1 downto 0);
  signal vs: std_logic;
  signal hs: std_logic;
  
  signal ioctl_wr : std_logic;
  signal ioctl_addr : std_logic_vector(24 downto 0);
  signal ioctl_data : std_logic_vector(7 downto 0);
  signal ioctl_ram_addr : std_logic_vector(24 downto 0);
  signal ioctl_ram_data : std_logic_vector(7 downto 0);
  signal ioctl_ram_wr : std_logic := '0';
  signal downl : std_logic := '0';
  signal size : std_logic_vector(24 downto 0) := (others=>'0');
  signal reset_n : std_logic := '1';
  signal dbr : std_logic := '0';
  
begin

	clock_inst: work.pll
	port map (
		inclk0	=> CLOCK_27(0),
		c0		  => clk_64M,
		c1		  => SDRAM_CLK,
    locked  => pll_locked);
    
   -- generate 16MHz video clock from 64MHz main clock by dividing it by 4
  process(clk_64M)
  begin
    if rising_edge(clk_64M) then
      clk_div <= clk_div + 1;
    end if;
     
    clk16 <= clk_div(1);
  end process;
  
  -- generate 8MHz system clock from 16MHz video clock
  process(clk16)
  begin
    if rising_edge(clk16) then
      clk_cpu <= not clk_cpu;
    end if;
  end process;
	
	video_inst: vga_video
	port map (
		clk16			=> clk16,
		pal			=> status(1),
		x	 			=> x,
		y				=> y,
		color			=> color,
		
		hsync			=> hs,
		vsync			=> vs,
		red			=> r,
		green			=> g,
		blue			=> b
	);
  
  osd_inst : osd
    port map (
      pclk => clk16,
      sdi => SPI_DI,
      sck => SPI_SCK,
      ss => SPI_SS3,
      red_in => r & r & r,
      green_in => g & g & g,
      blue_in => b & b & b,
      hs_in => hs,
      vs_in => vs,
      red_out => VGA_R,
      green_out => VGA_G,
      blue_out => VGA_B,
      hs_out => VGA_HS,
      vs_out => VGA_VS
    );
  
  -- sdram interface
  SDRAM_CKE <= '1';
  SDRAM_DQMH <= sdram_dqm(1);
	SDRAM_DQML <= sdram_dqm(0);
  
  sdram_inst : sdram
    port map( sd_data => SDRAM_DQ,
              sd_addr => SDRAM_A,
              sd_dqm => sdram_dqm,
              sd_cs => SDRAM_nCS,
              sd_ba => SDRAM_BA,
              sd_we => SDRAM_nWE,
              sd_ras => SDRAM_nRAS,
              sd_cas => SDRAM_nCAS,
              clk => clk_64M,
              clkref => clk_cpu,
              init => not pll_locked,
              din => ram_din,
              addr => "000" & ram_a,
              we => ram_we,
              oe => ram_oe,
              dout => ram_dout
    );
    
  ram_a   <= ioctl_ram_addr(21 downto 0) when downl = '1' else sys_a;
  ram_din <= ioctl_ram_data;
  ram_we  <= '1' when ioctl_ram_wr = '1' else '0';
  ram_oe  <= '0' when downl = '1' else not ram_oe_n;
    
  data_io_inst: data_io
    port map(SPI_SCK, SPI_SS2, SPI_DI, downl, size, clk_cpu, ioctl_wr, ioctl_addr, ioctl_data);
    
  process(clk_cpu)
  begin
    if falling_edge(clk_cpu) then
      if downl='1' then
        reset_n <= '0';
        dbr <= '1';
      else
        reset_n <= '1';
      end if;
      if ioctl_wr ='1' then
        -- io controller sent a new byte.
        ioctl_ram_wr <= '1';
        ioctl_ram_addr <= ioctl_addr;
        ioctl_ram_data <= ioctl_data;
      else
        ioctl_ram_wr <= '0';
      end if;
    end if;
  end process;
    
  user_io_d : user_io
    generic map (STRLEN => CONF_STR'length)
    
    port map (
      SPI_CLK => SPI_SCK,
      SPI_SS_IO => CONF_DATA0,
      SPI_MISO => SPI_DO,
      SPI_MOSI => SPI_DI,
      conf_str => to_slv(CONF_STR),
      status => status,
      JOY0 => joy0,
      JOY1 => joy1,
      SWITCHES => switches,
      BUTTONS => buttons,
     -- clk => open,
      ps2_clk => open,
      ps2_data => open
    );

	-- joysticks can be swapped
	joya <= joy1 when status(2)='0' else joy0;
	joyb <= joy0 when status(2)='0' else joy1;
	 
	system_inst: work.system
	port map (
		clk_cpu		=> clk_cpu,
		clk_vdp		=> clk16,
		
		-- ram interface used  for cartridge emulation
		ram_oe_n		=> ram_oe_n,
		ram_a			=> sys_a,
		ram_do    	=> ram_dout,

		-- buttons and joysticks
		j1_up			=> not joya(3),
		j1_down		=> not joya(2),
		j1_left		=> not joya(1),
		j1_right		=> not joya(0),
		j1_tl			=> not joya(4),
		j1_tr			=> not joya(5),
		j2_up			=> not joyb(3),
		j2_down		=> not joyb(2),
		j2_left		=> not joyb(1),
		j2_right		=> not joyb(0),
		j2_tl			=> not joyb(4),
		j2_tr			=> not joyb(5),
		reset			=> not buttons(1) and not status(4) and not status(0) and pll_locked and reset_n,
		pause			=> not status(3),

		-- video
		x				=> x,
		y				=> y,
		color			=> color,
		audio			=> audio,

		dbr       	=> dbr
	);
	
	AUDIO_L <= audio;
	AUDIO_R <= audio;
	
end Behavioral;

