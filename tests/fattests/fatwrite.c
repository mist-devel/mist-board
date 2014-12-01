/*
  fatwrite.c

  fat write test for the minimig fat routines
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mmc.h"
#include "usb.h"
#include "fat.h"

FILE *img = NULL;
size_t imgsize = 0;

unsigned char MMC_ReadMultiple(unsigned long lba, unsigned char *pReadBuffer, unsigned long nBlockCount) {
  puts(__FUNCTION__);
  abort();
}

unsigned char MMC_Read(unsigned long lba, unsigned char *pReadBuffer) {
  printf("MMC_Read(%ld, %p)\n", lba, pReadBuffer);

  if(lba * 512 > imgsize-511) {
    printf("<<<<<<<< CRITIAL >>>>>>>>>: Read exceeding image limits\n");
    return 0;
  }
  
  if(fseek(img, 512*lba, SEEK_SET) < 0) perror("fseek()");
  if(fread(pReadBuffer, 1, 512, img) != 512) perror("fread()");

  return 1;
}

unsigned char MMC_Write(unsigned long lba, unsigned char *pWriteBuffer) {
  printf("MMC_Write(%ld, %p)\n", lba, pWriteBuffer);

  if(lba * 512 > imgsize-511) {
    printf("<<<<<<<< CRITIAL >>>>>>>>>: Write exceeding image limits\n");
    return 0;
  }

  if(fseek(img, 512*lba, SEEK_SET) < 0) perror("fseek()");
  if(fwrite(pWriteBuffer, 1, 512, img) != 512) perror("fwrite()");

  return 1;
}

unsigned char MMC_CheckCard() {
  puts(__FUNCTION__);
  abort();
}

uint8_t storage_devices;
unsigned char usb_storage_read(unsigned long lba, unsigned char *pReadBuffer) {
  puts(__FUNCTION__);
  abort();
}

unsigned char usb_storage_write(unsigned long lba, unsigned char *pWriteBuffer) {
  puts(__FUNCTION__);
  abort();
}

char BootPrint(const char *text) {
  printf("%s", text);
}

void ErrorMessage(const char *message, unsigned char code) {
  puts(__FUNCTION__);
  abort();
}

int main(int argc, char **argv) {
  if(argc != 3) {
    printf("Give a filename and 8+3 name to write to image\n");
    exit(-1);
  }

  FILE *infile = fopen(argv[1], "rb");
  if(!infile) {
    perror("fopen()");
    exit(-1);
  }

  // determine size of input file, allocate buffer and read it
  fseek(infile, 0, SEEK_END);
  size_t insize = ftell(infile);
  fseek(infile, 0, SEEK_SET);
  void *inbuf = malloc(insize);
  if(fread(inbuf, 1, insize, infile) != insize) {
    perror("fread(infile)");
    exit(-1);
  }
  fclose(infile);

  img = fopen("disk.img", "r+b");
  if(!img) { perror(""); exit(-1); }
  fseek(img, 0, SEEK_END);
  imgsize = ftell(img);
  fseek(img, 0, SEEK_SET);

  if(sizeof(struct MasterBootRecord) != 512) {
    printf("size of struct MasterBootRecord does not equal 512\n");
    exit(-1);
  }

  // init fat layer
  if(!FindDrive()) {
    printf("fat layer init failed\n");
    exit(-1);
  }

  /* write file */
  fileTYPE file;
  if(!FileNew(&file, argv[2], insize))
    printf("file creation failed");
  else {
    char buf[512];
    char *inptr = (char*)inbuf;

    while(insize) {
      int bytes2copy = (insize>512)?512:insize;
      memset(buf, 0, 512);
      memcpy(buf, inptr, bytes2copy);

      printf("Writing chunk with %d bytes\n", bytes2copy);

      if(!FileWrite(&file, buf))
	printf("File write failed\n");

      if(insize != bytes2copy)
	if(!FileNextSectorExpand(&file))
	  printf("File next sector failed\n");

      inptr += bytes2copy;
      insize -= bytes2copy;
    }

    // end writing file, so cluster chain may be trimmed
    if(!FileWriteEnd(&file))
      printf("End chain failed\n");
  }

  free(inbuf);
  fclose(img);
}
