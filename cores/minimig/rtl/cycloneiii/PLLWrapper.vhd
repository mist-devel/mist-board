-- A wrapper to encapsulate reconfiguring a PLL from multiple MIF files.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity PLLWrapper is
	port (
		areset : in std_logic;
		inclk0 : in std_logic;
		eightmhz : in std_logic;
		c0 : out std_logic;
		c1 : out std_logic;
		c2 : out std_logic;
		locked : out std_logic
	);
end entity;
	
architecture rtl of PLLWrapper is

-- ROM signals
signal muxdata : std_logic;
signal dat1 : std_logic_vector(0 downto 0);
signal dat2 : std_logic_vector(0 downto 0);
signal dat3 : std_logic_vector(0 downto 0);
signal romdata : std_logic_vector(0 downto 0);
signal rom_address : std_logic_vector(7 downto 0);
signal rom_write : std_logic;

-- Mode signals
signal oldmode1 : std_logic:='0';
signal oldmode2 : std_logic:='0';
signal mode_f : std_logic:='0'; -- Filtered version, safe to use from the lower clock domain.
signal mode_f_prev : std_logic:='0'; -- Used to detect changes in mode and trigger reconfig.

-- PLL signals
signal pll_reset : std_logic;
signal pll_configupdate : std_logic;
signal pll_scanclk : std_logic;
signal pll_scanclkena : std_logic;
signal pll_scandata : std_logic;
signal pll_locked : std_logic;
signal pll_scandataout : std_logic;
signal pll_scandone : std_logic;
signal pll_reconfig : std_logic;
signal pll_reconfig_d : std_logic :='0';
signal pll_reconfig_busy : std_logic;

-- Output clock signals.
--signal c0 : std_logic;


component MyPLLReconfig
	PORT
	(
		clock		: IN STD_LOGIC ;
		counter_param		: IN STD_LOGIC_VECTOR (2 DOWNTO 0);
		counter_type		: IN STD_LOGIC_VECTOR (3 DOWNTO 0);
		data_in		: IN STD_LOGIC_VECTOR (8 DOWNTO 0);
		pll_areset_in		: IN STD_LOGIC  := '0';
		pll_scandataout		: IN STD_LOGIC ;
		pll_scandone		: IN STD_LOGIC ;
		read_param		: IN STD_LOGIC ;
		reconfig		: IN STD_LOGIC ;
		reset		: IN STD_LOGIC ;
		reset_rom_address		: IN STD_LOGIC  := '0';
		rom_data_in		: IN STD_LOGIC  := '0';
		write_from_rom		: IN STD_LOGIC  := '0';
		write_param		: IN STD_LOGIC ;
		busy		: OUT STD_LOGIC ;
		data_out		: OUT STD_LOGIC_VECTOR (8 DOWNTO 0);
		pll_areset		: OUT STD_LOGIC ;
		pll_configupdate		: OUT STD_LOGIC ;
		pll_scanclk		: OUT STD_LOGIC ;
		pll_scanclkena		: OUT STD_LOGIC ;
		pll_scandata		: OUT STD_LOGIC ;
		rom_address_out		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
		write_rom_ena		: OUT STD_LOGIC 
	);
end component;

begin

locked <= pll_locked;

-- Filter the incoming mode signal
process(inclk0, eightmhz, oldmode1, oldmode2)
begin
	if rising_edge(inclk0) then
		if oldmode2=eightmhz then -- Signal has been stable for 2 clocks
			mode_f<=oldmode2;
		end if;
		oldmode2<=oldmode1;
		oldmode1<=eightmhz;

		rom_write<='0';
		if mode_f/=mode_f_prev then	-- Trigger a reconfiguration when the mode signal changes
			rom_write<=not pll_reconfig_busy;
			pll_reconfig_d<='1';
		end if;

		pll_reconfig<='0';
		if pll_reconfig_busy='0' and rom_write='0' and pll_reconfig_d='1' then
			pll_reconfig_d<='0';
			pll_reconfig<='1';
		end if;
		
		mode_f_prev<=mode_f;

	end if;
end process;


-- Multiplexer for ROMs
romdata <=	dat1 when mode_f='0' else
				dat2;

				
-- The PLL itself
mypll : entity work.MyPLL
	port map(
		areset => pll_reset,
		configupdate => pll_configupdate,
		inclk0 => inclk0,
		scanclk => pll_scanclk,
		scanclkena => pll_scanclkena,
		scandata	=> pll_scandata,
		c0 => c0,
		c1 => c1,
		c2 => c2,
		locked => pll_locked,
		scandataout => pll_scandataout,
		scandone	=> pll_scandone
	);

-- Reconfiguration component
reconfig : component MyPLLReconfig
	PORT map	(
		clock	=> inclk0,
		counter_param => "000",
		counter_type => "0000",
		data_in => X"00"&'0',
		pll_areset_in => areset,
		pll_scandataout => pll_scandataout,
		pll_scandone => pll_scandone,
		read_param => '0',
		reconfig => pll_reconfig,
		reset => '0',
		reset_rom_address => '0',
		rom_data_in	=> romdata(0),
		write_from_rom => rom_write,
		write_param	=> '0',
		busy => pll_reconfig_busy,
		data_out	=> open,
		pll_areset => pll_reset,
		pll_configupdate => pll_configupdate,
		pll_scanclk	=> pll_scanclk,
		pll_scanclkena	=> pll_scanclkena,
		pll_scandata => pll_scandata,
		rom_address_out => rom_address,
		write_rom_ena => open
	);
	
rom1 : ENTITY work.PLLROM_7MHz
	PORT map
	(
		address => rom_address,
		clock => inclk0,
		q => dat1
	);

rom2 : ENTITY work.PLLROM_8MHz
	PORT map
	(
		address => rom_address,
		clock => inclk0,
		q => dat2
	);
	
end architecture;
