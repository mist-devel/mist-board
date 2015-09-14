// Gameboy for the MiST
// (c) 2015 Till Harbaum

// The gameboy lcd runs from a shift register which is filled at 4194304 pixels/sec

module lcd (
	input   clk,
	input   clkena,
	input [1:0] data,
	input [1:0] mode,

	input tint,
	
	// pixel clock
   input  pclk,
	input  on,
	
   // VGA output
   output reg	hs,
   output reg 	vs,
   output [5:0] r,
   output [5:0] g,
   output [5:0] b
);

// Mode 00:  h-blank
// Mode 01:  v-blank
// Mode 10:  oam
// Mode 11:  oam and vram

// space for 2*160 pixel
reg [7:0] shift_reg_wptr;
reg p_toggle;
reg [1:0] shift_reg [511:0];
reg [1:0] last_mode_in;

// shift register input
always @(posedge clk) begin
	last_mode_in <= mode;

	// end of vsync
	if(clkena) begin
		shift_reg[{p_toggle, shift_reg_wptr}] <= data;
		shift_reg_wptr <= shift_reg_wptr + 8'd1;
	end
	
	// reset write pointer at end of hsync phase
	if((mode != 2'b00) && (last_mode_in == 2'b00)) begin
		shift_reg_wptr <= 8'd0;
		p_toggle <= !p_toggle;
	end
end
		
// 
parameter H   = 160;    // width of visible area
parameter HFP = 24;     // unused time before hsync
parameter HS  = 20;     // width of hsync
parameter HBP = 24;     // unused time after hsync
// total = 228

parameter V   = 576;    // height of visible area
parameter VFP = 2;      // unused time before vsync
parameter VS  = 2;      // width of vsync
parameter VBP = 36;     // unused time after vsync
// total = 616

reg[7:0] h_cnt;         // horizontal pixel counter
reg[9:0] v_cnt;         // vertical pixel counter

// horizontal pixel counter
reg [1:0] last_mode_h;
always@(posedge pclk) begin
	last_mode_h <= mode;
	
	if(h_cnt==H+HFP+HS+HBP-1)   h_cnt <= 0;
	else                        h_cnt <= h_cnt + 1;

	// generate negative hsync signal
	if(h_cnt == H+HFP)    hs <= 1'b0;
	if(h_cnt == H+HFP+HS) hs <= 1'b1;

	// synchronize to input mode
	// end of hblank
	if((mode == 2'b10) && (last_mode_h == 2'b00))
		h_cnt <= 0;
end

// veritical pixel counter
reg [1:0] last_mode_v;
always@(posedge pclk) begin
	// the vertical counter is processed at the begin of each hsync
	if(h_cnt == H+HFP+HS+HBP-1) begin
		if(v_cnt==VS+VFP+V+VBP-1)  v_cnt <= 0; 
		else							   v_cnt <= v_cnt + 1;

	   // generate positive vsync signal
		if(v_cnt == V+VFP)    vs <= 1'b1;
		if(v_cnt == V+VFP+VS) vs <= 1'b0;

		last_mode_v <= mode;

		// synchronize to input mode
		// end of mode 01 (vblank)
		// make and offset of - 4 for the 4 line delay of the scandoubler
		if((mode != 2'b01) && (last_mode_v == 2'b01))
			v_cnt <= 616-4;
	end
end

// -------------------------------------------------------------------------------
// ------------------------------- pixel generator -------------------------------
// -------------------------------------------------------------------------------
reg blank;
reg [1:0] pixel_reg;
reg [7:0] shift_reg_rptr;

always@(posedge pclk) begin
	// visible area?
	if((v_cnt < V) && (h_cnt < H)) begin
		blank <= 1'b0;
		pixel_reg <= shift_reg[{!p_toggle, shift_reg_rptr}];
		shift_reg_rptr <= shift_reg_rptr + 8'd1;
	end else begin
		blank <= 1'b1;
		shift_reg_rptr <= 8'd0;
	end
end

wire [1:0] pixel = on?pixel_reg:2'b00;

// gameboy "color" palette
wire [5:0] yellow_r = (pixel==0)?6'b100111:(pixel==1)?6'b100000:  // 1:100011
		     (pixel==2)?6'b001100:6'b000111;
wire [5:0] yellow_g = (pixel==0)?6'b101111:(pixel==1)?6'b101000:  // 1:101011
		     (pixel==2)?6'b011001:6'b000100;
wire [5:0] yellow_b = (pixel==0)?6'b000100:(pixel==1)?6'b000010:  // 1:000100
		     (pixel==2)?6'b001100:6'b000100;

// greyscale
wire [5:0] grey = (pixel==0)?6'd63:(pixel==1)?6'd42:(pixel==2)?6'd24:6'd0;

assign r = blank?6'b000000:tint?yellow_r:grey;
assign g = blank?6'b000000:tint?yellow_g:grey;
assign b = blank?6'b000000:tint?yellow_b:grey;

endmodule
