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
 
module user_io #(parameter STRLEN=0, parameter PS2DIV=100) (
	input [(8*STRLEN)-1:0] conf_str,

	input               clk_sys, // clock for system-related messages (kbd, joy, etc...)
	input               clk_sd,  // clock for SD-card related messages

	input               SPI_CLK,
	input               SPI_SS_IO,
	output reg          SPI_MISO,
	input               SPI_MOSI,

	output reg [31:0]   joystick_0,
	output reg [31:0]   joystick_1,
	output reg [31:0]   joystick_2,
	output reg [31:0]   joystick_3,
	output reg [31:0]   joystick_4,
	output reg [15:0]   joystick_analog_0,
	output reg [15:0]   joystick_analog_1,
	output [1:0]        buttons,
	output [1:0]        switches,
	output 		        scandoubler_disable,
	output              ypbpr,
	output reg [31:0]   status,

	// connection to sd card emulation
	input        [31:0] sd_lba,
	input 		        sd_rd,
	input 		        sd_wr,
	output reg 	        sd_ack,
	output reg          sd_ack_conf,
	input 		        sd_conf,
	input 		        sd_sdhc,
	output reg    [7:0] sd_dout, // valid on rising edge of sd_dout_strobe
	output reg 	        sd_dout_strobe,
	input         [7:0] sd_din,
	output reg 	        sd_din_strobe,
	output reg    [8:0] sd_buff_addr,

	output reg          img_mounted, //rising edge if a new image is mounted
	output reg   [31:0] img_size,    // size of image in bytes

	// ps2 keyboard/mouse emulation
	output              ps2_kbd_clk,
	output reg          ps2_kbd_data,
	output              ps2_mouse_clk,
	output reg          ps2_mouse_data,

	// keyboard data
	output reg          key_pressed,  // 1-make (pressed), 0-break (released)
	output reg          key_extended, // extended code
	output reg    [7:0] key_code,     // key scan code
	output reg          key_strobe,   // key data valid

	// mouse data
	output reg    [8:0] mouse_x,
	output reg    [8:0] mouse_y,
	output reg    [7:0] mouse_flags,  // YOvfl, XOvfl, dy8, dx8, 1, mbtn, rbtn, lbtn
	output reg          mouse_strobe, // mouse data is valid on mouse_strobe

	// serial com port 
	input [7:0]         serial_data,
	input               serial_strobe
);

reg [6:0]     sbuf;
reg [7:0]     cmd;
reg [2:0] 	  bit_cnt;    // counts bits 0-7 0-7 ...
reg [9:0]     byte_cnt;   // counts bytes
reg [7:0] 	  but_sw;
reg [2:0]     stick_idx;

assign buttons = but_sw[1:0];
assign switches = but_sw[3:2];
assign scandoubler_disable = but_sw[4];
assign ypbpr = but_sw[5];

// this variant of user_io is for 8 bit cores (type == a4) only
wire [7:0] core_type = 8'ha4;

