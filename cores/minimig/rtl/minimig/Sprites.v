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
// This is the sprites part of denise 
// It supports all OCS sprite modes.
//
// 12-06-2005	-started coding
//				-first finished version
// 21-06-2005	-changed sprite priority logic and nsprite output
// 02-10-2005	-sprites are now attached if odd,even or both sprites SPRXCTL bit 7 is set
// 17-10-2005	-sprites were displayed one pixel too early, fixed.
// ----------
// JB:
// 2008-07-14	- swapped shifta and shiftb in serialized output (fix for Zool2: copper writes to SPRxDATx registers)
// 2009-01-26	- cleanup
//				- added sprena signal
// 2009-05-24	- clean-up & renaming
// 2010-06-17	- improved OCS sprite attach mode

module sprites
(
	input 	clk,					// bus clock	
	input 	reset,		    		// reset
	input	ecs,					// ECS chipset features
	input	[8:1] reg_address_in,	// register address input
	input	[8:0] hpos,				// horizontal beam counter
	input 	[15:0] data_in, 		// bus data in
	input	sprena,					// sprite enable signal
	output 	[7:0] nsprite,		  	// sprite data valid signals 
	output	reg [3:0] sprdata		// sprite data out
);

//register names and adresses		
parameter	SPRPOSCTLBASE = 9'h140;	//sprite data, position and control register base address

//local signals
wire		selspr0;				// select sprite 0
wire		selspr1;				// select sprite 1
wire		selspr2;				// select sprite 2
wire		selspr3;				// select sprite 3
wire		selspr4;				// select sprite 4
wire		selspr5;				// select sprite 5
wire		selspr6;				// select sprite 6
wire		selspr7;				// select sprite 7

wire		[1:0] sprdat0;			// data sprite 0
wire		[1:0] sprdat1;			// data sprite 1
wire		[1:0] sprdat2;			// data sprite 2
wire		[1:0] sprdat3;			// data sprite 3
wire		[1:0] sprdat4;			// data sprite 4
wire		[1:0] sprdat5;			// data sprite 5
wire		[1:0] sprdat6;			// data sprite 6
wire		[1:0] sprdat7;			// data sprite 7

wire		attach0;				// attach sprite 0,1
wire		attach1;				// attach sprite 0,1
wire		attach2;				// attach sprite 2,3
wire		attach3;				// attach sprite 2,3
wire		attach4;				// attach sprite 4,5
wire		attach5;				// attach sprite 4,5
wire		attach6;				// attach sprite 6,7
wire		attach7;				// attach sprite 6,7

//--------------------------------------------------------------------------------------

// sprite register address decoder
wire	selsprx;

assign selsprx = SPRPOSCTLBASE[8:6]==reg_address_in[8:6] ? 1'b1 : 1'b0; // base address
assign selspr0 = selsprx && reg_address_in[5:3]==3'd0    ? 1'b1 : 1'b0;
assign selspr1 = selsprx && reg_address_in[5:3]==3'd1    ? 1'b1 : 1'b0;
assign selspr2 = selsprx && reg_address_in[5:3]==3'd2    ? 1'b1 : 1'b0;
assign selspr3 = selsprx && reg_address_in[5:3]==3'd3    ? 1'b1 : 1'b0;
assign selspr4 = selsprx && reg_address_in[5:3]==3'd4    ? 1'b1 : 1'b0;
assign selspr5 = selsprx && reg_address_in[5:3]==3'd5    ? 1'b1 : 1'b0;
assign selspr6 = selsprx && reg_address_in[5:3]==3'd6    ? 1'b1 : 1'b0;
assign selspr7 = selsprx && reg_address_in[5:3]==3'd7    ? 1'b1 : 1'b0;

//--------------------------------------------------------------------------------------

// instantiate sprite 0
sprshift sps0
(
	.clk(clk),
	.reset(reset),
	.aen(selspr0),
	.address(reg_address_in[2:1]),
	.hpos(hpos),
	.data_in(data_in),
	.sprdata(sprdat0),
	.attach(attach0)
);

