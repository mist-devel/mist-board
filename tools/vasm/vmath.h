#ifndef VMATH_H
#define VMATH_H

typedef unsigned char int96[12];    /* 96-bit little endian format */

unsigned char *int96_assign32(unsigned char *,int32_t);
unsigned char *int96_assign64(unsigned char *,int64_t);
unsigned char *int96_add(unsigned char *,unsigned char *);
unsigned char *int96_add32(unsigned char *,int32_t);
unsigned char *int96_add64(unsigned char *,int64_t);
unsigned char *int96_negate(unsigned char *);
unsigned char *int96_lshleft(unsigned char *,int);
unsigned char *int96_lshright(unsigned char *,int);
unsigned char *int96_ashright(unsigned char *,int);
unsigned char *int96_mulu(unsigned char *,unsigned char *);
unsigned char *int96_muls(unsigned char *,unsigned char *);
long double int96_conv2longdouble(unsigned char *);
int int96_cntz(unsigned char *);
int int96_compare(unsigned char *,unsigned char *);
void int96_copybe(unsigned char *,unsigned char *,int);
void int96_copyle(unsigned char *,unsigned char *,int);

#endif
