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
// Create Date:    22:03:30 11/20/2014 
// Design Name: 	 Commodore Plus/4 color value conversion to 12bit RGB values 
// Module Name:    colors_to_rgb.v 
// Project Name:   FPGATED
// Target Devices: Xilinx Spartan 3E
//
// Description: 	
// 	Converts TED's 7 bit color codes to 12 bit RGB values used by video DAC.
//		12 bit DAC values from Jozsef Laszlo
//
// Revisions: 
// Revision 0.1 - File Created 
//
//////////////////////////////////////////////////////////////////////////////////
module colors_to_rgb(
	 input clk,
    input [6:0] color,
    output [3:0] red,
    output [3:0] green,
    output [3:0] blue
    );
reg [11:0] color_lut [127:0];
reg [11:0] rgbcolor;

initial
	begin
	color_lut[0]=12'b0000_0000_0000;
	color_lut[1]=12'b0010_0010_0010;
	color_lut[2]=12'b0101_0000_0000;
	color_lut[3]=12'b0000_0011_0011;
	color_lut[4]=12'b0100_0000_0101;
	color_lut[5]=12'b0000_0100_0000;
	color_lut[6]=12'b0001_0001_0111;
	color_lut[7]=12'b0010_0010_0000;
	color_lut[8]=12'b0100_0001_0000;
	color_lut[9]=12'b0011_0010_0000;
	color_lut[10]=12'b0001_0011_0000;
	color_lut[11]=12'b0101_0000_0010;
	color_lut[12]=12'b0000_0011_0001;
	color_lut[13]=12'b0000_0010_0110;
	color_lut[14]=12'b0001_0001_0111;
	color_lut[15]=12'b0000_0011_0000;
	color_lut[16]=12'b0000_0000_0000;
	color_lut[17]=12'b0010_0010_0010;
	color_lut[18]=12'b0110_0001_0001;
	color_lut[19]=12'b0000_0100_0100;
	color_lut[20]=12'b0101_0000_0110;
	color_lut[21]=12'b0000_0100_0000;
	color_lut[22]=12'b0010_0010_1000;
	color_lut[23]=12'b0011_0011_0000;
	color_lut[24]=12'b0101_0010_0000;
	color_lut[25]=12'b0100_0010_0000;
	color_lut[26]=12'b0010_0100_0000;
	color_lut[27]=12'b0110_0001_0011;
	color_lut[28]=12'b0000_0100_0010;
	color_lut[29]=12'b0000_0011_0111;
	color_lut[30]=12'b0010_0001_1000;
	color_lut[31]=12'b0001_0100_0000;
	color_lut[32]=12'b0000_0000_0000;
	color_lut[33]=12'b0011_0011_0011;
	color_lut[34]=12'b0110_0010_0010;
	color_lut[35]=12'b0000_0101_0101;
	color_lut[36]=12'b0110_0001_0111;
	color_lut[37]=12'b0000_0101_0000;
	color_lut[38]=12'b0010_0011_1001;
	color_lut[39]=12'b0100_0100_0000;
	color_lut[40]=12'b0110_0010_0000;
	color_lut[41]=12'b0101_0011_0000;
	color_lut[42]=12'b0010_0101_0000;
	color_lut[43]=12'b0110_0001_0100;
	color_lut[44]=12'b0000_0101_0011;
	color_lut[45]=12'b0001_0011_1000;
	color_lut[46]=12'b0011_0010_1001;
	color_lut[47]=12'b0001_0101_0000;
	color_lut[48]=12'b0000_0000_0000;
	color_lut[49]=12'b0100_0100_0100;
	color_lut[50]=12'b0111_0011_0011;
	color_lut[51]=12'b0001_0110_0110;
	color_lut[52]=12'b0111_0010_1000;
	color_lut[53]=12'b0001_0110_0010;
	color_lut[54]=12'b0100_0100_1010;
	color_lut[55]=12'b0101_0101_0000;
	color_lut[56]=12'b0111_0100_0001;
	color_lut[57]=12'b0110_0100_0000;
	color_lut[58]=12'b0011_0110_0000;
	color_lut[59]=12'b0111_0011_0101;
	color_lut[60]=12'b0001_0110_0100;
	color_lut[61]=12'b0010_0100_1001;
	color_lut[62]=12'b0100_0011_1010;
	color_lut[63]=12'b0011_0110_0000;
	color_lut[64]=12'b0000_0000_0000;
	color_lut[65]=12'b0110_0110_0110;
	color_lut[66]=12'b1010_0101_0101;
	color_lut[67]=12'b0011_1000_1000;
	color_lut[68]=12'b1001_0100_1010;
	color_lut[69]=12'b0100_1000_0100;
	color_lut[70]=12'b0110_0110_1100;
	color_lut[71]=12'b0111_0111_0001;
	color_lut[72]=12'b1001_0110_0011;
	color_lut[73]=12'b1000_0110_0010;
	color_lut[74]=12'b0110_1000_0001;
	color_lut[75]=12'b1010_0101_0111;
	color_lut[76]=12'b0011_1000_0110;
	color_lut[77]=12'b0100_0111_1011;
	color_lut[78]=12'b0110_0101_1100;
	color_lut[79]=12'b0101_1000_0010;
	color_lut[80]=12'b0000_0000_0000;
	color_lut[81]=12'b1000_1000_1000;
	color_lut[82]=12'b1011_0111_0111;
	color_lut[83]=12'b0101_1001_1001;
	color_lut[84]=12'b1011_0110_1011;
	color_lut[85]=12'b0101_1010_0101;
	color_lut[86]=12'b0111_0111_1110;
	color_lut[87]=12'b1001_1001_0010;
	color_lut[88]=12'b1011_0111_0101;
	color_lut[89]=12'b1010_1000_0011;
	color_lut[90]=12'b0111_1001_0010;
	color_lut[91]=12'b1011_0110_1001;
	color_lut[92]=12'b0101_1010_1000;
	color_lut[93]=12'b0110_1000_1101;
	color_lut[94]=12'b1000_0111_1110;
	color_lut[95]=12'b0110_1010_0011;
	color_lut[96]=12'b0000_0000_0000;
	color_lut[97]=12'b1011_1011_1011;
	color_lut[98]=12'b1110_1001_1001;
	color_lut[99]=12'b1000_1100_1100;
	color_lut[100]=12'b1101_1001_1110;
	color_lut[101]=12'b1000_1101_1000;
	color_lut[102]=12'b1010_1010_1111;
	color_lut[103]=12'b1011_1011_0101;
	color_lut[104]=12'b1101_1010_1000;
	color_lut[105]=12'b1100_1011_0110;
	color_lut[106]=12'b1010_1100_0101;
	color_lut[107]=12'b1110_1001_1011;
	color_lut[108]=12'b0111_1100_1010;
	color_lut[109]=12'b1001_1011_1111;
	color_lut[110]=12'b1010_1010_1111;
	color_lut[111]=12'b1001_1100_0110;
	color_lut[112]=12'b0000_0000_0000;
	color_lut[113]=12'b1110_1110_1110;
	color_lut[114]=12'b1111_1101_1101;
	color_lut[115]=12'b1011_1111_1111;
	color_lut[116]=12'b1111_1100_1111;
	color_lut[117]=12'b1100_1111_1100;
	color_lut[118]=12'b1110_1110_1111;
	color_lut[119]=12'b1111_1111_1001;
	color_lut[120]=12'b1111_1110_1011;
	color_lut[121]=12'b1111_1110_1010;
	color_lut[122]=12'b1110_1111_1001;
	color_lut[123]=12'b1111_1101_1111;
	color_lut[124]=12'b1011_1111_1110;
	color_lut[125]=12'b1100_1110_1111;
	color_lut[126]=12'b1110_1101_1111;
	color_lut[127]=12'b1101_1111_1010;
	end

always @(posedge clk)
	begin
	rgbcolor<=color_lut[color];
	end
	
assign red=rgbcolor[11:8];
assign green=rgbcolor[7:4];
assign blue=rgbcolor[3:0];

endmodule
