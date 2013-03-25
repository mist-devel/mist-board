// Copyright 2006, 2007 Dennis van Weeren
//
// This file is part of Minimig
//
// Minimig is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Minimig is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
//
// This is the top module for the Minimig rev1.0 board
//
// 19-03-2005 	-started coding
// 10-04-2005	-added cia's 
//				-verified timers a/b and I/O ports
// 11-04-2005	-adapted top to cleaned up address decoder
//				-connected cia's to .clk(~qclk) and .tick(e) for testing
// 13-04-2005	-_foe and _loe are now made with clocks driving FF's
//				-sram_bridge now also gets .clk(clk)
// 18-04-2005	-added second synchronisation latch for mreset
// 19-04-2005	-bootrom is now 2Kbyte large
// 05-05-2005	-made preparations for dma (bus multiplexers between agnus and cpu)
// 15-05-2005	-added denise
// 				-connected vertb (vertical blank intterupt) to int3 input of paula
// 18-05-2005	-removed interlaced top input pin
// 28-06-2005	-done some experimentation to solve logic loop in Agnus
// 17-07-2005	-connected second ram bank to hold kickstart rom
// 				-added ovl (kickstart overlay) and boot (bootrom overlay) signals
//				-wired cia in/out ports more correctly
//				-wired vsync/hsync to cia's
// 18-07-2005	-experimented to get kickstart running
// 20-07-2005	-still experimenting..
// 07-08-2005	-Jahoeee!! kickstart doesn't guru anymore but 'clicks' the floppy drive !
//				-the guru's were caused by spurious writes to ram which is fixed now in the sram controller
//				-unfortunately still no insert workbench screen but that may be caused by the missing blitter
// 04-09-2005	-added blitter finished interrupt
// 11-09-2005	-added 2meg addressing for Agnus
// 13-09-2005	-added 4bit (per color) video output
// 16-10-2005	-added user IO module
// 23-10-2005	-added dmal signal wire
// 08-11-2005	-fixed typo in instantiation of Paula
// 21-11-2005	-added some signals to handle floppy
// 22-11-2005	-adapted to new add-on develop board
//				-added joystick 1 port
// 10-12-2005	-done some experimentation to find floppy bug
// 21-12-2005	-reworked code to use new style gary module
// 27-12-2005	-added dskindx interrupt
// 03-01-2006	-added dmas to avoid interference with copper cycles
// 11-01-2006	-added Amber
// 15-01-2006	-added syscontrol module to handle automatic boot sequence
// 22-01-2006	-removed _csync port from agnus
// 23-01-2006	-added fastblit input
// 24-01-2006	-cia's now count positive _hsync/_vsync transitions
// 14-02-2006	-code clean up
//				-added fastchip input
// 19-02-2006	-improved indx disk interrupt timing
//				-cia timers now connect to sol/sof
// 12-11-2006	-started porting code to Minimig rev1.0 board
// 17-11-2006	-added address decoding for Minimig rev1.0 ram
// 22-11-2006	-added keyboard reset
// 27-11-2006	-code adapted to new synchronous bootrom
// 03-12-2006	-added dimming powerled
// 11-12-2006	-updated code to new ciaa
// 27-12-2006	-updated code to new ciab
// 24-06-2007	-moved cpu/sram/clock and syscontrol to this file to reduce number of source files
//
// TODO: 		-fixs bug and implement things I forgot.....

//JB:
// 2008-07-17
//	- scan doubler with vertical and horizontal interpolation
//	- transparent osd window
//	- selected osd line highlight
//	- osd control by joystick (up and down pressed simultaneously invoke menu) 
//	- memory configuration from osd (512KB chip, 1MB chip, 512KB chip/512KB slow, 1MB chip/512KB slow)
//	- video interpolation filter configuration from osd (vertical and horizontal)
//	- user reset accessible from osd
//	- user reset to bootloader (kickstart reloading)
//	- new bootloader (text messages during kickstart loading)
//	- ECS blittter
//	- PAL/NTSC selection
//	- modified display dma engine (better compatibility)
//	- modified sprite dma engine (better compatibility)
//	- modified copper timing (better compatibility) 
//	- modified floppy interface (better read and write support)
//	- Action Replay III module for debugging (takes 512KB memory bank)
//
// Thanks to:
// Dennis for his great Minimig
// Loriano for impressive enclosure 
// Darrin and Oscar for their ideas, support and help
// Toni for his indispensable help and logic analyzer (and WinUAE :-)
//
// 2008-09-22 	- code clean-up
// 2008-09-23	- added c1 and c3 clock anable signals
//				- adapted sram bridge to use only clk28m clock
// 2008-09-24	- added support for floppy _sel[3:1] signals
// 2008-11-14	- ram interface synchronous with clk28m, 70ns access cycle
// 2009-04-21	- code clean up
//
// Thanks to Loriano, Darrin, Richard, Edwin, Sascha, Peter and others for their help, support, ideas, testing, bug reports and feature requests.
//
// 2009-05-17	- hires OSD
// 2009-05-23	- more cycle exact CPU bus timing during CIA access
// 2009-05-24	- clean-up & renaming
// 2009-05-29	- changed blitter timing to be more cycle exact
// 2009-06-09	- fixed disk index pulses to 5 Hz (300 RPM)
// 2009-06-10	- fixed non-interlaced frames to be long
// 2009-06-11	- fixed serial port divider
// 2009-06-12	- CIA's SDR register returns written value
// 2009-07-01	- enabling of ddfstrt/ddfstop ECS extension bits is configurable
// 2009-08-11	- support for second hardfile
// 2009-08-16	- Action Replay problem fixed (thanks Sascha)
// 2009-12-15 - improved blitter data flow
// 2009-12-16 - improved bitplane dma timing
//        - Denise id is selectable
// 2010-05-30 - htotal changed
// 2010-07-27 - fixed isue with external reset
// 2010-07-28 - added vsync for the MCU
// 2010-08-05 - added cache for the CPU
// 2010-08-15 - added joystick emulation
//
// SB:
// 2010-12-22 - better drive step sound at 31KHz mode
// 2011-03-06 - changed autofire function to handless mode
// 2011-03-08 - added dip and fat agnus DIWSTRT handling (fix RoboCop2)
// 2011-04-02 - added functional ciaa port b (parallel) register to let Unreal game work and some trainer store data
// 2011-04-04 - added pwm controlled power-led at "off" state and active Turbo mode (thanks Herzi for the idea)
// 2011-04-10 - added readable VPOSW and VHPOSW register (fix for RSI slideshow)
// 11-04-2011 - autofire function toggle able via capslock / led status
// 2011-04-24 - fixed CIA TOD read
// 2011-07-21 - changed '#' key scan code, thanks Chris
//
// TobiFlex(TF):
// 2012-02-12  - change sigma/delta module
//
// SB:
// 2012-03-23 - fixed sprite enable signal (coppermaster demo)

