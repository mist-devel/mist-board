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

	input      		   SPI_SCK,
	input      		   CONF_DATA0,
	output reg        SPI_DO,
	input      		   SPI_DI,
	
	output reg  [7:0] joystick_0,
	output reg  [7:0] joystick_1,
	output reg [15:0] joystick_analog_0,
	output reg [15:0] joystick_analog_1,
	output      [1:0] buttons,
	output      [1:0] switches,
	output  				scandoubler_disable,
	output  				ypbpr,

	output reg [7:0]  status,

	// connection to sd card emulation
	input      [31:0] sd_lba,
	input             sd_rd,
	input             sd_wr,
	output reg	      sd_ack,
	input             sd_conf,
	input             sd_sdhc,
	output reg [7:0]  sd_dout,
	output reg	      sd_dout_strobe,
	input [7:0]       sd_din,
	output reg 	      sd_din_strobe,
	output            sd_mounted,
	

	// ps2 keyboard emulation
	input 	  		   ps2_clk,				// 12-16khz provided by core
	output	 		   ps2_kbd_clk,
	output reg 		   ps2_kbd_data,
	output	 		   ps2_mouse_clk,
	output reg 		   ps2_mouse_data,

	// serial com port 
	input [7:0]		   serial_data,
	input				   serial_strobe
);

reg [6:0] sbuf;
reg [7:0] cmd;
reg [2:0] bit_cnt;    // counts bits 0-7 0-7 ...
reg [7:0] byte_cnt;   // counts bytes
reg [7:0] but_sw;
reg [2:0] stick_idx;

reg    mount_strobe = 1'b0;
assign sd_mounted   = mount_strobe;

assign buttons = but_sw[1:0];
assign switches = but_sw[3:2];
assign scandoubler_disable = but_sw[4];
assign ypbpr = but_sw[5];

wire [7:0] dout = { sbuf, SPI_DI};

// this variant of user_io is for 8 bit cores (type == a4) only
wire [7:0] core_type = 8'ha4;

// command byte read by the io controller
wire [7:0] sd_cmd = { 4'h5, sd_conf, sd_sdhc, sd_wr, sd_rd };

// drive MISO only when transmitting core id
always@(negedge SPI_SCK or posedge CONF_DATA0) begin
	if(CONF_DATA0 == 1) begin
	   SPI_DO <= 1'bZ;
	end else begin

		// first byte returned is always core type, further bytes are 
		// command dependent
      if(byte_cnt == 0) begin
		  SPI_DO <= core_type[~bit_cnt];

		end else begin
			// reading serial fifo
		   if(cmd == 8'h1b) begin
				// send alternating flag byte and data
				if(byte_cnt[0]) 	SPI_DO <= serial_out_status[~bit_cnt];
				else					SPI_DO <= serial_out_byte[~bit_cnt];
			end
			
			// reading config string
		   else if(cmd == 8'h14) begin
				// returning a byte from string
				if(byte_cnt < STRLEN + 1)
					SPI_DO <= conf_str[{STRLEN - byte_cnt,~bit_cnt}];
				else
					SPI_DO <= 1'b0;
			end
			
			// reading sd card status
		   else if(cmd == 8'h16) begin
				if(byte_cnt == 1)
					SPI_DO <= sd_cmd[~bit_cnt];
				else if((byte_cnt >= 2) && (byte_cnt < 6))
					SPI_DO <= sd_lba[{5-byte_cnt, ~bit_cnt}];
				else
					SPI_DO <= 1'b0;
			end
			
			// reading sd card write data
		   else if(cmd == 8'h18)
				SPI_DO <= sd_din[~bit_cnt];
				
			else
				SPI_DO <= 1'b0;
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
		ps2_kbd_rptr <= ps2_kbd_rptr + 3'd1;

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
		ps2_mouse_rptr <= ps2_mouse_rptr + 3'd1;

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
		serial_out_wptr <= serial_out_wptr + 6'd1;
	end
end 

always@(negedge SPI_SCK or posedge status[0]) begin
	if(status[0] == 1) begin
		serial_out_rptr <= 0;
	end else begin
		if((byte_cnt != 0) && (cmd == 8'h1b)) begin
			// read last bit -> advance read pointer
			if((bit_cnt == 7) && !byte_cnt[0] && serial_out_data_available)
				serial_out_rptr <= serial_out_rptr + 6'd1;
		end
	end
end

// SPI receiver
always@(posedge SPI_SCK or posedge CONF_DATA0) begin

	if(CONF_DATA0 == 1) begin
	   bit_cnt <= 3'd0;
	   byte_cnt <= 8'd0;
		sd_ack <= 1'b0;
		sd_dout_strobe <= 1'b0;
		sd_din_strobe <= 1'b0;
	end else begin
		sd_dout_strobe <= 1'b0;
		sd_din_strobe <= 1'b0;
		
		sbuf <= dout[6:0];
		bit_cnt <= bit_cnt + 3'd1;

		// finished reading command byte
      if(bit_cnt == 7) begin
			if(byte_cnt != 8'd255) byte_cnt <= byte_cnt + 8'd1;
			if(byte_cnt == 0) begin
				cmd <= dout;
			
				// fetch first byte when sectore FPGA->IO command has been seen
				if(dout == 8'h18)
					sd_din_strobe <= 1'b1;
					
				if((dout == 8'h17) || (dout == 8'h18))
					sd_ack <= 1'b1;

				mount_strobe <= 1'b0;
					
			end else begin
			
				case(cmd)
				// buttons and switches
					8'h01: but_sw <= dout; 
					8'h02: joystick_0 <= dout;
					8'h03: joystick_1 <= dout;

					// store incoming ps2 mouse bytes 
					8'h04: begin
							ps2_mouse_fifo[ps2_mouse_wptr] <= dout; 
							ps2_mouse_wptr <= ps2_mouse_wptr + 3'd1;
						end

					// store incoming ps2 keyboard bytes 
					8'h05: begin
							ps2_kbd_fifo[ps2_kbd_wptr] <= dout; 
							ps2_kbd_wptr <= ps2_kbd_wptr + 3'd1;
						end
				
					8'h15: status <= dout;
				
					// send SD config IO -> FPGA
					// flag that download begins
					// sd card knows data is config if sd_dout_strobe is asserted
					// with sd_ack still being inactive (low)
					8'h19,
					// send sector IO -> FPGA
					// flag that download begins
					8'h17: begin 
							sd_dout        <= dout;
							sd_dout_strobe <= 1'b1;
						end
				
					// send sector FPGA -> IO
					8'h18: sd_din_strobe <= 1'b1;
				
					// joystick analog
					8'h1a: begin
							// first byte is joystick index
							if(byte_cnt == 1) stick_idx <= dout[2:0];
							else if(byte_cnt == 2) begin
								// second byte is x axis
								if(stick_idx == 0) joystick_analog_0[15:8] <= dout;
									else if(stick_idx == 1) joystick_analog_1[15:8] <= dout;
							end else if(byte_cnt == 3) begin
								// third byte is y axis
								if(stick_idx == 0) joystick_analog_0[7:0] <= dout;
									else if(stick_idx == 1) joystick_analog_1[7:0] <= dout;
							end
						end

					// notify image selection
					8'h1c: mount_strobe <= 1'b1;

					default: ;
				endcase
			end
		end
	end
end
   
endmodule
