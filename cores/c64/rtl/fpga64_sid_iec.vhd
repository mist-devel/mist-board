-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------
--
-- System runs on 32 Mhz (derived from a 50MHz clock). 
-- The VIC-II runs in the first 4 cycles of 32 Mhz clock.
-- The CPU runs in the last 16 cycles. Effective cpu speed is 1 Mhz.
-- 4 additional cycles are used to interface with the C-One IEC port.
-- 
-- -----------------------------------------------------------------------
-- Dar 08/03/2014 
--
-- Based on fpga64_cone
-- add external selection for 15KHz(TV)/31KHz(VGA)
-- add external selection for power on NTSC(60Hz)/PAL(50Hz)
-- add external conection in/out for IEC signal
-- add sid entity 
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

-- -----------------------------------------------------------------------

entity fpga64_sid_iec is
	generic (
		resetCycles : integer := 4095
	);
	port(
		clk32       : in  std_logic;
		reset_n     : in  std_logic;
		c64gs       : in std_logic;
		-- keyboard interface (use any ordinairy PS2 keyboard)
		kbd_clk     : in  std_logic;
		kbd_dat     : in  std_logic;
		reset_key   : out std_logic;
		cart_detach_key : out std_logic;

		-- external memory
		ramAddr     : out unsigned(15 downto 0);
		ramDataIn   : in  unsigned(7 downto 0);
		ramDataOut  : out unsigned(7 downto 0);

		ramCE       : out std_logic;
		ramWe       : out std_logic;

		idle        : out std_logic;

		-- VGA/SCART interface
		ntscInitMode: in  std_logic;
		hsync       : out std_logic;
		vsync       : out std_logic;
		r           : out unsigned(7 downto 0);
		g           : out unsigned(7 downto 0);
		b           : out unsigned(7 downto 0);
		
		-- cartridge port
		game        : in  std_logic;
		exrom       : in  std_logic;
		ioE_rom     : in std_logic;
		ioF_rom     : in std_logic;
		max_ram     : in std_logic;
		irq_n       : inout std_logic;
		nmi_n       : in  std_logic;
		nmi_ack     : out std_logic;
		dma_n       : in  std_logic;
		ba          : out std_logic;
		romL			: out std_logic;													-- cart signals LCA
		romH			: out std_logic;													-- cart signals LCA
		UMAXromH 	: out std_logic;													-- cart signals LCA
		IOE			: out std_logic;													-- cart signals LCA
		IOF			: out std_logic;													-- cart signals LCA
		CPU_hasbus  : out std_logic;													-- CPU has the bus STROBE
		freeze_key  : out std_logic;

		-- joystick interface
		joyA        : in  unsigned(6 downto 0);
		joyB        : in  unsigned(6 downto 0);

		-- serial port, for connection to pheripherals
		serioclk    : out std_logic;
		ces         : out std_logic_vector(3 downto 0);

		--Connector to the SID
		SIDclk      : buffer std_logic;
		still       : out unsigned(15 downto 0);
		audio_data  : out std_logic_vector(15 downto 0);
		extfilter_en: in  std_logic;

		-- IEC
		iec_data_o	: out std_logic;
		iec_data_i	: in  std_logic;
		iec_clk_o	: out std_logic;
		iec_clk_i	: in  std_logic;
		iec_atn_o	: out std_logic;
--		iec_atn_i	: in  std_logic;
		
		disk_num    : out std_logic_vector(7 downto 0);

		c64rom_addr : in std_logic_vector(13 downto 0);
		c64rom_data : in std_logic_vector(7 downto 0);
		c64rom_wr   : in std_logic
);
end fpga64_sid_iec;

-- -----------------------------------------------------------------------

