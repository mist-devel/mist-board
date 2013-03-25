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
// This is the Minimig PS/2 keyboard handler
//
// 19-11-2006	-started coding
// 20-11-2006	-more coding
// 21-11-2006	-finished PS/2 state machine, added keymap
// 29-11-2006	-keymap is now blockram, saves almost 80 slices!
// 04-12-2006	-added keyack signal
// 05-12-2006	-more work; cleaning up, optimizing
//			-added on-screen-display control
// 01-01-2007	-added extra key for on-screen-display control
// 11-02-2007	-reset is now ctrl-alt-alt (as in Amiga OS4) instead of ctrl-lgui-rgui 

// this is the ps2 keyboard module itself
// every time a new key is decoded, keystrobe is asserted.
// keydat is only valid when keystrobe is asserted
// after keystrobe, keyboard controller waits for keyack or timeout
// kbdrst is asserted when the control, left gui and right gui keys are hold down together
// leda and ledb control the numlock and scrolllock leds


// JB:
// added support for prtscr and ctrlbrk keys
// verilog 2001 style module declaration
// osd_ctrl is 8-bit wide
//
// 2009-05-24	- clean-up & renaming
// 2010-08-18	- joystick emulation

// SB:
// 2011-04-09 - added autofire lock function using capslock
// 2011-07-21 - changed '#' key scan code, thanks Chris

module ps2keyboard
(
	input 	clk,		   		//bus clock
	input 	reset,			   	//reset (system reset in)
	inout	ps2kdat,			//keyboard PS/2 data
	inout	ps2kclk,			//keyboard PS/2 clk
	input	leda,				//keyboard led a in
	input	ledb,				//keyboard led b in
  output  aflock,   // auto fire toggle
	output	kbdrst,				//keyboard reset out
	output	[7:0] keydat,		//keyboard data out
	output	reg keystrobe,		//keyboard data out strobe
	input	keyack,				//keyboard data out acknowledge
  input   osd_enable,
	output	[7:0] osd_ctrl,		//on-screen-display controll
	output	_lmb,				//emulated left mouse button
	output	_rmb,				//emulated right mouse button
	output	[5:0] _joy2,		//joystick emulation
	output	freeze,				//Action Replay freeze button
  output [5:0] mou_emu,
  output [5:0] joy_emu,
  input joy_emu_en
);

//local signals
reg		pclkout; 				//ps2 clk out
wire	pdatout;				//ps2 data out
wire	pclkneg;				//negative edge of ps2 clock strobe
reg		pdatb,pclkb,pclkc;		//input synchronization	

reg		[11:0] preceive;		//ps2 receive register
reg		[11:0] psend;			//ps2 send register
reg		[19:0] ptimer;			//ps2 timer
reg		[2:0] kstate;			//keyboard controller current state
reg		[2:0] knext;			//keyboard controller next state
reg		capslock;				//capslock status
wire	numlock;

reg		prreset;				//ps2 receive reset
wire	prbusy;					//ps2 receive busy
reg		ptreset;				//ps2 reset timer
wire	pto1;					//ps2 timer timeout 1 
wire	pto2;					//ps2 timer timeout 2
reg		psled1;					//ps2 send led code 1
reg		psled2;					//ps2 send led code 2
wire	psready;				//ps2 send ready
wire	valid;					//valid amiga key code at keymap output

//bidirectional open collector IO buffers
assign ps2kclk = pclkout ? 1'bz : 1'b0;
assign ps2kdat = pdatout ? 1'bz : 1'b0;

//input synchronization of external signals
always @(posedge clk)
begin
	pdatb <= ps2kdat;
	pclkb <= ps2kclk;
	pclkc <= pclkb;
end						

//detect ps2 clock negative edge
assign pclkneg = pclkc & ~pclkb;

//PS2 input shifter
wire prready;

