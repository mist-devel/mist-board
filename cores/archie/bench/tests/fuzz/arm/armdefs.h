/*  armdefs.h -- ARMulator common definitions:  ARM6 Instruction Emulator.
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

/* DAG - added header recursion tests */
#ifndef ARMDEFS_HEADER
#define ARMDEFS_HEADER

#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <stdint.h>
#include <stdbool.h>

typedef uint32_t ARMword; /* must be 32 bits wide */

typedef struct ARMul_State ARMul_State;
extern ARMul_State statestr;

#define FALSE 0
#define TRUE 1
#define LOW 0
#define HIGH 1

#define LATEABTSIG LOW /* TODO - is this correct? */

#define MIN(a,b) ((a)<(b)?(a):(b))
#define MAX(a,b) ((a)>(b)?(a):(b))

#define UPDATEBLOCKSIZE 256

/***************************************************************************\
*                   Macros to extract instruction fields                    *
\***************************************************************************/

#define BIT(n) ( (ARMword)(instr>>(n))&1)   /* bit n of instruction */
#define BITS(m,n) ( (ARMword)(instr<<(31-(n))) >> ((31-(n))+(m)) ) /* bits m to n of instr */
#define TOPBITS(n) (instr >> (n)) /* bits 31 to n of instr */

/***************************************************************************\
*                      The hardware vector addresses                        *
\***************************************************************************/

#define ARMResetV 0L
#define ARMUndefinedInstrV 4L
#define ARMSWIV 8L
#define ARMPrefetchAbortV 12L
#define ARMDataAbortV 16L
#define ARMAddrExceptnV 20L
#define ARMIRQV 24L
#define ARMFIQV 28L
#define ARMErrorV 32L /* This is an offset, not an address ! */

#define ARMul_ResetV ARMResetV
#define ARMul_UndefinedInstrV ARMUndefinedInstrV
#define ARMul_SWIV ARMSWIV
#define ARMul_PrefetchAbortV ARMPrefetchAbortV
#define ARMul_DataAbortV ARMDataAbortV
#define ARMul_AddrExceptnV ARMAddrExceptnV
#define ARMul_IRQV ARMIRQV
#define ARMul_FIQV ARMFIQV

/***************************************************************************\
*                          Mode and Bank Constants                          *
\***************************************************************************/

#define USER26MODE 0L
#define FIQ26MODE 1L
#define IRQ26MODE 2L
#define SVC26MODE 3L

#define USERBANK USER26MODE
#define FIQBANK FIQ26MODE
#define IRQBANK IRQ26MODE
#define SVCBANK SVC26MODE

/***************************************************************************\
*                          Fastmap definitions                              *
\***************************************************************************/

/* The fast map encodes the page access flags, memory pointer, and read/write
   function pointers into just two words of data (8 bytes on 32bit platforms,
   16 bytes on 64bit)
   The first word contains the access flags and memory pointer
   The second word contains the read/write func pointer (combined function
   under the assumption that MMIO read/write will be infrequent) 
*/

#ifndef FASTMAP_64
#ifdef __LP64__
#define FASTMAP_64
#endif
#endif

typedef intptr_t FastMapInt;
typedef uintptr_t FastMapUInt;

#ifdef FASTMAP_64
#define FASTMAP_FLAG(X) (((FastMapUInt)(X))<<56) /* Shift a byte to the top byte of the word */
#else
#define FASTMAP_FLAG(X) (((FastMapUInt)(X))<<24) /* Shift a byte to the top byte of the word */
#endif

#define FASTMAP_SIZE (0x4000000/4096)

#define FASTMAP_R_FUNC FASTMAP_FLAG(0x80) /* Use function for reading */
#define FASTMAP_W_FUNC FASTMAP_FLAG(0x40) /* Use function for writing */
#define FASTMAP_R_SVC  FASTMAP_FLAG(0x20) /* Page has SVC read access */
#define FASTMAP_W_SVC  FASTMAP_FLAG(0x10) /* Page has SVC write access */
#define FASTMAP_R_OS   FASTMAP_FLAG(0x08) /* Page has OS read access */
#define FASTMAP_W_OS   FASTMAP_FLAG(0x04) /* Page has OS write access */
#define FASTMAP_R_USR  FASTMAP_FLAG(0x02) /* Page has USR read access */
#define FASTMAP_W_USR  FASTMAP_FLAG(0x01) /* Page has USR write access */

