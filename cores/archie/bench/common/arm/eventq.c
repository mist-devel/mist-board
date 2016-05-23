/*
  eventq.c

  (c) 2011 Jeffrey Lee <me@phlamethrower.co.uk>

  Part of Arcem released under the GNU GPL, see file COPYING
  for details.

  Basic priority queue implementation for managing all CPU-external events.
  Events are scheduled using the cycle counter (ARMul_Time) as the time base,
  so real-time events will need an extra helping hand (e.g. ARMul_EmuRate)
*/

#include "eventq.h"

static void DummyEventFunc(ARMul_State *state,CycleCount nowtime)
{
	/* Queue should (must!) be empty, so just poke our time value */
	state->EventQ[0].Time = nowtime+MAX_CYCLES_INTO_FUTURE;
}

void EventQ_Init(ARMul_State *state)
{
	/* When empty, the first entry in the queue is a dummy entry so that the main loop doesn't have to worry about checking for an empty queue */
	state->NumEvents = 0;
	state->EventQ[0].Time = ARMul_Time+MAX_CYCLES_INTO_FUTURE;
	state->EventQ[0].Func = DummyEventFunc;
}
