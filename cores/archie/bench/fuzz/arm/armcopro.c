/*  armcopro.c -- co-processor interface:  ARM6 Instruction Emulator.
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
#include "cp15.h"

#include "armcopro.h"

/***************************************************************************\
*                            Dummy Co-processors                            *
\***************************************************************************/

static unsigned NoCoPro3R(ARMul_State *state,unsigned,ARMword);
static unsigned NoCoPro4R(ARMul_State *state,unsigned,ARMword,ARMword);
static unsigned NoCoPro4W(ARMul_State *state,unsigned,ARMword,ARMword *);

/***************************************************************************\
*                Define Co-Processor instruction handlers here              *
\***************************************************************************/


/***************************************************************************\
*         Install co-processor instruction handlers in this routine         *
\***************************************************************************/

unsigned ARMul_CoProInit(ARMul_State *state, ArmProcessorType ptype) {
  unsigned int i;

  /* initialise them all first */
  for (i = 0; i < 16; i++) {
    ARMul_CoProDetach(state, i);
  }

 /* Install CoPro Instruction handlers here
    The format is
    ARMul_CoProAttach(state, CP Number, Init routine, Exit routine
                      LDC routine, STC routine, MRC routine, MCR routine,
                      CDP routine, Read Reg routine, Write Reg routine);
   */

    /* Add in the ARM3 processor CPU control coprocessor if the user
       wants it */
    if(Processor_ARM3 == ptype) {
      ARMul_CoProAttach(state, 15, ARM3_Initialise, NULL,
                        NULL, NULL, ARM3_MRCs, ARM3_MCRs,
                        NULL, ARM3_RegisterRead, ARM3_RegisterWrite);
    }

    /* No handlers below here */

    for (i = 0; i < 16; i++) {
      /* Call all the initialisation routines */
     if (state->CPInit[i]) {
       (state->CPInit[i])(state);
     }
   }
   return(TRUE);
}


/***************************************************************************\
*         Install co-processor finalisation routines in this routine        *
\***************************************************************************/

void ARMul_CoProExit(ARMul_State *state) {
  unsigned int i;

  for (i = 0; i < 16; i++)
    if (state->CPExit[i])
      (state->CPExit[i])(state);
  for (i = 0; i < 16; i++) /* Detach all handlers */
     ARMul_CoProDetach(state, i);
}

/***************************************************************************\
*              Routines to hook Co-processors into ARMulator                 *
\***************************************************************************/

void ARMul_CoProAttach(ARMul_State *state, unsigned number,
                       ARMul_CPInits *init,  ARMul_CPExits *exits,
                       ARMul_LDCs *ldc,  ARMul_STCs *stc,
                       ARMul_MRCs *mrc,  ARMul_MCRs *mcr,  ARMul_CDPs *cdp,
                       ARMul_CPReads *reads, ARMul_CPWrites *writes)
{if (init != NULL)
    state->CPInit[number] = init;
 if (exits != NULL)
    state->CPExit[number] = exits;
 if (ldc != NULL)
    state->LDC[number] = ldc;
 if (stc != NULL)
    state->STC[number] = stc;
 if (mrc != NULL)
    state->MRC[number] = mrc;
 if (mcr != NULL)
    state->MCR[number] = mcr;
 if (cdp != NULL)
    state->CDP[number] = cdp;
 if (reads != NULL)
    state->CPRead[number] = reads;
 if (writes != NULL)
    state->CPWrite[number] = writes;
}

void ARMul_CoProDetach(ARMul_State *state, unsigned number)
{ARMul_CoProAttach(state, number, NULL, NULL,
                   NoCoPro4R, NoCoPro4W, NoCoPro4W, NoCoPro4R,
                   NoCoPro3R, NULL, NULL);
 state->CPInit[number] = NULL;
 state->CPExit[number] = NULL;
 state->CPRead[number] = NULL;
 state->CPWrite[number] = NULL;
}

/***************************************************************************\
*         There is no CoPro around, so Undefined Instruction trap           *
\***************************************************************************/

static unsigned NoCoPro3R(ARMul_State *state, unsigned a, ARMword b)
{
  state = state;
  a = a;
  b = b;

  return(ARMul_CANT);
}

static unsigned NoCoPro4R(ARMul_State *state, unsigned a, ARMword b, ARMword c)
{
  state = state;
  a = a;
  b = b;
  c = c;

  return(ARMul_CANT);
}

static unsigned NoCoPro4W(ARMul_State *state, unsigned a, ARMword b, ARMword *c)
{
  state = state;
  a = a;
  b = b;
  c = c;

  return(ARMul_CANT);
}
