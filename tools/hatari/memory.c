 /*
  * UAE - The Un*x Amiga Emulator - CPU core
  *
  * Memory management
  *
  * (c) 1995 Bernd Schmidt
  *
  * Adaptation to Hatari by Thomas Huth
  *
  * This file is distributed under the GNU Public License, version 2 or at
  * your option any later version. Read the file gpl.txt for details.
  */
const char Memory_fileid[] = "Hatari memory.c : " __DATE__ " " __TIME__;

#define NE_EMU

/*
  ne2000 remarks

  This file includes a ne2000 emulation which is ethernec compatible.
  It has been tested with STinG only and may lack features required for
  other drivers and operating systems.

  The current implementation was done to check the feasibility of an FPGA
  implementation. It thus doesn't implement the 16kBytes ring buffer but
  works with two single ethernet frame buffers to save FPGA space. This
  works but a "real" implementation inside hatari should implement the 
  ring buffer correctly.

  Also the network io routines should be moved into a seperate thread
  to not block emulation itself.

  The resulting binary needs to be run with root rights as sending and
  receiving raw ethernet frames requires this.

  This implementation has its own mac address (ba:db:ad:c0:ff:ee) and 
  looks like a completely seperate device to all other units in the
  network. However, the host itself cannot be reached by hatari this way.

  Network access is based on libpcap and the resulting binary needs to
  be linked against libpcap.

  This implementation collides with hataris internal cartridge and can
  thus e.g. not be used tegether with the extended video modes or any
  other feature that requires the cartridge.
*/


#ifdef NE_EMU
#define NE2000      // otherwise NE1000 
#include <pcap.h>
#endif

#include "config.h"
#include "sysdeps.h"
#include "hatari-glue.h"
#include "maccess.h"
#include "memory.h"

#include "main.h"
#include "tos.h"
#include "ide.h"
#include "ioMem.h"
#include "reset.h"
#include "stMemory.h"
#include "m68000.h"

#include "newcpu.h"


/* Set illegal_mem to 1 for debug output: */
#define illegal_mem 1


static uae_u32 STmem_size, TTmem_size = 0;
static uae_u32 TTmem_mask;

#define STmem_start  0x00000000
#define ROMmem_start 0x00E00000
#define IdeMem_start 0x00F00000
#define IOmem_start  0x00FF0000
#define TTmem_start  0x01000000

#define IdeMem_size  65536
#define IOmem_size  65536
#define ROMmem_size (0x00FF0000 - 0x00E00000)  /* So we cover both possible ROM regions + cartridge */

#define STmem_mask  0x00ffffff
#define ROMmem_mask 0x00ffffff
#define IdeMem_mask  (IdeMem_size - 1)
#define IOmem_mask  (IOmem_size - 1)


#ifdef SAVE_MEMORY_BANKS
addrbank *mem_banks[65536];
#else
addrbank mem_banks[65536];
#endif

#ifdef NO_INLINE_MEMORY_ACCESS
__inline__ uae_u32 longget (uaecptr addr)
{
    return call_mem_get_func (get_mem_bank (addr).lget, addr);
}
__inline__ uae_u32 wordget (uaecptr addr)
{
    return call_mem_get_func (get_mem_bank (addr).wget, addr);
}
__inline__ uae_u32 byteget (uaecptr addr)
{
    return call_mem_get_func (get_mem_bank (addr).bget, addr);
}
__inline__ void longput (uaecptr addr, uae_u32 l)
{
    call_mem_put_func (get_mem_bank (addr).lput, addr, l);
}
__inline__ void wordput (uaecptr addr, uae_u32 w)
{
    call_mem_put_func (get_mem_bank (addr).wput, addr, w);
}
__inline__ void byteput (uaecptr addr, uae_u32 b)
{
    call_mem_put_func (get_mem_bank (addr).bput, addr, b);
}
#endif


/* Some prototypes: */
extern void SDL_Quit(void);
static int STmem_check (uaecptr addr, uae_u32 size) REGPARAM;
static uae_u8 *STmem_xlate (uaecptr addr) REGPARAM;


/* A dummy bank that only contains zeros */

static uae_u32 dummy_lget(uaecptr addr)
{
    if (illegal_mem)
	write_log ("Illegal lget at %08lx\n", (long)addr);

    return 0;
}

static uae_u32 dummy_wget(uaecptr addr)
{
    if (illegal_mem)
	write_log ("Illegal wget at %08lx\n", (long)addr);

    return 0;
}

static uae_u32 dummy_bget(uaecptr addr)
{
    if (illegal_mem)
	write_log ("Illegal bget at %08lx\n", (long)addr);

    return 0;
}

