/*  armemu.h -- ARMulator emulation macros:  ARM6 Instruction Emulator.
    Copyright (C) 1994 Advanced RISC Machines Ltd.

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA. */

/* Control the use of the immediate constant table (ARMul_ImmedTable)
   On ARM we don't want to use it, as it's about 8% slower than using the barrel shifter directly
   Other platforms with decent a rotate right instruction may want to avoid using the table too
*/

#ifndef __arm__
#ifndef __PPC__
#define ARMUL_USE_IMMEDTABLE
#endif
#endif

#include <stdint.h>
#include <stdbool.h>

#define READMEM(s,a) state->Memory[a>>2];

/***************************************************************************\
*                           Condition code values                           *
\***************************************************************************/

#define EQ 0
#define NE 1
#define CS 2
#define CC 3
#define MI 4
#define PL 5
#define VS 6
#define VC 7
#define HI 8
#define LS 9
#define GE 10
#define LT 11
#define GT 12
#define LE 13
#define AL 14
#define NV 15

/***************************************************************************\
*                               Shift Opcodes                               *
\***************************************************************************/

#define LSL 0
#define LSR 1
#define ASR 2
#define ROR 3

/***************************************************************************\
*               Macros to twiddle the status flags and mode                 *
\***************************************************************************/

#define NBIT (UINT32_C(1) << 31)
#define ZBIT (UINT32_C(1) << 30)
#define CBIT (UINT32_C(1) << 29)
#define VBIT (UINT32_C(1) << 28)
#define R15IBIT (UINT32_C(1) << 27)
#define R15FBIT (UINT32_C(1) << 26)
#define R15IFBITS (UINT32_C(3) << 26)

#define POS(i) ( (~(i)) >> 31 )
#define NEG(i) ( (i) >> 31 )

#define NFLAG ((state->Reg[15]>>31)&1)
#define SETN state->Reg[15] |= NBIT
#define CLEARN state->Reg[15] &= ~NBIT
#ifndef __arm__
#define ASSIGNN(res) state->Reg[15] = (res?state->Reg[15]|NBIT:state->Reg[15]&~NBIT)
#else
#define ASSIGNN(res) inlASSIGN(state,res,NBIT)
static inline void inlASSIGN(ARMul_State *state,ARMword res,ARMword bit)
{
	ARMword temp = state->Reg[15];
	if(res)
		temp |= bit;
	else
		temp &= ~bit;
	state->Reg[15] = temp;
}
#endif

#define ZFLAG ((state->Reg[15]>>30)&1)
#define SETZ state->Reg[15] |= ZBIT
#define CLEARZ state->Reg[15] &= ~ZBIT
#ifndef __arm__
#define ASSIGNZ(res) state->Reg[15] = (res?state->Reg[15]|ZBIT:state->Reg[15]&~ZBIT)
#else
#define ASSIGNZ(res) inlASSIGN(state,res,ZBIT)
#endif

#define CFLAG ((state->Reg[15]>>29)&1)
#define SETC state->Reg[15] |= CBIT
#define CLEARC state->Reg[15] &= ~CBIT
#ifndef __arm__
#define ASSIGNC(res) state->Reg[15] = (res?state->Reg[15]|CBIT:state->Reg[15]&~CBIT)
#else
#define ASSIGNC(res) inlASSIGN(state,res,CBIT)
#endif

#define VFLAG ((state->Reg[15]>>28)&1)
#define SETV state->Reg[15] |= VBIT
#define CLEARV state->Reg[15] &= ~VBIT
#ifndef __arm__
#define ASSIGNV(res) state->Reg[15] = (res?state->Reg[15]|VBIT:state->Reg[15]&~VBIT)
#else
#define ASSIGNV(res) inlASSIGN(state,res,VBIT)
#endif

#define CLEARNCV state->Reg[15] &= ~(NBIT|CBIT|VBIT)
#define CLEARCV state->Reg[15] &= ~(CBIT|VBIT)

#define IFLAG ((state->Reg[15]>>27)&1)
#define FFLAG ((state->Reg[15]>>26)&1)
#define IFFLAGS ((state->Reg[15]>>26)&3)
#define ASSIGNR15INT(res) state->Reg[15] = (state->Reg[15]&~R15IFBITS) | ((res)&R15IFBITS)


