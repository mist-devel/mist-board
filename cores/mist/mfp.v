//

// define this for cubase acia irq hack
// `define CUBHACK   

module mfp (
	// cpu register interface
	input 		 clk,
	input 		 reset,
	input [7:0] 	 din,
	input 		 sel,
	input [4:0] 	 addr,
	input 		 ds,
	input 		 rw,
	output reg [7:0] dout,
	output 		 irq,
	input 		 iack,

	// serial rs232 connection to io controller
	output 		 serial_data_out_available,
	input  		 serial_strobe_out,
	output [7:0] serial_data_out,

	input 		 clk_ext,   // external 2.457MHz
	input 		 de,
	input 		 dma_irq, 
	input 		 acia_irq,
	input 		 mono_detect
);

localparam FIFO_ADDR_BITS = 4;
localparam FIFO_DEPTH = (1 << FIFO_ADDR_BITS);

// 
reg [7:0] fifoOut [FIFO_DEPTH-1:0];
reg [FIFO_ADDR_BITS-1:0] writePout, readPout;

assign serial_data_out_available = (readPout != writePout);
assign serial_data_out = fifoOut[readPout];

// signal "fifo is full" via uart config bit
wire serial_data_out_fifo_full = (readPout === (writePout + 4'd1));

// ---------------- send mfp uart data to io controller ------------
reg serial_strobe_outD, serial_strobe_outD2;
always @(posedge clk) begin
	serial_strobe_outD <= serial_strobe_out;
	serial_strobe_outD2 <= serial_strobe_outD;

	if(reset)
		readPout <= 4'd0;
	else
		if(serial_strobe_outD && !serial_strobe_outD2)
			readPout <= readPout + 4'd1;
end

// timer to let bytes arrive at a reasonable speed
reg [13:0] readTimer;

wire write = sel && ~ds && ~rw;

wire timera_done;
wire [7:0] timera_dat_o;
wire [4:0] timera_ctrl_o;

mfp_timer timer_a (
	.CLK 			(clk),
	.XCLK_I		(clk_ext),
	.RST 			(reset),
   .CTRL_I		(din[4:0]),
   .CTRL_O		(timera_ctrl_o),
   .CTRL_WE		((addr == 5'h0c) && write),
   .DAT_I		(din),
   .DAT_O		(timera_dat_o),
   .DAT_WE		((addr == 5'h0f) && write),
   .T_O_PULSE	(timera_done)
);


wire timerb_done;
wire [7:0] timerb_dat_o;
wire [4:0] timerb_ctrl_o;

mfp_timer timer_b (
	.CLK 			(clk),
	.XCLK_I		(clk_ext),
	.RST 			(reset),
   .CTRL_I		(din[4:0]),
   .CTRL_O		(timerb_ctrl_o),
   .CTRL_WE		((addr == 5'h0d) && write),
   .DAT_I		(din),
   .DAT_O		(timerb_dat_o),
   .DAT_WE		((addr == 5'h10) && write),
   .T_I			(de),
   .T_O_PULSE	(timerb_done)
);

wire timerc_done;
wire [7:0] timerc_dat_o;
wire [4:0] timerc_ctrl_o;

mfp_timer timer_c (
	.CLK 			(clk),
	.XCLK_I		(clk_ext),
	.RST 			(reset),
   .CTRL_I		({2'b00, din[6:4]}),
   .CTRL_O		(timerc_ctrl_o),
   .CTRL_WE		((addr == 5'h0e) && write),
   .DAT_I		(din),
   .DAT_O		(timerc_dat_o),
   .DAT_WE		((addr == 5'h11) && write),
   .T_O_PULSE	(timerc_done)
);

wire timerd_done;
wire [7:0] timerd_dat_o;
wire [4:0] timerd_ctrl_o;

mfp_timer timer_d (
	.CLK 			(clk),
	.XCLK_I		(clk_ext),
	.RST 			(reset),
   .CTRL_I		({2'b00, din[2:0]}),
   .CTRL_O		(timerd_ctrl_o),
   .CTRL_WE		((addr == 5'h0e) && write),
   .DAT_I		(din),
   .DAT_O		(timerd_dat_o),
   .DAT_WE		((addr == 5'h12) && write),
   .T_O_PULSE	(timerd_done)
);

reg [7:0] aer, ddr, gpip;

// the mfp can handle 16 irqs, 8 internal and 8 external
reg [15:0] ipr, ier, imr, isr;   // interrupt registers
reg [7:0] vr;


// any pending and not masked interrupt causes the irq line to go high
// if highest_irq_pending != higest_irq_active then there's a high prio
// irq in service and no irq is generated until this one is finished
assign irq = ((ipr & imr) != 16'h0000) && (highest_irq_active == highest_irq_pending);

// handle pending and in service irqs
wire [15:0] irq_active_map;
assign irq_active_map = (ipr | isr) & imr;

// (i am pretty sure this can be done much more elegant ...)
// check the number of the highest active irq
wire [3:0] highest_irq_active;
assign highest_irq_active=
	( irq_active_map[15]    == 1'b1)?4'd15:
	((irq_active_map[15:14] == 2'b01)?4'd14:
	((irq_active_map[15:13] == 3'b001)?4'd13:
	((irq_active_map[15:12] == 4'b0001)?4'd12:
	((irq_active_map[15:11] == 5'b00001)?4'd11:
	((irq_active_map[15:10] == 6'b000001)?4'd10:
	((irq_active_map[15:9]  == 7'b0000001)?4'd9:
	((irq_active_map[15:8]  == 8'b00000001)?4'd8:
	((irq_active_map[15:7]  == 9'b000000001)?4'd7:
	((irq_active_map[15:6]  == 10'b000000001)?4'd6:
	((irq_active_map[15:5]  == 11'b0000000001)?4'd5:
	((irq_active_map[15:4]  == 12'b00000000001)?4'd4:
	((irq_active_map[15:3]  == 13'b000000000001)?4'd3:
	((irq_active_map[15:2]  == 14'b0000000000001)?4'd2:
	((irq_active_map[15:1]  == 15'b00000000000001)?4'd1:
	((irq_active_map[15:0]  == 16'b000000000000001)?4'd0:
			4'd0)))))))))))))));

wire [15:0] irq_pending_map;
assign irq_pending_map = ipr & imr;

// check the number of the highest pending irq 
wire [3:0] highest_irq_pending;
assign highest_irq_pending =
	( irq_pending_map[15]    == 1'b1)?4'd15:
	((irq_pending_map[15:14] == 2'b01)?4'd14:
	((irq_pending_map[15:13] == 3'b001)?4'd13:
	((irq_pending_map[15:12] == 4'b0001)?4'd12:
	((irq_pending_map[15:11] == 5'b00001)?4'd11:
	((irq_pending_map[15:10] == 6'b000001)?4'd10:
	((irq_pending_map[15:9]  == 7'b0000001)?4'd9:
	((irq_pending_map[15:8]  == 8'b00000001)?4'd8:
	((irq_pending_map[15:7]  == 9'b000000001)?4'd7:
	((irq_pending_map[15:6]  == 10'b000000001)?4'd6:
	((irq_pending_map[15:5]  == 11'b0000000001)?4'd5:
	((irq_pending_map[15:4]  == 12'b00000000001)?4'd4:
	((irq_pending_map[15:3]  == 13'b000000000001)?4'd3:
	((irq_pending_map[15:2]  == 14'b0000000000001)?4'd2:
	((irq_pending_map[15:1]  == 15'b00000000000001)?4'd1:
	((irq_pending_map[15:0]  == 16'b000000000000001)?4'd0:
			4'd0)))))))))))))));
	
// wire inputs to external gpip in
// acia/dma irq is active low in st, but active high in this config, we thus invert
// it to make sure tos sees what it expects to see when it looks at the registers
wire [7:0] gpip_in;
assign gpip_in = { mono_detect, 1'b0, !dma_irq, !acia_irq, 4'b0000 };

// gpip as output to the cpu
wire [7:0] gpip_cpu_out;
assign gpip_cpu_out = (gpip_in & ~ddr) | (gpip & ddr);
	
// cpu read interface
always @(iack, sel, ds, rw, addr, gpip_cpu_out, aer, ddr, ier, ipr, isr, imr, 
	vr, irq_vec, serial_data_out_fifo_full, timera_dat_o, timerb_dat_o,
	timerc_dat_o, timerd_dat_o, timera_ctrl_o, timerb_ctrl_o, timerc_ctrl_o, 
	timerd_ctrl_o) begin

	dout = 8'd0;
	if(sel && ~ds && rw) begin
		if(addr == 5'h00) dout = gpip_cpu_out;
		if(addr == 5'h01) dout = aer;
		if(addr == 5'h02) dout = ddr;
	
		if(addr == 5'h03) dout = ier[15:8];
		if(addr == 5'h05) dout = ipr[15:8];
		if(addr == 5'h07) dout = isr[15:8];
		if(addr == 5'h09) dout = imr[15:8];
		if(addr == 5'h04) dout = ier[7:0];
		if(addr == 5'h06) dout = ipr[7:0];
		if(addr == 5'h08) dout = isr[7:0];
		if(addr == 5'h0a) dout = imr[7:0];
		if(addr == 5'h0b) dout = vr;
	
		// timers
		if(addr == 5'h0c) dout = { 3'b000, timera_ctrl_o};
		if(addr == 5'h0d) dout = { 3'b000, timerb_ctrl_o};
		if(addr == 5'h0e) dout = { timerc_ctrl_o[3:0], timerd_ctrl_o[3:0]};
		if(addr == 5'h0f) dout = timera_dat_o;
		if(addr == 5'h10) dout = timerb_dat_o;
		if(addr == 5'h11) dout = timerc_dat_o;
		if(addr == 5'h12) dout = timerd_dat_o;
		
		// uart: report "tx buffer empty" if fifo is not full
		if(addr == 5'h16) dout = serial_data_out_fifo_full?8'h00:8'h80;
		
	end else if(iack) begin
		dout = irq_vec;
	end
end

`ifndef CUBHACK  
// delay de and timer to detect changes
reg acia_irqD, acia_irqD2, dma_irqD, dma_irqD2;
`endif

reg [7:0] irq_vec;

always @(posedge clk) begin
`ifndef CUBHACK  
   dma_irqD <=  dma_irq;
   acia_irqD <=  acia_irq;
`endif

   iackD <= iack;

   // the polarity of the irq is negated over a real st.   
//   if(aer[7]) dma_irqD <=  dma_irq;
//   else       dma_irqD <= !dma_irq;

//   if(aer[6]) acia_irqD <=  acia_irq;
//   else       acia_irqD <= !acia_irq;
   
	// the pending irq changes in the middle of an iack
	// phase, so we latch the current vector to keep is stable
	// during the entire cpu read
	irq_vec <= { vr[7:4], highest_irq_pending };
end
	
reg iackD;
always @(negedge clk) begin
	dma_irqD2 <= dma_irqD; 		
 	acia_irqD2 <= acia_irqD; 		
 	
	if(reset) begin
		ipr <= 16'h0000; ier <= 16'h0000; 
		imr <= 16'h0000; isr <= 16'h0000;
		writePout <= 0;
	end else begin

		// ack pending irqs and set isr if enabled
		if(iackD) begin
			// remove active bit from ipr
			ipr[highest_irq_pending] <= 1'b0;
		
			// move bit into isr if s-bit in vr is set
			if(vr[3])
				isr[highest_irq_pending] <= 1'b1;		
		end

		// map timer interrupts
		if(timera_done && ier[13])	ipr[13] <= 1'b1;  // timer_a
		if(timerb_done && ier[ 8])	ipr[ 8] <= 1'b1;	// timer_b
		if(timerc_done && ier[ 5])	ipr[ 5] <= 1'b1;	// timer_c
		if(timerd_done && ier[ 4])	ipr[ 4] <= 1'b1;	// timer_d

`ifndef CUBHACK  
		// in the real atari st the irqs are edge sensitive. however, this makes problems
      // with the acias in cubase as a work around ... 
      if(acia_irqD && !acia_irqD2) begin
			if(ier[6]) ipr[6] <= 1'b1;
		end
           
		// ... and dma
		if(dma_irqD && !dma_irqD2) begin
			if(ier[7]) ipr[7] <= 1'b1;
		end
`else
		// ... they can be implemented level sensitive. However, this breaks some games
		// like eg. "no second place" and even the rainbow logo in the tos 1.04 desktop
		
      // irq by acia ...
		if(acia_irq && ier[6])
			ipr[6] <= 1'b1;

      // ... and dma
		if(dma_irq && ier[7])
			ipr[7] <= 1'b1;
`endif
		
		if(sel && ~ds && ~rw) begin
			if(addr == 5'h00) gpip <= din;
			if(addr == 5'h01)	aer <= din;
			if(addr == 5'h02)	ddr <= din;

			if(addr == 5'h03) begin
				ier[15:8] <= din;
				ipr[15:8]<= ipr[15:8] & din;  // clear pending interrupts
			end
				
			if(addr == 5'h05)	ipr[15:8] <= ipr[15:8] & din;
			if(addr == 5'h07)	isr[15:8] <= isr[15:8] & din;  // zero bits are cleared
			if(addr == 5'h09)	imr[15:8] <= din;

			if(addr == 5'h04) begin
				ier[7:0] <= din;
				ipr[7:0] <= ipr[7:0] & din;  // clear pending interrupts
			end

			if(addr == 5'h06) ipr[7:0] <= ipr[7:0] & din;
			if(addr == 5'h08)	isr[7:0] <= isr[7:0] & din;  // zero bits are cleared
			if(addr == 5'h0a)	imr[7:0] <= din;
			if(addr == 5'h0b) vr <= din;
			
			if(addr == 5'h17) begin
				fifoOut[writePout] <= din;
				writePout <= writePout + 4'd1;
			end
		end
	end
end

endmodule