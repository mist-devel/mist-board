/////////////////////////////////////////////////////////////////////
// TZX to VAV Converter v0.2 for Bloodshed Dev-C++ compiler        //
// (C) 2006 Francisco Javier Crespo <tzx2wav@ya.com>               //
//                                                                 //
// Hardware description header file                                //
/////////////////////////////////////////////////////////////////////

// Hardware Type entries

const char hwtype_01[] = "Computer";
const char hwtype_02[] = "External Storage";
const char hwtype_03[] = "ROM/RAM Type Add-On";
const char hwtype_04[] = "Sound Device";
const char hwtype_05[] = "Joystick";
const char hwtype_06[] = "Mouse";
const char hwtype_07[] = "Other Controller";
const char hwtype_08[] = "Serial Port";
const char hwtype_09[] = "Parallel Port";
const char hwtype_10[] = "Printer";
const char hwtype_11[] = "Modem";
const char hwtype_12[] = "Digitiser";
const char hwtype_13[] = "Network Adapter";
const char hwtype_14[] = "Keyboard or Keypad";
const char hwtype_15[] = "AD/DA Converter";
const char hwtype_16[] = "EPROM Programmer";

// Computer entries

const char hwid_01_01[] = "ZX Spectrum 16k";
const char hwid_01_02[] = "ZX Spectrum 48k, Plus";
const char hwid_01_03[] = "ZX Spectrum 48k Issue 1";
const char hwid_01_04[] = "ZX Spectrum 128k (Sinclair)";
const char hwid_01_05[] = "ZX Spectrum 128k +2 (Grey case)";
const char hwid_01_06[] = "ZX Spectrum 128k +2A, +3";
const char hwid_01_07[] = "Timex Sinclair TC-2048";
const char hwid_01_08[] = "Timex Sinclair TS-2068";
const char hwid_01_09[] = "Pentagon 128";
const char hwid_01_10[] = "Sam Coupe";
const char hwid_01_11[] = "Didaktik M";
const char hwid_01_12[] = "Didaktik Gama";
const char hwid_01_13[] = "ZX-81 with 1k RAM";
const char hwid_01_14[] = "ZX-81 with 16k RAM or more";
const char hwid_01_15[] = "ZX Spectrum 128k, Spanish version";
const char hwid_01_16[] = "ZX Spectrum, Arabic version";
const char hwid_01_17[] = "TK 90-X";
const char hwid_01_18[] = "TK 95";
const char hwid_01_19[] = "Byte";
const char hwid_01_20[] = "Elwro";
const char hwid_01_21[] = "ZS Scorpion";
const char hwid_01_22[] = "Amstrad CPC 464";
const char hwid_01_23[] = "Amstrad CPC 664";
const char hwid_01_24[] = "Amstrad CPC 6128";
const char hwid_01_25[] = "Amstrad CPC 464+";
const char hwid_01_26[] = "Amstrad CPC 6128+";
const char hwid_01_27[] = "Jupiter ACE";
const char hwid_01_28[] = "Enterprise";
const char hwid_01_29[] = "Commodore 64";
const char hwid_01_30[] = "Commodore 128";

const char *hwids_01[30] =
{hwid_01_01, hwid_01_02, hwid_01_03, hwid_01_04, hwid_01_05, hwid_01_06,
 hwid_01_07, hwid_01_08, hwid_01_09, hwid_01_10, hwid_01_11, hwid_01_12,
 hwid_01_13, hwid_01_14, hwid_01_15, hwid_01_16, hwid_01_17, hwid_01_18,
 hwid_01_19, hwid_01_20, hwid_01_21, hwid_01_22, hwid_01_23, hwid_01_24,
 hwid_01_25, hwid_01_26, hwid_01_27, hwid_01_28, hwid_01_29, hwid_01_30};

// External Storage entries
 
const char hwid_02_01[] = "Microdrive";
const char hwid_02_02[] = "Opus Discovery";
const char hwid_02_03[] = "Disciple";
const char hwid_02_04[] = "Plus-D";
const char hwid_02_05[] = "Rotronics Wafadrive";
const char hwid_02_06[] = "TR-DOS (BetaDisk)";
const char hwid_02_07[] = "Byte Drive";
const char hwid_02_08[] = "Watsford";
const char hwid_02_09[] = "FIZ";
const char hwid_02_10[] = "Radofin";
const char hwid_02_11[] = "Didaktik disk drives";
const char hwid_02_12[] = "BS-DOS (MB-02)";
const char hwid_02_13[] = "ZX Spectrum +3 disk drive";
const char hwid_02_14[] = "JLO (Oliger) disk interface";
const char hwid_02_15[] = "FDD3000";
const char hwid_02_16[] = "Zebra disk drive";
const char hwid_02_17[] = "Ramex Millenia";
const char hwid_02_18[] = "Larken";

const char *hwids_02[18] =
{hwid_02_01, hwid_02_02, hwid_02_03, hwid_02_04, hwid_02_05, hwid_02_06,
 hwid_02_07, hwid_02_08, hwid_02_09, hwid_02_10, hwid_02_11, hwid_02_12,
 hwid_02_13, hwid_02_14, hwid_02_15, hwid_02_16, hwid_02_17, hwid_02_18};

// ROM/RAM Type Add-On entries

