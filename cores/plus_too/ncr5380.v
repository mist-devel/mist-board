/* verilator lint_off UNUSED */

/* based on minimigmac by Benjamin Herrenschmidt */

/* Read registers */
`define RREG_CDR        3'h0    /* Current SCSI data */
`define RREG_ICR        3'h1    /* Initiator Command */
`define RREG_MR         3'h2    /* Mode register */
`define RREG_TCR        3'h3    /* Target Command */
`define RREG_CSR        3'h4    /* SCSI bus status */
`define RREG_BSR        3'h5    /* Bus and status */
`define RREG_IDR        3'h6    /* Input data */
`define RREG_RST        3'h7    /* Reset */

/* Write registers */
`define WREG_ODR        3'h0    /* Output data */
`define WREG_ICR        3'h1    /* Initiator Command */
`define WREG_MR         3'h2    /* Mode register */
`define WREG_TCR        3'h3    /* Target Command */
`define WREG_SER        3'h4    /* Select Enable */
`define WREG_DMAS       3'h5    /* Start DMA Send */
`define WREG_DMATR      3'h6    /* Start DMA Target receive */
`define WREG_IDMAR      3'h7    /* Start DMA Initiator receive */

/* MR bit numbers */
`define MR_DMA_MODE     1
`define MR_ARB          0

/* ICR bit numbers */
`define ICR_A_RST       7
`define ICR_TEST_MODE   6
`define ICR_DIFF_ENBL   5
`define ICR_A_ACK       4
`define ICR_A_BSY       3
`define ICR_A_SEL       2
`define ICR_A_ATN       1
`define ICR_A_DATA      0

/* TCR bit numbers */
`define TCR_A_REQ       3
`define TCR_A_MSG       2
`define TCR_A_CD        1
`define TCR_A_IO        0

