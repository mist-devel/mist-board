//
// data_io.v
//
// io controller writable ram for the MiST board
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

module data_io (
	// io controller spi interface
	input         sck,
	input         ss,
	input         sdi,

	output        downloading,   // signal indicating an active download
   output reg [4:0]  index,     // menu index used to upload the file
	 
	// external ram interface
	input 			   clk,
	output reg        wr,
	output reg [24:0] addr,
	output reg [7:0]  data
);

// *********************************************************************************
// spi client
// *********************************************************************************

// this core supports only the display related OSD commands
// of the minimig
reg [6:0]     sbuf;
reg [7:0]     cmd;
reg [3:0]     cnt;
reg rclk;

reg [24:0] laddr;
reg [7:0]  ldata;
	
localparam UIO_FILE_TX      = 8'h53;
localparam UIO_FILE_TX_DAT  = 8'h54;
localparam UIO_FILE_INDEX   = 8'h55;

assign downloading = downloading_reg;
reg downloading_reg = 1'b0;

// filter spi clock. the 8 bit gate delay is ~2.5ns in total
wire [7:0] spi_sck_D = { spi_sck_D[6:0], sck } /* synthesis keep */;
wire spi_sck = (spi_sck && spi_sck_D != 8'h00) || (!spi_sck && spi_sck_D == 8'hff);

// data_io has its own SPI interface to the io controller
always@(posedge spi_sck, posedge ss) begin
	if(ss == 1'b1)
		cnt <= 4'd0;
	else begin
		rclk <= 1'b0;

		// don't shift in last bit. It is evaluated directly
		// when writing to ram
		if(cnt[2:0] != 3'd7)
			sbuf <= { sbuf[5:0], sdi};
	 
		// count 0-7 8-15 8-15 ... 
		if(cnt != 15) 	cnt <= cnt + 4'd1;
		else				cnt <= 4'd8;

		// finished command byte
      if(cnt == 7)
			cmd <= {sbuf, sdi};

		if(cnt == 15) begin
			
			// prepare/end transmission
			if(cmd == UIO_FILE_TX) begin
				// prepare 
				if(sdi) begin
					// download rom into sideways rom slot e
					laddr <= { 7'b0000001, 4'hd, 14'h0 } - 25'd1;
					downloading_reg <= 1'b1; 
				end else
					downloading_reg <= 1'b0; 
			end
		
			// command 0x54: UIO_FILE_TX
			if(cmd == UIO_FILE_TX_DAT) begin
				ldata <= {sbuf, sdi};
				laddr <= laddr + 25'd1;
				rclk <= 1'b1;
			end
		
			// expose file (menu) index
			if(cmd == UIO_FILE_INDEX)
				index <= {sbuf[3:0], sdi};
		end
	end
end

reg mem_req;
always @(posedge rclk or posedge wr) begin
	if(wr) mem_req <= 1'b0;
	else   mem_req <= 1'b1;
end

// memory request needs to be valid on the rising
// edge so data and address are sure stable in it's
// falling edge
reg mem_reqD;
always@(posedge clk)
	mem_reqD <= mem_req;

always@(negedge clk) begin
	wr <= 1'b0;

	if(mem_reqD) begin
		addr <= laddr;
		data <= ldata;
		wr <= 1'b1;
	end
end

endmodule
