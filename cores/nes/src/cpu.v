// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

//`include "MicroCode.v"

module MyAddSub(input [7:0] A,B,
                input CI,ADD,
                output [7:0] S,
                output CO,OFL);
  wire C0,C1,C2,C3,C4,C5,C6;
  wire C6O;
  wire [7:0] I = A ^ B ^ {8{~ADD}};
  MUXCY_L MUXCY_L0 (.LO(C0),.CI(CI),.DI(A[0]),.S(I[0]) );
  MUXCY_L MUXCY_L1 (.LO(C1),.CI(C0),.DI(A[1]),.S(I[1]) );
  MUXCY_L MUXCY_L2 (.LO(C2),.CI(C1),.DI(A[2]),.S(I[2]) );
  MUXCY_L MUXCY_L3 (.LO(C3),.CI(C2),.DI(A[3]),.S(I[3]) );
  MUXCY_L MUXCY_L4 (.LO(C4),.CI(C3),.DI(A[4]),.S(I[4]) );
  MUXCY_L MUXCY_L5 (.LO(C5),.CI(C4),.DI(A[5]),.S(I[5]) );
  MUXCY_D MUXCY_D6 (.LO(C6),.O(C6O),.CI(C5),.DI(A[6]),.S(I[6]) );
  MUXCY   MUXCY_7  (.O(CO),.CI(C6),.DI(A[7]),.S(I[7]) );
  XORCY XORCY0 (.O(S[0]),.CI(CI),.LI(I[0]));
  XORCY XORCY1 (.O(S[1]),.CI(C0),.LI(I[1]));
  XORCY XORCY2 (.O(S[2]),.CI(C1),.LI(I[2]));
  XORCY XORCY3 (.O(S[3]),.CI(C2),.LI(I[3]));
  XORCY XORCY4 (.O(S[4]),.CI(C3),.LI(I[4]));
  XORCY XORCY5 (.O(S[5]),.CI(C4),.LI(I[5]));
  XORCY XORCY6 (.O(S[6]),.CI(C5),.LI(I[6]));
  XORCY XORCY7 (.O(S[7]),.CI(C6),.LI(I[7]));
  XOR2 X1(.O(OFL),.I0(C6O),.I1(CO));
endmodule

