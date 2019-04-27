// MOS6526
// by Rayne
// Timers & Interrupts are rewritten by slingshot
// Passes all Lorenz CIA Timer tests
// Passes all CIA tests from VICE, except dd0dtest

module mos6526 (
  input  wire       mode,   // 0 - 6526 "old", 1 - 8521 "new"
  input  wire       clk,
  input  wire       phi2_p, // Phi 2 positive edge
  input  wire       phi2_n, // Phi 2 negative edge
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
reg [4:0] imr;
reg [4:0] icr;
reg timer_b_int; // for Timer B bug
reg [7:0] cra;
reg [7:0] crb;

// Internal Signals
reg        flag_n_prev;

reg [15:0] timer_a;
reg [15:0] timer_b;

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

reg        int_reset;

wire       rd = phi2_n & !cs_n & rw;
wire       wr = phi2_n & !cs_n & !rw;

// Register Decoding
always @(posedge clk) begin
  if (!res_n) db_out <= 8'h00;
  else if (rd)
    case (rs)
      4'h0: db_out <= pa_in;
      4'h1: db_out <= pb_in;
      4'h2: db_out <= ddra;
      4'h3: db_out <= ddrb;
      4'h4: db_out <= timer_a[ 7:0];
      4'h5: db_out <= timer_a[15:8];
      4'h6: db_out <= timer_b[ 7:0];
      4'h7: db_out <= timer_b[15:8];
      4'h8: db_out <= {4'h0, tod_latch[3:0]};
      4'h9: db_out <= {1'b0, tod_latch[10:4]};
      4'ha: db_out <= {1'b0, tod_latch[17:11]};
      4'hb: db_out <= {tod_latch[23], 2'h0, tod_latch[22:18]};
      4'hc: db_out <= sdr;
      4'hd: db_out <= {~irq_n, 2'b00, icr};
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
  else if (wr)
    case (rs)
      4'h0: pra  <= db_in;
      4'h2: ddra <= db_in;
      default: ;
    endcase
  if (phi2_p) pa_out <= pra | ~ddra;
end

// Port B Output
always @(posedge clk) begin
  if (!res_n) begin
    prb  <= 8'h00;
    ddrb <= 8'h00;
  end
  else if (wr)
    case (rs)
      4'h1: prb  <= db_in;
      4'h3: ddrb <= db_in;
      default: ;
    endcase
  if (phi2_p) begin
    pb_out[7]   <= crb[1] ? (crb[2] ? timerBff ^ timerBoverflow : timerBoverflow) : prb[7] | ~ddrb[7];
    pb_out[6]   <= cra[1] ? (cra[2] ? timerAff ^ timerAoverflow : timerAoverflow) : prb[6] | ~ddrb[6];
    pb_out[5:0] <= prb[5:0] | ~ddrb[5:0];
  end
end

// FLAG Input
always @(posedge clk) begin
  if (!res_n) icr[4] <= 1'b0;
  else begin
    if (phi2_p) begin
      if (int_reset) icr[4] <= 1'b0;
      flag_n_prev <= flag_n;
      if (!flag_n && flag_n_prev) icr[4] <= 1'b1;
    end
  end
end

