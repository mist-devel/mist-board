/*	sdram_top.v

	Copyright (c) 2013-2014, Stephen J. Leary
	All rights reserved.

	Redistribution and use in source and binary forms, with or without
	modification, are permitted provided that the following conditions are met:
		 * Redistributions of source code must retain the above copyright
			notice, this list of conditions and the following disclaimer.
		 * Redistributions in binary form must reproduce the above copyright
			notice, this list of conditions and the following disclaimer in the
			documentation and/or other materials provided with the distribution.
		 * Neither the name of the Stephen J. Leary nor the
			names of its contributors may be used to endorse or promote products
			derived from this software without specific prior written permission.

	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
	ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
	WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
	DISCLAIMED. IN NO EVENT SHALL STEPHEN J. LEARY BE LIABLE FOR ANY
	DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
	(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
	LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
	ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
	(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
	SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
*/

module sdram_top (

	// interface to the MT48LC16M16 chip
	input			sd_clk,		// sdram is accessed at 128MHz
	input			sd_rst,		// reset the sdram controller.
	output			sd_cke,		// clock enable.
	inout  reg[15:0]sd_dq,		// 16 bit bidirectional data bus
	output reg[12:0]sd_addr,	// 13 bit multiplexed address bus
	output reg[1:0]	sd_dqm = 2'b00,		// two byte masks
	output reg[1:0]	sd_ba = 2'b00,		// two banks
	output			sd_cs_n,	// a single chip select
	output			sd_we_n,	// write enable
	output			sd_ras_n,	// row address select
	output			sd_cas_n,	// columns address select
	output reg		sd_ready = 0,	// sd ready.

	// cpu/chipset interface

	input          	wb_clk,     // 32MHz chipset clock to which sdram state machine is synchonized	
	input	[31:0]	wb_dat_i,	// data input from chipset/cpu
	output reg[31:0]wb_dat_o = 0,	// data output to chipset/cpu
	output	reg		wb_ack = 0, 
	input	[23:0]	wb_adr,		// lower 2 bits are ignored.
	input	[3:0]	wb_sel,		// 
	input	[2:0]	wb_cti,		// cycle type. 
	input			wb_stb, 	//	
	input			wb_cyc, 	// cpu/chipset requests cycle
	input			wb_we   	// cpu/chipset requests write
);

