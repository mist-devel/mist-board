module sid_filters (clk, rst, Fc_lo, Fc_hi, Res_Filt, Mode_Vol,
                    voice1, voice2, voice3, input_valid, ext_in, sound, extfilter_en);

// Input Signals
input wire [ 0:0] clk;
input wire [ 0:0] rst;
input wire [ 7:0] Fc_lo;
input wire [ 7:0] Fc_hi;
input wire [ 7:0] Res_Filt;
input wire [ 7:0] Mode_Vol;
input wire [11:0] voice1;
input wire [11:0] voice2;
input wire [11:0] voice3;
input wire [ 0:0] input_valid;
input wire [11:0] ext_in;
input wire [ 0:0] extfilter_en;

// Output Signals
output reg [15:0] sound;

// Internal Signals
reg signed [17:0] mula;
reg signed [17:0] mulb;
reg [35:0] mulr;
reg [ 0:0] mulen;

wire [35:0] mul1;
wire [35:0] mul2;
wire [35:0] mul3;
wire [35:0] mul4;

wire [10:0] divmul [0:15];

reg signed [17:0] Vhp;
reg signed [17:0] Vbp;
reg [17:0] dVbp;
reg [17:0] Vlp;
reg [17:0] dVlp;
reg [17:0] Vi;
reg [17:0] Vnf;
reg [17:0] Vf;
reg signed [17:0] w0;
reg signed [17:0] q;
reg  [ 3:0] state;

assign divmul[4'h0] = 11'd1448;
assign divmul[4'h1] = 11'd1328;
assign divmul[4'h2] = 11'd1218;
assign divmul[4'h3] = 11'd1117;
assign divmul[4'h4] = 11'd1024;
assign divmul[4'h5] = 11'd939;
assign divmul[4'h6] = 11'd861;
assign divmul[4'h7] = 11'd790;
assign divmul[4'h8] = 11'd724;
assign divmul[4'h9] = 11'd664;
assign divmul[4'ha] = 11'd609;
assign divmul[4'hb] = 11'd558;
assign divmul[4'hc] = 11'd512;
assign divmul[4'hd] = 11'd470;
assign divmul[4'he] = 11'd431;
assign divmul[4'hf] = 11'd395;

// Multiplier
always @(posedge clk)
begin
  if (mulen)
    mulr <= mula * mulb;
end

assign mul1 = w0 * Vhp;
assign mul2 = w0 * Vbp;
assign mul3 = q * Vbp;
assign mul4 = 18'd82355 * ({Fc_hi, Fc_lo[2:0]} + 1'b1);

// Filter
always @(posedge clk)
begin
  if (rst)
    begin
      state <= 4'h0;
      Vlp   <= 18'h00000;
      Vbp   <= 18'h00000;
      Vhp   <= 18'h00000;
    end
  else
    begin
      mula  <= 18'h00000;
      mulb  <= 18'h00000;
      mulen <= 1'b0;
      case (state)
        4'h0:
          begin
            if (input_valid)
              begin
                state <= 4'h1;
                Vi <= 18'h00000;
                Vnf <= 18'h00000;
              end
          end
        4'h1:
          begin
            state <= 4'h2;
            w0 <= {mul4[35], mul4[28:12]};
				if (Res_Filt[0])
              Vi <= Vi + (voice1 << 2);
            else
              Vnf <= Vnf + (voice1 << 2);
          end
        4'h2:
          begin
            state <= 4'h3;
            if (Res_Filt[1])
              Vi <= Vi + (voice2 << 2);
            else
              Vnf <= Vnf + (voice2 << 2);
          end
        4'h3:
          begin
            state <= 4'h4;
            if (Res_Filt[2])
              Vi <= Vi + (voice3 << 2);
            else
              if (!Mode_Vol[7])
                  Vnf <= Vnf + (voice3 << 2);
            dVbp <= {mul1[35], mul1[35:19]};            
          end
        4'h4:
          begin
            state <= 4'h5;
            if (Res_Filt[3])
              Vi <= Vi + (ext_in << 2);
            else
              Vnf <= Vnf + (ext_in << 2);
            dVlp <= {mul2[35], mul2[35:19]};
            Vbp <= Vbp - dVbp;
            q <= divmul[Res_Filt[7:4]];
          end
        4'h5:
          begin
            state <= 4'h6;
            Vlp <= Vlp - dVlp;
            Vf <= (Mode_Vol[5]) ? Vbp : 18'h00000;
          end
        4'h6:
          begin
            state <= 4'h7;
            Vhp <= {mul3[35], mul3[26:10]} - Vlp;
            Vf <= (Mode_Vol[4]) ? Vf + Vlp : Vf;
          end
        4'h7:
          begin
            state <= 4'h8;
            Vhp <= Vhp - Vi;
          end
        4'h8:
          begin
            state <= 4'h9;
            Vf <= (Mode_Vol[6]) ? Vf + Vhp : Vf;
          end
        4'h9:
          begin
            state <= 4'ha;
            //Vf <= {~Vf + 1'b1} + Vnf;
				Vf <= (extfilter_en) ? {~Vf + 1'b1} + Vnf : Vi + Vnf;
          end
        4'ha:
          begin
            state <= 4'hb;
            mulen <= 1'b1;
            mula <= Vf;
            mulb <= Mode_Vol[3:0];
          end
        4'hb:
          begin
            state <= 4'h0;
            sound <= (mulr[21] != mulr[20]) ? sound : mulr[20:5];
          end
        default:
          ;
      endcase
    end
end

endmodule