module NewAlu(input  [10:0] OP, // ALU Operation
           input  [7:0] A,   // Registers input
           input  [7:0] X,   //       ""
           input  [7:0] Y,   //       ""
           input  [7:0] S,   //       ""
           input  [7:0] M,  // Secondary input to ALU
           input  [7:0] T,  // Secondary input to ALU
                             // -- Flags Input
           input        CI,  // Carry In
           input        VI,  // Overflow In
                             // -- Flags output
           output reg   CO,  // Carry out
           output reg   VO,  // Overflow out
           output reg   SO,  // Sign out
           output reg   ZO,  // zero out
                             // -- Result output
           output reg [7:0] Result,// Result out
           output reg [7:0] IntR); // Intermediate result out
  // Crack the ALU Operation
  wire [1:0] o_left_input, o_right_input;
  wire [2:0] o_first_op, o_second_op;
  wire o_fc;
  assign {o_left_input, o_right_input, o_first_op, o_second_op, o_fc} = OP;
  
  // Determine left, right inputs to Add/Sub ALU.
  reg [7:0] L, R;
  reg CR;
  always begin
    casez(o_left_input)
    0: L = A;
    1: L = Y;
    2: L = X;
    3: L = A & X;
    endcase
    casez(o_right_input)
    0: R = M;
    1: R = T;
    2: R = L;
    3: R = S;
    endcase
    CR = CI;
    casez(o_first_op[2:1])
    0: {CR, IntR} = {R, CI & o_first_op[0]};  // SHL, ROL
    1: {IntR, CR} = {CI & o_first_op[0], R};  // SHR, ROR
    2: IntR = R;                              // Passthrough
    3: IntR = R + (o_first_op[0] ? 8'b1 : 8'b11111111); // INC/DEC
    endcase
  end
  wire [7:0] AddR;
  wire AddCO, AddVO;
  MyAddSub addsub(.A(L),.B(IntR),.CI(o_second_op[0] ? CR : 1'b1),.ADD(!o_second_op[2]), .S(AddR), .CO(AddCO), .OFL(AddVO));
  // Produce the output of the second stage.
  always begin
    casez(o_second_op)
    0:       {CO, Result} = {CR,    L | IntR};
    1:       {CO, Result} = {CR,    L & IntR};
    2:       {CO, Result} = {CR,    L ^ IntR};
    3, 6, 7: {CO, Result} = {AddCO, AddR};
    4, 5:    {CO, Result} = {CR,    IntR};
    endcase
    // Final result
    ZO = (Result == 0);
    // Compute overflow flag
    VO = VI;
    casez(o_second_op)
    1: if (!o_fc) VO = IntR[6]; // Set V to 6th bit for BIT
    3: VO = AddVO;              // ADC always sets V
    7: if (o_fc) VO = AddVO;    // Only SBC sets V.
    endcase
    // Compute sign flag. It's always the uppermost bit of the result,
    // except for BIT that sets it to the 7th input bit
    SO = (o_second_op == 1 && !o_fc) ? IntR[7] : Result[7];
  end
endmodule

module AddressGenerator(input clk, input ce,
                        input [4:0] Operation, 
                        input [1:0] MuxCtrl,
                        input [7:0] DataBus, T, X, Y,
                        output [15:0] AX,
                        output Carry);
  // Actual contents of registers
  reg [7:0] AL, AH;
  // Last operation generated a carry?
  reg SavedCarry;
  assign AX = {AH, AL};

  wire [2:0] ALCtrl = Operation[4:2];
  wire [1:0] AHCtrl = Operation[1:0];

  // Possible new value for AL.
  wire [7:0] NewAL;
  assign {Carry,NewAL} = {1'b0, (MuxCtrl[1] ? T : AL)} + {1'b0, (MuxCtrl[0] ? Y : X)};
  
  // The other one
  wire TmpVal = (!AHCtrl[1] | SavedCarry);
  wire [7:0] TmpAdd = (AHCtrl[1] ? AH : AL) + {7'b0, TmpVal};
  
  always @(posedge clk) if (ce) begin
    SavedCarry <= Carry;
    if (ALCtrl[2])
      case(ALCtrl[1:0])
      0: AL <= NewAL;
      1: AL <= DataBus;
      2: AL <= TmpAdd;
      3: AL <= T;
      endcase
     
    case(AHCtrl[1:0])
    0: AH <= AH;
    1: AH <= 0;
    2: AH <= TmpAdd;
    3: AH <= DataBus;
    endcase
  end
endmodule

module ProgramCounter(input clk, input ce,
                      input [1:0] LoadPC,
                      input GotInterrupt,
                      input [7:0] DIN,
                      input [7:0] T,
                      output reg [15:0] PC, output JumpNoOverflow);
  reg [15:0] NewPC;
  assign JumpNoOverflow = ((PC[8] ^ NewPC[8]) == 0) & LoadPC[0] & LoadPC[1];

  always begin
    // Load PC Control
    case (LoadPC) 
    0,1: NewPC = PC + {15'b0, (LoadPC[0] & ~GotInterrupt)};
    2:   NewPC = {DIN,T};
    3:   NewPC = PC + {{8{T[7]}},T};
    endcase
  end
  
  always @(posedge clk)
    if (ce)
      PC <= NewPC;    
endmodule


module CPU(input clk, input ce, input reset,
           input [7:0] DIN,
           input irq,
           input nmi,
           output reg [7:0] dout, output reg [15:0] aout,
           output reg mr,
           output reg mw);
  reg [7:0] A, X, Y;
  reg [7:0] SP, T, P;
  reg [7:0] IR;
  reg [2:0] State;
  reg GotInterrupt;
  
  reg IsResetInterrupt;
  wire [15:0] PC;
  reg JumpTaken;
  wire JumpNoOverflow;

  // De-multiplex microcode
  wire [37:0] MicroCode;
  wire [1:0] LoadSP = MicroCode[1:0];            // 7 LUT
  wire [1:0] LoadPC = MicroCode[3:2];            // 12 LUT
  wire [1:0] AddrBus = MicroCode[5:4];           // 18 LUT
  wire [2:0] MemWrite = MicroCode[8:6];          // 10 LUT
  wire [4:0] AddrCtrl = MicroCode[13:9];       
  wire       FlagCtrl = MicroCode[14];           // RegWrite + FlagCtrl = 22 LUT
  wire [1:0] LoadT = MicroCode[16:15];           // 13 LUT
  wire [1:0] StateCtrl = MicroCode[18:17];
  wire [2:0] FlagsCtrl = MicroCode[21:19];
  wire [15:0] IrFlags = MicroCode[37:22];

  // Load Instruction Register? Force BRK on Interrupt.
  wire [7:0] NextIR = (State == 0) ? (GotInterrupt ? 8'd0 : DIN) : IR;
  wire IsBranchCycle1 = (IR[4:0] == 5'b10000) && State[0];

  // Compute next state.
  reg [2:0] NextState;
  always begin
    case (StateCtrl)
    0: NextState = State + 3'd1;
    1: NextState = (AXCarry ? 3'd4 : 3'd5);
    2: NextState = (IsBranchCycle1 && JumpTaken) ? 2 : 0; // Override next state if the branch is taken.
    3: NextState = (JumpNoOverflow ? 3'd0 : 3'd4);
    endcase
  end

  wire [15:0] AX;
  wire AXCarry;
AddressGenerator addgen(clk, ce, AddrCtrl, {IrFlags[0], IrFlags[1]}, DIN, T, X, Y, AX, AXCarry);

// Microcode table has a 1 clock latency (block ram).
MicroCodeTable micro2(clk, ce, reset, NextIR, NextState, MicroCode);

  wire [7:0] AluR;
  wire [7:0] AluIntR;
  wire CO, VO, SO,ZO;
NewAlu new_alu(IrFlags[15:5], A,X,Y,SP,DIN,T, P[0], P[6], CO, VO, SO, ZO, AluR, AluIntR);

// Registers
always @(posedge clk) if (reset) begin
  A <= 0;
  X <= 0;
  Y <= 0;
end else if (ce) begin
  if (FlagCtrl & IrFlags[2]) X <= AluR;
  if (FlagCtrl & IrFlags[3]) A <= AluR;
  if (FlagCtrl & IrFlags[4]) Y <= AluR;
end

// Program counter
ProgramCounter pc(clk, ce, LoadPC, GotInterrupt, DIN, T, PC, JumpNoOverflow);

reg IsNMIInterrupt;
reg LastNMI;
// NMI is triggered at any time, except during reset, or when we're in the middle of
// reading the vector address
wire turn_nmi_on = (AddrBus != 3) && !IsResetInterrupt && nmi && !LastNMI;
// Controls whether we'll remember the state in LastNMI
wire nmi_remembered = (AddrBus != 3) && !IsResetInterrupt ? nmi : LastNMI;
// NMI flag is cleared right after we read the vector address
wire turn_nmi_off = (AddrBus == 3) && (State[0] == 0);
// Controls whether IsNmiInterrupt will get set
wire nmi_active = turn_nmi_on ? 1 : turn_nmi_off ? 0 : IsNMIInterrupt;
always @(posedge clk) begin
  if (reset) begin
    IsNMIInterrupt <= 0;
    LastNMI <= 0;
  end else if (ce) begin
    IsNMIInterrupt <= nmi_active;
    LastNMI <= nmi_remembered;
  end
end

// Generate outputs from module...
always begin
  dout = 8'bX;
  case (MemWrite[1:0])
  'b00: dout = T;
  'b01: dout = AluR;
  'b10: dout = {P[7:6], 1'b1, !GotInterrupt, P[3:0]};
  'b11: dout = State[0] ? PC[7:0] : PC[15:8];
  endcase
  mw = MemWrite[2] && !IsResetInterrupt; // Prevent writing while handling a reset
  mr = !mw;
end

always begin
  case (AddrBus)
  0: aout = PC;
  1: aout = AX;
  2: aout = {8'h01, SP};
  // irq/BRK vector FFFE
  // nmi vector FFFA
  // Reset vector FFFC
  3: aout = {13'b1111_1111_1111_1, !IsNMIInterrupt, !IsResetInterrupt, ~State[0]};
  endcase 
end

 
always @(posedge clk) begin
  if (reset) begin
    // Reset runs the BRK instruction as usual.
    State <= 0;
    IR <= 0;
    GotInterrupt <= 1;
    IsResetInterrupt <= 1;
    P <= 'h24;
    SP <= 0;
    T <= 0;
    JumpTaken <= 0;
  end else if (ce) begin      
    // Stack pointer control.
    // The operand is an optimization that either
    // returns -1,0,1 depending on LoadSP 
    case (LoadSP)
    0,2,3: SP <= SP + { {7{LoadSP[0]}}, LoadSP[1] };
    1: SP <= X;
    endcase 

    // LoadT control
    case (LoadT)
    2: T <= DIN;
    3: T <= AluIntR;
    endcase

    if (FlagCtrl) begin
      case(FlagsCtrl)
      0: P <= P;      // No Op
      1: {P[0], P[1], P[6], P[7]} <= {CO, ZO, VO, SO}; // ALU
      2: P[2] <= 1;     // BRK
      3: P[6] <= 0;     // CLV
      4: {P[7:6],P[3:0]} <= {DIN[7:6], DIN[3:0]}; // RTI/PLP
      5: P[0] <= IR[5]; // CLC/SEC
      6: P[2] <= IR[5]; // CLI/SEI
      7: P[3] <= IR[5]; // CLD/SED
      endcase
    end

    // Compute if the jump is to be taken. Result is stored in a flipflop, so
    // it won't be available until next cycle.
    // NOTE: Using DIN here. DIN is IR at cycle 0. This means JumpTaken will
    // contain the Jump status at cycle 1.
    case (DIN[7:5])
    0: JumpTaken <= ~P[7]; // BPL
    1: JumpTaken <=  P[7]; // BMI
    2: JumpTaken <= ~P[6]; // BVC
    3: JumpTaken <=  P[6]; // BVS
    4: JumpTaken <= ~P[0]; // BCC
    5: JumpTaken <=  P[0]; // BCS
    6: JumpTaken <= ~P[1]; // BNE
    7: JumpTaken <=  P[1]; // BEQ
    endcase
    
    // Check the interrupt status on the last cycle of the current instruction,
    // (or on cycle #1 of any branch instruction)
    if (StateCtrl == 2'b10) begin
      GotInterrupt <= (irq & ~P[2]) | nmi_active;
      IsResetInterrupt <= 0;
    end

    IR <= NextIR;
    State <= NextState;
  end
end
endmodule