architecture rtl of fpga64_sid_iec is
	-- System state machine
	type sysCycleDef is (
		CYCLE_IDLE0, CYCLE_IDLE1, CYCLE_IDLE2, CYCLE_IDLE3,
		CYCLE_IDLE4, CYCLE_IDLE5, CYCLE_IDLE6, CYCLE_IDLE7,
		CYCLE_IDLE8,
		CYCLE_IEC0, CYCLE_IEC1, CYCLE_IEC2, CYCLE_IEC3,
		CYCLE_VIC0, CYCLE_VIC1, CYCLE_VIC2, CYCLE_VIC3,
		CYCLE_CPU0, CYCLE_CPU1, CYCLE_CPU2, CYCLE_CPU3,
		CYCLE_CPU4, CYCLE_CPU5, CYCLE_CPU6, CYCLE_CPU7,
		CYCLE_CPUP, CYCLE_CPUQ,
		CYCLE_CPU8, CYCLE_CPU9, CYCLE_CPUA, CYCLE_CPUB,
		CYCLE_CPUC, CYCLE_CPUD, CYCLE_CPUE, CYCLE_CPUF
	);

	signal sysCycle : sysCycleDef := sysCycleDef'low;
	signal sysCycleCnt : unsigned(2 downto 0);
	signal phi0_cpu : std_logic;
	signal phi0_vic : std_logic;
	signal cpuHasBus : std_logic;
	
	signal cycleRestart : std_logic;
	signal cycleRestartReg1 : std_logic;
	signal cycleRestartReg2 : std_logic;
	signal cycleRestartEdge : std_logic;

	signal baLoc: std_logic;
	signal irqLoc: std_logic;
	signal nmiLoc: std_logic;

	signal enableCpu: std_logic;
	signal enableVic : std_logic;
	signal enablePixel : std_logic;

	signal irq_cia1: std_logic;
	signal irq_cia2: std_logic;
	signal irq_vic: std_logic;

	signal systemWe: std_logic;
	signal pulseWrRam: std_logic;
	signal pulseWrIo: std_logic;
	signal pulseRd: std_logic;
	signal colorWe : std_logic;
	signal systemAddr: unsigned(15 downto 0);
	signal ramDataReg : unsigned(7 downto 0);

	signal cs_vic: std_logic;
	signal cs_sid: std_logic;
	signal cs_color: std_logic;
	signal cs_cia1: std_logic;
	signal cs_cia2: std_logic;
	signal cs_ram: std_logic;
   signal cs_ioE: std_logic;
   signal cs_ioF: std_logic;	
	signal cs_romL: std_logic;
	signal cs_romH: std_logic;
	signal cs_UMAXromH: std_logic;							-- romH VIC II read flag
	
	signal reset: std_logic := '1';
	signal reset_cnt: integer range 0 to resetCycles := 0;

	signal bankSwitch: unsigned(2 downto 0);
	
	-- SID signals
	signal sid_do : std_logic_vector(7 downto 0);

	-- CIA signals
	signal enableCia : std_logic;
	signal cia1Do: unsigned(7 downto 0);
	signal cia2Do: unsigned(7 downto 0);

