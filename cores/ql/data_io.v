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
	output reg [15:0] data
);

// *********************************************************************************
// spi client
// *********************************************************************************

// this core supports only the display related OSD commands
// of the minimig
reg [14:0]     sbuf;
reg [7:0]      cmd;
reg [4:0]      cnt;
reg rclk;

reg [24:0] laddr;
reg [15:0] ldata;
	
localparam UIO_FILE_TX      = 8'h53;
localparam UIO_FILE_TX_DAT  = 8'h54;
localparam UIO_FILE_INDEX   = 8'h55;

assign downloading = downloading_reg;
reg downloading_reg = 1'b0;

// data_io has its own SPI interface to the io controller
always@(posedge sck, posedge ss) begin
	if(ss == 1'b1)
		cnt <= 5'd0;
	else begin
		rclk <= 1'b0;

		// don't shift in last bit. It is evaluated directly
		// when writing to ram
		if(cnt != 23)
			sbuf <= { sbuf[13:0], sdi};
	 
		// count 0-7 8-15 16-23 8-15 16-23 ... 
		if(cnt < 23) 	cnt <= cnt + 4'd1;
		else				cnt <= 4'd8;

		// finished command byte
      if(cnt == 7)
			cmd <= {sbuf[6:0], sdi};

		// prepare/end transmission
		if((cmd == UIO_FILE_TX) && (cnt == 15)) begin
			// prepare 
			if(sdi) begin
				// download rom to address 0, microdrive image to 16MB+
				if(index == 0) laddr <= 25'h0 - 25'd1;
				if(index == 1) laddr <= 25'h800000 - 25'd1; //mdv1_
				if(index == 2) laddr <= 25'h900000 - 25'd1; //mdv2_
				if(index == 3) laddr <= 25'h0 - 25'd1;  //Additional ROM bios selection
				
				downloading_reg <= 1'b1; 
			end else
				downloading_reg <= 1'b0; 
		end
		
		// command 0x54: UIO_FILE_TX
		if((cmd == UIO_FILE_TX_DAT) && (cnt == 23)) begin
			ldata <= {sbuf, sdi};
			laddr <= laddr + 1;
			rclk <= 1'b1;
		end
		
      // expose file (menu) index
      if((cmd == UIO_FILE_INDEX) && (cnt == 15))
			index <= {sbuf[3:0], sdi};
	end
end

reg rclkD, rclkD2;
always@(posedge clk) begin
	// bring all signals from spi clock domain into local clock domain
	rclkD <= rclk;
	rclkD2 <= rclkD;
	wr <= 1'b0;
	
	if(rclkD && !rclkD2) begin
		addr <= laddr;
		data <= ldata;
		wr <= 1'b1;
	end
end

endmodule
