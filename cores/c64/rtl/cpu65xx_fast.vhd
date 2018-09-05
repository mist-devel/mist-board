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
--
-- Table driven, cycle exact 6502/6510 core
--
-- -----------------------------------------------------------------------

library IEEE;
use ieee.std_logic_1164.ALL;
use ieee.std_logic_unsigned.ALL;
use ieee.numeric_std.ALL;

-- -----------------------------------------------------------------------

-- Store Zp    (3) => fetch, cycle2, cycleEnd
-- Store Zp,x  (4) => fetch, cycle2, preWrite, cycleEnd
-- Read  Zp,x  (4) => fetch, cycle2, cycleRead, cycleRead2
-- Rmw   Zp,x  (6) => fetch, cycle2, cycleRead, cycleRead2, cycleRmw, cycleEnd
-- Store Abs   (4) => fetch, cycle2, cycle3, cycleEnd
-- Store Abs,x (5) => fetch, cycle2, cycle3, preWrite, cycleEnd
-- Rts         (6) => fetch, cycle2, cycle3, cycleRead, cycleJump, cycleIncrEnd
-- Rti         (6) => fetch, cycle2, stack1, stack2, stack3, cycleJump
-- Jsr         (6) => fetch, cycle2, .. cycle5, cycle6, cycleJump
-- Jmp abs     (-) => fetch, cycle2, .., cycleJump
-- Jmp (ind)   (-) => fetch, cycle2, .., cycleJump
-- Brk / irq   (6) => fetch, cycle2, stack2, stack3, stack4
-- -----------------------------------------------------------------------

architecture fast of cpu65xx is
-- Statemachine
	type cpuCycles is (
		opcodeFetch,  -- New opcode is read and registers updated
		cycle2,
		cycle3,
		cyclePreIndirect,
		cycleIndirect,
		cycleBranchTaken,
		cycleBranchPage,
		cyclePreRead,     -- Cycle before read while doing zeropage indexed addressing.
		cycleRead,        -- Read cycle
		cycleRead2,       -- Second read cycle after page-boundary crossing.
		cycleRmw,         -- Calculate ALU output for read-modify-write instr.		
		cyclePreWrite,    -- Cycle before write when doing indexed addressing.
		cycleWrite,       -- Write cycle for zeropage or absolute addressing.
		cycleStack1,
		cycleStack2,
		cycleStack3,
		cycleStack4,
		cycleJump,	      -- Last cycle of Jsr, Jmp. Next fetch address is target addr.
		cycleEnd
	);
	signal theCpuCycle : cpuCycles;
	signal nextCpuCycle : cpuCycles;
	signal updateRegisters : boolean;
	signal processIrq : std_logic;
	signal nmiReg: std_logic;
	signal nmiEdge: std_logic;
	signal irqReg : std_logic; -- Delay IRQ input with one clock cycle.
	signal soReg : std_logic; -- SO pin edge detection

-- Opcode decoding
	constant opcUpdateA    : integer := 0;
	constant opcUpdateX    : integer := 1;
	constant opcUpdateY    : integer := 2;
	constant opcUpdateS    : integer := 3;
	constant opcUpdateN    : integer := 4;
	constant opcUpdateV    : integer := 5;
	constant opcUpdateD    : integer := 6;
	constant opcUpdateI    : integer := 7;
	constant opcUpdateZ    : integer := 8;
	constant opcUpdateC    : integer := 9;

	constant opcSecondByte : integer := 10;
	constant opcAbsolute   : integer := 11;
	constant opcZeroPage   : integer := 12;
	constant opcIndirect   : integer := 13;
	constant opcStackAddr  : integer := 14; -- Push/Pop address
	constant opcStackData  : integer := 15; -- Push/Pop status/data
	constant opcJump       : integer := 16;
	constant opcBranch     : integer := 17;
	constant indexX        : integer := 18;
	constant indexY        : integer := 19;
	constant opcStackUp    : integer := 20;
	constant opcWrite      : integer := 21;
	constant opcRmw        : integer := 22;
	constant opcIncrAfter  : integer := 23; -- Insert extra cycle to increment PC (RTS)
	constant opcRti        : integer := 24;
	constant opcIRQ        : integer := 25;

	constant opcInA        : integer := 26;
	constant opcInE        : integer := 27;
	constant opcInX        : integer := 28;
	constant opcInY        : integer := 29;
	constant opcInS        : integer := 30;
	constant opcInT        : integer := 31;
	constant opcInH        : integer := 32;
	constant opcInClear    : integer := 33;
	constant aluMode1From  : integer := 34;
	--
	constant aluMode1To    : integer := 37;
	constant aluMode2From  : integer := 38;
	--
	constant aluMode2To    : integer := 40;
	--
	constant opcInCmp      : integer := 41;
	constant opcInCpx      : integer := 42;
	constant opcInCpy      : integer := 43;
	

	subtype addrDef is unsigned(0 to 15);
	--
	--               is Interrupt  -----------------+
	--          instruction is RTI ----------------+|
	--    PC++ on last cycle (RTS) ---------------+||
	--                      RMW    --------------+|||
	--                     Write   -------------+||||
	--               Pop/Stack up -------------+|||||
	--                    Branch   ---------+  ||||||
	--                      Jump ----------+|  ||||||
	--            Push or Pop data -------+||  ||||||
	--            Push or Pop addr ------+|||  ||||||
	--                   Indirect  -----+||||  ||||||
	--                    ZeroPage ----+|||||  ||||||
	--                    Absolute ---+||||||  ||||||
	--              PC++ on cycle2 --+|||||||  ||||||
	--                               |AZI||JBXY|WM|||
	constant immediate : addrDef := "1000000000000000";
	constant implied   : addrDef := "0000000000000000";
	-- Zero page
	constant readZp    : addrDef := "1010000000000000";
	constant writeZp   : addrDef := "1010000000010000";
	constant rmwZp     : addrDef := "1010000000001000";
	-- Zero page indexed
	constant readZpX   : addrDef := "1010000010000000";
	constant writeZpX  : addrDef := "1010000010010000";
	constant rmwZpX    : addrDef := "1010000010001000";
	constant readZpY   : addrDef := "1010000001000000";
	constant writeZpY  : addrDef := "1010000001010000";
	constant rmwZpY    : addrDef := "1010000001001000";
	-- Zero page indirect
	constant readIndX  : addrDef := "1001000010000000";
	constant writeIndX : addrDef := "1001000010010000";
	constant rmwIndX   : addrDef := "1001000010001000";
	constant readIndY  : addrDef := "1001000001000000";
	constant writeIndY : addrDef := "1001000001010000";
	constant rmwIndY   : addrDef := "1001000001001000";
	--                               |AZI||JBXY|WM||
	-- Absolute
	constant readAbs   : addrDef := "1100000000000000";	
	constant writeAbs  : addrDef := "1100000000010000";	
	constant rmwAbs    : addrDef := "1100000000001000";	
	constant readAbsX  : addrDef := "1100000010000000";	
	constant writeAbsX : addrDef := "1100000010010000";	
	constant rmwAbsX   : addrDef := "1100000010001000";	
	constant readAbsY  : addrDef := "1100000001000000";	
	constant writeAbsY : addrDef := "1100000001010000";	
	constant rmwAbsY   : addrDef := "1100000001001000";	
	-- PHA PHP
	constant push      : addrDef := "0000010000000000";
	-- PLA PLP
	constant pop       : addrDef := "0000010000100000";
	-- Jumps
	constant jsr       : addrDef := "1000101000000000";
	constant jumpAbs   : addrDef := "1000001000000000";
	constant jumpInd   : addrDef := "1100001000000000";
	constant relative  : addrDef := "1000000100000000";
	-- Specials
	constant rts       : addrDef := "0000101000100100";
	constant rti       : addrDef := "0000111000100010";
	constant brk       : addrDef := "1000111000000001";