-- keyboard
	signal newScanCode: std_logic;
	signal theScanCode: unsigned(7 downto 0);

	-- I/O
	signal cia1_pai: unsigned(7 downto 0);
	signal cia1_pao: unsigned(7 downto 0);
	signal cia1_pad: unsigned(7 downto 0);
	signal cia1_pbi: unsigned(7 downto 0);
	signal cia1_pbo: unsigned(7 downto 0);
	signal cia1_pbd: unsigned(7 downto 0);
	signal cia2_pai: unsigned(7 downto 0);
	signal cia2_pao: unsigned(7 downto 0);
	signal cia2_pad: unsigned(7 downto 0);
	signal cia2_pbi: unsigned(7 downto 0);
	signal cia2_pbo: unsigned(7 downto 0);
	signal cia2_pbd: unsigned(7 downto 0);

	signal debugWE: std_logic := '0';
	signal debugData: unsigned(7 downto 0) := (others => '0');
	signal debugAddr: integer range 2047 downto 0 := 0;

	signal cpuWe: std_logic;
	signal cpuAddr: unsigned(15 downto 0);
	signal cpuDi: unsigned(7 downto 0);
	signal cpuDo: unsigned(7 downto 0);
	signal cpuIO: unsigned(7 downto 0);
	
	signal ioF_ext: std_logic;
	signal ioE_ext: std_logic;
	signal io_data: unsigned(7 downto 0);

	signal vicDi: unsigned(7 downto 0);
	signal vicAddr: unsigned(15 downto 0);
	signal vicData: unsigned(7 downto 0);
	signal lastVicDi : unsigned(7 downto 0);

	signal colorQ : unsigned(3 downto 0);
	signal colorData : unsigned(3 downto 0);

	signal cpuStep : std_logic;
	signal traceKey : std_logic;
	signal trace2Key : std_logic;

	-- video
	signal vicColorIndex : unsigned(3 downto 0);
	signal vicHSync : std_logic;
	signal vicVSync : std_logic;

	signal vgaColorIndex : unsigned(3 downto 0);
	alias vgaColorIndex_int : std_logic_vector is std_logic_vector(vgaColorIndex);
	signal vgaR : unsigned(7 downto 0);
	signal vgaG : unsigned(7 downto 0);
	signal vgaB : unsigned(7 downto 0);
	signal vgaVSync : std_logic;
	signal vgaHSync : std_logic;
	signal debuggerOn : std_logic;
	signal traceStep : std_logic;
   signal scanline : std_logic;
	
	-- config
	signal videoKey : std_logic;
	signal ntscMode : std_logic;
	signal ntscModeInvert : std_logic := '0' ;
	signal restore_key : std_logic;
	
	signal clk_1MHz     : std_logic_vector(31 downto 0);
	signal voice_volume : signed(17 downto 0);
	signal pot_x        : std_logic_vector(7 downto 0);
	signal pot_y        : std_logic_vector(7 downto 0);

	component sid8580
		port (
			reset    : in std_logic;
			clk      : in std_logic;
			ce_1m    : in std_logic;
			we       : in std_logic;
			addr     : in std_logic_vector(4 downto 0);
			data_in  : in std_logic_vector(7 downto 0);
			data_out : out std_logic_vector(7 downto 0);
			pot_x    : in std_logic_vector(7 downto 0);
			pot_y    : in std_logic_vector(7 downto 0);
			audio_data   : out std_logic_vector(15 downto 0);
			extfilter_en : in std_logic
	  );
	end component sid8580;
	
begin
-- -----------------------------------------------------------------------
-- Local signal to outside world
-- -----------------------------------------------------------------------
	ba <= baLoc;

	idle <= '1' when
		(sysCycle = CYCLE_IDLE0) or (sysCycle = CYCLE_IDLE1) or
		(sysCycle = CYCLE_IDLE2) or (sysCycle = CYCLE_IDLE3) or
		(sysCycle = CYCLE_IDLE4) or (sysCycle = CYCLE_IDLE5) or
		(sysCycle = CYCLE_IDLE6) or (sysCycle = CYCLE_IDLE7) or
		(sysCycle = CYCLE_IDLE8) else '0';
	