#define FASTMAP_MODE_USR FASTMAP_FLAG(0x02) /* We are in user mode */
#define FASTMAP_MODE_OS  FASTMAP_FLAG(0x08) /* The OS flag is set in the control register */
#define FASTMAP_MODE_SVC FASTMAP_FLAG(0x20) /* We are in SVC mode */
#define FASTMAP_MODE_MBO FASTMAP_FLAG(0x80) /* Must be one! */

#define FASTMAP_ACCESSFUNC_WRITE       0x01UL
#define FASTMAP_ACCESSFUNC_BYTE        0x02UL /* Only relevant for writes */
#define FASTMAP_ACCESSFUNC_STATECHANGE 0x04UL /* Only relevant for writes */

#define FASTMAP_CLOBBEREDFUNC 0 /* Value written when a func gets clobbered */

typedef FastMapInt FastMapRes; /* Result of a DecodeRead/DecodeWrite function */

typedef ARMword (*FastMapAccessFunc)(ARMul_State *state,ARMword addr,ARMword data,ARMword flags);

typedef struct {
  FastMapUInt FlagsAndData;
  FastMapAccessFunc AccessFunc;
} FastMapEntry;

/***************************************************************************\
*                               Event queue                                 *
\***************************************************************************/

/* The event queue is a simple priority queue used for all time-based events
   external to the CPU. Updating IOC timers, frontend screen output, etc.

   The CPU cycle counter is the timer used to trigger the events.
   
   When an event is triggered, it must either remove itself (via EventQ_Remove)
   or reschedule itself for a different time (EventQ_RescheduleHead). Failure
   to do either of those will result in an infinite loop where the same event
   is repeatedly triggered without the CPU emulation advancing.

   It's also acceptable for an event to remove itself and schedule several
   other events, in its place. Just be careful about the order events are
   inserted, otherwise when you call Remove(0) or RescheduleHead() the head
   may not be the same as before. Also be wary of timer overflows; any event
   scheduled for more than MAX_CYCLES_INTO_FUTURE cycles into the future will
   be considered as having already been triggered and will fire immediately.
 */

typedef uint32_t CycleCount;
typedef int32_t CycleDiff;
#define MAX_CYCLES_INTO_FUTURE LONG_MAX

typedef void (*EventQ_Func)(ARMul_State *state,CycleCount nowtime);

typedef struct {
  CycleCount Time;  /* When to trigger the event */
  EventQ_Func Func;    /* Function to call */
} EventQ_Entry;

#define EVENTQ_SIZE 8

/* NOTE - For speed reasons there aren't any overflow checks in the eventq
          code, so be aware of how many systems are using the queue. At the
          moment, these are:

          arch/newsound.c - One entry for sound DMA fetches
          arch/XXXdisplaydev.c - One entry for screen updates
          arch/keyboard.c - One entry for keyboard/mouse polling
          arch/archio.c - One entry for IOC timers
          arch/archio.c - One entry for FDC & HDC updates
        = 5 total
*/

/***************************************************************************\
*                          Main emulator state                              *
\***************************************************************************/

typedef unsigned ARMul_CPInits(ARMul_State *state);
typedef unsigned ARMul_CPExits(ARMul_State *state);
typedef unsigned ARMul_LDCs(ARMul_State *state, unsigned type, ARMword instr, ARMword value);
typedef unsigned ARMul_STCs(ARMul_State *state, unsigned type, ARMword instr, ARMword *value);
typedef unsigned ARMul_MRCs(ARMul_State *state, unsigned type, ARMword instr, ARMword *value);
typedef unsigned ARMul_MCRs(ARMul_State *state, unsigned type, ARMword instr, ARMword value);
typedef unsigned ARMul_CDPs(ARMul_State *state, unsigned type, ARMword instr);
typedef unsigned ARMul_CPReads(ARMul_State *state, unsigned reg, ARMword *value);
typedef unsigned ARMul_CPWrites(ARMul_State *state, unsigned reg, ARMword value);

typedef enum ARMStartIns {
  NORMAL        = 0,
  PCINCED       = 1,
  PRIMEPIPE     = 2,
  RESUME        = 4
} ARMStartIns;

#define Exception_IRQ R15IBIT
#define Exception_FIQ R15FBIT

