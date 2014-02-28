//

module mfp (
	// cpu register interface
	input 		 clk,
	input 		 reset,
	input [7:0]  din,
	input 		 sel,
	input [4:0]  addr,
	input 		 ds,
	input 		 rw,
	output reg [7:0] dout,
	output 		 irq,
	input 		 iack,

	// serial rs232 connection to io controller
	output 		 serial_data_out_available,
	input  		 serial_strobe_out,
	output [7:0] serial_data_out,

	// serial rs223 connection from io controller
   input 		serial_strobe_in,
   input [7:0] serial_data_in,
	output      serial_data_in_full,

	// inputs
	input 		 clk_ext,   // external 2.457MHz
	input [1:0]	 t_i,  // timer input
 	input [7:0]  i     // input port
);

// --- mfp output fifo ---
// filled by the CPU when writing to the mfp uart data register
// emptied by the io controller when reading via SPI
io_fifo mfp_out_fifo (
	.reset 				(reset),		

	.in_clk   			(!clk),          // latch incoming data on negedge
	.in 					(din),
	.in_strobe 			(1'b0),
	.in_enable			(sel && ~ds && ~rw && (addr == 5'h17)),

	.out_clk          (clk),
	.out 					(serial_data_out),
	.out_strobe 		(serial_strobe_out),
	.out_enable 		(1'b0),

	.full             (serial_data_out_fifo_full),
	.data_available 	(serial_data_out_available)
);

// --- mfp input fifo ---
// filled by the io controller when writing via SPI
// emptied by CPU when reading the mfp uart data register
io_fifo mfp_in_fifo (
	.reset 				(reset),		

	.in_clk   			(!clk),          // latch incoming data on negedge
	.in 					(serial_data_in),
	.in_strobe 			(serial_strobe_in),
	.in_enable			(1'b0),

	.out_clk          (!clk),
	.out 					(serial_data_in_cpu),
	.out_strobe 		(1'b0),
	.out_enable 		(serial_cpu_data_read && serial_data_in_available),

	.full					(serial_data_in_full),
	.data_available 	(serial_data_in_available)
);

// ---------------- mfp uart data to/from io controller ------------
reg serial_cpu_data_read;
wire serial_data_in_available;
wire [7:0] serial_data_in_cpu;

always @(negedge clk) begin
	// read on uart data register
	serial_cpu_data_read <= 1'b0;
	if(sel && ~ds && rw && (addr == 5'h17))
		serial_cpu_data_read <= 1'b1;
end 

wire write = sel && ~ds && ~rw;

// timer a/b is in pulse mode
wire [1:0] pulse_mode;
   
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
	.PULSE_MODE    (pulse_mode[1]),
   .T_I			(t_i[0] ^ aer[4]),
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
	.PULSE_MODE    (pulse_mode[0]),
   .T_I			(t_i[1] ^ aer[3]),
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

// generate irq signal if an irq is pending and no other irq of same or higher prio is in service
assign irq = ((ipr & imr) != 16'h0000) && (highest_irq_pending >= irq_in_service);
   
// check number of current interrupt in service
wire [3:0] irq_in_service =
	(isr[15]    ==  1'b1)?4'd15:
	(isr[15:14] ==  2'b1)?4'd14:
	(isr[15:13] ==  3'b1)?4'd13:
	(isr[15:12] ==  4'b1)?4'd12:
	(isr[15:11] ==  5'b1)?4'd11:
	(isr[15:10] ==  6'b1)?4'd10:
	(isr[15:9]  ==  7'b1)?4'd9:
	(isr[15:8]  ==  8'b1)?4'd8:
	(isr[15:7]  ==  9'b1)?4'd7:
	(isr[15:6]  == 10'b1)?4'd6:
	(isr[15:5]  == 11'b1)?4'd5:
	(isr[15:4]  == 12'b1)?4'd4:
	(isr[15:3]  == 13'b1)?4'd3:
	(isr[15:2]  == 14'b1)?4'd2:
	(isr[15:1]  == 15'b1)?4'd1:
	(isr[15:0]  == 16'b1)?4'd0:
		4'd0;

wire [15:0] irq_pending_map = ipr & imr;

// check the number of the highest pending irq 
wire [3:0] highest_irq_pending =
	(irq_pending_map[15]    ==  1'b1)?4'd15:
	(irq_pending_map[15:14] ==  2'b1)?4'd14:
	(irq_pending_map[15:13] ==  3'b1)?4'd13:
	(irq_pending_map[15:12] ==  4'b1)?4'd12:
	(irq_pending_map[15:11] ==  5'b1)?4'd11:
	(irq_pending_map[15:10] ==  6'b1)?4'd10:
	(irq_pending_map[15:9]  ==  7'b1)?4'd9:
	(irq_pending_map[15:8]  ==  8'b1)?4'd8:
	(irq_pending_map[15:7]  ==  9'b1)?4'd7:
	(irq_pending_map[15:6]  == 10'b1)?4'd6:
	(irq_pending_map[15:5]  == 11'b1)?4'd5:
	(irq_pending_map[15:4]  == 12'b1)?4'd4:
	(irq_pending_map[15:3]  == 13'b1)?4'd3:
	(irq_pending_map[15:2]  == 14'b1)?4'd2:
	(irq_pending_map[15:1]  == 15'b1)?4'd1:
	(irq_pending_map[15:0]  == 16'b1)?4'd0:
		4'd0;
	
// gpip as output to the cpu (ddr bit == 1 -> gpip pin is output)
wire [7:0] gpip_cpu_out = (i & ~ddr) | (gpip & ddr);

// cpu controllable uart control bits
reg [1:0] uart_rx_ctrl;
reg [3:0] uart_tx_ctrl;

// cpu read interface
always @(iack, sel, ds, rw, addr, gpip_cpu_out, aer, ddr, ier, ipr, isr, imr, 
	vr, serial_data_out_fifo_full, timera_dat_o, timerb_dat_o,
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
		if(addr == 5'h15) dout = {  serial_data_in_available, 5'b00000 , uart_rx_ctrl}; 
		if(addr == 5'h16) dout = { !serial_data_out_fifo_full, 3'b000 , uart_tx_ctrl}; 
		if(addr == 5'h17) dout = serial_data_in_cpu;
		
	end else if(iack) begin
		dout = irq_vec;
	end
end

// mask of input irqs which are overwritten by timer a/b inputs
wire [7:0] ti_irq_mask = { 3'b000, pulse_mode, 3'b000};
wire [7:0] ti_irq      = { 3'b000, t_i[0], t_i[1], 3'b000};

// delay inputs to detect changes
reg [7:0] iD, iD2;
reg iackD;

// latch to keep irq vector stable during irq ack cycle
reg [7:0] irq_vec;

reg [1:0] usart_irqD;

always @(negedge clk) begin
   iackD <= iack;

	// update the irq vector periodically unless we are in the
	// middle of an interrupt acknowledge phase
	if(!iack)
		irq_vec <= { vr[7:4], highest_irq_pending };
	
	// delay inputs for irq generation, apply aer (irq edge)
	iD <= aer ^ ((i & ~ti_irq_mask) | (ti_irq & ti_irq_mask));
	iD2 <= iD;

	// delay usart states to react on changes
	usart_irqD[0] <= !serial_data_out_fifo_full;
	usart_irqD[1] <= serial_data_in_available;
	
	if(reset) begin
		ipr <= 16'h0000; ier <= 16'h0000; 
		imr <= 16'h0000; isr <= 16'h0000;
	end else begin 
 
		// ack pending irqs and set isr if enabled
		if(iack && !iackD) begin
			// remove active bit from ipr
			ipr[highest_irq_pending] <= 1'b0;
		
			// move bit into isr if s-bit in vr is set
			if(vr[3])
				isr[highest_irq_pending] <= 1'b1;		
		end

		// map timer interrupts
		if(timera_done && ier[13])	     ipr[13] <= 1'b1;   // timer_a
		if(timerb_done && ier[ 8])	     ipr[ 8] <= 1'b1;	// timer_b
		if(timerc_done && ier[ 5])	     ipr[ 5] <= 1'b1;	// timer_c
		if(timerd_done && ier[ 4])	     ipr[ 4] <= 1'b1;	// timer_d

		// input port irqs are edge sensitive
		if(!iD[3] && iD2[3] && ier[ 3]) ipr[ 3] <= 1'b1;   // blitter
      if(!iD[4] && iD2[4] && ier[ 6]) ipr[ 6] <= 1'b1;   // acia
		if(!iD[5] && iD2[5] && ier[ 7]) ipr[ 7] <= 1'b1;   // dma
		if(!iD[7] && iD2[7] && ier[15]) ipr[15] <= 1'b1;   // mono detect

		// output fifo just became "not full" or input fifo became "not empty"
		if(!usart_irqD[0] && !serial_data_out_fifo_full && ier[10]) ipr[10] <= 1'b1;
		if(!usart_irqD[1] &&  serial_data_in_available  && ier[12]) ipr[12] <= 1'b1;

		if(sel && ~ds && ~rw) begin
			if(addr == 5'h00) gpip <= din;
			if(addr == 5'h01)	aer <= din;
			if(addr == 5'h02)	ddr <= din;

			if(addr == 5'h03) begin
				ier[15:8] <= din;
				ipr[15:8] <= ipr[15:8] & din;  // clear pending interrupts
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

			// ------- uart ------------
			if(addr == 5'h15) uart_rx_ctrl <= din[1:0];
			if(addr == 5'h16) uart_tx_ctrl <= din[3:0];
			
			// write to addr == 5'h17 is handled by the output fifo
		end
	end
end

endmodule