/* vmath.c 96-bit integer and floating point routines for vasm */
/* (c) in 2002 by Frank Wille */

#include "vasm.h"
#include <math.h>

static int96 one = { 1,0,0,0,0,0,0,0,0,0,0,0 };


unsigned char *int96_assign32(unsigned char *x,int32_t val)
{
  int i;

  for (i=0; i<4; i++) {
    x[i] = val & 0xff;
    val >>= 8;
  }
  memset(&x[4],(x[3] & 0x80)?0xff:0,8);
  return x;
}


unsigned char *int96_assign64(unsigned char *x,int64_t val)
{
  int i;

  for (i=0; i<8; i++) {
    x[i] = val & 0xff;
    val >>= 8;
  }
  memset(&x[8],(x[7] & 0x80)?0xff:0,4);
  return x;
}


unsigned char *int96_add(unsigned char *x,unsigned char *y)
{
  unsigned char s,v;
  int i;

  for (i=0,v=0; i<12; i++) {
    s = x[i] + y[i] + v;
    v = s<x[i] || s<y[i];
    x[i] = s;
  }
  return x;
}


unsigned char *int96_add32(unsigned char *x,int32_t val)
{
  int96 y;

  return int96_add(x,int96_assign32(y,val));
}


unsigned char *int96_add64(unsigned char *x,int64_t val)
{
  int96 y;

  return int96_add(x,int96_assign64(y,val));
}


unsigned char *int96_negate(unsigned char *x)
{
  int i;

  for (i=0; i<12; i++)
    x[i] = ~x[i];
  return int96_add(x,one);
}


unsigned char *int96_lshleft(unsigned char *x,int cnt)
{
  unsigned short old=0,new;
  int i,sh;

  while (cnt > 0) {
    sh = (cnt > 8) ? 8 : cnt;
    for (i=0; i<12; i++) {
      new = (unsigned short)x[i] << sh;
      x[i] = (new & 0xff) | ((old >> 8) & 0xff);
      old = new;
    }
    cnt -= sh;
  }
  return x;
}


unsigned char *int96_lshright(unsigned char *x,int cnt)
{
  unsigned short old=0,new;
  int i,sh;

  while (cnt > 0) {
    sh = (cnt > 8) ? 8 : cnt;
    for (i=11; i>=0; i--) {
      new = ((unsigned short)x[i]<<8) >> sh;
      x[i] = (old & 0xff) | ((new >> 8) & 0xff);
      old = new;
    }
    cnt -= sh;
  }
  return x;
}


unsigned char *int96_ashright(unsigned char *x,int cnt)
{
  unsigned short new;
  unsigned short old = (x[11]>=0x80) ? 0xffff : 0;
  int i,sh;

  while (cnt > 0) {
    sh = (cnt > 8) ? 8 : cnt;
    for (i=11; i>=0; i--) {
      new = ((unsigned short)x[i]<<8) >> sh;
      x[i] = (old & 0xff) | ((new >> 8) & 0xff);
      old = new;
    }
    cnt -= sh;
  }
  return x;
}


unsigned char *int96_mulu(unsigned char *x,unsigned char *y)
{
  int i,j;
  uint16_t m;
  unsigned char p[13];
  int96 sum;

  memset(sum,0,12);
  memset(p,0,13);
  for (i=0; i<12; i++) {
    for (j=0; j<(12-i); j++) {
      m = (uint16_t)x[i] * (uint16_t)y[j];
      p[i+j] = m & 0xff;
      p[i+j+1] = (m >> 8) & 0xff;
      int96_add(sum,p);
      p[i+j] = p[i+j+1] = 0;
    }
  }
  memcpy(x,sum,12);
  return x;
}


unsigned char *int96_muls(unsigned char *x,unsigned char *y)
{
  int neg = 0;

  if (x[11] >= 0x80) {
    neg = 1;
    int96_negate(x);
  }
  if (y[11] >= 0x80) {
    neg ^= 1;
    int96_negate(y);
  }
  int96_mulu(x,y);
  if (neg)
    int96_negate(x);
  return x;
}


long double int96_conv2longdouble(unsigned char *x)
{
  long double f = 0.0;
  long double m = 1.0;
  int i,neg=0;

  if (x[11] >= 0x80) {
    neg = 1;
    int96_negate(x);
  }
  for (i=0; i<12; i++) {
    f += (long double)x[i] * m;
    m *= 256.0;
  }
  return neg ? -f : f;
}


int int96_cntz(unsigned char *x)
{
  int cnt = 0;
  int i;

  for (i=11; i>=0; i--) {
    unsigned char v = x[i];
    unsigned char m = 0x80;

    for (m=0x80; m; m>>=1) {
      if (v & m) {
        i = -1;
        break;
      }
      cnt++;
    }
  }
  return cnt;
}


int int96_compare(unsigned char *x,unsigned char *y)
{
  int96 cmp;
  int i;

  for (i=0; i<12; i++)
    cmp[i] = ~y[i];
  int96_add(cmp,one);
  int96_add(cmp,x);
  for (i=0; i<12; i++) {
    if (cmp[i])
      return cmp[11]>=0x80 ? -1 : 1;
  }
  return 0;
}


void int96_copybe(unsigned char *d,unsigned char *x,int len)
{
  int i;

  for (i=len-1; i>=0; i--)
    *d++ = x[i];
}


void int96_copyle(unsigned char *d,unsigned char *x,int len)
{
  memcpy(d,x,len);
}
