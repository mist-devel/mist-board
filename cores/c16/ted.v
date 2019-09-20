`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//  Copyright 2013-2016 Istvan Hegedus
//
//  FPGATED is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  FPGATED is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//
// Create Date:   12/18/2013 - 31/03/2016
// Design Name: 	MOS 8360 video chip
// Module Name:   ted.v 
// Project Name:  FPGATED
// Description: 	Cycle exact MOS 8360 TED display chip
//
// Revision history:  
//	0.2	 12/11/2015			diag 264 runs, all screenmodes implemented, external dram works, scroll bug in diag264
// 0.3	 22/01/2016			DRAM resfresh horizontal events improved (increment start/stop, counter reset),vertical scroll bug in Invincible, FF1E write bug in New FLI, FLI incorrect 	 				
// 0.4	 03/02/2016			VertSub counter fixed for Invincible start screen
// 0.5	 22/02/2016			Raster interrupt fixed, Invincible does not freeze now
// 0.6	 03/03/2016			Multicolor Character mode bug fixed in pixelgenerator. Majesty Of Sprites looks good now
// 0.7	 30/03/2016			Audio sound generator and audio D/A implemented
// 1.0	 14/07/2016			First public release, functionally equivalent to 0.7, code cleaned up, license information added
//////////////////////////////////////////////////////////////////////////////////

module ted(
    input wire clk,								// clk must be 4*dot clk so 28.375152MHz for PAL (1.6*PAL system's clock) and 28.63636 for NTSC (2*NTSC system's clock) 
	 input wire [15:0] addr_in,
	 output wire [15:0] addr_out,
	 input wire [7:0] data_in,
	 output wire [7:0] data_out,
	 input wire rw,
	 output wire cpuclk,							// this is a CPU clock for external real CPU
	 output wire [6:0] color,					// 7 bits color code
	 output wire csync,
	 output reg hsync,
	 output reg vsync,
	 output wire irq,
	 output wire ba,
	 output reg mux,
	 output reg ras,
	 output reg cas,
	 output reg cs0,
	 output reg cs1,
	 output reg aec,
	 output wire snd,
	 output wire pal,
	 input wire [7:0] k,
	 output wire cpuenable						// this TED signals is needed only for FPGA bustiming and FPGA internal cpu. If external CPU is used, it is not needed.
    );


	 
// TED register addresses

parameter TIMER1LO=6'h00;
parameter TIMER1HI=6'h01;
parameter TIMER2LO=6'h02;
parameter TIMER2HI=6'h03;
parameter TIMER3LO=6'h04;
parameter TIMER3HI=6'h05;
parameter CONTROL1=6'h06;
parameter CONTROL2=6'h07;
parameter KEYLATCH=6'h08;
parameter IRQ		=6'h09;
parameter IRQEN	=6'h0A;
parameter RASTER	=6'h0B;
parameter CURPOSHI=6'h0C;
parameter CURPOSLO=6'h0D;
parameter CH1FREQLO=6'h0E;
parameter CH2FREQLO=6'h0F;
parameter CH2FREQHI=6'h10;
parameter SOUNDCTRL=6'h11;
parameter BMAPBASE=6'h12;
parameter CHARBASE=6'h13;
parameter VIDEOBASE=6'h14;
parameter BGCOLOR0=6'h15;
parameter BGCOLOR1=6'h16;
parameter BGCOLOR2=6'h17;
parameter BGCOLOR3=6'h18;
parameter EXCOLOR=6'h19;
parameter CHARPOSRELOADHI=6'h1A;
parameter CHARPOSRELOADLO=6'h1B;
parameter VSCANPOSHI=6'h1C;
parameter VSCANPOSLO=6'h1D;
parameter HSCANPOS=6'h1E;
parameter FLASH_VERTSUB=6'h1F;
parameter ROMEN=6'h3E;
parameter RAMEN=6'h3F;

// DMA FSM states

localparam IDLE=3'b000,THALT1=3'b001,THALT2=3'b010,THALT3=3'b011,TDMA=3'b100;
reg [2:0] dma_state=IDLE,dma_nextstate;			// DMA FSM state register

// TED user accessible registers
// These registers are the actual TED registers accessible by end users

reg [15:0] timer1=16'b0,timer1_reload=16'b0;													// $FF00/01
reg [15:0] timer2=16'b0;																			// $FF02/03
reg [15:0] timer3=16'b0;																			// $FF04/05
reg test=1'b0,ecm=1'b0,bmm=1'b0,den=1'b0,rsel=1'b0;										// $FF06 control1 register bits
reg [2:0] yscroll=3'b0;																				// $FF06 bits 0-2, vertical scroll register
reg bmm_reg=1'b0,ecm_reg=1'b0;																	// delayed registered values of BMM and ECM
reg reverse=1'b0,stop=1'b0,mcm=1'b0,csel=1'b0;									         // $FF07 control2 register bits
reg [2:0] xscroll=3'b0;																				// $FF07 bits 0-2, horizontal scroll regitser
reg reverse_reg=1'b0,mcm_reg=1'b0;																// delayed registered values of REVERSE and ECM
reg [7:0] keylatch=8'hff;																			// $FF08 keyboard latch
reg Cnt1Irq=1'b0,Cnt2Irq=1'b0,Cnt3Irq=1'b0,RasterIrq=1'b0,LPIrq=1'b1;				// $FF09 IRQ register
reg enCnt1Irq=1'b0,enCnt2Irq=1'b0,enCnt3Irq=1'b0,enRasterIrq=1'b0,enLPIrq=1'b0; 	// $FF0A IRQ enable register
reg [8:0] RasterCmp=9'b0;																			// $FF0B
reg [9:0] CursorPos=10'b0;																			// $FF0C/0D
reg [9:0] Ch1Freq=10'b0;																			// $FF0E, $FF12 bits 0-1
reg [9:0] Ch2Freq=10'b0;																			// $FF0F, $FF10 bits 0-1
reg damode=1'b0,ch2noise=1'b0,ch2en=1'b0,ch1en=1'b0;										// $FF11 bits 4-7
reg [3:0] volume=4'b0;																				// $FF11 bits 0-3
reg [2:0] bmapbase=3'b0;																			// $FF12 bits 3-5, Bitmap base address
reg charrom=1'b0;																						// $FF12 bit 2
reg [5:0] charbase=6'b0;																			// $FF13 bits 2-7, Character memory base address
reg clkmode=1'b0;																						// $FF13 bit 1, force single clock mode
reg [4:0] vmbase=5'b0;																				// $FF14 bits 3-7, Video RAM base address register 
reg [6:0] bgcolor0=7'b0,bgcolor1=7'b0,bgcolor2=7'b0,bgcolor3=7'b0,excolor=7'b0;	// $FF15-19 color registers
reg [9:0] CharPosReload=10'b0;																	// $FF1A/B, Character Position Reload increments by 40 for each character row completed
reg [8:0] vcounter=9'b0;							   											// $FF1C/D, Vertical line counter
reg [8:0] hcounter=9'b0;							   											// $FF1E, Horizontal dot counter. In real TED it is 11bit. Counts from 0 to 455
reg [4:0] FlashCount=5'b0;																			// $FF1F bits 3-6, Flash counter's 5th bit is the actual flash state and is not user accessible
reg [2:0] VertSubCount=3'b0;																		// $FF1f bits 0-2, Vertical Character scan line position

// TED internal operational registers
// These are needed for the internal operation 

reg [7:0] refreshcounter=8'h00;
reg refresh=1'b0;
reg [3:0] phicounter=4'b0;				    			// CPU single clock generator counter
reg phi=1'b0;												// CPU single clock
reg singleclock=1'b0;									// signals single clock mode

reg [8:0] hcounter_next;
reg [8:0] vcounter_next;
reg [8:0] videoline=9'b0;								// vcounter latched at start of each scanline
reg [7:0] dataout_reg=8'hff;							// TED's databus out register
reg [7:0] data_in_reg;									// TED databus in register
reg [5:0] addr_in_reg;									// TED address in register

reg [6:0] colorreg=7'b0;								// video out register
reg ramen=1'b0;											// High memory address RAM enable register (above $8000)
reg t1stop=1'b0,t2stop=1'b0,t3stop=1'b0;			// Timer disable signals
reg resetRasterIrq,resetLpIrq,resetCnt1Irq,resetCnt2Irq,resetCnt3Irq; // Interrupt reset signals
reg RasterIrqDone=1'b0;									// Signals that raster interrupt has already happened in this line
reg enabledisplay=1'b0;									// DEN register changes enabledisplay signal on first scanline only
reg badline2=1'b0;										// signals 2nd badline (1st badline signal is a wire)
reg ext_fetch=1'b0;										// signals external fetch window inside scanline
reg char_fetch=1'b0;										// signals character fetch window inside scanline
reg dma_window=1'b0;										// signals active dma range inside a scanline
reg char_window=1'b0;									// signals when character/pixel data can be latched from data bus inside a scanline
reg inc_flashcount_window=1'b0;						// signals flash counter increase window
reg inc_vertsub_window=1'b0;							// active for one single clock cycle, signals vertsub register incrementation point (thus actual increment point is delayed with a single clock cycle)
reg inc_vertline_window=1'b0;							// active for one single clock cycle, signals vertical line incrementation point (thus actual increment point is delayed with a single clock cycle)

// horizontal event positions used for the horizontal event decoder. They don't necessarily reflect the values seen in documentation 
reg hpos_0,hpos_8,hpos_154,hpos_172,hpos_288,hpos_295,hpos_296,hpos_303,hpos_304;
reg hpos_312,hpos_320,hpos_336,hpos_343,hpos_348,hpos_353,hpos_359,hpos_380,hpos_382;
reg hpos_384,hpos_391,hpos_392,hpos_400,hpos_407,hpos_423,hpos_431,hpos_432,hpos_440;

reg inc_charpos=1'b0;									// signals internal character position register (not user accessible) increment range inside scanline (not same as $FF1A/$FF1B) 
reg [15:0] addr_out_reg;								// TED's address out register
reg [15:0] tedaddress;									// this is a non registered TED address (although register variable but used in combinational logic)
reg datahold=1'b0;										// signals whether TED should hold its data on the databus 
reg VertSubActive=1'b0;									// signals the scanline ranges when Vertsub counter is active
reg tedwrite_delay=1'b0;								// this signal was needed to emulate a one dot clock delay when TED writes data to its internal registers. Although most probably this delay exist at
																// all TED register writes, in FPGATED we use it only for hcounter/vcounter and color register writes. This emulates white pixel bug too.
reg csyncreg=1'b0,palreg=1'b0,equalization=1'b0,eq1=1'b1,eq2=1'b1;		// PAL/NTSC video screen signals
reg [9:0] videocounter=10'b0;							// videocounter is the actual DMA counter.
reg inc_videocounter=1'b0;								// signals videocounter increment window
reg [9:0] videocounter_reload=10'b0;				// videocounter is reloaded with this value at the beginning of each displayed line
reg [9:0] CharPosition=10'b0;							// CharPosition is loaded by $FF1A/$FF1B and is similar to videocounter. It is used for pixel data fetch from memory. 
reg CharPosLatch=1'b0;									// Signals latching position of CharPosition and videocounter
reg latch_window=1'b0;									// CharPosition and videocounter latch delay window
reg latch_charposition=1'b0;							// Charposition and videocounter latch position

reg [7:0] attr_buf [0:39];								// TED internal videomatrix attribute memory
reg [7:0] char_buf [0:39];								// TED internal videomatrix character pointer memory
reg [7:0] nextchar=8'b0,currentchar=8'b0,waitingchar=8'b0,pixelchar=8'b0;	// next...,current... is a 2 bytes shiftregister to keep data until rendering. waiting... is waiting to be loaded to rendering shiftregister
reg [7:0] nextattr=8'b0,currentattr=8'b0,waitingattr=8'b0,pixelattr=8'b0;	
reg [7:0] nextpixels=8'b0,currentpixels=8'b0,waitingpixels=8'b0;
reg [7:0] pixelshiftreg=8'b0;							// This register contains pixel data and shifts it during rendering
reg [5:0] shiftcount=6'b0;								// Used by the videomatrix shift register to count number of shifts
reg verticalscreen=1'b0;								// Signals which lines are in screen area (top/bottom border control)
reg widescreen=1'b0,narrowscreen=1'b0;				// Signals horizontal screen area (left/right border control)
reg videoshift=1'b0;										// Signals when vide shoft register is active
reg nextcursor=1'b0,currentcursor=1'b0,waitingcursor=1'b0;  // cursor state internal storage for 3 signle clock cycles

reg [6:0] pixelcolor;									// Color of a pixel
reg doubleshift=1'b0;									// During multicolor mode 2 pixels identify one pixel, so this register signals to pixel generator wheter to shift one or two pixels to get color data
reg dotfetch;												// Signals when TED is fetching pixeldata from databus
reg dotfetch_reg=1'b0;									// Registered version of dotfetch
reg [2:0] xscroll_latch=3'b0;							// Registered version of xscroll register
reg [2:0] yscroll_latch=3'b0;							// Registered version of yscroll register
reg hblank=1'b0,vblank=1'b0;							// Signals blanking area
reg refresh_inc=1'b0;									// Dram refresh counter increment window
reg stopreg=1'b0;											// This is a latched version of stop register. Latched at single cycle end

// audio part registers

reg [1:0] audiocycle=2'b0;								// Audio cycle counter divides single clock by 4 and generates audio clock
reg [9:0] ch1count=10'b0,ch2count=10'b0;			// Audio channel1 and channel2 counters
reg ch1state=1'b0,ch2state=1'b0;						// State register of audio channels
reg ch1stateclk_prev=1'b0,ch2stateclk_prev=1'b0;
reg [7:0] noisegen=8'b0;								// Noise generator register
reg [4:0] pwmcounter1=5'b0,pwmcounter2=5'b0;		// PWM D/A counters
reg ch1pwm=0,ch2pwm=0;									// continous square wave with proportional duty cycle to volume
reg [4:0] digivolume=5'b0;								// A digital value signaling at which pwmclock cycle PWM signal high value starts. A digitized version of volume level
reg [17:0] watchdog_ch1=18'b0,watchdog_ch2=18'b0;	// Watchdog timer to emulate sound decay of TED's dynamic latch behaviour


integer i;
integer j;
integer n;

// Internal wires, flags

wire dphi;													// double phi clock
wire [8:0] EOS,VS_START,VS_STOP,EQ_START,EQ_STOP,VBLANK_START,VBLANK_STOP;		//video signal generation constants. Vertical Sync, Equalization, Blank 
wire tick8;													// enable tick for pixelclock (8MHz)
wire blanking;												// screen blanking area flag
wire lowrom,highrom;										// TED low and high rom area flags
wire irqpos;												// IRQ position flag inside clock cycle. Emulates real TED's IRQ signal activation position
wire io,tedreg,tedwrite;								// IO area flag, TED user registers area flag, TED write cycle flag (signals when TED register is written by CPU)
wire badline;												// badline flag
wire attr_fetch_line;									// Visible screen area flag (signals active window)
wire tedlatch;												// tedlatch simulates at which exact position TED latches value into its internal register from the databus
wire [7:0] charpointer,attrpointer;
wire multicolor;											// multicolor mode flag
wire pixelscreen;											// visible pixelscreen area flag (excluding borders)
wire ch1clk,ch2clk;										// Audio channel clocks
wire ch1stateclk,ch2stateclk;							// Audio state register change clock
wire ch1audio,ch2audio;									// Audio channel square waves not modulated by volume (before PWM)
wire noise;													// Noise
wire watchdog_ch1max,watchdog_ch2max;				// Audio watchdog timer maximum values. Actual value is taken from plus4emu

// Initializing internal video matrix

initial
	begin
	for(i=0;i<=39;i=i+1)
		begin
		char_buf[i]=0;
		attr_buf[i]=0;
		end
	end


//-----------------------------------------------------------------------
// Often used combinational signals
//-----------------------------------------------------------------------

assign cycle_end=(phicounter==15)?1'b1:1'b0;				// high pulse at the end of each double clock cycle
assign single_cycle_end=(cycle_end & phi)?1'b1:1'b0;	// high pulse at the end of each single clock cycle

//-----------------------------------------------------------------------
// Clock signal driver phi=Single Clock  dphi=Double Clock
//-----------------------------------------------------------------------

always @(posedge clk)											// Counting FPGA clock cycles during double clock. phicounter is mod16 counter, 16*clk=half phi
	begin
	phicounter<=phicounter+1;
	end
	
assign cpuclk = singleclock?phi:dphi;						// Generated CPU clock. Used only when real 8501 CPU is connected to FPGA
assign dphi = phicounter[3];									// Internal double clock signal
assign cpuenable=(single_cycle_end)?1'b1:					// Generated CPU enable signal. Used only when FPGA CPU is used
						(cycle_end && !singleclock)?1'b1:
						1'b0;
			
always @(posedge clk)											// Internal single clock signal is always generated
	begin
		if (cycle_end)
				phi<=~phi;											
	end

always @(posedge clk)											// clock mode controller. Single or double clock multiplex for the CPU.
	begin
	if(single_cycle_end)											// clock mode change happens only at single clock boundary
		singleclock<=((enabledisplay & ext_fetch) | refresh | clkmode | stop);		// there are 4 criterias to generate single clock: display area,dram refresh,forced 1Mhz,TED stop
	end

always @(posedge clk)
	begin
	if(single_cycle_end)
		stopreg<=stop;
	end

//--------------------------------------------------------------------------
// Attribute Fetch
//--------------------------------------------------------------------------

always @(posedge clk)											// flip flop to signal external fetch single clock window, delayed with 1 single clock cycle
	begin
	if(hpos_296)
		ext_fetch<=0;
	else if(hpos_400)
		ext_fetch<=1;
	end

assign attr_fetch_line=(videoline>=0 && videoline<203);

//--------------------------------------------------------------------------
// DRAM Refresh
//--------------------------------------------------------------------------	

always @(posedge clk)											// refresh single clock control
	begin
	if(hpos_336)
		refresh<=0;
	else if(hpos_296)
		refresh<=1;
	end

always @(posedge clk)											// refresh counter increment control
	begin
	if(hpos_343)
		refresh_inc<=0;
	else if(hpos_303)
		refresh_inc<=1;
	end

always @(posedge clk)
	begin
		if(single_cycle_end & (refresh_inc|stopreg))
					refreshcounter<=refreshcounter+1;
		else	if(hpos_431 & (videoline==0|refresh_inc|stopreg))
			refreshcounter<=8'h00;
	end

//-------------------------------------------------------------------------------------------
// Horizontal counter running on ~8Mhz and vertical counter qualified by horizontal counter
//-------------------------------------------------------------------------------------------

assign tick8=(phicounter[1:0]==3)?1'b1:1'b0; //8Mhz clock tick for pixelclock. tick8 must activate one fastclk cycle earlier to use it for hcounter 


always @(posedge clk)
	begin
		hcounter<=hcounter_next;
		vcounter<=vcounter_next;
		if(hpos_392)
			videoline<=vcounter;
	end
	
always @*									//horizontal counter next state logic
	begin
	hcounter_next=hcounter;
		if (tedlatch & addr_in_reg[5:0]==HSCANPOS)								// horizontal counter is written by CPU 
			begin
				hcounter_next=hcounter+1;
				hcounter_next[8:3]=~data_in_reg[7:2];		// bit 0-2 are not modified by user write to prevent clock phase change
			end
		else if (tick8 & ~stopreg)
			begin
				if (hcounter==9'd455)
					hcounter_next=9'd0;
				else
					hcounter_next=hcounter+1;
			end
	end

always @*									//vertical counter next state logic
	begin
	vcounter_next=vcounter;
		if(tedwrite & addr_in[5:1]==5'b01110)								// $ff1c or $ff1d register write (VSCAN HI and LO)
			begin
			if(addr_in[0]==0)
				vcounter_next={data_in[0],vcounter[7:0]};
			else vcounter_next={vcounter[8],data_in};
			end
		else if(inc_vertline_window & single_cycle_end)
				begin
					if (vcounter==EOS)
							vcounter_next=0;
					else	vcounter_next=vcounter+1;
				end
	end
	
always @(posedge clk)
	begin
	if(hpos_384)
		inc_vertline_window<=1;
	else if (single_cycle_end)
		inc_vertline_window<=0;
	end
	

//---------------------------------------------------------------------------
// Timer 1
//---------------------------------------------------------------------------
// timer 1 decrements during odd single clock cycle (phi=0)
// exact counter change position is unknown but can be estimated based on IRQ place and reading counter values every cycle on a real hardware
// timer 1 changes approximately at half of phi low cycle after IRQ position (IRQ position is 160ns after phi low cycle start).
//   

always @(posedge clk)
	begin
	if(tedwrite)												// load timer 1 at cycle border
		begin
		if (addr_in[5:0]==TIMER1LO)
			begin
				timer1[7:0]<=data_in;
				timer1_reload[7:0]<=data_in;
				t1stop<=1;
			end
		if (addr_in[5:0]==TIMER1HI)
			begin
				timer1[15:8]<=data_in;
				timer1_reload[15:8]<=data_in;
				t1stop<=0;
			end
		end
	if(phicounter==7 && ~phi & ~t1stop & ~stopreg)			// decrement or reload timer 1
		begin															
		if(timer1==0)											
			timer1<=timer1_reload-1;
		else
			timer1<=timer1-1;
		end
	end
	
//---------------------------------------------------------------------------
// Timer 2
//---------------------------------------------------------------------------
// timer 2 decrements during even single clock cycle (phi=1)
// timer 2 changes approximately at odd-even single clock cycle boundary (phi low - high transition)

always @(posedge clk)
	begin
	if(tedwrite)													// load timer 2 at cycle border
		begin
		if (addr_in[5:0]==TIMER2LO)
			begin
				timer2[7:0]<=data_in;
				t2stop<=1;
			end
		if (addr_in[5:0]==TIMER2HI)
			begin
				timer2[15:8]<=data_in;
				t2stop<=0;
			end
		end
	else if(phicounter==15 && phi==0 && t2stop==0 && stopreg==0)		// if not loaded, decrement timer 2 at odd-even cycle border
		begin
		timer2<=timer2-1;
		end
	end

//---------------------------------------------------------------------------
// Timer 3
//---------------------------------------------------------------------------
// timer 3 decrements during even single clock cycle (phi=1)
// timer 3 changes approximately at half of phi high cycle (contrary to timer 1)

always @(posedge clk)
	begin
	if(tedwrite)
		begin
		if (addr_in[5:0]==TIMER3LO)							// load timer 3 at cycle border
			begin
				timer3[7:0]<=data_in;
				t3stop<=1;
			end
		if (addr_in[5:0]==TIMER3HI)
			begin
				timer3[15:8]<=data_in;
				t3stop<=0;
			end
		end
	if(phicounter==7 && phi==1 && t3stop==0 && stopreg==0)				// decrement timer 3
		begin
		timer3<=timer3-1;
		end
	end
	
//---------------------------------------------------------------------------
// Timer IRQs
//---------------------------------------------------------------------------
//

assign irqpos=(phicounter==4 & ~phi)?1'b1:1'b0;

always @(posedge clk)
	begin
	if(resetCnt1Irq)
		Cnt1Irq<=0;
	else if(irqpos && timer1==0)
		Cnt1Irq<=1;
	end
	
always @(posedge clk)
	begin
	if(resetCnt2Irq)
		Cnt2Irq<=0;
	else if(irqpos && timer2==0)
		Cnt2Irq<=1;
	end

always @(posedge clk)
	begin
	if(resetCnt3Irq)
		Cnt3Irq<=0;
	else if(irqpos && timer3==0) 
		Cnt3Irq<=1;
	end
	

//---------------------------------------------------------------------------
// Raster IRQ
//---------------------------------------------------------------------------
	
always @(posedge clk)
	begin
	if (resetRasterIrq)
		RasterIrq<=0;
	else	if (RasterCmp==vcounter)
		begin
		if(~RasterIrqDone & tick8)			// do raster interrupt only 1 time per raster line and interrupt happens when phi or dphi is low and about 170ns after cycle start
			begin
			RasterIrq<=1;
			RasterIrqDone<=1;
			end
		end
	else RasterIrqDone<=0;
	end
	
//---------------------------------------------------------------------------
// IRQ signal
//---------------------------------------------------------------------------
 
assign irq=~((enCnt1Irq & Cnt1Irq)|(enCnt2Irq & Cnt2Irq)| (enCnt3Irq & Cnt3Irq) | (enRasterIrq & RasterIrq) | (enLPIrq & LPIrq));

//---------------------------------------------------------------------------
// AEC signal generating
//---------------------------------------------------------------------------

always @(posedge clk)
	begin
		if((singleclock & ~phi) | (dma_state==TDMA))
			aec<=0;
		else aec<=1;
	end

//---------------------------------------------------------------------------
// BA signal 	(RDY)
//---------------------------------------------------------------------------

assign ba=(dma_state==IDLE)?1'b1:1'b0;

//---------------------------------------------------------------------------
// badline
//---------------------------------------------------------------------------

assign badline=((yscroll_latch==videoline[2:0]) & enabledisplay & attr_fetch_line)?1'b1:1'b0;			// signal 1st badline

always @(posedge clk)
	begin
	if(inc_vertline_window & single_cycle_end)
		begin
		if(badline)
			badline2<=1;
		else if(badline2)
			badline2<=0;
		end
/*	else if(badline & ~hpos_392)							//when yscroll changed to generate badline, abort an already started badline2 (except at start of line)
		badline2<=0;*/
	end

always @(posedge clk)										// synchronize yscroll changes to single cycle border
	begin
	if(single_cycle_end)
		yscroll_latch<=yscroll;
	end

//---------------------------------------------------------------------------
// EnableDisplay signal
//---------------------------------------------------------------------------

always @(posedge clk)
	begin
	if(videoline==0 && den==1)
		enabledisplay<=1;
	if(videoline==204)
		enabledisplay<=0;
	end

//---------------------------------------------------------------------------
// Bitmapmask fetch signal
//---------------------------------------------------------------------------

always @(posedge clk)					// character fetch window starts at first badline2 and stops at line 204. It signals that character fetches can happen in these lines.
	begin
	if(videoline==9'd204)
		char_fetch<=0;
	else if(badline2)
		char_fetch<=1;
	end
//----------------------------------------------------------------------------
// Character Position register $FF1A/$FF1B
//----------------------------------------------------------------------------

always @(posedge clk)					// character fetch position increase from horizontal count 432 to horizontal count 296
	begin
	if(hpos_296)
		inc_charpos<=0;
	else if(hpos_432)
		inc_charpos<=1;
	end

always @(posedge clk)					// DMA and Charpos latch delay trick
	begin
	latch_charposition<=0;
	if(hpos_288)
		latch_window<=1;
	else if(single_cycle_end & latch_window)
		begin
		latch_window<=0;
		latch_charposition<=1;			// 1 FPGA cycle long latch enable signal used for Character position and videocounter position reload latch
		end
	end

always @(posedge clk)
	begin
	if(hpos_392)
		begin
		if(VertSubCount==6)
			CharPosLatch<=1;				// CharPosLatch signal activates in line 6 and signals that videocounter (DMA counter) has been latched. It is used in line 7 for character position latch.
		else 
			CharPosLatch<=0;
		end
	end

always @(posedge clk)					// Character Position Reload register $FF1A/$FF1B
	begin
	if(tedwrite & addr_in[5:0]==CHARPOSRELOADHI)
			CharPosReload[9:8]<=data_in[1:0];
	else if(tedwrite & addr_in[5:0]==CHARPOSRELOADLO)
			CharPosReload[7:0]<=data_in;
	else if(hpos_392 & videoline==EOS)		// clear character position reload at last line
			CharPosReload<=0;
	else if(CharPosLatch & latch_charposition & enabledisplay)				// latch character position at 7th line of a character row if videocunter was latched in previous 6th row
			CharPosReload<=CharPosition;
	end

always @(posedge clk)									// Character Position counter (not user accessible)
	begin
	if(hpos_392)											// clear character position in each line at 392
		CharPosition<=0;
	else
		begin
		if(hpos_432 & enabledisplay & VertSubActive)										// FIXME this might need delay
			CharPosition<=CharPosReload;
		else if(inc_charpos & single_cycle_end)
			CharPosition<=CharPosition+1;
		end
	end


//---------------------------------------------------------------------------
// Attribute fetch (DMA) 
//---------------------------------------------------------------------------
// DMA FSM

always @(posedge clk)
	begin
	dma_state<=dma_nextstate;
	end

always @*
	begin
	dma_nextstate=dma_state;
	case(dma_state)
	IDLE:		begin	
				if((badline|badline2) & dma_window)
					dma_nextstate=THALT1;
				end
	THALT1:	begin
				if((badline|badline2) & dma_window & single_cycle_end)
					dma_nextstate=THALT2;
				else if (~dma_window | ~(badline|badline2))
					dma_nextstate=IDLE;
				end
	THALT2:	begin
				if((badline|badline2) & dma_window & single_cycle_end)
					dma_nextstate=THALT3;
				else if (~dma_window | ~(badline|badline2))
					dma_nextstate=IDLE;
				end
	THALT3:	begin
				if((badline|badline2) & dma_window & single_cycle_end)
					dma_nextstate=TDMA;
				else if (~dma_window | ~(badline|badline2))
					dma_nextstate=IDLE;
				end
	TDMA:		begin
				if (~dma_window | ~(badline|badline2))
					dma_nextstate=IDLE;
				end
	default:	dma_nextstate=IDLE;
	endcase	
	end

always @(posedge clk)
	begin
	if(hpos_407 & tick8)
		dma_window<=1;
	else if(hpos_295 & tick8)
		dma_window<=0;
	end


//-------------
// Attribute fetch address generation (videocounter is DMA position counter)
//-------------

always @(posedge clk)				// videocounter increase window				
	begin
	if(enabledisplay)
		begin
		if(hpos_296 | shiftcount==6'd40)
			inc_videocounter<=0;
		else if(hpos_432)
			inc_videocounter<=1;
		end
	end

always @(posedge clk)
	begin
	if(hpos_392 & videoline==EOS)	// clear videocounter reload register at last line
		videocounter_reload<=0;
	else if(inc_videocounter && hcounter_next == 9'd432 && tick8) // if the videocounter running when it's reloaded, that affects the reload value (HSP in Alpharay)
		videocounter_reload<=videocounter+1'd1;
	else if(VertSubCount==6 && latch_charposition && enabledisplay)			// Latch videocounter position at 6th line of a character row
		videocounter_reload<=videocounter;
	end	
	
always @(posedge clk)						// videocounter used for attribute and character pointer fetches (DMA counter)
	begin
	if(enabledisplay)
		begin
		if(hpos_432)
			videocounter<=videocounter_reload;
		else if(inc_videocounter & single_cycle_end)							// increase videocounter at cycle border
			videocounter<=videocounter+1;
		end
	end

//------------------------------------
// Internal VideoMatrix (DMA buffers)	
//------------------------------------

	
always @(posedge clk)
	begin
	if(single_cycle_end)
		begin
		if(inc_videocounter)
			begin
			if(badline)	begin									// in 1st badline fetch attribute from databus and place to buffer's start
				attr_buf[0]<=data_in;
				end
			else begin
				attr_buf[0]<=attr_buf[39];
				end
			for(i=1;i<40;i=i+1) begin
				attr_buf[i]<=attr_buf[i-1];
				end
			nextattr<=attr_buf[39];
			shiftcount<=shiftcount+1;
			
			if(((CursorPos==CharPosition) && VertSubActive) || (CursorPos==0 && CharPosition==0))					// cursor position must be checked here 
				nextcursor<=1;
			else nextcursor<=0;
			
			end
		else begin
			nextattr<=0;
			shiftcount<=0;
			end
		end
	end
	
always @(posedge clk)
	begin
	if(single_cycle_end)
		begin
		if(inc_videocounter)
			begin
			if(badline2) begin
				char_buf[0]<=data_in;
				nextchar<=data_in;
				end
			else begin
				char_buf[0]<=char_buf[39];
				nextchar<=char_buf[39];
				end
			for(j=1;j<40;j=j+1) begin
				char_buf[j]<=char_buf[j-1];
				end
			end 	
		else begin
			nextchar<=0;
			end
		end
	end


always @(posedge clk)							// character window flag is needed for fetching pixel data from bus
	begin
	if(hpos_304)
		char_window<=0;
	else if(hpos_440 & enabledisplay)
		char_window<=1;
	end

always @(posedge clk)								// latch pixel data from data bus at phi0 change from 0 to 1
	begin
	if(char_window)
		begin
		if(hpos_440)
			nextpixels<=0;
		else if(cycle_end & ~phi)
			nextpixels<=data_in;
		end
	end

//---------------------------------------------------------------------------
// Vertical Sub register represents actual raster line inside character
//---------------------------------------------------------------------------

always @(posedge clk)
	begin
	if(hpos_392)					
		inc_vertsub_window<=1;
	else if(single_cycle_end)
		inc_vertsub_window<=0;
	
			
	if (hpos_380 & badline)													// ... activates at 1st badline of the frame
		VertSubActive<=1;
	else if (~enabledisplay)												// ... inactivates at line 204
		VertSubActive<=0;
	end
		
always @(posedge clk)
		begin
			if(tedwrite && addr_in[5:0]==FLASH_VERTSUB)					// if it is written by user
				VertSubCount<=data_in[2:0];
			else 
				if(inc_vertsub_window & single_cycle_end)					// if it is time to change VertSub
						if (videoline==0)											// ... changes to 7 at line 0 FIXME: between cycle $C8 and $CA
							VertSubCount<=3'd7;
						else if(enabledisplay & VertSubActive) 
							VertSubCount<=VertSubCount+1;					// ... increases between line 0 and 204
		end

//---------------------------------------------------------------------------
// Flash counter
// 5th bit of FlashCount contains flash status and not accessible via FF1F register
//---------------------------------------------------------------------------

always @(posedge clk)
	begin
	if(hpos_348)
		inc_flashcount_window<=1;
	else if(single_cycle_end)
		inc_flashcount_window<=0;

	if(tedwrite && addr_in[5:0]==FLASH_VERTSUB)
			FlashCount[3:0]<=data_in[6:3];
	else if(videoline==205 & inc_flashcount_window & single_cycle_end)
			FlashCount<=FlashCount+1;
	end

//---------------------------------------------------------------------------
// Horizontal event decodes
//---------------------------------------------------------------------------

always @(hcounter)
	begin
	hpos_0=0;
	hpos_8=0;
	hpos_154=0;
	hpos_172=0;
	hpos_288=0;
	hpos_295=0;
	hpos_296=0;
	hpos_303=0;
	hpos_304=0;
	hpos_312=0;
	hpos_320=0;
	hpos_336=0;
	hpos_343=0;
	hpos_348=0;
	hpos_353=0;
	hpos_359=0;
	hpos_380=0;
	hpos_382=0;
	hpos_384=0;
	hpos_391=0;
	hpos_392=0;
	hpos_400=0;
	hpos_407=0;
	hpos_423=0;
	hpos_431=0;
	hpos_432=0;
	hpos_440=0;
	case (hcounter)
				0:		hpos_0=1;				// Start of 40 column screen
				8:		hpos_8=1;				// Start of 38 column screen
				154:  hpos_154=1;				// Equalization pulse 1 start
				172:	hpos_172=1;				// Equalization pulse 1 end
				288:	hpos_288=1;				//	CharPosition and Videocounter latch position delayed by 1 cycle (starts at 296)
				295:	hpos_295=1;				// Attribute fetch (DMA) FSM stop
				296:	hpos_296=1;				// Stop external fetch single clock delayed by 1 cycle
													// Start refresh singleclock delayed by 1 cycle (actual start at 304)
				303:	hpos_303=1;				// Start refresh counter increment (304 in real TED)
				304:  hpos_304=1;				// End of character window
				312:	hpos_312=1;				// End of 38 column screen
				320: 	hpos_320=1;				// End of 40 column screen
				336:  hpos_336=1;				// Stop refresh singleclock but delayed by 2 cycle (actual stop at 344)
				343:	hpos_343=1;				// Stop refresh counter increment (344 in real TED)
				348:	hpos_348=1;				// Flash (blink) counter increment point delayed by 2 cycles (increments at 352)
				353:	hpos_353=1;				// Horizontal blanking start
				359:	hpos_359=1;				// Horizontal sync start (358 in real TED however line change takes time thus the delay)				
				380:	hpos_380=1;
				382:	hpos_382=1;				// Equalization pulse 2 start
				384:	hpos_384=1;				// End Of Screen. Clear vertical line,refresh counters and character reload register, increase vertical line after 1 cycle delay
				391: 	hpos_391=1;	
				392:	hpos_392=1;				// VertSub register increment (delayed), Hsync end
				400:  hpos_400=1;				// Start external fetch single clock (delayed), Equalization pulse 2 end
				407:	hpos_407=1;				// Attribute fetch (DMA) FSM start
				423:	hpos_423=1;				// Horizontal blanking stop
				431:	hpos_431=1;				// Refresh counter reset point
				432:	hpos_432=1;				// Start videocounter increment
				440:  hpos_440=1;				// Start video shiftregister
	endcase				
end

//---------------------------------------------------------------------------
// Border control
//---------------------------------------------------------------------------

always @(posedge clk)									// 25/24 row select and top/bottom borders
	begin
		if(rsel==1) begin
			if(videoline==9'd4)					// if 25 rows mode, screen starts at line 4
				verticalscreen<=1;
			else if (videoline==9'd204)			// stops at line 204
				verticalscreen<=0;
		 end
		else begin
			if(videoline==9'd8)					// if 24 rows mode, screen starts at line 8
				verticalscreen<=1;
			else if(videoline==9'd200)			// stops at line 200
				verticalscreen<=0;
		end
	end

always @(posedge clk)									// 38/40 columns select and side borders
	begin
		if(enabledisplay & verticalscreen) 
			begin 
				if(hpos_320 & tick8)
					widescreen<=0;
				else if (hpos_0 & tick8)
					widescreen<=1;
				if(hpos_312 & tick8)
					narrowscreen<=0;
				else if (hpos_8 & tick8)
					narrowscreen<=1;
			end
	end

	


//---------------------------------------------------------------------------
// VideoShift Register	
//---------------------------------------------------------------------------
	
always @(posedge clk)
	begin
	if (hpos_312)
		videoshift<=0;
	else if(enabledisplay & hpos_440)
		videoshift<=1;
	end

always @(posedge clk)						// video shift register stores fetched video data until pixelshiftregister is loaded
	begin
	if(hpos_440)
		begin
		waitingattr<=0;
		waitingchar<=0;
		waitingpixels<=0;
		currentattr<=0;
		currentchar<=0;
		currentpixels<=0;
		end
	else if(cycle_end & videoshift)
		begin
		if(phi)
			begin
			currentchar<=nextchar;
			waitingchar<=currentchar;
			currentattr<=nextattr;
			waitingattr<=currentattr;
			waitingpixels<=currentpixels;
			currentcursor<=nextcursor;
			waitingcursor<=currentcursor;
			end
		else if(~phi)
			currentpixels<=nextpixels;
		end
	end
	
assign cursor=(waitingcursor & ~FlashCount[4]);

//---------------------------------------------------------------------------
// Pixel Generator
// Final screen is delayed by 2 pixels 
//---------------------------------------------------------------------------
always @(posedge clk)										// synchronize xscroll and display mode changes to single cycle border
	begin
	if (single_cycle_end)
		begin
		xscroll_latch<=xscroll;
		ecm<=ecm_reg;
		bmm<=bmm_reg;
		reverse<=reverse_reg;
		mcm<=mcm_reg;
		end
	end

always @(posedge clk)										// video pixel shift tregister
	begin
	if(videoshift | widescreen)												// shift register works only when beam is on wide screen area
		begin
		if(tick8)									
			begin
				doubleshift<=~doubleshift;
				if(hcounter[2:0] == xscroll_latch)				// load register based on xscroll
					begin
					doubleshift<=0;
					if(cursor & ~bmm & ~ecm & ~mcm)		// when character is at cursor position and in Standard Character mode, load the invert of character mask
						pixelshiftreg<=waitingpixels^8'hFF;
					else pixelshiftreg<=waitingpixels;
					pixelattr<=waitingattr;					// latch attribute and charpointer for pixelgenerator
					pixelchar<=waitingchar;
					end
				else
					begin
					if(~multicolor)
						pixelshiftreg<={pixelshiftreg[6:0],1'b0};
					else if(doubleshift)											// double pixel shifting
						pixelshiftreg<={pixelshiftreg[5:0],2'b0};
					end
			end
		end
	else pixelshiftreg<=0;									// clear shiftreg at the end of screen line to avoid shifting in its content at next line		
	end


assign pixelscreen=(csel)?widescreen:narrowscreen;					// change between narrow and wide screens plus 1 pixel delay due to latch


assign multicolor= mcm & (ecm | pixelattr[3] | bmm);			// multicolor rendering is initiated when mcm=1 and either ecm,bmm or character attribute's 4th bit is 1


always @*									// video pixel color generator
	begin
	pixelcolor=bgcolor0;
	if(pixelscreen & enabledisplay)
		begin
			if (~bmm & ~ecm) 				// Standard and Multicolor Character modes
				begin
				if(~multicolor)					// Standard Character mode
					begin
					if((reverse|mcm)?pixelshiftreg[7]:(pixelshiftreg[7]& ~(pixelattr[7] & FlashCount[4]))^pixelchar[7])
						pixelcolor=pixelattr[6:0];
					end
				else 
					begin						// Multicolor Character mode
						case(pixelshiftreg[7:6])
							2'b00:	pixelcolor=bgcolor0;
							2'b01:	pixelcolor=bgcolor1;
							2'b10:	pixelcolor=bgcolor2;
							2'b11:	pixelcolor={pixelattr[6:4],1'b0,pixelattr[2:0]};
						endcase
					end				
				end
			else if (~mcm & ~bmm & ecm)		// Extended Color Character mode
				begin
					if(pixelshiftreg[7])
						pixelcolor=pixelattr[6:0];
					else begin
						case(pixelchar[7:6])
							2'b00:	pixelcolor=bgcolor0;
							2'b01:	pixelcolor=bgcolor1;
							2'b10:	pixelcolor=bgcolor2;
							2'b11:	pixelcolor=bgcolor3;
						endcase
					end	
				end
			else if(~mcm & bmm & ~ecm)			// Standard Bitmap mode
				begin
				if(pixelshiftreg[7])
					pixelcolor={pixelattr[2:0],pixelchar[7:4]};
				else pixelcolor={pixelattr[6:4],pixelchar[3:0]};
				end
			else if(mcm & bmm & ~ecm)		 // Multicolor bitmap mode
				begin
				case(pixelshiftreg[7:6])
							2'b00:	pixelcolor=bgcolor0;
							2'b01:	pixelcolor={pixelattr[2:0],pixelchar[7:4]};
							2'b10:	pixelcolor={pixelattr[6:4],pixelchar[3:0]};
							2'b11:	pixelcolor=bgcolor1;
						endcase
				end
			else										// invalid mode
				begin
				pixelcolor=7'b0;
				end
		end
	else
			pixelcolor=excolor;
	end

always @(posedge clk)						// latch pixelcolor and multiplex it with blank signal
	begin
	if (tick8)
		if(~blanking)
		colorreg<=pixelcolor;
		else colorreg<=0;
	end


//---------------------------------------------------------------------------
// Screen signals generation
//---------------------------------------------------------------------------
	
// PAL/NTSC screen constants 
assign pal = !palreg;

assign EOS = pal?9'd311:9'd261;					// End of Screen scanline
assign VS_START = pal?9'd254:9'd229;			// Vertical sync start
assign VS_STOP = pal?9'd257:9'd232; 			// Vertical sync stop 
assign EQ_START = pal?9'd251:9'd226;			// Equalization start
assign EQ_STOP = pal?9'd260:9'd235;				// Equalization stop
assign VBLANK_START = pal?9'd251:9'd226; 		// Screen blanking start
assign VBLANK_STOP = pal?9'd269:9'd244;		// Screen blanking stop// Composite Sync signal

always @(posedge clk)								// composite synchron is either hsync or equalization+vsync
	begin
	csyncreg<=(equalization)?~((eq1&eq2)|~vsync):hsync;
	end

always @(posedge clk)								// vsync signal inverts equalization signal
	begin
	if (videoline==VS_START && hpos_400)
		vsync<=1;
	else if (videoline==VS_STOP && hpos_400)
		vsync<=0;
	end

always @(posedge clk)								// equalization signal active during actual vsync+equalization window
	begin
	if(videoline==EQ_START && hpos_400)
		equalization<=1;
	else if (videoline==EQ_STOP && hpos_400)
		equalization<=0;
	end

always @(posedge clk)								// Equalization pulses generated by horizontal decoder events
	begin
	if(hpos_154)
		eq1<=0;
	else if (hpos_172)
		eq1<=1;
	if(hpos_382)
		eq2<=0;
	else if (hpos_400)
		eq2<=1;
	end
	
always @(posedge clk)								//	Horizontal sync pulse (due to original HMOS technology signal change takes 2 pixels long thus these change positions differ from the specification)
	begin
	if(hpos_359)
		hsync<=0;
	else if (hpos_391)
		hsync<=1;
	end

always @(posedge clk)							// horizontal blanking zone
	begin
	if(hpos_423)										
		hblank<=0;
	else if(hpos_353)								// in real TED it starts at 352 but slew rate takes 2 pixels. 353 is at halfway. FIXME: Might be initiated at 344.
		hblank<=1;
	end

always @(posedge clk)							// vertical blanking zone
	begin
	if(videoline==VBLANK_STOP)
		vblank<=0;
	else if(videoline==VBLANK_START)
		vblank<=1;
	end

assign blanking=hblank|vblank;
assign csync=csyncreg;
assign color=colorreg;

//-----------------------------------------------------------------------------------------------
// Memory Controller
//-----------------------------------------------------------------------------------------------

always @(posedge clk)		// Generating RAS, internal CAS and MUX signals based on clk28 cycle numbers. Not 100% precise reproduction of original TED timing but still in dram specifications
	case (phicounter)			// one clk28 cycle is 35.35ns
	1:		begin	
			ras<=1;
			cas<=1;
			mux<=1;
			cs0<=1;
			cs1<=1;
			end
	6: 	ras<=0;				// RAS goes low 35ns before MUX (20ns on real system)
	7:		begin
			mux<=0;				// MUX goes low when double phi changes to high at half double clock cycle, CS0,CS1 changes together with MUX when needed
			if(rw)				// CS0,CS1 generation only on read cycles
				begin
				if((~ramen & ~dotfetch_reg) | (charrom & dotfetch_reg ))		// ROM chip select is controlled by ramen register or by charrom register depending on whether dot data is fetched from bus
					begin
					if(lowrom)	// Basic area
						cs0<=0;
					if(highrom & ~io & ~tedreg)	// Kernal area
						cs1<=0;
					end
				end
			end
// TH: relax write timing a little bit
//	8:		if (rw & cs0 & cs1 & ~io & ~tedreg)				// when read cycle, CAS goes low 35ns after MUX (40ns on real system)
//				cas<=0;
//	11:	if (~rw & ~io & ~tedreg)								// when write cycle, CAS goes low 160ns after MUX
//				cas<=0;
	8:		if ((rw & cs0 & cs1 & ~io & ~tedreg) || (~rw & ~io & ~tedreg))
				cas<=0;
				
	default: 					// otherwise they don't change
			begin
			ras<=ras;
			mux<=mux;
			cas<=cas;
			cs0<=cs0;
			cs1<=cs1;
			end
	endcase


// Generating memory area flags. 

assign lowrom=(addr_in[15:14]==2'b10)?1'b1:1'b0;								//$8000-$bfff		low rom area (Basic)
assign highrom=(addr_in[15:14]==2'b11)?1'b1:1'b0;								//$c000-$ffff		high rom area (Kernal, IO and TED area)
assign io=(addr_in[15:8]==8'hFD || addr_in[15:8]==8'hFE)?1'b1:1'b0;		//$fd00-$feff		IO space
assign tedreg=(addr_in[15:6]==10'b1111111100 && (addr_in[5]==0 || addr_in[5:1]==7'b11111))?1'b1:1'b0;						//$ff00-$ff1f  & $ff3e-$ff3f		TED registers

//-----------------------------------------------------------------------------------------------
// Generating TED address out
//-----------------------------------------------------------------------------------------------

assign addr_out=(~aec)?addr_out_reg:16'hffff;

always @(posedge clk)
	begin
		if(cycle_end)
			begin
			addr_out_reg<=tedaddress;
			dotfetch_reg<=dotfetch;
			end
	end

assign charpointer=(inc_videocounter)?((badline2)?data_in:char_buf[39]):0;	
assign attrpointer=attr_buf[39];
	
always @*
	begin
	tedaddress=16'hffff;
	dotfetch=0;
	if(phi==0)						// generating address for phi1 phase (will be clocked and valid in phi1)
		begin
		if(dma_state==TDMA)
			tedaddress={vmbase,(badline)?1'b0:1'b1,videocounter};				// attribute or character pointer fetch address
		end
	else if(~test)	
		begin						 // generating address for phi0 phase (will be clocked and valid in phi0)
		if(refresh_inc|stopreg)				// dram refresh address
			tedaddress={8'hff,refreshcounter};
		else if(inc_charpos & char_fetch)
			begin
			dotfetch=1;
			if(~bmm)				// Text mode fetch address
				begin
				tedaddress=(~reverse)?{charbase[5:0],charpointer[6:0],VertSubCount}:{charbase[5:1],charpointer,VertSubCount};
				tedaddress[10:9]=(ecm)?2'b00:tedaddress[10:9];
				end
			else
				tedaddress={bmapbase,CharPosition,VertSubCount};	// bitmap mode fetch address
			end
		end
	else begin					// IC test mode fetch addresses
			dotfetch=1;
			if(~bmm)
				tedaddress={5'hF8,attrpointer,VertSubCount};				// test mode character screen
			else tedaddress={3'b111,(CharPosition && {2'b11,attrpointer}),VertSubCount};
			end
	end

//-----------------------------------------------------------------------------------------------
// TED registers write
//-----------------------------------------------------------------------------------------------

assign tedwrite=tedreg&~rw&cycle_end;		// It signals TED register write which happens always when rw is low and end of double clock cycle
assign tedlatch=tedwrite_delay & (phicounter==3);		// trying to simulate when exactly the hcounter is written by TED

always @(posedge clk)
	begin
		if(tedwrite)
			tedwrite_delay<=1;
		else if (phicounter==3)
			tedwrite_delay<=0;
	end

always @(posedge clk)
	begin
	resetRasterIrq<=1'b0;
	resetLpIrq<=1'b0;
	resetCnt1Irq<=1'b0;
	resetCnt2Irq<=1'b0;
	resetCnt3Irq<=1'b0;
	if (tedwrite)											// when TED registers are addressed		
		begin
		data_in_reg<=data_in;
		addr_in_reg<=addr_in[5:0];
			case(addr_in[5:0])
				CONTROL1:	// $FF06	
							begin
							test<=data_in[7];
							ecm_reg<=data_in[6];
							bmm_reg<=data_in[5];
							den<=data_in[4];
							rsel<=data_in[3];
							yscroll<=data_in[2:0];
							end
				CONTROL2:	// $FF07
							begin
							reverse_reg<=data_in[7];
							palreg<=data_in[6];
							stop<=data_in[5];
							mcm_reg<=data_in[4];
							csel<=data_in[3];
							xscroll<=data_in[2:0];
							end
				KEYLATCH:	// $FF08
							keylatch<=k[7:0];
				IRQ:			// $FF09
							begin
							resetCnt3Irq<=data_in[6];
							resetCnt2Irq<=data_in[4];
							resetCnt1Irq<=data_in[3];
							resetLpIrq<=data_in[2];
							resetRasterIrq<=data_in[1];
							end
				IRQEN:		// $FF0A
							begin
							enCnt3Irq<=data_in[6];
							enCnt2Irq<=data_in[4];
							enCnt1Irq<=data_in[3];
							enRasterIrq<=data_in[1];
							RasterCmp[8]<=data_in[0];
							end
				RASTER:		// $FF0B
							RasterCmp[7:0]<=data_in;
				CURPOSHI:	// $FF0C
							CursorPos[9:8]<=data_in[1:0];
				CURPOSLO:	// $FF0D
							CursorPos[7:0]<=data_in;
				CH1FREQLO:	// $FF0E
							Ch1Freq[7:0]<=data_in;
				CH2FREQLO:	// $FF0F
							Ch2Freq[7:0]<=data_in;
				CH2FREQHI:	// $FF10
							Ch2Freq[9:8]<=data_in[1:0];
				SOUNDCTRL:	// $FF11
							begin
							damode<=data_in[7];
							ch2noise<=data_in[6];
							ch2en<=data_in[5];
							ch1en<=data_in[4];
							volume<=data_in[3:0];
							end
				BMAPBASE:	// $FF12
							begin
							bmapbase<=data_in[5:3];
							charrom<=data_in[2];
							Ch1Freq[9:8]<=data_in[1:0];
							end
				CHARBASE:	// $FF13
							begin
							charbase<=data_in[7:2];
							clkmode<=data_in[1];
							end
				VIDEOBASE:	// $FF14
							vmbase<=data_in[7:3];
				BGCOLOR0:	// $FF15 , color change at cycle start, emulating white pixel bug (for all 5 color registers)
							bgcolor0<=8'hff;
				BGCOLOR1:	// $FF16
							bgcolor1<=8'hff;
				BGCOLOR2:	// $FF17
							bgcolor2<=8'hff;
				BGCOLOR3:	// $FF18
							bgcolor3<=8'hff;
				EXCOLOR:		// $FF19
							excolor<=8'hff;
				ROMEN:		ramen<=1'b0;
				RAMEN:		ramen<=1'b1;
				default:;
			endcase
		end
									    // Color registers write (white pixel bug emulation)
	else if (tedlatch)			// these events happen 1 pixel later after cycle start, setting the proper color to color registers
		case(addr_in_reg[5:0])
				BGCOLOR0:	// $FF15
							bgcolor0<=data_in_reg[6:0];
				BGCOLOR1:	// $FF16
							bgcolor1<=data_in_reg[6:0];
				BGCOLOR2:	// $FF17
							bgcolor2<=data_in_reg[6:0];
				BGCOLOR3:	// $FF18
							bgcolor3<=data_in_reg[6:0];
				EXCOLOR:		// $FF19
							excolor<=data_in_reg[6:0];
				default:;
		endcase
	end

// TED register read

always @(posedge clk)
	begin
	if(tedreg & rw)
		begin
		if(phicounter==7)										// latch register contents to dataout reg at mux change
			begin
				case(addr_in[5:0])
				TIMER1LO:	// $FF00
							dataout_reg<=timer1[7:0];
				TIMER1HI:	// $FF01
							dataout_reg<=timer1[15:8];
				TIMER2LO:	// $FF02
							dataout_reg<=timer2[7:0];
				TIMER2HI:	// $FF03
							dataout_reg<=timer2[15:8];
				TIMER3LO:	// $FF04
							dataout_reg<=timer3[7:0];
				TIMER3HI:	// $FF05
							dataout_reg<=timer3[15:8];
				CONTROL1:	// $FF06
							begin
							dataout_reg[7]<=test;
							dataout_reg[6]<=ecm;
							dataout_reg[5]<=bmm;
							dataout_reg[4]<=den;
							dataout_reg[3]<=rsel;
							dataout_reg[2:0]<=yscroll;
							end
				CONTROL2:	// $FF07
							begin
							dataout_reg[7]<=reverse;
							dataout_reg[6]<=palreg;
							dataout_reg[5]<=stop;
							dataout_reg[4]<=mcm;
							dataout_reg[3]<=csel;
							dataout_reg[2:0]<=xscroll;
							end
				KEYLATCH:	// $FF08
							begin
							dataout_reg<=keylatch;
							end
				
				IRQ:			// $FF09		
							begin
							dataout_reg[7]<=~irq;
							dataout_reg[6]<=Cnt3Irq;
							dataout_reg[4]<=Cnt2Irq;
							dataout_reg[3]<=Cnt1Irq;
							dataout_reg[2]<=LPIrq;			// Lightpen irq is always 1 as it is not implemented in TED
							dataout_reg[1]<=RasterIrq;
							end
				IRQEN:		// $FF0A
							begin
							dataout_reg[6]<=enCnt3Irq;
							dataout_reg[4]<=enCnt2Irq;
							dataout_reg[3]<=enCnt1Irq;
							dataout_reg[2]<=enLPIrq;			// lightpen irq enable bit is implemented in TED
							dataout_reg[1]<=enRasterIrq;
							dataout_reg[0]<=RasterCmp[8];
							end
				RASTER:		// $FF0B
							dataout_reg<=RasterCmp[7:0];
				CURPOSHI:	// $FF0C
							dataout_reg[1:0]<=CursorPos[9:8];
				CURPOSLO:	// $FF0D
							dataout_reg<=CursorPos[7:0];
				CH1FREQLO:	// $FF0E
							dataout_reg<=Ch1Freq[7:0];
				CH2FREQLO:	// $FF0F
							dataout_reg<=Ch2Freq[7:0];
				CH2FREQHI:	// $FF10
							begin
							dataout_reg[7]<=1'b0;				// the 8th unused bit is always 0
							dataout_reg[1:0]<=Ch2Freq[9:8];
							end
				SOUNDCTRL: //$FF11
							begin
							dataout_reg[7]<=damode;
							dataout_reg[6]<=ch2noise;
							dataout_reg[5]<=ch2en;
							dataout_reg[4]<=ch1en;
							dataout_reg[3:0]<=volume;
							end
				BMAPBASE:  // $FF12
							begin
							dataout_reg[5:3]<=bmapbase;
							dataout_reg[2]<=charrom;
							dataout_reg[1:0]<=Ch1Freq[9:8];
							end
				CHARBASE:  // $FF13
							begin
							dataout_reg[7:2]<=charbase;
							dataout_reg[1]<=clkmode;
							dataout_reg[0]<=~ramen;
							end
				VIDEOBASE: // $FF14
							dataout_reg[7:3]<=vmbase;
				BGCOLOR0: // $FF15
							dataout_reg[6:0]<=bgcolor0;
				BGCOLOR1: // $FF16
							dataout_reg[6:0]<=bgcolor1;
				BGCOLOR2: // $FF17
							dataout_reg[6:0]<=bgcolor2;
				BGCOLOR3: // $FF18
							dataout_reg[6:0]<=bgcolor3;
				EXCOLOR: // $FF19
							dataout_reg[6:0]<=excolor;
				CHARPOSRELOADHI: //$FF1A
							dataout_reg[1:0]<=CharPosReload[9:8];
				CHARPOSRELOADLO: //$FF1B
							dataout_reg<=CharPosReload[7:0];
				VSCANPOSHI:	// $FF1C
							dataout_reg[0]<=vcounter[8];
				VSCANPOSLO: // $FF1D
							dataout_reg<=vcounter[7:0];
				HSCANPOS:	// $FF1E
							dataout_reg<={hcounter[8:2],1'b0};
				FLASH_VERTSUB: //$FF1F
							begin
							dataout_reg[6:3]<=FlashCount[3:0];
							dataout_reg[2:0]<=VertSubCount;
							end
				ROMEN:	// $FF3E
							dataout_reg<=8'h00;
				RAMEN:	// $FF3F
							dataout_reg<=8'h00;
				default:;
				endcase
			end
		else if(phicounter==10)								// put dataout register content to databus at this moment
			datahold<=1;
		end
	if(phicounter==1)
		begin
		datahold<=0;
		dataout_reg<=8'hff;
		end
	end

assign data_out=(datahold)?dataout_reg:8'hff;

//--------------------------------------------------------------------------------
// TED audio generator
//--------------------------------------------------------------------------------

assign snd=(ch1audio&ch1pwm)|(ch2audio&ch2pwm);		// mixing audio channel signals


always @(posedge clk)						//	audio cycle counter divides single clock by 4
	begin
	if(single_cycle_end)
		audiocycle<=audiocycle+1;
	end

assign ch1clk=single_cycle_end&(audiocycle==2'b11);		// Channel1 clock 
assign ch2clk=single_cycle_end&(audiocycle==2'b01);		// Channel2 clock

// Channel 1

always @(posedge clk)
	begin
	if(ch1clk)
		begin
		if((ch1count==10'h3ff) || damode)
			ch1count<=Ch1Freq+1;
		else	ch1count<=ch1count+1;
		end
	end

assign ch1stateclk=(ch1count==10'h3ff)?1'b1:1'b0;

always @(posedge clk)	// Channel 1 state clock rising edge detection 
	begin
	ch1stateclk_prev<=ch1stateclk;
	if(damode|watchdog_ch1max)							// reset ch1state if damode is enabled or watchdog timer expires
		ch1state<=0;
	else if(~ch1stateclk_prev & ch1stateclk)		// if rising edge
				ch1state<=~ch1state;						// change channel 1 state
	end
	
assign ch1audio=(ch1en)?~ch1state:1'b0;		// ch1audio before D/A conversion

always @(posedge clk)									// emulating dynamic latch behaviour using watchdog timer (forgets setting after 188416 * audio clock cycles)
	begin
	if((~ch1stateclk_prev & ch1stateclk)|watchdog_ch1max)		// reset watchdog timer at channel1 state change or when maximum time reached
		watchdog_ch1<=0;
	else if(ch1clk)										// watchdog timer counts with audio clock cycles
		watchdog_ch1<=watchdog_ch1+1;
	end

assign watchdog_ch1max=(watchdog_ch1==18'd188416)?1'b1:1'b0;	

// Channel 2

always @(posedge clk)
	begin
	if(ch2clk)
		begin
		if((ch2count==10'h3ff) || damode)
			ch2count<=Ch2Freq+1;
		else	ch2count<=ch2count+1;
		end
	end

assign ch2stateclk=(ch2count==10'h3ff)?1'b1:1'b0;

always @(posedge clk)	// Channel 2 state clock rising edge detection 
	begin
	ch2stateclk_prev<=ch2stateclk;
	if(damode)												// reset ch2state if damode is enabled
		ch2state<=0;
	else if(~ch2stateclk_prev & ch2stateclk)		// if rising edge
				ch2state<=~ch2state;						// change channel 2 state
	end
	
assign ch2audio=(ch2en)?~ch2state:noise;		// ch2audio combined with noise before D/A conversion

always @(posedge clk)									// emulating dynamic latch behaviour using watchdog timer (forgets setting after 188416 * audio clock cycles)
	begin
	if((~ch2stateclk_prev & ch2stateclk)|watchdog_ch2max)		// reset watchdog timer at channel1 state change or when maximum time reached
		watchdog_ch2<=0;
	else if(ch2clk)										// watchdog timer counts with audio clock cycles
		watchdog_ch2<=watchdog_ch2+1;
	end

assign watchdog_ch2max=(watchdog_ch2==18'd188416)?1'b1:1'b0;	


// Noise generator

always @(posedge clk)
	begin
	if(damode)
		noisegen<=0;
	else if(~ch2stateclk_prev & ch2stateclk)
		begin
		for(n=1;n<8;n=n+1)
			begin
			noisegen[n]<=noisegen[n-1];
			end
		noisegen[0]<=1^noisegen[7]^noisegen[5]^noisegen[4]^noisegen[1];
		end
	end

assign noise=(ch2noise)?noisegen[0]:1'b0;		// noise signal

// D/A converter

always @*								// volume value conversion to pwmcounter numbers where PWM signal high value starts
	begin
	case (volume)
		0:		digivolume=31;
		1:		digivolume=30;
		2:		digivolume=28;
		3:		digivolume=26;
		4:		digivolume=24;
		5:		digivolume=22;
		6:		digivolume=20;
		7:		digivolume=18;
		8:		digivolume=16;
		default:	digivolume=16;
	endcase
	end

always @(posedge clk)					// generating PWM pulses for channel1
	begin
	if(tick8)
		begin
		if(ch1clk)							// synchronizing channel1 PWM signal to channel1 audio 
			pwmcounter1<=0;
		else pwmcounter1<=pwmcounter1+1;
		
		if ( pwmcounter1 < digivolume || pwmcounter1==31 )		// set pwm signal duty cycle based on modified volume value
				ch1pwm<=0;
		else	ch1pwm<=1;
		end
	end

always @(posedge clk)					// generating PWM pulses for channel2
	begin
	if(tick8)
		begin
		if(ch2clk)							// synchronizing channel2 PWM signal to channel2 audio (it is shifted by 2 single clock cycles compared to channel1)
			pwmcounter2<=0;
		else pwmcounter2<=pwmcounter2+1;
		
		if ( pwmcounter2 < digivolume || pwmcounter2==31 )		// set pwm signal duty cycle based on modified volume value
				ch2pwm<=0;
		else	ch2pwm<=1;
		end
	end
	
endmodule