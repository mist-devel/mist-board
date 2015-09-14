//
// video.v
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

module video (
	input  reset,
   input  clk,    // 4 Mhz cpu clock
	
	// cpu register adn oam interface
	input  cpu_sel_oam,
	input  cpu_sel_reg,
	input [7:0] cpu_addr,
	input  cpu_wr,
	input [7:0] cpu_di,
	output [7:0] cpu_do,
	
	// output to lcd
	output lcd_on,
	output lcd_clkena,
	output [1:0] lcd_data,
	output reg irq,
	
	// vram connection
	output [1:0] mode,
	output vram_rd,
	output [12:0] vram_addr,
	input [7:0] vram_data,

	// dma connection
	output dma_rd,
	output [15:0] dma_addr,
	input [7:0] dma_data
);

localparam STAGE2  = 9'd250;   // oam + disp + pause
localparam OAM_LEN = 80;

wire sprite_pixel_active;
wire [1:0] sprite_pixel_data;
wire sprite_pixel_cmap;
wire sprite_pixel_prio;

wire [7:0] oam_do;
wire [3:0] sprite_index = h_cnt[7:4]-(OAM_LEN/16);   // memory io starts at h_cnt == 16
wire [10:0] sprite_addr;

// "data strobe" for the two bytes each sprite line consists of
wire [1:0] sprite_dvalid = {
	(h_cnt[3:0] == 4'hf) && !vblank && !hblank,
	(h_cnt[3:0] == 4'h7) && !vblank && !hblank };

sprites sprites (
	.clk      ( clk          ),
	.size16   ( lcdc_spr_siz ),
	
	.v_cnt    ( v_cnt        ),
	.h_cnt    ( h_cnt-STAGE2 ),     // sprites are added in second stage
	.sort     ( h_cnt == 0   ),     // start of oam phase

	.pixel_active ( sprite_pixel_active ),
	.pixel_data   ( sprite_pixel_data   ),
	.pixel_cmap   ( sprite_pixel_cmap   ),
	.pixel_prio   ( sprite_pixel_prio   ),

	.index    ( sprite_index ),
	.addr     ( sprite_addr  ),
	.dvalid   ( sprite_dvalid),
	.data     ( vram_data    ),
	
	.oam_wr   ( oam_wr       ),
	.oam_addr ( oam_addr     ),
	.oam_di   ( oam_di       ),
	.oam_do   ( oam_do       )
);

// give dma access to oam
wire [7:0] oam_addr = dma_active?dma_addr[7:0]:cpu_addr;
wire oam_wr = dma_active?(dma_cnt[1:0] == 2):(cpu_wr && cpu_sel_oam);
wire [7:0] oam_di = dma_active?dma_data:cpu_di;


assign lcd_on = lcdc_on;

// $ff40 LCDC
wire lcdc_on = lcdc[7];
wire lcdc_win_tile_map_sel = lcdc[6];
wire lcdc_win_ena = lcdc[5];
wire lcdc_tile_data_sel = lcdc[4];
wire lcdc_bg_tile_map_sel = lcdc[3];
wire lcdc_spr_siz = lcdc[2];
wire lcdc_spr_ena = lcdc[1];
wire lcdc_bg_ena = lcdc[0];
reg [7:0] lcdc;

// ff41 STAT
reg [7:0] stat;

// ff42, ff43 background scroll registers
reg [7:0] scy;
reg [7:0] scy_r;   // stable over entire image
reg [7:0] scx;
reg [7:0] scx_r;   // stable over line

// ff44 line counter
reg [7:0] ly;

// ff45 line counter compare
wire lyc_match = (ly == lyc);
reg [7:0] lyc;

reg [7:0] bgp;
reg [7:0] obp0;
reg [7:0] obp1;

reg [7:0] wy;
reg [7:0] wy_r;   // stable over entire image
reg [7:0] wx;
reg [7:0] wx_r;   // stable over line

// --------------------------------------------------------------------
// ----------------------------- DMA engine ---------------------------
// --------------------------------------------------------------------

assign dma_addr = { dma, dma_cnt[9:2] };
assign dma_rd = dma_active;

reg dma_active;
reg [7:0] dma;
reg [9:0] dma_cnt;     // dma runs 4*160 clock cycles = 160us @ 4MHz
always @(posedge clk) begin
	if(reset)
		dma_active <= 1'b0;
	else begin
		// writing the dma register engages the dma engine
		if(cpu_sel_reg && cpu_wr && (cpu_addr[3:0] == 4'h6)) begin
			dma_active <= 1'b1;
			dma_cnt <= 10'd0;
		end else if(dma_cnt != 160*4-1)
			dma_cnt <= dma_cnt + 10'd1;
		else 
			dma_active <= 1'b0;
	end
end

// --------------------------------------------------------------------
// ------------------------------- IRQs -------------------------------
// --------------------------------------------------------------------

always @(posedge clk) begin
	irq <= 1'b0;

	// lyc=ly coincidence
	if(stat[6] && (h_cnt == 0) && lyc_match)
		irq <= 1'b1;
		
	// begin of oam phase
	if(stat[5] && (h_cnt == 0))
		irq <= 1'b1;

	// begin of vblank
	if(stat[4] && (h_cnt == 455) && (v_cnt == 143))
		irq <= 1'b1;

	// begin of hblank
	if(stat[3] && (h_cnt == OAM_LEN + 160 + hextra))
		irq <= 1'b1;
end

// --------------------------------------------------------------------
// --------------------- CPU register interface -----------------------
// --------------------------------------------------------------------

always @(posedge clk) begin
	if(reset) begin
		lcdc <= 8'h00;  // screen must be off since dmg rom writes to vram
		scy <= 8'h00;
		scx <= 8'h00;
		wy <= 8'h00;
		wx <= 8'h00;
		bgp <= 8'hfc;
		obp0 <= 8'hff;
		obp1 <= 8'hff;
	end else begin
		if(cpu_sel_reg && cpu_wr) begin
			case(cpu_addr[3:0]) 
				4'h0:	lcdc <= cpu_di;
				4'h1:	stat <= cpu_di;
				4'h2:	scy <= cpu_di;
				4'h3:	scx <= cpu_di;
				// a write to 4 is supposed to reset the v_cnt
				4'h5:	lyc <= cpu_di;
				4'h6:	dma <= cpu_di;
				4'h7:	bgp <= cpu_di;
				4'h8:	obp0 <= cpu_di;
				4'h9:	obp1 <= cpu_di;
				4'ha:	wy <= cpu_di;
				4'hb:	wx <= cpu_di;
			endcase
		end
	end
end

assign cpu_do = 
	cpu_sel_oam?oam_do:
	(cpu_addr[3:0] == 4'h0)?lcdc:
	(cpu_addr[3:0] == 4'h1)?{stat[7:3], lyc_match, mode}:
	(cpu_addr[3:0] == 4'h2)?scy:
	(cpu_addr[3:0] == 4'h3)?scx:
	(cpu_addr[3:0] == 4'h4)?ly:
	(cpu_addr[3:0] == 4'h5)?lyc:
	(cpu_addr[3:0] == 4'h6)?dma:
	(cpu_addr[3:0] == 4'h7)?bgp:
	(cpu_addr[3:0] == 4'h8)?obp0:
	(cpu_addr[3:0] == 4'h9)?obp1:
	(cpu_addr[3:0] == 4'ha)?wy:
	(cpu_addr[3:0] == 4'hb)?wx:
	8'hff;
	
// --------------------------------------------------------------------
// ----------------- second output stage: sprites ---------------------
// --------------------------------------------------------------------

assign lcd_data = stage2_data;
assign lcd_clkena = stage2_clkena;

reg [1:0] stage2_data;
reg stage2_clkena;

reg [1:0] stage2_buffer [159:0];
reg [7:0] stage2_wptr;
reg [7:0] stage2_rptr;

// apply bg palette
wire [1:0] stage2_bg_pix = (!lcdc_bg_ena && !window_ena)?2'b11:  // background off?
	(stage2_buffer[stage2_rptr] == 2'b00)?bgp[1:0]:
	(stage2_buffer[stage2_rptr] == 2'b01)?bgp[3:2]:
	(stage2_buffer[stage2_rptr] == 2'b10)?bgp[5:4]:
	bgp[7:6];

// apply sprite palette
wire [7:0] obp = sprite_pixel_cmap?obp1:obp0;
wire [1:0] sprite_pix = 
	(sprite_pixel_data == 2'b00)?obp[1:0]:
	(sprite_pixel_data == 2'b01)?obp[3:2]:
	(sprite_pixel_data == 2'b10)?obp[5:4]:
	obp[7:6];

// a sprite pixel is visible if
// - sprites are enabled
// - there's a sprite at the current position
// - the sprites prioroty bit is 0, or
// - the prites priority is 1 and the backrgound color is 00
	
wire sprite_pixel_visible = 
	sprite_pixel_active && lcdc_spr_ena && 
	((!sprite_pixel_prio) || (stage2_buffer[stage2_rptr] == 2'b00));
	
always @(posedge clk) begin
	if(h_cnt == 455) begin
		stage2_wptr <= 8'h00;
		stage2_rptr <= 8'h00;
	end

	if(stage1_clkena) begin
		stage2_buffer[stage2_wptr] <= stage1_data;
		stage2_wptr <= stage2_wptr + 8'd1;
	end
	
	stage2_clkena = !vblank && stage2;
	if(stage2) begin
		// mix sprites and bg
		if(sprite_pixel_visible) stage2_data <= sprite_pix;
		else							 stage2_data <= stage2_bg_pix;
		
		stage2_rptr <= stage2_rptr + 8'd1;
	end
end

// --------------------------------------------------------------------
// --------------- first output stage: bg and window ------------------
// --------------------------------------------------------------------
	
reg window_ena;

// output shift registers for both video data bits
reg [7:0] tile_shift_0;
reg [7:0] tile_shift_1;

reg [7:0] bg_tile;
reg [7:0] bg_tile_data0;
reg [7:0] bg_tile_data1;

wire stage1_clkena = !vblank && hdvalid;
wire [1:0] stage1_data = { tile_shift_1[7], tile_shift_0[7] };

// read data half a clock cycle after ram has been selected
always @(posedge clk) begin

	// every memory access is two pixel cycles
	if(h_cnt[0]) begin
		if(bg_tile_map_rd) bg_tile <= vram_data;
		if(bg_tile_data0_rd) bg_tile_data0 <= vram_data;
		if(bg_tile_data1_rd) bg_tile_data1 <= vram_data;
		// sprite data is evaluated inside the sprite engine
	end
	
	// shift bg/window pixels out 
	if(bg_tile_obj_rd && h_cnt[0]) begin
		tile_shift_0 <= bg_tile_data0;
		tile_shift_1 <= bg_tile_data1;
	end else begin 
		tile_shift_0 <= { tile_shift_0[6:0], 1'b0 };
		tile_shift_1 <= { tile_shift_1[6:0], 1'b0 };
	end
end

assign vram_rd = lcdc_on && (bg_tile_map_rd || bg_tile_data0_rd || 
										bg_tile_data1_rd || bg_tile_obj_rd);

wire bg_tile_a12 = !lcdc_tile_data_sel?(~bg_tile[7]):1'b0;

wire tile_map_sel = window_ena?lcdc_win_tile_map_sel:lcdc_bg_tile_map_sel;

assign vram_addr =
	bg_tile_map_rd?{2'b11, tile_map_sel, bg_tile_map_addr}:
	bg_tile_data0_rd?{bg_tile_a12, bg_tile, tile_line, 1'b0}:
	bg_tile_data1_rd?{bg_tile_a12, bg_tile, tile_line, 1'b1}:
	{1'b0, sprite_addr, h_cnt[3]};

reg [9:0] bg_tile_map_addr;

wire vblank  = (v_cnt >= 144);

// x scroll & 7 needs one more memory read per line
reg [1:0] hextra_tiles;
wire [7:0] hextra = { 3'b000, hextra_tiles, 3'b000 };
wire hblank  = ((h_cnt < OAM_LEN) || (h_cnt >= 160+OAM_LEN+hextra));
wire oam     = (h_cnt < OAM_LEN);                            // 80 clocks oam
wire stage2  = ((h_cnt >= STAGE2) && (h_cnt < STAGE2+160));  // output out of stage2

// first valid pixels are delivered 8 clocks after end of hblank
// wire hdvalid = ((h_cnt >= OAM_LEN+8) && (h_cnt < 160+OAM_LEN+8));
wire hdvalid = de;

reg de;
reg [7:0] skip;
reg [7:0] pcnt;

localparam STATE_HBLANK = 0;
localparam STATE_OAM    = 1;
localparam STATE_ACTIVE = 2;

always @(negedge clk) begin
	if(h_cnt == 455) begin
		// end of line
		
		de <= 1'b0;
		hextra_tiles <= 2'd0;
		pcnt <= 8'd0;
		skip <= 8'd0;
	end else if(h_cnt == OAM_LEN) begin
		// start of line
	
		// skip entire oam time plus time until first data is delivered plus
		// time to skip the pixels according to the horizontal scroll position 
		// (or the window start if line starts with window)
		if(lcdc_win_ena && (v_cnt >= wy_r) && (wx_r < 8))
			skip <= 8'd8 + (8'd7 - wx_r) - 8'd1;
		else
			skip <= 8'd8 + scx_r[2:0] - 8'd1;
		
		// calculate how many extra tiles will have to be read in this line
		if(lcdc_win_ena && (v_cnt >= wy_r) && (wx_r < 168)) begin
			// window needs at least one extra cycle, two if bg scroll position or 
			// window are not 8 pixel aligned
			if((wx_r[2:0] != 3'd7) || (scx_r[2:0] != 3'd0)) begin
				if(wx_r[2:0] > ~scx_r[2:0])
					hextra_tiles <= 2'd3;
				else
					hextra_tiles <= 2'd2;
			end else
				hextra_tiles <= 2'd1;
		end else 
			if(scx_r[2:0] != 3'd0)
				hextra_tiles <= 2'd1;
	end else begin
		if(win_start) begin
			// if window starts skip until end of current cycle and skip 
			// pixels until new window data is ready
			skip <= { 5'b00000 ,~h_cnt[2:0] } + 8'd8;
			de <= 1'b0;
		end

		if(skip) skip <= skip - 8'd1;
	
		// (re-)enable display at the end of the wait phase
		if(skip == 1)
			de <= 1'b1;

		if(de) begin
			if(pcnt != 160)
				pcnt <= pcnt + 8'd1;
			else
				de <= 1'b0;
		end
	end
end
	
// cycle through the B01s states
wire bg_tile_map_rd = (!vblank) && (!hblank) && (h_cnt[2:1] == 2'b00);
wire bg_tile_data0_rd = (!vblank) && (!hblank) && (h_cnt[2:1] == 2'b01);
wire bg_tile_data1_rd = (!vblank) && (!hblank) && (h_cnt[2:1] == 2'b10);
wire bg_tile_obj_rd = (!vblank) && (!hblank) && (h_cnt[2:1] == 2'b11);

// Mode 00:  h-blank
// Mode 01:  v-blank
// Mode 10:  oam
// Mode 11:  oam and vram
assign mode = 
	vblank?2'b01:
	oam?2'b10:
	hblank?2'b00:
	2'b11;

reg [8:0] h_cnt;            // max 455
reg [7:0] v_cnt;            // max 153

// line inside the background/window currently being drawn
wire [7:0] win_line = v_cnt - wy_r;
wire [7:0] bg_line = v_cnt + scy_r;
wire [2:0] tile_line = window_ena?win_line[2:0]:bg_line[2:0];

wire win_start = lcdc_win_ena && (v_cnt >= wy_r) && de && (wx_r >= 7) && (pcnt == wx_r-8);

// each memory access takes two cycles
always @(negedge clk) begin
	// this ly change h_cnt is wrong!!!
	if(h_cnt == 0)
		ly <= (v_cnt >= 153)?(v_cnt-8'd153):(v_cnt+8'd1);

	if(h_cnt != 455) begin
		h_cnt <= h_cnt + 9'd1;

		// make sure sginals don't change during the line
		// latch at latest possible moment (one clock before display starts)
		if(h_cnt == OAM_LEN-2) begin
			scx_r <= scx;
			wx_r <= wx;
			scy_r <= scy;
		end

		// increment address at the end of each 8-pixel-cycle. But don't
		// increment while waiting for current cycle to end due to window start
		if(!hblank && h_cnt[2:0] == 3'b111 && (skip <= 8))
			bg_tile_map_addr[4:0] <= bg_tile_map_addr[4:0] + 10'd1;

		// begin of line
		if(h_cnt == OAM_LEN-1) begin
			// set tile map address for this line, assume there is no window
			bg_tile_map_addr[9:5] <= bg_line[7:3];
			bg_tile_map_addr[4:0] <= scx_r[7:3];
		
			// special case wx < 8: line starts with window, no background 
			// visible at all
			if(lcdc_win_ena && (v_cnt >= wy_r) && (wx_r < 8)) begin
				window_ena <= 1'b1;
				bg_tile_map_addr[9:5] <= win_line[7:3];
				bg_tile_map_addr[4:0] <= 5'd0;           // window always start with its very left
			end
		end
		
		// check if the window starts here
		if(win_start) begin
			window_ena <= 1'b1;
			bg_tile_map_addr[9:5] <= win_line[7:3];
			bg_tile_map_addr[4:0] <= 5'd0;           // window always start with its very left
		end
	end else begin
		window_ena <= 1'b0;   // next line starts with background
	
		// end of line reached
		h_cnt <= 9'd0;
			
		if(v_cnt != 153)
			v_cnt <= v_cnt + 8'd1;
		else begin
			// start of new image
			v_cnt <= 8'd0;
			
			// make sure sginals don't change during the image
			wy_r <= wy;
		end
	end
end

endmodule