module Minimig1
(
	//m68k pins
	input	[23:1] cpu_address,	// m68k address bus
	output 	[15:0] cpu_data,	// m68k data bus
	input	[15:0] cpudata_in,	// m68k data in
	output	[2:0] _cpu_ipl,		// m68k interrupt request
	input	_cpu_as,			// m68k address strobe
	input	_cpu_uds,			// m68k upper data strobe
	input	_cpu_lds,			// m68k lower data strobe
	input	cpu_r_w,			// m68k read / write
	output	_cpu_dtack,			// m68k data acknowledge
	output	_cpu_reset,			// m68k reset
	input	cpu_clk,			// m68k clock
	//sram pins
	output	[15:0] ram_data,	//sram data bus
	input	[15:0] ramdata_in,		//sram data bus in
	output	[21:1] ram_address,	//sram address bus
	output	[3:0] _ram_ce,		//sram chip enable
	output	_ram_bhe,			//sram upper byte select
	output	_ram_ble,			//sram lower byte select
	output	_ram_we,			//sram write enable
	output	_ram_oe,			//sram output enable
	//system	pins
//  input mclk,       // master system clock (4.433619MHz)
	input	clk,				//system clock (7.09379 MHz)
	input	clk28m,				//28.37516 MHz clock
	//rs232 pins
	input	rxd,				//rs232 receive
	output	txd,				//rs232 send
	input	cts,				//rs232 clear to send
	output	rts,				//rs232 request to send
	//I/O
	input	[5:0]_joy1,			//joystick 1 [fire2,fire,up,down,left,right] (default mouse port)
	input	[5:0]_joy2,			//joystick 2 [fire2,fire,up,down,left,right] (default joystick port)
  input [2:0] mouse_btn, // mouse buttons 
  input kbd_mouse_strobe,
  input [1:0] kbd_mouse_type,
  input [7:0] kbd_mouse_data,
  input joy_emu_en, // enable keyboard joystick emulation
	input	_15khz,				//scandoubler disable
	output	pwrled,				//power led
	inout	msdat,				//PS2 mouse data
	inout	msclk,				//PS2 mouse clk
	inout	kbddat,				//PS2 keyboard data
	inout	kbdclk,				//PS2 keyboard clk
	//host controller interface (SPI)
	input	[2:0]_scs,			//SPI chip select
	input	direct_sdi,			//SD Card direct in
	input	sdi,				//SPI data input
	inout	sdo,				//SPI data output
	input	sck,				//SPI clock
	//video
	output	_hsync,				//horizontal sync
	output	_vsync,				//vertical sync
	output	[3:0] red,			//red
	output	[3:0] green,		//green
	output	[3:0] blue,			//blue
	//audio
	output	left,				//audio bitstream left
	output	right,				//audio bitstream right
	output	[14:0]ldata,			//left DAC data
	output	[14:0]rdata, 			//right DAC data
	//user i/o
	output	gpio,
  output  [1:0] cpu_config,
  output  [5:0] memcfg,
  output  drv_snd,
  output  init_b,       // vertical sync for MCU (sync OSD update)
  // fifo / track display
	output  [7:0]trackdisp,
	output  [13:0]secdisp,
  output  floppy_fwr,
  output  floppy_frd,
  output  hd_fwr,
  output  hd_frd
);

//--------------------------------------------------------------------------------------

	parameter [0:0] NTSC = 1'b0;	//Agnus type (PAL/NTSC)

//--------------------------------------------------------------------------------------

//local signals for data bus
wire		[15:0] cpu_data_in;		//cpu data bus in
wire		[15:0] cpu_data_out;	//cpu data bus out
wire		[15:0] ram_data_in;		//ram data bus in
wire		[15:0] ram_data_out;	//ram data bus out
wire		[15:0] custom_data_in;	//custom chips data bus in
wire		[15:0] custom_data_out;	//custom chips data bus out
wire		[15:0] agnus_data_out;	//agnus data out
wire		[15:0] paula_data_out;	//paula data bus out
wire		[15:0] denise_data_out;	//denise data bus out
wire		[15:0] user_data_out;	//user IO data out
wire		[15:0] gary_data_out;	//data out from memory bus multiplexer
wire		[15:0] gayle_data_out;	//Gayle data out
wire		[15:0] boot_data_out;	//boot rom data bus out
wire		[15:0] cia_data_out;	//cia A+B data bus out
wire		[15:0] ar3_data_out;	//Action Replay data out
wire    [15:0] boot_data;     // boot rom data out

//local signals for spi bus
wire		paula_sdo; 				//paula spi data out
wire		user_sdo;				//userio spi data out

//local signals for address bus
wire		[23:1] cpu_address_out;	//cpu address out
wire		[20:1] dma_address_out;	//agnus address out
wire		[18:1] ram_address_out;	//ram address out

//local signals for control bus
wire		ram_rd;					//ram read enable
wire		ram_hwr;				//ram high byte write enable 
wire		ram_lwr;				//ram low byte write enable 
wire		cpu_rd; 				//cpu read enable
wire		cpu_hwr;				//cpu high byte write enable
wire		cpu_lwr;				//cpu low byte write enable
wire		cck;					//colour clock (chipset dma slots indication)

//register address bus
wire		[8:1] reg_address; 		//main register address bus

//rest of local signals
wire		kbdrst;					//keyboard reset
wire		reset;					//global reset
wire    aflock;
//wire		clk;					//bus clock
//wire		clk28m;					//28MHz clock for Amber (and ECS Denise in future)
wire		c1,c3;					//clock enable signals
wire		[9:0] eclk;				//E clock enable
wire		dbr;					//data bus request, Agnus tells CPU that she is using the bus
wire		dbwe;					//data bus write enable, Agnus tells the RAM it's writing data
wire		dbs;					//data bus slow down, used for slowing down CPU access to chip, slow and custor register address space
wire		xbs;					//cross bridge access (memory and custom registers)
wire		ovl;					//kickstart overlay enable
wire		_led;					//power led
wire		boot;    				//bootrom overlay enable
wire		[3:0] sel_chip;			//chip ram select
wire		[2:0] sel_slow;			//slow ram select
wire		sel_kick;				//rom select
wire		sel_cia;				//CIA address space
wire		sel_reg;				//chip register select
wire		sel_cia_a;				//cia A select
wire		sel_cia_b;				//cia B select
wire		sel_boot;				//boot rom select
wire		int2;					//intterrupt 2
wire		int3;					//intterrupt 3 
wire		int6;					//intterrupt 6
wire		[7:0] osd_ctrl;			//OSD control
wire    kb_lmb;
wire    kb_rmb;
wire    [5:0] kb_joy2;
wire		freeze;					//Action Replay freeze button
wire		_fire0;					//joystick 1 fire signal to cia A
wire		_fire1;					//joystick 2 fire signal to cia A
wire		[3:0] audio_dmal;		//audio dma data transfer request from Paula to Agnus
wire		[3:0] audio_dmas;		//audio dma location pointer restart from Paula to Agnus
wire		disk_dmal;				//disk dma data transfer request from Paula to Agnus
wire		disk_dmas;				//disk dma special request from Paula to Agnus
wire		index;					//disk index interrupt

//local video signals
wire		blank;					//blanking signal
wire		sol;					//start of video line
wire		sof;					//start of video frame
wire    vbl_int;        // vertical blanking interrupt
wire		strhor_denise;			//horizontal strobe for Denise
wire		strhor_paula;			//horizontal strobe for Paula
wire		[3:0]red_i;				//denise red (internal)
wire		[3:0]green_i;			//denise green (internal)
wire		[3:0]blue_i;			//denise blue (internal)
wire		osd_blank;				//osd blanking 
wire		osd_pixel;				//osd pixel(video) data
wire    osd_enable;
wire		_hsync_i;				//horizontal sync (internal)
wire		_vsync_i;				//vertical sync (internal)
wire		_csync_i;				//composite sync (internal)
wire		[8:1] htotal;			//video line length (140ns units)

