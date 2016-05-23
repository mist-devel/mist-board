/*
  prof.h

  (c) 2011 Jeffrey Lee <me@phlamethrower.co.uk>

  Part of Arcem released under the GNU GPL, see file COPYING
  for details.

  Basic profiling interface; vanishes to nothingness if profiling is disabled.
  See prof.s for the true horror show.

*/

#ifndef prof_h
#define prof_h

#ifdef PROFILE_ENABLED

extern void Prof_Init(void);
extern void Prof_Dump(FILE *f);
extern void Prof_BeginFunc(const void *);
extern void Prof_EndFunc(const void *);
extern void Prof_Begin(const char *);
extern void Prof_End(const char *);
extern void Prof_Reset(void);

#else

#define Prof_Init() ((void) 0)
#define Prof_Dump(x) ((void) 0)
#define Prof_BeginFunc(x) ((void) 0)
#define Prof_EndFunc(x) ((void) 0)
#define Prof_Begin(x) ((void) 0)
#define Prof_End(x) ((void) 0)
#define Prof_Reset() ((void) 0)

#endif

#endif
