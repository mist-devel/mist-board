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
// This is the audio part of Paula
//
// 27-12-2005	- started coding
// 28-12-2005	- done lots of work
// 29-12-2005	- done lots of work
// 01-01-2006	- we are having OK sound in dma mode now
// 02-01-2006	- fixed last state
// 03-01-2006	- added dmas to avoid interference with copper cycles
// 04-01-2006	- experimented with DAC
// 06-01-2006	- experimented some more with DAC and decided to leave it as it is for now
// 07-01-2006	- cleaned up code
// 21-02-2006	- improved audio state machine
// 22-02-2006	- fixed dma interrupt timing, Turrican-3 theme now plays correct!
//
// -- JB --
// 2008-10-12	- code clean-up
// 2008-12-20	- changed DMA slot allocation
// 2009-03-08	- horbeam removed
//				- strhor signal added (cures problems with freezing of some games)
//				- corrupted Agony title song
// 2009-03-17	- audio FSM rewritten to comply more exactly with HRM state diagram, Agony still has problems
// 2009-03-26	- audio dma requests are latched and cleared at the start of every scan line, seemd to cure Agony problem
//				- Forgotten Worlds freezes at game intro screen due to missed audio irq
// 2009-05-24	- clean-up & renaming
// 2009-11-14 - modified audio state machine to be more cycle-exact with its real counterpart
//        - sigma-delta modulator is clocked at 28 MHz
// 2010-06-15 - updated description

// Paula requests data from Agnus using DMAL line (high active state)
// DMAL time slot allocation (relative to first refresh slot referenced as $00):
// $03,$05,$07 - all these slots are active when disk dma is inactive or write operation is in progress
// $04 - at least 3 words to read / at least 1 word  to write (transfer in $08)
// $06 - at least 2 words to read / at least 2 words to write (transfer in $0A)
// $08 - at least 1 word  to read / at least 3 words to write (transfer in $0C)
// $09 - audio channel #0 location pointer reload request (active with data request) 
// $0A - audio channle #0 dma data request (data transfered in slot $0E)
// $0B - audio channel #1 location pointer reload request (active with data request) 
// $0C - audio channle #1 dma data request (data transfered in slot $10)
// $0D - audio channel #2 location pointer reload request (active with data request) 
// $0E - audio channle #2 dma data request (data transfered in slot $12)
// $0F - audio channel #3 location pointer reload request (active with data request) 
// $10 - audio channle #3 dma data request (data transfered in slot $14)
// minimum sampling period for audio channels in CCKs (no length reload)
// #0 : 121 (120) 
// #1 : 122 (121)
// #2 : 123 (122)
// #3 : 124 (123)

// SB:
// 2011-01-18 - fixed sound output, no more high pitch noise at game Gods

// RK:
// 2012-11-11 - two-stage sigma-delta modulator added
// 2013-02-10 - two stage sigma-delta updated:
//  - used AMR's silence fix
//  - added interpolator at sigma-delta input
//  - all bits of the x3/4 input signal are used, dithering removed
//  - two LFSR PRNGs are combined and high-pass filtered for a HP triangular PDF noise
//  - random noise is applied directly in front of the quantizer, which helps randomize the output stream
//  - some noise shaping (filtering) added to the error feedback signal


module audio
(
	input 	clk,		    		//bus clock
  input clk28m,
	input 	cck,		    		//colour clock enable
	input 	reset,			   		//reset 
	input	strhor,					//horizontal strobe
	input 	[8:1] reg_address_in,	//register address input
	input	[15:0] data_in,			//bus data in
	input	[3:0] dmaena,			//audio dma register input
	output	[3:0] audint,			//audio interrupt request
	input	[3:0] audpen,			//audio interrupt pending
	output	reg [3:0] dmal,			//dma request 
	output	reg [3:0] dmas,			//dma special 
	output	left,					//audio bitstream out left
	output	right,					//audio bitstream out right
	output	[14:0]ldata,		//left DAC data
	output	[14:0]rdata 		//right DAC data
);

//register names and addresses
parameter	AUD0BASE = 9'h0a0;
parameter	AUD1BASE = 9'h0b0;
parameter	AUD2BASE = 9'h0c0;
parameter	AUD3BASE = 9'h0d0;

