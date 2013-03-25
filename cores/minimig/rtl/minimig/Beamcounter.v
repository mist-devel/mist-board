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
// JB:
// 14-03-2008	- moving beamcounter to a separate file
//				- pal/ntsc switching, NTSC doesn't use short/long line toggling,all lines are short like in PAL (227 CCKs)
//				- composite blanking use hblank which is combined with vblank
// 2009-03-08	- clean-up
// 2009-05-24	- clean-up & renaming
// 2009-06-10	- in non-interlace mode all frames are long (313 lines for PAL)
// 2010-01-19	- added vertical interrupt request signal for Paula
// 2010-04-14	- A1000 compatible VBL interrupt generation
//
// SB:
// 2011-04-10 - added readable VPOSW and VHPOSW register (fix for RSI slideshow)

module beamcounter
(
	input	clk,					// bus clock
	input	reset,					// reset
	input	cck,					// CCK clock
	input	ntsc,					// NTSC mode switch
	input	ecs,					// ECS enable switch
	input	a1k,					// enable A1000 VBL interrupt timing
	input	[15:0] data_in,			// bus data in
	output	reg [15:0] data_out,	// bus data out
	input 	[8:1] reg_address_in,	// register address inputs
	output	reg [8:0] hpos,			// horizontal beam counter (140ns)
	output	reg [10:0] vpos,		// vertical beam counter
	output	reg _hsync,				// horizontal sync
	output	reg _vsync,				// vertical sync
	output	_csync,					// composite sync
	output	reg blank,				// video blanking
	output	vbl,					// vertical blanking
	output	vblend,					// last line of vertival blanking
	output	eol,					// end of video line
	output	eof,					// end of video frame
	output	reg vbl_int,			// vertical interrupt request (for Paula)
	output	[8:1] htotal			// video line length
);

// local beam position counters
reg		ersy;
reg		lace;

//local signals for beam counters and sync generator
reg		long_frame;		// 1 : long frame (313 lines); 0 : normal frame (312 lines)
reg		pal;			// pal mode switch
reg		long_line;		// long line signal for NTSC compatibility (actually long lines are not supported yet)
reg		vser;			// vertical sync serration pulses for composite sync

//register names and adresses		
parameter	VPOSR    = 9'h004;
parameter	VPOSW    = 9'h02A;
parameter	VHPOSR   = 9'h006;
parameter	VHPOSW   = 9'h02C;
parameter	BEAMCON0 = 9'h1DC;
parameter	BPLCON0  = 9'h100;

//parameter	HTOTAL  = 9'h1C0;
//parameter	HSSTOP  = 9'h1C2;
//parameter	HBSTRT  = 9'h1C4;
//parameter	HBSTOP  = 9'h1C6;
//parameter	VTOTAL  = 9'h1C8;
//parameter	VSSTOP  = 9'h1CA;
//parameter	VBSTRT  = 9'h1CC;
//parameter	VBSTOP  = 9'h1CE;
//parameter	BEAMCON = 9'h1DC;
//parameter	HSSTRT  = 9'h1DE;
//parameter	VSSTRT  = 9'h1E0;
//parameter	HCENTER = 9'h1E2;

parameter	hbstrt  = 17+4+4;	// horizontal blanking start
parameter	hsstrt  = 29+4+4;	// front porch = 1.6us (29)
parameter	hsstop  = 63-1+4+4;	// hsync pulse duration = 4.7us (63)
parameter	hbstop  = 103-5+4;	// back porch = 4.7us (103) shorter blanking for overscan visibility
parameter	hcenter = 256+4+4;	// position of vsync pulse during the long field of interlaced screen
parameter	vsstrt  = 2; //3	// vertical sync start
parameter	vsstop  = 5;	// PAL vsync width: 2.5 lines (NTSC: 3 lines - not implemented)
parameter	vbstrt  = 0;	// vertical blanking start

wire	[10:0] vtotal;		// total number of lines less one
wire	[8:0] vbstop;		// vertical blanking stop