//local floppy signals (CIA<-->Paula)
wire		_step;					//step heads of disk
wire		direc;					//step heads direction
wire		_sel0;					//disk0 select 	
wire		_sel1;					//disk1 select 	
wire		_sel2;					//disk2 select 	
wire		_sel3;					//disk3 select 	
wire		side;					//upper/lower disk head
wire		_motor;					//disk motor control
wire		_track0;				//track zero detect
wire		_change;				//disk has been removed from drive
wire		_ready;					//disk is ready
wire		_wprot;					//disk is write-protected

//--------------------------------------------------------------------------------------

wire	bls;					//blitter slowdown - required for sharing bus cycles between Blitter and CPU

wire	int7;					//int7 interrupt request from Action Replay
wire	[2:0] _iplx;			//interrupt request lines from Paula
wire	selcart;				//Action Replay RAM select
wire	ovr;					//overide chip memmory decoding

wire	usrrst;					//user reset from osd interface
wire	bootrst;				//user reset to bootloader
wire	[1:0] lr_filter;		//lowres interpolation filter mode: bit 0 - horizontal, bit 1 - vertical
wire	[1:0] hr_filter;		//hires interpolation filter mode: bit 0 - horizontal, bit 1 - vertical
wire	[1:0] scanline;			//scanline effect configuration
wire	hires;					//hires signal from Denise for interpolation filter enable in Amber
wire	aron;					//Action Replay is enabled
wire	cpu_speed;				//requests CPU to switch speed mode
wire	turbo;					//CPU is working in turbo mode
wire	[5:0] memory_config;	//memory configuration
wire	[3:0] floppy_config;	//floppy drives configuration (drive number and speed)
wire	[3:0] chipset_config;	//chipset features selection
wire	[2:0] ide_config;		//HDD & HDC config: bit #0 enables Gayle, bit #1 enables Master drive, bit #2 enables Slave drive

//gayle stuff
wire	sel_ide;				//select IDE drive registers
wire	sel_gayle;				//select GAYLE control registers
wire	gayle_irq;				//interrupt request
wire  gayle_nrdy;       // HDD fifo is not ready for reading
//emulated hard disk drive signals
wire	hdd_cmd_req;			//hard disk controller has written command register and requests processing
wire	hdd_dat_req;			//hard disk controller requests data from emulated hard disk drive
wire	[2:0] hdd_addr;			//emulated hard disk drive register address bus
wire	[15:0] hdd_data_out;	//data output port of emulated hard disk drive
wire	[15:0] hdd_data_in;		//data input port of emulated hard disk drive
wire	hdd_wr;					//register write strobe
wire	hdd_status_wr;			//status register write strobe
wire	hdd_data_wr;			//data port write strobe
wire	hdd_data_rd;			//data port read strobe

wire	[7:0] bank;				//memory bank select

wire	keyboard_disabled;		//disables Amiga keyboard while OSD is active
wire	disk_led;				//floppy disk activity LED

reg		ntsc = NTSC;			//PAL/NTSC video mode selection

wire  [5:0] mou_emu;
wire  [5:0] joy_emu;

wire  dtr;


//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

assign memcfg = memory_config;

// SPI clock buffer
//wire buf_sck;
//BUFG sckbuf1 ( .I(sck), .O(buf_sck) );

// power led control
reg [3:0] led_cnt;
reg led_dim;

assign pwrled = (_led & (led_dim | ~turbo)) ? 1'b0 : 1'b1; // led dim at off-state and active turbo mode
//assign pwrled = _led ? 1'b0 : 1'b1;

// power led pwm 
always @(posedge clk)
  if (_hsync)
    led_cnt <= led_cnt + 1;

always @(posedge clk)
  if (!_hsync)
    led_dim <= |led_cnt;

// drive step sound emulation
reg _step_del;
always @(posedge clk)
  _step_del <= _step; // delayed version of _step for edge detection

wire  step_pulse;
assign  step_pulse = _step & ~_step_del; // rising edge detection

reg sol_del;
always @(posedge clk)
  sol_del <= sol; // delayed version of sol (Amiga display line) for edge detection

wire  sol_pulse;
assign sol_pulse = sol & ~sol_del; // rising edge detection

reg [3:0] drv_cnt;
always @(posedge clk)
  if (drv_cnt != 0 && sol_pulse || drv_cnt == 0 && step_pulse && !boot && _change) // count only sol pulses when counter is not zero or step pulses and bootloader is not active
    drv_cnt <= drv_cnt + 1;

reg drvsnd;
always @(posedge clk)
  drvsnd <= |drv_cnt; // high when at least one bit of drv_cnt vector is not zero (| is the reduction operator) and any drive has an inserted disk

assign drv_snd = drvsnd ? 1'b1 : 1'b0;

//extra memory Chip Selects for additional RAM chips
assign gpio = 1'bz;

// NTSC/PAL switching is controlled by OSD menu, change requires reset to take effect
always @(posedge clk)
	if (reset)
		ntsc <= chipset_config[1];

// vertical sync for the MCU
reg vsync_del = 1'b0;   // delayed vsync signal for edge detection
reg vsync_t = 1'b0;   // toggled vsync output

always @(posedge clk)
  vsync_del <= _vsync_i;
  
always @(posedge clk)
  if (~_vsync_i && vsync_del)
    vsync_t <= ~vsync_t;

assign init_b = vsync_t;


//--------------------------------------------------------------------------------------

//instantiate agnus
Agnus AGNUS1
(
	.clk(clk),
	.clk28m(clk28m),
	.cck(cck),
	.reset(reset),
	.aen(sel_reg),
	.rd(cpu_rd),
	.hwr(cpu_hwr),
	.lwr(cpu_lwr),
	.data_in(custom_data_in),
	.data_out(agnus_data_out),
	.address_in(cpu_address_out[8:1]),
	.address_out(dma_address_out),
	.reg_address_out(reg_address),
	.dbr(dbr),
	.dbwe(dbwe),
	._hsync(_hsync_i),
	._vsync(_vsync_i),
	._csync(_csync_i),
	.blank(blank),
	.sol(sol),
	.sof(sof),
  .vbl_int(vbl_int),
	.strhor_denise(strhor_denise),
	.strhor_paula(strhor_paula),
	.htotal(htotal),
	.int3(int3),
	.audio_dmal(audio_dmal),
	.audio_dmas(audio_dmas),
	.disk_dmal(disk_dmal),
	.disk_dmas(disk_dmas),
	.bls(bls),
	.ntsc(ntsc),
  .a1k(chipset_config[2]),
	.ecs(chipset_config[3]),
	.floppy_speed(floppy_config[0]),
	.turbo(turbo)
);