always @(posedge clk)
	if (prreset  ||  prready)
		preceive[11:0] <= 12'b111111111111;
	else if (pclkneg)
		preceive[11:0] <= {1'b0,pdatb,preceive[10:1]};
		
assign prready = ~preceive[0];
assign prbusy = ~preceive[11];

//PS2 timer
always @(posedge clk)
	if (ptreset)
		ptimer[19:0] <= 20'd0;
	else if (!pto2)
		ptimer[19:0] <= ptimer[19:0] + 20'd1;
		
assign pto1 = ptimer[15];//4.6ms @ 7.09Mhz
assign pto2 = ptimer[19];//74ms @ 7.09Mhz

//PS2 send shifter
always @(posedge clk)
	if (psled1)
		psend[11:0] <= 12'b111111011010;//$ED
	else if (psled2)
		psend[11:0] <= {2'b11,~(capslock^numlock^ledb),5'b00000,capslock,numlock,ledb,1'b0};//led status
	else if (!psready && pclkneg)
		psend[11:0] <= {1'b0,psend[11:1]};
		
assign psready = (psend[11:0]==12'b000000000001) ? 1'd1 : 1'd0;
assign pdatout = psend[0];

//keyboard state machine
always @(posedge clk)
	if (reset)//master reset
		kstate <= 3'd0;
	else 
		kstate <= knext;
		
always @(kstate or pto1 or pto2 or psready or prready or prbusy or keystrobe or keyack)
begin
	case(kstate)
		0://reset timer
			begin
				prreset = 1'd1;
				ptreset = 1'd1;
				pclkout = 1'd0;
				psled1 = 1'd0;
				psled2 = 1'd0;
				
				knext = 3'd1;
			end
		1://"request-to-send" for led1 code  
			begin
				prreset = 1'd1;
				ptreset = 1'd0;
				pclkout = 1'd0;
				psled1 = 1'd1;
				psled2 = 1'd0;
				
				if (pto1)
					knext = 3'd2;
				else
					knext = 3'd1;
			end
		2://wait for led1 code to be sent and acknowledge received
			begin
				prreset = ~psready;
				ptreset = 1'd1;
				pclkout = 1'd1;
				psled1 = 1'd0;
				psled2 = 1'd0;
				
				if (prready)
					knext = 3'd3;
				else
					knext = 3'd2;
			end
		3://"request-to-send" for led2 code
			begin
				prreset = 1'd1;
				ptreset = 1'd0;
				pclkout = 1'd0;
				psled1 = 1'd0;
				psled2 = 1'd1;
				
				if (pto1)
					knext = 3'd4;
				else
					knext = 3'd3;
			end
		4://wait for led2 code to be sent
			begin
				prreset = ~psready;
				ptreset = 1'd1;
				pclkout = 1'd1;
				psled1 = 1'd0;
				psled2 = 1'd0;
				
				if (prready)
					knext = 3'd5;
				else
					knext = 3'd4;
			end


		5://wait for valid amiga key code
			begin
				prreset = 1'd0;
				ptreset = keystrobe;
				pclkout = 1'd1;
				psled1 = 1'd0;
				psled2 = 1'd0;
				if (keystrobe)//valid amiga key decoded
					knext = 3'd6;
				else if (!prbusy && pto2)//timeout, update leds
					knext = 3'd0;
				else//stay here
					knext = 3'd5;
 			end

		6://hold of ps2 keyboard and wait for keyack or timeout
			begin
				prreset = 1'd0;
				ptreset = keyack;
				pclkout = 1'd0;
				psled1 = 1'd0;
				psled2 = 1'd0;
				if (keyack  ||  pto2)//keyack or timeout
					knext = 3'd5;
				else//stay here
					knext = 3'd6;
 			end

		default://we should never come here
			begin
				prreset = 1'd0;//ps2 receiver reset
				ptreset = 1'd0;//ps2 timer reset
				pclkout = 1'd1;//ps2 clock override
				psled1 = 1'd0;//ps2 send led code 1
				psled2 = 1'd0;//ps2 send led code 2

				knext = 3'd0;//go to reset state
 			end

	endcase
end

//instantiate keymap to convert ps2 scan codes to amiga raw key codes
wire ctrl,aleft,aright,caps;
ps2keyboardmap km1
(
	.clk(clk),
	.reset(reset),
	.enable(prready),
	.ps2key(preceive[8:1]),
	.valid(valid),
	.akey(keydat[7:0]),
	.ctrl(ctrl),
	.aleft(aleft),
	.aright(aright),
	.caps(caps),
	.numlock(numlock),
  .osd_enable(osd_enable),
	.osd_ctrl(osd_ctrl),
	._lmb(_lmb),
	._rmb(_rmb),
	._joy2(_joy2),
	.freeze(freeze),
  .mou_emu(mou_emu),
  .joy_emu(joy_emu),
  .joy_emu_en(joy_emu_en)
);

//Duplicate key filter and caps lock handling.
//A ps/2 keyboard has a future called "typematic".
//This means that the last key downstroke event
//is repeated (at approx 2Hz default).
//An Amiga keyboard does not do this so this filter removes
//all duplicate downstroke events:
//When a duplicate downstroke event is detected, keystrobe is not asserted.
//When the event is unique (no duplicate), keystrobe is asserted when valid is asserted.
//
//Capslock on amiga is "remembered" by keyboard. A ps/2 keyboard doesn't do this
//therefore, amiga-like caps lock behaviour is simulated here
wire keyequal;
reg [7:0]keydat2;
assign keyequal = keydat2[6:0]==keydat[6:0] ? 1'd1 : 1'd0; //detect if latched key equals new key

//latch last key downstroke event
always @(posedge clk)
	if (reset)
		keydat2[7:0] <= 8'd0;
	else if (valid && !keydat[7])//latch downstroke event for last key pressed
		keydat2[7:0] <= keydat[7:0];
	else if (valid && keydat[7] && keyequal)//upstroke event for latched key received
		keydat2[7:0] <= keydat[7:0];

//toggle capslock status on capslock downstroke event		
always @(posedge clk)
	if (reset)
		capslock <= 1'd0;
	else if (valid && !keydat[7] && caps && !(keyequal && (keydat[7]==keydat2[7])))
		capslock <= ~capslock;

assign aflock = capslock;

//generate keystrobe to indicate valid keycode				
always @(capslock or caps or keyequal or keydat or keydat2 or valid)
	if (capslock && caps)//filter out capslock downstroke && capslock upstroke events if capslock is set
		keystrobe = 1'd0;
	else if (keyequal && (keydat[7]==keydat2[7]))//filter out duplicate events
		keystrobe = 1'd0;
	else if (valid)//valid amiga keycode, assert strobe
		keystrobe = 1'd1;
	else
		keystrobe = 1'd0;

//Keyboard reset detector. 
//Reset is accomplished by holding down the
//ctrl or caps, left alt and right alt keys all at the same time
reg [2:0]kbdrststatus;
always @(posedge clk)
begin
	//latch status of control key
	if (reset)
		kbdrststatus[2] <= 1'd1;
	else if (valid && (ctrl || caps))
		kbdrststatus[2] <= keydat[7];
	//latch status of left alt key
	if (reset)
		kbdrststatus[1] <= 1'd1;
	else if (valid && aleft)
		kbdrststatus[1] <= keydat[7];
	//latch status of right alt key
	if (reset)
		kbdrststatus[0] <= 1'd1;
	else if (valid && aright)
		kbdrststatus[0] <= keydat[7];
end
assign kbdrst = ~(kbdrststatus[2] | kbdrststatus[1] | kbdrststatus[0]);//reset if all 3 keys down

endmodule

//-------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------

//ps2 key to amiga key mapper using blockram
//this module also handles the osd_ctrl signals
module ps2keyboardmap
(
	input 	clk,		    	//clock
	input	reset,				//reset
	input	enable,				//enable
	input 	[7:0] ps2key,		//ps2 key code input
	output	valid,				//amiga key code valid (strobed when new valid keycode at output) 
	output	[7:0] akey,			//amiga key code output
	output	ctrl,	  			//amiga control key
	output	aleft, 				//amiga left alt key
	output	aright,	   			//amiga right alt key
	output	caps,	   			//amiga capslock key
	output	reg numlock = 0, 	//ps/2 numlock status
  input osd_enable,
	output	reg [7:0] osd_ctrl,	//osd menu control
	output	reg _lmb,			//mouse button emulation
	output	reg _rmb,			//mouse button emulation
	output	reg [5:0] _joy2,	//joystick emulation
	output	reg freeze,			//int7 freeze button
  output [5:0] mou_emu,
  output reg [5:0] joy_emu,
  input joy_emu_en
);
//local parameters
//localparam JOY2KEY_UP    = 7'h3E;
//localparam JOY2KEY_DOWN  = 7'h2E;
//localparam JOY2KEY_LEFT  = 7'h2D;
//localparam JOY2KEY_RIGHT = 7'h2F;
//localparam JOY2KEY_FIRE0 = 7'h0F;
//localparam JOY2KEY_FIRE1 = 7'h43;
//localparam JOY1KEY_FIRE0 = 7'h5C;
//localparam JOY1KEY_FIRE1 = 7'h5D;

localparam JOY2KEY_UP    = 7'h4c;
localparam JOY2KEY_DOWN  = 7'h4d;
localparam JOY2KEY_LEFT  = 7'h4f;
localparam JOY2KEY_RIGHT = 7'h4e;
localparam JOY2KEY_FIRE0 = 7'h0F;
localparam JOY2KEY_FIRE1 = 7'h43;
localparam JOY1KEY_FIRE0 = 7'h5C;
localparam JOY1KEY_FIRE1 = 7'h5D;

//local signals
reg		[15:0] keyrom;			//rom output
reg		enable2;				//enable signal delayed by one clock
reg		upstroke;				//upstroke key status
reg		extended;				//extended key status			

//generate delayed enable signal (needed because of blockram pipelining)
always @(posedge clk)
	enable2 <= enable;

//latch special ps2 keycodes
//keyrom[7] is used together with [0], [1] and [2] for ps2 special codes decoding
//these are needed for complete decoding of the ps2 codes
always @(posedge clk)
	if (reset)//reset
	begin
		upstroke <= 1'd0;
		extended <= 1'd0;
	end
	else if (enable2 && keyrom[7] && keyrom[0])//extended key identifier found
		extended <= 1'd1;
	else if (enable2 && keyrom[7] && keyrom[1])//upstroke identifier found
		upstroke <= 1'd1;
	else if (enable2 && !(keyrom[7] && keyrom[2]))//other key found and it was not an ack, reset both status bits
	begin
		upstroke <= 1'd0;
		extended <= 1'd0;
	end

//assign all output signals
//keyrom[6:0] = amiga keycode
assign valid = keyrom[15] & (~keyrom[9] | ~numlock) & enable2;
assign ctrl = keyrom[14];
assign aleft = keyrom[13];
assign aright = keyrom[12];
assign caps = keyrom[11];
assign akey[7:0] = {upstroke, keyrom[6:0]};

//osd control handling
//keyrom[8] - OSD key, keyrom[15] - Amiga key
always @(posedge clk)
begin
	if (reset)
		osd_ctrl[7:0] <= 8'd0;
	else if (enable2 && (keyrom[8] || keyrom[15]))
		osd_ctrl[7:0] <= {upstroke, keyrom[6:0]};
end

//freeze key for Action Replay
always @(posedge clk)
begin
	if (reset)
		freeze <= 1'b0;
	else if (enable2 && keyrom[8] && keyrom[7:0]==8'h6F)
		freeze <= ~upstroke;
end

//numlock
always @(posedge clk)
begin
	if (enable2 && keyrom[10] && ~upstroke)
		numlock <= ~numlock;
end

//[fire2,fire,up,down,left,right] 
always @(posedge clk)
begin
	if (reset || !numlock || enable2 && keyrom[15] && keyrom[7:0]==JOY2KEY_LEFT && !upstroke)
		_joy2[0] <= 1'b1;
	else if (enable2 && keyrom[15] && keyrom[7:0]==JOY2KEY_RIGHT)
		_joy2[0] <= upstroke;
end

always @(posedge clk)
begin
	if (reset || !numlock || enable2 && keyrom[15] && keyrom[7:0]==JOY2KEY_RIGHT && !upstroke)
		_joy2[1] <= 1'b1;
	else if (enable2 && keyrom[15] && keyrom[7:0]==JOY2KEY_LEFT)
		_joy2[1] <= upstroke;
end

always @(posedge clk)
begin
	if (reset || !numlock || enable2 && keyrom[15] && keyrom[7:0]==JOY2KEY_UP && !upstroke)
		_joy2[2] <= 1'b1;
	else if (enable2 && keyrom[15] && keyrom[7:0]==JOY2KEY_DOWN)
		_joy2[2] <= upstroke;
end

always @(posedge clk)
begin
	if (reset || !numlock || enable2 && keyrom[15] && keyrom[7:0]==JOY2KEY_DOWN && !upstroke)
		_joy2[3] <= 1'b1;
	else if (enable2 && keyrom[15] && keyrom[7:0]==JOY2KEY_UP)
		_joy2[3] <= upstroke;
end

always @(posedge clk)
begin
	if (reset || !numlock)
		_joy2[4] <= 1'b1;
	else if (enable2 && ctrl/*keyrom[15] && keyrom[7:0]==JOY2KEY_FIRE0*/)
		_joy2[4] <= upstroke;
end

always @(posedge clk)
begin
	if (reset || !numlock)
		_joy2[5] <= 1'b1;
	else if (enable2 && aleft /*keyrom[15] && keyrom[7:0]==JOY2KEY_FIRE1*/)
		_joy2[5] <= upstroke;
end

// mouse button emulation
always @(posedge clk)
begin
	if (reset || !numlock)
		_lmb <= 1'b1;
	else if (enable2 && keyrom[15] && keyrom[7:0]==JOY1KEY_FIRE0)
		_lmb <= upstroke;
end

always @(posedge clk)
begin
	if (reset || !numlock)
		_rmb <= 1'b1;
	else if (enable2 && keyrom[15] && keyrom[7:0]==JOY1KEY_FIRE1)
		_rmb <= upstroke;
end


reg guileft;
reg guiright;
reg altleft;
reg altright;

always @(posedge clk)
begin
  if (reset)
  begin
    guileft <= 0;
    guiright <= 0;
    altleft <= 0;
    altright <= 0;
  end
  else
  if (enable2)
  begin
    if (keyrom[7:0] == 8'h66)
      guileft <= ~upstroke;
    else if (keyrom[7:0] == 8'h67)
      guiright <= ~upstroke;
    else if (aleft)
      altleft <= ~upstroke;
    else if (aright)
      altright <= ~upstroke;
  end
end

// active low
assign mou_emu[5] = ~(guiright & altright);
assign mou_emu[4] = ~(guileft & altleft);
assign mou_emu[3:0] = 4'b1111;

always @(posedge clk)
begin
  if (reset)
    joy_emu <= 6'b11_1111;
  else if (~joy_emu_en)
    joy_emu <= #1 6'b11_1111;
  else if (enable2) begin
    if (keyrom[7:0] == 8'h4c)
      joy_emu[3] <= upstroke;  // UP
    else if (keyrom[7:0] == 8'h4d)
      joy_emu[2] <= upstroke;  // DOWN
    else if (keyrom[7:0] == 8'h4f)
      joy_emu[1] <= upstroke;  // LEFT
    else if (keyrom[7:0] == 8'h4e)
      joy_emu[0] <= upstroke;  // RIGHT
    else if (ctrl)
      joy_emu[4] <= upstroke;  // FIRE
    else if (aleft & ~guileft)
      joy_emu[5] <= upstroke;  // FIRE2
  end
end



//-------------------------------------------------------------------------------------------------

//here follows the ps2 to Amiga key romtable:
//standard decodes
//[6:0] = amiga key code
//[15] = valid amiga key (present in rom)
//decodes for special function keys :
//[14] = control key
//[13] = left alt key
//[12] = right alt key
//[11] = capslock key
//[10] = numlock
//PS2 specific decodes:
//[7]&[0] = PS2 EXTENDED KEY
//[7]&[1] = PS2 UPSTROKE IDENTIFIER
//[7]&[2] = PS2 ACKNOWLEDGE
//OSD control decodes
//[8] = extra PS/2 key

always @(posedge clk)
begin
	if (enable)
	begin
		case({extended,ps2key[7:0]}) // Scan Code Set 2
			9'h000:		keyrom[15:0] <= 16'h0000;
			9'h001:		keyrom[15:0] <= 16'h8058;//F9
			9'h002:		keyrom[15:0] <= 16'h0000;
			9'h003:		keyrom[15:0] <= 16'h8054;//F5
			9'h004:		keyrom[15:0] <= 16'h8052;//F3
			9'h005:		keyrom[15:0] <= 16'h8050;//F1
			9'h006:		keyrom[15:0] <= 16'h8051;//F2
			9'h007:		keyrom[15:0] <= 16'h0169;//F12 <OSD>
			9'h008:		keyrom[15:0] <= 16'h0000;
			9'h009:		keyrom[15:0] <= 16'h8059;//F10
			9'h00a:		keyrom[15:0] <= 16'h8057;//F8
			9'h00b:		keyrom[15:0] <= 16'h8055;//F6
			9'h00c:		keyrom[15:0] <= 16'h8053;//F4
			9'h00d:		keyrom[15:0] <= 16'h8042;//TAB
			9'h00e:		keyrom[15:0] <= 16'h8000;//~
			9'h00f:		keyrom[15:0] <= 16'h0000;
			9'h010:		keyrom[15:0] <= 16'h0000;
			9'h011:		keyrom[15:0] <= 16'ha064;//LEFT ALT
			9'h012:		keyrom[15:0] <= 16'h8060;//LEFT SHIFT
			9'h013:		keyrom[15:0] <= 16'h0000;
			9'h014:		keyrom[15:0] <= 16'hc063;//CTRL
			9'h015:		keyrom[15:0] <= 16'h8010;//q
			9'h016:		keyrom[15:0] <= 16'h8001;//1
			9'h017:		keyrom[15:0] <= 16'h0000;
			9'h018:		keyrom[15:0] <= 16'h0000;
			9'h019:		keyrom[15:0] <= 16'h0000;
			9'h01a:		keyrom[15:0] <= 16'h8031;//z
			9'h01b:		keyrom[15:0] <= 16'h8021;//s
			9'h01c:		keyrom[15:0] <= 16'h8020;//a
			9'h01d:		keyrom[15:0] <= 16'h8011;//w
			9'h01e:		keyrom[15:0] <= 16'h8002;//2
			9'h01f:		keyrom[15:0] <= 16'h0000;
			9'h020:		keyrom[15:0] <= 16'h0000;
			9'h021:		keyrom[15:0] <= 16'h8033;//c
			9'h022:		keyrom[15:0] <= 16'h8032;//x
			9'h023:		keyrom[15:0] <= 16'h8022;//d
			9'h024:		keyrom[15:0] <= 16'h8012;//e
			9'h025:		keyrom[15:0] <= 16'h8004;//4
			9'h026:		keyrom[15:0] <= 16'h8003;//3
			9'h027:		keyrom[15:0] <= 16'h0000;
			9'h028:		keyrom[15:0] <= 16'h0000;
			9'h029:		keyrom[15:0] <= 16'h8040;//SPACE
			9'h02a:		keyrom[15:0] <= 16'h8034;//v
			9'h02b:		keyrom[15:0] <= 16'h8023;//f
			9'h02c:		keyrom[15:0] <= 16'h8014;//t
			9'h02d:		keyrom[15:0] <= 16'h8013;//r
			9'h02e:		keyrom[15:0] <= 16'h8005;//5
			9'h02f:		keyrom[15:0] <= 16'h0000;
			9'h030:		keyrom[15:0] <= 16'h0000;
			9'h031:		keyrom[15:0] <= 16'h8036;//n
			9'h032:		keyrom[15:0] <= 16'h8035;//b
			9'h033:		keyrom[15:0] <= 16'h8025;//h
			9'h034:		keyrom[15:0] <= 16'h8024;//g
			9'h035:		keyrom[15:0] <= 16'h8015;//y
			9'h036:		keyrom[15:0] <= 16'h8006;//6
			9'h037:		keyrom[15:0] <= 16'h0000;
			9'h038:		keyrom[15:0] <= 16'h0000;
			9'h039:		keyrom[15:0] <= 16'h0000;
			9'h03a:		keyrom[15:0] <= 16'h8037;//m
			9'h03b:		keyrom[15:0] <= 16'h8026;//j
			9'h03c:		keyrom[15:0] <= 16'h8016;//u
			9'h03d:		keyrom[15:0] <= 16'h8007;//7
			9'h03e:		keyrom[15:0] <= 16'h8008;//8
			9'h03f:		keyrom[15:0] <= 16'h0000;
			9'h040:		keyrom[15:0] <= 16'h0000;
			9'h041:		keyrom[15:0] <= 16'h8038;//<
			9'h042:		keyrom[15:0] <= 16'h8027;//k
			9'h043:		keyrom[15:0] <= 16'h8017;//i
			9'h044:		keyrom[15:0] <= 16'h8018;//o
			9'h045:		keyrom[15:0] <= 16'h800a;//0
			9'h046:		keyrom[15:0] <= 16'h8009;//9
			9'h047:		keyrom[15:0] <= 16'h0000;
			9'h048:		keyrom[15:0] <= 16'h0000;
			9'h049:		keyrom[15:0] <= 16'h8039;//>
			9'h04a:		keyrom[15:0] <= 16'h803a;//FORWARD SLASH
			9'h04b:		keyrom[15:0] <= 16'h8028;//l
			9'h04c:		keyrom[15:0] <= 16'h8029;//;
			9'h04d:		keyrom[15:0] <= 16'h8019;//p
			9'h04e:		keyrom[15:0] <= 16'h800b;//-
			9'h04f:		keyrom[15:0] <= 16'h0000;
			9'h050:		keyrom[15:0] <= 16'h0000;
			9'h051:		keyrom[15:0] <= 16'h0000;
			9'h052:		keyrom[15:0] <= 16'h802a;//"
			9'h053:		keyrom[15:0] <= 16'h0000;
			9'h054:		keyrom[15:0] <= 16'h801a;//[
			9'h055:		keyrom[15:0] <= 16'h800c;// = 
			9'h056:		keyrom[15:0] <= 16'h0000;
			9'h057:		keyrom[15:0] <= 16'h0000;
			9'h058:		keyrom[15:0] <= 16'h8862;//CAPSLOCK
			9'h059:		keyrom[15:0] <= 16'h8061;//RIGHT SHIFT
			9'h05a:		keyrom[15:0] <= 16'h8044;//ENTER
			9'h05b:		keyrom[15:0] <= 16'h801b;//]
			9'h05c:		keyrom[15:0] <= 16'h0000;
			9'h05d:		keyrom[15:0] <= 16'h802B;//international enter cut out (German '#' key), Amiga scancode $2B
			9'h05e:		keyrom[15:0] <= 16'h0000;
			9'h05f:		keyrom[15:0] <= 16'h0000;
			9'h060:		keyrom[15:0] <= 16'h0000;
			9'h061:		keyrom[15:0] <= 16'h8030;//international left shift cut out (German '<>' key), 0x56 Set#1 code, $30 Amiga scancode
			9'h062:		keyrom[15:0] <= 16'h0000;
			9'h063:		keyrom[15:0] <= 16'h0000;
			9'h064:		keyrom[15:0] <= 16'h0000;
			9'h065:		keyrom[15:0] <= 16'h0000;
			9'h066:		keyrom[15:0] <= 16'h8041;//BACKSPACE
			9'h067:		keyrom[15:0] <= 16'h0000;
			9'h068:		keyrom[15:0] <= 16'h0000;
			9'h069:		keyrom[15:0] <= 16'h821d;//KP 1
			9'h06a:		keyrom[15:0] <= 16'h0000;
			9'h06b:		keyrom[15:0] <= 16'h822d;//KP 4
			9'h06c:		keyrom[15:0] <= 16'h823d;//KP 7
			9'h06d:		keyrom[15:0] <= 16'h0000;
			9'h06e:		keyrom[15:0] <= 16'h0000;
			9'h06f:		keyrom[15:0] <= 16'h0000;
			9'h070:		keyrom[15:0] <= 16'h820f;//KP 0
			9'h071:		keyrom[15:0] <= 16'h823c;//KP .
			9'h072:		keyrom[15:0] <= 16'h821e;//KP 2
			9'h073:		keyrom[15:0] <= 16'h822e;//KP 5
			9'h074:		keyrom[15:0] <= 16'h822f;//KP 6
			9'h075:		keyrom[15:0] <= 16'h823e;//KP 8
			9'h076:		keyrom[15:0] <= 16'h8045;//ESCAPE
			9'h077:		keyrom[15:0] <= 16'h0400;//NUMLOCK
			9'h078:		keyrom[15:0] <= 16'h0000;//0168;//F11 <OSD>
			9'h079:		keyrom[15:0] <= 16'h825e;//KP +
			9'h07a:		keyrom[15:0] <= 16'h821f;//KP 3
			9'h07b:		keyrom[15:0] <= 16'h824a;//KP -
			9'h07c:		keyrom[15:0] <= 16'h825d;//KP *
			9'h07d:		keyrom[15:0] <= 16'h823f;//KP 9
			9'h07e:		keyrom[15:0] <= 16'h0169;//SCROLL LOCK = OSD (asc)
			9'h07f:		keyrom[15:0] <= 16'h0000;
			9'h080:		keyrom[15:0] <= 16'h0000;
			9'h081:		keyrom[15:0] <= 16'h0000;
			9'h082:		keyrom[15:0] <= 16'h0000;
			9'h083:		keyrom[15:0] <= 16'h8056;//F7
			9'h084:		keyrom[15:0] <= 16'h0000;
			9'h085:		keyrom[15:0] <= 16'h0000;
			9'h086:		keyrom[15:0] <= 16'h0000;
			9'h087:		keyrom[15:0] <= 16'h0000;
			9'h088:		keyrom[15:0] <= 16'h0000;
			9'h089:		keyrom[15:0] <= 16'h0000;
			9'h08a:		keyrom[15:0] <= 16'h0000;
			9'h08b:		keyrom[15:0] <= 16'h0000;
			9'h08c:		keyrom[15:0] <= 16'h0000;
			9'h08d:		keyrom[15:0] <= 16'h0000;
			9'h08e:		keyrom[15:0] <= 16'h0000;
			9'h08f:		keyrom[15:0] <= 16'h0000;
			9'h090:		keyrom[15:0] <= 16'h0000;
			9'h091:		keyrom[15:0] <= 16'h0000;
			9'h092:		keyrom[15:0] <= 16'h0000;
			9'h093:		keyrom[15:0] <= 16'h0000;
			9'h094:		keyrom[15:0] <= 16'h0000;
			9'h095:		keyrom[15:0] <= 16'h0000;
			9'h096:		keyrom[15:0] <= 16'h0000;
			9'h097:		keyrom[15:0] <= 16'h0000;
			9'h098:		keyrom[15:0] <= 16'h0000;
			9'h099:		keyrom[15:0] <= 16'h0000;
			9'h09a:		keyrom[15:0] <= 16'h0000;
			9'h09b:		keyrom[15:0] <= 16'h0000;
			9'h09c:		keyrom[15:0] <= 16'h0000;
			9'h09d:		keyrom[15:0] <= 16'h0000;
			9'h09e:		keyrom[15:0] <= 16'h0000;
			9'h09f:		keyrom[15:0] <= 16'h0000;
			9'h0a0:		keyrom[15:0] <= 16'h0000;
			9'h0a1:		keyrom[15:0] <= 16'h0000;
			9'h0a2:		keyrom[15:0] <= 16'h0000;
			9'h0a3:		keyrom[15:0] <= 16'h0000;
			9'h0a4:		keyrom[15:0] <= 16'h0000;
			9'h0a5:		keyrom[15:0] <= 16'h0000;
			9'h0a6:		keyrom[15:0] <= 16'h0000;
			9'h0a7:		keyrom[15:0] <= 16'h0000;
			9'h0a8:		keyrom[15:0] <= 16'h0000;
			9'h0a9:		keyrom[15:0] <= 16'h0000;
			9'h0aa:		keyrom[15:0] <= 16'h0000;
			9'h0ab:		keyrom[15:0] <= 16'h0000;
			9'h0ac:		keyrom[15:0] <= 16'h0000;
			9'h0ad:		keyrom[15:0] <= 16'h0000;
			9'h0ae:		keyrom[15:0] <= 16'h0000;
			9'h0af:		keyrom[15:0] <= 16'h0000;
			9'h0b0:		keyrom[15:0] <= 16'h0000;
			9'h0b1:		keyrom[15:0] <= 16'h0000;
			9'h0b2:		keyrom[15:0] <= 16'h0000;
			9'h0b3:		keyrom[15:0] <= 16'h0000;
			9'h0b4:		keyrom[15:0] <= 16'h0000;
			9'h0b5:		keyrom[15:0] <= 16'h0000;
			9'h0b6:		keyrom[15:0] <= 16'h0000;
			9'h0b7:		keyrom[15:0] <= 16'h0000;
			9'h0b8:		keyrom[15:0] <= 16'h0000;
			9'h0b9:		keyrom[15:0] <= 16'h0000;
			9'h0ba:		keyrom[15:0] <= 16'h0000;
			9'h0bb:		keyrom[15:0] <= 16'h0000;
			9'h0bc:		keyrom[15:0] <= 16'h0000;
			9'h0bd:		keyrom[15:0] <= 16'h0000;
			9'h0be:		keyrom[15:0] <= 16'h0000;
			9'h0bf:		keyrom[15:0] <= 16'h0000;
			9'h0c0:		keyrom[15:0] <= 16'h0000;
			9'h0c1:		keyrom[15:0] <= 16'h0000;
			9'h0c2:		keyrom[15:0] <= 16'h0000;
			9'h0c3:		keyrom[15:0] <= 16'h0000;
			9'h0c4:		keyrom[15:0] <= 16'h0000;
			9'h0c5:		keyrom[15:0] <= 16'h0000;
			9'h0c6:		keyrom[15:0] <= 16'h0000;
			9'h0c7:		keyrom[15:0] <= 16'h0000;
			9'h0c8:		keyrom[15:0] <= 16'h0000;
			9'h0c9:		keyrom[15:0] <= 16'h0000;
			9'h0ca:		keyrom[15:0] <= 16'h0000;
			9'h0cb:		keyrom[15:0] <= 16'h0000;
			9'h0cc:		keyrom[15:0] <= 16'h0000;
			9'h0cd:		keyrom[15:0] <= 16'h0000;
			9'h0ce:		keyrom[15:0] <= 16'h0000;
			9'h0cf:		keyrom[15:0] <= 16'h0000;
			9'h0d0:		keyrom[15:0] <= 16'h0000;
			9'h0d1:		keyrom[15:0] <= 16'h0000;
			9'h0d2:		keyrom[15:0] <= 16'h0000;
			9'h0d3:		keyrom[15:0] <= 16'h0000;
			9'h0d4:		keyrom[15:0] <= 16'h0000;
			9'h0d5:		keyrom[15:0] <= 16'h0000;
			9'h0d6:		keyrom[15:0] <= 16'h0000;
			9'h0d7:		keyrom[15:0] <= 16'h0000;
			9'h0d8:		keyrom[15:0] <= 16'h0000;
			9'h0d9:		keyrom[15:0] <= 16'h0000;
			9'h0da:		keyrom[15:0] <= 16'h0000;
			9'h0db:		keyrom[15:0] <= 16'h0000;
			9'h0dc:		keyrom[15:0] <= 16'h0000;
			9'h0dd:		keyrom[15:0] <= 16'h0000;
			9'h0de:		keyrom[15:0] <= 16'h0000;
			9'h0df:		keyrom[15:0] <= 16'h0000;
			9'h0e0:		keyrom[15:0] <= 16'h0081;//ps2 extended key
			9'h0e1:		keyrom[15:0] <= 16'h0000;
			9'h0e2:		keyrom[15:0] <= 16'h0000;
			9'h0e3:		keyrom[15:0] <= 16'h0000;
			9'h0e4:		keyrom[15:0] <= 16'h0000;
			9'h0e5:		keyrom[15:0] <= 16'h0000;
			9'h0e6:		keyrom[15:0] <= 16'h0000;
			9'h0e7:		keyrom[15:0] <= 16'h0000;
			9'h0e8:		keyrom[15:0] <= 16'h0000;
			9'h0e9:		keyrom[15:0] <= 16'h0000;
			9'h0ea:		keyrom[15:0] <= 16'h0000;
			9'h0eb:		keyrom[15:0] <= 16'h0000;
			9'h0ec:		keyrom[15:0] <= 16'h0000;
			9'h0ed:		keyrom[15:0] <= 16'h0000;
			9'h0ee:		keyrom[15:0] <= 16'h0000;
			9'h0ef:		keyrom[15:0] <= 16'h0000;
			9'h0f0:		keyrom[15:0] <= 16'h0082;//ps2 release code
			9'h0f1:		keyrom[15:0] <= 16'h0000;
			9'h0f2:		keyrom[15:0] <= 16'h0000;
			9'h0f3:		keyrom[15:0] <= 16'h0000;
			9'h0f4:		keyrom[15:0] <= 16'h0000;
			9'h0f5:		keyrom[15:0] <= 16'h0000;
			9'h0f6:		keyrom[15:0] <= 16'h0000;
			9'h0f7:		keyrom[15:0] <= 16'h0000;
			9'h0f8:		keyrom[15:0] <= 16'h0000;
			9'h0f9:		keyrom[15:0] <= 16'h0000;
			9'h0fa:		keyrom[15:0] <= 16'h0084;//ps2 ack code
			9'h0fb:		keyrom[15:0] <= 16'h0000;
			9'h0fc:		keyrom[15:0] <= 16'h0000;
			9'h0fd:		keyrom[15:0] <= 16'h0000;
			9'h0fe:		keyrom[15:0] <= 16'h0000;
			9'h0ff:		keyrom[15:0] <= 16'h0000;
			9'h100:		keyrom[15:0] <= 16'h0000;
			9'h101:		keyrom[15:0] <= 16'h0000;
			9'h102:		keyrom[15:0] <= 16'h0000;
			9'h103:		keyrom[15:0] <= 16'h0000;
			9'h104:		keyrom[15:0] <= 16'h0000;
			9'h105:		keyrom[15:0] <= 16'h0000;
			9'h106:		keyrom[15:0] <= 16'h0000;
			9'h107:		keyrom[15:0] <= 16'h0000;
			9'h108:		keyrom[15:0] <= 16'h0000;
			9'h109:		keyrom[15:0] <= 16'h0000;
			9'h10a:		keyrom[15:0] <= 16'h0000;
			9'h10b:		keyrom[15:0] <= 16'h0000;
			9'h10c:		keyrom[15:0] <= 16'h0000;
			9'h10d:		keyrom[15:0] <= 16'h0000;
			9'h10e:		keyrom[15:0] <= 16'h0000;
			9'h10f:		keyrom[15:0] <= 16'h0000;
			9'h110:		keyrom[15:0] <= 16'h0000;
			9'h111:		keyrom[15:0] <= 16'h9065;//RIGHT ALT
			9'h112:		keyrom[15:0] <= 16'h0000;
			9'h113:		keyrom[15:0] <= 16'h0000;
			9'h114:		keyrom[15:0] <= 16'h0000;
			9'h115:		keyrom[15:0] <= 16'h0000;
			9'h116:		keyrom[15:0] <= 16'h0000;
			9'h117:		keyrom[15:0] <= 16'h0000;
			9'h118:		keyrom[15:0] <= 16'h0000;
			9'h119:		keyrom[15:0] <= 16'h0000;
			9'h11a:		keyrom[15:0] <= 16'h0000;
			9'h11b:		keyrom[15:0] <= 16'h0000;
			9'h11c:		keyrom[15:0] <= 16'h0000;
			9'h11d:		keyrom[15:0] <= 16'h0000;
			9'h11e:		keyrom[15:0] <= 16'h0000;
			9'h11f:		keyrom[15:0] <= 16'h8066;//LEFT AMIGA (LEFT GUI)
			9'h120:		keyrom[15:0] <= 16'h0000;
			9'h121:		keyrom[15:0] <= 16'h0000;
			9'h122:		keyrom[15:0] <= 16'h0000;
			9'h123:		keyrom[15:0] <= 16'h0000;
			9'h124:		keyrom[15:0] <= 16'h0000;
			9'h125:		keyrom[15:0] <= 16'h0000;
			9'h126:		keyrom[15:0] <= 16'h0000;
			9'h127:		keyrom[15:0] <= 16'h8067;//RIGHT AMIGA (RIGHT GUI)
			9'h128:		keyrom[15:0] <= 16'h0000;
			9'h129:		keyrom[15:0] <= 16'h0000;
			9'h12a:		keyrom[15:0] <= 16'h0000;
			9'h12b:		keyrom[15:0] <= 16'h0000;
			9'h12c:		keyrom[15:0] <= 16'h0000;
			9'h12d:		keyrom[15:0] <= 16'h0000;
			9'h12e:		keyrom[15:0] <= 16'h0000;
			9'h12f:		keyrom[15:0] <= 16'h8067;//RIGHT AMIGA (APPS)
			9'h130:		keyrom[15:0] <= 16'h0000;
			9'h131:		keyrom[15:0] <= 16'h0000;
			9'h132:		keyrom[15:0] <= 16'h0000;
			9'h133:		keyrom[15:0] <= 16'h0000;
			9'h134:		keyrom[15:0] <= 16'h0000;
			9'h135:		keyrom[15:0] <= 16'h0000;
			9'h136:		keyrom[15:0] <= 16'h0000;
			9'h137:		keyrom[15:0] <= 16'h0000;
			9'h138:		keyrom[15:0] <= 16'h0000;
			9'h139:		keyrom[15:0] <= 16'h0000;
			9'h13a:		keyrom[15:0] <= 16'h0000;
			9'h13b:		keyrom[15:0] <= 16'h0000;
			9'h13c:		keyrom[15:0] <= 16'h0000;
			9'h13d:		keyrom[15:0] <= 16'h0000;
			9'h13e:		keyrom[15:0] <= 16'h0000;
			9'h13f:		keyrom[15:0] <= 16'h0000;
			9'h140:		keyrom[15:0] <= 16'h0000;
			9'h141:		keyrom[15:0] <= 16'h0000;
			9'h142:		keyrom[15:0] <= 16'h0000;
			9'h143:		keyrom[15:0] <= 16'h0000;
			9'h144:		keyrom[15:0] <= 16'h0000;
			9'h145:		keyrom[15:0] <= 16'h0000;
			9'h146:		keyrom[15:0] <= 16'h0000;
			9'h147:		keyrom[15:0] <= 16'h0000;
			9'h148:		keyrom[15:0] <= 16'h0000;
			9'h149:		keyrom[15:0] <= 16'h0000;
			9'h14a:		keyrom[15:0] <= 16'h825c;//KP /
			9'h14b:		keyrom[15:0] <= 16'h0000;
			9'h14c:		keyrom[15:0] <= 16'h0000;
			9'h14d:		keyrom[15:0] <= 16'h0000;
			9'h14e:		keyrom[15:0] <= 16'h0000;
			9'h14f:		keyrom[15:0] <= 16'h0000;
			9'h150:		keyrom[15:0] <= 16'h0000;
			9'h151:		keyrom[15:0] <= 16'h0000;
			9'h152:		keyrom[15:0] <= 16'h0000;
			9'h153:		keyrom[15:0] <= 16'h0000;
			9'h154:		keyrom[15:0] <= 16'h0000;
			9'h155:		keyrom[15:0] <= 16'h0000;
			9'h156:		keyrom[15:0] <= 16'h0000;
			9'h157:		keyrom[15:0] <= 16'h0000;
			9'h158:		keyrom[15:0] <= 16'h0000;
			9'h159:		keyrom[15:0] <= 16'h0000;
			9'h15a:		keyrom[15:0] <= 16'h8243;//KP ENTER
			9'h15b:		keyrom[15:0] <= 16'h0000;
			9'h15c:		keyrom[15:0] <= 16'h0000;
			9'h15d:		keyrom[15:0] <= 16'h0000;
			9'h15e:		keyrom[15:0] <= 16'h0000;
			9'h15f:		keyrom[15:0] <= 16'h0000;
			9'h160:		keyrom[15:0] <= 16'h0000;
			9'h161:		keyrom[15:0] <= 16'h0000;
			9'h162:		keyrom[15:0] <= 16'h0000;
			9'h163:		keyrom[15:0] <= 16'h0000;
			9'h164:		keyrom[15:0] <= 16'h0000;
			9'h165:		keyrom[15:0] <= 16'h0000;
			9'h166:		keyrom[15:0] <= 16'h0000;
			9'h167:		keyrom[15:0] <= 16'h0000;
			9'h168:		keyrom[15:0] <= 16'h0000;
			9'h169:		keyrom[15:0] <= 16'h016B;//END
			9'h16a:		keyrom[15:0] <= 16'h0000;
			9'h16b:		keyrom[15:0] <= 16'h804f;//ARROW LEFT
			9'h16c:		keyrom[15:0] <= 16'h016A;//HOME
			9'h16d:		keyrom[15:0] <= 16'h0000;
			9'h16e:		keyrom[15:0] <= 16'h0000;
			9'h16f:		keyrom[15:0] <= 16'h0000;
			9'h170:		keyrom[15:0] <= 16'h805f;//INSERT = HELP
			9'h171:		keyrom[15:0] <= 16'h8046;//DELETE
			9'h172:		keyrom[15:0] <= 16'h804d;//ARROW DOWN
			9'h173:		keyrom[15:0] <= 16'h0000;
			9'h174:		keyrom[15:0] <= 16'h804e;//ARROW RIGHT
			9'h175:		keyrom[15:0] <= 16'h804c;//ARROW UP
			9'h176:		keyrom[15:0] <= 16'h0000;
			9'h177:		keyrom[15:0] <= 16'h0000;
			9'h178:		keyrom[15:0] <= 16'h0000;
			9'h179:		keyrom[15:0] <= 16'h0000;
			9'h17a:		keyrom[15:0] <= 16'h016D;//PGDN <OSD>
			9'h17b:		keyrom[15:0] <= 16'h0000;
			9'h17c:		keyrom[15:0] <= 16'h016E;//PRTSCR <OSD>
			9'h17d:		keyrom[15:0] <= 16'h016C;//PGUP <OSD>
			9'h17e:		keyrom[15:0] <= 16'h016F;//ctrl+break
			9'h17f:		keyrom[15:0] <= 16'h0000;
			9'h180:		keyrom[15:0] <= 16'h0000;
			9'h181:		keyrom[15:0] <= 16'h0000;
			9'h182:		keyrom[15:0] <= 16'h0000;
			9'h183:		keyrom[15:0] <= 16'h0000;
			9'h184:		keyrom[15:0] <= 16'h0000;
			9'h185:		keyrom[15:0] <= 16'h0000;
			9'h186:		keyrom[15:0] <= 16'h0000;
			9'h187:		keyrom[15:0] <= 16'h0000;
			9'h188:		keyrom[15:0] <= 16'h0000;
			9'h189:		keyrom[15:0] <= 16'h0000;
			9'h18a:		keyrom[15:0] <= 16'h0000;
			9'h18b:		keyrom[15:0] <= 16'h0000;
			9'h18c:		keyrom[15:0] <= 16'h0000;
			9'h18d:		keyrom[15:0] <= 16'h0000;
			9'h18e:		keyrom[15:0] <= 16'h0000;
			9'h18f:		keyrom[15:0] <= 16'h0000;
			9'h190:		keyrom[15:0] <= 16'h0000;
			9'h191:		keyrom[15:0] <= 16'h0000;
			9'h192:		keyrom[15:0] <= 16'h0000;
			9'h193:		keyrom[15:0] <= 16'h0000;
			9'h194:		keyrom[15:0] <= 16'h0000;
			9'h195:		keyrom[15:0] <= 16'h0000;
			9'h196:		keyrom[15:0] <= 16'h0000;
			9'h197:		keyrom[15:0] <= 16'h0000;
			9'h198:		keyrom[15:0] <= 16'h0000;
			9'h199:		keyrom[15:0] <= 16'h0000;
			9'h19a:		keyrom[15:0] <= 16'h0000;
			9'h19b:		keyrom[15:0] <= 16'h0000;
			9'h19c:		keyrom[15:0] <= 16'h0000;
			9'h19d:		keyrom[15:0] <= 16'h0000;
			9'h19e:		keyrom[15:0] <= 16'h0000;
			9'h19f:		keyrom[15:0] <= 16'h0000;
			9'h1a0:		keyrom[15:0] <= 16'h0000;
			9'h1a1:		keyrom[15:0] <= 16'h0000;
			9'h1a2:		keyrom[15:0] <= 16'h0000;
			9'h1a3:		keyrom[15:0] <= 16'h0000;
			9'h1a4:		keyrom[15:0] <= 16'h0000;
			9'h1a5:		keyrom[15:0] <= 16'h0000;
			9'h1a6:		keyrom[15:0] <= 16'h0000;
			9'h1a7:		keyrom[15:0] <= 16'h0000;
			9'h1a8:		keyrom[15:0] <= 16'h0000;
			9'h1a9:		keyrom[15:0] <= 16'h0000;
			9'h1aa:		keyrom[15:0] <= 16'h0000;
			9'h1ab:		keyrom[15:0] <= 16'h0000;
			9'h1ac:		keyrom[15:0] <= 16'h0000;
			9'h1ad:		keyrom[15:0] <= 16'h0000;
			9'h1ae:		keyrom[15:0] <= 16'h0000;
			9'h1af:		keyrom[15:0] <= 16'h0000;
			9'h1b0:		keyrom[15:0] <= 16'h0000;
			9'h1b1:		keyrom[15:0] <= 16'h0000;
			9'h1b2:		keyrom[15:0] <= 16'h0000;
			9'h1b3:		keyrom[15:0] <= 16'h0000;
			9'h1b4:		keyrom[15:0] <= 16'h0000;
			9'h1b5:		keyrom[15:0] <= 16'h0000;
			9'h1b6:		keyrom[15:0] <= 16'h0000;
			9'h1b7:		keyrom[15:0] <= 16'h0000;
			9'h1b8:		keyrom[15:0] <= 16'h0000;
			9'h1b9:		keyrom[15:0] <= 16'h0000;
			9'h1ba:		keyrom[15:0] <= 16'h0000;
			9'h1bb:		keyrom[15:0] <= 16'h0000;
			9'h1bc:		keyrom[15:0] <= 16'h0000;
			9'h1bd:		keyrom[15:0] <= 16'h0000;
			9'h1be:		keyrom[15:0] <= 16'h0000;
			9'h1bf:		keyrom[15:0] <= 16'h0000;
			9'h1c0:		keyrom[15:0] <= 16'h0000;
			9'h1c1:		keyrom[15:0] <= 16'h0000;
			9'h1c2:		keyrom[15:0] <= 16'h0000;
			9'h1c3:		keyrom[15:0] <= 16'h0000;
			9'h1c4:		keyrom[15:0] <= 16'h0000;
			9'h1c5:		keyrom[15:0] <= 16'h0000;
			9'h1c6:		keyrom[15:0] <= 16'h0000;
			9'h1c7:		keyrom[15:0] <= 16'h0000;
			9'h1c8:		keyrom[15:0] <= 16'h0000;
			9'h1c9:		keyrom[15:0] <= 16'h0000;
			9'h1ca:		keyrom[15:0] <= 16'h0000;
			9'h1cb:		keyrom[15:0] <= 16'h0000;
			9'h1cc:		keyrom[15:0] <= 16'h0000;
			9'h1cd:		keyrom[15:0] <= 16'h0000;
			9'h1ce:		keyrom[15:0] <= 16'h0000;
			9'h1cf:		keyrom[15:0] <= 16'h0000;
			9'h1d0:		keyrom[15:0] <= 16'h0000;
			9'h1d1:		keyrom[15:0] <= 16'h0000;
			9'h1d2:		keyrom[15:0] <= 16'h0000;
			9'h1d3:		keyrom[15:0] <= 16'h0000;
			9'h1d4:		keyrom[15:0] <= 16'h0000;
			9'h1d5:		keyrom[15:0] <= 16'h0000;
			9'h1d6:		keyrom[15:0] <= 16'h0000;
			9'h1d7:		keyrom[15:0] <= 16'h0000;
			9'h1d8:		keyrom[15:0] <= 16'h0000;
			9'h1d9:		keyrom[15:0] <= 16'h0000;
			9'h1da:		keyrom[15:0] <= 16'h0000;
			9'h1db:		keyrom[15:0] <= 16'h0000;
			9'h1dc:		keyrom[15:0] <= 16'h0000;
			9'h1dd:		keyrom[15:0] <= 16'h0000;
			9'h1de:		keyrom[15:0] <= 16'h0000;
			9'h1df:		keyrom[15:0] <= 16'h0000;
			9'h1e0:		keyrom[15:0] <= 16'h0081;//ps2 extended key(duplicate, see $e0)
			9'h1e1:		keyrom[15:0] <= 16'h0000;
			9'h1e2:		keyrom[15:0] <= 16'h0000;
			9'h1e3:		keyrom[15:0] <= 16'h0000;
			9'h1e4:		keyrom[15:0] <= 16'h0000;
			9'h1e5:		keyrom[15:0] <= 16'h0000;
			9'h1e6:		keyrom[15:0] <= 16'h0000;
			9'h1e7:		keyrom[15:0] <= 16'h0000;
			9'h1e8:		keyrom[15:0] <= 16'h0000;
			9'h1e9:		keyrom[15:0] <= 16'h0000;
			9'h1ea:		keyrom[15:0] <= 16'h0000;
			9'h1eb:		keyrom[15:0] <= 16'h0000;
			9'h1ec:		keyrom[15:0] <= 16'h0000;
			9'h1ed:		keyrom[15:0] <= 16'h0000;
			9'h1ee:		keyrom[15:0] <= 16'h0000;
			9'h1ef:		keyrom[15:0] <= 16'h0000;
			9'h1f0:		keyrom[15:0] <= 16'h0082;//ps2 release code(duplicate, see $f0)
			9'h1f1:		keyrom[15:0] <= 16'h0000;
			9'h1f2:		keyrom[15:0] <= 16'h0000;
			9'h1f3:		keyrom[15:0] <= 16'h0000;
			9'h1f4:		keyrom[15:0] <= 16'h0000;
			9'h1f5:		keyrom[15:0] <= 16'h0000;
			9'h1f6:		keyrom[15:0] <= 16'h0000;
			9'h1f7:		keyrom[15:0] <= 16'h0000;
			9'h1f8:		keyrom[15:0] <= 16'h0000;
			9'h1f9:		keyrom[15:0] <= 16'h0000;
			9'h1fa:		keyrom[15:0] <= 16'h0084;//ps2 ack code(duplicate see $fa)
			9'h1fb:		keyrom[15:0] <= 16'h0000;
			9'h1fc:		keyrom[15:0] <= 16'h0000;
			9'h1fd:		keyrom[15:0] <= 16'h0000;
			9'h1fe:		keyrom[15:0] <= 16'h0000;
			9'h1ff:		keyrom[15:0] <= 16'h0000;
	 	endcase
	end
end


endmodule
