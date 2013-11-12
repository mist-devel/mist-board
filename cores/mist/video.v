//
// video.v
// 
// Atari ST(E) shifter implementation for the MiST board
// http://code.google.com/p/mist-board/
// 
// Copyright (c) 2013 Till Harbaum <till@harbaum.org> 
// Modified by Juan Carlos González Amestoy.
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

// TODO:
// - async timing

// Overscan:
// http://codercorner.com/fullscrn.txt
// Examples: automation 000 + 001 + 097: bottom border
//           automation 196: top + bottom border

// Todo STE:
// http://alive.atari.org/alive12/ste_hwsc.php
// http://atari-ste.anvil-soft.com/html/devdocu2.htm
// + 3*4 bit palette (4096 colors)
// + lowest video base address byte
// + video counter writeable
// + pixel offset
// + line offset
// - undocumented 16 pixel "line offset overscan"

module video (
  // system interface
  input clk,                      // 31.875 MHz
  input clk27,                    // 27.000 Mhz
  input [3:0] bus_cycle,          // bus-cycle for sync

  // SPI interface for OSD
  input         sck,
  input         ss,
  input         sdi,

  // memory interface
  output reg [22:0] vaddr,   // video word address counter
  output          read,      // video read cycle
  input [15:0]    data,      // video data read
  
  // cpu register interface
  input           reg_clk,
  input           reg_reset,
  input [15:0]    reg_din,
  input           reg_sel,
  input [5:0]     reg_addr,
  input           reg_uds,
  input           reg_lds,
  input           reg_rw,
  output reg [15:0] reg_dout,
  
  // screen interface
  output reg          hs,      // H_SYNC
  output reg          vs,      // V_SYNC
  output reg [5:0]    video_r, // Red[5:0]
  output reg [5:0]    video_g, // Green[5:0]
  output reg [5:0]    video_b, // Blue[5:0]

  // system config
  input       			pal56,           // use VGA compatible 56hz for PAL
  input [1:0] 			scanlines,       // scanlines (00-none 01-25% 10-50% 11-100%)
  input [15:0] 		adjust,          // hor/ver video adjust
  input 					ste,             // enable STE featurss
  
  // signals not affected by scan doubler for internal use like irqs
  output      st_de,
  output      st_vs,
  output      st_hs
);

localparam LINE_WIDTH  = 10'd640;
localparam LINE_BORDER = 10'd80;   // width of left and right screen border

localparam STATE_SYNC   = 2'd0;
localparam STATE_BLANK  = 2'd1;
localparam STATE_BORDER = 2'd2;
localparam STATE_DISP   = 2'd3;

// ---------------------------------------------------------------------------
// ------------------------------ internal signals ---------------------------
// ---------------------------------------------------------------------------

// st_de is the internal display enable signal as used by the mfp. This is used
// by software to generate a line interrupt and to e.g. do 512 color effects.
// st_de is active low. Using memory enable (me) for this makes sure the cpu has
// plenty of time before data for the next line is starting to be fetched
assign st_de = ~me;

// hsync irq is generated at the rising edge of st_hs
assign st_hs = (st_h_state == STATE_SYNC);

// vsync irq is generated at the rising edge of st_vs
assign st_vs = (v_state == STATE_SYNC);

// ---------------------------------------------------------------------------
// -------------------------------- video mode -------------------------------
// ---------------------------------------------------------------------------

wire [121:0] config_string;

video_modes video_modes(
	// signals used to select the appropriate mode
	.mono      (mono),
	.pal       (pal),
	.pal56     (pal56),

	// resulting string containing timing values
	.mode_str  (config_string)
);

// The video config string contains 12 counter values (tX), six for horizontal
// timing and six for vertical timing. Each value has 10 bits, the total string
// is thus 120 bits long + space for some additional info like sync polarity

// display               border blank(FP)   sync   blank(BP) border 
// |--------------------|xxxxxx|#########|_______|##########|xxxxxx|
//                     t0     t1        t2      t3         t4     t5  horizontal
//                     t6     t7        t8      t9        t10    t11  vertical

// extract the various timing parameters from the config string 
wire h_sync_pol              = config_string[121];
wire [9:0] t0_h_border_right = config_string[120:111];
wire [9:0] t1_h_blank_right  = config_string[110:101];
wire [9:0] t2_h_sync         = config_string[100:91];
wire [9:0] t3_h_blank_left   = config_string[90:81];
wire [9:0] t4_h_border_left  = config_string[80:71];
wire [9:0] t5_h_end          = config_string[70:61];

