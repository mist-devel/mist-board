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
	
	output [7:0] 	JOY0,
	output [7:0] 	JOY1,
	output [1:0] 	BUTTONS,
	output [1:0] 	SWITCHES,

	input [7:0]    kbd_out_data,
	input          kbd_out_strobe,
	
	output [7:0]   kbd_in_data,
	output reg     kbd_in_strobe
);

// kbd in data is valid on rising edge of kbd_in_strobe
assign kbd_in_data = { sbuf, SPI_MOSI };

reg [6:0]         sbuf;
reg [7:0]         cmd;
reg [2:0] 	      bit_cnt;    // counts bits 0-7 0-7 ...
reg [7:0]         byte_cnt;   // counts bytes
reg [7:0]         joystick0;
reg [7:0]         joystick1;
reg [3:0] 	      but_sw;

assign JOY0 = joystick0;
assign JOY1 = joystick1;
assign BUTTONS = but_sw[1:0];
assign SWITCHES = but_sw[3:2];

// this variant of user_io is for the achie core (type == a6) only
wire [7:0] core_type = 8'ha6;

reg kbd_out_data_available;
always @(posedge kbd_out_strobe or posedge kbd_out_ack) begin
	if(kbd_out_ack)  kbd_out_data_available <= 1'b0;
	else             kbd_out_data_available <= 1'b1;
end

wire [7:0] kbd_out_status = { 4'ha, 3'b000, kbd_out_data_available };

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
			// reading keyboard data
		   if(cmd == 8'h04) begin
				if(byte_cnt == 1)	SPI_MISO <= kbd_out_status[~bit_cnt];
				else					SPI_MISO <= kbd_out_data[~bit_cnt];
			end
			
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

// SPI receiver
reg kbd_out_ack;
always@(posedge SPI_CLK or posedge SPI_SS_IO) begin

	if(SPI_SS_IO == 1) begin
	   bit_cnt <= 3'd0;
	   byte_cnt <= 8'd0;
		kbd_out_ack <= 1'b0;
		kbd_in_strobe <= 1'b0;
	end else begin
		kbd_out_ack <= 1'b0;
		kbd_in_strobe <= 1'b0;

		bit_cnt <= bit_cnt + 3'd1;
		if(bit_cnt == 7) byte_cnt <= byte_cnt + 8'd1;
		else       		  sbuf[6:0] <= { sbuf[5:0], SPI_MOSI };

		// finished reading command byte
      if(bit_cnt == 7) begin
			if(byte_cnt == 0)
				cmd <= { sbuf, SPI_MOSI};

			if(byte_cnt != 0) begin
			
				if(cmd == 8'h01)
					but_sw <= { sbuf[2:0], SPI_MOSI }; 

				if(cmd == 8'h02)
					joystick0 <= { sbuf, SPI_MOSI };
				 
				if(cmd == 8'h03)
					joystick1 <= { sbuf, SPI_MOSI };
					
				// KBD_OUT status byte has been read
				if((cmd == 8'h04) && (byte_cnt == 1))
					kbd_out_ack <= 1'b1;
					
				// KBD_IN data byte
				if((cmd == 8'h05) && (byte_cnt == 1))
					kbd_in_strobe <= 1'b1;
			end
		end
	end
end
   
endmodule