--	constant        : unsigned(0 to 0) := "0";
	constant xxxxxxxx  : addrDef := "----------0---00";
	
	-- A = accu
	-- E = Accu | 0xEE (for ANE, LXA)
	-- X = index X
	-- Y = index Y
	-- S = Stack pointer
	-- H = indexH
	-- 
	--                                       AEXYSTHc
	constant aluInA   : unsigned(0 to 7) := "10000000";
	constant aluInE   : unsigned(0 to 7) := "01000000";
	constant aluInEXT : unsigned(0 to 7) := "01100100";
	constant aluInET  : unsigned(0 to 7) := "01000100";
	constant aluInX   : unsigned(0 to 7) := "00100000";
	constant aluInXH  : unsigned(0 to 7) := "00100010";
	constant aluInY   : unsigned(0 to 7) := "00010000";
	constant aluInYH  : unsigned(0 to 7) := "00010010";
	constant aluInS   : unsigned(0 to 7) := "00001000";
	constant aluInT   : unsigned(0 to 7) := "00000100";
	constant aluInAX  : unsigned(0 to 7) := "10100000";
	constant aluInAXH : unsigned(0 to 7) := "10100010";
	constant aluInAT  : unsigned(0 to 7) := "10000100";
	constant aluInXT  : unsigned(0 to 7) := "00100100";
	constant aluInST  : unsigned(0 to 7) := "00001100";
	constant aluInSet : unsigned(0 to 7) := "00000000";
	constant aluInClr : unsigned(0 to 7) := "00000001";
	constant aluInXXX : unsigned(0 to 7) := "--------";
	
	-- Most of the aluModes are just like the opcodes.
	-- aluModeInp -> input is output. calculate N and Z
	-- aluModeCmp -> Compare for CMP, CPX, CPY
	-- aluModeFlg -> input to flags needed for PLP, RTI and CLC, SEC, CLV
	-- aluModeInc -> for INC but also INX, INY
	-- aluModeDec -> for DEC but also DEX, DEY

	subtype aluMode1 is unsigned(0 to 3);
	subtype aluMode2 is unsigned(0 to 2);
	subtype aluMode is unsigned(0 to 9);

	-- Logic/Shift ALU
	constant aluModeInp : aluMode1 := "0000";
	constant aluModeP   : aluMode1 := "0001";
	constant aluModeInc : aluMode1 := "0010";
	constant aluModeDec : aluMode1 := "0011";
	constant aluModeFlg : aluMode1 := "0100";
	constant aluModeBit : aluMode1 := "0101";
	-- 0110
	-- 0111
	constant aluModeLsr : aluMode1 := "1000";
	constant aluModeRor : aluMode1 := "1001";
	constant aluModeAsl : aluMode1 := "1010";
	constant aluModeRol : aluMode1 := "1011";
	-- 1100
	-- 1101
	-- 1110
	constant aluModeAnc : aluMode1 := "1111";

	-- Arithmetic ALU
	constant aluModePss : aluMode2 := "000";
	constant aluModeCmp : aluMode2 := "001";
	constant aluModeAdc : aluMode2 := "010";
	constant aluModeSbc : aluMode2 := "011";
	constant aluModeAnd : aluMode2 := "100";
	constant aluModeOra : aluMode2 := "101";
	constant aluModeEor : aluMode2 := "110";
	constant aluModeArr : aluMode2 := "111";


	constant aluInp  : aluMode := aluModeInp & aluModePss & "---";
	constant aluP    : aluMode := aluModeP   & aluModePss & "---";
	constant aluInc  : aluMode := aluModeInc & aluModePss & "---";
	constant aluDec  : aluMode := aluModeDec & aluModePss & "---";
	constant aluFlg  : aluMode := aluModeFlg & aluModePss & "---";
	constant aluBit  : aluMode := aluModeBit & aluModeAnd & "---";
	constant aluRor  : aluMode := aluModeRor & aluModePss & "---";
	constant aluLsr  : aluMode := aluModeLsr & aluModePss & "---";
	constant aluRol  : aluMode := aluModeRol & aluModePss & "---";
	constant aluAsl  : aluMode := aluModeAsl & aluModePss & "---";

	constant aluCmp  : aluMode := aluModeInp & aluModeCmp & "100";
	constant aluCpx  : aluMode := aluModeInp & aluModeCmp & "010";
	constant aluCpy  : aluMode := aluModeInp & aluModeCmp & "001";
	constant aluAdc  : aluMode := aluModeInp & aluModeAdc & "---";
	constant aluSbc  : aluMode := aluModeInp & aluModeSbc & "---";
	constant aluAnd  : aluMode := aluModeInp & aluModeAnd & "---";
	constant aluOra  : aluMode := aluModeInp & aluModeOra & "---";
	constant aluEor  : aluMode := aluModeInp & aluModeEor & "---";
	
	constant aluSlo  : aluMode := aluModeAsl & aluModeOra & "---";
	constant aluSre  : aluMode := aluModeLsr & aluModeEor & "---";
	constant aluRra  : aluMode := aluModeRor & aluModeAdc & "---";
	constant aluRla  : aluMode := aluModeRol & aluModeAnd & "---";
	constant aluDcp  : aluMode := aluModeDec & aluModeCmp & "100";
	constant aluIsc  : aluMode := aluModeInc & aluModeSbc & "---";
	constant aluAnc  : aluMode := aluModeAnc & aluModeAnd & "---";
	constant aluArr  : aluMode := aluModeRor & aluModeArr & "---";
	constant aluSbx  : aluMode := aluModeInp & aluModeCmp & "110";
	
	constant aluXXX  : aluMode := (others => '-');


	-- Stack operations. Push/Pop/None
	constant stackInc : unsigned(0 to 0) := "0";
	constant stackDec : unsigned(0 to 0) := "1";
	constant stackXXX : unsigned(0 to 0) := "-";

	subtype decodedBitsDef is unsigned(0 to 43);
	type opcodeInfoTableDef is array(0 to 255) of decodedBitsDef;
	constant opcodeInfoTable : opcodeInfoTableDef := (
	-- +------- Update register A
	-- |+------ Update register X
	-- ||+----- Update register Y
	-- |||+---- Update register S
	-- ||||       +-- Update Flags
	-- ||||       |   
	-- ||||      _|__ 
	-- ||||     /    \
	-- AXYS     NVDIZC    addressing  aluInput  aluMode
	  "0000" & "000100" & brk       & aluInXXX & aluP,   -- 00 BRK
	  "1000" & "100010" & readIndX  & aluInT   & aluOra, -- 01 ORA (zp,x)
	  "----" & "------" & xxxxxxxx  & aluInXXX & aluXXX, -- 02 *** JAM ***
	  "1000" & "100011" & rmwIndX   & aluInT   & aluSlo, -- 03 iSLO (zp,x)
	  "0000" & "000000" & readZp    & aluInXXX & aluXXX, -- 04 iNOP zp
	  "1000" & "100010" & readZp    & aluInT   & aluOra, -- 05 ORA zp
	  "0000" & "100011" & rmwZp     & aluInT   & aluAsl, -- 06 ASL zp
	  "1000" & "100011" & rmwZp     & aluInT   & aluSlo, -- 07 iSLO zp
	  "0000" & "000000" & push      & aluInXXX & aluP,   -- 08 PHP
	  "1000" & "100010" & immediate & aluInT   & aluOra, -- 09 ORA imm
	  "1000" & "100011" & implied   & aluInA   & aluAsl, -- 0A ASL accu
	  "1000" & "100011" & immediate & aluInT   & aluAnc, -- 0B iANC imm
	  "0000" & "000000" & readAbs   & aluInXXX & aluXXX, -- 0C iNOP abs
	  "1000" & "100010" & readAbs   & aluInT   & aluOra, -- 0D ORA abs
	  "0000" & "100011" & rmwAbs    & aluInT   & aluAsl, -- 0E ASL abs
	  "1000" & "100011" & rmwAbs    & aluInT   & aluSlo, -- 0F iSLO abs
	  "0000" & "000000" & relative  & aluInXXX & aluXXX, -- 10 BPL
	  "1000" & "100010" & readIndY  & aluInT   & aluOra, -- 11 ORA (zp),y
	  "----" & "------" & xxxxxxxx  & aluInXXX & aluXXX, -- 12 *** JAM ***
	  "1000" & "100011" & rmwIndY   & aluInT   & aluSlo, -- 13 iSLO (zp),y
	  "0000" & "000000" & readZpX   & aluInXXX & aluXXX, -- 14 iNOP zp,x
	  "1000" & "100010" & readZpX   & aluInT   & aluOra, -- 15 ORA zp,x
	  "0000" & "100011" & rmwZpX    & aluInT   & aluAsl, -- 16 ASL zp,x
	  "1000" & "100011" & rmwZpX    & aluInT   & aluSlo, -- 17 iSLO zp,x
	  "0000" & "000001" & implied   & aluInClr & aluFlg, -- 18 CLC
	  "1000" & "100010" & readAbsY  & aluInT   & aluOra, -- 19 ORA abs,y
	  "0000" & "000000" & implied   & aluInXXX & aluXXX, -- 1A iNOP implied
	  "1000" & "100011" & rmwAbsY   & aluInT   & aluSlo, -- 1B iSLO abs,y
	  "0000" & "000000" & readAbsX  & aluInXXX & aluXXX, -- 1C iNOP abs,x
	  "1000" & "100010" & readAbsX  & aluInT   & aluOra, -- 1D ORA abs,x
	  "0000" & "100011" & rmwAbsX   & aluInT   & aluAsl, -- 1E ASL abs,x
	  "1000" & "100011" & rmwAbsX   & aluInT   & aluSlo, -- 1F iSLO abs,x
	-- AXYS     NVDIZC    addressing  aluInput  aluMode
	  "0000" & "000000" & jsr       & aluInXXX & aluXXX, -- 20 JSR
	  "1000" & "100010" & readIndX  & aluInT   & aluAnd, -- 21 AND (zp,x)
	  "----" & "------" & xxxxxxxx  & aluInXXX & aluXXX, -- 22 *** JAM ***
	  "1000" & "100011" & rmwIndX   & aluInT   & aluRla, -- 23 iRLA (zp,x)
	  "0000" & "110010" & readZp    & aluInT   & aluBit, -- 24 BIT zp
	  "1000" & "100010" & readZp    & aluInT   & aluAnd, -- 25 AND zp
	  "0000" & "100011" & rmwZp     & aluInT   & aluRol, -- 26 ROL zp
	  "1000" & "100011" & rmwZp     & aluInT   & aluRla, -- 27 iRLA zp
	  "0000" & "111111" & pop       & aluInT   & aluFlg, -- 28 PLP
	  "1000" & "100010" & immediate & aluInT   & aluAnd, -- 29 AND imm
	  "1000" & "100011" & implied   & aluInA   & aluRol, -- 2A ROL accu
	  "1000" & "100011" & immediate & aluInT   & aluAnc, -- 2B iANC imm
	  "0000" & "110010" & readAbs   & aluInT   & aluBit, -- 2C BIT abs
	  "1000" & "100010" & readAbs   & aluInT   & aluAnd, -- 2D AND abs
	  "0000" & "100011" & rmwAbs    & aluInT   & aluRol, -- 2E ROL abs
	  "1000" & "100011" & rmwAbs    & aluInT   & aluRla, -- 2F iRLA abs
	  "0000" & "000000" & relative  & aluInXXX & aluXXX, -- 30 BMI
	  "1000" & "100010" & readIndY  & aluInT   & aluAnd, -- 31 AND (zp),y
	  "----" & "------" & xxxxxxxx  & aluInXXX & aluXXX, -- 32 *** JAM ***
	  "1000" & "100011" & rmwIndY   & aluInT   & aluRla, -- 33 iRLA (zp),y
	  "0000" & "000000" & readZpX   & aluInXXX & aluXXX, -- 34 iNOP zp,x
	  "1000" & "100010" & readZpX   & aluInT   & aluAnd, -- 35 AND zp,x
	  "0000" & "100011" & rmwZpX    & aluInT   & aluRol, -- 36 ROL zp,x
	  "1000" & "100011" & rmwZpX    & aluInT   & aluRla, -- 37 iRLA zp,x
	  "0000" & "000001" & implied   & aluInSet & aluFlg, -- 38 SEC
	  "1000" & "100010" & readAbsY  & aluInT   & aluAnd, -- 39 AND abs,y
	  "0000" & "000000" & implied   & aluInXXX & aluXXX, -- 3A iNOP implied
	  "1000" & "100011" & rmwAbsY   & aluInT   & aluRla, -- 3B iRLA abs,y
	  "0000" & "000000" & readAbsX  & aluInXXX & aluXXX, -- 3C iNOP abs,x
	  "1000" & "100010" & readAbsX  & aluInT   & aluAnd, -- 3D AND abs,x
	  "0000" & "100011" & rmwAbsX   & aluInT   & aluRol, -- 3E ROL abs,x
	  "1000" & "100011" & rmwAbsX   & aluInT   & aluRla, -- 3F iRLA abs,x
	-- AXYS     NVDIZC    addressing  aluInput  aluMode
	  "0000" & "111111" & rti       & aluInT   & aluFlg, -- 40 RTI
	  "1000" & "100010" & readIndX  & aluInT   & aluEor, -- 41 EOR (zp,x)
	  "----" & "------" & xxxxxxxx  & aluInXXX & aluXXX, -- 42 *** JAM ***
	  "1000" & "100011" & rmwIndX   & aluInT   & aluSre, -- 43 iSRE (zp,x)
	  "0000" & "000000" & readZp    & aluInXXX & aluXXX, -- 44 iNOP zp
	  "1000" & "100010" & readZp    & aluInT   & aluEor, -- 45 EOR zp
	  "0000" & "100011" & rmwZp     & aluInT   & aluLsr, -- 46 LSR zp
	  "1000" & "100011" & rmwZp     & aluInT   & aluSre, -- 47 iSRE zp
	  "0000" & "000000" & push      & aluInA   & aluInp, -- 48 PHA
	  "1000" & "100010" & immediate & aluInT   & aluEor, -- 49 EOR imm
	  "1000" & "100011" & implied   & aluInA   & aluLsr, -- 4A LSR accu
	  "1000" & "100011" & immediate & aluInAT  & aluLsr, -- 4B iALR imm
	  "0000" & "000000" & jumpAbs   & aluInXXX & aluXXX, -- 4C JMP abs
	  "1000" & "100010" & readAbs   & aluInT   & aluEor, -- 4D EOR abs
	  "0000" & "100011" & rmwAbs    & aluInT   & aluLsr, -- 4E LSR abs
	  "1000" & "100011" & rmwAbs    & aluInT   & aluSre, -- 4F iSRE abs
	  "0000" & "000000" & relative  & aluInXXX & aluXXX, -- 50 BVC
	  "1000" & "100010" & readIndY  & aluInT   & aluEor, -- 51 EOR (zp),y
	  "----" & "------" & xxxxxxxx  & aluInXXX & aluXXX, -- 52 *** JAM ***
	  "1000" & "100011" & rmwIndY   & aluInT   & aluSre, -- 53 iSRE (zp),y
	  "0000" & "000000" & readZpX   & aluInXXX & aluXXX, -- 54 iNOP zp,x
	  "1000" & "100010" & readZpX   & aluInT   & aluEor, -- 55 EOR zp,x
	  "0000" & "100011" & rmwZpX    & aluInT   & aluLsr, -- 56 LSR zp,x
	  "1000" & "100011" & rmwZpX    & aluInT   & aluSre, -- 57 SRE zp,x
	  "0000" & "000100" & implied   & aluInClr & aluXXX, -- 58 CLI
	  "1000" & "100010" & readAbsY  & aluInT   & aluEor, -- 59 EOR abs,y
	  "0000" & "000000" & implied   & aluInXXX & aluXXX, -- 5A iNOP implied
	  "1000" & "100011" & rmwAbsY   & aluInT   & aluSre, -- 5B iSRE abs,y
	  "0000" & "000000" & readAbsX  & aluInXXX & aluXXX, -- 5C iNOP abs,x
	  "1000" & "100010" & readAbsX  & aluInT   & aluEor, -- 5D EOR abs,x
	  "0000" & "100011" & rmwAbsX   & aluInT   & aluLsr, -- 5E LSR abs,x
	  "1000" & "100011" & rmwAbsX   & aluInT   & aluSre, -- 5F SRE abs,x
	-- AXYS     NVDIZC    addressing  aluInput  aluMode
	  "0000" & "000000" & rts       & aluInXXX & aluXXX, -- 60 RTS
	  "1000" & "110011" & readIndX  & aluInT   & aluAdc, -- 61 ADC (zp,x)
	  "----" & "------" & xxxxxxxx  & aluInXXX & aluXXX, -- 62 *** JAM ***
	  "1000" & "110011" & rmwIndX   & aluInT   & aluRra, -- 63 iRRA (zp,x)
	  "0000" & "000000" & readZp    & aluInXXX & aluXXX, -- 64 iNOP zp
	  "1000" & "110011" & readZp    & aluInT   & aluAdc, -- 65 ADC zp
	  "0000" & "100011" & rmwZp     & aluInT   & aluRor, -- 66 ROR zp
	  "1000" & "110011" & rmwZp     & aluInT   & aluRra, -- 67 iRRA zp
	  "1000" & "100010" & pop       & aluInT   & aluInp, -- 68 PLA
	  "1000" & "110011" & immediate & aluInT   & aluAdc, -- 69 ADC imm
	  "1000" & "100011" & implied   & aluInA   & aluRor, -- 6A ROR accu
	  "1000" & "110011" & immediate & aluInAT  & aluArr, -- 6B iARR imm
	  "0000" & "000000" & jumpInd   & aluInXXX & aluXXX, -- 6C JMP indirect
	  "1000" & "110011" & readAbs   & aluInT   & aluAdc, -- 6D ADC abs
	  "0000" & "100011" & rmwAbs    & aluInT   & aluRor, -- 6E ROR abs
	  "1000" & "110011" & rmwAbs    & aluInT   & aluRra, -- 6F iRRA abs
	  "0000" & "000000" & relative  & aluInXXX & aluXXX, -- 70 BVS
	  "1000" & "110011" & readIndY  & aluInT   & aluAdc, -- 71 ADC (zp),y
	  "----" & "------" & xxxxxxxx  & aluInXXX & aluXXX, -- 72 *** JAM ***
	  "1000" & "110011" & rmwIndY   & aluInT   & aluRra, -- 73 iRRA (zp),y
	  "0000" & "000000" & readZpX   & aluInXXX & aluXXX, -- 74 iNOP zp,x
	  "1000" & "110011" & readZpX   & aluInT   & aluAdc, -- 75 ADC zp,x
	  "0000" & "100011" & rmwZpX    & aluInT   & aluRor, -- 76 ROR zp,x
	  "1000" & "110011" & rmwZpX    & aluInT   & aluRra, -- 77 iRRA zp,x
	  "0000" & "000100" & implied   & aluInSet & aluXXX, -- 78 SEI
	  "1000" & "110011" & readAbsY  & aluInT   & aluAdc, -- 79 ADC abs,y
	  "0000" & "000000" & implied   & aluInXXX & aluXXX, -- 7A iNOP implied
	  "1000" & "110011" & rmwAbsY   & aluInT   & aluRra, -- 7B iRRA abs,y
	  "0000" & "000000" & readAbsX  & aluInXXX & aluXXX, -- 7C iNOP abs,x
	  "1000" & "110011" & readAbsX  & aluInT   & aluAdc, -- 7D ADC abs,x
	  "0000" & "100011" & rmwAbsX   & aluInT   & aluRor, -- 7E ROR abs,x
	  "1000" & "110011" & rmwAbsX   & aluInT   & aluRra, -- 7F iRRA abs,x
	-- AXYS     NVDIZC    addressing  aluInput  aluMode
	  "0000" & "000000" & immediate & aluInXXX & aluXXX, -- 80 iNOP imm
	  "0000" & "000000" & writeIndX & aluInA   & aluInp, -- 81 STA (zp,x)
	  "0000" & "000000" & immediate & aluInXXX & aluXXX, -- 82 iNOP imm
	  "0000" & "000000" & writeIndX & aluInAX  & aluInp, -- 83 iSAX (zp,x)
	  "0000" & "000000" & writeZp   & aluInY   & aluInp, -- 84 STY zp
	  "0000" & "000000" & writeZp   & aluInA   & aluInp, -- 85 STA zp
	  "0000" & "000000" & writeZp   & aluInX   & aluInp, -- 86 STX zp
	  "0000" & "000000" & writeZp   & aluInAX  & aluInp, -- 87 iSAX zp
	  "0010" & "100010" & implied   & aluInY   & aluDec, -- 88 DEY
	  "0000" & "000000" & immediate & aluInXXX & aluXXX, -- 84 iNOP imm
	  "1000" & "100010" & implied   & aluInX   & aluInp, -- 8A TXA
	  "1000" & "100010" & immediate & aluInEXT & aluInp, -- 8B iANE imm
	  "0000" & "000000" & writeAbs  & aluInY   & aluInp, -- 8C STY abs
	  "0000" & "000000" & writeAbs  & aluInA   & aluInp, -- 8D STA abs
	  "0000" & "000000" & writeAbs  & aluInX   & aluInp, -- 8E STX abs
	  "0000" & "000000" & writeAbs  & aluInAX  & aluInp, -- 8F iSAX abs
	  "0000" & "000000" & relative  & aluInXXX & aluXXX, -- 90 BCC
	  "0000" & "000000" & writeIndY & aluInA   & aluInp, -- 91 STA (zp),y
	  "----" & "------" & xxxxxxxx  & aluInXXX & aluXXX, -- 92 *** JAM ***
	  "0000" & "000000" & writeIndY & aluInAXH & aluInp, -- 93 iAHX (zp),y
	  "0000" & "000000" & writeZpX  & aluInY   & aluInp, -- 94 STY zp,x
	  "0000" & "000000" & writeZpX  & aluInA   & aluInp, -- 95 STA zp,x
	  "0000" & "000000" & writeZpY  & aluInX   & aluInp, -- 96 STX zp,y
	  "0000" & "000000" & writeZpY  & aluInAX  & aluInp, -- 97 iSAX zp,y
	  "1000" & "100010" & implied   & aluInY   & aluInp, -- 98 TYA
	  "0000" & "000000" & writeAbsY & aluInA   & aluInp, -- 99 STA abs,y
	  "0001" & "000000" & implied   & aluInX   & aluInp, -- 9A TXS
	  "0001" & "000000" & writeAbsY & aluInAXH & aluInp, -- 9B iSHS abs,y
	  "0000" & "000000" & writeAbsX & aluInYH  & aluInp, -- 9C iSHY abs,x
	  "0000" & "000000" & writeAbsX & aluInA   & aluInp, -- 9D STA abs,x
	  "0000" & "000000" & writeAbsY & aluInXH  & aluInp, -- 9E iSHX abs,y
	  "0000" & "000000" & writeAbsY & aluInAXH & aluInp, -- 9F iAHX abs,y
	-- AXYS     NVDIZC    addressing  aluInput  aluMode
	  "0010" & "100010" & immediate & aluInT   & aluInp, -- A0 LDY imm
	  "1000" & "100010" & readIndX  & aluInT   & aluInp, -- A1 LDA (zp,x)
	  "0100" & "100010" & immediate & aluInT   & aluInp, -- A2 LDX imm
	  "1100" & "100010" & readIndX  & aluInT   & aluInp, -- A3 LAX (zp,x)
	  "0010" & "100010" & readZp    & aluInT   & aluInp, -- A4 LDY zp
	  "1000" & "100010" & readZp    & aluInT   & aluInp, -- A5 LDA zp
	  "0100" & "100010" & readZp    & aluInT   & aluInp, -- A6 LDX zp
	  "1100" & "100010" & readZp    & aluInT   & aluInp, -- A7 iLAX zp
	  "0010" & "100010" & implied   & aluInA   & aluInp, -- A8 TAY
	  "1000" & "100010" & immediate & aluInT   & aluInp, -- A9 LDA imm
	  "0100" & "100010" & implied   & aluInA   & aluInp, -- AA TAX
	  "1100" & "100010" & immediate & aluInET  & aluInp, -- AB iLXA imm
	  "0010" & "100010" & readAbs   & aluInT   & aluInp, -- AC LDY abs
	  "1000" & "100010" & readAbs   & aluInT   & aluInp, -- AD LDA abs
	  "0100" & "100010" & readAbs   & aluInT   & aluInp, -- AE LDX abs
	  "1100" & "100010" & readAbs   & aluInT   & aluInp, -- AF iLAX abs
	  "0000" & "000000" & relative  & aluInXXX & aluXXX, -- B0 BCS
	  "1000" & "100010" & readIndY  & aluInT   & aluInp, -- B1 LDA (zp),y
	  "----" & "------" & xxxxxxxx  & aluInXXX & aluXXX, -- B2 *** JAM ***
	  "1100" & "100010" & readIndY  & aluInT   & aluInp, -- B3 iLAX (zp),y
	  "0010" & "100010" & readZpX   & aluInT   & aluInp, -- B4 LDY zp,x
	  "1000" & "100010" & readZpX   & aluInT   & aluInp, -- B5 LDA zp,x
	  "0100" & "100010" & readZpY   & aluInT   & aluInp, -- B6 LDX zp,y
	  "1100" & "100010" & readZpY   & aluInT   & aluInp, -- B7 iLAX zp,y
	  "0000" & "010000" & implied   & aluInClr & aluFlg, -- B8 CLV
	  "1000" & "100010" & readAbsY  & aluInT   & aluInp, -- B9 LDA abs,y
	  "0100" & "100010" & implied   & aluInS   & aluInp, -- BA TSX
	  "1101" & "100010" & readAbsY  & aluInST  & aluInp, -- BB iLAS abs,y
	  "0010" & "100010" & readAbsX  & aluInT   & aluInp, -- BC LDY abs,x
	  "1000" & "100010" & readAbsX  & aluInT   & aluInp, -- BD LDA abs,x
	  "0100" & "100010" & readAbsY  & aluInT   & aluInp, -- BE LDX abs,y
	  "1100" & "100010" & readAbsY  & aluInT   & aluInp, -- BF iLAX abs,y
	-- AXYS     NVDIZC    addressing  aluInput  aluMode
	  "0000" & "100011" & immediate & aluInT   & aluCpy, -- C0 CPY imm
	  "0000" & "100011" & readIndX  & aluInT   & aluCmp, -- C1 CMP (zp,x)
	  "0000" & "000000" & immediate & aluInXXX & aluXXX, -- C2 iNOP imm
	  "0000" & "100011" & rmwIndX   & aluInT   & aluDcp, -- C3 iDCP (zp,x)
	  "0000" & "100011" & readZp    & aluInT   & aluCpy, -- C4 CPY zp
	  "0000" & "100011" & readZp    & aluInT   & aluCmp, -- C5 CMP zp
	  "0000" & "100010" & rmwZp     & aluInT   & aluDec, -- C6 DEC zp
	  "0000" & "100011" & rmwZp     & aluInT   & aluDcp, -- C7 iDCP zp
	  "0010" & "100010" & implied   & aluInY   & aluInc, -- C8 INY
	  "0000" & "100011" & immediate & aluInT   & aluCmp, -- C9 CMP imm
	  "0100" & "100010" & implied   & aluInX   & aluDec, -- CA DEX
	  "0100" & "100011" & immediate & aluInT   & aluSbx, -- CB SBX imm
	  "0000" & "100011" & readAbs   & aluInT   & aluCpy, -- CC CPY abs
	  "0000" & "100011" & readAbs   & aluInT   & aluCmp, -- CD CMP abs
	  "0000" & "100010" & rmwAbs    & aluInT   & aluDec, -- CE DEC abs
	  "0000" & "100011" & rmwAbs    & aluInT   & aluDcp, -- CF iDCP abs
	  "0000" & "000000" & relative  & aluInXXX & aluXXX, -- D0 BNE
	  "0000" & "100011" & readIndY  & aluInT   & aluCmp, -- D1 CMP (zp),y
	  "----" & "------" & xxxxxxxx  & aluInXXX & aluXXX, -- D2 *** JAM ***
	  "0000" & "100011" & rmwIndY   & aluInT   & aluDcp, -- D3 iDCP (zp),y
	  "0000" & "000000" & readZpX   & aluInXXX & aluXXX, -- D4 iNOP zp,x
	  "0000" & "100011" & readZpX   & aluInT   & aluCmp, -- D5 CMP zp,x
	  "0000" & "100010" & rmwZpX    & aluInT   & aluDec, -- D6 DEC zp,x
	  "0000" & "100011" & rmwZpX    & aluInT   & aluDcp, -- D7 iDCP zp,x
	  "0000" & "001000" & implied   & aluInClr & aluXXX, -- D8 CLD
	  "0000" & "100011" & readAbsY  & aluInT   & aluCmp, -- D9 CMP abs,y
	  "0000" & "000000" & implied   & aluInXXX & aluXXX, -- DA iNOP implied
	  "0000" & "100011" & rmwAbsY   & aluInT   & aluDcp, -- DB iDCP abs,y
	  "0000" & "000000" & readAbsX  & aluInXXX & aluXXX, -- DC iNOP abs,x
	  "0000" & "100011" & readAbsX  & aluInT   & aluCmp, -- DD CMP abs,x
	  "0000" & "100010" & rmwAbsX   & aluInT   & aluDec, -- DE DEC abs,x
	  "0000" & "100011" & rmwAbsX   & aluInT   & aluDcp, -- DF iDCP abs,x
	-- AXYS    NVDIZC    addressing  aluInput  aluMode
	  "0000" & "100011" & immediate & aluInT   & aluCpx, -- E0 CPX imm
	  "1000" & "110011" & readIndX  & aluInT   & aluSbc, -- E1 SBC (zp,x)
	  "0000" & "000000" & immediate & aluInXXX & aluXXX, -- E2 iNOP imm
	  "1000" & "110011" & rmwIndX   & aluInT   & aluIsc, -- E3 iISC (zp,x)
	  "0000" & "100011" & readZp    & aluInT   & aluCpx, -- E4 CPX zp
	  "1000" & "110011" & readZp    & aluInT   & aluSbc, -- E5 SBC zp
	  "0000" & "100010" & rmwZp     & aluInT   & aluInc, -- E6 INC zp
	  "1000" & "110011" & rmwZp     & aluInT   & aluIsc, -- E7 iISC zp
	  "0100" & "100010" & implied   & aluInX   & aluInc, -- E8 INX
	  "1000" & "110011" & immediate & aluInT   & aluSbc, -- E9 SBC imm
	  "0000" & "000000" & implied   & aluInXXX & aluXXX, -- EA NOP
	  "1000" & "110011" & immediate & aluInT   & aluSbc, -- EB SBC imm (illegal opc)
	  "0000" & "100011" & readAbs   & aluInT   & aluCpx, -- EC CPX abs
	  "1000" & "110011" & readAbs   & aluInT   & aluSbc, -- ED SBC abs
	  "0000" & "100010" & rmwAbs    & aluInT   & aluInc, -- EE INC abs
	  "1000" & "110011" & rmwAbs    & aluInT   & aluIsc, -- EF iISC abs
	  "0000" & "000000" & relative  & aluInXXX & aluXXX, -- F0 BEQ
	  "1000" & "110011" & readIndY  & aluInT   & aluSbc, -- F1 SBC (zp),y
	  "----" & "------" & xxxxxxxx  & aluInXXX & aluXXX, -- F2 *** JAM ***
	  "1000" & "110011" & rmwIndY   & aluInT   & aluIsc, -- F3 iISC (zp),y
	  "0000" & "000000" & readZpX   & aluInXXX & aluXXX, -- F4 iNOP zp,x
	  "1000" & "110011" & readZpX   & aluInT   & aluSbc, -- F5 SBC zp,x
	  "0000" & "100010" & rmwZpX    & aluInT   & aluInc, -- F6 INC zp,x
	  "1000" & "110011" & rmwZpX    & aluInT   & aluIsc, -- F7 iISC zp,x
	  "0000" & "001000" & implied   & aluInSet & aluXXX, -- F8 SED
	  "1000" & "110011" & readAbsY  & aluInT   & aluSbc, -- F9 SBC abs,y
	  "0000" & "000000" & implied   & aluInXXX & aluXXX, -- FA iNOP implied
	  "1000" & "110011" & rmwAbsY   & aluInT   & aluIsc, -- FB iISC abs,y
	  "0000" & "000000" & readAbsX  & aluInXXX & aluXXX, -- FC iNOP abs,x
	  "1000" & "110011" & readAbsX  & aluInT   & aluSbc, -- FD SBC abs,x
	  "0000" & "100010" & rmwAbsX   & aluInT   & aluInc, -- FE INC abs,x
	  "1000" & "110011" & rmwAbsX   & aluInT   & aluIsc  -- FF iISC abs,x
	);
	signal opcInfo        : decodedBitsDef;
	signal nextOpcInfo    : decodedBitsDef;	-- Next opcode (decoded)
	signal nextOpcInfoReg : decodedBitsDef;	-- Next opcode (decoded) pipelined
	signal theOpcode      : unsigned(7 downto 0);
	signal nextOpcode     : unsigned(7 downto 0);

