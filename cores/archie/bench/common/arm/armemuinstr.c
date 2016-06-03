/* ################################################################################## */
/* ## Individual decoded instruction functions                                     ## */
/* ################################################################################## */
static void EMFUNCDECL26(Branch) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
  /* Note that the upper bits of instr (those that don't form the branch offset) get masked out by INCPC */
  INCPCAMT(instr<<2);
  FLUSHPIPE;
} /* EMFUNCDECL26(Branch */

static void EMFUNCDECL26(BranchLink) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
#ifndef ARMUL_USE_IMMEDTABLE
  /* Do what INCPCAMT does when the immedtable isn't in use. Compiler should spot that they're similar and merge them. */
  ARMword temp2 = state->Reg[15];
  temp2 = ROTATER(temp2,26)-(4<<6);
  state->Reg[14] = ROTATER(temp2,6);
#else
  state->Reg[14] = ((state->Reg[15] - 4) & R15PCBITS) | R15CCINTMODE;
#endif
  /* Note that the upper bits of instr (those that don't form the branch offset) get masked out by INCPC */
  INCPCAMT(instr<<2);
  FLUSHPIPE;
} /* EMFUNCDECL26(BranchLink */

static void EMFUNCDECL26(Mul) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = state->Reg[MULRHSReg];
  if (MULLHSReg == MULDESTReg) {
     state->Reg[MULDESTReg] = 0;
     }
  else if (MULDESTReg != 15)
     state->Reg[MULDESTReg] = state->Reg[MULLHSReg] * rhs;
  else {
     }
  for(temp=31;temp;temp--)
    if (rhs & (1L << temp))
      break;
  ARMul_Icycles(state,ARMul_MultTable[temp]);

} /* EMFUNCDECL26(Mul */

static void EMFUNCDECL26(Muls) (ARMul_State *state, ARMword instr) {
  register ARMword dest,temp;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = state->Reg[MULRHSReg];
  if (MULLHSReg == MULDESTReg) {
     state->Reg[MULDESTReg] = 0;
     CLEARN;
     SETZ;
     }
  else if (MULDESTReg != 15) {
     dest = state->Reg[MULLHSReg] * rhs;
     ARMul_NegZero(state,dest);
     state->Reg[MULDESTReg] = dest;
     }
  else {
     }
  for(temp=31;temp;temp--)
    if (rhs & (1L << temp))
      break;
  ARMul_Icycles(state,ARMul_MultTable[temp]);

} /* EMFUNCDECL26(Muls */

static void EMFUNCDECL26(Mla) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = state->Reg[MULRHSReg];
  if (MULLHSReg == MULDESTReg) {
     state->Reg[MULDESTReg] = state->Reg[MULACCReg];
     }
  else if (MULDESTReg != 15)
     state->Reg[MULDESTReg] = state->Reg[MULLHSReg] * rhs + state->Reg[MULACCReg];
  else {
     }
  for(temp=31;temp;temp--)
    if (rhs & (1L << temp))
      break;
  ARMul_Icycles(state,ARMul_MultTable[temp]);

} /* EMFUNCDECL26(Mla */

static void EMFUNCDECL26(Mlas) (ARMul_State *state, ARMword instr) {
  register ARMword dest,temp;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = state->Reg[MULRHSReg];
  if (MULLHSReg == MULDESTReg) {
     dest = state->Reg[MULACCReg];
     ARMul_NegZero(state,dest);
     state->Reg[MULDESTReg] = dest;
     }
  else if (MULDESTReg != 15) {
     dest = state->Reg[MULLHSReg] * rhs + state->Reg[MULACCReg];
     ARMul_NegZero(state,dest);
     state->Reg[MULDESTReg] = dest;
     }
  else {
     }
  for(temp=31;temp;temp--)
    if (rhs & (1L << temp))
      break;
  ARMul_Icycles(state,ARMul_MultTable[temp]);

} /* EMFUNCDECL26(Mlas */

static void EMFUNCDECL26(AndReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = DPRegRHS;
  dest = LHS & rhs;
  WRITEDEST(dest);

} /* EMFUNCDECL26(AndReg */

static void EMFUNCDECL26(AndsReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = DPSRegRHS;
  dest = LHS & rhs;
  WRITESDEST(dest);

} /* EMFUNCDECL26(AndsReg */

static void EMFUNCDECL26(EorReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = DPRegRHS;
  dest = LHS ^ rhs;
  WRITEDEST(dest);

} /* EMFUNCDECL26(EorReg */

static void EMFUNCDECL26(EorsReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = DPSRegRHS;
  dest = LHS ^ rhs;
  WRITESDEST(dest);

} /* EMFUNCDECL26(EorsReg */

static void EMFUNCDECL26(SubReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = DPRegRHS;
  dest = LHS - rhs;
  WRITEDEST(dest);
} /* EMFUNCDECL26(SubReg */

static void EMFUNCDECL26(SubsReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword lhs,rhs;

  EMFUNC_CONDTEST
          lhs = LHS;
             rhs = DPRegRHS;
             dest = lhs - rhs;
             if ((lhs >= rhs) || ((rhs | lhs) >> 31)) {
                ARMul_SubCarry(state,lhs,rhs,dest);
                ARMul_SubOverflow(state,lhs,rhs,dest);
                }
             else {
                CLEARCV;
                }
             WRITESDEST(dest);

} /* EMFUNCDECL26(SubsReg */

static void EMFUNCDECL26(RsbReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = DPRegRHS;
  dest = rhs - LHS;
  WRITEDEST(dest);
} /* EMFUNCDECL26(RsbReg */

