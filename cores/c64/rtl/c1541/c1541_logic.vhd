library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

--
-- Model 1541B
--
entity c1541_logic is
port
(
	clk_32M       : in  std_logic;
	reset         : in  std_logic;

	-- serial bus
	sb_data_oe    : out std_logic;
	sb_data_in    : in  std_logic;
	sb_clk_oe     : out std_logic;
	sb_clk_in     : in  std_logic;
	sb_atn_in     : in  std_logic;

	c1541rom_clk  : in  std_logic;
	c1541rom_addr : in  std_logic_vector(13 downto 0);
	c1541rom_data : in  std_logic_vector(7 downto 0);
	c1541rom_wr   : in  std_logic;

	-- drive-side interface
	ds            : in  std_logic_vector(1 downto 0);   -- device select
	di            : in  std_logic_vector(7 downto 0);   -- disk read data
	do            : out std_logic_vector(7 downto 0);   -- disk write data
	mode          : out std_logic;                      -- read/write
	stp           : out std_logic_vector(1 downto 0);   -- stepper motor control
	mtr           : out std_logic;                      -- stepper motor on/off
	freq          : out std_logic_vector(1 downto 0);   -- motor frequency
	sync_n        : in  std_logic;                      -- reading SYNC bytes
	byte_n        : in  std_logic;                      -- byte ready
	wps_n         : in  std_logic;                      -- write-protect sense
	tr00_sense_n  : in  std_logic;                      -- track 0 sense (unused?)
	act           : out std_logic                       -- activity LED
);
end c1541_logic;

architecture SYN of c1541_logic is

	-- clocks
	signal p2_h_r         : std_logic;
	signal p2_h_f         : std_logic;

	-- cpu signals  
	signal cpu_a          : std_logic_vector(16 downto 0);
	signal cpu_di         : std_logic_vector(7 downto 0);
	signal cpu_do         : std_logic_vector(7 downto 0);
	signal cpu_rw         : std_logic;
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
	signal uc1_cs         : std_logic;
	signal uc1_irq_n      : std_logic;
	signal uc1_pa_i       : std_logic_vector(7 downto 0) := (others => '0');
	signal uc1_pb_i       : std_logic_vector(7 downto 0) := (others => '0');
	signal uc1_pb_o       : std_logic_vector(7 downto 0);
	signal uc1_pb_oe_n    : std_logic_vector(7 downto 0);

	-- UC3 (VIA6522) signals
	signal uc3_do         : std_logic_vector(7 downto 0);
	signal uc3_cs         : std_logic;
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

	signal sb_data        : std_logic;
	signal sb_clk         : std_logic;

	signal iec_atn_d1     : std_logic;
	signal iec_data_d1    : std_logic;
	signal iec_clk_d1     : std_logic;
	signal iec_atn_d2     : std_logic;
	signal iec_data_d2    : std_logic;
	signal iec_clk_d2     : std_logic;
	signal iec_atn        : std_logic;
	signal iec_data       : std_logic;
	signal iec_clk        : std_logic;