#define CCBITS (UINT32_C(0xf0000000))
#define R15INTBITS (UINT32_C(3) << 26)
#define R15PCBITS (UINT32_C(0x03fffffc))
#define R15PCMODEBITS (UINT32_C(0x03ffffff))
#define R15MODEBITS (UINT32_C(0x3))

#define PCMASK R15PCBITS
#define PCWRAP(pc) ((pc) & R15PCBITS)
#define PC (state->Reg[15] & PCMASK)
#define R15CCINTMODE (state->Reg[15] & (CCBITS | R15INTBITS | R15MODEBITS))
#define R15INT (state->Reg[15] & R15INTBITS)
#define R15INTPC (state->Reg[15] & (R15INTBITS | R15PCBITS))
#define R15INTPCMODE (state->Reg[15] & (R15INTBITS | R15PCBITS | R15MODEBITS))
#define R15INTMODE (state->Reg[15] & (R15INTBITS | R15MODEBITS))
#define R15PC (state->Reg[15] & R15PCBITS)
#define R15PCMODE (state->Reg[15] & (R15PCBITS | R15MODEBITS))
#define R15MODE (state->Reg[15] & R15MODEBITS)

#define ECC (state->Reg[15] & CCBITS)
#define ER15INT (state->Reg[15] & R15IFBITS)
#define EMODE (state->Reg[15] & R15MODEBITS)

#define SETR15PSR(s) if (R15MODE == USER26MODE) { \
                        state->Reg[15] = ((s) & CCBITS) | R15INTPCMODE; \
                        } \
                     else { \
                        state->Reg[15] = R15PC | ((s) & (CCBITS | R15INTBITS | R15MODEBITS)); \
                        ARMul_R15Altered(state); \
                        }
#define SETABORT(i,m) state->Reg[15] = (state->Reg[15]&~R15MODEBITS) | (i) | (m)
#define SETPC(pc) state->Reg[15] = (state->Reg[15]&~R15PCBITS)|((pc)&R15PCBITS)

/* Assumed that 'amt' is a multiple of 4 */
#ifdef ARMUL_USE_IMMEDTABLE
/* Simple implementation for platforms without a rotate left/right instruction */
#define INCPCAMT(amt) SETPC(state->Reg[15]+(amt))
#else
/* Using ROTATER should reduce the instruction count a bit */
#define INCPCAMT(amt) do { \
                        ARMword temp=state->Reg[15]; \
                        temp = ROTATER(temp,26)+((amt)<<6); \
                        state->Reg[15] = ROTATER(temp,6); \
                      } while(0)
#endif

#define LEGALADDR (UINT32_C(0x03ffffff))
#define ADDREXCEPT(address) (address >= (LEGALADDR+1))

#define INTERNALABORT(address) state->Aborted = ARMul_AddrExceptnV;

#define TAKEABORT if (state->Aborted == ARMul_AddrExceptnV) \
                     ARMul_Abort(state,ARMul_AddrExceptnV); \
                  else \
                     ARMul_Abort(state,ARMul_DataAbortV)
#define CPTAKEABORT if (!state->Aborted) \
                       ARMul_Abort(state,ARMul_UndefinedInstrV); \
                    else if (state->Aborted == ARMul_AddrExceptnV) \
                       ARMul_Abort(state,ARMul_AddrExceptnV); \
                    else \
                       ARMul_Abort(state,ARMul_DataAbortV)


/***************************************************************************\
*               Different ways to start the next instruction                *
\***************************************************************************/

#define NORMALCYCLE state->NextInstr = NORMAL
#define BUSUSEDN ((void)0) /* the next fetch will be an N cycle */
#define BUSUSEDINCPCS state->Reg[15] += 4; /* a standard PC inc and an S cycle */ \
                      state->NextInstr |= PCINCED
#define BUSUSEDINCPCN state->Reg[15] += 4; /* a standard PC inc and an N cycle */ \
                      state->NextInstr |= PCINCED
#define INCPC state->Reg[15] += 4; /* a standard PC inc */ \
                      state->NextInstr |= PCINCED
#define FLUSHPIPE state->NextInstr |= PRIMEPIPE

/***************************************************************************\
*                          Cycle based emulation                            *
\***************************************************************************/

#define OUTPUTCP(i,a,b)
#define NCYCLE
#define SCYCLE
#define ICYCLE
#define CCYCLE
#define NEXTCYCLE(c)

/***************************************************************************\
*                 States of the cycle based state machine                   *
\***************************************************************************/


