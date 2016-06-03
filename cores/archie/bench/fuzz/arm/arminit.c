/*  arminit.c -- ARMulator initialization:  ARM6 Instruction Emulator.
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

#include <stdio.h>
#include "armdefs.h"
#include "armemu.h"

#define MEMTOP 8*1024*1024

ARMword ARMul_LoadWordS(ARMul_State *state,ARMword address)
{
	if (address < MEMTOP)
	{
		return state->Memory[address>>2];
	}
	else 
	{
		return 0;
	}
}

void ARMul_StoreWordS(ARMul_State *state,ARMword address, ARMword data)
{
	//state->Memory[address>>2] = data;
}

ARMword ARMul_LoadByte(ARMul_State *state,ARMword address)
{
	if (address < MEMTOP)
	{
		uint8_t *mem = (uint8_t *) (state->Memory);
		ARMword temp = mem[address];	
	}
	else
	{
		return 0;
	}
}

void ARMul_StoreByte(ARMul_State *state, ARMword address, ARMword data)
{
	if (address < MEMTOP)
	{
		uint8_t *mem = (uint8_t *) (state->Memory);
		//mem[address] = (uint8_t) data;	
	}
}

ARMword ARMul_SwapWord(ARMul_State *state, ARMword address, ARMword data)
{
	ARMword temp = 0;

	if (address < MEMTOP)
	{
		temp = state->Memory[address>>2];
		//state->Memory[address>>2] = data;
	}

	return temp;
}

ARMword ARMul_SwapByte(ARMul_State *state, ARMword address, ARMword data)
{
	ARMword temp = 0;
	
	if (address < MEMTOP)
	{
		uint8_t *mem = (uint8_t *) (state->Memory);
		temp = mem[address];
		//mem[address] = (uint8_t) data;
	}
	
	return temp;
}




/***************************************************************************\
*                 Definitions for the emulator architecture                 *
\***************************************************************************/

uint_fast8_t ARMul_MultTable[32] = { 1,  2,  2,  3,  3,  4,  4,  5,
                                     5,  6,  6,  7,  7,  8,  8,  9,
                                     9, 10, 10, 11, 11, 12, 12, 13,
                                    13, 14, 14, 15, 15, 16, 16, 16};

#ifdef ARMUL_USE_IMMEDTABLE
ARMword ARMul_ImmedTable[4096]; /* immediate DP LHS values */
#endif
uint_fast8_t ARMul_BitList[256]; /* number of bits in a byte table */

uint_fast16_t ARMul_CCTable[16];

/***************************************************************************\
*         Call this routine once to set up the emulator's tables.           *
\***************************************************************************/

void ARMul_EmulateInit(void) {
  unsigned int i, j;

#ifdef ARMUL_USE_IMMEDTABLE
  for (i = 0; i < 4096; i++) { /* the values of 12 bit dp rhs's */
    ARMul_ImmedTable[i] = ROTATER(i & 0xffL,(i >> 7L) & 0x1eL);
  }
#endif

  for (i = 0; i < 256; ARMul_BitList[i++] = 0 ); /* how many bits in LSM */
  for (j = 1; j < 256; j <<= 1)
    for (i = 0; i < 256; i++)
      if ((i & j) > 0 )
         ARMul_BitList[i]++;

  for (i = 0; i < 256; i++)
    ARMul_BitList[i] *= 4; /* you always need 4 times these values */

#define V ((i&1)!=0)
#define C ((i&2)!=0)
#define Z ((i&4)!=0)
#define N ((i&8)!=0)
#define COMPUTE(CC,TST) ARMul_CCTable[CC] = 0; for(i=0;i<16;i++) if(TST) ARMul_CCTable[CC] |= 1<<i;
  COMPUTE(EQ,Z)
  COMPUTE(NE,!Z)
  COMPUTE(CS,C)
  COMPUTE(CC,!C)
  COMPUTE(MI,N)
  COMPUTE(PL,!N)
  COMPUTE(VS,V)
  COMPUTE(VC,!V)
  COMPUTE(HI,C&&!Z)
  COMPUTE(LS,!C||Z)
  COMPUTE(GE,N==V)
  COMPUTE(LT,N!=V)
  COMPUTE(GT,!Z&&(N==V))
  COMPUTE(LE,Z||(N!=V))
  COMPUTE(AL,1)
  COMPUTE(NV,0)
#undef V
#undef C
#undef Z
#undef N
#undef COMPUTE
}