//local signals 
wire	[3:0] aen;			//address enable 0-3
wire	[3:0] dmareq;		//dma request 0-3
wire	[3:0] dmaspc;		//dma restart 0-3
wire	[7:0] sample0;		//channel 0 audio sample 
wire	[7:0] sample1;		//channel 1 audio sample 
wire	[7:0] sample2;		//channel 2 audio sample 
wire	[7:0] sample3;		//channel 3 audio sample 
wire	[6:0] vol0;			//channel 0 volume 
wire	[6:0] vol1;			//channel 1 volume 
wire	[6:0] vol2;			//channel 2 volume 
wire	[6:0] vol3;			//channel 3 volume 
wire  [15:0] ldatasum;
wire  [15:0] rdatasum;

//--------------------------------------------------------------------------------------

//address decoder
assign aen[0] = (reg_address_in[8:4]==AUD0BASE[8:4]) ? 1'b1 : 1'b0;
assign aen[1] = (reg_address_in[8:4]==AUD1BASE[8:4]) ? 1'b1 : 1'b0;
assign aen[2] = (reg_address_in[8:4]==AUD2BASE[8:4]) ? 1'b1 : 1'b0;
assign aen[3] = (reg_address_in[8:4]==AUD3BASE[8:4]) ? 1'b1 : 1'b0;

//--------------------------------------------------------------------------------------

//DMA slot allocation is managed by Agnus 
//#0 : 0E
//#1 : 10
//#2 : 12
//#3 : 14

always @(posedge clk)
	if (strhor)
	begin
		dmal <= (dmareq);
		dmas <= (dmaspc);
	end
		
//--------------------------------------------------------------------------------------

//instantiate audio channel 0
audiochannel ach0
(
	.clk(clk),
	.reset(reset),
	.cck(cck),
	.aen(aen[0]),
	.dmaena(dmaena[0]),
	.reg_address_in(reg_address_in[3:1]),
	.data(data_in),
	.volume(vol0),
	.sample(sample0),
	.intreq(audint[0]),
	.intpen(audpen[0]),
	.dmareq(dmareq[0]),
	.dmas(dmaspc[0]),
	.strhor(strhor)
);

//instantiate audio channel 1
audiochannel ach1
(
	.clk(clk),
	.reset(reset),
	.cck(cck),
	.aen(aen[1]),
	.dmaena(dmaena[1]),
	.reg_address_in(reg_address_in[3:1]),
	.data(data_in),
	.volume(vol1),
	.sample(sample1),
	.intreq(audint[1]),
	.intpen(audpen[1]),
	.dmareq(dmareq[1]),
	.dmas(dmaspc[1]),
	.strhor(strhor)
);

//instantiate audio channel 2
audiochannel ach2 
(	
	.clk(clk),
	.reset(reset),
	.cck(cck),
	.aen(aen[2]),
	.dmaena(dmaena[2]),
	.reg_address_in(reg_address_in[3:1]),
	.data(data_in),
	.volume(vol2),
	.sample(sample2),
	.intreq(audint[2]),
	.intpen(audpen[2]),
	.dmareq(dmareq[2]),
	.dmas(dmaspc[2]),
	.strhor(strhor)	
);

//instantiate audio channel 3
audiochannel ach3
(		
	.clk(clk),
	.reset(reset),
	.cck(cck),
	.aen(aen[3]),
	.dmaena(dmaena[3]),
	.reg_address_in(reg_address_in[3:1]),
	.data(data_in),
	.volume(vol3),
	.sample(sample3),
	.intreq(audint[3]),
	.intpen(audpen[3]),
	.dmareq(dmareq[3]),
	.dmas(dmaspc[3]),
	.strhor(strhor)
);


//--------------------------------------------------------------------------------------

// instantiate mixer
audiomixer mix (
  .clk      (clk28m),
  .sample0  (sample0),
  .sample1  (sample1),
  .sample2  (sample2),
  .sample3  (sample3),
  .vol0     (vol0),
  .vol1     (vol1),
  .vol2     (vol2),
  .vol3     (vol3),
  .ldatasum (ldata),
  .rdatasum (rdata)
);


//--------------------------------------------------------------------------------------

