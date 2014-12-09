#include <stdio.h>
#include <osbind.h>

// http://mikro.naprvyraz.sk/docs/Memory%20Maps/HARDWARE.TXT

// read byte test. Returns 1 on bus error
char test_rb(void *adr);

asm (
     "_test_rb: move.l  4(sp),a0\n\t"  // address
     "       movem.l d1-d2,-(sp)\n\t"  // save registers
     "       move.l sp, d1\n\t"        // save stack pointer
     "       st.b  d0\n\t"
     "       move.l 8,d2\n\t"
     "       move.l #berr,8\n\t"
     "       move.b (a0),d3\n\t"
     "       clr.b   d0\n\t"
     "berr:  move.l d2,8\n\t"
     "       move.l d1,sp\n\t"
     "       movem.l (sp)+,d1-d2\n\t"
     "       rts\n\t"
     );

// read word test. Returns 1 on bus error
char test_rw(void *adr);

asm (
     "_test_rw: move.l  4(sp),a0\n\t"  // address
     "       movem.l d1-d2,-(sp)\n\t"  // save registers
     "       move.l sp, d1\n\t"        // save stack pointer
     "       st.b  d0\n\t"
     "       move.l 8,d2\n\t"
     "       move.l #berr2,8\n\t"
     "       move.w (a0),d3\n\t"
     "       clr.b   d0\n\t"
     "berr2: move.l d2,8\n\t"
     "       move.l d1,sp\n\t"
     "       movem.l (sp)+,d1-d2\n\t"
     "       rts\n\t"
     );

char *acc[8] = {                // WOE
  "any",                        // 000
  "odd byte and word",          // 001
  "even byte and word",         // 010
  "word",                       // 011
  "byte",                       // 100
  "odd byte",                   // 101
  "even byte",                  // 110
  "no"                          // 111
};

int main(void) {
  // do various sanity tests
  long usp = Super(0l);

  FILE *file;
  file = fopen("berrscan.log", "w+");
  if(!file) {
    printf("unable to open log file\n");
    getchar();
    return 1;
  }

  fprintf(file, "Access ranges:\n");
  // check bus error ranges
  unsigned long start = 0xFF8000;
  unsigned long i, j = start;
  unsigned char last_state = 0;
  for(i=start;i<0x1000000;i+=2) {
    unsigned char berr_e = test_rb((void*)i);
    unsigned char berr_o = test_rb((void*)(i+1));
    unsigned char berr_w = test_rw((void*)i);
    unsigned char state = 
      (berr_e?0x01:0x00)|(berr_o?0x02:0x00)|(berr_w?0x04:0x00);

    if((state != last_state) && (i!=start)) {
      fprintf(file, "from %lx to %lx: %s\n", j, i-1, acc[last_state]);
      j = i;
    }
    last_state = state;
  }
  
  if(j != i)
    fprintf(file, "from %lx to %lx: %s\n", j, i-1, acc[last_state]);
  
  fclose(file);

  Super(usp);

  return 0;
}
