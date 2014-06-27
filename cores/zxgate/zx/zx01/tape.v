//
// tape.v
//
// ZX81 tape implementation for the MiST board
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

module tape(
	input       sck,
   input       ss,
   input  		sdi,
	
	input			clk,      // 500kHz
	input 		play,     // "press play on tape"
	output reg	tape_out
);

// create clock to be used for signaltap
reg [7:0] tape_clk /* synthesis noprune */;
always @(posedge clk) 	
	tape_clk <= tape_clk + 8'd1;

// tape bit timing
// 0 bit = /\/\/\/\_________   (4* 150us H + 150us L + 1300us L)
// 1 bit = /\/\/\/\/\/\/\/\/\_____________

// 0 = idle, 1 = 1300us low, 2/4/6/../18 = 150us high, 3/5/7/../19 = 150us L
reg [4:0] pulse_state;

// 150us = 75 cycles @ 500kHz
// 1300us = 650 cycles @ 500kHz
reg [9:0] pulse_cnt;  // 10 bit = 1024 max range

reg bit_done;

// generate bit timing
always @(posedge clk) begin
	bit_done <= 1'b0;

	if(pulse_cnt == 0) begin
		// end of idle state, start new bit
		if(pulse_state == 0) begin
			if(bit_start) begin
				tape_out <= 1'b1;
				pulse_state <= bit?5'd19:5'd9;
				pulse_cnt <= 10'd74;
			end
		end
			
		// end of 1300us seperator phase
		else if(pulse_state == 1) begin
			tape_out <= 1'b0;
			pulse_state <= 5'd0;
			pulse_cnt <= 10'd0;
			bit_done <= 1'b1;
		end
			
		// end of last high phase
		else if(pulse_state == 2) begin
			tape_out <= 1'b0;
			pulse_state <= 5'd1;
			pulse_cnt <= 10'd649;
		end
		
		// end of normal pulse hi/lo phase
		else if(pulse_state > 2) begin
			// tape level is 1 when coming from state 4,6,8,...
			tape_out <= !pulse_state[0];
			pulse_state <= pulse_state - 5'd1;
			pulse_cnt <= 10'd74;
		end
	
	end else
		pulse_cnt <= pulse_cnt - 10'd1;
end

// bring play signal into local clock domain and 
// generate start signal from it
reg start;
reg playD, playD2;
always @(posedge clk) begin
	start <= 1'b0;
	playD <= play;
	playD2 <= playD;

	if(playD && !playD2)
		start <= 1'b1;
end

// byte transmitter
wire bit = byte[bit_cnt];

// reg [7:0] byte = 8'h55 /* synthesis noprune */;
reg [2:0] bit_cnt;
reg byte_tx_running = 1'b0;
reg bit_in_progress;
reg bit_start;

reg byte_done;

always @(posedge clk) begin
	bit_start <= 1'b0;
	byte_done <= 1'b0;

	// start signal starts a new byte transmission
	if(!byte_tx_running) begin
		if(byte_start) begin
			byte_tx_running <= 1'b1;
			bit_in_progress <= 1'b0;
			bit_cnt <= 3'd7;
		end
	end else begin
		// byte transmission in progress
		
		if(!bit_in_progress) begin
			// start new bit
			bit_start <= 1'b1;
			bit_in_progress <= 1'b1;
		end else begin
			// wait for bit transmission to finish
			if(bit_done) begin
				bit_in_progress <= 1'b0;
				
				if(bit_cnt != 0)
					bit_cnt <= bit_cnt - 3'd1;
				else begin
					byte_tx_running <= 1'b0;
					byte_done <= 1'b1;
				end
			end
		end
	end
end

// byte tx engine
reg [15:0] byte_count;

// 0=idle, 1=filename, 2=file
reg [1:0] byte_state = 2'd0;

reg byte_start;


always @(posedge clk) begin
	byte_start <= 1'b0;

	if(byte_state == 0) begin
		// start transmission if user presses "play". don't do anything if
		// there's no tape data in the buffer
		if(start && (file_size != 0)) begin
			byte_state <= 2'd1;
			
			// transmit the "file name"
			byte_start <= 1'b1;
		end
	end else if(byte_state == 1) begin
		if(byte_done) begin
			byte_state <= 2'd2;
			byte_start <= 1'b1;
			byte_count <= 16'h0000;
		end
	
	end else if(byte_state == 2) begin
		if(byte_done) begin
			if(byte_count != file_size - 16'd1) begin
				byte_count <= byte_count + 16'd1;
				byte_start <= 1'b1;
			end else
				byte_state <= 2'd0;
		end
	end
end

wire [7:0] filename = { 1'b1, 7'h3f}; // 'Z' with end flag
wire [7:0] byte = (byte_state == 1)?filename:ram_data_out;
wire [7:0] ram_data_out;

wire [15:0] file_size; 

// include the io controller connected ram
data_io data_io (
	.sck				( sck						),
	.ss				( ss						),
	.sdi				( sdi						),

	.downloading	(							),
	.size				( file_size          ),

	// ram interface
	.clk				( clk						),
	.we				( 1'b0					),
	.a					( byte_count[10:0] 	),
	.din				( 8'h00					),
	.dout				( ram_data_out			)
);

endmodule