//instantiate paula
Paula PAULA1
(
	.clk(clk),
  .clk28m(clk28m),
	.cck(cck),
	.reset(reset),
	.reg_address_in(reg_address),
	.data_in(custom_data_in),
	.data_out(paula_data_out),
	.txd(txd),
	.rxd(rxd),
  .ntsc(ntsc),
	.sof(sof),
  .strhor(strhor_paula),
  .vblint(vbl_int),
	.int2(int2|gayle_irq),
	.int3(int3),
	.int6(int6),
	._ipl(_iplx),
	.audio_dmal(audio_dmal),
	.audio_dmas(audio_dmas),
	.disk_dmal(disk_dmal),
	.disk_dmas(disk_dmas),
	._step(_step),
	.direc(direc),
	._sel({_sel3,_sel2,_sel1,_sel0}),
	.side(side),
	._motor(_motor),
	._track0(_track0),
	._change(_change),
	._ready(_ready),
	._wprot(_wprot),
  .index(index),
	.disk_led(disk_led),
	._scs(_scs[0]),
	.sdi(sdi),
	.sdo(paula_sdo),
	.sck(sck),
	.left(left),
	.right(right),
	.ldata(ldata),
	.rdata(rdata),

	.floppy_drives(floppy_config[3:2]),
	//ide stuff
	.direct_scs(~_scs[2]),
	.direct_sdi(direct_sdi),
	.hdd_cmd_req(hdd_cmd_req),	
	.hdd_dat_req(hdd_dat_req),
	.hdd_addr(hdd_addr),
	.hdd_data_out(hdd_data_out),
	.hdd_data_in(hdd_data_in),
	.hdd_wr(hdd_wr),
	.hdd_status_wr(hdd_status_wr),
	.hdd_data_wr(hdd_data_wr),
	.hdd_data_rd(hdd_data_rd),
  // fifo / track display
	.trackdisp(trackdisp),
	.secdisp(secdisp),
  .floppy_fwr (floppy_fwr),
  .floppy_frd (floppy_frd)
);

//instantiate user IO
userio USERIO1 
(	
	.clk(clk),
	.reset(reset),
	.clk28m(clk28m),
	.c1(c1),
	.c3(c3),
	.sol(sol),
	.sof(sof),
	.reg_address_in(reg_address),
	.data_in(custom_data_in),
	.data_out(user_data_out),
	.ps2mdat(msdat),
	.ps2mclk(msclk),
	._fire0(_fire0),
	._fire1(_fire1),
  .aflock(aflock),
	._joy1(_joy1),
	._joy2(_joy2),
   .mouse_btn(mouse_btn),
   .kbd_mouse_type(kbd_mouse_type),
   .kbd_mouse_strobe(kbd_mouse_strobe),
   .kbd_mouse_data(kbd_mouse_data), 
   .osd_ctrl(osd_ctrl),
	.keyboard_disabled(keyboard_disabled),
	._scs(_scs[1]),
	.sdi(sdi),
	.sdo(user_sdo),
	.sck(sck),
	.osd_blank(osd_blank),
	.osd_pixel(osd_pixel),
  .osd_enable(osd_enable),
	.lr_filter(lr_filter),
	.hr_filter(hr_filter),
	.memory_config(memory_config),
	.chipset_config(chipset_config),
	.floppy_config(floppy_config),
	.scanline(scanline),
	.ide_config(ide_config),
  .cpu_config(cpu_config),
	.usrrst(usrrst),
	.bootrst(bootrst)
);

//assign cpu_speed = (chipset_config[0] & ~int7 & ~freeze & ~ovr);
assign cpu_speed = 1'b0;

//instantiate Denise
Denise DENISE1
(		
  .clk28m(clk28m),
	.clk(clk),
  .c1(c1),
  .c3(c3),
  .cck(cck),
	.reset(reset),
	.strhor(strhor_denise),
	.reg_address_in(reg_address),
	.data_in(custom_data_in),
	.data_out(denise_data_out),
	.blank(blank),
	.red(red_i),
	.green(green_i),
	.blue(blue_i),
  .ecs(chipset_config[3]),
  .a1k(chipset_config[2]),
	.hires(hires)
);

//instantiate Amber
Amber AMBER1
(		
	.clk28m(clk28m),
	.dblscan(_15khz),
	.lr_filter(lr_filter),
	.hr_filter(hr_filter),
	.scanline(scanline),
	.htotal(htotal),
	.hires(hires),
	.osd_blank(osd_blank),
	.osd_pixel(osd_pixel),
	.red_in(red_i),
	.blue_in(blue_i),
	.green_in(green_i),
	._hsync_in(_hsync_i),
	._vsync_in(_vsync_i),
	._csync_in(_csync_i),
	.red_out(red),
	.blue_out(blue),
	.green_out(green),
	._hsync_out(_hsync),
	._vsync_out(_vsync)
);

//instantiate cia A
ciaa CIAA1
(
	.clk(clk),
	.aen(sel_cia_a),
	.rd(cpu_rd),
	.wr(cpu_lwr|cpu_hwr),
	.reset(reset),
	.rs(cpu_address_out[11:8]),
	.data_in(cpu_data_out[7:0]),
	.data_out(cia_data_out[7:0]),
	.tick(_vsync_i),
	.eclk(eclk[8]),
	.irq(int2),
	.porta_in({_fire1,_fire0,_ready,_track0,_wprot,_change}),
	.porta_out({_led,ovl}),
	.kbdrst(kbdrst),
	.kbddat(kbddat),
	.kbdclk(kbdclk),
   .kbd_mouse_type(kbd_mouse_type),
   .kbd_mouse_strobe(kbd_mouse_strobe),
   .kbd_mouse_data(kbd_mouse_data), 
	.keyboard_disabled(keyboard_disabled),
	.osd_ctrl(osd_ctrl),
  ._lmb(kb_lmb),
  ._rmb(kb_rmb),
  ._joy2(kb_joy2),
  .aflock(aflock),
	.freeze(freeze),
	.disk_led(disk_led),
  .osd_enable(osd_enable),
  .mou_emu (mou_emu),
  .joy_emu (joy_emu),
  .joy_emu_en(joy_emu_en)
);

//instantiate cia B
ciab CIAB1 
(
	.clk(clk),
	.aen(sel_cia_b),
	.rd(cpu_rd),
	.wr(cpu_hwr|cpu_lwr),
	.reset(reset),
	.rs(cpu_address_out[11:8]),
	.data_in(cpu_data_out[15:8]),
	.data_out(cia_data_out[15:8]),
	.tick(_hsync_i),
	.eclk(eclk[8]),
	.irq(int6),
	.flag(index),
	.porta_in({1'b0,cts,1'b0}),
	.porta_out({dtr,rts}),
	.portb_out({_motor,_sel3,_sel2,_sel1,_sel0,side,direc,_step})
);


//instantiate cpu bridge
m68k_bridge CPU1 
(
	.clk28m(clk28m),
  .blk(scanline[1]),
	.c1(c1),
	.c3(c3),
	.cck(cck),
	.clk(clk),
  .cpu_clk(cpu_clk),
	.eclk(eclk),
	.vpa(sel_cia),
	.dbr(dbr),
	.dbs(dbs),
	.xbs(xbs),
  .nrdy(gayle_nrdy),
	.bls(bls),
	.cpu_speed(cpu_speed),
  .memory_config(memory_config[3:0]),
	.turbo(turbo),
	._as(_cpu_as),
	._lds(_cpu_lds),
	._uds(_cpu_uds),
	.r_w(cpu_r_w),
	._dtack(_cpu_dtack),
	.rd(cpu_rd),
	.hwr(cpu_hwr),
	.lwr(cpu_lwr),
	.address(cpu_address),
	.address_out(cpu_address_out),
	.cpudatain(cpudata_in),
	.data(cpu_data),
	.data_out(cpu_data_out),
	.data_in(cpu_data_in)
);

