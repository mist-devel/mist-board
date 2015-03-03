#include "Vsd_card.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include "integer.h"
extern "C"
{
  #include "spi.h"
  #include "mmc.h"
  #include "simpledir.h"
  #include "simplefile.h"
  void hexdump(void *, uint16_t, uint16_t);
}

void hexdump(void *data, uint16_t size, uint16_t offset) {
  uint8_t i, b2c;
  uint16_t n=0;
  char *ptr = (char*)data;

  if(!size) return;

  while(size>0) {
    printf("%04x: ", n + offset);

    b2c = (size>16)?16:size;
    for(i=0;i<b2c;i++)      printf("%02x ", 0xff&ptr[i]);
    printf("  ");
    for(i=0;i<(16-b2c);i++) printf("   ");
    for(i=0;i<b2c;i++)      printf("%c", isprint(ptr[i])?ptr[i]:'.');
    printf("\n");
    ptr  += b2c;
    size -= b2c;
    n    += b2c;
  }
}

Vsd_card* top = NULL;
VerilatedVcdC* tfp = NULL;
int evcnt = 0;

void dump() {
  top->eval();
  tfp->dump (evcnt++);
}

void host_init() {
  // csd/cid
  u08 cid_csd[] = {
    0x3e, 0x00, 0x00, 0x34, 0x38, 0x32, 0x44, 0x00, 
    0x00, 0x38, 0x87, 0x43, 0xd8, 0x00, 0xc7, 0x0b,
    0x00, 0x7f, 0x00, 0x32, 0x5b, 0x59, 0x83, 0xbc, 
    0xf6, 0xdb, 0xff, 0x9f, 0x96, 0x40, 0x00, 0x93,
    0x00
  };
  
  int i;

  for(i=0;i<0x21;i++) {
    //    printf("INIT(%x)\n", cid_csd[i]);

    top->io_din = cid_csd[i];
    top->io_din_strobe = 1;
    dump();
    top->io_din_strobe = 0;
    dump();
  }
}

extern "C" void wait_us(int);

void spiReceiveData(u08 * from, u08 * to) {
  int i;
  for(i=0;i<512;i++)
    *from++ = spiTransferByte(*to++);

  //  hexdump(from-512, 512, 0);
}

void spiInit() {}
void set_spi_clock_freq() {}
void wait_us(int) {}

void mmcChipSelect(int select) {
  top->sd_cs = select?0:1;
}

void check4io() {
  static int state = 0;
  static u08 buffer[512];

  // check for external request 
  if(top->io_rd) {
    if(!state) {
      FILE *file = fopen("card.img", "rb");
      if(!file) { perror(""); exit(-1); }
      fseek(file, 512*top->io_lba, SEEK_SET);
      fread(buffer, 1, 512, file);
      fclose(file);

      //      printf("SD RD %d\n", top->io_lba);
      top->io_ack = 1;
      dump();
      state = 512;
    }
  }

  if(state != 0) {
    //    printf("tx[%d]=%x\n", 512-state, buffer[512-state]);

    top->io_din = buffer[512-state];
    top->io_din_strobe = 1;
    dump();
    top->io_din_strobe = 0;
    dump();

    state--;

    if(state == 0) {
      //      printf("TX done\n");
      top->io_ack = 0;
      dump();
    }
  }
}

u08 spiTransferByte(u08 byte) {
  int i;
  u08 rval = 0;

  //  printf("SPI(%x)=", byte);

  check4io();

  dump();

  for(i=0;i<8;i++) {
    top->sd_sdi = (byte & 0x80)?1:0;

    dump();
    top->sd_sck = 1;
    dump();
    top->sd_sck = 0;
  
    rval = (rval << 1)|(top->sd_sdo?1:0);

    byte <<= 1;
  }
  dump();

  //  printf("%x\n", rval);

  return rval;
}

u08 spiTransferFF() {
  return spiTransferByte(0xff);
}

void spiTx1(int i) {
  while(i--) {
    top->sd_sdi = 1;

    dump();
    top->sd_sck = 1;
    dump();
    top->sd_sck = 0;
    dump();
  }
  dump();
}

#define DIR_INIT_MEMSIZE 16*1024
u08 mem[DIR_INIT_MEMSIZE];
char ROM_DIR[]="/atari800/rom";

int main(int argc, char **argv, char **env) {
  struct SimpleFile *file;
  int i;
  int clk;
  Verilated::commandArgs(argc, argv);
  // init top verilog instance
  top = new Vsd_card;

  // init trace dump
  Verilated::traceEverOn(true);
  tfp = new VerilatedVcdC;
  top->trace (tfp, 1000);
  tfp->open ("sd_card.vcd");
 
  // initialize simulation inputs
  top->io_ack = 0;
  top->io_din = 0x00;
  top->io_din_strobe = 0;
  top->io_dout_strobe = 0;
  top->allow_sdhc = 1;

  top->sd_cs = 1;
  top->sd_sck = 0;
  top->sd_sdi = 1;

  file = (struct SimpleFile *)alloca(file_struct_size());
  file_init(file);
  
  host_init();

  if (SimpleFile_OK == dir_init((void *)mem, DIR_INIT_MEMSIZE)) {
    struct SimpleDirEntry * entries = dir_entries(ROM_DIR);
    if (SimpleFile_OK == file_open_name_in_dir(entries, "atarixl.rom", file)) {
      unsigned char b[512];
      int r = 0, total = 0;

      // dump current contents
      printf("atarixl.rom found\n");

      while((SimpleFile_OK == file_read(file, b, 512, &r)) && (r > 0)) {
	//	printf("read %d\n", r);
	total += r;
      }

      printf("read total of %d bytes\n", total);

    } else
      printf("atarixl.rom not found\n");
  } else
    printf("dir init failed\n");

  tfp->close();

  printf("MMC access done\n");

  exit(0);
}

