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

module SquareChan(input MMC5,
                  input clk, input ce, input reset, input sq2,
                  input [1:0] Addr,
                  input [7:0] DIN,
                  input MW,
                  input LenCtr_Clock,
                  input Env_Clock,
                  input odd_or_even,
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
// XXX: This should be enabled for MMC5, but do we really want ultrasonic frequencies?
// Re-enable if we ever get a proper LPF.
wire ValidFreq = /*(MMC5==1) ||*/ ((|Period[10:3]) && (SweepNegate || !NewSweepPeriod[11]));
 // |Period[10:3] is equivalent to Period >= 8

//double speed for MMC5=Env_Clock
wire LenCtrClockEnable = (MMC5==0 && LenCtr_Clock) || (MMC5==1 && Env_Clock);

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
		if (MMC5==0) begin
      SweepEnable <= DIN[7];
      SweepPeriod <= DIN[6:4];
      SweepNegate <= DIN[3];
      SweepShift <= DIN[2:0];
      SweepReset <= 1;
		end
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
  // Should be clocked on every even cpu cycle
  if (~odd_or_even) begin
    if (TimerCtr == 0) begin
      // Timer was clocked
      TimerCtr <= Period;
      SeqPos <= SeqPos - 1'd1;
    end else begin
      TimerCtr <= TimerCtr - 1'd1;
    end
  end

  // Clock the length counter?
  if (LenCtrClockEnable && LenCtr != 0 && !LenCtrHalt) begin
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

wire DutyEnabledUsed = (MMC5==1) ^ DutyEnabled;  

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
  if (LenCtr == 0 || !ValidFreq || !DutyEnabledUsed)
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
                    output reg [3:0] Sample,
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
    //LinCtrl <= 0; do not reset
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
  // XXX: Ultrisonic frequencies cause issues, so are disabled.
  // This can be removed for accuracy if a proper LPF is ever implemented.
  always @(posedge clk)
    Sample <= (Period > 1) ? SeqPos[3:0] ^ {4{~SeqPos[4]}} : Sample;
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
    0: NoisePeriod = 12'd4;
    1: NoisePeriod = 12'd8;
    2: NoisePeriod = 12'd16;
    3: NoisePeriod = 12'd32;
    4: NoisePeriod = 12'd64;
    5: NoisePeriod = 12'd96;
    6: NoisePeriod = 12'd128;
    7: NoisePeriod = 12'd160;
    8: NoisePeriod = 12'd202;
    9: NoisePeriod = 12'd254;
    10: NoisePeriod = 12'd380;
    11: NoisePeriod = 12'd508;
    12: NoisePeriod = 12'd762;
    13: NoisePeriod = 12'd1016;
    14: NoisePeriod = 12'd2034;
    15: NoisePeriod = 12'd4068;
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
    LenCtr <= 1;
    ShortMode <= 0;
    Shift <= 1;
    Period <= 0;
    TimerCtr <= NoisePeriod - 1'b1;
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
      TimerCtr <= NoisePeriod - 1'b1;
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

module DmcChan(input MMC5,
               input clk, input ce, input reset,
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
               input PAL,
               output IsDmcActive);
  reg IrqEnable;
  reg IrqActive;
  reg Loop;                 // Looping enabled
  reg [3:0] Freq;           // Current value of frequency register
  reg [7:0] Dac = 0;        // Current value of DAC
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
  assign Sample = Dac[6:0];
  assign Irq = IrqActive;
  assign IsDmcActive = DmcEnabled;
  
  assign DmaReq = !HasSampleBuffer && DmcEnabled && !ActivationDelay[0];
    
  wire [8:0] NewPeriod[16] = '{
		428, 380, 340, 320,
		286, 254, 226, 214,
		190, 160, 142, 128,
		106, 84, 72, 54
  };

  wire [8:0] NewPeriodPAL[16] = '{
    398, 354, 316, 298,
    276, 236, 210, 198,
    176, 148, 132, 118,
    98,  78,  66,  50
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
      SampleLen <= 1;
      ShiftReg <= 8'h0; // XXX: should be 0 or 07? Visual 2C02 says 0, as does Mesen.
      Cycles <= 439;
      Address <= 15'h4000;
      BytesLeft <= 0;
      BitsUsed <= 0;
      SampleBuffer <= 0;
      HasSampleBuffer <= 0;
      HasShiftReg <= 0;
      DmcEnabled <= 1;
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
            Dac <= {(MMC5==1) && DIN[7],DIN[6:0]};
          end
        2: begin  // $4012   aaaa aaaa   sample address
            SampleAddress <= (MMC5==1) ? 8'h0 : DIN[7:0];
          end
        3: begin  // $4013   llll llll   sample length
            SampleLen <= (MMC5==1) ? 8'h0 : DIN[7:0];
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
        Cycles <= PAL ? NewPeriodPAL[Freq] : NewPeriod[Freq];
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

