// boot_rom.c
// Boot ROM for the Z80 system on a chip (SoC)
// (c) 2015 Till Harbaum

#include <stdio.h>
#include <string.h>
#include "pff.h"

#define BUFFERS  8

const BYTE animation[] = "|/-\\";

// space for 8 sectors
DWORD frames = 0;
WORD rptr = 0xffff;
BYTE rsec = 0;

BYTE ym_buffer[BUFFERS][512];

__sfr __at 0x10 PsgAddrPort;
__sfr __at 0x11 PsgDataPort;

// YM replay is happening in the interrupt
void isr(void) __interrupt {
  BYTE i, *p;

  if(frames) {
    frames--;

    // write all 14 psg sound registers
    p = ym_buffer[rsec] + rptr;

    // unrolled loop for min delay between register writes
    PsgAddrPort = 0; PsgDataPort = *p++;
    PsgAddrPort = 1; PsgDataPort = *p++;
    PsgAddrPort = 2; PsgDataPort = *p++;
    PsgAddrPort = 3; PsgDataPort = *p++;
    PsgAddrPort = 4; PsgDataPort = *p++;
    PsgAddrPort = 5; PsgDataPort = *p++;
    PsgAddrPort = 6; PsgDataPort = *p++;
    PsgAddrPort = 7; PsgDataPort = *p++;
    PsgAddrPort = 8; PsgDataPort = *p++;
    PsgAddrPort = 9; PsgDataPort = *p++;
    PsgAddrPort = 10; PsgDataPort = *p++;
    PsgAddrPort = 11; PsgDataPort = *p++;
    PsgAddrPort = 12; PsgDataPort = *p++;
    PsgAddrPort = 13;
    if(*p != 255) PsgDataPort = *p++;

    rptr += 16;

    // one whole sector processed?
    if(rptr == 512) {
      rsec++;
      rptr=0;
      
      if(rsec == BUFFERS)
	rsec = 0;
    }
  } else {
    // not playing? mute all channels
    for(i=0;i<16;i++) {
      PsgAddrPort = i;
      PsgDataPort = 0;
    }
  }

  // re-enable interrupt
  __asm
    ei    
  __endasm;
}


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
  FRESULT rc;
  UINT bytes_read;
  BYTE i, wsec = 0;

  ei();
  cls();

  puts("    << Z80 SoC >>");

  printf("Mounting SD card...\n");

  // not playing? mute all channels
  for(i=0;i<16;i++) {
    PsgAddrPort = i;
    PsgDataPort = 0;
  }

  rc = pf_mount(&fatfs);
  if (rc) die(rc);

  // open song.ym
  printf("Opening SONG.YM...\n");
  rc = pf_open("SONG.YM");
  if(rc == FR_NO_FILE) {
    printf("File not found");
    for(;;);
  }
  if (rc) die(rc);

  // read file sector by sector
  do {
    // Wait while irq routine is playing and all sector buffers are
    // full This would be the place where we'd be doing the main
    // processing like running a game engine.
    while((wsec == rsec) && frames);

    rc = pf_read(ym_buffer[wsec], 512, &bytes_read);

    // No song info yet? Read and analyse header!
    if(!frames) {
      // check for file header
      if((ym_buffer[0][0] != 'Y')||(ym_buffer[0][1] != 'M')) {
	printf("No YM file!\n");
	for(;;);
      }
      
      printf("YM version: %.4s\n", ym_buffer[0]);

      // we only support files that are not interleaved
      if(ym_buffer[0][19] & 1) {
	printf("No Interleave!\n");
	for(;;);
      }

      // we don't support digi drums
      if(ym_buffer[0][20] || ym_buffer[0][21]) {
	printf("No Digidums!\n");
	for(;;);
      }

      // skip Song name, Author name and Song comment
      rptr = 34;
      printf("%s\n", ym_buffer[0]+rptr);
      while(ym_buffer[0][rptr]) rptr++;  // song name
      rptr++;
      printf("%s\n", ym_buffer[0]+rptr);
      while(ym_buffer[0][rptr]) rptr++;  // author name
      rptr++;
      while(ym_buffer[0][rptr]) rptr++;  // song comment
      rptr++;

      // extract frames
      frames = 256l*256l*256l*ym_buffer[0][12] + 256l*256l*ym_buffer[0][13] + 
	256l*ym_buffer[0][14] + ym_buffer[0][15];
      printf("Frames: %ld\n", frames);
    }

    // circle through the sector buffers
    wsec++;
    if(wsec == BUFFERS)
      wsec = 0;

    // do some animation
    printf("%c\r", animation[wsec&3]);

    // do this until all sectors are read
  } while((!rc) && (bytes_read == 512));
  if (rc) die(rc);

  printf("done.\n");

  while(1);
}
