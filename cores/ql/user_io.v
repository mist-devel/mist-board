//
// user_io.v - interface to MIST arm io controller
//
// Sinclair QL for the MiST
// https://github.com/mist-devel
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

// parameter STRLEN and the actual length of conf_str have to match
 
module user_io #(parameter STRLEN=0) (
	input [(8*STRLEN)-1:0] conf_str,

	input      		SPI_CLK,
	input      		SPI_SS_IO,
	output     		reg SPI_MISO,
	input      		SPI_MOSI,
	
	output reg [7:0] 	joystick_0,
	output reg [7:0] 	joystick_1,
	output reg [15:0] joystick_analog_0,
	output reg [15:0] joystick_analog_1,
	output [1:0] 		buttons,
	output [1:0] 		switches,
	output  				scandoubler_disable,

	output reg [7:0]   status,

	// connection to sd card emulation
	input [31:0]  sd_lba,
	input         sd_rd,
	input         sd_wr,
	output reg	  sd_ack,
	input         sd_conf,
	input         sd_sdhc,
	output [7:0]  sd_dout,  // valid on rising edge of sd_dout_strobe
	output reg	  sd_dout_strobe,
	input [7:0]   sd_din,
	output reg 	  sd_din_strobe,
	output reg    sd_change,

	// ps2 keyboard emulation
	input 	  		ps2_clk,				// 12-16khz provided by core
	output	 		ps2_kbd_clk,
	output reg 		ps2_kbd_data,
	output	 		ps2_mouse_clk,
	output reg 		ps2_mouse_data,

	// serial com port 
	input [7:0]		serial_data,
	input				serial_strobe
);

reg [6:0]         sbuf;
reg [7:0]         cmd;
reg [2:0] 	      bit_cnt;    // counts bits 0-7 0-7 ...
reg [7:0]         byte_cnt;   // counts bytes
reg [5:0]         joystick0;
reg [5:0]         joystick1;
reg [7:0] 	      but_sw;
reg [2:0]         stick_idx;

assign buttons = but_sw[1:0];
assign switches = but_sw[3:2];
assign scandoubler_disable = but_sw[4];
assign sd_dout = { sbuf, SPI_MOSI};

// this variant of user_io is for 8 bit cores (type == a4) only
wire [7:0] core_type = 8'ha4;

