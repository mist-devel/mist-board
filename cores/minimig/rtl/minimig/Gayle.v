// Copyright 2008, 2009 by Jakub Bednarski
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
// -- JB --
//
// 2008-10-06	- initial version
// 2008-10-08	- interrupt controller implemented, kickstart boots
// 2008-10-09	- working identify device command implemented (hdtoolbox detects our drive)
//				- read command reads data from hardfile (fixed size and name, only one sector read size supported, workbench sees hardfile partition)
// 2008-10-10	- multiple sector transfer supported: works ok, sequential transfers with direct spi read and 28MHz CPU from 400 to 520 KB/s
//				- arm firmare seekfile function very slow: seeking from start to 20MB takes 144 ms (some software improvements required)
// 2008-10-30	- write support added
// 2008-12-31	- added hdd enable
// 2009-05-24	- clean-up & renaming
// 2009-08-11	- hdd_ena enables Master & Slave drives
// 2009-11-18	- changed sector buffer size
// 2010-04-13	- changed sector buffer size
// 2010-08-10	- improved BSY signal handling

module gayle
(
	input	clk,
	input	reset,
	input	[23:1] address_in,
	input	[15:0] data_in,
	output	[15:0] data_out,
	input	rd,
	input	hwr,
	input	lwr,
	input	sel_ide,			// $DAxxxx
	input	sel_gayle,			// $DExxxx
	output	irq,
	output	nrdy,				// fifo is not ready for reading 
	input	[1:0] hdd_ena,		// enables Master & Slave drives

	output	hdd_cmd_req,
	output	hdd_dat_req,
	input	[2:0] hdd_addr,
	input	[15:0] hdd_data_out,
	output	[15:0] hdd_data_in,
	input	hdd_wr,
	input	hdd_status_wr,
	input	hdd_data_wr,
	input	hdd_data_rd,
  output hd_fwr,
  output hd_frd
);

localparam VCC = 1'b1;
localparam GND = 1'b0;

//0xda2000 Data
//0xda2004 Error | Feature
//0xda2008 SectorCount
//0xda200c SectorNumber
//0xda2010 CylinderLow
//0xda2014 CylinderHigh
//0xda2018 Device/Head
//0xda201c Status | Command
//0xda3018 Control

/*
memory map:

$DA0000 - $DA0FFFF : CS1 16-bit speed
$DA1000 - $DA1FFFF : CS2 16-bit speed
$DA2000 - $DA2FFFF : CS1 8-bit speed
$DA3000 - $DA3FFFF : CS2 8-bit speed
$DA4000 - $DA7FFFF : reserved
$DA8000 - $DA8FFFF : IDE INTREQ state status register (not implemented as scsi.device doesn't use it)
$DA9000 - $DA9FFFF : IDE INTREQ change status register (writing zeros resets selected bits, writing ones doesn't change anything) 
$DAA000 - $DAAFFFF : IDE INTENA register (r/w, only MSB matters)
 

command class:
PI (PIO In)
PO (PIO Out)
ND (No Data)

Status:
#6 - DRDY	- Drive Ready
#7 - BSY	- Busy
#3 - DRQ	- Data Request
#0 - ERR	- Error
INTRQ	- Interrupt Request

*/
 

// address decoding signals
wire 	sel_gayleid;	// Gayle ID register select
wire 	sel_tfr;		// HDD task file registers select
wire 	sel_fifo;		// HDD data port select (FIFO buffer)
wire 	sel_status;		// HDD status register select
wire 	sel_command;	// HDD command register select
wire 	sel_intreq;		// Gayle interrupt request status register select
wire 	sel_intena;		// Gayle interrupt enable register select

// internal registers
reg		intena;			// Gayle IDE interrupt enable bit
reg		intreq;			// Gayle IDE interrupt request bit
reg		busy;			// busy status (command processing state)
reg		pio_in;			// pio in command type is being processed
reg		pio_out;		// pio out command type is being processed
reg		error;			// error status (command processing failed)

reg		dev;			// drive select (Master/Slave)
wire 	bsy;			// busy
wire 	drdy;			// drive ready
wire 	drq;			// data request
wire 	err;			// error
wire 	[7:0] status;	// HDD status

// FIFO control
wire	fifo_reset;
wire	[15:0] fifo_data_in;
wire	[15:0] fifo_data_out;
wire 	fifo_rd;
wire 	fifo_wr;
wire 	fifo_full;
wire 	fifo_empty;
wire	fifo_last;			// last word of a sector is being read