// instantiate sprite 1
sprshift sps1
(
	.clk(clk),
	.reset(reset),
	.aen(selspr1),
	.address(reg_address_in[2:1]),
	.hpos(hpos),
	.data_in(data_in),
	.sprdata(sprdat1),
	.attach(attach1)
);

// instantiate sprite 2
sprshift sps2
(
	.clk(clk),
	.reset(reset),
	.aen(selspr2),
	.address(reg_address_in[2:1]),
	.hpos(hpos),
	.data_in(data_in),
	.sprdata(sprdat2),
	.attach(attach2)
);

// instantiate sprite 3
sprshift sps3
(
	.clk(clk),
	.reset(reset),
	.aen(selspr3),
	.address(reg_address_in[2:1]),
	.hpos(hpos),
	.data_in(data_in),
	.sprdata(sprdat3),
	.attach(attach3)
);

// instantiate sprite 4
sprshift sps4
(
	.clk(clk),
	.reset(reset),
	.aen(selspr4),
	.address(reg_address_in[2:1]),
	.hpos(hpos),
	.data_in(data_in),
	.sprdata(sprdat4),
	.attach(attach4)
);

// instantiate sprite 5
sprshift sps5
(
	.clk(clk),
	.reset(reset),
	.aen(selspr5),
	.address(reg_address_in[2:1]),
	.hpos(hpos),
	.data_in(data_in),
	.sprdata(sprdat5),
	.attach(attach5)
);

// instantiate sprite 6
sprshift sps6
(
	.clk(clk),
	.reset(reset),
	.aen(selspr6),
	.address(reg_address_in[2:1]),
	.hpos(hpos),
	.data_in(data_in),
	.sprdata(sprdat6),
	.attach(attach6)
);

// instantiate sprite 7
sprshift sps7
(
	.clk(clk),
	.reset(reset),
	.aen(selspr7),
	.address(reg_address_in[2:1]),
	.hpos(hpos),
	.data_in(data_in),
	.sprdata(sprdat7),
	.attach(attach7)
);

//--------------------------------------------------------------------------------------

