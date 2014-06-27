//
// data_io.v
//
// io controller writable ram for the MiST board
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

module data_io (
	// io controller spi interface
	input         sck,
	input         ss,
	input         sdi,

	output        downloading,   // signal indicating an active download
	output [15:0] size,          // number of bytes in input buffer
	
	// cpu ram interface
	input 			clk,
	input          we,
	input [10:0]   a,
	input [8:0]    din,
	output [8:0]   dout
);

parameter START_ADDR = 16'h0000;

assign size = addr;

// *********************************************************************************
// spi client
// *********************************************************************************

// this core supports only the display related OSD commands
// of the minimig
reg [6:0]      sbuf;
reg [7:0]      cmd /* synthesis noprune */;
reg [7:0]      data /* synthesis noprune */;
reg [4:0]      cnt /* synthesis noprune */;

reg [15:0]     addr /* synthesis noprune */;
reg rclk /* synthesis noprune */;

localparam UIO_FILE_TX      = 8'h53;
localparam UIO_FILE_TX_DAT  = 8'h54;

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
		if(cnt != 15)
			sbuf <= { sbuf[5:0], sdi};

		// increase target address after write
		if(rclk)
			addr <= addr + 16'd1;
	 
		// count 0-7 8-15 8-15 ... 
		if(cnt < 15) 	cnt <= cnt + 4'd1;
		else				cnt <= 4'd8;

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
		end
	end
end

// include the embedded dual port ram
data_io_ram data_io_ram (
	// wire up cpu port
	.address_a   	( a					),
	.clock_a			( clk					),
	.data_a			( din					),
	.wren_a			( we					),
	.q_a				( dout				),
	
	// io controller port
	.address_b		( addr[10:0]		),
	.clock_b			( rclk				),
	.data_b			( {sbuf, sdi}		),
	.wren_b			( (cmd == UIO_FILE_TX_DAT) && !ss	)
);

endmodule