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

use work.mos6526.all;
-- -----------------------------------------------------------------------

entity fpga64_sid_iec is
	generic (
		resetCycles : integer := 4095
	);
	port(
		clk32       : in  std_logic;
		reset_n     : in  std_logic;
		-- keyboard interface (use any ordinairy PS2 keyboard)
		kbd_clk     : in  std_logic;
		kbd_dat     : in  std_logic;
		reset_key   : out std_logic;
		tap_playstop_key : out std_logic;

		-- external memory
		ramAddr     : out unsigned(15 downto 0);
		ramDataIn   : in  unsigned(7 downto 0);
		ramDataOut  : out unsigned(7 downto 0);
		romAddr     : out unsigned(15 downto 0);

		ramCE       : out std_logic;
		ramWe       : out std_logic;
		romCE       : out std_logic;

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
		potA_x      : in  std_logic_vector(7 downto 0);
		potA_y      : in  std_logic_vector(7 downto 0);
		potB_x      : in  std_logic_vector(7 downto 0);
		potB_y      : in  std_logic_vector(7 downto 0);

		-- serial port, for connection to pheripherals
		serioclk    : out std_logic;
		ces         : out std_logic_vector(3 downto 0);

		--Connector to the SID
		SIDclk      : buffer std_logic;
		still       : out unsigned(15 downto 0);
		audio_data_l: out std_logic_vector(17 downto 0);
		audio_data_r: out std_logic_vector(17 downto 0);
		extfilter_en: in  std_logic;
		sid_mode    : in  std_logic_vector(2 downto 0);

		-- IEC
		iec_data_o	: out std_logic;
		iec_data_i	: in  std_logic;
		iec_clk_o	: out std_logic;
		iec_clk_i	: in  std_logic;
		iec_atn_o	: out std_logic;
--		iec_atn_i	: in  std_logic;

		-- user port
		cnt1_in		: in std_logic := '1';
		cnt1_out	: out std_logic;
		cnt2_in		: in std_logic := '1';
		cnt2_out	: out std_logic;
		sp1_in		: in std_logic := '1';
		sp1_out		: out std_logic;
		sp2_in		: in std_logic := '1';
		sp2_out		: out std_logic;
		flag2_n		: in std_logic := '1';
		pc2_n		: out std_logic;
		pa2_in		: in std_logic;
		pa2_out		: out std_logic;
		pb_in 		: in std_logic_vector(7 downto 0);
		pb_out		: out std_logic_vector(7 downto 0);

		-- CIA
		cia_mode    : in std_logic;
		todclk      : in std_logic;

		cass_motor  : out std_logic;
		cass_write  : out std_logic;
		cass_sense  : in  std_logic;
		cass_read   : in  std_logic;

		disk_num    : out std_logic_vector(7 downto 0)
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
	signal cs_rom: std_logic;
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
	signal sid_do6581 : std_logic_vector(7 downto 0);
	signal sid_do8580_l : std_logic_vector(7 downto 0);
	signal sid_do8580_r : std_logic_vector(7 downto 0);
	signal second_sid_en: std_logic;

	-- CIA signals
	signal enableCia_p : std_logic;
	signal enableCia_n : std_logic;
	signal cia1Do: unsigned(7 downto 0);
	signal cia2Do: unsigned(7 downto 0);

-- keyboard
	signal newScanCode: std_logic;
	signal theScanCode: unsigned(7 downto 0);

	-- I/O
	signal cia1_pai: std_logic_vector(7 downto 0);
	signal cia1_pao: std_logic_vector(7 downto 0);
	signal cia1_pbi: std_logic_vector(7 downto 0);
	signal cia1_pbo: std_logic_vector(7 downto 0);
	signal cia2_pai: std_logic_vector(7 downto 0);
	signal cia2_pao: std_logic_vector(7 downto 0);
	signal cia2_pbi: std_logic_vector(7 downto 0);
	signal cia2_pbo: std_logic_vector(7 downto 0);

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

	signal cd4066_sigA  : std_logic_vector(7 downto 0);
	signal cd4066_sigB  : std_logic_vector(7 downto 0);
	signal cd4066_sigC  : std_logic_vector(7 downto 0);
	signal cd4066_sigD  : std_logic_vector(7 downto 0);

	signal clk_1MHz     : std_logic_vector(31 downto 0);
	signal voice_l      : signed(17 downto 0);
	signal voice_r      : signed(17 downto 0);
	signal pot_x        : std_logic_vector(7 downto 0);
	signal pot_y        : std_logic_vector(7 downto 0);
	signal audio_8580_l : std_logic_vector(15 downto 0);
	signal audio_8580_r : std_logic_vector(15 downto 0);

	component sid8580
		port (
			reset    : in std_logic;
			cs       : in std_logic;
			clk32    : in std_logic;
			clk_1MHz : in std_logic;
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
			enableCia_n <= '0';
			enableCia_p <= '0';
			enableCpu <= '0';

			case sysCycle is
			when CYCLE_VIC2 =>
				enableVic <= '1';
			when CYCLE_CPUE =>
				enableVic <= '1';
				enableCpu <= '1';
			when CYCLE_CPUC =>
				enableCia_n <= '1';
			when CYCLE_CPUF =>
				enableCia_p <= '1';
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
		cs_rom => cs_rom,
		cs_ioE => cs_ioE,
		cs_ioF => cs_ioF,
		cs_romL => cs_romL,
		cs_romH => cs_romH,
		cs_UMAXromH => cs_UMAXromH
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

	audio_data_l <= std_logic_vector(voice_l) when sid_mode(1)='0' else
	                (audio_8580_l & "00");
	audio_data_r <= std_logic_vector(voice_l) when sid_mode="000" else
	                std_logic_vector(voice_r) when sid_mode="001" else
	                (audio_8580_r & "00")     when sid_mode="011" else
					(audio_8580_l & "00");
	sid_do <= sid_do6581 when sid_mode(1)='0' else
	          sid_do8580_l when second_sid_en='0' else
			  sid_do8580_r;

	-- CD4066 analogue switch
	cd4066_sigA <= x"FF" when cia1_pao(7) = '0' else potA_x;
	cd4066_sigB <= x"FF" when cia1_pao(7) = '0' else potA_y;
	cd4066_sigC <= x"FF" when cia1_pao(6) = '0' else potB_x;
	cd4066_sigD <= x"FF" when cia1_pao(6) = '0' else potB_y;

	pot_x <= cd4066_sigA and cd4066_sigC;
	pot_y <= cd4066_sigB and cd4066_sigD;

	second_sid_en <= '0' when sid_mode(0) = '0' else
                     '1' when cpuAddr(11 downto 8) = x"4" and cpuAddr(5) = '1' else -- D420
                     '1' when cpuAddr(11 downto 8) = x"5" else -- D500
                     '0';

	sid_6581: entity work.sid_top
	generic map (
		g_num_voices => 11
	)
	port map (
		clock => clk32,
		reset => reset,

		addr => second_sid_en & "00" & cpuAddr(4 downto 0),
		wren => pulseWrRam and phi0_cpu and cs_sid,
		wdata => std_logic_vector(cpuDo),
		rdata => sid_do6581,

		potx => pot_x,
		poty => pot_y,

		comb_wave_l => '0',
		comb_wave_r => '0',

		extfilter_en => extfilter_en,

		start_iter => clk_1MHz(31),
		sample_left => voice_l,
		sample_right => voice_r
	);

	sid_8580_l : sid8580
	port map (
		reset => reset,
		clk32 => clk32,
		clk_1MHz => clk_1MHz(31),
		cs => cs_sid and not second_sid_en,
		we => pulseWrRam and phi0_cpu,
		addr => std_logic_vector(cpuAddr(4 downto 0)),
		data_in => std_logic_vector(cpuDo),
		data_out => sid_do8580_l,
		pot_x => pot_x,
		pot_y => pot_y,
		audio_data => audio_8580_l,
		extfilter_en => extfilter_en
	);

	sid_8580_r : sid8580
	port map (
		reset => reset,
		clk32 => clk32,
		clk_1MHz => clk_1MHz(31),
		cs => cs_sid and second_sid_en,
		we => pulseWrRam and phi0_cpu,
		addr => std_logic_vector(cpuAddr(4 downto 0)),
		data_in => std_logic_vector(cpuDo),
		data_out => sid_do8580_r,
		pot_x => pot_x,
		pot_y => pot_y,
		audio_data => audio_8580_r,
		extfilter_en => extfilter_en
);

-- -----------------------------------------------------------------------
-- CIAs
-- -----------------------------------------------------------------------
	cia1: mos6526
		port map (
			mode => cia_mode,
			clk => clk32,
            phi2_p => enableCia_p,
            phi2_n => enableCia_n,
            res_n => not reset,
            cs_n => not cs_cia1,
            rw => not cpuWe,

            rs => std_logic_vector(cpuAddr)(3 downto 0),
            db_in => std_logic_vector(cpuDo),
            unsigned(db_out) => cia1Do,

            pa_in => std_logic_vector(cia1_pai),
            unsigned(pa_out) => cia1_pao,
            pb_in => std_logic_vector(cia1_pbi),
            unsigned(pb_out) => cia1_pbo,

            flag_n => cass_read,
            sp_in => sp1_in,
            sp_out => sp1_out,
            cnt_in => cnt1_in,
            cnt_out => cnt1_out,

            pc_n => open,
            tod => todclk,
            irq_n => irq_cia1
		);

	cia2: mos6526
		port map (
			mode => cia_mode,
			clk => clk32,
            phi2_p => enableCia_p,
            phi2_n => enableCia_n,
            res_n => not reset,
            cs_n => not cs_cia2,
            rw => not cpuWe,

            rs => std_logic_vector(cpuAddr)(3 downto 0),
            db_in => std_logic_vector(cpuDo),
            unsigned(db_out) => cia2Do,

            pa_in => std_logic_vector(cia2_pai),
            unsigned(pa_out) => cia2_pao,
            pb_in => std_logic_vector(cia2_pbi),
            unsigned(pb_out) => cia2_pbo,

            flag_n => flag2_n,
            sp_in => sp2_in,
            sp_out => sp2_out,
            cnt_in => cnt2_in,
            cnt_out => cnt2_out,

            pc_n => pc2_n,
            tod => todclk,
            irq_n => irq_cia2
		);

-- -----------------------------------------------------------------------
-- 6510 CPU
-- -----------------------------------------------------------------------
	cpu: entity work.cpu_6510

		port map (
			clk => clk32,
			reset => reset,
			enable => enableCpu,
			nmi_n => nmiLoc,
			nmi_ack => nmi_ack,
			irq_n => irqLoc,
			rdy => baLoc,

			di => cpuDi,
			addr => cpuAddr,
			do => cpuDo,
			we => cpuWe,
			
			diIO => cpuIO(7) & cpuIO(6) & cpuIO(5) & cass_sense & cpuIO(3) & "111",
			doIO => cpuIO
		);

	cass_motor <= cpuIO(5);
	cass_write <= cpuIO(3);
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
			pai => unsigned(cia1_pao),
			pbi => unsigned(cia1_pbo),
			std_logic_vector(pao) => cia1_pai,
			std_logic_vector(pbo) => cia1_pbi,

			videoKey => videoKey,
			traceKey => open,
			trace2Key => trace2Key,
			reset_key => reset_key,
			restore_key => restore_key,
			tapPlayStopKey => tap_playstop_key,
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

	iec_data_o <= not cia2_pao(5);
	iec_clk_o <= not cia2_pao(4);
	iec_atn_o <= not cia2_pao(3);
	ramDataOut <= "00" & unsigned(cia2_pao)(5 downto 3) & "000" when sysCycle >= CYCLE_IEC0 and sysCycle <= CYCLE_IEC3 else cpuDo;
	ramAddr <= systemAddr when (phi0_cpu = '1') or (phi0_vic = '1') else (others => '0');
	ramWe <= '0' when sysCycle = CYCLE_IEC2 or sysCycle = CYCLE_IEC3 else not systemWe;
	ramCE <= '0' when sysCycle /= CYCLE_IDLE0 and sysCycle /= CYCLE_IDLE1 and sysCycle /= CYCLE_IDLE2 and 
		   sysCycle /= CYCLE_IDLE3 and sysCycle /= CYCLE_IDLE4 and sysCycle /= CYCLE_IDLE5 and
		   sysCycle /= CYCLE_IDLE6 and sysCycle /= CYCLE_IDLE7 and sysCycle /= CYCLE_IDLE8 and
		   sysCycle /= CYCLE_IEC0 and sysCycle /= CYCLE_IEC1 and sysCycle /= CYCLE_IEC2 and 
		   sysCycle /= CYCLE_IEC3 and sysCycle /= CYCLE_CPU0 and sysCycle /= CYCLE_CPU1 and sysCycle /= CYCLE_CPUF and
			cs_ram = '1' else '1';

	romAddr <= "00" & cpuAddr(14) & cpuAddr(12 downto 0);
	romCE <= '0' when sysCycle /= CYCLE_IDLE0 and sysCycle /= CYCLE_IDLE1 and sysCycle /= CYCLE_IDLE2 and 
		   sysCycle /= CYCLE_IDLE3 and sysCycle /= CYCLE_IDLE4 and sysCycle /= CYCLE_IDLE5 and
		   sysCycle /= CYCLE_IDLE6 and sysCycle /= CYCLE_IDLE7 and sysCycle /= CYCLE_IDLE8 and
		   sysCycle /= CYCLE_IEC0 and sysCycle /= CYCLE_IEC1 and sysCycle /= CYCLE_IEC2 and 
		   sysCycle /= CYCLE_IEC3 and sysCycle /= CYCLE_CPU0 and sysCycle /= CYCLE_CPU1 and sysCycle /= CYCLE_CPUF and
			cs_rom = '1' else '1';

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
				cia2_pai(7) <= iec_data_i and not cia2_pao(5);
				cia2_pai(6) <= iec_clk_i and not cia2_pao(4);
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
	cia2_pai(2) <= pa2_in;
	pa2_out <= cia2_pao(2);
	cia2_pbi <= pb_in;
	pb_out <= cia2_pbo;

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
