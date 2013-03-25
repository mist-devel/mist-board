//Copyright 2006, 2007 Dennis van Weeren
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
// This is the user IO module
// joystick signals are _joy[5:0]=[fire2,fire,up,down,left,right];
//
// 16-10-2005	-started coding
// 17-10-2005	-added proper reset for mouse buttons/counters
//				-improved mouse startup timing
// 22-11-2005	-added joystick 1
// 05-02-2006	-unused buttons of joystick port 2 are now high
// 06-02-2006	-cleaned up code
//				-added user output
// 27-12-2006	-added joystick port 1 and automatic joystick/mouse switch
//				-started coding osd display
// 28-12-2006	-more osd display work done
// 29-12-2006	-fixed some bugs in osd module
// 30-12-2006	-cleaned up osd module, added osd_ctrl input
//-----------------------------------------------------------------------------
// JB:
// 2008-06-17	- added osd control by joy2
//				- spi8 rewritten to use spi clock
//				- added highlight (inversion) of selected osd line
//				- added user reset and reset to bootloader
//				- added memory and interpolation filters configuration
// 2008-07-28	- added JOYTEST register to make it compatible with ALPHA1/SIRIAX flashtro/trainer
// 2008-09-30	- removed user output
// 2008-10-12	- added floppy_config and chipset_config outputs
// 2008-12-12	- added scanline outputs
// 2008-12-27	- added hdd_ena output
// 2009-02-10	- sampling of joystick signals using sof (acting as simple debouncing filter)
// 2009-03-21	- disable keyboard until all keys are released
// 2009-05-08	- fixed problem with activation of OSD menu using UP+DOWN joystick signals
// 2009-05-24	- clean-up & renaming
// 2009-07-18	- change of memory_config takes effect after reset
// 2009-08-11	- hdd_ena replaced with ide_config
// 2009-08-17	- OSD position moved right
// 2009-12-18 - clean-up
// 2010-08-16 - joystick emulation
// 2010-08-16 - autofire
//        - lmb & rmb emulation
//
// SB:
//  06-03-2011  - added autofire without key press & permanent fire at KP0
// 11-04-2011 - autofire function toggle able via capslock / led status
// 17-01-2013  - added POTGO write register handling (required by Asterix game)
//                         

module userio
(
	input 	clk,		    		//bus clock
	input 	reset,			   		//reset
	input	clk28m,
	input	c1,
	input	c3,
	input	sol,					//start of video line
	input	sof,					//start of video frame 
	input 	[8:1] reg_address_in,	//register adress inputs
	input	[15:0] data_in,			//bus data in
	output	reg [15:0] data_out,	//bus data out
	inout	ps2mdat,				//mouse PS/2 data
	inout	ps2mclk,				//mouse PS/2 clk
	output	_fire0,					//joystick 0 fire output (to CIA)
	output	_fire1,					//joystick 1 fire output (to CIA)
	input	[5:0] _joy1,			//joystick 1 in (default mouse port)
	input	[5:0] _joy2,			//joystick 2 in (default joystick port)
  input aflock,         // auto fire lock
  input [2:0] mouse_btn,
  input kbd_mouse_strobe,
  input [1:0] kbd_mouse_type,
  input [7:0] kbd_mouse_data,
	input	[7:0] osd_ctrl,			//OSD control (minimig->host, [menu,select,down,up])
  output  reg keyboard_disabled,  // disables Amiga keyboard while OSD is active
	input	_scs,					//SPI enable
	input	sdi,		  			//SPI data in
	output	sdo,	 				//SPI data out
	input	sck,	  				//SPI clock
	output	osd_blank,				//osd overlay, normal video blank output
	output	osd_pixel,				//osd video pixel
  output  osd_enable,
	output	[1:0] lr_filter,
	output	[1:0] hr_filter,
	output	[5:0] memory_config,
	output	[3:0] chipset_config,
	output	[3:0] floppy_config,
	output	[1:0] scanline,
	output	[2:0] ide_config,
  output  [1:0] cpu_config,
	output	usrrst,					//user reset from osd module
	output	bootrst					//user reset to bootloader
);

