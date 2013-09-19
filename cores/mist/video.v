//
// video.v - new version
// 
// Atari ST shifter implementation for the MiST board
// http://code.google.com/p/mist-board/
// 
// Copyright (c) 2013 Till Harbaum <till@harbaum.org> 
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

// original atari video timing 
//         mono     color
// pclk    32MHz    16/8MHz
// hfreq   35.7kHz  15.75kHz
// vfreq   71.2Hz   50/60Hz
//
// avg. values derived from frequencies:
// hdisp   640      640/320
// htot    896      1015/507
// vdisp   400      200
// vtot    501      315/262

// TODO:
// - async timing


// Overscan:
// http://codercorner.com/fullscrn.txt

// Examples: automation 000 + 001: bottom border
//           automation 097: top+ bottom border

module video (
  // system interface
  input clk,                      // 31.875 MHz
  input clk27,                    // 27.000 Mhz
  input reset,                    // reset
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
  input       pal56,           // use VGA compatible 56hz for PAL
  input [1:0] scanlines,       // scanlines (00-none 01-25% 10-50% 11-100%)
  
  // for internal use
  output          deO,
  output          hsO
);

// ---------------------------------------------------------------------------
// ------------------------------ internal signals ---------------------------
// ---------------------------------------------------------------------------

// deO is the internal display enable signal as used by the mfp. This is used
// by software to generate a line interrupt and to e.g. do 512 color effects.
// deO is active low
assign deO = ~(scan_doubler_enable?sd_de:de);

