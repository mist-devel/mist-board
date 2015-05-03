//
// shifter.v
// 
// Atari ST(E) shifter implementation for the MiST board
// http://code.google.com/p/mist-board/
// 
// Copyright (c) 2013-2015 Till Harbaum <till@harbaum.org> 
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

module shifter (
  // system interface
  input 	    			clk, // 32.000 MHz
  input [1:0] 	    	bus_cycle, // bus-cycle for sync

  // memory interface
  output reg [22:0] 	vaddr, // video word address counter
  output 	    		read, // video read cycle
  input [63:0] 	   data, // video data read
  
  // cpu register interface
  input 	    			cpu_clk,
  input 	    			cpu_reset,
  input [15:0] 	   cpu_din,
  input 	    			cpu_sel,
  input [5:0] 	    	cpu_addr,
  input 	    			cpu_uds,
  input 	    			cpu_lds,
  input 	    			cpu_rw,
  output reg [15:0] 	cpu_dout,
  
  // screen interface
  output reg 	    	hs, // H_SYNC
  output reg 	    	vs, // V_SYNC
  output reg [3:0] 	video_r, // Red
  output reg [3:0] 	video_g, // Green
  output reg [3:0] 	video_b, // Blue

  // system config
  input 	    			pal56, // use VGA compatible 56hz for PAL
  input 	    			ste, // enable STE featurss

  output 	    		vga_hs_pol, // sync polarity to be used on vga
  output 	    		vga_vs_pol,
  output          	clk_16,     // 16Mhz clock for scan doubler
 
  // signals not affected by scan doubler for internal use like irqs
  output 	    		st_de,
  output reg 	   	st_vs,
  output reg 	   	st_hs
);

localparam STATE_SYNC   = 2'd0;
localparam STATE_BLANK  = 2'd1;
localparam STATE_BORDER = 2'd2;
localparam STATE_DISP   = 2'd3;

// ---------------------------------------------------------------------------
// --------------------------- internal state counter ------------------------
// ---------------------------------------------------------------------------

