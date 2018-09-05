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
--
-- c1541_logic    modified for : slow down CPU (EOI ack missed by real c64)
--                             : remove iec internal OR wired
--                             : synched atn_in (sometime no IRQ with real c64)
-- spi_controller modified for : sector start and size adapted + busy signal
-- via6522        modified for : no modification
--
--
-- Input clk 32MHz
--
---------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

entity c1541_sd is
port
(
	clk32          : in std_logic;
	reset          : in std_logic;

	disk_change    : in std_logic;
	disk_readonly  : in std_logic;

	iec_atn_i      : in std_logic;
	iec_data_i     : in std_logic;
	iec_clk_i      : in std_logic;

	iec_atn_o      : out std_logic;
	iec_data_o     : out std_logic;
	iec_clk_o      : out std_logic;

	sd_lba         : out std_logic_vector(31 downto 0);
	sd_rd          : out std_logic;
	sd_wr          : out std_logic;
	sd_ack         : in  std_logic;
	sd_ack_conf    : in  std_logic;

	sd_sdhc        : out std_logic;
	sd_conf        : out std_logic;
	sd_buff_addr   : in  std_logic_vector(8 downto 0);
	sd_buff_dout   : in  std_logic_vector(7 downto 0);
	sd_buff_din    : out std_logic_vector(7 downto 0);
	sd_buff_wr     : in  std_logic;

	led            : out std_logic;

	c1541rom_addr  : in  std_logic_vector(13 downto 0);
	c1541rom_data  : in  std_logic_vector(7 downto 0);
	c1541rom_wr    : in  std_logic
);
end c1541_sd;

architecture struct of c1541_sd is

	component sd_card port
	(
		sd_lba         : out std_logic_vector(31 downto 0);
		sd_rd          : out std_logic;
		sd_wr          : out std_logic;
		sd_ack         : in  std_logic;
		sd_ack_conf    : in  std_logic;
		sd_sdhc        : out std_logic;
		sd_conf        : out std_logic;

		sd_buff_addr   : in  std_logic_vector(8 downto 0);
		sd_buff_dout   : in  std_logic_vector(7 downto 0);
		sd_buff_din    : out std_logic_vector(7 downto 0);
		sd_buff_wr     : in  std_logic;

		buff_addr      : in  std_logic_vector(7 downto 0);
		buff_dout      : out std_logic_vector(7 downto 0);
		buff_din       : in  std_logic_vector(7 downto 0);
		buff_we        : in  std_logic;

		save_track     : in  std_logic;

		change         : in  std_logic;                     -- Force reload as disk may have changed
		track          : in  std_logic_vector(5 downto 0);  -- Track number (0-34)
		sector         : in  std_logic_vector(4 downto 0);  -- Sector number (0-20)
		busy           : out std_logic;

		clk            : in  std_logic;     -- System clock
		reset          : in  std_logic
	);
	end component sd_card;

	signal buff_dout  : std_logic_vector(7 downto 0);
	signal buff_din   : std_logic_vector(7 downto 0);
	signal buff_we    : std_logic;
	signal do         : std_logic_vector(7 downto 0); -- disk read data
	signal di         : std_logic_vector(7 downto 0); -- disk write data
	signal mode       : std_logic;                    -- read/write
	signal stp        : std_logic_vector(1 downto 0); -- stepper motor control
	signal stp_r      : std_logic_vector(1 downto 0); -- stepper motor control
	signal mtr        : std_logic ;                   -- stepper motor on/off
	signal sync_n     : std_logic;                    -- reading SYNC bytes
	signal byte_n     : std_logic;                    -- byte ready
	signal act        : std_logic;                    -- activity LED
	signal act_r      : std_logic;                    -- activity LED
	signal sd_busy    : std_logic;
	signal sector     : std_logic_vector(4 downto 0);
	signal byte_addr  : std_logic_vector(7 downto 0);
	signal track_num_dbl : std_logic_vector(6 downto 0);
	signal track      : std_logic_vector(5 downto 0);

	signal tr00_sense_n     : std_logic;
	signal save_track       : std_logic;
	signal track_modified   : std_logic;