static void dummy_lput(uaecptr addr, uae_u32 l)
{
    if (illegal_mem)
	write_log ("Illegal lput at %08lx\n", (long)addr);
}

static void dummy_wput(uaecptr addr, uae_u32 w)
{
    if (illegal_mem)
	write_log ("Illegal wput at %08lx\n", (long)addr);
}

static void dummy_bput(uaecptr addr, uae_u32 b)
{
    if (illegal_mem)
	write_log ("Illegal bput at %08lx\n", (long)addr);
}

static int dummy_check(uaecptr addr, uae_u32 size)
{
    if (illegal_mem)
	write_log ("Illegal check at %08lx\n", (long)addr);

    return 0;
}

static uae_u8 *dummy_xlate(uaecptr addr)
{
    write_log("Your Atari program just did something terribly stupid:"
              " dummy_xlate($%x)\n", addr);
    /*Reset_Warm();*/
    return STmem_xlate(addr);  /* So we don't crash. */
}


/* **** This memory bank only generates bus errors **** */

static uae_u32 BusErrMem_lget(uaecptr addr)
{
    if (illegal_mem)
	write_log ("Bus error lget at %08lx\n", (long)addr);

    M68000_BusError(addr, BUS_ERROR_READ);
    return 0;
}

static uae_u32 BusErrMem_wget(uaecptr addr)
{
    if (illegal_mem)
	write_log ("Bus error wget at %08lx\n", (long)addr);

    M68000_BusError(addr, BUS_ERROR_READ);
    return 0;
}

static uae_u32 BusErrMem_bget(uaecptr addr)
{
    if (illegal_mem)
	write_log ("Bus error bget at %08lx\n", (long)addr);

    M68000_BusError(addr, BUS_ERROR_READ);
    return 0;
}

static void BusErrMem_lput(uaecptr addr, uae_u32 l)
{
    if (illegal_mem)
	write_log ("Bus error lput at %08lx\n", (long)addr);

    M68000_BusError(addr, BUS_ERROR_WRITE);
}

static void BusErrMem_wput(uaecptr addr, uae_u32 w)
{
    if (illegal_mem)
	write_log ("Bus error wput at %08lx\n", (long)addr);

    M68000_BusError(addr, BUS_ERROR_WRITE);
}

static void BusErrMem_bput(uaecptr addr, uae_u32 b)
{
    if (illegal_mem)
	write_log ("Bus error bput at %08lx\n", (long)addr);

    M68000_BusError(addr, BUS_ERROR_WRITE);
}

static int BusErrMem_check(uaecptr addr, uae_u32 size)
{
    if (illegal_mem)
	write_log ("Bus error check at %08lx\n", (long)addr);

    return 0;
}

static uae_u8 *BusErrMem_xlate (uaecptr addr)
{
    write_log("Your Atari program just did something terribly stupid:"
              " BusErrMem_xlate($%x)\n", addr);

    /*M68000_BusError(addr);*/
    return STmem_xlate(addr);  /* So we don't crash. */
}


/* **** ST RAM memory **** */

/*static uae_u8 *STmemory;*/
#define STmemory STRam

static uae_u32 STmem_lget(uaecptr addr)
{
    addr -= STmem_start & STmem_mask;
    addr &= STmem_mask;
    return do_get_mem_long(STmemory + addr);
}

static uae_u32 STmem_wget(uaecptr addr)
{
    addr -= STmem_start & STmem_mask;
    addr &= STmem_mask;
    return do_get_mem_word(STmemory + addr);
}

static uae_u32 STmem_bget(uaecptr addr)
{
    addr -= STmem_start & STmem_mask;
    addr &= STmem_mask;
    return STmemory[addr];
}

static void STmem_lput(uaecptr addr, uae_u32 l)
{
    addr -= STmem_start & STmem_mask;
    addr &= STmem_mask;
    do_put_mem_long(STmemory + addr, l);
}

static void STmem_wput(uaecptr addr, uae_u32 w)
{
    addr -= STmem_start & STmem_mask;
    addr &= STmem_mask;
    do_put_mem_word(STmemory + addr, w);
}

static void STmem_bput(uaecptr addr, uae_u32 b)
{
    addr -= STmem_start & STmem_mask;
    addr &= STmem_mask;
    STmemory[addr] = b;
}

static int STmem_check(uaecptr addr, uae_u32 size)
{
    addr -= STmem_start & STmem_mask;
    addr &= STmem_mask;
    return (addr + size) <= STmem_size;
}

static uae_u8 *STmem_xlate(uaecptr addr)
{
    addr -= STmem_start & STmem_mask;
    addr &= STmem_mask;
    return STmemory + addr;
}