-- -----------------------------------------------------------------------
-- System state machine, controls bus accesses
-- and triggers enables of other components
-- -----------------------------------------------------------------------
	process(clk32)
	begin
		if rising_edge(clk32) then
			if sysCycle = sysCycleDef'high then
				sysCycle <= sysCycleDef'low;
			elsif sysCycle = CYCLE_CPU6 then
				sysCycle <= CYCLE_CPU8;
			else
				sysCycle <= sysCycleDef'succ(sysCycle);
			end if;
		end if;
	end process;

	iecClock: process(clk32)
	begin
		if rising_edge(clk32) then
			serioclk <= '1';
			if sysCycle = CYCLE_IEC0
			or sysCycle = CYCLE_IEC1 then
				serioclk <= '0'; --for iec write
			end if;	
		end if;
	end process;

	sidClock: process(clk32)
	begin
		if rising_edge(clk32) then
			-- Toggle SIDclk early to compensate for the delay caused by the gbridge
			if sysCycle = CYCLE_VIC3 then
				SIDclk <= '1';
			end if;
			if sysCycle = CYCLE_CPUD then
				SIDclk <= '0';
			end if;
		end if;
	end process;

	-- PHI0/2-clock emulation
	process(clk32)
	begin
		if rising_edge(clk32) then
			if sysCycle = sysCycleDef'pred(CYCLE_CPU0) then
				phi0_cpu <= '1';
				if baLoc = '1' or cpuWe = '1' then
					cpuHasBus <= '1';
				end if;
			end if;
			if sysCycle = sysCycleDef'high then
				phi0_cpu <= '0';
				cpuHasBus <= '0';
			end if;
			if sysCycle = sysCycleDef'pred(CYCLE_VIC0) then
				phi0_vic <= '1';
			end if;
			if sysCycle = CYCLE_VIC3 then
				phi0_vic <= '0';
			end if;
		end if;
	end process;

	process(clk32)
	begin
		if rising_edge(clk32) then
			enableVic <= '0';
			enableCia <= '0';
			enableCpu <= '0';

			case sysCycle is
			when CYCLE_VIC2 =>
				enableVic <= '1';
			when CYCLE_CPUE =>
				enableCia <= '1';
				enableVic <= '1';
				if baLoc = '1'
				or cpuWe = '1' then
					enableCpu <= '1';
				end if;
			when others =>
				null;
			end case;
		end if;
	end process;
	
	hSync <= vicHSync;
	vSync <= vicVSync;

	c64colors: entity work.fpga64_rgbcolor
		port map (
			index => vicColorIndex,
			r => r,
			g => g,
			b => b
		);
-- -----------------------------------------------------------------------
-- Color RAM
-- -----------------------------------------------------------------------
	colorram: entity work.gen_ram
		generic map (
			dWidth => 4,
			aWidth => 10
		)
		port map (
			clk => clk32,
			we => colorWe,
			addr => systemAddr(9 downto 0),
			d => cpuDo(3 downto 0),
			q => colorQ
		);

	process(clk32)
	begin
		if rising_edge(clk32) then
			colorWe <= (cs_color and pulseWrRam);
			colorData <= colorQ;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- PLA and bus-switches
