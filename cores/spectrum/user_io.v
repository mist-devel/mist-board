//
// user_io.v
//
// user_io for the MiST board
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
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

// parameter STRLEN and the actual length of conf_str have to match

module user_io #(parameter STRLEN=0) (
	input [(8*STRLEN)-1:0] conf_str,

	input      		SPI_CLK,
	input      		SPI_SS_IO,
	output     		reg SPI_MISO,
	input      		SPI_MOSI,
	
	output [5:0] 	JOY0,
	output [5:0] 	JOY1,
	output [1:0] 	BUTTONS,
	output [1:0] 	SWITCHES,

	output reg [7:0]   status,
		
	input 	  		clk,
	output	 		ps2_clk,
	output reg 		ps2_data
);

reg [6:0]         sbuf;
reg [7:0]         cmd;
reg [2:0] 	      bit_cnt;    // counts bits 0-7 0-7 ...
reg [7:0]         byte_cnt;   // counts bytes
reg [5:0]         joystick0;
reg [5:0]         joystick1;
reg [3:0] 	      but_sw;

assign JOY0 = joystick0;
assign JOY1 = joystick1;
assign BUTTONS = but_sw[1:0];
assign SWITCHES = but_sw[3:2];

// this variant of user_io is for 8 bit cores (type == a4) only
wire [7:0] core_type = 8'ha4;

// drive MISO only when transmitting core id
always@(negedge SPI_CLK or posedge SPI_SS_IO) begin
	if(SPI_SS_IO == 1) begin
	   SPI_MISO <= 1'bZ;
	end else begin
		// first byte returned is always core type, further bytes are 
		// command dependent
      if(byte_cnt == 0) begin
		  SPI_MISO <= core_type[~bit_cnt];
		end else begin
			// reading config string
		   if(cmd == 8'h14) begin
				// returning a byte from string
				if(byte_cnt < STRLEN + 1)
					SPI_MISO <= conf_str[{STRLEN - byte_cnt,~bit_cnt}];
				else
					SPI_MISO <= 1'b0;
			end
		end
   end
end

// 8 byte fifo to store ps2 bytes
localparam PS2_FIFO_BITS = 3;
reg [7:0] ps2_fifo [(2**PS2_FIFO_BITS)-1:0];
reg [PS2_FIFO_BITS-1:0] ps2_wptr;
reg [PS2_FIFO_BITS-1:0] ps2_rptr;

// ps2 transmitter state machine
reg [3:0] ps2_tx_state;
reg [7:0] ps2_tx_byte;
reg ps2_parity;

assign ps2_clk = clk || (ps2_tx_state == 0);

// ps2 transmitter
// Takes a byte from the FIFO and sends it in a ps2 compliant serial format.
reg ps2_r_inc;
always@(posedge clk) begin
	ps2_r_inc <= 1'b0;
	
	if(ps2_r_inc)
		ps2_rptr <= ps2_rptr + 1;

	// transmitter is idle?
	if(ps2_tx_state == 0) begin
		// data in fifo present?
		if(ps2_wptr != ps2_rptr) begin
			// load tx register from fifo
			ps2_tx_byte <= ps2_fifo[ps2_rptr];
			ps2_r_inc <= 1'b1;
			
			// reset parity
			ps2_parity <= 1'b1;
			
			// start transmitter
			ps2_tx_state <= 4'd1;

			// put start bit on data line
			ps2_data <= 1'b0;			// start bit is 0
		end
	end else begin
	
		// transmission of 8 data bits
		if((ps2_tx_state >= 1)&&(ps2_tx_state < 9)) begin
			ps2_data <= ps2_tx_byte[0];			  // data bits
			ps2_tx_byte[6:0] <= ps2_tx_byte[7:1]; // shift down
			if(ps2_tx_byte[0]) 
				ps2_parity <= !ps2_parity;
		end

		// transmission of parity
		if(ps2_tx_state == 9)
			ps2_data <= ps2_parity;
			
		// transmission of stop bit
		if(ps2_tx_state == 10)
			ps2_data <= 1'b1;			// stop bit is 1

		// advance state machine
		if(ps2_tx_state < 11)
			ps2_tx_state <= ps2_tx_state + 4'd1;
		else	
			ps2_tx_state <= 4'd0;
	
	end
end

// SPI receiver
always@(posedge SPI_CLK or posedge SPI_SS_IO) begin

	if(SPI_SS_IO == 1) begin
	   bit_cnt <= 3'd0;
	   byte_cnt <= 8'd0;
	end else begin
		sbuf[6:0] <= { sbuf[5:0], SPI_MOSI };
		bit_cnt <= bit_cnt + 3'd1;
		if(bit_cnt == 7) byte_cnt <= byte_cnt + 8'd1;

		// finished reading command byte
      if(bit_cnt == 7) begin
			if(byte_cnt == 0)
				cmd <= { sbuf, SPI_MOSI};

			if(byte_cnt != 0) begin
				if(cmd == 8'h01)
					but_sw <= { sbuf[2:0], SPI_MOSI }; 

				if(cmd == 8'h02)
					joystick0 <= { sbuf[4:0], SPI_MOSI };
				 
				if(cmd == 8'h03)
					joystick1 <= { sbuf[4:0], SPI_MOSI };
				 
				if(cmd == 8'h05) begin
					// store incoming keyboard bytes in 
					ps2_fifo[ps2_wptr] <= { sbuf, SPI_MOSI }; 
					ps2_wptr <= ps2_wptr + 1;
				end
				
				if(cmd == 8'h15) begin
					status <= { sbuf[4:0], SPI_MOSI };
				end
			end
		end
	end
end
   
endmodule
