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
// This is paula
//
// 06-03-2005	-started coding
// 19-03-2005	-added interupt controller and uart
// 04-09-2005	-added blitter finished interrupt
// 19-10-2005	-removed cck (color clock enable) input
//				-removed intb signal
//				-added sof signal
// 23-10-2005	-added dmal signal
//				-added paula part of DMACON
// 21-11-2005	-added floppy controller
// 				-added ADKCON/ADCONR registers
//				-added local horbeam counter
// 27-11-2005	-den is now active low (_den)
//				-some typo's fixed
// 11-12-2005	-disable syncword interrupt
// 13-12-2005	-enable syncword interrupt
// 27-12-2005	-cleaned up code
// 28-12-2005	-added audio module
// 03-01-2006	-added dmas to avoid interference with copper cycles
// 07-01-2006	-added dmas for disk controller
// 06-02-2006	-added user disk control input
// 03-07-2007	-moved interrupt controller and uart to this file to reduce number of sourcefiles
// JB:
// 2008-09-24	- code clean-up
//				- added support for floppy _sel[3:1] signals
// 2008-09-30	- removed user disk control input
// 2008-10-12	- source clean-up
// 2009-01-08	- added audio_dmal, audio_dmas
// 2009-03-08	- removed horbeam counter and sol
//				- added strhor
// 2009-04-05	- code clean-up
// 2009-05-24	- clean-up & renaming
// 2009-07-10	- implementation of intreq[14] (Unreal needs it)
// 2009-11-14 - added 28 MHz clock input for sigma-delta modulator

module Paula
(
	// system bus interface
	input 	clk,		    		//bus clock
  input clk28m,         // 28 MHz system clock
	input 	cck,		    		//colour clock enable
	input 	reset,			   		//reset 
	input 	[8:1] reg_address_in,	//register address inputs
	input	[15:0] data_in,			//bus data in
	output	[15:0] data_out,		//bus data out
	//serial (uart) 
	output 	txd,					//serial port transmitted data
	input 	rxd,			  		//serial port received data
	//interrupts and dma
  input ntsc,         // PAL/NTSC mode
  input sof,          // start of vertical frame
	input	strhor,					//start of video line (latches audio DMA requests)
  input vblint,         // vertical blanking interrupt trigger
	input	int2,					//level 2 interrupt
	input	int3,					//level 3 interrupt
	input	int6,					//level 6 interrupt
	output	[2:0] _ipl,				//m68k interrupt request
	output	[3:0] audio_dmal,		//audio dma data transfer request (to Agnus)
	output	[3:0] audio_dmas,		//audio dma location pointer restart (to Agnus)
	output	disk_dmal,				//disk dma data transfer request (to Agnus)
	output	disk_dmas,				//disk dma special request (to Agnus)
	//disk control signals from cia and user
	input	_step,					//step heads of disk
	input	direc,					//step heads direction
	input	[3:0] _sel,				//disk select 	
	input	side,					//upper/lower disk head
	input	_motor,					//disk motor control
	output	_track0,				//track zero detect
	output	_change,				//disk has been removed from drive
	output	_ready,					//disk is ready
	output	_wprot,					//disk is write-protected
  output  index,          // disk index pulse
	output	disk_led,				//disk activity LED
	//flash drive host controller interface	(SPI)
	input	_scs,					//async. serial data enable
	input	sdi,					//async. serial data input
	output	sdo,					//async. serial data output
	input	sck,					//async. serial data clock
	//audio outputs
	output	left,					//audio bitstream left
	output	right,					//audio bitstream right
	output	[14:0]ldata,			//left DAC data
	output	[14:0]rdata, 			//right DAC data
  // system configuration
	input	[1:0] floppy_drives,	//number of extra floppy drives
  // direct sector read from SD card
	input	direct_scs,				//spi select line for direct transfers from SD card
	input	direct_sdi,				//spi data line for direct transfers from SD card
  // emulated Hard Disk Drive signals
	input	hdd_cmd_req,      // command request
	input	hdd_dat_req,     // data request
	output	[2:0] hdd_addr,     // task file register address
	output	[15:0] hdd_data_out,  // data bus output
	input	[15:0] hdd_data_in,   // data bus input
	output	hdd_wr,         // task file write enable
	output	hdd_status_wr,      // drive status write enable
	output	hdd_data_wr,      // data port write enable
	output	hdd_data_rd,        // data port read enable
  // fifo / track display
	output  [7:0]trackdisp,
	output  [13:0]secdisp,
  output  floppy_fwr,
  output  floppy_frd
);
//--------------------------------------------------------------------------------------

