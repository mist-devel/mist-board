library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

library work;
use work.pace_pkg.all;
use work.sdram_pkg.all;
use work.video_controller_pkg.all;
use work.maple_pkg.all;
use work.gamecube_pkg.all;
use work.project_pkg.all;
use work.platform_pkg.all;
use work.target_pkg.all;

entity target_top is
  port
    (
      --////////////////////	Clock Input	 	////////////////////	 
      CLOCK_27      : in std_logic_vector(1 downto 0);                       --	50 MHz
      --////////////////////////	SPI	////////////////////////
      SPI_SCK : in std_logic;
      SPI_DI : in std_logic;
      SPI_DO : out std_logic;
      CONF_DATA0 : in std_logic;
      --////////////////////////	Speaker		////////////////////////
      AUDIO_L           : out std_logic;
      AUDIO_R           : out std_logic;
      --////////////////////	VGA		////////////////////////////
      VGA_VS        : out std_logic;                        --	VGA H_SYNC
      VGA_HS        : out std_logic;                        --	VGA V_SYNC
      VGA_R         : out std_logic_vector(5 downto 0);     --	VGA Red[3:0]
      VGA_G         : out std_logic_vector(5 downto 0);     --	VGA Green[3:0]
      VGA_B         : out std_logic_vector(5 downto 0);      --	VGA Blue[3:0]

      SDRAM_nCS     : out std_logic

      -- DATA0	    : in std_logic;                          --	DATA0
  );    
  
end target_top;

architecture SYN of target_top is

  component user_io
    port ( SPI_CLK, SPI_SS_IO, SPI_MOSI :in std_logic;
           SPI_MISO : out std_logic;
           JOY0 :     out std_logic_vector(5 downto 0);
           SWITCHES : out std_logic_vector(1 downto 0);
           BUTTONS : out std_logic_vector(1 downto 0);
           CORE_TYPE : in std_logic_vector(7 downto 0)
           );
   end component user_io;

  signal init       	: std_logic := '1';  
  signal clock_50       : std_logic;
  
  signal clkrst_i       : from_CLKRST_t;
  signal buttons_i      : from_BUTTONS_t;
  signal switches_i     : from_SWITCHES_t;
  signal leds_o         : to_LEDS_t;
  signal inputs_i       : from_INPUTS_t;
  signal flash_i        : from_FLASH_t;
  signal flash_o        : to_FLASH_t;
  signal sram_i			: from_SRAM_t;
  signal sram_o			: to_SRAM_t;	
  signal sdram_i        : from_SDRAM_t;
  signal sdram_o        : to_SDRAM_t;
  signal video_i        : from_VIDEO_t;
  signal video_o        : to_VIDEO_t;
  signal audio_i        : from_AUDIO_t;
  signal audio_o        : to_AUDIO_t;
  signal ser_i          : from_SERIAL_t;
  signal ser_o          : to_SERIAL_t;
  signal project_i      : from_PROJECT_IO_t;
  signal project_o      : to_PROJECT_IO_t;
  signal platform_i     : from_PLATFORM_IO_t;
  signal platform_o     : to_PLATFORM_IO_t;
  signal target_i       : from_TARGET_IO_t;
  signal target_o       : to_TARGET_IO_t;

  signal joystick       : std_logic_vector(5 downto 0);
  signal switches       : std_logic_vector(1 downto 0);
  signal buttons        : std_logic_vector(1 downto 0);
  
--//********************

begin

  SDRAM_nCS <= '1';   -- don't select SDRAM

