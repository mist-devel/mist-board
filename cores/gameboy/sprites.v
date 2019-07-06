//
// sprites.v
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

module sprites (
	input clk,
	input clk_reg,
	input size16,
	input isGBC_game,

	// pixel position input which the current pixel is generated for
	input [7:0] v_cnt,
	input [7:0] h_cnt,
	
	// pixel output
	output pixel_active,        // current pixel
	output [1:0] pixel_data,
	output pixel_cmap,
	output pixel_prio,
	
	//gbc
	output [2:0] pixel_cmap_gbc,

	input sort,
	input [3:0] index,          // index of sprite which video wants to read data for
	output [10:0] addr,
	input [1:0] dvalid,
	input [7:0] data,
	input [7:0] data1,

	// oam memory interface
	input oam_wr,
	input [7:0] oam_addr,
	input [7:0] oam_di,
	output [7:0] oam_do
);

localparam SPRITES = 40;

// ------------------------------------------------------------------------
// ---------------------------- priority sorting --------------------------
// ------------------------------------------------------------------------

// sprites have priority from left to right and the leftmost 10 are
// being displayed. We thus need to sort them	
wire [SPRITES*8-1:0] sprite_x;
wire [SPRITES*6-1:0] sprite_idx;

sprite_sort #(.WIDTH(SPRITES)) sprite_sort (
	.clk   ( clk         ),
	.load  ( sort        ),    // begin of oam phase
	.x     ( sprite_x    ),
	.idx   ( sprite_idx  )
);

wire [SPRITES-1:0] sprite_pixel_active;
wire [SPRITES-1:0] sprite_pixel_cmap;
wire [SPRITES-1:0] sprite_pixel_prio;
wire [1:0] sprite_pixel_data [SPRITES-1:0];
	
wire [10:0] sprite_addr [SPRITES-1:0];
wire [7:0] sprite_oam_do [SPRITES-1:0];

assign oam_do = sprite_oam_do[oam_addr[7:2]];

