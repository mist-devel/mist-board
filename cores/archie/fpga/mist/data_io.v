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

	output 			    downloading, // signal indicating an active download
	output [ADDR_WIDTH-1:0]     size, // number of bytes in input buffer

        // additional signals for floppy emulation
	input [31:0] 		    fdc_status_out,
	output reg [31:0] 	    fdc_status_in,
	output reg 		    fdc_data_in_strobe,
	output [7:0] 		    fdc_data_in,
							   
	// external ram interface
	input 			    clk,
	output reg 		    wr,
	output reg [ADDR_WIDTH-1:0] a,
	output [3:0] 		    sel, 
	output [31:0] 		    d
);

// filter spi clock. the 8 bit gate delay is ~2.5ns in total
wire [7:0] spi_sck_D = { spi_sck_D[6:0], sck } /* synthesis keep */;
wire spi_sck = (spi_sck && spi_sck_D != 8'h00) || (!spi_sck && spi_sck_D == 8'hff);

assign fdc_data_in = { sbuf, sdi };
   
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
reg [4:0]      cnt;
reg [2:0]      byte_cnt;

reg [ADDR_WIDTH-1:0] addr;
reg rclk;

localparam UIO_FILE_TX         = 8'h53;
localparam UIO_FILE_TX_DAT     = 8'h54;
localparam UIO_FDC_GET_STATUS  = 8'h55;
localparam UIO_FDC_TX_DATA     = 8'h56;
localparam UIO_FDC_SET_STATUS  = 8'h57;

assign downloading = downloading_reg;
reg downloading_reg = 1'b0;

// data_io has its own SPI interface to the io controller
always@(posedge spi_sck, posedge ss) begin
	if(ss == 1'b1) begin
		cnt <= 5'd0;
		byte_cnt <= 3'd0;
		fdc_data_in_strobe <= 1'b0;
	end else begin
		rclk <= 1'b0;
		fdc_data_in_strobe <= 1'b0;

		// don't shift in last bit. It is evaluated directly
		// when writing to ram
		if(cnt != 15)
			sbuf <= { sbuf[5:0], sdi};

		// increase target address after write
		if(rclk)
			addr <= addr + 1;
	 
		// count 0-7 8-15 8-15 ... 
		if(cnt < 15) 	
			cnt <= cnt + 4'd1;
		else begin	
			cnt <= 5'd8;
			if(byte_cnt != 7)
				byte_cnt <= byte_cnt + 3'd1;
		end
		
		// finished command byte
      if(cnt == 7)
			cmd <= {sbuf, sdi};

		// prepare/end transmission
		if((cmd == UIO_FILE_TX) && (cnt == 15)) begin
			// prepare
			if(sdi) begin
				addr <= START_ADDR;
				downloading_reg <= 1'b1; 
			end else
				downloading_reg <= 1'b0; 
		end
		
		// command 0x54: UIO_FILE_TX
		if((cmd == UIO_FILE_TX_DAT) && (cnt == 15)) begin
			data <= {sbuf, sdi};
			rclk <= 1'b1;
			a <= addr;
		end
		
		// command 0x56: UIO_FDC_TX_DATA
		if((cmd == UIO_FDC_TX_DATA) && (cnt == 15))
			fdc_data_in_strobe <= 1'b1;
	   
		// command 0x57: UIO_FDC_SET_STATUS
		if((cmd == UIO_FDC_SET_STATUS) && (cnt == 15)) begin
		   if(byte_cnt == 0) fdc_status_in[31:24] <= { sbuf, sdi};
		   if(byte_cnt == 1) fdc_status_in[23:16] <= { sbuf, sdi};
		   if(byte_cnt == 2) fdc_status_in[15:8]  <= { sbuf, sdi};
		   if(byte_cnt == 3) fdc_status_in[7:0]   <= { sbuf, sdi};
		end
	end
end
   
always@(negedge spi_sck or posedge ss) begin
   if(ss == 1) begin
      sdo <= 1'bZ;
   end else begin
		if(cmd == UIO_FDC_GET_STATUS)
			sdo <= fdc_status_out[{~byte_cnt[1:0],~(cnt[2:0])}];
		else
			sdo <= 1'b0;
   end
end

reg rclkD, rclkD2;
always@(posedge clk) begin
	// bring rclk from spi clock domain into core clock domain
	rclkD <= rclk;
	rclkD2 <= rclkD;
	wr <= 1'b0;
	
	if(rclkD && !rclkD2) 
		wr <= 1'b1;
end

endmodule