-- Program counter
	signal PC : unsigned(15 downto 0); -- Program counter

-- Address generation
	type nextAddrDef is (
		nextAddrHold,
		nextAddrIncr,
		nextAddrIncrL, -- Increment low bits only (zeropage accesses)
		nextAddrIncrH, -- Increment high bits only (page-boundary)
		nextAddrDecrH, -- Decrement high bits (branch backwards)
		nextAddrPc,
		nextAddrIrq,
		nextAddrReset,
		nextAddrAbs,
		nextAddrAbsIndexed,
		nextAddrZeroPage,
		nextAddrZPIndexed,
		nextAddrStack,
		nextAddrRelative
	);
	signal nextAddr : nextAddrDef;
	signal myAddr : unsigned(15 downto 0);
	signal myAddrIncr : unsigned(15 downto 0);
	signal myAddrIncrH : unsigned(7 downto 0);
	signal myAddrDecrH : unsigned(7 downto 0);
	signal theWe : std_logic;

	signal irqActive : std_logic;
	
-- Output register
	signal doReg : unsigned(7 downto 0);
	
-- Buffer register
	signal T : unsigned(7 downto 0);

-- General registers
	signal A: unsigned(7 downto 0); -- Accumulator
	signal X: unsigned(7 downto 0); -- Index X
	signal Y: unsigned(7 downto 0); -- Index Y
	signal S: unsigned(7 downto 0); -- stack pointer