struct ARMul_State {
   /* Most common stuff, current register file first to ease indexing */
   ARMword Reg[16];           /* the current register file */
   CycleCount NumCycles;      /* Number of cycles */
   enum ARMStartIns NextInstr;/* Pipeline state */
   unsigned abortSig;         /* Abort state */
   ARMword Aborted;           /* sticky flag for aborts */
   ARMword AbortAddr;         /* to keep track of Prefetch aborts */
   ARMword Exception;         /* IRQ & FIQ pins */
   ARMword Bank;              /* the current register bank */
   unsigned NtransSig;        /* MEMC USR/SVC flag, somewhat redundant with FastMapMode */
   ARMword Base;              /* extra hand for base writeback */
   int	   InstrLimit;
   bool	   Done;
   ARMword *Memory; 		
   /* Event queue */
   EventQ_Entry EventQ[EVENTQ_SIZE];
   uint_fast8_t NumEvents;

   /* Fastmap stuff */
//   FastMapUInt FastMapMode;   /* Current access mode flags */
//   FastMapUInt FastMapInstrFuncOfs; /* Offset between the RAM/ROM data and the ARMEmuFunc data */
//   FastMapEntry *FastMap;

   /* Less common stuff */   
   ARMword RegBank[4][16];    /* all the registers */
   ARMword instr, pc, temp;   /* saved register state */
   ARMword loaded, decoded;   /* saved pipeline state */

   /* Rare stuff */
   ARMul_CPInits *CPInit[16]; /* coprocessor initialisers */
   ARMul_CPExits *CPExit[16]; /* coprocessor finalisers */
   ARMul_LDCs *LDC[16];       /* LDC instruction */
   ARMul_STCs *STC[16];       /* STC instruction */
   ARMul_MRCs *MRC[16];       /* MRC instruction */
   ARMul_MCRs *MCR[16];       /* MCR instruction */
   ARMul_CDPs *CDP[16];       /* CDP instruction */
   ARMul_CPReads *CPRead[16]; /* Read CP register */
   ARMul_CPWrites *CPWrite[16]; /* Write CP register */
   unsigned char *CPData[16]; /* Coprocessor data */

 };

#ifdef AMIGA
extern void *state_alloc(int s);
extern void state_free(void *p);
#else
/* If you need special allocation for the state rather than
 * using the usual static global, you can override these functions
 * and provide your own.
 */
static inline void *state_alloc(int s)
{
	return &statestr;
}

static inline void state_free(void *p)
{
}
#endif
 
/***************************************************************************\
*                  Definitons of things in the emulator                     *
\***************************************************************************/

void ARMul_EmulateInit(void);
ARMul_State *ARMul_NewState(void);
void ARMul_Reset(ARMul_State *state);
ARMword ARMul_DoProg(ARMul_State *state);

/***************************************************************************\
*                Definitons of things for event handling                    *
\***************************************************************************/

#define ARMul_Time (state->NumCycles)

/***************************************************************************\
*                          Useful support routines                          *
\***************************************************************************/

void ARMul_SetReg(ARMul_State *state, unsigned mode, unsigned reg, ARMword value);
ARMword ARMul_GetPC(ARMul_State *state);
ARMword ARMul_GetNextPC(ARMul_State *state);
void ARMul_SetPC(ARMul_State *state, ARMword value);
ARMword ARMul_GetR15(ARMul_State *state);
void ARMul_SetR15(ARMul_State *state, ARMword value);

/***************************************************************************\
*                  Definitons of things to handle aborts                    *
\***************************************************************************/

extern void ARMul_Abort(ARMul_State *state, ARMword address);
#define ARMul_ABORTWORD 0xefffffff /* SWI -1 */
#define ARMul_PREFETCHABORT(address) if (state->AbortAddr == 1) \
                                        state->AbortAddr = ((address) & ~3L)
#define ARMul_DATAABORT(address) state->abortSig = HIGH; \
                                 state->Aborted = ARMul_DataAbortV;
#define ARMul_CLEARABORT state->abortSig = LOW

/***************************************************************************\
*            Definitons of things in the co-processor interface             *
\***************************************************************************/

#define ARMul_FIRST 0
#define ARMul_TRANSFER 1
#define ARMul_BUSY 2
#define ARMul_DATA 3
#define ARMul_INTERRUPT 4
#define ARMul_DONE 0
#define ARMul_CANT 1
#define ARMul_INC 3

typedef void (*ARMEmuFunc)(ARMul_State *state, ARMword instr);
ARMEmuFunc ARMul_Emulate_DecodeInstr(ARMword instr);

#endif
