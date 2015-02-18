#include <SDL.h>

#include "Vvideo.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

// analyze video mode and compare with:
// http://alive.atari.org/alive9/ovrscn1.php

// TODO:
// - ST hsync timing
//   - hsync 16 pixel later
//   - use shifter sync signals for ST directly
// - NTSC timing from Troed/Overscan
// - v-event position from Troed (4 cycles before DE in ST LOW)
// Synthesis:
// - OSD right border
// - check STE sound

#define DUMP 1
#define VIKING 0 // enable viking card
#define REZ 0    // LOW=0, MID=1, HI=2
#define SD 1     // scan doubler on/off
#define SL 2     // scanlines 0=off -> 3=75%
#define PAL 1    // 0-NTSC or 1-PAL
#define PAL56 0  // enable PAL56 mode

#define STE_SHIFT       0  // 1
#define STE_LINE_OFFSET 0

#define CLK        (31875000.0)

#if VIKING
#define W 900
#define H 540
#else
#if REZ==0 && SD==0
#define W 513
#else
#define W 1026
#endif

#if REZ==2 || SD==1
#define H 626
#else
#define H 313
#endif
#endif

unsigned char vidmem[1280*1024/8]; 

SDL_Surface* screen = NULL;

Vvideo* top = NULL;
#if DUMP
VerilatedVcdC* tfp = NULL;
#endif

double time_ns = 0;

#define MHZ2NS(a)  (1000000000.0/(a))

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

void put_pixel32(int x, int y, Uint32 pixel ) {
  // Convert the pixels to 32 bit 
  Uint32 *pixels = (Uint32 *)screen->pixels; 
  // Set the pixel 
#if VIKING
  // average half size
  if((x < 2*W) && (y < 2*H)) {
    pixel = (pixel>>2)&0x3f3f3f;
    if(!(y&1) && !(x&1)) 
      pixels[ ( y/2 * screen->w ) + x/2 ] = pixel;
    else
      pixels[ ( y/2 * screen->w ) + x/2 ] += pixel;
  }
#else
  if((x < W) && (y < H))
    pixels[ ( y * screen->w ) + x ] = pixel; 
#endif
} 

int dump_enabled = 0;