-- Status register
	signal C: std_logic; -- Carry
	signal Z: std_logic; -- Zero flag
	signal I: std_logic; -- Interrupt flag
	signal D: std_logic; -- Decimal mode
	signal V: std_logic; -- Overflow
	signal N: std_logic; -- Negative

-- ALU
	-- ALU input
	signal aluInput : unsigned(7 downto 0);
	signal aluCmpInput : unsigned(7 downto 0);
	-- ALU output
	signal aluRegisterOut : unsigned(7 downto 0);
	signal aluRmwOut : unsigned(7 downto 0);
	signal aluC : std_logic;
	signal aluZ : std_logic;
	signal aluV : std_logic;
	signal aluN : std_logic;
	-- Pipeline registers
	signal aluInputReg : unsigned(7 downto 0);
	signal aluCmpInputReg : unsigned(7 downto 0);
	signal aluRmwReg : unsigned(7 downto 0);
	signal aluNineReg : unsigned(7 downto 0);
	signal aluCReg : std_logic;
	signal aluZReg : std_logic;
	signal aluVReg : std_logic;
	signal aluNReg : std_logic;

-- Indexing
	signal indexOut : unsigned(8 downto 0);

begin
processAluInput: process(clk, opcInfo, A, X, Y, T, S)
		variable temp : unsigned(7 downto 0);
	begin
		temp := (others => '1');
		if opcInfo(opcInA) = '1' then
			temp := temp and A;
		end if;
		if opcInfo(opcInE) = '1' then
			temp := temp and (A or X"EE");
		end if;
		if opcInfo(opcInX) = '1' then
			temp := temp and X;
		end if;
		if opcInfo(opcInY) = '1' then
			temp := temp and Y;
		end if;
		if opcInfo(opcInS) = '1' then
			temp := temp and S;
		end if;
		if opcInfo(opcInT) = '1' then
			temp := temp and T;
		end if;
		if opcInfo(opcInClear) = '1' then
			temp := (others => '0');
		end if;
		if rising_edge(clk) then
			aluInputReg <= temp;
		end if;

		aluInput <= temp;
		if pipelineAluMux then
			aluInput <= aluInputReg;
		end if;
	end process;

