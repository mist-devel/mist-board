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

// Master clock generator for minimig
// This module generates all necessary clocks from the 4.433619 PAL clock
// JB:
// 2008-03-01	- added ddl for generating in phase system clock with 28MHz clock
// 2008-09-23	- added c1 and c3 clock enable outputs
// 2008-10-15	- adapted e clock enable to be in sync with cck
// 2009-05-23	- eclk modification

module clock_generator
(
//	input	mclk,		// 4.433619 MHz master clock input
	input	clk28m,	 	// 28.37516 MHz clock output
	output	reg c1,		// clk28m clock domain signal synchronous with clk signal
	output	reg c3,		// clk28m clock domain signal synchronous with clk signal delayed by 90 degrees
	output 	cck,		// colour clock output (3.54 MHz)
	input 	clk, 		// 7.09379  MHz clock output
//	output	cpu_clk,
//	input	turbo,
	output 	[9:0] eclk	// 0.709379 MHz clock enable output (clk domain pulse)
);

//            __    __    __    __    __
// clk28m  __/  \__/  \__/  \__/  \__/  
//            ___________             __
// clk     __/           \___________/  
//            ___________             __
// c1      __/           \___________/   <- clk28m domain
//                  ___________
// c3      ________/           \________ <- clk28m domain
//


reg		[3:0] e_cnt;	//used to generate e clock enable

/*
//generate e in sync with cck
always @(cck)
  e_cnt[0] <= ~cck;

always @(posedge clk)
  if (e_cnt[0])
    if (e_cnt[3]) //if e_cnt==9 reset counter
      e_cnt[3:1] <= 0;
    else
      e_cnt[3:1] <= e_cnt[3:1] + 1;
*/

// E clock counter
always @(posedge clk)
  if (e_cnt[3] && e_cnt[0])
    e_cnt[3:0] <= 0;
  else
    e_cnt[3:0] <= e_cnt[3:0] + 4'd1;

// CCK clock output
assign cck = ~e_cnt[0];

assign eclk[0] = ~e_cnt[3] & ~e_cnt[2] & ~e_cnt[1] & ~e_cnt[0]; // e_cnt == 0
assign eclk[1] = ~e_cnt[3] & ~e_cnt[2] & ~e_cnt[1] &  e_cnt[0]; // e_cnt == 1
assign eclk[2] = ~e_cnt[3] & ~e_cnt[2] &  e_cnt[1] & ~e_cnt[0]; // e_cnt == 2
assign eclk[3] = ~e_cnt[3] & ~e_cnt[2] &  e_cnt[1] &  e_cnt[0]; // e_cnt == 3
assign eclk[4] = ~e_cnt[3] &  e_cnt[2] & ~e_cnt[1] & ~e_cnt[0]; // e_cnt == 4
assign eclk[5] = ~e_cnt[3] &  e_cnt[2] & ~e_cnt[1] &  e_cnt[0]; // e_cnt == 5
assign eclk[6] = ~e_cnt[3] &  e_cnt[2] &  e_cnt[1] & ~e_cnt[0]; // e_cnt == 6
assign eclk[7] = ~e_cnt[3] &  e_cnt[2] &  e_cnt[1] &  e_cnt[0]; // e_cnt == 7
assign eclk[8] =  e_cnt[3] & ~e_cnt[2] & ~e_cnt[1] & ~e_cnt[0]; // e_cnt == 8
assign eclk[9] =  e_cnt[3] & ~e_cnt[2] & ~e_cnt[1] &  e_cnt[0]; // e_cnt == 9
		
always @(posedge clk28m)
	c3 <= clk;
	
always @(posedge clk28m)
	c1 <= ~c3;
	
endmodule
