#include <assert.h>
#include <stdio.h>

#include "mem.h"
#include "Musashi/m68k.h"

unsigned int  m68k_read_memory_8(unsigned int address) {
  unsigned int retval = (address & 1)?
    (mem_read(address, 3) & 0xff):(mem_read(address, 3) >> 8);
  //  printf("%s(%x)=%x\n", __FUNCTION__, address, retval);
  return retval;
}

unsigned int  m68k_read_memory_16(unsigned int address) {
  unsigned int retval;

  if(address & 1) {
    retval = 
      ((mem_read(address-1,3) & 0xff) << 8) +
      ((mem_read(address+1,3) & 0xff00) >> 8);
  } else
    retval = mem_read(address,3);

  //  printf("%s(%x)=%x\n", __FUNCTION__, address, retval);
  return retval;
}
 
unsigned int  m68k_read_memory_32(unsigned int address) {
  unsigned int retval;

  if(address & 1) {
    retval = 
      ((mem_read(address-1,3) & 0xff) << 24) +
      ((mem_read(address+1,3) & 0xffff) << 8) +
      ((mem_read(address+3,3) & 0xff00) >> 8);
  } else
    retval = (mem_read(address,3) << 16) + 
      mem_read(address+2,3);

  //  printf("%s(%x)=%x\n", __FUNCTION__, address, retval);
  return retval;
}

void m68k_write_memory_8(unsigned int address, unsigned int value) {
  //  printf("%s(%x, %x)\n", __FUNCTION__, address, value);
  if(address & 1) mem_write(address, value & 0xff, 2);
  else            mem_write(address, value << 8, 1);
}

void m68k_write_memory_16(unsigned int address, unsigned int value) {
  //  printf("%s(%x, %x)\n", __FUNCTION__, address, value);

  if(address & 1) {
    printf("<<<<<<<<<<<<<<<< untested >>>>>>>>>>>>>>>>\n");
    mem_write(address-1, value & 0xff00, 1);
    mem_write(address+1, value & 0xff, 2);
  } else 
    mem_write(address, value, 3);
}

void m68k_write_memory_32(unsigned int address, unsigned int value) {
  //  printf("%s(%x, %x)\n", __FUNCTION__, address, value);

  if(address & 1) {
    mem_write(address-1, (value >> 24) & 0xff, 2);
    mem_write(address+1, (value >> 8) & 0xffff, 3);
    mem_write(address+3, (value << 8) & 0xff00, 1);
  } else {
    mem_write(address, value >> 16, 3);
    mem_write(address+2, value & 0xffff, 3);
  }
}

int main(int argc, char **argv) {
  int i;

  if(argc != 2) {
    printf("Usage: m68k_run code.bin\n");
    return -1;
  }

  mem_init(argv[1]);
  m68k_init();
  m68k_set_cpu_type(M68K_CPU_TYPE_68020);
  m68k_pulse_reset();

  while(1)
    m68k_execute(0);

  return 0;
}
