/* Modified by DAG to remove memory leak */

/*  armsupp.c -- ARMulator support code:  ARM6 Instruction Emulator.
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

#include "armdefs.h"
#include "armemu.h"

/***************************************************************************\
* Given a processor mode, this routine returns the register bank that       *
* will be accessed in that mode.                                            *
\***************************************************************************/

static ARMword ModeToBank(ARMul_State *state, ARMword mode) {
    return(mode&3);
}

/***************************************************************************\
* This routine sets the value of a register for a mode.                     *
\***************************************************************************/

void ARMul_SetReg(ARMul_State *state, unsigned mode, unsigned reg, ARMword value)
{mode &= R15MODEBITS;
 if (mode != R15MODE)
    state->RegBank[ModeToBank(state,(ARMword)mode)][reg] = value;
 else
    state->Reg[reg] = value;
}

/***************************************************************************\
* This routine returns the value of the PC, mode independently.             *
\***************************************************************************/

ARMword ARMul_GetPC(ARMul_State *state)
{
    return(R15PC);
}

/***************************************************************************\
* This routine returns the value of the PC, mode independently.             *
\***************************************************************************/

ARMword ARMul_GetNextPC(ARMul_State *state)
{
    return((state->Reg[15] + 4) & R15PCBITS);
}

/***************************************************************************\
* This routine sets the value of the PC.                                    *
\***************************************************************************/

void ARMul_SetPC(ARMul_State *state, ARMword value)
{
  state->Reg[15] = R15CCINTMODE | (value & R15PCBITS);
 FLUSHPIPE;
}

/***************************************************************************\
* This routine returns the value of register 15, mode independently.        *
\***************************************************************************/

ARMword ARMul_GetR15(ARMul_State *state)
{
    return state->Reg[15];
}

/***************************************************************************\
* This routine sets the value of Register 15.                               *
\***************************************************************************/

void ARMul_SetR15(ARMul_State *state, ARMword value)
{
  state->Reg[15] = value;
  ARMul_R15Altered(state);
 FLUSHPIPE;
}

/***************************************************************************\
* This routine updates the state of the emulator after register 15 has      *
* been changed.  Both the processor flags and register bank are updated.    *
* This routine should only be called from a 26 bit mode.                    *
\***************************************************************************/

void ARMul_R15Altered(ARMul_State *state)
{
 register ARMword mode = R15MODE;
 if (state->Bank != mode) {
    ARMul_SwitchMode(state,state->Bank,mode);
    state->NtransSig = (mode)?HIGH:LOW;
    }
}

/***************************************************************************\
* This routine controls the saving and restoring of registers across mode   *
* changes.  The regbank matrix is largely unused, only rows 13 and 14 are   *
* used across all modes, 8 to 14 are used for FIQ, all others use the USER  *
* column.  It's easier this way.  old and new parameter are modes numbers.  *
* Notice the side effect of changing the Bank variable.                     *
\***************************************************************************/

ARMword ARMul_SwitchMode(ARMul_State *state,ARMword oldmode, ARMword newmode)
{unsigned i;

 oldmode = ModeToBank(state,oldmode);
 state->Bank = ModeToBank(state,newmode);
 if (oldmode != state->Bank) { /* really need to do it */
    switch (oldmode) { /* save away the old registers */
       case USERBANK  :
       case IRQBANK   :
       case SVCBANK   : if (state->Bank == FIQBANK)
                           for (i = 8; i < 13; i++)
                              state->RegBank[USERBANK][i] = state->Reg[i];
                        state->RegBank[oldmode][13] = state->Reg[13];
                        state->RegBank[oldmode][14] = state->Reg[14];
                        break;
       case FIQBANK   : for (i = 8; i < 15; i++)
                           state->RegBank[FIQBANK][i] = state->Reg[i];
                        break;

       }
    switch (state->Bank) { /* restore the new registers */
       case USERBANK  :
       case IRQBANK   :
       case SVCBANK   : if (oldmode == FIQBANK)
                           for (i = 8; i < 13; i++)
                              state->Reg[i] = state->RegBank[USERBANK][i];
                        state->Reg[13] = state->RegBank[state->Bank][13];
                        state->Reg[14] = state->RegBank[state->Bank][14];
                        break;
       case FIQBANK  : for (i = 8; i < 15; i++)
                           state->Reg[i] = state->RegBank[FIQBANK][i];
                        break;
       } /* switch */
    } /* if */
    return(newmode);
}