const char hwid_03_01[] = "Sam Ram";
const char hwid_03_02[] = "Multiface";
const char hwid_03_03[] = "Multiface 128k";
const char hwid_03_04[] = "Multiface +3";
const char hwid_03_05[] = "MultiPrint";
const char hwid_03_06[] = "MB-02 ROM/RAM expansion";

const char *hwids_03[6] =
{hwid_03_01, hwid_03_02, hwid_03_03, hwid_03_04, hwid_03_05, hwid_03_06};

// Sound Device entries

const char hwid_04_01[] = "Classic AY hardware (compatible with 128k ZXs)";
const char hwid_04_02[] = "Fuller Box AY sound hardware";
const char hwid_04_03[] = "Currah microSpeech";
const char hwid_04_04[] = "SpecDrum";
const char hwid_04_05[] = "AY ACB stereo; Melodik";
const char hwid_04_06[] = "AY ABC stereo";

const char *hwids_04[6] =
{hwid_04_01, hwid_04_02, hwid_04_03, hwid_04_04, hwid_04_05, hwid_04_06};

// Joystick entries

const char hwid_05_01[] = "Kempston";
const char hwid_05_02[] = "Cursor, Protek, AGF";
const char hwid_05_03[] = "Sinclair 2 Left";
const char hwid_05_04[] = "Sinclair 1 Right";
const char hwid_05_05[] = "Fuller";

const char *hwids_05[5] =
{hwid_05_01, hwid_05_02, hwid_05_03, hwid_05_04, hwid_05_05};

// Mouse entries

const char hwid_06_01[] = "AMX Mouse";
const char hwid_06_02[] = "Kempston mouse";

const char *hwids_06[2] = {hwid_06_01, hwid_06_02};

// Other Controller entries

const char hwid_07_01[] = "Trickstick";
const char hwid_07_02[] = "ZX Light Gun";
const char hwid_07_03[] = "Zebra Graphics Tablet";

const char *hwids_07[3] = {hwid_07_01, hwid_07_02, hwid_07_03};

// Serial Port entries

const char hwid_08_01[] = "ZX Interface 1";
const char hwid_08_02[] = "ZX Spectrum 128k";

const char *hwids_08[2] = {hwid_08_01, hwid_08_02};

// Parallel Port entries

const char hwid_09_01[] = "Kempston S";
const char hwid_09_02[] = "Kempston E";
const char hwid_09_03[] = "ZX Spectrum +3";
const char hwid_09_04[] = "Tasman";
const char hwid_09_05[] = "DK'Tronics";
const char hwid_09_06[] = "Hilderbay";
const char hwid_09_07[] = "INES Printerface";
const char hwid_09_08[] = "ZX LPrint Interface 3";
const char hwid_09_09[] = "MultiPrint";
const char hwid_09_10[] = "Opus Discovery";
const char hwid_09_11[] = "Standard 8255 chip";

const char *hwids_09[11] =
{hwid_09_01, hwid_09_02, hwid_09_03, hwid_09_04, hwid_09_05, hwid_09_06,
 hwid_09_07, hwid_09_08, hwid_09_09, hwid_09_10, hwid_09_11};

// Printer entries

const char hwid_10_01[] = "ZX Printer, Alphacom 32 & Compatibles";
const char hwid_10_02[] = "Generic Printer";
const char hwid_10_03[] = "EPSON Compatible";

const char *hwids_10[3] = {hwid_10_01, hwid_10_02, hwid_10_03};

// Modem entries

const char hwid_11_01[] = "VTX 5000";
const char hwid_11_02[] = "T/S 2050 or Westridge 2050";

const char *hwids_11[2] = {hwid_11_01, hwid_11_02};

// Digitiser entries

const char hwid_12_01[] = "RD Digital Tracer";
const char hwid_12_02[] = "DK'Tronics Light Pen";
const char hwid_12_03[] = "British MicroGraph Pad";

const char *hwids_12[3] = {hwid_12_01, hwid_12_02, hwid_12_03};

// Network Adapter entries

const char hwid_13_01[] = "ZX interface 1";

const char *hwids_13[1] = {hwid_13_01};

// Keyboard or Keypad entries

const char hwid_14_01[] = "Keypad for ZX Spectrum 128k";

const char *hwids_14[1] = {hwid_14_01};

// AD/DA Converter entries

const char hwid_15_01[] = "Harley Systems ADC 8.2";
const char hwid_15_02[] = "Blackboard Electronics";

const char *hwids_15[2] = {hwid_15_01, hwid_15_02};

// EPROM Programmer entries

const char hwid_16_01[] = "Orme Electronics";

const char *hwids_16[1] = {hwid_16_01};

// Variables used in main program

const char *hwtypes[16] = 
{hwtype_01, hwtype_02, hwtype_03, hwtype_04, hwtype_05, hwtype_06, hwtype_07, hwtype_08,
 hwtype_09, hwtype_10, hwtype_11, hwtype_12, hwtype_13, hwtype_14, hwtype_15, hwtype_16};

const char **hwids[16] = 
{hwids_01, hwids_02, hwids_03, hwids_04, hwids_05, hwids_06, hwids_07, hwids_08,
 hwids_09, hwids_10, hwids_11, hwids_12, hwids_13, hwids_14, hwids_15, hwids_16};
