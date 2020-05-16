//
// data_io.v
//
// Data interface for the archimedes core on the MiST board. 
// Providing ROM and IDE data up- and download via the MISTs
// own arm7 cpu.
//
// https://github.com/mist-devel/mist-board
//
// Copyright (c) 2014-2015 Till Harbaum <till@harbaum.org>
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

module data_io #(parameter ADDR_WIDTH=24, START_ADDR = 0) (
	// io controller spi interface
	input               sck,
	input               ss,
	input               ss_sd,
	input               sdi,
	output reg          sdo,

	input               reset,
	input               ide_req,
	output reg          ide_ack,
	output reg          ide_err,
	output reg    [2:0] ide_reg_i_adr,
	input         [7:0] ide_reg_i,
	output reg          ide_reg_we,
	output reg    [2:0] ide_reg_o_adr,
	output reg    [7:0] ide_reg_o,

	output reg    [8:0] ide_data_addr,
	output reg    [7:0] ide_data_o,
	input         [7:0] ide_data_i,
	output reg          ide_data_rd,
	output reg          ide_data_we,

	output reg downloading, // signal indicating an active download
	output reg uploading,   // signal indicating an active upload (CMOS RAM)
	output [ADDR_WIDTH-1:0]     size, // number of bytes in input buffer
	output reg [7:0] index, // menu index

	// external ram interface
	input 			    clk,
	output reg 		    wr,
	output reg [ADDR_WIDTH-1:0] a,
	output [3:0] 		    sel, 
	output [31:0] 		  dout,
	input  [7:0]        din
);

(*KEEP="TRUE"*)assign sel = a[1:0] == 	2'b00 ? 4'b0001 :
								a[1:0] == 	2'b01 ? 4'b0010 :
								a[1:0] == 	2'b10 ? 4'b0100 : 4'b1000;

assign dout = {data,data,data,data};
assign size = addr - START_ADDR;

// *********************************************************************************
// spi client
// *********************************************************************************

reg [6:0]      sbuf;
reg [7:0]      cmd;
reg [7:0]      data;
reg [2:0]      bit_cnt;
reg [4:0]      byte_cnt;

reg [6:0]      sbuf_sd;
reg [2:0]      bit_cnt_sd;

reg [ADDR_WIDTH-1:0] addr;

localparam DIO_FILE_TX         = 8'h53;
localparam DIO_FILE_TX_DAT     = 8'h54;
localparam DIO_FILE_INDEX      = 8'h55;
localparam DIO_FILE_INFO       = 8'h56;
localparam DIO_FILE_RX         = 8'h57;
localparam DIO_FILE_RX_DAT     = 8'h58;

localparam CMD_IDECMD          = 8'h04;
localparam CMD_IDEDAT          = 8'h08;
localparam CMD_IDE_REGS_RD     = 8'h80;
localparam CMD_IDE_REGS_WR     = 8'h90;
localparam CMD_IDE_DATA_WR     = 8'hA0;
localparam CMD_IDE_DATA_RD     = 8'hB0;
localparam CMD_IDE_STATUS_WR   = 8'hF0;

// SPI bit and byte counters
always@(posedge sck or posedge ss) begin
	if(ss == 1) begin
		bit_cnt <= 0;
		byte_cnt <= 0;
	end else begin
		if((&bit_cnt)&&(~&byte_cnt)) begin
			byte_cnt <= byte_cnt + 1'd1;
		end
		bit_cnt <= bit_cnt + 1'd1;
	end
end

reg       spi_receiver_strobe_sd_r = 0;
reg       spi_transfer_end_sd_r = 1;
reg [7:0] spi_byte_in_sd;

// direct SD
always@(posedge sck or posedge ss_sd) begin
	if(ss_sd == 1) begin
		bit_cnt_sd <= 0;
		spi_transfer_end_sd_r <= 1;
	end else begin
		bit_cnt_sd <= bit_cnt_sd + 1'd1;
		spi_transfer_end_sd_r <= 0;
		if(&bit_cnt_sd) begin
			// finished reading a byte, prepare to transfer to clk_sys
			spi_byte_in_sd <= { sbuf_sd, sdi};
			spi_receiver_strobe_sd_r <= ~spi_receiver_strobe_sd_r;
		end else
			sbuf_sd[6:0] <= { sbuf_sd[5:0], sdi };
	end
