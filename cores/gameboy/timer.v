//
// timer.v
//
// Gameboy for the MIST board https://github.com/mist-devel
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
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
//

module timer (
	input  reset,
   input  clk,    // 4 Mhz cpu clock
	output reg irq,
	
	// cpu register interface
	input  cpu_sel,
	input [1:0] cpu_addr,
	input  cpu_wr,
	input [7:0] cpu_di,
	output [7:0] cpu_do
);

// input: 4Mhz
// clk_div[0] = 2Mhz
// clk_div[1] = 1Mhz
// clk_div[2] = 524khz
// clk_div[3] = 262khz
// clk_div[4] = 131khz
// clk_div[5] = 65khz
// clk_div[6] = 32khz
// clk_div[7] = 16khz
// clk_div[8] = 8khz
// clk_div[9] = 4khz

wire resetdiv = cpu_sel && cpu_wr && (cpu_addr == 2'b00); //resetdiv also resets internal counter

reg [9:0] clk_div;
always @(posedge clk or posedge resetdiv)
	if(resetdiv)
	  clk_div <= 10'd2;
	else
		if (reset)
		     clk_div <= 10'd8;
		  else
	        clk_div <= clk_div + 10'd1;

reg [7:0] div;
reg [7:0] tma;
reg [7:0] tima;
reg [2:0] tac;

always @(posedge clk) begin
	if(reset) begin
		tima <= 0;
		tma <= 0;
		tac <= 0;
		irq <= 0;
		div <= 0;
	end else begin
		irq <= 0;

		if(clk_div[7:0] == 0)   // 16kHz
			div <= div + 8'd1;

		// timer enabled?
		if(tac[2]) begin
			// timer frequency
			if(((tac[1:0] == 2'b00) && (clk_div[9:0] == 0)) ||     // 4 khz
				((tac[1:0] == 2'b01) && (clk_div[3:0] == 0)) ||     // 262 khz
				((tac[1:0] == 2'b10) && (clk_div[5:0] == 0)) ||     // 65 khz
				((tac[1:0] == 2'b11) && (clk_div[7:0] == 0))) begin // 16 khz

				if(tima != 8'hff)
					tima <= tima + 8'd1;
				else begin
					irq <= 1'b1;    // irq when timer overflows
					tima <= tma;    // reload timer
				end
			end
		end
		
		if(cpu_sel && cpu_wr) begin
			case(cpu_addr)
				2'b00:  div <= 8'h00;    // writing clears counter
				2'b01:  tima <= cpu_di;
				2'b10:  tma <= cpu_di;
				2'b11:  tac <= cpu_di[2:0];
			endcase
		end
	end
end

assign cpu_do = 
	(cpu_addr == 2'b00)?div:
	(cpu_addr == 2'b01)?tima:
	(cpu_addr == 2'b10)?tma:
	{5'b11111, tac};
	
endmodule
