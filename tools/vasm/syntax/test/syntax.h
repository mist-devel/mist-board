/* snytax.h  syntax header file for vasm */
/* (c) in 2002 by Volker Barthelmann */

/* macros to recognize identifiers */
#define ISIDSTART(x) ((x)=='.'||(x)=='_'||isalpha((unsigned char)(x)))
#define ISIDCHAR(x) ((x)=='.'||(x)=='_'||isalnum((unsigned char)(x)))