/***************************************************************************\
*                 Macros to extract parts of instructions                   *
\***************************************************************************/

#define DESTReg (BITS(12,15))
#define LHSReg (BITS(16,19))
#define RHSReg (BITS(0,3))

#define DEST (state->Reg[DESTReg])

#ifndef __arm__ /* GCC makes a mess of this ternary op, much better to go with the hand-holding approach to ensure there's only one LDR */
#define LHS ((LHSReg == 15) ? R15PC : (state->Reg[LHSReg]) )
#else
#define LHS inlLHS(state,LHSReg)
static inline ARMword inlLHS(ARMul_State *state,ARMword r)
{
	ARMword lhs = state->Reg[r];
	if(r == 15)
		lhs &= R15PCBITS;
	return lhs;
}
#endif

#define MULDESTReg (BITS(16,19))
#define MULLHSReg (BITS(0,3))
#define MULRHSReg (BITS(8,11))
#define MULACCReg (BITS(12,15))

#ifdef ARMUL_USE_IMMEDTABLE
#define DPImmRHS (ARMul_ImmedTable[BITS(0,11)])
#define DPSImmRHS temp = BITS(0,11); \
                  rhs = ARMul_ImmedTable[temp]; \
                  if (temp > 255) /* there was a shift */ \
                     ASSIGNC(rhs >> 31);
#else
#define DPImmRHS (ROTATER(BITS(0,7),BITS(8,11)<<1))
#define DPSImmRHS temp = BITS(0,11); \
                  rhs = ROTATER(BITS(0,7),BITS(8,11)<<1); \
                  if (temp > 255) /* there was a shift */ \
                     ASSIGNC(rhs >> 31);
#endif

#define DPRegRHS ((BITS(0,11)<15) ? state->Reg[RHSReg] \
                                  : GetDPRegRHS(state, instr))
#define DPSRegRHS ((BITS(0,11)<15) ? state->Reg[RHSReg] \
                                   : GetDPSRegRHS(state, instr))

#define LSBase state->Reg[LHSReg]
#define LSImmRHS (BITS(0,11))

#define LSRegRHS ((BITS(0,11)<15) ? state->Reg[RHSReg] \
                                  : GetLSRegRHS(state, instr))

#define LSMNumRegs ((ARMword)ARMul_BitList[BITS(0,7)] + \
                    (ARMword)ARMul_BitList[BITS(8,15)] )
#define LSMBaseFirst ((LHSReg == 0 && BIT(0)) || \
                      (BIT(LHSReg) && BITS(0,LHSReg-1) == 0))

#define SWAPSRC (state->Reg[RHSReg])

#define LSCOff (BITS(0,7) << 2)
#define CPNum BITS(8,11)

/***************************************************************************\
*                    Macro to rotate n right by b bits                      *
\***************************************************************************/

#define ROTATER(n,b) (((n)>>(b))|((n)<<(32-(b))))

/***************************************************************************\
*                 Macros to store results of instructions                   *
\***************************************************************************/

#define WRITEDEST(d) {/*fprintf(stderr,"WRITEDEST: %d=0x%08x\n",DESTReg,d);*/\
                      if (DESTReg==15) \
                        WriteR15(state, d); \
                     else \
                          DEST = d;\
                      }

#define WRITEDESTNORM(d) {/*fprintf(stderr,"WRITEDEST: %d=0x%08x\n",DESTReg,d);*/ DEST = d;}

#define WRITEDESTPC(d) {/*fprintf(stderr,"WRITEDEST: %d=0x%08x\n", 15, d);*/ WriteR15(state, d);}

#define WRITESDEST(d) { /*fprintf(stderr,"WRITESDEST: %d=0x%08x\n",DESTReg,d);*/\
                      if (DESTReg == 15) \
                         WriteSR15(state, d); \
                      else { \
                         DEST = d; \
                         ARMul_NegZero(state, d); \
                         };\
                      }

#define WRITESDESTNORM(d) {DEST = d; \
                         ARMul_NegZero(state, d); }

#define WRITESDESTPC(d) WriteSR15(state, d)

#define LOADMULT(instr,address,wb) LoadMult(state,instr,address,wb)
#define LOADSMULT(instr,address,wb) LoadSMult(state,instr,address,wb)
#define STOREMULT(instr,address,wb) StoreMult(state,instr,address,wb)
#define STORESMULT(instr,address,wb) StoreSMult(state,instr,address,wb)