static void EMFUNCDECL26(RsbsReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword lhs,rhs;

  EMFUNC_CONDTEST
          lhs = LHS;
             rhs = DPRegRHS;
             dest = rhs - lhs;
             if ((rhs >= lhs) || ((rhs | lhs) >> 31)) {
                ARMul_SubCarry(state,rhs,lhs,dest);
                ARMul_SubOverflow(state,rhs,lhs,dest);
                }
             else {
                CLEARCV;
                }
             WRITESDEST(dest);

} /* EMFUNCDECL26(RsbsReg */

static void EMFUNCDECL26(AddReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
         rhs = DPRegRHS;
             dest = LHS + rhs;
             WRITEDEST(dest);

} /* EMFUNCDECL26(AddReg */

static void EMFUNCDECL26(AddsReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword lhs,rhs;

  EMFUNC_CONDTEST
         lhs = LHS;
             rhs = DPRegRHS;
             dest = lhs + rhs;
             ASSIGNZ(dest==0);
             if ((lhs | rhs) >> 30) { /* possible C,V,N to set */
                ASSIGNN(NEG(dest));
                ARMul_AddCarry(state,lhs,rhs,dest);
                ARMul_AddOverflow(state,lhs,rhs,dest);
                }
             else {
                CLEARNCV;
                }
             WRITESDEST(dest);

} /* EMFUNCDECL26(AddsReg */

static void EMFUNCDECL26(AdcReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
rhs = DPRegRHS;
             dest = LHS + rhs + CFLAG;
             WRITEDEST(dest);

} /* EMFUNCDECL26(AdcReg */

static void EMFUNCDECL26(AdcsReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword lhs,rhs;

  EMFUNC_CONDTEST

  lhs = LHS;
             rhs = DPRegRHS;
             dest = lhs + rhs + CFLAG;
             ASSIGNZ(dest==0);
             if ((lhs | rhs) >> 30) { /* possible C,V,N to set */
                ASSIGNN(NEG(dest));
                ARMul_AddCarry(state,lhs,rhs,dest);
                ARMul_AddOverflow(state,lhs,rhs,dest);
                }
             else {
                CLEARNCV;
                }
             WRITESDEST(dest);

} /* EMFUNCDECL26(AdcsReg */

static void EMFUNCDECL26(SbcReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
 rhs = DPRegRHS;
             dest = LHS - rhs - !CFLAG;
             WRITEDEST(dest);

} /* EMFUNCDECL26(SbcReg */

static void EMFUNCDECL26(SbcsReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword lhs,rhs;

  EMFUNC_CONDTEST
 lhs = LHS;
             rhs = DPRegRHS;
             dest = lhs - rhs - !CFLAG;
             if ((lhs >= rhs) || ((rhs | lhs) >> 31)) {
                ARMul_SubCarry(state,lhs,rhs,dest);
                ARMul_SubOverflow(state,lhs,rhs,dest);
                }
             else {
                CLEARCV;
                }
             WRITESDEST(dest);

} /* EMFUNCDECL26(SbcsReg */

static void EMFUNCDECL26(RscReg) (ARMul_State *state, ARMword instr) {
  ARMword dest,rhs;

  EMFUNC_CONDTEST
  rhs = DPRegRHS;
             dest = rhs - LHS - !CFLAG;
             WRITEDEST(dest);

} /* EMFUNCDECL26(RscReg */

static void EMFUNCDECL26(RscsReg) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword lhs,rhs;

  EMFUNC_CONDTEST
    lhs = LHS;
             rhs = DPRegRHS;
             dest = rhs - lhs - !CFLAG;
             if ((rhs >= lhs) || ((rhs | lhs) >> 31)) {
                ARMul_SubCarry(state,rhs,lhs,dest);
                ARMul_SubOverflow(state,rhs,lhs,dest);
                }
             else {
                CLEARCV;
                }
             WRITESDEST(dest);

} /* EMFUNCDECL26(RscsReg */

static void EMFUNCDECL26(TstRegMrs1SwpNorm) (ARMul_State *state, ARMword instr) {
  register ARMword dest, temp;

  EMFUNC_CONDTEST
             if (BITS(4,11) == 9) { /* SWP */
                temp = LHS;
                BUSUSEDINCPCS;

                if (ADDREXCEPT(temp)) {
                   dest = 0; /* Stop GCC warning, not sure what's appropriate */
                   INTERNALABORT(temp);
                   (void)ARMul_LoadWordN(state,temp);
                   (void)ARMul_LoadWordN(state,temp);

                } else {
                  dest = ARMul_SwapWord(state,temp,state->Reg[RHSReg]);
                }

                if (temp & 3) {
                  DEST = ARMul_Align(state,temp,dest);
                } else {
                  DEST = dest;
                }

                if (state->abortSig || state->Aborted) {
                  TAKEABORT;
                }
             }

} /* EMFUNCDECL26( */

