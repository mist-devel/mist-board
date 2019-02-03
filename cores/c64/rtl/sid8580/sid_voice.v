module sid_voice (clock, reset, freq_lo, freq_hi, pw_lo, pw_hi,
                  control, att_dec, sus_rel, osc_msb_in, osc_msb_out,
                  signal_out, osc_out, env_out);

// Input Signals
input wire [0:0] clock;
input wire [0:0] reset;
input wire [7:0] freq_lo;
input wire [7:0] freq_hi;
input wire [7:0] pw_lo;
input wire [3:0] pw_hi;
input wire [7:0] control;
input wire [7:0] att_dec;
input wire [7:0] sus_rel;
input wire [0:0] osc_msb_in;

// Output Signals
output wire [ 0:0] osc_msb_out;
output wire [11:0] signal_out;
output wire [ 7:0] osc_out;
output wire [ 7:0] env_out;

// Internal Signals
reg  [23:0] oscillator;
reg  [ 0:0] osc_edge;
reg  [ 0:0] osc_msb_in_prv;
reg  [11:0] triangle;
reg  [11:0] sawtooth;
reg  [11:0] pulse;
reg  [11:0] noise;
reg  [22:0] lfsr_noise;
reg  [ 7:0] wave__st;
reg  [ 7:0] wave_p_t;
reg  [ 7:0] wave_ps_;
reg  [ 7:0] wave_pst;
wire [ 7:0] envelope;
reg  [11:0] wave_out;
reg  [19:0] dca_out;