//instantiate RAM banks mapper
bank_mapper BMAP1
(
	.chip0((~ovr|~cpu_rd|dbr) & sel_chip[0]),
	.chip1(sel_chip[1]),
	.chip2(sel_chip[2]),
	.chip3(sel_chip[3]),	
	.slow0(sel_slow[0]),
	.slow1(sel_slow[1]),
	.slow2(sel_slow[2]),
	.kick(sel_kick),
	.cart(selcart),
	.aron(aron),
  .ecs(chipset_config[3]),
	.memory_config(memory_config[3:0]),
	.bank(bank)
);

//instantiate sram bridge
sram_bridge RAM1 
(
	.clk28m(clk28m),
	.c1(c1),
	.c3(c3),	
	.bank(bank),
	.address_in(ram_address_out),
	.data_in(ram_data_in),
	.data_out(ram_data_out),
	.rd(ram_rd),
	.hwr(ram_hwr),
	.lwr(ram_lwr),
	._bhe(_ram_bhe),
	._ble(_ram_ble),
	._we(_ram_we),
	._oe(_ram_oe),
	._ce({_ram_ce[3],_ram_ce[2],_ram_ce[1],_ram_ce[0]}),
	.address(ram_address),
	.data(ram_data),	
	.ramdata_in(ramdata_in)	
);

ActionReplay CART1
(
	.clk(clk),
	.reset(reset),
	.cpu_address(cpu_address),
	.cpu_address_in(cpu_address_out),
	.cpu_clk(cpu_clk),
	._cpu_as(_cpu_as),
	.reg_address_in(reg_address),
	.reg_data_in(custom_data_in),
	.data_in(cpu_data_out),
	.data_out(ar3_data_out),
	.cpu_rd(cpu_rd),
	.cpu_hwr(cpu_hwr),
	.cpu_lwr(cpu_lwr),
	.dbr(dbr),
	.boot(boot),
	.freeze(freeze),
	.int7(int7),
	.ovr(ovr),
	.selmem(selcart),
	.aron(aron)
);

//level 7 interrupt for CPU
assign _cpu_ipl = int7 ? 3'b000 : _iplx;	//m68k interrupt request

//instantiate gary
gary GARY1 
(
	.cpu_address_in(cpu_address_out),
	.dma_address_in(dma_address_out),
	.ram_address_out(ram_address_out),
	.cpu_data_out(cpu_data_out),
	.cpu_data_in(gary_data_out),
	.custom_data_out(custom_data_out),
	.custom_data_in(custom_data_in),
	.ram_data_out(ram_data_out),
	.ram_data_in(ram_data_in),
	.cpu_rd(cpu_rd),
	.cpu_hwr(cpu_hwr),
	.cpu_lwr(cpu_lwr),
	.ovl(ovl),
	.boot(boot),
	.dbr(dbr),
	.dbwe(dbwe),
	.dbs(dbs),
	.xbs(xbs),
	.memory_config(memory_config[3:0]),
	.hdc_ena(ide_config[0]), // Gayle decoding enable	
	.ram_rd(ram_rd),
	.ram_hwr(ram_hwr),
	.ram_lwr(ram_lwr),
  .ecs(chipset_config[3]),
  .a1k(chipset_config[2]),
	.sel_chip(sel_chip),
	.sel_slow(sel_slow),
	.sel_kick(sel_kick),
	.sel_boot(sel_boot),
	.sel_cia(sel_cia),
	.sel_reg(sel_reg),
	.sel_cia_a(sel_cia_a),
	.sel_cia_b(sel_cia_b),
	.sel_ide(sel_ide),
	.sel_gayle(sel_gayle)
);

gayle GAYLE1
(
	.clk(clk),
	.reset(reset),
	.address_in(cpu_address_out),
	.data_in(cpu_data_out),
	.data_out(gayle_data_out),
	.rd(cpu_rd),
	.hwr(cpu_hwr),
	.lwr(cpu_lwr),
	.sel_ide(sel_ide),
	.sel_gayle(sel_gayle),
	.irq(gayle_irq),
  .nrdy(gayle_nrdy),
	.hdd_ena(ide_config[2:1]),

	.hdd_cmd_req(hdd_cmd_req),
	.hdd_dat_req(hdd_dat_req),
	.hdd_data_in(hdd_data_in),
	.hdd_addr(hdd_addr),
	.hdd_data_out(hdd_data_out),
	.hdd_wr(hdd_wr),
	.hdd_status_wr(hdd_status_wr),
	.hdd_data_wr(hdd_data_wr),
	.hdd_data_rd(hdd_data_rd),
  .hd_fwr(hd_fwr),
  .hd_frd(hd_frd)
);
	
//instantiate boot rom
//bootrom BOOTROM1 
//(	
//	.clk(clk),
//	.aen(sel_boot),
//	.rd(cpu_rd),
//	.address_in(cpu_address_out[10:1]),
//	.data_out(boot_data_out)
//);

//JBboot BOOTROM1 
//( 
//  .clock(clk),
//  .address(cpu_address[10:1]),
//  .q(boot_data)
//);

amiga_boot BOOTROM1 (
  .clock    (clk),
  .address  (cpu_address[8:1]),
  .q        (boot_data)
);

assign boot_data_out[15:0] = (sel_boot) ? boot_data[15:0] : 16'h0000;

//instantiate system control
syscontrol CONTROL1 
(	
	.clk(clk),
	.cnt(sof),
	.mrst(kbdrst | usrrst),
	.boot_done(sel_cia_a & sel_cia_b),
	.reset(reset),
	.boot(boot),
	.boot_rst(bootrst)
);

//instantiate clock generator
clock_generator CLOCK1
(	
//	.mclk(mclk),
	.clk28m(clk28m),	// 28.37516 MHz clock output
	.c1(c1),			// clock enable signal
	.c3(c3),			// clock enable signal
	.cck(cck),			// colour clock enable
	.clk(clk),			// 7.09379  MHz clock output
//	.cpu_clk(cpu_clk),
//	.turbo(turbo),
	.eclk(eclk)			// ECLK enable (1/10th of CLK)
);


//-------------------------------------------------------------------------------------

//data multiplexer
assign cpu_data_in[15:0] = gary_data_out[15:0]
						 | boot_data_out[15:0]
						 | cia_data_out[15:0]
						 | ar3_data_out[15:0]
						 | gayle_data_out[15:0];

assign custom_data_out[15:0] = agnus_data_out[15:0]
							 | paula_data_out[15:0]
							 | denise_data_out[15:0]
							 | user_data_out[15:0];

//--------------------------------------------------------------------------------------

//spi multiplexer
//assign sdo = _scs[1] ? paula_sdo : user_sdo;
assign sdo = paula_sdo | user_sdo;
//assign sdo = (!_scs[0] || !_scs[1]) ? (paula_sdo | user_sdo) : 1'bz;

//--------------------------------------------------------------------------------------

//cpu reset and clock
assign _cpu_reset = ~reset;

//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//syscontrol handles the startup of the FGPA,
//after fpga config, it automatically does a global system reset and asserts boot.
//the boot signal puts gary in a special mode so that the bootrom
//is mapped into the system memory map.	The firmware in the bootrom
//then loads the kickstart via the diskcontroller into the kickstart ram area.
//When kickstart has been loaded, the bootrom asserts bootdone by selecting both cia's at once. 
//This resets the system for a second time but it also de-asserts boot.
//Thus, the system now boots as a regular amiga.
//Subsequent resets by asserting mrst will not assert boot again.
//
// JB:
// 2008-07-11	- reset to bootloader
// 2009-03-13	- shorter reset
// 2009-08-17	- reset generator modification

