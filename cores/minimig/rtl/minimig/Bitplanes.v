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
// This is the bitplane part of denise 
// It accepts data from the bus and converts it to serial video data (6 bits).
// It supports all ocs modes and also handles the pf1<->pf2 priority handling in
// a seperate module.
//
// 11-05-2005	-started coding
// 15-05-2005	-first finished version
// 16-05-2005	-fixed hires scrolling, now you can fetch 2 words early
// 22-05-2005	-fixed bug in dual playfield mode when both playfields where transparant
// 22-06-2005	-moved playfield engine / priority logic to seperate module
// ----------
// JB:
// 2008-12-27	- addapted playfield horizontal scrolling
// 2009-02-09	- added hpos for proper horizontal scroll of non-aligned dma fetches
// 2009-05-24	- clean-up & renaming
// 2009-10-07	- pixel pipe line extra delay (alligment of bitplane data and copper colour change)


module bitplanes
(
	input 	clk,		   			// system bus clock
	input 	clk28m,					// 35ns pixel clock
	input 	c1,						// 35ns clock enable signals (for synchronization with clk)
	input 	c3,
	input 	[8:1] reg_address_in, 	// register address
	input 	[15:0] data_in,	 		// bus data in
	input 	hires,		   			// high resolution mode select
	input 	shres,		   			// super high resolution mode select
	input	[8:0] hpos,				// horizontal position (70ns resolution)
	output 	[6:1] bpldata			// bitplane data out
);
//register names and adresses
parameter BPLCON1 = 9'h102;  		
parameter BPL1DAT = 9'h110;
parameter BPL2DAT = 9'h112;
parameter BPL3DAT = 9'h114;
parameter BPL4DAT = 9'h116;
parameter BPL5DAT = 9'h118;
parameter BPL6DAT = 9'h11a;

//local signals
reg 	[7:0] bplcon1;		// bplcon1 register
reg		[15:0] bpl1dat;		// buffer register for bit plane 2
reg		[15:0] bpl2dat;		// buffer register for bit plane 2
reg		[15:0] bpl3dat;		// buffer register for bit plane 3
reg		[15:0] bpl4dat;		// buffer register for bit plane 4
reg		[15:0] bpl5dat;		// buffer register for bit plane 5
reg		[15:0] bpl6dat;		// buffer register for bit plane 6
reg		load;				// bpl1dat written => load shif registers

reg		[3:0] extra_delay;	// extra delay when not alligned ddfstart
reg		[3:0] pf1h;			// playfield 1 horizontal scroll
reg		[3:0] pf2h;			// playfield 2 horizontal scroll
reg		[3:0] pf1h_del;		// delayed playfield 1 horizontal scroll
reg		[3:0] pf2h_del;		// delayed playfield 2 horizontal scroll

//--------------------------------------------------------------------------------------

// horizontal scroll depends on horizontal position when BPL0DAT in written
// visible display scroll is updated on fetch boundaries
// increasing scroll value during active display inserts blank pixels

always @(hpos)
	case (hpos[3:2])
		2'b00 : extra_delay = 4'b0000;
		2'b01 : extra_delay = 4'b1100;
		2'b10 : extra_delay = 4'b1000;
		2'b11 : extra_delay = 4'b0100;
	endcase

//playfield 1 effective horizontal scroll
always @(posedge clk)
	if (load)
		pf1h <= bplcon1[3:0] + extra_delay;

always @(posedge clk)
	pf1h_del <= pf1h;
		
//playfield 2 effective horizontal scroll
always @(posedge clk)
	if (load)
		pf2h <= bplcon1[7:4] + extra_delay;

always @(posedge clk)
	pf2h_del <= pf2h;
	
//writing bplcon1 register : horizontal scroll codes for even and odd bitplanes
always @(posedge clk)
	if (reg_address_in[8:1]==BPLCON1[8:1])
		bplcon1 <= data_in[7:0];

//--------------------------------------------------------------------------------------

//bitplane buffer register for plane 1
always @(posedge clk)
	if (reg_address_in[8:1]==BPL1DAT[8:1])
		bpl1dat <= data_in[15:0];
		