processCmpInput: process(clk, opcInfo, A, X, Y)
		variable temp : unsigned(7 downto 0);
	begin
		temp := (others => '1');
		if opcInfo(opcInCmp) = '1' then
			temp := temp and A;
		end if;
		if opcInfo(opcInCpx) = '1' then
			temp := temp and X;
		end if;
		if opcInfo(opcInCpy) = '1' then
			temp := temp and Y;
		end if;
		if rising_edge(clk) then
			aluCmpInputReg <= temp;
		end if;

		aluCmpInput <= temp;
		if pipelineAluMux then
			aluCmpInput <= aluCmpInputReg;
		end if;
	end process;

	-- ALU consists of two parts
	-- Read-Modify-Write or index instructions: INC/DEC/ASL/LSR/ROR/ROL 
	-- Accumulator instructions: ADC, SBC, EOR, AND, EOR, ORA
	-- Some instructions are both RMW and accumulator so for most
	-- instructions the rmw results are routed through accu alu too.
processAlu: process(clk, opcInfo, aluInput, aluCmpInput, A, T, irqActive, N, V, D, I, Z, C)
		variable lowBits: unsigned(5 downto 0);
		variable nineBits: unsigned(8 downto 0);
		variable rmwBits: unsigned(8 downto 0);
		
		variable varC : std_logic;
		variable varZ : std_logic;
		variable varV : std_logic;
		variable varN : std_logic;
	begin
		lowBits := (others => '-');
		nineBits := (others => '-');
		rmwBits := (others => '-');
		varV := aluInput(6); -- Default for BIT / PLP / RTI

		-- Shift unit
		case opcInfo(aluMode1From to aluMode1To) is
		when aluModeInp =>
			rmwBits := C & aluInput;
		when aluModeP =>
			rmwBits := C & N & V & '1' & (not irqActive) & D & I & Z & C;
		when aluModeInc =>
			rmwBits := C & (aluInput + 1);
		when aluModeDec =>
			rmwBits := C & (aluInput - 1);
		when aluModeAsl =>
			rmwBits := aluInput & "0";
		when aluModeFlg =>
			rmwBits := aluInput(0) & aluInput;
		when aluModeLsr =>
			rmwBits := aluInput(0) & "0" & aluInput(7 downto 1);
		when aluModeRol =>
			rmwBits := aluInput & C;
		when aluModeRoR =>
			rmwBits := aluInput(0) & C & aluInput(7 downto 1);
		when aluModeAnc =>
			rmwBits := (aluInput(7) and A(7)) & aluInput;
		when others =>
			rmwBits := C & aluInput;
		end case;
		
		-- ALU
		case opcInfo(aluMode2From to aluMode2To) is
		when aluModeAdc =>
			lowBits := ("0" & A(3 downto 0) & rmwBits(8)) + ("0" & rmwBits(3 downto 0) & "1");
			ninebits := ("0" & A) + ("0" & rmwBits(7 downto 0)) + (B"00000000" & rmwBits(8));
		when aluModeSbc =>
			lowBits := ("0" & A(3 downto 0) & rmwBits(8)) + ("0" & (not rmwBits(3 downto 0)) & "1");
			ninebits := ("0" & A) + ("0" & (not rmwBits(7 downto 0))) + (B"00000000" & rmwBits(8));
		when aluModeCmp =>
			ninebits := ("0" & aluCmpInput) + ("0" & (not rmwBits(7 downto 0))) + "000000001";
		when aluModeAnd =>
			ninebits := rmwBits(8) & (A and rmwBits(7 downto 0));
		when aluModeEor =>
			ninebits := rmwBits(8) & (A xor rmwBits(7 downto 0));
		when aluModeOra =>
			ninebits := rmwBits(8) & (A or rmwBits(7 downto 0));
		when others =>
			ninebits := rmwBits;
		end case;

		if (opcInfo(aluMode1From to aluMode1To) = aluModeFlg) then
			varZ := rmwBits(1);
		elsif ninebits(7 downto 0) = X"00" then
			varZ := '1';
		else
			varZ := '0';
		end if;

		case opcInfo(aluMode2From to aluMode2To) is
		when aluModeAdc =>
			-- decimal mode low bits correction, is done after setting Z flag.
			if D = '1' then
				if lowBits(5 downto 1) > 9 then
					ninebits(3 downto 0) := ninebits(3 downto 0) + 6;
					if lowBits(5) = '0'  then
						ninebits(8 downto 4) := ninebits(8 downto 4) + 1;
					end if;
				end if;
			end if;
		when others =>
			null;
		end case;

		if (opcInfo(aluMode1From to aluMode1To) = aluModeBit)
		or (opcInfo(aluMode1From to aluMode1To) = aluModeFlg) then
			varN := rmwBits(7);
		else
			varN := nineBits(7);
		end if;
		varC := ninebits(8);
		if opcInfo(aluMode2From to aluMode2To) = aluModeArr then
			varC := aluInput(7);
			varV := aluInput(7) xor aluInput(6);
		end if;

		case opcInfo(aluMode2From to aluMode2To) is
		when aluModeAdc =>
			-- decimal mode high bits correction, is done after setting Z and N flags
			varV := (A(7) xor ninebits(7)) and (rmwBits(7) xor ninebits(7));
			if D = '1' then
				if ninebits(8 downto 4) > 9 then
					ninebits(8 downto 4) := ninebits(8 downto 4) + 6;
					varC := '1';
				end if;
			end if;
		when aluModeSbc =>
			varV := (A(7) xor ninebits(7)) and ((not rmwBits(7)) xor ninebits(7));
			if D = '1' then
				-- Check for borrow (lower 4 bits)
				if lowBits(5) = '0' then
					ninebits(3 downto 0) := ninebits(3 downto 0) - 6;
				end if;
				-- Check for borrow (upper 4 bits)
				if ninebits(8) = '0' then
					ninebits(8 downto 4) := ninebits(8 downto 4) - 6;
				end if;
			end if;
		when aluModeArr =>
			if D = '1' then
				if (("0" & aluInput(3 downto 0)) + ("0000" & aluInput(0))) > 5 then
					ninebits(3 downto 0) := ninebits(3 downto 0) + 6;
				end if;
				if (("0" & aluInput(7 downto 4)) + ("0000" & aluInput(4))) > 5 then
					ninebits(8 downto 4) := ninebits(8 downto 4) + 6;
					varC := '1';
				else
					varC := '0';
				end if;
			end if;
		when others =>
			null;
		end case;

		if rising_edge(clk) then
			aluRmwReg <= rmwBits(7 downto 0);
			aluNineReg <= ninebits(7 downto 0);
			aluCReg <= varC;
			aluZReg <= varZ;
			aluVReg <= varV;
			aluNReg <= varN;
		end if;

		aluRmwOut <= rmwBits(7 downto 0);
		aluRegisterOut <= ninebits(7 downto 0);
		aluC <= varC;
		aluZ <= varZ;
		aluV <= varV;
		aluN <= varN;
		if pipelineAluOut then
			aluRmwOut <= aluRmwReg;
			aluRegisterOut <= aluNineReg;
			aluC <= aluCReg;
			aluZ <= aluZReg;
			aluV <= aluVReg;
			aluN <= aluNReg;
		end if;
	end process;

