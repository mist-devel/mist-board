module mos6526 (
  input  wire       clk,
  input  wire       phi2,
  input  wire       res_n,
  input  wire       cs_n,
  input  wire       rw,

  input  wire [3:0] rs,
  input  wire [7:0] db_in,
  output reg  [7:0] db_out,

  input  wire [7:0] pa_in,
  output reg  [7:0] pa_out,
  input  wire [7:0] pb_in,
  output reg  [7:0] pb_out,

  input  wire       flag_n,
  output reg        pc_n,

  input  wire       tod,

  input  wire       sp_in,
  output reg        sp_out,

  input  wire       cnt_in,
  output reg        cnt_out,

  output reg        irq_n
);

// Internal Registers
reg [7:0] pra;
reg [7:0] prb;
reg [7:0] ddra;
reg [7:0] ddrb;

reg [7:0] ta_lo;
reg [7:0] ta_hi;
reg [7:0] tb_lo;
reg [7:0] tb_hi;

reg [3:0] tod_10ths;
reg [6:0] tod_sec;
reg [6:0] tod_min;
reg [5:0] tod_hr;

reg [7:0] sdr;
reg [4:0] icr;
reg [7:0] cra;
reg [7:0] crb;

// Internal Signals
reg        flag_n_prev;

reg [15:0] timer_a;
reg [ 1:0] timer_a_out;
reg [15:0] timer_b;
reg [ 1:0] timer_b_out;

reg        tod_prev;
reg        tod_run;
reg [ 2:0] tod_count;
reg        tod_tick;
reg [23:0] tod_alarm;
reg        tod_alarm_reg;
reg [23:0] tod_latch;
reg        tod_latched;

reg        sp_pending;
reg        sp_received;
reg        sp_transmit;
reg [ 7:0] sp_shiftreg;

reg        cnt_in_prev;
reg        cnt_out_prev;
reg [ 2:0] cnt_pulsecnt;

reg [ 4:0] int_data;
reg [ 1:0] int_reset;

// Register Decoding
always @(posedge clk) begin
  if (!res_n) db_out <= 8'h00;
  else if (!cs_n && rw)
    case (rs)
      4'h0: db_out <= pa_in;
      4'h1: db_out <= pb_in;
      4'h2: db_out <= ddra;
      4'h3: db_out <= ddrb;
      4'h4: db_out <= timer_a[ 7:0];
      4'h5: db_out <= timer_a[15:8];
      4'h6: db_out <= timer_b[ 7:0];
      4'h7: db_out <= timer_b[15:8];
      4'h8: db_out <= tod_latched ?
                      {4'h0, tod_latch[3:0]} : {4'h0, tod_10ths};
      4'h9: db_out <= tod_latched ?
                      {1'b0, tod_latch[10:4]} : {1'b0, tod_sec};
      4'ha: db_out <= tod_latched ?
                      {1'b0, tod_latch[17:11]} : {1'b0, tod_min};
      4'hb: db_out <= tod_latched ?
                      {tod_latch[23], 2'h0, tod_latch[22:18]} :
                      {tod_hr[5], 2'h0, tod_hr[4:0]};
      4'hc: db_out <= sdr;
      4'hd: db_out <= {~irq_n, 2'b00, int_data};
      4'he: db_out <= {cra[7:5], 1'b0, cra[3:0]};
      4'hf: db_out <= {crb[7:5], 1'b0, crb[3:0]};
    endcase
end

// Port A Output
always @(posedge clk) begin
  if (!res_n) begin
    pra  <= 8'h00;
    ddra <= 8'h00;
  end
  else if (!cs_n && !rw)
    case (rs)
      4'h0: pra  <= db_in;
      4'h2: ddra <= db_in;
		default: begin
        pra  <= pra;
        ddra <= ddra;
		end
    endcase
  if (phi2) pa_out <= pra | ~ddra;
end

