// boot_rom.c
// Boot ROM for the Z80 system on a chip (SoC)
// (c) 2015 Till Harbaum

#include <stdlib.h>   // for abs()

// draw a pixel
// At 160x100 pixel screen size a byte is sufficient to hold the x and
// y coordinates- Video memory begins at address 0 and is write only.
// The address space is shared with the ROM which is read only.
void put_pixel(unsigned char x, unsigned char y, unsigned char color) {
  *((unsigned char*)(160*y+x)) = color;
}

// bresenham algorithm to draw a line
void draw_line(unsigned char x, unsigned char y, 
	       unsigned char x2, unsigned char y2, 
	       unsigned char color) {
  unsigned char longest, shortest, numerator, i;
  char dx1 = (x<x2)?1:-1;
  char dy1 = (y<y2)?1:-1;
  char dx2, dy2;
  
  longest = abs(x2 - x);
  shortest = abs(y2 - y);
  if(longest<shortest) {
    longest = abs(y2 - y);
    shortest = abs(x2 - x);
    dx2 = 0;            
    dy2 = dy1;
  } else {
    dx2 = dx1;
    dy2 = 0;
  }

  numerator = longest/2;
  for(i=0;i<=longest;i++) {
    put_pixel(x,y,color) ;
    if(numerator >= longest-shortest) {
      numerator += shortest ;
      numerator -= longest ;
      x += dx1;
      y += dy1;
    } else {
      numerator += shortest ;
      x += dx2;
      y += dy2;
    }
  }
}

void main() {
  int i;
  unsigned char color = 0;

  // clear screen
  for(i=0;i<16000;i++)
    *(char*)i = 0x00;

  // draw colorful lines forever ...
  while(1) {
    for(i=0;i<100;i++)   draw_line(0,0,159,i,color++);
    for(i=159;i>=0;i--)  draw_line(0,0,i,99,color++);
    
    for(i=0;i<160;i++)   draw_line(0,99,i,0,color++);
    for(i=0;i<100;i++)   draw_line(0,99,159,i,color++);
    
    for(i=99;i>=0;i--)   draw_line(159,99,0,i,color++);
    for(i=0;i<160;i++)   draw_line(159,99,i,0,color++);
    
    for(i=159;i>=0;i--)  draw_line(159,0,i,99,color++);
    for(i=99;i>=0;i--)   draw_line(159,0,0,i,color++);
  }
}
