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

module user_io (
        input            clk_sys,
        input            SPI_CLK,
        input            SPI_SS_IO,
        output reg       SPI_MISO,
        input            SPI_MOSI,

        output     [7:0] JOY0,
        output     [7:0] JOY1,
        output           scandoubler_disable,
        output           ypbpr,

        input      [7:0] kbd_out_data,
        input            kbd_out_strobe,

        output reg [7:0] kbd_in_data,
        output reg       kbd_in_strobe,

        output     [1:0] BUTTONS,
        output     [1:0] SWITCHES,

        // connection to sd card emulation
        input     [31:0] sd_lba,
        input      [1:0] sd_rd,
        input      [1:0] sd_wr,
        output reg       sd_ack,
        output reg       sd_ack_conf,
        input            sd_conf,
        input            sd_sdhc,
        output reg [7:0] sd_dout, // valid on rising edge of sd_dout_strobe
        output reg       sd_dout_strobe,
        input      [7:0] sd_din,
        output reg       sd_din_strobe,
        output reg [8:0] sd_buff_addr,

        output reg [1:0] img_mounted, //rising edge if a new image is mounted
        output reg[31:0] img_size     // size of image in bytes
);

reg [6:0]     sbuf;
reg [7:0]     cmd;
reg [2:0]     bit_cnt;    // counts bits 0-7 0-7 ...
reg [9:0]     byte_cnt;   // counts bytes
reg [7:0]     but_sw;

reg [31:0]    joystick_0;
reg [31:0]    joystick_1;
reg [31:0]    joystick_2;
reg [31:0]    joystick_3;
reg [31:0]    joystick_4;

assign JOY0 = joystick_0[7:0];
assign JOY1 = joystick_1[7:0];

assign BUTTONS  = but_sw[1:0];
assign SWITCHES = but_sw[3:2];
assign scandoubler_disable = but_sw[4];
assign ypbpr = but_sw[5];

// this variant of user_io is for the achie core (type == a6) only
wire [7:0] core_type = 8'ha6;
reg  [7:0] spi_byte_out;

reg kbd_out_data_available = 0;

// SPI bit and byte counters
always@(posedge SPI_CLK or posedge SPI_SS_IO) begin
    if(SPI_SS_IO == 1) begin
        bit_cnt <= 0;
        byte_cnt <= 0;
        cmd <= 0;
    end else begin
        if((&bit_cnt)&&(~&byte_cnt)) begin
            byte_cnt <= byte_cnt + 8'd1;
            if (!byte_cnt) cmd <= {sbuf, SPI_MOSI};
        end
        bit_cnt <= bit_cnt + 1'd1;
    end
end

wire drive_sel = sd_rd[1] | sd_wr[1];

always@(negedge SPI_CLK or posedge SPI_SS_IO) begin
    reg  [7:0] kbd_out_status;
    reg  [7:0] kbd_out_data_r;
    reg [31:0] sd_lba_r;
    reg  [7:0] drive_sel_r;
    reg  [7:0] sd_cmd;
    reg  [7:0] sd_din_r;

    if(SPI_SS_IO == 1) begin
        SPI_MISO <= 1'bZ;
	end else begin
        kbd_out_status <= { 4'ha, 3'b000, kbd_out_data_available };
        kbd_out_data_r <= kbd_out_data;
        sd_cmd <= { 4'h6, sd_conf, sd_sdhc, sd_wr[drive_sel], sd_rd[drive_sel] };
        if(&bit_cnt) sd_din_r <= sd_din;

        // first byte returned is always core type, further bytes are 
        // command dependent
        if(byte_cnt == 0) begin
            SPI_MISO <= core_type[~bit_cnt];
        end else begin
            // reading keyboard data
            if(cmd == 8'h04) begin
                if(byte_cnt == 1) SPI_MISO <= kbd_out_status[~bit_cnt];
                else              SPI_MISO <= kbd_out_data_r[~bit_cnt];
            end

            // reading sd card status
            if(cmd == 8'h16) begin
                if(byte_cnt == 1) begin
                    SPI_MISO <= sd_cmd[~bit_cnt];
                    sd_lba_r <= sd_lba;
                    drive_sel_r <= {6'b0, drive_sel};
                end
                else if(byte_cnt == 2) SPI_MISO <= drive_sel_r[~bit_cnt];
				else if(byte_cnt < 7) SPI_MISO <= sd_lba_r[{6-byte_cnt, ~bit_cnt}];
            end

			// reading sd card write data
            if(cmd == 8'h18) SPI_MISO <= sd_din_r[~bit_cnt];
        end
    end
end

// SPI receiver IO -> FPGA

reg       spi_receiver_strobe_r = 0;
reg       spi_transfer_end_r = 1;
reg [7:0] spi_byte_in;

// Read at spi_sck clock domain, assemble bytes for transferring to clk_sys
always@(posedge SPI_CLK or posedge SPI_SS_IO) begin

    if(SPI_SS_IO == 1) begin
        spi_transfer_end_r <= 1;
    end else begin
        spi_transfer_end_r <= 0;

        if(&bit_cnt) begin
            // finished reading a byte, prepare to transfer to clk_sys
            spi_byte_in <= { sbuf, SPI_MOSI};
            spi_receiver_strobe_r <= ~spi_receiver_strobe_r;
        end else
            sbuf[6:0] <= { sbuf[5:0], SPI_MOSI };
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

    kbd_in_strobe <= 0;

    //synchronize between SPI and sys clock domains
    spi_receiver_strobeD <= spi_receiver_strobe_r;
    spi_receiver_strobe <= spi_receiver_strobeD;
    spi_transfer_endD       <= spi_transfer_end_r;
    spi_transfer_end        <= spi_transfer_endD;

    // strobe is set whenever a valid byte has been received
    if (~spi_transfer_endD & spi_transfer_end) begin
        abyte_cnt <= 8'd0;
    end else if (spi_receiver_strobeD ^ spi_receiver_strobe) begin

        if(~&abyte_cnt)
            abyte_cnt <= abyte_cnt + 8'd1;

        if(!abyte_cnt) begin
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

                8'h04: if (abyte_cnt == 1) kbd_out_data_available <= 0;
                8'h05: if (abyte_cnt == 1) begin
                           kbd_in_strobe <= 1;
                           kbd_in_data <= spi_byte_in;
                       end
            endcase
        end
    end
    if (kbd_out_strobe) kbd_out_data_available <= 1;
end

// Process SD-card related bytes from SPI
always @(posedge clk_sys) begin

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
		sd_buff_addr<= 0;
	end else if (spi_receiver_strobeD ^ spi_receiver_strobe) begin

		if(~&abyte_cnt) 
			abyte_cnt <= abyte_cnt + 8'd1;

		if(abyte_cnt == 0) begin
			acmd <= spi_byte_in;

			if((spi_byte_in == 8'h17) || (spi_byte_in == 8'h18))
				sd_ack <= 1'b1;

			if (spi_byte_in == 8'h18) begin
				sd_din_strobe <= 1'b1;
				sd_buff_addr <= sd_buff_addr + 1'b1;
			end

		end else begin
			case(acmd)

				// send sector IO -> FPGA
				8'h17: begin
					// flag that download begins
					sd_dout_strobe <= 1'b1;
					sd_dout <= spi_byte_in;
				end

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

				8'h1c: img_mounted[spi_byte_in[0]] <= 1;

				// send image info
				8'h1d: if(abyte_cnt<5) img_size[(abyte_cnt-1)<<3 +:8] <= spi_byte_in;
			endcase
		end
	end
end

endmodule
