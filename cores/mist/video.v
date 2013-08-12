// http://martin.hinner.info/vga/timing.html
// http://www.epanorama.net/faq/vga2rgb/calc.html

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

// Overscan:
// http://codercorner.com/fullscrn.txt

// Examples: automation 000 + 001: bottom border
//           automation 097: top+ bottom border

module video (
	// system interface
	input         	clk,     // 31.875 MHz
	input         	reset,   // reset
	input [3:0]   	bus_cycle,

	// SPI interface for OSD
	input      		sck,
   input      		ss,
   input      		sdi,

	// memory interface
	output reg [22:0] vaddr,   // video word address counter
	output        	read,        // video read cycle
	input [15:0]  	data,
	
	// cpu register interface
	input         	reg_clk,
	input         	reg_reset,
	input [15:0]  	reg_din,
	input         	reg_sel,
	input [5:0]   	reg_addr,
	input         	reg_uds,
	input         	reg_lds,
	input         	reg_rw,
	output reg [15:0] reg_dout,
	
	// screen interface
	output reg	  	hs,      // H_SYNC
	output reg	  	vs,      // V_SYNC
	output reg [5:0]  	video_r, // Red[5:0]
	output reg [5:0]  	video_g, // Green[5:0]
	output reg [5:0]  	video_b, // Blue[5:0]

	// system config
	input 			pal56,   // use VGA compatible 56hz for PAL
	
	// for internal use
	output        	deO,
	output        	hsO
);

// basic video parameters
localparam H_PRE = 10'd16;   // 16 clocks read prefetch
localparam H_ACT = 10'd640;
localparam V_ACT = 10'd400;

// default video mode is 
parameter DEFAULT_MODE = 2'd2;

// output a de/hs signal with half the hsyncs in color mode 
assign deO = ~(mono?de:deC);
assign hsO =   mono?hs:hsC;

// line buffer for scan doubler for color video modes
// the color modes have 80 words per line (320*4/16 or 640*2/16) and
// we need space for two lines -> 160 words
reg [15:0] sd_buffer0 [63:0];
reg [15:0] sd_buffer1 [63:0];
reg [15:0] sd_buffer2 [63:0];
reg [15:0] sd_buffer3 [63:0];
reg [6:0]  sd_wptr, sd_rptr;

reg [15:0] dataR;

// instance of video timing module for monochrome (72hz)
wire [9:0] vcnt_mono, hcnt_mono;
wire hs_mono, vs_mono, hmax_mono, vmax_mono;
timing timing_mono (
		.clk 		(clk			),
		.reset 	(reset		),
		.vcnt 	(vcnt_mono	),
		.hcnt 	(hcnt_mono	),
		.vs 		(vs_mono		),
		.hs 		(hs_mono		),
		.vmax 	(vmax_mono	),
		.hmax 	(hmax_mono	)
);

// instance of video timing module for pal@56Hz, 32kHz
wire [9:0] vcnt_pal56, hcnt_pal56;
wire hs_pal56, vs_pal56, hmax_pal56, vmax_pal56, bd_pal56;
timing #(10'd120, 10'd40, 10'd200, 10'd100, 10'd3, 10'd66) timing_pal56 (
		.clk 		(clk			),
		.reset 	(reset		),
		.border 	(bd_pal56	),
		.vcnt 	(vcnt_pal56	),
		.hcnt 	(hcnt_pal56	),
		.vs 		(vs_pal56	),
		.hs 		(hs_pal56	),
		.vmax 	(vmax_pal56	),
		.hmax 	(hmax_pal56	)
);

// instance of video timing module for pal@50Hz, 32kHz
wire [9:0] vcnt_pal50, hcnt_pal50;
wire hs_pal50, vs_pal50, hmax_pal50, vmax_pal50, bd_pal50;
timing #(10'd128, 10'd40, 10'd192, 10'd117, 10'd3, 10'd117) timing_pal50 (
 		.clk 		(clk			),
		.reset 	(reset		),
		.border 	(bd_pal50	),
		.vcnt 	(vcnt_pal50	),
		.hcnt 	(hcnt_pal50	),
		.vs 		(vs_pal50	),
		.hs 		(hs_pal50	),
		.vmax 	(vmax_pal50	),
		.hmax 	(hmax_pal50	)
);

