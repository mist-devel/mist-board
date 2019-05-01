module sid8580 (clk_1MHz, clk32, reset, cs, we, addr, data_in, data_out,
                pot_x, pot_y, audio_data, extfilter_en);

// Input Ports
input wire [0:0] clk_1MHz;
input wire [0:0] clk32;
input wire [0:0] reset;
input wire [0:0] cs;
input wire [0:0] we;
input wire [4:0] addr;
input wire [7:0] data_in;
input wire [7:0] pot_x;
input wire [7:0] pot_y;
input wire [0:0] extfilter_en;

// Output Ports
output wire [ 7:0] data_out;
output wire [15:0] audio_data;

// Internal Signals
reg  [7:0] Voice_1_Freq_lo;
reg  [7:0] Voice_1_Freq_hi;
reg  [7:0] Voice_1_Pw_lo;
reg  [3:0] Voice_1_Pw_hi;
reg  [7:0] Voice_1_Control;
reg  [7:0] Voice_1_Att_dec;
reg  [7:0] Voice_1_Sus_Rel;

reg  [7:0] Voice_2_Freq_lo;
reg  [7:0] Voice_2_Freq_hi;
reg  [7:0] Voice_2_Pw_lo;
reg  [3:0] Voice_2_Pw_hi;
reg  [7:0] Voice_2_Control;
reg  [7:0] Voice_2_Att_dec;
reg  [7:0] Voice_2_Sus_Rel;

reg  [7:0] Voice_3_Freq_lo;
reg  [7:0] Voice_3_Freq_hi;
reg  [7:0] Voice_3_Pw_lo;
reg  [3:0] Voice_3_Pw_hi;
reg  [7:0] Voice_3_Control;
reg  [7:0] Voice_3_Att_dec;
reg  [7:0] Voice_3_Sus_Rel;

reg  [7:0] Filter_Fc_lo;
reg  [7:0] Filter_Fc_hi;
reg  [7:0] Filter_Res_Filt;
reg  [7:0] Filter_Mode_Vol;

wire [7:0] Misc_Osc3_Random;
wire [7:0] Misc_Env3;

reg  [7:0] Ext_hi;
reg  [3:0] Ext_lo;

reg  [7:0] do_buf;
reg  [7:0] sidrandom;

wire [11:0] voice_1;
wire [11:0] voice_2;
wire [11:0] voice_3;
wire [17:0] voice_mixed;
reg  [17:0] voice_volume;

wire [ 0:0] voice_1_PA_MSB;
wire [ 0:0] voice_2_PA_MSB;
wire [ 0:0] voice_3_PA_MSB;

wire [18:0] filtered_audio;
reg  [ 0:0] tick_q1;
reg  [ 0:0] tick_q2;
reg  [ 0:0] input_valid;
wire [17:0] unsigned_audio;
wire [18:0] unsigned_filt;
reg  [ 0:0] ff1;

localparam DC_offset = 14'b00111111111111;

// Voice 1 Instantiation
sid_voice v1 (.clock(clk_1MHz), .reset(reset),
             .freq_lo(Voice_1_Freq_lo), .freq_hi(Voice_1_Freq_hi),
             .pw_lo(Voice_1_Pw_lo), .pw_hi(Voice_1_Pw_hi),
             .control(Voice_1_Control),
             .att_dec(Voice_1_Att_dec), .sus_rel(Voice_1_Sus_Rel),
             .osc_msb_in(voice_3_PA_MSB), .osc_msb_out(voice_1_PA_MSB),
             .signal_out(voice_1));

// Voice 2 Instantiation
sid_voice v2 (.clock(clk_1MHz), .reset(reset),
             .freq_lo(Voice_2_Freq_lo), .freq_hi(Voice_2_Freq_hi),
             .pw_lo(Voice_2_Pw_lo), .pw_hi(Voice_2_Pw_hi),
             .control(Voice_2_Control),
             .att_dec(Voice_2_Att_dec), .sus_rel(Voice_2_Sus_Rel),
             .osc_msb_in(voice_1_PA_MSB), .osc_msb_out(voice_2_PA_MSB),
             .signal_out(voice_2));

