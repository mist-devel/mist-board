-------------------------------------------------------------------------------
--
-- SD/MMC interface (SPI-style) for the Apple ][ Emulator
--
-- Michel Stempin (michel.stempin@wanadoo.fr)
-- Working with MMC/SD/SDHC cards
-- 
-- From previous work by:
-- Stephen A. Edwards (sedwards@cs.columbia.edu)
--
-------------------------------------------------------------------------------
-- Principle : (after card init)
--		* read track_size data (26*256 bytes) from sd card to ram buffer when 
-- 	disk_num or track_num change
--    * write track_size data back from ram buffer to sd card when save_track
--    is pulsed to '1'
--
--	   Data read from sd_card always start on 512 bytes boundaries.
--		When actual D64 track starts on 512 bytes boundary sector_offset is set
--    to 0.
--		When actual D64 track starts on 256 bytes boundary sector_offset is set
--    to 1.
--		External ram buffer 'user' should mind sector_offset to retrieve correct
--    data offset.
--
-- 	One should be advised that extra bytes may be read and write out of disk
--    boundary when using last track. With a single sd card user this should 
-- 	lead to no problem since written data always comes from the exact same
--		read place (extra written data will replaced same value on disk).
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;


entity spi_controller is
  generic (
    BLOCK_SIZE  : natural := 512;  -- necessary for block write
    BLOCK_BITS  : natural := 9;
    TRACK_SIZE  : natural := 16#1A00# 
  );

  port (
    -- Card Interface ---------------------------------------------------------
    cs_n           : out std_logic;     -- sd card chip select
    mosi           : out std_logic;     -- data to sd card (master out slave in)
    miso           : in  std_logic;     -- data from sd card (master in slave out)
    sclk           : out std_logic;     -- sd card clock
	 bus_available  : in  std_logic;     -- Spi bus available
    -- Track buffer Interface -------------------------------------------------
    ram_addr       : out std_logic_vector(12 downto 0);
    ram_di         : out std_logic_vector(7 downto 0);
    ram_do         : in  std_logic_vector(7 downto 0);
    ram_we         : out std_logic;
    track_num      : in  std_logic_vector(5 downto 0);  -- Track number (0/1-40)
    disk_num       : in  std_logic_vector(9 downto 0);  -- Which disk image to read
	 busy           : buffer std_logic;
	 save_track     : in  std_logic;   -- pulse to 1 to write ram buffer back to sd card
	 sector_offset  : out std_logic;  -- 0 : sector 0 is at ram adr 0, 1 : sector 0 is at ram adr 256
    -- System Interface -------------------------------------------------------
	 clk            : in  std_logic;  -- System clock	 
    reset          : in  std_logic;
	 -- Debug ------------------------------------------------------------------
	 dbg_state      : out std_logic_vector(7 downto 0)  
  );

end spi_controller;

architecture rtl of spi_controller is

  -----------------------------------------------------------------------------
  -- States of the combined MMC/SD/SDHC reset, track and command FSM
  --
  type states is (
                  -- Reset FSM
                  POWER_UP,
                  RAMP_UP,
                  CHECK_CMD0,
                  CHECK_CMD8,
                  CHECK_CMD55,
                  CHECK_ACMD41,
                  CHECK_CMD1,
                  CHECK_CMD58,
                  CHECK_SET_BLOCKLEN,
                  ERROR,
                  -- Track read FSM
                  IDLE,
                  READ_TRACK,
                  READ_BLOCK_WAIT,
                  READ_BLOCK_DATA,
                  READ_BLOCK_CRC,
                  -- Track write FSM
						WRITE_TRACK,
						WRITE_BLOCK_INIT,
						WRITE_BLOCK_DATA,
						WRITE_BYTE,
						WRITE_BLOCK_WAIT,
                  -- SD command embedded FSM
                  WAIT_NRC,
                  SEND_CMD,
                  RECEIVE_BYTE_WAIT,
                  RECEIVE_BYTE);
  --
  signal state, return_state : states;
  --
  -----------------------------------------------------------------------------

  signal slow_clk : boolean := true;
  signal spi_clk  : std_logic;
  signal sclk_sig : std_logic;
  
  signal current_track_num : std_logic_vector(5 downto 0); -- track number currently in buffer
  signal current_disk_num  : std_logic_vector(9 downto 0); -- disk  number currently in buffer
  signal ram_addr_in       : std_logic_vector(12 downto 0) := (others => '0');

  signal command     : std_logic_vector(5 downto 0);
  signal argument    : std_logic_vector(31 downto 0);
  signal crc7        : std_logic_vector(6 downto 0);
  signal command_out : std_logic_vector(55 downto 0);
  signal recv_bytes  : std_logic_vector(39 downto 0);
  type versions is (MMC, SD1x, SD2x);
  signal version     : versions;
  signal high_capacity : boolean;
  
  -- C64 - 1541 start_sector in D64 format per track number [0..40]
	type start_sector_array_type is array(0 to 40) of integer range 0 to 1023;
	signal start_sector_array : start_sector_array_type := 
		(  0,  0, 21, 42, 63, 84,105,126,147,168,189,210,231,252,273,294,315,336,357,376,395,
		414,433,452,471,490,508,526,544,562,580,598,615,632,649,666,683,700,717,734,751);
	
	signal start_sector_addr : std_logic_vector(9 downto 0); -- addresse of sector within full disk
	
	signal cmd_data_mode : std_logic := '1'; -- 1:command to sd card, 0:data to sd card 
	signal data_to_write : std_logic_vector(7 downto 0) := X"00";
	
begin
  -----------------------------------------------------------------------------
  -- Process var_clkgen
  --
  -- Purpose:
  --   Implements the variable speed clock for MMC compatibility.
  --   If slow_clk is false, spi_clk == CLK_14M, thus SCLK = 7M
  --   If slow_clk is true, spi_clk = CLK_14M / 32 and SCLK = 223.214kHz, which
  --   is between 100kHz and 400kHz, as required for MMC compatibility.
  --
	
  var_clkgen : process (clk, slow_clk)
    variable var_clk : unsigned(4 downto 0) := (others => '0');
  begin
    if slow_clk then
      spi_clk <= var_clk(4);
      if rising_edge(clk) then
        var_clk := var_clk + 1;
      end if;
    else
      spi_clk <= clk;
    end if;
  end process;

  sclk <= sclk_sig;
  --
  -----------------------------------------------------------------------------
 start_sector_addr <= std_logic_vector(to_unsigned(start_sector_array(to_integer(unsigned(track_num))),10));
 sector_offset <= start_sector_addr(0);
  -----------------------------------------------------------------------------
  -- Process sd_fsm
  --
  -- Purpose:
  --   Implements the combined "SD Card init", "track read" and "command" FSMs.
  --
  sd_fsm : process(spi_clk)
  subtype cmd_t is std_logic_vector(5 downto 0);
  constant CMD0   : cmd_t := std_logic_vector(to_unsigned(0, 6));
  constant CMD1   : cmd_t := std_logic_vector(to_unsigned(1, 6));
  constant CMD8   : cmd_t := std_logic_vector(to_unsigned(8, 6));
  constant CMD16  : cmd_t := std_logic_vector(to_unsigned(16, 6));
  constant CMD17  : cmd_t := std_logic_vector(to_unsigned(17, 6));
  constant CMD24  : cmd_t := std_logic_vector(to_unsigned(24, 6));
  constant CMD55  : cmd_t := std_logic_vector(to_unsigned(55, 6));
  constant CMD58  : cmd_t := std_logic_vector(to_unsigned(58, 6));
  constant ACMD41 : cmd_t := std_logic_vector(to_unsigned(41, 6));
  variable counter : unsigned(7 downto 0);
  variable byte_counter : unsigned(BLOCK_BITS downto 0);
  variable lba : std_logic_vector(31 downto 0);

  begin
    if rising_edge(spi_clk) then
      ram_we <= '0';
      if reset = '1' then
			state <= POWER_UP;
        -- Deliberately out of range
			current_track_num <= (others => '1');
			current_disk_num <= (others => '1');
			sclk_sig <= '0';
			slow_clk <= true;
			cs_n <= '1';
			cmd_data_mode <= '1';
			command <= (others => '0');
			argument <= (others => '0');
			crc7 <= (others => '0');
			command_out <= (others => '1');
			counter := TO_UNSIGNED(0, 8);
			byte_counter := TO_UNSIGNED(0, BLOCK_BITS+1);
			ram_addr_in <= (others => '0');
			high_capacity <= false;
			version <= MMC;
			lba := (others => '0');
			busy <= '1';
			dbg_state <= x"00";
	    else
        case state is

          ---------------------------------------------------------------------
          -- SD Card init FSM
          ---------------------------------------------------------------------
          when POWER_UP =>
            counter := TO_UNSIGNED(224, 8);
            state <= RAMP_UP;

          -- Output a series of 74 clock signals (or 1ms delay, whichever is
          -- greater) to wake up the card
          when RAMP_UP =>
            if counter = 0 then
              cs_n <= '0';
              command <= CMD0;
              argument <= (others => '0');
              crc7 <= "1001010";
              return_state <= CHECK_CMD0;
				  
				  if bus_available = '1' then
						state <= WAIT_NRC;
				  end if;
            else
              counter := counter - 1;
              sclk_sig <= not sclk_sig;
            end if;

          -- CMD0: GO_IDLE_STATE ----------------------------------------------
          when CHECK_CMD0 =>
            if recv_bytes(7 downto 0) = x"01" then
              command <= CMD8;
              -- Propose 2.7-3.6V operating voltage and a "10101010" test pattern
              argument <= x"000001aa";
              crc7 <= "1000011";
              return_state <= CHECK_CMD8;
              state <= WAIT_NRC;
            else
              state <= ERROR;
            end if;

          -- CMD8: SEND_IF_COND -----------------------------------------------
          when CHECK_CMD8 =>
            argument <= (others => '0');
            crc7 <= (others => '0');
            if recv_bytes(39 downto 32) <= x"01" then
              -- This is an SD 2.x/3.x Card
              version <= SD2x;
              if recv_bytes(11 downto 8) /= "0001" or recv_bytes(7 downto 0) /= x"aa" then
                -- Operating voltage or pattern check failure
                state <= ERROR;
              else
                command <= CMD55;
                high_capacity <= true;
                return_state <= CHECK_CMD55;
                state <= WAIT_NRC;
              end if;
            else
              -- This is an MMC Card or an SD 1.x Card
              version <= SD1x;
              high_capacity <= false;
              command <= CMD55;
              return_state <= CHECK_CMD55;
              state <= WAIT_NRC;
            end if;

          -- CMD55: APP_CMD ---------------------------------------------------
          when CHECK_CMD55 =>
            if recv_bytes(7 downto 0) = x"01" then
              -- This is an SD Card
              command <= ACMD41;
              if high_capacity then
                -- Ask for HCS (High Capacity Support)
                argument <= x"40000000";
              end if;
              return_state <= CHECK_ACMD41;
              state <= WAIT_NRC;
            else
              -- This is an MMC Card
              version <= MMC;
              command <= CMD1;
              return_state <= CHECK_CMD1;
              state <= WAIT_NRC;
            end if;

          -- ACMD41: SEND_OP_CMD (SD Card) ------------------------------------
          when CHECK_ACMD41 =>
            if recv_bytes(7 downto 0) = x"00" then
              if version = SD2x then
                -- This is an SD 2.x/3.x Card, read OCR
                command <= CMD58;
                argument <= (others => '0');
                return_state <= CHECK_CMD58;
                state <= WAIT_NRC;
              else
                -- This is an SD 1.x Card, no HCS
                command <= CMD16;
                argument <= std_logic_vector(to_unsigned(BLOCK_SIZE, 32));
                return_state <= CHECK_SET_BLOCKLEN;
                state <= WAIT_NRC;
              end if;
            elsif recv_bytes(7 downto 0) = x"01" then
              -- Wait until the card goes out of idle state
              command <= CMD55;
              argument <= (others => '0');
              return_state <= CHECK_CMD55;
              state <= WAIT_NRC;
            else
              -- Found an MMC card that understands CMD55, but not ACMD41
              command <= CMD1;
              return_state <= CHECK_CMD1;
              state <= WAIT_NRC;
            end if;

          -- CMD1: SEND_OP_CMD (MMC Card) -------------------------------------
          when CHECK_CMD1 =>
            if recv_bytes(7 downto 0) <= x"01" then
              command <= CMD16;
              argument <= std_logic_vector(to_unsigned(BLOCK_SIZE, 32));
              return_state <= CHECK_SET_BLOCKLEN;
              state <= WAIT_NRC;
            else
              -- Wait until the card goes out of idle state
              command <= CMD1;
              return_state <= CHECK_CMD1;
              state <= WAIT_NRC;
            end if;

          -- CMD58: READ_OCR --------------------------------------------------
          when CHECK_CMD58 =>
            if recv_bytes(7 downto 0) = x"00" then
              if recv_bytes(30) = '1' then
                high_capacity <= true;
              else
                high_capacity <= false;
              end if;
              command <= CMD16;
              argument <= std_logic_vector(to_unsigned(BLOCK_SIZE, 32));
              return_state <= CHECK_SET_BLOCKLEN;
              state <= WAIT_NRC;
            else
              state <= ERROR;
            end if;

          -- CMD16: SET_BLOCKLEN (BLOCK_SIZE) ---------------------------------
          when CHECK_SET_BLOCKLEN =>
            if recv_bytes(7 downto 0) = x"00" then
              slow_clk <= false;
              state <= IDLE;
            else
              state <= ERROR;
            end if;

          -- Error state ------------------------------------------------------
          when ERROR =>
            sclk_sig <= '0';
            slow_clk <= true;
            cs_n <= '1';

          ---------------------------------------------------------------------
          -- Embedded "read track" FSM
          ---------------------------------------------------------------------
          -- Idle state where we sit waiting for user image/track change or 
			 -- save request
			when IDLE =>
				dbg_state <= x"01";
				
				-- For C64 1541 format D64 image (disk_num) must start every 256Ko --					 
				lba := (X"0" & disk_num & start_sector_addr(9 downto 1) & '0' & X"00");
				if high_capacity then
				-- For SDHC, blocks are addressed by blocks, not bytes
					lba := std_logic_vector(to_unsigned(0,BLOCK_BITS)) & lba(31 downto BLOCK_BITS);
				end if;	

				ram_addr_in <= (others => '0');
				sclk_sig <= '1';

				cs_n <= '0';
				busy <= '0';
				
            if save_track = '1' then 
					if bus_available = '1' then
					   busy <= '1';
						state <= WRITE_TRACK;
					end if;
				else	
					if track_num /= current_track_num or disk_num /= current_disk_num then
						if bus_available = '1' then -- and busy = '1' then
							busy <= '1';
							state <= READ_TRACK;
						end if;
					else
						cs_n <= '1';
					end if;						
				end if;

          -- Read in a whole track into buffer memory -------------------------
          when READ_TRACK =>
				dbg_state <= x"02";
            if ram_addr_in = std_logic_vector(to_unsigned(TRACK_SIZE,13)) then
					state <= IDLE;
					current_track_num <= track_num;
					current_disk_num <= disk_num;
            else
              command <= CMD17;
              argument <= std_logic_vector(lba);
              return_state <= READ_BLOCK_WAIT;
              state <= WAIT_NRC;
            end if;
            
          -- Wait for a 0 bit to signal the start of the block ----------------
          when READ_BLOCK_WAIT =>
				dbg_state <= x"03";
            if sclk_sig = '1' and miso = '0' then
              state <= READ_BLOCK_DATA;
              byte_counter := TO_UNSIGNED(BLOCK_SIZE - 1, BLOCK_BITS+1);
              counter := TO_UNSIGNED(7, 8);
              return_state <= READ_BLOCK_DATA;
              state <= RECEIVE_BYTE;
            end if;
            sclk_sig <= not sclk_sig;            

          -- Read a block of data ---------------------------------------------
          when READ_BLOCK_DATA =>
				dbg_state <= x"04";
            ram_we <= '1';
            ram_addr_in <= ram_addr_in + '1';
				ram_addr <= ram_addr_in;
            if byte_counter = 0 then
              counter := TO_UNSIGNED(7, 8);
              return_state <= READ_BLOCK_CRC;
              state <= RECEIVE_BYTE;
            else
              byte_counter := byte_counter - 1;
              counter := TO_UNSIGNED(7, 8);
              return_state <= READ_BLOCK_DATA;
              state <= RECEIVE_BYTE;
            end if;

          -- Read the block CRC -----------------------------------------------
          when READ_BLOCK_CRC =>
				dbg_state <= x"05";
            counter := TO_UNSIGNED(7, 8);
            return_state <= READ_TRACK;
            if high_capacity then
              lba := lba + 1;
            else
              lba := lba + BLOCK_SIZE;
            end if;
            state <= RECEIVE_BYTE;
				
          ---------------------------------------------------------------------
			 -- write track FSM
          ---------------------------------------------------------------------

          -- write out a whole track from buffer memory -------------------------
          when WRITE_TRACK =>
				dbg_state <= x"11";
				cmd_data_mode <= '1';
            if ram_addr_in = std_logic_vector(to_unsigned(TRACK_SIZE,13)) then
					state <= IDLE;
            else
              command <= CMD24;
              argument <= std_logic_vector(lba);
              return_state <= WRITE_BLOCK_INIT;
					if save_track = '0' then  -- wait cmd released
						state <= WAIT_NRC;
						dbg_state <= x"12";
					end if;
            end if;
            
          -- Wait for a 0 bit to signal the start of the block ----------------
          when WRITE_BLOCK_INIT =>
				dbg_state <= x"13";
				cmd_data_mode <= '0';
				state <= WRITE_BLOCK_DATA;
				byte_counter := TO_UNSIGNED(BLOCK_SIZE +3 , BLOCK_BITS+1);
				counter := TO_UNSIGNED(7, 8);

          -- write a block of data ---------------------------------------------
          when WRITE_BLOCK_DATA =>
				dbg_state <= x"14";
            if byte_counter = 0 then
              return_state <= WRITE_BLOCK_WAIT;
              state <= RECEIVE_BYTE_WAIT;
				else
					if byte_counter = TO_UNSIGNED(1, BLOCK_BITS+1) or 
									byte_counter = TO_UNSIGNED(2, BLOCK_BITS+1) then					
						data_to_write <= X"FF";
					elsif byte_counter = TO_UNSIGNED(BLOCK_SIZE +3 , BLOCK_BITS+1) then
						data_to_write <= X"FE";
						ram_addr <= ram_addr_in;
					else
						data_to_write <= ram_do;
						ram_addr_in <= ram_addr_in + '1';
						ram_addr <= ram_addr_in + '1';
					end if;
					counter := TO_UNSIGNED(7, 8);
					state <= WRITE_BYTE;
					byte_counter := byte_counter - 1;
            end if;

			 -- write one byte --- -----------------------------------------------
          when WRITE_BYTE =>
				dbg_state <= x"15";
            if sclk_sig = '1' then
              if counter = 0 then
                state <= WRITE_BLOCK_DATA;
              else
                counter := counter - 1;
                data_to_write <= data_to_write(6 downto 0) & "1";
              end if;
            end if;
            sclk_sig <= not sclk_sig;

          -- wait end of write  -----------------------------------------------
          when WRITE_BLOCK_WAIT =>
				dbg_state <= x"16";
            if sclk_sig = '1' then
					if miso = '1' then
						dbg_state <= x"17";
						state <= WRITE_TRACK;
						if high_capacity then
							lba := lba + 1;
						else
							lba := lba + BLOCK_SIZE;
						end if;
					end if;
				end if;
            sclk_sig <= not sclk_sig;
								
          ---------------------------------------------------------------------
          -- Embedded "command" FSM
          ---------------------------------------------------------------------
          -- Wait for card response in front of host command ------------------
          when WAIT_NRC =>
				dbg_state <= x"06";
            counter := TO_UNSIGNED(63, 8);
            command_out <= "11111111" & "01" & command & argument & crc7 & "1";
            sclk_sig <= not sclk_sig;
            state <= SEND_CMD;

          -- Send a command to the card ---------------------------------------
          when SEND_CMD =>
				dbg_state <= x"07";
            if sclk_sig = '1' then
              if counter = 0 then
                state <= RECEIVE_BYTE_WAIT;
              else
                counter := counter - 1;
                command_out <= command_out(54 downto 0) & "1";
              end if;
            end if;
            sclk_sig <= not sclk_sig;

          -- Wait for a "0", indicating the first bit of a response -----------
          when RECEIVE_BYTE_WAIT =>
				dbg_state <= x"08";
            if sclk_sig = '1' then
              if miso = '0' then
                recv_bytes <= (others => '0');
                if command = CMD8 or command = CMD58 then
                  -- This is an R7 response, but we already have read bit 39
                  counter := TO_UNSIGNED(38,8);
                else
                  -- This is a data byte or an r1 response, but we already read
                  -- bit 7
                  counter := TO_UNSIGNED(6, 8);
                end if;
                state <= RECEIVE_BYTE;
              end if;
            end if;
            sclk_sig <= not sclk_sig;

          -- Receive a byte ---------------------------------------------------
          when RECEIVE_BYTE =>
				dbg_state <= x"09";
            if sclk_sig = '1' then
              recv_bytes <= recv_bytes(38 downto 0) & miso;
              if counter = 0 then
                state <= return_state;
                ram_di <= recv_bytes(6 downto 0) & miso;
              else
                counter := counter - 1;
              end if;
            end if;
            sclk_sig <= not sclk_sig;
                        
          when others => 
				dbg_state <= x"1F";
				
        end case;
      end if;
    end if;
  end process sd_fsm;

  mosi <= command_out(55) when cmd_data_mode = '1' else data_to_write(7);

end rtl;