// instance of video timing module for ntsc@60Hz, 32kHz
wire [9:0] vcnt_ntsc, hcnt_ntsc;
wire hs_ntsc, vs_ntsc, hmax_ntsc, vmax_ntsc, bd_ntsc;
timing #(10'd160, 10'd40, 10'd160, 10'd64, 10'd3, 10'd64) timing_ntsc (
		.clk 		(clk			),
		.reset 	(reset		),
		.border 	(bd_ntsc		),
		.vcnt 	(vcnt_ntsc	),
		.hcnt 	(hcnt_ntsc	),
		.vs 		(vs_ntsc		),
		.hs 		(hs_ntsc		),
		.vmax 	(vmax_ntsc	),
		.hmax 	(hmax_ntsc	)
);

// ----------- de-multiplex video timing signals ------------

// de-multiplex pal50(50hz)/pal56(56hz) timing
wire [9:0] hcnt_pal = pal56?hcnt_pal56:hcnt_pal50;
wire [9:0] vcnt_pal = pal56?vcnt_pal56:vcnt_pal50;
wire bd_pal = pal56?bd_pal56:bd_pal50;
wire hs_pal = pal56?hs_pal56:hs_pal50;
wire vs_pal = pal56?vs_pal56:vs_pal50;
wire hmax_pal = pal56?hmax_pal56:hmax_pal50;
wire vmax_pal = pal56?vmax_pal56:vmax_pal50;

// de-multiplex pal(50hz/56hz)/ntsc(60hz) timing
wire [9:0] hcnt_color = pal?hcnt_pal:hcnt_ntsc;
wire [9:0] vcnt_color = pal?vcnt_pal:vcnt_ntsc;
wire bd_color = pal?bd_pal:bd_ntsc;
wire hs_color = pal?hs_pal:hs_ntsc;
wire vs_color = pal?vs_pal:vs_ntsc;
wire hmax_color = pal?hmax_pal:hmax_ntsc;
wire vmax_color = pal?vmax_pal:vmax_ntsc;

// de-multiplex mono(72hz)/color(50hz/56hz/60hz) timing
wire [9:0] hcnt = mono?hcnt_mono:hcnt_color;
wire [9:0] vcnt = mono?vcnt_mono:vcnt_color;
wire bd = mono?1'b0:bd_color;
// monochome is 640x480 (hs & vs neg)
// color is 800x600 (hs & vs pos)
wire hmax = mono?hmax_mono:hmax_color;
wire vmax = mono?vmax_mono:vmax_color;

always @(posedge clk) begin
   hs <= mono?~hs_mono:hs_color;
   vs <= mono?~vs_mono:vs_color;
end

reg [15:0] tx, tx0, tx1, tx2, tx3;      // output shift registers

localparam BASE_ADDR = 23'h8000;   // default video base address 0x010000
reg [22:0] _v_bas_ad;              // video base address register