-- -----------------------------------------------------------------------
	buslogic: entity work.fpga64_buslogic
	port map (
		clk => clk32,
		reset => reset,
		c64gs => c64gs,
		cpuHasBus => cpuHasBus,

		bankSwitch => cpuIO(2 downto 0),

		game => game,
		exrom => exrom,
		ioE_rom => ioE_rom,
		ioF_rom => ioF_rom,
		max_ram => max_ram,

		ramData => ramDataReg,
--		ioF_ext => ioF_ext,
--		ioE_ext => ioE_ext,
--		io_data => io_data,

		cpuWe => cpuWe,
		cpuAddr => cpuAddr,
		cpuData => cpuDo,
		vicAddr => vicAddr,
		vicData => vicData,
		sidData => unsigned(sid_do),
		colorData => colorData,
		cia1Data => cia1Do,
		cia2Data => cia2Do,
		lastVicData => lastVicDi,

		systemWe => systemWe,
		systemAddr => systemAddr,
		dataToCpu => cpuDi,
		dataToVic => vicDi,

		cs_vic => cs_vic,
		cs_sid => cs_sid,
		cs_color => cs_color,
		cs_cia1 => cs_cia1,
		cs_cia2 => cs_cia2,
		cs_ram => cs_ram,
		cs_ioE => cs_ioE,
		cs_ioF => cs_ioF,
		cs_romL => cs_romL,
		cs_romH => cs_romH,
		cs_UMAXromH => cs_UMAXromH,

		c64rom_addr => c64rom_addr,
		c64rom_data => c64rom_data,
		c64rom_wr => c64rom_wr
	);

	process(clk32)
	begin
		if rising_edge(clk32) then
			pulseWrRam <= '0';
			pulseWrIo <= '0';
			pulseRd <= '0';
			if cpuWe = '1' then
				if sysCycle = CYCLE_CPUC then
					pulseWrRam <= '1';
				end if;
				if sysCycle = CYCLE_CPUC then
					pulseWrIo <= '1';
				end if;
			else
				if sysCycle = CYCLE_CPUE then
					pulseRd <= '1';
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- VIC-II video interface chip
-- -----------------------------------------------------------------------
	vic: entity work.video_vicii_656x
		generic map (
			registeredAddress => false,
			emulateRefresh => false,
			emulateLightpen => true,
			emulateGraphics => true
		)			
		port map (
			clk => clk32,
			reset => reset,
			enaPixel => enablePixel,
			enaData => enableVic,
			phi => phi0_cpu,
			
			baSync => '0',
			ba => baLoc,

			mode6569 => (not ntscMode),
			mode6567old => '0',
			mode6567R8 => ntscMode,
			mode6572 => '0',
			
			cs => cs_vic,
			we => pulseWrIo,
			rd => pulseRd,
			lp_n => cia1_pbi(4),

			aRegisters => cpuAddr(5 downto 0),
			diRegisters => cpuDo,
			di => vicDi,
			diColor => colorData,
			do => vicData,

			vicAddr => vicAddr(13 downto 0),

			hsync => vicHSync,
			vsync => vicVSync,
			colorIndex => vicColorIndex,

			irq_n => irq_vic
		);

	-- Pixel timing
	process(clk32)
	begin
		if rising_edge(clk32) then
			enablePixel <= '0';
			if sysCycle = CYCLE_VIC2
			or sysCycle = CYCLE_IDLE3      -- IDLE2
			or sysCycle = CYCLE_IDLE7      -- IDLE6
			or sysCycle = CYCLE_IEC2
			or sysCycle = CYCLE_CPU2
			or sysCycle = CYCLE_CPU6
			or sysCycle = CYCLE_CPUB       -- CPUA
  			or sysCycle = CYCLE_CPUF then  -- CPUE
				enablePixel <= '1';
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- SID
-- -----------------------------------------------------------------------
div1m: process(clk32)				-- this process devides 32 MHz to 1MHz (for the SID)
	begin									
		if (rising_edge(clk32)) then			    			
			if (reset = '1') then				
				clk_1MHz 	<= "00000000000000000000000000000001";
			else
				clk_1MHz(31 downto 1) <= clk_1MHz(30 downto 0);
				clk_1MHz(0)           <= clk_1MHz(31);
			end if;
		end if;
	end process;

sid_8580 : sid8580
	port map (
		reset => reset,
		clk => clk32,
		ce_1m => clk_1MHz(31),
		we => pulseWrRam and phi0_cpu and cs_sid,
		addr => std_logic_vector(cpuAddr(4 downto 0)),
		data_in => std_logic_vector(cpuDo),
		data_out => sid_do,
		pot_x => pot_x,
		pot_y => pot_y,
		audio_data => audio_data,
		extfilter_en => extfilter_en
	);
	
	pot_x <= X"FF" when ((cia1_pao(7) and JoyA(5)) or (cia1_pao(6) and JoyB(5))) = '0' else X"00";
	pot_y <= X"FF" when ((cia1_pao(7) and JoyA(6)) or (cia1_pao(6) and JoyB(6))) = '0' else X"00";
