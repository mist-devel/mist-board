---------------------------------------------------------------------------------
-- Commodore 1541 to SD card (read only) by Dar (darfpga@aol.fr) 02-April-2015
-- http://darfpga.blogspot.fr
--
-- c1541_sd reads D64 data from raw SD card, produces GCR data, feeds c1541_logic
-- Raw SD data : each D64 image must start on 256KB boundaries
-- disk_num allow to select D64 image
--
-- c1541_logic    from : Mark McDougall
-- spi_controller from : Michel Stempin, Stephen A. Edwards
-- via6522        from : Arnim Laeuger, Mark McDougall, MikeJ
-- T65            from : Daniel Wallner, MikeJ, ehenciak
--
-- c1541_logic    modified for : slow down CPU (EOI ack missed by real c64)
--                             : remove iec internal OR wired
--                             : synched atn_in (sometime no IRQ with real c64)
-- spi_controller modified for : sector start and size adapted + busy signal
-- via6522        modified for : no modification
--
--
-- Input clk 32MHz and 18MHz (18MHz could be replaced with 32/2 if needed)
--     
---------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

entity c1541_sd is
port
(
	clk32       : in std_logic;
	clk18       : in std_logic;
	reset       : in std_logic;

	disk_change : in std_logic;
	disk_num    : in std_logic_vector(9 downto 0);

	iec_atn_i   : in std_logic;
	iec_data_i  : in std_logic;
	iec_clk_i   : in std_logic;

	iec_atn_o   : out std_logic;
	iec_data_o  : out std_logic;
	iec_clk_o   : out std_logic;

	sd_dat      : in std_logic;
	sd_dat3     : buffer std_logic;
	sd_cmd      : buffer std_logic;
	sd_clk      : buffer std_logic;

	led         : out std_logic_vector(7 downto 0);

	c1541rom_addr   : in std_logic_vector(13 downto 0);
	c1541rom_data   : in std_logic_vector(7 downto 0);
	c1541rom_wr     : in std_logic
);
end c1541_sd;

architecture struct of c1541_sd is

signal ram_write_addr : unsigned(12 downto 0);
signal ram_addr       : unsigned(12 downto 0);
signal ram_di         : unsigned( 7 downto 0);
signal ram_do         : unsigned( 7 downto 0);
signal ram_we         : std_logic;
signal do             : std_logic_vector(7 downto 0); -- disk read data
signal mode           : std_logic;                    -- read/write
signal stp            : std_logic_vector(1 downto 0); -- stepper motor control
signal stp_r          : std_logic_vector(1 downto 0); -- stepper motor control
signal mtr            : std_logic ;                   -- stepper motor on/off
signal freq           : std_logic_vector(1 downto 0); -- motor (gcr_bit) frequency
signal sync_n         : std_logic;                    -- reading SYNC bytes
signal byte_n         : std_logic;                    -- byte ready
signal act            : std_logic;                    -- activity LED
signal track_dbl      : std_logic_vector(6 downto 0);
signal sd_busy        : std_logic;
signal track_read_adr : std_logic_vector(12 downto 0);

begin
	
	c1541 : entity work.c1541_logic
	generic map
	(
		DEVICE_SELECT => "00"
	)
	port map
	(
		clk_32M => clk32,
		reset => reset,

		-- serial bus
		sb_data_oe => iec_data_o,
		sb_clk_oe  => iec_clk_o,
		sb_atn_oe  => iec_atn_o,
		
		sb_data_in => not iec_data_i,
		sb_clk_in  => not iec_clk_i,
		sb_atn_in  => not iec_atn_i,
    
		c1541rom_addr => c1541rom_addr,
		c1541rom_data => c1541rom_data,
		c1541rom_wr => c1541rom_wr,

		-- drive-side interface
		ds              => "00",   -- device select
		di              => do,     -- disk write data
		do              => open,   -- disk read data
		mode            => mode,   -- read/write
		stp             => stp,    -- stepper motor control
		mtr             => mtr,    -- motor on/off
		freq            => freq,   -- motor frequency
		sync_n          => sync_n, -- reading SYNC bytes
		byte_n          => byte_n, -- byte ready
		wps_n           => '0',    -- write-protect sense
		tr00_sense_n    => '1',    -- track 0 sense (unused?)
		act             => act     -- activity LED
	);

	floppy : entity work.gcr_floppy
	port map
	(
		clk32  => clk32,

		do     => do,     -- disk read data
		mode   => mode,   -- read/write
		stp    => stp,    -- stepper motor control
		mtr    => mtr,    -- stepper motor on/off
		freq   => freq,   -- motor (gcr_bit) frequency
		sync_n => sync_n, -- reading SYNC bytes
		byte_n => byte_n, -- byte ready
		
		track       => track_dbl(6 downto 1),
		track_adr   => track_read_adr,
		track_data  => std_logic_vector(ram_do), 	
		track_ready => not sd_busy
	);
	
	process (clk32)
	begin
		if rising_edge(clk32) then
			stp_r <= stp;
			if reset = '1' then
				track_dbl <= "0000010";
			else
				if mtr = '1' then
					if(  (stp_r = "00" and stp = "10")
						or (stp_r = "10" and stp = "01")
						or (stp_r = "01" and stp = "11")
						or (stp_r = "11" and stp = "00")) then
							if track_dbl < "1010000" then
								track_dbl <= std_logic_vector(unsigned(track_dbl) + 1);
							end if;
					end if;
				
					if(  (stp_r = "00" and stp = "11")
						or (stp_r = "10" and stp = "00")
						or (stp_r = "01" and stp = "10")
						or (stp_r = "11" and stp = "01")) then 
							if track_dbl > "0000001" then
								track_dbl <= std_logic_vector(unsigned(track_dbl) - 1);
							end if;
					end if;
				end if;
			end if;
		end if;
	end process;


	sd_spi : entity work.spi_controller
	port map
	(
		CS_N => sd_dat3, --: out std_logic;     -- MMC chip select
		MOSI => sd_cmd,  --: out std_logic;     -- Data to card (master out slave in)
		MISO => sd_dat,  --: in  std_logic;     -- Data from card (master in slave out)
		SCLK => sd_clk,  --: out std_logic;     -- Card clock
  
		ram_write_addr => ram_write_addr, --: out unsigned(13 downto 0);
		ram_di         => ram_di,         --: out unsigned(7 downto 0);
		ram_we         => ram_we,         
  
      change => disk_change,
		track => unsigned(track_dbl(6 downto 1)),
		image => unsigned(disk_num),
  
		CLK_14M => clk18,
		reset   => reset, 
		busy => sd_busy
	);
	
	track_buffer : entity work.gen_ram
	generic map
	(
		dWidth => 8,
		aWidth => 13
	)
	port map
	(
		clk  => not clk18,
		we   => ram_we,
		addr => ram_addr,
		d    => ram_di,
		q    => ram_do
	);
	
	with sd_busy select 
--		ram_addr <= ram_write_addr when '1', unsigned('0'&track_read_adr) when others; 
		ram_addr <= ram_write_addr when '1', unsigned(track_read_adr) when others; 

	led(0)          <= mode;     -- read/write
	led(2 downto 1) <= stp;      -- stepper motor control
	led(3)          <= mtr;      -- stepper motor on/off
	led(5 downto 4) <= freq;     -- motor frequency
	led(6)          <= act;      -- activity LED
	led(7)          <= sd_busy;  -- SD read	
end struct;