calcInterrupt: process(clk)
	begin
		if rising_edge(clk) then
			if enable = '1' then
				if theCpuCycle = cycleStack4
				or reset = '1' then
					nmiReg <= '1';
				end if;

				if nextCpuCycle /= cycleBranchTaken
				and nextCpuCycle /= opcodeFetch then
					irqReg <= irq_n;
					nmiEdge <= nmi_n;
					if (nmiEdge = '1') and (nmi_n = '0') then
						nmiReg <= '0';
					end if;
				end if;
				-- The 'or opcInfo(opcSetI)' prevents NMI immediately after BRK or IRQ.
				-- Presumably this is done in the real 6502/6510 to prevent a double IRQ.
				processIrq <= not ((nmiReg and (irqReg or I)) or opcInfo(opcIRQ));
			end if;
		end if;
	end process;

calcNextOpcode: process(clk, di, reset, processIrq)
		variable myNextOpcode : unsigned(7 downto 0);
	begin
		-- Next opcode is read from input unless a reset or IRQ is pending.
		myNextOpcode := di;
		if reset = '1' then
			myNextOpcode := X"4C";
		elsif processIrq = '1' then
			myNextOpcode := X"00";
		end if;
		
		nextOpcode <= myNextOpcode;
	end process;

	nextOpcInfo <= opcodeInfoTable(to_integer(nextOpcode));
	process(clk)
	begin
		if rising_edge(clk) then
			nextOpcInfoReg <= nextOpcInfo;
		end if;
	end process;

	-- Read bits and flags from opcodeInfoTable and store in opcInfo.
	-- This info is used to control the execution of the opcode.
calcOpcInfo: process(clk)
	begin
		if rising_edge(clk) then
			if enable = '1' then
				if (reset = '1') or (theCpuCycle = opcodeFetch) then
					opcInfo <= nextOpcInfo;
					if pipelineOpcode then
						opcInfo <= nextOpcInfoReg;
					end if;
				end if;
			end if;
		end if;
	end process;

