// Copyright 2006, 2007 Dennis van Weeren
//
// This file is part of Minimig
//
// Minimig is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Minimig is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
//
// This is the Copper (part of the Agnus chip)
//
// 24-05-2005	-started coding (created all user accessible registers)
// 25-05-2005	-added beam counter compare logic
// 29-05-2005	-added blitter finished disable logic
//				-added copper danger/address range check logic
//				-added controlling state machine
//				-adapted to use reqdma/ackdma model
//				-first finished version
// 11-09-2005	-added proper reset for copper location registers
// 24-09-2005	-fixed bug, when an illegal register is loaded by MOVE,
//				 the copper must halt until the next strobe or vertical blank.
//				 the copper now does this properly
// 02-10-2005	-modified skip instruction to only skip MOVE instructions.
// 19-10-2005	-replaced vertb (vertical blank) signal by sof (start of frame)
// 07-12-2005	-added dummy cycle after copper wakeup, this is needed for copperlists
//				 that wait for vertical beamcounter rollover ($FFDF,FFFE)
//				 The dummy cycle is indicated by making both selins and selreg high.
// 26-12-2005	-added exception for last cycle of horizontal line, this cycle is not used by copper
//
// JB:
// 2008-03-03	- ECS copper danger behaviour
// 2008-07-08	- clean-up
// 2008-07-17	- real Amiga timing behaviour (thanks to Toni Wilen for help)
// 2008-11-24	- clean-up
// 				- wait/skip free cycles reimplementation
//
// Although I spend a lot of time trying to figure out real behaviour of Amiga hardware this solution is not complete.
// more cycle-exact
//				- dma_bpl implementation 
//				- WAIT and SKIP states no longer keep CPU and blitter off the bus
// 2009-01-16	- clean-up
// 2009-05-24	- clean-up & renaming
// 2009-05-29	- dma_bpl replaced with dma_ena
// 2009-10-07	- implementation of blocked $E1 cycles
//				- modified copper restart
// 2010-06-16	- ECS/OCS CDANG behaviour implemented

module copper
(
	input 	clk,	 					// bus clock
	input 	reset,	 					// system reset (synchronous)
	input	ecs,						// enable ECS chipset features
	output	reqdma,						// copper requests dma cycle
	input	ackdma,						// agnus dma priority logic grants dma cycle
	input	enadma,						// current slot is not used by any higher priority DMA channel
	input	sof,						// start of frame input
	input	blit_busy,					// blitter busy flag input
	input	[7:0] vpos,					// vertical beam counter
	input	[8:0] hpos,					// horizontal beam counter
	input 	[15:0] data_in,	    		// data bus input
	input 	[8:1] reg_address_in,		// register address input
	output 	reg [8:1] reg_address_out,	// register address output
	output 	reg [20:1] address_out 		// chip address output
);

// register names and adresses		
parameter COP1LCH = 9'h080;
parameter COP1LCL = 9'h082;
parameter COP2LCH = 9'h084;
parameter COP2LCL = 9'h086;
parameter COPCON  = 9'h02e;
parameter COPINS  = 9'h08c;
parameter COPJMP1 = 9'h088;
parameter COPJMP2 = 9'h08a;

// copper states
parameter RESET     = 3'b000;
parameter FETCH1    = 3'b100;
parameter FETCH2    = 3'b101;
parameter WAITSKIP1 = 3'b111;
parameter WAITSKIP2 = 3'b110;

// local signals
reg		[20:16] cop1lch;	// copper location register 1
reg		[15:1] cop1lcl;		// copper location register 1
reg		[20:16] cop2lch;	// copper location register 2
reg		[15:1] cop2lcl;		// copper location register 2
reg		cdang;				// copper danger bit
reg		[15:1] ir1;			// instruction register 1
reg		[15:0] ir2;			// instruction register 2
reg		[2:0] copper_state;	// current state of copper state machine
reg		[2:0] copper_next;	// next state of copper state machine

reg		strobe1;			// strobe 1 
reg		strobe2;			// strobe 2 
reg		strobe;
reg		illegalreg;			// illegal register (MOVE instruction)
reg		skip_flag;			// skip move instruction latch
reg		selins;				// load instruction register (register address out = COPINS)
reg		selreg;				// load chip register address, when both selins and selreg are active
							// a dummy cycle is executed
reg		skip;				// skip next move instruction (input to skip_flag register)

wire	enable;				// enables copper fsm and dma slot
reg		dma_req;
wire	dma_ack;
wire  dma_ena;
reg		beam_match;			// delayed beam match signal
wire	beam_match_skip;	// beam match signal for SKIP condition check
reg		beam_match_wait;	// beam match signal for WAIT condition chaeck

