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
// along with this program.  If not, see <http:// www.gnu.org/licenses/>.
// 
// 
// 
// These are the cia's
// Note that these are simplified implementation of both CIA's, just enough
// to get Minimig going
// NOT implemented is:
// serial data register for CIA B(but keyboard input for CIA A is supported)
// port B for CIA A
// counter inputs for timer A and B other then 'E' clock
// toggling of PB6/PB7 by timer A/B
// 
// 30-03-2005	-started coding 
// 				-intterupt description finished
// 03-04-2005	-added timers A,B and D
// 05-04-2005	-simplified state machine of timerab
// 				-improved timing of timer-reload of timerab
// 				-cleaned up timer d
// 				-moved intterupt part to seperate module
// 				-created nice central address decoder
// 06-04-2005	-added I/O ports
// 				-fixed small bug in timerab state machine
// 10-04-2005	-added clock synchronisation latch on input ports
// 				-added rd (read) input to detect valid bus states
// 11-04-2005	-removed rd again due to change in address decoder
// 				-better reset behaviour for timer D
// 17-04-2005	-even better reset behaviour for timer D and timers A and B
// 17-07-2005	-added pull-up simulation on I/O ports
// 21-12-2005	-added rd input
// 21-11-2006	-splitted in seperate ciaa and ciab
// 				-added ps2 keyboard module to ciaa
// 22-11-2006	-added keyboard reset
// 05-12-2006	-added keyboard acknowledge
// 11-12-2006	-ciaa cleanup
// 27-12-2006	-ciab cleanup
// 01-01-2007	-osd_ctrl[] is now 4 bits/keys


// JB:
// 2008-03-25	- osd_ctrl[] is 6 bits/keys (Ctrl+Break and PrtScr keys added)
// 				- verilog 2001 style declaration
// 2008-04-02	- separate Timer A and Timer B descriptions (they differ a little)
// 				- one-shot mode of Timer A/B sets START bit in control register
// 				- implemented Timer B counting mode of Timer A underflows
// 2008-04-25	- added transmit interrupt for serial port
// 2008-07-28	- scroll lock led as disk activity led
// 2008-12-29	- more sophisticated implementation of serial port transmit interrupt (fixes problem with keyboard in Citadel)
// 				- fixed reloading of Timer A/B when writing THI in stop mode
// 2009-02-01	- osd_ctrl[] is 8 bit wide
// 2009-05-24	- clean-up & renaming
// 2009-06-12	- sdr returns written value
// 2009-06-17	- timer A&B reset to 0xFFFF
// 2009-07-09	- reading of port B of CIA A ($BFE101) returns all ones ($FF)
// 2009-12-28	- added serial port register to CIA B
// 2010-08-15	- added joystick emulation
// 
// SB:
// 2011-04-02 - added ciaa port b (parallel) register to let Unreal game work and some trainer store data
// 2011-04-24 - fixed TOD read
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------

/*cia a*/
module ciaa
(
	input 	clk,	  			// clock
	input 	aen,		    	// adress enable
	input	rd,					// read enable
	input	wr,					// write enable
	input 	reset, 				// reset
	input 	[3:0] rs,	   		// register select (address)
	input 	[7:0] data_in,		// bus data in
	output 	[7:0] data_out,		// bus data out
	input 	tick,				// tick (counter input for TOD timer)
	input 	eclk,    			// eclk (counter input for timer A/B)
	output 	irq,	   			// interrupt request out
	input	[7:2] porta_in, 	// porta in
	output 	[1:0] porta_out,	// porta out
	output	kbdrst,				// keyboard reset out
	inout	kbddat,				// ps2 keyboard data
	inout	kbdclk,				// ps2 keyboard clock
	input	keyboard_disabled,	// disable keystrokes
   input kbd_mouse_strobe,
   input [1:0] kbd_mouse_type,
   input [7:0] kbd_mouse_data,
	output	[7:0] osd_ctrl,		// osd control
	output	_lmb,
	output	_rmb,
	output	[5:0] _joy2,
  output  aflock,       // auto fire lock
	output	freeze,				// Action Replay freeze key
	input	disk_led,			// floppy disk activity LED
  input osd_enable,
  output [5:0] mou_emu,
  output [5:0] joy_emu,
  input joy_emu_en
);

