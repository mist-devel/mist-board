//
// data_io.v
//
// Data interface for the archimedes core on the MiST board. 
// Providing ROM and floppy data up- and download via the MISTs
// own arm7 cpu.
//
// http://code.google.com/p/mist-board/
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
	input 			    sck,
	input 			    ss,
	input 			    sdi,
	output reg 		    sdo,

	output reg downloading, // signal indicating an active download
	output [ADDR_WIDTH-1:0]     size, // number of bytes in input buffer

	// additional signals for floppy emulation
	input [31:0] 		    fdc_status_out,
	output reg [31:0] 	    fdc_status_in,
	output reg 		    fdc_data_in_strobe,
	output reg [7:0] 	    fdc_data_in,

	// external ram interface
	input 			    clk,
	output reg 		    wr,
	output reg [ADDR_WIDTH-1:0] a,
	output [3:0] 		    sel, 
	output [31:0] 		    d
);

(*KEEP="TRUE"*)assign sel = a[1:0] == 	2'b00 ? 4'b0001 :
								a[1:0] == 	2'b01 ? 4'b0010 :
								a[1:0] == 	2'b10 ? 4'b0100 : 4'b1000;

assign d = {data,data,data,data};
assign size = addr - START_ADDR;

// *********************************************************************************
// spi client
// *********************************************************************************

// this core supports only the display related OSD commands
// of the minimig
reg [6:0]      sbuf;
reg [7:0]      cmd;
reg [7:0]      data;
reg [2:0]      bit_cnt;
reg [2:0]      byte_cnt;

reg [ADDR_WIDTH-1:0] addr;

localparam UIO_FILE_TX         = 8'h53;
localparam UIO_FILE_TX_DAT     = 8'h54;
localparam UIO_FDC_GET_STATUS  = 8'h55;
localparam UIO_FDC_TX_DATA     = 8'h56;
localparam UIO_FDC_SET_STATUS  = 8'h57;

// data_io has its own SPI interface to the io controller

// SPI bit and byte counters
always@(posedge sck or posedge ss) begin
	if(ss == 1) begin
		bit_cnt <= 0;
		byte_cnt <= 0;
		cmd <= 0;
	end else begin
		if((&bit_cnt)&&(~&byte_cnt)) begin
			byte_cnt <= byte_cnt + 1'd1;
			if (!byte_cnt) cmd <= {sbuf, sdi};
		end
		bit_cnt <= bit_cnt + 1'd1;
	end
end

always@(negedge sck or posedge ss) begin
	if(ss == 1) begin
		sdo <= 1'bZ;
	end else begin
		if(cmd == UIO_FDC_GET_STATUS)
			sdo <= fdc_status_out[{4-byte_cnt,~bit_cnt}];
		else
			sdo <= 1'b0;
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
	end else begin
		spi_transfer_end_r <= 0;

		if(&bit_cnt) begin
			// finished reading a byte, prepare to transfer to clk_sys
			spi_byte_in <= { sbuf, sdi};
			spi_receiver_strobe_r <= ~spi_receiver_strobe_r;
		end else
			sbuf[6:0] <= { sbuf[5:0], sdi };
	end
end

// Process bytes from SPI at the clk_sys domain
always @(posedge clk) begin

	reg       spi_receiver_strobe;
	reg       spi_transfer_end;
	reg       spi_receiver_strobeD;
	reg       spi_transfer_endD;
	reg [7:0] acmd;
	reg [3:0] abyte_cnt;   // counts bytes

	fdc_data_in_strobe <= 0;
	wr <= 0;

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
			UIO_FILE_TX:
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
			UIO_FILE_TX_DAT:
			begin
				a <= addr;
				addr <= addr + 1'd1;
				data <= spi_byte_in;
				wr <= 1;
			end

			// command 0x56: UIO_FDC_TX_DATA
			UIO_FDC_TX_DATA:
			begin
				fdc_data_in_strobe <= 1'b1;
				fdc_data_in <= spi_byte_in;
			end

			// command 0x57: UIO_FDC_SET_STATUS
			UIO_FDC_SET_STATUS:
			begin
				if (abyte_cnt == 1) fdc_status_in[31:24] <= spi_byte_in;
				if (abyte_cnt == 2) fdc_status_in[23:16] <= spi_byte_in;
				if (abyte_cnt == 3) fdc_status_in[15: 8] <= spi_byte_in;
				if (abyte_cnt == 4) fdc_status_in[ 7: 0] <= spi_byte_in;
			end
			endcase
		end
	end
end

endmodule
