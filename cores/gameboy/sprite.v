//
// sprite.v
//
// Gameboy for the MIST board https://github.com/mist-devel
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

module sprite (
	input clk,
	input size16,
	input isGBC_game,
	input [7:0] sprite_index,

	input [7:0] v_cnt,
	input [7:0] h_cnt,

	output [7:0] x,
	
	// interface to read pixel data from memory	
	output [10:0] addr,
   input [1:0] ds,
	input [7:0] data,
	input [7:0] data_1,

	output pixel_active,
	output pixel_cmap,
	output pixel_prio,
	output [1:0] pixel_data,
	
	//gbc
	output [2:0] pixel_cmap_gbc,
	
	input oam_wr,
	input [1:0] oam_addr,
	input [7:0] oam_di,
	output [7:0] oam_do
);

// x position for priority detection. Invisible sprites are far to the right and
// have minimum priority
assign x = v_visible?isGBC_game?sprite_index:x_pos:8'hff;

// register used to store pixel data for current line
reg [7:0] data0;
reg [7:0] data1;

always @(posedge clk) begin
	if(ds[0]) data0 <= flags[3]&&isGBC_game?data_1:data;
	if(ds[1]) data1 <= flags[3]&&isGBC_game?data_1:data;
end

wire [7:0] height = size16?8'd16:8'd8;

wire v_visible = (v_cnt + 8'd16 >= y_pos) && (v_cnt + 8'd16 < y_pos + height);
wire visible = v_visible && (h_cnt + 8'd8 >= x_pos) && (h_cnt < x_pos);

// x position within sprite, mirror horizontally if required
wire [7:0] col_n = h_cnt - x_pos;
wire [2:0] col = flags[5]?col_n[2:0]:~col_n[2:0];

assign pixel_data = { data1[col], data0[col] };
assign pixel_active = (pixel_data != 0) && visible;

// y position within sprite, mirror vertically if required
wire [7:0] row_n = v_cnt - y_pos;
wire [3:0] row = flags[6]?~row_n[3:0]:row_n[3:0];

// 16 pixel tall sprites use one more rwo counter bit and the lsb
// of the tile index is ignored
wire [10:0] addr8  = { tile , row[2:0]};
wire [10:0] addr16 = { tile[7:1] , row};
assign addr = size16?addr16:addr8;

assign pixel_cmap = flags[4];
assign pixel_prio = flags[7];

assign pixel_cmap_gbc = flags[2:0];

reg [7:0] y_pos;
reg [7:0] x_pos;
reg [7:0] tile;
reg [7:0] flags;

always @(posedge clk) begin
	if(oam_wr) begin
		case(oam_addr)
			0: y_pos <= oam_di;
			1: x_pos <= oam_di;
			2: tile  <= oam_di;
			3: flags <= oam_di;
		endcase
	end
end

assign oam_do = 
	(oam_addr == 0)?y_pos:
	(oam_addr == 1)?x_pos:
	(oam_addr == 2)?tile:
	 flags;

endmodule
