// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.
 
module LenCtr_Lookup(input [4:0] X, output [7:0] Yout);
reg [6:0] Y;
always @*
begin
  case(X)
  0: Y = 7'h05;
  1: Y = 7'h7F;
  2: Y = 7'h0A;
  3: Y = 7'h01;
  4: Y = 7'h14;
  5: Y = 7'h02;
  6: Y = 7'h28;
  7: Y = 7'h03;
  8: Y = 7'h50;
  9: Y = 7'h04;
  10: Y = 7'h1E;
  11: Y = 7'h05;
  12: Y = 7'h07;
  13: Y = 7'h06;
  14: Y = 7'h0D;
  15: Y = 7'h07;
  16: Y = 7'h06;
  17: Y = 7'h08;
  18: Y = 7'h0C;
  19: Y = 7'h09;
  20: Y = 7'h18;
  21: Y = 7'h0A;
  22: Y = 7'h30;
  23: Y = 7'h0B;
  24: Y = 7'h60;
  25: Y = 7'h0C;
  26: Y = 7'h24;
  27: Y = 7'h0D;
  28: Y = 7'h08;
  29: Y = 7'h0E;
  30: Y = 7'h10;
  31: Y = 7'h0F;
  endcase
end
assign Yout = {Y, 1'b0};
endmodule

module SquareChan(input clk, input ce, input reset, input sq2,
                  input [1:0] Addr,
                  input [7:0] DIN,
                  input MW,
                  input LenCtr_Clock,
                  input Env_Clock,
                  input Enabled,
                  input [7:0] LenCtr_In,
                  output reg [3:0] Sample,
                  output IsNonZero);
reg [7:0] LenCtr;

// Register 1
reg [1:0] Duty;
reg EnvLoop, EnvDisable, EnvDoReset;
reg [3:0] Volume, Envelope, EnvDivider;
wire LenCtrHalt = EnvLoop; // Aliased bit
assign IsNonZero = (LenCtr != 0);
// Register 2
reg SweepEnable, SweepNegate, SweepReset;
reg [2:0] SweepPeriod, SweepDivider, SweepShift;

reg [10:0] Period;
reg [11:0] TimerCtr;
reg [2:0] SeqPos;
wire [10:0] ShiftedPeriod = (Period >> SweepShift);
wire [10:0] PeriodRhs = (SweepNegate ? (~ShiftedPeriod + {10'b0, sq2}) : ShiftedPeriod);
wire [11:0] NewSweepPeriod = Period + PeriodRhs;
wire ValidFreq = (|Period[10:3]) && (SweepNegate || !NewSweepPeriod[11]);

always @(posedge clk) if (reset) begin
    LenCtr <= 0;
    Duty <= 0;
    EnvDoReset <= 0;
    EnvLoop <= 0;
    EnvDisable <= 0;
    Volume <= 0;
    Envelope <= 0;
    EnvDivider <= 0;
    SweepEnable <= 0;
    SweepNegate <= 0;
    SweepReset <= 0;
    SweepPeriod <= 0;
    SweepDivider <= 0;
    SweepShift <= 0;    
    Period <= 0;
    TimerCtr <= 0;
    SeqPos <= 0;
  end else if (ce) begin
  // Check if writing to the regs of this channel
  // NOTE: This needs to be done before the clocking below.
  if (MW) begin
    case(Addr)
    0: begin
//      if (sq2) $write("SQ0: Duty=%d, EnvLoop=%d, EnvDisable=%d, Volume=%d\n", DIN[7:6], DIN[5], DIN[4], DIN[3:0]);
      Duty <= DIN[7:6];
      EnvLoop <= DIN[5];
      EnvDisable <= DIN[4];
      Volume <= DIN[3:0];
    end
    1: begin
//      if (sq2) $write("SQ1: SweepEnable=%d, SweepPeriod=%d, SweepNegate=%d, SweepShift=%d, DIN=%X\n", DIN[7], DIN[6:4], DIN[3], DIN[2:0], DIN);
      SweepEnable <= DIN[7];
      SweepPeriod <= DIN[6:4];
      SweepNegate <= DIN[3];
      SweepShift <= DIN[2:0];
      SweepReset <= 1;
    end
    2: begin
//      if (sq2) $write("SQ2: Period=%d. DIN=%X\n", DIN, DIN);
      Period[7:0] <= DIN;
    end
    3: begin
      // Upper bits of the period
//      if (sq2) $write("SQ3: PeriodUpper=%d LenCtr=%x DIN=%X\n", DIN[2:0], LenCtr_In, DIN);
      Period[10:8] <= DIN[2:0];
      LenCtr <= LenCtr_In;
      EnvDoReset <= 1;
      SeqPos <= 0;
    end
    endcase
  end

  
  // Count down the square timer...
  if (TimerCtr == 0) begin
    // Timer was clocked
    TimerCtr <= {Period, 1'b0};
    SeqPos <= SeqPos - 1'd1;
  end else begin
    TimerCtr <= TimerCtr - 1'd1;
  end

  // Clock the length counter?
  if (LenCtr_Clock && LenCtr != 0 && !LenCtrHalt) begin
    LenCtr <= LenCtr - 1'd1;
  end
  
  // Clock the sweep unit?
  if (LenCtr_Clock) begin
    if (SweepDivider == 0) begin
      SweepDivider <= SweepPeriod;
      if (SweepEnable && SweepShift != 0 && ValidFreq)
        Period <= NewSweepPeriod[10:0];
    end else begin
      SweepDivider <= SweepDivider - 1'd1;
    end
    if (SweepReset)
      SweepDivider <= SweepPeriod;
    SweepReset <= 0;
  end
  
  // Clock the envelope generator?
  if (Env_Clock) begin
    if (EnvDoReset) begin
      EnvDivider <= Volume;
      Envelope <= 15;
      EnvDoReset <= 0;
    end else if (EnvDivider == 0) begin
      EnvDivider <= Volume;
      if (Envelope != 0 || EnvLoop)
        Envelope <= Envelope - 1'd1;
    end else begin
      EnvDivider <= EnvDivider - 1'd1;
    end
  end
 
  // Length counter forced to zero if disabled.
  if (!Enabled)
    LenCtr <= 0;
end

reg DutyEnabled;  
always @* begin
  // Determine if the duty is enabled or not
  case (Duty)
  0: DutyEnabled = (SeqPos == 7);
  1: DutyEnabled = (SeqPos >= 6);
  2: DutyEnabled = (SeqPos >= 4);
  3: DutyEnabled = (SeqPos < 6);
  endcase

  // Compute the output
  if (LenCtr == 0 || !ValidFreq || !DutyEnabled)
    Sample = 0;
  else
    Sample = EnvDisable ? Volume : Envelope;
end
endmodule



module TriangleChan(input clk, input ce, input reset,
                    input [1:0] Addr,
                    input [7:0] DIN,
                    input MW,
                    input LenCtr_Clock,
                    input LinCtr_Clock,
                    input Enabled,
                    input [7:0] LenCtr_In,
                    output [3:0] Sample,
                    output IsNonZero);
  //
  reg [10:0] Period, TimerCtr;
  reg [4:0] SeqPos;
  //
  // Linear counter state
  reg [6:0] LinCtrPeriod, LinCtr;
  reg LinCtrl, LinHalt;
  wire LinCtrZero = (LinCtr == 0);
  //
  // Length counter state
  reg [7:0] LenCtr;
  wire LenCtrHalt = LinCtrl; // Aliased bit
  wire LenCtrZero = (LenCtr == 0);
  assign IsNonZero = !LenCtrZero;
  //
  always @(posedge clk) if (reset) begin
    Period <= 0;
    TimerCtr <= 0;
    SeqPos <= 0;
    LinCtrPeriod <= 0;
    LinCtr <= 0;
    LinCtrl <= 0;
    LinHalt <= 0;
    LenCtr <= 0;
  end else if (ce) begin
    // Check if writing to the regs of this channel 
    if (MW) begin
      case (Addr)
      0: begin
        LinCtrl <= DIN[7];
        LinCtrPeriod <= DIN[6:0];
      end
      2: begin
        Period[7:0] <= DIN;
      end
      3: begin
        Period[10:8] <= DIN[2:0];
        LenCtr <= LenCtr_In;
        LinHalt <= 1;
      end
      endcase
    end

    // Count down the period timer...
    if (TimerCtr == 0) begin
      TimerCtr <= Period;
    end else begin
      TimerCtr <= TimerCtr - 1'd1;
    end
    //
    // Clock the length counter?
    if (LenCtr_Clock && !LenCtrZero && !LenCtrHalt) begin
      LenCtr <= LenCtr - 1'd1;
    end
    //
    // Clock the linear counter?
    if (LinCtr_Clock) begin
      if (LinHalt)
        LinCtr <= LinCtrPeriod;
      else if (!LinCtrZero)
        LinCtr <= LinCtr - 1'd1;
      if (!LinCtrl)
        LinHalt <= 0;
    end
    //
    // Length counter forced to zero if disabled.
    if (!Enabled)
      LenCtr <= 0;
      //
    // Clock the sequencer position
    if (TimerCtr == 0 && !LenCtrZero && !LinCtrZero)
      SeqPos <= SeqPos + 1'd1;
  end
  // Generate the output
  assign Sample = SeqPos[3:0] ^ {4{~SeqPos[4]}};
  //
endmodule


module NoiseChan(input clk, input ce, input reset,
                 input [1:0] Addr,
                 input [7:0] DIN,
                 input MW,
                 input LenCtr_Clock,
                 input Env_Clock,
                 input Enabled,
                 input [7:0] LenCtr_In,
                 output [3:0] Sample,
                 output IsNonZero);
  //
  // Envelope volume
  reg EnvLoop, EnvDisable, EnvDoReset;
  reg [3:0] Volume, Envelope, EnvDivider;
  // Length counter
  wire LenCtrHalt = EnvLoop; // Aliased bit
  reg [7:0] LenCtr;
  //
  reg ShortMode;
  reg [14:0] Shift = 1;
  
  assign IsNonZero = (LenCtr != 0);
  //
  // Period stuff
  reg [3:0] Period;
  reg [11:0] NoisePeriod, TimerCtr;
  always @* begin
    case (Period)
    0: NoisePeriod = 12'h004;
    1: NoisePeriod = 12'h008;
    2: NoisePeriod = 12'h010;
    3: NoisePeriod = 12'h020;
    4: NoisePeriod = 12'h040;
    5: NoisePeriod = 12'h060;
    6: NoisePeriod = 12'h080;
    7: NoisePeriod = 12'h0A0;
    8: NoisePeriod = 12'h0CA;
    9: NoisePeriod = 12'h0FE;
    10: NoisePeriod = 12'h17C;
    11: NoisePeriod = 12'h1FC;
    12: NoisePeriod = 12'h2FA;
    13: NoisePeriod = 12'h3F8;
    14: NoisePeriod = 12'h7F2;
    15: NoisePeriod = 12'hFE4;  
    endcase
  end
  //
  always @(posedge clk) if (reset) begin
    EnvLoop <= 0;
    EnvDisable <= 0;
    EnvDoReset <= 0;
    Volume <= 0;
    Envelope <= 0;
    EnvDivider <= 0;
    LenCtr <= 0;
    ShortMode <= 0;
    Shift <= 1;
    Period <= 0;
    TimerCtr <= 0;
  end else if (ce) begin
    // Check if writing to the regs of this channel 
    if (MW) begin
      case (Addr)
      0: begin
        EnvLoop <= DIN[5];
        EnvDisable <= DIN[4];
        Volume <= DIN[3:0];
      end
      2: begin
        ShortMode <= DIN[7];
        Period <= DIN[3:0];
      end
      3: begin
        LenCtr <= LenCtr_In;
        EnvDoReset <= 1;
      end
      endcase
    end
    // Count down the period timer...
    if (TimerCtr == 0) begin
      TimerCtr <= NoisePeriod;
      // Clock the shift register. Use either 
      // bit 1 or 6 as the tap.
      Shift <= { 
        Shift[0] ^ (ShortMode ? Shift[6] : Shift[1]), 
        Shift[14:1]}; 
    end else begin
      TimerCtr <= TimerCtr - 1'd1;
    end
    // Clock the length counter?
    if (LenCtr_Clock && LenCtr != 0 && !LenCtrHalt) begin
      LenCtr <= LenCtr - 1'd1;
    end
    // Clock the envelope generator?
    if (Env_Clock) begin
      if (EnvDoReset) begin
        EnvDivider <= Volume;
        Envelope <= 15;
        EnvDoReset <= 0;
      end else if (EnvDivider == 0) begin
        EnvDivider <= Volume;
        if (Envelope != 0)
          Envelope <= Envelope - 1'd1;
        else if (EnvLoop)
          Envelope <= 15;
      end else
        EnvDivider <= EnvDivider - 1'd1;
    end
    if (!Enabled)
      LenCtr <= 0;
  end
  // Produce the output signal
  assign Sample = 
    (LenCtr == 0 || Shift[0]) ?
      4'd0 : 
      (EnvDisable ? Volume : Envelope);
endmodule

module DmcChan(input clk, input ce, input reset,
               input odd_or_even,
               input [2:0] Addr,
               input [7:0] DIN,
               input MW,
               output [6:0] Sample,
               output DmaReq,          // 1 when DMC wants DMA
               input DmaAck,           // 1 when DMC byte is on DmcData. DmcDmaRequested should go low.
               output [15:0] DmaAddr,  // Address DMC wants to read
               input [7:0] DmaData,    // Input data to DMC from memory.
               output Irq,
               output IsDmcActive);
  reg IrqEnable;
  reg IrqActive;
  reg Loop;                 // Looping enabled
  reg [3:0] Freq;           // Current value of frequency register
  reg [6:0] Dac = 0;        // Current value of DAC
  reg [7:0] SampleAddress;  // Base address of sample
  reg [7:0] SampleLen;      // Length of sample
  reg [7:0] ShiftReg;       // Shift register
  reg [8:0] Cycles;         // Down counter, is the period
  reg [14:0] Address;        // 15 bits current address, 0x8000-0xffff
  reg [11:0] BytesLeft;      // 12 bits bytes left counter 0 - 4081.
  reg [2:0] BitsUsed;        // Number of bits left in the SampleBuffer.
  reg [7:0] SampleBuffer;    // Next value to be loaded into shift reg
  reg HasSampleBuffer;       // Sample buffer is nonempty
  reg HasShiftReg;           // Shift reg is non empty
  reg DmcEnabled;
  reg [1:0] ActivationDelay;
  assign DmaAddr = {1'b1, Address};
  assign Sample = Dac;
  assign Irq = IrqActive;
  assign IsDmcActive = DmcEnabled;
  
  assign DmaReq = !HasSampleBuffer && DmcEnabled && !ActivationDelay[0];
    
  wire [8:0] NewPeriod[16] = '{
		428, 380, 340, 320,
		286, 254, 226, 214,
		190, 160, 142, 128,
		106, 84, 72, 54
  };

  // Shift register initially loaded with 07
  always @(posedge clk) begin
    if (reset) begin
      IrqEnable <= 0;
      IrqActive <= 0;
      Loop <= 0;
      Freq <= 0;
      Dac <= 0;
      SampleAddress <= 0;
      SampleLen <= 0;
      ShiftReg <= 8'hff;
      Cycles <= 439;
      Address <= 0;
      BytesLeft <= 0;
      BitsUsed <= 0;
      SampleBuffer <= 0;
      HasSampleBuffer <= 0;
      HasShiftReg <= 0;
      DmcEnabled <= 0;
      ActivationDelay <= 0;
    end else if (ce) begin
      if (ActivationDelay == 3 && !odd_or_even) ActivationDelay <= 1;
      if (ActivationDelay == 1) ActivationDelay <= 0;
      
      if (MW) begin
        case (Addr)
        0: begin  // $4010   il-- ffff   IRQ enable, loop, frequency index
            IrqEnable <= DIN[7];
            Loop <= DIN[6];
            Freq <= DIN[3:0];
            if (!DIN[7]) IrqActive <= 0;
          end
        1: begin  // $4011   -ddd dddd   DAC
            // This will get missed if the Dac <= far below runs, that is by design.
            Dac <= DIN[6:0];
          end
        2: begin  // $4012   aaaa aaaa   sample address
            SampleAddress <= DIN[7:0];
          end
        3: begin  // $4013   llll llll   sample length
            SampleLen <= DIN[7:0];
          end
        5: begin // $4015 write	---D NT21  Enable DMC (D)
            IrqActive <= 0;
            DmcEnabled <= DIN[4];
            // If the DMC bit is set, the DMC sample will be restarted only if not already active.
            if (DIN[4] && !DmcEnabled) begin
              Address <= {1'b1, SampleAddress, 6'b000000};
              BytesLeft <= {SampleLen, 4'b0000};
              ActivationDelay <= 3;
            end
          end
        endcase
      end

      Cycles <= Cycles - 1'd1;
      if (Cycles == 1) begin
        Cycles <= NewPeriod[Freq];
        if (HasShiftReg) begin
          if (ShiftReg[0]) begin
            Dac[6:1] <= (Dac[6:1] != 6'b111111) ? Dac[6:1] + 6'b000001 : Dac[6:1];
          end else begin
            Dac[6:1] <= (Dac[6:1] != 6'b000000) ? Dac[6:1] + 6'b111111 : Dac[6:1];
          end
        end
        ShiftReg <= {1'b0, ShiftReg[7:1]};
        BitsUsed <= BitsUsed + 1'd1;
        if (BitsUsed == 7) begin
          HasShiftReg <= HasSampleBuffer;
          ShiftReg <= SampleBuffer;
          HasSampleBuffer <= 0;
        end
      end
      
      // Acknowledge DMA?
      if (DmaAck) begin
        Address <= Address + 1'd1;
        BytesLeft <= BytesLeft - 1'd1;
        HasSampleBuffer <= 1;
        SampleBuffer <= DmaData;
        if (BytesLeft == 0) begin
          Address <= {1'b1, SampleAddress, 6'b000000};
          BytesLeft <= {SampleLen, 4'b0000};
          DmcEnabled <= Loop;
          if (!Loop && IrqEnable)
            IrqActive <= 1;
        end
      end      
    end
  end
endmodule

module ApuLookupTable
(
	input clk,
	input [7:0] in_a,
	input [7:0] in_b,
	output reg [15:0] out
);

wire [15:0] lookup_a[256] = '{
       0,   760,  1503,  2228,  2936,  3627,  4303,  4963,  5609,  6240,  6858,  7462,  8053,  8631,  9198,  9752,
   10296, 10828, 11349, 11860, 12361, 12852, 13334, 13807, 14270, 14725, 15171, 15609, 16039, 16461, 16876,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0
};

wire [15:0] lookup_b[256] = '{
       0,   439,   874,  1306,  1735,  2160,  2581,  2999,  3414,  3826,  4234,  4639,  5041,  5440,  5836,  6229,
    6618,  7005,  7389,  7769,  8147,  8522,  8895,  9264,  9631,  9995, 10356, 10714, 11070, 11423, 11774, 12122,
   12468, 12811, 13152, 13490, 13825, 14159, 14490, 14818, 15145, 15469, 15791, 16110, 16427, 16742, 17055, 17366,
   17675, 17981, 18286, 18588, 18888, 19187, 19483, 19777, 20069, 20360, 20648, 20935, 21219, 21502, 21783, 22062,
   22339, 22615, 22889, 23160, 23431, 23699, 23966, 24231, 24494, 24756, 25016, 25274, 25531, 25786, 26040, 26292,
   26542, 26791, 27039, 27284, 27529, 27772, 28013, 28253, 28492, 28729, 28964, 29198, 29431, 29663, 29893, 30121,
   30349, 30575, 30800, 31023, 31245, 31466, 31685, 31904, 32121, 32336, 32551, 32764, 32976, 33187, 33397, 33605,
   33813, 34019, 34224, 34428, 34630, 34832, 35032, 35232, 35430, 35627, 35823, 36018, 36212, 36405, 36597, 36788,
   36978, 37166, 37354, 37541, 37727, 37912, 38095, 38278, 38460, 38641, 38821, 39000, 39178, 39355, 39532, 39707,
   39881, 40055, 40228, 40399, 40570, 40740, 40909, 41078, 41245, 41412, 41577, 41742, 41906, 42070, 42232, 42394,
   42555, 42715, 42874, 43032, 43190, 43347, 43503, 43659, 43813, 43967, 44120, 44273, 44424, 44575, 44726, 44875,
   45024, 45172, 45319, 45466, 45612, 45757, 45902, 46046, 46189, 46332, 46474, 46615, 46756, 46895, 47035, 47173,
   47312, 47449, 47586, 47722, 47857, 47992, 48127, 48260, 48393, 48526, 48658,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0
};

always @(posedge clk) begin
	out <= lookup_a[in_a] + lookup_b[in_b];
end

endmodule


module APU(input clk, input ce, input reset,
           input [4:0] ADDR,  // APU Address Line
           input [7:0] DIN,   // Data to APU
           output [7:0] DOUT, // Data from APU
           input MW,          // Writes to APU
           input MR,          // Reads from APU
           input [4:0] audio_channels, // Enabled audio channels
           output [15:0] Sample,

           output DmaReq,      // 1 when DMC wants DMA
           input DmaAck,           // 1 when DMC byte is on DmcData. DmcDmaRequested should go low.
           output [15:0] DmaAddr,  // Address DMC wants to read
           input [7:0] DmaData,    // Input data to DMC from memory.

           output odd_or_even,
           output IRQ);       // IRQ asserted

// Which channels are enabled?
reg [3:0] Enabled;

// Output samples from the 4 channels
wire [3:0] Sq1Sample,Sq2Sample,TriSample,NoiSample;

// Output samples from the DMC channel
wire [6:0] DmcSample;
wire DmcIrq;
wire IsDmcActive;

// Generate internal memory write signals
wire ApuMW0 = MW && ADDR[4:2]==0; // SQ1
wire ApuMW1 = MW && ADDR[4:2]==1; // SQ2
wire ApuMW2 = MW && ADDR[4:2]==2; // TRI
wire ApuMW3 = MW && ADDR[4:2]==3; // NOI
wire ApuMW4 = MW && ADDR[4:2]>=4; // DMC
wire ApuMW5 = MW && ADDR[4:2]==5; // Control registers

wire Sq1NonZero, Sq2NonZero, TriNonZero, NoiNonZero;

// Common input to all channels
wire [7:0] LenCtr_In;
LenCtr_Lookup len(DIN[7:3], LenCtr_In);


// Frame sequencer registers
reg FrameSeqMode;
reg [15:0] Cycles;
reg ClkE, ClkL;
reg Wrote4017;
reg [1:0] IrqCtr;
reg InternalClock; // APU Differentiates between Even or Odd clocks
assign odd_or_even = InternalClock;


// Generate each channel
SquareChan   Sq1(clk, ce, reset, 0, ADDR[1:0], DIN, ApuMW0, ClkL, ClkE, Enabled[0], LenCtr_In, Sq1Sample, Sq1NonZero);
SquareChan   Sq2(clk, ce, reset, 1, ADDR[1:0], DIN, ApuMW1, ClkL, ClkE, Enabled[1], LenCtr_In, Sq2Sample, Sq2NonZero);
TriangleChan Tri(clk, ce, reset, ADDR[1:0], DIN, ApuMW2, ClkL, ClkE, Enabled[2], LenCtr_In, TriSample, TriNonZero);
NoiseChan    Noi(clk, ce, reset, ADDR[1:0], DIN, ApuMW3, ClkL, ClkE, Enabled[3], LenCtr_In, NoiSample, NoiNonZero);
DmcChan      Dmc(clk, ce, reset, odd_or_even, ADDR[2:0], DIN, ApuMW4, DmcSample, DmaReq, DmaAck, DmaAddr, DmaData, DmcIrq, IsDmcActive);

// Reading this register clears the frame interrupt flag (but not the DMC interrupt flag).
// If an interrupt flag was set at the same moment of the read, it will read back as 1 but it will not be cleared.
reg FrameInterrupt, DisableFrameInterrupt;


//mode 0: 4-step  effective rate (approx)
//---------------------------------------
//    - - - f      60 Hz
//    - l - l     120 Hz
//    e e e e     240 Hz


//mode 1: 5-step  effective rate (approx)
//---------------------------------------
//    - - - - -   (interrupt flag never set)
//    l - l - -    96 Hz
//    e e e e -   192 Hz

   
always @(posedge clk) if (reset) begin
  FrameSeqMode <= 0;
  DisableFrameInterrupt <= 0;
  FrameInterrupt <= 0;
  Enabled <= 0;
  InternalClock <= 0;
  Wrote4017 <= 0;
  ClkE <= 0;
  ClkL <= 0;
  Cycles <= 4; // This needs to be 5 for proper power up behavior
  IrqCtr <= 0;
end else if (ce) begin   
  FrameInterrupt <= IrqCtr[1] ? 1'd1 : (ADDR == 5'h15 && MR || ApuMW5 && ADDR[1:0] == 3 && DIN[6]) ? 1'd0 : FrameInterrupt;
  InternalClock <= !InternalClock;
  IrqCtr <= {IrqCtr[0], 1'b0};
  Cycles <= Cycles + 1;
  ClkE <= 0;
  ClkL <= 0;
  if (Cycles == 7457) begin
    ClkE <= 1;
  end else if (Cycles == 14913) begin
    ClkE <= 1;
    ClkL <= 1;
  end else if (Cycles == 22371) begin
    ClkE <= 1;
  end else if (Cycles == 29829) begin
    if (!FrameSeqMode) begin
      ClkE <= 1;
      ClkL <= 1;
      Cycles <= 0;
      IrqCtr <= 3;
      FrameInterrupt <= 1;
    end
  end else if (Cycles == 37281) begin
    ClkE <= 1;
    ClkL <= 1;
    Cycles <= 0;
  end
  
  // Handle one cycle delayed write to 4017.
  Wrote4017 <= 0;
  if (Wrote4017) begin
    if (FrameSeqMode) begin
      ClkE <= 1;
      ClkL <= 1;
    end
    Cycles <= 0;
  end
  
//  if (ClkE||ClkL) $write("%d: Clocking %s%s\n", Cycles, ClkE?"E":" ", ClkL?"L":" ");

  // Handle writes to control registers
  if (ApuMW5) begin
    case (ADDR[1:0])
    1: begin // Register $4015
      Enabled <= DIN[3:0];
//      $write("$4015 = %X\n", DIN);
    end
    3: begin // Register $4017
      FrameSeqMode <= DIN[7]; // 1 = 5 frames cycle, 0 = 4 frames cycle
      DisableFrameInterrupt <= DIN[6];
     
      // If the internal clock is even, things happen
      // right away.
      if (!InternalClock) begin
        if (DIN[7]) begin
          ClkE <= 1;
          ClkL <= 1;
        end
        Cycles <= 0;
      end
      
      // Otherwise they get delayed one clock
      Wrote4017 <= InternalClock;
    end
    endcase
  end


end

ApuLookupTable lookup(clk, 
                      (audio_channels[0] ? {4'b0, Sq1Sample} : 8'b0) + 
                      (audio_channels[1] ? {4'b0, Sq2Sample} : 8'b0), 
                      (audio_channels[2] ? {4'b0, TriSample} + {3'b0, TriSample, 1'b0} : 8'b0) + 
                      (audio_channels[3] ? {3'b0, NoiSample, 1'b0} : 8'b0) +
                      (audio_channels[4] ? {1'b0, DmcSample} : 8'b0),
                      Sample);

wire frame_irq = FrameInterrupt && !DisableFrameInterrupt;

// Generate bus output
assign DOUT = {DmcIrq, frame_irq, 1'b0, 
               IsDmcActive,
               NoiNonZero,
               TriNonZero,
               Sq2NonZero,
               Sq1NonZero};

assign IRQ = frame_irq || DmcIrq;

endmodule