// command byte read by the io controller
wire [7:0] sd_cmd = { 4'h5, sd_conf, sd_sdhc, sd_wr, sd_rd };

// filter spi clock. the 8 bit gate delay is ~2.5ns in total
wire [7:0] spi_sck_D = { spi_sck_D[6:0], SPI_CLK } /* synthesis keep */;
wire spi_sck = (spi_sck && spi_sck_D != 8'h00) || (!spi_sck && spi_sck_D == 8'hff);

// drive MISO only when transmitting core id
always@(negedge spi_sck or posedge SPI_SS_IO) begin
	if(SPI_SS_IO == 1) begin
	   SPI_MISO <= 1'bZ;
	end else begin

		// first byte returned is always core type, further bytes are 
		// command dependent
      if(byte_cnt == 0) begin
		  SPI_MISO <= core_type[~bit_cnt];

		end else begin
			// reading serial fifo
		   if(cmd == 8'h1b) begin
				// send alternating flag byte and data
				if(byte_cnt[0]) 	SPI_MISO <= serial_out_status[~bit_cnt];
				else					SPI_MISO <= serial_out_byte[~bit_cnt];
			end
			
			// reading config string
		   else if(cmd == 8'h14) begin
				// returning a byte from string
				if(byte_cnt < STRLEN + 1)
					SPI_MISO <= conf_str[{STRLEN - byte_cnt,~bit_cnt}];
				else
					SPI_MISO <= 1'b0;
			end
			
			// reading sd card status
		   else if(cmd == 8'h16) begin
				if(byte_cnt == 1)
					SPI_MISO <= sd_cmd[~bit_cnt];
				else if((byte_cnt >= 2) && (byte_cnt < 6))
					SPI_MISO <= sd_lba[{5-byte_cnt, ~bit_cnt}];
				else
					SPI_MISO <= 1'b0;
			end
			
			// reading sd card write data
		   else if(cmd == 8'h18)
				SPI_MISO <= sd_din[~bit_cnt];
				
			else
				SPI_MISO <= 1'b0;
		end
   end
end

// ---------------- PS2 ---------------------

// 8 byte fifos to store ps2 bytes
localparam PS2_FIFO_BITS = 3;

// keyboard
reg [7:0] ps2_kbd_fifo [(2**PS2_FIFO_BITS)-1:0];
reg [PS2_FIFO_BITS-1:0] ps2_kbd_wptr;
reg [PS2_FIFO_BITS-1:0] ps2_kbd_rptr;

// ps2 transmitter state machine
reg [3:0] ps2_kbd_tx_state;
reg [7:0] ps2_kbd_tx_byte;
reg ps2_kbd_parity;

assign ps2_kbd_clk = ps2_clk || (ps2_kbd_tx_state == 0);

// ps2 transmitter
// Takes a byte from the FIFO and sends it in a ps2 compliant serial format.
reg ps2_kbd_r_inc;
always@(posedge ps2_clk) begin
	ps2_kbd_r_inc <= 1'b0;
	
	if(ps2_kbd_r_inc)
		ps2_kbd_rptr <= ps2_kbd_rptr + 1;

	// transmitter is idle?
	if(ps2_kbd_tx_state == 0) begin
		// data in fifo present?
		if(ps2_kbd_wptr != ps2_kbd_rptr) begin
			// load tx register from fifo
			ps2_kbd_tx_byte <= ps2_kbd_fifo[ps2_kbd_rptr];
			ps2_kbd_r_inc <= 1'b1;
			
			// reset parity
			ps2_kbd_parity <= 1'b1;
			
			// start transmitter
			ps2_kbd_tx_state <= 4'd1;

			// put start bit on data line
			ps2_kbd_data <= 1'b0;			// start bit is 0
		end
	end else begin
	
		// transmission of 8 data bits
		if((ps2_kbd_tx_state >= 1)&&(ps2_kbd_tx_state < 9)) begin
			ps2_kbd_data <= ps2_kbd_tx_byte[0];			  // data bits
			ps2_kbd_tx_byte[6:0] <= ps2_kbd_tx_byte[7:1]; // shift down
			if(ps2_kbd_tx_byte[0]) 
				ps2_kbd_parity <= !ps2_kbd_parity;
		end

		// transmission of parity
		if(ps2_kbd_tx_state == 9)
			ps2_kbd_data <= ps2_kbd_parity;
			
		// transmission of stop bit
		if(ps2_kbd_tx_state == 10)
			ps2_kbd_data <= 1'b1;			// stop bit is 1

		// advance state machine
		if(ps2_kbd_tx_state < 11)
			ps2_kbd_tx_state <= ps2_kbd_tx_state + 4'd1;
		else	
			ps2_kbd_tx_state <= 4'd0;
	
	end
end
  
// mouse
reg [7:0] ps2_mouse_fifo [(2**PS2_FIFO_BITS)-1:0];
reg [PS2_FIFO_BITS-1:0] ps2_mouse_wptr;
reg [PS2_FIFO_BITS-1:0] ps2_mouse_rptr;

// ps2 transmitter state machine
reg [3:0] ps2_mouse_tx_state;
reg [7:0] ps2_mouse_tx_byte;
reg ps2_mouse_parity;

assign ps2_mouse_clk = ps2_clk || (ps2_mouse_tx_state == 0);

// ps2 transmitter
// Takes a byte from the FIFO and sends it in a ps2 compliant serial format.
reg ps2_mouse_r_inc;
always@(posedge ps2_clk) begin
	ps2_mouse_r_inc <= 1'b0;
	
	if(ps2_mouse_r_inc)
		ps2_mouse_rptr <= ps2_mouse_rptr + 1;

	// transmitter is idle?
	if(ps2_mouse_tx_state == 0) begin
		// data in fifo present?
		if(ps2_mouse_wptr != ps2_mouse_rptr) begin
			// load tx register from fifo
			ps2_mouse_tx_byte <= ps2_mouse_fifo[ps2_mouse_rptr];
			ps2_mouse_r_inc <= 1'b1;
			
			// reset parity
			ps2_mouse_parity <= 1'b1;
			
			// start transmitter
			ps2_mouse_tx_state <= 4'd1;

			// put start bit on data line
			ps2_mouse_data <= 1'b0;			// start bit is 0
		end
	end else begin
	
		// transmission of 8 data bits
		if((ps2_mouse_tx_state >= 1)&&(ps2_mouse_tx_state < 9)) begin
			ps2_mouse_data <= ps2_mouse_tx_byte[0];			  // data bits
			ps2_mouse_tx_byte[6:0] <= ps2_mouse_tx_byte[7:1]; // shift down
			if(ps2_mouse_tx_byte[0]) 
				ps2_mouse_parity <= !ps2_mouse_parity;
		end

		// transmission of parity
		if(ps2_mouse_tx_state == 9)
			ps2_mouse_data <= ps2_mouse_parity;
			
		// transmission of stop bit
		if(ps2_mouse_tx_state == 10)
			ps2_mouse_data <= 1'b1;			// stop bit is 1

		// advance state machine
		if(ps2_mouse_tx_state < 11)
			ps2_mouse_tx_state <= ps2_mouse_tx_state + 4'd1;
		else	
			ps2_mouse_tx_state <= 4'd0;
	
	end
end

// fifo to receive serial data from core to be forwarded to io controller

// 16 byte fifo to store serial bytes
localparam SERIAL_OUT_FIFO_BITS = 6;
reg [7:0] serial_out_fifo [(2**SERIAL_OUT_FIFO_BITS)-1:0];
reg [SERIAL_OUT_FIFO_BITS-1:0] serial_out_wptr;
reg [SERIAL_OUT_FIFO_BITS-1:0] serial_out_rptr;
 
wire serial_out_data_available = serial_out_wptr != serial_out_rptr;
wire [7:0] serial_out_byte = serial_out_fifo[serial_out_rptr] /* synthesis keep */;
wire [7:0] serial_out_status = { 7'b1000000, serial_out_data_available};

// status[0] is reset signal from io controller and is thus used to flush
// the fifo
always @(posedge serial_strobe or posedge status[0]) begin
	if(status[0] == 1) begin
		serial_out_wptr <= 0;
	end else begin 
		serial_out_fifo[serial_out_wptr] <= serial_data;
		serial_out_wptr <= serial_out_wptr + 1;
	end
end 

always@(negedge spi_sck or posedge status[0]) begin
	if(status[0] == 1) begin
		serial_out_rptr <= 0;
	end else begin
		if((byte_cnt != 0) && (cmd == 8'h1b)) begin
			// read last bit -> advance read pointer
			if((bit_cnt == 7) && !byte_cnt[0] && serial_out_data_available)
				serial_out_rptr <= serial_out_rptr + 1;
		end
	end
end

// SPI receiver
always@(posedge spi_sck or posedge SPI_SS_IO) begin

	if(SPI_SS_IO == 1) begin
	   bit_cnt <= 3'd0;
	   byte_cnt <= 8'd0;
		sd_ack <= 1'b0;
		sd_dout_strobe <= 1'b0;
		sd_din_strobe <= 1'b0;
		sd_change <= 1'b0;
	end else begin
		sd_dout_strobe <= 1'b0;
		sd_din_strobe <= 1'b0;
		
		if(bit_cnt != 7)
			sbuf[6:0] <= { sbuf[5:0], SPI_MOSI };
			
		bit_cnt <= bit_cnt + 3'd1;
		if((bit_cnt == 7)&&(byte_cnt != 8'd255)) 
			byte_cnt <= byte_cnt + 8'd1;

		// finished reading command byte
      if(bit_cnt == 7) begin
			if(byte_cnt == 0) begin
				cmd <= { sbuf, SPI_MOSI};
			
				// fetch first byte when sectore FPGA->IO command has been seen
				if({ sbuf, SPI_MOSI} == 8'h18)
					sd_din_strobe <= 1'b1;
					
				if(({ sbuf, SPI_MOSI} == 8'h17) || ({ sbuf, SPI_MOSI} == 8'h18))
					sd_ack <= 1'b1;
					
			end else begin
			
				// buttons and switches
				if(cmd == 8'h01)
					but_sw <= { sbuf, SPI_MOSI }; 

				if(cmd == 8'h02)
					joystick_0 <= { sbuf, SPI_MOSI };
				 
				if(cmd == 8'h03)
					joystick_1 <= { sbuf, SPI_MOSI };
				 
				if(cmd == 8'h04) begin
					// store incoming ps2 mouse bytes 
					ps2_mouse_fifo[ps2_mouse_wptr] <= { sbuf, SPI_MOSI }; 
					ps2_mouse_wptr <= ps2_mouse_wptr + 1;
				end

				if(cmd == 8'h05) begin
					// store incoming ps2 keyboard bytes 
					ps2_kbd_fifo[ps2_kbd_wptr] <= { sbuf, SPI_MOSI }; 
					ps2_kbd_wptr <= ps2_kbd_wptr + 1;
				end
				
				if(cmd == 8'h15)
					status <= { sbuf[6:0], SPI_MOSI };
				
				// send sector IO -> FPGA
				if(cmd == 8'h17) begin
					// flag that download begins
					sd_dout_strobe <= 1'b1;
				end
				
				// send sector FPGA -> IO
				if(cmd == 8'h18)
					sd_din_strobe <= 1'b1;
				
				// send SD config IO -> FPGA
				if(cmd == 8'h19) begin
					// flag that download begins
					// sd card knows data is config if sd_dout_strobe is asserted
					// with sd_ack still being inactive (low)
					sd_dout_strobe <= 1'b1;
				end
				
				// joystick analog
				if(cmd == 8'h1a) begin
					// first byte is joystick indes
					if(byte_cnt == 1)
						stick_idx <= { sbuf[1:0], SPI_MOSI };
					else if(byte_cnt == 2) begin
						// second byte is x axis
						if(stick_idx == 0)
							joystick_analog_0[15:8] <= { sbuf, SPI_MOSI };
						else if(stick_idx == 1)
							joystick_analog_1[15:8] <= { sbuf, SPI_MOSI };
					end else if(byte_cnt == 3) begin
						// third byte is y axis
						if(stick_idx == 0)
							joystick_analog_0[7:0] <= { sbuf, SPI_MOSI };
						else if(stick_idx == 1)
							joystick_analog_1[7:0] <= { sbuf, SPI_MOSI };
					end
				end
				
				// set sd card status. The fact that this register is being	
				// set by the arm controller indicates a possible disk change
				if(cmd == 8'h1c)
					sd_change <= 1'b1;

			end
		end
	end
end
   
endmodule