// similar for hsync
assign hsO = scan_doubler_enable?sd_hs:(h_state == 2'd0);

// special de and hs signals while scan doubler is being used
wire sd_hs = vcnt[0] && (h_state == 2'd0);

reg sd_de;
always @(posedge clk) begin

	// begin of de: even line when memory is being read, begin of display phase
	if(!vcnt[0] && (v_state == 2'd3) && (hcnt == t5_h_end)) 
		sd_de <= 1'b1;

	// end of de: odd line, when memory is being read, end of display phase
	// There's a problem with this shifter: Color table changes affect the
	// VGA image after the scan doubler. Thus the display timing is much faster
	// than in a real ST. We artificially move the irq a little bit (160 clocks)
	// back so the irq latency results in color table changes in the blank/sync phase	
	if(vcnt[0] && (v_state == 2'd3) && (hcnt == (t0_h_border_right - 10'd160))) 
		sd_de <= 1'b0;
end

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

// scandoubler is used for the mid and low rez mode
wire scan_doubler_enable = mid || low;

// line buffer for scan doubler for color video modes
// the color modes have 80 words per line (320*4/16 or 640*2/16) and
// we need space for two lines -> 160 words
reg [15:0] sd_buffer0 [63:0];
reg [15:0] sd_buffer1 [63:0];
reg [15:0] sd_buffer2 [63:0];
reg [15:0] sd_buffer3 [63:0];
reg [6:0]  sd_wptr;
reg [5:0]  sd_rptr;

reg [1:0] syncmode;
reg [1:0] syncmode_latch;
wire pal = (syncmode_latch[1] == 1'b1);

 // data input buffers for up to 4 planes
reg [15:0] data_latch[4];

localparam BASE_ADDR = 23'h8000;   // default video base address 0x010000
reg [22:0] _v_bas_ad;              // video base address register

// 16 colors with 3*3 bits each
reg [2:0] palette_r[15:0];
reg [2:0] palette_g[15:0];
reg [2:0] palette_b[15:0];

// ---------------------------------------------------------------------------
// ----------------------------- CPU register read ---------------------------
// ---------------------------------------------------------------------------
   
always @(reg_sel, reg_rw, reg_uds, reg_lds, reg_addr, _v_bas_ad, shmode, vaddr, syncmode) begin
  reg_dout = 16'h0000;

  // read registers
  if(reg_sel && reg_rw) begin

     // video base register (r/w)
    if(reg_addr == 6'h00)      reg_dout <= { 8'h00, _v_bas_ad[22:15] };
    if(reg_addr == 6'h01)      reg_dout <= { 8'h00, _v_bas_ad[14: 7] };

     // video address counter (ro on ST)
    if(reg_addr == 6'h02)      reg_dout <= { 8'h00, vaddr[22:15]     };
    if(reg_addr == 6'h03)      reg_dout <= { 8'h00, vaddr[14:7 ]     };
    if(reg_addr == 6'h04)      reg_dout <= { 8'h00, vaddr[6:0], 1'b0 };

     // syncmode register
    if(reg_addr == 6'h05)      reg_dout <= { 6'h00, syncmode, 8'h00  };

    // the color palette registers
    if(reg_addr >= 6'h20 && reg_addr < 6'h30 ) begin
      reg_dout[2:0]  <= palette_b[reg_addr[3:0]];
      reg_dout[6:4]  <= palette_g[reg_addr[3:0]];
      reg_dout[10:8] <= palette_r[reg_addr[3:0]];
    end

     // shift mode register
    if(reg_addr == 6'h30)      reg_dout <= { 6'h00, shmode, 8'h00    };
  end
end

// ---------------------------------------------------------------------------
// ----------------------------- CPU register write --------------------------
// ---------------------------------------------------------------------------
always @(negedge reg_clk) begin
  if(reg_reset) begin
    _v_bas_ad <= BASE_ADDR;
    shmode <= DEFAULT_MODE;   // default video mode 2 => mono
    syncmode <= 2'b00;        // 60hz
    
    if(DEFAULT_MODE == 0) begin
      // TOS default palette, can be disabled after tests
      palette_r[ 0] <= 3'b111; palette_g[ 0] <= 3'b111; palette_b[ 0] <= 3'b111;
      palette_r[ 1] <= 3'b111; palette_g[ 1] <= 3'b000; palette_b[ 1] <= 3'b000;
      palette_r[ 2] <= 3'b000; palette_g[ 2] <= 3'b111; palette_b[ 2] <= 3'b000;
      palette_r[ 3] <= 3'b111; palette_g[ 3] <= 3'b111; palette_b[ 3] <= 3'b000;
      palette_r[ 4] <= 3'b000; palette_g[ 4] <= 3'b000; palette_b[ 4] <= 3'b111;
      palette_r[ 5] <= 3'b111; palette_g[ 5] <= 3'b000; palette_b[ 5] <= 3'b111;
      palette_r[ 6] <= 3'b000; palette_g[ 6] <= 3'b111; palette_b[ 6] <= 3'b111;
      palette_r[ 7] <= 3'b101; palette_g[ 7] <= 3'b101; palette_b[ 7] <= 3'b101;
      palette_r[ 8] <= 3'b011; palette_g[ 8] <= 3'b011; palette_b[ 8] <= 3'b011;
      palette_r[ 9] <= 3'b111; palette_g[ 9] <= 3'b011; palette_b[ 9] <= 3'b011;
      palette_r[10] <= 3'b011; palette_g[10] <= 3'b111; palette_b[10] <= 3'b011;
      palette_r[11] <= 3'b111; palette_g[11] <= 3'b111; palette_b[11] <= 3'b011;
      palette_r[12] <= 3'b011; palette_g[12] <= 3'b011; palette_b[12] <= 3'b111;
      palette_r[13] <= 3'b111; palette_g[13] <= 3'b011; palette_b[13] <= 3'b111;
      palette_r[14] <= 3'b011; palette_g[14] <= 3'b111; palette_b[14] <= 3'b111;
      palette_r[15] <= 3'b000; palette_g[15] <= 3'b000; palette_b[15] <= 3'b000;
    end else  
      palette_b[ 0] <= 3'b111;
        
  end else begin
    // write registers
    if(reg_sel && ~reg_rw) begin
      if(reg_addr == 6'h00 && ~reg_lds) _v_bas_ad[22:15] <= reg_din[7:0];
      if(reg_addr == 6'h01 && ~reg_lds) _v_bas_ad[14:7] <= reg_din[7:0];

      if(reg_addr == 6'h05 && ~reg_uds) begin
        // writing to sync mode toggles between 50 and 60 hz modes
        syncmode <= reg_din[9:8];
      end

      // the color palette registers
      if(reg_addr >= 6'h20 && reg_addr < 6'h30 ) begin
        if(~reg_uds) begin 
          palette_r[reg_addr[3:0]] <= reg_din[10:8];
        end
          
        if(~reg_lds) begin
          palette_g[reg_addr[3:0]] <= reg_din[6:4];
          palette_b[reg_addr[3:0]] <= reg_din[2:0];
        end
      end
        
      if(reg_addr == 6'h30 && ~reg_uds) shmode <= reg_din[9:8];
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
	.hcnt       (hcnt       ),
	.vcnt       (vcnt       ),
	.in_r       ({stvid_r, stvid_r}),
	.in_g       ({stvid_g, stvid_g}),
	.in_b       ({stvid_b, stvid_b}),

	// receive signal with OSD overlayed
	.out_r      (st_and_osd_r),
	.out_g      (st_and_osd_g),
	.out_b      (st_and_osd_b)
);
	
// ----------------------- monochrome video signal ---------------------------
// mono uses the lsb of blue palette entry 0 to invert video
wire [2:0] blue0 = palette_b[0];
wire mono_bit = blue0[0]^shift0[15];
wire [2:0] mono_rgb = de?{mono_bit, mono_bit, mono_bit}:3'b100;

// ------------------------- colour video signal -----------------------------
// border color is taken from palette[0]
wire [3:0] index16 = { shift3[15], shift2[15], shift1[15], shift0[15] };
wire [2:0] color_r = de?palette_r[index16]:palette_r[0];
wire [2:0] color_g = de?palette_g[index16]:palette_g[0];
wire [2:0] color_b = de?palette_b[index16]:palette_b[0];

// --------------- de-multiplex color and mono into one vga signal -----------
wire [2:0] stvid_r = mono?mono_rgb:color_r;
wire [2:0] stvid_g = mono?mono_rgb:color_g;
wire [2:0] stvid_b = mono?mono_rgb:color_b;

// shift registers for up to 4 planes
reg [15:0] shift0, shift1, shift2, shift3;

// this line is to be displayed darker in scanline mode
wire scanline = scan_doubler_enable && vcnt[0];

always @(posedge clk) begin
   hs <= h_sync_pol ^ ((h_state == 2'd0)?1'b0:1'b1);
   vs <= v_sync_pol ^ ((v_state == 2'd0)?1'b0:1'b1);

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
		// shift0 register every 16 clocks
		if(hcnt[3:0] == 4'hf) shift0       <= data_latch[0];
		else      				 shift0[15:1] <= shift0[14:0];
		
		// TODO: Color modes not using scan doubler
		
	end else begin		
		// double buffered color mode: reload every 32 clocks

		// reset read counter right before data is being read
		if(hcnt == t5_h_end - 10'h1) sd_rptr <= 6'd0;
		
		// low rez 320x200		
		if(low) begin
			// h_state == 2'd3 -> display enable

			// half pixel clock
			if(hcnt[0] == 1'b1) begin
				if(hcnt[4:1] == 4'hf) begin
					// read words for all four planes
					shift0 <= sd_buffer0[{!sd_toggle, sd_rptr[5:1]}];
					shift1 <= sd_buffer1[{!sd_toggle, sd_rptr[5:1]}];
					shift2 <= sd_buffer2[{!sd_toggle, sd_rptr[5:1]}];
					shift3 <= sd_buffer3[{!sd_toggle, sd_rptr[5:1]}];
					sd_rptr <= sd_rptr + 6'd2;
				end else begin
					// shift every second pixel     
					shift0[15:1] <= shift0[14:0];
					shift1[15:1] <= shift1[14:0];
					shift2[15:1] <= shift2[14:0];
					shift3[15:1] <= shift3[14:0];
				end
			end
		end
		
		// med rez 640x200
		else if(mid) begin
			if(hcnt[3:0] == 4'hf) begin
				// read words for all two planes
				if(sd_rptr[0] == 1'b0) begin
					shift0 <= sd_buffer0[{!sd_toggle, sd_rptr[5:1]}];
					shift1 <= sd_buffer1[{!sd_toggle, sd_rptr[5:1]}];
				end else begin
					shift0 <= sd_buffer2[{!sd_toggle, sd_rptr[5:1]}];
					shift1 <= sd_buffer3[{!sd_toggle, sd_rptr[5:1]}];
				end
				sd_rptr <= sd_rptr + 6'd1;
			end else begin
				// shift every pixel      
				shift0[15:1] <= shift0[14:0];
				shift1[15:1] <= shift1[14:0];
				shift2[15:1] <= 15'h0000;
				shift3[15:1] <= 15'h0000;
			end
		end
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
   if((vcnt == 10'd399)||(vcnt == 10'd400)) begin
		// syncmode has changed from 1 to 0 (50 to 60 hz)
      if((syncmode[1] == 1'b0) && (last_syncmode == 1'b1))
			overscan_detect <= 1'b1;
   end
	
	// latch overscan state at topleft screen edge
	if((hcnt == t4_h_border_left) && (vcnt == t10_v_border_top)) begin
		// save and reset overscan
      overscan <= overscan_detect;
      overscan_detect <= 1'b0;		
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

// required pixel offset allowing for prefetch of 1, 2 or 4 planes (16, 32 or 64 pixels)
wire [9:0] memory_prefetch = { 3'b000, planes, 4'b0000 };
wire [9:0] me_h_start      = t5_h_end - memory_prefetch;
wire [9:0] me_h_end        = t0_h_border_right - memory_prefetch;
// line offset required for scan doubler
wire [9:0] me_v_offset     = scan_doubler_enable?10'd2:10'd0;
wire [9:0] me_v_start      = t11_v_end - me_v_offset;
wire [9:0] me_v_end        = t6_v_border_bot - me_v_offset;

// scan doubler signale indicating first or second buffer used
wire sd_toggle = vcnt[1];

always @(posedge clk) begin

	// line in which memory access is enabled
	// in scan doubler mode two lines ahead of vertical display enable
	if(hcnt == v_event) begin
		if(vcnt == me_v_start)  me_v <= 1'b1;
		if(vcnt == me_v_end)    me_v <= 1'b0;
	end
		
	// memory enable signal 16/32/64 bits (16*planes) ahead of display enable (de)
	if(me_v) begin
		if(hcnt == me_h_start)  me <= 1'b1;
		if(hcnt == me_h_end)    me <= 1'b0;
	end
		
	// starting new image at left/top start of border
	if((hcnt == t4_h_border_left) && (vcnt == t10_v_border_top)) begin
		vaddr <= _v_bas_ad;
		plane <= 2'd0;

		// copy syncmode
		syncmode_latch <= syncmode;
	end else begin
	
		// ---- scan doubler pointer handling -----
		// reset write pointer only every second line since in color mode a line has
		// twice the bytes per line
		if((hcnt == v_event) && vcnt[0]) 
			sd_wptr <= 7'd0;
	
		// read if memory enable is active and only within the video bus cycle
		if(me && (bus_cycle == 3)) begin

			// move data directly into data latch if not using scan doubler ...
			data_latch[plane] <= data;

			// ... and store it in buffer for later scan doubler use
			case(sd_wptr[1:0])
				2'b00:  sd_buffer0[{sd_toggle, sd_wptr[6:2]}] <= data;
				2'b01:  sd_buffer1[{sd_toggle, sd_wptr[6:2]}] <= data;
				2'b10:  sd_buffer2[{sd_toggle, sd_wptr[6:2]}] <= data;
				2'b11:  sd_buffer3[{sd_toggle, sd_wptr[6:2]}] <= data;
			endcase
          
			// increase scan doubler address
			sd_wptr <= sd_wptr + 7'd1;
			
			// advance plane counter
			if(planes != 1) begin
				plane <= plane + 2'd1;
				if(plane == planes - 2'd1)
					plane <= 2'd0;
			end
			
			vaddr <= vaddr + 23'd1;
		end
	end
end

// ---------------------------------------------------------------------------
// ------------------------- video timing generator --------------------------
// ---------------------------------------------------------------------------

reg [9:0] hcnt;     // horizontal pixel counter
reg [9:0] vcnt;     // vertical line counter

reg [1:0] h_state;  // 0=sync, 1=blank, 2=border, 3=display
reg [1:0] v_state;  // 0=sync, 1=blank, 2=border, 3=display

// blank level is also used during sync
wire blank  = (v_state == 2'd1) || (h_state == 2'd1) || (v_state == 2'd0) || (h_state == 2'd0);
wire de     = (v_state == 2'd3) && (h_state == 2'd3);

wire border = 
     ((v_state == 2'd2) && ((h_state == 2'd3) || (h_state == 2'd2)) ||  // top/bottom border
      (h_state == 2'd2) && ((v_state == 2'd3) || (v_state == 2'd2)));   // left/right border

// time in horizontal timing where vertical states change (at the begin of the left blank phase)
wire [9:0] v_event = t3_h_blank_left;

always @(posedge clk) begin
	if(reset) begin
		hcnt <= 10'd0;
		vcnt <= 10'd0;
	end else begin
		// ------------- horizontal signal generation -------------
		if(hcnt == t5_h_end)  hcnt <= 10'd0;
		else                  hcnt <= hcnt + 10'd1;

		// generate horizontal video signal states
		if( hcnt == t2_h_sync )                                        h_state <= 2'd0;
		if((hcnt == t0_h_border_right) || (hcnt == t4_h_border_left))  h_state <= 2'd2;
		if((hcnt == t1_h_blank_right) || (hcnt == t3_h_blank_left))    h_state <= 2'd1;
		if( hcnt == t5_h_end)                                          h_state <= 2'd3;
	  
		// vertical state changes at end of hsync (begin of left blank)
		if(hcnt == v_event) begin

			// ------------- vertical signal generation -------------
			// increase vcnt
			if(vcnt == t11_v_end)  vcnt <= 10'd0;
			else                   vcnt <= vcnt + 10'd1;

			// generate vertical video signal states
			if( vcnt == t8_v_sync )                                        v_state <= 2'd0;
			if((vcnt == t6_v_border_bot) || (vcnt == t10_v_border_top))    v_state <= 2'd2;
			if((vcnt == t7_v_blank_bot) || (vcnt == t9_v_blank_top))       v_state <= 2'd1;
			if( vcnt == t11_v_end)                                         v_state <= 2'd3;
		end
	end
end

endmodule