reg [1:0] 	    t;
always @(posedge clk) begin
   // 32Mhz counter synchronous to 8 Mhz clock
   // force counter to pass state 0 exactly after the rising edge of clk_reg (8Mhz)
   if(((t == 2'd3)  && ( cpu_clk == 0)) ||
      ((t == 2'd0) && ( cpu_clk == 1)) ||
      ((t != 2'd3) && (t != 2'd0)))
     t <= t + 2'd1;
end

// give 16Mhz clock to scan doubler
assign clk_16 = t[0];
     
// create internal bus_cycle signal which is stable on the positive clock
// edge and extends the previous state by half a 32 Mhz clock cycle
reg [3:0] bus_cycle_L;
always @(negedge clk)
	bus_cycle_L <= { bus_cycle, t };

// ---------------------------------------------------------------------------
// ------------------------------ internal signals ---------------------------
// ---------------------------------------------------------------------------

// st_de is the internal display enable signal as used by the mfp. This is used
// by software to generate a line interrupt and to e.g. do 512 color effects.
// st_de is active low. Using display enable (de) for this makes sure the cpu has
// plenty of time before data for the next line is starting to be fetched
// assign st_de = ~de;

// according to hatari video.h/video.c the timer_b irq comes 28 8MHz cycles after
// the last pixel has been displayed. Our de is 4 cycles earlier then the end
// of the line, so we delay by 28+4=32
reg [31:0] st_de_delay;
assign st_de = st_de_delay[31];
always @(posedge t[1])
   st_de_delay <= { st_de_delay[30:0], ~de };
 
always @(posedge clk) begin
   st_hs <= h_sync;
   
	// vsync irq is generated right after the last border line has been displayed

	// According to hatari vbl happens in cycle 64. Display starts at cycle 56,
	// so vbl happens at cycle 8 of the display phase
	if(hcnt == 8) begin		
		// vsync starts at begin of blanking phase
		if(vcnt == t7_v_blank_bot)   st_vs <= 1'b1;
		
		// vsync ends at begin of top border
		if(vcnt == t10_v_border_top) st_vs <= 1'b0;
	end
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

// horizontal timing values are for 640 pixel and are divided by 2 for 320 pixel low rez
assign vga_hs_pol = config_string[121];
wire [9:0] t0_h_border_right = low?{1'b0,config_string[120:112]}:config_string[120:111];
wire [9:0] t1_h_blank_right  = low?{1'b0,config_string[110:102]}:config_string[110:101];
wire [9:0] t2_h_sync         = low?{1'b0,config_string[100:92]}:config_string[100:91];
wire [9:0] t3_h_blank_left   = low?{1'b0,config_string[90:82]}:config_string[90:81];
wire [9:0] t4_h_border_left  = low?{1'b0,config_string[80:72]}:config_string[80:71];
wire [9:0] t5_h_end          = low?{1'b0,config_string[70:62]}:config_string[70:61];

assign vga_vs_pol = config_string[60];
wire [9:0] t6_v_border_bot   = config_string[59:50];
wire [9:0] t7_v_blank_bot    = config_string[49:40];
wire [9:0] t8_v_sync         = config_string[39:30];
wire [9:0] t9_v_blank_top    = config_string[29:20];
wire [9:0] t10_v_border_top  = config_string[19:10];
wire [9:0] t11_v_end         = config_string[9:0];

// default video mode is monochrome
parameter DEFAULT_MODE = 3'd2;

// shiftmode register
reg [1:0] shmode;
wire mono  = (shmode == 2'd2);
wire mid   = (shmode == 2'd1);
wire low   = (shmode == 2'd0);

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
reg [7:0] line_offset;              // number of words to skip at the end of each line
reg [3:0] pixel_offset;             // number of pixels to skip at begin of line
reg ste_overscan_enable;            // STE has a special 16 bit overscan

// ---------------------------------------------------------------------------
// ----------------------------- CPU register read ---------------------------
// ---------------------------------------------------------------------------

always @(cpu_sel, cpu_rw, cpu_uds, cpu_lds, cpu_addr, _v_bas_ad, shmode, vaddr, 
			syncmode, line_offset, pixel_offset, ste) begin
	cpu_dout = 16'h0000;

	// read registers
	if(cpu_sel && cpu_rw) begin

		// video base register (r/w)
		if(cpu_addr == 6'h00)      	cpu_dout <= {   8'h00, _v_bas_ad[22:15] };
		if(cpu_addr == 6'h01)      	cpu_dout <= {   8'h00, _v_bas_ad[14: 7] };
		if(ste && cpu_addr == 6'h06)  cpu_dout <= {   8'h00, _v_bas_ad[ 6: 0], 1'b0 };

		// video address counter (ro on ST)
		if(cpu_addr == 6'h02)      	cpu_dout <= {   8'h00, vaddr[22:15]     };
		if(cpu_addr == 6'h03)      	cpu_dout <= {   8'h00, vaddr[14:7 ]     };
		if(cpu_addr == 6'h04)      	cpu_dout <= {   8'h00, vaddr[6:0], 1'b0 };

		// syncmode register
		if(cpu_addr == 6'h05)      	cpu_dout <= {   6'h00, syncmode, 8'h00  };

		if(ste) begin
			if(cpu_addr == 6'h07)    	cpu_dout <= {   8'h00, line_offset      };
			if(cpu_addr == 6'h32)    	cpu_dout <= { 12'h000, pixel_offset     };
		end

		// the color palette registers
		if(cpu_addr >= 6'h20 && cpu_addr < 6'h30 ) begin
			cpu_dout[3:0]  <= palette_b[cpu_addr[3:0]];
			cpu_dout[7:4]  <= palette_g[cpu_addr[3:0]];
			cpu_dout[11:8] <= palette_r[cpu_addr[3:0]];

			// return only the 3 msb in non-ste mode
			if(!ste) begin
				cpu_dout[3] <= 1'b0;
				cpu_dout[7] <= 1'b0;
				cpu_dout[11] <= 1'b0;
			end
		end

		// shift mode register
		if(cpu_addr == 6'h30)      cpu_dout <= { 6'h00, shmode, 8'h00    };
	end
end

// ---------------------------------------------------------------------------
// ----------------------------- CPU register write --------------------------
// ---------------------------------------------------------------------------

// STE video address write signal is evaluated inside memory engine
wire ste_vaddr_write = ste && cpu_sel && !cpu_rw && !cpu_lds;
 
always @(negedge cpu_clk) begin
	if(cpu_reset) begin
		_v_bas_ad <= BASE_ADDR;
		shmode <= DEFAULT_MODE;   // default video mode 2 => mono
		syncmode <= 2'b00;        // 60hz
   
		// disable STE hard scroll features
		line_offset <= 8'h00;
		pixel_offset <= 4'h0;
		ste_overscan_enable <= 1'b0;

	        palette_b[ 0] <= 4'b111;
        
	end else begin
		// write registers
		if(cpu_sel && !cpu_rw) begin
			if(!cpu_lds) begin
			
				// video base address hi/mid (ST and STE)
				if(cpu_addr == 6'h00) _v_bas_ad[22:15] <= cpu_din[7:0];
				if(cpu_addr == 6'h01) _v_bas_ad[14:7] <= cpu_din[7:0];

				// In the STE setting hi or mid clears the low byte for ST compatibility
				// in ST mode this doesn't harm
				if(cpu_addr[5:1] == 5'h00) _v_bas_ad[6:0] <= 7'h00;

				// the low byte can only be written in STE mode
				if(ste && cpu_addr == 6'h06)  _v_bas_ad[6:0] <= cpu_din[7:1];
			end
				
			// writing to sync mode toggles between 50 and 60 hz modes
			if(cpu_addr == 6'h05 && !cpu_uds) syncmode <= cpu_din[9:8];

			// writing special STE registers
			if(ste && !cpu_lds) begin
				if(cpu_addr == 6'h07) line_offset <= cpu_din[7:0];
				if(cpu_addr == 6'h32) begin
					pixel_offset <= cpu_din[3:0];
					ste_overscan_enable <= 1'b0;
				end
				
				// Writing the video address counter happens directly inside the 
				// memory engine further below!!!
			end

			// byte write of 0 to ff8264 while ff8365 (pixel_offset) != 0 results in extra
			// ste overscan
			if(ste && !cpu_uds && cpu_lds) begin
				if((cpu_addr == 6'h32) && (pixel_offset != 0))
					ste_overscan_enable <= 1'b1;
			end
			
			// the color palette registers, always write bit 3 with zero if not in 
			// ste mode as this is the lsb of ste
			if(cpu_addr >= 6'h20 && cpu_addr < 6'h30 ) begin
				if(!cpu_uds) begin 
					if(!ste)	palette_r[cpu_addr[3:0]] <= { 1'b0 , cpu_din[10:8] };
					else		palette_r[cpu_addr[3:0]] <= cpu_din[11:8];
				end
          
				if(!cpu_lds) begin
					if(!ste) begin
						palette_g[cpu_addr[3:0]] <= { 1'b0, cpu_din[6:4] };
						palette_b[cpu_addr[3:0]] <= { 1'b0, cpu_din[2:0] };
					end else begin
						palette_g[cpu_addr[3:0]] <= cpu_din[7:4];
						palette_b[cpu_addr[3:0]] <= cpu_din[3:0];
					end
				end
			end

		        // make msb writeable if MiST video modes are enabled
			if(cpu_addr == 6'h30 && !cpu_uds) shmode <= cpu_din[9:8];
		end
	end
end

// ---------------------------------------------------------------------------
// -------------------------- video signal generator -------------------------
// ---------------------------------------------------------------------------

// ----------------------- monochrome video signal ---------------------------
// mono uses the lsb of blue palette entry 0 to invert video
wire [3:0] blue0 = palette_b[0];
wire mono_bit = blue0[0]^shift_0[15];
wire [3:0] mono_rgb = { mono_bit, mono_bit, mono_bit, mono_bit };

// ------------------------- colour video signal -----------------------------

// For ST compatibility reasons the STE has the color bit order 0321. This is 
// handled here
wire [3:0] color_index = border?4'd0:{ shift_3[15], shift_2[15], shift_1[15], shift_0[15] };
wire [3:0] color_r_pal = palette_r[color_index];
wire [3:0] color_r = { color_r_pal[2:0], color_r_pal[3] };
wire [3:0] color_g_pal = palette_g[color_index];
wire [3:0] color_g = { color_g_pal[2:0], color_g_pal[3] };
wire [3:0] color_b_pal = palette_b[color_index];
wire [3:0] color_b = { color_b_pal[2:0], color_b_pal[3] };

// --------------- de-multiplex color and mono into one vga signal -----------
wire [3:0] stvid_r = mono?mono_rgb:color_r;
wire [3:0] stvid_g = mono?mono_rgb:color_g;
wire [3:0] stvid_b = mono?mono_rgb:color_b;
 
// shift registers for up to 4 planes
reg [15:0] shift_0, shift_1, shift_2, shift_3;

// clock divider to generate the mid and low rez pixel clocks
wire   pclk = low?t[1]:mid?t[0]:clk;

// use variable dot clock
always @(posedge pclk) begin
   hs <= ~h_sync;
   vs <= ~v_sync;

   // drive video output
   video_r <= blank?4'b0000:stvid_r;
   video_g <= blank?4'b0000:stvid_g;
   video_b <= blank?4'b0000:stvid_b;

   // shift all planes and reload 
   // shift registers every 16 pixels
   if((hcnt[3:0] == 4'hf)||(hcnt == t5_h_end)) begin	
      if(!ste || (pixel_offset == 0) || ste_overscan_enable) begin
	 shift_0 <= data_latch[0];
	 shift_1 <= data_latch[1];
	 shift_2 <= data_latch[2];
	 shift_3 <= data_latch[3];
      end else begin
	 shift_0 <= ste_shifted_0;
	 shift_1 <= ste_shifted_1;
	 shift_2 <= ste_shifted_2;
	 shift_3 <= ste_shifted_3;
      end
   end else begin
	shift_0 <= { shift_0[14:0], 1'b0 };
	shift_1 <= { shift_1[14:0], 1'b0 };
	shift_2 <= { shift_2[14:0], 1'b0 };
	shift_3 <= { shift_3[14:0], 1'b0 };
   end
end

// ---------------------------------------------------------------------------
// ----------------------------- overscan detection --------------------------
// ---------------------------------------------------------------------------

// Currently only opening the bottom border for overscan is supported. Opening
// the top border should also be easy. Opening the side borders is basically 
// impossible as this requires a 100% perfect CPU and shifter timing.

reg last_syncmode;
reg [3:0] bottom_overscan_cnt;
reg [3:0] top_overscan_cnt;

wire bottom_overscan = (bottom_overscan_cnt != 0);
wire top_overscan = (top_overscan_cnt != 0);

reg syncmode_at_line_start;

always @(posedge clk) begin
	if(cpu_reset) begin
		top_overscan_cnt <= 4'd0;
		bottom_overscan_cnt <= 4'd0;
	end else begin
		last_syncmode <= syncmode[1];  // delay syncmode to detect changes

      // reset counters
		if((vcnt == 0) && (hcnt == 10'd0)) begin
		   if(bottom_overscan_cnt != 0)
		     bottom_overscan_cnt  <= bottom_overscan_cnt - 4'd1;

		   if(top_overscan_cnt != 0)
		     top_overscan_cnt  <= top_overscan_cnt - 4'd1;
		end
	   
		// this is the magic used to do "overscan".
		// the magic actually involves more than toggling syncmode (50/60hz)
		// within line 200. But this is sufficient for our detection

		// trigger in line 199
		if( (vcnt >= 9'd194) && (vcnt <= 9'd202) ) begin
			// syncmode has changed between 1 and 0 (50/60 hz)
			if(syncmode[1] != last_syncmode)
				bottom_overscan_cnt <= 4'd15;
		end 
	  
		// trigger in line 284/285 and 1/2
		if( ( (vcnt >= 9'd280) && (vcnt <= 9'd290) ) ||
			 ( (vcnt >=   9'd0) && (vcnt <=   9'd3) ) ) begin
			// syncmode has changed between 1 and 0 (50/60 hz)
			if(syncmode[1] != last_syncmode)
				top_overscan_cnt <= 4'd15;
		end
		
		// latch syncmode at begin of line and check if it changed at the end
		// this special case causes 2 less (50->60) or more (60->50) bytes to be read
		// during a line
		if(hcnt == de_h_start)
			syncmode_at_line_start <= syncmode[1];
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
	if((bus_cycle_L == 4'd08) && (plane == 2'd0)) begin
		// shift up 16 pixels and load new data into lower bits of shift registers
		ste_shift_0 <= { ste_shift_0[15:0], data_latch[0] };
		ste_shift_1 <= { ste_shift_1[15:0], (planes > 3'd1)?data_latch[1]:16'h0000 };
		ste_shift_2 <= { ste_shift_2[15:0], (planes > 3'd2)?data_latch[2]:16'h0000 };
		ste_shift_3 <= { ste_shift_3[15:0], (planes > 3'd2)?data_latch[3]:16'h0000 };
	end
end

// ---------------------------------------------------------------------------
// ------------------------------- memory engine -----------------------------
// ---------------------------------------------------------------------------

assign read = (bus_cycle == 0) && de;  // display enable can directly be used as a ram read signal

// current plane to be read from memory
reg [1:0] plane;  

// To be able to output the first pixel we need to have one word for every plane already
// present in memory. We thus need a display enable signal which is (depending on color depth)
// 16, 32 or 64 pixel ahead of display enable
reg de, de_v;

// required pixel offset allowing for prefetch of 16 pixels
wire [9:0] ste_overscan = ste_overscan_enable?10'd16:10'd0;
// ste is starting another 16 pixels earlier if horizontal hard scroll is being used
wire [9:0] ste_prefetch    = (ste && ((pixel_offset != 0) && !ste_overscan_enable))?10'd16:10'd0;
wire [9:0] de_h_start      = t5_h_end - 10'd16 - ste_prefetch;
wire [9:0] de_h_end        = t0_h_border_right - 10'd16 + ste_overscan;

// extra lines required by vertical overscan
wire [9:0] de_v_top_extra  = top_overscan?10'd29:10'd0 /* synthesis keep */;  // 29 extra ST lines at top
wire [9:0] de_v_bot_extra  = bottom_overscan?10'd38:10'd0 /* synthesis keep */;    // 38 extra ST lines at bottom

// calculate lines in which active display starts end ends
wire [9:0] de_v_start      = t11_v_end - de_v_top_extra;
wire [9:0] de_v_end        = t6_v_border_bot + de_v_bot_extra;

always @(posedge clk) begin

	// line in which memory access is enabled
	if(hcnt == v_event) begin
		if(vcnt == de_v_start)  de_v <= 1'b1;
		if(vcnt == de_v_end)    de_v <= 1'b0;
	end
		
	// display enable signal 16/32/64 bits (16*planes) ahead of display enable (de)
	// include bus cycle to stay in sync in scna doubler mode
	if(de_v) begin
		if(hcnt == de_h_start)  de <= 1'b1;
		if(hcnt == de_h_end)    de <= 1'b0;
	end
 
	// according to hatari the video counter is reloaded 3 lines before 
	// the vbi occurs. This is right after the display has been painted.
	// The video address counter is reloaded right after display ends 
   // also according to hatari this happens 8 cycles before display starts
	// in mono mode it doesn't work that way as there's no border and 
	// three lines before blank is inside the display area
	if((hcnt == t5_h_end-8 ) && 
		(vcnt == (mono?(t7_v_blank_bot+10'd1):(t7_v_blank_bot-10'd3)))) begin
		vaddr <= _v_bas_ad;
		plane <= 2'd0;

		// copy syncmode
		syncmode_latch <= syncmode;
	end else begin

		// video transfer happens in cycle 3 (end of video cycle)
		if(bus_cycle_L == 3) begin
	
			// read if display enable is active
			if(de) begin
			
				// move incoming video data into data latch
			        // ST shifter only uses 16 out of possible 64 bits, so select the right word
				case(vaddr[1:0])
						2'd0: data_latch[plane] <= data[15: 0];
						2'd1: data_latch[plane] <= data[31:16];
						2'd2: data_latch[plane] <= data[47:32];
						2'd3: data_latch[plane] <= data[63:48];
				endcase
				
				// advance video address
				vaddr <= vaddr + 23'd1;

				// advance plane counter
				if(planes != 1) begin
					plane <= plane + 2'd1;
					if(plane == planes - 2'd1)
						plane <= 2'd0;
				end
			end
		end
	end

	// at the end of each line check whether someone messed with the 
	// syncmode register in a way that the line ends at  adifferent mode than
	// it started
	if(de_v && (hcnt == de_h_end + 1 ) && (t == 0)) begin
		if(syncmode_at_line_start && !syncmode[1])    // 50->60 Hz => two bytes less
			vaddr <= vaddr - 23'd1;                    // two bytes less

		if(!syncmode_at_line_start && syncmode[1])    // 60->50 Hz => two bytes less
			vaddr <= vaddr + 23'd1;                    // two bytes more
	end

	// STE has additional ways to influence video address
	if(ste) begin
		// add line offset at the end of each video line
		if(de_v && (hcnt == de_h_end) && (t == 0))
			vaddr <= vaddr + line_offset;

		// STE vaddr write handling
		// bus_cycle 6 is in the middle of a cpu cycle
		if((bus_cycle_L == 6) && ste_vaddr_write) begin
			if(cpu_addr == 6'h02) vaddr[22:15] <= cpu_din[7:0];
			if(cpu_addr == 6'h03) vaddr[14: 7] <= cpu_din[7:0];
			if(cpu_addr == 6'h04) vaddr[ 6: 0] <= cpu_din[7:1];
		end 
	end
end

// ---------------------------------------------------------------------------
// ------------------------- video timing generator --------------------------
// ---------------------------------------------------------------------------

reg [9:0] hcnt;      // horizontal pixel counter
reg [1:0] h_state;   // 0=sync, 1=blank, 2=border, 3=display

// A seperate vertical timing is not needed, vcnt[9:1] is the st line
reg [9:0] vcnt;      // vertical line counter
reg [1:0] v_state;   // 0=sync, 1=blank, 2=border, 3=display

// blank level is also used during sync
wire blank  = (v_state == STATE_BLANK) || (h_state == STATE_BLANK) || 
	      (v_state == STATE_SYNC)  || (h_state == STATE_SYNC);

// only the color modes use the border
wire border = (v_state == STATE_BORDER)||(h_state == STATE_BORDER);

// time in horizontal timing where vertical states change (at the begin of the sync phase)
wire [9:0] v_event = t2_h_sync;

reg v_sync, h_sync;

always @(posedge pclk) begin
	// ------------- horizontal ST timing generation -------------
	// Run st timing at full speed if no scan doubler is being used. Otherwise run
	// it at half speed
	if(hcnt == t5_h_end) begin
	   // sync hcnt to bus
	   if((low  && (bus_cycle_L[3:2] == 2'b11)) ||
		   (mid  && (bus_cycle_L[3:1] == 3'b111)) ||
		   (mono && (bus_cycle_L[3:0] == 4'b1111)))
	     hcnt <= 10'd0;
	end else 
	  hcnt <= hcnt + 10'd1;

   if( hcnt == t2_h_sync)       h_sync <= 1'b1;
   if( hcnt == t3_h_blank_left) h_sync <= 1'b0;
 
	// generate horizontal video signal states
	if( hcnt == t2_h_sync )                                     h_state <= STATE_SYNC;
	if((hcnt == t0_h_border_right + ste_overscan) || 
		(hcnt == t4_h_border_left))                              h_state <= STATE_BORDER;
	if((hcnt == t1_h_blank_right) || (hcnt == t3_h_blank_left)) h_state <= STATE_BLANK;
	if( hcnt == t5_h_end)                                       h_state <= STATE_DISP;

	// vertical state changes at begin of hsync
	if(hcnt == v_event) begin

		// ------------- vertical timing generation -------------
		// increase vcnt
		if(vcnt == t11_v_end)  vcnt <= 10'd0;
		else                   vcnt <= vcnt + 10'd1;

		if( vcnt == t8_v_sync) 	    v_sync <= 1'b1;
		if( vcnt == t9_v_blank_top) v_sync <= 1'b0;

		// generate vertical video signal states
		if( vcnt == t8_v_sync )                                        v_state <= STATE_SYNC;
		if((vcnt == de_v_end) || (vcnt == t10_v_border_top))           v_state <= STATE_BORDER;
		if((vcnt == t7_v_blank_bot) || (vcnt == t9_v_blank_top))       v_state <= STATE_BLANK;
		if( vcnt == de_v_start)                                        v_state <= STATE_DISP;
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