static void EMFUNCDECL26(TstpRegNorm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = DPSRegRHS;
  dest = LHS & rhs;
  ARMul_NegZero(state,dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(TeqpRegNorm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;
  EMFUNC_CONDTEST

  rhs = DPSRegRHS;
  dest = LHS ^ rhs;
  ARMul_NegZero(state,dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(CmpRegMrs2SwpNorm) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

             if (BITS(4,11) == 9) { /* SWP */
                temp = LHS;
                BUSUSEDINCPCS;
                if (ADDREXCEPT(temp)) {
                   INTERNALABORT(temp);
                   (void)ARMul_LoadByte(state,temp);
                   (void)ARMul_LoadByte(state,temp);
                   }
                else
                DEST = ARMul_SwapByte(state,temp,state->Reg[RHSReg]);
                if (state->abortSig || state->Aborted) {
                   TAKEABORT;
                   }
                }

} /* EMFUNCDECL26( */

static void EMFUNCDECL26(CmppRegNorm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword lhs,rhs;
  EMFUNC_CONDTEST

  lhs = LHS;
  rhs = DPRegRHS;
  dest = lhs - rhs;
  ARMul_NegZero(state,dest);
  if ((lhs >= rhs) || ((rhs | lhs) >> 31)) {
     ARMul_SubCarry(state,lhs,rhs,dest);
     ARMul_SubOverflow(state,lhs,rhs,dest);
     }
  else {
     CLEARCV;
                   }
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(CmnpRegNorm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword lhs,rhs;
  EMFUNC_CONDTEST

  lhs = LHS;
  rhs = DPRegRHS;
  dest = lhs + rhs;
  ASSIGNZ(dest==0);
  if ((lhs | rhs) >> 30) { /* possible C,V,N to set */
     ASSIGNN(NEG(dest));
     ARMul_AddCarry(state,lhs,rhs,dest);
     ARMul_AddOverflow(state,lhs,rhs,dest);
  } else {
    CLEARNCV;
  }
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(OrrRegNorm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;
  EMFUNC_CONDTEST

  rhs = DPRegRHS;
  dest = LHS | rhs;
  WRITEDESTNORM(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(OrrsRegNorm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = DPSRegRHS;
  dest = LHS | rhs;
  WRITESDESTNORM(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(MovRegNorm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = DPRegRHS;
  WRITEDESTNORM(dest);
} /* EMFUNCDECL26(MovReg */

static void EMFUNCDECL26(MovsRegNorm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = DPSRegRHS;
  WRITESDESTNORM(dest);
} /* EMFUNCDECL26(MovsReg */

static void EMFUNCDECL26(BicRegNorm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = DPRegRHS;
  dest = LHS & ~rhs;
  WRITEDESTNORM(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(BicsRegNorm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = DPSRegRHS;
  dest = LHS & ~rhs;
  WRITESDESTNORM(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(MvnRegNorm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = ~DPRegRHS;
  WRITEDESTNORM(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(MvnsRegNorm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = ~DPSRegRHS;
  WRITESDESTNORM(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(TstRegMrs1SwpPC) (ARMul_State *state, ARMword instr) {
  register ARMword dest, temp;

  EMFUNC_CONDTEST
             if (BITS(4,11) == 9) { /* SWP */
                temp = LHS;
                BUSUSEDINCPCS;
                if (ADDREXCEPT(temp)) {
                   dest = 0; /* Stop GCC warning, not sure what's appropriate */
                   INTERNALABORT(temp);
                   (void)ARMul_LoadWordN(state,temp);
                   (void)ARMul_LoadWordN(state,temp);
                   }
                else
                  dest = ARMul_SwapWord(state,temp,state->Reg[RHSReg]);
                if (temp & 3)
                    DEST = ARMul_Align(state,temp,dest);
                else
                    DEST = dest;
                if (state->abortSig || state->Aborted) {
                   TAKEABORT;
                   }
                }

} /* EMFUNCDECL26( */

static void EMFUNCDECL26(TstpRegPC) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = DPRegRHS;
  temp = LHS & rhs;
  SETR15PSR(temp);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(TeqpRegPC) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  ARMword rhs;
  EMFUNC_CONDTEST

  rhs = DPRegRHS;
  temp = LHS ^ rhs;
  SETR15PSR(temp);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(CmpRegMrs2SwpPC) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

             if (BITS(4,11) == 9) { /* SWP */
                temp = LHS;
                BUSUSEDINCPCS;
                if (ADDREXCEPT(temp)) {
                   INTERNALABORT(temp);
                   (void)ARMul_LoadByte(state,temp);
                   (void)ARMul_LoadByte(state,temp);
                   }
                else
                  DEST = ARMul_SwapByte(state,temp,state->Reg[RHSReg]);
                if (state->abortSig || state->Aborted) {
                   TAKEABORT;
                   }
                }

} /* EMFUNCDECL26( */

static void EMFUNCDECL26(CmppRegPC) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  ARMword rhs;
  EMFUNC_CONDTEST

  rhs = DPRegRHS;
  temp = LHS - rhs;
  SETR15PSR(temp);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(CmnpRegPC) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  ARMword rhs;
  EMFUNC_CONDTEST

  rhs = DPRegRHS;
  temp = LHS + rhs;
  SETR15PSR(temp);

} /* EMFUNCDECL26( */

static void EMFUNCDECL26(OrrRegPC) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;
  EMFUNC_CONDTEST

  rhs = DPRegRHS;
  dest = LHS | rhs;
  WRITEDESTPC(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(OrrsRegPC) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = DPSRegRHS;
  dest = LHS | rhs;
  WRITESDESTPC(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(MovRegPC) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = DPRegRHS;
  WRITEDESTPC(dest);
} /* EMFUNCDECL26(MovReg */

static void EMFUNCDECL26(MovsRegPC) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = DPSRegRHS;
  WRITESDESTPC(dest);
} /* EMFUNCDECL26(MovsReg */

static void EMFUNCDECL26(BicRegPC) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = DPRegRHS;
  dest = LHS & ~rhs;
  WRITEDESTPC(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(BicsRegPC) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  ARMword rhs;

  EMFUNC_CONDTEST
  rhs = DPSRegRHS;
  dest = LHS & ~rhs;
  WRITESDESTPC(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(MvnRegPC) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = ~DPRegRHS;
  WRITEDESTPC(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(MvnsRegPC) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = ~DPSRegRHS;
  WRITESDESTPC(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(AndImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = LHS & DPImmRHS;
  WRITEDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(AndsImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest,rhs,temp;

  EMFUNC_CONDTEST
  DPSImmRHS;
  dest = LHS & rhs;
  WRITESDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(EorImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = LHS ^ DPImmRHS;
  WRITEDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(EorsImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest,rhs,temp;

  EMFUNC_CONDTEST
  DPSImmRHS;
  dest = LHS ^ rhs;
  WRITESDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(SubImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = LHS - DPImmRHS;
  WRITEDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(SubsImmNorm) (ARMul_State *state, ARMword instr) {
  register ARMword dest,rhs,lhs;

  EMFUNC_CONDTEST
             lhs = LHS;
             rhs = DPImmRHS;
             dest = lhs - rhs;
             if ((lhs >= rhs) || ((rhs | lhs) >> 31)) {
                ARMul_SubCarry(state,lhs,rhs,dest);
                ARMul_SubOverflow(state,lhs,rhs,dest);
                }  
             else {
                CLEARCV;
                }

             if (DESTReg == 15)
                WRITESDESTPC(dest);
             else
                WRITESDESTNORM(dest);

} /* EMFUNCDECL26( */

/*static void EMFUNCDECL26(SubsImmPc) (ARMul_State *state, ARMword instr) {
  register ARMword dest,rhs,lhs;

  EMFUNC_CONDTEST
             lhs = LHS;
             rhs = DPImmRHS;
             dest = lhs - rhs;
             if ((lhs >= rhs) || ((rhs | lhs) >> 31)) {
                ARMul_SubCarry(state,lhs,rhs,dest);
                ARMul_SubOverflow(state,lhs,rhs,dest);
                }  
             else {
                CLEARC;
                CLEARV;
                }
             WRITESDESTPC(dest);

}*/ /* EMFUNCDECL26( */

static void EMFUNCDECL26(RsbImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = DPImmRHS - LHS;
  WRITEDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(RsbsImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest,rhs,lhs;

  EMFUNC_CONDTEST
            lhs = LHS;
             rhs = DPImmRHS;
             dest = rhs - lhs;
             if ((rhs >= lhs) || ((rhs | lhs) >> 31)) {
                ARMul_SubCarry(state,rhs,lhs,dest);
                ARMul_SubOverflow(state,rhs,lhs,dest);
                }
             else {
                CLEARCV;
                }
             WRITESDEST(dest);

} /* EMFUNCDECL26( */

static void EMFUNCDECL26(AddImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = LHS + DPImmRHS;
  WRITEDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(AddsImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest,lhs,rhs;

  EMFUNC_CONDTEST
            lhs = LHS;
             rhs = DPImmRHS;
             dest = lhs + rhs;
             ASSIGNZ(dest==0);
             if ((lhs | rhs) >> 30) { /* possible C,V,N to set */
                ASSIGNN(NEG(dest));
                ARMul_AddCarry(state,lhs,rhs,dest);
                ARMul_AddOverflow(state,lhs,rhs,dest);
                }
             else {
                CLEARNCV;
                }
             WRITESDEST(dest);

} /* EMFUNCDECL26( */

static void EMFUNCDECL26(AdcImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = LHS + DPImmRHS + CFLAG;
  WRITEDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(AdcsImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest,lhs,rhs;

  EMFUNC_CONDTEST
           lhs = LHS;
             rhs = DPImmRHS;
             dest = lhs + rhs + CFLAG;
             ASSIGNZ(dest==0);
             if ((lhs | rhs) >> 30) { /* possible C,V,N to set */
                ASSIGNN(NEG(dest));
                ARMul_AddCarry(state,lhs,rhs,dest);
                ARMul_AddOverflow(state,lhs,rhs,dest);
                }
             else {
                CLEARNCV;
                }
             WRITESDEST(dest);

} /* EMFUNCDECL26( */

static void EMFUNCDECL26(SbcImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = LHS - DPImmRHS - !CFLAG;
  WRITEDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(SbcsImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest,lhs,rhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             rhs = DPImmRHS;
             dest = lhs - rhs - !CFLAG;
             if ((lhs >= rhs) || ((rhs | lhs) >> 31)) {
                ARMul_SubCarry(state,lhs,rhs,dest);
                ARMul_SubOverflow(state,lhs,rhs,dest);
                }
             else {
                CLEARCV;
                }
             WRITESDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(RscImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;

  EMFUNC_CONDTEST
  dest = DPImmRHS - LHS - !CFLAG;
  WRITEDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(RscsImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest,lhs,rhs;
  EMFUNC_CONDTEST

            lhs = LHS;
             rhs = DPImmRHS;
             dest = rhs - lhs - !CFLAG;
             if ((rhs >= lhs) || ((rhs | lhs) >> 31)) {
                ARMul_SubCarry(state,rhs,lhs,dest);
                ARMul_SubOverflow(state,rhs,lhs,dest);
                }
             else {
                CLEARCV;
                }
             WRITESDEST(dest);

} /* EMFUNCDECL26( */

static void EMFUNCDECL26(TstpImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest,rhs,temp;
  EMFUNC_CONDTEST

             if (DESTReg == 15) { /* TSTP immed */
                temp = LHS & DPImmRHS;
                SETR15PSR(temp);
                }
             else {
                DPSImmRHS; /* TST immed */
                dest = LHS & rhs;
                ARMul_NegZero(state,dest);
                }

} /* EMFUNCDECL26( */

static void EMFUNCDECL26(TeqpImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest,rhs,temp;
  EMFUNC_CONDTEST

             if (DESTReg == 15) { /* TEQP immed */
                temp = LHS ^ DPImmRHS;
                SETR15PSR(temp);
                }
             else {
                DPSImmRHS; /* TEQ immed */
                dest = LHS ^ rhs;
                ARMul_NegZero(state,dest);
                }

} /* EMFUNCDECL26( */

static void EMFUNCDECL26(CmppImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest,lhs,rhs,temp;
  EMFUNC_CONDTEST

             if (DESTReg == 15) { /* CMPP immed */
                temp = LHS - DPImmRHS;
                SETR15PSR(temp);
                }
             else {
                lhs = LHS; /* CMP immed */
                rhs = DPImmRHS;
                dest = lhs - rhs;
                ARMul_NegZero(state,dest);
                if ((lhs >= rhs) || ((rhs | lhs) >> 31)) {
                   ARMul_SubCarry(state,lhs,rhs,dest);
                   ARMul_SubOverflow(state,lhs,rhs,dest);
                   }
                else {
                   CLEARCV;
                   }
                }

} /* EMFUNCDECL26( */

static void EMFUNCDECL26(CmnpImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest,lhs,rhs,temp;
  EMFUNC_CONDTEST


             if (DESTReg == 15) { /* CMNP immed */
                temp = LHS + DPImmRHS;
                SETR15PSR(temp);
                }
             else {
                lhs = LHS; /* CMN immed */
                rhs = DPImmRHS;
                dest = lhs + rhs;
                ASSIGNZ(dest==0);
                if ((lhs | rhs) >> 30) { /* possible C,V,N to set */
                   ASSIGNN(NEG(dest));
                   ARMul_AddCarry(state,lhs,rhs,dest);
                   ARMul_AddOverflow(state,lhs,rhs,dest);
                   }
                else {
                   CLEARNCV;
                   }
                }

} /* EMFUNCDECL26( */

static void EMFUNCDECL26(OrrImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  EMFUNC_CONDTEST

  dest = LHS | DPImmRHS;
  WRITEDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(OrrsImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest,rhs,temp;
  EMFUNC_CONDTEST

  DPSImmRHS;
  dest = LHS | rhs;
  WRITESDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(MovImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  EMFUNC_CONDTEST

  dest = DPImmRHS;
  WRITEDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(MovsImm) (ARMul_State *state, ARMword instr) {
  register ARMword rhs,temp;
  EMFUNC_CONDTEST

  DPSImmRHS;
  WRITESDEST(rhs);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(BicImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  EMFUNC_CONDTEST

  dest = LHS & ~DPImmRHS;
  WRITEDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(BicsImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest,rhs,temp;
  EMFUNC_CONDTEST

  DPSImmRHS;
  dest = LHS & ~rhs;
  WRITESDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(MvnImm) (ARMul_State *state, ARMword instr) {
  register ARMword dest;
  EMFUNC_CONDTEST

  dest = ~DPImmRHS;
  WRITEDEST(dest);
} /* EMFUNCDECL26( */

static void EMFUNCDECL26(MvnsImm) (ARMul_State *state, ARMword instr) {
  register ARMword rhs,temp;
  EMFUNC_CONDTEST

  DPSImmRHS;
  WRITESDEST(~rhs);
} /* EMFUNCDECL26( */


static void EMFUNCDECL26(StoreNoWritePostDecImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (StoreWord(state,instr,lhs))
                LSBase = lhs - LSImmRHS;
}

static void EMFUNCDECL26(LoadNoWritePostDecImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (LoadWord(state,instr,lhs))
                LSBase = lhs - LSImmRHS;
}

static void EMFUNCDECL26(StoreWritePostDecImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs,temp;
  EMFUNC_CONDTEST
             lhs = LHS;
             temp = lhs - LSImmRHS;
             state->NtransSig = LOW;
             if (StoreWord(state,instr,lhs))
                LSBase = temp;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}

static void EMFUNCDECL26(LoadWritePostDecImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (LoadWord(state,instr,lhs))
                LSBase = lhs - LSImmRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}

static void EMFUNCDECL26(StoreBNoWritePostDecImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (StoreByte(state,instr,lhs))
                LSBase = lhs - LSImmRHS;
}

static void EMFUNCDECL26(LoadBNoWritePostDecImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (LoadByte(state,instr,lhs))
                LSBase = lhs - LSImmRHS;
}

static void EMFUNCDECL26(StoreBWritePostDecImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (StoreByte(state,instr,lhs))
                LSBase = lhs - LSImmRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}

static void EMFUNCDECL26(LoadBWritePostDecImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (LoadByte(state,instr,lhs))
                LSBase = lhs - LSImmRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}

static void EMFUNCDECL26(StoreNoWritePostIncImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (StoreWord(state,instr,lhs))
                LSBase = lhs + LSImmRHS;
}

static void EMFUNCDECL26(LoadNoWritePostIncImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (LoadWord(state,instr,lhs))
                LSBase = lhs + LSImmRHS;
}

static void EMFUNCDECL26(StoreWritePostIncImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (StoreWord(state,instr,lhs))
                LSBase = lhs + LSImmRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}

static void EMFUNCDECL26(LoadWritePostIncImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (LoadWord(state,instr,lhs))
                LSBase = lhs + LSImmRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}

static void EMFUNCDECL26(StoreBNoWritePostIncImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (StoreByte(state,instr,lhs))
                LSBase = lhs + LSImmRHS;
}

static void EMFUNCDECL26(LoadBNoWritePostIncImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (LoadByte(state,instr,lhs))
                LSBase = lhs + LSImmRHS;
}

static void EMFUNCDECL26(StoreBWritePostIncImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (StoreByte(state,instr,lhs))
                LSBase = lhs + LSImmRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}

static void EMFUNCDECL26(LoadBWritePostIncImm) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (LoadByte(state,instr,lhs))
                LSBase = lhs + LSImmRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}


static void EMFUNCDECL26(StoreNoWritePreDecImm) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)StoreWord(state,instr,LHS - LSImmRHS);
}

static void EMFUNCDECL26(LoadNoWritePreDecImm) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)LoadWord(state,instr,LHS - LSImmRHS);
}

static void EMFUNCDECL26(StoreWritePreDecImm) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS - LSImmRHS;
             if (StoreWord(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(LoadWritePreDecImm) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS - LSImmRHS;
             if (LoadWord(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(StoreBNoWritePreDecImm) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)StoreByte(state,instr,LHS - LSImmRHS);
}

static void EMFUNCDECL26(LoadBNoWritePreDecImm) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)LoadByte(state,instr,LHS - LSImmRHS);
}

static void EMFUNCDECL26(StoreBWritePreDecImm) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS - LSImmRHS;
             if (StoreByte(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(LoadBWritePreDecImm) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS - LSImmRHS;
             if (LoadByte(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(StoreNoWritePreIncImm) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)StoreWord(state,instr,LHS + LSImmRHS);
}

static void EMFUNCDECL26(LoadNoWritePreIncImm) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)LoadWord(state,instr,LHS + LSImmRHS);
}

static void EMFUNCDECL26(StoreWritePreIncImm) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS + LSImmRHS;
             if (StoreWord(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(LoadWritePreIncImm) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS + LSImmRHS;
             if (LoadWord(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(StoreBNoWritePreIncImm) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)StoreByte(state,instr,LHS + LSImmRHS);
}

static void EMFUNCDECL26(LoadBNoWritePreIncImm) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)LoadByte(state,instr,LHS + LSImmRHS);
}

static void EMFUNCDECL26(StoreBWritePreIncImm) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS + LSImmRHS;
             if (StoreByte(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(LoadBWritePreIncImm) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS + LSImmRHS;
             if (LoadByte(state,instr,temp))
                LSBase = temp;
}


static void EMFUNCDECL26(StoreNoWritePostDecReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (StoreWord(state,instr,lhs))
                LSBase = lhs - LSRegRHS;
}

static void EMFUNCDECL26(LoadNoWritePostDecReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (LoadWord(state,instr,lhs))
                LSBase = lhs - LSRegRHS;
}

static void EMFUNCDECL26(StoreWritePostDecReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (StoreWord(state,instr,lhs))
                LSBase = lhs - LSRegRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}

static void EMFUNCDECL26(LoadWritePostDecReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (LoadWord(state,instr,lhs))
                LSBase = lhs - LSRegRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}

static void EMFUNCDECL26(StoreBNoWritePostDecReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (StoreByte(state,instr,lhs))
                LSBase = lhs - LSRegRHS;
}

static void EMFUNCDECL26(LoadBNoWritePostDecReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (LoadByte(state,instr,lhs))
                LSBase = lhs - LSRegRHS;
}

static void EMFUNCDECL26(StoreBWritePostDecReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (StoreByte(state,instr,lhs))
                LSBase = lhs - LSRegRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}

static void EMFUNCDECL26(LoadBWritePostDecReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (LoadByte(state,instr,lhs))
                LSBase = lhs - LSRegRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}

static void EMFUNCDECL26(StoreNoWritePostIncReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (StoreWord(state,instr,lhs))
                LSBase = lhs + LSRegRHS;
}

static void EMFUNCDECL26(LoadNoWritePostIncReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (LoadWord(state,instr,lhs))
                LSBase = lhs + LSRegRHS;
}

static void EMFUNCDECL26(StoreWritePostIncReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (StoreWord(state,instr,lhs))
                LSBase = lhs + LSRegRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}

static void EMFUNCDECL26(LoadWritePostIncReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (LoadWord(state,instr,lhs))
                LSBase = lhs + LSRegRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}

static void EMFUNCDECL26(StoreBNoWritePostIncReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (StoreByte(state,instr,lhs))
                LSBase = lhs + LSRegRHS;
}

static void EMFUNCDECL26(LoadBNoWritePostIncReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             if (LoadByte(state,instr,lhs))
                LSBase = lhs + LSRegRHS;
}

static void EMFUNCDECL26(StoreBWritePostIncReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (StoreByte(state,instr,lhs))
                LSBase = lhs + LSRegRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}

static void EMFUNCDECL26(LoadBWritePostIncReg) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST
             lhs = LHS;
             state->NtransSig = LOW;
             if (LoadByte(state,instr,lhs))
                LSBase = lhs + LSRegRHS;
             state->NtransSig = (R15MODE)?HIGH:LOW;
}


static void EMFUNCDECL26(StoreNoWritePreDecReg) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)StoreWord(state,instr,LHS - LSRegRHS);
}

static void EMFUNCDECL26(LoadNoWritePreDecReg) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)LoadWord(state,instr,LHS - LSRegRHS);
}

static void EMFUNCDECL26(StoreWritePreDecReg) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS - LSRegRHS;
             if (StoreWord(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(LoadWritePreDecReg) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS - LSRegRHS;
             if (LoadWord(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(StoreBNoWritePreDecReg) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)StoreByte(state,instr,LHS - LSRegRHS);
}

static void EMFUNCDECL26(LoadBNoWritePreDecReg) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)LoadByte(state,instr,LHS - LSRegRHS);
}

static void EMFUNCDECL26(StoreBWritePreDecReg) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS - LSRegRHS;
             if (StoreByte(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(LoadBWritePreDecReg) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS - LSRegRHS;
             if (LoadByte(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(StoreNoWritePreIncReg) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)StoreWord(state,instr,LHS + LSRegRHS);
}

static void EMFUNCDECL26(LoadNoWritePreIncReg) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)LoadWord(state,instr,LHS + LSRegRHS);
}

static void EMFUNCDECL26(StoreWritePreIncReg) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS + LSRegRHS;
             if (StoreWord(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(LoadWritePreIncReg) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS + LSRegRHS;
             if (LoadWord(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(StoreBNoWritePreIncReg) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)StoreByte(state,instr,LHS + LSRegRHS);
}

static void EMFUNCDECL26(LoadBNoWritePreIncReg) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             (void)LoadByte(state,instr,LHS + LSRegRHS);
}

static void EMFUNCDECL26(StoreBWritePreIncReg) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS + LSRegRHS;
             if (StoreByte(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(LoadBWritePreIncReg) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST
             temp = LHS + LSRegRHS;
             if (LoadByte(state,instr,temp))
                LSBase = temp;
}

static void EMFUNCDECL26(Undef) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
  ARMul_UndefInstr(state,instr);
}

static void EMFUNCDECL26(MultiStorePostDec) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  STOREMULT(instr,LSBase - LSMNumRegs + 4L,0L);
}

static void EMFUNCDECL26(MultiLoadPostDec) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  LOADMULT(instr,LSBase - LSMNumRegs + 4L,0L);
  
}

static void EMFUNCDECL26(MultiStoreWritePostDec) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase - LSMNumRegs;
  STOREMULT(instr,temp + 4L,temp);}

static void EMFUNCDECL26(MultiLoadWritePostDec) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase - LSMNumRegs;
  LOADMULT(instr,temp + 4L,temp);

}

static void EMFUNCDECL26(MultiStoreFlagsPostDec) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  STORESMULT(instr,LSBase - LSMNumRegs + 4L,0L);
}

static void EMFUNCDECL26(MultiLoadFlagsPostDec) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  LOADSMULT(instr,LSBase - LSMNumRegs + 4L,0L);
}

static void EMFUNCDECL26(MultiStoreWriteFlagsPostDec) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase - LSMNumRegs;
  STORESMULT(instr,temp + 4L,temp);
}

static void EMFUNCDECL26(MultiLoadWriteFlagsPostDec) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase - LSMNumRegs;
  LOADSMULT(instr,temp + 4L,temp);
}

static void EMFUNCDECL26(MultiStorePostInc) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  STOREMULT(instr,LSBase,0L);
}

static void EMFUNCDECL26(MultiLoadPostInc) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  LOADMULT(instr,LSBase,0L);
}

static void EMFUNCDECL26(MultiStoreWritePostInc) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase;
  STOREMULT(instr,temp,temp + LSMNumRegs);
}

static void EMFUNCDECL26(MultiLoadWritePostInc) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase;
  LOADMULT(instr,temp,temp + LSMNumRegs);
}

static void EMFUNCDECL26(MultiStoreFlagsPostInc) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  STORESMULT(instr,LSBase,0L);
}

static void EMFUNCDECL26(MultiLoadFlagsPostInc) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  LOADSMULT(instr,LSBase,0L);
}

static void EMFUNCDECL26(MultiStoreWriteFlagsPostInc) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase;
  STORESMULT(instr,temp,temp + LSMNumRegs);
}

static void EMFUNCDECL26(MultiLoadWriteFlagsPostInc) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase;
  LOADSMULT(instr,temp,temp + LSMNumRegs);
}

static void EMFUNCDECL26(MultiStorePreDec) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  STOREMULT(instr,LSBase - LSMNumRegs,0L);
}

static void EMFUNCDECL26(MultiLoadPreDec) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  LOADMULT(instr,LSBase - LSMNumRegs,0L);
}

static void EMFUNCDECL26(MultiStoreWritePreDec) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase - LSMNumRegs;
  STOREMULT(instr,temp,temp);
}

static void EMFUNCDECL26(MultiLoadWritePreDec) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase - LSMNumRegs;
  LOADMULT(instr,temp,temp);
}

static void EMFUNCDECL26(MultiStoreFlagsPreDec) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  STORESMULT(instr,LSBase - LSMNumRegs,0L);
  
}

static void EMFUNCDECL26(MultiLoadFlagsPreDec) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  LOADSMULT(instr,LSBase - LSMNumRegs,0L);
}

static void EMFUNCDECL26(MultiStoreWriteFlagsPreDec) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase - LSMNumRegs;
  STORESMULT(instr,temp,temp);
}

static void EMFUNCDECL26(MultiLoadWriteFlagsPreDec) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase - LSMNumRegs;
  LOADSMULT(instr,temp,temp);
}

static void EMFUNCDECL26(MultiStorePreInc) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  STOREMULT(instr,LSBase + 4L,0L);
}

static void EMFUNCDECL26(MultiLoadPreInc) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  LOADMULT(instr,LSBase + 4L,0L);
}

static void EMFUNCDECL26(MultiStoreWritePreInc) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase;
  STOREMULT(instr,temp + 4L,temp + LSMNumRegs);
}

static void EMFUNCDECL26(MultiLoadWritePreInc) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase;
  LOADMULT(instr,temp + 4L,temp + LSMNumRegs);
}