/***************************************************************************\
*                      Stuff that is shared across modes                    *
\***************************************************************************/

void ARMul_Emulate26(ARMul_State *state);
void ARMul_Icycles(ARMul_State *state,unsigned number);

extern uint_fast8_t ARMul_MultTable[]; /* Number of I cycles for a mult */
#ifdef ARMUL_USE_IMMEDTABLE
extern ARMword ARMul_ImmedTable[]; /* Immediate DP LHS values */
#endif
extern uint_fast8_t ARMul_BitList[];       /* Number of bits in a byte table */
extern uint_fast16_t ARMul_CCTable[16];
#define ARMul_CCCheck(instr,psr) (ARMul_CCTable[instr>>28] & (1<<(psr>>28)))

unsigned ARMul_NthReg(ARMword instr,unsigned number);
void ARMul_R15Altered(ARMul_State *state);
ARMword ARMul_SwitchMode(ARMul_State *state,ARMword oldmode, ARMword newmode);
unsigned ARMul_NthReg(ARMword instr, unsigned number);
void ARMul_LDC(ARMul_State *state,ARMword instr,ARMword address);
void ARMul_STC(ARMul_State *state,ARMword instr,ARMword address);
void ARMul_MCR(ARMul_State *state,ARMword instr, ARMword source);
ARMword ARMul_MRC(ARMul_State *state,ARMword instr);
void ARMul_CDP(ARMul_State *state,ARMword instr);
unsigned IntPending(ARMul_State *state);
ARMword ARMul_Align(ARMul_State *state, ARMword address, ARMword data);


/***************************************************************************\
*                               ARM Support                                 *
\***************************************************************************/

void ARMul_UndefInstr(ARMul_State *state,ARMword instr);

/* An estimate of how many cycles the host is executing per second */
extern uint32_t ARMul_EmuRate;

/* Reset the EmuRate code, to cope with situations where the emulator has just been resumed after being suspended for a period of time (i.e. > 1 second) */
void EmuRate_Reset(ARMul_State *state);

/* Update the EmuRate value. Note: Manipulates event queue! */
void EmuRate_Update(ARMul_State *state);

/***************************************************************************\
*                      Macros to scrutinise instructions                    *
\***************************************************************************/


#define UNDEF_Test
#define UNDEF_Shift
#define UNDEF_MSRPC
#define UNDEF_MRSPC
#define UNDEF_MULPCDest
#define UNDEF_MULDestEQOp1
#define UNDEF_LSRBPC
#define UNDEF_LSRBaseEQOffWb
#define UNDEF_LSRBaseEQDestWb
#define UNDEF_LSRPCBaseWb
#define UNDEF_LSRPCOffWb
#define UNDEF_LSMNoRegs
#define UNDEF_LSMPCBase
#define UNDEF_LSMUserBankWb
#define UNDEF_LSMBaseInListWb
#define UNDEF_SWPPC
#define UNDEF_CoProHS
#define UNDEF_MCRPC
#define UNDEF_LSCPCBaseWb
#define UNDEF_UndefNotBounced
#define UNDEF_ShortInt
#define UNDEF_IllegalMode
#define UNDEF_Prog32SigChange
#define UNDEF_Data32SigChange

/* ------------------- inlined higher-level memory funcs ---------------------- */

ARMword ARMul_LoadWordS(ARMul_State *state,ARMword address);
ARMword ARMul_LoadByte(ARMul_State *state,ARMword address);
void ARMul_StoreWordS(ARMul_State *state, ARMword address, ARMword data);
void ARMul_StoreByte(ARMul_State *state, ARMword address, ARMword data);
ARMword ARMul_SwapWord(ARMul_State *state, ARMword address, ARMword data);
ARMword ARMul_SwapByte(ARMul_State *state, ARMword address, ARMword data);

/**
 * ARMul_LoadWordN
` *
 * Load Word, Non Sequential Cycle
 *
 * @param state
 * @param address
 * @returns
 */
#define ARMul_LoadWordN ARMul_LoadWordS /* These were 100% equivalent in the original implementation! */

/**
 * ARMul_StoreWordN
 *
 * Store Word, Non Sequential Cycle
 *
 * @param state
 * @param address
 * @param data
 */
#define ARMul_StoreWordN ARMul_StoreWordS /* These were 100% equivalent in the original implementation! */