// local signals
wire 	[7:0] icr_out;
wire	[7:0] tmra_out;			
wire	[7:0] tmrb_out;
wire	[7:0] tmrd_out;
wire	[7:0] sdr_out;	
reg		[7:0] pa_out;
reg		[7:0] pb_out;
wire  [7:0] portb_out;
wire	alrm;				// TOD interrupt
wire	ta;					// TIMER A interrupt
wire	tb;					// TIMER B interrupt
wire	tmra_ovf;			// TIMER A underflow (for Timer B)

wire	spmode;				// TIMER A Serial Port Mode (0-input, 1-output)
wire	ser_tx_irq;			// serial port transmit interrupt request
reg		[3:0] ser_tx_cnt; 	// serial port transmit bit counter
reg		ser_tx_run;			// serial port is transmitting

reg		tick_del;			// required for edge detection

//----------------------------------------------------------------------------------
// address decoder
//----------------------------------------------------------------------------------
wire	pra,prb,ddra,ddrb,cra,talo,tahi,crb,tblo,tbhi,tdlo,tdme,tdhi,icrs,sdr;
wire	enable;

assign enable = aen & (rd | wr);

// decoder
assign	pra  = (enable && rs==4'h0) ? 1'b1 : 1'b0;
assign	prb  = (enable && rs==4'h1) ? 1'b1 : 1'b0;
assign	ddra = (enable && rs==4'h2) ? 1'b1 : 1'b0;
assign  ddrb = (enable && rs==4'h3) ? 1'b1 : 1'b0;
assign	talo = (enable && rs==4'h4) ? 1'b1 : 1'b0;
assign	tahi = (enable && rs==4'h5) ? 1'b1 : 1'b0;
assign	tblo = (enable && rs==4'h6) ? 1'b1 : 1'b0;
assign	tbhi = (enable && rs==4'h7) ? 1'b1 : 1'b0;
assign	tdlo = (enable && rs==4'h8) ? 1'b1 : 1'b0;
assign	tdme = (enable && rs==4'h9) ? 1'b1 : 1'b0;
assign	tdhi = (enable && rs==4'hA) ? 1'b1 : 1'b0;
assign	sdr  = (enable && rs==4'hC) ? 1'b1 : 1'b0;
assign	icrs = (enable && rs==4'hD) ? 1'b1 : 1'b0;
assign	cra  = (enable && rs==4'hE) ? 1'b1 : 1'b0;
assign	crb  = (enable && rs==4'hF) ? 1'b1 : 1'b0;

//----------------------------------------------------------------------------------
// data_out multiplexer
//----------------------------------------------------------------------------------
assign data_out = icr_out | tmra_out | tmrb_out | tmrd_out | sdr_out | pb_out | pa_out;

//----------------------------------------------------------------------------------
// instantiate keyboard module
//----------------------------------------------------------------------------------
reg		[7:0] sdr_latch;

`ifdef PS2_KEYBOARD
wire	[7:0] keydat;

ps2keyboard	kbd1
(
	.clk(clk),
	.reset(reset),
	.ps2kdat(kbddat),
	.ps2kclk(kbdclk),
	.leda(~porta_out[1]),	// keyboard joystick LED - num lock
	.ledb(disk_led),		// disk activity LED - scroll lock
   .aflock(aflock),
	.kbdrst(kbdrst),
	.keydat(keydat[7:0]),
	.keystrobe(keystrobe),
	.keyack(keyack),
   .osd_enable(osd_enable),
	.osd_ctrl(osd_ctrl),
	._lmb(_lmb),
	._rmb(_rmb),
	._joy2(_joy2),
	.freeze(freeze),
  .mou_emu(mou_emu),
  .joy_emu(joy_emu),
  .joy_emu_en (joy_emu_en)
);
`endif

assign kbdrst = 1'b0;
assign _lmb = 1'b1;
assign _rmb = 1'b1;
assign _joy2 = 6'b11_1111;
assign joy_emu = 6'b11_1111;
assign mou_emu = 6'b11_1111;
assign freeze = 1'b0;
assign aflock = 1'b0;
 
reg [7:0] osd_ctrl_reg;

reg keystrobe_reg;
assign keystrobe = keystrobe_reg;

assign osd_ctrl = osd_ctrl_reg;

// generate a keystrobe which is valid exactly one clk cycle
reg kbd_mouse_strobeD, kbd_mouse_strobeD2;
always @(posedge clk)
	kbd_mouse_strobeD <= kbd_mouse_strobe;
	
always @(negedge clk) begin
	kbd_mouse_strobeD2 <= kbd_mouse_strobeD;
	keystrobe_reg <= kbd_mouse_strobeD && !kbd_mouse_strobeD2;
end
	
// sdr register
// !!! Amiga receives keycode ONE STEP ROTATED TO THE RIGHT AND INVERTED !!!
always @(posedge clk) begin
	if (reset) begin
		sdr_latch[7:0] <= 8'h00;
		osd_ctrl_reg[7:0] <= 8'd0;
   end else begin
		if (keystrobe && (kbd_mouse_type == 2) && ~keyboard_disabled)
			sdr_latch[7:0] <= ~{kbd_mouse_data[6:0],kbd_mouse_data[7]};
		else if (wr & sdr)
			sdr_latch[7:0] <= data_in[7:0];

		if(keystrobe && ((kbd_mouse_type == 2) || (kbd_mouse_type == 3)))
			osd_ctrl_reg[7:0] <= kbd_mouse_data;
	end
end
			
// sdr register	read
assign sdr_out = (!wr && sdr) ? sdr_latch[7:0] : 8'h00;
// keyboard acknowledge
assign keyack = (!wr && sdr) ? 1'b1 : 1'b0;

// serial port transmision in progress
always @(posedge clk)
	if (reset || !spmode) // reset or not in output mode
		ser_tx_run <= 0;
	else if (sdr && wr) // write to serial port data register when serial port is in output mode
		ser_tx_run <= 1;
	else if (ser_tx_irq) // last bit has been transmitted
		ser_tx_run <= 0;

// serial port transmitted bits counter		
always @(posedge clk)
	if (!ser_tx_run)
		ser_tx_cnt <= 4'd0;
	else if (tmra_ovf) // bits are transmitted when tmra overflows
		ser_tx_cnt <= ser_tx_cnt + 4'd1;

assign ser_tx_irq = &ser_tx_cnt & tmra_ovf; // signal irq when ser_tx_cnt overflows

//----------------------------------------------------------------------------------
// porta
//----------------------------------------------------------------------------------
reg [7:2] porta_in2;
reg [1:0] regporta;
reg [7:0] ddrporta;

// synchronizing of input data
always @(posedge clk)
	porta_in2[7:2] <= porta_in[7:2];

// writing of output port
always @(posedge clk)
	if (reset)
		regporta[1:0] <= 2'd0;
	else if (wr && pra)
		regporta[1:0] <= data_in[1:0];

// writing of ddr register 
always @(posedge clk)
	if (reset)
		ddrporta[7:0] <= 8'd0;
	else if (wr && ddra)
 		ddrporta[7:0] <= data_in[7:0];

// reading of port/ddr register
always @(wr or pra or porta_in2 or porta_out or ddra or ddrporta)
begin
	if (!wr && pra)
		pa_out[7:0] = {porta_in2[7:2],porta_out[1:0]};
	else if (!wr && ddra)
		pa_out[7:0] = ddrporta[7:0];
	else
		pa_out[7:0] = 8'h00;
end
		
// assignment of output port while keeping in mind that the original 8520 uses pull-ups
assign porta_out[1:0] = (~ddrporta[1:0]) | regporta[1:0];

//----------------------------------------------------------------------------------
// portb
//----------------------------------------------------------------------------------
reg [7:0] regportb;
reg [7:0] ddrportb;

// writing of output port
always @(posedge clk)
  if (reset)
    regportb[7:0] <= 8'd0;
  else if (wr && prb)
    regportb[7:0] <= (data_in[7:0]);

// writing of ddr register 
always @(posedge clk)
  if (reset)
    ddrportb[7:0] <= 8'd0;
  else if (wr && ddrb)
    ddrportb[7:0] <= (data_in[7:0]);

// reading of port/ddr register
always @(wr or prb or portb_out or ddrb or ddrportb)
begin
  if (!wr && prb)
    pb_out[7:0] = (portb_out[7:0]);
  else if (!wr && ddrb)
    pb_out[7:0] = (ddrportb[7:0]);
  else
    pb_out[7:0] = 8'h00;
end

// assignment of output port while keeping in mind that the original 8520 uses pull-ups
assign portb_out[7:0] = ((~ddrportb[7:0]) | (regportb[7:0]));

// delayed tick signal for edge detection
always @(posedge clk)
	tick_del <= tick;

//----------------------------------------------------------------------------------
// instantiate cia interrupt controller
//----------------------------------------------------------------------------------
ciaint cnt 
(
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.icrs(icrs),
	.ta(ta),
	.tb(tb),
	.alrm(alrm),
	.flag(1'b0),
	.ser(keystrobe & ~keyboard_disabled | ser_tx_irq),
	.data_in(data_in),
	.data_out(icr_out),
	.irq(irq)	
);

//----------------------------------------------------------------------------------
// instantiate timer A
//----------------------------------------------------------------------------------
timera tmra 
(
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.tlo(talo),
	.thi(tahi),
	.tcr(cra),
	.data_in(data_in),
	.data_out(tmra_out),
	.eclk(eclk),
	.spmode(spmode),
	.tmra_ovf(tmra_ovf),
	.irq(ta) 
);

//----------------------------------------------------------------------------------
// instantiate timer B
//----------------------------------------------------------------------------------
timerb tmrb 
(	
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.tlo(tblo),
	.thi(tbhi),
	.tcr(crb),
	.data_in(data_in),
	.data_out(tmrb_out),
	.eclk(eclk),
	.tmra_ovf(tmra_ovf),
	.irq(tb) 
);

//----------------------------------------------------------------------------------
// instantiate timer D
//----------------------------------------------------------------------------------
timerd tmrd
(
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.tlo(tdlo),
	.tme(tdme),
	.thi(tdhi),
	.tcr(crb),
	.data_in(data_in),
	.data_out(tmrd_out),
	.count(tick & ~tick_del),
	.irq(alrm)	
); 

endmodule

//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------

/*cia b*/
module ciab
(
	input 	clk,	  			// clock
	input 	aen,		    	// adress enable
	input	rd,					// read enable
	input	wr,					// write enable
	input 	reset, 				// reset
	input 	[3:0] rs,	   		// register select (address)
	input 	[7:0] data_in,		// bus data in
	output 	[7:0] data_out,		// bus data out
	input 	tick,				// tick (counter input for TOD timer)
	input 	eclk,	   			// eclk (counter input for timer A/B)
	input 	flag, 				// flag (set FLG bit in ICR register)
	output 	irq,	   			// interrupt request out
	input	[5:3] porta_in, 	// input port
	output 	[7:6] porta_out,	// output port
	output	[7:0] portb_out		// output port
);

// local signals
	wire 	[7:0] icr_out;
	wire	[7:0] tmra_out;			
	wire	[7:0] tmrb_out;
	wire	[7:0] tmrd_out;	
	reg		[7:0] pa_out;
	reg		[7:0] pb_out;		
	wire	alrm;				// TOD interrupt
	wire	ta;					// TIMER A interrupt
	wire	tb;					// TIMER B interrupt
	wire	tmra_ovf;			// TIMER A underflow (for Timer B)

	reg		[7:0] sdr_latch;
	wire	[7:0] sdr_out;	
	
	reg		tick_del;			// required for edge detection
	
//----------------------------------------------------------------------------------
// address decoder
//----------------------------------------------------------------------------------
	wire	pra,prb,ddra,ddrb,cra,talo,tahi,crb,tblo,tbhi,tdlo,tdme,tdhi,sdr,icrs;
	wire	enable;

assign enable = aen & (rd | wr);

// decoder
assign	pra  = (enable && rs==4'h0) ? 1'b1 : 1'b0;
assign	prb  = (enable && rs==4'h1) ? 1'b1 : 1'b0;
assign	ddra = (enable && rs==4'h2) ? 1'b1 : 1'b0;
assign	ddrb = (enable && rs==4'h3) ? 1'b1 : 1'b0;
assign	talo = (enable && rs==4'h4) ? 1'b1 : 1'b0;
assign	tahi = (enable && rs==4'h5) ? 1'b1 : 1'b0;
assign	tblo = (enable && rs==4'h6) ? 1'b1 : 1'b0;
assign	tbhi = (enable && rs==4'h7) ? 1'b1 : 1'b0;
assign	tdlo = (enable && rs==4'h8) ? 1'b1 : 1'b0;
assign	tdme = (enable && rs==4'h9) ? 1'b1 : 1'b0;
assign	tdhi = (enable && rs==4'hA) ? 1'b1 : 1'b0;
assign	sdr  = (enable && rs==4'hC) ? 1'b1 : 1'b0;
assign	icrs = (enable && rs==4'hD) ? 1'b1 : 1'b0;
assign	cra  = (enable && rs==4'hE) ? 1'b1 : 1'b0;
assign	crb  = (enable && rs==4'hF) ? 1'b1 : 1'b0;

//----------------------------------------------------------------------------------
// data_out multiplexer
//----------------------------------------------------------------------------------
assign data_out = icr_out | tmra_out | tmrb_out | tmrd_out | sdr_out | pb_out | pa_out;

// fake serial port data register
always @(posedge clk)
	if (reset)
		sdr_latch[7:0] <= 8'h00;
	else if (wr & sdr)
		sdr_latch[7:0] <= data_in[7:0];
		
// sdr register read
assign sdr_out = (!wr && sdr) ? sdr_latch[7:0] : 8'h00;		

//----------------------------------------------------------------------------------
// porta
//----------------------------------------------------------------------------------
reg [5:3] porta_in2;
reg [7:0] regporta;
reg [7:0] ddrporta;

// synchronizing of input data
always @(posedge clk)
	porta_in2[5:3] <= porta_in[5:3];

// writing of output port
always @(posedge clk)
	if (reset)
		regporta[7:0] <= 8'd0;
	else if (wr && pra)
		regporta[7:0] <= data_in[7:0];

// writing of ddr register 
always @(posedge clk)
	if (reset)
		ddrporta[7:0] <= 8'd0;
	else if (wr && ddra)
 		ddrporta[7:0] <= data_in[7:0];

// reading of port/ddr register
always @(wr or pra or porta_in2 or porta_out or ddra or ddrporta)
begin
	if (!wr && pra)
		pa_out[7:0] = {porta_out[7:6],porta_in2[5:3],3'b111};
	else if (!wr && ddra)
		pa_out[7:0] = ddrporta[7:0];
	else
		pa_out[7:0] = 8'h00;
end
		
// assignment of output port while keeping in mind that the original 8520 uses pull-ups
assign porta_out[7:6] = (~ddrporta[7:6]) | regporta[7:6];	

//----------------------------------------------------------------------------------
// portb
//----------------------------------------------------------------------------------
reg [7:0] regportb;
reg [7:0] ddrportb;

// writing of output port
always @(posedge clk)
	if (reset)
		regportb[7:0] <= 8'd0;
	else if (wr && prb)
		regportb[7:0] <= data_in[7:0];

// writing of ddr register 
always @(posedge clk)
	if (reset)
		ddrportb[7:0] <= 8'd0;
	else if (wr && ddrb)
 		ddrportb[7:0] <= data_in[7:0];

// reading of port/ddr register
always @(wr or prb or portb_out or ddrb or ddrportb)
begin
	if (!wr && prb)
		pb_out[7:0] = portb_out[7:0];
	else if (!wr && ddrb)
		pb_out[7:0] = ddrportb[7:0];
	else
		pb_out[7:0] = 8'h00;
end
		
// assignment of output port while keeping in mind that the original 8520 uses pull-ups
assign portb_out[7:0] = (~ddrportb[7:0]) | regportb[7:0];	

// deleyed tick signal for edge detection
always @(posedge clk)
	tick_del <= tick;
	
//----------------------------------------------------------------------------------
// instantiate cia interrupt controller
//----------------------------------------------------------------------------------
ciaint cnt
(
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.icrs(icrs),
	.ta(ta),
	.tb(tb),
	.alrm(alrm),
	.flag(flag),
	.ser(1'b0),
	.data_in(data_in),
	.data_out(icr_out),
	.irq(irq)
);

//----------------------------------------------------------------------------------
// instantiate timer A
//----------------------------------------------------------------------------------
timera tmra
(
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.tlo(talo),
	.thi(tahi),
	.tcr(cra),
	.data_in(data_in),
	.data_out(tmra_out),
	.eclk(eclk),
	.tmra_ovf(tmra_ovf),
	.irq(ta) 
);

//----------------------------------------------------------------------------------
// instantiate timer B
//----------------------------------------------------------------------------------
timerb tmrb
(
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.tlo(tblo),
	.thi(tbhi),
	.tcr(crb),
	.data_in(data_in),
	.data_out(tmrb_out),
	.eclk(eclk),
	.tmra_ovf(tmra_ovf),
	.irq(tb)
);

//----------------------------------------------------------------------------------
// instantiate timer D
//----------------------------------------------------------------------------------
timerd tmrd 
(
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.tlo(tdlo),
	.tme(tdme),
	.thi(tdhi),
	.tcr(crb),
	.data_in(data_in),
	.data_out(tmrd_out),
	.count(tick & ~tick_del),
	.irq(alrm)
); 

endmodule

//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------
// interrupt control
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------

module ciaint
(
	input 	clk,	  			// clock
	input	wr,					// write enable
	input 	reset, 				// reset
	input 	icrs,				// intterupt control register select
	input	ta,					// ta (set TA bit in ICR register)
	input	tb,				    // tb (set TB bit in ICR register)
	input	alrm,	 			// alrm (set ALRM bit ICR register)
	input 	flag, 				// flag (set FLG bit in ICR register)
	input 	ser,				// ser (set SP bit in ICR register)
	input 	[7:0] data_in,		// bus data in
	output 	[7:0] data_out,		// bus data out
	output	irq					// intterupt out
);

reg  [4:0] icr = 5'd0;			// interrupt register
reg  [4:0] icrmask = 5'd0;		// interrupt mask register

// reading of interrupt data register 
assign data_out[7:0] = icrs && !wr ? {irq,2'b00,icr[4:0]} : 8'b0000_0000;

// writing of interrupt mask register
always @(posedge clk)
	if (reset)
		icrmask[4:0] <= 5'b0_0000;
	else if (icrs && wr)
	begin
		if (data_in[7])
			icrmask[4:0] <= icrmask[4:0] | data_in[4:0];
		else
			icrmask[4:0] <= icrmask[4:0] & (~data_in[4:0]);
	end

// register new interrupts and/or changes by user reads
always @(posedge clk)
	if (reset)// synchronous reset	
		icr[4:0] <= 5'b0_0000;
	else if (icrs && !wr)
	begin// clear latched intterupts on read
		icr[0] <= ta;			// timer a
		icr[1] <= tb;			// timer b
		icr[2] <= alrm;   		// timer tod
		icr[3] <= ser;	 		// external ser input
		icr[4] <= flag;			// external flag input
	end
	else
	begin// keep latched intterupts
		icr[0] <= icr[0] | ta;		// timer a
		icr[1] <= icr[1] | tb;		// timer b
		icr[2] <= icr[2] | alrm;	// timer tod
		icr[3] <= icr[3] | ser;		// external ser input
		icr[4] <= icr[4] | flag;	// external flag input
	end

// generate irq output (interrupt request)
assign irq 	= (icrmask[0] & icr[0]) 
			| (icrmask[1] & icr[1])
			| (icrmask[2] & icr[2])
			| (icrmask[3] & icr[3])
			| (icrmask[4] & icr[4]);

endmodule

//----------------------------------------------------------------------------------
// timer A/B
//----------------------------------------------------------------------------------

module timera
(
	input 	clk,	  				// clock
	input	wr,						// write enable
	input 	reset, 					// reset
	input 	tlo,					// timer low byte select
	input	thi,		 			// timer high byte select
	input	tcr,					// timer control register
	input 	[7:0] data_in,			// bus data in
	output 	[7:0] data_out,			// bus data out
	input	eclk,	  				// count enable
	output	tmra_ovf,				// timer A underflow
	output	spmode,					// serial port mode
	output	irq						// intterupt out
);

reg		[15:0] tmr;				// timer 
reg		[7:0] tmlh;				// timer latch high byte
reg		[7:0] tmll;				// timer latch low byte
reg		[6:0] tmcr;				// timer control register
reg		forceload;				// force load strobe
wire	oneshot;				// oneshot mode
wire	start;					// timer start (enable)
reg		thi_load;    			// load tmr after writing thi in one-shot mode
wire	reload;					// reload timer counter
wire	zero;					// timer counter is zero
wire	underflow;				// timer is going to underflow
wire	count;					// count enable signal
	
// count enable signal	
assign count = eclk;
	
// writing timer control register
always @(posedge clk)
	if (reset)	// synchronous reset
		tmcr[6:0] <= 7'd0;
	else if (tcr && wr)	// load control register, bit 4(strobe) is always 0
		tmcr[6:0] <= {data_in[6:5],1'b0,data_in[3:0]};
	else if (thi_load && oneshot)	// start timer if thi is written in one-shot mode
		tmcr[0] <= 1'd1;
	else if (underflow && oneshot) // stop timer in one-shot mode
		tmcr[0] <= 1'd0;

always @(posedge clk)
	forceload <= tcr & wr & data_in[4];	// force load strobe 
	
assign oneshot = tmcr[3];		// oneshot alias
assign start = tmcr[0];			// start alias
assign spmode = tmcr[6];		// serial port mode (0-input, 1-output)

// timer A latches for high and low byte
always @(posedge clk)
	if (reset)
		tmll[7:0] <= 8'b1111_1111;
	else if (tlo && wr)
		tmll[7:0] <= data_in[7:0];
		
always @(posedge clk)
	if (reset)
		tmlh[7:0] <= 8'b1111_1111;
	else if (thi && wr)
		tmlh[7:0] <= data_in[7:0];

// thi is written in one-shot mode so tmr must be reloaded
always @(posedge clk)
	thi_load <= thi & wr & (~start | oneshot);

// timer counter reload signal
assign reload = thi_load | forceload | underflow;

// timer counter	
always @(posedge clk)
	if (reset)
		tmr[15:0] <= 16'hFF_FF;
	else if (reload)
		tmr[15:0] <= {tmlh[7:0],tmll[7:0]};
	else if (start && count)
		tmr[15:0] <= tmr[15:0] - 16'd1;

// timer counter equals zero		
assign zero = ~|tmr;		

// timer counter is going to underflow
assign underflow = zero & start & count;

// Timer A underflow signal for Timer B
assign tmra_ovf = underflow;

// timer underflow interrupt request
assign irq = underflow;

// data output
assign data_out[7:0] = ({8{~wr&tlo}} & tmr[7:0]) 
					| ({8{~wr&thi}} & tmr[15:8])
					| ({8{~wr&tcr}} & {1'b0,tmcr[6:0]});		
				
endmodule

module timerb
(
	input 	clk,	  				// clock
	input	wr,						// write enable
	input 	reset, 					// reset
	input 	tlo,					// timer low byte select
	input	thi,		 			// timer high byte select
	input	tcr,					// timer control register
	input 	[7:0] data_in,			// bus data in
	output 	[7:0] data_out,			// bus data out
	input	eclk,	  				// count enable
	input	tmra_ovf,				// timer A underflow
	output	irq						// intterupt out
);

reg		[15:0] tmr;				// timer 
reg		[7:0] tmlh;				// timer latch high byte
reg		[7:0] tmll;				// timer latch low byte
reg		[6:0] tmcr;				// timer control register
reg		forceload;				// force load strobe
wire	oneshot;				// oneshot mode
wire	start;					// timer start (enable)
reg		thi_load; 				// load tmr after writing thi in one-shot mode
wire	reload;					// reload timer counter
wire	zero;					// timer counter is zero
wire	underflow;				// timer is going to underflow
wire	count;					// count enable signal

// Timer B count signal source
assign count = tmcr[6] ? tmra_ovf : eclk;

// writing timer control register
always @(posedge clk)
	if (reset)	// synchronous reset
		tmcr[6:0] <= 7'd0;
	else if (tcr && wr)	// load control register, bit 4(strobe) is always 0
		tmcr[6:0] <= {data_in[6:5],1'b0,data_in[3:0]};
	else if (thi_load && oneshot)	// start timer if thi is written in one-shot mode
		tmcr[0] <= 1'd1;
	else if (underflow && oneshot) // stop timer in one-shot mode
		tmcr[0] <= 1'd0;

always @(posedge clk)
	forceload <= tcr & wr & data_in[4];	// force load strobe 
	
assign oneshot = tmcr[3];					// oneshot alias
assign start = tmcr[0];					// start alias

// timer B latches for high and low byte
always @(posedge clk)
	if (reset)
		tmll[7:0] <= 8'b1111_1111;
	else if (tlo && wr)
		tmll[7:0] <= data_in[7:0];
		
always @(posedge clk)
	if (reset)
		tmlh[7:0] <= 8'b1111_1111;
	else if (thi && wr)
		tmlh[7:0] <= data_in[7:0];

// thi is written in one-shot mode so tmr must be reloaded
always @(posedge clk)
	thi_load <= thi & wr & (~start | oneshot);

// timer counter reload signal
assign reload = thi_load | forceload | underflow;

// timer counter	
always @(posedge clk)
	if (reset)
		tmr[15:0] <= 16'hFF_FF;
	else if (reload)
		tmr[15:0] <= {tmlh[7:0],tmll[7:0]};
	else if (start && count)
		tmr[15:0] <= tmr[15:0] - 16'd1;

// timer counter equals zero		
assign zero = ~|tmr;		

// timer counter is going to underflow
assign underflow = zero & start & count;

// timer underflow interrupt request
assign irq = underflow;

// data output
assign data_out[7:0] = ({8{~wr&tlo}} & tmr[7:0]) 
					| ({8{~wr&thi}} & tmr[15:8])
					| ({8{~wr&tcr}} & {1'b0,tmcr[6:0]});		
				
endmodule

//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------
// timer D
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------

module timerd
(
	input 	clk,	  				// clock
	input	wr,						// write enable
	input 	reset, 					// reset
	input 	tlo,					// timer low byte select
	input 	tme,					// timer mid byte select
	input	thi,		 			// timer high byte select
	input	tcr,					// timer control register
	input 	[7:0] data_in,			// bus data in
	output 	reg [7:0] data_out,		// bus data out
	input	count,	  				// count enable
	output	irq						// intterupt out
);

	reg		latch_ena;				// timer d output latch enable
	reg 	count_ena;				// timer d count enable
	reg		crb7;					// bit 7 of control register B
	reg		[23:0] tod;				// timer d
	reg		[23:0] alarm;			// alarm
	reg		[23:0] tod_latch;		// timer d latch
	reg		count_del;				// delayed count signal for interrupt requesting

// timer D output latch control
always @(posedge clk)
	if (reset)
		latch_ena <= 1'd1;
	else if (!wr)
	begin
		if (thi) // if MSB read, hold data for subsequent reads
			latch_ena <= 1'd0;
		else if (!thi) // if LSB read, update data every clock
			latch_ena <= 1'd1;
	end
always @(posedge clk)
	if (latch_ena)
		tod_latch[23:0] <= tod[23:0];

// timer D and crb7 read 
always @(wr or tlo or tme or thi or tcr or tod or tod_latch or crb7)
	if (!wr)
	begin
		if (thi) // high byte of timer D
			data_out[7:0] = tod_latch[23:16];
		else if (tme) // medium byte of timer D (latched)
			data_out[7:0] = tod_latch[15:8];
		else if (tlo) // low byte of timer D (latched)
			data_out[7:0] = tod_latch[7:0];
		else if (tcr) // bit 7 of crb
			data_out[7:0] = {crb7,7'b000_0000};
		else
			data_out[7:0] = 8'd0;
	end
	else
		data_out[7:0] = 8'd0;  

// timer D count enable control
always @(posedge clk)
	if (reset)
		count_ena <= 1'd1;
	else if (wr && !crb7) // crb7==0 enables writing to TOD counter
	begin
		if (thi || tme) // stop counting
			count_ena <= 1'd0;
		else if (tlo) // write to LSB starts counting again
			count_ena <= 1'd1;			
	end

// timer D counter
always @(posedge clk)
	if (reset) // synchronous reset
	begin
		tod[23:0] <= 24'd0;
	end
	else if (wr && !crb7) // crb7==0 enables writing to TOD counter
	begin
		if (tlo)
			tod[7:0] <= data_in[7:0];
		if (tme)
			tod[15:8] <= data_in[7:0];
		if (thi)
			tod[23:16] <= data_in[7:0];
	end
	else if (count_ena && count)
		tod[23:0] <= tod[23:0] + 24'd1;

// alarm write
always @(posedge clk)
	if (reset) // synchronous reset
	begin
		alarm[7:0] <= 8'b1111_1111;
		alarm[15:8] <= 8'b1111_1111;
		alarm[23:16] <= 8'b1111_1111;
	end
	else if (wr && crb7) // crb7==1 enables writing to ALARM
	begin
		if (tlo)
			alarm[7:0] <= data_in[7:0];
		if (tme)
			alarm[15:8] <= data_in[7:0];
		if (thi)
			alarm[23:16] <= data_in[7:0];
	end

// crb7 write
always @(posedge clk)
	if (reset)
		crb7 <= 1'd0;
	else if (wr && tcr)
		crb7 <= data_in[7];

// delayed count enable signal
always @(posedge clk)
	count_del <= count & count_ena;
	
// alarm interrupt request
assign irq = (tod[23:0]==alarm[23:0] && count_del) ? 1'b1 : 1'b0;

endmodule
