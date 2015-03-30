module overlay (
	// OSDs pixel clock, should be synchronous to cores pixel clock to
	// avoid jitter.
	input 	     pclk,
	input        enable,	     

	// values to be displayed
	input [31:0] val_a,
	input [31:0] val_d,
	input [31:0] val_s,
		
	// VGA signals coming from core
	input [5:0]  red_in,
	input [5:0]  green_in,
	input [5:0]  blue_in,
	input 	     hs_in,
	input 	     vs_in,
	
	// VGA signals going to video connector
	output [5:0] red_out,
	output [5:0] green_out,
	output [5:0] blue_out
);

// ****************************************************************************
// video timing and sync polarity anaylsis
// ****************************************************************************

// horizontal counter
reg [9:0] h_cnt;
reg hsD, hsD2;
reg [9:0] hs_low, hs_high;
wire hs_pol = hs_high < hs_low;

always @(posedge pclk) begin
	// bring hsync into local clock domain
	hsD <= hs_in;
	hsD2 <= hsD;

	// falling edge of hs_in
	if(!hsD && hsD2) begin	
		h_cnt <= 10'd0;
		hs_high <= h_cnt;
	end

	// rising edge of hs_in
	else if(hsD && !hsD2) begin	
		h_cnt <= 10'd0;
		hs_low <= h_cnt;
	end 
	
	else
		h_cnt <= h_cnt + 10'd1;
end

// vertical counter
reg [9:0] v_cnt;
reg vsD, vsD2;
reg [9:0] vs_low, vs_high;
wire vs_pol = vs_high < vs_low;

always @(posedge hs_in) begin
	// bring vsync into local clock domain
	vsD <= vs_in;
	vsD2 <= vsD; 

	// falling edge of vs_in 
	if(!vsD && vsD2) begin	
		v_cnt <= 10'd0;
		vs_high <= v_cnt;
	end

	// rising edge of vs_in
	else if(vsD && !vsD2) begin	
		v_cnt <= 10'd0;
		vs_low <= v_cnt;
	end 
	
	else
		v_cnt <= v_cnt + 10'd1;
end

parameter X = 13;
parameter Y = 1;

// address entry (A:XXXXXXXX)
wire a_act;
wire [7:0] a_data; 
entry entry_a ( 
  .h    ( h_cnt  ),
  .v    ( v_cnt  ),

  .t    ( "A"    ),
  .x    ( X      ),			     
  .y    ( Y      ),			     
  .val  ( val_a  ),

  .data ( a_data ),
  .act  ( a_act  )
);

// data entry (D:XXXX)
wire d_act;
wire [7:0] d_data;
entry entry_d (
  .h    ( h_cnt  ),
  .v    ( v_cnt  ),

  .t    ( "D"    ),
  .x    ( X+12   ),			     
  .y    ( Y      ),			     
  .val  ( val_d  ),

  .data ( d_data ),
  .act  ( d_act  )
);

// s (S:XX)
wire s_act; 
wire [7:0] s_data;
entry entry_s (
  .h    ( h_cnt  ),
  .v    ( v_cnt  ),

  .t    ( "S"    ),
  .x    ( X+24   ),			     
  .y    ( Y      ),			     
  .val  ( val_s  ),

  .data ( s_data ),
  .act  ( s_act  )
);

wire    act = a_act || d_act || s_act;
wire [7:0] data =
	   a_act?a_data:
	   d_act?d_data:
	   s_act?s_data:
	   "-";
   
// ---------------- display -------------------
reg oe;

wire [6:0] font_chr = data-7'd32;
wire [2:0] font_line = v_cnt[4:2];
wire [9:0] font_addr = { font_chr, font_line };
 
wire [7:0] font_data;

// -=- include 8x8 font -=-
font font (
   .clk ( pclk ),
   .a  ( font_addr ),
   .d  ( font_data )
);

reg [7:0] obyte;
reg act_out;
   
always @(posedge pclk) begin
   oe <= 1'b0; 
   act_out <= act;
   
   // only process outside sync phase 
   if((vs_in != vs_pol) && (hs_in != hs_pol)) begin
      if(act_out) begin
	 if(h_cnt[3:0] == 1)    obyte <= font_data;
	 else if(h_cnt[0] == 1) obyte[7:1] <= obyte[6:0];
	 oe <= 1'b1;
      end
   end
end

wire fg = enable && oe && obyte[7];
wire bg = enable && oe;

// mix signal into vga data stream
assign red_out   = fg?6'b111111:bg?{1'b0,  red_in[5:1]}:  red_in;
assign green_out = fg?6'b001000:bg?{1'b0,green_in[5:1]}:green_in;
assign blue_out  = fg?6'b001000:bg?{1'b0, blue_in[5:1]}: blue_in;

endmodule

module entry (
  input [9:0] 	    h,
  input [9:0] 	    v,

  input [7:0] 	    t,
  input [6:0] 	    x,      // first character x position 0-127
  input [5:0] 	    y,      // first character y position 0-63
  input [31:0]     val,

  output [7:0] 	    data,
  output 	    act     // this entry is currently active
);
 
assign act = (h[9:4] >= x) && (h[9:4] < x + 8 + 2) && (y == v[9:5]);

// x position within "string"
wire [6:0] x_i = h[9:4]-x; 

wire [7:0] asc0, asc1, asc2, asc3, asc4, asc5, asc6, asc7;
hex2asc hex0 ( .in (val[31:28]), .out (asc0 ) );
hex2asc hex1 ( .in (val[27:24]), .out (asc1 ) );
hex2asc hex2 ( .in (val[23:20]), .out (asc2 ) );
hex2asc hex3 ( .in (val[19:16]), .out (asc3 ) );
hex2asc hex4 ( .in (val[15:12]), .out (asc4 ) );
hex2asc hex5 ( .in ( val[11:8]), .out (asc5 ) );
hex2asc hex6 ( .in (  val[7:4]), .out (asc6 ) );
hex2asc hex7 ( .in (  val[3:0]), .out (asc7 ) );

assign data = (x_i==0)?t: 
	      (x_i==1)?":":
	      (x_i==2)?asc0:
	      (x_i==3)?asc1:
	      (x_i==4)?asc2:
	      (x_i==5)?asc3:
	      (x_i==6)?asc4:
	      (x_i==7)?asc5:
	      (x_i==8)?asc6:
	      (x_i==9)?asc7:
	      "X";

endmodule

module hex2asc (
  input [3:0] in,
  output [7:0] out
);
   
assign out = (in <= 9)?("0"+in):
	     ("A"-10+in);
 
endmodule
