`timescale 1ns / 100ps

/*
 * Generic PS2 interface module
 * 
 * istrobe, oreq, oack and timeout are all 1-clk strobes,
 * ibyte must be latched on that strobe, obyte is latched
 * as oreq is detected, oreq is ignore while already
 * sending.
 * 
 * we ignore bad parity on input for now
 */

module ps2(input	sysclk,
	   input	reset,

//	   inout	ps2dat,
//	   inout	ps2clk,
	   input	ps2dat,
	   input	ps2clk,

	   output	istrobe,
	   output [7:0] ibyte,

	   input	oreq,
	   input [7:0]	obyte,
	   output	oack,

	   output	timeout,

	   output[1:0]	dbg_state
	   );

	reg [7:0] 	clkbuf;
	reg [7:0] 	datbuf;
	reg		clksync;
 	reg		clkprev;
	reg		datsync;	
	reg [10:0] 	shiftreg;
	reg [3:0] 	shiftcnt;
	wire		shiftend;
 	reg [1:0] 	state;
	wire 		datout;
	reg [23:0] 	timecnt; 	
	wire		clkdown;
	wire 		opar;

	/* State machine */
	localparam ps2_state_idle = 0;
	localparam ps2_state_ring = 1;
	localparam ps2_state_send = 2;
	localparam ps2_state_recv = 3;

	always@(posedge sysclk or posedge reset) begin
		if (reset)
		  state <= ps2_state_idle;
		else begin
			if (timeout && !oreq)
			  state <= ps2_state_idle;
			else
			  case(state)
				  ps2_state_idle: begin
					  if (oreq)
					    state <= ps2_state_ring;
					  else if (clkdown)
					    state <= ps2_state_recv;
				  end
				  ps2_state_ring: begin
					  if (timecnt[12])
					    state <= ps2_state_send;
				  end
				  ps2_state_send: begin
					  if (shiftend)
					    state <= ps2_state_idle;
				  end
				  ps2_state_recv: begin
					  if (oreq)
					    state <= ps2_state_ring;
					  else if (shiftend)
					    state <= ps2_state_idle;
				  end
			  endcase
		end
	end
	assign dbg_state = state;	

	/* Tristate control of clk & data */
	assign datout = state == ps2_state_ring || state == ps2_state_send;
//	assign ps2dat = (datout & ~shiftreg[0]) ? 1'b0 : 1'bz;
// assign ps2clk = (state == ps2_state_ring) ? 1'b0 : 1'bz;

	/* Bit counter */
	always@(posedge sysclk or posedge reset) begin
		if (reset)
		  shiftcnt <= 10;
		else begin
			if (state == ps2_state_idle)
			  shiftcnt <= 10;
			else if (state == ps2_state_ring)
			  shiftcnt <= 11;			
			else if (clkdown && state != ps2_state_ring)
			  shiftcnt <= shiftcnt - 1'b1;
		end
	end

	/* Shift register, ticks on falling edge of ps2 clock */
	always@(posedge sysclk or posedge reset) begin
		if (reset)
		  shiftreg <= 0;
		else begin
			if (oreq)
			  shiftreg <= { 1'b1, opar, obyte, 1'b0 };
			else if (clkdown && state != ps2_state_ring)
			  shiftreg <= { datsync, shiftreg[10:1] };
		end
	end


	/* Ack/strobe logic */
	assign shiftend = shiftcnt == 0;	
	assign oack = (state == ps2_state_send && shiftend);
	assign istrobe = (state == ps2_state_recv && shiftend);	
	assign ibyte = shiftreg[8:1];

	/* Filters/synchronizers on PS/2 clock */
	always@(posedge sysclk or posedge reset) begin
		if (reset) begin
			clkbuf <= 0;
			clksync <= 0;
			clkprev <= 0;
		end else begin
			clkprev <= clksync;			
			clkbuf <= { clkbuf[6:0], ps2clk };
			if (clkbuf[7:2] == 6'b000000)
			  clksync <= 0;
			if (clkbuf[7:2] == 6'b111111)
			  clksync <= 1;
		end
	end
	assign clkdown = clkprev & ~clksync;

	/* Filters/synchronizers on PS/2 data */
	always@(posedge sysclk or posedge reset) begin
		if (reset) begin
			datbuf <= 0;
			datsync <= 0;
		end else begin
			datbuf <= { datbuf[6:0], ps2dat };
			if (datbuf[7:2] == 6'b000000)
			  datsync <= 0;
			if (datbuf[7:2] == 6'b111111)
			  datsync <= 1;
		end
	end
		      
	/* Parity for output byte */
	assign opar = ~(obyte[0] ^ obyte[1] ^ obyte[2] ^ obyte[3] ^
			obyte[4] ^ obyte[5] ^ obyte[6] ^ obyte[7]);	

	/* Timeout logic */
	always@(posedge sysclk or posedge reset) begin
		if (reset)
		  timecnt <= 0;
		else begin
			if (clkdown | oreq)
			  timecnt <= 0;
			else
			  timecnt <= timecnt + 1'b1;
		end
	end
	assign timeout = (timecnt == 24'hff_ffff);	
endmodule