void eval(void) {
  // evaluate recent changes
  top->eval();

#if DUMP
  if(dump_enabled)
    tfp->dump(time_ns);
#endif

  // check if hsync changes
  { static int hs = 0;
    static double hs_ns = 0;
    static double hs_hi_ns = 0;
    static double hs_lo_ns = 0;
    static double hs_tot_ns = 0;
    static unsigned long last_addr = 0;
    static int last_addr_inc = 0;

    if(top->v__DOT__stvid_hs != hs) {
      if(hs_ns) {
	double hs_time = time_ns - hs_ns;
	int change = 0;

	if(hs) {
	  if(fabs(hs_hi_ns - hs_time) > 0.001) change = 1;
	  hs_hi_ns = hs_time;
	} else {
	  if(fabs(hs_lo_ns - hs_time) > 0.001) change = 1;
	  hs_lo_ns = hs_time;
	}
	double hs_tot_ns = hs_lo_ns + hs_hi_ns;
	if(change && hs_lo_ns && hs_hi_ns)
	  printf("HSYNC changed line in %d HI/LO %.3fus/%.3fus, tot %.3fus / %.3fkhz\n", 
		 top->v__DOT__shifter__DOT__vcnt, hs_hi_ns/1000, hs_lo_ns/1000, 
		 hs_tot_ns/1000, 1000000/hs_tot_ns);
      }

      hs_ns = time_ns;
      hs = top->v__DOT__stvid_hs;
    }
  }

  // check if vsync changes
  { static int vs = 0;
    static double vs_ns = 0;
    static double vs_hi_ns = 0;
    static double vs_lo_ns = 0;
    static double vs_tot_ns = 0;
    if(top->v__DOT__stvid_vs != vs) {
      if(vs_ns) {
	double vs_time = time_ns - vs_ns;
	int change = 0;

	if(vs) {
	  if(fabs(vs_hi_ns - vs_time) > 1) change = 1;
	  vs_hi_ns = vs_time;
	} else {
	  if(fabs(vs_lo_ns - vs_time) > 1) change = 1;
	  vs_lo_ns = vs_time;
	}
	double vs_tot_ns = vs_lo_ns + vs_hi_ns;
	if(change && vs_lo_ns && vs_hi_ns)
	  printf("VSYNC HI/LO %.3fms/%.3fms, tot %.3fms / %.3fhz\n", 
		 vs_hi_ns/1000000, vs_lo_ns/1000000, vs_tot_ns/1000000, 1000000000/vs_tot_ns);
      }

      vs_ns = time_ns;
      vs = top->v__DOT__stvid_vs;
    }
  }

  // eval on negedge of 8 mhz clk
  { static int last_cpu_clk = 0;
    if(!top->cpu_clk && last_cpu_clk) {
      if(top->read) {
	unsigned long long v;
#if VIKING
	// viking can address up to 256kb
	memcpy(&v, vidmem+2*(top->vaddr&0x1fffc), 8);
#else
	memcpy(&v, vidmem+2*(top->vaddr&0x7ffc), 8);
#endif 
	top->data =
	  ((v & 0xff00ff00ff00ff00) >> 8) |
	  ((v & 0x00ff00ff00ff00ff) << 8);

	// Bus cycles 0 and 2 may be used by video
	// Usually shifter uses 0 (incl STE DMA audio)
	// Viking uses 2
	// And MISTXVID uses 0 and 2 (and thus doesn't support STE DMA audio)
	if((top->bus_cycle != 0)&&(top->bus_cycle != 2)) {
	  printf("illegal read in bus_cycle %d\n", top->bus_cycle);
	  exit(-1);
	}
      }
    }
    last_cpu_clk = top->cpu_clk;
  }

  // eval on negedge of 32 mhz clk
  if(dump_enabled) { 
    static int last_clk = 0;
    // scan doubled output is always analyzed at 32MHz
    if(!
#if VIKING
       top->clk_128
#elif SD
       top->clk_32
#else
       top->v__DOT__shifter__DOT__pclk
#endif
       && last_clk) {
      static int last_hs=0, last_vs=0;
      static int x=0, y=0;
      
      put_pixel32(x, y, 
	  (top->video_r<<18) + (top->video_g<<10) + (top->video_b<<2));

      // draw hsync in dark red
      if(top->v__DOT__stvid_hs == top->v__DOT__osd__DOT__hs_pol) {
	put_pixel32(x, y, 0x800000);

	// all pixels should be black during sync, highlight other ones in green
	if((top->video_r != 0) || (top->video_g != 0) || (top->video_b != 0))
	  put_pixel32(x, y, 0x00ff00);
      }

      x++;
      if(top->v__DOT__stvid_hs != last_hs) {
	// and of hsync
	if(last_hs == top->v__DOT__osd__DOT__hs_pol)
	  { x = 0; y++; }
	last_hs = top->v__DOT__stvid_hs;

	/* update the screen */
	SDL_UpdateRect(screen, 0, 0, 0, 0);
      }
      if(top->v__DOT__stvid_vs != last_vs) {
	if(top->v__DOT__stvid_vs) y = 0;
	last_vs = top->v__DOT__stvid_vs;
      }
    }
#if VIKING
    last_clk = top->clk_128;
#elif SD
    last_clk = top->clk_32;
#else
    last_clk = top->v__DOT__shifter__DOT__pclk;
#endif
  }
}

unsigned long cpu_write_addr = 0;
unsigned short cpu_write_data;