module ncr5380
(
	input    		clk,
	input    		ce,

	input 	     	reset,

	/* Bus interface. 3-bit address, to be wired
	 * appropriately upstream (to A4..A6) plus one
	 * more bit (A9) wired as dack.
	 */
	input 	     bus_cs,
	input 	     bus_we,
	input   [2:0] bus_rs,
	input 	     dack,
	input   [7:0] wdata,
	output  [7:0] rdata,


	// connections to io controller
	input   [1:0] img_mounted,
	input  [31:0] img_size,
	
	output [15:0] io_req_type,
	output [31:0] io_lba,
	output  [1:0] io_rd,
	output  [1:0] io_wr,
	input 	     io_ack,

	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr
);

	reg  [7:0] mr;        /* Mode Register */
	reg  [7:0] icr;       /* Initiator Command Register */
	reg  [3:0] tcr;       /* Target Command Register */
	wire [7:0] csr;       /* SCSI bus status register */

	/* Data in and out latches and associated
	* control logic for DMA
	*/
	wire [7:0] din;
	reg  [7:0] dout;
	reg        dphase;
	reg        dma_en;

	/* --- Main host-side interface --- */

	/* Register & DMA accesses decodes */
	reg dma_rd;
	reg dma_wr;
	reg reg_wr;

	wire i_dma_rd = bus_cs &  dack & ~bus_we;
	wire i_dma_wr = bus_cs &  dack &  bus_we;
	wire i_reg_wr = bus_cs & ~dack &  bus_we;

	always @(posedge clk) begin
		reg old_dma_rd, old_dma_wr, old_reg_wr;

		old_dma_rd <= i_dma_rd;
		old_dma_wr <= i_dma_wr;
		old_reg_wr <= i_reg_wr;

		dma_rd <= 0;
		dma_wr <= 0;
		reg_wr <= 0;

		if(~old_dma_wr & i_dma_wr) dma_wr <= 1;
		else if(~old_dma_rd & i_dma_rd) dma_rd <= 1;
		else if(~old_reg_wr & i_reg_wr) reg_wr <= 1;
	end

	/* System bus reads */
	assign rdata = dack                ? cur_data         :
	               bus_rs == `RREG_CDR ? cur_data         :
	               bus_rs == `RREG_ICR ? icr_read         :
	               bus_rs == `RREG_MR  ? mr               :
	               bus_rs == `RREG_TCR ? { 4'h0, tcr }    :
	               bus_rs == `RREG_CSR ? csr              :
	               bus_rs == `RREG_BSR ? bsr              :
	               bus_rs == `RREG_IDR ? cur_data         :
	               bus_rs == `RREG_RST ? 8'hff            :
	               8'hff;

   /* DMA handhsaking logic. Two phase logic, in phase 0
    * DRQ follows SCSI _REQ until we see DACK. In phase 1
    * we just wait for SCSI _REQ to go down and go back to
    * phase 0. We assert SCSI _ACK in phase 1.
    */
	always@(posedge clk or posedge reset) begin
		if (reset) begin
			dphase <= 0;
		end else begin
			if (!dma_en) begin
				dphase <= 0;
			end else if (dphase == 0) begin
				/* Be careful to do that in bus phase 1,
				* not phase 0, or we would incorrectly
				* assert bus_hold and lock up the system
				*/
				if ((dma_rd || dma_wr) && scsi_req) begin
					dphase <= 1;
				end
			end else if (!scsi_req) begin
				dphase <= 0;
			end
		end
	end
   
	/* Data out latch (in DMA mode, this is one cycle after we've
	* asserted ACK)
	*/
	always@(posedge clk) if((reg_wr && bus_rs == `WREG_ODR) || dma_wr) dout <= wdata;
   
	/* Current data register. Simplified logic: We loop back the
	* output data if we are asserting the bus, else we get the
	* input latch
    */
	wire [7:0] cur_data = out_en ? dout : din;
   
	/* Logic for "asserting the bus" simplified */
	wire       out_en = icr[`ICR_A_DATA] | mr[`MR_ARB];
   
	/* ICR read wires */
	wire [7:0] icr_read = { icr[`ICR_A_RST],
	                        icr_aip,
	                        icr_la,
	                        icr[`ICR_A_ACK],
	                        icr[`ICR_A_BSY],
	                        icr[`ICR_A_SEL],
	                        icr[`ICR_A_ATN],
	                        icr[`ICR_A_DATA] };

	/* ICR write */
	always@(posedge clk or posedge reset) begin
		if (reset) begin
			icr <= 0;
		end else if (reg_wr && (bus_rs == `WREG_ICR)) begin
			icr <= wdata;
		end
	end
   
	/* MR write */
	always@(posedge clk or posedge reset) begin
		if (reset) mr <= 8'b0;
		else if (reg_wr && (bus_rs == `WREG_MR)) mr <= wdata;
	end
   
	/* TCR write */
	always@(posedge clk or posedge reset) begin
		if (reset) tcr <= 4'b0;
		else if (reg_wr && (bus_rs == `WREG_TCR)) tcr <= wdata[3:0];
	end
   
	/* DMA start send & receive registers. We currently ignore
	* the direction.
	*/
	always@(posedge clk or posedge reset) begin
		if (reset) begin
			dma_en <= 0;
		end else begin
			if (!mr[`MR_DMA_MODE]) begin
				dma_en <= 0;
			end else if (reg_wr && (bus_rs == `WREG_DMAS)) begin
				dma_en <= 1;
			end else if (reg_wr && (bus_rs == `WREG_IDMAR)) begin
				dma_en <= 1;
			end
		end
	end
   
	/* CSR (read only). We don't do parity */
	assign csr = { scsi_rst, scsi_bsy, scsi_req, scsi_msg,
	               scsi_cd, scsi_io, scsi_sel, 1'b0 };	

	/* Bus and Status register */
	/* BSR (read only). We don't do a few things... */
	wire bsr_eodma = 1'b0;	/* We don't do EOP */
	wire bsr_dmarq = scsi_req & dma_en;
	wire bsr_perr = 1'b0;	/* We don't do parity */
	wire bsr_irq = 1'b0;	        /* XXX ? Does MacOS use this ? */
	wire bsr_pmatch = 
	         tcr[`TCR_A_MSG] == scsi_msg &&
	         tcr[`TCR_A_CD ] == scsi_cd  &&
	         tcr[`TCR_A_IO ] == scsi_io;

	wire bsr_berr = 1'b0;	/* XXX ? Does MacOS use this ? */
	wire [7:0] bsr = { bsr_eodma, bsr_dmarq, bsr_perr, bsr_irq,
	                   bsr_pmatch, bsr_berr, scsi_atn, scsi_ack };

   /* --- Simulated SCSI Signals --- */

   /* BSY logic (simplified arbitration, see notes) */
	wire scsi_bsy = 
	    icr[`ICR_A_BSY] |
	    scsi2_bsy |
	    //scsi6_bsy |
	    mr[`MR_ARB];

	/* Remains of simplified arbitration logic */
	wire icr_aip = mr[`MR_ARB];
	wire icr_la = 0;

	reg 	dma_ack;
	always @(posedge clk) if(ce) dma_ack <= dphase;

	/* Other ORed SCSI signals */
	wire scsi_sel = icr[`ICR_A_SEL];
	wire scsi_rst = icr[`ICR_A_RST];
	wire scsi_ack = icr[`ICR_A_ACK] | dma_ack;
	wire scsi_atn = icr[`ICR_A_ATN];

	wire scsi_cd  = scsi2_cd;
	wire scsi_io  = scsi2_io;
	wire scsi_msg = scsi2_msg;
	wire scsi_req = scsi2_req;
	
	assign din = scsi2_dout;

	assign io_lba      = io_lba_2;
	assign sd_buff_din = sd_buff_din_2;
	/* Other trivial lines set by target */
	/*
	wire scsi_cd  = (scsi2_bsy) ? scsi2_cd : scsi6_cd;
	wire scsi_io  = (scsi2_bsy) ? scsi2_io : scsi6_io;
	wire scsi_msg = (scsi2_bsy) ? scsi2_msg : scsi6_msg;
	wire scsi_req = (scsi2_bsy) ? scsi2_req : scsi6_req;
	
	assign din = scsi2_bsy ? scsi2_dout : 
	             scsi6_bsy ? scsi6_dout : 
	             8'h55;

	assign io_lba      = (scsi2_bsy) ? io_lba_2 : io_lba_6;
	assign sd_buff_din = (scsi2_bsy) ? sd_buff_din_2 : sd_buff_din_6;
	assign io_req_type = 16'h0000;	// Not used atm. Could be used for CD-ROM sector requests later. ElectronAsh.
*/
	// input signals from target 2
	wire scsi2_bsy, scsi2_msg, scsi2_io, scsi2_cd, scsi2_req;
	wire [7:0] scsi2_dout;

	wire [31:0] io_lba_2;
	wire [7:0] sd_buff_din_2;

	// connect a target
	scsi #(.ID(2)) scsi2
	(
		.clk    ( clk ),
		.rst    ( scsi_rst ),
		.sel    ( scsi_sel ),
		.atn    ( scsi_atn ),
		
		.ack    ( scsi_ack ),
		
		.bsy    ( scsi2_bsy ),
		.msg    ( scsi2_msg ),
		.cd     ( scsi2_cd ),
		.io     ( scsi2_io ),
		.req    ( scsi2_req ),
		.dout   ( scsi2_dout ),
		
		.din    ( dout ),

		// connection to io controller to read and write sectors
		// to sd card
		.img_mounted(img_mounted[0]),
		.img_blocks(img_size[31:9]),
		.io_lba ( io_lba_2 ),
		.io_rd  ( io_rd[0] ),
		.io_wr  ( io_wr[0] ),
		.io_ack ( io_ack & scsi2_bsy ),

		.sd_buff_addr( sd_buff_addr ),
		.sd_buff_dout( sd_buff_dout ),
		.sd_buff_din( sd_buff_din_2 ),
		.sd_buff_wr( sd_buff_wr & scsi2_bsy )
	);

/*
	// input signals from target 6
	wire scsi6_bsy, scsi6_msg, scsi6_io, scsi6_cd, scsi6_req;
	wire [7:0] scsi6_dout;
	
	wire [31:0] io_lba_6;
	wire [7:0] sd_buff_din_6;

	scsi #(.ID(6)) scsi6
	(
		.clk		( clk ) ,           // input  clk
		.rst		( scsi_rst ) ,      // input  rst
		.sel		( scsi_sel ) ,      // input  sel
		.atn		( scsi_atn ) ,      // input  atn
		
		.ack		( scsi_ack ) ,      // input  ack
		
		.bsy		( scsi6_bsy ) ,     // output  bsy
		.msg		( scsi6_msg ) ,     // output  msg
		.cd         ( scsi6_cd ) ,      // output  cd
		.io         ( scsi6_io ) ,      // output  io
		.req		( scsi6_req ) ,     // output  req
		.dout		( scsi6_dout ) ,    // output [7:0] dout

		.din		( dout ) ,          // input [7:0] din

		// connection to io controller to read and write sectors
		// to sd card
		.img_mounted( img_mounted[1] ),
		.img_blocks( img_size[31:9] ),
		.io_lba	( io_lba_6 ) ,		// output [31:0] io_lba
		.io_rd	( io_rd[1] ) ,		// output  io_rd
		.io_wr	( io_wr[1] ) ,		// output  io_wr
		.io_ack	( io_ack & scsi6_bsy ) ,		// input  io_ack

		.sd_buff_addr( sd_buff_addr ) ,	// input [8:0] sd_buff_addr
		.sd_buff_dout( sd_buff_dout ) ,	// input [7:0] sd_buff_dout
		.sd_buff_din( sd_buff_din_6 ) ,	// output [7:0] sd_buff_din
		.sd_buff_wr( sd_buff_wr & scsi6_bsy ) 	// input  sd_buff_wr
	);
*/

endmodule