//local signals	
reg		[5:0] _sjoy1;				//synchronized joystick 1 signals
reg		[5:0] _xjoy2;				//synchronized joystick 2 signals
wire	[5:0] _sjoy2;				//synchronized joystick 2 signals
reg            [15:0] potreg;                  // POTGO write
wire	[15:0] mouse0dat;			//mouse counters
wire	_mleft;						//left mouse button
wire	_mthird;					//middle mouse button
wire	_mright;					//right mouse buttons
reg		joy1enable;					//joystick 1 enable (mouse/joy switch)
reg		joy2enable;					//joystick 2 enable when no osd
//wire	osd_enable;					// OSD display enable
wire  key_disable;        // Amiga keyboard disable
reg		[7:0] t_osd_ctrl;			//JB: osd control lines
wire	test_load;					//load test value to mouse counter 
wire	[15:0] test_data;			//mouse counter test value
wire  [1:0] autofire_config;
reg   [1:0] autofire_cnt;
reg   autofire;
reg   sel_autofire;     // select autofire and permanent fire

//register names and adresses		
parameter JOY0DAT = 9'h00a;
parameter JOY1DAT = 9'h00c;
parameter POTINP  = 9'h016;
parameter POTGO   = 9'h034;
parameter JOYTEST = 9'h036;

parameter KEY_MENU  = 8'h69;
parameter KEY_ESC   = 8'h45;
parameter KEY_ENTER = 8'h44;
parameter KEY_UP    = 8'h4C;
parameter KEY_DOWN  = 8'h4D;
parameter KEY_LEFT  = 8'h4F;
parameter KEY_RIGHT = 8'h4E;
parameter KEY_PGUP   = 8'h6c;
parameter KEY_PGDOWN = 8'h6d;

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// POTGO register
always @(posedge clk)
  if (reset)
    potreg <= 0;
  else if (reg_address_in[8:1]==POTGO[8:1])
    potreg[15:0] <= data_in[15:0];
   
//autofire pulses generation
always @(posedge clk)
  if (sof)
    if (autofire_cnt == 1)
      autofire_cnt <= autofire_config;
    else
      autofire_cnt <= autofire_cnt - 2'd1;

