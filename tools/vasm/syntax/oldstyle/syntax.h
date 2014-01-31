/* syntax.h  syntax header file for vasm */
/* (c) in 2002,2012 by Frank Wille */

/* macros to recognize identifiers */
#define ISIDSTART(x) ((x)=='.'||(x)=='_'||isalpha((unsigned char)(x)))
#define ISIDCHAR(x) ((x)=='_'||isalnum((unsigned char)(x)))