module APU(input MMC5,
           input clk, input ce, input reset,
           input PAL,
           input [4:0] ADDR,  // APU Address Line
           input [7:0] DIN,   // Data to APU
           output [7:0] DOUT, // Data from APU
           input MW,          // Writes to APU
           input MR,          // Reads from APU
           input [4:0] audio_channels, // Enabled audio channels
           output [15:0] Sample,

           output DmaReq,          // 1 when DMC wants DMA
           input DmaAck,           // 1 when DMC byte is on DmcData. DmcDmaRequested should go low.
           output [15:0] DmaAddr,  // Address DMC wants to read
           input [7:0] DmaData,    // Input data to DMC from memory.

           input  odd_or_even,
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


// Generate each channel
SquareChan	 Sq1(MMC5, clk, ce, reset, 1'b0, ADDR[1:0], DIN, ApuMW0, ClkL, ClkE, odd_or_even, Enabled[0], LenCtr_In, Sq1Sample, Sq1NonZero);
SquareChan   Sq2(MMC5, clk, ce, reset, 1'b1, ADDR[1:0], DIN, ApuMW1, ClkL, ClkE, odd_or_even, Enabled[1], LenCtr_In, Sq2Sample, Sq2NonZero);
TriangleChan Tri(clk, ce, reset, ADDR[1:0], DIN, ApuMW2, ClkL, ClkE, Enabled[2], LenCtr_In, TriSample, TriNonZero);
NoiseChan    Noi(clk, ce, reset, ADDR[1:0], DIN, ApuMW3, ClkL, ClkE, Enabled[3], LenCtr_In, NoiSample, NoiNonZero);
DmcChan      Dmc(MMC5, clk, ce, reset, odd_or_even, ADDR[2:0], DIN, ApuMW4, DmcSample, DmaReq, DmaAck, DmaAddr, DmaData, DmcIrq, PAL, IsDmcActive);

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

reg [7:0] last_4017 = 0;
reg [2:0] delayed_clear;
reg delayed_interrupt;
wire set_irq_ntsc = (Cycles == cyc_ntsc[3]) || (Cycles == cyc_ntsc[4]);
wire set_irq_pal = (Cycles == cyc_pal[3]) || (Cycles == cyc_pal[4]);
wire set_irq = ( (PAL ? set_irq_pal : set_irq_ntsc) || delayed_interrupt) && ~DisableFrameInterrupt && ~FrameSeqMode;

int cyc_pal[7] = '{8312, 16626, 24938, 33251, 33252, 41564, 41565};
int cyc_ntsc[7]  = '{7456, 14912, 22370, 29828, 29829, 37280, 37281};

always @(posedge clk) if (reset) begin
  delayed_interrupt <= 0;
  FrameInterrupt <= 0;
  Enabled <= 0;
  ClkE <= 0;
  ClkL <= 0;
  delayed_clear <= 0;
  Cycles <= 0;
  IrqCtr <= 0;
  {FrameSeqMode, DisableFrameInterrupt} <= last_4017[7:6];
end else if (ce) begin   
  FrameInterrupt <= set_irq ? 1'd1 : (ADDR == 5'h15 && MR || ApuMW5 && ADDR[1:0] == 3 && DIN[6]) ? 1'd0 : FrameInterrupt;

  IrqCtr <= {IrqCtr[0], 1'b0};

  // NesDev's wiki on this is ambiguous and written from a strange perspective. To the best
  // of my understanding, the Frame Counter works like this:
  // The APU alternates between Read cycles (even) and Write cycles, (odd). The internal counter
  // is incremented on every Write cycle, and if it hits certain special points, the clocks are
  // generated *on* the next Read cycle. The counter can only be controlled by one thing at a time,
  // so resetting the counter must always be on a Write cycle.
  //
  // In the case of writes to 4017, the internal registers are written normally as the write occurs, so
  // that their values are visible on the next CE, however a reset cannot start writing to the counter
  // until the *next* Write cycle. It's probably implemented as a flag to tell the counter to reset, that
  // is written as part of the register data, and since the counter only runs on Writes, that's when it
  // happens.

  if (delayed_clear)
    delayed_clear <= delayed_clear - 1'b1;
 
  Cycles <= Cycles + 1'd1;

  ClkE <= 0;
  ClkL <= 0;
  delayed_interrupt <= 1'b0;
  if (Cycles == (PAL ? cyc_pal[0] : cyc_ntsc[0])) begin
    ClkE <= 1;
  end else if (Cycles == (PAL ? cyc_pal[1] : cyc_ntsc[1])) begin
    ClkE <= 1;
    ClkL <= 1;
  end else if (Cycles == (PAL ? cyc_pal[2] : cyc_ntsc[2])) begin
    ClkE <= 1;
  end else if (Cycles == (PAL ? cyc_pal[3] : cyc_ntsc[3])) begin
    if (!FrameSeqMode) begin
      ClkE <= 1;
      ClkL <= 1;
    end
  end else if (Cycles == (PAL ? cyc_pal[4] : cyc_ntsc[4])) begin
    if (!FrameSeqMode) begin
      delayed_interrupt <= 1'b1;
      Cycles <= 0;
    end
  end else if (Cycles == (PAL ? cyc_pal[5] : cyc_ntsc[5])) begin
    ClkE <= 1;
    ClkL <= 1;
  end else if (Cycles == (PAL ? cyc_pal[6] : cyc_ntsc[6])) begin
    Cycles <= 0;
  end
  
  // Handle one cycle delayed write to 4017.
  if (delayed_clear == 1) begin
    if (FrameSeqMode) begin
      ClkE <= 1;
      ClkL <= 1;
    end
    Cycles <= 0;
  end
  
  // Handle writes to control registers
  if (ApuMW5) begin
    case (ADDR[1:0])
    1: begin // Register $4015
      Enabled <= DIN[3:0];
    end
    3: begin // Register $4017
      if (~MMC5) begin
        last_4017 <= DIN;
        FrameSeqMode <= DIN[7]; // 1 = 5 frames cycle, 0 = 4 frames cycle
        DisableFrameInterrupt <= DIN[6];

        if (odd_or_even)
          delayed_clear <= 3'd2;
        else
          delayed_clear <= 3'd1;
      end
    end
    endcase
  end


end

APUMixer mixer (
  .square1(Sq1Sample),
  .square2(Sq2Sample),
  .noise(NoiSample),
  .triangle(TriSample),
  .dmc(DmcSample),
  .sample(Sample)
);

wire frame_irq = FrameInterrupt && !DisableFrameInterrupt;

// Generate bus output
assign DOUT = {DmcIrq, FrameInterrupt, 1'b0,
               IsDmcActive,
               NoiNonZero,
               TriNonZero,
               Sq2NonZero,
               Sq1NonZero};

assign IRQ = frame_irq || DmcIrq;

endmodule

// http://wiki.nesdev.com/w/index.php/APU_Mixer
// I generated three LUT's for each mix channel entry and one lut for the squares, then a
// 282 entry lut for the mix channel. It's more accurate than the original LUT system listed on
// the NesDev page.

module APUMixer (
  input [3:0] square1,
  input [3:0] square2,
  input [3:0] triangle,
  input [3:0] noise,
  input [6:0] dmc,
  output [15:0] sample
);

wire [15:0] pulse_lut[32] = '{
  16'd0,     16'd763,   16'd1509,  16'd2236,  16'd2947,  16'd3641,  16'd4319,  16'd4982,
  16'd5630,  16'd6264,  16'd6883,  16'd7490,  16'd8083,  16'd8664,  16'd9232,  16'd9789,
  16'd10334, 16'd10868, 16'd11392, 16'd11905, 16'd12408, 16'd12901, 16'd13384, 16'd13858,
  16'd14324, 16'd14780, 16'd15228, 16'd15668, 16'd16099, 16'd16523, 16'd16939, 16'd17348
};

wire [5:0] tri_lut[16] = '{
  6'd0,  6'd3,  6'd7,  6'd11, 6'd15, 6'd19, 6'd23, 6'd27,
  6'd31, 6'd35, 6'd39, 6'd43, 6'd47, 6'd51, 6'd55, 6'd59
};

wire [5:0] noise_lut[16] = '{
  6'd0,  6'd2,  6'd5,  6'd8,  6'd10, 6'd13, 6'd16, 6'd18,
  6'd21, 6'd24, 6'd26, 6'd29, 6'd32, 6'd34, 6'd37, 6'd40
};