module syscontrol
(
	input	clk,			//bus clock
	input	cnt,			//pulses for counting
	input	mrst,			//master/user reset input
	input	boot_done,		//bootrom program finished input
	output	reset,			//global synchronous system reset
	output	boot,			//bootrom overlay enable output
	input	boot_rst		//reset to bootloader
);

//local signals
reg		smrst0, smrst1;					//registered input
reg		_boot = 0;
reg		[2:0] rst_cnt = 0;		//reset timer SHOULD BE CLEARED BY CONFIG
wire	_rst;					//local reset signal

//asynchronous mrst input synchronizer
always @(posedge clk) begin
  smrst0 <= mrst;
	smrst1 <= smrst0;
end

//reset timer and mrst control
always @(posedge clk)
	if (smrst1 || (boot && boot_done && _rst))
		rst_cnt <= 3'd0;
	else if (!_rst && cnt)
		rst_cnt <= rst_cnt + 3'd1;

assign _rst = rst_cnt[2];

//boot control
always @(posedge clk)
	if (boot_rst)
		_boot <= 1'd0;
	else if (boot_done)
		_boot <= 1'd1;

//global boot output
assign boot = ~_boot;

//global reset output
assign reset = ~_rst;

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//This module maps physical 512KB blocks of every memory chip to different memory ranges in Amiga
module bank_mapper
(
	input	chip0,				// chip ram select: 1st 512 KB block
	input	chip1,				// chip ram select: 2nd 512 KB block
	input	chip2,				// chip ram select: 3rd 512 KB block
	input	chip3,				// chip ram select: 4th 512 KB block
	input	slow0,				// slow ram select: 1st 512 KB block 
	input	slow1,				// slow ram select: 2nd 512 KB block 
	input	slow2,				// slow ram select: 3rd 512 KB block 
	input	kick,				// Kickstart ROM address range select
	input	cart,				// Action Reply memory range select
	input	aron,				// Action Reply enable
  input ecs,        // ECS chipset enable
	input	[3:0] memory_config,// memory configuration
	output	reg [7:0] bank		// bank select
);


always @(aron or memory_config or chip0 or chip1 or chip2 or chip3 or slow0 or slow1 or slow2 or kick or cart or ecs)
begin
  case ({aron,memory_config})
    5'b0_0000 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     kick,  1'b0,  1'b0, chip0 | chip1 | chip2 | chip3 }; // 0.5M CHIP
    5'b0_0001 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     kick,  1'b0, chip1 | chip3, chip0 | chip2 }; // 1.0M CHIP
    5'b0_0010 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     kick, chip2, chip1, chip0 }; // 1.5M CHIP
    5'b0_0011 : bank = {  1'b0,  1'b0, chip3,  1'b0,     kick, chip2, chip1, chip0 }; // 2.0M CHIP
    5'b0_0100 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     kick, slow0,  1'b0, chip0 | (chip1 & !ecs) | chip2 | (chip3 & !ecs) }; // 0.5M CHIP + 0.5MB SLOW
    5'b0_0101 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     kick, slow0, chip1 | chip3, chip0 | chip2 }; // 1.0M CHIP + 0.5MB SLOW
    5'b0_0110 : bank = {  1'b0,  1'b0,  1'b0, slow0,     kick, chip2, chip1, chip0 }; // 1.5M CHIP + 0.5MB SLOW
    5'b0_0111 : bank = {  1'b0,  1'b0, chip3, slow0,     kick, chip2, chip1, chip0 }; // 2.0M CHIP + 0.5MB SLOW
    5'b0_1000 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     kick, slow0, slow1, chip0 | chip1 | chip2 | chip3 }; // 0.5M CHIP + 1.0MB SLOW
    5'b0_1001 : bank = {  1'b0,  1'b0, slow1,  1'b0,     kick, slow0, chip1 | chip3, chip0 | chip2 }; // 1.0M CHIP + 1.0MB SLOW
    5'b0_1010 : bank = {  1'b0,  1'b0, slow1, slow0,     kick, chip2, chip1, chip0 }; // 1.5M CHIP + 1.0MB SLOW
    5'b0_1011 : bank = { slow1,  1'b0, chip3, slow0,     kick, chip2, chip1, chip0 }; // 2.0M CHIP + 1.0MB SLOW
    5'b0_1100 : bank = {  1'b0,  1'b0,  1'b0, slow2,     kick, slow0, slow1, chip0 | chip1 | chip2 | chip3 }; // 0.5M CHIP + 1.5MB SLOW
    5'b0_1101 : bank = {  1'b0,  1'b0, slow1, slow2,     kick, slow0, chip1 | chip3, chip0 | chip2 }; // 1.0M CHIP + 1.5MB SLOW
    5'b0_1110 : bank = {  1'b0, slow2, slow1, slow0,     kick, chip2, chip1, chip0 }; // 1.5M CHIP + 1.5MB SLOW
    5'b0_1111 : bank = { slow1, slow2, chip3, slow0,     kick, chip2, chip1, chip0 }; // 2.0M CHIP + 1.5MB SLOW
    
    5'b1_0000 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     kick,  cart,  1'b0, chip0 | chip1 | chip2 | chip3 }; // 0.5M CHIP
    5'b1_0001 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     kick,  cart, chip1 | chip3, chip0 | chip2 }; // 1.0M CHIP
    5'b1_0010 : bank = {  1'b0,  1'b0,  1'b0, chip2,     kick,  cart, chip1, chip0 }; // 1.5M CHIP
    5'b1_0011 : bank = {  1'b0,  1'b0, chip3, chip2,     kick,  cart, chip1, chip0 }; // 2.0M CHIP
    5'b1_0100 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     kick,  cart, slow0, chip0 | (chip1 & !ecs) | chip2 | (chip3 & !ecs) }; // 0.5M CHIP + 0.5MB SLOW
    5'b1_0101 : bank = {  1'b0,  1'b0,  1'b0, slow0,     kick,  cart, chip1 | chip3, chip0 | chip2 }; // 1.0M CHIP + 0.5MB SLOW
    5'b1_0110 : bank = {  1'b0,  1'b0, slow0, chip2,     kick,  cart, chip1, chip0 }; // 1.5M CHIP + 0.5MB SLOW
    5'b1_0111 : bank = {  1'b0, slow0, chip3, chip2,     kick,  cart, chip1, chip0 }; // 2.0M CHIP + 0.5MB SLOW
    5'b1_1000 : bank = {  1'b0,  1'b0, slow1,  1'b0,     kick,  cart, slow0, chip0 | chip1 | chip2 | chip3 }; // 0.5M CHIP + 1.0MB SLOW
    5'b1_1001 : bank = {  1'b0,  1'b0, slow1, slow0,     kick,  cart, chip1 | chip3, chip0 | chip2 }; // 1.0M CHIP + 1.0MB SLOW
    5'b1_1010 : bank = { slow1,  1'b0, slow0, chip2,     kick,  cart, chip1, chip0 }; // 1.5M CHIP + 1.0MB SLOW
    5'b1_1011 : bank = { slow1, slow0, chip3, chip2,     kick,  cart, chip1, chip0 }; // 2.0M CHIP + 1.0MB SLOW
    5'b1_1100 : bank = {  1'b0,  1'b0, slow1, slow2,     kick,  cart, slow0, chip0 | chip1 | chip2 | chip3 }; // 0.5M CHIP + 1.5MB SLOW
    5'b1_1101 : bank = {  1'b0, slow2, slow1, slow0,     kick,  cart, chip1 | chip3, chip0 | chip2 }; // 1.0M CHIP + 1.5MB SLOW
    5'b1_1110 : bank = { slow1, slow2, slow0, chip2,     kick,  cart, chip1, chip0 }; // 1.5M CHIP + 1.5MB SLOW
    5'b1_1111 : bank = { slow1, slow0, chip3, chip2,     kick,  cart, chip1, chip0 }; // 2.0M CHIP + 1.5MB SLOW
  endcase
