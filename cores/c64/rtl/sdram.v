//
// sdram.v
//
// sdram controller implementation for the MiST board
// http://code.google.com/p/mist-board/
// 
// Copyright (c) 2013 Till Harbaum <till@harbaum.org> 
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

module sdram (

	// interface to the MT48LC16M16 chip
	output [12:0]		sd_addr,    // 13 bit multiplexed address bus
	output [1:0] 		sd_ba,      // two banks
	output 				sd_cs,      // a single chip select
	output 				sd_we,      // write enable
	output 				sd_ras,     // row address select
	output 				sd_cas,     // columns address select

	// cpu/chipset interface
	input 		 		init,			// init signal after FPGA config to initialize RAM
	input 		 		clk,			// sdram is accessed at up to 128MHz
	
//	input [15:0]   	addr,       // 25 bit byte address
	input [24:0]   	addr,       // 25 bit byte address
	input 		 		refresh,    // refresh cycle
	input 		 		ce,         // cpu/chipset access
	input 		 		we          // cpu/chipset requests write
);

// no burst configured
localparam RASCAS_DELAY   = 3'd2;   // tRCD>=20ns -> 2 cycles@64MHz
localparam BURST_LENGTH   = 3'b000; // 000=none, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 

// ---------------------------------------------------------------------
// ------------------------ cycle state machine ------------------------
// ---------------------------------------------------------------------

localparam STATE_IDLE      = 3'd0;   // first state in cycle
localparam STATE_CMD_START = 3'd1;   // state in which a new command can be started
localparam STATE_CMD_CONT  = STATE_CMD_START  + RASCAS_DELAY - 3'd1; // 4 command can be continued
localparam STATE_LAST      = 3'd7;   // last state in cycle

reg [2:0] q /* synthesis noprune */;
reg last_ce, last_refresh;
always @(posedge clk) begin
	last_ce <= ce;
	last_refresh <= refresh;

	// start a new cycle in rising edge of ce or refresh
	if((ce && !last_ce) || (refresh && !last_refresh))
		q <= 3'd1;
	
	if(q != 0)
			q <= q + 3'd1;
end

// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

// wait 1ms (32 clkref cycles) after FPGA config is done before going
// into normal operation. Initialize the ram in the last 16 reset cycles (cycles 15-0)
reg [4:0] reset;
always @(posedge clk) begin
	if(init)	reset <= 5'h1f;
	else if((q == STATE_LAST) && (reset != 0))
		reset <= reset - 5'd1;
end

// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
localparam CMD_INHIBIT         = 4'b1111;
localparam CMD_NOP             = 4'b0111;
localparam CMD_ACTIVE          = 4'b0011;
localparam CMD_READ            = 4'b0101;
localparam CMD_WRITE           = 4'b0100;
localparam CMD_BURST_TERMINATE = 4'b0110;
localparam CMD_PRECHARGE       = 4'b0010;
localparam CMD_AUTO_REFRESH    = 4'b0001;
localparam CMD_LOAD_MODE       = 4'b0000;

reg [3:0] sd_cmd;   // current command sent to sd ram

// drive control signals according to current command
assign sd_cs  = sd_cmd[3];
assign sd_ras = sd_cmd[2];
assign sd_cas = sd_cmd[1];
assign sd_we  = sd_cmd[0];

// assign sd_data = we?{din, din}:16'bZZZZZZZZZZZZZZZZ;
// assign dout = sd_data[7:0];

always @(posedge clk) begin
	sd_cmd <= CMD_INHIBIT;

	if(reset != 0) begin
		if(q == STATE_IDLE) begin
			if(reset == 13)  sd_cmd <= CMD_PRECHARGE;
			if(reset ==  2)  sd_cmd <= CMD_LOAD_MODE;
		end
	end else begin
		if(q == STATE_IDLE) begin
			if(ce && !last_ce)           sd_cmd <= CMD_ACTIVE;
			if(refresh && !last_refresh) sd_cmd <= CMD_AUTO_REFRESH;
		end else if((q == STATE_CMD_CONT)&&(!refresh)) begin
			if(we)		 sd_cmd <= CMD_WRITE;
			else if(ce)  sd_cmd <= CMD_READ;
		end
	end
end
	
wire [12:0] reset_addr = (reset == 13)?13'b0010000000000:MODE;
	
wire [12:0] run_addr = 
//	(q == STATE_CMD_START)?{ 5'b00000, addr[15:8]}:{ 5'b00100, addr[7:0]};
//(q == STATE_CMD_START)?addr[21:9]:{ 4'b0010, addr[8:0]};  							//possibly try this LCA 6mar17
	(q == STATE_CMD_START)?addr[20:8]:{ 4'b0010, addr[23], addr[7:0]};

assign sd_addr = (reset != 0)?reset_addr:run_addr;

//assign sd_ba = 2'b00;
assign sd_ba = addr[22:21];

endmodule