reg		end_of_line;
wire	end_of_frame;

reg 	vpos_inc;			// increase vertical position counter
wire 	vpos_equ_vtotal;	// vertical beam counter is equal to its maximum count (in interlaced mode it counts one line more)
reg		extra_line;			// extra line (used in interlaced mode)
wire	last_line;			// indicates the last line is displayed (in non-interlaced mode vpos equals to vtotal, in interlaced mode vpos equals to vtotal+1)


//beam position output signals
assign	htotal = 8'd227 - 8'd1;					// line length of 227 CCKs in PAL mode (NTSC line length of 227.5 CCKs is not supported)
assign	vtotal = pal ? 11'd312 - 11'd1 : 11'd262 - 11'd1;	// total number of lines (PAL: 312 lines, NTSC: 262)
assign	vbstop = pal ? 9'd25 : 9'd20;			// vertical blanking end (PAL 26 lines, NTSC vblank 21 lines)

//first visible line $1A (PAL) or $15 (NTSC)
//sprites are fetched on line $19 (PAL) or $14 (NTSC) - vblend signal used to tell Agnus to fetch sprites during the last vertical blanking line

//--------------------------------------------------------------------------------------

//beamcounter read registers VPOSR and VHPOSR
always @(reg_address_in or long_frame or long_line or vpos or hpos or ntsc or ecs)
	if (reg_address_in[8:1]==VPOSR[8:1] || reg_address_in[8:1]==VPOSW[8:1])
		data_out[15:0] = {long_frame,1'b0,ecs,ntsc,4'b0000,long_line,4'b0000,vpos[10:8]};
	else if (reg_address_in[8:1]==VHPOSR[8:1] || reg_address_in[8:1]==VHPOSW[8:1])
		data_out[15:0] = {vpos[7:0],hpos[8:1]};
	else
		data_out[15:0] = 0;

//write ERSY bit of bplcon0 register (External ReSYnchronization - genlock)
always @(posedge clk)
	if (reset)
		ersy <= 1'b0;
	else if (reg_address_in[8:1] == BPLCON0[8:1])
		ersy <= data_in[1];
		
//BPLCON0 register
always @(posedge clk)
	if (reset)
		lace <= 1'b0;
	else if (reg_address_in[8:1]==BPLCON0[8:1])
		lace <= data_in[2];

//BEAMCON0 register
always @(posedge clk)
	if (reset)
		pal <= ~ntsc;
	else if (reg_address_in[8:1]==BEAMCON0[8:1] && ecs)
		pal <= data_in[5];

//--------------------------------------------------------------------------------------//
//                                                                                      //
//   HORIZONTAL BEAM COUNTER                                                            //
//                                                                                      //
//--------------------------------------------------------------------------------------//

//generate start of line signal
always @(posedge clk)
	if (hpos[8:0]=={htotal[8:1],1'b0})
		end_of_line <= 1'b1;
	else
		end_of_line <= 1'b0;

// horizontal beamcounter
always @(posedge clk)
	if (reg_address_in[8:1]==VHPOSW[8:1])
		hpos[8:1] <= data_in[7:0]; 
	else if (end_of_line)
		hpos[8:1] <= 0;
	else if (cck && (~ersy || |hpos[8:1]))
		hpos[8:1] <= hpos[8:1] + 1'b1;
		
always @(cck)
	hpos[0] = cck;

//long line signal (not used, only for better NTSC compatibility)
always @(posedge clk)
	if (end_of_line)
		if (pal)
			long_line <= 1'b0;
		else
			long_line <= ~long_line;

//--------------------------------------------------------------------------------------//
//                                                                                      //
//   VERTICAL BEAM COUNTER                                                              //
//                                                                                      //
//--------------------------------------------------------------------------------------//

//vertical counter increase
always @(posedge clk)
	if (hpos==2) //actual chipset works in this way
		vpos_inc <= 1'b1;
	else
		vpos_inc <= 1'b0;

//external signals assigment
assign eol = vpos_inc;

//vertical position counter
//vpos changes after hpos equals 3
always @(posedge clk)
	if (reg_address_in[8:1]==VPOSW[8:1])
		vpos[10:8] <= data_in[2:0];
	else if (reg_address_in[8:1]==VHPOSW[8:1])
		vpos[7:0] <= data_in[15:8];
	else if (vpos_inc)
		if (last_line)
			vpos <= 0;
		else
			vpos <= vpos + 1'b1;

// long_frame - long frame signal used in interlaced mode
always @(posedge clk)
	if (reset)
		long_frame <= 1'b1;
	else if (reg_address_in[8:1]==VPOSW[8:1])
		long_frame <= data_in[15];
	else if (end_of_frame && lace) // interlace
		long_frame <= ~long_frame;

//maximum position of vertical beam position
assign vpos_equ_vtotal = vpos==vtotal ? 1'b1 : 1'b0;

//extra line in interlaced mode	
always @(posedge clk)
	if (vpos_inc)
		if (long_frame && vpos_equ_vtotal)
			extra_line <= 1'b1;
		else
			extra_line <= 1'b0;

//in non-interlaced display the last line is equal to vtotal or vtotal+1 (depends on long_frame)
//in interlaced mode every second frame is vtotal+1 long
assign last_line = long_frame ? extra_line : vpos_equ_vtotal;

//generate end of frame signal
assign end_of_frame = vpos_inc & last_line;

//external signal assigment
assign eof = end_of_frame;

always @(posedge clk)
	vbl_int <= hpos==8 && vpos==(a1k ? 1 : 0) ? 1'b1 : 1'b0; // OCS AGNUS CHIPS 8361/8367 assert vbl int in line #1

//--------------------------------------------------------------------------------------//
//                                                                                      //
//  VIDEO SYNC GENERATOR                                                                //
//                                                                                      //
//--------------------------------------------------------------------------------------//

//horizontal sync
always @(posedge clk)
	if (hpos==hsstrt)//start of sync pulse (front porch = 1.69us)
		_hsync <= 1'b0;
	else if (hpos==hsstop)//end of sync pulse (sync pulse = 4.65us)
		_hsync <= 1'b1;

//vertical sync and vertical blanking
always @(posedge clk)
	if ((vpos==vsstrt && hpos==hsstrt && !long_frame) || (vpos==vsstrt && hpos==hcenter && long_frame))
		_vsync <= 1'b0;
	else if ((vpos==vsstop && hpos==hcenter && !long_frame) || (vpos==vsstop+1 && hpos==hsstrt && long_frame))
		_vsync <= 1'b1;		

//apparently generating csync from vsync alligned with leading edge of hsync results in malfunction of the AD724 CVBS/S-Video encoder (no colour in interlaced mode)
//to overcome this limitation semi (only present before horizontal sync pulses) vertical sync serration pulses are inserted into csync
always @(posedge clk)//sync
	if (hpos==hsstrt-(hsstop-hsstrt))//start of sync pulse (front porch = 1.69us)
		vser <= 1'b1;
	else if (hpos==hsstrt)//end of sync pulse	(sync pulse = 4.65us)
		vser <= 1'b0;
		
//composite sync
assign _csync = _hsync & _vsync | vser; //composite sync with serration pulses

//--------------------------------------------------------------------------------------//
//                                                                                      //
//  VIDEO BLANKING GENERATOR                                                            //
//                                                                                      //
//--------------------------------------------------------------------------------------//

//vertical blanking
assign vbl = vpos <= vbstop ? 1'b1 : 1'b0;

//vertical blanking end (last line)
assign vblend = vpos==vbstop ? 1'b1 : 1'b0;

//composite display blanking		
always @(posedge clk)
	if (hpos==hbstrt)//start of blanking (active line=51.88us)
		blank <= 1'b1;
	else if (hpos==hbstop)//end of blanking (back porch=5.78us)
		blank <= vbl;

endmodule
