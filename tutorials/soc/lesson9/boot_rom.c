// boot_rom.c
// Boot ROM for the Z80 system on a chip (SoC)
// (c) 2015 Till Harbaum

#include <stdio.h>
#include <string.h>
#include <stdlib.h>   // for abs()

extern unsigned char font[];

// the pointer has a mask 
const unsigned char cursor_data[] = {
  0x00, 0xb0, 0xb8, 0x9c, 0xae, 0xb5, 0x1a, 0x0c };

const unsigned char cursor_mask[] = {
  0x7c, 0x78, 0x7c, 0x7e, 0x5f, 0x0e, 0x04, 0x00 };

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
  cur_x = 0;
  cur_y = 0;
}

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

// the key registers has two bits:
// 0 - <SPACE>
// 1 - S
// 2 - C
__sfr __at 0x20 keys;

__sfr __at 0x30 mouse_x_reg;
__sfr __at 0x31 mouse_y_reg;
__sfr __at 0x32 mouse_but_reg;

void main() {
  int mouse_x=80, mouse_y=50;
  int last_x = -1, last_y;
  char i;

  cls();

  // load cursor image into VGA controller
  for(i=0;i<8;i++) {
    *(char*)(0x3f00+i) = cursor_data[i];
    *(char*)(0x3f08+i) = cursor_mask[i];
  }

  // set cursor hotspot to pixel 1,0
  *(unsigned char*)0x3efd = 0x10;

  // cursor colors
  *(unsigned char*)0x3efb = 0xda;    // bright grey
  *(unsigned char*)0x3efc = 0x49;    // dark grey

  puts(" << Z80 SoC Paint >>\n");

  puts("    <C>lear image\n");
  puts("    Hit <Space>");

  // wait for bit 0 to show up on key register
  while(!(keys & 1));

  cls();

  puts("Paint ...");

  // clear mouse registers by reading them
  i = (char)mouse_x_reg;
  i = (char)mouse_y_reg;

  while(1) {
    // 'C' clears screen
    if(keys & 4) cls();

    mouse_x += (char)mouse_x_reg;
    mouse_y -= (char)mouse_y_reg;

    // limit mouse movement
    if(mouse_x < 0)   mouse_x = 0;
    if(mouse_x > 159) mouse_x = 159;
    if(mouse_y < 0)   mouse_y = 0;
    if(mouse_y > 99)  mouse_y = 99;

    // set mouse cursor position
    *(unsigned char*)0x3efe = mouse_x;
    *(unsigned char*)0x3eff = mouse_y;

    if(mouse_but_reg & 3) {
      // left button draws white, right button black and both red
      unsigned char colors[] = { 0x00, 0xff, 0x00, 0xe0 };

      // there is a valid "last" mouse position
      if(last_x >= 0)
	draw_line(last_x, last_y, mouse_x, mouse_y, colors[mouse_but_reg]);

      last_x = mouse_x;
      last_y = mouse_y;
    } else
      last_x = -1;
  }
}