// address where the sprite wants to read data from
wire [5:0] sprite_idx_array [SPRITES-1:0];
wire [5:0] padded_index = {2'd0,index};
wire [5:0] prio_index = sprite_idx_array[padded_index];
assign addr = sprite_addr[prio_index];

//gbc
wire [2:0] sprite_pixel_cmap_gbc [SPRITES-1:0];
wire sprite_tile_vbank [SPRITES-1:0];

generate
genvar i;
for(i=0;i<SPRITES;i=i+1) begin : spr
	// map 1d array to 2d array
	assign sprite_idx_array[i] = sprite_idx[6*i+5:6*i];

	sprite sprite (
		.clk      ( clk_reg ),
		.size16   ( size16  ),
		.isGBC_game    ( isGBC_game  ),
		
		.sprite_index ( i   ),

		.v_cnt    ( v_cnt   ),
		.h_cnt    ( h_cnt   ),
		.x        ( sprite_x[(8*i)+7:(8*i)] ),
	
		.addr     ( sprite_addr[i] ),
		.ds       ( (prio_index == i)?dvalid:2'b00),
		.data     ( data     ),
		.data_1   ( data1    ),

		.pixel_cmap   ( sprite_pixel_cmap[i] ),
		.pixel_prio   ( sprite_pixel_prio[i] ),
		.pixel_active ( sprite_pixel_active[i] ),
		.pixel_data   ( sprite_pixel_data[i] ),
		
		
	   //gbc
	   .pixel_cmap_gbc ( sprite_pixel_cmap_gbc[i] ),
	
		.oam_wr   ( oam_wr && (oam_addr[7:2] == i) ),
		.oam_addr ( oam_addr[1:0] ),
		.oam_di   ( oam_di  ),
		.oam_do   ( sprite_oam_do[i] )
	);
end
endgenerate

// ------------------------------------------------------------------------
// ---------------------------- priority display --------------------------
// ------------------------------------------------------------------------

// only the 10 leftmost sprites are potentially being displayed

// get the indices of the 10 leftmost sprites
wire [5:0] spr0 = sprite_idx_array[0];
wire [5:0] spr1 = sprite_idx_array[1];
wire [5:0] spr2 = sprite_idx_array[2];
wire [5:0] spr3 = sprite_idx_array[3];
wire [5:0] spr4 = sprite_idx_array[4];
wire [5:0] spr5 = sprite_idx_array[5];
wire [5:0] spr6 = sprite_idx_array[6];
wire [5:0] spr7 = sprite_idx_array[7];
wire [5:0] spr8 = sprite_idx_array[8];
wire [5:0] spr9 = sprite_idx_array[9];

// if any of these is active then the current pixel is being driven by
// the sprite engine
assign pixel_active = 
	sprite_pixel_active[spr0] ||
	sprite_pixel_active[spr1] ||
	sprite_pixel_active[spr2] ||
	sprite_pixel_active[spr3] ||
	sprite_pixel_active[spr4] ||
	sprite_pixel_active[spr5] ||
	sprite_pixel_active[spr6] ||
	sprite_pixel_active[spr7] ||
	sprite_pixel_active[spr8] ||
	sprite_pixel_active[spr9];

// get the pixel information of the leftmost sprite
assign pixel_data =
	sprite_pixel_active[spr0]?sprite_pixel_data[spr0]:
	sprite_pixel_active[spr1]?sprite_pixel_data[spr1]:
	sprite_pixel_active[spr2]?sprite_pixel_data[spr2]:
	sprite_pixel_active[spr3]?sprite_pixel_data[spr3]:
	sprite_pixel_active[spr4]?sprite_pixel_data[spr4]:
	sprite_pixel_active[spr5]?sprite_pixel_data[spr5]:
	sprite_pixel_active[spr6]?sprite_pixel_data[spr6]:
	sprite_pixel_active[spr7]?sprite_pixel_data[spr7]:
	sprite_pixel_active[spr8]?sprite_pixel_data[spr8]:
	sprite_pixel_active[spr9]?sprite_pixel_data[spr9]:
	2'b00;
	
// get the colormap of the leftmost sprite
assign pixel_cmap =
	sprite_pixel_active[spr0]?sprite_pixel_cmap[spr0]:
	sprite_pixel_active[spr1]?sprite_pixel_cmap[spr1]:
	sprite_pixel_active[spr2]?sprite_pixel_cmap[spr2]:
	sprite_pixel_active[spr3]?sprite_pixel_cmap[spr3]:
	sprite_pixel_active[spr4]?sprite_pixel_cmap[spr4]:
	sprite_pixel_active[spr5]?sprite_pixel_cmap[spr5]:
	sprite_pixel_active[spr6]?sprite_pixel_cmap[spr6]:
	sprite_pixel_active[spr7]?sprite_pixel_cmap[spr7]:
	sprite_pixel_active[spr8]?sprite_pixel_cmap[spr8]:
	sprite_pixel_active[spr9]?sprite_pixel_cmap[spr9]:
	1'b0;

// get the colormap of the leftmost sprite gbc
assign pixel_cmap_gbc =
	sprite_pixel_active[spr0]?sprite_pixel_cmap_gbc[spr0]:
	sprite_pixel_active[spr1]?sprite_pixel_cmap_gbc[spr1]:
	sprite_pixel_active[spr2]?sprite_pixel_cmap_gbc[spr2]:
	sprite_pixel_active[spr3]?sprite_pixel_cmap_gbc[spr3]:
	sprite_pixel_active[spr4]?sprite_pixel_cmap_gbc[spr4]:
	sprite_pixel_active[spr5]?sprite_pixel_cmap_gbc[spr5]:
	sprite_pixel_active[spr6]?sprite_pixel_cmap_gbc[spr6]:
	sprite_pixel_active[spr7]?sprite_pixel_cmap_gbc[spr7]:
	sprite_pixel_active[spr8]?sprite_pixel_cmap_gbc[spr8]:
	sprite_pixel_active[spr9]?sprite_pixel_cmap_gbc[spr9]:
	1'b0;

// get the priority of the leftmost sprite
assign pixel_prio =
	sprite_pixel_active[spr0]?sprite_pixel_prio[spr0]:
	sprite_pixel_active[spr1]?sprite_pixel_prio[spr1]:
	sprite_pixel_active[spr2]?sprite_pixel_prio[spr2]:
	sprite_pixel_active[spr3]?sprite_pixel_prio[spr3]:
	sprite_pixel_active[spr4]?sprite_pixel_prio[spr4]:
	sprite_pixel_active[spr5]?sprite_pixel_prio[spr5]:
	sprite_pixel_active[spr6]?sprite_pixel_prio[spr6]:
	sprite_pixel_active[spr7]?sprite_pixel_prio[spr7]:
	sprite_pixel_active[spr8]?sprite_pixel_prio[spr8]:
	sprite_pixel_active[spr9]?sprite_pixel_prio[spr9]:
	1'b0;

endmodule