end


endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// This module interfaces the minimig's synchronous bus to the asynchronous sram
// on the Minimig rev1.0 board
//
// JB:
// 2008-09-23	- generation of write strobes moved to clk28m clock domain

module sram_bridge
(
	//clocks
	input	clk28m,						// 28 MHz system clock
	input	c1,							// clock enable signal
	input	c3,							// clock enable signal	
	//chipset internal port
	input	[7:0] bank,					// memory bank select (512KB)
	input	[18:1] address_in,			// bus address
	input	[15:0] data_in,				// bus data in
	output	[15:0] data_out,			// bus data out
	input	rd,			   				// bus read
	input	hwr,						// bus high byte write
	input	lwr,						// bus low byte write
	//SRAM external signals
//	output	reg _bhe = 1,				// sram upper byte
//	output	reg _ble = 1,   				// sram lower byte
//	output	reg _we = 1,				// sram write enable
//	output	reg _oe = 1,				// sram output enable
//	output	reg [3:0] _ce = 4'b1111,	// sram chip enable
//	output	reg [19:1] address,			// sram address bus
//	inout	[15:0] data		  			// sram data das
	output	_bhe,				// sram upper byte
	output	_ble,   				// sram lower byte
	output	_we,				// sram write enable
	output	_oe,				// sram output enable
	output	[3:0] _ce,	// sram chip enable
	output	[21:1] address,			// sram address bus
	output	[15:0] data,	  			// sram data das
	input	[15:0] ramdata_in	  		// sram data das in
);	 

/* basic timing diagram

phase          : Q0  : Q1  : Q2  : Q3  : Q0  : Q1  : Q2  : Q3  : Q0  : Q1  :
               :     :     :     :     :     :     :     :     :     :     :
			    ___________             ___________             ___________
clk			___/           \___________/           \___________/           \_____ (7.09 MHz - dedicated clock)

               :     :     :     :     :     :     :     :     :     :     :
			    __    __    __    __    __    __    __    __    __    __    __
clk28m		___/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__ (28.36 MHz - dedicated clock)
               :     :     :     :     :     :     :     :     :     :     :
			    ___________             ___________             ___________
c1			___/           \___________/           \___________/           \_____ (7.09 MHz)
               :     :     :     :     :     :     :     :     :     :     :
			          ___________             ___________             ___________
c3			_________/           \___________/           \___________/            (7.09 MHz)
               :     :     :     :     :     :     :     :     :     :     :
			_________                   _____                   _____   
_ce			         \_________________/     \_________________/     \___________ (ram chip enable)
               :     :     :     :     :     :     :     :     :     :     :
			_______________             ___________             ___________   
_we			               \___________/           \___________/           \_____ (ram write strobe)
               :     :     :     :     :     :     :     :     :     :     :
			_________                   _____                   _____
_oe			         \_________________/     \_________________/     \___________ (ram output enable)
               :     :     :     :     :     :     :     :     :     :     :
			          _________________       _________________       ___________
doe			_________/                 \_____/                 \_____/            (data bus output enable)
               :     :     :     :     :     :     :     :     :     :     :
*/

wire	enable;				// indicates memory access cycle
reg		doe;				// data output enable (activates ram data bus buffers during write cycle)