wire	clk_ena;			// enables every other clock cycle for chipset use 
reg		bus_ena;			// enables CCK cycle for copper use
reg		bus_blk;			// bus blocked by attempting an access in the "unusable" cycle

//--------------------------------------------------------------------------------------

// since Minimig's memory bus runs twice as fast as its real Amiga counterpart
// the chipset is required to use every other memory cycle to run virtually at the same speed
assign clk_ena = hpos[0];

// horizontal counter in Agnus is advanced 4 lores pixels in comparision with the one in Denise
// if the horizontal line contains odd number of CCK cycles (short lines of NTSC mode and all lines of PAL mode)
// there is a place where two cycles usable by the copper are located back to back
// in such a situation the first cycle is not used (but locks the bus if it has a chance)

//write copper location register 1 high and low word
always @(posedge clk)
	if (reset)
		cop1lch[20:16] <= 0;
	else if (reg_address_in[8:1]==COP1LCH[8:1])
		cop1lch[20:16] <= data_in[4:0];
		
always @(posedge clk)
	if (reset)
		cop1lcl[15:1] <= 0;
	else if (reg_address_in[8:1]==COP1LCL[8:1])
		cop1lcl[15:1] <= data_in[15:1];

//write copper location register 2 high and low word
always @(posedge clk)
	if (reset)
		cop2lch[20:16]<=0;
	else if (reg_address_in[8:1]==COP2LCH[8:1])
		cop2lch[20:16] <= data_in[4:0];

always @(posedge clk)
	if (reset)
		cop2lcl[15:1] <= 0;
	else if (reg_address_in[8:1]==COP2LCL[8:1])
		cop2lcl[15:1] <= data_in[15:1];

//write copcon register (copper danger bit)
always @(posedge clk)
	if (reset)
		cdang <= 0;
	else if (reg_address_in[8:1]==COPCON[8:1])
		cdang <= data_in[1];

//copper instruction registers ir1 and ir2
always @(posedge clk)
	if (reg_address_in[8:1]==COPINS[8:1])
	begin
		ir1[15:1] <= ir2[15:1];
		ir2[15:0] <= data_in[15:0];
	end

//--------------------------------------------------------------------------------------

//chip address pointer (or copper program counter) controller
always @(posedge clk)
	if (dma_ack && strobe1 && copper_state==RESET)//load pointer with location register 1
		address_out[20:1] <= {cop1lch[20:16],cop1lcl[15:1]};
	else if (dma_ack && strobe2 && copper_state==RESET)//load pointer with location register 2
		address_out[20:1] <= {cop2lch[20:16],cop2lcl[15:1]};
	else if (dma_ack && (selins || selreg))//increment address pointer (when not dummy cycle) 
		address_out[20:1] <= address_out[20:1] + 1'b1;

//--------------------------------------------------------------------------------------

// regaddress output select
// if selins=1 the address of the copper instruction register
// is sent out (not strictly necessary as we can load copins directly. However, this is 
// more according to what happens in a real amiga... I think), else the contents of
// ir2[8:1] is selected 
// (if you ask yourself: IR2? is this a bug? then check how ir1/ir2 are loaded in this design)
always @(enable or selins or selreg or ir2)
	if (enable & selins) //load our instruction register
		reg_address_out[8:1] = COPINS[8:1];
	else if (enable & selreg)//load register in move instruction
		reg_address_out[8:1] = ir2[8:1];
	else
		reg_address_out[8:1] = 8'hFF;//during dummy cycle null register address is present

// detect illegal register access
// CDANG = 0 (OCS/ECS) : $080-$1FE allowed
// CDANG = 1 (OCS)     : $040-$1FE allowed
// CDANG = 1 (ECS)     : $000-$1FE allowed
always @(ir2 or cdang or ecs)
	if (ir2[8:7]==2'b00 && !cdang || ir2[8:6]==3'b000 && !ecs) // illegal access
		illegalreg = 1'b1;
	else // $080 -> $1FE always allowed
		illegalreg = 1'b0;

//--------------------------------------------------------------------------------------

reg copjmp1, copjmp2;
	
always @(posedge clk)
	if (reg_address_in[8:1]==COPJMP1[8:1] || sof)
		copjmp1 = 1;
	else if (clk_ena)
		copjmp1 = 0;
		
always @(posedge clk)
	if (reg_address_in[8:1]==COPJMP2[8:1])
		copjmp2 = 1;
	else if (clk_ena)
		copjmp2 = 0;
		