-- // Need Clock 50Mhz to Clock 27Mhz

  BLK_CLOCKING : block
  begin
    clkrst_i.clk_ref <= CLOCK_27(0);
  
    GEN_PLL : if PACE_HAS_PLL generate
    
      pll_27_inst : entity work.pllclk_ez --entity work.pllclk_ez  --entity work.pll
        port map
        (
          inclk0  => CLOCK_27(0),
          c0      => clkrst_i.clk(0),  --30Mhz
          c1      => clkrst_i.clk(1),  --40Mhz
          c3      => clock_50,  --40Mhz
          c4      => clkrst_i.clk(2)   --18.46Mhz
        );

    end generate GEN_PLL;
    
  end block BLK_CLOCKING;
	
  -- FPGA STARTUP
	-- should extend power-on reset if registers init to '0'
	process (clock_50)
		variable count : std_logic_vector (11 downto 0) := (others => '0');
	begin
		if rising_edge(clock_50) then
			if count = X"FFF" then
				init <= '0';
			else
				count := count + 1;
				init <= '1';
			end if;
		end if;
	end process;

  clkrst_i.arst <= init;
  clkrst_i.arst_n <= not clkrst_i.arst;

  GEN_RESETS : for i in 0 to 3 generate

    process (clkrst_i.clk(i), clkrst_i.arst)
      variable rst_r : std_logic_vector(2 downto 0) := (others => '0');
    begin
      if clkrst_i.arst = '1' then
        rst_r := (others => '1');
      elsif rising_edge(clkrst_i.clk(i)) then
        rst_r := rst_r(rst_r'left-1 downto 0) & '0';
      end if;
      clkrst_i.rst(i) <= rst_r(rst_r'left);
    end process;

  end generate GEN_RESETS;

      -- inputs
      user_io_d : user_io
        port map
        (
          SPI_CLK => SPI_SCK,
          SPI_SS_IO => CONF_DATA0,
          SPI_MISO => SPI_DO,
          SPI_MOSI => SPI_DI,
          JOY0 => joystick,
          SWITCHES => switches,
          BUTTONS => buttons,
          CORE_TYPE => X"a2"            -- PACE core type
          );

       switches_i(0) <= switches(0);
       switches_i(1) <= switches(1);

       GEN_NO_JAMMA : if PACE_JAMMA = PACE_JAMMA_NONE generate
		inputs_i.jamma_n.coin(1) <= not buttons(0);
		inputs_i.jamma_n.p(1).start <= not buttons(1);
		inputs_i.jamma_n.p(1).up <= not joystick(3);
		inputs_i.jamma_n.p(1).down <= not joystick(2);
		inputs_i.jamma_n.p(1).left <= not joystick(1);
		inputs_i.jamma_n.p(1).right <= not joystick(0);
		inputs_i.jamma_n.p(1).button(1) <= not joystick(4); 
		inputs_i.jamma_n.p(1).button(2) <= not joystick(5); 
		inputs_i.jamma_n.p(1).button(3) <= '1';
		inputs_i.jamma_n.p(1).button(4) <= '1';
		inputs_i.jamma_n.p(1).button(5) <= '1';
        end generate GEN_NO_JAMMA;
  
	-- not currently wired to any inputs
	inputs_i.jamma_n.coin_cnt <= (others => '1');
	inputs_i.jamma_n.coin(2) <= '1';
	inputs_i.jamma_n.p(2).start <= '1';
	inputs_i.jamma_n.p(2).up <= '1';
	inputs_i.jamma_n.p(2).down <= '1';
	inputs_i.jamma_n.p(2).left <= '1';
	inputs_i.jamma_n.p(2).right <= '1';
	inputs_i.jamma_n.p(2).button <= (others => '1');
	inputs_i.jamma_n.service <= '1';
	inputs_i.jamma_n.tilt <= '1';
	inputs_i.jamma_n.test <= '1';
		
  BLK_VIDEO : block
  begin

    video_i.clk <= clkrst_i.clk(1);	-- by convention
    video_i.clk_ena <= '1';
    video_i.reset <= clkrst_i.rst(1);
    
    VGA_R <= video_o.rgb.r(video_o.rgb.r'left downto video_o.rgb.r'left-5);
    VGA_G <= video_o.rgb.g(video_o.rgb.g'left downto video_o.rgb.g'left-5);
    VGA_B <= video_o.rgb.b(video_o.rgb.b'left downto video_o.rgb.b'left-5);
    VGA_HS <= video_o.hsync;
    VGA_VS <= video_o.vsync;
 
  end block BLK_VIDEO;

  BLK_AUDIO : block
  begin
  
    dacl : entity work.sigma_delta_dac
      port map (
        clk     => CLOCK_27(0),
        din     => audio_o.ldata(15 downto 8),
        dout    => AUDIO_L
      );        

    dacr : entity work.sigma_delta_dac
      port map (
        clk     => CLOCK_27(0),
        din     => audio_o.rdata(15 downto 8),
        dout    => AUDIO_R
      );        

  end block BLK_AUDIO;
 
 pace_inst : entity work.pace                                            
   port map
   (
     -- clocks and resets
     clkrst_i					=> clkrst_i,

     -- misc inputs and outputs
     buttons_i         => buttons_i,
     switches_i        => switches_i,
     leds_o            => open,
     
     -- controller inputs
     inputs_i          => inputs_i,

     	-- external ROM/RAM
     flash_i           => flash_i,
     flash_o           => flash_o,
     sram_i        		=> sram_i,
     sram_o        		=> sram_o,
     sdram_i           => sdram_i,
     sdram_o           => sdram_o,
  
      -- VGA video
      video_i           => video_i,
      video_o           => video_o,
      
      -- sound
      audio_i           => audio_i,
      audio_o           => audio_o,

      -- SPI (flash)
      spi_i.din         => '0',
      spi_o             => open,
  
      -- serial
      ser_i             => ser_i,
      ser_o             => ser_o,
      
      -- custom i/o
      project_i         => project_i,
      project_o         => project_o,
      platform_i        => platform_i,
      platform_o        => platform_o,
      target_i          => target_i,
      target_o          => target_o
    );
end SYN;