static void EMFUNCDECL26(MultiStoreFlagsPreInc) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  STORESMULT(instr,LSBase + 4L,0L);
}

static void EMFUNCDECL26(MultiLoadFlagsPreInc) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  LOADSMULT(instr,LSBase + 4L,0L);
}

static void EMFUNCDECL26(MultiStoreWriteFlagsPreInc) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase;
  STORESMULT(instr,temp + 4L,temp + LSMNumRegs);
}

static void EMFUNCDECL26(MultiLoadWriteFlagsPreInc) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

  temp = LSBase;
  LOADSMULT(instr,temp + 4L,temp + LSMNumRegs);
}

static void EMFUNCDECL26(CoLoadWritePostDec) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST

  lhs = LHS;
  state->Base = lhs - LSCOff;
  ARMul_LDC(state,instr,lhs);
}

static void EMFUNCDECL26(CoStoreNoWritePostDec) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  ARMul_STC(state,instr,LHS);

}

static void EMFUNCDECL26(CoLoadNoWritePostDec) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  ARMul_LDC(state,instr,LHS);
}

static void EMFUNCDECL26(CoStoreWritePostDec) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST

  lhs = LHS;
  state->Base = lhs - LSCOff;
  ARMul_STC(state,instr,lhs);
}

static void EMFUNCDECL26(CoStoreNoWritePostInc) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  ARMul_STC(state,instr,LHS);
}