// gayle id reg
reg		[1:0] gayleid_cnt;	// sequence counter
wire	gayleid;			// output data (one bit wide)

// hd leds
assign hd_fwr = fifo_wr;
assign hd_frd = fifo_rd;

// HDD status register
assign status = {bsy,drdy,2'b00,drq,2'b00,err};

// HDD status register bits
assign bsy = busy & ~drq;
assign drdy = ~(bsy|drq);
assign err = error;

// address decoding
assign sel_gayleid = sel_gayle && address_in[15:12]==4'b0001 ? VCC : GND;	//$DE1xxx
assign sel_tfr = sel_ide && address_in[15:14]==2'b00 && !address_in[12] ? VCC : GND;
assign sel_status = rd && sel_tfr && address_in[4:2]==3'b111 ? VCC : GND;
assign sel_command = hwr && sel_tfr && address_in[4:2]==3'b111 ? VCC : GND;
assign sel_fifo = sel_tfr && address_in[4:2]==3'b000 ? VCC : GND;
assign sel_intreq = sel_ide && address_in[15:12]==4'b1001 ? VCC : GND;	//INTREQ
assign sel_intena = sel_ide && address_in[15:12]==4'b1010 ? VCC : GND;	//INTENA

//===============================================================================================//

// task file registers
reg		[7:0] tfr [7:0];
wire	[2:0] tfr_sel;
wire	[7:0] tfr_in;
wire	[7:0] tfr_out;
wire	tfr_we;

reg		[7:0] sector_count;	// sector counter
wire	sector_count_dec;	// decrease sector counter