//instantiate sigma/delta modulator
sigmadelta dac
(
  .clk(clk),
  .ldatasum(ldata),
  .rdatasum(rdata),
  .left(left),
  .right(right)
);


//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------




//--------------------------------------------------------------------------------------

// stereo volume control
// channel 1&2 --> left
// channel 0&3 --> right
module audiomixer (
	input 	clk,				//bus clock
	input	[7:0] sample0,		//sample 0 input
	input	[7:0] sample1,		//sample 1 input
	input	[7:0] sample2,		//sample 2 input
	input	[7:0] sample3,		//sample 3 input
	input	[6:0] vol0,			//volume 0 input
	input	[6:0] vol1,			//volume 1 input
	input	[6:0] vol2,			//volume 2 input
	input	[6:0] vol3,			//volume 3 input
	output reg	[14:0]ldatasum,		//left DAC data
	output reg	[14:0]rdatasum		//right DAC data
);

// volume control
wire [14-1:0] msample0, msample1, msample2, msample3;
// when volume MSB is set, volume is always maximum
svmul sv0
(
	.sample(sample0),
	.volume({	(vol0[6] | vol0[5]),
				    (vol0[6] | vol0[4]),
				    (vol0[6] | vol0[3]),
				    (vol0[6] | vol0[2]),
				    (vol0[6] | vol0[1]),
				    (vol0[6] | vol0[0]) }),
	.out(msample0)
);

svmul sv1
(
	.sample(sample1),
	.volume({	(vol1[6] | vol1[5]),
				    (vol1[6] | vol1[4]),
				    (vol1[6] | vol1[3]),
				    (vol1[6] | vol1[2]),
				    (vol1[6] | vol1[1]),
				    (vol1[6] | vol1[0]) }),
	.out(msample1)
);

svmul sv2
(
	.sample(sample2),
	.volume({	(vol2[6] | vol2[5]),
				    (vol2[6] | vol2[4]),
				    (vol2[6] | vol2[3]),
				    (vol2[6] | vol2[2]),
				    (vol2[6] | vol2[1]),
				    (vol2[6] | vol2[0]) }),
	.out(msample2)
);

svmul sv3
(
	.sample(sample3),
	.volume({	(vol3[6] | vol3[5]),
				    (vol3[6] | vol3[4]),
				    (vol3[6] | vol3[3]),
				    (vol3[6] | vol3[2]),
				    (vol3[6] | vol3[1]),
				    (vol3[6] | vol3[0]) }),
	.out(msample3)
);


// channel muxing
always @ (posedge clk) begin
  ldatasum <= #1 {msample1[13], msample1} + {msample2[13], msample2};
  rdatasum <= #1 {msample0[13], msample0} + {msample3[13], msample3};
end

endmodule


//--------------------------------------------------------------------------------------

// audio data processing
// stereo sigma/delta bitstream modulator
module sigmadelta
(
	input 	clk,				//bus clock
	input	[14:0] ldatasum,			// left channel data
	input	[14:0] rdatasum,			// right channel data
	output	reg left=0,				//left bitstream output
	output	reg right=0				//right bitsteam output
);

//--------------------------------------------------------------------------------------

// local signals
localparam DW = 15;
localparam CW = 2;
localparam RW  = 4;
localparam A1W = 2;
localparam A2W = 5;

wire [DW+2+0  -1:0] sd_l_er0, sd_r_er0;
reg  [DW+2+0  -1:0] sd_l_er0_prev=0, sd_r_er0_prev=0;
wire [DW+A1W+2-1:0] sd_l_aca1,  sd_r_aca1;
wire [DW+A2W+2-1:0] sd_l_aca2,  sd_r_aca2;
reg  [DW+A1W+2-1:0] sd_l_ac1=0, sd_r_ac1=0;
reg  [DW+A2W+2-1:0] sd_l_ac2=0, sd_r_ac2=0;
wire [DW+A2W+3-1:0] sd_l_quant, sd_r_quant;

// LPF noise LFSR
reg [24-1:0] seed1 = 24'h654321;
reg [19-1:0] seed2 = 19'h12345;
reg [24-1:0] seed_sum=0, seed_prev=0, seed_out=0;
always @ (posedge clk) begin
  if (&seed1)
    seed1 <= #1 24'h654321;
  else
    seed1 <= #1 {seed1[22:0], ~(seed1[23] ^ seed1[22] ^ seed1[21] ^ seed1[16])};
