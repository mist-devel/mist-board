library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

--use work.platform_pkg.all;
--use work.project_pkg.all;

--
-- Model 1541B
--

entity c1541_logic is
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

	c1541rom_addr   : in std_logic_vector(13 downto 0);
	c1541rom_data   : in std_logic_vector(7 downto 0);
	c1541rom_wr     : in std_logic;

	-- drive-side interface
	ds              : in std_logic_vector(1 downto 0);    -- device select
	di              : in std_logic_vector(7 downto 0);    -- disk read data
	do              : out std_logic_vector(7 downto 0);   -- disk write data
	mode            : out std_logic;                      -- read/write
	stp             : out std_logic_vector(1 downto 0);   -- stepper motor control
	mtr             : out std_logic;                      -- stepper motor on/off
	freq            : out std_logic_vector(1 downto 0);   -- motor frequency
	sync_n          : in std_logic;                       -- reading SYNC bytes
	byte_n          : in std_logic;                       -- byte ready
	wps_n           : in std_logic;                       -- write-protect sense
	tr00_sense_n    : in std_logic;                       -- track 0 sense (unused?)
	act             : out std_logic                       -- activity LED
);
end c1541_logic;

architecture SYN of c1541_logic is

	-- clocks, reset
	signal reset_n        : std_logic;
	signal clk_4M_en      : std_logic;
	signal p2_h           : std_logic;
	signal clk_1M_pulse   : std_logic;

	-- cpu signals  
	signal cpu_a          : unsigned(15 downto 0);
	signal cpu_di         : unsigned(7 downto 0);
	signal cpu_do         : unsigned(7 downto 0);
	signal cpu_a_l        : std_logic_vector(23 downto 0);
	signal cpu_do_l       : std_logic_vector(7 downto 0);
	signal cpu_rw         : std_logic;
	signal cpu_rw_n       : std_logic;
	signal cpu_irq_n      : std_logic;
	signal cpu_so_n       : std_logic;

	-- rom signals
	signal rom_cs         : std_logic;
	signal rom_do         : std_logic_vector(cpu_di'range); 

	-- ram signals
	signal ram_cs         : std_logic;
	signal ram_wr         : std_logic;
	signal ram_do         : std_logic_vector(cpu_di'range);

	-- UC1 (VIA6522) signals
	signal uc1_do         : std_logic_vector(7 downto 0);
	signal uc1_cs1        : std_logic;
	signal uc1_cs2_n      : std_logic;
	signal uc1_irq_n      : std_logic;
	signal uc1_ca1_i      : std_logic;
	signal uc1_pa_i       : std_logic_vector(7 downto 0);
	signal uc1_pb_i       : std_logic_vector(7 downto 0) := (others => '0');
	signal uc1_pb_o       : std_logic_vector(7 downto 0);
	signal uc1_pb_oe_n    : std_logic_vector(7 downto 0);

	-- UC3 (VIA6522) signals
	signal uc3_do         : std_logic_vector(7 downto 0);
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

	type t_byte_array is array(2047 downto 0) of std_logic_vector(7 downto 0);
	signal ram            : t_byte_array;
  
begin

	reset_n <= not reset;
  
	process (clk_32M, reset)
		variable count  : std_logic_vector(8 downto 0) := (others => '0');
		alias hcnt : std_logic_vector(1 downto 0) is count(4 downto 3);
	begin
		if rising_edge(clk_32M) then
			-- generate 1MHz pulse
			clk_1M_pulse <= '0';
			--if count(4 downto 0) = "00111" then			
			if count(4 downto 0) = "01000" then
				clk_1M_pulse <= '1';
			end if;
	--      if count = "000100000" then -- DAR divide by 33 (otherwise real c64 miss EOI acknowledge)
			if count = "000011111" then -- TH: divide by 32 
				count := (others => '0');   -- DAR	
			else                        -- DAR
				count := std_logic_vector(unsigned(count) + 1);
			end if;                     -- DAR
		end if;
		p2_h <= not hcnt(1);

    -- for original m6522 design that requires a real clock
--    clk_4M_en <= not count(2);

    -- for version 002 with clock enable
		if count(2 downto 0) = "111" then
			clk_4M_en <= '1';
		else
			clk_4M_en <= '0';
		end if;
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
	ram_wr <= '1' when ram_cs = '1' and cpu_rw = '1' else '0';

	--
	-- hook up UC1 ports
	--
  
	uc1_cs1 <= cpu_a(11);
	--uc1_cs2_n: see decode logic above
	-- CA1
	--uc1_ca1_i <= not sb_atn_in;  -- DAR comment : synched with clk_4M_en see below
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
	uc1_pb_i(6 downto 5) <= ds;     -- allows override
	uc1_pb_i(7) <= not sb_atn_in;

	--
	-- hook up UC3 ports
	--
  
	uc3_cs1 <= cpu_a(11);
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
	cpu_di <= unsigned(rom_do) when rom_cs = '1' else
             unsigned(ram_do) when ram_cs = '1' else
             unsigned(uc1_do) when (uc1_cs1 = '1' and uc1_cs2_n = '0') else
             unsigned(uc3_do) when (uc3_cs1 = '1' and uc3_cs2_n = '0') else
             (others => '1');
	cpu_irq_n <= uc1_irq_n and uc3_irq_n;
	cpu_so_n <= byte_n or not soe;
  
	-- internal connections
	atn <= atna xor (not sb_atn_in);
  
	-- external connections
	-- ATN never driven by the 1541
	sb_atn_oe <= '0';
      
			
	-- DAR
	process (clk_32M)
	begin 
    if rising_edge(clk_32M) then
			if clk_4M_en = '1' then
				uc1_ca1_i <= not sb_atn_in; -- DAR sample external atn to ensure not missing edge within VIA
			end if;
		end if;
	end process;
	
	cpu: entity work.cpu65xx
	generic map (
		pipelineOpcode => false,
		pipelineAluMux => false,
		pipelineAluOut => false
	)
	port map (
		clk => clk_32M,
		enable => clk_1M_pulse,
		reset => reset,
		nmi_n => '1',
		irq_n => cpu_irq_n,
		so_n => cpu_so_n,
		di => cpu_di,
		do => cpu_do,
		addr => cpu_a,
		we => cpu_rw
	);

	rom_inst: entity work.rom_C1541
	port map (
		clock => clk_32M,

		wren => c1541rom_wr,
		data => c1541rom_data,
		wraddress => c1541rom_addr,

		rdaddress => std_logic_vector(cpu_a(13 downto 0)),
		q => rom_do
	);

	process (clk_32M)
	begin 
		if rising_edge(clk_32M) then
			ram_do <= ram(to_integer(cpu_a(13 downto 0)));
			if ram_wr = '1' then
				ram(to_integer(cpu_a(13 downto 0))) <= std_logic_vector(cpu_do);
			end if;
		end if;
	end process;


	uc1_via6522_inst : entity work.M6522
	port map
	(
		I_RS            => std_logic_vector(cpu_a(3 downto 0)),
		I_DATA          => std_logic_vector(cpu_do),
		O_DATA          => uc1_do,
		O_DATA_OE_L     => open,

		I_RW_L          => not cpu_rw,
		I_CS1           => uc1_cs1,
		I_CS2_L         => uc1_cs2_n,

		O_IRQ_L         => uc1_irq_n,

		-- port a
		I_CA1           => uc1_ca1_i,
		I_CA2           => '0',
		O_CA2           => open,
		O_CA2_OE_L      => open,

		I_PA            => uc1_pa_i,
		O_PA            => open,
		O_PA_OE_L       => open,

		-- port b
		I_CB1           => '0',
		O_CB1           => open,
		O_CB1_OE_L      => open,

		I_CB2           => '0',
		O_CB2           => open,
		O_CB2_OE_L      => open,

		I_PB            => uc1_pb_i,
		O_PB            => uc1_pb_o,
		O_PB_OE_L       => uc1_pb_oe_n,

		RESET_L         => reset_n,
		CLK             => clk_32M,
		I_P2_H          => p2_h,          -- high for phase 2 clock   ____----__
		ENA_4           => clk_4M_en      -- 4x system clock (4MHZ)   _-_-_-_-_-
	);

	uc3_via6522_inst : entity work.M6522
	port map
	(
		I_RS            => std_logic_vector(cpu_a(3 downto 0)),
		I_DATA          => std_logic_vector(cpu_do),
		O_DATA          => uc3_do,
		O_DATA_OE_L     => open,

		I_RW_L          => not cpu_rw,
		I_CS1           => cpu_a(11),
		I_CS2_L         => uc3_cs2_n,

		O_IRQ_L         => uc3_irq_n,

		-- port a
		I_CA1           => uc3_ca1_i,
		I_CA2           => '0',
		O_CA2           => uc3_ca2_o,
		O_CA2_OE_L      => uc3_ca2_oe_n,

		I_PA            => uc3_pa_i,
		O_PA            => uc3_pa_o,
		O_PA_OE_L       => uc3_pa_oe_n,

		-- port b
		I_CB1           => '0',
		O_CB1           => open,
		O_CB1_OE_L      => open,
		
		I_CB2           => '0',
		O_CB2           => uc3_cb2_o,
		O_CB2_OE_L      => uc3_cb2_oe_n,

		I_PB            => uc3_pb_i,
		O_PB            => uc3_pb_o,
		O_PB_OE_L       => uc3_pb_oe_n,

		RESET_L         => reset_n,
		CLK             => clk_32M,
		I_P2_H          => p2_h,          -- high for phase 2 clock   ____----__
		ENA_4           => clk_4M_en      -- 4x system clock (4MHZ)   _-_-_-_-_-
	);

end SYN;
