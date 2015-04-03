// mfp.v
//
// Atari ST multi function peripheral (MFP) for the MiST board
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
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

wire serial_data_out_fifo_full;

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
	.PULSE_MODE (pulse_mode[1]),
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
	.PULSE_MODE (pulse_mode[0]),
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
reg [15:0] imr, ier;   // interrupt registers
reg [7:0] vr;

// generate irq signal if an irq is pending and no other irq of same or higher prio is in service
assign irq = ((ipr & imr) != 16'h0000) && (highest_irq_pending > irq_in_service);
   
// check number of current interrupt in service
wire [3:0] irq_in_service;
mfp_hbit16 irq_in_service_index (
	.value 	( isr					),
	.index	( irq_in_service	)
);

// check the number of the highest pending irq 
wire [3:0] highest_irq_pending;
wire [15:0]	highest_irq_pending_mask;
mfp_hbit16 irq_pending_index (
	.value 	( ipr & imr						),
	.index	( highest_irq_pending		),
	.mask		( highest_irq_pending_mask	)
);
	
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
		if(addr == 5'h04) dout = ier[7:0];
		if(addr == 5'h06) dout = ipr[7:0];
		if(addr == 5'h05) dout = ipr[15:8];
		if(addr == 5'h07) dout = isr[15:8];
		if(addr == 5'h08) dout = isr[7:0];
		if(addr == 5'h09) dout = imr[15:8];
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

// latch to keep irq vector stable during irq ack cycle
reg [7:0] irq_vec;

// IPR bits are always set on the rising edge of their input and are cleared asynchronously
wire [7:0] gpio_irq = ~aer ^ ((i & ~ti_irq_mask) | (ti_irq & ti_irq_mask));

// ------------------------ IPR register --------------------------
wire [15:0] ipr;
reg [15:0] ipr_reset;

// map the 16 interrupt sources onto the 16 interrupt register bits
wire [15:0]	ipr_set = {  
	gpio_irq[7:6], timera_done, serial_data_in_available, 
	1'b0 /* rcv err */, !serial_data_out_fifo_full, 1'b0 /* tx err */, timerb_done,
	gpio_irq[5:4], timerc_done, timerd_done, gpio_irq[3:0]
};

mfp_srff16 ipr_latch (
	.set    	( ipr_set       	),
	.mask   	( ier	            ),
	.reset	( ipr_reset			),
	.out		( ipr					)
);

// ------------------------ ISR register --------------------------
wire [15:0] isr;
reg [15:0] isr_reset;
reg [15:0] isr_set;

// move highest pending irq into isr when s bit set and iack raises
mfp_srff16 isr_latch (
	.set    	( isr_set			),
	.mask   	( 16'hffff			),
	.reset	( isr_reset			),
	.out		( isr					)
);

// this needs to happen at the same time the isr is set so it doesn't hurt
// if a new irq arrives in between these two events and a different irq is
// moved from ipr to isr than reported to the cpu
always @(posedge iack)
	irq_vec <= { vr[7:4], highest_irq_pending };

always @(negedge clk) begin
	ipr_reset <= 16'h0000; 
	isr_reset <= 16'h0000; 

	if(reset) begin
		ipr_reset <= 16'hffff;
		isr_reset <= 16'hffff;
		ier <= 16'h0000; 
		imr <= 16'h0000;
		isr_set <= 16'h0000;
	end else begin 
 
		// remove active bit from ipr and set it in isr
		if(iack) begin
			ipr_reset[highest_irq_pending] <= 1'b1;
			isr_set <= (vr[3] && iack)?highest_irq_pending_mask:16'h0000;
		end
			
		if(sel && ~ds && ~rw) begin
			// -------- GPIO ---------
			if(addr == 5'h00) gpip <= din;
			if(addr == 5'h01)	aer <= din;
			if(addr == 5'h02)	ddr <= din;

			// ------ IRQ handling -------
			if(addr == 5'h03) begin
				ier[15:8] <= din;
				ipr_reset[15:8] <= ipr_reset[15:8] | ~din;
			end
				
			if(addr == 5'h04) begin
				ier[7:0] <= din;
				ipr_reset[7:0] <= ipr_reset[7:0] | ~din;
			end
			
			if(addr == 5'h05)	ipr_reset[15:8] <= ipr_reset[15:8] | ~din;
			if(addr == 5'h06) ipr_reset[7:0]  <= ipr_reset[7:0]  | ~din;
			if(addr == 5'h07)	isr_reset[15:8] <= isr_reset[15:8] | ~din;  // zero bits are cleared
			if(addr == 5'h08)	isr_reset[7:0]  <= isr_reset[7:0]  | ~din;  // -"-
			if(addr == 5'h09)	imr[15:8] <= din;
			if(addr == 5'h0a)	imr[7:0]  <= din;
			if(addr == 5'h0b) vr <= din;

			// ------- uart ------------
			if(addr == 5'h15) uart_rx_ctrl <= din[1:0];
			if(addr == 5'h16) uart_tx_ctrl <= din[3:0];
			
			// write to addr == 5'h17 is handled by the output fifo
		end
	end
end

endmodule