// generate enable signal if any of the banks is selected
//assign enable = |bank[7:0];
assign enable = (bank[7:0]==8'b00000000) ? 1'b0 : 1'b1;

// generate _we
assign _we = (!hwr && !lwr) | !enable;
//always @(posedge clk28m)
//	if (!c1 && !c3) // deassert write strobe in Q0
//		_we <= 1'b1;
//	else if (c1 && c3 && enable && !rd)	//assert write strobe in Q2
//		_we <= 1'b0;

// generate ram output enable _oe
assign _oe = !rd | !enable; 
//assign _oe = !enable;
//always @(posedge clk28m)
//	if (!c1 && !c3) // deassert output enable in Q0
//		_oe <= 1'b1;
//	else if (c1 && !c3 && enable && rd)	//assert output enable in Q1 during read cycle
//		_oe <= 1'b0;

// generate ram upper byte enable _bhe
assign _bhe = !hwr | !enable;
//always @(posedge clk28m)
//	if (!c1 && !c3) // deassert upper byte enable in Q0
//		_bhe <= 1'b1;
//	else if (c1 && !c3 && enable && rd) // assert upper byte enable in Q1 during read cycle
//		_bhe <= 1'b0;
//	else if (c1 && c3 && enable && hwr) // assert upper byte enable in Q2 during write cycle
//		_bhe <= 1'b0;
		
// generate ram lower byte enable _ble
assign _ble = !lwr | !enable;
//always @(posedge clk28m)
//	if (!c1 && !c3) // deassert lower byte enable in Q0
//		_ble <= 1'b1;
//	else if (c1 && !c3 && enable && rd) // assert lower byte enable in Q1 during read cycle
//		_ble <= 1'b0;	
//	else if (c1 && c3 && enable && lwr) // assert lower byte enable in Q2 during write cycle
//		_ble <= 1'b0;
			
//generate data buffer output enable
always @(posedge clk28m)
	if (!c1 && !c3)  // deassert output enable in Q0
		doe <= 1'b0;
	else if (c1 && !c3 && enable && !rd) // assert output enable in Q1 during write cycle
		doe <= 1'b1;	

// generate sram chip selects (every sram chip is 512K x 16bits)
assign		_ce[3:0] = {~|bank[7:6],~|bank[5:4],~|bank[3:2],~|bank[1:0]};
//always @(posedge clk28m)
//	if (!c1 && !c3) // deassert chip selects in Q0
//		_ce[3:0] <= 4'b1111;
//	else if (c1 && !c3) // assert chip selects in Q1
//		_ce[3:0] <= {~|bank[7:6],~|bank[5:4],~|bank[3:2],~|bank[1:0]};

// ram address bus
assign		address = {bank[7]|bank[6]|bank[5]|bank[4],bank[7]|bank[6]|bank[3]|bank[2],bank[7]|bank[5]|bank[3]|bank[1],address_in[18:1]};
//always @(posedge clk28m)
//	if (c1 && !c3 && enable)	// set address in Q1		
//		address <= {bank[7]|bank[5]|bank[3]|bank[1],address_in[18:1]};
			
// data_out multiplexer
assign data_out[15:0] = (enable && rd) ? ramdata_in[15:0] : 16'b0000000000000000;

// data bus output buffers
//assign data[15:0] = doe ? data_in[15:0] : 16'bz;
assign data[15:0] = data_in[15:0];

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// This module interfaces Minimig's synchronous bus to the 68SEC000 CPU
//
// cycle exact CIA interface:
// ECLK low for 6 cycles and high for 4
// data latched with falling edge of ECLK
// VPA sampled 3 CLKs before rising edge of ECLK
// VMA asserted one clock later if VPA recognized
// DTACK sampled one clock before ECLK falling edge
//
//             ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___
// CLK     ___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___
//         ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___
// CPU_CLK    \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/
//         ___ _______ _______ _______ _______ _______ _______ _______ _______ _______ _______ _______
//         ___X___0___X___1___X___2___X___3___X___4___X___5___X___6___X___7___X___8___X___9___X___0___
//         ___                                                 _______________________________
// ECLK       \_______________________________________________/                               \_______
//                                    |       |_VMA_asserted                          
//                                    |_VPA_sampled                   _______________           ______
//                                                                            \\\\\\\\_________/       DTACK asserted (7MHz)
//                                                                                    |__DTACK_sampled (7MHz) 
//                                                                    _____________________     ______
//                                                                                         \___/       DTACK asserted (28MHz)
//                                                                                          |__DTACK_sampled (28MHz)
//
// NOTE: in 28MHz mode this timing model is not (yet?) supported, CPU talks to CIAs with no waitstates
//

module m68k_bridge
(
	input	clk28m,					// 28 MHz system clock
  input blk,
	input	c1,						// clock enable signal
	input	c3,						// clock enable signal
	input	clk,					// bus clock
  input cpu_clk,        // cpu clock
	input	[9:0] eclk,				// ECLK enable signal
	input	vpa,					// valid peripheral address (CIAs)
	input	dbr, 					// data bus request, Gary keeps CPU off the bus (custom chips transfer data)
	input	dbs,					// data bus slowdown (access to chip ram or custom registers)
	input	xbs,					// cross bridge access (active dbr holds off CPU access)
  input nrdy,         // target device is not ready
	output	bls,					// blitter slowdown, tells the blitter that CPU wants the bus
	input	cck,					// colour clock enable, active when dma can access the memory bus
	input	cpu_speed,				// CPU speed select request
  input [3:0] memory_config,  // system memory config
	output	reg turbo,				// indicates current CPU speed mode
	input	_as,					// m68k adress strobe
	input	_lds,					// m68k lower data strobe d0-d7
	input	_uds,					// m68k upper data strobe d8-d15
	input	r_w,					// m68k read / write
	output	 _dtack,				// m68k data acknowledge to cpu
	output	rd,						// bus read 
	output	hwr,					// bus high write
	output	lwr,					// bus low write
	input	[23:1] address,			// external cpu address bus
//	output	reg [23:1] address_out,	// internal cpu address bus output
	output	[23:1] address_out,	// internal cpu address bus output
  output  [15:0] data,      // external cpu data bus
  input [15:0] cpudatain,
//  output  reg [15:0] data_out,  // internal data bus output
  output  [15:0] data_out,  // internal data bus output
  input [15:0] data_in      // internal data bus input
);



localparam VCC = 1'b1;
localparam GND = 1'b0;

/*
68000 bus timing diagram

          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
        7 . 0 . 1 . 2 . 3 . 4 . 5 . 6 . 7 . 0 . 1 . 2 . 3 . 4 . 5 . 6 . 7 . 0 . 1
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
           ___     ___     ___     ___     ___     ___     ___     ___     ___
CLK    ___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
       _____________________________________________                         _____		  
R/W                 \_ _ _ _ _ _ _ _ _ _ _ _/       \_______________________/     
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
       _________ _______________________________ _______________________________ _		  
ADDR   _________X_______________________________X_______________________________X_
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
       _____________                     ___________                     _________
/AS                 \___________________/           \___________________/         
          .....   .   .   .       .   .   .....   .   .   .   .       .   .....
       _____________        READ         ___________________    WRITE    _________
/DS                 \___________________/                   \___________/         
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
       _____________________     ___________________________     _________________
/DTACK                      \___/                           \___/                 
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
                                     ___
DIN    -----------------------------<___>-----------------------------------------
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
                                                         ___________________
DOUT   -------------------------------------------------<___________________>-----
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
*/

wire	doe;					// data buffer output enable
reg		[15:0] ldata_in;		// latched data_in
wire	enable;					// enable
reg		lr_w,l_as,l_dtack;  	// synchronised inputs
reg		l_uds,l_lds;

//reg   l_as28m;        // latched address strobe in turbo mode

reg		lvpa;					// latched valid peripheral address (CIAs)
reg		vma;					// valid memory address (synchronised VPA with ECLK)
reg		_ta;					// transfer acknowledge

//CPU speed mode is allowed to change only when there is no bus access
always @(posedge clk)
	if (_as)
		turbo <= cpu_speed;
		
//latched valid peripheral address
always @(posedge clk)
	lvpa <= vpa;

//vma output
always @(posedge clk)
	if (eclk[9])
		vma <= 0;
	else if (eclk[3] && lvpa)
		vma <= 1;

//latched CPU bus control signals
always @(posedge clk)
//	{lr_w,l_as,l_uds,l_lds,l_dtack} <= {r_w,_as,_uds,_lds,_dtack};
  {lr_w,l_as,l_dtack} <= ({r_w,_as,_dtack});

always @(posedge clk28m)
  {l_uds,l_lds} <= ({_uds,_lds});

reg _as28m;
always @(posedge clk28m)
  _as28m <= _as;

reg l_as28m;
always @(posedge clk)
  l_as28m <= _as28m;

// data transfer acknowledge in normal mode
reg _ta_n;
//always @(posedge clk28m or posedge _as)
always @(negedge clk or posedge _as)
  if (_as)
    _ta_n <= VCC;
  else if (!l_as && cck && ((!vpa && !(dbr && dbs)) || (vpa && vma && eclk[8])) && !nrdy)
    _ta_n <= GND; 

    
// actual _dtack generation (from 7MHz synchronous bus access and cache hit access)
//assign _dtack = (_ta_n & _ta_t & ~cache_hit);
assign _dtack = (_ta_n );

// synchronous control signals
assign enable = ((~l_as & ~l_dtack & ~cck & ~turbo) | (~l_as28m & l_dtack & ~(dbr & xbs) & ~nrdy & turbo));
assign rd = (enable & lr_w);
// in turbo mode l_uds and l_lds may be delayed by 35 ns
assign hwr = (enable & ~lr_w & ~l_uds);
assign lwr = (enable & ~lr_w & ~l_lds);

//blitter slow down signalling, asserted whenever CPU is missing bus access to chip ram, slow ram and custom registers 
assign bls = dbs & ~l_as & l_dtack;

// generate data buffer output enable
assign doe = r_w & ~_as;

// --------------------------------------------------------------------------------------

// data_out multiplexer and latch   
//always @(data)
//  data_out <= wrdata;
assign data_out = cpudatain;

//always @(clk or data_in)
//  if (!clk)
//    ldata_in <= data_in;
always @(posedge clk28m)
  if (!c1 && c3 && enable)
    ldata_in <= data_in;
//assign ldata_in = data_in;

// --------------------------------------------------------------------------------------

// CPU data bus tristate buffers and output data multiplexer
//assign data[15:0] = doe ? cache_hit ? cache_out : ldata_in[15:0] : 16'bz;
assign data[15:0] = ldata_in;

//always @(posedge clk)
//	address_out[23:1] <= address[23:1];
assign 	address_out[23:1] = address[23:1];

endmodule

