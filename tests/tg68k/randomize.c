#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// returns 1/3 negative numbers, 1/3 positive and 1/3  0, -1, min and max
unsigned long my_random(unsigned int mask) {
  unsigned long sign = 0;
  if(mask == 0xffffffff) sign = 0x80000000;
  if(mask == 0xffff) sign = 0x8000;
  if(mask == 0xff) sign = 0x80;

  switch(random() % 3) { 
  case 0:
    return (random() & mask) | sign;  // negative

  case 1:
    return (random() & mask) & ~sign;  // positive

  case 2:
    switch(random() & 3) {
    case 0:
      return 0xffffffff & mask;

    case 1:
      return 0;

    case 2:
      return sign;         // long/word/byte min (e.g. 0x80)

    case 3:
      return mask ^ sign;  // long/word/byte max (e.g. 0x7f)
    }
  }

  return 0;
}

int main(int argc, char **argv) {
  char buffer[256];

  printf("tg68k/musashi test randomizer\n");

  srandom(time(NULL));

  if(argc != 3) {
    fprintf(stderr, "Usage: randomize <infile> <outfile>\n");
    exit(-1);
  }
    
  FILE *in = fopen(argv[1], "r");
  if(!in) { perror("open input"); exit(-1); };
  FILE *out = fopen(argv[2], "w");
  if(!out) { perror("open output"); exit(-1); };

  while(!feof(in)) {
    // read in the line and make sure it was successful
    if (fgets(buffer,sizeof(buffer),in) != NULL) {
      // now we process the line

      while(strchr(buffer, '@') != 0) {

	char *cut = strchr(buffer, '@');
	*cut = 0;    // separate both strings
	char tmp[256];

	strcpy(tmp, buffer);
	unsigned long mask = 0;
	switch(cut[1]) {
	case 'l': strcat(tmp, "$%08lx"); mask = 0xffffffff; break;
	case 'w': strcat(tmp, "$%04x"); mask = 0xffff; break;
	case 'b': strcat(tmp, "$%02x"); mask = 0xff; break;
	default: strcat(tmp, "<ERROR>");
	}

	unsigned long rnd = my_random(mask);

	// check for "<" 
	if(cut[2] == '<') {
	  char *end = strchr(cut+2, '>');
	  unsigned long lower, upper;
	  sscanf(cut+3, "%lu,%lu", &lower, &upper);

	  // make sure rnd is not bigger than upper
	  if(rnd > upper) 
	    rnd = rnd % (upper+1);

	  // make sure rnd is not smaller than lower
	  if(rnd < lower) 
	    rnd = (rnd + lower) % (upper+1);
	  
	  strcat(tmp, end+1);
	} else
	  strcat(tmp, cut+2);

	sprintf(buffer, tmp, rnd);
      }
      fprintf(out, "%s", buffer);
    }
  }
    
  fclose(in);
  fclose(out);

  return 0;
}