//strobe1 (also triggered by sof, start of frame)
always @(posedge clk)
	if (copjmp1 && clk_ena)
		strobe1 = 1;
	else if (copper_state==RESET && dma_ack)
		strobe1 = 0;
		
//strobe2
always @(posedge clk)
	if (copjmp2 && clk_ena)
		strobe2 = 1;
	else if (copper_state==RESET && dma_ack)
		strobe2 = 0;
		
always @(posedge clk)
	if (clk_ena)
		strobe = copjmp1 | copjmp2;		
		
//--------------------------------------------------------------------------------------

//beam compare circuitry
//when the mask for a compare bit is 1, the beamcounter is compared with that bit,
//when the mask is 0, the compare bit is replaced with the corresponding beamcounter bit
//itself, thus the compare is always true.
//the blitter busy flag is also checked if blitter finished disable is false

wire [8:2] horcmp;
wire [7:0] vercmp;

//construct compare value for horizontal beam counter (4 lores pixels resolution)
assign horcmp[2] = (ir2[1]) ? ir1[1] : hpos[2];
assign horcmp[3] = (ir2[2]) ? ir1[2] : hpos[3];
assign horcmp[4] = (ir2[3]) ? ir1[3] : hpos[4];
assign horcmp[5] = (ir2[4]) ? ir1[4] : hpos[5];
assign horcmp[6] = (ir2[5]) ? ir1[5] : hpos[6];
assign horcmp[7] = (ir2[6]) ? ir1[6] : hpos[7];
assign horcmp[8] = (ir2[7]) ? ir1[7] : hpos[8];

//construct compare value for vertical beam counter (1 line resolution)
assign vercmp[0] =  (ir2[8]) ?  ir1[8] : vpos[0];
assign vercmp[1] =  (ir2[9]) ?  ir1[9] : vpos[1];
assign vercmp[2] = (ir2[10]) ? ir1[10] : vpos[2];
assign vercmp[3] = (ir2[11]) ? ir1[11] : vpos[3];
assign vercmp[4] = (ir2[12]) ? ir1[12] : vpos[4];
assign vercmp[5] = (ir2[13]) ? ir1[13] : vpos[5];
assign vercmp[6] = (ir2[14]) ? ir1[14] : vpos[6];
assign vercmp[7] = ir1[15];
 
// actual beam position comparator
always @(posedge clk)
	if (clk_ena)
		if ({vpos[7:0],hpos[8:2]} >= {vercmp[7:0],horcmp[8:2]}) 
			beam_match <= 1'b1;
		else
			beam_match <= 1'b0;

assign beam_match_skip = beam_match & (ir2[15] | ~blit_busy);

always @(posedge clk)
	if (clk_ena)
		beam_match_wait <= beam_match_skip;

//--------------------------------------------------------------------------------------
/*


WAIT: first cycle after fetch of second instruction word is a cycle when comparision with beam counter takes place
this comparision is beeing done all the time regardless of the available DMA slot
when the comparision condition is safisfied the FSM goes to wait_wake_up state,
it stays in this state as long as display DMA takes the DMA slots
when display DMA doesn't use even bus cycle the FSM advances to the fetch state (the slot isn't used by the copper, DBR is deasserted)
such a behaviour is caused by dma request pipelining in real Agnus

*/
//--------------------------------------------------------------------------------------
    
//generate dma request signal (reqdma)
//copper only uses even cycles: hpos[1:0]==2'b01)
//the last cycle of the short line is not usable by the copper
//in PAL mode when the copper wants to access memory bus in cycle $E1 the DBR is activated 
//(blocks the blitter and CPU) but actual transfer takes place in the next cycle (DBR still asserted)