static void EMFUNCDECL26(CoLoadNoWritePostInc) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  ARMul_LDC(state,instr,LHS);
}

static void EMFUNCDECL26(CoStoreWritePostInc) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST

  lhs = LHS;
  state->Base = lhs + LSCOff;
  ARMul_STC(state,instr,LHS);
}

static void EMFUNCDECL26(CoLoadWritePostInc) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST

  lhs = LHS;
  state->Base = lhs + LSCOff;
  ARMul_LDC(state,instr,LHS);
}

static void EMFUNCDECL26(CoStoreNoWritePreDec) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  ARMul_STC(state,instr,LHS - LSCOff);
}

static void EMFUNCDECL26(CoLoadNoWritePreDec) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  ARMul_LDC(state,instr,LHS - LSCOff);
}

static void EMFUNCDECL26(CoStoreWritePreDec) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST

  lhs = LHS - LSCOff;
  state->Base = lhs;
  ARMul_STC(state,instr,lhs);
}

static void EMFUNCDECL26(CoLoadWritePreDec) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST

  lhs = LHS - LSCOff;
  state->Base = lhs;
  ARMul_LDC(state,instr,lhs);
}

static void EMFUNCDECL26(CoStoreNoWritePreInc) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  ARMul_STC(state,instr,LHS + LSCOff);

}