calcTheOpcode:	process(clk)
	begin	
		if rising_edge(clk) then
			if enable = '1' then
				if theCpuCycle = opcodeFetch then
					irqActive <= '0';
					if processIrq = '1' then
						irqActive <= '1';
					end if;
					-- Fetch opcode
					theOpcode <= nextOpcode;
				end if;
			end if;
		end if;
	end process;
	
-- -----------------------------------------------------------------------
-- State machine
-- -----------------------------------------------------------------------
	process(enable, theCpuCycle, opcInfo)
	begin
		updateRegisters <= false;
		if enable = '1' then
			if opcInfo(opcRti) = '1' then
				if theCpuCycle = cycleRead then
					updateRegisters <= true;
				end if;
			elsif theCpuCycle = opcodeFetch then
				updateRegisters <= true;
			end if;
		end if;
	end process;

	debugOpcode <= theOpcode;
	process(clk)
	begin
		if rising_edge(clk) then
			if enable = '1' then
				theCpuCycle <= nextCpuCycle;
			end if;
			if reset = '1' then
				theCpuCycle <= cycle2;
			end if;				
		end if;			
	end process;

	-- Determine the next cpu cycle. After the last cycle we always
	-- go to opcodeFetch to get the next opcode.
calcNextCpuCycle: process(theCpuCycle, opcInfo, theOpcode, indexOut, T, N, V, C, Z)
	begin
		nextCpuCycle <= opcodeFetch;

		case theCpuCycle is
		when opcodeFetch =>
			nextCpuCycle <= cycle2;
		when cycle2 =>
			if opcInfo(opcBranch) = '1' then
				if (N = theOpcode(5) and theOpcode(7 downto 6) = "00")
				or (V = theOpcode(5) and theOpcode(7 downto 6) = "01")
				or (C = theOpcode(5) and theOpcode(7 downto 6) = "10")
				or (Z = theOpcode(5) and theOpcode(7 downto 6) = "11") then
					-- Branch condition is true
					nextCpuCycle <= cycleBranchTaken;
				end if;
			elsif (opcInfo(opcStackUp) = '1') then
				nextCpuCycle <= cycleStack1;
			elsif opcInfo(opcStackAddr) = '1'
			and opcInfo(opcStackData) = '1' then
				nextCpuCycle <= cycleStack2;
			elsif opcInfo(opcStackAddr) = '1' then
				nextCpuCycle <= cycleStack1;
			elsif opcInfo(opcStackData) = '1' then
				nextCpuCycle <= cycleWrite;
			elsif opcInfo(opcAbsolute) = '1' then
				nextCpuCycle <= cycle3;
			elsif opcInfo(opcIndirect) = '1' then
				if opcInfo(indexX) = '1' then
					nextCpuCycle <= cyclePreIndirect;			
				else
					nextCpuCycle <= cycleIndirect;
				end if;					
			elsif opcInfo(opcZeroPage) = '1' then
				if opcInfo(opcWrite) = '1' then
					if (opcInfo(indexX) = '1')
					or (opcInfo(indexY) = '1') then
						nextCpuCycle <= cyclePreWrite;
					else						
						nextCpuCycle <= cycleWrite;
					end if;						
				else
					if (opcInfo(indexX) = '1')
					or (opcInfo(indexY) = '1') then
						nextCpuCycle <= cyclePreRead;
					else						
						nextCpuCycle <= cycleRead2;
					end if;						
				end if;					
			elsif opcInfo(opcJump) = '1' then
				nextCpuCycle <= cycleJump;
			end if;
		when cycle3 =>
			nextCpuCycle <= cycleRead;
			if opcInfo(opcWrite) = '1' then
				if (opcInfo(indexX) = '1')
				or (opcInfo(indexY) = '1') then
					nextCpuCycle <= cyclePreWrite;
				else						
					nextCpuCycle <= cycleWrite;
				end if;					
			end if;
			if (opcInfo(opcIndirect) = '1')
			and (opcInfo(indexX) = '1') then
				if opcInfo(opcWrite) = '1' then
					nextCpuCycle <= cycleWrite;
				else					
					nextCpuCycle <= cycleRead2;
				end if;
			end if;									
		when cyclePreIndirect =>			
			nextCpuCycle <= cycleIndirect;
		when cycleIndirect =>
			nextCpuCycle <= cycle3;
		when cycleBranchTaken =>
			if indexOut(8) /= T(7) then
				-- Page boundary crossing during branch.
				nextCpuCycle <= cycleBranchPage;
			end if;
		when cyclePreRead =>
			if opcInfo(opcZeroPage) = '1' then
				nextCpuCycle <= cycleRead2;
			end if;
		when cycleRead =>
			if opcInfo(opcJump) = '1' then
				nextCpuCycle <= cycleJump;
			elsif indexOut(8) = '1' then
				-- Page boundary crossing while indexed addressing.
				nextCpuCycle <= cycleRead2;
			elsif opcInfo(opcRmw) = '1' then
				nextCpuCycle <= cycleRmw;
				if opcInfo(indexX) = '1'
				or opcInfo(indexY) = '1' then
					-- 6510 needs extra cycle for indexed addressing
					-- combined with RMW indexing
					nextCpuCycle <= cycleRead2;
				end if;
			end if;											
		when cycleRead2 =>
			if opcInfo(opcRmw) = '1' then
				nextCpuCycle <= cycleRmw;
			end if;											
		when cycleRmw =>
			nextCpuCycle <= cycleWrite;
		when cyclePreWrite =>
			nextCpuCycle <= cycleWrite;
		when cycleStack1 =>
			nextCpuCycle <= cycleRead;
			if opcInfo(opcStackAddr) = '1' then
				nextCpuCycle <= cycleStack2;
			end if;				
		when cycleStack2 =>
			nextCpuCycle <= cycleStack3;
			if opcInfo(opcRti) = '1' then
				nextCpuCycle <= cycleRead;
			end if;
			if opcInfo(opcStackData) = '0'
			and opcInfo(opcStackUp) = '1' then
				nextCpuCycle <= cycleJump;
			end if;
		when cycleStack3 =>
			nextCpuCycle <= cycleRead;
			if opcInfo(opcStackData) = '0'
			or opcInfo(opcStackUp) = '1' then
				nextCpuCycle <= cycleJump;
			elsif opcInfo(opcStackAddr) = '1' then
				nextCpuCycle <= cycleStack4;				
			end if;
		when cycleStack4 =>
			nextCpuCycle <= cycleRead;
		when cycleJump =>
			if opcInfo(opcIncrAfter) = '1' then
				-- Insert extra cycle
				nextCpuCycle <= cycleEnd;
			end if;				
		when others =>
			null;
		end case;
	end process;		

-- -----------------------------------------------------------------------
-- T register
-- -----------------------------------------------------------------------
calcT: process(clk)
	begin
		if rising_edge(clk) then
			if enable = '1' then
				case theCpuCycle is
				when cycle2 =>
					T <= di;
				when cycleStack1 | cycleStack2 =>
					if opcInfo(opcStackUp) = '1' then
						-- Read from stack
						T <= di;
					end if;											
				when cycleIndirect | cycleRead | cycleRead2 =>
					T <= di;
				when others =>
					null;					
				end case;
			end if;
		end if;		
	end process;

-- -----------------------------------------------------------------------
-- A register
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if updateRegisters then
				if opcInfo(opcUpdateA) = '1' then
					A <= aluRegisterOut;
				end if;					
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- X register
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if updateRegisters then
				if opcInfo(opcUpdateX) = '1' then
					X <= aluRegisterOut;
				end if;					
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Y register
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if updateRegisters then
				if opcInfo(opcUpdateY) = '1' then
					Y <= aluRegisterOut;
				end if;					
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- C flag
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if updateRegisters then
				if opcInfo(opcUpdateC) = '1' then
					C <= aluC;
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Z flag
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if updateRegisters then
				if opcInfo(opcUpdateZ) = '1' then
					Z <= aluZ;
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- I flag
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if updateRegisters then
				if opcInfo(opcUpdateI) = '1' then
					I <= aluInput(2);
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- D flag
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if updateRegisters then
				if opcInfo(opcUpdateD) = '1' then
					D <= aluInput(3);
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- V flag
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if updateRegisters then
				if opcInfo(opcUpdateV) = '1' then
					V <= aluV;
				end if;
			end if;
			if enable = '1' then
				if soReg = '1' and so_n = '0' then
					V <= '1';
				end if;
				soReg <= so_n;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- N flag
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if updateRegisters then
				if opcInfo(opcUpdateN) = '1' then
					N <= aluN;
				end if;
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Stack pointer
-- -----------------------------------------------------------------------
	process(clk)
		variable sIncDec : unsigned(7 downto 0);
		variable updateFlag : boolean;
	begin
		if rising_edge(clk) then

			if opcInfo(opcStackUp) = '1' then
				sIncDec := S + 1;
			else
				sIncDec := S - 1;
			end if;	
			
			if enable = '1' then
				updateFlag := false;			
				case nextCpuCycle is
				when cycleStack1 =>
					if (opcInfo(opcStackUp) = '1')
					or (opcInfo(opcStackData) = '1') then
						updateFlag := true;			
					end if;
				when cycleStack2 =>
					updateFlag := true;
				when cycleStack3 =>
					updateFlag := true;			
				when cycleStack4 =>
					updateFlag := true;
				when cycleRead =>
					if opcInfo(opcRti) = '1' then							
						updateFlag := true;
					end if;						
				when cycleWrite =>
					if opcInfo(opcStackData) = '1' then
						updateFlag := true;
					end if;						
				when others =>
					null;					
				end case;
				if updateFlag then
					S <= sIncDec;
				end if;					
			end if;
			if updateRegisters then
				if opcInfo(opcUpdateS) = '1' then
					S <= aluRegisterOut;
				end if;					
			end if;
		end if;
	end process;

