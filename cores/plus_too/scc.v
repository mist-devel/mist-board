`timescale 1ns / 100ps

/*
 * Zilog 8530 SCC module for minimigmac.
 *
 * Located on high data bus, but writes are done at odd addresses as
 * LDS is used as WR signals or something like that on a Mac Plus.
 * 
 * We don't care here and just ignore which side was used.
 * 
 * NOTE: We don't implement the 85C30 or ESCC additions such as WR7'
 * for now, it's all very simplified
 */

module scc(input	sysclk,
	   input	reset_hw,

	   /* Bus interface. 2-bit address, to be wired
	    * appropriately upstream (to A1..A2).
	    */
	   input	cs,
	   input	we,
	   input [1:0]	rs, /* [1] = data(1)/ctl [0] = a_side(1)/b_side */
	   input [7:0]	wdata,
	   output [7:0]	rdata,
	   output	_irq,

	   /* A single serial port on Minimig */
	   input	rxd,
	   output	txd,
	   input	cts, /* normally wired to device DTR output
			      * on Mac cables. That same line is also
			      * connected to the TRxC input of the SCC
			      * to do fast clocking but we don't do that
			      * here
			      */
	   output	rts, /* on a real mac this activates line
			      * drivers when low */

	   /* DCD for both ports are hijacked by mouse interface */
	   input	dcd_a, /* We don't synchronize those inputs */
	   input	dcd_b,

	   /* Write request */
	   output	wreq
	   );

	/* Register access is semi-insane */
	reg [3:0]	rindex;
	reg [3:0]	rindex_latch;
	wire 		wreg_a;
	wire 		wreg_b;
	wire 		wdata_a;
	wire 		wdata_b;
	wire 		rdata_a;
	wire 		rdata_b;

	/* Resets via WR9, one clk pulses */
	wire		reset_a;
	wire		reset_b;
	wire		reset;

	/* Data registers */
	reg [7:0] 	data_a = 0;
	reg [7:0] 	data_b = 0;

	/* Read registers */
	wire [7:0] 	rr0_a;
	wire [7:0] 	rr0_b;
	wire [7:0] 	rr1_a;
	wire [7:0] 	rr1_b;
	wire [7:0] 	rr2_b;
	wire [7:0] 	rr3_a;
	wire [7:0] 	rr10_a;
	wire [7:0] 	rr10_b;
	wire [7:0] 	rr15_a;
	wire [7:0] 	rr15_b;

	/* Write registers. Only some are implemented,
	 * some result in actions on write and don't
	 * store anything
	 */
	reg [7:0] 	wr1_a;
	reg [7:0] 	wr1_b;
	reg [7:0] 	wr2;
	reg [7:0] 	wr3_a;
	reg [7:0] 	wr3_b;
	reg [7:0] 	wr4_a;
	reg [7:0] 	wr4_b;
	reg [7:0] 	wr5_a;
	reg [7:0] 	wr5_b;
	reg [7:0] 	wr6_a;
	reg [7:0] 	wr6_b;
	reg [7:0] 	wr7_a;
	reg [7:0] 	wr7_b;
	reg [7:0] 	wr8_a;
	reg [7:0] 	wr8_b;
	reg [5:0] 	wr9;
	reg [7:0] 	wr10_a;
	reg [7:0] 	wr10_b;
	reg [7:0] 	wr11_a;
	reg [7:0] 	wr11_b;
	reg [7:0] 	wr12_a;
	reg [7:0] 	wr12_b;
	reg [7:0] 	wr13_a;
	reg [7:0] 	wr13_b;
	reg [7:0] 	wr14_a;
	reg [7:0] 	wr14_b;
	reg [7:0] 	wr15_a;
	reg [7:0] 	wr15_b;

	/* Status latches */
	reg		latch_open_a;
	reg		latch_open_b;
	reg		dcd_latch_a;
	reg		dcd_latch_b;
	wire		dcd_ip_a;
	wire		dcd_ip_b;
	wire		do_latch_a;
	wire		do_latch_b;
	wire		do_extreset_a;
	wire		do_extreset_b;	

	/* IRQ stuff */
	wire		rx_irq_pend_a;
	wire		rx_irq_pend_b;
	wire		tx_irq_pend_a;
	wire		tx_irq_pend_b;
	wire		ex_irq_pend_a;
	wire		ex_irq_pend_b;
	reg		ex_irq_ip_a;
	reg		ex_irq_ip_b;
	wire [2:0] 	rr2_vec_stat;	
 		
	/* Register/Data access helpers */
	assign wreg_a  = cs & we & (~rs[1]) &  rs[0];
	assign wreg_b  = cs & we & (~rs[1]) & ~rs[0];
	assign wdata_a = cs & we & (rs[1] | (rindex == 8)) &  rs[0];
	assign wdata_b = cs & we & (rs[1] | (rindex == 8)) & ~rs[0];
	assign rdata_a = cs & (~we) & (rs[1] | (rindex == 8)) &  rs[0];
	assign rdata_b = cs & (~we) & (rs[1] | (rindex == 8)) & ~rs[0];

	// make sure rindex changes after the cpu cycle has ended so
	// read data is still stable while cpu advances
	always@(negedge sysclk)
		rindex <= rindex_latch;

	/* Register index is set by a write to WR0 and reset
	 * after any subsequent write. We ignore the side
	 */
	always@(negedge sysclk or posedge reset) begin
		if (reset)
		  rindex_latch <= 0;
		else if (cs && !rs[1]) begin
			/* Default, reset index */
			rindex_latch <= 0;

			/* Write to WR0 */
			if (we && rindex == 0) begin
				/* Get low index bits */
				rindex_latch[2:0] <= wdata[2:0];
				  
				/* Add point high */
				rindex_latch[3] <= (wdata[5:3] == 3'b001);
			end
		end
	end

	/* Reset logic (write to WR9 cmd)
	 *
	 * Note about resets: Some bits are documented as unchanged/undefined on
	 * HW reset by the doc. We apply this to channel and soft resets, however
	 * we _do_ reset every bit on an external HW reset in this implementation
	 * to make the FPGA & synthesis tools happy.
	 */
	assign reset   = ((wreg_a | wreg_b) & (rindex == 9) & (wdata[7:6] == 2'b11)) | reset_hw;
	assign reset_a = ((wreg_a | wreg_b) & (rindex == 9) & (wdata[7:6] == 2'b10)) | reset;	
	assign reset_b = ((wreg_a | wreg_b) & (rindex == 9) & (wdata[7:6] == 2'b01)) | reset;

	/* WR1
	 * Reset: bit 5 and 2 unchanged */
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr1_a <= 0;
		else begin
			if (reset_a)
			  wr1_a <= { 2'b00, wr1_a[5], 2'b00, wr1_a[2], 2'b00 };
			else if (wreg_a && rindex == 1)
			  wr1_a <= wdata;
		end
	end
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr1_b <= 0;
		else begin
			if (reset_b)
			  wr1_b <= { 2'b00, wr1_b[5], 2'b00, wr1_b[2], 2'b00 };
			else if (wreg_b && rindex == 1)
			  wr1_b <= wdata;
		end
	end

	/* WR2
	 * Reset: unchanged 
	 */
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr2 <= 0;
		else if ((wreg_a || wreg_b) && rindex == 2)
		  wr2 <= wdata;			
	end

	/* WR3
	 * Reset: bit 0 to 0, otherwise unchanged.
	 */
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr3_a <= 0;
		else begin
			if (reset_a)
			  wr3_a[0] <= 0;
			else if (wreg_a && rindex == 3)
			  wr3_a <= wdata;
		end
	end
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr3_b <= 0;
		else begin
			if (reset_b)
			  wr3_b[0] <= 0;
			else if (wreg_b && rindex == 3)
			  wr3_b <= wdata;
		end
	end

	/* WR4
	 * Reset: Bit 2 to 1, otherwise unchanged
	 */
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr4_a <= 0;
		else begin
			if (reset_a)
			  wr4_a[2] <= 1;
			else if (wreg_a && rindex == 4)
			  wr4_a <= wdata;
		end
	end
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr4_b <= 0;
		else begin
			if (reset_b)
			  wr4_b[2] <= 1;
			else if (wreg_b && rindex == 4)
			  wr4_b <= wdata;
		end
	end

	/* WR5
	 * Reset: Bits 7,4,3,2,1 to 0
	 */
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr5_a <= 0;
		else begin
			if (reset_a)
			  wr5_a <= { 1'b0, wr5_a[6:5], 4'b0000, wr5_a[0] };			
			else if (wreg_a && rindex == 5)
			  wr5_a <= wdata;
		end
	end
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr5_b <= 0;
		else begin
			if (reset_b)
			  wr5_b <= { 1'b0, wr5_b[6:5], 4'b0000, wr5_b[0] };			
			else if (wreg_b && rindex == 5)
			  wr5_b <= wdata;
		end
	end

	/* WR6
	 * Reset: Unchanged.
	 */
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr6_a <= 0;
		else if (wreg_a && rindex == 6)
		  wr6_a <= wdata;
	end
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr6_b <= 0;
		else if (wreg_b && rindex == 6)
		  wr6_b <= wdata;
	end

	/* WR7
	 * Reset: Unchanged.
	 */
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr7_a <= 0;
		else if (wreg_a && rindex == 7)
		  wr7_a <= wdata;
	end
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr7_b <= 0;
		else if (wreg_b && rindex == 7)
		  wr7_b <= wdata;
	end
	
	/* WR9. Special: top bits are reset, handled separately, bottom
	 * bits are only reset by a hw reset
	 */
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr9 <= 0;
		else if ((wreg_a || wreg_b) && rindex == 9)
		  wr9 <= wdata[5:0];			
	end

	/* WR10
	 * Reset: all 0, except chanel reset retains 6 and 5
	 */
	always@(negedge sysclk or posedge reset) begin
		if (reset)
		  wr10_a <= 0;
		else begin
			if (reset_a)
			  wr10_a <= { 1'b0, wr10_a[6:5], 5'b00000 };
			else if (wreg_a && rindex == 10)
			  wr10_a <= wdata;
		end		
	end
	always@(negedge sysclk or posedge reset) begin
		if (reset)
		  wr10_b <= 0;
		else begin
			if (reset_b)
			  wr10_b <= { 1'b0, wr10_b[6:5], 5'b00000 };
			else if (wreg_b && rindex == 10)
			  wr10_b <= wdata;
		end		
	end

	/* WR11
	 * Reset: On full reset only, not channel reset
	 */
	always@(negedge sysclk or posedge reset) begin
		if (reset)
		  wr11_a <= 8'b00001000;
		else if (wreg_a && rindex == 11)
		  wr11_a <= wdata;
	end
	always@(negedge sysclk or posedge reset) begin
		if (reset)
		  wr11_b <= 8'b00001000;
		else if (wreg_b && rindex == 11)
		  wr11_b <= wdata;
	end

	/* WR12
	 * Reset: Unchanged
	 */
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr12_a <= 0;
		else if (wreg_a && rindex == 12)
		  wr12_a <= wdata;
	end
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr12_b <= 0;		
		else if (wreg_b && rindex == 12)
		  wr12_b <= wdata;
	end

	/* WR13
	 * Reset: Unchanged
	 */
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr13_a <= 0;
		else if (wreg_a && rindex == 13)
		  wr13_a <= wdata;
	end
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr13_b <= 0;		
		else if (wreg_b && rindex == 13)
		  wr13_b <= wdata;
	end

	/* WR14
	 * Reset: Full reset maintains  top 2 bits,
	 * Chan reset also maitains bottom 2 bits, bit 4 also
	 * reset to a different value
	 */
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr14_a <= 0;
		else begin
			if (reset)
			  wr14_a <= { wr14_a[7:6], 6'b110000 };
			else if (reset_a)
			  wr14_a <= { wr14_a[7:6], 4'b1000, wr14_a[1:0] };
			else if (wreg_a && rindex == 14)
			  wr14_a <= wdata;
		end		
	end
	always@(negedge sysclk or posedge reset_hw) begin
		if (reset_hw)
		  wr14_b <= 0;
		else begin
			if (reset)
			  wr14_b <= { wr14_b[7:6], 6'b110000 };
			else if (reset_b)
			  wr14_b <= { wr14_b[7:6], 4'b1000, wr14_b[1:0] };
			else if (wreg_b && rindex == 14)
			  wr14_b <= wdata;
		end		
	end

	/* WR15 */
	always@(negedge sysclk or posedge reset) begin
		if (reset) begin
		  wr15_a <= 8'b11111000;
		  wr15_b <= 8'b11111000;
		end else if (rindex == 15) begin
		  if(wreg_a) wr15_a <= wdata;			
		  if(wreg_b) wr15_b <= wdata;			
		end
	end
	
	/* Read data mux */	
	assign rdata = rs[1] && rs[0]       ? data_a :
		       rs[1]                ? data_b :
		       rindex ==  0 && rs[0] ? rr0_a :
		       rindex ==  0          ? rr0_b :
		       rindex ==  1 && rs[0] ? rr1_a :
		       rindex ==  1          ? rr1_b :
		       rindex ==  2 && rs[0] ? wr2 :
		       rindex ==  2          ? rr2_b :
		       rindex ==  3 && rs[0] ? rr3_a :
		       rindex ==  3          ? 8'h00 :
		       rindex ==  4 && rs[0] ? rr0_a :
		       rindex ==  4          ? rr0_b :
		       rindex ==  5 && rs[0] ? rr1_a :
		       rindex ==  5          ? rr1_b :
		       rindex ==  6 && rs[0] ? wr2 :
		       rindex ==  6          ? rr2_b :
		       rindex ==  7 && rs[0] ? rr3_a :
		       rindex ==  7          ? 8'h00 :

		       rindex ==  8 && rs[0] ? data_a :
		       rindex ==  8          ? data_b :
		       rindex ==  9 && rs[0] ? wr13_a :
		       rindex ==  9          ? wr13_b :
		       rindex == 10 && rs[0] ? rr10_a :
		       rindex == 10          ? rr10_b :
		       rindex == 11 && rs[0] ? rr15_a :
		       rindex == 11          ? rr15_b :
		       rindex == 12 && rs[0] ? wr12_a :
		       rindex == 12          ? wr12_b :
		       rindex == 13 && rs[0] ? wr13_a :
		       rindex == 13          ? wr13_b :
		       rindex == 14 && rs[0] ? rr10_a :
		       rindex == 14          ? rr10_b :
		       rindex == 15 && rs[0] ? rr15_a :
		       rindex == 15          ? rr15_b : 8'hff;

	/* RR0 */
	assign rr0_a = { 1'b0, /* Break */
			 1'b1, /* Tx Underrun/EOM */
			 1'b0, /* CTS */
			 1'b0, /* Sync/Hunt */
			 wr15_a[3] ? dcd_latch_a : dcd_a, /* DCD */
			 1'b1, /* Tx Empty */
			 1'b0, /* Zero Count */
			 1'b0  /* Rx Available */
			 };
	assign rr0_b = { 1'b0, /* Break */
			 1'b1, /* Tx Underrun/EOM */
			 1'b0, /* CTS */
			 1'b0, /* Sync/Hunt */
			 wr15_b[3] ? dcd_latch_b : dcd_b, /* DCD */
			 1'b1, /* Tx Empty */
			 1'b0, /* Zero Count */
			 1'b0  /* Rx Available */
			 };

	/* RR1 */
	assign rr1_a = { 1'b0, /* End of frame */
			 1'b0, /* CRC/Framing error */
			 1'b0, /* Rx Overrun error */
			 1'b0, /* Parity error */
			 1'b0, /* Residue code 0 */
			 1'b1, /* Residue code 1 */
			 1'b1, /* Residue code 2 */
			 1'b1  /* All sent */
			 };
	
	assign rr1_b = { 1'b0, /* End of frame */
			 1'b0, /* CRC/Framing error */
			 1'b0, /* Rx Overrun error */
			 1'b0, /* Parity error */
			 1'b0, /* Residue code 0 */
			 1'b1, /* Residue code 1 */
			 1'b1, /* Residue code 2 */
			 1'b1  /* All sent */
			 };
	
	/* RR2 (Chan B only, A is just WR2) */
	assign rr2_b = { wr2[7],
			 wr9[4] ? rr2_vec_stat[0] : wr2[6],
			 wr9[4] ? rr2_vec_stat[1] : wr2[5],
			 wr9[4] ? rr2_vec_stat[2] : wr2[4],
			 wr9[4] ? wr2[3] : rr2_vec_stat[2],
			 wr9[4] ? wr2[2] : rr2_vec_stat[1],
			 wr9[4] ? wr2[1] : rr2_vec_stat[0],
			 wr2[0]
			 };
	

	/* RR3 (Chan A only) */
	assign rr3_a = { 2'b0,
			 rx_irq_pend_a, /* Rx interrupt pending */
			 tx_irq_pend_a, /* Tx interrupt pending */
			 ex_irq_pend_a, /* Status/Ext interrupt pending */
			 rx_irq_pend_b,
			 tx_irq_pend_b,
			 ex_irq_pend_b
			};

	/* RR10 */
	assign rr10_a = { 1'b0, /* One clock missing */
			  1'b0, /* Two clocks missing */
			  1'b0,
			  1'b0, /* Loop sending */
			  1'b0,
			  1'b0,
			  1'b0, /* On Loop */
			  1'b0
			  };
	assign rr10_b = { 1'b0, /* One clock missing */
			  1'b0, /* Two clocks missing */
			  1'b0,
			  1'b0, /* Loop sending */
			  1'b0,
			  1'b0,
			  1'b0, /* On Loop */
			  1'b0
			  };
	
	/* RR15 */
	assign rr15_a = { wr15_a[7],
			  wr15_a[6],
			  wr15_a[5],
			  wr15_a[4],
			  wr15_a[3],
			  1'b0,
			  wr15_a[1],
			  1'b0
			  };

	assign rr15_b = { wr15_b[7],
			  wr15_b[6],
			  wr15_b[5],
			  wr15_b[4],
			  wr15_b[3],
			  1'b0,
			  wr15_b[1],
			  1'b0
			  };
	
	/* Interrupts. Simplified for now
	 *
	 * Need to add latches. Tx irq is latched when buffer goes from full->empty,
	 * it's not a permanent state. For now keep it clear. Will have to fix that.
	 */
	assign rx_irq_pend_a = 0;
	assign tx_irq_pend_a = 0 /*& wr1_a[1]*/; /* Tx always empty for now */
	assign ex_irq_pend_a = ex_irq_ip_a;
	assign rx_irq_pend_b = 0;
	assign tx_irq_pend_b = 0 /*& wr1_b[1]*/; /* Tx always empty for now */
	assign ex_irq_pend_b = ex_irq_ip_b;

	assign _irq = ~(wr9[3] & (rx_irq_pend_a |
				  rx_irq_pend_b |
				  tx_irq_pend_a |
				  tx_irq_pend_b |
				  ex_irq_pend_a |
				  ex_irq_pend_b));

	/* XXX Verify that... also missing special receive condition */
	assign rr2_vec_stat = rx_irq_pend_a ? 3'b110 :
			      tx_irq_pend_a ? 3'b100 :
			      ex_irq_pend_a ? 3'b101 :
			      rx_irq_pend_b ? 3'b010 :
			      tx_irq_pend_b ? 3'b000 :
			      ex_irq_pend_b ? 3'b001 : 3'b011;
	
	/* External/Status interrupt & latch logic */
	assign do_extreset_a = wreg_a & (rindex == 0) & (wdata[5:3] == 3'b010);
	assign do_extreset_b = wreg_b & (rindex == 0) & (wdata[5:3] == 3'b010);

	/* Internal IP bit set if latch different from source and
	 * corresponding interrupt is enabled in WR15
	 */
	assign dcd_ip_a = (dcd_a != dcd_latch_a) & wr15_a[3];
	assign dcd_ip_b = (dcd_b != dcd_latch_b) & wr15_b[3];

	/* Latches close when an enabled IP bit is set and latches
	 * are currently open
	 */
	assign do_latch_a = latch_open_a & (dcd_ip_a /* | cts... */);
	assign do_latch_b = latch_open_b & (dcd_ip_b /* | cts... */);

	/* "Master" interrupt, set when latch close & WR1[0] is set */
	always@(posedge sysclk or posedge reset) begin
		if (reset)
		  ex_irq_ip_a <= 0;
		else if (do_extreset_a)
		  ex_irq_ip_a <= 0;
		else if (do_latch_a && wr1_a[0])
		  ex_irq_ip_a <= 1;
	end
	always@(posedge sysclk or posedge reset) begin
		if (reset)
		  ex_irq_ip_b <= 0;
		else if (do_extreset_b)
		  ex_irq_ip_b <= 0;
		else if (do_latch_b && wr1_b[0])
		  ex_irq_ip_b <= 1;
	end

	/* Latch open/close control */
	always@(posedge sysclk or posedge reset) begin
		if (reset)
		  latch_open_a <= 1;
		else begin
			if (do_extreset_a)
			  latch_open_a <= 1;
			else if (do_latch_a)
			  latch_open_a <= 0;
		end
	end
	always@(posedge sysclk or posedge reset) begin
		if (reset)
		  latch_open_b <= 1;
		else begin
			if (do_extreset_b)
			  latch_open_b <= 1;
			else if (do_latch_b)
			  latch_open_b <= 0;
		end
	end

	/* Latches proper */
	always@(posedge sysclk or posedge reset) begin
		if (reset) begin
			dcd_latch_a <= 0;
			/* cts ... */
		end else begin
			if (do_latch_a)
			  dcd_latch_a <= dcd_a;
			/* cts ... */
		end
	end
	always@(posedge sysclk or posedge reset) begin
		if (reset) begin
			dcd_latch_b <= 0;			
			/* cts ... */
		end else begin
			if (do_latch_b)
			  dcd_latch_b <= dcd_b;
			/* cts ... */
		end
	end
	
	/* NYI */
	assign txd = 1;
	assign rts = 1;

	assign wreq = 1;	
endmodule
