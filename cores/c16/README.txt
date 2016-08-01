C16 for MIST
MiST port by Till Harbaum

This is the source code of the MIST port of the FPGATED project. The MIST
port has the follwing changes over the original version:

- VGA scan doubler (can be disabled through the mist.ini config file)
- MIST on screen display overlay (OSD)
- Joystick integration
- Switchable 16k/64k memory layout
- builtin kernal can be overloaded (to e.g. switch to NTSC)
- direct PRG injection into c16 memory

-------------------------------------------------------------------------------
FPGATED v1.0
Copyright 2013-2016 Istvan Hegedus

FPGATED is a cycle exact FPGA core for the MOS 7360/8360 TED chip written in verilog language.
MOS 7360/8360 is complex chip providing graphic, sound, bus and memory control for the Commodore 264
series 8 bit computers, namely the Commodore Plus4, Commodore 16 and Commodore 116.

In addition to the TED core modul FPGATED contains a simple C16 implementation using TED core and Gadget Factory's 
Papilio One 500k platform with a customized IO wing called Papilio TEDWing. The 6502 CPU core of C16 is created by 
Peter Wendrich in vhdl and is taken from the FPGA64 project with the permission of the author.

For more technical details and building Papilio TEDWing module visit https://hackaday.io/project/11460-fpgated

Files

basic_rom.v		C16/Plus4 Basic rom module
c16.v			This is the TOP module of FPGATED implementing a C16 computer
c16_testbench.v		C16 testbench for simulation
c16_keymatrix.v		C16/Plus4 keyboard matrix emulation module
colors_to_rgb.v		TED color code conversion module to 12bit RGB values
cpu65xx_e.vhd		6502 core vhdl header
cpu65xx_fast.vhd	6502 core vhdl code
dram.v			DRAM module for internal FPGA SRAM memory implementation
kernal_rom.v		C16/Plus4 Kernal rom module
mos6529.v		MOS 6529 IO chip emulation module
mos8501.v		MOS 8501 CPU shell for 6502 core
palclockgen.v		Xilinx DCM module for PAL system clock signal
ps2receiver.v		PS2 keyboard receiver module
ram.v			Simulated RAM for testbench
ted.v			MOS 7360/8360 FPGA core

basic.hex		C16/Plus4 BASIC rom hexadecimal dump
Diag264_NTSC.hex	Diag264 NTSC kernal hexadecimal dump
Diag264_PAL.hex		Diag264 PAL kernal hexadecimal dump
kernal_NTSC.hex		C16/Plus4 NTSC Kernal rom hexadecimal dump
kernal_PAL.hex		C16/PLus4 PAL Kernal rom hexadecimal dump

TEDwing.ucf		Xilinx ucf file for Papilio TEDwing
bin2hex.pl		Perl script for creating hex dump of binary rom image files
  
c16_PAL.bit		A compiled PAL FPGATED core for Papilio platform using FPGATED wing


Installation instructions are for Xilinx FPGA platforms but the source files with the exception of palclockgen.v
and Xilinx ucf files can be used for other vendor's FPGAs. 
Some modules are using Xilinx specific (* RAM_STYLE="BLOCK" *) directive for forcing the synthesis tool to 
use FPGA internal block ram for certain arrays. In case of other vendor's FPGAs see vendor specific documentation
for generating block ram.

Building FPGATED on the Papilio Platform requires a suitable wing. One can use the Arcade megawing but it lacks
external memory and IEC bus for peripherial connections. Thus I recommend to build TEDwing designed by me. Look for
eagle PCB and schematic files in FPGATED source package.
Although FPGATED can be synthetised to a Papilio One board using Spartan3E chip, I recommend to go for Papilio Pro
platform which has external 8Mbyte SDRAM and a Spartan 6 LX9 FPGA which has more internal sram. In both cases there
are plenty of free resources on the FPGA for FPGATED (if you use external 64k ram).

Installation instructions:

1. Create a new project in Xilinx ISE Webpack and choose the proper FPGA family for the implementation.
2. Choose to use HDL verilog and vhdl for the design.
3. Add all *.v files to the project
4. Using ISE DCM wizard create a clock generator for FPGATED. 
   Use CLKFX output of DCM and specify 28.37515MHz PAL or 28.63636MHz for NTSC system
   This will be the main FPGA clock connected to the clk signal of all modules
   Modify C16.v to use proper DCM instantiation (out of scope of this document)
5. Open kernal_rom.v and uncomment the proper Kernal file (Kernal_NTSC.hex or Kernal_PAL.hex) to use.
   You can even use a custom rom or JiffyDos if you own it (JiffyDos is working fine, I have tested).
   Diag264 roms are included for testing purposes.
6. If you don't use TEDwing modify or replace TEDwing.ucf file for proper pinout setup
7. Video output of FPGATED is a PAL/NTSC RGBS signal so you will need a VGA->scart custom cable to
   hook it up to a monitor or television. The cable is identical to minimig scart cables (see internet for wiring diagram)

Enjoy FPGATED.

See https://hackaday.io/project/11460-fpgated for detailed installation instructions.

TED module signals:

 input wire clk			main FPGA clock must be 4*dot clk so 28.375152MHz for PAL and 28.63636 for NTSC 
 input wire [15:0] addr_in	16 bits address bus in
 output wire [15:0] addr_out	16 bits address bus out
 input wire [7:0] data_in	8 bits data bus in
 output wire [7:0] data_out	8 bits data bus out
 input wire rw			RW signal to TED, low during write, high during read (real TED pulls it high during reads)
 output wire cpuclk		this is a CPU clock out for external real CPU
 output wire [6:0] color	7 bits color code using TED's color palette values
 output wire csync		composite sync signal for PAL/NTSC displays
 output wire irq		active low IRQ signal to CPU
 output wire ba			BA (or with other name RDY) signal to 8501 CPU 
 output reg mux			MUX signal, identical to original
 output reg ras			RAS signal, identical to original
 output reg cas			CAS signal, identical to original
 output reg cs0			CS0 signal, identical to original
 output reg cs1			CS1 signal, identical to original
 output reg aec			AEC signal, identical to original
 output wire snd		Sound output. PWM modulated sound, needs a low pass filter outside the FPGA
 input wire [7:0] k		Keyport in, same as in original TED
 output wire cpuenable		a short enable signal used for synchronous FPGA 6502 CPU clocking


Still to do:

FPGATED is not ready yet. I just released it in this state because I did not want to keep it in a secret longer before someone else
creates it. I have plans to continue.

- write a plus4 shell using Papilio Pro platform
- Jostick emulation on keyboard (as TEDwing doesn't have joystick ports) 
- scandoubler for VGA displays
- fix internal video shift mechanism for proper FLI emulation
- Chorma/Luma signal generation
- Try it in a real C16 or Plus4!

Contact: hegedusis@t-online.hu

Special Thanks to Levente Harsfalvi for the technical information on TED sound generators and for some other important hints!
Thanks to Laszlo Jozsef for the color conversion table and the Spartan6 board that I have never had time to build...