wire v_sync_pol              = config_string[60];
// in overscan mode the bottom border is removed and data is displayed instead
wire [9:0] t6_v_border_bot   = overscan?config_string[49:40]:config_string[59:50];
wire [9:0] t7_v_blank_bot    = config_string[49:40];
wire [9:0] t8_v_sync         = config_string[39:30];
wire [9:0] t9_v_blank_top    = config_string[29:20];
wire [9:0] t10_v_border_top  = config_string[19:10];
wire [9:0] t11_v_end         = config_string[9:0];


// default video mode is monochrome
parameter DEFAULT_MODE = 2'd2;

// shiftmode register
reg [1:0] shmode;
wire mono = (shmode == 2'd2);
wire mid  = (shmode == 2'd1);
wire low  = (shmode == 2'd0);

// derive number of planes from shiftmode
wire [2:0] planes = mono?3'd1:(mid?3'd2:3'd4);

reg [1:0] syncmode;
reg [1:0] syncmode_latch;
wire pal = (syncmode_latch[1] == 1'b1);

 // data input buffers for up to 4 planes
reg [15:0] data_latch[4];

localparam BASE_ADDR = 23'h8000;   // default video base address 0x010000
reg [22:0] _v_bas_ad;              // video base address register

// 16 colors with 3*4 bits each (4 bits for STE, ST only uses 3 bits)
reg [3:0] palette_r[15:0];
reg [3:0] palette_g[15:0];
reg [3:0] palette_b[15:0];

// STE-only registers
reg [7:0] line_offset;            	// number of words to skip at the end of each line
reg [3:0] pixel_offset;             // number of pixels to skip at begin of line

// ---------------------------------------------------------------------------
// ----------------------------- CPU register read ---------------------------
// ---------------------------------------------------------------------------

always @(reg_sel, reg_rw, reg_uds, reg_lds, reg_addr, _v_bas_ad, shmode, vaddr, 
			syncmode, line_offset, pixel_offset, ste) begin
	reg_dout = 16'h0000;

	// read registers
	if(reg_sel && reg_rw) begin

		// video base register (r/w)
		if(reg_addr == 6'h00)      	reg_dout <= {   8'h00, _v_bas_ad[22:15] };
		if(reg_addr == 6'h01)      	reg_dout <= {   8'h00, _v_bas_ad[14: 7] };
		if(ste && reg_addr == 6'h06)  reg_dout <= {   8'h00, _v_bas_ad[ 6: 0], 1'b0 };

		// video address counter (ro on ST)
		if(reg_addr == 6'h02)      	reg_dout <= {   8'h00, vaddr[22:15]     };
		if(reg_addr == 6'h03)      	reg_dout <= {   8'h00, vaddr[14:7 ]     };
		if(reg_addr == 6'h04)      	reg_dout <= {   8'h00, vaddr[6:0], 1'b0 };

		// syncmode register
		if(reg_addr == 6'h05)      	reg_dout <= {   6'h00, syncmode, 8'h00  };

		if(ste) begin
			if(reg_addr == 6'h07)    	reg_dout <= {   8'h00, line_offset      };
			if(reg_addr == 6'h32)    	reg_dout <= { 12'h000, pixel_offset     };
		end

		// the color palette registers
		if(reg_addr >= 6'h20 && reg_addr < 6'h30 ) begin
			reg_dout[3:0]  <= palette_b[reg_addr[3:0]];
			reg_dout[7:4]  <= palette_g[reg_addr[3:0]];
			reg_dout[11:8] <= palette_r[reg_addr[3:0]];

			// return only the 3 msb in non-ste mode
			if(!ste) begin
				reg_dout[3] <= 1'b0;
				reg_dout[7] <= 1'b0;
				reg_dout[11] <= 1'b0;
			end
		end

		// shift mode register
		if(reg_addr == 6'h30)      reg_dout <= { 6'h00, shmode, 8'h00    };
	end
end

// ---------------------------------------------------------------------------
// ----------------------------- CPU register write --------------------------
// ---------------------------------------------------------------------------

// STE video address write signal is evaluated inside memory engine
wire ste_vaddr_write = ste && reg_sel && !reg_rw && !reg_lds;
 
always @(negedge reg_clk) begin
	if(reg_reset) begin
		_v_bas_ad <= BASE_ADDR;
		shmode <= DEFAULT_MODE;   // default video mode 2 => mono
		syncmode <= 2'b00;        // 60hz
   
		// disable STE hard scroll features
		line_offset <= 8'h00;
		pixel_offset <= 4'h0;

		if(DEFAULT_MODE == 0) begin
			// TOS default palette, can be disabled after tests
			palette_r[ 0] <= 4'b111; palette_g[ 0] <= 4'b111; palette_b[ 0] <= 4'b111;
			palette_r[ 1] <= 4'b111; palette_g[ 1] <= 4'b000; palette_b[ 1] <= 4'b000;
			palette_r[ 2] <= 4'b000; palette_g[ 2] <= 4'b111; palette_b[ 2] <= 4'b000;
			palette_r[ 3] <= 4'b111; palette_g[ 3] <= 4'b111; palette_b[ 3] <= 4'b000;
			palette_r[ 4] <= 4'b000; palette_g[ 4] <= 4'b000; palette_b[ 4] <= 4'b111;
			palette_r[ 5] <= 4'b111; palette_g[ 5] <= 4'b000; palette_b[ 5] <= 4'b111;
			palette_r[ 6] <= 4'b000; palette_g[ 6] <= 4'b111; palette_b[ 6] <= 4'b111;
			palette_r[ 7] <= 4'b101; palette_g[ 7] <= 4'b101; palette_b[ 7] <= 4'b101;
			palette_r[ 8] <= 4'b011; palette_g[ 8] <= 4'b011; palette_b[ 8] <= 4'b011;
			palette_r[ 9] <= 4'b111; palette_g[ 9] <= 4'b011; palette_b[ 9] <= 4'b011;
			palette_r[10] <= 4'b011; palette_g[10] <= 4'b111; palette_b[10] <= 4'b011;
			palette_r[11] <= 4'b111; palette_g[11] <= 4'b111; palette_b[11] <= 4'b011;
			palette_r[12] <= 4'b011; palette_g[12] <= 4'b011; palette_b[12] <= 4'b111;
			palette_r[13] <= 4'b111; palette_g[13] <= 4'b011; palette_b[13] <= 4'b111;
			palette_r[14] <= 4'b011; palette_g[14] <= 4'b111; palette_b[14] <= 4'b111;
			palette_r[15] <= 4'b000; palette_g[15] <= 4'b000; palette_b[15] <= 4'b000;
		end else  
			palette_b[ 0] <= 4'b111;
        
	end else begin
		// write registers
		if(reg_sel && !reg_rw) begin
			if(!reg_lds) begin
			
				// video base address hi/mid (ST and STE)
				if(reg_addr == 6'h00) _v_bas_ad[22:15] <= reg_din[7:0];
				if(reg_addr == 6'h01) _v_bas_ad[14:7] <= reg_din[7:0];

				// In the STE setting hi or mid clears the low byte for ST compatibility
				// in ST mode this doesn't harm
				if(reg_addr[5:1] == 5'h00) _v_bas_ad[6:0] <= 7'h00;

				// the low byte can only be written in STE mode
				if(ste && reg_addr == 6'h06)  _v_bas_ad[6:0] <= reg_din[7:1];
			end
				
			// writing to sync mode toggles between 50 and 60 hz modes
			if(reg_addr == 6'h05 && !reg_uds) syncmode <= reg_din[9:8];

			// writing special STE registers
			if(ste && !reg_lds) begin
				if(reg_addr == 6'h07) line_offset <= reg_din[7:0];
				if(reg_addr == 6'h32) pixel_offset <= reg_din[3:0];
				
				// Writing the video address counter happens directly inside the 
				// memory engine further below!!!
			end
				
			// the color palette registers, always write bit 3 with zero if not in 
			// ste mode as this is the lsb of ste
			if(reg_addr >= 6'h20 && reg_addr < 6'h30 ) begin
				if(!reg_uds) begin 
					if(!ste)	palette_r[reg_addr[3:0]] <= { 1'b0 , reg_din[10:8] };
					else		palette_r[reg_addr[3:0]] <= reg_din[11:8];
				end
          
				if(!reg_lds) begin
					if(!ste) begin
						palette_g[reg_addr[3:0]] <= { 1'b0, reg_din[6:4] };
						palette_b[reg_addr[3:0]] <= { 1'b0, reg_din[2:0] };
					end else begin
						palette_g[reg_addr[3:0]] <= reg_din[7:4];
						palette_b[reg_addr[3:0]] <= reg_din[3:0];
					end
				end
			end
        
			if(reg_addr == 6'h30 && !reg_uds) shmode <= reg_din[9:8];
		end
	end
end

// ---------------------------------------------------------------------------
// -------------------------- video signal generator -------------------------
// ---------------------------------------------------------------------------

// final st video data combined with OSD
wire [5:0] st_and_osd_r, st_and_osd_g, st_and_osd_b;

osd osd (
	// OSD spi interface to io controller
	.sdi   		(sdi			),
	.sck  		(sck			),
	.ss    		(ss			),

	// feed ST video signal into OSD
	.clk        (clk        ),
	.hcnt       (vga_hcnt   ),
	.vcnt       (vcnt       ),
	.in_r       ({stvid_r, 2'b00}),
	.in_g       ({stvid_g, 2'b00}),
	.in_b       ({stvid_b, 2'b00}),

	// receive signal with OSD overlayed
	.out_r      (st_and_osd_r),
	.out_g      (st_and_osd_g),
	.out_b      (st_and_osd_b)
);
	
// ----------------------- monochrome video signal ---------------------------
// mono uses the lsb of blue palette entry 0 to invert video
wire [3:0] blue0 = palette_b[0];
wire mono_bit = blue0[0]^shift_0[15];
wire [3:0] mono_rgb = de?{mono_bit, mono_bit, mono_bit, mono_bit}:4'b1000;

// ------------------------- colour video signal -----------------------------

// For ST compatibility reasons the STE has the color bit order 0321. This is 
// handled here
reg [11:0] color;
wire [3:0] color_r = { color[10:8], color[11] };
wire [3:0] color_g = { color[ 6:4], color[ 7] };
wire [3:0] color_b = { color[ 2:0], color[ 3] };

// --------------- de-multiplex color and mono into one vga signal -----------
wire [3:0] stvid_r = mono?mono_rgb:color_r;
wire [3:0] stvid_g = mono?mono_rgb:color_g;
wire [3:0] stvid_b = mono?mono_rgb:color_b;

// shift registers for up to 4 planes
reg [15:0] shift_0, shift_1, shift_2, shift_3;

// this line is to be displayed darker in scanline mode
wire scanline = scan_doubler_enable && sd_vcnt[0];

// reading the scan doubler ram results in one extra delay and thus
// reading it has to look one vga_hcnt cycle into the future
wire [9:0] border_width = t5_h_end - t4_h_border_left;
wire [9:0] vga_hcnt_next = 
	(vga_hcnt == t5_h_end)?LINE_BORDER:
	((vga_hcnt >= t4_h_border_left)?(vga_hcnt-t4_h_border_left):(vga_hcnt+LINE_BORDER+10'd1));

always @(posedge clk) begin
   hs <= h_sync_pol ^ ~vga_h_sync;
   vs <= v_sync_pol ^ ~vga_v_sync;

	// color data is permanently read from the scan doubler buffers
	color <= sd_buffer[{vga_hcnt_next, !sd_toggle}];

	// drive video output and apply scanline effect if enabled
	if(!scanline || scanlines == 2'b00) begin //if no scanlines or not a scanline
		video_r <= blank?6'b000000:st_and_osd_r;
		video_g <= blank?6'b000000:st_and_osd_g;
		video_b <= blank?6'b000000:st_and_osd_b;
	end else begin
		case(scanlines)
			2'b01: begin //25%
				video_r <= blank?6'b000000:(({1'b0,st_and_osd_r,1'b0}+{2'b00,st_and_osd_r})>>2);
				video_g <= blank?6'b000000:(({1'b0,st_and_osd_g,1'b0}+{2'b00,st_and_osd_g})>>2);
				video_b <= blank?6'b000000:(({1'b0,st_and_osd_b,1'b0}+{2'b00,st_and_osd_b})>>2);
			end

			2'b10: begin //50%
				video_r <= blank?6'b000000:{1'b0,st_and_osd_r[5:1]};
				video_g <= blank?6'b000000:{1'b0,st_and_osd_g[5:1]};
				video_b <= blank?6'b000000:{1'b0,st_and_osd_b[5:1]};
			end

			2'b11: begin //75%
				video_r <= blank?6'b000000:{2'b00,st_and_osd_r[5:2]};
				video_g <= blank?6'b000000:{2'b00,st_and_osd_g[5:2]};
				video_b <= blank?6'b000000:{2'b00,st_and_osd_b[5:2]};
			end
		endcase
	end	

	if(!scan_doubler_enable) begin
		// hires mode: shift one plane only and reload 
		// shift_0 register every 16 clocks
		if(vga_hcnt[3:0] == 4'hf) shift_0       <= data_latch[0];
		else      				     shift_0[15:1] <= shift_0[14:0];
		
		// TODO: Color modes not using scan doubler
		
	end
end

// ---------------------------------------------------------------------------
// ----------------------------- overscan detection --------------------------
// ---------------------------------------------------------------------------

// Currently only opening the bottom border for overscan is supported. Opening
// the top border should also be easy. Opening the side borders is basically 
// impossible as this requires a 100% perfect CPU and shifter timing.

reg last_syncmode, overscan_detect, overscan;

always @(posedge clk) begin
   last_syncmode <= syncmode[1];  // delay syncmode to detect changes
	 
   // this is the magic used to do "overscan".
   // the magic actually involves more than writing zero (60hz)
   // within line 200. But this is sufficient for our detection
   if(vcnt[9:2] == 8'd99) begin
		// syncmode has changed from 1 to 0 (50 to 60 hz)
      if((syncmode[1] == 1'b0) && (last_syncmode == 1'b1))
			overscan_detect <= 1'b1;
   end
	
	// latch overscan state at topleft screen edge
	if((vga_hcnt == t4_h_border_left) && (vcnt == t10_v_border_top)) begin
		// save and reset overscan
      overscan <= overscan_detect;
      overscan_detect <= 1'b0;		
	end	
end

// ---------------------------------------------------------------------------
// --------------------------- STE hard scroll shifter -----------------------
// ---------------------------------------------------------------------------

// When STE hard scrolling is being used (pixel_offset != 0) then memory reading starts
// 16 pixels earlier and data is being moved through an additional shift register 

// extra 32 bit registers required for STE hard scrolling
reg [31:0] ste_shift_0, ste_shift_1, ste_shift_2, ste_shift_3;

// shifted data
wire [15:0] ste_shifted_0, ste_shifted_1, ste_shifted_2, ste_shifted_3;

// connect STE scroll shifters for each plane
ste_shifter ste_shifter_0 (
	.skew (pixel_offset),
   .in 	(ste_shift_0),
   .out 	(ste_shifted_0)
);
				
ste_shifter ste_shifter_1 (
	.skew (pixel_offset),
   .in 	(ste_shift_1),
   .out 	(ste_shifted_1)
);

ste_shifter ste_shifter_2 (
	.skew (pixel_offset),
   .in 	(ste_shift_2),
   .out 	(ste_shifted_2)
);

ste_shifter ste_shifter_3 (
	.skew (pixel_offset),
   .in 	(ste_shift_3),
   .out 	(ste_shifted_3)
);

// move data into STE hard scroll shift registers 
always @(posedge clk) begin
	if((bus_cycle == 4'd14) && (plane == 2'd0)) begin
		// shift up 16 pixels and load new data into lower bits of shift registers
		ste_shift_0 <= { ste_shift_0[15:0], data_latch[0] };
		ste_shift_1 <= { ste_shift_1[15:0], (planes > 3'd1)?data_latch[1]:16'h0000 };
		ste_shift_2 <= { ste_shift_2[15:0], (planes > 3'd2)?data_latch[2]:16'h0000 };
		ste_shift_3 <= { ste_shift_3[15:0], (planes > 3'd2)?data_latch[3]:16'h0000 };
	end
end

// ---------------------------------------------------------------------------
// ------------------------------- scan doubler ------------------------------
// ---------------------------------------------------------------------------
		
// scandoubler is used for the mid and low rez mode
wire scan_doubler_enable = mid || low;

// scan doubler signale indicating first or second buffer used
wire sd_toggle = sd_vcnt[1];

// four scan doubler shift registers for up to 4 planes
reg [15:0] sd_shift_0, sd_shift_1, sd_shift_2, sd_shift_3;

// msb of the shift registers is the index used to access the palette registers.
// Return border color index (0) if outside display area
wire [3:0] sd_index = (!me_v)?4'd0:
	{ sd_shift_3[15], sd_shift_2[15], sd_shift_1[15], sd_shift_0[15]};
								
// line buffer for two lines of 720 pixels (640 + 2 * 40 border) 3 * 4 (STE!) bit rgb data
reg [11:0] sd_buffer [(2*(LINE_WIDTH+2*LINE_BORDER))-1:0];

// the scan doubler needs to know which border (left or right) is currently being displayed
reg sd_border_side;

// line counter used to create scan doubler states
reg [1:0] sd_vcnt;

always @(posedge clk) begin
		
	// vertical state changes at end of hsync (begin of left blank)
	if(vga_hcnt == v_event) begin
		// reset state counter two vga lines before screen start since scan doubler
		// starts prefetching data two vga lines before
		if(vcnt == (t11_v_end-10'd2))	sd_vcnt <= 2'd0;
		else                   			sd_vcnt <= sd_vcnt + 2'd1;
	end
		
	// permanently move data from data_latch into scan doublers shift registers
	if((bus_cycle == 4'd15) && (plane == 2'd0)) begin

		// normally data is directly moved from the input latches into the 
		// shift registers. Only on an ste with pixel scrolling enabled
		// the data is moved through additional shift registers
		if(!ste || (pixel_offset == 0)) begin
			// load data into shift registers as required by color depth
			sd_shift_0 <= data_latch[0];
			sd_shift_1 <= (planes > 3'd1)?data_latch[1]:16'h0000;
			sd_shift_2 <= (planes > 3'd2)?data_latch[2]:16'h0000;
			sd_shift_3 <= (planes > 3'd2)?data_latch[3]:16'h0000;
		end else begin
			sd_shift_0 <= ste_shifted_0;
			sd_shift_1 <= ste_shifted_1;
			sd_shift_2 <= ste_shifted_2;
			sd_shift_3 <= ste_shifted_3;
		end
		
	end else begin
		// do the actual shifting
		if((planes == 3'd1) ||
			((planes == 3'd2) && (vga_hcnt[0] == 1'b1)) ||
			((planes == 3'd4) && (vga_hcnt[1:0] == 2'b11))) begin
			sd_shift_0[15:1] <= sd_shift_0[14:0];
			sd_shift_1[15:1] <= sd_shift_1[14:0];
			sd_shift_2[15:1] <= sd_shift_2[14:0];
			sd_shift_3[15:1] <= sd_shift_3[14:0];
		end
	end

	// to store border colors we need to know which border we currently draw
	if(st_hcnt == t4_h_border_left)  sd_border_side <= 1'b0;
	if(st_hcnt == t0_h_border_right) sd_border_side <= 1'b1;

	// scan doubler makes the st side operate at half the vga pixel clock
	if(vga_hcnt[0] == 1'b0) begin
	
		// move data from shift register into line buffer. capture border colors as
		// well to have the scan doubler delay in the border colors as well just in
		// case a program changes border colors dynamically (e.g. different colors
		// for left and right or top and bottom borders)
		if(st_h_state == STATE_DISP) begin
			sd_buffer[{LINE_BORDER + st_hcnt[9:0], sd_toggle}] <= 
					{palette_r[sd_index], palette_g[sd_index], palette_b[sd_index]};
		end else if(st_h_state == STATE_BORDER) begin
			// move bites from left/right border into appropriate places in the line buffer
			if(!sd_border_side)
				// left border
				sd_buffer[{st_hcnt[9:0] - t4_h_border_left-10'd1, sd_toggle}] <=
							{palette_r[0], palette_g[0], palette_b[0]};
			else
				// right border
				sd_buffer[{st_hcnt[9:0] + LINE_BORDER, sd_toggle}] <=
							{palette_r[0], palette_g[0], palette_b[0]};
		end
	end
end		
		
// ---------------------------------------------------------------------------
// ------------------------------- memory engine -----------------------------
// ---------------------------------------------------------------------------

assign read = (bus_cycle[3:2] == 0) && me;  // memory enable can directly be used as a ram read signal

// current plane to be read from memory
reg [1:0] plane;  

// To be able to output the first pixel we need to have one word for every plane already
// present in memory. We thus need a "memory enable" signal which is (depending on color depth)
// 16, 32 or 64 pixel ahead of display enable
reg me, me_v;

// required pixel offset allowing for prefetch of 16 pixels in 1, 2 or 4 planes (16, 32 or 64 cycles)
wire [9:0] memory_prefetch = scan_doubler_enable?{ 4'd0, planes, 3'd0 }:{ 3'd0, planes, 4'd0 };
// ste is starting another 16 pixels earlier if horizontal hard scroll is being used
wire [9:0] ste_prefetch    = (ste && (pixel_offset != 0))?memory_prefetch:10'd0;
wire [9:0] me_h_start      = t5_h_end - memory_prefetch - ste_prefetch;
wire [9:0] me_h_end        = t0_h_border_right - memory_prefetch;
// line offset required for scan doubler
wire [9:0] me_v_offset     = scan_doubler_enable?10'd2:10'd0;
wire [9:0] me_v_start      = t11_v_end - me_v_offset;
wire [9:0] me_v_end        = t6_v_border_bot - me_v_offset;

// with scan doubler being active, there are two main clock cycles per st hor counter
// st_h_active makes sure these events only trigger once
wire st_h_active = (!scan_doubler_enable || bus_cycle[0]);
 
always @(posedge clk) begin

	// line in which memory access is enabled
	// in scan doubler mode two lines ahead of vertical display enable
	if(vga_hcnt == v_event) begin
		if(vcnt == me_v_start)  me_v <= 1'b1;
		if(vcnt == me_v_end)    me_v <= 1'b0;
	end
		
	// memory enable signal 16/32/64 bits (16*planes) ahead of display enable (de)
	// include bus cycle to stay in sync in scna doubler mode
	if(me_v && st_h_active) begin
		if(st_hcnt == me_h_start)  me <= 1'b1;
		if(st_hcnt == me_h_end)    me <= 1'b0;
	end

	// make sure each line starts with plane 0
	if(st_hcnt == me_h_start)
		plane <= 2'd0;
	
	// The video address counter is reloaded slightly before vsync
	if((vga_hcnt == t4_h_border_left) && (vcnt == t8_v_sync - 10'd3)) begin
		vaddr <= _v_bas_ad;

		// copy syncmode
		syncmode_latch <= syncmode;
	end else begin

		// video transfer happens in cycle 3
		if(bus_cycle == 3) begin
	
			// read if memory enable is active
			if(me) begin
				// move incoming video data into data latch
				data_latch[plane] <= data;
				vaddr <= vaddr + 23'd1;
			end

			// advance plane counter
			if(planes != 1) begin
				plane <= plane + 2'd1;
				if(plane == planes - 2'd1)
					plane <= 2'd0;
			end
		end
	end

	// STE has additional ways to influence video address
	if(ste) begin
		// add line offset at the end of each video line
		if(me_v && st_h_active && (st_hcnt == t2_h_sync))
			vaddr <= vaddr + line_offset;

		// STE vaddr write handling
		// bus_cycle 6 is in the middle of a cpu cycle
		if((bus_cycle == 6) && ste_vaddr_write) begin
			if(reg_addr == 6'h02) vaddr[22:15] <= reg_din[7:0];
			if(reg_addr == 6'h03) vaddr[14: 7] <= reg_din[7:0];
			if(reg_addr == 6'h04) vaddr[ 6: 0] <= reg_din[7:1];
		end 
	end
end

// ---------------------------------------------------------------------------
// ------------------------- video timing generator --------------------------
// ---------------------------------------------------------------------------

// Two horizontal timings are generated: a vga one and a st one. Both are identical
// without the scan doubler being used (mono mode), but in scan doubler mode the
// st timing has exactly half the pixel rate as the vga one and all times are exactly
// twice as long
reg [9:0] vga_hcnt;     // horizontal pixel counter
reg [1:0] vga_h_state;  // 0=sync, 1=blank, 2=border, 3=display

reg [9:0] st_hcnt;      // horizontal pixel counter
reg [1:0] st_h_state;   // 0=sync, 1=blank, 2=border, 3=display

// A seperate vertical timing is not needed, vcnt[9:1] is the st line
reg [9:0] vcnt;     		// vertical line counter
reg [1:0] v_state;  		// 0=sync, 1=blank, 2=border, 3=display

// blank level is also used during sync
wire blank  = 	(v_state == STATE_BLANK) || (vga_h_state == STATE_BLANK) || 
					(v_state == STATE_SYNC) || (vga_h_state == STATE_SYNC);
wire de     = (v_state == STATE_DISP) && (vga_h_state == STATE_DISP);

// time in horizontal timing where vertical states change (at the begin of the sync phase)
wire [9:0] v_event = t2_h_sync;

// extend adjust values to 10 bits
wire [9:0] adjust_v = { adjust[7], adjust[7], adjust[7:0] };
wire [9:0] adjust_h = { adjust[15], adjust[15], adjust[15:8] };
reg vga_v_sync, vga_h_sync;

always @(posedge clk) begin
	// ------------- horizontal VGA timing generation -------------

	// sync horizontal counter with bus cycle counter so cpu and video stay synchronous
	// even if horizotal counter is affected by resolution changes
	// the scan doubler is a special case as the atari line timing then expands over two vga
	// lines and may/must be asynchronous to the vga timing at the end of the first line
	if(vga_hcnt == t5_h_end) begin
		if((bus_cycle == 4'd15) || (scan_doubler_enable && sd_vcnt[0]))
			vga_hcnt <= 10'd0;
	end else
		vga_hcnt <= vga_hcnt + 10'd1;

	// generate user adjustable vga sync signal
	if( vga_hcnt == t2_h_sync - adjust_h ) 		vga_h_sync <= 1'b1;
	if( vga_hcnt == t3_h_blank_left - adjust_h ) vga_h_sync <= 1'b0;

	// generate horizontal video signal states
	if( vga_hcnt == t2_h_sync )                                        		vga_h_state <= STATE_SYNC;
	if((vga_hcnt == t0_h_border_right) || (vga_hcnt == t4_h_border_left))  	vga_h_state <= STATE_BORDER;
	if((vga_hcnt == t1_h_blank_right) || (vga_hcnt == t3_h_blank_left))    	vga_h_state <= STATE_BLANK;
	if( vga_hcnt == t5_h_end)                                          		vga_h_state <= STATE_DISP;
	  
	// ------------- horizontal ST timing generation -------------
	// Run st timing at full speed if no scan doubler is being used. Otherwise run
	// it at half speed
	if((!scan_doubler_enable) || vga_hcnt[0]) begin
		if(st_hcnt == t5_h_end) begin
			// changing video modes toggles scan_doubler_enable and will bring
			// the two hcnt counters out of sync. So we'll resync st_hcnt with vgs_hcnt here
			if((vga_hcnt == t5_h_end) && (!scan_doubler_enable || !sd_vcnt[0]))
				st_hcnt <= 10'd0; 
		end else 
			st_hcnt <= st_hcnt + 10'd1;

		// generate horizontal video signal states
		if( st_hcnt == t2_h_sync )                                        	st_h_state <= STATE_SYNC;
		if((st_hcnt == t0_h_border_right) || (st_hcnt == t4_h_border_left))  st_h_state <= STATE_BORDER;
		if((st_hcnt == t1_h_blank_right) || (st_hcnt == t3_h_blank_left))    st_h_state <= STATE_BLANK;
		if( st_hcnt == t5_h_end)                                          	st_h_state <= STATE_DISP;
	end

	// vertical state changes at end of hsync (begin of left blank)
	if(vga_hcnt == v_event) begin

		// ------------- vertical timing generation -------------
		// increase vcnt
		if(vcnt == t11_v_end)  vcnt <= 10'd0;
		else                   vcnt <= vcnt + 10'd1;

		if( vcnt == t8_v_sync - adjust_v ) 			vga_v_sync <= 1'b1;
		if( vcnt == t9_v_blank_top - adjust_v ) 	vga_v_sync <= 1'b0;

		// generate vertical video signal states
		if( vcnt == t8_v_sync )                                        v_state <= STATE_SYNC;
		if((vcnt == t6_v_border_bot) || (vcnt == t10_v_border_top))    v_state <= STATE_BORDER;
		if((vcnt == t7_v_blank_bot) || (vcnt == t9_v_blank_top))       v_state <= STATE_BLANK;
		if( vcnt == t11_v_end)                                         v_state <= STATE_DISP;
	end
end

endmodule

// ---------------------------------------------------------------------------
// --------------------------- STE hard scroll shifter -----------------------
// ---------------------------------------------------------------------------

module ste_shifter (
	input  [3:0] skew,
   input  [31:0] in,
   output reg [15:0] out
);

always @(skew, in) begin
	out = 16'h0000;

   case(skew)
     15: out =  in[16:1];
     14: out =  in[17:2];
     13: out =  in[18:3];
     12: out =  in[19:4];
     11: out =  in[20:5];
     10: out =  in[21:6];
     9:  out =  in[22:7];
     8:  out =  in[23:8];
     7:  out =  in[24:9];
     6:  out =  in[25:10];
     5:  out =  in[26:11];
     4:  out =  in[27:12];
     3:  out =  in[28:13];
     2:  out =  in[29:14];
     1:  out =  in[30:15];
     0:  out =  in[31:16];
   endcase; // case (skew)
end

endmodule