end

// SPI transmitter FPGA -> IO
// CMD_IDEDAT is required before the first sector of a write commands
// and just before the _first_ one, even with multiple sector writes.
wire [7:0] cmdcode = write_start ? CMD_IDEDAT : newcmd ? CMD_IDECMD : 8'h0;
wire [4:0] tf_o_pos = byte_cnt - 4'd5;

// need to know the ATA command sent by Archie for some local processing here
reg  [7:0] ide_cmd;

always@(negedge sck or posedge ss) begin
	reg [7:0] dout_r;

	if(ss == 1) begin
		sdo <= 1'bZ;
	end else begin

		if (&bit_cnt) begin
			case(cmd)
				CMD_IDE_REGS_RD:
				begin
					// send task file regs
					dout_r <= ide_reg_i;
					ide_reg_i_adr <= tf_o_pos[3:1];
					if (tf_o_pos[3:1] == 3'd7) ide_cmd <= ide_reg_i;
				end

				CMD_IDE_DATA_RD: dout_r <= ide_data_i;

				DIO_FILE_RX_DAT: dout_r <= din;

				default: dout_r <= cmdcode;

			endcase
		end
		sdo <= (cmd == 0) ? cmdcode[~bit_cnt] : dout_r[~bit_cnt];
	end
end

// SPI receiver IO -> FPGA

reg       spi_receiver_strobe_r = 0;
reg       spi_transfer_end_r = 1;
reg [7:0] spi_byte_in;

// Read at spi_sck clock domain, assemble bytes for transferring to clk_sys
always@(posedge sck or posedge ss) begin

	if(ss == 1) begin
		spi_transfer_end_r <= 1;
		cmd <= 0;
	end else begin
		spi_transfer_end_r <= 0;

		if(&bit_cnt) begin
			// finished reading a byte, prepare to transfer to clk_sys
			spi_byte_in <= { sbuf, sdi};
			spi_receiver_strobe_r <= ~spi_receiver_strobe_r;
			if (!byte_cnt) cmd <= { sbuf, sdi };
		end else
			sbuf[6:0] <= { sbuf[5:0], sdi };
	end
end

reg       newcmd = 0;
reg       write_req = 0;
reg       write_start = 0;

// Process bytes from SPI at the clk_sys domain
always @(posedge clk) begin

	reg       spi_receiver_strobe;
	reg       spi_transfer_end;
	reg       spi_receiver_strobeD;
	reg       spi_transfer_endD;
	reg [7:0] acmd;
	reg [4:0] abyte_cnt;   // counts bytes

	reg       spi_receiver_strobe_sd;
	reg       spi_transfer_end_sd;
	reg       spi_receiver_strobe_sdD;
	reg       spi_transfer_end_sdD;
	reg [4:0] abyte_cnt_sd;

	wr <= 0;

	// This "state-machine" is messy, but the firmware has to be clean up
	// to make it more clear. And that would require changes in Minimig, too.
	if (reset) begin
		newcmd <= 0;
		write_req <= 0;
		write_start <= 0;
	end
	if (ide_req) begin
		ide_data_addr <= 0;
		ide_err <= 0;
		newcmd <= 1;
		write_start <= write_req;
	end
	ide_reg_we <= 0;
	ide_ack <= 0;

	ide_data_we <= 0;
	if (ide_data_we) begin
		ide_data_addr <= ide_data_addr + 1'd1;
		newcmd <= 0;
	end

	ide_data_rd <= 0;
    if (ide_data_rd) begin
		ide_data_addr <= ide_data_addr + 1'b1;
		write_req <= 0;
		write_start <= 0;
	end

	//synchronize between SPI and sys clock domains
	spi_receiver_strobeD <= spi_receiver_strobe_r;
	spi_receiver_strobe <= spi_receiver_strobeD;
	spi_transfer_endD       <= spi_transfer_end_r;
	spi_transfer_end        <= spi_transfer_endD;

	// strobe is set whenever a valid byte has been received
	if (~spi_transfer_endD & spi_transfer_end) begin
		abyte_cnt <= 0;
	end else if (spi_receiver_strobeD ^ spi_receiver_strobe) begin

		if(~&abyte_cnt)
			abyte_cnt <= abyte_cnt + 1'd1;

		if(!abyte_cnt) begin
			acmd <= spi_byte_in;
		end else begin
			case(acmd)
			// IDE commands
			CMD_IDE_STATUS_WR:
			if (abyte_cnt == 1) begin
				// "real" status register handling inside the IDE module,
				// since firmware status codes are not real ATA-1 status codes
				// (I wonder how it works for Amiga)
				if (spi_byte_in[7]) ide_ack <= 1;   // IDE_STATUS_END
				if (spi_byte_in[4]) newcmd <= 0;    // IDE_STATUS_IRQ
				if (spi_byte_in[2] || ((ide_cmd == 8'h30 || ide_cmd == 8'hc5) && spi_byte_in[4] && ~spi_byte_in[7])) write_req <= 1;
				if (spi_byte_in[1]) ide_err <= 1;   // IDE_STATUS_ERR
			end

			CMD_IDE_REGS_WR:
			begin
				ide_reg_o <= spi_byte_in;
				if (abyte_cnt ==  9) begin ide_reg_o_adr <= 3'd1; ide_reg_we <= 1; end // error
				if (abyte_cnt == 11) begin ide_reg_o_adr <= 3'd2; ide_reg_we <= 1; end // sector count
				if (abyte_cnt == 13) begin ide_reg_o_adr <= 3'd3; ide_reg_we <= 1; end // sector number
				if (abyte_cnt == 15) begin ide_reg_o_adr <= 3'd4; ide_reg_we <= 1; end // cyl low
				if (abyte_cnt == 17) begin ide_reg_o_adr <= 3'd5; ide_reg_we <= 1; end // cyl high
				if (abyte_cnt == 19) begin ide_reg_o_adr <= 3'd6; ide_reg_we <= 1; end // drive/head
			end

			CMD_IDE_DATA_WR:
			if (abyte_cnt > 5) begin
					ide_data_we <= 1;
					ide_data_o <= spi_byte_in;
			end

			CMD_IDE_DATA_RD: 
			if (abyte_cnt > 4) ide_data_rd <= 1;

			// file transfer commands
			DIO_FILE_TX:
			begin
				// prepare 
				if(spi_byte_in) begin
					addr <= START_ADDR;
					downloading <= 1; 
				end else begin
					a <= addr;
					downloading <= 0;
				end
			end

			// transfer
			DIO_FILE_TX_DAT:
			begin
				a <= addr;
				addr <= addr + 1'd1;
				data <= spi_byte_in;
				wr <= 1;
			end

			// index
			DIO_FILE_INDEX: index <= spi_byte_in;

			// start/stop receive
			DIO_FILE_RX:
			begin
				// prepare 
				if(spi_byte_in) begin
					a <= START_ADDR;
					uploading <= 1; 
				end else begin
					uploading <= 0;
				end
			end

			DIO_FILE_RX_DAT:
			begin
				a <= a + 1'd1;
			end

			endcase;
		end
	end

	// direct-sd connection
	// synchronize between SPI and sys clock domains
	spi_receiver_strobe_sdD <= spi_receiver_strobe_sd_r;
	spi_receiver_strobe_sd  <= spi_receiver_strobe_sdD;
	spi_transfer_end_sdD    <= spi_transfer_end_sd_r;
	spi_transfer_end_sd     <= spi_transfer_end_sdD;

	// strobe is set whenever a valid byte has been received
	if (~spi_transfer_end_sdD & spi_transfer_end_sd) begin
		abyte_cnt_sd <= 0;
	end else if (spi_receiver_strobe_sdD ^ spi_receiver_strobe_sd) begin

		if(~&abyte_cnt_sd)
			abyte_cnt_sd <= abyte_cnt_sd + 1'd1;

		if (abyte_cnt_sd == 0 || ide_data_addr != 0) begin // filter spurious byte at the end
			ide_data_we <= 1;
			ide_data_o <= spi_byte_in_sd;
		end
	end

end

endmodule