//bitplane buffer register for plane 2
always @(posedge clk)
	if (reg_address_in[8:1]==BPL2DAT[8:1])
		bpl2dat <= data_in[15:0];

//bitplane buffer register for plane 3
always @(posedge clk)
	if (reg_address_in[8:1]==BPL3DAT[8:1])
		bpl3dat <= data_in[15:0];

//bitplane buffer register for plane 4
always @(posedge clk)
	if (reg_address_in[8:1]==BPL4DAT[8:1])
		bpl4dat <= data_in[15:0];

//bitplane buffer register for plane 5
always @(posedge clk)
	if (reg_address_in[8:1]==BPL5DAT[8:1])
		bpl5dat <= data_in[15:0];

//bitplane buffer register for plane 6
always @(posedge clk)
	if (reg_address_in[8:1]==BPL6DAT[8:1])
		bpl6dat <= data_in[15:0];

//generate load signal when plane 1 is written
always @(posedge clk)
	load <= reg_address_in[8:1]==BPL1DAT[8:1] ? 1'b1 : 1'b0;

//--------------------------------------------------------------------------------------

//instantiate bitplane 1 parallel to serial converters, this plane is loaded directly from bus
bitplane_shifter bplshft1 
(
	.clk28m(clk28m),
	.c1(c1),
	.c3(c3),
	.load(load),
	.hires(hires),
	.shres(shres),
	.data_in(bpl1dat),
	.scroll(pf1h_del),
	.out(bpldata[1])	
);

//instantiate bitplane 2 to 6 parallel to serial converters, (loaded from buffer registers)
bitplane_shifter bplshft2 
(	
	.clk28m(clk28m),
	.c1(c1),
	.c3(c3),
	.load(load),
	.hires(hires),
	.shres(shres),
	.data_in(bpl2dat),
	.scroll(pf2h_del),
	.out(bpldata[2])	
);

bitplane_shifter bplshft3 
(	
	.clk28m(clk28m),
	.c1(c1),
	.c3(c3),
	.load(load),
	.hires(hires),
	.shres(shres),
	.data_in(bpl3dat),
	.scroll(pf1h_del),
	.out(bpldata[3])	
);

bitplane_shifter bplshft4 
(	
	.clk28m(clk28m),
	.c1(c1),
	.c3(c3),
	.load(load),
	.hires(hires),
	.shres(shres),
	.data_in(bpl4dat),
	.scroll(pf2h_del),
	.out(bpldata[4])	
);

bitplane_shifter bplshft5 
(	
	.clk28m(clk28m),
	.c1(c1),
	.c3(c3),
	.load(load),
	.hires(hires),
	.shres(shres),
	.data_in(bpl5dat),
	.scroll(pf1h_del),
	.out(bpldata[5])	
);

bitplane_shifter bplshft6 
(	
	.clk28m(clk28m),
	.c1(c1),
	.c3(c3),
	.load(load),
	.hires(hires),
	.shres(shres),
	.data_in(bpl6dat),
	.scroll(pf2h_del),
	.out(bpldata[6])	
);

//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//This is the playfield engine.
//It takes the raw bitplane data and generates a
//single or dual playfield
//it also generated the nplayfield valid data signals which are needed
//by the main video priority logic in Denise

module playfields
(
	input 	[6:1] bpldata,	   		//raw bitplane data in
	input 	dblpf,		   			//double playfield select
	input	[6:0] bplcon2,			//bplcon2 (playfields priority)
	output	reg [2:1] nplayfield,	//playfield 1,2 valid data
	output	reg [5:0] plfdata		//playfield data out
);

//local signals
wire pf2pri;						//playfield 2 priority over playfield 1
wire [2:0] pf2p;					//playfield 2 priority code

assign pf2pri = bplcon2[6];
assign pf2p = bplcon2[5:3];