// command byte read by the io controller
wire [7:0] sd_cmd = { 4'h5, sd_conf, sd_sdhc, sd_wr, sd_rd };

wire spi_sck = SPI_CLK;

// ---------------- PS2 ---------------------
// 8 byte fifos to store ps2 bytes
localparam PS2_FIFO_BITS = 3;

reg ps2_clk;
always @(negedge clk_sys) begin
	integer cnt;
	cnt <= cnt + 1'd1;
	if(cnt == PS2DIV) begin
		ps2_clk <= ~ps2_clk;
		cnt <= 0;
	end
end

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
always@(posedge clk_sys) begin
	reg ps2_clkD;

	ps2_clkD <= ps2_clk;
	if (~ps2_clkD & ps2_clk) begin
		ps2_kbd_r_inc <= 1'b0;

		if(ps2_kbd_r_inc)
			ps2_kbd_rptr <= ps2_kbd_rptr + 1'd1;

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
always@(posedge clk_sys) begin
	reg ps2_clkD;

	ps2_clkD <= ps2_clk;
	if (~ps2_clkD & ps2_clk) begin
		ps2_mouse_r_inc <= 1'b0;

		if(ps2_mouse_r_inc)
			ps2_mouse_rptr <= ps2_mouse_rptr + 1'd1;

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
		serial_out_wptr <= serial_out_wptr + 1'd1;
	end
end 

always@(negedge spi_sck or posedge status[0]) begin
	if(status[0] == 1) begin
		serial_out_rptr <= 0;
	end else begin
		if((byte_cnt != 0) && (cmd == 8'h1b)) begin
			// read last bit -> advance read pointer
			if((bit_cnt == 7) && !byte_cnt[0] && serial_out_data_available)
				serial_out_rptr <= serial_out_rptr + 1'd1;
		end
	end
end


// SPI bit and byte counters
always@(posedge spi_sck or posedge SPI_SS_IO) begin
	if(SPI_SS_IO == 1) begin
		bit_cnt <= 0;
		byte_cnt <= 0;
	end else begin
		if((bit_cnt == 7)&&(~&byte_cnt)) 
			byte_cnt <= byte_cnt + 8'd1;

		bit_cnt <= bit_cnt + 1'd1;
	end
end

// SPI transmitter FPGA -> IO
reg [7:0] spi_byte_out;

always@(negedge spi_sck or posedge SPI_SS_IO) begin
	if(SPI_SS_IO == 1) begin
	   SPI_MISO <= 1'bZ;
	end else begin
		SPI_MISO <= spi_byte_out[~bit_cnt];
	end
end

always@(posedge spi_sck or posedge SPI_SS_IO) begin
	reg [31:0] sd_lba_r;

	if(SPI_SS_IO == 1) begin
		spi_byte_out <= core_type;
	end else begin
		// read the command byte to choose the response
		if(bit_cnt == 7) begin
			if(!byte_cnt) cmd <= {sbuf, SPI_MOSI};

			spi_byte_out <= 0;
			case({(!byte_cnt) ? {sbuf, SPI_MOSI} : cmd})
			// reading config string
			8'h14: if(byte_cnt < STRLEN) spi_byte_out <= conf_str[(STRLEN - byte_cnt - 1)<<3 +:8];

			// reading sd card status
			8'h16: if(byte_cnt == 0) begin
					spi_byte_out <= sd_cmd;
					sd_lba_r <= sd_lba;
				end
				else if(byte_cnt < 5) spi_byte_out <= sd_lba_r[(4-byte_cnt)<<3 +:8];

			// reading sd card write data
			8'h18: spi_byte_out <= sd_din;
			8'h1b:
				// send alternating flag byte and data
				if(byte_cnt[0]) spi_byte_out <= serial_out_status;
				else spi_byte_out <= serial_out_byte;
			endcase
		end
	end
end

// SPI receiver IO -> FPGA

reg       spi_receiver_strobe_r = 0;
reg       spi_transfer_end_r = 1;
reg [7:0] spi_byte_in;

// Read at spi_sck clock domain, assemble bytes for transferring to clk_sys
always@(posedge spi_sck or posedge SPI_SS_IO) begin

	if(SPI_SS_IO == 1) begin
		spi_transfer_end_r <= 1;
	end else begin
		spi_transfer_end_r <= 0;

		if(bit_cnt != 7)
			sbuf[6:0] <= { sbuf[5:0], SPI_MOSI };

		// finished reading a byte, prepare to transfer to clk_sys
		if(bit_cnt == 7) begin
			spi_byte_in <= { sbuf, SPI_MOSI};
			spi_receiver_strobe_r <= ~spi_receiver_strobe_r;
		end
	end
end

// Process bytes from SPI at the clk_sys domain
always @(posedge clk_sys) begin

	reg       spi_receiver_strobe;
	reg       spi_transfer_end;
	reg       spi_receiver_strobeD;
	reg       spi_transfer_endD;
	reg [7:0] acmd;
	reg [7:0] abyte_cnt;   // counts bytes

	reg [7:0] mouse_flags_r;
	reg [7:0] mouse_x_r;

	reg       key_pressed_r;
	reg       key_extended_r;

	//synchronize between SPI and sys clock domains
	spi_receiver_strobeD <= spi_receiver_strobe_r;
	spi_receiver_strobe <= spi_receiver_strobeD;
	spi_transfer_endD	<= spi_transfer_end_r;
	spi_transfer_end	<= spi_transfer_endD;

	key_strobe <= 0;
	mouse_strobe <= 0;

	if (~spi_transfer_endD & spi_transfer_end) begin
		abyte_cnt <= 8'd0;
	end else if (spi_receiver_strobeD ^ spi_receiver_strobe) begin

		if(~&abyte_cnt) 
			abyte_cnt <= abyte_cnt + 8'd1;

		if(abyte_cnt == 0) begin
			acmd <= spi_byte_in;
		end else begin
			case(acmd)
				// buttons and switches
				8'h01: but_sw <= spi_byte_in;
				8'h60: if (abyte_cnt < 5) joystick_0[(abyte_cnt-1)<<3 +:8] <= spi_byte_in;
				8'h61: if (abyte_cnt < 5) joystick_1[(abyte_cnt-1)<<3 +:8] <= spi_byte_in;
				8'h62: if (abyte_cnt < 5) joystick_2[(abyte_cnt-1)<<3 +:8] <= spi_byte_in;
				8'h63: if (abyte_cnt < 5) joystick_3[(abyte_cnt-1)<<3 +:8] <= spi_byte_in;
				8'h64: if (abyte_cnt < 5) joystick_4[(abyte_cnt-1)<<3 +:8] <= spi_byte_in;
				8'h04: begin
					// store incoming ps2 mouse bytes 
					ps2_mouse_fifo[ps2_mouse_wptr] <= spi_byte_in;
					ps2_mouse_wptr <= ps2_mouse_wptr + 1'd1;
					if (abyte_cnt == 1) mouse_flags_r <= spi_byte_in;
					else if (abyte_cnt == 2) mouse_x_r <= spi_byte_in;
					else if (abyte_cnt == 3) begin
						// flags: YOvfl, XOvfl, dy8, dx8, 1, mbtn, rbtn, lbtn
						mouse_flags <= mouse_flags_r;
						mouse_x <= { mouse_flags_r[4], mouse_x_r };
						mouse_y <= { mouse_flags_r[5], spi_byte_in };
						mouse_strobe <= 1;
					end
				end
				8'h05: begin
					// store incoming ps2 keyboard bytes 
					ps2_kbd_fifo[ps2_kbd_wptr] <= spi_byte_in;
					ps2_kbd_wptr <= ps2_kbd_wptr + 1'd1;
					if (abyte_cnt == 1) begin
						key_extended_r <= 0;
						key_pressed_r <= 1;
					end
					if (spi_byte_in == 8'he0) key_extended_r <= 1'b1;
					else if (spi_byte_in == 8'hf0) key_pressed_r <= 1'b0;
					else begin
						key_extended <= key_extended_r;
						key_pressed <= key_pressed_r || abyte_cnt == 1;
						key_code <= spi_byte_in;
						key_strobe <= 1'b1;
					end
				end

				// joystick analog
				8'h1a: begin
					// first byte is joystick index
					if(abyte_cnt == 1)
						stick_idx <= spi_byte_in[2:0];
					else if(abyte_cnt == 2) begin
						// second byte is x axis
						if(stick_idx == 0)
							joystick_analog_0[15:8] <= spi_byte_in;
						else if(stick_idx == 1)
							joystick_analog_1[15:8] <= spi_byte_in;
					end else if(abyte_cnt == 3) begin
						// third byte is y axis
						if(stick_idx == 0)
							joystick_analog_0[7:0] <= spi_byte_in;
						else if(stick_idx == 1)
							joystick_analog_1[7:0] <= spi_byte_in;
					end
				end

				8'h15: status <= spi_byte_in;

				// status, 32bit version
				8'h1e: if(abyte_cnt<5) status[(abyte_cnt-1)<<3 +:8] <= spi_byte_in;

				endcase
		end
	end
end

// Process SD-card related bytes from SPI at the clk_sd domain
always @(posedge clk_sd) begin

	reg       spi_receiver_strobe;
	reg       spi_transfer_end;
	reg       spi_receiver_strobeD;
	reg       spi_transfer_endD;
	reg       sd_wrD;
	reg [7:0] acmd;
	reg [7:0] abyte_cnt;   // counts bytes

	//synchronize between SPI and sd clock domains
	spi_receiver_strobeD <= spi_receiver_strobe_r;
	spi_receiver_strobe <= spi_receiver_strobeD;
	spi_transfer_endD	<= spi_transfer_end_r;
	spi_transfer_end	<= spi_transfer_endD;

	if(sd_dout_strobe) begin
		sd_dout_strobe<= 0;
		if(~&sd_buff_addr) sd_buff_addr <= sd_buff_addr + 1'b1;
	end

	sd_din_strobe<= 0;
	sd_wrD <= sd_wr;
	// fetch the first byte immediately after the write command seen
	if (~sd_wrD & sd_wr) begin
		sd_buff_addr <= 0;
		sd_din_strobe <= 1;
	end

	img_mounted <= 0;

	if (~spi_transfer_endD & spi_transfer_end) begin
		abyte_cnt <= 8'd0;
		sd_ack <= 1'b0;
		sd_ack_conf <= 1'b0;
		sd_dout_strobe <= 1'b0;
		sd_din_strobe <= 1'b0;
		sd_buff_addr <= 0;
	end else if (spi_receiver_strobeD ^ spi_receiver_strobe) begin

		if(~&abyte_cnt) 
			abyte_cnt <= abyte_cnt + 8'd1;

		if(abyte_cnt == 0) begin
			acmd <= spi_byte_in;

			if(spi_byte_in == 8'h18) begin
				sd_din_strobe <= 1'b1;
				if(~&sd_buff_addr) sd_buff_addr <= sd_buff_addr + 1'b1;
			end

			if((spi_byte_in == 8'h17) || (spi_byte_in == 8'h18))
				sd_ack <= 1'b1;

		end else begin
			case(acmd)

				// send sector IO -> FPGA
				8'h17: begin
					// flag that download begins
					sd_dout_strobe <= 1'b1;
					sd_dout <= spi_byte_in;
				end

				// send sector FPGA -> IO
				8'h18: begin
					sd_din_strobe <= 1'b1;
					if(~&sd_buff_addr) sd_buff_addr <= sd_buff_addr + 1'b1;
				end

				// send SD config IO -> FPGA
				8'h19: begin
					// flag that download begins
					sd_dout_strobe <= 1'b1;
					sd_ack_conf <= 1'b1;
					sd_dout <= spi_byte_in;
				end

				8'h1c: img_mounted <= 1;

				// send image info
				8'h1d: if(abyte_cnt<5) img_size[(abyte_cnt-1)<<3 +:8] <= spi_byte_in;
			endcase
		end
	end
end

endmodule
