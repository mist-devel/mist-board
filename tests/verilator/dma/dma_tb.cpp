// TODO: include real tos.c

#include "Vdma.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

Vdma* top = NULL;
VerilatedVcdC* tfp = NULL;

double time_ns = 0;

#define MEMBASE 0xfc0000
#define MEMSIZE 256*1024
unsigned char mem[MEMSIZE];

#define MHZ2NS(a)  (1000000000.0/(a))
#define CLK        (8000000.0)

void hexdump(void *data, int size) {
  int i, b2c, n=0;
  char *ptr = (char*)data;

  if(!size) return;

  while(size>0) {
    printf("  %04x: ", n);
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

unsigned long cpu_read_addr = 0;
unsigned short cpu_read_data;

unsigned long cpu_write_addr = 0;
unsigned short cpu_write_data;

void eval(void) {
  static int last_clk = 0;

  // evaluate recent changes
  top->eval();
  tfp->dump(time_ns);

  // eval on negedge of clk
  if(!top->clk && last_clk) {

    // check if someone wants to read
    if(top->ram_read) {
      unsigned short data = 0;
      unsigned long addr = top->ram_addr<<1;
      unsigned char *ptr = mem+addr-MEMBASE;
      
      if((addr >= MEMBASE) && (addr < MEMBASE+MEMSIZE))
	data = 256*ptr[0] + ptr[1];
      else
	printf("Reading outside range: %lx\n", addr);

      //      printf("    RAM_READ(%lx)=%x\n", addr, data);
      top->ram_din = data;
    }
    
    // check if someone wants to write
    if(top->ram_write) {
      unsigned long addr = top->ram_addr<<1;
      unsigned short data = 
	((top->ram_dout & 0xff)<<8) | ((top->ram_dout & 0xff00)>>8);
      
      //      printf("    RAM_WRITE(%lx, %x)\n", addr, top->ram_dout);
      
      if((addr >= MEMBASE) && (addr < MEMBASE+MEMSIZE)) 
	*(unsigned short*)(mem+addr-MEMBASE) = data;
      else
	printf("Writing outside range: %lx\n", addr);
    }
  }
  last_clk = top->clk;
}

// advance time and create valid 8 Mhz clock and signals
// derived from it 
void wait_ns(double n) {
  static int clk_time = 0;

  eval();

  // check if next clk event is within waiting period
  while(clk_time <= n) {
    time_ns += clk_time;    // advance time to next clk event
    n -= clk_time;          // reduce remainung waiting time

    // process change on clk 
    top->clk = !top->clk;

    // cpu reads on falling clock edge
    if((!top->clk) && (top->bus_cycle == 0)) {
      // read access in progress?
      if(top->cpu_sel && top->cpu_rw) {
	cpu_read_data = top->cpu_dout;
	cpu_read_addr = 0;
      }
    }

    if(top->clk) {
      // do everything that's supposed to happen on the rising
      // edge of clk
      top->bus_cycle = (top->bus_cycle + 1)&3;
      top->cpu_sel = 0;	  

      if(top->bus_cycle == 0) {
	if(cpu_read_addr) {
	  // perform cpu read access
	  top->cpu_sel = (cpu_read_addr & ~0xf) == 0xff8600;
	  top->cpu_addr = (cpu_read_addr & 0x0f)>>1;
	  top->cpu_rw = 1;
	  top->cpu_uds = top->cpu_lds = 0;
	} 

	// perform cpu write access
	if(cpu_write_addr) {
	  top->cpu_sel = (cpu_write_addr & ~0xf) == 0xff8600;
	  top->cpu_addr = (cpu_write_addr & 0x0f)>>1;
	  top->cpu_rw = 0;
	  top->cpu_din = cpu_write_data;
	  top->cpu_uds = top->cpu_lds = 0;
	  cpu_write_addr = 0;
	}
      }
    }

    eval();

    clk_time = MHZ2NS(CLK)/2; // next clk change in 62.5ns
  }

  // next event is when done waiting
  time_ns += n; // advance time
  clk_time -= n;
}

void wait_us(double n) {
  wait_ns(n * 1000.0);
}

void wait_ms(double n) {
  wait_us(n * 1000.0);
}

void cpu_write(unsigned long addr, unsigned short data) {
  cpu_write_addr = addr;
  cpu_write_data = data;
  wait_us(1);               // wait two 2MHz system cycles
}

unsigned short cpu_read(unsigned long addr) {
  cpu_read_addr = addr;
  wait_us(1);               // wait two 2MHz system cycles
  return cpu_read_data;
}

#define SPI_CLK  24000000.0
#define SPI_CLK_NS  MHZ2NS(SPI_CLK)

// send a byte over spi
unsigned char SPI(unsigned char byte) {
  unsigned char bit;
  unsigned char retval = 0;

  // spi at 24Mhz: complete cycle = 41.6666ns

  // data has to be stable on pos edge of sck
  for(bit=0;bit<8;bit++) {
    wait_ns(SPI_CLK_NS/4);
    top->sck = 0;
    wait_ns(SPI_CLK_NS/4);
    top->sdi = (byte & (0x80>>bit))?1:0;
    retval = (retval << 1) | (top->sdo?1:0);
    wait_ns(SPI_CLK_NS/4);
    top->sck = 1;
    wait_ns(SPI_CLK_NS/4);
  }

  return retval;
}

#define SPI_WRITE(a) SPI(a)

void EnableFpga(void) {
  wait_ns(100);
  top->ss = 0;
  wait_ns(100);
}

void DisableFpga(void) {
  wait_ns(200);
  top->ss = 1;
  wait_ns(10);
}

// ------- routines takes from firmware tos.c ----------------
#define MIST_SET_ADDRESS  0x01
#define MIST_WRITE_MEMORY 0x02
#define MIST_READ_MEMORY  0x03
#define MIST_SET_CONTROL  0x04
#define MIST_GET_DMASTATE 0x05   // reads state of dma and floppy controller
#define MIST_ACK_DMA      0x06   // acknowledge a dma command
#define MIST_SET_VADJ     0x09
#define MIST_NAK_DMA      0x0a   // reject a dma command

static void mist_memory_set_address(unsigned long a, unsigned char s, char rw) {
  a |= rw?0x1000000:0;
  a >>= 1;

  EnableFpga();
  SPI(MIST_SET_ADDRESS);
  SPI(s);
  SPI((a >> 16) & 0xff);
  SPI((a >>  8) & 0xff);
  SPI((a >>  0) & 0xff);
  DisableFpga();
}

static void mist_memory_write(char *data, unsigned long words) {

  EnableFpga();
  SPI(MIST_WRITE_MEMORY);

  while(words--) {
    SPI_WRITE(*data++);
    SPI_WRITE(*data++);
  }

  DisableFpga();
}

static void mist_memory_read(char *data, unsigned long words) {

  EnableFpga();
  SPI(MIST_READ_MEMORY);

  // transmitted bytes must be multiple of 2 (-> words)
  while(words--) {
    *data++ = SPI(0);
    *data++ = SPI(0);
    //    printf("SPI RX: %02x %02x\n", *(data-2), *(data-1));
  }

  DisableFpga();
}

void tos_set_video_adjust(unsigned char a, unsigned char b) {
  EnableFpga();
  SPI(MIST_SET_VADJ);
  SPI(a);
  SPI(b);
  DisableFpga();
}

static void mist_set_control(unsigned long ctrl) {
  EnableFpga();
  SPI(MIST_SET_CONTROL);
  SPI((ctrl >> 24) & 0xff);
  SPI((ctrl >> 16) & 0xff);
  SPI((ctrl >>  8) & 0xff);
  SPI((ctrl >>  0) & 0xff);
  DisableFpga();
}

static void mist_get_dmastate(unsigned char *buffer) {
  int i;
  
  EnableFpga();
  SPI(MIST_GET_DMASTATE);
  for(i=0;i<16;i++)
    buffer[i] = SPI(0);
  DisableFpga();

  //  printf("  IO controllers view on DMA state:\n");
  //  hexdump(buffer, 16);

  // check if acsi is busy
  if(buffer[15] & 1) 
    printf("ACSI busy flag set\n");
    //    handle_acsi(buffer);

  // check if fdc is busy
  if(buffer[8] & 1) {
    printf("FDC busy flag set\n");
    printf("FDC CMD = %x\n", buffer[4]);
    printf("FDC TRK = %x\n", buffer[5]);
    printf("FDC SEC = %x\n", buffer[6]);
    printf("FDC DAT = %x\n", buffer[7]);
    printf("FDC FLG = %x\n", buffer[8]);
    
    //    handle_fdc(buffer);
  }
}

static void spi_noise() {
  int i, cnt = random()&15;
  for(i=0;i<cnt;i++)
    SPI(random());
}

void dma_address_verify(unsigned long a, unsigned char s, char rw) {
  unsigned char buffer[16];

  wait_us(5);

  // check that address has advanced correctly
  if((top->ram_addr<<1) != a) {
    printf("ERROR: DMA address is %x, should be %lx\n", 
	   top->ram_addr<<1, a);
    tfp->close();
    exit(0);
  }

  if(top->v__DOT__dma_scnt != s) {
    printf("  ERROR: Sector count is %d, should be %d\n", 
	   top->v__DOT__dma_scnt, s);
    tfp->close();
    exit(0);
  }

  // check that direction matches 
  if(top->v__DOT__dma_direction_out != rw) {
    printf("  ERROR: Direction is incorrect, is %d, should be %d\n", 
	   top->v__DOT__dma_direction_out, rw);
    tfp->close();
    exit(0);
  }

  // cpu only works if system is not in reset
  if(!top->reset) {
    unsigned long cpu_dma_addr = 
      (cpu_read(0xFF8609)<<16) | (cpu_read(0xFF860B)<<8) | cpu_read(0xFF860D);
  
    // check that dma address visible to cpu matches
    if(cpu_dma_addr != a) { 
      printf("ERROR: cpu visible DMA address is %lx, should be %lx\n", 
	     cpu_dma_addr, a);
      tfp->close();
      exit(0);
    }
    
    // enable access to sector count register
    cpu_write(0xFF8606, 0x10);

    unsigned char cpu_dma_scnt = cpu_read(0xFF8604);
    if(cpu_dma_scnt != s) {
      printf("  ERROR: CPU visible sector count is %d, should be %d\n", 
	     cpu_dma_scnt, s);
      tfp->close();
      exit(0);
    }
  }
    
  // and check address and sector count encoded in dma state
  mist_get_dmastate(buffer);  

  //  printf("  FIFO: r=%d, w=%d\n", (buffer[10]>>4)&0x0f, buffer[10]&0x0f);  

  unsigned long ioc_dma_addr = 
    (buffer[0] << 16) + (buffer[1] << 8) + (buffer[2]&0xfe); 

  if(ioc_dma_addr != a) { 
    printf("ERROR: io controller visible DMA address is %lx, should be %lx\n", 
	   ioc_dma_addr, a);
    tfp->close();
    exit(0);
  }
  
  if(buffer[3] != s) {
    printf("  ERROR: IO controller visible sector count is %d, should be %d\n",
	   buffer[3], s);
    tfp->close();
    exit(0);
  }

  printf("  dir %s, scnt %d, addr $%lx ok. CPU %s\n", 
	 rw?"out":"in", s, a, top->reset?"ignored":"ok");
}

void port_test() {
  printf("== IO controller port test ==\n");

  // test some config/setup routines
  tos_set_video_adjust(0x12, 0x34);
  if(top->video_adj != 0x1234) {
    printf("ERROR: setting vadj failed\n");
    tfp->close();
    exit(1);
  } else
    printf("  Video adjustment ok\n");

  mist_set_control(0x12345678);
  if(top->ctrl_out != 0x12345678) {
    printf("ERROR: setting control failed\n");
    tfp->close();
    exit(1);
  } else
    printf("  Control register write ok\n");
}

// $FF8606|word |DMA mode/status                 BIT 8 7 6 . 4 3 2 1 .|W
//        |     |0 - read FDC/HDC,1 - write ---------' | | | | | | |  |
//        |     |0 - HDC access,1 - FDC access --------' | | | | | |  |
//        |     |0 - DMA on,1 - no DMA ------------------' | | | | |  |
//        |     |Reserved ---------------------------------' | | | |  |
//        |     |0 - FDC reg,1 - sector count reg -----------' | | |  |
//        |     |0 - FDC access,1 - HDC access ----------------' | |  |
//        |     |0 - pin A1 low, 1 - pin A1 high ----------------' |  |
//        |     |0 - pin A0 low, 1 - pin A0 high ------------------'  |

void dma_mode_dump() {
  printf(">> DMA mode = %x\n", top->v__DOT__dma_mode);

  if(!(top->v__DOT__dma_mode & 0x100)) 
    printf(" - DMA read (%s)\n", top->v__DOT__dma_direction_out?"write":"read"); 
  else 
    printf(" - DMA write (%s)\n", top->v__DOT__dma_direction_out?"write":"read");
  if(!(top->v__DOT__dma_mode & 0x80))  printf(" - ACSI DMA\n"); else printf(" - FDC DMA\n");
  if(!(top->v__DOT__dma_mode & 0x40))  printf(" - DMA on\n"); else printf(" - DMA off\n");
  if(!(top->v__DOT__dma_mode & 0x10))  printf(" - FDC/ACSI reg\n"); else printf(" - Sector count\n");
  if(!(top->v__DOT__dma_mode & 0x08))  printf(" - FDC access\n"); else printf(" - ACSI access\n");
  printf(" - A1/A0 = %d\n", (top->v__DOT__dma_mode >> 1)&3); 

  // fdc registers        
  printf("FDC CMD: %x\n", top->v__DOT__fdc__DOT__cmd);
  printf("FDC TRK: %x\n", top->v__DOT__fdc__DOT__track);
  printf("FDC SEC: %x\n", top->v__DOT__fdc__DOT__sector);
  printf("FDC DAT: %x\n", top->v__DOT__fdc__DOT__data);
}

void dma_cpu_test() {
  unsigned char buffer[16];

  // ----- now start a dma transfer from the cpu interface -----

  printf("== Core DMA write test ==\n");
  
  dma_mode_dump();

  // set dma address
  cpu_write(0xFF8609, 0xfc);
  cpu_write(0xFF860B, 0x00);
  cpu_write(0xFF860D, 0x00);
  
  // enable access to sector count register
  cpu_write(0xFF8606, 0x10);

  dma_mode_dump();

  // write 1 to sector counter register (starts dma on write to io controller)
  cpu_write(0xFF8604, 0x01);

  dma_mode_dump();

  // dma transfer itself is done by the io controller

#define dmal 0xff860d
#define dmam 0xff860b
#define dmah 0xff8609

#define fdcc 0xff8604
#define dmac 0xff8606

  mist_get_dmastate(buffer);

  // a2 = dmac, a3 = fdcc
  cpu_write(dmac, 0x82); // *Track register
  dma_mode_dump();
  
  printf("current track = %d\n", cpu_read(fdcc)); //* Current track
  cpu_write(fdcc, 0x01);
  printf("current track = %d\n", cpu_read(fdcc)); //* Current track

  cpu_write(dmac, 0x86); // *Data register
  cpu_write(fdcc, 0x01);

  mist_get_dmastate(buffer);

  printf("181:\n");
  cpu_write(dmac, 0x181); // *Data register

  dma_mode_dump();

  //      move.w #$13,(a3)  *Seek command, steprate 3ms
  //      bsr comexd 
}

void io_write_test(char *data, int size, int chunk_size) {
  printf("== IO controller DMA %d bytes %s write test ==\n", 
	 size, chunk_size?"chunky":"burst");

  if(chunk_size) printf("  Chunk size = %d\n", chunk_size);

  unsigned char scnt = (size+511)/512;
  printf("  Sector count will be %d\n", scnt);

  // destination address can be set externally
  mist_memory_set_address(MEMBASE, scnt, 0);
  dma_address_verify(MEMBASE, scnt, 0);

  // data is transferred in 16 bytes chunks
  unsigned long bytes = size & ~0x0f;

  // initiate dma transfer
  printf("  Sending %d bytes via dma, expecting %lu to arrive ...\n", 
	 size, bytes);

  if(chunk_size > 0) {
    int sent = 0;
    char *p = data;
    int s = size;
    while(s) {
      //      printf("chunk\n");
      int cs = (s>=chunk_size)?chunk_size:s;
      mist_memory_write(p, cs/2);
      p += chunk_size;
      s -= cs;
      sent += chunk_size;
      //      printf("after: sent=%d, rem=%d\n", sent, s);

      if(s)
	dma_address_verify(MEMBASE+(sent&~15), (s+511)/512, 0);
    }
  } else
    mist_memory_write(data, size/2);
	  
  wait_us(5);

  // check that data has arrived in memory
  if(memcmp(data, mem, bytes) != 0) {
    int i=0;
    while(data[i] == (char)(mem[i])) i++;

    printf("ERROR: dma verify failed at index %d\n", i);

    hexdump(data, 32);
    hexdump(mem, 32);

    tfp->close();
    exit(0);
  } else
    printf("  %ld bytes successfully verified\n", bytes);
  
  // if transferred bytes is not a multiple of 512, then scnt will not reach 0
  dma_address_verify(MEMBASE+bytes, (bytes&0x1ff)?1:0, 0);

  // printf("  RAM contents now:\n");
  //  hexdump(mem, 48);
}

void io_read_test(char *data, int size, int chunk_size) {
  unsigned char test_rx[size];

  // inject test data into memory
  memcpy(mem, data, size);

  // ----- read data back via DMA interface -----
  printf("== IO controller DMA %d bytes %s read test ==\n", 
	 size, chunk_size?"chunky":"burst");

  unsigned char scnt = (size+511)/512;
  printf("  Sector count will be %d\n", scnt);

  // data is transferred in 16 bytes chunks
  //  unsigned long bytes = (size+16) & ~0x0f;
  unsigned long bytes = (size+31) & ~0x0f;
  // but never more than scnt allows
  if(bytes > 512*scnt) bytes = 512*scnt;

  // re-set destination address as it has advanced during
  // the DMA transfer
  // address bit 24 == 1 -> dma read
  mist_memory_set_address(MEMBASE, scnt, 1);  

  // initiate dma transfer
  printf("  Receiving %d bytes via dma, expecting %d bytes to be read ...\n", 
	 size, bytes);
  
  // A whole turbo dma read of 16 bytes takes 8*250ns = 2us. 
  // We can start earlier since only one word has to be arrived
  // in the fifo for us to read. 
  wait_us(1);

  if(chunk_size > 0) {
    spi_noise();

    int mb = MEMBASE;
    char *p = (char*)test_rx;
    int s = size;
    while(s) {
      int cs = (s>=chunk_size)?chunk_size:s;
      mist_memory_read(p, cs/2);
      p += chunk_size;
      s -= cs;
      mb+=512;
      dma_address_verify(mb+(s?16:0), s/512, 1);
    }
  } else
    mist_memory_read((char*)test_rx, size/2);
  
  //  hexdump(test_rx, sizeof(test_rx));

  // check that data has arrived in buffer
  if(memcmp(test_rx, mem, size) != 0) {
    int i=0;
    while(test_rx[i] == mem[i]) i++;

    printf("ERROR: dma verify failed at index %d\n", i);

    hexdump(mem, 48);
    hexdump(test_rx, 48);

    tfp->close();
    exit(0);
  } else
    printf("  %ld bytes successfully verified\n", size);

  // the DMA will reload after this, so wait some time for it to get
  // into a stable (non-empty) state again
  wait_us(5);

  dma_address_verify(MEMBASE+bytes, (bytes&0x1ff)?1:0, 1);
}

int main(int argc, char **argv, char **env) {
  Verilated::commandArgs(argc, argv);
  // init top verilog instance
  top = new Vdma;

  srandom(time(NULL));

  // init trace dump
  Verilated::traceEverOn(true);
  tfp = new VerilatedVcdC;
  top->trace (tfp, 99);
  tfp->open ("dma.vcd");

  // initialize system inputs
  top->clk = 1;
  top->reset = 1;

  // enabling the turbo doesn't make much sense as the dma in non-turbo
  // at 2Mcycles/sec can transfer 4MBytes/sec is always faster than the
  // SPI at 24Mhz doing 3MBytes/sec
  top->turbo = 0;

  // init cpu interface
  top->cpu_sel <= 0;

  // init spi
  top->sdi = 1;
  top->ss = 1;
  top->sck = 1;

  // floppy
  top->drv_sel = 3;     // no drive delected
  top->drv_side = 0;
  top->fdc_wr_prot = 0;

  wait_us(1);

  port_test();

  unsigned char test[2048];
  int i;
#if 1
  for(i=0;i<sizeof(test);i++) test[i] = random();
#else
  for(i=0;i<sizeof(test);i++) test[i] = i;
#endif

  // small chunks (as e.q. inquiry would do)
  io_write_test((char*)test, 100, 20);  
 
#if 0
  // multiple of 16 but less than 512
  io_write_test((char*)test, 32, 0);  
  io_read_test((char*)test, 32, 0);

  // not multiple of 16
  io_write_test((char*)test, 40, 0);  
  io_read_test((char*)test, 40, 0);

  if(!top->v__DOT__dma_in_progress) {
    printf("ERROR: DMA is expected to still be active after incomplete transfer\n");
    tfp->close();
    exit(1);
  }
    
  // stop uncompleted DMA
  mist_memory_set_address(0,0,0);

  if(top->v__DOT__dma_in_progress) {
    printf("ERROR: DMA is expected to be stopped now\n");
    tfp->close();
    exit(1);
  }

  // multiple of 16 and multiple of 512
  io_write_test((char*)test, sizeof(test), 0);  
  io_read_test((char*)test, sizeof(test), 0);

  // leave reset
  top->reset = 0;
      
  // multiple of 16 and multiple of 512 in chunks
  io_write_test((char*)test, sizeof(test), 512);  
  io_read_test((char*)test, sizeof(test), 512);
#endif

  top->reset = 0;
  wait_ns(100);

  //   dma_cpu_test();

  tfp->close();

  exit(0);
 }