// Port Control Output
always @(posedge clk) begin
  if (!cs_n && rs == 4'h1) pc_n <= 1'b0;
  else pc_n <= phi2_p ? 1'b1 : pc_n;
end

// Timer A
reg countA0, countA1, countA2, countA3, loadA1, oneShotA0;
reg timerAff;
wire timerAin = cra[5] ? countA1 : 1'b1;
wire [15:0] newTimerAVal = countA3 ? (timer_a - 1'b1) : timer_a;
wire timerAoverflow = !newTimerAVal & countA2;

always @(posedge clk) begin

  if (!res_n) begin
    ta_lo          <= 8'hff;
    ta_hi          <= 8'hff;
    cra            <= 8'h00;
    timer_a        <= 16'h0000;
    timerAff       <= 1'b0;
    icr[0]         <= 1'b0;
  end
  else begin
    if (phi2_p) begin
      if (int_reset) icr[0] <= 0;
      countA0 <= cnt_in && ~cnt_in_prev;
      countA1 <= countA0;
      countA2 <= timerAin & cra[0];
      countA3 <= countA2;
      loadA1 <= cra[4];
      cra[4] <= 0;
      oneShotA0 <= cra[3];
      timer_a <= newTimerAVal;
      if (timerAoverflow) begin
        timerAff <= ~timerAff;
        icr[0] <= 1;
        timer_a <= {ta_hi, ta_lo};
        countA3 <= 0;
        if (cra[3] | oneShotA0) begin
            cra[0] <= 0;
            countA2 <= 0;
        end
      end

      if (loadA1) begin
        timer_a <= {ta_hi, ta_lo};
        countA3 <= 0;
      end
    end

    if (wr)
      case (rs)
        4'h4:
        begin
            ta_lo <= db_in;
            if (timerAoverflow) timer_a <= {ta_hi, db_in};
        end
        4'h5:
        begin
            ta_hi <= db_in;
            if (~cra[0]) begin
                timer_a <= {db_in, ta_lo};
                countA3 <= 0;
            end
        end
        4'he:
        begin
            cra   <= db_in;
            timerAff <= timerAff | (db_in[0] & ~cra[0]);
        end
        default: ;
      endcase;
  end
end

// Timer B
reg countB0, countB1, countB2, countB3, loadB1, oneShotB0;
reg timerBff;
wire timerBin = crb[6] ? timerAoverflow & (~crb[5] | cnt_in) : (~crb[5] | countB1);
wire [15:0] newTimerBVal = countB3 ? (timer_b - 1'b1) : timer_b;
wire timerBoverflow = !newTimerBVal & countB2;

always @(posedge clk) begin

  if (!res_n) begin
    tb_lo          <= 8'hff;
    tb_hi          <= 8'hff;
    crb            <= 8'h00;
    timer_b        <= 16'h0000;
    timerBff       <= 1'b0;
    icr[1]         <= 1'b0;
    timer_b_int    <= 0;
  end
  else begin
    if (phi2_p) begin
      if (int_reset) begin
        icr[1] <= 0;
        timer_b_int <= 0;
      end
      countB0 <= cnt_in && ~cnt_in_prev;
      countB1 <= countB0;
      countB2 <= timerBin & crb[0];
      countB3 <= countB2;
      loadB1 <= crb[4];
      crb[4] <= 0;
      oneShotB0 <= crb[3];
      timer_b <= newTimerBVal;
      if (timerBoverflow) begin
        timerBff <= ~timerBff;
        icr[1] <= 1;
        timer_b_int <= 1;
        timer_b <= {tb_hi, tb_lo};
        countB3 <= 0;
        if (crb[3] | oneShotB0) begin
            crb[0] <= 0;
            countB2 <= 0;
        end
      end
      // Timer B bug - INT fired, but ICR not set
      if (!mode & int_reset) icr[1] <= 0;

      if (loadB1) begin
        timer_b <= {tb_hi, tb_lo};
        countB3 <= 0;
      end
    end

    if (wr)
      case (rs)
        4'h6:
        begin
            tb_lo <= db_in;
            if (timerBoverflow) timer_b <= {tb_hi, db_in};
        end
        4'h7:
        begin
            tb_hi <= db_in;
            if (~crb[0]) begin
                timer_b <= {db_in, tb_lo};
                countB3 <= 0;
            end
        end
        4'hf:
        begin
            crb   <= db_in;
            timerBff <= timerBff | (db_in[0] & ~crb[0]);
        end
        default: ;
      endcase;
  end
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
    icr[2] <= 1'b0;
  end
  else if (rd)
    case (rs)
      4'h8: tod_latched <= 1'b0;
      4'hb: tod_latched <= 1'b1;
      default: ;
    endcase
  else if (wr)
    case (rs)
      4'h8: if (crb[7]) tod_alarm[3:0] <= db_in[3:0];
            else begin
              tod_run   <= 1'b1;
              tod_10ths <= db_in[3:0];
            end
      4'h9: if (crb[7]) tod_alarm[10:4] <= db_in[6:0];
            else tod_sec <= db_in[6:0];
      4'ha: if (crb[7]) tod_alarm[17:11] <= db_in[6:0];
            else tod_min <= db_in[6:0];
      4'hb: if (crb[7]) tod_alarm[23:18] <= {db_in[7], db_in[4:0]};
            else begin
              tod_run <= 1'b0;
              if (db_in[4:0] == 5'h12) tod_hr <= {~db_in[7], db_in[4:0]};
              else tod_hr <= {db_in[7], db_in[4:0]};
            end
      default: ;
    endcase
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
          tod_hr[4]   <= 1'b1;
          tod_hr[3:0] <= tod_hr[4] ? tod_hr[3:0] + 1'b1 : 4'h0;
        end
        if (tod_min == 7'h59 && tod_sec == 7'h59)
          if (tod_hr[4:0] == 5'h11) tod_hr[5] <= ~tod_hr[5];
          else if (tod_hr[4:0] == 5'h12) tod_hr[4:0] <= 5'h01;
      end
    end
  end
  else tod_count <= 3'h0;

  if (phi2_p) begin
    if (!tod_latched) tod_latch <= {tod_hr, tod_min, tod_sec, tod_10ths};
    if ({tod_hr, tod_min, tod_sec, tod_10ths} == tod_alarm) begin
      tod_alarm_reg <= 1'b1;
      icr[2]   <= !tod_alarm_reg ? 1'b1 : icr[2];
    end
    else tod_alarm_reg <= 1'b0;
    if (int_reset) icr[2] <= 1'b0;
  end
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
    icr[3]      <= 1'b0;
  end
  else begin
    if (wr)
      case (rs)
        4'hc:
          begin
            sdr <= db_in;
            sp_pending <= 1;
          end
      endcase

    if (phi2_p) begin
      if (int_reset) icr[3] <= 1'b0;

      if (!cra[6]) begin // input
        if (sp_received) begin
          sdr         <= sp_shiftreg;
          icr[3]      <= 1'b1;
          sp_received <= 1'b0;
          sp_shiftreg <= 8'h00;
        end
        else if (cnt_in && !cnt_in_prev) begin
          sp_shiftreg <= {sp_shiftreg[6:0], sp_in};
          sp_received <= (cnt_pulsecnt == 3'h7) ? 1'b1 : sp_received;
        end
      end
      else if (cra[6]) begin // output
        if (sp_pending && !sp_transmit) begin
          sp_pending  <= 1'b0;
          sp_transmit <= 1'b1;
          sp_shiftreg <= sdr;
        end
        else if (!cnt_out && cnt_out_prev) begin
          if (cnt_pulsecnt == 3'h7) begin
            icr[3]      <= 1'b1;
            sp_transmit <= 1'b0;
          end
          sp_out      <= sp_shiftreg[7];
          sp_shiftreg <= {sp_shiftreg[6:0], 1'b0};
        end
      end
    end
  end
end

// CNT Input/Output
always @(posedge clk) begin
  if (!res_n) begin
    cnt_out      <= 1'b1;
    cnt_out_prev <= 1'b1;
    cnt_pulsecnt <= 3'h0;
  end
  else if (phi2_p) begin
    cnt_in_prev  <= cnt_in;
    cnt_out_prev <= cnt_out;

    if (!cra[6] && cnt_in && !cnt_in_prev) cnt_pulsecnt <= cnt_pulsecnt + 1'b1;
    else if (cra[6]) begin
      if (sp_transmit) begin
        cnt_out <= timerAoverflow ? ~cnt_out : cnt_out;
        if (!cnt_out && cnt_out_prev) cnt_pulsecnt <= cnt_pulsecnt + 1'b1;
      end
      else cnt_out <= timerAoverflow ? 1'b1 : cnt_out;
    end
  end
end

wire [4:0] icr_adj = {icr[4:2], timer_b_int, icr[0]};

// Interrupt Control
always @(posedge clk) begin
  reg [7:0] imr_reg;

  if (!res_n) begin
    imr       <= 5'h00;
    imr_reg   <= 0;
    irq_n     <= 1'b1;
    int_reset <= 0;
  end
  else begin
    if (wr && rs == 4'hd) imr_reg <= db_in;
    if (rd && rs == 4'hd) int_reset <= 1;

    if (phi2_p | mode) begin
      imr <= imr_reg[7] ? imr | imr_reg[4:0] : imr & ~imr_reg[4:0];
      irq_n <= irq_n ? ~|(imr & icr_adj) : irq_n;
    end
    if (phi2_p & int_reset) begin
      irq_n <= 1;
	  int_reset <= 0;
    end
  end
end

endmodule