begin
	process (clk_32M) begin
		if rising_edge(clk_32M) then
			iec_atn_d1 <=sb_atn_in;
			iec_atn_d2 <=iec_atn_d1;
			iec_atn    <=iec_atn_d2;

			iec_data_d1<=sb_data_in;
			iec_data_d2<=iec_data_d1;
			iec_data   <=iec_data_d2;

			iec_clk_d1 <=sb_clk_in;
			iec_clk_d2 <=iec_clk_d1;
			iec_clk    <=iec_clk_d2;
		end if;
	end process;

	process (clk_32M, reset)
		variable count  : std_logic_vector(4 downto 0) := (others => '0');
	begin
		if rising_edge(clk_32M) then
			count := std_logic_vector(unsigned(count) + 1);

			p2_h_r <= '0';	if count = "00000" then p2_h_r <= '1'; end if;
			p2_h_f <= '0';	if count = "10000" then p2_h_f <= '1'; end if;
		end if;
	end process;

	-- decode logic
	ram_cs <= '1' when STD_MATCH(cpu_a(15 downto 0), "00000-----------") else '0'; -- RAM $0000-$07FF (2KB)
	uc1_cs <= '1' when STD_MATCH(cpu_a(15 downto 0), "000110000000----") else '0'; -- UC1 $1800-$180F
	uc3_cs <= '1' when STD_MATCH(cpu_a(15 downto 0), "000111000000----") else '0'; -- UC3 $1C00-$1C0F
	rom_cs <= '1' when STD_MATCH(cpu_a(15 downto 0), "11--------------") else '0'; -- ROM $C000-$FFFF (16KB)

	-- qualified write signals
	ram_wr <= '1' when ram_cs = '1' and cpu_rw = '0' else '0';

	--
	-- hook up UC1 ports
	--
	sb_data <= (uc1_pb_o(1) and not uc1_pb_oe_n(1)) or atn;
	sb_clk  <= uc1_pb_o(3) and not uc1_pb_oe_n(3);
	atna    <= uc1_pb_o(4);

	uc1_pa_i(0) <= tr00_sense_n;
	uc1_pb_i(0) <= not iec_data or sb_data;
	uc1_pb_i(2) <= not iec_clk or sb_clk;
	uc1_pb_i(7) <= not iec_atn;
	uc1_pb_i(6 downto 5) <= ds;

	sb_data_oe  <= sb_data;
	sb_clk_oe   <= sb_clk;

	--
	-- hook up UC3 ports
	--
	uc3_ca1_i <= cpu_so_n; -- byte ready gated with soe
	soe       <= uc3_ca2_o or uc3_ca2_oe_n;
	uc3_pa_i  <= di;
	do        <= uc3_pa_o or uc3_pa_oe_n;
	mode      <= uc3_cb2_o or uc3_cb2_oe_n;

	stp(1)    <= uc3_pb_o(0) or uc3_pb_oe_n(0);
	stp(0)    <= uc3_pb_o(1) or uc3_pb_oe_n(1);
	mtr       <= uc3_pb_o(2) or uc3_pb_oe_n(2);
	act       <= uc3_pb_o(3) or uc3_pb_oe_n(3);
	freq      <= uc3_pb_o(6 downto 5) or uc3_pb_oe_n(6 downto 5);
	uc3_pb_i  <= sync_n & "11" & wps_n & "1111";
  
	--
	-- CPU connections
	--
	cpu_di <= rom_do when rom_cs = '1' else
             ram_do when ram_cs = '1' else
             uc1_do when uc1_cs = '1' else
             uc3_do when uc3_cs = '1' else
             (others => '1');

	cpu_irq_n <= uc1_irq_n and uc3_irq_n;
	cpu_so_n  <= byte_n or not soe;

	-- internal connections
	atn <= atna xor (not sb_atn_in);

	cpu: work.proc_core
	port map(
		reset        => reset,
		clock_en     => p2_h_f,
		clock        => clk_32M,
		so_n         => cpu_so_n,
		irq_n        => cpu_irq_n,
		read_write_n => cpu_rw,
		addr_out     => cpu_a,
		data_in      => cpu_di,
		data_out     => cpu_do
	);

	rom_inst: entity work.C1541_rom
	port map (
		wrclock => c1541rom_clk,

		wren => c1541rom_wr,
		data => c1541rom_data,
		wraddress => c1541rom_addr,

		rdclock => clk_32M,
		rdaddress => cpu_a(13 downto 0),
		q => rom_do
	);

	process (clk_32M)
	begin 
		if rising_edge(clk_32M) then
			ram_do <= ram(to_integer(unsigned(cpu_a(13 downto 0))));
			if ram_wr = '1' then
				ram(to_integer(unsigned(cpu_a(13 downto 0)))) <= cpu_do;
			end if;
		end if;
	end process;

	uc1_via6522_inst : entity work.c1541_via6522
	port map
	(
		addr       => cpu_a(3 downto 0),
		data_in    => cpu_do,
		data_out   => uc1_do,

		ren        => cpu_rw and uc1_cs,
		wen        => not cpu_rw and uc1_cs,
		
		irq_l      => uc1_irq_n,

		-- port a
		ca1_i      => not sb_atn_in,
		ca2_i      => '0',

		port_a_i   => uc1_pa_i,

		-- port b
		cb1_i      => '0',
		cb2_i      => '0',

		port_b_i   => uc1_pb_i,
		port_b_o   => uc1_pb_o,
		port_b_t_l => uc1_pb_oe_n,

		reset      => reset,
		clock      => clk_32M,
		rising     => p2_h_r,
		falling    => p2_h_f
	);

	uc3_via6522_inst : entity work.c1541_via6522
	port map
	(
		addr       => cpu_a(3 downto 0),
		data_in    => cpu_do,
		data_out   => uc3_do,

		ren        => cpu_rw and uc3_cs,
		wen        => not cpu_rw and uc3_cs,

		irq_l      => uc3_irq_n,

		-- port a
		ca1_i      => uc3_ca1_i,
		ca2_i      => '0',
		ca2_o      => uc3_ca2_o,
		ca2_t_l    => uc3_ca2_oe_n,

		port_a_i   => uc3_pa_i,
		port_a_o   => uc3_pa_o,
		port_a_t_l => uc3_pa_oe_n,

		-- port b
		cb1_i      => '0',
		cb2_i      => '0',
		cb2_o      => uc3_cb2_o,
		cb2_t_l    => uc3_cb2_oe_n,

		port_b_i   => uc3_pb_i,
		port_b_o   => uc3_pb_o,
		port_b_t_l => uc3_pb_oe_n,

		reset      => reset,
		clock      => clk_32M,
		rising     => p2_h_r,
		falling    => p2_h_f
	);

end SYN;