-- -----------------------------------------------------------------------
-- CIAs
-- -----------------------------------------------------------------------
	cia1: entity work.cia6526
		port map (
			clk => clk32,
			todClk => vicVSync,
			reset => reset,
			enable => enableCia,
			cs => cs_cia1,
			we => pulseWrIo,
			rd => pulseRd,

			addr => cpuAddr(3 downto 0),
			di => cpuDo,
			do => cia1Do,

			ppai => cia1_pai,
			ppao => cia1_pao,
			ppbi => cia1_pbi,
			ppbo => cia1_pbo,

			flag_n => '1',

			irq_n => irq_cia1
		);

	cia2: entity work.cia6526
		port map (
			clk => clk32,
			todClk => vicVSync,
			reset => reset,
			enable => enableCia,
			cs => cs_cia2,
			we => pulseWrIo,
			rd => pulseRd,

			addr => cpuAddr(3 downto 0),
			di => cpuDo,
			do => cia2Do,

			ppai => cia2_pai,
			ppao => cia2_pao,
			ppbi => cia2_pbi,
			ppbo => cia2_pbo,

			flag_n => '1',

			irq_n => irq_cia2
		);

-- -----------------------------------------------------------------------
-- 6510 CPU
-- -----------------------------------------------------------------------
	cpu: entity work.cpu_6510
		generic map (
			pipelineOpcode => false,
			pipelineAluMux => false,
			pipelineAluOut => false
		)
		port map (
			clk => clk32,
			reset => reset,
			enable => enableCpu,
			nmi_n => nmiLoc,
			nmi_ack => nmi_ack,
			irq_n => irqLoc,

			di => cpuDi,
			addr => cpuAddr,
			do => cpuDo,
			we => cpuWe,
			
			diIO => "00010111",
			doIO => cpuIO,

			debugOpcode => open,
			debugPc => open,
			debugA => open,
			debugX => open,
			debugY => open,
			debugS => open
		);

-- -----------------------------------------------------------------------
-- Keyboard
-- -----------------------------------------------------------------------
	myKeyboard: entity work.io_ps2_keyboard
		port map (
			clk => clk32,
			kbd_clk => kbd_clk,
			kbd_dat => kbd_dat,
			interrupt => newScanCode,
			scanCode => theScanCode
		);

	myKeyboardMatrix: entity work.fpga64_keyboard_matrix
		port map (
			clk => clk32,
			theScanCode => theScanCode,
			newScanCode => newScanCode,

			joyA => (not joyA(4 downto 0)),
			joyB => (not joyB(4 downto 0)),
			pai => cia1_pao,
			pbi => cia1_pbo,
			pao => cia1_pai,
			pbo => cia1_pbi,
			
			videoKey => videoKey,
			traceKey => open,
			trace2Key => trace2Key,
			reset_key => reset_key,
			restore_key => restore_key,
			cart_detach_key => cart_detach_key,					-- cartridge detach key CTRL-D - LCA
			disk_num => disk_num,
			
			backwardsReadingEnabled => '1'
		);

-- -----------------------------------------------------------------------
-- Reset button
-- -----------------------------------------------------------------------
	calcReset: process(clk32)
	begin
		if rising_edge(clk32) then
			if sysCycle = sysCycleDef'high then
				if reset_cnt = resetCycles then
					reset <= '0';
				else
					reset <= '1';
					reset_cnt <= reset_cnt + 1;
				end if;
			end if;
			if reset_n = '0'
			or dma_n = '0' then -- temp reset fix
				reset_cnt <= 0;
			end if;
		end if;
	end process;
	
	-- Video modes
	ntscMode <= ntscInitMode xor ntscModeInvert;
	process(clk32)
	begin
		if rising_edge(clk32) then
			if videoKey = '1' then
				ntscModeInvert <= not ntscModeInvert;
			end if;
		end if;
	end process;

	iec_data_o <= cia2_pao(5);
	iec_clk_o <= cia2_pao(4);
	iec_atn_o <= cia2_pao(3);
	ramDataOut <= "00" & cia2_pao(5 downto 3) & "000" when sysCycle >= CYCLE_IEC0 and sysCycle <= CYCLE_IEC3 else cpuDo;
	ramAddr <= systemAddr when (phi0_cpu = '1') or (phi0_vic = '1') else (others => '0');
	ramWe <= '0' when sysCycle = CYCLE_IEC2 or sysCycle = CYCLE_IEC3 else not systemWe;
	ramCE <= '0' when sysCycle /= CYCLE_IDLE0 and sysCycle /= CYCLE_IDLE1 and sysCycle /= CYCLE_IDLE2 and 
		   sysCycle /= CYCLE_IDLE3 and sysCycle /= CYCLE_IDLE4 and sysCycle /= CYCLE_IDLE5 and
		   sysCycle /= CYCLE_IDLE6 and sysCycle /= CYCLE_IDLE7 and sysCycle /= CYCLE_IDLE8 and
		   sysCycle /= CYCLE_IEC0 and sysCycle /= CYCLE_IEC1 and sysCycle /= CYCLE_IEC2 and 
		   sysCycle /= CYCLE_IEC3 and sysCycle /= CYCLE_CPU0 and sysCycle /= CYCLE_CPU1 and sysCycle /= CYCLE_CPUF and
			cs_ram = '1' else '1';

	process(clk32)
	begin
		if rising_edge(clk32) then
			if sysCycle = CYCLE_CPUD
			or sysCycle = CYCLE_VIC2 then
				ramDataReg <= unsigned(ramDataIn);
			end if;
		end if;
	end process;

