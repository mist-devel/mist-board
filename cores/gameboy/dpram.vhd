LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY dpram IS
	generic (
		 addr_width : integer := 8;
		 data_width : integer := 8
	); 
	PORT
	(
		clock_a		: IN STD_LOGIC;
		clken_a		: IN STD_LOGIC := '1';
		address_a	: IN STD_LOGIC_VECTOR (addr_width-1 DOWNTO 0);
		data_a		: IN STD_LOGIC_VECTOR (data_width-1 DOWNTO 0);
		wren_a		: IN STD_LOGIC := '0';
		q_a			: OUT STD_LOGIC_VECTOR (data_width-1 DOWNTO 0);

		clock_b		: IN STD_LOGIC;
		clken_b		: IN STD_LOGIC := '1';
		address_b	: IN STD_LOGIC_VECTOR (addr_width-1 DOWNTO 0);
		data_b		: IN STD_LOGIC_VECTOR (data_width-1 DOWNTO 0) := (others => '0');
		wren_b		: IN STD_LOGIC := '0';
		q_b			: OUT STD_LOGIC_VECTOR (data_width-1 DOWNTO 0)
	);
END dpram;


ARCHITECTURE SYN OF dpram IS
BEGIN
	altsyncram_component : altsyncram
	GENERIC MAP (
		address_reg_b => "CLOCK1",
		clock_enable_input_a => "NORMAL",
		clock_enable_input_b => "NORMAL",
		clock_enable_output_a => "BYPASS",
		clock_enable_output_b => "BYPASS",
		indata_reg_b => "CLOCK1",
		intended_device_family => "Cyclone III",
		lpm_type => "altsyncram",
		numwords_a => 2**addr_width,
		numwords_b => 2**addr_width,
		operation_mode => "BIDIR_DUAL_PORT",
		outdata_aclr_a => "NONE",
		outdata_aclr_b => "NONE",
		outdata_reg_a => "UNREGISTERED",
		outdata_reg_b => "UNREGISTERED",
		power_up_uninitialized => "FALSE",
		read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ",
		read_during_write_mode_port_b => "NEW_DATA_NO_NBE_READ",
		widthad_a => addr_width,
		widthad_b => addr_width,
		width_a => data_width,
		width_b => data_width,
		width_byteena_a => 1,
		width_byteena_b => 1,
		wrcontrol_wraddress_reg_b => "CLOCK1"
	)
	PORT MAP (
		address_a => address_a,
		address_b => address_b,
		clock0 => clock_a,
		clock1 => clock_b,
		clocken0 => clken_a,
		clocken1 => clken_b,
		data_a => data_a,
		data_b => data_b,
		wren_a => wren_a,
		wren_b => wren_b,
		q_a => q_a,
		q_b => q_b
	);

END SYN;


--------------------------------------------------------------
-- Dual port Block RAM different parameters on ports
--------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

entity dpram_dif is
	generic (
		addr_width_a  : integer := 8;
		data_width_a  : integer := 8;
		addr_width_b  : integer := 8;
		data_width_b  : integer := 8;
		mem_init_file : string := " "
	);
	PORT
	(
		clock			: in  STD_LOGIC;

		address_a	: in  STD_LOGIC_VECTOR (addr_width_a-1 DOWNTO 0);
		data_a		: in  STD_LOGIC_VECTOR (data_width_a-1 DOWNTO 0) := (others => '0');
		enable_a		: in  STD_LOGIC := '1';
		wren_a		: in  STD_LOGIC := '0';
		q_a			: out STD_LOGIC_VECTOR (data_width_a-1 DOWNTO 0);
		cs_a        : in  std_logic := '1';

		address_b	: in  STD_LOGIC_VECTOR (addr_width_b-1 DOWNTO 0) := (others => '0');
		data_b		: in  STD_LOGIC_VECTOR (data_width_b-1 DOWNTO 0) := (others => '0');
		enable_b		: in  STD_LOGIC := '1';
		wren_b		: in  STD_LOGIC := '0';
		q_b			: out STD_LOGIC_VECTOR (data_width_b-1 DOWNTO 0);
		cs_b        : in  std_logic := '1'
	);
end entity;


ARCHITECTURE SYN OF dpram_dif IS

	signal q0 : std_logic_vector((data_width_a - 1) downto 0);
	signal q1 : std_logic_vector((data_width_b - 1) downto 0);

BEGIN
	q_a<= q0 when cs_a = '1' else (others => '1');
	q_b<= q1 when cs_b = '1' else (others => '1');

	altsyncram_component : altsyncram
	GENERIC MAP (
		address_reg_b => "CLOCK1",
		clock_enable_input_a => "NORMAL",
		clock_enable_input_b => "NORMAL",
		clock_enable_output_a => "BYPASS",
		clock_enable_output_b => "BYPASS",
		indata_reg_b => "CLOCK1",
		intended_device_family => "Cyclone V",
		lpm_type => "altsyncram",
		numwords_a => 2**addr_width_a,
		numwords_b => 2**addr_width_b,
		operation_mode => "BIDIR_DUAL_PORT",
		outdata_aclr_a => "NONE",
		outdata_aclr_b => "NONE",
		outdata_reg_a => "UNREGISTERED",
		outdata_reg_b => "UNREGISTERED",
		power_up_uninitialized => "FALSE",
		read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ",
		read_during_write_mode_port_b => "NEW_DATA_NO_NBE_READ",
		init_file => mem_init_file, 
		widthad_a => addr_width_a,
		widthad_b => addr_width_b,
		width_a => data_width_a,
		width_b => data_width_b,
		width_byteena_a => 1,
		width_byteena_b => 1,
		wrcontrol_wraddress_reg_b => "CLOCK1"
	)
	PORT MAP (
		address_a => address_a,
		address_b => address_b,
		clock0 => clock,
		clock1 => clock,
		clocken0 => enable_a,
		clocken1 => enable_b,
		data_a => data_a,
		data_b => data_b,
		wren_a => wren_a and cs_a,
		wren_b => wren_b and cs_b,
		q_a => q0,
		q_b => q1
	);

END SYN;
