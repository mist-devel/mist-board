`timescale 1ns / 100ps

/*
 * PS2 mouse protocol
 * Bit       7    6    5    4    3    2    1    0  
 * Byte 0: YOVR XOVR YSGN XSGN   1   MBUT RBUT LBUT
 * Byte 1:                 XMOVE
 * Byte 2:                 YMOVE
 */

/*
 * PS2 Mouse to Mac interface module
 */
module ps2_mouse(input	sysclk,
		 input	reset,

		 input	ps2dat,
		 input	ps2clk,
		 
		 output	reg x1,
		 output reg y1,
		 output reg x2,
		 output reg y2,
		 output reg button
);
	wire 		istrobe;
	wire [7:0] 	ibyte;
	wire		timeout;
	wire		oack;
	reg [7:0]	obyte;
	reg		oreq;
	reg [2:0] 	state;
	reg [2:0] 	next;
	reg [7:0] 	nbyte;
	reg		nreq;
	reg [9:0] 	xacc;
	reg [9:0] 	yacc;
	reg		xsign;
	reg		ysign;
	reg [11:0] 	clkdiv;
	wire		tick;	
	wire[1:0]	dbg_lowstate;
	
	ps2 ps20(.sysclk(sysclk),
		 .reset(reset),
		 .ps2dat(ps2dat),
		 .ps2clk(ps2clk),
		 .istrobe(istrobe),
		 .ibyte(ibyte),
		 .oreq(oreq),
		 .obyte(obyte),
		 .oack(oack),
		 .timeout(timeout),
		 .dbg_state(dbg_lowstate));
	
	/* State machine:
	 *
	 *  - at state_init: wait for BAT reply
	 *     * 0xaa                   -> state_id
	 *     * 0xfa      -> send 0xff -> state_init
	 *     * bad reply -> send 0xff -> state_init
	 *     * timeout   -> send 0xff -> state_init
	 * 
	 *  - at state_id: wait for device_id
	 *     * 0x00      -> send 0xf4 -> state_setup
	 *     * bad reply -> send 0xff -> state_init
	 *     * timeout   -> send 0xff -> state_init
	 * 
	 *  - at state_setup: wait for enable data reporting ack
	 *     * 0xfa                   -> state_byte0
	 *     * bad reply -> send 0xff -> state_init
	 *     * timeout   -> send 0xff -> state_init
	 * 
	 *  - at state_byte0: wait for data byte 0
	 *     * data                   -> state_byte1
	 *     * data                   -> state_byte1
	 *     * timeout   -> send 0xff -> state_init
	 * 
	 *  - at state_byte1: wait for data byte 1
	 *     * data                   -> state_byte2
	 *     * timeout   -> send 0xff -> state_init
	 *
	 *  - at state_byte2: wait for data byte 2
	 *     * data                   -> state_byte0
	 *     * timeout   -> send 0xff -> state_init
	 */
	localparam ps2m_state_init	= 3'h0;
	localparam ps2m_state_id	= 3'h1;
	localparam ps2m_state_setup	= 3'h2;
	localparam ps2m_state_byte0	= 3'h3;
	localparam ps2m_state_byte1	= 3'h4;
	localparam ps2m_state_byte2	= 3'h5;

	/* Unlike my other modules, here I'll play with a big fat
	 * combo logic. The outputs are:
	 *  - oreq   : triggers sending of a byte. Set based on either
	 *             timeout or istrobe, and as such only set for a
	 *             clock.
	 *  - next   : next state
	 *  - obyte  : next byte to send
	 */
	always@(timeout or state or istrobe or ibyte) begin
		nreq = 0;
		next = state;
		nbyte = 8'hff;
//		if (timeout) begin
//			next = ps2m_state_byte0;  // ps2m_state_init
//			nreq = 1;			
//		end else 
     if (istrobe)
		  case(state)
			  ps2m_state_init: begin
				  if (ibyte == 8'haa)
				    next = ps2m_state_id;
				  else if (ibyte != 8'hfa)
				    nreq = 1;
			  end
			  ps2m_state_id: begin
				  nreq = 1;
				  if (ibyte == 8'h00) begin
					  nbyte = 8'hf4;
					  next = ps2m_state_setup;
				  end else
				    next = ps2m_state_init;
			  end
			  ps2m_state_setup: begin
				  if (ibyte == 8'hfa)
				    next = ps2m_state_byte0;
				  else begin
					  nreq = 1;
					  next = ps2m_state_init;
				  end
			  end
			  ps2m_state_byte0:
				  if(ibyte[3])      // bit 3 must be 1
					next = ps2m_state_byte1;
			  
			  ps2m_state_byte1: next = ps2m_state_byte2;
			  ps2m_state_byte2: next = ps2m_state_byte0;
			  default: // shouldn't ever get into these states
				  next = ps2m_state_init;
		  endcase
	end

	/* State related latches. We latch oreq and obyte, we don't
	 * necessarily have to but that avoids back to back
	 * receive/send at the low level which can upset things
	 */
	always@(posedge sysclk or posedge reset)
		if (reset)
		  state <= ps2m_state_byte0; // ps2m_state_init
		else
		  state <= next;
	always@(posedge sysclk or posedge reset)
		if (reset)
		  oreq <= 0;
		else
		  oreq <= nreq;
	always@(posedge sysclk or posedge reset)
		if (reset)
		  obyte <= 0;
		else
		  obyte <= nbyte;

	/* Capture button state */
	always@(posedge sysclk or posedge reset)
		if (reset)
		  button <= 1;
		else if (istrobe && state == ps2m_state_byte0)
			if(ibyte[3])
				button <= ~ibyte[0];		

	/* Clock divider to flush accumulators */
	always@(posedge sysclk or posedge reset)
		if (reset)
		  clkdiv <= 0;
		else
		  clkdiv <= clkdiv + 1'b1;
	assign tick = clkdiv == 0;

	/* Toggle output lines base on accumulator */
	always@(posedge sysclk or posedge reset) begin
		if (reset) begin
			x1 <= 0;
			x2 <= 0;
		end else if (tick && xacc != 0) begin
			x1 <= ~x1;
			x2 <= ~x1 ^ ~xacc[9];
		end
	end
	always@(posedge sysclk or posedge reset) begin
		if (reset) begin
			y1 <= 0;
			y2 <= 0;
		end else if (tick && yacc != 0) begin
			y1 <= ~y1;
			y2 <= ~y1 ^ ~yacc[9];
		end
	end

	/* Capture sign bits */
	always@(posedge sysclk or posedge reset) begin
		if (reset) begin
			xsign <= 0;
			ysign <= 0;			
		end else if (istrobe && state == ps2m_state_byte0) begin
			if(ibyte[3]) begin
				xsign <= ibyte[4];
				ysign <= ibyte[5];
			end
		end
	end

	/* Movement accumulators. Needs tuning ! */
	always@(posedge sysclk or posedge reset) begin
		if (reset)
		  xacc <= 0;
		else begin
			/* Add movement, convert to a 10-bit number if not over */
			if (istrobe && state == ps2m_state_byte1 && xacc[8] == xacc[9])
				xacc <= xacc + { xsign, xsign, ibyte };
			else
			  /* Decrement */
			  if (tick && xacc != 0)
			    xacc <= xacc + { {9{~xacc[9]}}, 1'b1 };
		end
	end
	
	always@(posedge sysclk or posedge reset) begin
		if (reset)
		  yacc <= 0;
		else begin
			/* Add movement, convert to a 10-bit number if not over*/
			if (istrobe && state == ps2m_state_byte2 && yacc[8] == yacc[9])
				yacc <= yacc + { ysign, ysign, ibyte };
			else
			  /* Decrement */
			  if (tick && yacc != 0)
			    yacc <= yacc + { {9{~yacc[9]}}, 1'b1 };
		end
	end
endmodule