-- -----------------------------------------------------------------------
-- Data out
-- -----------------------------------------------------------------------
--calcDo: process(cpuNo, theCpuCycle, aluOut, PC, T)
calcDo: process(clk)
	begin
		if rising_edge(clk) then
			if enable = '1' then
				doReg <= aluRmwOut;
				if opcInfo(opcInH) = '1' then
					-- For illegal opcodes SHA, SHX, SHY, SHS
					doReg <= aluRmwOut and myAddrIncrH;
				end if;

				case nextCpuCycle is
				when cycleStack2 =>
					if opcInfo(opcIRQ) = '1'
					and irqActive = '0' then
						doReg <= myAddrIncr(15 downto 8);
					else
						doReg <= PC(15 downto 8);
					end if;
				when cycleStack3 =>
					doReg <= PC(7 downto 0);
				when cycleRmw =>
--					do <= T; -- Read-modify-write write old value first.
					doReg <= di; -- Read-modify-write write old value first.
				when others => null;
				end case;
			end if;			
		end if;
	end process;
	do <= doReg;
	


-- -----------------------------------------------------------------------
-- Write enable
-- -----------------------------------------------------------------------
calcWe: process(clk)
	begin
		if rising_edge(clk) then
			if enable = '1' then
				theWe <= '0';
				case nextCpuCycle is
				when cycleStack1 =>
					if opcInfo(opcStackUp) = '0'
					and ((opcInfo(opcStackAddr) = '0')
					or (opcInfo(opcStackData) = '1')) then
						theWe <= '1';
					end if;						
				when cycleStack2 | cycleStack3 | cycleStack4 =>
					if opcInfo(opcStackUp) = '0' then
						theWe <= '1';
					end if;						
				when cycleRmw =>
					theWe <= '1';
				when cycleWrite =>
					theWe <= '1';
				when others =>
					null;
				end case;				
			end if;
		end if;							
	end process;
	we <= theWe;

-- -----------------------------------------------------------------------
-- Program counter
-- -----------------------------------------------------------------------
calcPC: process(clk)
	begin
		if rising_edge(clk) then
			if enable = '1' then
				case theCpuCycle is
				when opcodeFetch =>
					PC <= myAddr;
				when cycle2 =>
					if irqActive = '0' then
						if opcInfo(opcSecondByte) = '1' then
							PC <= myAddrIncr;
						else							
							PC <= myAddr;
						end if;							
					end if;						
				when cycle3 =>
					if opcInfo(opcAbsolute) = '1' then
						PC <= myAddrIncr;					
					end if;
				when others =>
					null;
				end case;
			end if;
		end if;
	end process;
	debugPc <= PC;

-- -----------------------------------------------------------------------
-- Address generation
-- -----------------------------------------------------------------------
calcNextAddr: process(theCpuCycle, opcInfo, indexOut, T, reset)
	begin
		nextAddr <= nextAddrIncr;
		case theCpuCycle is
		when cycle2 =>
			if opcInfo(opcStackAddr) = '1' 
			or opcInfo(opcStackData) = '1' then
				nextAddr <= nextAddrStack;
			elsif opcInfo(opcAbsolute) = '1' then
				nextAddr <= nextAddrIncr;
			elsif opcInfo(opcZeroPage) = '1' then
				nextAddr <= nextAddrZeroPage;
			elsif opcInfo(opcIndirect) = '1' then
				nextAddr <= nextAddrZeroPage;
			elsif opcInfo(opcSecondByte) = '1' then
				nextAddr <= nextAddrIncr;
			else
				nextAddr <= nextAddrHold;
			end if;
		when cycle3 =>
			if (opcInfo(opcIndirect) = '1')
			and (opcInfo(indexX) = '1') then
				nextAddr <= nextAddrAbs;
			else							
				nextAddr <= nextAddrAbsIndexed;
			end if;				
		when cyclePreIndirect =>
			nextAddr <= nextAddrZPIndexed;
		when cycleIndirect =>
			nextAddr <= nextAddrIncrL;
		when cycleBranchTaken =>
			nextAddr <= nextAddrRelative;
		when cycleBranchPage =>
			if T(7) = '0' then
				nextAddr <= nextAddrIncrH;
			else				
				nextAddr <= nextAddrDecrH;
			end if;
		when cyclePreRead =>
			nextAddr <= nextAddrZPIndexed;
		when cycleRead =>
			nextAddr <= nextAddrPc;
			if opcInfo(opcJump) = '1' then
				-- Emulate 6510 bug, jmp(xxFF) fetches from same page.
				-- Replace with nextAddrIncr if emulating 65C02 or later cpu.
				nextAddr <= nextAddrIncrL; 
			elsif indexOut(8) = '1' then
				nextAddr <= nextAddrIncrH;
			elsif opcInfo(opcRmw) = '1' then
				nextAddr <= nextAddrHold;
			end if;
		when cycleRead2 =>
			nextAddr <= nextAddrPc;
			if opcInfo(opcRmw) = '1' then
				nextAddr <= nextAddrHold;
			end if;
		when cycleRmw =>
			nextAddr <= nextAddrHold;			
		when cyclePreWrite =>
			nextAddr <= nextAddrHold;			
			if opcInfo(opcZeroPage) = '1' then
				nextAddr <= nextAddrZPIndexed;
			elsif indexOut(8) = '1' then
				nextAddr <= nextAddrIncrH;
			end if;							
		when cycleWrite =>
			nextAddr <= nextAddrPc;			
		when cycleStack1 =>
			nextAddr <= nextAddrStack;
		when cycleStack2 =>
			nextAddr <= nextAddrStack;
		when cycleStack3 =>
			nextAddr <= nextAddrStack;
			if opcInfo(opcStackData) = '0' then
				nextAddr <= nextAddrPc;
			end if;				
		when cycleStack4 =>
			nextAddr <= nextAddrIrq;
		when cycleJump =>
			nextAddr <= nextAddrAbs;
		when others =>
			null;
		end case;										
		if reset = '1' then
			nextAddr <= nextAddrReset;
		end if;			
	end process;
	
indexAlu: process(opcInfo, myAddr, T, X, Y)
	begin
		if opcInfo(indexX) = '1' then
			indexOut <= (B"0" & T) + (B"0" & X);
		elsif opcInfo(indexY) = '1' then
			indexOut <= (B"0" & T) + (B"0" & Y);
		elsif opcInfo(opcBranch) = '1' then			
			indexOut <= (B"0" & T) + (B"0" & myAddr(7 downto 0));
		else
			indexOut <= B"0" & T;
		end if;
	end process;

calcAddr: process(clk)
	begin
		if rising_edge(clk) then
			if enable = '1' then
				case nextAddr is
				when nextAddrIncr => myAddr <= myAddrIncr;
				when nextAddrIncrL => myAddr(7 downto 0) <= myAddrIncr(7 downto 0);
				when nextAddrIncrH => myAddr(15 downto 8) <= myAddrIncrH;
				when nextAddrDecrH => myAddr(15 downto 8) <= myAddrDecrH;
				when nextAddrPc => myAddr <= PC;
				when nextAddrIrq =>
					myAddr <= X"FFFE";
					if nmiReg = '0' then
						myAddr <= X"FFFA";
					end if;
				when nextAddrReset => myAddr <= X"FFFC";
				when nextAddrAbs => myAddr <= di & T;
				when nextAddrAbsIndexed => myAddr <= di & indexOut(7 downto 0);
				when nextAddrZeroPage => myAddr <= "00000000" & di;
				when nextAddrZPIndexed => myAddr <= "00000000" & indexOut(7 downto 0);
				when nextAddrStack => myAddr <= "00000001" & S;
				when nextAddrRelative => myAddr(7 downto 0) <= indexOut(7 downto 0);
				when others => null;
				end case;
			end if;
		end if;							
	end process;	

	myAddrIncr <= myAddr + 1;
	myAddrIncrH <= myAddr(15 downto 8) + 1;
	myAddrDecrH <= myAddr(15 downto 8) - 1;

	addr <= myAddr;

	debugA <= A;
	debugX <= X;
	debugY <= Y;
	debugS <= S;
	
end architecture;


