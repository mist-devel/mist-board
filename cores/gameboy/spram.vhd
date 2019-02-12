LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY spram IS
	generic (
		 addr_width : integer := 8;
		 data_width : integer := 8
	); 
	PORT
	(
		clock		: IN STD_LOGIC;
		clken		: IN STD_LOGIC := '1';
		address		: IN STD_LOGIC_VECTOR (addr_width-1 DOWNTO 0);
		data		: IN STD_LOGIC_VECTOR (data_width-1 DOWNTO 0);
		wren		: IN STD_LOGIC := '0';
		q			: OUT STD_LOGIC_VECTOR (data_width-1 DOWNTO 0)
	);
END spram;


ARCHITECTURE SYN OF spram IS

BEGIN
	altsyncram_component : altsyncram
	GENERIC MAP (
		clock_enable_input_a => "NORMAL",
		clock_enable_output_a => "BYPASS",
		intended_device_family => "Cyclone III",
		lpm_hint => "ENABLE_RUNTIME_MOD=NO",
		lpm_type => "altsyncram",
		numwords_a => 2**addr_width,
		operation_mode => "SINGLE_PORT",
		outdata_aclr_a => "NONE",
		outdata_reg_a => "UNREGISTERED",
		power_up_uninitialized => "FALSE",
		read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ",
		widthad_a => addr_width,
		width_a => data_width,
		width_byteena_a => 1
	)
	PORT MAP (
		address_a => address,
		clock0 => clock,
		clocken0 => clken,
		data_a => data,
		wren_a => wren,
		q_a => q
	);



END SYN;
