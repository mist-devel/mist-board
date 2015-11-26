// ym files are usually interleaved for better compression. But that's
// not convenient for streaming. This tool de-interleaves a ym file

#include <stdio.h>
#include <stdlib.h>

#define SWAP32(a)  ((((a)&0xff)<<24)|(((a)&0xff00)<<8)|(((a)&0xff0000)>>8)|(((a)&0xff000000)>>24))

int main(int argc, char **argv) {
  FILE *in, *out;
  char hdr[34], end[4];
  int v, i, j;

  if(argc != 3) {
    printf("Usage: ym_deint <infile> <outfile>\n");
    exit(-1);
  }

  printf("%s\n", argv[1]);
  in = fopen(argv[1], "rb");
  if(!in) {
    printf("Unable to open %s\n", argv[1]);
    exit(-1);
  }

  out = fopen(argv[2], "wb");
  if(!out) {
    printf("Unable to open %s\n", argv[2]);
    exit(-1);
  }

  if((v=fread(hdr, sizeof(hdr), 1, in)) < 0) {
    perror("fread");
    exit(-1);
  }

  if(v != 1) {
    printf("short read\n");
    exit(-1);
  }
  
  // check for ym file
  if((hdr[0] != 'Y')||(hdr[1] != 'M')) {
    printf("Not a YM file. Maybe compressed, please uncompress first\n");
    exit(-1);
  }

  // check for digidrums
  if(hdr[20]||hdr[21]) {
    printf("Digidrums not supported\n");
    exit(-1);
  }

  // check for interleaved
  if(hdr[19] != 0x01) {
    printf("File is not interleaved\n");
    exit(-1);
  }

  // remove interleave marker
  hdr[19] = 0;
    
  // write header
  if(fwrite(hdr, sizeof(hdr), 1, out) < 0) {
    perror("fwrite");
    exit(-1);
  }
  
  // skip names
  int c;
  printf("Name: ");
  while(((c = fgetc(in)) > 0) && c) {
    putchar(c);
    fputc(c, out);
  }
  fputc(c, out);
  puts("");

  printf("Author: ");
  while(((c = fgetc(in)) > 0) && c) {
    putchar(c);
    fputc(c, out);
  }
  fputc(c, out);
  puts("");

  printf("Comment: ");
  while(((c = fgetc(in)) > 0) && c) {
    putchar(c);
    fputc(c, out);
  }
  fputc(c, out);
  puts("");

  unsigned long frames = SWAP32(*(unsigned long*)(hdr+12));
  printf("converting %lu frames\n", frames);

  // allocate buffer for interleaved frames
  char *b = malloc(frames*16);
  if(!b) {
    perror("malloc");
    exit(-1);
  }

  if((v=fread(b, 16, frames, in)) < 0) {
    perror("fread");
    exit(-1);
  }

  if(v != frames) {
    printf("short read\n");
    exit(-1);
  }

  // write de-interleaved
  for(i=0;i<frames;i++)
    for(j=0;j<16;j++)
      fputc(b[frames*j+i], out);

  if((v=fread(end, sizeof(end), 1, in)) < 0) {
    perror("fread");
    exit(-1);
  }

  if(v != 1) {
    printf("short read\n");
    exit(-1);
  }

  // check for ym file
  if((end[0] != 'E')||(end[1] != 'n')||(end[2] != 'd')||(end[3] != '!')) {
    printf("No End ID!\n");
    exit(-1);
  }

  // write end
  if(fwrite(end, sizeof(end), 1, out) < 0) {
    perror("fwrite");
    exit(-1);
  }

  fclose(in);
  return 0;
}