end
always @ (posedge clk) begin
  if (&seed2)
    seed2 <= #1 19'h12345;
  else
    seed2 <= #1 {seed2[17:0], ~(seed2[18] ^ seed2[17] ^ seed2[16] ^ seed2[13] ^ seed2[0])};
end
always @ (posedge clk) begin
  seed_sum  <= #1 seed1 + {5'b0, seed2};
  seed_prev <= #1 seed_sum;
  seed_out  <= #1 seed_sum - seed_prev;
end

// linear interpolate
localparam ID=4; // counter size, also 2^ID = interpolation rate
reg  [ID+0-1:0] int_cnt = 0;
always @ (posedge clk) int_cnt <= #1 int_cnt + 'd1;

reg  [DW+0-1:0] ldata_cur=0, ldata_prev=0;
reg  [DW+0-1:0] rdata_cur=0, rdata_prev=0;
wire [DW+1-1:0] ldata_step, rdata_step;
reg  [DW+ID-1:0] ldata_int=0, rdata_int=0;
wire [DW+0-1:0] ldata_int_out, rdata_int_out;
assign ldata_step = {ldata_cur[DW-1], ldata_cur} - {ldata_prev[DW-1], ldata_prev}; // signed subtract
assign rdata_step = {rdata_cur[DW-1], rdata_cur} - {rdata_prev[DW-1], rdata_prev}; // signed subtract
always @ (posedge clk) begin
  if (~|int_cnt) begin
    ldata_prev <= #1 ldata_cur;
    ldata_cur  <= #1 ldatasum; //{~ldatasum[DW-1], ldatasum[DW-2:0]}; // convert to offset binary, samples no longer signed!
    rdata_prev <= #1 rdata_cur;
    rdata_cur  <= #1 rdatasum; //{~rdatasum[DW-1], rdatasum[DW-2:0]}; // convert to offset binary, samples no longer signed!
    ldata_int  <= #1 {ldata_cur[DW-1], ldata_cur, {ID{1'b0}}};
    rdata_int  <= #1 {rdata_cur[DW-1], rdata_cur, {ID{1'b0}}};
  end else begin
    ldata_int  <= #1 ldata_int + {{ID{ldata_step[DW+1-1]}}, ldata_step};
    rdata_int  <= #1 rdata_int + {{ID{rdata_step[DW+1-1]}}, rdata_step};
  end
end
assign ldata_int_out = ldata_int[DW+ID-1:ID];
assign rdata_int_out = rdata_int[DW+ID-1:ID];