begin
	
	tr00_sense_n <= '1' when (track > "000000") else '0';

	c1541 : entity work.c1541_logic
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
		c1541rom_wr   => c1541rom_wr,

		-- drive-side interface
		ds            => "00",   -- device select
		di            => do,     -- disk read data
		do            => di,     -- disk write data
		mode          => mode,   -- read/write
		stp           => stp,    -- stepper motor control
		mtr           => mtr,    -- motor on/off
		freq          => open,   -- motor frequency
		sync_n        => sync_n, -- reading SYNC bytes
		byte_n        => byte_n, -- byte ready
		wps_n         => not disk_readonly,    -- write-protect sense
		tr00_sense_n  => tr00_sense_n,    -- track 0 sense (unused?)
		act           => act     -- activity LED
	);

	floppy : entity work.gcr_floppy
	port map
	(
		clk32  => clk32,

		dout        => do,     -- disk read data	
		din         => di,
		mode        => mode,
		mtr    => mtr,    -- stepper motor on/off
		sync_n => sync_n, -- reading SYNC bytes
		byte_n => byte_n, -- byte ready
		
		track       => track,
		sector      => sector,

		byte_addr   => byte_addr,

		ram_do      => buff_dout,
		ram_di      => buff_din,
		ram_we      => buff_we,

		ram_ready   => not sd_busy
	);

	sd : sd_card
	port map
	(
		sd_lba  => sd_lba,
		sd_rd   => sd_rd,
		sd_wr   => sd_wr,
		sd_ack  => sd_ack,
		sd_conf => sd_conf,
		sd_sdhc => sd_sdhc,
		sd_ack_conf => sd_ack_conf,

		sd_buff_addr => sd_buff_addr,
		sd_buff_dout => sd_buff_dout,
		sd_buff_din  => sd_buff_din,
		sd_buff_wr   => sd_buff_wr,

		buff_addr => byte_addr,
		buff_dout => buff_dout,
		buff_din  => buff_din,
		buff_we   => buff_we,

		save_track => save_track,
		change  => disk_change,
		track   => track,
		sector  => sector,

		clk     => clk32,
		reset   => reset, 
		busy    => sd_busy
	);

	led <= act or sd_busy;

	process (clk32)
	begin
		if rising_edge(clk32) then
			stp_r <= stp;
			act_r <= act;
			save_track <= '0';
			track <= track_num_dbl(6 downto 1);

			if buff_we     = '1' then track_modified <= '1'; end if;
			if disk_change = '1' then track_modified <= '0'; end if;

			if reset = '1' then
				track_num_dbl  <= "0100100";--"0000010";
				track_modified <= '0';
			else
				if mtr = '1' then
					if(  (stp_r = "00" and stp = "10")
						or (stp_r = "10" and stp = "01")
						or (stp_r = "01" and stp = "11")
						or (stp_r = "11" and stp = "00")) then
							if track_num_dbl < "1010000" then
								track_num_dbl <= track_num_dbl + '1';
							end if;
							save_track <= track_modified;
							track_modified <= '0';
					end if;

					if(  (stp_r = "00" and stp = "11")
						or (stp_r = "10" and stp = "00")
						or (stp_r = "01" and stp = "10")
						or (stp_r = "11" and stp = "01")) then 
							if track_num_dbl > "0000001" then
								track_num_dbl <= track_num_dbl - '1';
							end if;
							save_track <= track_modified;
							track_modified <= '0';
					end if;
				end if;

				if act_r = '1' and act = '0' then -- stopping activity
					save_track <= track_modified;
					track_modified <= '0';
				end if;
			end if;
		end if;  -- rising edge clock
	end process;

end struct;
