// 
// c1541_track
// Copyright (c) 2016 Sorgelig
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
//
/////////////////////////////////////////////////////////////////////////

module c1541_track
(
	input         clk,
	input         reset,

	output [31:0] sd_lba,
	output reg    sd_rd,
	output reg    sd_wr,
	input         sd_ack,

	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	input         save_track,
	input         change,
	input   [5:0] track,
	input   [4:0] sector,
	input   [7:0] buff_addr,
	output  [7:0] buff_dout,
	input   [7:0] buff_din,
	input         buff_we,
	output reg    busy
);

assign sd_lba = lba;

trk_dpram buffer
(
	.clock(clk),

	.address_a(sd_buff_base + base_fix + sd_buff_addr),
	.data_a(sd_buff_dout),
	.wren_a(sd_ack & sd_buff_wr),
	.q_a(sd_buff_din),

	.address_b({sector, buff_addr}),
	.data_b(buff_din),
	.wren_b(buff_we),
	.q_b(buff_dout)
);

wire [9:0] start_sectors[41] =
		'{  0,  0, 21, 42, 63, 84,105,126,147,168,189,210,231,252,273,294,315,336,357,376,395,
		  414,433,452,471,490,508,526,544,562,580,598,615,632,649,666,683,700,717,734,751};

reg [31:0] lba;
reg [12:0] base_fix;
reg [12:0] sd_buff_base;

always @(posedge clk) begin
	reg old_ack;
	reg [5:0] cur_track = 0;
	reg old_change, ready = 0;
	reg saving = 0;

	old_change <= change;
	if(~old_change & change) ready <= 1;

	old_ack <= sd_ack;
	if(sd_ack) {sd_rd,sd_wr} <= 0;

	if(reset) begin
		cur_track <= 'b111111;
		busy  <= 0;
		sd_rd <= 0;
		sd_wr <= 0;
		saving<= 0;
	end
	else
	if(busy) begin
		if(old_ack && ~sd_ack) begin
			if(sd_buff_base < 'h1800) begin
				sd_buff_base <= sd_buff_base + 13'd512;
				lba <= lba + 1'd1;
				if(saving) sd_wr <= 1;
					else sd_rd <= 1;
			end
			else
			if(saving && (cur_track != track)) begin
				saving <= 0;
				cur_track <= track;
				sd_buff_base <= 0;
				base_fix <= start_sectors[track][0] ? 13'h1F00 : 13'h0000;
				lba <= start_sectors[track][9:1];
				sd_rd <= 1;
			end
			else
			begin
				busy <= 0;
			end
		end
	end
	else
	if(ready) begin
		if(save_track && cur_track != 'b111111) begin
			saving <= 1;
			sd_buff_base <= 0;
			lba <= start_sectors[cur_track][9:1];
			sd_wr <= 1;
			busy <= 1;
		end
		else
		if((cur_track != track) || (old_change && ~change)) begin
			saving <= 0;
			cur_track <= track;
			sd_buff_base <= 0;
			base_fix <= start_sectors[track][0] ? 13'h1F00 : 13'h0000;
			lba <= start_sectors[track][9:1];
			sd_rd <= 1;
			busy <= 1;
		end
	end
end

endmodule

module trk_dpram #(parameter DATAWIDTH=8, ADDRWIDTH=13)
(
	input	                     clock,

	input	     [ADDRWIDTH-1:0] address_a,
	input	     [DATAWIDTH-1:0] data_a,
	input	                     wren_a,
	output reg [DATAWIDTH-1:0] q_a,

	input	     [ADDRWIDTH-1:0] address_b,
	input	     [DATAWIDTH-1:0] data_b,
	input	                     wren_b,
	output reg [DATAWIDTH-1:0] q_b
);

logic [DATAWIDTH-1:0] ram[0:(1<<ADDRWIDTH)-1];

always_ff@(posedge clock) begin
	if(wren_a) begin
		ram[address_a] <= data_a;
		q_a <= data_a;
	end else begin
		q_a <= ram[address_a];
	end
end

always_ff@(posedge clock) begin
	if(wren_b) begin
		ram[address_b] <= data_b;
		q_b <= data_b;
	end else begin
		q_b <= ram[address_b];
	end
end

endmodule