//generate playfield 1,2 data valid signals
always @(dblpf or bpldata)
begin
	if (dblpf) //dual playfield
	begin
		if (bpldata[5] || bpldata[3] || bpldata[1]) //detect data valid for playfield 1
			nplayfield[1] = 1;
		else
			nplayfield[1] = 0;
			
		if (bpldata[6] || bpldata[4] || bpldata[2]) //detect data valid for playfield 2
			nplayfield[2] = 1;
		else
			nplayfield[2] = 0;	
	end
	else //single playfield is always playfield 2
	begin
		nplayfield[1] = 0;
		if (bpldata[6:1]!=6'b000000)
			nplayfield[2] = 1;
		else
			nplayfield[2] = 0;	
	end
end

//--------------------------------------------------------------------------------------

//playfield 1 and 2 priority logic
always @(nplayfield or dblpf or pf2pri or bpldata or pf2p)
begin
	if (dblpf) //dual playfield
	begin
		if (pf2pri) //playfield 2 (2,4,6) has priority
		begin
			if (nplayfield[2])
				plfdata[5:0] = {3'b001,bpldata[6],bpldata[4],bpldata[2]};
			else if (nplayfield[1])
				plfdata[5:0] = {3'b000,bpldata[5],bpldata[3],bpldata[1]};
			else //both planes transparant, select background color
				plfdata[5:0] = 6'b000000;
		end
		else //playfield 1 (1,3,5) has priority
		begin
			if (nplayfield[1])
				plfdata[5:0] = {3'b000,bpldata[5],bpldata[3],bpldata[1]};
			else if (nplayfield[2])
				plfdata[5:0] = {3'b001,bpldata[6],bpldata[4],bpldata[2]};
			else //both planes transparant, select background color
				plfdata[5:0] = 6'b000000;
		end
	end
	else //normal single playfield (playfield 2 only)
	//OCS/ECS undocumented feature when bpu=5 and pf2pri>5 (Swiv score display)
		if (pf2p>5 && bpldata[5])
			plfdata[5:0] = {6'b010000};
		else
			plfdata[5:0] = bpldata[6:1];
end

//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//this is the bitplane parallel to serial converter
module bitplane_shifter
(
	input 	clk28m,		   		//35ns pixel clock
	input	c1,
	input	c3,
	input	load,				//load shift register
	input	hires,				//high resolution select
	input	shres,				//super high resolution select (takes priority over hires)
	input	[15:0] data_in,		//parallel load data input
	input	[3:0] scroll,		//scrolling value
	output	out					//shift register out
);

//local signals
reg		[15:0] shifter;			//main shifter
reg		[15:0] scroller;		//scroller shifter
reg		shift;					//shifter enable
reg	 	[3:0] select;			//delayed pixel select
wire	scroller_out;
reg		[3:0] delay;

//--------------------------------------------------------------------------------------

//main shifter
always @(posedge clk28m)
	if (load && !c1 && !c3) //load new data into shifter
		shifter[15:0] <= data_in[15:0];
	else if (shift) //shift already loaded data
		shifter[15:0] <= {shifter[14:0],1'b0};

always @(posedge clk28m)
	if (shift) //shift scroller data
		scroller[15:0] <= {scroller[14:0],shifter[15]};

assign scroller_out = scroller[select[3:0]];//select odd pixel

//--------------------------------------------------------------------------------------

//delay by one low resolution pixel
always @(posedge clk28m)
	delay[3:0] <= {delay[2:0], scroller_out};
	
// select output pixel
assign out = delay[3];

//--------------------------------------------------------------------------------------

// main shifter and scroller control
always @(hires or shres or scroll or c1 or c3)
	if (shres) // super hires mode
	begin
		shift = 1'b1; // shifter always enabled
		select[3:0] = {scroll[1:0],2'b11}; // scroll in 4 pixel steps
	end
	else if (hires) // hires mode
	begin
		shift = ~c1 ^ c3; // shifter enabled every other clock cycle
		select[3:0] = {scroll[2:0],1'b1}; // scroll in 2 pixel steps
	end
	else // lowres mode
	begin
		shift = ~c1 & ~c3; // shifter enabled once every 4 clock cycles
		select[3:0] = scroll[3:0]; // scroll in 1 pixel steps
	end
			
endmodule		