wire [7:0] dmc_lut[128] = '{
  8'd0,   8'd1,   8'd2,   8'd4,   8'd5,   8'd7,   8'd8,   8'd10,  8'd11,  8'd13,  8'd14,  8'd15,  8'd17,  8'd18,  8'd20,  8'd21,
  8'd23,  8'd24,  8'd26,  8'd27,  8'd28,  8'd30,  8'd31,  8'd33,  8'd34,  8'd36,  8'd37,  8'd39,  8'd40,  8'd41,  8'd43,  8'd44,
  8'd46,  8'd47,  8'd49,  8'd50,  8'd52,  8'd53,  8'd55,  8'd56,  8'd57,  8'd59,  8'd60,  8'd62,  8'd63,  8'd65,  8'd66,  8'd68,
  8'd69,  8'd70,  8'd72,  8'd73,  8'd75,  8'd76,  8'd78,  8'd79,  8'd81,  8'd82,  8'd83,  8'd85,  8'd86,  8'd88,  8'd89,  8'd91,
  8'd92,  8'd94,  8'd95,  8'd96,  8'd98,  8'd99,  8'd101, 8'd102, 8'd104, 8'd105, 8'd107, 8'd108, 8'd110, 8'd111, 8'd112, 8'd114,
  8'd115, 8'd117, 8'd118, 8'd120, 8'd121, 8'd123, 8'd124, 8'd125, 8'd127, 8'd128, 8'd130, 8'd131, 8'd133, 8'd134, 8'd136, 8'd137,
  8'd138, 8'd140, 8'd141, 8'd143, 8'd144, 8'd146, 8'd147, 8'd149, 8'd150, 8'd151, 8'd153, 8'd154, 8'd156, 8'd157, 8'd159, 8'd160,
  8'd162, 8'd163, 8'd165, 8'd166, 8'd167, 8'd169, 8'd170, 8'd172, 8'd173, 8'd175, 8'd176, 8'd178, 8'd179, 8'd180, 8'd182, 8'd183
};

