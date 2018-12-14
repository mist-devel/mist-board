//
// data_io.v
//
// data_io for the MiST board
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
///////////////////////////////////////////////////////////////////////

module data_io
(
	input             clk_sys,

	// Global SPI clock from ARM. 24MHz
	input             SPI_SCK,
	input             SPI_SS2,
	input             SPI_DI,

	// ARM -> FPGA download
	input             ioctl_force_erase,
	output reg        ioctl_download = 0, // signal indicating an active download
	output reg        ioctl_erasing = 0,  // signal indicating an active erase
	output reg  [7:0] ioctl_index,        // menu index used to upload the file
	output reg        ioctl_wr = 0,
	output reg [24:0] ioctl_addr,
	output reg  [7:0] ioctl_dout
);


///////////////////////////////   DOWNLOADING   ///////////////////////////////

reg  [7:0] data_w;
reg [24:0] addr_w;
reg        rclk   = 0;

localparam UIO_FILE_TX      = 8'h53;
localparam UIO_FILE_TX_DAT  = 8'h54;
localparam UIO_FILE_INDEX   = 8'h55;

// data_io has its own SPI interface to the io controller
always@(posedge SPI_SCK, posedge SPI_SS2) begin
	reg  [6:0] sbuf;
	reg  [7:0] cmd;
	reg  [4:0] cnt;
	reg [24:0] addr;

	if(SPI_SS2) cnt <= 0;
	else begin
		rclk <= 0;

		// don't shift in last bit. It is evaluated directly
		// when writing to ram
		if(cnt != 15) sbuf <= { sbuf[5:0], SPI_DI};

		// increase target address after write
		if(rclk) addr <= addr + 1'd1;

		// count 0-7 8-15 8-15 ... 
		if(cnt < 15) cnt <= cnt + 1'd1;
			else cnt <= 8;

		// finished command byte
		if(cnt == 7) cmd <= {sbuf, SPI_DI};

		// prepare/end transmission
		if((cmd == UIO_FILE_TX) && (cnt == 15)) begin
			// prepare 
			if(SPI_DI) begin
				addr <= 0;
				ioctl_download <= 1; 
			end else begin
				addr_w <= addr;
				ioctl_download <= 0;
			end
		end

		// command 0x54: UIO_FILE_TX
		if((cmd == UIO_FILE_TX_DAT) && (cnt == 15)) begin
			addr_w <= addr;
			data_w <= {sbuf, SPI_DI};
			rclk <= 1;
		end

      // expose file (menu) index
      if((cmd == UIO_FILE_INDEX) && (cnt == 15)) ioctl_index <= {sbuf, SPI_DI};
	end
end

reg  [24:0] erase_mask;
wire [24:0] next_erase = (ioctl_addr + 1'd1) & erase_mask;

always@(posedge clk_sys) begin
	reg        rclkD, rclkD2;
	reg        old_force = 0;
	reg  [6:0] erase_clk_div;
	reg [24:0] end_addr;

	rclkD    <= rclk;
	rclkD2   <= rclkD;
	ioctl_wr <= 0;

	if(rclkD & ~rclkD2) begin
		ioctl_dout <= data_w;
		ioctl_addr <= addr_w;
		ioctl_wr   <= 1;
	end

	if(ioctl_download) begin
		old_force     <= 0;
		ioctl_erasing <= 0;
	end else begin

		old_force <= ioctl_force_erase;
		if(ioctl_force_erase & ~old_force) begin
			ioctl_addr    <= 'h1FFFF;
			erase_mask    <= 'h1FFFF;
			end_addr      <= 'h10002;
			erase_clk_div <= 1;
			ioctl_erasing <= 1;
		end else if(ioctl_erasing) begin
			erase_clk_div <= erase_clk_div + 1'd1;
			if(!erase_clk_div) begin
				if(next_erase == end_addr) ioctl_erasing <= 0;
				else begin
					ioctl_addr <= next_erase;
					ioctl_dout <= 0;
					ioctl_wr   <= 1;
				end
			end
		end
	end
end

endmodule