// autofire 
always @(posedge clk)
  if (sof)
    if (autofire_config == 2'd0)
      autofire <= 1'b0;
    else if (autofire_cnt == 2'd1)
      autofire <= ~autofire;

// auto fire function toggle via capslock status
always @(posedge clk)
  sel_autofire <= (~aflock ^ _xjoy2[4]) ? autofire : 1'b0;

// disable keyboard when OSD is displayed
always @(key_disable)
  keyboard_disabled <= key_disable;
										   
//input synchronization of external signals
always @(posedge clk)
	_sjoy1[5:0] <= _joy1[5:0];	

always @(posedge clk)
	if (sof)
		_xjoy2[5:0] <= _joy2[5:0];	

//port 2 joystick disable in osd
always @(posedge clk)
	if (key_disable)
		joy2enable <= 0;
	else if (_xjoy2[5:0] == 6'b11_1111)
		joy2enable <= 1;

//  autofire is permanent active if enabled, can be overwritten any time by normal fire button
assign _sjoy2[5:0] = joy2enable ? {_xjoy2[5], sel_autofire ^ _xjoy2[4], _xjoy2[3:0]} : 6'b11_1111;

always @(joy2enable or _xjoy2 or osd_ctrl)
	if (~joy2enable)
		if (~_xjoy2[5] || (~_xjoy2[3] && ~_xjoy2[2]))
			t_osd_ctrl = KEY_MENU;
		else if (~_xjoy2[4])
			t_osd_ctrl = KEY_ENTER;
		else if (~_xjoy2[3])
			t_osd_ctrl = KEY_UP;
		else if (~_xjoy2[2])
			t_osd_ctrl = KEY_DOWN;
		else if (~_xjoy2[1])
			t_osd_ctrl = KEY_LEFT;
		else if (~_xjoy2[0])
			t_osd_ctrl = KEY_RIGHT;
    else if (~_xjoy2[1] && ~_xjoy2[3])
      t_osd_ctrl = KEY_PGUP;
    else if (~_xjoy2[0] && ~_xjoy2[2])
      t_osd_ctrl = KEY_PGDOWN;
		else
			t_osd_ctrl = osd_ctrl;
	else
		if (~_xjoy2[3] && ~_xjoy2[2])
			t_osd_ctrl = KEY_MENU;
		else
			t_osd_ctrl = osd_ctrl;

//port 1 automatic mouse/joystick switch
always @(posedge clk)
	if (!_mleft || reset)//when left mouse button pushed, switch to mouse (default)
		joy1enable = 0;
	else if (!_sjoy1[4])//when joystick 1 fire pushed, switch to joystick
		joy1enable = 1;

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//data output multiplexer
always @(reg_address_in or joy1enable or _sjoy1 or mouse0dat or _sjoy2 or _mright or _mthird)
	if ((reg_address_in[8:1]==JOY0DAT[8:1]) && joy1enable)//read port 1 joystick
		data_out[15:0] = {6'b000000,~_sjoy1[1],_sjoy1[3]^_sjoy1[1],6'b000000,~_sjoy1[0],_sjoy1[2]^_sjoy1[0]};
	else if (reg_address_in[8:1]==JOY0DAT[8:1])//read port 1 mouse
		data_out[15:0] = mouse0dat[15:0];
	else if (reg_address_in[8:1]==JOY1DAT[8:1])//read port 2 joystick
		data_out[15:0] = {6'b000000,~_sjoy2[1],_sjoy2[3]^_sjoy2[1],6'b000000,~_sjoy2[0],_sjoy2[2]^_sjoy2[0]};
	else if (reg_address_in[8:1]==POTINP[8:1])//read mouse and joysticks extra buttons
                data_out[15:0] = {1'b0,_sjoy2[5]&potreg[14],1'b0,potreg[12]&1'b1,1'b0,potreg[10]&_mright&_sjoy1[5],1'b0,potreg[8]&_mthird,8'b00000000};
	else
		data_out[15:0] = 16'h0000;

//assign fire outputs to cia A
assign _fire0 = _sjoy1[4] & _mleft;
assign _fire1 = _sjoy2[4];

//JB: some trainers writes to JOYTEST register to reset current mouse counter
assign test_load = reg_address_in[8:1]==JOYTEST[8:1] ? 1'b1 : 1'b0;
assign test_data = data_in[15:0];

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

`ifdef PS2MOUSE
//instantiate mouse controller
ps2mouse pm1
(
	.clk(clk),
	.reset(reset),
	.ps2mdat(ps2mdat),
	.ps2mclk(ps2mclk),
	.ycount(mouse0dat[15:8]),
	.xcount(mouse0dat[7:0]),
	._mleft(_mleft),
	._mthird(_mthird),
	._mright(_mright),
	.test_load(test_load),
	.test_data(test_data)
);
`else
reg [7:0] xcount;
reg [7:0] ycount;

assign mouse0dat[7:0] = xcount;
assign mouse0dat[15:8] = ycount;

assign _mleft = ~mouse_btn[0];
assign _mright = ~mouse_btn[1];
assign _mthird = ~mouse_btn[2];

// delay mouse strobe a little bit
reg kbd_mouse_strobeD, kbd_mouse_strobeD2;
always @(posedge clk)
	kbd_mouse_strobeD <= kbd_mouse_strobe;
	
always @(negedge clk)
	kbd_mouse_strobeD2 <= kbd_mouse_strobeD;
	
always @(posedge kbd_mouse_strobeD2) begin
	if(reset) begin
      xcount <= 8'b00000000;
      ycount <= 8'b00000000;
	end else begin
		if(kbd_mouse_type == 0)
			xcount[7:0] <= xcount[7:0] + kbd_mouse_data[7:0];
		else if(kbd_mouse_type == 1)
			ycount[7:0] <= ycount[7:0] + kbd_mouse_data[7:0];
	end	  
end
`endif



//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------


//instantiate osd controller
osd	osd1
(
	.clk(clk),
	.reset(reset),
	.clk28m(clk28m),
	.c1(c1),
	.c3(c3),
	.sol(sol),
	.sof(sof),
	.osd_ctrl(t_osd_ctrl),
	._scs(_scs),
	.sdi(sdi),
	.sdo(sdo),
	.sck(sck),
	.osd_blank(osd_blank),
	.osd_pixel(osd_pixel),
	.osd_enable(osd_enable),
  .key_disable(key_disable),
	.lr_filter(lr_filter),
	.hr_filter(hr_filter),
	.memory_config(memory_config),
	.chipset_config(chipset_config),
	.floppy_config(floppy_config),
	.scanline(scanline),
	.ide_config(ide_config),
  .cpu_config(cpu_config),
  .autofire_config(autofire_config),
	.usrrst(usrrst),
	.bootrst(bootrst)
);

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//on screen display controller
module osd
(
	input 	clk,		    	//pixel clock
	input	reset,				//reset
	input	clk28m,				//35ns clock
	input	c1,					//clk28m domain clock enable
	input	c3,
	input	sol,				//start of video line
	input	sof,				//start of video frame 
	input	[7:0] osd_ctrl,		//keycode for OSD control (Amiga keyboard codes + additional keys coded as values > 80h)
	input	_scs,				//SPI enable
	input	sdi,		  		//SPI data in
	output	sdo,	 			//SPI data out
	input	sck,	  			//SPI clock
	output	osd_blank,			//osd overlay, normal video blank output
	output	osd_pixel,			//osd video pixel
	output	reg osd_enable = 0,			//osd enable
  output  reg key_disable = 0,      // keyboard disable
	output	reg [1:0] lr_filter = 0,
	output	reg [1:0] hr_filter = 0,
	output	reg [5:0] memory_config = 0,
	output	reg [3:0] chipset_config = 0,
	output	reg [3:0] floppy_config = 0,
	output	reg [1:0] scanline = 0,
	output	reg	[2:0] ide_config = 0,		//enable hard disk support
  output  reg [1:0] cpu_config = 0,
  output  reg [1:0] autofire_config = 0,
	output	usrrst,
	output	bootrst
);

//local signals
reg		[10:0] horbeam;			//horizontal beamcounter
reg		[8:0] verbeam;			//vertical beamcounter
reg		[7:0] osdbuf [2047:0];	//osd video buffer
wire	osdframe;				//true if beamcounters within osd frame
reg		[7:0] bufout;			//osd buffer read data
reg 	[10:0] wraddr;			//osd buffer write address
wire	[7:0] wrdat;			//osd buffer write data
wire	wren;					//osd buffer write enable

reg		[3:0] highlight;		//highlighted line number
reg		invert;					//invertion of highlighted line
reg		[5:0] vpos;
reg		vena;

reg 	[5:0] t_memory_config = 0;
reg		[2:0] t_ide_config = 0;
reg   [1:0] t_cpu_config = 0;
reg   [3:0] t_chipset_config = 0;

//--------------------------------------------------------------------------------------
// memory configuration select signal
//--------------------------------------------------------------------------------------

// configuration changes only while reset is active
always @(posedge clk)
  if (reset)
  begin
    chipset_config[1] <= t_chipset_config[1];
    ide_config <= t_ide_config;
    cpu_config <= t_cpu_config;
    memory_config <= t_memory_config;
  end

always @(posedge clk)
begin
  chipset_config[3:2] <= t_chipset_config[3:2];
  chipset_config[0] <= t_chipset_config[0];
end


//--------------------------------------------------------------------------------------
//OSD video generator
//--------------------------------------------------------------------------------------

//osd local horizontal beamcounter
always @(posedge clk28m)
	if (sol && !c1 && !c3)
		horbeam <= 11'd0;
	else
		horbeam <= horbeam + 11'd1;

//osd local vertical beamcounter
always @(posedge clk)
	if (sof)
		verbeam <= 9'd0;
	else if (sol)
		verbeam <= verbeam + 9'd1;
		
always @(posedge clk)
	if (sol)
		vpos[5:0] <= verbeam[5:0];

//--------------------------------------------------------------------------------------
//generate osd video frame


//horizontal part..
wire hframe;

assign hframe = (horbeam[7] & horbeam[8] & horbeam[9] & ~horbeam[10]) | (~horbeam[8] & ~horbeam[9] & horbeam[10]) | (~horbeam[7] & horbeam[8] & ~horbeam[9] & horbeam[10]);

//vertical part..
reg vframe;

always @(posedge clk)
	if (verbeam[7] && !verbeam[6])
		vframe <= 1;
	else if (verbeam[0])
		vframe <= 0;
		
always @(posedge clk)
	if (sol)
		vena <= vframe;

// combine..
reg osd_enabled;
always @(posedge clk)
  if (sof)
    osd_enabled <= osd_enable;
    
assign osdframe = vframe & hframe & osd_enabled;

always @(posedge clk)
	if (~highlight[3] && verbeam[5:3]==highlight[2:0] && !verbeam[6])
		invert <= 1;
	else if (verbeam[0])
		invert <= 0;

//--------------------------------------------------------------------------------------

//assign osd blank and pixel outputs
assign osd_pixel = invert ^ (vena & bufout[vpos[2:0]]);
assign osd_blank = osdframe;

//--------------------------------------------------------------------------------------
//video buffer
//--------------------------------------------------------------------------------------

//dual ported osd video buffer
//video buffer is 1024*8
//this buffer should be a single blockram
always @(posedge clk)//input part
	if (wren)
		osdbuf[wraddr[10:0]] <= wrdat[7:0];
		
always @(posedge clk28m)//output part
	bufout[7:0] <= osdbuf[{vpos[5:3],horbeam[8]^horbeam[7],~horbeam[7],horbeam[6:1]}];

//--------------------------------------------------------------------------------------
//interface to host
//--------------------------------------------------------------------------------------
wire	rx;
wire	cmd;
reg   wrcmd;    // spi write command

//instantiate spi interface
spi8 spi0
(
	.clk(clk),
	._scs(_scs),
	.sdi(sdi),
	.sdo(sdo),
	.sck(sck),
	.in(osd_ctrl),
	.out(wrdat[7:0]),
	.rx(rx),
	.cmd(cmd)
);

// OSD SPI commands:
//
// 8'b00000000  NOP
// 8'b001H0NNN  write data to osd buffer line <NNN> (H - highlight)
// 8'b0100--KE  enable OSD display (E) and disable Amiga keyboard (K)
// 8'b1000000B  reset Minimig (B - reset to bootloader)
// 8'b100001AA  set autofire rate
// 8'b1001---S  set cpu speed
// 8'b1010--SS  set scanline mode
// 8'b1011-SMC  set hard disk config (C - enable HDC, M - enable Master HDD, S - enable Slave HDD)
// 8'b1100FF-S  set floppy speed and drive number
// 8'b1101-EAN  set chipset features (N - ntsc, A - OCS A1000, E - ECS)
// 8'b1110HHLL  set interpolation filter (H - Hires, L - Lores)
// 8'b111100CC  set memory configuration (S - Slow, C - Chip, F - Fast)
// 8'b111101SS  set memory configuration (S - Slow, C - Chip, F - Fast)
// 8'b111110FF  set memory configuration (S - Slow, C - Chip, F - Fast)
// 8'b111111TT  set cpu type TT=00-68000, 01-68010, 11-68020


always @(posedge clk)
  if (rx && cmd)
    wrcmd <= wrdat[7:5]==3'b001 ? 1'b1 : 1'b0;

//scanline mode
always @(posedge clk)
	if (rx && cmd && wrdat[7:4]==4'b1010)
		scanline <= wrdat[1:0];
		
//hdd config
always @(posedge clk)
	if (rx && cmd && wrdat[7:4]==4'b1011)
		t_ide_config <= wrdat[2:0];
		
//floppy speed select
always @(posedge clk)
	if (rx && cmd && wrdat[7:4]==4'b1100)
		floppy_config[3:0] <= wrdat[3:0];
		
// chipset features select
always @(posedge clk)
	if (rx && cmd && wrdat[7:4]==4'b1101)
		t_chipset_config[3:0] <= wrdat[3:0];
		
// video filter configuration
always @(posedge clk)
	if (rx && cmd && wrdat[7:4]==4'b1110)
		{hr_filter[1:0],lr_filter[1:0]} <= wrdat[3:0];

// memory configuration
always @(posedge clk)
  if (rx && cmd && wrdat[7:2]==6'b1111_00)  //chip
    t_memory_config[1:0] <= wrdat[1:0];
always @(posedge clk)
  if (rx && cmd && wrdat[7:2]==6'b1111_01)  //slow
    t_memory_config[3:2] <= wrdat[1:0];
always @(posedge clk)
  if (rx && cmd && wrdat[7:2]==6'b1111_10)  //fast
    t_memory_config[5:4] <= wrdat[1:0];
    
// cpu config
always @(posedge clk)
  if (rx && cmd && wrdat[7:2]==6'b1111_11)
    t_cpu_config <= wrdat[1:0];

// autofire configuration
always @(posedge clk)
  if (rx && cmd && wrdat[7:2]==6'b1000_01)
    autofire_config[1:0] <= wrdat[1:0];

//address counter and buffer write control (write line <NNN> command)
always @(posedge clk)
	if (rx && cmd && wrdat[7:5]==3'b001)//set linenumber from incoming command byte
		wraddr[10:0] <= {wrdat[2:0],8'b0000_0000};
	else if (rx)	//increment for every data byte that comes in
		wraddr[10:0] <= wraddr[10:0] + 11'd1;

always @(posedge clk)
	if (~osd_enable)
		highlight <= 4'b1000;
	else if (rx && cmd && wrdat[7:4]==4'b0011)
		highlight <= wrdat[3:0];

// disable/enable osd display
// memory configuration
always @(posedge clk)
  if (rx && cmd && wrdat[7:4]==4'b0100)
    {key_disable, osd_enable} <= wrdat[1:0];

assign wren = rx && ~cmd && wrcmd ? 1'b1 : 1'b0;

// user reset request (from osd menu)   
assign usrrst = rx && cmd && wrdat[7:1]==7'b1000_000 ? 1'b1 : 1'b0;

// reset to bootloader
assign bootrst = rx && cmd && wrdat[7:0]==8'b1000_0001 ? 1'b1 : 1'b0;
		

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//SPI interface module (8 bits)
//this is a slave module, clock is controlled by host
//clock is high when bus is idle
//ingoing data is sampled at the positive clock edge
//outgoing data is shifted/changed at the negative clock edge
//msb is sent first
//         ____   _   _   _   _
//sck   ->    |_| |_| |_| |_|
//data   ->     777 666 555 444
//sample ->      ^   ^   ^   ^
//strobe is asserted at the end of every byte and signals that new data must
//be registered at the out output. At the same time, new data is read from the in input.
//The data at input in is also sent as the first byte after _scs is asserted (without strobe!). 
module spi8
(
	input 	clk,		    //pixel clock
	input	_scs,			//SPI chip select
	input	sdi,		  	//SPI data in
	output	sdo,	 		//SPI data out
	input	sck,	  		//SPI clock
	input	[7:0] in,		//parallel input data
	output reg	[7:0] out,		//parallel output data
	output	reg rx,		//byte received
	output	reg cmd			//first byte received
);

//locals
reg [2:0] bit_cnt;		//bit counter
reg [7:0] sdi_reg;		//input shift register	(rising edge of SPI clock)
reg [7:0] sdo_reg;		//output shift register	 (falling edge of SPI clock)

reg new_byte;			//new byte (8 bits) received
reg rx_sync;			//synchronization to clk (first stage)
reg first_byte;		//first byte is going to be received

//------ input shift register ------//
always @(posedge sck)
		sdi_reg <= {sdi_reg[6:0],sdi};

always @(posedge sck)
    if (bit_cnt==7)
      out <= {sdi_reg[6:0],sdi};

//------ receive bit counter ------//
always @(posedge sck or posedge _scs)
	if (_scs)
		bit_cnt <= 0;					//always clear bit counter when CS is not active
	else
		bit_cnt <= bit_cnt + 3'd1;		//increment bit counter when new bit has been received

//----- rx signal ------//
//this signal goes high for one clk clock period just after new byte has been received
//it's synchronous with clk, output data shouldn't change when rx is active
always @(posedge sck or posedge rx)
	if (rx)
		new_byte <= 0;		//cleared asynchronously when rx is high (rx is synchronous with clk)
	else if (bit_cnt == 3'd7)
		new_byte <= 1;		//set when last bit of a new byte has been just received

always @(negedge clk)
	rx_sync <= new_byte;	//double synchronization to avoid metastability

always @(posedge clk)
	rx <= rx_sync;			//synchronous with clk

//------ cmd signal generation ------//
//this signal becomes active after reception of first byte
//when any other byte is received it's deactivated indicating data bytes
always @(posedge sck or posedge _scs)
	if (_scs)
		first_byte <= 1'b1;		//set when CS is not active
	else if (bit_cnt == 3'd7)
		first_byte <= 1'b0;		//cleared after reception of first byte

always @(posedge sck)
	if (bit_cnt == 3'd7)
		cmd <= first_byte;		//active only when first byte received
	
//------ serial data output register ------//
always @(negedge sck)	//output change on falling SPI clock
	if (bit_cnt == 3'd0)
		sdo_reg <= in;
	else
		sdo_reg <= {sdo_reg[6:0],1'b0};

//------ SPI output signal ------//
assign sdo = ~_scs & sdo_reg[7];	//force zero if SPI not selected

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//PS2 mouse controller.
//This module decodes the standard 3 byte packet of an PS/2 compatible 2 or 3 button mouse.
//The module also automatically handles power-up initailzation of the mouse.
module ps2mouse
(
	input 	clk,		    	//bus clock
	input 	reset,			   	//reset 
	inout	ps2mdat,			//mouse PS/2 data
	inout	ps2mclk,			//mouse PS/2 clk
	output	reg [7:0]ycount,	//mouse Y counter
	output	reg [7:0]xcount,	//mouse X counter
	output	reg _mleft,			//left mouse button output
	output	reg _mthird,		//third(middle) mouse button output
	output	reg _mright,		//right mouse button output
	input	test_load,			//load test value to mouse counter
	input	[15:0] test_data	//mouse counter test value
);

//local signals
reg		mclkout; 				//mouse clk out
wire	mdatout;				//mouse data out
reg		mdatb,mclkb,mclkc;		//input synchronization	

reg		[10:0] mreceive;		//mouse receive register	
reg		[11:0] msend;			//mouse send register
reg		[15:0] mtimer;			//mouse timer
reg		[2:0] mstate;			//mouse current state
reg		[2:0] mnext;			//mouse next state

wire	mclkneg;				//negative edge of mouse clock strobe
reg		mrreset;				//mouse receive reset
wire	mrready;				//mouse receive ready;
reg		msreset;				//mosue send reset
wire	msready;				//mouse send ready;
reg		mtreset;				//mouse timer reset
wire	mtready;				//mouse timer ready	 
wire	mthalf;					//mouse timer somewhere halfway timeout
reg		[1:0] mpacket;			//mouse packet byte valid number

//bidirectional open collector IO buffers
assign ps2mclk = (mclkout) ? 1'bz : 1'b0;
assign ps2mdat = (mdatout) ? 1'bz : 1'b0;

//input synchronization of external signals
always @(posedge clk)
begin
	mdatb <= ps2mdat;
	mclkb <= ps2mclk;
	mclkc <= mclkb;
end						

//detect mouse clock negative edge
assign mclkneg = mclkc & (~mclkb);

//PS2 mouse input shifter
always @(posedge clk)
	if (mrreset)
		mreceive[10:0]<=11'b11111111111;
	else if (mclkneg)
		mreceive[10:0]<={mdatb,mreceive[10:1]};
assign mrready=~mreceive[0];

//PS2 mouse send shifter
always @(posedge clk)
	if (msreset)
		msend[11:0]<=12'b110111101000;
	else if (!msready && mclkneg)
		msend[11:0]<={1'b0,msend[11:1]};
assign msready=(msend[11:0]==12'b000000000001) ? 1'b1 : 1'b0;
assign mdatout=msend[0];

//PS2 mouse timer
always @(posedge clk)
	if (mtreset)
		mtimer[15:0]<=16'h0000;
	else
		mtimer[15:0]<=mtimer[15:0] + 16'd1;
assign mtready=(mtimer[15:0]==16'hffff) ? 1'b1 : 1'b0;
assign mthalf=mtimer[11];

//PS2 mouse packet decoding and handling
always @(posedge clk)
begin
	if (reset)//reset
	begin
		{_mthird,_mright,_mleft} <= 3'b111;
		xcount[7:0] <= 8'h00;	
		ycount[7:0] <= 8'h00;
	end
	else if (test_load) //test value preload
		{ycount[7:2],xcount[7:2]} <= {test_data[15:10],test_data[7:2]};
	else if (mpacket==1)//buttons
		{_mthird,_mright,_mleft} <= ~mreceive[3:1];
	else if (mpacket==2)//delta X movement
		xcount[7:0] <= xcount[7:0] + mreceive[8:1];
	else if (mpacket==3)//delta Y movement
		ycount[7:0] <= ycount[7:0] - mreceive[8:1];
end

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//PS2 mouse state machine
always @(posedge clk)
	if (reset || mtready)//master reset OR timeout
		mstate<=0;
	else 
		mstate<=mnext;
always @(mstate or mthalf or msready or mrready or mreceive)
begin
	case(mstate)
		0://initialize mouse phase 0, start timer
			begin
				mclkout=1;
				mrreset=0;
				mtreset=1;
				msreset=0;
				mpacket=0;
				mnext=1;
			end

		1://initialize mouse phase 1, hold clk low and reset send logic
			begin
				mclkout=0;
				mrreset=0;
				mtreset=0;
				msreset=1;
				mpacket=0;
				if (mthalf)//clk was low long enough, go to next state
					mnext=2;
				else
					mnext=1;
			end

		2://initialize mouse phase 2, send 'enable data reporting' command to mouse
			begin
				mclkout=1;
				mrreset=1;
				mtreset=0;
				msreset=0;
				mpacket=0;
				if (msready)//command set, go get 'ack' byte
					mnext=5;
				else
					mnext=2;
			end

		3://get first packet byte
			begin
				mclkout=1;
				mtreset=1;
				msreset=0;
				if (mrready)//we got our first packet byte
				begin
					mpacket=1;
					mrreset=1;
					mnext=4;
 				end
				else//we are still waiting				
 				begin
					mpacket=0;
					mrreset=0;
					mnext=3;
				end
			end

		4://get second packet byte
			begin
				mclkout=1;
				mtreset=0;
				msreset=0;
				if (mrready)//we got our second packet byte
				begin
					mpacket=2;
					mrreset=1;
					mnext=5;

				end
				else//we are still waiting				
 				begin
					mpacket=0;
					mrreset=0;
					mnext=4;
				end
			end

		5://get third packet byte (or get 'ACK' byte..)
			begin
				mclkout=1;
				mtreset=0;
				msreset=0;
				if (mrready)//we got our third packet byte
				begin
					mpacket=3;
					mrreset=1;
					mnext=3;

				end
				else//we are still waiting				
 				begin
					mpacket=0;
					mrreset=0;
					mnext=5;
				end
			end
 
		default://we should never come here
			begin
				mclkout=1'bx;
				mrreset=1'bx;
				mtreset=1'bx;
				msreset=1'bx;
				mpacket=2'bxx;
				mnext=0;
			end

	endcase
end

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

endmodule

