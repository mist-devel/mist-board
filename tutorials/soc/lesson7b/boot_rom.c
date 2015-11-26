// boot_rom.c
// Boot ROM for the Z80 system on a chip (SoC)
// (c) 2015 Till Harbaum

#include <stdio.h>
#include <string.h>
#include "pff.h"

extern unsigned char font[];

unsigned char cur_x=0, cur_y=0;
void putchar(char c) {
  unsigned char *p;
  unsigned char *dptr = (unsigned char*)(160*(8*cur_y) + 8*cur_x);
  char i, j;

  if(c < 32) {
    if(c == '\r') 
      cur_x=0;

    if(c == '\n') {
      cur_y++;
      cur_x=0;

      if(cur_y >= 12)
	cur_y = 0;
    }
    return;
  }

  if(c < 0) return;

  p = font+8*(unsigned char)(c-32);
  for(i=0;i<8;i++) {
    unsigned char l = *p++;
    for(j=0;j<8;j++) {
      *dptr++ = (l & 0x80)?0xff:0x00;
      l <<= 1;
    }
    dptr += (160-8);
  }

  cur_x++;
  if(cur_x >= 20) {
    cur_x = 0;
    cur_y++;

    if(cur_y >= 12)
      cur_y = 0;
  }
}

volatile unsigned char global_color = 0x55;

// 16 topleft pixels flicker so we know the vsync interrupt is working
void isr(void) __interrupt {
  unsigned char x, y;
  unsigned char *v = (unsigned char*)(160*2+2);

  for(y=0;y<4;y++) {
    for(x=0;x<4;x++) 
      *v++ = global_color;

    v += 160-4;
  }

  global_color++;

  __asm
    ei    
  __endasm;
}

void cls(void) {
  unsigned char i;
  unsigned char *p = (unsigned char*)0;

  for(i=0;i<100;i++) {
    memset(p, 0, 160);
    p+=160;
  }
}

void ei() {
  // set interrupt mode 1 and enable interrupts
  __asm
    im 1
    ei    
  __endasm;
}

void die (FRESULT rc) {
  printf("Fail rc=%u", rc);
  for (;;) ;
}


void main() {
  FATFS fatfs;                    /* File system object */
  DIR dir;                                /* Directory object */
  FILINFO fno;                    /* File information object */
  FRESULT rc;
  char i;

  ei();
  cls();

  puts("    << Z80 SoC >>");

  printf("Reading SD card ...\r");

  rc = pf_mount(&fatfs);
  if (rc) die(rc);

  // list first 11 files on card
  rc = pf_opendir(&dir, "/");	
  if (rc) die(rc);

  printf("                   \r");
  for(i=0;i<11;i++) {
    rc = pf_readdir(&dir, &fno);
    if (rc != FR_OK || fno.fname[0] == 0) break;
    if (fno.fattrib & AM_DIR) {
      printf("<DIR> %s\n", fno.fname);
    } else {
      printf("      %s\n", fno.fname);
    }
  }


#if 0
  printf("Open CORE.RBF ...\n");
  rc = pf_open("CORE.RBF");
  if (rc) die(rc);
#endif

  while(1);
}
