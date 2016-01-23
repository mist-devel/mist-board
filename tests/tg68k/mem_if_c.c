#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// #define DEBUG

#include "mem.h"

#define SULV_U  (0) /* Uninitialized   */
#define SULV_X  (1) /* Forcing Unknown */
#define SULV_0  (2) /* Forcing 0       */
#define SULV_1  (3) /* Forcing 1       */
#define SULV_Z  (4) /* High Impedance  */
#define SULV_W  (5) /* Weak Unknown    */
#define SULV_L  (6) /* Weak 0          */
#define SULV_H  (7) /* Weak 1          */
#define SULV__  (8) /* Don't care      */

unsigned char chr[] = { 'U','X','0','1','Z','W','L','H','-' };

void mem_if_c(char clk, char bs[2], char ds[2], char addr[32], char din[16], char dout[16]) {
  static unsigned int data_out = 0;
  static char init = 0;
  static char last_clk = 0;
  static unsigned int last_addr = 0xffffffff;
  static unsigned short last_data;

  int busstate = ((bs[1]==SULV_1)?1:0) + ((bs[0]==SULV_1)?2:0);
  int dstrobe = ((ds[1]==SULV_1)?1:0) + ((ds[0]==SULV_1)?2:0);
  char wr = (busstate == 3)?SULV_1:SULV_0;

  // default: restore previous data_out
  int i;
  for(i=0;i<16;i++)
    dout[i] = (data_out & (0x8000>>i))?SULV_1:SULV_0;
  
  if(busstate == 1)
    return;

  if(!init) {
    // check if a file name was given
    if(getenv("TG68K_BIN"))
      mem_init(getenv("TG68K_BIN"));
    else {
      fprintf(stderr, "Please specify a bin file via TG68K_BIN\n");
      exit(-1);
    }
    
    init=1;
  }
    
  // only do something if clock changes
  if(clk == last_clk) 
    return;

  last_clk = clk;

  // only react on falling clk edge
  if(clk == SULV_1) return;

  unsigned int a = 0;
  for(i=0;i<32;i++) {
    a <<= 1;
    if((addr[i] == SULV_1)||(addr[i] == SULV_H))
      a |= 1;
  }

#ifdef DEBUG
  printf("mem(%08x/%d/%d) = ", a, dstrobe, busstate);
#endif

  if(wr == SULV_1) {
    unsigned int d = 0;
    for(i=0;i<16;i++) {
      d <<= 1;
      if((din[i] == SULV_1)||(din[i] == SULV_H))
	d |= 1;
    }

#ifdef DEBUG    
    printf("WRITE %x\n", d);
#endif
    mem_write(a, d, dstrobe);
  } else {
    //    exit(-1);

    int d16 = mem_read(a, 3);
#ifdef DEBUG    
    printf("READ %x\n", d16);
#endif

    for(i=0;i<16;i++)
      dout[i] = (d16 & (0x8000>>i))?SULV_1:SULV_0;

    data_out = d16;
  }
}
