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
// Create Date:    09:08:17 12/17/2015 
// Design Name: 	 FPGATED
// Module Name:    mos6529.v 
// Description:	 MOS 6529 IC emulation.
//	
// Revision: 
// 0.1	first release 				
//	1.0	chip read bug fixed 5/04/2016
//  
// Additional Comments: 
// CS signal is high active while in real IC it is low active.
//////////////////////////////////////////////////////////////////////////////////

module mos6529(
	 input clk,
    input [7:0] data_in,
    output wire [7:0] data_out,
    input [7:0] port_in,
    output wire [7:0] port_out,
    input rw,
    input cs
    );

reg [7:0] iodata=0;

assign port_out=iodata;
assign data_out=(cs & rw)?iodata:8'hff;

always @(posedge clk)
	begin
	if(cs)
		if(rw)
			iodata<=port_in;
		else
			iodata<=data_in;
	end
endmodule