//register names and addresses
parameter DMACON  = 9'h096;	
parameter ADKCON  = 9'h09e;
parameter ADKCONR = 9'h010;	

//local signals
reg		[4:0] dmacon;			//dmacon paula bits 
reg		dmaen;					//master dma enable
reg		[14:0] adkcon;			//audio and disk control register
wire	[15:0] uartdata_out; 	//UART data out
wire	[15:0] intdata_out;  	//interrupt controller data out
wire	[15:0] diskdata_out;		//disk controller data out
wire	[15:0] adkconr;			//ADKCONR register data out
wire	rbfmirror; 				//rbf mirror (from uart to interrupt controller)
wire	rxint;  				//uart rx interrupt request
wire	txint;					//uart tx interrupt request
wire	blckint;				//disk block finished interrupt
wire	syncint;				//disk syncword match interrupt
wire	[3:0] audint;			//audio channels 0,1,2,3 interrupt request
wire	[3:0] audpen;			//audio channels 0,1,2,3 interrupt pending
wire	[3:0] auden;			//audio channels 0,1,2,3 dma enable
wire	dsken; 					//disk dma enable


//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//data_out multiplexer
assign data_out = uartdata_out | intdata_out | diskdata_out | adkconr;

//--------------------------------------------------------------------------------------

//DMACON register write
//NOTE: this register is also present in the Agnus module,
//there DMACONR (read) is implemented
always @(posedge clk)
	if (reset) begin
    dmaen <= 0;
		dmacon <= 5'd0;
	end else if (reg_address_in[8:1]==DMACON[8:1]) begin
		if (data_in[15])
			{dmaen,dmacon[4:0]} <= {dmaen,dmacon[4:0]} | {data_in[9],data_in[4:0]};
		else
			{dmaen,dmacon[4:0]} <= {dmaen,dmacon[4:0]} & (~{data_in[9],data_in[4:0]});	
	end

//assign disk and audio dma enable bits
assign	dsken = dmacon[4] & dmaen;
assign	auden[3] = dmacon[3] & dmaen;
assign	auden[2] = dmacon[2] & dmaen;
assign	auden[1] = dmacon[1] & dmaen;
assign	auden[0] = dmacon[0] & dmaen;

//--------------------------------------------------------------------------------------

//ADKCON register write
always @(posedge clk)
	if (reset)
		adkcon <= 15'd0;
	else if (reg_address_in[8:1]==ADKCON[8:1])
	begin
		if (data_in[15])
			adkcon[14:0] <= adkcon[14:0] | data_in[14:0];
		else
			adkcon[14:0] <= adkcon[14:0] & (~data_in[14:0]);	
	end