/*
 * **** ST RAM system memory ****
 * We need a separate mem bank for this region since the first 0x800 bytes on
 * the ST can only be accessed in supervisor mode. Note that the very first
 * 8 bytes of the ST memory are also a mirror of the TOS ROM, so they are write
 * protected!
 */
static uae_u32 SysMem_lget(uaecptr addr)
{
    if(addr < 0x800 && !regs.s)
    {
      M68000_BusError(addr, BUS_ERROR_READ);
      return 0;
    }

    addr -= STmem_start & STmem_mask;
    addr &= STmem_mask;

    return do_get_mem_long(STmemory + addr);
}

static uae_u32 SysMem_wget(uaecptr addr)
{
    if(addr < 0x800 && !regs.s)
    {
      M68000_BusError(addr, BUS_ERROR_READ);
      return 0;
    }

    addr -= STmem_start & STmem_mask;
    addr &= STmem_mask;

    return do_get_mem_word(STmemory + addr);
}

static uae_u32 SysMem_bget(uaecptr addr)
{
    if(addr < 0x800 && !regs.s)
    {
      M68000_BusError(addr, BUS_ERROR_READ);
      return 0;
    }

    addr -= STmem_start & STmem_mask;
    addr &= STmem_mask;

    return STmemory[addr];
}

static void SysMem_lput(uaecptr addr, uae_u32 l)
{
    if(addr < 0x8 || (addr < 0x800 && !regs.s))
    {
      M68000_BusError(addr, BUS_ERROR_WRITE);
      return;
    }

    addr -= STmem_start & STmem_mask;
    addr &= STmem_mask;

    do_put_mem_long(STmemory + addr, l);
}

static void SysMem_wput(uaecptr addr, uae_u32 w)
{
    if(addr < 0x8 || (addr < 0x800 && !regs.s))
    {
      M68000_BusError(addr, BUS_ERROR_WRITE);
      return;
    }

    addr -= STmem_start & STmem_mask;
    addr &= STmem_mask;

    do_put_mem_word(STmemory + addr, w);
}

static void SysMem_bput(uaecptr addr, uae_u32 b)
{
    if(addr < 0x8 || (addr < 0x800 && !regs.s))
    {
      M68000_BusError(addr, BUS_ERROR_WRITE);
      return;
    }

    addr -= STmem_start & STmem_mask;
    addr &= STmem_mask;
    STmemory[addr] = b;
}


/*
 * **** Void memory ****
 * Between the ST-RAM end and the 4 MB barrier, there is a void memory space:
 * Reading always returns the same value and writing does nothing at all.
 */

static uae_u32 VoidMem_lget(uaecptr addr)
{
    return 0;
}

static uae_u32 VoidMem_wget(uaecptr addr)
{
    return 0;
}

static uae_u32 VoidMem_bget(uaecptr addr)
{
    return 0;
}

static void VoidMem_lput(uaecptr addr, uae_u32 l)
{
}

static void VoidMem_wput(uaecptr addr, uae_u32 w)
{
}

static void VoidMem_bput (uaecptr addr, uae_u32 b)
{
}

static int VoidMem_check(uaecptr addr, uae_u32 size)
{
    if (illegal_mem)
	write_log ("Void memory check at %08lx\n", (long)addr);

    return 0;
}

static uae_u8 *VoidMem_xlate (uaecptr addr)
{
    write_log("Your Atari program just did something terribly stupid:"
              " VoidMem_xlate($%x)\n", addr);

    return STmem_xlate(addr);  /* So we don't crash. */
}


/* **** TT fast memory (not yet supported) **** */

static uae_u8 *TTmemory;

static uae_u32 TTmem_lget(uaecptr addr)
{
    addr -= TTmem_start & TTmem_mask;
    addr &= TTmem_mask;
    return do_get_mem_long(TTmemory + addr);
}

static uae_u32 TTmem_wget(uaecptr addr)
{
    addr -= TTmem_start & TTmem_mask;
    addr &= TTmem_mask;
    return do_get_mem_word(TTmemory + addr);
}

static uae_u32 TTmem_bget(uaecptr addr)
{
    addr -= TTmem_start & TTmem_mask;
    addr &= TTmem_mask;
    return TTmemory[addr];
}

static void TTmem_lput(uaecptr addr, uae_u32 l)
{
    addr -= TTmem_start & TTmem_mask;
    addr &= TTmem_mask;
    do_put_mem_long(TTmemory + addr, l);
}

static void TTmem_wput(uaecptr addr, uae_u32 w)
{
    addr -= TTmem_start & TTmem_mask;
    addr &= TTmem_mask;
    do_put_mem_word(TTmemory + addr, w);
}

