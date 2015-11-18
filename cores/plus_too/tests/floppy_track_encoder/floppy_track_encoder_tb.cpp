#include "Vfloppy_track_encoder.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#define TRACK 0

void hexdump(void *data, int size) {
  int i, b2c;
  int n=0;
  char *ptr = (char*)data;

  if(!size) return;

  while(size>0) {
    fprintf(stderr, "%04x: ", n);

    b2c = (size>16)?16:size;
    for(i=0;i<b2c;i++)      fprintf(stderr, "%02x ", 0xff&ptr[i]);
    fprintf(stderr, "  ");
    for(i=0;i<(16-b2c);i++) fprintf(stderr, "   ");
    for(i=0;i<b2c;i++)      fprintf(stderr, "%c", isprint(ptr[i])?ptr[i]:'.');
    fprintf(stderr, "\n");
    ptr  += b2c;
    size -= b2c;
    n    += b2c;
  }
}

Vfloppy_track_encoder* top = NULL;
VerilatedVcdC* tfp = NULL;

// an encoded track requires 1024 bytes per sector
// max 12 sectors are stored per track
int encoded_track_size;
unsigned char encoded_track_buffer[12*1024];

// an unencoded track requires 512 bytes per sector
int track_size;
unsigned char track_buffer[12*512];

// return number of sectors per track
int spt(int t) {
  if((t >> 4) == 0) return 12;         //  0-15
  else if((t >> 4) == 1) return 11;    // 16-31
  else if((t >> 4) == 2) return 10;    // 32-47
  else if((t >> 4) == 3) return 9;     // 48-63
  else return 8;                       // 64 ...
}

// return sector offset of first sector in track
int track_sector_index(int t) {
  int index = 0;
  while(t) 
    index += spt(--t);

  return index;
}

int offset;

//
int load_track(int t, int s) {
  printf("File: %s\n", "../Disk603.bin");

  FILE *file = fopen("../Disk603.bin", "rb");
  if(!file) return 0;

  fseek(file, 0, SEEK_END);
  int size = ftell(file);
  fseek(file, 0, SEEK_SET);

  //  printf("size: %d\n", size);

  int sectors = size/1024;
  //  printf("total sectors: %d\n", sectors);
  //  printf("avg spt: %d\n", sectors/80);

  int sides = 2;

  printf("track %d is at %d, len = %d\n", t, 
	 sides*track_sector_index(t), spt(t));

  // offset and length in bytes
  int byte_offset = track_sector_index(t) * 1024 * sides + 1024 * s * spt(t);
  int byte_len = spt(t) * 1024;

  //  printf("byte offset %d, len %d\n", byte_offset, byte_len);

  encoded_track_size = byte_len;
  fseek(file, byte_offset, SEEK_SET);
  fread(encoded_track_buffer, 1, byte_len, file);
  fclose(file);

  // begin of encoded payload
  //  hexdump(encoded_track_buffer, 1024 /*byte_len*/);

  // and load the unencoded counterpart
  printf("File: %s\n", "../Disk603.dsk");

  file = fopen("../Disk603.dsk", "rb");
  if(!file) return 0;

  fseek(file, 0, SEEK_END);
  size = ftell(file);
  fseek(file, 0, SEEK_SET);

  //  printf("size: %d\n", size);

  sectors = size/512;
  //  printf("total sectors: %d\n", sectors);
  //  printf("avg spt: %d\n", sectors/80);

  printf("track %d is at %d, len = %d\n", t, 
	 sides*track_sector_index(t), spt(t));

  // offset and length in bytes
  byte_offset = track_sector_index(t) * 512 * sides + 512 * s * spt(t);
  byte_len = spt(t) * 512;

  //  printf("byte offset %d, len %d\n", byte_offset, byte_len);

  track_size = byte_len;
  fseek(file, byte_offset, SEEK_SET);
  fread(track_buffer, 1, byte_len, file);
  fclose(file);

  offset = byte_offset;

  // begin of payload
  //  hexdump(track_buffer, 16);

  return 1;
}

int tim = 0;
int fail = 0;

int ocnt = 0;
int icnt = 0;
int track, side;

void step() {
  if(!top->rst) {
    if(top->strobe) {
      int adr = offset+icnt;
      int adri = top->addr - 0x200000;

      //      printf("%x\n", top->addr);

      if(adri != adr) {
	printf("address mismatch %d/%d %d/%d\n", 
	       adri/512, adri%512, 
	       adr/512, adr%512);
	fail++;
      }
      top->idata = track_buffer[icnt++];
    }

    if(icnt == 512*spt(track))
      icnt = 0;
    
    if(top->odata != encoded_track_buffer[ocnt++]) {
      printf("encoding error at %d: %x != %x\n",
	     ocnt-1, top->odata, encoded_track_buffer[ocnt-1]);
      fail++;
    }

    if(ocnt == 1024*spt(track))
      ocnt = 0;
  }

  top->clk = 0;
  top->eval();
  tfp->dump(tim++);

  top->clk = 1;
  top->eval();
  tfp->dump(tim++);

}

void step_n(int n) {
  while(--n)
    step();
}

int main(int argc, char **argv, char **env) {
  int i;
  int clk;

  Verilated::commandArgs(argc, argv);
  // init top verilog instance
  top = new Vfloppy_track_encoder;

  // init trace dump
  Verilated::traceEverOn(true);
  tfp = new VerilatedVcdC;
  top->trace (tfp, 99);
  tfp->open ("floppy_track_encoder.vcd");

  srandom(time(NULL));

  for(track = 0;track < 80;track++) {
    for(side = 0;side < 2;side++) {

      printf(">>>>> doing track %d/side %d <<<<<<<\n", track, side);
    
      ocnt = 0;
      icnt = 0;
      
      if(!load_track(track, side))
	return 1;
      
      // initialize simulation inputs
      top->clk = 0;
      top->rst = 1;
      top->sides = 1;
      top->side = side;
      top->track = track;
      
      step();
      step();
      step();
    
      top->rst = 0;
      step_n(13000);
      
      printf("done\n");
    }
  }

  tfp->close();
  
  if(fail) printf("%d tests failed\n", fail);
  else     printf("all tests passed\n");
  
  exit(0);
}