// Port B Output
always @(posedge clk) begin
  if (!res_n) begin
    prb  <= 8'h00;
    ddrb <= 8'h00;
  end
  else if (!cs_n && !rw)
    case (rs)
      4'h1: prb  <= db_in;
      4'h3: ddrb <= db_in;
      default: begin
        prb  <= prb;
        ddrb <= ddrb;
      end
    endcase
  if (phi2) begin
    pb_out[7]   <= crb[1] ? crb[2] ? timer_b_out[1] | ~ddrb[7] :
                   timer_b_out[0] | ~ddrb[7] : prb[7] | ~ddrb[7];
    pb_out[6]   <= cra[1] ? cra[2] ? timer_a_out[1] | ~ddrb[6] :
                   timer_a_out[0] | ~ddrb[7] : prb[6] | ~ddrb[6];
    pb_out[5:0] <= prb[5:0] | ~ddrb[5:0];
  end
end

// FLAG Input
always @(posedge clk) begin
  if (!res_n || int_reset[1]) int_data[4] <= 1'b0;
  else if (!flag_n && flag_n_prev) int_data[4] <= 1'b1;
  if (phi2) flag_n_prev <= flag_n;
end

// Port Control Output
always @(posedge clk) begin
  if (!cs_n && rs == 4'h1) pc_n <= 1'b0;
  else pc_n <= phi2 ? 1'b1 : pc_n;
end

// Timer A
always @(posedge clk) begin
  if (!res_n) begin
    ta_lo          <= 8'hff;
    ta_hi          <= 8'hff;
    cra            <= 8'h00;
    timer_a        <= 16'h0000;
    timer_a_out[1] <= 1'b0;
    int_data[0]    <= 1'b0;
  end
  else if (!cs_n && !rw)
    case (rs)
      4'h4: ta_lo <= db_in;
      4'h5: ta_hi <= db_in;
      4'he: begin
        cra            <= db_in;
        timer_a_out[1] <= timer_a_out[1] | db_in[0];
      end
      default: begin
        ta_lo          <= ta_lo;
        ta_hi          <= ta_hi;
        cra            <= cra;
        timer_a_out[1] <= timer_a_out[1];
      end
    endcase
  timer_a_out[0] <= phi2 ? 1'b0 : timer_a_out[0];
  if (phi2 && cra[0] && !cra[4]) begin
    if (!cra[5]) timer_a <= timer_a - 1'b1;
    else timer_a <= (cnt_in && !cnt_in_prev) ? timer_a - 1'b1 : timer_a;
    if (!timer_a) begin
      cra[0]      <= ~cra[3];
      int_data[0] <= 1'b1;
      timer_a     <= {ta_hi, ta_lo};
      timer_a_out <= {~timer_a_out[1], 1'b1};
    end
  end
  if ((phi2 && cra[4]) || (!cra[0] && !cs_n && !rw && rs == 4'h5)) begin
    cra[4]  <= 1'b0;
    timer_a <= {ta_hi, ta_lo};
  end
  if (int_reset[1]) int_data[0] <= 1'b0;
end

// Timer B
always @(posedge clk) begin
  if (!res_n) begin
    tb_lo          <= 8'hff;
    tb_hi          <= 8'hff;
    crb            <= 8'h00;
    timer_b        <= 16'h0000;
    timer_b_out[1] <= 1'b0;
    int_data[1]    <= 1'b0;
  end
  else if (!cs_n && !rw)
    case (rs)
      4'h6: tb_lo <= db_in;
      4'h7: tb_hi <= db_in;
      4'hf: begin
        crb            <= db_in;
        timer_b_out[1] <= timer_b_out[1] | db_in[0];
      end
      default: begin
        tb_lo          <= tb_lo;
        tb_hi          <= tb_hi;
        crb            <= crb;
        timer_b_out[1] <= timer_b_out[1];
      end
    endcase
  timer_b_out[0] <= phi2 ? 1'b0 : timer_b_out[0];
  if (phi2 && crb[0] && !crb[4]) begin
    case (crb[6:5])
      2'b00: timer_b <= timer_b - 1'b1;
      2'b01: timer_b <= (cnt_in && !cnt_in_prev) ? timer_b - 1'b1 : timer_b;
      2'b10: timer_b <= timer_a_out[0] ? timer_b - 1'b1 : timer_b;
      2'b11: timer_b <= (timer_a_out[0] && cnt_in) ? timer_b - 1'b1 : timer_b;
    endcase
    if (!timer_b) begin
      crb[0]      <= ~crb[3];
      int_data[1] <= 1'b1;
		timer_b     <= {tb_hi, tb_lo};
      timer_b_out <= {~timer_b_out[1], 1'b1};
    end
  end
  if ((phi2 && crb[4]) || (!crb[0] && !cs_n && !rw && rs == 4'h7)) begin
    crb[4]  <= 1'b0;
    timer_b <= {tb_hi, tb_lo};    
  end
  if (int_reset[1]) int_data[1] <= 1'b0;
end

// Time of Day
always @(posedge clk) begin
  if (!res_n) begin
    tod_10ths   <= 4'h0;
    tod_sec     <= 7'h00;
    tod_min     <= 7'h00;
    tod_hr      <= 6'h01;
    tod_run     <= 1'b0;
    tod_alarm   <= 24'h000000;
    tod_latch   <= 24'h000000;
    tod_latched <= 1'b0;
    int_data[2] <= 1'b0;
  end
  else if (!cs_n && !rw)
    case (rs)
      4'h8: if (crb[7]) tod_alarm[3:0] <= db_in[3:0];
            else tod_10ths <= db_in[3:0];
      4'h9: if (crb[7]) tod_alarm[10:4] <= db_in[6:0];
            else tod_sec <= db_in[6:0];
      4'ha: if (crb[7]) tod_alarm[17:11] <= db_in[6:0];
            else tod_min <= db_in[6:0];
      4'hb: if (crb[7]) tod_alarm[23:18] <= {db_in[7], db_in[4:0]};
            else tod_hr <= {db_in[7], db_in[4:0]};
      default: begin
        tod_10ths <= tod_10ths;
        tod_sec   <= tod_sec;
        tod_min   <= tod_min;
        tod_hr    <= tod_hr;
        tod_alarm <= tod_alarm;
      end
    endcase
  if (!cs_n)
    if (rs == 4'h8)
      if (!rw) tod_run <= !crb[7] ? 1'b1 : tod_run;
      else begin
        tod_latched <= 1'b0;
        tod_latch   <= 24'h000000;
      end
    else if (rs == 4'hb)
      if (!rw) tod_run <= !crb[7] ? 1'b0 : tod_run;
      else begin
        tod_latched <= 1'b1;
        tod_latch   <= {tod_hr, tod_min, tod_sec, tod_10ths};
      end
  tod_prev <= tod;
  tod_tick <= 1'b0;
  if (tod_run) begin
    tod_count <= (tod && !tod_prev) ? tod_count + 1'b1 : tod_count;
    if ((cra[7] && tod_count == 3'h5) || tod_count == 3'h6) begin
      tod_tick  <= 1'b1;
      tod_count <= 3'h0;
    end
    if (tod_tick) begin
      tod_10ths <= (tod_10ths == 4'h9) ? 1'b0 : tod_10ths + 1'b1;
      if (tod_10ths == 4'h9) begin
        tod_sec[3:0] <= tod_sec[3:0] + 1'b1;
        if (tod_sec[3:0] == 4'h9) begin
          tod_sec[3:0] <= 4'h0;
          tod_sec[6:4] <= tod_sec[6:4] + 1'b1;
        end
        if (tod_sec == 7'h59) begin
          tod_sec[6:4] <= 3'h0;
          tod_min[3:0] <= tod_min[3:0] + 1'b1;
        end
        if (tod_min[3:0] == 4'h9 && tod_sec == 7'h59) begin
          tod_min[3:0] <= 4'h0;
          tod_min[6:4] <= tod_min[6:4] + 1'b1;
        end
        if (tod_min == 7'h59 && tod_sec == 7'h59) begin
          tod_min[6:4] <= 3'h0;
          tod_hr[3:0]  <= tod_hr[3:0] + 1'b1;
        end
        if (tod_hr[3:0] == 4'h9 && tod_min == 7'h59 && tod_sec == 7'h59) begin
          tod_hr[3:0] <= 4'h0;
          tod_hr[4]   <= tod_hr[4] + 1'b1;
        end
        if (tod_min == 7'h59 && tod_sec == 7'h59)
          if (tod_hr[4:0] == 5'h11)
            if (!tod_hr[5]) begin
              tod_hr[5]   <= ~tod_hr[5];
              tod_hr[3:0] <= tod_hr[3:0] + 1'b1;
            end
            else begin
              tod_hr[5]   <= ~tod_hr[5];
              tod_hr[4:0] <= 5'h00;
            end
          else if (tod_hr[4:0] == 5'h12) tod_hr[4:0] <= 5'h01;
      end
    end
  end
  else tod_count <= 3'h0;
  if ({tod_hr, tod_min, tod_sec, tod_10ths} == tod_alarm) begin
    tod_alarm_reg <= 1'b1;
    int_data[2]   <= !tod_alarm_reg ? 1'b1 : int_data[2];
  end
  else tod_alarm_reg <= 1'b0;
  if (int_reset[1]) int_data[2] <= 1'b0;
end

// Serial Port Input/Output
always @(posedge clk) begin
  if (!res_n) begin
    sdr         <= 8'h00;
    sp_out      <= 1'b0;
    sp_pending  <= 1'b0;
    sp_received <= 1'b0;
    sp_transmit <= 1'b0;
    sp_shiftreg <= 8'h00;
    int_data[3] <= 1'b0;
  end
  else if (!cs_n && !rw)
    case (rs)
      4'hc: sdr <= db_in;
      default: sdr <= sdr;
    endcase
  if (!cra[6]) begin
    if (sp_received) begin
      sdr         <= sp_shiftreg;
      int_data[3] <= 1'b1;
      sp_received <= 1'b0;
      sp_shiftreg <= 8'h00;
    end
    else if (cnt_in && !cnt_in_prev) begin
      sp_shiftreg <= {sp_shiftreg[6:0], sp_in};
      sp_received <= (cnt_pulsecnt == 3'h7) ? 1'b1 : sp_received;
    end
  end
  else if (cra[6] && !cra[3] && cra[0]) begin
    if (!cs_n && !rw && rs == 8'hc) sp_pending <= 1'b1;
    if (sp_pending && !sp_transmit) begin
      sp_pending  <= 1'b0;
      sp_transmit <= 1'b1;
      sp_shiftreg <= sdr;
    end
    else if (!cnt_out && cnt_out_prev) begin
      if (cnt_pulsecnt == 3'h7) begin
        int_data[3] <= 1'b1;
        sp_transmit <= 1'b0;
      end
      sp_out      <= sp_shiftreg[7];
      sp_shiftreg <= {sp_shiftreg[6:0], 1'b0};
    end
  end
  if (int_reset[1]) int_data[3] <= 1'b0;
end

// CNT Input/Output
always @(posedge clk) begin
  if (!res_n) begin
    cnt_out      <= 1'b1;
    cnt_out_prev <= 1'b1;
    cnt_pulsecnt <= 3'h0;
  end
  else if (phi2) begin
    cnt_in_prev  <= cnt_in;
    cnt_out_prev <= cnt_out;
  end
  if (!cra[6] && cnt_in && !cnt_in_prev) cnt_pulsecnt <= cnt_pulsecnt + 1'b1;
  else if (cra[6] && !cra[3] && cra[0]) begin
    if (sp_transmit) begin
      cnt_out <= timer_a_out[0] ? ~cnt_out : cnt_out;
      if (!cnt_out && cnt_out_prev) cnt_pulsecnt <= cnt_pulsecnt + 1'b1;
    end
    else cnt_out <= timer_a_out[0] ? 1'b1 : cnt_out;
  end
end

// Interrupt Control
always @(posedge clk) begin
  if (!res_n) begin
    icr       <= 5'h00;
    irq_n     <= 1'b1;
    int_reset <= 2'b00;
  end
  else if (!cs_n && !rw)
    case (rs)
      4'hd: icr <= db_in[7] ? icr | db_in[4:0] : icr & ~db_in[4:0];
      default: icr <= icr;
    endcase
  else irq_n <= irq_n ? ~|(icr & int_data) : int_reset[1] ? 1'b1 : irq_n;
  if (!cs_n && rw && rs == 4'hd) int_reset <= 2'b01;
  else if (int_reset) int_reset <= {int_reset[0], 1'b0};
end

endmodule