wire [15:0] mix_lut[512] = '{
  16'd0,     16'd318,   16'd635,   16'd950,   16'd1262,  16'd1573,  16'd1882,  16'd2190,  16'd2495,  16'd2799,  16'd3101,  16'd3401,  16'd3699,  16'd3995,  16'd4290,  16'd4583,
  16'd4875,  16'd5164,  16'd5452,  16'd5739,  16'd6023,  16'd6306,  16'd6588,  16'd6868,  16'd7146,  16'd7423,  16'd7698,  16'd7971,  16'd8243,  16'd8514,  16'd8783,  16'd9050,
  16'd9316,  16'd9581,  16'd9844,  16'd10105, 16'd10365, 16'd10624, 16'd10881, 16'd11137, 16'd11392, 16'd11645, 16'd11897, 16'd12147, 16'd12396, 16'd12644, 16'd12890, 16'd13135,
  16'd13379, 16'd13622, 16'd13863, 16'd14103, 16'd14341, 16'd14579, 16'd14815, 16'd15050, 16'd15284, 16'd15516, 16'd15747, 16'd15978, 16'd16206, 16'd16434, 16'd16661, 16'd16886,
  16'd17110, 16'd17333, 16'd17555, 16'd17776, 16'd17996, 16'd18215, 16'd18432, 16'd18649, 16'd18864, 16'd19078, 16'd19291, 16'd19504, 16'd19715, 16'd19925, 16'd20134, 16'd20342,
  16'd20549, 16'd20755, 16'd20960, 16'd21163, 16'd21366, 16'd21568, 16'd21769, 16'd21969, 16'd22169, 16'd22367, 16'd22564, 16'd22760, 16'd22955, 16'd23150, 16'd23343, 16'd23536,
  16'd23727, 16'd23918, 16'd24108, 16'd24297, 16'd24485, 16'd24672, 16'd24858, 16'd25044, 16'd25228, 16'd25412, 16'd25595, 16'd25777, 16'd25958, 16'd26138, 16'd26318, 16'd26497,
  16'd26674, 16'd26852, 16'd27028, 16'd27203, 16'd27378, 16'd27552, 16'd27725, 16'd27898, 16'd28069, 16'd28240, 16'd28410, 16'd28579, 16'd28748, 16'd28916, 16'd29083, 16'd29249,
  16'd29415, 16'd29580, 16'd29744, 16'd29907, 16'd30070, 16'd30232, 16'd30393, 16'd30554, 16'd30714, 16'd30873, 16'd31032, 16'd31190, 16'd31347, 16'd31503, 16'd31659, 16'd31815,
  16'd31969, 16'd32123, 16'd32276, 16'd32429, 16'd32581, 16'd32732, 16'd32883, 16'd33033, 16'd33182, 16'd33331, 16'd33479, 16'd33627, 16'd33774, 16'd33920, 16'd34066, 16'd34211,
  16'd34356, 16'd34500, 16'd34643, 16'd34786, 16'd34928, 16'd35070, 16'd35211, 16'd35352, 16'd35492, 16'd35631, 16'd35770, 16'd35908, 16'd36046, 16'd36183, 16'd36319, 16'd36456,
  16'd36591, 16'd36726, 16'd36860, 16'd36994, 16'd37128, 16'd37261, 16'd37393, 16'd37525, 16'd37656, 16'd37787, 16'd37917, 16'd38047, 16'd38176, 16'd38305, 16'd38433, 16'd38561,
  16'd38689, 16'd38815, 16'd38942, 16'd39068, 16'd39193, 16'd39318, 16'd39442, 16'd39566, 16'd39690, 16'd39813, 16'd39935, 16'd40057, 16'd40179, 16'd40300, 16'd40421, 16'd40541,
  16'd40661, 16'd40780, 16'd40899, 16'd41017, 16'd41136, 16'd41253, 16'd41370, 16'd41487, 16'd41603, 16'd41719, 16'd41835, 16'd41950, 16'd42064, 16'd42178, 16'd42292, 16'd42406,
  16'd42519, 16'd42631, 16'd42743, 16'd42855, 16'd42966, 16'd43077, 16'd43188, 16'd43298, 16'd43408, 16'd43517, 16'd43626, 16'd43735, 16'd43843, 16'd43951, 16'd44058, 16'd44165,
  16'd44272, 16'd44378, 16'd44484, 16'd44589, 16'd44695, 16'd44799, 16'd44904, 16'd45008, 16'd45112, 16'd45215, 16'd45318, 16'd45421, 16'd45523, 16'd45625, 16'd45726, 16'd45828,
  16'd45929, 16'd46029, 16'd46129, 16'd46229, 16'd46329, 16'd46428, 16'd46527, 16'd46625, 16'd46723, 16'd46821, 16'd46919, 16'd47016, 16'd47113, 16'd47209, 16'd47306, 16'd47402,
  16'd47497, 16'd47592, 16'd47687, 16'd47782, 16'd47876, 16'd47970, 16'd48064, 16'd48157, 16'd48250, 16'd48343, 16'd48436, 16'd0,     16'd0,     16'd0,     16'd0,     16'd0,
  16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,
  16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,
  16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,
  16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,
  16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,
  16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,
  16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,
  16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,
  16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,
  16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,
  16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,
  16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,
  16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,
  16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0,     16'd0
};

wire [4:0] squares = square1 + square2;
wire [8:0] mix = tri_lut[triangle] + noise_lut[noise] + dmc_lut[dmc];
wire [15:0] ch1 = pulse_lut[squares];
wire [15:0] ch2 = mix_lut[mix];
wire [63:0] chan_mix = ch1 + ch2;

assign sample = chan_mix > 16'hFFFF ? 16'hFFFF : chan_mix[15:0];

endmodule