reg [1:0] shmode;
wire mono = (shmode == 2'd2);
wire low = (shmode == 2'd0);

// syncmode is delayed until next vsync to cope with "bottom border overscan"
reg [1:0] syncmode;
reg [1:0] syncmode_latch;
wire pal = (syncmode_latch[1] == 1'b1);

reg overscan;        	// overscan detected in current frame
reg overscan_latched;

// 16 colors with 3*3 bits each
reg [2:0] palette_r[15:0];
reg [2:0] palette_g[15:0];
reg [2:0] palette_b[15:0];

always @(reg_sel, reg_rw, reg_uds, reg_lds, reg_addr, _v_bas_ad, shmode, vaddr, syncmode) begin
	reg_dout = 16'h0000;

	// read registers
	if(reg_sel && reg_rw) begin
		
		if(reg_addr == 6'h00 && ~reg_lds)
			reg_dout = { 8'h00, _v_bas_ad[22:15]};

		if(reg_addr == 6'h01 && ~reg_lds)
			reg_dout = { 8'h00, _v_bas_ad[14:7]};
			
      if(reg_addr == 6'h02 && ~reg_lds)
         reg_dout = { 8'h00, vaddr[22:15]};

      if(reg_addr == 6'h03 && ~reg_lds)
         reg_dout = { 8'h00, vaddr[14:7]};

      if(reg_addr == 6'h04 && ~reg_lds)
         reg_dout = { 8'h00, vaddr[6:0], 1'b0 };

		if(reg_addr == 6'h05 && ~reg_uds)
			reg_dout = { 6'h00, syncmode, 8'h00};

		// the color palette registers
		if(reg_addr >= 6'h20 && reg_addr < 6'h30 ) begin
			reg_dout[2:0]  = palette_b[reg_addr[3:0]];
			reg_dout[6:4]  = palette_g[reg_addr[3:0]];
			reg_dout[10:8] = palette_r[reg_addr[3:0]];
		end

		if(reg_addr == 6'h30 && ~reg_uds)
			reg_dout = { 6'h00, shmode, 8'h00};
	end
end

always @(negedge reg_clk) begin
	if(reg_reset) begin
		_v_bas_ad <= BASE_ADDR;
		shmode <= DEFAULT_MODE;	// default video mode 2 => mono
		syncmode <= 2'b00;		// 60hz
		
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

// ------------ monochrome video signal ----------------
wire [2:0] blue0 = palette_b[0];
wire mono_bit = blue0[0]?~tx[15]:tx[15];
wire [2:0] mono_rgb = de?{mono_bit, mono_bit, mono_bit}:3'b000;

// --------------- colour video signal ------------------
// border color is taken from palette[0]
wire [3:0] index16 = { tx3[15], tx2[15], tx1[15], tx0[15] };
wire [2:0] color_r = de?palette_r[index16]:(bd?palette_r[0]:3'b000);
wire [2:0] color_g = de?palette_g[index16]:(bd?palette_g[0]:3'b000);
wire [2:0] color_b = de?palette_b[index16]:(bd?palette_b[0]:3'b000);

// de-multiplex color and mono into one vga signal ...
wire [2:0] stvid_r = mono?mono_rgb:color_r;
wire [2:0] stvid_g = mono?mono_rgb:color_g;
wire [2:0] stvid_b = mono?mono_rgb:color_b;

// ... add OSD overlay and feed into VGA outputs
always @(posedge clk) begin
   video_r <= !osd_oe?{stvid_r,stvid_r}:{osd_pixel, osd_pixel, osd_pixel, stvid_r};
   video_g <= !osd_oe?{stvid_g,stvid_g}:{osd_pixel, osd_pixel,      1'b1, stvid_g};
   video_b <= !osd_oe?{stvid_b,stvid_b}:{osd_pixel, osd_pixel, osd_pixel, stvid_b};
end

wire [9:0] overscan_bottom = overscan_latched?10'd60:10'd0;

// display enable signal
// the color modes use a scan doubler and output the data with 2 lines delay
wire [9:0] v_offset = mono?10'd0:10'd2; 
wire de = (hcnt >= H_PRE) && (hcnt < H_ACT+H_PRE) && (vcnt >= v_offset && vcnt < V_ACT+v_offset+overscan_bottom);

// a fake de signal for timer a for color modes with half the hsync frequency
wire deC = (((hcnt >= H_PRE) && !vcnt[0]) || ((hcnt < H_ACT+H_PRE-10'd160) && vcnt[0])) && 
	(vcnt >= (v_offset-10'd0) && vcnt < (V_ACT+v_offset+overscan_bottom-10'd0));

// a fake hsync pulse for the scan doubled color modes
wire hsC = vcnt[0] && hs; 

// create a read signal that's 16 clocks ahead of oe
assign read = (bus_cycle[3:2] == 0) && (hcnt < H_ACT) && (vcnt < V_ACT + overscan_bottom);

reg line;
reg last_syncmode;

always @(posedge clk) begin
	if(reset) begin
		vaddr <= _v_bas_ad;
	end else begin
		last_syncmode <= syncmode[1];  // delay syncmode to detect changes
		line <= vcnt[1];
		
		// ---- scan doubler pointer handling -----
		if(hmax) begin
			// reset counters at and of each line
			sd_rptr <= 7'd0;
			
			if(vcnt[0])
				sd_wptr <= 7'd0;
		end
		
		// ------------ memory fetch --------------
		if(read) begin
			if(bus_cycle == 3) begin
				// 16bit buffer for direct mono generation
				dataR <= data;
				
				// two line buffer for scan doubling
				case(sd_wptr[1:0])
					2'b00: 	sd_buffer0[{!line, sd_wptr[6:2]}] <= data;
					2'b01: 	sd_buffer1[{!line, sd_wptr[6:2]}] <= data;
					2'b10:	sd_buffer2[{!line, sd_wptr[6:2]}] <= data;
					2'b11:	sd_buffer3[{!line, sd_wptr[6:2]}] <= data;
				endcase
					
				// increase scan doubler address
				sd_wptr <= sd_wptr + 7'd1;
					
				// increase video address to next word
				vaddr <= vaddr + 23'd1;
			end
		end else begin
		
			// this is also the magic used to do "overscan".
			// the magic actually involves more than writing zero (60hz)
			// within line 200. But htis is sufficient for our detection
			if(vcnt[9:1] == 8'd200) begin
				// syncmode has changed from 1 to 0 (50 to 60 hz)
				if((syncmode[1] == 1'b0) && (last_syncmode == 1'b1))
					overscan <= 1'b1;
			end
		
			// reached last possible pixel pos
			if(hmax && vmax) begin
				// reset video address counter
				vaddr <= _v_bas_ad;
				
				// copy syncmode
				syncmode_latch <= syncmode;
				
				// save and reset overscan
				overscan_latched <= overscan;
				overscan <= 1'b0;
			end
		end
		
		// ------------ screen output ----------------

		// hires mode: reload shift register every 16 clocks
		if(hcnt[3:0] == 4'b1111)
			tx <= dataR;
		else
			tx[15:1] <= tx[14:0];

		// double buffered color mode: reload every 32 clocks
		// low rez 320x200
		if(low) begin
			if((hcnt < H_ACT) && (hcnt[4:0] == 5'b01110)) begin
				// read words for all four planes
				tx0 <= sd_buffer0[{line, sd_rptr[6:2]}];
				tx1 <= sd_buffer1[{line, sd_rptr[6:2]}];
				tx2 <= sd_buffer2[{line, sd_rptr[6:2]}];
				tx3 <= sd_buffer3[{line, sd_rptr[6:2]}];
				sd_rptr <= sd_rptr + 7'd4;
			end else if(hcnt[0] == 1'b0) begin
				// shift every second pixel			
				tx0[15:1] <= tx0[14:0];
				tx1[15:1] <= tx1[14:0];
				tx2[15:1] <= tx2[14:0];
				tx3[15:1] <= tx3[14:0];
			end
		end else begin
			// med rez 640x200
			if((hcnt < H_ACT) && (hcnt[3:0] == 4'b1111)) begin
				// read words for all four planes
				if(sd_rptr[1] == 1'b0) begin
					tx0 <= sd_buffer0[{line, sd_rptr[6:2]}];
					tx1 <= sd_buffer1[{line, sd_rptr[6:2]}];
				end else begin
					tx0 <= sd_buffer2[{line, sd_rptr[6:2]}];
					tx1 <= sd_buffer3[{line, sd_rptr[6:2]}];
				end
				sd_rptr <= sd_rptr + 7'd2;
			end else begin
				// shift every pixel			
				tx0[15:1] <= tx0[14:0];
				tx1[15:1] <= tx1[14:0];
				tx2[15:1] <= 15'h0000;
				tx3[15:1] <= 15'h0000;
			end
		end
	end
end

// ----------------------------------- OSD -----------------------------------

// this core supports only the display related OSD commands
// of the minimig

reg [7:0]       sbuf;
reg [7:0]       cmd;
reg [4:0]       cnt;
reg [10:0]      bcnt;

// the OSD has its own SPI interface to the io controller
always@(posedge sck, posedge ss) begin
	if(ss == 1'b1) begin
      cnt <= 5'd0;
      bcnt <= 11'd0;
	end else begin
		sbuf <= { sbuf[6:0], sdi};

		// 0:7 is command, rest payload
		if(cnt < 15)
			cnt <= cnt + 4'd1;
		else
			cnt <= 4'd8;

      if(cnt == 7) begin
		   cmd <= {sbuf[6:0], sdi};
			
			// lower three command bits are line address
			bcnt <= { sbuf[1:0], sdi, 8'h00};

			// command 0x40: OSDCMDENABLE, OSDCMDDISABLE
			if(sbuf[6:3] == 4'b0100)
				osd_enable <= sdi;
		end

		// command 0x20: OSDCMDWRITE
		if((cmd[7:3] == 5'b00100) && (cnt == 15)) begin
			osd_buffer[bcnt] <= {sbuf[6:0], sdi};
			bcnt <= bcnt + 11'd1;
		end
	end
end

// input from video controller
// vcnt (0..399) / hcnt (0..639)

reg osd_enable;
reg [7:0] osd_buffer [2047:0];	// the OSD buffer itself

localparam OSD_WIDTH  = 10'd256;
localparam OSD_HEIGHT = 10'd128;   // pixels are doubled vertically

localparam OSD_POS_X  = (H_ACT-OSD_WIDTH)>>1;
localparam OSD_POS_Y  = (V_ACT-OSD_HEIGHT)>>1;

localparam OSD_BORDER  = 10'd2;

wire osd_oe    = osd_enable && (
	(hcnt >=  OSD_POS_X-OSD_BORDER) &&
	(hcnt <  (OSD_POS_X + OSD_WIDTH + OSD_BORDER)) &&
	(vcnt >=  OSD_POS_Y - OSD_BORDER) &&
	(vcnt <  (OSD_POS_Y + OSD_HEIGHT + OSD_BORDER)));

wire osd_content_area =
	(hcnt >=  OSD_POS_X) &&
	(hcnt <  (OSD_POS_X + OSD_WIDTH)) &&
	(vcnt >=  OSD_POS_Y) &&
	(vcnt <  (OSD_POS_Y + OSD_HEIGHT));

wire [7:0] osd_hcnt = hcnt - OSD_POS_X + 7'd1;  // one pixel offset for osd_byte register
wire [6:0] osd_vcnt = vcnt - OSD_POS_Y;
	
wire osd_pixel = osd_content_area?osd_byte[osd_vcnt[3:1]]:1'b0;

reg [7:0] osd_byte;
always @(posedge clk)
	osd_byte <= osd_buffer[{osd_vcnt[6:4], osd_hcnt}];
	
endmodule

// generic video timing generator
module timing (
	input         	clk,     // 31.875 MHz pixel clock
	input         	reset,

	output border,              // border (incl active area)

	output reg [9:0]   vcnt,    // vertical pixel counter
	output reg [9:0]   hcnt,    // horizontal pixel counter

	output vs,              // vertical sync signal
	output hs,              // horizontal sync signal
	
	output vmax,            // max vertical pixel position reached
	output hmax             // max horizontal pixel position reached
);

localparam H_PRE = 10'd16;
localparam H_ACT = 10'd640;
localparam V_ACT = 10'd400;

// default: VESA 640x480x72 timing (2*40 blank lines added)
// VESA == 31.5 MHz, Atari ST == 32 Mhz, MIST == 31.875MHz
parameter H_FP  = 10'd24;
parameter H_S   = 10'd40;
parameter H_BP  = 10'd128;
localparam H_TOT = H_ACT + H_FP + H_S + H_BP;

parameter V_FP  = 10'd55;
parameter V_S   = 10'd3;
parameter V_BP  = 10'd73;
localparam V_TOT = V_ACT + V_FP + V_S + V_BP;

// generate sync pulses
assign hs = (hcnt >= (H_ACT+H_FP+H_PRE)) && (hcnt < (H_ACT+H_FP+H_S+H_PRE));
assign vs = (vcnt >= (V_ACT+V_FP)) && (vcnt < (V_ACT+V_FP+V_S));

// max is not really the max possible position but something "far" behind the
// visible area to allow for counter resets etc
assign hmax = (hcnt == H_ACT + H_FP + H_PRE);
assign vmax = (vcnt == V_ACT + V_FP);

localparam H_BORDER = 10'd40;
localparam V_BORDER = 10'd40;

// the following only works if H_BORDER > H_PRE
wire rborder = (hcnt < H_ACT+H_PRE+H_BORDER)  && ((vcnt < V_ACT+V_BORDER)   || (vcnt >= V_TOT-V_BORDER));
wire lborder = (hcnt >= H_TOT-H_BORDER+H_PRE) && ((vcnt < V_ACT+V_BORDER-1) || (vcnt >= V_TOT-V_BORDER-1));

assign border = lborder || rborder;

always @(posedge clk) begin
	// ------------ video counters --------------
	if(reset) begin
		// using reset here is important to make sure video counters
		// run synchronous to bus state machine
		hcnt <= 10'd0;
		vcnt <= 10'd0;
	end else begin
		// horizontal video counter
		if(hcnt < H_TOT - 10'd1)
			hcnt <= hcnt + 10'd1;
		else begin
			hcnt <= 10'd0;
			// vertical video counter
			if(vcnt < V_TOT - 10'd1)
				vcnt <= vcnt + 10'd1;
			else begin
				vcnt <= 10'd0;
			end
		end
	end
end


endmodule