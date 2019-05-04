`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//  Copyright 2013-2016 Istvan Hegedus
//
//  FPGATED is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  FPGATED is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//
// 
// Create Date:    12:02:05 10/24/2014 
// Design Name: 	 Commodore 16 
// Module Name:    C16.v
// Project Name: 	 FPGATED
//
// Description: 	
//	This module provides the top level framework for FPGATED. It implements a Commodore 16 computer without expansion port.
// It is written for Papilio FPGATED wing 1.x but can be easily modified for any other platforms.
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module C16 (
	input wire CLK28,
	input wire RESET,
	input wire WAIT,
	
	output wire HSYNC,
	output wire VSYNC,
	output wire CSYNC,
	output wire [3:0] RED,
	output wire [3:0] GREEN,
	output wire [3:0] BLUE,
	
	output wire RAS,
	output wire CAS,
	output wire RW,
	output wire [7:0] A,
	input wire [7:0] DIN,
	output wire [7:0] DOUT,

	output wire CS0, // Select BASIC ROM (low active)
	output wire CS1, // Select Kernal ROM (low active)
	output wire [3:0] ROM_SEL, // 3:2 - Kernal, Cartridge1 HIGH, Function HIGH, Cartridge2 HIGH
	                           // 1:0 - BASIC, Cartridge2 LOW, Function LOW, Cartridge2 LOW

	output wire [13:0] ROM_ADDR,

	input [4:0] JOY0,
	input [4:0] JOY1,
	
	input PS2DAT,
	input PS2CLK,
	
	output IEC_DATAOUT,
	input IEC_DATAIN,
	output IEC_CLKOUT,
	input IEC_CLKIN,
	output IEC_ATNOUT,
	//input IEC_ATNIN,
	output IEC_RESET,
	
	input CASS_READ,
	output CASS_WRITE,
	input CASS_SENSE,
	output CASS_MOTOR,

	input [1:0] SID_TYPE,
	output [17:0] SID_AUDIO,

	output AUDIO_L,
	output AUDIO_R,

	input [13:0] dl_addr,
	input [7:0] dl_data,
	input kernal_dl_write,
	input basic_dl_write,

	output PAL,
	
	output RS232_TX,
	output RGBS
    );

parameter MODE_PAL = 1;
parameter INTERNAL_ROM = 1;

wire [15:0] c16_addr;
wire [15:0] ted_addr;
wire [15:0] cpu_addr;
wire [7:0] c16_data,ted_data,ram_data,cpu_data,basic_data,kernal_data,port_in,port_out,keyport_data;
wire [7:0] keyboard_row,kbus,kbus_kbd;
wire [7:0] keyscancode;
wire keyreceived;
wire [6:0] c16_color;
wire mux,cpuenable;
wire aec,rdy;
wire keyboardio;
wire sound;
reg [7:0] c16_datalatch=8'b0;
reg sreset=1'b0;
reg [23:0] resetcounter=24'b0;
reg [15:0] c16_addrlatch=16'b0;
wire irq1;
wire keyreset;

// wire joysticks 
wire [4:0] joy0_sel = (!c16_data[2])?{!JOY0[4],!JOY0[0],!JOY0[1],!JOY0[2],!JOY0[3]}:5'h1f;
wire [4:0] joy1_sel = (!c16_data[1])?{!JOY1[4],!JOY1[0],!JOY1[1],!JOY1[2],!JOY1[3]}:5'h1f;
assign kbus[3:0] = kbus_kbd[3:0] & joy0_sel[3:0] & joy1_sel[3:0];
assign kbus[5:4] = kbus_kbd[5:4]; // no joystick line connected here
assign kbus[6] = kbus_kbd[6] & joy0_sel[4];
assign kbus[7] = kbus_kbd[7] & joy1_sel[4];
assign ROM_ADDR = c16_addr[13:0];

reg [3:0] rom_sel_reg;
wire kern = c16_addr[15:8] == 8'hFC; // FCXX is always kernal
assign ROM_SEL = { rom_sel_reg[3:2] & { ~kern, ~kern }, rom_sel_reg[1:0] };

always @(posedge CLK28) begin
	if (sreset)
		rom_sel_reg <= 0;
	else begin
		// FDD0-FDDF is ROM banking address
		if (c16_addr[15:4] == 12'hFDD && ~RW) rom_sel_reg <= c16_addr[3:0];
	end
end

// 8501 CPU
	mos8501 cpu (
		.clk(CLK28), 
		.reset(sreset), 
		.enable(cpuenable && !WAIT),  
		.irq_n(irq_n), 
		.data_in(c16_data), 
		.data_out(cpu_data), 
		.address(cpu_addr),
		.gate_in(mux),
		.rw(RW),								// rw=high read, rw=low write
		.port_in(port_in),
		.port_out(port_out),
		.rdy(rdy),
		.aec(aec)
	);

// TED 8360 instance	
wire irq_n, cpuclk;

ted mos8360(
	.clk(CLK28),
	.addr_in(c16_addr),
	.addr_out(ted_addr),
	.data_in(c16_data),
	.data_out(ted_data),
	.rw(RW),
	.cpuclk(cpuclk),
	.color(c16_color),
	.csync(CSYNC),
	.hsync(HSYNC),
	.vsync(VSYNC),
	.irq(irq_n),
	.ba(rdy),
	.mux(mux),
	.ras(RAS),
	.cas(CAS),
	.cs0(CS0),
	.cs1(CS1),
	.aec(aec),
	.k(kbus),
	.snd(sound),
	.pal(PAL),
	.cpuenable(cpuenable)
	);
	
// Kernal rom

	kernal_rom #(.MODE_PAL(MODE_PAL)) kernal(
		.clk(CLK28),
		.address_in(kernal_dl_write?dl_addr:c16_addr[13:0]),
		.data_out(kernal_data_int),
		.data_in(dl_data),
		.wr(kernal_dl_write),
		.cs(CS1)
		);
wire [7:0] kernal_data_int;
assign kernal_data = INTERNAL_ROM ? kernal_data_int : (~CS1 & RW) ? DIN : 8'hFF;

// Basic rom

	basic_rom basic(
		.clk(CLK28),
		.address_in(basic_dl_write?dl_addr:c16_addr[13:0]),
		.data_out(basic_data_int),
		.data_in(dl_data),
		.wr(basic_dl_write),
		.cs(CS0)
		);
wire [7:0] basic_data_int;
assign basic_data = INTERNAL_ROM ? basic_data_int : (~CS0 & RW) ? DIN : 8'hFF;
// Color decoder to 12bit RGB	
 
colors_to_rgb colordecode (
	.clk(CLK28),
	.color(c16_color),
	.red(RED),
	.green(GREEN),
	.blue(BLUE)
	);

// keyboard part

ps2receiver ps2rcv(
    .clk(CLK28),
    .ps2_clk(PS2CLK),
    .ps2_data(PS2DAT),
    .rx_done(keyreceived),
    .ps2scancode(keyscancode)
    );

c16_keymatrix keyboard(
	 .clk(CLK28),
    .scancode(keyscancode),
    .receiveflag(keyreceived),
	 .row(keyboard_row),
    .kbus(kbus_kbd),
	 .keyreset(keyreset)
    );

mos6529 keyport(
	 .clk(CLK28),
    .data_in(c16_data),
    .data_out(keyport_data),
    .port_in(keyboard_row),	// keyport 6529 in C16 is unidirectional however if we read it the last written data is read back so we feed back its output.
    .port_out(keyboard_row),
    .rw(RW),
    .cs(keyboardio)
    );
	 
assign AUDIO_R=sound;
assign AUDIO_L=sound;
assign RGBS=1'bz;				// VGA/RGBS jumper is not implemented in current version
assign RS232_TX=1'bz;		// RS232 is not implemented in current version

assign keyboardio=(c16_addr[15:4]==12'hfd3)?1'b1:1'b0;		// as we don't have PLA, keyport is identified here

// C16 additional motherboard functions


always @(posedge CLK28)		// reset tries to emulate the length of a real reset
	begin
	if(RESET|keyreset) begin		// reset can be triggered by reset button or CTRL+ALT+DEL from keyboard
		resetcounter<=0;
		sreset<=1;
	end else begin
		if(resetcounter==24'd16777215)
			sreset<=0;
		else begin
			resetcounter<=resetcounter+1'd1;
			sreset<=1;
			end
		end
	end	
	
// assign VSYNC=1'b1; // set scart mode to RGB for TV

assign c16_addr=(~mux)?c16_addrlatch:cpu_addr&ted_addr;																	// C16 address bus
assign c16_data=(mux)?c16_datalatch:cpu_data&ted_data&ram_data&kernal_data&basic_data&keyport_data&cass_data&sid_data;	// C16 data bus

always @(posedge CLK28)							// addres and data bus latching emulates dynamic memory behaviour of these buses 
	begin
	c16_datalatch<=c16_data;
	c16_addrlatch<=c16_addr;
	end

// external 4464 DRAM signal connections on Papilio FPGATED wing

assign A=(~mux)?c16_addr[15:8]:c16_addr[7:0];	//  DRAM address multiplexer for TMS4464 address lines
assign DOUT=c16_data;					// only drive external TMS4464 data lines when there is a write cycle

assign ram_data=(RW & ~CAS)?DIN:8'hff;				// internal ram_data should be 0xff when external RAM's data line is in high impedance state

// connect IEC bus

assign IEC_DATAOUT=port_out[0];
assign port_in[7]=IEC_DATAIN;
assign IEC_CLKOUT=port_out[1];
assign port_in[6]=IEC_CLKIN;
assign IEC_ATNOUT=port_out[2];
//assign ATN=IEC_ATNIN;
assign IEC_RESET=sreset;

assign     CASS_MOTOR = port_out[3];
assign     port_in[4] = CASS_READ;
wire       cass_sel   = cpu_addr[15:4] == 12'hFD1;
wire [7:0] cass_data  = { 5'b11111, cass_sel ? CASS_SENSE : 1'b1, 2'b11 };
assign     CASS_WRITE = port_out[6];

// SID extension
reg sid_clk_en;
always @(posedge CLK28) begin
	reg muxD, sid_clk;

	sid_clk_en <= 0;
	muxD <= mux;
	if (~muxD & mux) begin
		sid_clk <= ~sid_clk;
		sid_clk_en <= sid_clk;
	end
end

// valid adresses for SID: FD40-FD5F and FE80-FE9F
wire cs_sid = SID_TYPE && ((c16_addr[15:5] == 'b1111_1101_010) || (c16_addr[15:5] == 'b1111_1110_100));

wire  [7:0] sid8580_data;
wire [15:0] sid8580_audio;

sid8580 sid8580
(
	.reset(sreset),
	.clk32(CLK28),
	.clk_1MHz(sid_clk_en),

	.cs(cs_sid),
	.we(~RW),
	.addr(c16_addr[4:0]),
	.data_in(c16_data),
	.data_out(sid8580_data),

	.extfilter_en(1),
	.audio_data(sid8580_audio)
);

wire  [7:0] sid6581_data;
wire [17:0] sid6581_audio;

sid_top #(.g_num_voices(3)) sid6581
(
	.reset(sreset),
	.clock(CLK28),
	.start_iter(sid_clk_en),

	.wren(~RW & cs_sid),
	.addr({ 3'd0, c16_addr[4:0] }),
	.wdata(c16_data),
	.rdata(sid6581_data),

	.extfilter_en(1),
	.sample_left(sid6581_audio)
);

assign      SID_AUDIO = SID_TYPE[0] ? sid6581_audio : (SID_TYPE[1] ? { sid8580_audio, 2'd0 } : 18'd0);
wire  [7:0] sid_data  = (cs_sid & RW) ? (SID_TYPE[0] ? sid6581_data : sid8580_data) : 8'hFF;

endmodule