/***************************************************************************\
* Returns the register number of the nth register in a reg list.            *
\***************************************************************************/

unsigned ARMul_NthReg(ARMword instr, unsigned number)
{unsigned bit, upto;

 for (bit = 0, upto = 0; upto <= number; bit++)
    if (BIT(bit)) upto++;
 return(bit - 1);
}

/***************************************************************************\
* This function does the work of generating the addresses used in an        *
* LDC instruction.  The code here is always post-indexed, it's up to the    *
* caller to get the input address correct and to handle base register       *
* modification. It also handles the Busy-Waiting.                           *
\***************************************************************************/

void ARMul_LDC(ARMul_State *state,ARMword instr,ARMword address)
{
 unsigned cpab;
 ARMword data;

 UNDEF_LSCPCBaseWb;
 if (ADDREXCEPT(address)) {
    INTERNALABORT(address);
    }
 cpab = (state->LDC[CPNum])(state,ARMul_FIRST,instr,0);
 while (cpab == ARMul_BUSY) {
    ARMul_Icycles(state,1);
    if (IntPending(state)) {
       cpab = (state->LDC[CPNum])(state,ARMul_INTERRUPT,instr,0);
       return;
       }
    else
       cpab = (state->LDC[CPNum])(state,ARMul_BUSY,instr,0);
    }
 if (cpab == ARMul_CANT) {
    CPTAKEABORT;
    return;
    }
 cpab = (state->LDC[CPNum])(state,ARMul_TRANSFER,instr,0);
 data = ARMul_LoadWordN(state,address);
 BUSUSEDINCPCN;
 if (BIT(21))
    LSBase = state->Base;
 cpab = (state->LDC[CPNum])(state,ARMul_DATA,instr,data);
 while (cpab == ARMul_INC) {
    address += 4;
    data = ARMul_LoadWordN(state,address);
    cpab = (state->LDC[CPNum])(state,ARMul_DATA,instr,data);
    }
 if (state->abortSig || state->Aborted) {
    TAKEABORT;
    }
 }

/***************************************************************************\
* This function does the work of generating the addresses used in an        *
* STC instruction.  The code here is always post-indexed, it's up to the    *
* caller to get the input address correct and to handle base register       *
* modification. It also handles the Busy-Waiting.                           *
\***************************************************************************/

void ARMul_STC(ARMul_State *state,ARMword instr,ARMword address)
{unsigned cpab;
 ARMword data;

 UNDEF_LSCPCBaseWb;
 if (ADDREXCEPT(address)) {
    INTERNALABORT(address);
    }
 cpab = (state->STC[CPNum])(state,ARMul_FIRST,instr,&data);
 while (cpab == ARMul_BUSY) {
    ARMul_Icycles(state,1);
    if (IntPending(state)) {
       cpab = (state->STC[CPNum])(state,ARMul_INTERRUPT,instr,0);
       return;
       }
    else
       cpab = (state->STC[CPNum])(state,ARMul_BUSY,instr,&data);
    }
 if (cpab == ARMul_CANT) {
    CPTAKEABORT;
    return;
    }
 if (ADDREXCEPT(address) ) {
    INTERNALABORT(address);
    }
 BUSUSEDINCPCN;
 if (BIT(21))
    LSBase = state->Base;
 cpab = (state->STC[CPNum])(state,ARMul_DATA,instr,&data);
 ARMul_StoreWordN(state,address,data);
 while (cpab == ARMul_INC) {
    address += 4;
    cpab = (state->STC[CPNum])(state,ARMul_DATA,instr,&data);
    ARMul_StoreWordN(state,address,data);
    }
 if (state->abortSig || state->Aborted) {
    TAKEABORT;
    }
 }

