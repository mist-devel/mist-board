// 
// block_io.v
//
// This file implements a simple block interface to the SD card.
// It can be used instead of the sd_card.v whenever there's no need
// on core side for a full sd card interface. This is usually the
// case if the core is not ported from/to other boards.
//
// Copyright (c) 2015 Till Harbaum <till@harbaum.org>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the Lesser GNU General Public License as published
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

module block_io (
	// link to user_io for io controller
	output reg [31:0] io_lba,
	output reg        io_rd,
	output            io_wr,
	input 	      	io_ack,
	output 	      	io_conf,
	output 	      	io_sdhc,
	
	// data coming in from io controller
	input [7:0]   		io_din,
	input 	      	io_din_strobe,

	// data going out to io controller
	output [7:0]  		io_dout,
	input 	      	io_dout_strobe,

	// interface to the cpu
	input         		reset,
	input         		clk,
	input         		rd,
	input         		wr,
	input [7:0]   		din,
	input [2:0]   		addr,
	output [7:0]  		dout		 
); 

assign io_wr   = 1'b0;  // we never write ...
assign io_dout = 1'b0;  // ... and thus never send data to the io controller
assign io_conf = 1'b0;  // we need no configuration info from the SD card

// raise io_rd signal whenever SoC requests a sector and release it
// once IO controller acknowleges it
always @(posedge io_rd_req or posedge io_ack) begin
	if(io_ack) io_rd <= 1'b0;
   else       io_rd <= 1'b1;
end

// ---------------------------------------------------------------
// --------------------- sector buffer ---------------------------
// ---------------------------------------------------------------
reg [7:0]  buffer [511:0];
reg [8:0]  buffer_wptr;    // buffer write pointer
reg [8:0]  buffer_rptr;    // buffer read pointer

// IO controller writes to buffer
always @(posedge io_din_strobe)
	buffer[buffer_wptr] <= io_din;

// buffer is not busy anymore if IO controller ack'd io_rd and has 
// tranferred 512 bytes (counter wrapped to 0 again)
wire busy = io_rd || (buffer_wptr != 0);
	
// write pointer increases whenever io controller writes a byte. It's reset
// when the SoC requests a new sector.
always @(negedge io_din_strobe or posedge io_rd_req) begin
	if(io_rd_req) buffer_wptr <= 9'd0;
	else 			  buffer_wptr <= buffer_wptr + 9'd1;
end

// clock data out of buffer to allow for embedded ram
reg [7:0] buffer_dout;
always @(posedge clk)
	buffer_dout <= buffer[buffer_rptr];

// read pointer increases whenever cpu reads a byte from the buffer. It's
// reset when the SoC requests a new sector
always @(posedge cpu_byte_rd or posedge io_rd_req) begin
  if(io_rd_req) buffer_rptr <= 9'd0;
  else          buffer_rptr <= buffer_rptr + 9'd1;
end
	
// ---------------------- CPU register read/write -----------------

reg io_rd_req;     // cpu triggers a sector read
reg cpu_byte_rd;   // cpu read a byte

// only addresses 4 and 5 can be read and return valid data	
assign dout = (addr == 4)?{7'b0000000, busy }:
				  (addr == 5)?buffer_dout:
					8'hff;

always @(negedge clk) begin
	io_rd_req <= 1'b0;
	cpu_byte_rd <= 1'b0;

	// cpu reads from the data register
	if(rd && addr == 5)
		cpu_byte_rd <= 1'b1;
	
	if(wr) begin
		case(addr)
			// cpu writes the four bytes of the sector address
			0: io_lba[31:24] <= din;
			1: io_lba[23:16] <= din;
			2: io_lba[15: 8] <= din;
			3: io_lba[ 7: 0] <= din;
			// cpu writes 1 to bit 0 of the control register
			4: io_rd_req <= din[0];
		endcase
	end
end

endmodule
