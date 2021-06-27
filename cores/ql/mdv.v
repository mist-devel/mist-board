//
// mdv.v - Microdrive
//
// Sinclair QL for the MiST
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

module mdv (
   input clk,               // 21mhz clock
	input reset,
	
	input reverse,

   input mdv_drive,
   
	input sel,               // select microdrive 1 or 2

   // control bits	
	output gap,
	output tx_empty,
	output rx_ready,
	output [7:0] dout,

	// ram interface to read image
	input download,
	input [24:0] dl_addr,

	input mem_ena,	
	input mem_cycle,	
	input mem_clk,
	output reg mem_read,
	output reg [24:0] mem_addr,
	input [15:0] mem_din
);

// mdv1_ image stored at h800000, mdv2_ image stored at address h900000
wire [24:0] BASE_ADDR = (mdv_drive == 1)?25'h800000:25'h900000;
  
// a gap is permanently present if no mdv is inserted or if
// there's a gap on the inserted one. This is the signal that triggers
// the irq and can be seen by the cpu
assign gap = (!mdv_present) || mdv_gap /* synthesis keep */;  

// the mdv_rx_ready flag must be quite short as the CPU never waist for it to end
wire mdv_valid = (mdv_bit_cnt[2:0] == 2);
assign rx_ready = mdv_present && mdv_data_valid && mdv_valid /* synthesis keep */;
assign tx_empty = 1'b0;

// microdrive implementation works with images which are uploaded by the user into
// the part of ram which is unavailable to the 68k CPU (>16MB). It is then continously
// replayed from there at 200kbit/s

reg [24:0] mdv_end /* synthesis noprune */;

// determine mdv image size after download
always @(negedge download or posedge reset) begin
	if(reset) mdv_end <= BASE_ADDR;
	else      mdv_end <= dl_addr;
end

// the microdrive at 200kbit/s reads a bit every 8.3us and needs a new word
// every 80us. video hsync comes every  64us. A new word can thus be read in
// the hsync phase while video isn't accessing ram and the next word will not
// be needed before the next hsync

// gaps are 2800/3400 us which is 35 words at 200kbit/s

assign dout = mdv_bit_cnt[3]?mdv_data[7:0]:mdv_data[15:8];

// data is valid at the end of the video cycle while mem_read is active
reg [15:0] mdv_din /* synthesis noprune */;
always @(negedge mem_cycle)
	if(mem_read) mdv_din <= mem_din;

// activate memory read for the next full video cycle after mdv_required
always @(negedge mem_clk) begin
	// mdv memory enable signal from zx8301 to give mdv emulation ram access
	if(!mem_cycle)
		mem_read <= mdv_rd_wait && mem_ena;
end

// wait for next hsync to service request
reg mdv_rd_wait /* synthesis noprune */;
wire mdv_rd_ack = mem_read;
always @(posedge mdv_next_word or posedge mdv_rd_ack) begin
	if(mdv_rd_ack) mdv_rd_wait <= 1'b0;
	else           mdv_rd_wait <= 1'b1;
end

// a microdrive image is present if at least one word is in the buffer
wire mdv_present = sel && (mdv_end != BASE_ADDR);
reg mdv_next_word /* synthesis noprune */;
reg [3:0] mdv_bit_cnt /* synthesis noprune */;

// also generate gap timing
reg [9:0] mdv_gap_cnt /* synthesis noprune */;
reg mdv_gap_state /* synthesis noprune */;
reg mdv_gap_active /* synthesis noprune */;
reg [15:0] mdv_data;
reg mdv_data_valid;
reg mdv_gap;

always @(posedge mdv_clk) begin
	mdv_next_word <= 1'b0;

	mdv_bit_cnt <= mdv_bit_cnt + 4'd1;
	if(mdv_bit_cnt == 15) begin
		mdv_data <= mdv_din;
	   mdv_data_valid <= !mdv_gap_active &&
			      // don't generate data_valid for first 12 bytes (preamble)
                              (mdv_gap_cnt > 5) &&
			      // and also not for the sector internal preamble
	 		      !(mdv_gap_state && (mdv_gap_cnt > 7) && (mdv_gap_cnt < 12));
	
		mdv_next_word <= 1'b1;

	   // reset counters when address is out of range
      if((mem_addr > mdv_end)||(mem_addr < BASE_ADDR)) begin

			mem_addr <= BASE_ADDR;
			
			// assume we start at the end of a post-sector/pre-header gap
			mdv_gap_cnt <= 10'd0;      // count bytes until gap
			mdv_gap_state <= 1'b1;      // toggle header + data gap
			mdv_gap_active <= 1'b1;     // gap atm
         mdv_gap <= 1'b1; 
		end else begin
			mdv_gap_cnt <= mdv_gap_cnt + 10'd1;
						
			if(mdv_gap_active) begin

				// stop sending gap after 35 words = 70 bytes = 2800us
				if(mdv_gap_cnt == 34) begin
					mdv_gap_cnt <= 10'd0;            // restart counter until next gap
					mdv_gap_active <= 1'b0;          // no gap anymore
					mdv_gap_state <= !mdv_gap_state; // toggle gap/data
					mdv_gap <= 1'b0;
				end
			end else begin
				mem_addr <= mem_addr + 25'd1;

				if((!mdv_gap_state) && (mdv_gap_cnt == 13)) begin
					// done reading 14 words header data
					mdv_gap_cnt <= 10'd0;            // restart counter for gap
					mdv_gap_active <= 1'b1;          // now comes a gap
					mdv_gap <= 1'b1;
				end else if(mdv_gap_state && (mdv_gap_cnt == 328)) begin
					// done reading 330 words sector data
					mdv_gap_cnt <= 10'd0;            // restart counter for gap
					mdv_gap_active <= 1'b1;          // now comes a gap
					mdv_gap <= 1'b1;

					if(reverse) begin
						// The sectors on cartridges are written in descending order
						// Some images seem to contain them in ascending order. So we
				      // have to replay them backwards for better performance

				      if(mem_addr == BASE_ADDR + 343 - 1)
							mem_addr <= mdv_end - 343 + 1;
						else
							mem_addr <= mem_addr - 2*343 + 1;
					end
				end
			end
		end
	end
end

// microdrive clock runs at 200khz
// -> new word required every 80us
localparam mdv_clk_scaler = 21000000/(2*200000)-1;
reg mdv_clk;
reg [7:0] mdv_clk_cnt;
always @(posedge clk) begin
	if(mdv_clk_cnt == mdv_clk_scaler) begin
		mdv_clk_cnt <= 8'd0;
		mdv_clk <= !mdv_clk;
	end else
		mdv_clk_cnt <= mdv_clk_cnt + 8'd1;
end

endmodule