always @(posedge clk)
	if (clk_ena)
		if (hpos[8:1]==8'h01)
			bus_blk <= 1; //cycle $E1 is blocked
		else
			bus_blk <= 0;

always @(posedge clk)
	if (clk_ena)
		if (bus_blk)
			bus_ena <= 1; //cycle $E2 is usable
		else
			bus_ena <= ~bus_ena;
						
assign enable = ~bus_blk & bus_ena & clk_ena;

assign reqdma = dma_req & bus_ena & clk_ena; //dma is request also during $E1 but output register address is idle
assign dma_ack = ackdma & enable; //dma ack is masked during $E1
assign dma_ena = enadma; //dma slot is empty and can be used by copper


//hint: during vblank copper instruction pointer is reloaded just after the first refresh slot	
//there is at least 2 CCK delay between writing COPJMPx register and pointer reload 
//copper state machine and skip_flag latch
always @(posedge clk)
	if (reset || clk_ena && strobe) // on strobe or reset fetch first instruction word
		copper_state <= RESET;
	else if (enable) // go to next state
		copper_state <= copper_next;

always @(posedge clk)
	if (enable)
		skip_flag <= skip;
	
always @(*)//(copper_state or ir2 or beam_match_wait or beam_match_skip or illegalreg or skip_flag or dma_ack or dma_ena)
begin
	case (copper_state)
	
		//when COPJMPx is written there is 2 cycle delay before data from new location is read to COPINS
		//usually first cycle is a read of the next instruction to COPINS or bitplane DMA,
		//the second is dma free cycle (it's a dummy cycle requested by copper but not used to transfer data)
		
		//after reset or strobe write an allocated DMA cycle is required to reload instruction pointer from location registers
		RESET:
		begin
			skip = 0;
			selins = 0;
			selreg = 0;
			dma_req = 1; //a DMA access is requested to reload instuction pointer
			if (dma_ack)
				copper_next = FETCH1;
			else
				copper_next = RESET;
		end
		
		//fetch first instruction word
		FETCH1:
		begin
			skip = skip_flag;
			selins = 1;
			selreg = 0;
			dma_req = 1;
			if (dma_ack)
				copper_next = FETCH2;
			else
				copper_next = FETCH1;
		end

		//fetch second instruction word, skip or do MOVE instruction or halt copper
		FETCH2:			
		begin
			if (!ir2[0] && illegalreg) // illegal MOVE instruction, halt copper
			begin
				skip = 0;
				selins = 0;
				selreg = 0;
				dma_req = 0;
				copper_next = FETCH2;
			end
			else if (!ir2[0] && skip_flag) // skip this MOVE instruction
			begin
				selins = 1;
				selreg = 0;
				dma_req = 1;
				if (dma_ack)
				begin
					skip = 0;
					copper_next = FETCH1;
				end
				else
				begin
					skip = 1;
					copper_next = FETCH2;
				end
			end
			else if (!ir2[0]) // MOVE instruction
			begin
				skip = 0;
				selins = 0;
				selreg = 1;
				dma_req = 1;
				if (dma_ack)
					copper_next = FETCH1;
				else
					copper_next = FETCH2;
			end
			else//fetch second instruction word of WAIT or SKIP instruction
			begin
				skip = 0;
				selins = 1;
				selreg = 0;
				dma_req = 1;
				if (dma_ack)
					copper_next = WAITSKIP1;
				else
					copper_next = FETCH2;				
			end
		end
		
		//both SKIP and WAIT have the same timing when WAIT is immediatelly complete
		//both these instructions complete in 4 cycles and these cycles must be allocated dma cycles
		//first cycle seems to be dummy

		WAITSKIP1:
		begin
			skip = 0;
			selins = 0;
			selreg = 0;
			dma_req = 0;
			if (dma_ena)
				copper_next = WAITSKIP2;
			else
				copper_next = WAITSKIP1;
		end
		
		//second cycle of WAIT or SKIP (allocated dma)
		//WAIT or SKIP instruction
		WAITSKIP2:
		begin
			if (!ir2[0]) // WAIT instruction
			begin
				if (beam_match_wait) // wait is over, fetch next instruction
				begin
					skip = 0;
					selins = 0;
					selreg = 0;
					dma_req = 0;
					if (dma_ena)
						copper_next = FETCH1;
					else
						copper_next = WAITSKIP2;
				end
				else//still waiting
				begin
					skip = 0;
					selins = 0;
					selreg = 0;
					dma_req = 0;
					copper_next = WAITSKIP2;
				end
			end
			else // SKIP instruction
			begin
				if (beam_match_skip) // compare is true, fetch next instruction and skip it if it's MOVE
				begin
					skip = 1;
					selins = 0;
					selreg = 0;
					dma_req = 0;			
					if (dma_ena)
						copper_next = FETCH1;
					else
						copper_next = WAITSKIP2;
				end
				else//do not skip, fetch next instruction
				begin
					skip = 0;
					selins = 0;
					selreg = 0;
					dma_req = 0;						
					if (dma_ena)
						copper_next = FETCH1;
					else
						copper_next = WAITSKIP2;
				end
			end
		end
	
		//default, go back to reset state
		default:
		begin
			skip = 0;
			selins = 0;
			selreg = 0;
			dma_req = 0;			
			copper_next = FETCH1;
		end
		
	endcase
end	

//--------------------------------------------------------------------------------------



//--------------------------------------------------------------------------------------

endmodule