static void EMFUNCDECL26(CoLoadNoWritePreInc) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST

  ARMul_LDC(state,instr,LHS + LSCOff);
}

static void EMFUNCDECL26(CoStoreWritePreInc) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST

  lhs = LHS + LSCOff;
  state->Base = lhs;
  ARMul_STC(state,instr,lhs);
}

static void EMFUNCDECL26(CoLoadWritePreInc) (ARMul_State *state, ARMword instr) {
  register ARMword lhs;
  EMFUNC_CONDTEST

  lhs = LHS + LSCOff;
  state->Base = lhs;
  ARMul_LDC(state,instr,lhs);
}

static void EMFUNCDECL26(CoMCRDataOp) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             if (BIT(4)) { /* MCR */
                if (DESTReg == 15) {
                   ARMul_MCR(state,instr,R15CCINTMODE |
                                          ((state->Reg[15] + 4) & R15PCBITS) );
                   }
                else
                   ARMul_MCR(state,instr,DEST);
                }
             else /* CDP Part 1 */
                ARMul_CDP(state,instr);
}

static void EMFUNCDECL26(CoMRCDataOp) (ARMul_State *state, ARMword instr) {
  register ARMword temp;
  EMFUNC_CONDTEST

             if (BIT(4)) { /* MRC */
                temp = ARMul_MRC(state,instr);
                if (DESTReg == 15) {
                   state->Reg[15] = (state->Reg[15]&~CCBITS) | (temp&CCBITS);
                   }
                else
                   DEST = temp;
                }
             else /* CDP Part 2 */
                ARMul_CDP(state,instr);
}

static void EMFUNCDECL26(SWI) (ARMul_State *state, ARMword instr) {
  EMFUNC_CONDTEST
             if (instr == ARMul_ABORTWORD && state->AbortAddr == ((state->Reg[15]-8) & R15PCBITS)) { /* a prefetch abort */
                ARMul_Abort(state,ARMul_PrefetchAbortV);
                return;
                }

                ARMul_Abort(state,ARMul_SWIV);
}

static void EMFUNCDECL26(Noop) (ARMul_State *state, ARMword instr) {
}