--serialBus and SID
	serialBus: process(clk32, sysCycle, cs_sid, cs_ioE, cs_ioF, cs_romL, cs_romH, cpuWe)
	begin
		ces <= "1111";
		if sysCycle = CYCLE_IEC0
		or sysCycle = CYCLE_IEC1
		or sysCycle = CYCLE_IEC2
		or sysCycle = CYCLE_IEC3 then
			ces <= "1011";--iec port
		end if;
		if cs_sid = '1' then
			ces <= "0011"; --SID 1
		end if;
		if cs_romL = '1' then
			ces <= "0000";
		end if;
		if cs_romH = '1' then
			ces <= "0100";
		end if;
		if sysCycle /= CYCLE_CPU0
		and sysCycle /= CYCLE_CPU1
		and sysCycle /= CYCLE_CPUF then
			if cs_ioE = '1' then
				ces <= "0101";
			end if;
			if cs_ioF = '1' then
				ces <= "0001";
			end if;
		end if;
		if rising_edge(clk32) then
			if sysCycle = CYCLE_IEC1 then
				cia2_pai(7) <= iec_data_i;
				cia2_pai(6) <= iec_clk_i;
			end if;	
		end if;
	end process;

	process(clk32)
	begin
		if rising_edge(clk32) then
			if phi0_vic = '1' then
				lastVicDi <= vicDi;
			end if;
		end if;
	end process;

	process(clk32)
	begin
		if rising_edge(clk32) then
			if trace2Key = '1' then
				debuggerOn <= not debuggerOn;
			end if;
		end if;
	end process;

	cia2_pai(5 downto 0) <= cia2_pao(5 downto 0);
	cia2_pbi(7 downto 0) <= cia2_pbo;

-- -----------------------------------------------------------------------
-- VIC bank to address lines
-- -----------------------------------------------------------------------
	vicAddr(14) <= (not cia2_pao(0));
	vicAddr(15) <= (not cia2_pao(1));

-- -----------------------------------------------------------------------
-- Interrupt lines
-- -----------------------------------------------------------------------
	irq_n <= 'Z';
	irqLoc <= irq_cia1 and irq_vic and irq_n; 
	nmiLoc <= irq_cia2 and nmi_n;
	freeze_key <= restore_key;

-- -----------------------------------------------------------------------
-- Dummy silence audio output
-- -----------------------------------------------------------------------
	still <= X"4000";
	
	
-- -----------------------------------------------------------------------
-- Cartridge port lines LCA
-- -----------------------------------------------------------------------
	romL <= cs_romL;
	romH <= cs_romH;
	IOE <= cs_ioE;
	IOF <= cs_ioF;
	UMAXromH <= cs_UMAXromH;
	CPU_hasbus <= cpuHasBus;
end architecture;
