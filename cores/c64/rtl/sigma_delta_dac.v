
// sigmadelta.v
// two channel second order sigma delta dac
// taken from Minimig

// audio data processing
// stereo sigma/delta bitstream modulator
module sigma_delta_dac (
	input 			clk,			// bus clock
	input	[14:0]	ldatasum,	// left channel data
	input	[14:0] 	rdatasum,	// right channel data
	output	reg 	aleft=0,		// left bitstream output
	output	reg 	aright=0		// right bitsteam output
);

//--------------------------------------------------------------------------------------

// local signals
localparam DW = 15;
localparam CW = 2;
localparam RW  = 4;
localparam A1W = 2;
localparam A2W = 5;

wire [DW+2+0  -1:0] sd_l_er0, sd_r_er0;
reg  [DW+2+0  -1:0] sd_l_er0_prev=0, sd_r_er0_prev=0;
wire [DW+A1W+2-1:0] sd_l_aca1,  sd_r_aca1;
wire [DW+A2W+2-1:0] sd_l_aca2,  sd_r_aca2;
reg  [DW+A1W+2-1:0] sd_l_ac1=0, sd_r_ac1=0;
reg  [DW+A2W+2-1:0] sd_l_ac2=0, sd_r_ac2=0;
wire [DW+A2W+3-1:0] sd_l_quant, sd_r_quant;

// LPF noise LFSR
reg [24-1:0] seed1 = 24'h654321;
reg [19-1:0] seed2 = 19'h12345;
reg [24-1:0] seed_sum=0, seed_prev=0, seed_out=0;
always @ (posedge clk) begin
  if (&seed1)
    seed1 <= #1 24'h654321;
  else
    seed1 <= #1 {seed1[22:0], ~(seed1[23] ^ seed1[22] ^ seed1[21] ^ seed1[16])};
end
always @ (posedge clk) begin
  if (&seed2)
    seed2 <= #1 19'h12345;
  else
    seed2 <= #1 {seed2[17:0], ~(seed2[18] ^ seed2[17] ^ seed2[16] ^ seed2[13] ^ seed2[0])};
end
always @ (posedge clk) begin
  seed_sum  <= #1 seed1 + {5'b0, seed2};
  seed_prev <= #1 seed_sum;
  seed_out  <= #1 seed_sum - seed_prev;
end

// linear interpolate
localparam ID=4; // counter size, also 2^ID = interpolation rate
reg  [ID+0-1:0] int_cnt = 0;
always @ (posedge clk) int_cnt <= #1 int_cnt + 'd1;

reg  [DW+0-1:0] ldata_cur=0, ldata_prev=0;
reg  [DW+0-1:0] rdata_cur=0, rdata_prev=0;
wire [DW+1-1:0] ldata_step, rdata_step;
reg  [DW+ID-1:0] ldata_int=0, rdata_int=0;
wire [DW+0-1:0] ldata_int_out, rdata_int_out;
assign ldata_step = {ldata_cur[DW-1], ldata_cur} - {ldata_prev[DW-1], ldata_prev}; // signed subtract
assign rdata_step = {rdata_cur[DW-1], rdata_cur} - {rdata_prev[DW-1], rdata_prev}; // signed subtract
always @ (posedge clk) begin
  if (~|int_cnt) begin
    ldata_prev <= #1 ldata_cur;
    ldata_cur  <= #1 ldatasum; //{~ldatasum[DW-1], ldatasum[DW-2:0]}; // convert to offset binary, samples no longer signed!
    rdata_prev <= #1 rdata_cur;
    rdata_cur  <= #1 rdatasum; //{~rdatasum[DW-1], rdatasum[DW-2:0]}; // convert to offset binary, samples no longer signed!
    ldata_int  <= #1 {ldata_cur[DW-1], ldata_cur, {ID{1'b0}}};
    rdata_int  <= #1 {rdata_cur[DW-1], rdata_cur, {ID{1'b0}}};
  end else begin
    ldata_int  <= #1 ldata_int + {{ID{ldata_step[DW+1-1]}}, ldata_step};
    rdata_int  <= #1 rdata_int + {{ID{rdata_step[DW+1-1]}}, rdata_step};
  end