`include "sdram_defines.v"

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 

reg [3:0]	t;
reg [4:0]	reset;

reg[31:0]	sd_dat	  = 0;	// data output to chipset/cpu
reg[31:0]	sd_dat_nxt = 0;	// data output to chipset/cpu

reg			sd_stb 	= 1'b0; // copy of the wishbone bus signal.
reg			sd_we 	= 1'b0; // copy of the wishbone bus signal.
reg			sd_cyc 	= 1'b0; // copy of the wishbone bus signal.
reg			sd_burst = 1'b0;

reg	[3:0]	sd_cycle= 4'd0;
reg			sd_done = 1'b0;

reg [3:0] 	sd_cmd 	= 4'd0;   // current command sent to sd ram

reg [9:0]	sd_refresh = 10'd0;
reg			sd_auto_refresh = 1'b0; 

wire 		sd_reading;
wire		sd_writing;

initial begin 
	t			= 4'd0;
	reset 		= 5'h1f;
	sd_addr		= 13'd0;
	sd_cmd 		= CMD_INHIBIT;
end

localparam CYCLE_RAS_START = 4'd1;  
localparam CYCLE_RFSH_START = CYCLE_RAS_START; 
localparam CYCLE_CAS0 		= CYCLE_RFSH_START  + RASCAS_DELAY; 
localparam CYCLE_CAS1 		= CYCLE_CAS0 + 4'd1;		
localparam CYCLE_CAS2 		= CYCLE_CAS1 + 4'd1;		
localparam CYCLE_CAS3 		= CYCLE_CAS2 + 4'd1;				
localparam CYCLE_READ0	   	= CYCLE_CAS0 + CAS_LATENCY + 4'd1;
localparam CYCLE_READ1	   	= CYCLE_READ0+ 1'd1;
localparam CYCLE_READ2	   	= CYCLE_READ1+ 1'd1;
localparam CYCLE_READ3	   	= CYCLE_READ2+ 1'd1;
localparam CYCLE_END	   	= 4'hF;
localparam CYCLE_WR_END		= CYCLE_CAS1 + 4'd4;
localparam CYCLE_RFSH_END	= CYCLE_RFSH_START + RFC_DELAY; 

localparam RAM_CLK		   = 128000000;
localparam REFRESH_PERIOD  = (RAM_CLK / (16 * 8192)) - CYCLE_END;
 
always @(posedge sd_clk) begin 

	if (sd_rst) begin 
		t			<= 4'd0;
		reset 	<= 5'h1f;
		sd_addr	<= 13'd0;
		sd_ready  <= 0;
	end else begin
		sd_dq <= 16'bZZZZZZZZZZZZZZZZ;
		if (!sd_ready) begin
			t <= t + 4'd1;

			if (t ==4'hF) begin 
				reset <= reset - 5'd1;		
			end

			if (t == 4'h0) begin 

				if(reset == 13) begin
					$display("precharging all banks");
					sd_cmd 		<= CMD_PRECHARGE;
					sd_addr[10] 	<= 1'b1;      // precharge all banks
				end

				if(reset == 2) begin
					sd_cmd 		<= CMD_LOAD_MODE;
					sd_addr		<= MODE;
				end

				if(reset == 1) begin
					$display("loading mode");
					sd_cmd 		<= CMD_LOAD_MODE;
					sd_addr		<= MODE;
				end

				if(reset == 0) sd_ready <= 1;
			end
		end else begin
	
			// bring the wishbone bus signal into the ram clock domain.

			sd_we	<= wb_we;
			sd_cmd	<= CMD_INHIBIT;
			if (wb_stb & wb_cyc & ~wb_ack) begin 
				sd_stb	<= wb_stb;
				sd_cyc	<= wb_cyc;
			end

			sd_refresh <= sd_refresh + 9'd1;

			// this is the auto refresh code.
			// it kicks in so that 8192 auto refreshes are 
			// issued in a 64ms period. Other bus operations 
			// are stalled during this period.
			if ((sd_refresh > REFRESH_PERIOD) && (sd_cycle == 4'd0)) begin 
				sd_auto_refresh <= 1'b1;
				sd_refresh		<= 10'd0;
			end else if (sd_auto_refresh) begin 
				// while the cycle is active count.
				sd_cycle <= sd_cycle + 3'd1;
				case (sd_cycle) 
				CYCLE_RFSH_START: begin 
					sd_cmd	<= CMD_AUTO_REFRESH;
				end

				CYCLE_RFSH_END: begin 
					// reset the count.
					sd_auto_refresh <= 1'b0;
					sd_cycle <= 4'd0;
				end
				endcase

			end else if (sd_cyc | (sd_cycle != 0)) begin 

				// while the cycle is active count.
				sd_cycle <= sd_cycle + 3'd1;
				//sd_cmd		<= CMD_NOP;
				case (sd_cycle)
				CYCLE_RAS_START: begin 
					sd_cmd 	<= CMD_ACTIVE;
					sd_addr	<= { 1'b0, wb_adr[20:9] };
					sd_ba 	<= wb_adr[22:21];

					if(sd_reading) begin 
						sd_dqm <= 2'b00;
					end else begin 
						sd_dqm <= 2'b11;
					end
				end

				// this is the first CAS cycle
				CYCLE_CAS0: begin 
					// always, always read on a 32bit boundary and completely ignore the lsb of wb_adr.
					sd_addr <= { 4'b0000, wb_adr[23], wb_adr[8:2], 1'b0 };  // no auto precharge
					sd_dqm		<= ~wb_sel[1:0];

					if (sd_reading) begin 
						sd_cmd <= CMD_READ;
					end else if (sd_writing) begin 
						sd_cmd		<= CMD_WRITE;
						sd_dq	 		<= wb_dat_i[15:0];
					end
				end

				CYCLE_CAS1: begin 
					// now we access the second part of the 32 bit location.
					sd_addr <= { 4'b0010, wb_adr[23], wb_adr[8:2], 1'b1 };  // auto precharge
					sd_dqm		<= ~wb_sel[3:2];
					if (sd_reading) begin 
						sd_cmd <= CMD_READ;
						if (burst_mode & can_burst) begin 
							sd_addr[10] <= 1'b0;
							sd_burst <= 1'b1; 
						end
					end else if (sd_writing) begin 
						sd_cmd		<= CMD_WRITE;
						sd_dq 		<= wb_dat_i[31:16];
						sd_done		<= 1'b1;
					end 
				end
				
				CYCLE_CAS2: begin 
					if (sd_burst) begin 
						// always, always read on a 32bit boundary and completely ignore the lsb of wb_adr.
						sd_addr <= { 4'b0000, wb_adr[23], wb_adr[8:3], 2'b10 };  // no auto precharge
						sd_dqm		<= ~wb_sel[1:0];
						if (sd_reading) begin 
							sd_cmd <= CMD_READ;
						end  
					end
				end

				CYCLE_CAS3: begin 
					if (sd_burst) begin 
						// always, always read on a 32bit boundary and completely ignore the lsb of wb_adr.
						sd_addr	<= { 4'b0010, wb_adr[23], wb_adr[8:3], 2'b11 };  // no auto precharge
						sd_dqm	<= ~wb_sel[3:2];
						if (sd_reading) begin 
							sd_cmd <= CMD_READ;
						end  
					end
				end

				CYCLE_READ0: begin 
					if (sd_writing) begin
						// if we are writing then the sd_done signal has been high for 
						// enough clock cycles. we can end the cycle here. 
						sd_done <= 1'b0;
						sd_cycle <= 4'd0;
						sd_cyc <= 1'b0;
						sd_stb <= 1'b0;
					end
					if (sd_reading) begin 
					        sd_dat[15:0] <= sd_dq;
					end 
				end

				CYCLE_READ1: begin 
					if (sd_reading) begin 
						sd_dat[31:16] <= sd_dq;
						sd_done			<= 1'b1;
					end
				end

				CYCLE_READ2: begin 
					if (sd_reading) begin 
						sd_dat_nxt[15:0] <= sd_dq;
					end
				end

				CYCLE_READ3: begin 
					if (sd_reading) begin 
						sd_dat_nxt[31:16] <= sd_dq;
					end
				end

				CYCLE_END: begin 
					sd_burst <= 1'b0;
					sd_done 	<= 1'b0;
					sd_cyc <= 1'b0;
					sd_stb <= 1'b0;
				end
				endcase
			end else begin
				sd_done		<= 1'd0;
				sd_cycle 	<= 4'd0;
				sd_burst <= 1'b0;
			end
		end
	end
end

reg wb_burst;

always @(posedge wb_clk) begin 
	
	wb_ack	<= sd_done & ~wb_ack;
	
	if (wb_stb & wb_cyc) begin 
	
		if (sd_done & ~wb_ack) begin 
	
			wb_dat_o <= sd_dat;
			wb_burst <= burst_mode;
	
		end
		
		if (wb_ack & wb_burst) begin 
		
			wb_ack	<= 1'b1;
			wb_burst	<= 1'b0;
			wb_dat_o <= sd_dat_nxt;
			
		end 
		
	
	end else begin 
	
		wb_burst <= 1'b0;
	
	end

		
end

assign burst_mode = wb_cti == 3'b010;
assign can_burst = wb_adr[2] === 1'b0;
assign sd_reading = sd_stb & sd_cyc & ~sd_we;
assign sd_writing = sd_stb & sd_cyc & sd_we;

// drive control signals according to current command
assign sd_cs_n  = sd_cmd[3];
assign sd_ras_n = sd_cmd[2];
assign sd_cas_n = sd_cmd[1];
assign sd_we_n  = sd_cmd[0];
assign sd_cke	= 1'b1;

endmodule