// generate sprite data valid signals
assign nsprite[0] = (sprena && sprdat0[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data
assign nsprite[1] = (sprena && sprdat1[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data
assign nsprite[2] = (sprena && sprdat2[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data
assign nsprite[3] = (sprena && sprdat3[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data
assign nsprite[4] = (sprena && sprdat4[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data
assign nsprite[5] = (sprena && sprdat5[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data
assign nsprite[6] = (sprena && sprdat6[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data
assign nsprite[7] = (sprena && sprdat7[1:0]!=2'b00) ? 1'b1 : 1'b0;//if any non-zero bit -> valid video data

//--------------------------------------------------------------------------------------

// sprite video priority logic and color decoder
always @(attach0 or attach1 or attach2 or attach3 or
		 attach4 or attach5 or attach6 or attach7 or
		 sprdat0 or sprdat1 or sprdat2 or sprdat3 or
		 sprdat4 or sprdat5 or sprdat6 or sprdat7 or
		 nsprite or ecs)
begin
	if (nsprite[1:0]!=2'b00) // sprites 0,1 non transparant ?
	begin
		if (/*ecs && attach0 ||*/ attach1) // sprites are attached -> 15 colors + transparant
			sprdata[3:0] = {sprdat1[1:0],sprdat0[1:0]};
	   	else if (nsprite[0]) // output lowered number sprite
			sprdata[3:0] = {2'b00,sprdat0[1:0]};
	   	else // output higher numbered sprite
			sprdata[3:0] = {2'b00,sprdat1[1:0]};
	end
	else if (nsprite[3:2]!=2'b00) // sprites 2,3 non transparant ?
	begin
		if (/*ecs && attach2 ||*/ attach3) // sprites are attached -> 15 colors + transparant
			sprdata[3:0] = {sprdat3[1:0],sprdat2[1:0]};
	   	else if (nsprite[2]) // output lowered number sprite
			sprdata[3:0] = {2'b01,sprdat2[1:0]};
	   	else // output higher numbered sprite
			sprdata[3:0] = {2'b01,sprdat3[1:0]};
	end
	else if (nsprite[5:4]!=2'b00) // sprites 4,5 non transparant ?
	begin
		if (/*ecs && attach4 ||*/ attach5) // sprites are attached -> 15 colors + transparant
			sprdata[3:0] = {sprdat5[1:0],sprdat4[1:0]};
	   	else if (nsprite[4]) // output lowered number sprite
			sprdata[3:0] = {2'b10,sprdat4[1:0]};
	   	else // output higher numbered sprite
			sprdata[3:0] = {2'b10,sprdat5[1:0]};
	end
	else if (nsprite[7:6]!=2'b00) // sprites 6,7 non transparant ?
	begin
		if (/*ecs && attach6 ||*/ attach7) // sprites are attached -> 15 colors + transparant
			sprdata[3:0] = {sprdat7[1:0],sprdat6[1:0]};
	   	else if (nsprite[6]) // output lowered number sprite
			sprdata[3:0] = {2'b11,sprdat6[1:0]};
	   	else // output higher numbered sprite
			sprdata[3:0] = {2'b11,sprdat7[1:0]};
	end
	else // all sprites transparant
	begin
		sprdata[3:0] = 4'b0000;	
	end	
end

//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// this is the sprite parallel to serial converter
// clk is 7.09379 MHz (low resolution pixel clock)
// the sprdata assign circuitry is constructed differently from the hardware
// as described	in the amiga hardware reference manual
// this is to make sure that the horizontal start position of a sprite
// aligns with the bitplane/playfield start position
module sprshift
(
	input 	clk,					// bus clock	
	input 	reset,		    		// reset
	input	aen,					// address enable
	input	[1:0] address,		   	// register address input
	input	[8:0] hpos,				// horizontal beam counter
	input 	[15:0] data_in, 		// bus data in
	output	[1:0] sprdata,			// serialized sprite data out
	output	reg attach				// sprite is attached
);

// register names and adresses		
parameter POS  = 2'b00;  		
parameter CTL  = 2'b01;  		
parameter DATA = 2'b10;  		
parameter DATB = 2'b11;  		

// local signals
reg		[15:0] datla;		// data register A
reg		[15:0] datlb;		// data register B
reg		[15:0] shifta;		// shift register A
reg		[15:0] shiftb;		// shift register B
reg		[8:0] hstart;		// horizontal start value
reg		armed;				// sprite "armed" signal
reg		load;				// load shift register signal
reg		load_del;

//--------------------------------------------------------------------------------------

// generate armed signal
always @(posedge clk)
	if (reset) // reset disables sprite
		armed <= 0;
	else if (aen && address==CTL) // writing CTL register disables sprite
		armed <= 0;
	else if (aen && address==DATA) // writing data register A arms sprite
		armed <= 1;

//--------------------------------------------------------------------------------------

// generate load signal
always @(posedge clk)
	load <= armed && hpos[8:0]==hstart[8:0] ? 1'b1 : 1'b0;

always @(posedge clk)
	load_del <= load;

//--------------------------------------------------------------------------------------

// POS register
always @(posedge clk)
	if (aen && address==POS)
		hstart[8:1] <= data_in[7:0];

// CTL register
always @(posedge clk)
	if (aen && address==CTL)
		{attach,hstart[0]} <= {data_in[7],data_in[0]};

// data register A
always @(posedge clk)
	if (aen && address==DATA)
		datla[15:0] <= data_in[15:0];

// data register B
always @(posedge clk)
	if (aen && address==DATB)
		datlb[15:0] <= data_in[15:0];

//--------------------------------------------------------------------------------------

// sprite shift register
always @(posedge clk)
	if (load_del) // load new data into shift register
	begin
		shifta[15:0] <= datla[15:0];
		shiftb[15:0] <= datlb[15:0];
	end
	else // shift out data
	begin
		shifta[15:0] <= {shifta[14:0],1'b0};
		shiftb[15:0] <= {shiftb[14:0],1'b0};
	end

// assign serialized output data
assign sprdata[1:0] = {shiftb[15],shifta[15]};

//--------------------------------------------------------------------------------------

endmodule
