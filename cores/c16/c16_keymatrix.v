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
// Create Date:    19:38:44 12/16/2015 
// Module Name:    c16_keymatrix.v
// Project Name: 	 FPGATED
//
// Description: 	C16/Plus4 keyboard matrix emulation for PS2 keyboards.
//
// Revisions:
// 1.0	first release
//
//////////////////////////////////////////////////////////////////////////////////
module c16_keymatrix(
	 input clk,
    input [7:0] scancode,
    input receiveflag,
	 input [7:0] row,
    output [7:0] kbus,
	 output keyreset
    );

reg releaseflag=0;
reg extendedflag=0;
reg [7:0] colsel=0;
reg key_A=0,key_B=0,key_C=0,key_D=0,key_E=0,key_F=0,key_G=0,key_H=0,key_I=0,key_J=0,key_K=0,key_L=0,key_M=0,key_N=0,key_O=0,key_P=0,key_Q=0,key_R=0,key_S=0,key_T=0,key_U=0,key_V=0,key_W=0,key_X=0,key_Y=0,key_Z=0;
reg key_1=0,key_2=0,key_3=0,key_4=0,key_5=0,key_6=0,key_7=0,key_8=0,key_9=0,key_0=0,key_del=0,key_return=0,key_help=0,key_F1=0,key_F2=0,key_F3=0,key_AT=0,key_shift=0,key_comma=0,key_dot=0;
reg key_minus=0,key_colon=0,key_star=0,key_semicolon=0,key_esc=0,key_equal=0,key_plus=0,key_slash=0,key_control=0,key_space=0,key_runstop=0;
reg key_pound=0,key_down=0,key_up=0,key_left=0,key_right=0,key_home=0,key_commodore=0,key_alt=0;
wire [7:0] rowsel;

assign rowsel=~row;
assign keyreset=key_control&key_alt&key_del;

