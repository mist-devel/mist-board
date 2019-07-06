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
	input  clk_reg,
	input  isGBC,
	input  isGBC_game,

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
	output [14:0] lcd_data,
	output reg irq,
	output reg vblank_irq,

	// vram connection
	output [1:0] mode,
	output vram_rd,
	output [12:0] vram_addr,
	input [7:0] vram_data,

	// vram connection bank1 (GBC)
	input [7:0] vram1_data,

	// dma connection
	output dma_rd,
	output [15:0] dma_addr,
	input [7:0] dma_data
);

localparam STAGE2  = 9'd250;   // oam + disp + pause
localparam OAM_LEN = 80;
localparam OAM_LEN16 = OAM_LEN/16;
localparam MODE3_OFFSET = 8'd16;

wire sprite_pixel_active;
wire [1:0] sprite_pixel_data;
wire sprite_pixel_cmap;
wire sprite_pixel_prio;

wire [7:0] oam_do;
wire [3:0] sprite_index = h_cnt[7:4] - OAM_LEN16[3:0];   // memory io starts at h_cnt == 16
wire [10:0] sprite_addr;

//gbc
wire [2:0] sprite_pixel_cmap_gbc;

// "data strobe" for the two bytes each sprite line consists of
wire [1:0] sprite_dvalid = {
	(h_cnt[3:0] == 4'hf) && !vblank && !hblank,
	(h_cnt[3:0] == 4'h7) && !vblank && !hblank };

sprites sprites (
	.clk      ( clk          ),
	.clk_reg  ( clk_reg      ),
	.size16   ( lcdc_spr_siz ),
	.isGBC_game ( isGBC&&isGBC_game ),

	.v_cnt    ( v_cnt        ),
	.h_cnt    ( h_cnt-STAGE2 ),     // sprites are added in second stage
	.sort     ( h_cnt == 0   ),     // start of oam phase

	.pixel_active ( sprite_pixel_active ),
	.pixel_data   ( sprite_pixel_data   ),
	.pixel_cmap   ( sprite_pixel_cmap   ),
	.pixel_prio   ( sprite_pixel_prio   ),

	.index    ( sprite_index                ),
	.addr     ( sprite_addr                 ),
	.dvalid   ( sprite_dvalid               ),
	.data     ( vram_data                   ),
	.data1    ( isGBC?vram1_data:vram_data  ),

	//gbc
	.pixel_cmap_gbc ( sprite_pixel_cmap_gbc ),

	.oam_wr   ( oam_wr       ),
	.oam_addr ( oam_addr     ),
	.oam_di   ( oam_di       ),
	.oam_do   ( oam_do       )
);

// give dma access to oam
wire [7:0] oam_addr = dma_active?dma_addr[7:0]:cpu_addr;
wire oam_wr = dma_active?(dma_cnt[1:0] == 2):(cpu_wr && cpu_sel_oam && !(mode==3 || mode==2));
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
reg [7:0] scy_r;   // stable over line
reg [7:0] scx;
reg [7:0] scx_r;   // stable over line

// ff44 line counter
wire [7:0] ly = v_cnt;

// ff45 line counter compare
wire lyc_match = (ly == lyc);
reg [7:0] lyc;
reg lyc_changed=0;

reg [7:0] bgp;
reg [7:0] obp0;
reg [7:0] obp1;

reg [7:0] wy;
reg [7:0] wy_r;   // stable over line

reg [7:0] wx;
reg [7:0] wx_r;   // stable over line


//ff68-ff6A GBC
//FF68 - BCPS/BGPI  - Background Palette Index
reg [5:0] bgpi; //Bit 0-5   Index (00-3F)
reg bgpi_ai;    //Bit 7     Auto Increment  (0=Disabled, 1=Increment after Writing)

//FF69 - BCPD/BGPD - Background Palette Data
reg[7:0] bgpd [63:0]; //64 bytes

//FF6A - OCPS/OBPI - Sprite Palette Index
reg [5:0] obpi; //Bit 0-5   Index (00-3F)
reg obpi_ai;    //Bit 7     Auto Increment  (0=Disabled, 1=Increment after Writing)

//FF6B - OCPD/OBPD - Sprite Palette Data
reg[7:0] obpd [63:0]; //64 bytes

// --------------------------------------------------------------------
// ----------------------------- DMA engine ---------------------------
// --------------------------------------------------------------------

assign dma_addr = { dma, dma_cnt[9:2] };
assign dma_rd = dma_active;

reg dma_active;
reg [7:0] dma;
reg [9:0] dma_cnt;     // dma runs 4*160 clock cycles = 160us @ 4MHz
always @(posedge clk_reg) begin
	if(reset)
		dma_active <= 1'b0;
	else begin
		// writing the dma register engages the dma engine
		if(cpu_sel_reg && cpu_wr && (cpu_addr == 8'h46)) begin
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

always @(posedge clk_reg) begin
	irq <= 1'b0;
	vblank_irq <= 1'b0;

	if(stat[6] && h_cnt == 0 && lyc_match)
		irq <= 1'b1;

	if(stat[6] && lyc_changed == 1 && h_cnt > 0 && lyc_match)
		irq <= 1'b1;

	// begin of oam phase
	if(stat[5] && (h_cnt == 0))
		irq <= 1'b1;

	// begin of vblank
	if((h_cnt == 455) && (v_cnt == 143)) begin
		if (stat[4])
			irq <= 1'b1;
		vblank_irq <= 1'b1;
	end

	// begin of hblank
	if(stat[3] && (h_cnt == OAM_LEN + 160 + hextra))
		irq <= 1'b1;
end

// --------------------------------------------------------------------
// --------------------- CPU register interface -----------------------
// --------------------------------------------------------------------
integer ii=0;
always @(posedge clk_reg) begin
	if(reset) begin
		lcdc <= 8'h00;  // screen must be off since dmg rom writes to vram
		scy <= 8'h00;
		scx <= 8'h00;
		wy <= 8'h00;
		wx <= 8'h00;
		stat <= 8'h00;
		bgp <= 8'hfc;
		obp0 <= 8'hff;
		obp1 <= 8'hff;

		bgpi <= 6'h0;
		obpi <= 6'h0;
		bgpi_ai <= 1'b0;
		obpi_ai <= 1'b0;

		for (ii=0;ii<64;ii=ii+1)begin
			bgpd[ii] <= 8'h00;
			obpd[ii] <= 8'h00;
		end

	end else begin
	   lyc_changed<=0;
		if(cpu_sel_reg && cpu_wr) begin
			case(cpu_addr)
				8'h40:	lcdc <= cpu_di;
				8'h41:	stat <= cpu_di;
				8'h42:	scy <= cpu_di;
				8'h43:	scx <= cpu_di;
				// a write to 4 is supposed to reset the v_cnt
				8'h45:	begin
								lyc <= cpu_di;
								lyc_changed<=1;
							end
				8'h46:	dma <= cpu_di;
				8'h47:	bgp <= cpu_di;
				8'h48:	obp0 <= cpu_di;
				8'h49:	obp1 <= cpu_di;
				8'h4a:	wy <= cpu_di;
				8'h4b:	wx <= cpu_di;

				//gbc
				8'h68: begin
							bgpi <= cpu_di[5:0];
							bgpi_ai <= cpu_di[7];
						 end
				8'h69: begin
							if (mode != 3) begin
								bgpd[bgpi] <= cpu_di;
								if (bgpi_ai)
									bgpi <= bgpi + 6'h1;
							end
						 end
				8'h6A: begin
							obpi <= cpu_di[5:0];
							obpi_ai <= cpu_di[7];
						 end
				8'h6B: begin
							if (mode != 3) begin
								obpd[obpi] <= cpu_di;
								if (obpi_ai)
								  obpi <= obpi + 6'h1;
							end
						 end
			endcase
		end
	end
end

assign cpu_do =
	cpu_sel_oam?oam_do:
	(cpu_addr == 8'h40)?lcdc:
	(cpu_addr == 8'h41)?{1'b1,stat[6:3], lyc_match, mode}:
	(cpu_addr == 8'h42)?scy:
	(cpu_addr == 8'h43)?scx:
	(cpu_addr == 8'h44)?ly:
	(cpu_addr == 8'h45)?lyc:
	(cpu_addr == 8'h46)?dma:
	(cpu_addr == 8'h47)?bgp:
	(cpu_addr == 8'h48)?obp0:
	(cpu_addr == 8'h49)?obp1:
	(cpu_addr == 8'h4a)?wy:
	(cpu_addr == 8'h4b)?wx:
	isGBC?
		(cpu_addr == 8'h68)?{bgpi_ai,1'd0,bgpi}:
		(cpu_addr == 8'h69 && mode != 3)?bgpd[bgpi]:
		(cpu_addr == 8'h6a)?{obpi_ai,1'd0,obpi}:
		(cpu_addr == 8'h6b && mode != 3)?obpd[obpi]:
		8'hff:
	8'hff;

// --------------------------------------------------------------------
// ----------------- second output stage: sprites ---------------------
// --------------------------------------------------------------------

assign lcd_data = stage2_data;
assign lcd_clkena = stage2_clkena;

reg [14:0] stage2_data;
reg stage2_clkena;

reg [1:0] stage2_buffer [159:0];
reg [3:0] stage2_bgp_buffer_pix [159:0]; //GBC keep record of palette used for tile and priority

reg [7:0] stage2_wptr;
reg [7:0] stage2_rptr;


wire [5:0] palette_index = isGBC_game? 
								(stage2_bgp_buffer_pix[stage2_rptr][2:0] << 3) + (stage2_buffer[stage2_rptr]<<1):  //GBC game
							//GB game in GBC mode
							(stage2_buffer[stage2_rptr] == 2'b00)?{3'd0,bgp[1:0],1'b0}:
							(stage2_buffer[stage2_rptr] == 2'b01)?{3'd0,bgp[3:2],1'b0}:
							(stage2_buffer[stage2_rptr] == 2'b10)?{3'd0,bgp[5:4],1'b0}:
							{3'd0,bgp[7:6],1'b0};

// apply bg palette
wire [14:0] stage2_bg_pix = (!lcdc_bg_ena && !window_ena)?15'h7FFF:  // background off?
	isGBC?{bgpd[palette_index+1][6:0],bgpd[palette_index]}: //gbc
	(stage2_buffer[stage2_rptr] == 2'b00)?{13'd0,bgp[1:0]}:
	(stage2_buffer[stage2_rptr] == 2'b01)?{13'd0,bgp[3:2]}:
	(stage2_buffer[stage2_rptr] == 2'b10)?{13'd0,bgp[5:4]}:
	{13'd0,bgp[7:6]};



// apply sprite palette

wire [5:0] sprite_palette_index = isGBC_game? 
									(sprite_pixel_cmap_gbc << 3) + (sprite_pixel_data<<1): //gbc game
								//GB game in GBC mode
								(sprite_pixel_data == 2'b00)? (sprite_pixel_cmap << 3) + (obp[1:0]<<1):
								(sprite_pixel_data == 2'b01)? (sprite_pixel_cmap << 3) + (obp[3:2]<<1):
								(sprite_pixel_data == 2'b10)? (sprite_pixel_cmap << 3) + (obp[5:4]<<1):
								(sprite_pixel_cmap << 3) + (obp[7:6]<<1);

wire [7:0] obp = sprite_pixel_cmap?obp1:obp0;
wire [14:0] sprite_pix = isGBC?{obpd[sprite_palette_index+1][6:0],obpd[sprite_palette_index]}: //gbc
							 (sprite_pixel_data == 2'b00)?{13'd0,obp[1:0]}:
							 (sprite_pixel_data == 2'b01)?{13'd0,obp[3:2]}:
							 (sprite_pixel_data == 2'b10)?{13'd0,obp[5:4]}:
							 {13'd0,obp[7:6]};

// https://forums.nesdev.com/viewtopic.php?f=20&t=10771&sid=8fdb6e110fd9b5434d4a567b1199585e#p122222
// priority list: BG0 < OBJL < BGL < OBJH < BGH
wire bg_piority = isGBC&&isGBC_game&&stage2_bgp_buffer_pix[stage2_rptr][3];
wire [1:0] bg_color = stage2_buffer[stage2_rptr];
reg sprite_pixel_visible;

always @(*) begin
	sprite_pixel_visible = 1'b0;
	if (sprite_pixel_active && lcdc_spr_ena) begin		// pixel active and sprites enabled

		if (isGBC&&isGBC_game) begin
			if (sprite_pixel_data == 2'b00)
				sprite_pixel_visible = 1'b0;
			else if (bg_color == 2'b00)
				sprite_pixel_visible = 1'b1;
			else if (!lcdc_bg_ena)
				sprite_pixel_visible = 1'b1;
			else if (bg_piority)
				sprite_pixel_visible = 1'b0;
			else if (!sprite_pixel_prio) //sprite pixel priority is enabled
				sprite_pixel_visible = 1'b1;

		end else begin
			if (sprite_pixel_data == 2'b00)
				sprite_pixel_visible = 1'b0;
			else if (bg_color == 2'b00)
				sprite_pixel_visible = 1'b1;
			else if (!sprite_pixel_prio) //sprite pixel priority is enabled
				sprite_pixel_visible = 1'b1;
		end

	end

end

always @(posedge clk) begin
	if(h_cnt == 455) begin
		stage2_wptr <= 8'h00;
		stage2_rptr <= 8'h00;
	end

	if(stage1_clkena) begin
		stage2_buffer[stage2_wptr] <= stage1_data;
		stage2_bgp_buffer_pix[stage2_wptr] <= {bg_tile_attr_old[7],bg_tile_attr_old[2:0]};  //GBC: buffer palette and Priority Bit
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

reg [7:0] tile_shift_0_x;
reg [7:0] tile_shift_1_x;


reg [7:0] bg_tile;
reg [7:0] bg_tile_data0;
reg [7:0] bg_tile_data1;


wire stage1_clkena = !vblank && hdvalid;
wire [1:0] stage1_data = (isGBC&&isGBC_game&&bg_tile_attr_old[5])?{ tile_shift_1_x[0], tile_shift_0_x[0] }:{ tile_shift_1[7], tile_shift_0[7] };

wire [7:0] vram_gbc_data = bg_tile_attr_new[3]?vram1_data:vram_data; //gbc check tile bank
reg [7:0] bg_tile_attr_old,bg_tile_attr_new; //GBC

// read data half a clock cycle after ram has been selected
always @(posedge clk) begin

	// every memory access is two pixel cycles
	if(h_cnt[0]) begin
		if(bg_tile_map_rd) bg_tile <= vram_data;

		if (isGBC&&isGBC_game) begin
			if(bg_tile_map_rd) bg_tile_attr_new <= vram1_data; //get tile attr from vram bank1
			if(bg_tile_data0_rd) bg_tile_data0 <= vram_gbc_data;
		   if(bg_tile_data1_rd) bg_tile_data1 <= vram_gbc_data;
		end else begin
			if(bg_tile_data0_rd) bg_tile_data0 <= vram_data;
		   if(bg_tile_data1_rd) bg_tile_data1 <= vram_data;
		end

		// sprite data is evaluated inside the sprite engine
	end

	// shift bg/window pixels out
	if(bg_tile_obj_rd && h_cnt[0]) begin
	   bg_tile_attr_old <= bg_tile_attr_new;
		tile_shift_0 <= bg_tile_data0;
		tile_shift_1 <= bg_tile_data1;
		tile_shift_0_x <= bg_tile_data0;
		tile_shift_1_x <= bg_tile_data1;
	end else begin
		tile_shift_0 <= { tile_shift_0[6:0], 1'b0 };
		tile_shift_1 <= { tile_shift_1[6:0], 1'b0 };
		//GBC x-flip
		tile_shift_0_x <= { 1'b0,tile_shift_0_x[7:1]};
		tile_shift_1_x <= { 1'b0,tile_shift_1_x[7:1]};
	end
end

assign vram_rd = lcdc_on && (bg_tile_map_rd || bg_tile_data0_rd ||
										bg_tile_data1_rd || bg_tile_obj_rd);

wire bg_tile_a12 = !lcdc_tile_data_sel?(~bg_tile[7]):1'b0;

wire tile_map_sel = window_ena?lcdc_win_tile_map_sel:lcdc_bg_tile_map_sel;

wire [2:0] tile_line_gbc = bg_tile_attr_new[6]? (3'b111 - tile_line): tile_line; //GBC: check if flipped y

assign vram_addr =
	bg_tile_map_rd?{2'b11, tile_map_sel, bg_tile_map_addr}:
	bg_tile_data0_rd?{bg_tile_a12, bg_tile, isGBC&&isGBC_game?tile_line_gbc:tile_line, 1'b0}:
	bg_tile_data1_rd?{bg_tile_a12, bg_tile, isGBC&&isGBC_game?tile_line_gbc:tile_line, 1'b1}:
	{1'b0, sprite_addr, h_cnt[3]};

reg [9:0] bg_tile_map_addr;

wire vblank  = (v_cnt >= 144);

// x scroll & 7 needs one more memory read per line
reg [1:0] hextra_tiles;
wire [7:0] hextra = { 3'b000, hextra_tiles, 3'b000 }+MODE3_OFFSET;
wire hblank  = ((h_cnt < OAM_LEN) || (h_cnt >= 160+OAM_LEN+hextra));
wire oam     = (h_cnt <= OAM_LEN);                            // 80 clocks oam
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
	(ly <= 144 && h_cnt<4)?2'b00:  //AntonioND https://github.com/AntonioND/giibiiadvance/blob/master/docs/TCAGBD.pdf
   !lcdc_on?2'b00:
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

	if (!lcdc_on) begin // don't increase counters if lcdoff
		//reset counters
		h_cnt <= 9'd6;
		v_cnt <= 8'd0;

	end else begin

		if(h_cnt != 455) begin
			h_cnt <= h_cnt + 9'd1;

			// make sure sginals don't change during the line
			// latch at latest possible moment (one clock before display starts)
			if(h_cnt == OAM_LEN-2) begin
				scx_r <= scx;
				wx_r <= wx;
				scy_r <= scy;
				wy_r <= wy;
			end

			// increment address at the end of each 8-pixel-cycle. But don't
			// increment while waiting for current cycle to end due to window start
			if(!hblank && h_cnt[2:0] == 3'b111 && (skip <= 8))
				bg_tile_map_addr[4:0] <= bg_tile_map_addr[4:0] + 1'd1;

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
//				wy_r <= wy;
			end
		end
	end
end

endmodule
