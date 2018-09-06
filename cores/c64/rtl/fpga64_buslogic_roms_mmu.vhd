-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Copyright 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------

-- -----------------------------------------------------------------------
-- Dar 08/03/2014
--
-- Based on mixing both fpga64_buslogic_roms and fpga64_buslogic_nommu
-- RAM should be external SRAM
-- Basic, Char and Kernel ROMs are included
-- Original Kernel replaced by JiffyDos
-- -----------------------------------------------------------------------

library IEEE;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

entity fpga64_buslogic is
	port (
		clk : in std_logic;
		reset : in std_logic;
		c64gs : in std_logic;

		cpuHasBus : in std_logic;

		ramData: in unsigned(7 downto 0);

		-- 2 CHAREN
		-- 1 HIRAM
		-- 0 LORAM
		bankSwitch: in unsigned(2 downto 0);

		-- From cartridge port
		game    : in std_logic;
		exrom   : in std_logic;
		ioE_rom : in std_logic;
		ioF_rom : in std_logic;
		max_ram : in std_logic;

		c64rom_addr: in std_logic_vector(13 downto 0);
		c64rom_data: in std_logic_vector(7 downto 0);
		c64rom_wr:   in std_logic;

		cpuWe: in std_logic;
		cpuAddr: in unsigned(15 downto 0);
		cpuData: in unsigned(7 downto 0);
		vicAddr: in unsigned(15 downto 0);
		vicData: in unsigned(7 downto 0);
		sidData: in unsigned(7 downto 0);
		colorData: in unsigned(3 downto 0);
		cia1Data: in unsigned(7 downto 0);
		cia2Data: in unsigned(7 downto 0);
		lastVicData : in unsigned(7 downto 0);

		systemWe: out std_logic;
		systemAddr: out unsigned(15 downto 0);
		dataToCpu : out unsigned(7 downto 0);
		dataToVic : out unsigned(7 downto 0);

		cs_vic: out std_logic;
		cs_sid: out std_logic;
		cs_color : out std_logic;
		cs_cia1: out std_logic;
		cs_cia2: out std_logic;
		cs_ram: out std_logic;

		-- To catridge port
		cs_ioE: out std_logic;
		cs_ioF: out std_logic;
		cs_romL : out std_logic;
		cs_romH : out std_logic;
		cs_UMAXromH : out std_logic
	);
end fpga64_buslogic;

-- -----------------------------------------------------------------------

architecture rtl of fpga64_buslogic is
	component fpga64_colorram is
		port (
			clk: in std_logic;
			cs: in std_logic;
			we: in std_logic;

			addr: in unsigned(9 downto 0);
			di: in unsigned(3 downto 0);
			do: out unsigned(3 downto 0)
		);
	end component;

	signal charData: unsigned(7 downto 0);
	signal basicData: unsigned(7 downto 0);
	signal romData: std_logic_vector(7 downto 0);
	signal romData_c64: std_logic_vector(7 downto 0);
	signal romData_c64gs: std_logic_vector(7 downto 0);
	signal c64gs_ena : std_logic := '0';

	signal cs_CharReg : std_logic;
	signal cs_romReg : std_logic;
	signal vicCharReg : std_logic;

	signal cs_ramReg : std_logic;
	signal cs_vicReg : std_logic;
	signal cs_sidReg : std_logic;
	signal cs_colorReg : std_logic;
	signal cs_cia1Reg : std_logic;
	signal cs_cia2Reg : std_logic;
	signal cs_ioEReg : std_logic;
	signal cs_ioFReg : std_logic;
	signal cs_romLReg : std_logic;
	signal cs_romHReg : std_logic;
	signal cs_UMAXromHReg : std_logic;
	signal ultimax : std_logic;

	signal currentAddr: unsigned(15 downto 0);
	
begin
	charrom: entity work.rom_c64_chargen
		port map (
			clk => clk,
			addr => currentAddr(11 downto 0),
			do => charData
		);

	kernelrom: entity work.rom_C64
		port map 
		(
			clock => clk,

			wren => c64rom_wr,
			data => c64rom_data,
			wraddress => c64rom_addr,

			rdaddress => std_logic_vector(cpuAddr(14) & cpuAddr(12 downto 0)),
			q => romData_c64
		);