// advance time and create valid 8 Mhz clock and signals
// derived from it 
void wait_ns(double n) {
  static double clk_time = 0;

  eval();

  // check if next clk event is within waiting period
  while(clk_time <= n) {
    time_ns += clk_time;    // advance time to next clk event
    n -= clk_time;          // reduce remainung waiting time

    // process change on clk 
#if VIKING    
    // viking needs 128MHz
    top->clk_128 = !top->clk_128;
    eval();
    static int x = 0;
    if(x++ == 3) {
    x = 0;
#else
    {
#endif

    top->clk_32 = !top->clk_32;
    eval();

    // things supposed to happen on rising clock edge
    if(top->clk_32) {
      // every 4th cycle ...
      static int clk_cnt = 0;

      if(clk_cnt == 1)
	top->bus_cycle = (top->bus_cycle + 1) &3;

      clk_cnt = clk_cnt + 1;
      top->cpu_clk = (clk_cnt&2)?1:0;   // 8MHz

      if(clk_cnt == 4) clk_cnt = 0;

      // ------------ cpu access ---------------
      if(clk_cnt == 2) {
	top->cpu_sel = 0;	  
	
	if(top->bus_cycle == 0) {

	  // perform cpu write access
	  if(cpu_write_addr) {
	    printf("CPU WRITE $%lx = $%x\n", cpu_write_addr, cpu_write_data);

	    top->cpu_sel = (cpu_write_addr & ~0xff) == 0xff8200;
	    top->cpu_addr = (cpu_write_addr & 0xff)>>1;
	    top->cpu_rw = 0;
	    top->cpu_din = cpu_write_data;
	    top->cpu_uds = top->cpu_lds = 0;
	    cpu_write_addr = 0;
	  }
	}
      }
    }
  }
    eval();

#if VIKING    
    clk_time = MHZ2NS(4*CLK)/2.0; // next clk change in 3.9ns
#else
    clk_time = MHZ2NS(CLK)/2.0; // next clk change in 31.25ns
#endif
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

void cpu_write_short(unsigned long addr, unsigned short data) {
  cpu_write_addr = addr;
  cpu_write_data = ((data & 0xff)<<8) | ((data & 0xff00)>>8);
  wait_us(1);               // wait two 2MHz system cycles
}
 
int main(int argc, char **argv, char **env) {

#if STE_SHIFT != 0
#if REZ == 0
#define XTRA_OFFSET (8+2*STE_LINE_OFFSET)    // 16 pixels * 4 bit
#elif REZ == 1
#define XTRA_OFFSET (4+2*STE_LINE_OFFSET)    // 16 pixels * 2 bit
#else
#define XTRA_OFFSET (2+2*STE_LINE_OFFSET)    // 16 pixels * 1 bit
#endif
#else
#define XTRA_OFFSET (0+2*STE_LINE_OFFSET)
#endif

  memset(vidmem, 0x80, sizeof(vidmem));

  // load image
#if VIKING
  FILE *in = fopen("viking.raw", "rb");
  if(in) {
    fread(vidmem, 1280*1024/8, 1, in);
    fclose(in); 
  }

#else
#if REZ == 0
  FILE *in = fopen("low.raw", "rb");
#elif REZ == 1
  FILE *in = fopen("mid.raw", "rb");
#else
  FILE *in = fopen("high.raw", "rb");
#endif
  if(in) {
    // load single lines with offset if wanted
    int i;
    unsigned char *p = vidmem;
    for(i=0;i<200;i++) {
      fread(p, 160, 1, in);
      p += 160+XTRA_OFFSET;
    }
    fclose(in); 
  }
#endif

#if 0
  // add some test pattern to the begin
  { 
  int x; for(x=0;x<8;x++) {
    // top left
    vidmem[x*(160+XTRA_OFFSET)+0] = 0x55; vidmem[x*(160+XTRA_OFFSET)+1] = 0x55; 
    vidmem[x*(160+XTRA_OFFSET)+2] = 0x33; vidmem[x*(160+XTRA_OFFSET)+3] = 0x33; 
    vidmem[x*(160+XTRA_OFFSET)+4] = 0x0f; vidmem[x*(160+XTRA_OFFSET)+5] = 0x0f;
    vidmem[x*(160+XTRA_OFFSET)+6] = 0x00; vidmem[x*(160+XTRA_OFFSET)+7] = 0xff;
    
  // top right
    vidmem[x*(160+XTRA_OFFSET)+152+XTRA_OFFSET] = 0x55; 
    vidmem[x*(160+XTRA_OFFSET)+153+XTRA_OFFSET] = 0x55; 
    vidmem[x*(160+XTRA_OFFSET)+154+XTRA_OFFSET] = 0x33; 
    vidmem[x*(160+XTRA_OFFSET)+155+XTRA_OFFSET] = 0x33; 
    vidmem[x*(160+XTRA_OFFSET)+156+XTRA_OFFSET] = 0x0f; 
    vidmem[x*(160+XTRA_OFFSET)+157+XTRA_OFFSET] = 0x0f;
    vidmem[x*(160+XTRA_OFFSET)+158+XTRA_OFFSET] = 0x00; 
    vidmem[x*(160+XTRA_OFFSET)+159+XTRA_OFFSET] = 0xff;
  }}
#endif
  
  /* initialize SDL */
  SDL_Init(SDL_INIT_VIDEO);
  
  /* set the title bar */
  SDL_WM_SetCaption("SDL Test", "SDL Test");
  
  /* create window */
  screen = SDL_SetVideoMode(W, H, 0, 0);

  Verilated::commandArgs(argc, argv);
  // init top verilog instance
  top = new Vvideo;

#if DUMP
  // init trace dump
  Verilated::traceEverOn(true);
  tfp = new VerilatedVcdC;
  top->trace (tfp, 99);
  tfp->open ("video.vcd");
#endif

  // initialize system inputs
  top->clk_32 = 1;

#if REZ == 0
  // setup palette
  unsigned char x,coltab[][3] = {
    { 7,7,7 }, { 7,0,0 }, { 0,7,0 }, { 7,7,0 }, { 0,0,7 }, { 7,0,7 }, { 0,7,7 }, { 5,5,5 },
    { 3,3,3 }, { 7,3,3 }, { 3,7,3 }, { 7,7,3 }, { 3,3,7 }, { 7,3,7 }, { 3,7,7 }, { 0,0,0 }};
  for(x=0;x<16;x++) {
    top->v__DOT__shifter__DOT__palette_r[x] = coltab[x][0];  
    top->v__DOT__shifter__DOT__palette_g[x] = coltab[x][1];  
    top->v__DOT__shifter__DOT__palette_b[x] = coltab[x][2];  
  }
#elif REZ == 1
  // setup palette
  unsigned char x,coltab[][3] = {
  { 7,7,7 }, { 7,0,0 }, { 0,7,0 }, { 0,0,0 } };
  for(x=0;x<4;x++) {
    top->v__DOT__shifter__DOT__palette_r[x] = coltab[x][0];  
    top->v__DOT__shifter__DOT__palette_g[x] = coltab[x][1];  
    top->v__DOT__shifter__DOT__palette_b[x] = coltab[x][2];  
  }
#endif

#if 1
  // show OSD
  top->v__DOT__osd__DOT__enabled = 1;
  { int i, j; 
    for(i=0;i<2048;i++)
      top->v__DOT__osd__DOT__buffer[i] = (i&8)?0xf0:0x0f;

    for(i=0;i<256;i++) {
      top->v__DOT__osd__DOT__buffer[i] = 0x33;
      top->v__DOT__osd__DOT__buffer[i+2048-256] = 0xcc;
    }
    
    for(i=0;i<8;i++) {
      for(j=0;j<4;j++) {
	top->v__DOT__osd__DOT__buffer[i*256+j+0]  = 0x66;
	top->v__DOT__osd__DOT__buffer[i*256+j+4]  = 0x00;
	top->v__DOT__osd__DOT__buffer[i*256+j+8]  = 0xff;
	top->v__DOT__osd__DOT__buffer[i*256+j+12] = 0x00;

	top->v__DOT__osd__DOT__buffer[i*256+255-j-12] = 0x00;
	top->v__DOT__osd__DOT__buffer[i*256+255-j-8]  = 0xff;
	top->v__DOT__osd__DOT__buffer[i*256+255-j-4]  = 0x00;
	top->v__DOT__osd__DOT__buffer[i*256+255-j-0]  = 0x66;
      }
    }
  }
#endif

  char adjust_x = -1;
  char adjust_y = 1;

  top->adjust = 256*(unsigned char)adjust_x + (unsigned char)adjust_y;

  top->scandoubler_disable = SD?0:1;
  top->viking_enable = VIKING?1:0;
  top->scanlines = SL;

  // reset
  wait_ns(100);
  top->cpu_reset = 1;
  wait_ns(random()%2000);
  top->cpu_reset = 0;

  top->v__DOT__shifter__DOT__hcnt = random();
 
#if (STE_SHIFT != 0) || (STE_LINE_OFFSET != 0)
  top->ste = 1;
  top->v__DOT__shifter__DOT__pixel_offset = STE_SHIFT;
  top->v__DOT__shifter__DOT__line_offset = STE_LINE_OFFSET;
#endif

#if VIKING
  wait_ms(13+14.5);
#else

#if REZ != 2
  // switch to pal 50 hz lowrez
  top->pal56 = PAL56;    
  top->v__DOT__shifter__DOT__shmode = REZ;    // lowrez/mid
  top->v__DOT__shifter__DOT__syncmode = PAL?2:0;  // pal

#if PAL
#if PAL56 && SD
#define IMGTIME (612 * 928 * 1000 / CLK)
  wait_ms(34+2*IMGTIME); // PAL56
#else
#define IMGTIME (626 * 1024 * 1000 / CLK) // one full image has 626 lines @ 32us   = 40.064
  wait_ms(36+2*IMGTIME); // PAL50
#endif 
#else
#define IMGTIME (526 * 1016 * 1000 / CLK)
  wait_ms(31+2*IMGTIME); // NTSC
#endif
#else
  // skip forward to first image
  wait_ms(12);
#endif
#endif

  // fetch image parameters
  //   top->v__DOT__shifter__DOT__de_h_end
  // top->v__DOT__shifter__DOT__t0_h_border_right
  // t1_h_blank_right
  // t2_h_sync
  // t3_h_blank_left
  // t4_h_border_left
  // t6_v_border_bot
  // t7_v_blank_bot
  // t8_v_sync
  // t9_v_blank_top
  // t10_v_border_top
  // t11_v_end

#if !VIKING
#if REZ==0
#define PCLK CLK/4
#elif REZ==1
#define PCLK CLK/2
#else
#define PCLK CLK
#endif
  printf("Timing:\n");
  printf("Total: %d\n", top->v__DOT__shifter__DOT__t5_h_end+1);
  printf("HFreq: %.3fkHz\n", PCLK/1000/(top->v__DOT__shifter__DOT__t5_h_end+1));

  // v__DOT__shifter__DOT__config_string[2U]
#endif

  printf("DUMP ENABLE\n");
  dump_enabled = 1;

  // verify scan doubler state
  //  printf("Scandoubler:\n");
  //  int total = top->v__DOT__scandoubler__DOT__hs_low + top->v__DOT__scandoubler__DOT__hs_high + 2;
  //  printf("  Hor total = %d -> %.3fkhz\n", total, CLK/2000.0/total);

  //  printf("scan doubler is %s\n", top->v__DOT__scandoubler_enabled?"enabled":"disabled");

#if VIKING
  wait_ms(14);
#else
#if REZ != 2
#if PAL
#if PAL56 && SD  // PAL56
  wait_ms(18);
#else
  wait_ms(21); // PAL50
#endif
#else
  wait_ms(18);  // NTSC
#endif
#else
  wait_ms(16);
#endif
#endif

#if DUMP
  tfp->close();
#endif

  getchar();

  /* cleanup SDL */
  SDL_Quit();

  exit(0);
 }

