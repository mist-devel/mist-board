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
//	 Create Date:    17:12:57 12/05/2014 
//  Design Name: 	 Commodore 16/Plus 4 Kernal ROM
//  Module Name:    kernal_rom 
//  Project Name: 	 FPGATED
//  Description:  
//		Kernal ROM synthetised to FPGA's internal SRAM. Xilinx ISE requires 
//		ROM_STYLE="BLOCK" parameter next to kernal array. For other vendor's
//		device syntax refer to the FPGA vendor's documentation.
//		
//		Choose the proper Kernal file version depending on NTSC or PAL system
// 	and comment out the ones which are not needed. 
//		If you want to convert your own kernal image to compatible version use
//		bin2hex.pl perl script to convert it to .hex format.
//////////////////////////////////////////////////////////////////////////////////
module kernal_rom #(parameter MODE_PAL=1) (
    input wire clk,
    input wire [13:0] address_in,
    output wire [7:0] data_out,
    input wire [7:0] data_in,
    input wire wr,
    input wire cs
    );

(* ROM_STYLE="BLOCK" *)
reg [7:0] kernal [0:16383];
reg [7:0] data;
reg cs_prev=1'b1;
wire enable;

initial begin
// uncomment the Kernal version to use

//$readmemh("Diag264_PAL.hex",kernal);

//$readmemh("Diag264_NTSC.hex",kernal);
if (MODE_PAL)
$readmemh("roms/kernal_PAL.hex",kernal);
else 
$readmemh("roms/kernal_NTSC.hex",kernal);


//$readmemh("Jiffy_PAL.hex",kernal); 
// Note that Jiffy DOS is not free so Jiffy_PAL.hex is not included with FPGATED source code

end

always@(posedge clk) begin
	if (wr)
		kernal[address_in] <= data_in;
		
	if(enable)
		data<=kernal[address_in];
end
		
always@(posedge clk)
	cs_prev<=cs;

assign enable=~cs&cs_prev;		// cs falling edge detection
assign data_out=(~cs)?data:8'hff;


endmodule
