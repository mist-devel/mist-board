#include <stdio.h>
#include <assert.h>
#include <stdlib.h>
#include "mem.h"

#define ROMSIZE 65536
#define RAMSIZE 65536

#define ROMBASE 0x0
#define RAMBASE 0x10000

#define VERBOSE

FILE *result = NULL;

// this should be the same as the VHDL counterpart
unsigned char code[ROMSIZE];
unsigned char ram[RAMSIZE];

void mem_init(char *name) {
  FILE *f = fopen(name, "rb");
  if(!f) { printf("unable to load %s\n", name); exit(-1); }

  int r = fread(code, 1, sizeof(code), f);
  printf("loaded %d bytes code\n", r);

  fclose(f);

  // try to open the result file
  char *p;
  if((p=getenv("RESULT"))) {
    printf("Writing restult to file %s\n", p);
    result = fopen(p, "w");

    if(!result)
      perror("");
  }
}

unsigned char *addr_ptr(unsigned int address) {
  if((address >= ROMBASE) && (address < ROMBASE+ROMSIZE))
    return code + address - ROMBASE;

  if((address >= RAMBASE) && (address < RAMBASE+RAMSIZE))
    return ram + address - RAMBASE;

  return NULL;
}

// ignore ds when reading
unsigned int mem_read(unsigned int addr, int ds) {
#ifdef VERBOSE
  printf("mem_read(0x%08x,%d) = ", addr, ds);
#endif

  if(addr == 0xbeefed) {
    printf("beefed read??\n");
    return 0;
  }

  unsigned char *a = addr_ptr(addr & 0xffffffe);
  if(!a) { 
    printf("suspicious address!!!\n");
    return 0;
  }

  unsigned int retval = 256ul * a[0] + a[1];
#ifdef VERBOSE
  printf("%04x\n", retval);
#endif
  return retval;
}

// ignore ds when reading
void mem_write(unsigned int addr, unsigned int data, int ds) {
#ifdef VERBOSE
  printf("mem_write(0x%08x,%d) = %04x\n", addr, ds, data);
#endif

  // dump area used to export hex numbers 
  if(result && (addr >= 0xc0ffee42) && (addr < 0xc0ffee42+32*4)) {
    char *name[] = { "D", "A", "X", "." };
    int reg = (addr - 0xc0ffee42)/2;
    if(reg == 32) {
      fprintf(result, "SR %04x XNZVC\n", data);

    } else 
      fprintf(result, "%s%d.%c:%04x\n",
	      name[reg>>4],(reg>>1)&7, (reg&1)?'l':'h', data);
    return;
  }
    
  if(addr == 0xbeefed) {
    if(!data) printf("Program terminated successful\n");
    else      printf("Program terminated with error code %d\n", data);
    exit(data);
  }

  unsigned char *a = addr_ptr(addr & 0xffffffe);
  if(!a) { 
    printf("suspicious address %x\n", addr);
    return;
  }

  if(ds&1) a[0] = data >> 8;
  if(ds&2) a[1] = data & 0xff;
}