// Voice 3 Instantiation
sid_voice v3 (.clock(clk_1MHz), .reset(reset),
             .freq_lo(Voice_3_Freq_lo), .freq_hi(Voice_3_Freq_hi),
             .pw_lo(Voice_3_Pw_lo), .pw_hi(Voice_3_Pw_hi),
             .control(Voice_3_Control),
             .att_dec(Voice_3_Att_dec), .sus_rel(Voice_3_Sus_Rel),
             .osc_msb_in(voice_2_PA_MSB), .osc_msb_out(voice_3_PA_MSB),
             .signal_out(voice_3), .osc_out(Misc_Osc3_Random),
             .env_out(Misc_Env3));

// Filter Instantiation
sid_filters filters (.clk(clk32), .rst(reset),
                    .Fc_lo(Filter_Fc_lo), .Fc_hi(Filter_Fc_hi),
                    .Res_Filt(Filter_Res_Filt), .Mode_Vol(Filter_Mode_Vol),
                    .voice1(voice_1), .voice2(voice_2),
                    .voice3(voice_3), .input_valid(input_valid),
                    .ext_in(12'hfff), .sound(audio_data),
						  .extfilter_en(extfilter_en));

assign data_out = do_buf;
//assign audio_data = {1'b0, (filtered_audio[18:5] + 14'b1000000000000000)};
//assign unsigned_filt  = filtered_audio + 19'b1000000000000000000;
//assign unsigned_audio = unsigned_filt[18:1];
//assign audio_data     = filtered_audio[18:3];// + 15'h4000;//{1'b0, unsigned_audio[17:1]};

// Toggle Flip Flop
always @(posedge clk_1MHz)
begin
  if (reset)
    ff1 <= 1'b0;
  else
    ff1 <= ~ff1;
end

always @(posedge clk32)
begin
  input_valid <= (tick_q1 != tick_q2) ? 1'b1 : 1'b0;
  tick_q1 <= ff1;
  tick_q2 <= tick_q1;
end

reg [7:0] last_wr;

// Register Decoding
always @(posedge clk32)
begin
  if (reset)
    begin
      Voice_1_Freq_lo <= 8'h00;
      Voice_1_Freq_hi <= 8'h00;
      Voice_1_Pw_lo   <= 8'h00;
      Voice_1_Pw_hi   <= 4'h0;
      Voice_1_Control <= 8'h00;
      Voice_1_Att_dec <= 8'h00;
      Voice_1_Sus_Rel <= 8'h00;
      Voice_2_Freq_lo <= 8'h00;
      Voice_2_Freq_hi <= 8'h00;
      Voice_2_Pw_lo   <= 8'h00;
      Voice_2_Pw_hi   <= 4'h0;
      Voice_2_Control <= 8'h00;
      Voice_2_Att_dec <= 8'h00;
      Voice_2_Sus_Rel <= 8'h00;
      Voice_3_Freq_lo <= 8'h00;
      Voice_3_Freq_hi <= 8'h00;
      Voice_3_Pw_lo   <= 8'h00;
      Voice_3_Pw_hi   <= 4'h0;
      Voice_3_Control <= 8'h00;
      Voice_3_Att_dec <= 8'h00;
      Voice_3_Sus_Rel <= 8'h00;
      Filter_Fc_lo    <= 8'h00;
      Filter_Fc_hi    <= 8'h00;
      Filter_Res_Filt <= 8'h00;
      Filter_Mode_Vol <= 8'h00;
      Ext_hi          <= 8'h00;
      Ext_lo          <= 4'h0;
    end
  else
    begin
      Voice_1_Freq_lo <= Voice_1_Freq_lo;
      Voice_1_Freq_hi <= Voice_1_Freq_hi;
      Voice_1_Pw_lo   <= Voice_1_Pw_lo;
      Voice_1_Pw_hi   <= Voice_1_Pw_hi;
      Voice_1_Control <= Voice_1_Control;
      Voice_1_Att_dec <= Voice_1_Att_dec;
      Voice_1_Sus_Rel <= Voice_1_Sus_Rel;
      Voice_2_Freq_lo <= Voice_2_Freq_lo;
      Voice_2_Freq_hi <= Voice_2_Freq_hi;
      Voice_2_Pw_lo   <= Voice_2_Pw_lo;
      Voice_2_Pw_hi   <= Voice_2_Pw_hi;
      Voice_2_Control <= Voice_2_Control;
      Voice_2_Att_dec <= Voice_2_Att_dec;
      Voice_2_Sus_Rel <= Voice_2_Sus_Rel;
      Voice_3_Freq_lo <= Voice_3_Freq_lo;
      Voice_3_Freq_hi <= Voice_3_Freq_hi;
      Voice_3_Pw_lo   <= Voice_3_Pw_lo;
      Voice_3_Pw_hi   <= Voice_3_Pw_hi;
      Voice_3_Control <= Voice_3_Control;
      Voice_3_Att_dec <= Voice_3_Att_dec;
      Voice_3_Sus_Rel <= Voice_3_Sus_Rel;
      Filter_Fc_lo    <= Filter_Fc_lo;
      Filter_Fc_hi    <= Filter_Fc_hi;
      Filter_Res_Filt <= Filter_Res_Filt;
      Filter_Mode_Vol <= Filter_Mode_Vol;
      Ext_hi          <= Ext_hi;
      Ext_lo          <= Ext_lo;
      do_buf          <= 8'h00;
    end
  if (cs)
    begin
      if (we)
		  begin
		  last_wr <= data_in;
          case (addr)
            5'h00: Voice_1_Freq_lo <= data_in;
            5'h01: Voice_1_Freq_hi <= data_in;
            5'h02: Voice_1_Pw_lo   <= data_in;
            5'h03: Voice_1_Pw_hi   <= data_in[3:0];
            5'h04: Voice_1_Control <= data_in;
            5'h05: Voice_1_Att_dec <= data_in;
            5'h06: Voice_1_Sus_Rel <= data_in;
            5'h07: Voice_2_Freq_lo <= data_in;
            5'h08: Voice_2_Freq_hi <= data_in;
            5'h09: Voice_2_Pw_lo   <= data_in;
            5'h0a: Voice_2_Pw_hi   <= data_in[3:0];
            5'h0b: Voice_2_Control <= data_in;
            5'h0c: Voice_2_Att_dec <= data_in;
            5'h0d: Voice_2_Sus_Rel <= data_in;
            5'h0e: Voice_3_Freq_lo <= data_in;
            5'h0f: Voice_3_Freq_hi <= data_in;
            5'h10: Voice_3_Pw_lo   <= data_in;
            5'h11: Voice_3_Pw_hi   <= data_in[3:0];
            5'h12: Voice_3_Control <= data_in;
            5'h13: Voice_3_Att_dec <= data_in;
            5'h14: Voice_3_Sus_Rel <= data_in;
            5'h15: Filter_Fc_lo    <= data_in;
            5'h16: Filter_Fc_hi    <= data_in;
            5'h17: Filter_Res_Filt <= data_in;
            5'h18: Filter_Mode_Vol <= data_in;
            5'h19: Ext_lo          <= data_in[3:0];
            5'h1a: Ext_hi          <= data_in;
            default:;
          endcase
        end
      else
        begin
          case (addr)
            5'h19: do_buf <= pot_x;
            5'h1a: do_buf <= pot_y;
            5'h1b: do_buf <= Misc_Osc3_Random;
            5'h1c: do_buf <= Misc_Env3;
            default: do_buf <= last_wr;
          endcase
        end
    end
end

endmodule