always @(posedge clk)
	begin
	if(receiveflag)
		begin
		if(scancode==8'hF0)
			releaseflag<=1;
		else if (scancode==8'hE0)
			extendedflag<=1;
		else 
			begin
			releaseflag<=0;
			if (~extendedflag)					// base code keys
				begin
				case(scancode)
					8'h1C:			key_A<=~releaseflag;
					8'h32:			key_B<=~releaseflag;
					8'h21:			key_C<=~releaseflag;
					8'h23:			key_D<=~releaseflag;
					8'h24:			key_E<=~releaseflag;
					8'h2B:			key_F<=~releaseflag;
					8'h34:			key_G<=~releaseflag;
					8'h33:			key_H<=~releaseflag;
					8'h43:			key_I<=~releaseflag;
					8'h3B:			key_J<=~releaseflag;
					8'h42:			key_K<=~releaseflag;
					8'h4B:			key_L<=~releaseflag;
					8'h3A:			key_M<=~releaseflag;
					8'h31:			key_N<=~releaseflag;
					8'h44:			key_O<=~releaseflag;
					8'h4D:			key_P<=~releaseflag;
					8'h15:			key_Q<=~releaseflag;
					8'h2D:			key_R<=~releaseflag;
					8'h1B:			key_S<=~releaseflag;
					8'h2C:			key_T<=~releaseflag;
					8'h3C:			key_U<=~releaseflag;
					8'h2A:			key_V<=~releaseflag;
					8'h1D:			key_W<=~releaseflag;
					8'h22:			key_X<=~releaseflag;
					8'h35:			key_Y<=~releaseflag;
					8'h1A:			key_Z<=~releaseflag;
					8'h69,
					8'h16:			key_1<=~releaseflag;
					8'h72,
					8'h1E:			key_2<=~releaseflag;
					8'h7A,
					8'h26:			key_3<=~releaseflag;
					8'h6B,
					8'h25:			key_4<=~releaseflag;
					8'h73,
					8'h2E:			key_5<=~releaseflag;
					8'h74,
					8'h36:			key_6<=~releaseflag;
					8'h6C,
					8'h3D:			key_7<=~releaseflag;
					8'h75,
					8'h3E:			key_8<=~releaseflag;
					8'h7D,
					8'h46:			key_9<=~releaseflag;
					8'h70,
					8'h45:			key_0<=~releaseflag;
					8'h66:			key_del<=~releaseflag;
					8'h5A:			key_return<=~releaseflag;
					8'h0C:			key_help<=~releaseflag;
					8'h05:			key_F1<=~releaseflag;
					8'h06:			key_F2<=~releaseflag;
					8'h04:			key_F3<=~releaseflag;
					8'h54:			key_AT<=~releaseflag;
					8'h12,
					8'h59:			key_shift<=~releaseflag;
					8'h41:			key_comma<=~releaseflag;
					8'h49:			key_dot<=~releaseflag;
					8'h7B,
					8'h4E:			key_minus<=~releaseflag;
					8'h4C:			key_colon<=~releaseflag;
					8'h7C,
					8'h5B:			key_star<=~releaseflag;
					8'h52:			key_semicolon<=~releaseflag;
					8'h76:			key_esc<=~releaseflag;
					8'h5D:			key_equal<=~releaseflag;
					8'h79,
					8'h55:			key_plus<=~releaseflag;
					8'h4A:			key_slash<=~releaseflag;
					8'h14:			key_control<=~releaseflag;
					8'h29:			key_space<=~releaseflag;
					8'h0D:			key_runstop<=~releaseflag;
					8'h11:			key_alt<=~releaseflag;
					default:;
				endcase
				end
			else begin									// extended code keys
				extendedflag<=0;
				case(scancode)
					8'h2F:			key_pound<=~releaseflag;
					8'h72:			key_down<=~releaseflag;
					8'h75:			key_up<=~releaseflag;
					8'h6B:			key_left<=~releaseflag;
					8'h74:			key_right<=~releaseflag;
					8'h6C:			key_home<=~releaseflag;
					8'h14:			key_control<=~releaseflag;
					8'h1F:			key_commodore<=~releaseflag;
					8'h4A:			key_slash<=~releaseflag;
					8'h5A:			key_return<=~releaseflag;
					8'h71:			key_del<=~releaseflag;
					8'h11:			key_alt<=~releaseflag;
					default:;
				endcase
				end
			end
		end
	end

always @(posedge clk)
	begin
	colsel[0]<=(key_del & rowsel[0]) | (key_3 & rowsel[1]) | (key_5 & rowsel[2]) | (key_7 & rowsel[3]) | (key_9 & rowsel[4]) | (key_down & rowsel[5]) | (key_left & rowsel[6]) | (key_1 & rowsel[7]);
	colsel[1]<=(key_return & rowsel[0]) | (key_W & rowsel[1]) | (key_R & rowsel[2]) | (key_Y & rowsel[3]) | (key_I & rowsel[4]) | (key_P & rowsel[5]) | (key_star & rowsel[6]) | (key_home & rowsel[7]);
	colsel[2]<=(key_pound & rowsel[0]) | (key_A & rowsel[1]) | (key_D & rowsel[2]) | (key_G & rowsel[3]) | (key_J & rowsel[4]) | (key_L & rowsel[5]) | (key_semicolon & rowsel[6]) | (key_control & rowsel[7]);
	colsel[3]<=(key_help & rowsel[0]) | (key_4 & rowsel[1]) | (key_6 & rowsel[2]) | (key_8 & rowsel[3]) | (key_0 & rowsel[4]) | (key_up & rowsel[5]) | (key_right & rowsel[6]) | (key_2 & rowsel[7]);
	colsel[4]<=(key_F1 & rowsel[0]) | (key_Z & rowsel[1]) | (key_C & rowsel[2]) | (key_B & rowsel[3]) | (key_M & rowsel[4]) | (key_dot & rowsel[5]) | (key_esc & rowsel[6]) | (key_space & rowsel[7]);
	colsel[5]<=(key_F2 & rowsel[0]) | (key_S & rowsel[1]) | (key_F & rowsel[2]) | (key_H & rowsel[3]) | (key_K & rowsel[4]) | (key_colon & rowsel[5]) | (key_equal & rowsel[6]) | (key_commodore & rowsel[7]);
	colsel[6]<=(key_F3 & rowsel[0]) | (key_E & rowsel[1]) | (key_T & rowsel[2]) | (key_U & rowsel[3]) | (key_O & rowsel[4]) | (key_minus & rowsel[5]) | (key_plus & rowsel[6]) | (key_Q & rowsel[7]);
	colsel[7]<=(key_AT & rowsel[0]) | (key_shift & rowsel[1]) | (key_X & rowsel[2]) | (key_V & rowsel[3]) | (key_N & rowsel[4]) | (key_comma & rowsel[5]) | (key_slash & rowsel[6]) | (key_runstop & rowsel[7]);
	end

assign kbus=~colsel;

endmodule