// input gain x3
wire [DW+2-1:0] ldata_gain, rdata_gain;
assign ldata_gain = {ldata_int_out[DW-1], ldata_int_out, 1'b0} + {{(2){ldata_int_out[DW-1]}}, ldata_int_out};
assign rdata_gain = {rdata_int_out[DW-1], rdata_int_out, 1'b0} + {{(2){rdata_int_out[DW-1]}}, rdata_int_out};

/*
// random dither to 15 bits
reg [DW-1:0] ldata=0, rdata=0;
always @ (posedge clk) begin
  ldata <= #1 ldata_gain[DW+2-1:2] + ( (~(&ldata_gain[DW+2-1-1:2]) && (ldata_gain[1:0] > seed_out[1:0])) ? 15'd1 : 15'd0 );
  rdata <= #1 rdata_gain[DW+2-1:2] + ( (~(&ldata_gain[DW+2-1-1:2]) && (ldata_gain[1:0] > seed_out[1:0])) ? 15'd1 : 15'd0 );
end
*/

// accumulator adders
assign sd_l_aca1 = {{(A1W){ldata_gain[DW+2-1]}}, ldata_gain} - {{(A1W){sd_l_er0[DW+2-1]}}, sd_l_er0} + sd_l_ac1;
assign sd_r_aca1 = {{(A1W){rdata_gain[DW+2-1]}}, rdata_gain} - {{(A1W){sd_r_er0[DW+2-1]}}, sd_r_er0} + sd_r_ac1;

assign sd_l_aca2 = {{(A2W-A1W){sd_l_aca1[DW+A1W+2-1]}}, sd_l_aca1} - {{(A2W){sd_l_er0[DW+2-1]}}, sd_l_er0} - {{(A2W+1){sd_l_er0_prev[DW+2-1]}}, sd_l_er0_prev[DW+2-1:1]} + sd_l_ac2;
assign sd_r_aca2 = {{(A2W-A1W){sd_r_aca1[DW+A1W+2-1]}}, sd_r_aca1} - {{(A2W){sd_r_er0[DW+2-1]}}, sd_r_er0} - {{(A2W+1){sd_r_er0_prev[DW+2-1]}}, sd_r_er0_prev[DW+2-1:1]} + sd_r_ac2;

// accumulators
always @ (posedge clk) begin
  sd_l_ac1 <= #1 sd_l_aca1;
  sd_r_ac1 <= #1 sd_r_aca1;
  sd_l_ac2 <= #1 sd_l_aca2;
  sd_r_ac2 <= #1 sd_r_aca2;
end

// value for quantizaton
assign sd_l_quant = {sd_l_ac2[DW+A2W+2-1], sd_l_ac2} + {{(DW+A2W+3-RW){seed_out[RW-1]}}, seed_out[RW-1:0]};
assign sd_r_quant = {sd_r_ac2[DW+A2W+2-1], sd_r_ac2} + {{(DW+A2W+3-RW){seed_out[RW-1]}}, seed_out[RW-1:0]};

// error feedback
assign sd_l_er0 = sd_l_quant[DW+A2W+3-1] ? {1'b1, {(DW+2-1){1'b0}}} : {1'b0, {(DW+2-1){1'b1}}};
assign sd_r_er0 = sd_r_quant[DW+A2W+3-1] ? {1'b1, {(DW+2-1){1'b0}}} : {1'b0, {(DW+2-1){1'b1}}};
always @ (posedge clk) begin
  sd_l_er0_prev <= #1 (&sd_l_er0) ? sd_l_er0 : sd_l_er0+1;
  sd_r_er0_prev <= #1 (&sd_r_er0) ? sd_r_er0 : sd_r_er0+1;
end

// output
always @ (posedge clk) begin
  left  <= #1 (~|ldata_gain) ? ~left  : ~sd_l_er0[DW+2-1];
  right <= #1 (~|rdata_gain) ? ~right : ~sd_r_er0[DW+2-1];
end

endmodule


//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//this module multiplies a signed 8 bit sample with an unsigned 6 bit volume setting
//it produces a 14bit signed result
module svmul
(
	input 	[7:0] sample,		//signed sample input
	input	[5:0] volume,		//unsigned volume input
	output	[13:0] out			//signed product out
);

wire	[13:0] sesample;   		//sign extended sample
wire	[13:0] sevolume;		//sign extended volume

