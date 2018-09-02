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
// Create Date:    22:20:09 12/09/2014 
// Module Name:    basic_rom.v 
// Project Name: 	 FPGATED
// Target Devices: Xilinx Spartan 3E
//
// Description: 
//		Basic ROM synthetised to FPGA's internal SRAM. Xilinx ISE requires 
//		ROM_STYLE="BLOCK" parameter next to kernal array. For other vendor's
//		device syntax refer to the FPGA vendor's documentation.
// 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module basic_rom(
    input wire clk,
    input wire [13:0] address_in,
    output wire [7:0] data_out,
    input wire [7:0] data_in,
    input wire wr,	 
    input wire cs
    );

(* ROM_STYLE="BLOCK" *)
reg [7:0] basic [0:16383];
reg [7:0] data;
reg cs_prev=1'b1;
wire enable;

always@(posedge clk) begin
	if (wr)
		basic[address_in] <= data_in;

	if(enable)
		data<=basic[address_in];
end

always@(posedge clk)
	cs_prev<=cs;

assign enable=~cs&cs_prev;		// cs falling edge detection
assign data_out=(~cs)?data:8'hff;

initial begin
$readmemh("roms/basic.hex",basic);
end

endmodule