always @(posedge clk)
	if (hwr && sel_tfr && address_in[4:2] == 3'b010) // sector count register loaded by the host
		sector_count <= data_in[15:8];
	else if (sector_count_dec)
		sector_count <= sector_count - 8'd1;

assign sector_count_dec = pio_in & fifo_last & sel_fifo & rd;
		
// task file register control
assign tfr_we = busy ? hdd_wr : sel_tfr & hwr;
assign tfr_sel = busy ? hdd_addr : address_in[4:2];
assign tfr_in = busy ? hdd_data_out[7:0] : data_in[15:8];

// input multiplexer for SPI host
assign hdd_data_in = tfr_sel==0 ? fifo_data_out : {8'h00,tfr_out};

// task file registers
always @(posedge clk)
	if (tfr_we)
		tfr[tfr_sel] <= tfr_in;
		
assign tfr_out = tfr[tfr_sel];

// master/slave drive select
always @(posedge clk)
	if (reset)
		dev <= 0;
	else if (sel_tfr && address_in[4:2]==6 && hwr)
		dev <= data_in[12];
		
// IDE interrupt enable register
always @(posedge clk)
	if (reset)
		intena <= GND;
	else if (sel_intena && hwr)
		intena <= data_in[15];
			
// gayle id register: reads 1->1->0->1 on MSB
always @(posedge clk)
	if (sel_gayleid)
		if (hwr) // a write resets sequence counter
			gayleid_cnt <= 2'd0;
		else if (rd)
			gayleid_cnt <= gayleid_cnt + 2'd1;

assign gayleid = ~gayleid_cnt[1] | gayleid_cnt[0]; // Gayle ID output data

// status register (write only from SPI host)
// 7 - busy status (write zero to finish command processing: allow host access to task file registers)
// 6
// 5
// 4 - intreq
// 3 - drq enable for pio in (PI) command type
// 2 - drq enable for pio out (PO) command type
// 1
// 0 - error flag (remember about setting error task file register)

// command busy status
always @(posedge clk)
	if (reset)
		busy <= GND;
	else if (hdd_status_wr && hdd_data_out[7] || sector_count_dec && sector_count == 8'h01)	// reset by SPI host (by clearing BSY status bit)
		busy <= GND;
	else if (sel_command)	// set when the CPU writes command register
		busy <= VCC;

// IDE interrupt request register
always @(posedge clk)
	if (reset)
		intreq <= GND;
	else if (busy && hdd_status_wr && hdd_data_out[4] && intena) // set by SPI host
		intreq <= VCC;
	else if (sel_intreq && hwr && !data_in[15]) // cleared by the CPU
		intreq <= GND;

assign irq = (~pio_in | drq) & intreq; // interrupt request line (INT2)

// pio in command type
always @(posedge clk)
	if (reset)
		pio_in <= GND;
	else if (drdy) // reset when processing of the current command ends
		pio_in <= GND;
	else if (busy && hdd_status_wr && hdd_data_out[3])	// set by SPI host 
		pio_in <= VCC;		

// pio out command type
always @(posedge clk)
	if (reset)
		pio_out <= GND;
	else if (busy && hdd_status_wr && hdd_data_out[7]) 	// reset by SPI host when command processing completes
		pio_out <= GND;
	else if (busy && hdd_status_wr && hdd_data_out[2])	// set by SPI host
		pio_out <= VCC;	
		
assign drq = (fifo_full & pio_in) | (~fifo_full & pio_out); // HDD data request status bit

// error status
always @(posedge clk)
	if (reset)
		error <= GND;
	else if (sel_command) // reset by the CPU when command register is written
		error <= GND;
	else if (busy && hdd_status_wr && hdd_data_out[0]) // set by SPI host
		error <= VCC;	
		
assign hdd_cmd_req = bsy; // bsy is set when command register is written, tells the SPI host about new command
assign hdd_dat_req = (fifo_full & pio_out); // the FIFO is full so SPI host may read it

// FIFO in/out multiplexer
assign fifo_reset = reset | sel_command;
assign fifo_data_in = pio_in ? hdd_data_out : data_in;
assign fifo_rd = pio_out ? hdd_data_rd : sel_fifo & rd;
assign fifo_wr = pio_in ? hdd_data_wr : sel_fifo & hwr & lwr;

//sector data buffer (FIFO)
fifo4096x16 SECBUF1
(
	.clk(clk),
	.reset(fifo_reset),
	.data_in(fifo_data_in),
	.data_out(fifo_data_out),
	.rd(fifo_rd),
	.wr(fifo_wr),
	.full(fifo_full),
	.empty(fifo_empty),
	.last(fifo_last)
);

// fifo is not ready for reading

assign nrdy = pio_in & sel_fifo & fifo_empty;

//data_out multiplexer
assign data_out = (sel_fifo && rd ? fifo_data_out : sel_status ? (!dev && hdd_ena[0]) || (dev && hdd_ena[1]) ? {status,8'h00} : 16'h00_00 : sel_tfr && rd ? {tfr_out,8'h00} : 16'h00_00)
			   | (sel_intreq && rd ? {intreq,15'b000_0000_0000_0000} : 16'h00_00)				
			   | (sel_intena && rd ? {intena,15'b000_0000_0000_0000} : 16'h00_00)				
			   | (sel_gayleid && rd ? {gayleid,15'b000_0000_0000_0000} : 16'h00_00);
 
//===============================================================================================//

//===============================================================================================//

endmodule

module fifo4096x16
(
	input 	clk,		    		// bus clock
	input 	reset,			   		// reset 
	input	[15:0] data_in,			// data in
	output	reg [15:0] data_out,	// data out
	input	rd,						// read from fifo
	input	wr,						// write to fifo
	output	full,					// fifo is full
	output	empty,					// fifo is empty
	output	last					// the last word of a sector is being read
);

// local signals and registers
reg 	[15:0] mem [4095:0];		// 16 bit wide fifo memory
reg		[12:0] inptr;				// fifo input pointer
reg		[12:0] outptr;				// fifo output pointer
wire	empty_rd;					// fifo empty flag (set immediately after reading the last word)
reg		empty_wr;					// fifo empty flag (set one clock after writting the empty fifo)

// main fifo memory (implemented using synchronous block ram)
always @(posedge clk)
	if (wr)
		mem[inptr[11:0]] <= data_in;
		
always @(posedge clk)
	data_out <= mem[outptr[11:0]];

// fifo write pointer control
always @(posedge clk)
	if (reset)
		inptr <= 12'd0;
	else if (wr)
		inptr <= inptr + 12'd1;

// fifo read pointer control
always @(posedge clk)
	if (reset)
		outptr <= 0;
	else if (rd)
		outptr <= outptr + 13'd1;

// the empty flag is set immediately after reading the last word from the fifo
assign empty_rd = inptr==outptr ? 1'b1 : 1'b0;

// after writting empty fifo the empty flag is delayed by one clock to handle ram write delay
always @(posedge clk)
	empty_wr <= empty_rd;

assign empty = empty_rd | empty_wr;

// at least 512 bytes are in FIFO 
// this signal is activated when 512th byte is written to the empty fifo
// then it's deactivated when 512th byte is read from the fifo (hysteresis)		
assign full = inptr[12:8]!=outptr[12:8] ? 1'b1 : 1'b0;	

assign last = outptr[7:0] == 8'hFF ? 1'b1 : 1'b0;	

endmodule