/***************************************************************************\
*            Returns a new instantiation of the ARMulator's state           *
\***************************************************************************/

ARMul_State *ARMul_NewState(void)
{ARMul_State *state;
 unsigned i, j;

 state = state_alloc(sizeof(ARMul_State));

 for (i = 0; i < 16; i++) {
    state->Reg[i] = 0;
    for (j = 0; j < 4; j++)
       state->RegBank[j][i] = 0;
    }

 state->Aborted = FALSE;
 state->InstrLimit = -1;
 ARMul_Reset(state);
 return(state);
 }

/***************************************************************************\
* Call this routine to set up the initial machine state (or perform a RESET *
\***************************************************************************/

void ARMul_Reset(ARMul_State *state)
{state->NextInstr = 0;
    state->Reg[15] = R15INTBITS | SVC26MODE;
 ARMul_R15Altered(state);
 state->Bank = SVCBANK;
 FLUSHPIPE;

 state->Exception = 0;
 state->NtransSig = (R15MODE) ? HIGH : LOW;
 state->abortSig = LOW;
 state->AbortAddr = 1;

 state->NumCycles = 0;
}


ARMword ARMul_DoProg(ARMul_State *state) {
  ARMword pc = 0;

  ARMul_Emulate26(state);
  return(pc);
}

/***************************************************************************\
* This routine causes an Abort to occur, including selecting the correct    *
* mode, register bank, and the saving of registers.  Call with the          *
* appropriate vector's memory address (0,4,8 ....)                          *
\***************************************************************************/

void ARMul_Abort(ARMul_State *state, ARMword vector) {
  ARMword temp;
  int exit_code;
  state->Aborted = FALSE;

#ifdef DEBUG
 printf("ARMul_Abort: vector=0x%x\n",vector);
#endif

  temp = state->Reg[15];

  switch (vector) {
    case ARMul_ResetV : /* RESET */
       SETABORT(R15INTBITS,SVC26MODE);
       ARMul_R15Altered(state);
       state->Reg[14] = temp;
       break;

    case ARMul_UndefinedInstrV : /* Undefined Instruction */
       SETABORT(R15IBIT,SVC26MODE);
       ARMul_R15Altered(state);
       state->Reg[14] = temp - 4;
       /*fprintf(stderr,"DAG: In ARMul_Abort: Taking undefined instruction trap R[14] being set to: 0x%08x\n",
               (unsigned int)(state->Reg[14])); */
       break;

    case ARMul_SWIV: /* Software Interrupt */
       {
         ARMword addr = (state->Reg[15]-8) & R15PCBITS;
         ARMword instr = state->Memory[addr>>2];
	 
	 // special implementation to exit a simulation.
	 if ((instr & 0x00FFFFFF) == 0x00FFFFFF)
	 {
	     state->Done = true;
	     return;
	 }
	 
	 SETABORT(R15IBIT,SVC26MODE);
         ARMul_R15Altered(state);
         state->Reg[14] = temp - 4;
       }
       break;

    case ARMul_PrefetchAbortV : /* Prefetch Abort */
       state->AbortAddr = 1;
       SETABORT(R15IBIT,SVC26MODE);
       ARMul_R15Altered(state);
       state->Reg[14] = temp - 4;
       break;

    case ARMul_DataAbortV : /* Data Abort */
       SETABORT(R15IBIT,SVC26MODE);
       ARMul_R15Altered(state);
       state->Reg[14] = temp - 4; /* the PC must have been incremented */
       break;

    case ARMul_AddrExceptnV : /* Address Exception */
       SETABORT(R15IBIT,SVC26MODE);
       ARMul_R15Altered(state);
       state->Reg[14] = temp - 4;
       break;

    case ARMul_IRQV : /* IRQ */
       SETABORT(R15IBIT,IRQ26MODE);
       ARMul_R15Altered(state);
       state->Reg[14] = temp - 4;
       break;

    case ARMul_FIQV : /* FIQ */
       SETABORT(R15INTBITS,FIQ26MODE);
       ARMul_R15Altered(state);
       state->Reg[14] = temp - 4;
       break;
  }

  ARMul_SetR15(state,R15CCINTMODE | vector);
}