//ADKCONR register 
assign adkconr[15:0] = (reg_address_in[8:1]==ADKCONR[8:1]) ? {1'b0,adkcon[14:0]} : 16'h0000;

//--------------------------------------------------------------------------------------

//instantiate uart
uart pu1
(
	.clk(clk),
	.reset(reset),
	.reg_address_in(reg_address_in),
	.data_in(data_in[14:0]),
	.data_out(uartdata_out),
	.rbfmirror(rbfmirror),
	.rxint(rxint),
	.txint(txint),
	.rxd(rxd),
	.txd(txd)
);

//instantiate interrupt controller
intcontroller pi1
(
	.clk(clk),
	.reset(reset),
	.reg_address_in(reg_address_in),
	.data_in(data_in),
	.data_out(intdata_out),
	.rxint(rxint),
	.txint(txint),
  .vblint(vblint),
	.int2(int2),
	.int3(int3),
	.int6(int6),
  .strhor(strhor),
	.blckint(blckint),
	.syncint(syncint),
	.audint(audint),
	.audpen(audpen),
	.rbfmirror(rbfmirror),
	._ipl(_ipl)
);

//instantiate floppy controller / flashdrive host interface
floppy pf1
(
	.clk(clk),
	.reset(reset),
  .ntsc(ntsc),
  .sof(sof),
	.enable(dsken),
	.reg_address_in(reg_address_in),
	.data_in(data_in),
	.data_out(diskdata_out),
	.dmal(disk_dmal),
	.dmas(disk_dmas),
	._step(_step),
	.direc(direc),
	._sel(_sel),
	.side(side),
	._motor(_motor),
	._track0(_track0),
	._change(_change),
	._ready(_ready),
	._wprot(_wprot),
  .index(index),
	.blckint(blckint),
	.syncint(syncint),
	.wordsync(adkcon[10]),
	._scs(_scs),
	.sdi(sdi),
	.sdo(sdo),
	.sck(sck),
	
	.disk_led(disk_led),
	.floppy_drives(floppy_drives),

	.direct_scs(direct_scs),
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
  // fifo / track diaply
	.trackdisp(trackdisp),
	.secdisp(secdisp),
  .floppy_fwr (floppy_fwr),
  .floppy_frd (floppy_frd)
);

//instantiate audio controller
audio ad1
(
	.clk(clk),
  .clk28m(clk28m),
	.cck(cck),
	.reset(reset),
	.strhor(strhor),
	.reg_address_in(reg_address_in),
	.data_in(data_in),
	.dmaena(auden[3:0]),
	.audint(audint[3:0]),
	.audpen(audpen),
	.dmal(audio_dmal),
	.dmas(audio_dmas),
	.left(left),
	.right(right),	
	.ldata(ldata),
	.rdata(rdata)
);

//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// interrupt controller //
module intcontroller
(
	output	inten,
	input 	clk,		    	//bus clock
	input 	reset,			   	//reset 
	input 	[8:1] reg_address_in,	//register address inputs
	input	[15:0] data_in,		//bus data in
	output	[15:0] data_out,		//bus data out
	input	rxint,				//uart receive interrupt
	input	txint,				//uart transmit interrupt
  input vblint,         // start of video frame
	input	int2,				//level 2 interrupt
	input	int3,				//level 3 interrupt
	input	int6,				//level 6 interrupt
	input	blckint,			//disk block finished interrupt
	input	syncint,			//disk syncword match interrupt
	input	[3:0] audint,		//audio channels 0,1,2,3 interrupts
  input strhor,         // start of video line
	output	[3:0] audpen,		//mirror of audio interrupts for audio controller
	output	rbfmirror,			//mirror of serial receive interrupt for uart SERDATR register
	output	reg [2:0] _ipl		//m68k interrupt request
);

//register names and addresses		
parameter INTENAR = 9'h01c;
parameter INTREQR = 9'h01e;
parameter INTENA  = 9'h09a;
parameter INTREQ  = 9'h09c;

//local signals
reg		[14:0] intena;			//int enable write register
reg 	[15:0] intenar;			//int enable read register
reg		[14:0] intreq;			//int request register
reg		[15:0] intreqr;			//int request readback

assign inten = intena[14];

//rbf mirror out
assign rbfmirror = intreq[11];

//audio mirror out
assign audpen[3:0] = intreq[10:7];

//data_out	multiplexer
assign data_out = intenar | intreqr;

//intena register
always @(posedge clk)
	if (reset)
		intena <= 0;
	else if (reg_address_in[8:1]==INTENA[8:1])
	begin
		if (data_in[15])
			intena[14:0] <= intena[14:0] | data_in[14:0];
		else
			intena[14:0] <= intena[14:0] & (~data_in[14:0]);	
	end

//intenar register
always @(reg_address_in or intena)
	if (reg_address_in[8:1]==INTENAR[8:1])
		intenar[15:0] = {1'b0,intena[14:0]};
	else
		intenar = 16'd0;

//intreqr register
always @(reg_address_in or intreq)
	if (reg_address_in[8:1]==INTREQR[8:1])
		intreqr[15:0] = {1'b0,intreq[14:0]};
	else
		intreqr = 16'd0;

// control all interrupts, intterupts are registered at the rising edge of clk
reg [14:0]tmp;

always @(reg_address_in or data_in or intreq)
	//check if we are addressed and some bits must change
	//(generate mask tmp[13:0])
	if (reg_address_in[8:1]==INTREQ[8:1])
	begin
		if (data_in[15])
			tmp[14:0] = intreq[14:0] | data_in[14:0];
		else
			tmp[14:0] = intreq[14:0] & (~data_in[14:0]);	
 	end
	else
		tmp[14:0] = intreq[14:0];
		
always @(posedge clk)
begin
	if (reset)//synchronous reset
		intreq <= 0;
	else 
	begin
		//transmit buffer empty interrupt
		intreq[0] <= tmp[0] | txint;
		//diskblock finished
		intreq[1] <= tmp[1] | blckint;
		//software interrupt
		intreq[2] <= tmp[2];
		//I/O ports and timers
		intreq[3] <= tmp[3] | int2;
		//Copper
		intreq[4] <= tmp[4];
		//start of vertical blank
		intreq[5] <= tmp[5] | vblint;
		//blitter finished
		intreq[6] <= tmp[6] | int3;
		//audio channel 0
		intreq[7] <= tmp[7] | audint[0];
		//audio channel 1
		intreq[8] <= tmp[8] | audint[1];
		//audio channel 2
		intreq[9] <= tmp[9] | audint[2];
		//audio channel 3
		intreq[10] <= tmp[10] | audint[3];
		//serial port receive interrupt
		intreq[11] <= tmp[11] | rxint;
		//disk sync register matches disk data
		intreq[12] <= tmp[12] | syncint;
		//external interrupt
		intreq[13] <= tmp[13] | int6;
		//undocumented interrupt
		intreq[14] <= tmp[14];
	end
end						  

//create m68k interrupt request signals
reg	[14:0]intreqena;
always @(intena or intreq)
begin
	//and int enable and request signals together
	if (intena[14])
		intreqena[14:0] = intreq[14:0] & intena[14:0];
	else
		intreqena[14:0] = 15'b000_0000_0000_0000;	
end

//interrupt priority encoder
always @(posedge clk)
begin
	casez (intreqena[14:0])
		15'b1?????????????? : _ipl <= 1;
		15'b01????????????? : _ipl <= 1;
		15'b001???????????? : _ipl <= 2;
		15'b0001??????????? : _ipl <= 2;
		15'b00001?????????? : _ipl <= 3;
		15'b000001????????? : _ipl <= 3;
		15'b0000001???????? : _ipl <= 3;
		15'b00000001??????? : _ipl <= 3;
		15'b000000001?????? : _ipl <= 4;
		15'b0000000001????? : _ipl <= 4;
		15'b00000000001???? : _ipl <= 4;
		15'b000000000001??? : _ipl <= 5;
		15'b0000000000001?? : _ipl <= 6;
		15'b00000000000001? : _ipl <= 6;
		15'b000000000000001 : _ipl <= 6;
		15'b000000000000000 : _ipl <= 7;
		default:			  _ipl <= 7;
	endcase
end

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//Simplified uart
//NOTES:
//not supported are 9 databits mode and overrun detection for the receiver
//also the behaviour of tsre is not completely according to the amiga hardware
//reference manual, it should work though
module uart
(
	input 	clk,		    	//bus clock
	input 	reset,			   	//reset 
	input 	[8:1] reg_address_in,	//register address inputs
	input	[14:0] data_in,		//bus data in
	output	reg [15:0] data_out,	//bus data out
	input	rbfmirror,			//rbf mirror from interrupt controller
	output 	reg txint,			//transmitter intterrupt
	output 	reg rxint,			//receiver intterupt
	output 	txd,				//serial port transmitted data
	input 	rxd					//serial port received data
);

//register names and addresses
parameter SERDAT  = 9'h030;		
parameter SERDATR = 9'h018;
parameter SERPER  = 9'h032;

//local signal for tx
reg		[14:0] serper;			//period (baud rate) register
reg		[15:0] txdiv;			//transmitter baud rate divider
reg		[10:0] serdat;			//serdat register
reg		[11:0] txshift;			//transmit shifter
reg		[1:0] txstate;			//transmitter state
reg		[1:0] txnextstate;		//next transmitter state
wire	txbaud;					//transmitter baud clock
reg 	txload;					//load transmit shifter
reg		tsre;					//transmit shift register empty
reg		tbe;					//transmit buffer empty

//local signals for rx
reg		[15:0] rxdiv;			//receiver baud rate divider
reg		[9:0] rxshift;			//receiver shift register
reg		[7:0] rxdat;			//received data buffer
reg		[1:0] rxstate;			//receiver state
reg		[1:0] rxnextstate;		//next receiver state
wire	rxbaud;					//receiver baud clock
reg		rxpreset;				//preset receiver baud clock	
reg		lrxd1;					//latched rxd signal
reg		lrxd2;					//latched rxd signal

//serper register
always @(posedge clk)
	if (reg_address_in[8:1]== SERPER[8:1])
		serper[14:0] <= data_in[14:0];		

//tx baudrate generator
always @(posedge clk)
	if (txbaud)
		txdiv[15:0] <= {serper[14:0],1'b1};//serper shifted right because of 7.09MHz clock
	else
		txdiv <= txdiv - 1'b1;
		
assign txbaud = (txdiv==0) ? 1'b1 : 1'b0;

//txd shifter
always @(posedge clk)
	if (reset)
		txshift[11:0] <= 12'b0000_0000_0001;	
	else if (txload && txbaud)
		txshift[11:0] <= {serdat[10:0],1'b0};
	else if (!tsre && txbaud)
		txshift[11:0] <= {1'b0,txshift[11:1]};
		
assign txd = txshift[0];

//generate tsre signal
always @(txshift[11:0])
	if (txshift[11:0]==12'b0000_0000_0001)
		tsre = 1'b1;
	else
		tsre = 1'b0;

//serdat register
always @(posedge clk)
	if (reg_address_in[8:1]==SERDAT[8:1])
		serdat[10:0] <= data_in[10:0];

//transmitter state machine
always @(posedge clk)
	if (reset)
		txstate <= 2'b00;
	else
		txstate <= txnextstate;
		
always @(txstate or tsre or reg_address_in)
begin
	case (txstate)
		2'b00://wait for new data and go to next state if serdat is loaded
			begin
				txint = 0;
				txload = 0;
				tbe = 1; 
				if (reg_address_in[8:1]==SERDAT[8:1])
					txnextstate = 2'b01;
				else
					txnextstate = 2'b00;
			end
		2'b01://wait for shift register to become empty (tsre goes high)
			begin
				txint = 0;
				txload = 0;
				tbe = 0;
				if (tsre)
					txnextstate = 2'b10;
				else
					txnextstate = 2'b01;
			end
		2'b10://wait for shift register to read serdat (tsre goes low)
			begin
				txint = 0;
				txload = 1;
				tbe = 0;
				if (!tsre)
					txnextstate = 2'b11;
				else
					txnextstate = 2'b10;
			end
		2'b11://serdat is now empty again, generate interupt
			begin
				txint = 1;
				txload = 0;
				tbe = 0;
				txnextstate = 2'b00;
			end
	endcase			
end

//rx baud rate generator
always @(posedge clk)
	if (rxpreset)
		rxdiv[15:0] <= {1'b0,serper[14:0]};
	else if (rxbaud)
		rxdiv[15:0] <= {serper[14:0],1'b1};//serper shifted left because of 7.09 MHz clock
	else
		rxdiv <= rxdiv - 1'b1;
		
assign rxbaud = rxdiv==0 ? 1'b1 : 1'b0;

//rxd input synchronizer latch
always @(posedge clk)
begin
	lrxd1 <= rxd;
	lrxd2 <= lrxd1;
end

//receiver shift register
always @(posedge clk)
	if (rxpreset)
		rxshift[9:0] <= 10'b11_1111_1111;
	else if (rxbaud)
		rxshift[9:0] <= {lrxd2,rxshift[9:1]};		

//receiver buffer
always @(posedge clk)
	if (rxint)
		rxdat[7:0] <= rxshift[8:1];

//receiver state machine
always @(posedge clk)
	if (reset)
		rxstate <= 2'b00;
	else
		rxstate <= rxnextstate;
		
always @(rxstate or lrxd2 or rxshift[0])
begin
	case (rxstate)
		2'b00://wait for startbit
			begin
			rxint = 1'b0;
			rxpreset = 1'b1;
			if (!lrxd2)
				rxnextstate = 2'b01;
			else
				rxnextstate = 2'b00;
			end
		2'b01://shift in 10 bits (start, 8 data, stop)
			begin
			rxint = 1'b0;
			rxpreset = 1'b0;
			if (!rxshift[0])
				rxnextstate = 2'b10;
			else
				rxnextstate = 2'b01;
			end
		2'b10,2'b11://new byte has been received, latch byte and request interrupt
			begin
			rxint = 1'b1;
			rxpreset = 1'b0;
			rxnextstate = 2'b00;
			end
	endcase
end	

//serdatr register
always @(reg_address_in or rbfmirror or tbe or tsre or lrxd2 or rxdat)
	if (reg_address_in[8:1]==SERDATR[8:1])
		data_out[15:0] = {1'b0,rbfmirror,tbe,tsre,lrxd2,3'b001,rxdat[7:0]};
	else
		data_out[15:0] = 16'h0000;

endmodule

