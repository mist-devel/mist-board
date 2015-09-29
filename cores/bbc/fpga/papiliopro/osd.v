`timescale 1ns / 1ps
//
// osd.v
// 
// On Screen Display implementation for the Papilio Pro board
// http://code.google.com/p/mist-board/
// 
// Copyright (c) 2013 Till Harbaum <till@harbaum.org> 
// Copyright (c) 2015 Stephen J. Leary <sleary@vavi.co.uk> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 


// A simple OSD implementation. Can be hooked up between a cores
// VGA output and the physical VGA pins

module osd (

	// OSDs pixel clock, should be synchronous to cores pixel clock to
	// avoid jitter.
	input 			pclk,

	// SPI interface
	input         sck,
	input         ss,
	input         sdi,

	// VGA signals coming from core
	input 		  	red_in,
	input 		  	green_in,
	input 		  	blue_in,
	input				hs_in,
	input				vs_in,
	
	// VGA signals going to video connector
	output [3:0]  	red_out,
	output [3:0]  	green_out,
	output [3:0]  	blue_out,
	output			hs_out,
	output			vs_out
);

parameter OSD_X_OFFSET = 10'd0;
parameter OSD_Y_OFFSET = 10'd0;
parameter OSD_COLOR    = 3'd0;

assign red_out 	= {4{red_in}};
assign green_out 	= {4{green_in}};
assign blue_out 	= {4{blue_in}};
assign hs_out		= hs_in;
assign vs_out		= vs_in;

endmodule