`define noise_ctrl   control[7]
`define pulse_ctrl   control[6]
`define saw_ctrl     control[5]
`define tri_ctrl     control[4]
`define test_ctrl    control[3]
`define ringmod_ctrl control[2]
`define sync_ctrl    control[1]

// Signal Assignments
assign osc_msb_out = oscillator[23];
assign signal_out  = dca_out[19:8];
assign osc_out     = wave_out[11:4];
assign env_out     = envelope;

// Digital Controlled Amplifier
always @(posedge clock)
begin
  dca_out <= wave_out * envelope;
end

// Envelope Instantiation
sid_envelope adsr (.clock(clock), .reset(reset), .gate(control[0]),
                  .att_dec(att_dec), .sus_rel(sus_rel), .envelope(envelope));

// Phase Accumulating Oscillator
always @(posedge clock)
begin
  osc_msb_in_prv <= osc_msb_in;
  if (reset || `test_ctrl ||
     ((`sync_ctrl) && (!osc_msb_in) && (osc_msb_in != osc_msb_in_prv)))
    oscillator <= 24'h000000;
  else
    oscillator <= oscillator + {freq_hi, freq_lo};
end

// Waveform Generator
always @(posedge clock)
begin
  if (reset)
    begin
      triangle   <= 12'h000;
      sawtooth   <= 12'h000;
      pulse      <= 12'h000;
      noise      <= 12'h000;
      osc_edge   <= 1'b0;
      lfsr_noise <= 23'h7fffff;
    end
  else
    begin
      triangle <= (`ringmod_ctrl) ?
                  {({11{osc_msb_in}} ^
                  {{11{oscillator[23]}}}) ^ oscillator[22:12], 1'b0} :
                  {{11{oscillator[23]}} ^ oscillator[22:12], 1'b0};
      sawtooth <= oscillator[23:12];
      pulse <= (`test_ctrl) ? 12'hfff :
               (oscillator[23:12] >= {pw_hi, pw_lo}) ? {12{1'b1}} : {12{1'b0}};
      noise <= {lfsr_noise[21], lfsr_noise[19], lfsr_noise[15],
               lfsr_noise[12], lfsr_noise[10], lfsr_noise[6],
               lfsr_noise[3], lfsr_noise[1], 4'b0000};
      osc_edge <= (oscillator[19] && !osc_edge) ? 1'b1 :
                  (!oscillator[19] && osc_edge) ? 1'b0 : osc_edge;
      lfsr_noise <= (oscillator[19] && !osc_edge) ?
                    {lfsr_noise[21:0], (lfsr_noise[22] | `test_ctrl) ^
                    lfsr_noise[17]} : lfsr_noise;
    end
end

// Waveform Output Selector
always @(posedge clock)
begin
  case (control[7:4])
    4'b0001:
      wave_out <= triangle;
    4'b0010:
      wave_out <= sawtooth;
    4'b0011:
      wave_out <= {wave__st, 4'b0000};
    4'b0100:
      wave_out <= pulse;
    4'b0101:
      wave_out <= {wave_p_t, 4'b0000} & pulse;
    4'b0110:
      wave_out <= {wave_ps_, 4'b0000} & pulse;
    4'b0111:
      wave_out <= {wave_pst, 4'b0000} & pulse;
    4'b1000:
      wave_out <= noise;
    default:
      wave_out <= 12'h000;
  endcase
end

// Combined Waveform Lookup Logic
always @(sawtooth or triangle)
begin
  wave__st = (sawtooth < 12'h07e) ? 8'h00 :
             (sawtooth < 12'h080) ? 8'h03 :
             (sawtooth < 12'h0fc) ? 8'h00 :
             (sawtooth < 12'h100) ? 8'h07 :
             (sawtooth < 12'h17e) ? 8'h00 :
             (sawtooth < 12'h180) ? 8'h03 :
             (sawtooth < 12'h1f8) ? 8'h00 :
             (sawtooth < 12'h1fc) ? 8'h0e :
             (sawtooth < 12'h200) ? 8'h0f :
             (sawtooth < 12'h27e) ? 8'h00 :
             (sawtooth < 12'h280) ? 8'h03 :
             (sawtooth < 12'h2fc) ? 8'h00 :
             (sawtooth < 12'h300) ? 8'h07 :
             (sawtooth < 12'h37e) ? 8'h00 :
             (sawtooth < 12'h380) ? 8'h03 :
             (sawtooth < 12'h3bf) ? 8'h00 :
             (sawtooth < 12'h3c0) ? 8'h01 :
             (sawtooth < 12'h3f0) ? 8'h00 :
             (sawtooth < 12'h3f8) ? 8'h1c :
             (sawtooth < 12'h3fa) ? 8'h1e :
             (sawtooth < 12'h400) ? 8'h1f :
             (sawtooth < 12'h47e) ? 8'h00 :
             (sawtooth < 12'h480) ? 8'h03 :
             (sawtooth < 12'h4fc) ? 8'h00 :
             (sawtooth < 12'h500) ? 8'h07 :
             (sawtooth < 12'h57e) ? 8'h00 :
             (sawtooth < 12'h580) ? 8'h03 :
             (sawtooth < 12'h5f8) ? 8'h00 :
             (sawtooth < 12'h5fc) ? 8'h0e :
             (sawtooth < 12'h5ff) ? 8'h0f :
             (sawtooth < 12'h600) ? 8'h1f :
             (sawtooth < 12'h67e) ? 8'h00 :
             (sawtooth < 12'h680) ? 8'h03 :
             (sawtooth < 12'h6fc) ? 8'h00 :
             (sawtooth < 12'h700) ? 8'h07 :
             (sawtooth < 12'h77e) ? 8'h00 :
             (sawtooth < 12'h780) ? 8'h03 :
             (sawtooth < 12'h7bf) ? 8'h00 :
             (sawtooth < 12'h7c0) ? 8'h01 :
             (sawtooth < 12'h7e0) ? 8'h00 :
             (sawtooth < 12'h7f0) ? 8'h38 :
             (sawtooth < 12'h7f7) ? 8'h3c :
             (sawtooth < 12'h7f8) ? 8'h3e :
             (sawtooth < 12'h800) ? 8'h7f :
             (sawtooth < 12'h87e) ? 8'h00 :
             (sawtooth < 12'h880) ? 8'h03 :
             (sawtooth < 12'h8fc) ? 8'h00 :
             (sawtooth < 12'h900) ? 8'h07 :
             (sawtooth < 12'h97e) ? 8'h00 :
             (sawtooth < 12'h980) ? 8'h03 :
             (sawtooth < 12'h9f8) ? 8'h00 :
             (sawtooth < 12'h9fc) ? 8'h0e :
             (sawtooth < 12'ha00) ? 8'h0f :
             (sawtooth < 12'ha7e) ? 8'h00 :
             (sawtooth < 12'ha80) ? 8'h03 :
             (sawtooth < 12'hafc) ? 8'h00 :
             (sawtooth < 12'hb00) ? 8'h07 :
             (sawtooth < 12'hb7e) ? 8'h00 :
             (sawtooth < 12'hb80) ? 8'h03 :
             (sawtooth < 12'hbbf) ? 8'h00 :
             (sawtooth < 12'hbc0) ? 8'h01 :
             (sawtooth < 12'hbf0) ? 8'h00 :
             (sawtooth < 12'hbf8) ? 8'h1c :
             (sawtooth < 12'hbfa) ? 8'h1e :
             (sawtooth < 12'hbfe) ? 8'h1f :
             (sawtooth < 12'hc00) ? 8'h3f :
             (sawtooth < 12'hc7e) ? 8'h00 :
             (sawtooth < 12'hc80) ? 8'h03 :
             (sawtooth < 12'hcfc) ? 8'h00 :
             (sawtooth < 12'hd00) ? 8'h07 :
             (sawtooth < 12'hd7e) ? 8'h00 :
             (sawtooth < 12'hd80) ? 8'h03 :
             (sawtooth < 12'hdbf) ? 8'h00 :
             (sawtooth < 12'hdc0) ? 8'h01 :
             (sawtooth < 12'hdf8) ? 8'h00 :
             (sawtooth < 12'hdfc) ? 8'h0e :
             (sawtooth < 12'hdfe) ? 8'h0f :
             (sawtooth < 12'he00) ? 8'h1f :
             (sawtooth < 12'he7c) ? 8'h00 :
             (sawtooth < 12'he7d) ? 8'h80 :
             (sawtooth < 12'he7e) ? 8'h00 :
             (sawtooth < 12'he80) ? 8'h83 :
             (sawtooth < 12'hefc) ? 8'h80 :
             (sawtooth < 12'heff) ? 8'h87 :
             (sawtooth < 12'hf00) ? 8'h8f :
             (sawtooth < 12'hf01) ? 8'hc0 :
             (sawtooth < 12'hf03) ? 8'he0 :
             (sawtooth < 12'hf05) ? 8'hc0 :
             (sawtooth < 12'hf09) ? 8'he0 :
             (sawtooth < 12'hf11) ? 8'hc0 :
             (sawtooth < 12'hf13) ? 8'he0 :
             (sawtooth < 12'hf18) ? 8'hc0 :
             (sawtooth < 12'hf19) ? 8'he0 :
             (sawtooth < 12'hf21) ? 8'hc0 :
             (sawtooth < 12'hf23) ? 8'he0 :
             (sawtooth < 12'hf25) ? 8'hc0 :
             (sawtooth < 12'hf2b) ? 8'he0 :
             (sawtooth < 12'hf2c) ? 8'hc0 :
             (sawtooth < 12'hf2d) ? 8'he0 :
             (sawtooth < 12'hf2e) ? 8'hc0 :
             (sawtooth < 12'hf7e) ? 8'he0 :
             (sawtooth < 12'hf80) ? 8'he3 :
             (sawtooth < 12'hfbf) ? 8'hf0 :
             (sawtooth < 12'hfc0) ? 8'hf1 :
             (sawtooth < 12'hfe0) ? 8'hf8 :
             (sawtooth < 12'hff0) ? 8'hfc :
             (sawtooth < 12'hff8) ? 8'hfe : 8'hff;
  wave_p_t = (triangle[11:1] < 11'h0ff) ? 8'h00 :
             (triangle[11:1] < 11'h100) ? 8'h07 :
             (triangle[11:1] < 11'h1fb) ? 8'h00 :
             (triangle[11:1] < 11'h1fc) ? 8'h1c :
             (triangle[11:1] < 11'h1fd) ? 8'h00 :
             (triangle[11:1] < 11'h1fe) ? 8'h3c :
             (triangle[11:1] < 11'h200) ? 8'h3f :
             (triangle[11:1] < 11'h2fd) ? 8'h00 :
             (triangle[11:1] < 11'h2fe) ? 8'h0c :
             (triangle[11:1] < 11'h2ff) ? 8'h5e :
             (triangle[11:1] < 11'h300) ? 8'h5f :
             (triangle[11:1] < 11'h377) ? 8'h00 :
             (triangle[11:1] < 11'h378) ? 8'h40 :
             (triangle[11:1] < 11'h37b) ? 8'h00 :
             (triangle[11:1] < 11'h37d) ? 8'h40 :
             (triangle[11:1] < 11'h37f) ? 8'h60 :
             (triangle[11:1] < 11'h380) ? 8'h6f :
             (triangle[11:1] < 11'h39f) ? 8'h00 :
             (triangle[11:1] < 11'h3a0) ? 8'h40 :
             (triangle[11:1] < 11'h3ae) ? 8'h00 :
             (triangle[11:1] < 11'h3b0) ? 8'h40 :
             (triangle[11:1] < 11'h3b3) ? 8'h00 :
             (triangle[11:1] < 11'h3b7) ? 8'h40 :
             (triangle[11:1] < 11'h3b8) ? 8'h60 :
             (triangle[11:1] < 11'h3ba) ? 8'h40 :
             (triangle[11:1] < 11'h3be) ? 8'h60 :
             (triangle[11:1] < 11'h3bf) ? 8'h70 :
             (triangle[11:1] < 11'h3c0) ? 8'h77 :
             (triangle[11:1] < 11'h3c5) ? 8'h00 :
             (triangle[11:1] < 11'h3cd) ? 8'h40 :
             (triangle[11:1] < 11'h3d0) ? 8'h60 :
             (triangle[11:1] < 11'h3d3) ? 8'h40 :
             (triangle[11:1] < 11'h3d7) ? 8'h60 :
             (triangle[11:1] < 11'h3d8) ? 8'h70 :
             (triangle[11:1] < 11'h3db) ? 8'h60 :
             (triangle[11:1] < 11'h3de) ? 8'h70 :
             (triangle[11:1] < 11'h3df) ? 8'h78 :
             (triangle[11:1] < 11'h3e0) ? 8'h7b :
             (triangle[11:1] < 11'h3e3) ? 8'h60 :
             (triangle[11:1] < 11'h3e4) ? 8'h70 :
             (triangle[11:1] < 11'h3e5) ? 8'h60 :
             (triangle[11:1] < 11'h3eb) ? 8'h70 :
             (triangle[11:1] < 11'h3ef) ? 8'h78 :
             (triangle[11:1] < 11'h3f0) ? 8'h7c :
             (triangle[11:1] < 11'h3f3) ? 8'h78 :
             (triangle[11:1] < 11'h3f4) ? 8'h7c :
             (triangle[11:1] < 11'h3f5) ? 8'h78 :
             (triangle[11:1] < 11'h3f7) ? 8'h7c :
             (triangle[11:1] < 11'h3f8) ? 8'h7e :
             (triangle[11:1] < 11'h3f9) ? 8'h7c :
             (triangle[11:1] < 11'h3fb) ? 8'h7e :
             (triangle[11:1] < 11'h400) ? 8'h7f :
             (triangle[11:1] < 11'h47f) ? 8'h00 :
             (triangle[11:1] < 11'h480) ? 8'h80 :
             (triangle[11:1] < 11'h4bd) ? 8'h00 :
             (triangle[11:1] < 11'h4c0) ? 8'h80 :
             (triangle[11:1] < 11'h4cf) ? 8'h00 :
             (triangle[11:1] < 11'h4d0) ? 8'h80 :
             (triangle[11:1] < 11'h4d7) ? 8'h00 :
             (triangle[11:1] < 11'h4d8) ? 8'h80 :
             (triangle[11:1] < 11'h4da) ? 8'h00 :
             (triangle[11:1] < 11'h4e0) ? 8'h80 :
             (triangle[11:1] < 11'h4e3) ? 8'h00 :
             (triangle[11:1] < 11'h4fe) ? 8'h80 :
             (triangle[11:1] < 11'h4ff) ? 8'h8e :
             (triangle[11:1] < 11'h500) ? 8'h9f :
             (triangle[11:1] < 11'h51f) ? 8'h00 :
             (triangle[11:1] < 11'h520) ? 8'h80 :
             (triangle[11:1] < 11'h52b) ? 8'h00 :
             (triangle[11:1] < 11'h52c) ? 8'h80 :
             (triangle[11:1] < 11'h52d) ? 8'h00 :
             (triangle[11:1] < 11'h530) ? 8'h80 :
             (triangle[11:1] < 11'h532) ? 8'h00 :
             (triangle[11:1] < 11'h540) ? 8'h80 :
             (triangle[11:1] < 11'h543) ? 8'h00 :
             (triangle[11:1] < 11'h544) ? 8'h80 :
             (triangle[11:1] < 11'h545) ? 8'h00 :
             (triangle[11:1] < 11'h57f) ? 8'h80 :
             (triangle[11:1] < 11'h580) ? 8'haf :
             (triangle[11:1] < 11'h5bb) ? 8'h80 :
             (triangle[11:1] < 11'h5bf) ? 8'ha0 :
             (triangle[11:1] < 11'h5c0) ? 8'hb7 :
             (triangle[11:1] < 11'h5cf) ? 8'h80 :
             (triangle[11:1] < 11'h5d0) ? 8'ha0 :
             (triangle[11:1] < 11'h5d6) ? 8'h80 :
             (triangle[11:1] < 11'h5db) ? 8'ha0 :
             (triangle[11:1] < 11'h5dc) ? 8'hb0 :
             (triangle[11:1] < 11'h5dd) ? 8'ha0 :
             (triangle[11:1] < 11'h5df) ? 8'hb0 :
             (triangle[11:1] < 11'h5e0) ? 8'hbb :
             (triangle[11:1] < 11'h5e6) ? 8'ha0 :
             (triangle[11:1] < 11'h5e8) ? 8'hb0 :
             (triangle[11:1] < 11'h5e9) ? 8'ha0 :
             (triangle[11:1] < 11'h5eb) ? 8'hb0 :
             (triangle[11:1] < 11'h5ec) ? 8'hb8 :
             (triangle[11:1] < 11'h5ed) ? 8'hb0 :
             (triangle[11:1] < 11'h5ef) ? 8'hb8 :
             (triangle[11:1] < 11'h5f0) ? 8'hbc :
             (triangle[11:1] < 11'h5f1) ? 8'hb0 :
             (triangle[11:1] < 11'h5f5) ? 8'hb8 :
             (triangle[11:1] < 11'h5f7) ? 8'hbc :
             (triangle[11:1] < 11'h5f8) ? 8'hbe :
             (triangle[11:1] < 11'h5fa) ? 8'hbc :
             (triangle[11:1] < 11'h5fb) ? 8'hbe :
             (triangle[11:1] < 11'h5fc) ? 8'hbf :
             (triangle[11:1] < 11'h5fd) ? 8'hbe :
             (triangle[11:1] < 11'h600) ? 8'hbf :
             (triangle[11:1] < 11'h63e) ? 8'h80 :
             (triangle[11:1] < 11'h640) ? 8'hc0 :
             (triangle[11:1] < 11'h657) ? 8'h80 :
             (triangle[11:1] < 11'h658) ? 8'hc0 :
             (triangle[11:1] < 11'h65a) ? 8'h80 :
             (triangle[11:1] < 11'h660) ? 8'hc0 :
             (triangle[11:1] < 11'h663) ? 8'h80 :
             (triangle[11:1] < 11'h664) ? 8'hc0 :
             (triangle[11:1] < 11'h665) ? 8'h80 :
             (triangle[11:1] < 11'h67f) ? 8'hc0 :
             (triangle[11:1] < 11'h680) ? 8'hcf :
             (triangle[11:1] < 11'h686) ? 8'h80 :
             (triangle[11:1] < 11'h689) ? 8'hc0 :
             (triangle[11:1] < 11'h68a) ? 8'h80 :
             (triangle[11:1] < 11'h6bf) ? 8'hc0 :
             (triangle[11:1] < 11'h6c0) ? 8'hd7 :
             (triangle[11:1] < 11'h6dd) ? 8'hc0 :
             (triangle[11:1] < 11'h6df) ? 8'hd0 :
             (triangle[11:1] < 11'h6e0) ? 8'hd9 :
             (triangle[11:1] < 11'h6e7) ? 8'hc0 :
             (triangle[11:1] < 11'h6e8) ? 8'hd0 :
             (triangle[11:1] < 11'h6e9) ? 8'hc0 :
             (triangle[11:1] < 11'h6ed) ? 8'hd0 :
             (triangle[11:1] < 11'h6ef) ? 8'hd8 :
             (triangle[11:1] < 11'h6f0) ? 8'hdc :
             (triangle[11:1] < 11'h6f2) ? 8'hd0 :
             (triangle[11:1] < 11'h6f5) ? 8'hd8 :
             (triangle[11:1] < 11'h6f7) ? 8'hdc :
             (triangle[11:1] < 11'h6f8) ? 8'hde :
             (triangle[11:1] < 11'h6fa) ? 8'hdc :
             (triangle[11:1] < 11'h6fb) ? 8'hde :
             (triangle[11:1] < 11'h6fc) ? 8'hdf :
             (triangle[11:1] < 11'h6fd) ? 8'hde :
             (triangle[11:1] < 11'h700) ? 8'hdf :
             (triangle[11:1] < 11'h71b) ? 8'hc0 :
             (triangle[11:1] < 11'h71c) ? 8'he0 :
             (triangle[11:1] < 11'h71d) ? 8'hc0 :
             (triangle[11:1] < 11'h720) ? 8'he0 :
             (triangle[11:1] < 11'h727) ? 8'hc0 :
             (triangle[11:1] < 11'h728) ? 8'he0 :
             (triangle[11:1] < 11'h72a) ? 8'hc0 :
             (triangle[11:1] < 11'h73f) ? 8'he0 :
             (triangle[11:1] < 11'h740) ? 8'he7 :
             (triangle[11:1] < 11'h75f) ? 8'he0 :
             (triangle[11:1] < 11'h760) ? 8'he8 :
             (triangle[11:1] < 11'h76e) ? 8'he0 :
             (triangle[11:1] < 11'h76f) ? 8'he8 :
             (triangle[11:1] < 11'h770) ? 8'hec :
             (triangle[11:1] < 11'h773) ? 8'he0 :
             (triangle[11:1] < 11'h776) ? 8'he8 :
             (triangle[11:1] < 11'h777) ? 8'hec :
             (triangle[11:1] < 11'h778) ? 8'hee :
             (triangle[11:1] < 11'h77b) ? 8'hec :
             (triangle[11:1] < 11'h77d) ? 8'hee :
             (triangle[11:1] < 11'h780) ? 8'hef :
             (triangle[11:1] < 11'h78d) ? 8'he0 :
             (triangle[11:1] < 11'h790) ? 8'hf0 :
             (triangle[11:1] < 11'h792) ? 8'he0 :
             (triangle[11:1] < 11'h7af) ? 8'hf0 :
             (triangle[11:1] < 11'h7b0) ? 8'hf4 :
             (triangle[11:1] < 11'h7b7) ? 8'hf0 :
             (triangle[11:1] < 11'h7b8) ? 8'hf4 :
             (triangle[11:1] < 11'h7b9) ? 8'hf0 :
             (triangle[11:1] < 11'h7bb) ? 8'hf4 :
             (triangle[11:1] < 11'h7bd) ? 8'hf6 :
             (triangle[11:1] < 11'h7c0) ? 8'hf7 :
             (triangle[11:1] < 11'h7c3) ? 8'hf0 :
             (triangle[11:1] < 11'h7c4) ? 8'hf8 :
             (triangle[11:1] < 11'h7c5) ? 8'hf0 :
             (triangle[11:1] < 11'h7db) ? 8'hf8 :
             (triangle[11:1] < 11'h7dd) ? 8'hfa :
             (triangle[11:1] < 11'h7e0) ? 8'hfb :
             (triangle[11:1] < 11'h7e1) ? 8'hf8 :
             (triangle[11:1] < 11'h7ed) ? 8'hfc :
             (triangle[11:1] < 11'h7f0) ? 8'hfd :
             (triangle[11:1] < 11'h7f8) ? 8'hfe : 8'hff;
  wave_ps_ = (sawtooth < 12'h07f) ? 8'h00 :
             (sawtooth < 12'h080) ? 8'h03 :
             (sawtooth < 12'h0bf) ? 8'h00 :
             (sawtooth < 12'h0c0) ? 8'h01 :
             (sawtooth < 12'h0ff) ? 8'h00 :
             (sawtooth < 12'h100) ? 8'h0f :
             (sawtooth < 12'h17f) ? 8'h00 :
             (sawtooth < 12'h180) ? 8'h07 :
             (sawtooth < 12'h1bf) ? 8'h00 :
             (sawtooth < 12'h1c0) ? 8'h03 :
             (sawtooth < 12'h1df) ? 8'h00 :
             (sawtooth < 12'h1e0) ? 8'h01 :
             (sawtooth < 12'h1fd) ? 8'h00 :
             (sawtooth < 12'h1ff) ? 8'h07 :
             (sawtooth < 12'h200) ? 8'h1f :
             (sawtooth < 12'h27f) ? 8'h00 :
             (sawtooth < 12'h280) ? 8'h03 :
             (sawtooth < 12'h2bf) ? 8'h00 :
             (sawtooth < 12'h2c0) ? 8'h03 :
             (sawtooth < 12'h2df) ? 8'h00 :
             (sawtooth < 12'h2e0) ? 8'h01 :
             (sawtooth < 12'h2fe) ? 8'h00 :
             (sawtooth < 12'h2ff) ? 8'h01 :
             (sawtooth < 12'h300) ? 8'h0f :
             (sawtooth < 12'h33f) ? 8'h00 :
             (sawtooth < 12'h340) ? 8'h01 :
             (sawtooth < 12'h37f) ? 8'h00 :
             (sawtooth < 12'h380) ? 8'h17 :
             (sawtooth < 12'h3bf) ? 8'h00 :
             (sawtooth < 12'h3c0) ? 8'h3b :
             (sawtooth < 12'h3df) ? 8'h00 :
             (sawtooth < 12'h3e0) ? 8'h3d :
             (sawtooth < 12'h3ef) ? 8'h00 :
             (sawtooth < 12'h3f0) ? 8'h3e :
             (sawtooth < 12'h3f7) ? 8'h00 :
             (sawtooth < 12'h3f8) ? 8'h3f :
             (sawtooth < 12'h3f9) ? 8'h00 :
             (sawtooth < 12'h3fa) ? 8'h0c :
             (sawtooth < 12'h3fb) ? 8'h1c :
             (sawtooth < 12'h3fc) ? 8'h3f :
             (sawtooth < 12'h3fd) ? 8'h1e :
             (sawtooth < 12'h400) ? 8'h3f :
             (sawtooth < 12'h47f) ? 8'h00 :
             (sawtooth < 12'h480) ? 8'h03 :
             (sawtooth < 12'h4bf) ? 8'h00 :
             (sawtooth < 12'h4c0) ? 8'h01 :
             (sawtooth < 12'h4ff) ? 8'h00 :
             (sawtooth < 12'h500) ? 8'h0f :
             (sawtooth < 12'h53f) ? 8'h00 :
             (sawtooth < 12'h540) ? 8'h01 :
             (sawtooth < 12'h57f) ? 8'h00 :
             (sawtooth < 12'h580) ? 8'h07 :
             (sawtooth < 12'h5bf) ? 8'h00 :
             (sawtooth < 12'h5c0) ? 8'h0b :
             (sawtooth < 12'h5df) ? 8'h00 :
             (sawtooth < 12'h5e0) ? 8'h0a :
             (sawtooth < 12'h5ef) ? 8'h00 :
             (sawtooth < 12'h5f0) ? 8'h5e :
             (sawtooth < 12'h5f7) ? 8'h00 :
             (sawtooth < 12'h5f8) ? 8'h5f :
             (sawtooth < 12'h5fb) ? 8'h00 :
             (sawtooth < 12'h5fc) ? 8'h5f :
             (sawtooth < 12'h5fd) ? 8'h0c :
             (sawtooth < 12'h600) ? 8'h5f :
             (sawtooth < 12'h63f) ? 8'h00 :
             (sawtooth < 12'h640) ? 8'h01 :
             (sawtooth < 12'h67f) ? 8'h00 :
             (sawtooth < 12'h680) ? 8'h47 :
             (sawtooth < 12'h6bf) ? 8'h00 :
             (sawtooth < 12'h6c0) ? 8'h43 :
             (sawtooth < 12'h6df) ? 8'h00 :
             (sawtooth < 12'h6e0) ? 8'h65 :
             (sawtooth < 12'h6ef) ? 8'h00 :
             (sawtooth < 12'h6f0) ? 8'h6e :
             (sawtooth < 12'h6f7) ? 8'h00 :
             (sawtooth < 12'h6f8) ? 8'h6f :
             (sawtooth < 12'h6f9) ? 8'h00 :
             (sawtooth < 12'h6fb) ? 8'h40 :
             (sawtooth < 12'h6fc) ? 8'h6f :
             (sawtooth < 12'h6fd) ? 8'h40 :
             (sawtooth < 12'h700) ? 8'h6f :
             (sawtooth < 12'h73f) ? 8'h00 :
             (sawtooth < 12'h740) ? 8'h63 :
             (sawtooth < 12'h75e) ? 8'h00 :
             (sawtooth < 12'h75f) ? 8'h40 :
             (sawtooth < 12'h760) ? 8'h61 :
             (sawtooth < 12'h767) ? 8'h00 :
             (sawtooth < 12'h768) ? 8'h40 :
             (sawtooth < 12'h76b) ? 8'h00 :
             (sawtooth < 12'h76c) ? 8'h40 :
             (sawtooth < 12'h76d) ? 8'h00 :
             (sawtooth < 12'h76f) ? 8'h40 :
             (sawtooth < 12'h770) ? 8'h70 :
             (sawtooth < 12'h772) ? 8'h00 :
             (sawtooth < 12'h777) ? 8'h40 :
             (sawtooth < 12'h778) ? 8'h70 :
             (sawtooth < 12'h779) ? 8'h40 :
             (sawtooth < 12'h77b) ? 8'h60 :
             (sawtooth < 12'h77c) ? 8'h77 :
             (sawtooth < 12'h77d) ? 8'h60 :
             (sawtooth < 12'h780) ? 8'h77 :
             (sawtooth < 12'h78f) ? 8'h00 :
             (sawtooth < 12'h790) ? 8'h40 :
             (sawtooth < 12'h796) ? 8'h00 :
             (sawtooth < 12'h797) ? 8'h40 :
             (sawtooth < 12'h798) ? 8'h60 :
             (sawtooth < 12'h799) ? 8'h00 :
             (sawtooth < 12'h79b) ? 8'h40 :
             (sawtooth < 12'h79c) ? 8'h60 :
             (sawtooth < 12'h79d) ? 8'h40 :
             (sawtooth < 12'h79f) ? 8'h60 :
             (sawtooth < 12'h7a0) ? 8'h79 :
             (sawtooth < 12'h7a1) ? 8'h00 :
             (sawtooth < 12'h7a7) ? 8'h40 :
             (sawtooth < 12'h7a8) ? 8'h60 :
             (sawtooth < 12'h7ab) ? 8'h40 :
             (sawtooth < 12'h7af) ? 8'h60 :
             (sawtooth < 12'h7b0) ? 8'h78 :
             (sawtooth < 12'h7b1) ? 8'h40 :
             (sawtooth < 12'h7b7) ? 8'h60 :
             (sawtooth < 12'h7b8) ? 8'h78 :
             (sawtooth < 12'h7b9) ? 8'h60 :
             (sawtooth < 12'h7bb) ? 8'h70 :
             (sawtooth < 12'h7bc) ? 8'h78 :
             (sawtooth < 12'h7bd) ? 8'h70 :
             (sawtooth < 12'h7be) ? 8'h79 :
             (sawtooth < 12'h7c0) ? 8'h7b :
             (sawtooth < 12'h7c7) ? 8'h60 :
             (sawtooth < 12'h7c8) ? 8'h70 :
             (sawtooth < 12'h7cb) ? 8'h60 :
             (sawtooth < 12'h7cc) ? 8'h70 :
             (sawtooth < 12'h7cd) ? 8'h60 :
             (sawtooth < 12'h7cf) ? 8'h70 :
             (sawtooth < 12'h7d0) ? 8'h7c :
             (sawtooth < 12'h7d1) ? 8'h60 :
             (sawtooth < 12'h7d7) ? 8'h70 :
             (sawtooth < 12'h7d8) ? 8'h7c :
             (sawtooth < 12'h7d9) ? 8'h70 :
             (sawtooth < 12'h7db) ? 8'h78 :
             (sawtooth < 12'h7dc) ? 8'h7c :
             (sawtooth < 12'h7dd) ? 8'h78 :
             (sawtooth < 12'h7df) ? 8'h7c :
             (sawtooth < 12'h7e0) ? 8'h7d :
             (sawtooth < 12'h7e1) ? 8'h70 :
             (sawtooth < 12'h7e7) ? 8'h78 :
             (sawtooth < 12'h7e8) ? 8'h7c :
             (sawtooth < 12'h7e9) ? 8'h78 :
             (sawtooth < 12'h7eb) ? 8'h7c :
             (sawtooth < 12'h7ec) ? 8'h7e :
             (sawtooth < 12'h7ed) ? 8'h7c :
             (sawtooth < 12'h7f0) ? 8'h7e :
             (sawtooth < 12'h7f3) ? 8'h7c :
             (sawtooth < 12'h7f5) ? 8'h7e :
             (sawtooth < 12'h7f8) ? 8'h7f :
             (sawtooth < 12'h7f9) ? 8'h7e :
             (sawtooth < 12'h7ff) ? 8'h7f :
             (sawtooth < 12'h800) ? 8'hff :
             (sawtooth < 12'h87f) ? 8'h00 :
             (sawtooth < 12'h880) ? 8'h03 :
             (sawtooth < 12'h8bf) ? 8'h00 :
             (sawtooth < 12'h8c0) ? 8'h01 :
             (sawtooth < 12'h8ff) ? 8'h00 :
             (sawtooth < 12'h900) ? 8'h8f :
             (sawtooth < 12'h93f) ? 8'h00 :
             (sawtooth < 12'h940) ? 8'h01 :
             (sawtooth < 12'h97f) ? 8'h00 :
             (sawtooth < 12'h980) ? 8'h87 :
             (sawtooth < 12'h9bf) ? 8'h00 :
             (sawtooth < 12'h9c0) ? 8'h83 :
             (sawtooth < 12'h9de) ? 8'h00 :
             (sawtooth < 12'h9df) ? 8'h80 :
             (sawtooth < 12'h9e0) ? 8'h8d :
             (sawtooth < 12'h9e7) ? 8'h00 :
             (sawtooth < 12'h9e8) ? 8'h80 :
             (sawtooth < 12'h9eb) ? 8'h00 :
             (sawtooth < 12'h9ec) ? 8'h80 :
             (sawtooth < 12'h9ed) ? 8'h00 :
             (sawtooth < 12'h9ef) ? 8'h80 :
             (sawtooth < 12'h9f0) ? 8'h8e :
             (sawtooth < 12'h9f3) ? 8'h00 :
             (sawtooth < 12'h9f7) ? 8'h80 :
             (sawtooth < 12'h9f8) ? 8'h8f :
             (sawtooth < 12'h9fb) ? 8'h80 :
             (sawtooth < 12'h9fc) ? 8'h9f :
             (sawtooth < 12'h9fd) ? 8'h80 :
             (sawtooth < 12'ha00) ? 8'h9f :
             (sawtooth < 12'ha3f) ? 8'h00 :
             (sawtooth < 12'ha40) ? 8'h01 :
             (sawtooth < 12'ha6f) ? 8'h00 :
             (sawtooth < 12'ha70) ? 8'h80 :
             (sawtooth < 12'ha77) ? 8'h00 :
             (sawtooth < 12'ha78) ? 8'h80 :
             (sawtooth < 12'ha7b) ? 8'h00 :
             (sawtooth < 12'ha7c) ? 8'h80 :
             (sawtooth < 12'ha7d) ? 8'h00 :
             (sawtooth < 12'ha7f) ? 8'h80 :
             (sawtooth < 12'ha80) ? 8'h87 :
             (sawtooth < 12'ha9f) ? 8'h00 :
             (sawtooth < 12'haa0) ? 8'h80 :
             (sawtooth < 12'haaf) ? 8'h00 :
             (sawtooth < 12'hab0) ? 8'h80 :
             (sawtooth < 12'hab7) ? 8'h00 :
             (sawtooth < 12'hab8) ? 8'h80 :
             (sawtooth < 12'habb) ? 8'h00 :
             (sawtooth < 12'habf) ? 8'h80 :
             (sawtooth < 12'hac0) ? 8'h83 :
             (sawtooth < 12'hacf) ? 8'h00 :
             (sawtooth < 12'had0) ? 8'h80 :
             (sawtooth < 12'had5) ? 8'h00 :
             (sawtooth < 12'had8) ? 8'h80 :
             (sawtooth < 12'had9) ? 8'h00 :
             (sawtooth < 12'hadf) ? 8'h80 :
             (sawtooth < 12'hae0) ? 8'h81 :
             (sawtooth < 12'haef) ? 8'h80 :
             (sawtooth < 12'haf0) ? 8'h84 :
             (sawtooth < 12'haf7) ? 8'h80 :
             (sawtooth < 12'haf8) ? 8'h87 :
             (sawtooth < 12'hafb) ? 8'h80 :
             (sawtooth < 12'hafc) ? 8'h87 :
             (sawtooth < 12'hafd) ? 8'h80 :
             (sawtooth < 12'hafe) ? 8'h8f :
             (sawtooth < 12'hb00) ? 8'haf :
             (sawtooth < 12'hb0f) ? 8'h00 :
             (sawtooth < 12'hb10) ? 8'h80 :
             (sawtooth < 12'hb17) ? 8'h00 :
             (sawtooth < 12'hb18) ? 8'h80 :
             (sawtooth < 12'hb1b) ? 8'h00 :
             (sawtooth < 12'hb20) ? 8'h80 :
             (sawtooth < 12'hb23) ? 8'h00 :
             (sawtooth < 12'hb24) ? 8'h80 :
             (sawtooth < 12'hb26) ? 8'h00 :
             (sawtooth < 12'hb28) ? 8'h80 :
             (sawtooth < 12'hb29) ? 8'h00 :
             (sawtooth < 12'hb3f) ? 8'h80 :
             (sawtooth < 12'hb40) ? 8'h83 :
             (sawtooth < 12'hb5f) ? 8'h80 :
             (sawtooth < 12'hb60) ? 8'h81 :
             (sawtooth < 12'hb6f) ? 8'h80 :
             (sawtooth < 12'hb70) ? 8'ha0 :
             (sawtooth < 12'hb77) ? 8'h80 :
             (sawtooth < 12'hb78) ? 8'ha0 :
             (sawtooth < 12'hb7b) ? 8'h80 :
             (sawtooth < 12'hb7c) ? 8'ha0 :
             (sawtooth < 12'hb7d) ? 8'h80 :
             (sawtooth < 12'hb7e) ? 8'ha3 :
             (sawtooth < 12'hb80) ? 8'hb7 :
             (sawtooth < 12'hb9f) ? 8'h80 :
             (sawtooth < 12'hba0) ? 8'hb1 :
             (sawtooth < 12'hbaf) ? 8'h80 :
             (sawtooth < 12'hbb0) ? 8'hb0 :
             (sawtooth < 12'hbb7) ? 8'h80 :
             (sawtooth < 12'hbb8) ? 8'hb0 :
             (sawtooth < 12'hbb9) ? 8'h80 :
             (sawtooth < 12'hbbb) ? 8'ha0 :
             (sawtooth < 12'hbbc) ? 8'hb0 :
             (sawtooth < 12'hbbd) ? 8'ha0 :
             (sawtooth < 12'hbbe) ? 8'hb8 :
             (sawtooth < 12'hbbf) ? 8'hb9 :
             (sawtooth < 12'hbc0) ? 8'hbb :
             (sawtooth < 12'hbc7) ? 8'h80 :
             (sawtooth < 12'hbc8) ? 8'ha0 :
             (sawtooth < 12'hbcb) ? 8'h80 :
             (sawtooth < 12'hbcc) ? 8'ha0 :
             (sawtooth < 12'hbcd) ? 8'h80 :
             (sawtooth < 12'hbcf) ? 8'ha0 :
             (sawtooth < 12'hbd0) ? 8'hb8 :
             (sawtooth < 12'hbd1) ? 8'h80 :
             (sawtooth < 12'hbd7) ? 8'ha0 :
             (sawtooth < 12'hbd8) ? 8'hb8 :
             (sawtooth < 12'hbd9) ? 8'ha0 :
             (sawtooth < 12'hbdb) ? 8'hb0 :
             (sawtooth < 12'hbdc) ? 8'hb8 :
             (sawtooth < 12'hbdd) ? 8'hb0 :
             (sawtooth < 12'hbdf) ? 8'hbc :
             (sawtooth < 12'hbe0) ? 8'hbd :
             (sawtooth < 12'hbe1) ? 8'ha0 :
             (sawtooth < 12'hbe5) ? 8'hb0 :
             (sawtooth < 12'hbe7) ? 8'hb8 :
             (sawtooth < 12'hbe8) ? 8'hbc :
             (sawtooth < 12'hbe9) ? 8'hb0 :
             (sawtooth < 12'hbeb) ? 8'hb8 :
             (sawtooth < 12'hbec) ? 8'hbc :
             (sawtooth < 12'hbed) ? 8'hb8 :
             (sawtooth < 12'hbee) ? 8'hbc :
             (sawtooth < 12'hbf0) ? 8'hbe :
             (sawtooth < 12'hbf1) ? 8'hb8 :
             (sawtooth < 12'hbf3) ? 8'hbc :
             (sawtooth < 12'hbf4) ? 8'hbe :
             (sawtooth < 12'hbf5) ? 8'hbc :
             (sawtooth < 12'hbf7) ? 8'hbe :
             (sawtooth < 12'hbf8) ? 8'hbf :
             (sawtooth < 12'hbf9) ? 8'hbe :
             (sawtooth < 12'hc00) ? 8'hbf :
             (sawtooth < 12'hc03) ? 8'h00 :
             (sawtooth < 12'hc04) ? 8'h80 :
             (sawtooth < 12'hc07) ? 8'h00 :
             (sawtooth < 12'hc08) ? 8'h80 :
             (sawtooth < 12'hc0b) ? 8'h00 :
             (sawtooth < 12'hc0c) ? 8'h80 :
             (sawtooth < 12'hc0f) ? 8'h00 :
             (sawtooth < 12'hc10) ? 8'h80 :
             (sawtooth < 12'hc11) ? 8'h00 :
             (sawtooth < 12'hc18) ? 8'h80 :
             (sawtooth < 12'hc19) ? 8'h00 :
             (sawtooth < 12'hc3f) ? 8'h80 :
             (sawtooth < 12'hc40) ? 8'h81 :
             (sawtooth < 12'hc7f) ? 8'h80 :
             (sawtooth < 12'hc80) ? 8'hc7 :
             (sawtooth < 12'hcbe) ? 8'h80 :
             (sawtooth < 12'hcbf) ? 8'hc0 :
             (sawtooth < 12'hcc0) ? 8'hc3 :
             (sawtooth < 12'hccf) ? 8'h80 :
             (sawtooth < 12'hcd0) ? 8'hc0 :
             (sawtooth < 12'hcd7) ? 8'h80 :
             (sawtooth < 12'hcd8) ? 8'hc0 :
             (sawtooth < 12'hcdb) ? 8'h80 :
             (sawtooth < 12'hcdc) ? 8'hc0 :
             (sawtooth < 12'hcdd) ? 8'h80 :
             (sawtooth < 12'hcdf) ? 8'hc0 :
             (sawtooth < 12'hce0) ? 8'hc1 :
             (sawtooth < 12'hce7) ? 8'h80 :
             (sawtooth < 12'hce8) ? 8'hc0 :
             (sawtooth < 12'hceb) ? 8'h80 :
             (sawtooth < 12'hcf7) ? 8'hc0 :
             (sawtooth < 12'hcf8) ? 8'hc7 :
             (sawtooth < 12'hcfb) ? 8'hc0 :
             (sawtooth < 12'hcfc) ? 8'hc7 :
             (sawtooth < 12'hcfd) ? 8'hc0 :
             (sawtooth < 12'hd00) ? 8'hcf :
             (sawtooth < 12'hd1f) ? 8'h80 :
             (sawtooth < 12'hd20) ? 8'hc0 :
             (sawtooth < 12'hd2f) ? 8'h80 :
             (sawtooth < 12'hd30) ? 8'hc0 :
             (sawtooth < 12'hd36) ? 8'h80 :
             (sawtooth < 12'hd38) ? 8'hc0 :
             (sawtooth < 12'hd39) ? 8'h80 :
             (sawtooth < 12'hd3f) ? 8'hc0 :
             (sawtooth < 12'hd40) ? 8'hc3 :
             (sawtooth < 12'hd47) ? 8'h80 :
             (sawtooth < 12'hd48) ? 8'hc0 :
             (sawtooth < 12'hd4b) ? 8'h80 :
             (sawtooth < 12'hd4c) ? 8'hc0 :
             (sawtooth < 12'hd4d) ? 8'h80 :
             (sawtooth < 12'hd50) ? 8'hc0 :
             (sawtooth < 12'hd51) ? 8'h80 :
             (sawtooth < 12'hd5f) ? 8'hc0 :
             (sawtooth < 12'hd60) ? 8'hc1 :
             (sawtooth < 12'hd7d) ? 8'hc0 :
             (sawtooth < 12'hd7e) ? 8'hc1 :
             (sawtooth < 12'hd7f) ? 8'hc7 :
             (sawtooth < 12'hd80) ? 8'hd7 :
             (sawtooth < 12'hdaf) ? 8'hc0 :
             (sawtooth < 12'hdb0) ? 8'hd0 :
             (sawtooth < 12'hdb7) ? 8'hc0 :
             (sawtooth < 12'hdb8) ? 8'hd0 :
             (sawtooth < 12'hdbb) ? 8'hc0 :
             (sawtooth < 12'hdbc) ? 8'hd0 :
             (sawtooth < 12'hdbd) ? 8'hc0 :
             (sawtooth < 12'hdbe) ? 8'hd0 :
             (sawtooth < 12'hdbf) ? 8'hd8 :
             (sawtooth < 12'hdc0) ? 8'hdb :
             (sawtooth < 12'hdcf) ? 8'hc0 :
             (sawtooth < 12'hdd0) ? 8'hd8 :
             (sawtooth < 12'hdd7) ? 8'hc0 :
             (sawtooth < 12'hdd8) ? 8'hd8 :
             (sawtooth < 12'hddb) ? 8'hc0 :
             (sawtooth < 12'hddc) ? 8'hd8 :
             (sawtooth < 12'hddd) ? 8'hd0 :
             (sawtooth < 12'hddf) ? 8'hd8 :
             (sawtooth < 12'hde0) ? 8'hdd :
             (sawtooth < 12'hde3) ? 8'hc0 :
             (sawtooth < 12'hde4) ? 8'hd0 :
             (sawtooth < 12'hde5) ? 8'hc0 :
             (sawtooth < 12'hde7) ? 8'hd0 :
             (sawtooth < 12'hde8) ? 8'hdc :
             (sawtooth < 12'hde9) ? 8'hd0 :
             (sawtooth < 12'hdeb) ? 8'hd8 :
             (sawtooth < 12'hdec) ? 8'hdc :
             (sawtooth < 12'hded) ? 8'hd8 :
             (sawtooth < 12'hdef) ? 8'hdc :
             (sawtooth < 12'hdf0) ? 8'hde :
             (sawtooth < 12'hdf1) ? 8'hd8 :
             (sawtooth < 12'hdf3) ? 8'hdc :
             (sawtooth < 12'hdf4) ? 8'hde :
             (sawtooth < 12'hdf5) ? 8'hdc :
             (sawtooth < 12'hdf7) ? 8'hde :
             (sawtooth < 12'hdf8) ? 8'hdf :
             (sawtooth < 12'hdf9) ? 8'hde :
             (sawtooth < 12'he00) ? 8'hdf :
             (sawtooth < 12'he3f) ? 8'hc0 :
             (sawtooth < 12'he40) ? 8'he3 :
             (sawtooth < 12'he57) ? 8'hc0 :
             (sawtooth < 12'he58) ? 8'he0 :
             (sawtooth < 12'he5b) ? 8'hc0 :
             (sawtooth < 12'he5c) ? 8'he0 :
             (sawtooth < 12'he5d) ? 8'hc0 :
             (sawtooth < 12'he5f) ? 8'he0 :
             (sawtooth < 12'he60) ? 8'he1 :
             (sawtooth < 12'he67) ? 8'hc0 :
             (sawtooth < 12'he68) ? 8'he0 :
             (sawtooth < 12'he6b) ? 8'hc0 :
             (sawtooth < 12'he70) ? 8'he0 :
             (sawtooth < 12'he71) ? 8'hc0 :
             (sawtooth < 12'he7d) ? 8'he0 :
             (sawtooth < 12'he7e) ? 8'he1 :
             (sawtooth < 12'he7f) ? 8'he3 :
             (sawtooth < 12'he80) ? 8'he7 :
             (sawtooth < 12'he87) ? 8'hc0 :
             (sawtooth < 12'he88) ? 8'he0 :
             (sawtooth < 12'he8b) ? 8'hc0 :
             (sawtooth < 12'he8c) ? 8'he0 :
             (sawtooth < 12'he8d) ? 8'hc0 :
             (sawtooth < 12'he90) ? 8'he0 :
             (sawtooth < 12'he93) ? 8'hc0 :
             (sawtooth < 12'he94) ? 8'he0 :
             (sawtooth < 12'he95) ? 8'hc0 :
             (sawtooth < 12'hebf) ? 8'he0 :
             (sawtooth < 12'hec0) ? 8'heb :
             (sawtooth < 12'hedb) ? 8'he0 :
             (sawtooth < 12'hedc) ? 8'he8 :
             (sawtooth < 12'hedd) ? 8'he0 :
             (sawtooth < 12'hedf) ? 8'he8 :
             (sawtooth < 12'hee0) ? 8'hed :
             (sawtooth < 12'hee7) ? 8'he0 :
             (sawtooth < 12'hee8) ? 8'hec :
             (sawtooth < 12'heeb) ? 8'he0 :
             (sawtooth < 12'heec) ? 8'hec :
             (sawtooth < 12'heed) ? 8'he8 :
             (sawtooth < 12'heef) ? 8'hec :
             (sawtooth < 12'hef0) ? 8'hee :
             (sawtooth < 12'hef3) ? 8'he8 :
             (sawtooth < 12'hef5) ? 8'hec :
             (sawtooth < 12'hef7) ? 8'hee :
             (sawtooth < 12'hef8) ? 8'hef :
             (sawtooth < 12'hef9) ? 8'hec :
             (sawtooth < 12'hf00) ? 8'hef :
             (sawtooth < 12'hf1f) ? 8'he0 :
             (sawtooth < 12'hf20) ? 8'hf0 :
             (sawtooth < 12'hf27) ? 8'he0 :
             (sawtooth < 12'hf28) ? 8'hf0 :
             (sawtooth < 12'hf2b) ? 8'he0 :
             (sawtooth < 12'hf2c) ? 8'hf0 :
             (sawtooth < 12'hf2d) ? 8'he0 :
             (sawtooth < 12'hf30) ? 8'hf0 :
             (sawtooth < 12'hf33) ? 8'he0 :
             (sawtooth < 12'hf3f) ? 8'hf0 :
             (sawtooth < 12'hf40) ? 8'hf3 :
             (sawtooth < 12'hf43) ? 8'he0 :
             (sawtooth < 12'hf5f) ? 8'hf0 :
             (sawtooth < 12'hf60) ? 8'hf5 :
             (sawtooth < 12'hf6d) ? 8'hf0 :
             (sawtooth < 12'hf6f) ? 8'hf4 :
             (sawtooth < 12'hf70) ? 8'hf6 :
             (sawtooth < 12'hf73) ? 8'hf0 :
             (sawtooth < 12'hf74) ? 8'hf4 :
             (sawtooth < 12'hf75) ? 8'hf0 :
             (sawtooth < 12'hf76) ? 8'hf4 :
             (sawtooth < 12'hf77) ? 8'hf6 :
             (sawtooth < 12'hf78) ? 8'hf7 :
             (sawtooth < 12'hf79) ? 8'hf4 :
             (sawtooth < 12'hf7b) ? 8'hf6 :
             (sawtooth < 12'hf80) ? 8'hf7 :
             (sawtooth < 12'hf87) ? 8'hf0 :
             (sawtooth < 12'hf88) ? 8'hf8 :
             (sawtooth < 12'hf8d) ? 8'hf0 :
             (sawtooth < 12'hf90) ? 8'hf8 :
             (sawtooth < 12'hf93) ? 8'hf0 :
             (sawtooth < 12'hf94) ? 8'hf8 :
             (sawtooth < 12'hf95) ? 8'hf0 :
             (sawtooth < 12'hf9f) ? 8'hf8 :
             (sawtooth < 12'hfa0) ? 8'hf9 :
             (sawtooth < 12'hfaf) ? 8'hf8 :
             (sawtooth < 12'hfb0) ? 8'hfa :
             (sawtooth < 12'hfb7) ? 8'hf8 :
             (sawtooth < 12'hfb8) ? 8'hfb :
             (sawtooth < 12'hfb9) ? 8'hf8 :
             (sawtooth < 12'hfbb) ? 8'hfa :
             (sawtooth < 12'hfc0) ? 8'hfb :
             (sawtooth < 12'hfc3) ? 8'hf8 :
             (sawtooth < 12'hfc4) ? 8'hfc :
             (sawtooth < 12'hfc5) ? 8'hf8 :
             (sawtooth < 12'hfd7) ? 8'hfc :
             (sawtooth < 12'hfd8) ? 8'hfd :
             (sawtooth < 12'hfdb) ? 8'hfc :
             (sawtooth < 12'hfe0) ? 8'hfd :
             (sawtooth < 12'hfe2) ? 8'hfc :
             (sawtooth < 12'hff0) ? 8'hfe : 8'hff;
  wave_pst = (sawtooth < 12'h3ff) ? 8'h00 :
             (sawtooth < 12'h400) ? 8'h1f :
             (sawtooth < 12'h7ee) ? 8'h00 :
             (sawtooth < 12'h7ef) ? 8'h20 :
             (sawtooth < 12'h7f0) ? 8'h70 :
             (sawtooth < 12'h7f1) ? 8'h60 :
             (sawtooth < 12'h7f2) ? 8'h20 :
             (sawtooth < 12'h7f7) ? 8'h70 :
             (sawtooth < 12'h7fa) ? 8'h78 :
             (sawtooth < 12'h7fc) ? 8'h7c :
             (sawtooth < 12'h7fe) ? 8'h7e :
             (sawtooth < 12'h800) ? 8'h7f :
             (sawtooth < 12'hbfd) ? 8'h00 :
             (sawtooth < 12'hbfe) ? 8'h08 :
             (sawtooth < 12'hbff) ? 8'h1e :
             (sawtooth < 12'hc00) ? 8'h3f :
             (sawtooth < 12'hdf7) ? 8'h00 :
             (sawtooth < 12'hdfe) ? 8'h80 :
             (sawtooth < 12'hdff) ? 8'h8c :
             (sawtooth < 12'he00) ? 8'h9f :
             (sawtooth < 12'he3e) ? 8'h00 :
             (sawtooth < 12'he40) ? 8'h80 :
             (sawtooth < 12'he5e) ? 8'h00 :
             (sawtooth < 12'he60) ? 8'h80 :
             (sawtooth < 12'he66) ? 8'h00 :
             (sawtooth < 12'he67) ? 8'h80 :
             (sawtooth < 12'he6a) ? 8'h00 :
             (sawtooth < 12'he80) ? 8'h80 :
             (sawtooth < 12'he82) ? 8'h00 :
             (sawtooth < 12'he83) ? 8'h80 :
             (sawtooth < 12'he85) ? 8'h00 :
             (sawtooth < 12'he89) ? 8'h80 :
             (sawtooth < 12'he8a) ? 8'h00 :
             (sawtooth < 12'heee) ? 8'h80 :
             (sawtooth < 12'heff) ? 8'hc0 :
             (sawtooth < 12'hf00) ? 8'hcf :
             (sawtooth < 12'hf6f) ? 8'hc0 :
             (sawtooth < 12'hf70) ? 8'he0 :
             (sawtooth < 12'hf74) ? 8'hc0 :
             (sawtooth < 12'hf7f) ? 8'he0 :
             (sawtooth < 12'hf80) ? 8'he3 :
             (sawtooth < 12'hfb6) ? 8'he0 :
             (sawtooth < 12'hfda) ? 8'hf0 :
             (sawtooth < 12'hfeb) ? 8'hf8 :
             (sawtooth < 12'hff5) ? 8'hfc :
             (sawtooth < 12'hff9) ? 8'hfe : 8'hff;
end

endmodule
