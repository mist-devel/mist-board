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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_controller is
  generic (
    BLOCK_SIZE     : natural := 512;
    BLOCK_BITS     : natural := 9;
--    BLOCK_SIZE     : natural := 256;
--   BLOCK_BITS     : natural := 8;
		
    TRACK_SIZE     : natural := 16#1A00#
  );

  port (
    -- Card Interface ---------------------------------------------------------
    CS_N           : out std_logic;     -- MMC chip select
    MOSI           : out std_logic;     -- Data to card (master out slave in)
    MISO           : in  std_logic;     -- Data from card (master in slave out)
    SCLK           : out std_logic;     -- Card clock
    -- Track buffer Interface -------------------------------------------------
    ram_write_addr : out unsigned(12 downto 0);
    ram_di         : out unsigned(7 downto 0);
    ram_we         : out std_logic;
    change         : in  std_logic;             -- Force reload as disk may have changed
    track          : in  unsigned(5 downto 0);  -- Track number (0-34)
    image          : in  unsigned(9 downto 0);  -- Which disk image to read
		busy           : out std_logic;
    -- System Interface -------------------------------------------------------
    CLK_14M        : in  std_logic;     -- System clock
    reset          : in  std_logic;
		dbg_state      : out std_logic_vector(7 downto 0) -- DTX
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
  signal spi_clk : std_logic;
  signal sclk_sig : std_logic;
  
  signal current_track : unsigned(5 downto 0);
  signal current_image : unsigned(9 downto 0);
--  signal write_addr : unsigned(13 downto 0);
  signal write_addr : unsigned(12 downto 0);

  signal command : std_logic_vector(5 downto 0);
  signal argument : std_logic_vector(31 downto 0);
  signal crc7 : std_logic_vector(6 downto 0);
  signal command_out : std_logic_vector(55 downto 0);
  signal recv_bytes : unsigned(39 downto 0);
  type versions is (MMC, SD1x, SD2x);
  signal version : versions;
  signal high_capacity : boolean;
  
  -- C64 - 1541 start_sector in D64 format per track number [0..40]
	type start_sector_array_type is array(0 to 40) of integer range 0 to 1023;
	constant start_sector_array : start_sector_array_type := 
		(  0,  0, 21, 42, 63, 84,105,126,147,168,189,210,231,252,273,294,315,336,357,376,395,
		414,433,452,471,490,508,526,544,562,580,598,615,632,649,666,683,700,717,734,751);
	
	signal start_sector : std_logic_vector(9 downto 0);
	signal reload : std_logic;
begin

	-- set reload flag whenever "change" rises and clear it once the	
	-- state machine starts reloading the track
	process(change, state)
	begin
	   if(state = READ_TRACK) then
			reload <= '0';
		else
			if rising_edge(change) then
				reload <= '1';
			end if;
		end if;
	end process;

  --ram_write_addr <= write_addr;

  -----------------------------------------------------------------------------
  -- Process var_clkgen
  --
  -- Purpose:
  --   Implements the variable speed clock for MMC compatibility.
  --   If slow_clk is false, spi_clk == CLK_14M, thus SCLK = 7M
  --   If slow_clk is true, spi_clk = CLK_14M / 32 and SCLK = 223.214kHz, which
  --   is between 100kHz and 400kHz, as required for MMC compatibility.
  --
	
  var_clkgen : process (CLK_14M, slow_clk)
    variable var_clk : unsigned(4 downto 0) := (others => '0');
  begin
    if slow_clk then
      spi_clk <= var_clk(4);
      if rising_edge(CLK_14M) then
        var_clk := var_clk + 1;
      end if;
    else
      spi_clk <= CLK_14M;
    end if;
  end process;

  SCLK <= sclk_sig;
  --
  -----------------------------------------------------------------------------
 
 
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
  constant CMD55  : cmd_t := std_logic_vector(to_unsigned(55, 6));
  constant CMD58  : cmd_t := std_logic_vector(to_unsigned(58, 6));
  constant ACMD41 : cmd_t := std_logic_vector(to_unsigned(41, 6));
  variable counter : unsigned(7 downto 0);
  variable byte_counter : unsigned(BLOCK_BITS - 1 downto 0);
  variable lba : unsigned(31 downto 0);

  begin
    if rising_edge(spi_clk) then
      ram_we <= '0';
      if reset = '1' then
        state <= POWER_UP;
        -- Deliberately out of range
        current_track <= (others => '1');
        current_image <= (others => '1');
        sclk_sig <= '0';
        slow_clk <= true;
        CS_N <= '1';
        command <= (others => '0');
        argument <= (others => '0');
        crc7 <= (others => '0');
        command_out <= (others => '1');
        counter := TO_UNSIGNED(0, 8);
        byte_counter := TO_UNSIGNED(0, BLOCK_BITS);
        write_addr <= (others => '0');
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
              CS_N <= '0';
              command <= CMD0;
              argument <= (others => '0');
              crc7 <= "1001010";
              return_state <= CHECK_CMD0;
              state <= WAIT_NRC;
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
            CS_N <= '1';

          ---------------------------------------------------------------------
          -- Embedded "read track" FSM
          ---------------------------------------------------------------------
          -- Idle state where we sit waiting for user image/track requests ----
          when IDLE =>
						dbg_state <= x"01";
            if reload='1' or track /= current_track or image /= current_image then
							----------------------------------------------------------
              -- Compute the LBA (Logical Block Address) from the given
              -- image/track numbers.
              -- Each Apple ][ floppy image contains 35 tracks, each consisting of
              -- 16 x 256-byte sectors.
              -- However, because of inter-sector gaps and address fields in
              -- raw mode, the actual length is set to 0x1A00, so each image is
              -- actually $1A00 bytes * 0x23 tracks = 0x38E00 bytes.
              -- So: lba = image * 0x38E00 + track * 0x1A00
              -- In order to avoid multiplications by constants, we replace
              -- them by direct add/sub of shifted image/track values:
              -- 0x38E00 = 0011 1000 1110 0000 0000
              --         = 0x40000 - 0x8000 + 0x1000 - 0x200
              -- 0x01A00 = 0000 0001 1010 0000 0000
              --         = 0x1000 + 0x800 + 0x200
							------------------------------------------------------
              --lba := ("0000" & image & "000000000000000000") -
              --       (           image &  "000000000000000") +
              --       (               image & "000000000000") -
              --       (                 image  & "000000000") +
              --       (                 track  & "000000000") +
              --       (               track &  "00000000000") +
              --       (              track  & "000000000000");
							------------------------------------------------------

							-- For C64 1541 format D64 image must start every 256Ko --
							lba := (X"0" & image & 
											to_unsigned(start_sector_array(to_integer(unsigned(track))),10) &
											X"00");
										 
				  -- check if track starts at 512 byte boundary ...
				  if to_unsigned(start_sector_array(to_integer(unsigned(track))),10)(0)='1' then
						-- ... no it doesn't. We thus start writing before the begin of the 
						-- buffer so the first 256 bytes are effectively skipped
						write_addr <= "1111100000000";
					else
						-- ... yes it does. We can just load the track to memory
						write_addr <= (others => '0');
				  end if;

              if high_capacity then
					-- TODO: This probably doesn't work in the same process where lba is set
				  
                -- For SDHC, blocks are addressed by blocks, not bytes
                lba := lba srl BLOCK_BITS;
              end if;
--              write_addr <= (others => '0');
              CS_N <= '0';
              state <= READ_TRACK;
              current_track <= track;
              current_image <= image;
							busy <= '1';
            else
              CS_N <= '1';
              sclk_sig <= '1';
							busy <= '0';
            end if;

          -- Read in a whole track into buffer memory -------------------------
          when READ_TRACK =>
						dbg_state <= x"02";
            if write_addr = TRACK_SIZE or write_addr = (TRACK_SIZE-256) then
              state <= IDLE;
            else
              command <= CMD17;
              argument <= std_logic_vector(lba);
              return_state <= READ_BLOCK_WAIT;
              state <= WAIT_NRC;
            end if;
            
          -- Wait for a 0 bit to signal the start of the block ----------------
          when READ_BLOCK_WAIT =>
						dbg_state <= x"03";
            if sclk_sig = '1' and MISO = '0' then
              state <= READ_BLOCK_DATA;
              byte_counter := TO_UNSIGNED(BLOCK_SIZE - 1, BLOCK_BITS);
              counter := TO_UNSIGNED(7, 8);
              return_state <= READ_BLOCK_DATA;
              state <= RECEIVE_BYTE;
            end if;
            sclk_sig <= not sclk_sig;            

          -- Read a block of data ---------------------------------------------
          when READ_BLOCK_DATA =>
						dbg_state <= x"04";
            ram_we <= '1';
            write_addr <= write_addr + 1;
						ram_write_addr <= write_addr;
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
              if MISO = '0' then
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
              recv_bytes <= recv_bytes(38 downto 0) & MISO;
              if counter = 0 then
                state <= return_state;
                ram_di <= recv_bytes(6 downto 0) & MISO;
              else
                counter := counter - 1;
              end if;
            end if;
            sclk_sig <= not sclk_sig;
                        
          when others => null;
        end case;
      end if;
    end if;
  end process sd_fsm;

  MOSI <= command_out(55);

end rtl;
