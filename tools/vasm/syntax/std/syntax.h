/* snytax.h  syntax header file for vasm */
/* (c) in 2002-2005 by Volker Barthelmann and Frank Wille */

/* macros to recognize identifiers */
#if defined(VASM_CPU_PPC)
#define ISIDSTART(x) ((x)=='.'||(x)=='_'||(x)=='@'||isalpha((unsigned char)(x)))
#define ISIDCHAR(x) ((x)=='.'||(x)=='_'||(x)=='$'||isalnum((unsigned char)(x)))
#else
#define ISIDSTART(x) ((x)=='.'||(x)=='_'||isalpha((unsigned char)(x)))
#define ISIDCHAR(x) ((x)=='.'||(x)=='_'||isalnum((unsigned char)(x)))
#endif

#ifndef CPU_DEF_ALIGN
#define CPU_DEF_ALIGN 2	 /* power2-alignment is default for .align */
#endif