static void TTmem_bput(uaecptr addr, uae_u32 b)
{
    addr -= TTmem_start & TTmem_mask;
    addr &= TTmem_mask;
    TTmemory[addr] = b;
}

static int TTmem_check(uaecptr addr, uae_u32 size)
{
    addr -= TTmem_start & TTmem_mask;
    addr &= TTmem_mask;
    return (addr + size) <= TTmem_size;
}

static uae_u8 *TTmem_xlate(uaecptr addr)
{
    addr -= TTmem_start & TTmem_mask;
    addr &= TTmem_mask;
    return TTmemory + addr;
}


/* **** ROM memory **** */

uae_u8 *ROMmemory;

static uae_u32 ROMmem_lget(uaecptr addr)
{
    addr -= ROMmem_start & ROMmem_mask;
    addr &= ROMmem_mask;
    return do_get_mem_long(ROMmemory + addr);
}

static uae_u32 ROMmem_wget(uaecptr addr)
{
    addr -= ROMmem_start & ROMmem_mask;
    addr &= ROMmem_mask;
    return do_get_mem_word(ROMmemory + addr);
}

void hexdump(void *data, int size) {
  int i, b2c;
  int n=0;
  char *ptr = data;

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

#ifdef NE_EMU

// prom contents
static const u_char mac[] = { 0xba, 0xdb, 0xad, 0xc0, 0xff, 0xee };

// pcap connection
pcap_t* pcap = NULL;

#define ETH_MIN_FRAME     64
#define ETH_MAX_FRAME   1536
char tx_buffer[ETH_MAX_FRAME];
int tx_cnt = 0;
char rx_buffer[ETH_MAX_FRAME+4];   // -"- incl. space for 4 byte packet header
int rx_cnt;
int rx_busy = 0;

// ne internal registers
static unsigned char isr, imr, bnry;
static unsigned char cr, dcr, rcr, tcr, tpsr, curr;
static unsigned char pstart, pstop, par[6], mar[8];
static unsigned short rbcr, rsar, tbcr;

static char reset, dma;

char *ne_reg_name(int addr, int rd) {
  static const char *read_names_p0[] = {
    "CR", "CLDA0", "CLDA1", "BNRY", "TSR", "NCR", "FIFO", "ISR", "CRDA0", "CRDA1", 
    "80191D0", "80191D1", "RSR", "CNTR0", "CNTR1", "CNTR2" };
  static const char *write_names_p0[] = {
    "CR", "PSTART", "PSTOP", "BNRY", "TPSR", "TBCR0", "TBCR1", "ISR", "RSAR0", "RSAR1",
    "RBCR0", "RBCR1", "RCR", "TCR", "DCR", "IMR" };
  static const char *names_p1[] = {
    "CR", "PAR0", "PAR1", "PAR2", "PAR3", "PAR4", "PAR5", "CURR", "MAR0", "MAR1", 
    "MAR2", "MAR3", "MAR4", "MAR5", "MAR6", "MAR7" };

  static const char name_dma[] = "DMA";
  static const char name_reset[] = "RESET";

  char ps = (cr>>6)&3;

  if(!pcap) {
    fprintf(stderr, "pcap not open, opening it\n");

    // Open a PCAP packet capture descriptor for the specified interface.
    char pcap_errbuf[PCAP_ERRBUF_SIZE];
    pcap_errbuf[0]='\0';
    pcap=pcap_open_live("eth1",1600,1,1,pcap_errbuf);
    if (pcap_errbuf[0]!='\0') 
      fprintf(stderr, "%s\n",pcap_errbuf);

    if (!pcap) {
      pcap=pcap_open_live("eth0",1600,1,1,pcap_errbuf);
      if (pcap_errbuf[0]!='\0') 
	fprintf(stderr, "%s\n",pcap_errbuf);
      
      if (!pcap) 
	exit(1);
    }

    if (pcap_setnonblock(pcap, 1, pcap_errbuf) == -1) {
      fprintf(stderr, "pcap_setnonblock failed: %s\n", pcap_errbuf);
      exit(2);
    }
  }

  // page select
  if(ps != 0 && ps != 1) {
    fprintf(stderr, "unexpected page =%d\n", ps);
    exit(1);
  }

  if(ps == 0) {
    if(rd && (addr < 0x10)) return read_names_p0[addr];
    if(!rd && (addr < 0x10)) return write_names_p0[addr];
  } else if(ps == 1) {
    if(addr < 0x10) return names_p1[addr];
  }

  if((addr & 0x18) == 0x10) return name_dma;
  if((addr & 0x18) == 0x18) return name_reset;

  fprintf(stderr, "unexpected addr %x\n", addr);
  exit(1);
  return NULL;
}

int ne_reg_read(int addr) {
  int retval = 0;

  // cr, reset and dma are always accessible
  if(addr == 0)
    return cr;

  if(addr >= 0x18 && addr < 0x20) {
    // also copy mac into buffer
#ifdef NE2000
    // ne2000 doubles every byte
    u_char *s=mac, *d=rx_buffer, i;
    for(i=0;i<6;i++) {
      *d++ = *s;
      *d++ = *s++;
    }
#else
    // ne1000 handles prom correctly on 8 bits
    memcpy(rx_buffer, mac, sizeof(mac));
#endif

    reset = 1;     // read to reset register sets reset
    isr |= 0x80;   // set reset flag in isr
    return 0;
  }

  if(addr >= 0x10 && addr < 0x18) {
    if(!--rbcr) {
      fprintf(stderr, "-----> all bytes read!\n");
      isr |= 0x40;    // singal end of remote transfer
    }

    return 0xff & rx_buffer[rx_cnt++];
  }

  char ps = (cr >> 6) & 3;
  if(ps == 0) {
    switch(addr) {
    case 0x04:
      return 0x23;  // tx ok
      break;

    case 0x07:
      return isr;
      break;
      
    default:
      fprintf(stderr, "unexpected page 0 read at %s\n", ne_reg_name(addr, 1));
      exit(-1);
    }
  } else if(ps == 1) {
    switch(addr) {
    case 0x07:
      return curr;
      break;
      
    default:
      fprintf(stderr, "unexpected page 1 read on %s\n", ne_reg_name(addr, 1));
      exit(-1);
    }
  } else {
    fprintf(stderr, "unexpected page %d read on %x\n", ps, addr);
    exit(-1);
  }
  
  return retval;
}

void ne_reg_write(int addr, int value) {

  // cr, reset and dma are always accessible
  if(addr == 0) {
    cr = value;

    char ps =  (cr>>6)&3;
    char rd = (cr>>3)&7;

    // evaluate command a little further
    fprintf(stderr, "  -> command: PS=%d, RD=%d, TXP=%d, STA=%d, STP=%d\n", 
	   ps, rd, (cr>>2)&1, (cr>>1)&1, (cr>>0)&1);

    if(rd == 1) {
      fprintf(stderr, "  -> remote read (start=%x, count=%d) -> start read at %d\n", rsar, rbcr, rsar&0xff);
      rx_cnt = rsar & 0xff;
    } else if(rd == 2) {
      fprintf(stderr, "  -> remote write\n");
      tx_cnt = 0;
    } else if((rd&4) == 4) {
      fprintf(stderr, "  -> abort DMA\n");
    } else {
      fprintf(stderr, "  -> unexpected rd\n");
      exit(-1);
    }

    if((cr>>2)&1) {
      fprintf(stderr, "TX (written %d, tbcr %d, rbcr %d) ...\n", tx_cnt, tbcr, rbcr);
      hexdump(tx_buffer, tx_cnt);

      // Write the Ethernet frame to the interface.
      if (pcap_inject(pcap,tx_buffer,tx_cnt)==-1) {
        pcap_perror(pcap,0);
        pcap_close(pcap);
        exit(1);
      }
      isr |= 2; // flag tx irq
    }

    return;
  }
    
  if(addr >= 0x18 && addr < 0x20) {
    reset = 0;    // write to reset register clears reset
    return;
  }

  if(addr >= 0x10 && addr < 0x18) {
    // write on data port ...
    tx_buffer[tx_cnt++] = value;

    if(!--tbcr) {
      fprintf(stderr, "-----> all bytes written!\n");
      isr |= 0x40;    // singal end of remote transfer
    }

    return;
  }

  char ps = (cr >> 6) & 3;
  if(ps == 0) {
    switch(addr) {
    case 0x01:
      pstart = value;
      break;

    case 0x02:
      pstop = value;
      break;

    case 0x03:
      bnry = value;
      break;
      
    case 0x04:
      tpsr = value;
      break;
      
    case 0x05:
      tbcr = (tbcr & 0xff00) | (value & 0x00ff);
      break;
      
    case 0x06:
      tbcr = (tbcr & 0x00ff) | ((value<<8) & 0xff00);
      break;

    case 0x07:
      // clear rx counter if host acknowledges rx irq. This allows to re-use the input buffer
      if(value & 1) {
	fprintf(stderr, "RX irq ack'd, allowing further rx\n");
	rx_busy = 0;
      }

      isr &= ~value;   // write to isr clears all bits written one
      break;
      
    case 0x08:
      rsar = (rsar & 0xff00) | (value & 0x00ff);
      break;
      
    case 0x09:
      rsar = (rsar & 0x00ff) | ((value<<8) & 0xff00);
      break;
      
    case 0x0a:
      rbcr = (rbcr & 0xff00) | (value & 0x00ff);
      break;
      
    case 0x0b:
      rbcr = (rbcr & 0x00ff) | ((value<<8) & 0xff00);
      break;
      
    case 0x0c:
      rcr = value;
      break;
      
    case 0x0d:
      tcr = value;
      break;
      
    case 0x0e:
      dcr = value;
      break;
      
    case 0x0f:
      imr = value;
      break;
      
    default:
      fprintf(stderr, "unexpected page 0 write to %s\n", ne_reg_name(addr, 0));
      exit(-1);
    }
  } else if(ps == 1) {
    if(addr >= 0x01 && addr < 0x07)
      par[addr-0x01] = value;
    else if(addr == 0x07)
      curr = value;
    else if(addr >= 0x08 && addr < 0x10)
      mar[addr-0x08] = value;
    else {
      fprintf(stderr, "unexpected page 1 write to %s\n", ne_reg_name(addr, 0));
      exit(-1);
    } 
  } else {
    fprintf(stderr, "unexpected page %d write to %s\n", ps, ne_reg_name(addr, 0));
    exit(-1);
  }
}
#endif

static uae_u32 ROMmem_bget(uaecptr addr)
{
#ifdef NE_EMU // enec stuff
  // check for incoming packets if everything has been processed
  if(pcap && !rx_busy) {
    struct pcap_pkthdr hdr;     /* pcap.h */
    const u_char *packet = pcap_next(pcap, &hdr);
    if(packet && (hdr.len <= ETH_MAX_FRAME)) {
      // check for correct destination mac (broadcast or own)
      if(((packet[0] == 0xff)&&(packet[1] == 0xff)&&(packet[2] == 0xff)&&
	  (packet[3] == 0xff)&&(packet[4] == 0xff)&&(packet[5] == 0xff)) ||
	 ((packet[0] == mac[0])&&(packet[1] == mac[1])&&(packet[2] == mac[2])&&
	  (packet[3] == mac[3])&&(packet[4] == mac[4])&&(packet[5] == mac[5]))) {
	int len = hdr.len;
	
	// min ethernet frame length is 64, ethernec driver will refuse shorter packets
	if(len < ETH_MIN_FRAME) len = ETH_MIN_FRAME;

	// check how many 256 byte pages this would need. The packet header is stored before,
	// so four more bytes are needed
	int pages = 1 + ((len+4) >> 8);

	// increase page counter accordingly
	while(pages--)
	  if(++curr == pstop) curr = pstart;

	// start with ne2000 header 
	rx_buffer[0] = 0x01;        // status ok
	rx_buffer[1] = curr;        // next page
	rx_buffer[2] = len & 0xff;
	rx_buffer[3] = len >> 8;

	// and append packet data
	memcpy(rx_buffer+4, packet, hdr.len);
	rx_busy = 1;

	fprintf(stderr, "RX forwarding %d bytes (%d received):\n", len, hdr.len);
	hexdump(tx_buffer, len);

	isr |= 0x01;   // rcv good
      }
    }
  }

  if((addr >= 0xfa0000)&&(addr < 0xfc0000)) {

    // disassemble rom port accesses into ne control signals
    int cread = (addr < 0xfb0000);   // /ROM4 is read, ROM3 is write
    int caddr = (addr >> 9)&0x1f;    // a0-a4
    int cwdata = (addr >> 1)&0xff;   // d0-d7 on write

    if(cread) { 
      int rval;
      
      // this is a "real" read
      fprintf(stderr, "NET IOR %s (%x) = ", ne_reg_name(caddr, 1), caddr);
      rval = ne_reg_read(caddr);
      fprintf(stderr, "%x\n", rval);
      return rval;
    } else {
      // this is a write accomplished via a read to a certain address
      fprintf(stderr, "NET IOW %s (%x) = $%x (%d)\n", ne_reg_name(caddr, 0), 
	     caddr, cwdata, cwdata);
      ne_reg_write(caddr, cwdata);
    }
  }
#endif

  addr -= ROMmem_start & ROMmem_mask;
  addr &= ROMmem_mask;
  return ROMmemory[addr];
}

static void ROMmem_lput(uaecptr addr, uae_u32 b)
{
    if (illegal_mem)
	write_log ("Illegal ROMmem lput at %08lx\n", (long)addr);

    M68000_BusError(addr, BUS_ERROR_WRITE);
}

static void ROMmem_wput(uaecptr addr, uae_u32 b)
{
    if (illegal_mem)
	write_log ("Illegal ROMmem wput at %08lx\n", (long)addr);

    M68000_BusError(addr, BUS_ERROR_WRITE);
}

static void ROMmem_bput(uaecptr addr, uae_u32 b)
{
    if (illegal_mem)
	write_log ("Illegal ROMmem bput at %08lx\n", (long)addr);

    M68000_BusError(addr, BUS_ERROR_WRITE);
}

static int ROMmem_check(uaecptr addr, uae_u32 size)
{
    addr -= ROMmem_start & ROMmem_mask;
    addr &= ROMmem_mask;
    return (addr + size) <= ROMmem_size;
}

static uae_u8 *ROMmem_xlate(uaecptr addr)
{
    addr -= ROMmem_start & ROMmem_mask;
    addr &= ROMmem_mask;
    return ROMmemory + addr;
}


/* IDE controller IO memory */
/* see also ide.c */

static uae_u8 *IdeMemory;

static int IdeMem_check(uaecptr addr, uae_u32 size)
{
    addr -= IdeMem_start;
    addr &= IdeMem_mask;
    return (addr + size) <= IdeMem_size;
}

static uae_u8 *IdeMem_xlate(uaecptr addr)
{
    addr -= IdeMem_start;
    addr &= IdeMem_mask;
    return IdeMemory + addr;
}


/* Hardware IO memory */
/* see also ioMem.c */

uae_u8 *IOmemory;

static int IOmem_check(uaecptr addr, uae_u32 size)
{
    addr -= IOmem_start;
    addr &= IOmem_mask;
    return (addr + size) <= IOmem_size;
}

static uae_u8 *IOmem_xlate(uaecptr addr)
{
    addr -= IOmem_start;
    addr &= IOmem_mask;
    return IOmemory + addr;
}



/* **** Address banks **** */

static addrbank dummy_bank =
{
    dummy_lget, dummy_wget, dummy_bget,
    dummy_lput, dummy_wput, dummy_bput,
    dummy_xlate, dummy_check
};

static addrbank BusErrMem_bank =
{
    BusErrMem_lget, BusErrMem_wget, BusErrMem_bget,
    BusErrMem_lput, BusErrMem_wput, BusErrMem_bput,
    BusErrMem_xlate, BusErrMem_check
};

static addrbank STmem_bank =
{
    STmem_lget, STmem_wget, STmem_bget,
    STmem_lput, STmem_wput, STmem_bput,
    STmem_xlate, STmem_check
};

static addrbank SysMem_bank =
{
    SysMem_lget, SysMem_wget, SysMem_bget,
    SysMem_lput, SysMem_wput, SysMem_bput,
    STmem_xlate, STmem_check
};

static addrbank VoidMem_bank =
{
    VoidMem_lget, VoidMem_wget, VoidMem_bget,
    VoidMem_lput, VoidMem_wput, VoidMem_bput,
    VoidMem_xlate, VoidMem_check
};

static addrbank TTmem_bank =
{
    TTmem_lget, TTmem_wget, TTmem_bget,
    TTmem_lput, TTmem_wput, TTmem_bput,
    TTmem_xlate, TTmem_check
};

static addrbank ROMmem_bank =
{
    ROMmem_lget, ROMmem_wget, ROMmem_bget,
    ROMmem_lput, ROMmem_wput, ROMmem_bput,
    ROMmem_xlate, ROMmem_check
};

static addrbank IdeMem_bank =
{
    Ide_Mem_lget, Ide_Mem_wget, Ide_Mem_bget,
    Ide_Mem_lput, Ide_Mem_wput, Ide_Mem_bput,
    IdeMem_xlate, IdeMem_check
};

static addrbank IOmem_bank =
{
    IoMem_lget, IoMem_wget, IoMem_bget,
    IoMem_lput, IoMem_wput, IoMem_bput,
    IOmem_xlate, IOmem_check
};



static void init_mem_banks (void)
{
    int i;
    for (i = 0; i < 65536; i++)
	put_mem_bank (i<<16, &dummy_bank);
}


/*
 * Initialize the memory banks
 */
void memory_init(uae_u32 nNewSTMemSize, uae_u32 nNewTTMemSize, uae_u32 nNewRomMemStart)
{
    STmem_size = (nNewSTMemSize + 65535) & 0xFFFF0000;
    TTmem_size = (nNewTTMemSize + 65535) & 0xFFFF0000;

    /*write_log("memory_init: STmem_size=$%x, TTmem_size=$%x, ROM-Start=$%x,\n",
              STmem_size, TTmem_size, nNewRomMemStart);*/

#if ENABLE_SMALL_MEM

    /* Allocate memory for ROM areas and IO memory space (0xE00000 - 0xFFFFFF) */
    ROMmemory = malloc(2*1024*1024);
    if (!ROMmemory) {
	fprintf(stderr, "Out of memory (ROM/IO mem)!\n");
	SDL_Quit();
	exit(1);
    }
    IdeMemory = ROMmemory + 0x100000;
    IOmemory  = ROMmemory + 0x1f0000;

    /* Allocate memory for normal ST RAM */
    STmemory = malloc(STmem_size);
    while (!STmemory && STmem_size > 512*1024) {
	STmem_size >>= 1;
	STmemory = (uae_u8 *)malloc (STmem_size);
	if (STmemory)
	    write_log ("Reducing STmem size to %dkb\n", STmem_size >> 10);
    }
    if (!STmemory) {
	write_log ("virtual memory exhausted (STmemory)!\n");
	SDL_Quit();
	exit(1);
    }

#else

    /* STmemory points to the 16 MiB STRam array, we just have to set up
     * the remaining pointers here: */
    ROMmemory = STRam + ROMmem_start;
    IdeMemory = STRam + IdeMem_start;
    IOmemory = STRam + IOmem_start;

#endif

    init_mem_banks();

    /* Map the ST system RAM: */
    map_banks(&SysMem_bank, 0x00, 1);
    /* Between STRamEnd and 4MB barrier, there is void space: */
    map_banks(&VoidMem_bank, 0x08, 0x38);
    /* Space between 4MB barrier and TOS ROM causes a bus error: */
    map_banks(&BusErrMem_bank, 0x400000 >> 16, 0xA0);
    /* Now map main ST RAM, overwriting the void and bus error regions if necessary: */
    map_banks(&STmem_bank, 0x01, (STmem_size >> 16) - 1);

    /* TT memory isn't really supported yet */
    if (TTmem_size > 0)
	TTmemory = (uae_u8 *)malloc (TTmem_size);
    if (TTmemory != 0)
	map_banks (&TTmem_bank, TTmem_start >> 16, TTmem_size >> 16);
    else
	TTmem_size = 0;
    TTmem_mask = TTmem_size - 1;

    /* ROM memory: */
    /* Depending on which ROM version we are using, the other ROM region is illegal! */
    if(nNewRomMemStart == 0xFC0000)
    {
        map_banks(&ROMmem_bank, 0xFC0000 >> 16, 0x3);
        map_banks(&BusErrMem_bank, 0xE00000 >> 16, 0x10);
    }
    else if(nNewRomMemStart == 0xE00000)
    {
        map_banks(&ROMmem_bank, 0xE00000 >> 16, 0x10);
        map_banks(&BusErrMem_bank, 0xFC0000 >> 16, 0x3);
    }
    else
    {
        write_log("Illegal ROM memory start!\n");
    }

    /* Cartridge memory: */
    map_banks(&ROMmem_bank, 0xFA0000 >> 16, 0x2);

    /* IO memory: */
    map_banks(&IOmem_bank, IOmem_start>>16, 0x1);

    /* IDE controller memory region: */
    map_banks(&IdeMem_bank, IdeMem_start >> 16, 0x1);  /* IDE controller on the Falcon */

    /* Illegal memory regions cause a bus error on the ST: */
    map_banks(&BusErrMem_bank, 0xF10000 >> 16, 0x9);
}


/*
 * Uninitialize the memory banks.
 */
void memory_uninit (void)
{
    /* Here, we free allocated memory from memory_init */
    if (TTmem_size > 0) {
	free(TTmemory);
	TTmemory = NULL;
    }

#if ENABLE_SMALL_MEM

    if (STmemory) {
	free(STmemory);
	STmemory = NULL;
    }

    if (ROMmemory) {
	free(ROMmemory);
	ROMmemory = NULL;
    }

#endif  /* ENABLE_SMALL_MEM */
}


void map_banks (addrbank *bank, int start, int size)
{
    int bnr;
    unsigned long int hioffs = 0, endhioffs = 0x100;

    if (start >= 0x100) {
	for (bnr = start; bnr < start + size; bnr++)
	    put_mem_bank (bnr << 16, bank);
	return;
    }
    /* Some ROMs apparently require a 24 bit address space... */
    if (currprefs.address_space_24)
	endhioffs = 0x10000;
    for (hioffs = 0; hioffs < endhioffs; hioffs += 0x100)
	for (bnr = start; bnr < start+size; bnr++)
	    put_mem_bank ((bnr + hioffs) << 16, bank);
}