/***************************************************************************\
*        This function does the Busy-Waiting for an MCR instruction.        *
\***************************************************************************/

void ARMul_MCR(ARMul_State *state,ARMword instr, ARMword source)
{unsigned cpab;

 cpab = (state->MCR[CPNum])(state,ARMul_FIRST,instr,source);
 while (cpab == ARMul_BUSY) {
    ARMul_Icycles(state,1);
    if (IntPending(state)) {
       cpab = (state->MCR[CPNum])(state,ARMul_INTERRUPT,instr,0);
       return;
       }
    else
       cpab = (state->MCR[CPNum])(state,ARMul_BUSY,instr,source);
    }
 if (cpab == ARMul_CANT)
    ARMul_Abort(state,ARMul_UndefinedInstrV);
 else {
    BUSUSEDINCPCN;
    ARMul_Icycles(state,1); /* Should be C */
    }
 }

/***************************************************************************\
*        This function does the Busy-Waiting for an MRC instruction.        *
\***************************************************************************/

ARMword ARMul_MRC(ARMul_State *state,ARMword instr)
{unsigned cpab;
 ARMword result = 0;

 cpab = (state->MRC[CPNum])(state,ARMul_FIRST,instr,&result);
 while (cpab == ARMul_BUSY) {
    ARMul_Icycles(state,1);
    if (IntPending(state)) {
       cpab = (state->MRC[CPNum])(state,ARMul_INTERRUPT,instr,0);
       return(0);
       }
    else
       cpab = (state->MRC[CPNum])(state,ARMul_BUSY,instr,&result);
    }
 if (cpab == ARMul_CANT) {
    ARMul_Abort(state,ARMul_UndefinedInstrV);
    result = ECC; /* Parent will destroy the flags otherwise */
    }
 else {
    BUSUSEDINCPCN;
    ARMul_Icycles(state,1);
    ARMul_Icycles(state,1);
    }
 return(result);
}

/***************************************************************************\
*        This function does the Busy-Waiting for an CDP instruction.        *
\***************************************************************************/

void ARMul_CDP(ARMul_State *state,ARMword instr)
{unsigned cpab;

 cpab = (state->CDP[CPNum])(state,ARMul_FIRST,instr);
 while (cpab == ARMul_BUSY) {
    ARMul_Icycles(state,1);
    if (IntPending(state)) {
       cpab = (state->CDP[CPNum])(state,ARMul_INTERRUPT,instr);
       return;
       }
    else
       cpab = (state->CDP[CPNum])(state,ARMul_BUSY,instr);
    }
 if (cpab == ARMul_CANT)
    ARMul_Abort(state,ARMul_UndefinedInstrV);
 else
    BUSUSEDN;
}

/***************************************************************************\
*      This function handles Undefined instructions, as CP instruction      *
\***************************************************************************/

void ARMul_UndefInstr(ARMul_State *state,ARMword instr)
{
 ARMul_Abort(state,ARMul_UndefinedInstrV);
}

/***************************************************************************\
*           Return TRUE if an interrupt is pending, FALSE otherwise.        *
\***************************************************************************/

unsigned IntPending(ARMul_State *state)
{
 ARMword excep = state->Exception & ~state->Reg[15];
 if(!excep) { /* anything? */
   return(FALSE);
 } else if(excep & Exception_FIQ) { /* FIQ? */
   ARMul_Abort(state,ARMul_FIQV);
   return(TRUE);
 } else { /* Must be IRQ */
   ARMul_Abort(state,ARMul_IRQV);
   return(TRUE);
 }
}

/***************************************************************************\
*               Align a word access to a non word boundary                  *
\***************************************************************************/

ARMword ARMul_Align(ARMul_State *state, ARMword address, ARMword data)
{/* this code assumes the address is really unaligned,
    as a shift by 32 is undefined in C */

 address = (address & 3) << 3; /* get the word address */
 return( ( data >> address) | (data << (32 - address)) ); /* rot right */
}

