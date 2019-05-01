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
// Create Date:    11:30:06 12/14/2015 
// Module Name:    ps2receiver.v
// Project Name: 	 FPGATED
// Description: 	 PS2 keyboard receiver
//
// 
//
// Revision: 
// Revision 1.0 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module ps2receiver(
    input clk,
    input ps2_clk,
    input ps2_data,
    output reg rx_done,
    output reg [7:0] ps2scancode
    );

reg ps2clkreg=1'b0,prev_ps2clkreg=1'b0;
reg [3:0] receivedbits=4'b0;
reg [11:0] watchdog=12'd2900;								// ~ 100us watchdog period with 28MHz clock
reg [7:0] ps2clkfilter;
reg [10:0] shiftreg;

always @(posedge clk)										// filtering ps2 clock line glitches
	begin
	ps2clkfilter<={ps2clkfilter[6:0],ps2_clk};
	if(ps2clkfilter==8'h00)
		ps2clkreg<=0;
	else if (ps2clkfilter==8'hff)
		ps2clkreg<=1;
	prev_ps2clkreg<=ps2clkreg;								// this is needed for clock edge detection
	end

always @(posedge clk)
	begin
	rx_done<=0;													// rx_done is active only for one clk cycle
	if(watchdog==0)											// when watchdog timer expires, reset received bits
		receivedbits<=0;
	else watchdog<=watchdog-1'd1;
		
	if(prev_ps2clkreg & ~ps2clkreg)						// falling edge of ps2 clock
		begin
		watchdog<=12'd2900;									// reload watchdog timer
		shiftreg<={ps2_data,shiftreg[10:1]};
		receivedbits<=receivedbits+1'd1;
		end
		
	if(receivedbits==4'd11)
		begin
		ps2scancode<=shiftreg[8:1];
		rx_done<=1;
		receivedbits<=0;
		end
	end

endmodule
