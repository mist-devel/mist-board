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
// Create Date:    16:36:31 12/10/2014 
// Module Name:    mos8501 
// Project Name:	 FPGATED 
// Target Devices: Xilinx Spartan 3E
//
// Description: 
//
// Dependencies: 
//	This module contains an instance of Peter Wendrich's 6502 CPU core from FPGA64 project. 
//	The CPU core is used and included with Peter's permission and not developed by me.
// The mos8501 shell around the CPU core is written by me, but inspired by fpga64 6510 CPU
// shell. It might shows certain similarities.
//
// Revision history:
//	0.1	first release using incorrect 6502 core from fpga64 project
//	1.0	CPU core replaced to cpu65xx_fast.vhd from fpga64 project
//
//////////////////////////////////////////////////////////////////////////////////
module mos8501(
    input clk,
    input reset,
    input enable,
    input irq_n,
    input [7:0] data_in,
	 output wire [7:0] data_out,
	 output [15:0] address,
	 input gate_in,
    output rw,
	 input [7:0] port_in,
	 output [7:0] port_out,
	 input rdy,
	 input aec
    );

wire we,enable_cpu;
wire [15:0] core_address;
wire [7:0] core_data_out;
wire port_access;
reg  [7:0] data_out_reg,core_data_in,port_io;
reg [7:0] port_dir=8'b0;
reg [7:0] port_data=8'b0;
reg rw_reg,aec_reg;

// 6502 CPU core

wire we_n;
assign we = ~we_n;

T65 cpu_core(
	
	.Mode (2'b00),
	.Res_n (~reset),
	.Enable(enable),
	.Clk(clk),
	.Rdy(rdy),
	.Abort_n(1),
	.IRQ_n(irq_n),
	.NMI_n(1),
	.SO_n(1),
	.R_w_n(we_n),
	.A(core_address),
	.DI(we_n ? core_data_in : core_data_out),
	.DO(core_data_out)
);

assign address=(aec)?core_address:16'hffff;		// address tri state emulated for easy bus signal combining

always @(posedge clk)		
	begin
	if(gate_in)				
		begin							
		if(port_access==1'b1 && we==1'b1)
			if(address[0]==1'b0)							// when port direction register is written, data on bus is last read byte which is 0x00
				data_out_reg<=8'h00;
			else												// when port register is written, data on bus is last read byte which is 0x01
				data_out_reg<=8'h01;
		else
			data_out_reg<=core_data_out;				// when mux is high, data out register is updated
		end
	else
		begin
		data_out_reg<=data_out_reg;					// hold off data out during write cycle
		end
	end

always @(posedge clk)
	begin
	if(gate_in)
		rw_reg<=~we;		
	end

always @(posedge clk)									// registering aec for 1 clk cycle delay
	begin
	aec_reg<=aec;
	end

assign rw=(~aec_reg)?1'b1:rw_reg;

assign data_out=(~aec_reg | gate_in | rw)?8'hff:data_out_reg;   		// when mux is low data out register is allowed to outside								
assign port_access=(address[15:1]==0)?1'b1:1'b0;

// IO port part of cpu
	
always @(posedge clk)									//writing port registers
	begin
	if(reset)
		begin
		port_dir<=0;
		port_data<=0;
		end
	else if (enable)
			if(port_access & we)
				if(address[0]==0)
					port_dir<=core_data_out;
				else
					port_data<=core_data_out;
	end
	
always @*													// reading port registers
	begin
	core_data_in=data_in;
	if (port_access & ~we)
		if(address[0]==0)
			core_data_in=port_dir;
		else
			core_data_in=port_io;
	end
	
// if direction bit is 0 then data is from chip's port
// if direction bit is 1 then data is from data port register filled earlier by CPU

always @*
	begin
		if(port_dir[0]==1'b0)
				port_io[0]=port_in[0];				
			else
				port_io[0]=port_data[0];			
		if(port_dir[1]==1'b0)
				port_io[1]=port_in[1];				
			else
				port_io[1]=port_data[1];
		if(port_dir[2]==1'b0)
				port_io[2]=port_in[2];				
			else
				port_io[2]=port_data[2];
		if(port_dir[3]==1'b0)
				port_io[3]=port_in[3];				
			else
				port_io[3]=port_data[3];
		if(port_dir[4]==1'b0)
				port_io[4]=port_in[4];				
			else
				port_io[4]=port_data[4];
		if(port_dir[5]==1'b0)
				port_io[5]=port_in[5];				
			else
				port_io[5]=port_data[5];
		if(port_dir[6]==1'b0)
				port_io[6]=port_in[6];				
			else
				port_io[6]=port_data[6];
		if(port_dir[7]==1'b0)
				port_io[7]=port_in[7];				
			else
				port_io[7]=port_data[7];
	end
	
assign port_out=port_data;
//assign enable_cpu=(~rdy & ~we)?1'b0:enable;			// When RDY is low and cpu would do a read, halt cpu
					 
endmodule