//sign extend input parameters
assign 	sesample[13:0] = {{6{sample[7]}},sample[7:0]};
assign	sevolume[13:0] = {8'b00000000,volume[5:0]};

//multiply, synthesizer should infer multiplier here
assign out[13:0] = {sesample[13:0] * sevolume[13:0]};

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//This module handles a single amiga audio channel. attached modes are not supported
module audiochannel
(
	input 	clk,					//bus clock	
	input 	reset,		    		//reset
	input	cck,					//colour clock enable
	input	aen,					//address enable
	input	dmaena,					//dma enable
	input	[3:1] reg_address_in,		//register address input
	input 	[15:0] data, 			//bus data input
	output	[6:0] volume,			//channel volume output
	output	[7:0] sample,			//channel sample output
	output	intreq,					//interrupt request
	input	intpen,					//interrupt pending input
	output	reg dmareq,				//dma request
	output	reg dmas,				//dma special (restart)
	input	strhor					//horizontal strobe
);

//register names and addresses
parameter	AUDLEN = 4'h4;
parameter	AUDPER = 4'h6;
parameter	AUDVOL = 4'h8;
parameter	AUDDAT = 4'ha;

//local signals
reg		[15:0] audlen;			//audio length register
reg		[15:0] audper;			//audio period register
reg		[6:0] audvol;			//audio volume register
reg		[15:0] auddat;			//audio data register

reg		[15:0] datbuf;			//audio data buffer
reg		[2:0] audio_state;		//audio current state
reg		[2:0] audio_next;	 	//audio next state

wire	datwrite;				//data register is written
reg		volcntrld;				//not used

reg		pbufld1;				//load output sample from sample buffer

reg		[15:0] percnt;			//audio period counter
reg		percount;				//decrease period counter
reg		percntrld;				//reload period counter
wire	perfin;					//period counter expired

reg		[15:0] lencnt;			//audio length counter
reg		lencount;				//decrease length counter
reg		lencntrld;				//reload length counter
wire	lenfin;					//length counter expired

reg 	AUDxDAT;				//audio data buffer was written
wire	AUDxON;					//audio DMA channel is enabled
reg		AUDxDR;					//audio DMA request
reg		AUDxIR;					//audio interrupt request
wire	AUDxIP;					//audio interrupt is pending

reg		intreq2_set;
reg		intreq2_clr;
reg		intreq2;				//buffered interrupt request

reg		dmasen;					//pointer register reloading request
reg		penhi;					//enable high byte of sample buffer

reg silence;  // AMR: disable audio if repeat length is 1
reg silence_d;  // AMR: disable audio if repeat length is 1
reg dmaena_d;

//--------------------------------------------------------------------------------------
 
//length register bus write
always @(posedge clk)
	if (reset)
		audlen[15:0] <= 16'h00_00;
	else if (aen && (reg_address_in[3:1]==AUDLEN[3:1]))
		audlen[15:0] <= data[15:0];

//period register bus write
always @(posedge clk)
	if (reset)
		audper[15:0] <= 16'h00_00;
	else if (aen && (reg_address_in[3:1]==AUDPER[3:1]))
		audper[15:0] <= data[15:0];

//volume register bus write
always @(posedge clk)
	if (reset)
		audvol[6:0] <= 7'b000_0000;
	else if (aen && (reg_address_in[3:1]==AUDVOL[3:1]))
		audvol[6:0] <= data[6:0];

//data register strobe
assign datwrite = (aen && (reg_address_in[3:1]==AUDDAT[3:1])) ? 1'b1 : 1'b0;

//data register bus write
always @(posedge clk)
	if (reset)
		auddat[15:0] <= 16'h00_00;
	else if (datwrite)
		auddat[15:0] <= data[15:0];

always @(posedge clk)
	if (datwrite)
		AUDxDAT <= 1'b1;
	else if (cck)
		AUDxDAT <= 1'b0;
	
//--------------------------------------------------------------------------------------

assign	AUDxON = dmaena;	//dma enable

assign	AUDxIP = intpen;	//audio interrupt pending

assign intreq = AUDxIR;		//audio interrupt request
	
//--------------------------------------------------------------------------------------

//period counter 
always @(posedge clk)
	if (percntrld && cck)//load period counter from audio period register
		percnt[15:0] <= audper[15:0];
	else if (percount && cck)//period counter count down
		percnt[15:0] <= percnt[15:0] - 16'd1;
		
assign perfin = (percnt[15:0]==1 && cck) ? 1'b1 : 1'b0;

//length counter 
always @(posedge clk)
  begin
    if (lencntrld && cck)//load length counter from audio length register
    begin
      lencnt[15:0] <= (audlen[15:0]);
      silence<=1'b0;
      if(audlen==1 || audlen==0)
        silence<=1'b1;
    end
    else if (lencount && cck)//length counter count down
      lencnt[15:0] <= (lencnt[15:0] - 1);

    // Silence fix
    dmaena_d<=dmaena;
    if(dmaena_d==1'b1 && dmaena==1'b0)
    begin
      silence_d<=1'b1; // Prevent next write from unsilencing the channel.
      silence<=1'b1;
    end
    if(AUDxDAT && cck)  // Unsilence the channel if the CPU writes to AUDxDAT
      if(silence_d)
        silence_d<=1'b0;
      else
        silence<=1'b0;
      
  end
	
assign lenfin = (lencnt[15:0]==1 && cck) ? 1'b1 : 1'b0;

//--------------------------------------------------------------------------------------

//audio buffer
always @(posedge clk)
	if (reset)
		datbuf[15:0] <= 16'h00_00;
	else if (pbufld1 && cck)
		datbuf[15:0] <= auddat[15:0];

//assign sample[7:0] = penhi ? datbuf[15:8] : datbuf[7:0];
assign sample[7:0] = silence ? 8'b0 : (penhi ? datbuf[15:8] : datbuf[7:0]);

//volume output
assign volume[6:0] = audvol[6:0];

//--------------------------------------------------------------------------------------

//dma request logic
always @(posedge clk)
begin
	if (reset)
	begin
		dmareq <= 1'b0;
		dmas <= 1'b0;
	end
	else if (AUDxDR && cck)
	begin
		dmareq <= 1'b1;
		dmas <= dmasen | lenfin;
	end
	else if (strhor) //dma request are cleared when transfered to Agnus
	begin
		dmareq <= 1'b0;
		dmas <= 1'b0;
	end
end

//buffered interrupt request
always @(posedge clk)
	if (cck)
		if (intreq2_set)
			intreq2 <= 1'b1;
		else if (intreq2_clr)
			intreq2 <= 1'b0;
	
//audio states
parameter AUDIO_STATE_0 = 3'b000;
parameter AUDIO_STATE_1 = 3'b001;
parameter AUDIO_STATE_2 = 3'b011;
parameter AUDIO_STATE_3 = 3'b010;
parameter AUDIO_STATE_4 = 3'b110;

//audio channel state machine
always @(posedge clk)
begin
	if (reset)
		audio_state <= AUDIO_STATE_0;
	else if (cck)
		audio_state <= audio_next;
end

//transition function
always @(audio_state or AUDxON or AUDxDAT or AUDxIP or lenfin or perfin or intreq2)
begin
	case (audio_state)
	
		AUDIO_STATE_0: //audio FSM idle state
		begin
			intreq2_clr = 1'b1;
			intreq2_set = 1'b0;
			lencount = 1'b0;
			penhi = 1'b0;
			percount = 1'b0;
			percntrld = 1'b1;
						
			if (AUDxON) //start of DMA driven audio playback
			begin
				audio_next = AUDIO_STATE_1;
				AUDxDR = 1'b1;
				AUDxIR = 1'b0;
				dmasen = 1'b1;
				lencntrld = 1'b1;
				pbufld1 = 1'b0;
				volcntrld = 1'b0;	
			end
			else if (AUDxDAT && !AUDxON && !AUDxIP)	//CPU driven audio playback
			begin
				audio_next = AUDIO_STATE_3;
				AUDxDR = 1'b0;				
				AUDxIR = 1'b1;
				dmasen = 1'b0;
				lencntrld = 1'b0;
				pbufld1 = 1'b1;
				volcntrld = 1'b1;
			end
			else
			begin
				audio_next = AUDIO_STATE_0;
				AUDxDR = 1'b0;				
				AUDxIR = 1'b0;
				dmasen = 1'b0;
				lencntrld = 1'b0;
				pbufld1 = 1'b0;
				volcntrld = 1'b0;	
			end
		end

		AUDIO_STATE_1: //audio DMA has been enabled
		begin
			dmasen = 1'b0;
			intreq2_clr = 1'b1;
			intreq2_set = 1'b0;
			lencntrld = 1'b0;
			penhi = 1'b0;
			percount = 1'b0;
			
			if (AUDxON && AUDxDAT) //requested data has arrived
			begin
				audio_next = AUDIO_STATE_2;
				AUDxDR = 1'b1;
				AUDxIR = 1'b1;
				lencount = ~lenfin;
        pbufld1 = 1'b0;  //first data received, discard it since first data access is used to reload pointer   
        percntrld = 1'b0;        
        volcntrld = 1'b0;
      end
      else if (!AUDxON) //audio DMA has been switched off so go to IDLE state
      begin
        audio_next = AUDIO_STATE_0;
        AUDxDR = 1'b0;
        AUDxIR = 1'b0;
        lencount = 1'b0;
        pbufld1 = 1'b0;
        percntrld = 1'b0; 
        volcntrld = 1'b0;
      end
      else
      begin
        audio_next = AUDIO_STATE_1;
        AUDxDR = 1'b0;
        AUDxIR = 1'b0;
        lencount = 1'b0;
        pbufld1 = 1'b0;        
        percntrld = 1'b0;
        volcntrld = 1'b0;
      end
    end

    AUDIO_STATE_2: //audio DMA has been enabled
    begin
      dmasen = 1'b0;
      intreq2_clr = 1'b1;
      intreq2_set = 1'b0;
      lencntrld = 1'b0;
      penhi = 1'b0;
      percount = 1'b0;
      
      if (AUDxON && AUDxDAT) //requested data has arrived
      begin
        audio_next = AUDIO_STATE_3;
        AUDxDR = 1'b1;
        AUDxIR = 1'b0;
        lencount = ~lenfin;
				pbufld1 = 1'b1;	//new data has been just received so put it in the output buffer		
				percntrld = 1'b1; 				
				volcntrld = 1'b1;
			end
			else if (!AUDxON) //audio DMA has been switched off so go to IDLE state
			begin
				audio_next = AUDIO_STATE_0;
				AUDxDR = 1'b0;
				AUDxIR = 1'b0;
				lencount = 1'b0;
				pbufld1 = 1'b0;
				percntrld = 1'b0; 
				volcntrld = 1'b0;
			end
			else
			begin
				audio_next = AUDIO_STATE_2;
				AUDxDR = 1'b0;
				AUDxIR = 1'b0;
				lencount = 1'b0;
				pbufld1 = 1'b0;				
				percntrld = 1'b0;
				volcntrld = 1'b0;
			end
		end

		AUDIO_STATE_3: //first sample is being output
		begin
			AUDxDR = 1'b0;
			AUDxIR = 1'b0;
			dmasen = 1'b0;
			intreq2_clr = 1'b0;
			intreq2_set = lenfin & AUDxON & AUDxDAT;
			lencount = ~lenfin & AUDxON & AUDxDAT;
			lencntrld = lenfin & AUDxON & AUDxDAT;
			pbufld1 = 1'b0;
			penhi = 1'b1;
			volcntrld = 1'b0;
		
			if (perfin) //if period counter expired output other sample from buffer
			begin
				audio_next = AUDIO_STATE_4;
				percount = 1'b0;
				percntrld = 1'b1;
			end
			else
			begin
				audio_next = AUDIO_STATE_3;
				percount = 1'b1;
				percntrld = 1'b0;
			end
		end

		AUDIO_STATE_4: //second sample is being output
		begin
			dmasen = 1'b0;
			intreq2_set = lenfin & AUDxON & AUDxDAT;
			lencount = ~lenfin & AUDxON & AUDxDAT;
			lencntrld = lenfin & AUDxON & AUDxDAT;
			penhi = 1'b0;
			volcntrld = 1'b0;
			
			if (perfin && (AUDxON || !AUDxIP)) //period counter expired and audio DMA active
			begin
				audio_next = AUDIO_STATE_3;
				AUDxDR = AUDxON;
				AUDxIR = (intreq2 & AUDxON) | ~AUDxON;
				intreq2_clr = intreq2;
				pbufld1 = 1'b1;
				percount = 1'b0;
				percntrld = 1'b1;
			end
			else if (perfin && !AUDxON && AUDxIP) //period counter expired and audio DMA inactive
			begin
				audio_next = AUDIO_STATE_0;
				AUDxDR = 1'b0;
				AUDxIR = 1'b0;
				intreq2_clr = 1'b0;
				pbufld1 = 1'b0;
				percount = 1'b0;
				percntrld = 1'b0;
			end
			else
			begin
				audio_next = AUDIO_STATE_4;
				AUDxDR = 1'b0;
				AUDxIR = 1'b0;
				intreq2_clr = 1'b0;
				pbufld1 = 1'b0;
				percount = 1'b1;
				percntrld = 1'b0;
			end
		end
		
		default:
		begin
			audio_next = AUDIO_STATE_0;
			AUDxDR = 1'b0;
			AUDxIR = 1'b0;
			dmasen = 1'b0;
			intreq2_clr = 1'b0;
			intreq2_set = 1'b0;
			lencntrld = 1'b0;
			lencount = 1'b0;
			pbufld1 = 1'b0;
			penhi = 1'b0;
			percount = 1'b0;
			percntrld = 1'b0;
			volcntrld = 1'b0;	
		end		
		
	endcase
end


//--------------------------------------------------------------------------------------

endmodule
