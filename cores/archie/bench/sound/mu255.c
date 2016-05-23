#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

short ulaw2linear(unsigned char ulawbyte) 
{

}

int main(int argc, char **argv)
{

  unsigned i;

  for (i = 0; i < 256; i++) {
    /*
     * (not VIDC1, whoops...)
     * VIDC2:
     * 0 Sign
     * 4,3,2,1 Point on chord
     * 7,6,5 Chord select
     */

    uint32_t chordSelect = (i & 0xE0) >> 5;
    uint32_t pointSelect = (i & 0x1E) >> 1;
    uint32_t sign = (i & 1);

    uint32_t stepSize;

    const uint32_t scale = (0xFFFF / (247 * 2));
    uint32_t chordBase;
    int32_t sample;

    switch (chordSelect) {
      case 0: chordBase = 0;
              stepSize = scale / 16;
              break;
      case 1: chordBase = scale;
              stepSize = (2 * scale) / 16;
              break;
      case 2: chordBase = 3*scale;
              stepSize = (4 * scale) / 16;
              break;
      case 3: chordBase = 7*scale;
              stepSize = (8 * scale) / 16;
              break;
      case 4: chordBase = 15*scale;
              stepSize = (16 * scale) / 16;
              break;
      case 5: chordBase = 31*scale;
              stepSize = (32 * scale) / 16;
              break;
      case 6: chordBase = 63*scale;
              stepSize = (64 * scale) / 16;
              break;
      case 7: chordBase = 127*scale;
              stepSize = (128 * scale) / 16;
              break;
      /* End of chord 7 is 247 * scale. */

      default: chordBase = 0;
               stepSize = 0;
               break;
    }

    sample = chordBase + stepSize * pointSelect;

    if (sign == 1) { /* negative */
      sample = -sample;
    }

    sample+=0x8000;

    printf("%04hx\n", sample);
  }

    return 0;
}