-- not enough BRAM on MIST FPGA		
--	kernelromGS: entity work.rom_GS64
--		port map 
--		(
--			clock => clk,

--			wren => '0',
--			data => (others => '0'),
--			wraddress => (others => '0'),

--			rdaddress => std_logic_vector(cpuAddr(14) & cpuAddr(12 downto 0)),
--			q => romData_c64gs
--		);
		

	romData <= romData_c64gs when c64gs_ena = '1' else romData_c64;

	process(clk)
	begin
		if rising_edge(clk) then
			if reset = '1' then 
				c64gs_ena <= c64gs;
			end if;
		end if;
	end process;

	--
	--begin
	process(ramData, vicData, sidData, colorData,
           cia1Data, cia2Data, charData, romData,
			  cs_romHReg, cs_romLReg, cs_romReg, cs_CharReg,
			  cs_ramReg, cs_vicReg, cs_sidReg, cs_colorReg,
			  cs_cia1Reg, cs_cia2Reg, lastVicData,
			  cs_ioEReg, cs_ioFReg, ioE_rom, ioF_rom)
	begin
		-- If no hardware is addressed the bus is floating.
		-- It will contain the last data read by the VIC. (if a C64 is shielded correctly)
		dataToCpu <= lastVicData;
		if cs_CharReg = '1' then	
			dataToCpu <= charData;
		elsif cs_romReg = '1' then	
			dataToCpu <= unsigned(romData);
		elsif cs_ramReg = '1' then
			dataToCpu <= ramData;
		elsif cs_vicReg = '1' then
			dataToCpu <= vicData;
		elsif cs_sidReg = '1' then
			dataToCpu <= sidData;
		elsif cs_colorReg = '1' then
			dataToCpu(3 downto 0) <= colorData;
		elsif cs_cia1Reg = '1' then
			dataToCpu <= cia1Data;
		elsif cs_cia2Reg = '1' then
			dataToCpu <= cia2Data;
		elsif cs_romLReg = '1' then
			dataToCpu <= ramData;
		elsif cs_romHReg = '1' then
			dataToCpu <= ramData;
		elsif cs_ioEReg = '1' and ioE_rom = '1' then
			dataToCpu <= ramData;
		elsif cs_ioFReg = '1' and ioF_rom = '1' then
			dataToCpu <= ramData;
		end if;
	end process;

	ultimax <= exrom and (not game);

	process(clk)
	begin
		if rising_edge(clk) then
			currentAddr <= (others => '1'); -- Prevent generation of a latch when neither vic or cpu is using the bus.

			systemWe <= '0';
			vicCharReg <= '0';
			cs_CharReg <= '0';
			cs_romReg <= '0';
			cs_ramReg <= '0';
			cs_vicReg <= '0';
			cs_sidReg <= '0';
			cs_colorReg <= '0';
			cs_cia1Reg <= '0';
			cs_cia2Reg <= '0';
			cs_ioEReg <= '0';
			cs_ioFReg <= '0';
			cs_romLReg <= '0';
			cs_romHReg <= '0';
			cs_UMAXromHReg <= '0';		-- Ultimax flag for the VIC access - LCA

			if (cpuHasBus = '1') then
				-- The 6502 CPU has the bus.					
				currentAddr <= cpuAddr;
				case cpuAddr(15 downto 12) is
				when X"E" | X"F" =>
					if ultimax = '1' and cpuWe = '0' then
						-- ULTIMAX MODE - drop out the kernal - LCA
						cs_romHReg <= '1';
					elsif cpuWe = '0' and bankSwitch(1) = '1' then
						-- Read kernal
						cs_romReg <= '1';
					else
						-- 64Kbyte RAM layout
						cs_ramReg <= '1';
					end if;
				when X"D" =>
					if (ultimax = '0' or max_ram = '1') and bankSwitch(1) = '0' and bankSwitch(0) = '0' then
						-- 64Kbyte RAM layout
						cs_ramReg <= '1';
					elsif ultimax = '1' or bankSwitch(2) = '1' then
						case cpuAddr(11 downto 8) is
							when X"0" | X"1" | X"2" | X"3" =>
								cs_vicReg <= '1';
							when X"4" | X"5" | X"6" | X"7" =>
								cs_sidReg <= '1';
							when X"8" | X"9" | X"A" | X"B" =>
								cs_colorReg <= '1';
							when X"C" =>
								cs_cia1Reg <= '1';
							when X"D" =>
								cs_cia2Reg <= '1';
							when X"E" =>
								cs_ioEReg <= '1';
							when X"F" =>
								cs_ioFReg <= '1';
							when others =>
								null;
						end case;
					else
						-- I/O space turned off. Read from charrom or write to RAM.
						if cpuWe = '0' then
							  cs_CharReg <= '1';
						else
							  cs_ramReg <= '1';
						end if;
					end if;
				when X"A" | X"B" =>
					if exrom = '0' and game = '0' and cpuWe = '0' and bankSwitch(1) = '1' then
						-- Access cartridge with romH
						cs_romHReg <= '1';
					elsif ultimax = '0' and cpuWe = '0' and bankSwitch(1) = '1' and bankSwitch(0) = '1' then
						-- Access basic rom
						-- May need turning off if kernal banked out LCA
						cs_romReg <= '1';
					elsif ultimax = '0' or max_ram = '1' then
						-- If not in Ultimax mode access ram
						cs_ramReg <= '1';
					end if;
				when X"8" | X"9" =>
					if ultimax = '1' then
						-- Ultimax access with romL
						cs_romLReg <= '1';
					elsif exrom = '0' and bankSwitch(1) = '1' and bankSwitch(0) = '1' then
						-- Access cartridge with romL
						cs_romLReg <= '1';
					else
						cs_ramReg <= '1';
					end if;
				when X"0" =>
					cs_ramReg <= '1';
				when others =>
					-- If not in Ultimax mode access ram
					if ultimax = '0' or max_ram = '1' then
						cs_ramReg <= '1';
					end if;
				end case;

				systemWe <= cpuWe;
			else
				-- The VIC-II has the bus.
				currentAddr <= vicAddr;

				if ultimax = '0' and vicAddr(14 downto 12)="001" then
					vicCharReg <= '1';
				elsif ultimax = '1' and vicAddr(13 downto 12)="11" then
					-- ultimax mode changes vic addressing - LCA 
					cs_UMAXromHReg <= '1';
				else
					cs_ramReg <= '1';
				end if;
			end if;
		end if;
	end process;

	cs_ram <= cs_ramReg or cs_romLReg or cs_romHReg or cs_UMAXromHReg;  -- need to keep ram active for cartridges LCA
	cs_vic <= cs_vicReg;
	cs_sid <= cs_sidReg;
	cs_color <= cs_colorReg;
	cs_cia1 <= cs_cia1Reg;
	cs_cia2 <= cs_cia2Reg;
	cs_ioE <= cs_ioEReg;
	cs_ioF <= cs_ioFReg;
	cs_romL <= cs_romLReg;
	cs_romH <= cs_romHReg;
	cs_UMAXromH <= cs_UMAXromHReg;

	dataToVic  <= charData when vicCharReg = '1' else ramData;
	systemAddr <= currentAddr;
end architecture;