end
assign ldata_int_out = ldata_int[DW+ID-1:ID];
assign rdata_int_out = rdata_int[DW+ID-1:ID];

// input gain x3
wire [DW+2-1:0] ldata_gain, rdata_gain;
assign ldata_gain = {ldata_int_out[DW-1], ldata_int_out, 1'b0} + {{(2){ldata_int_out[DW-1]}}, ldata_int_out};
assign rdata_gain = {rdata_int_out[DW-1], rdata_int_out, 1'b0} + {{(2){rdata_int_out[DW-1]}}, rdata_int_out};

/*
// random dither to 15 bits
reg [DW-1:0] ldata=0, rdata=0;
always @ (posedge clk) begin
  ldata <= #1 ldata_gain[DW+2-1:2] + ( (~(&ldata_gain[DW+2-1-1:2]) && (ldata_gain[1:0] > seed_out[1:0])) ? 15'd1 : 15'd0 );
  rdata <= #1 rdata_gain[DW+2-1:2] + ( (~(&ldata_gain[DW+2-1-1:2]) && (ldata_gain[1:0] > seed_out[1:0])) ? 15'd1 : 15'd0 );
end
*/

// accumulator adders
assign sd_l_aca1 = {{(A1W){ldata_gain[DW+2-1]}}, ldata_gain} - {{(A1W){sd_l_er0[DW+2-1]}}, sd_l_er0} + sd_l_ac1;
assign sd_r_aca1 = {{(A1W){rdata_gain[DW+2-1]}}, rdata_gain} - {{(A1W){sd_r_er0[DW+2-1]}}, sd_r_er0} + sd_r_ac1;

assign sd_l_aca2 = {{(A2W-A1W){sd_l_aca1[DW+A1W+2-1]}}, sd_l_aca1} - {{(A2W){sd_l_er0[DW+2-1]}}, sd_l_er0} - {{(A2W+1){sd_l_er0_prev[DW+2-1]}}, sd_l_er0_prev[DW+2-1:1]} + sd_l_ac2;
assign sd_r_aca2 = {{(A2W-A1W){sd_r_aca1[DW+A1W+2-1]}}, sd_r_aca1} - {{(A2W){sd_r_er0[DW+2-1]}}, sd_r_er0} - {{(A2W+1){sd_r_er0_prev[DW+2-1]}}, sd_r_er0_prev[DW+2-1:1]} + sd_r_ac2;

// accumulators
always @ (posedge clk) begin
  sd_l_ac1 <= #1 sd_l_aca1;
  sd_r_ac1 <= #1 sd_r_aca1;
  sd_l_ac2 <= #1 sd_l_aca2;
  sd_r_ac2 <= #1 sd_r_aca2;
end

// value for quantizaton
assign sd_l_quant = {sd_l_ac2[DW+A2W+2-1], sd_l_ac2} + {{(DW+A2W+3-RW){seed_out[RW-1]}}, seed_out[RW-1:0]};
assign sd_r_quant = {sd_r_ac2[DW+A2W+2-1], sd_r_ac2} + {{(DW+A2W+3-RW){seed_out[RW-1]}}, seed_out[RW-1:0]};

// error feedback
assign sd_l_er0 = sd_l_quant[DW+A2W+3-1] ? {1'b1, {(DW+2-1){1'b0}}} : {1'b0, {(DW+2-1){1'b1}}};
assign sd_r_er0 = sd_r_quant[DW+A2W+3-1] ? {1'b1, {(DW+2-1){1'b0}}} : {1'b0, {(DW+2-1){1'b1}}};
always @ (posedge clk) begin
  sd_l_er0_prev <= #1 (&sd_l_er0) ? sd_l_er0 : sd_l_er0+1;
  sd_r_er0_prev <= #1 (&sd_r_er0) ? sd_r_er0 : sd_r_er0+1;
end

// output
always @ (posedge clk) begin
  aleft  <= #1 (~|ldata_gain) ? ~aleft  : ~sd_l_er0[DW+2-1];
  aright <= #1 (~|rdata_gain) ? ~aright : ~sd_r_er0[DW+2-1];
end

endmodule 