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
`define WREG_ODR        3'h0    /* Ouptut data */
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

module ncr5380(input    sysclk,
               input 	     reset,
	       
               /* Bus interface. 3-bit address, to be wired
                * appropriately upstream (to A4..A6) plus one
                * more bit (A9) wired as dack.
                */
               input 	     bus_cs,
               input 	     bus_we,
               input [2:0]   bus_rs,
               input 	     dack,
               input [7:0]   wdata,
               output [7:0]  rdata,
	       
	       
	       // connections to io controller
	       output [31:0] io_lba,
	       output 	     io_rd,
	       output 	     io_wr,
	       input 	     io_ack,
               output [7:0]  io_dout,
               input 	     io_dout_strobe,
               input [7:0]   io_din,
               input 	     io_din_strobe
               );
   
   reg [7:0]  mr;        /* Mode Register */
   reg [7:0]  icr;       /* Initiator Command Register */
   reg [3:0]  tcr;       /* Target Command Register */
   wire [7:0] csr;       /* SCSI bus status register */
   
   /* Data in and out latches and associated
    * control logic for DMA
    */
   wire [7:0]  din;
   reg [7:0]  dout;
   reg 	      dphase;
   reg 	      dma_en;
   
   /* --- Main host-side interface --- */
   
   /* Register & DMA accesses decodes */
   wire       dma_rd = bus_cs &  dack & ~bus_we;
   wire       dma_wr = bus_cs &  dack &  bus_we;
   wire       reg_rd = bus_cs & ~dack & ~bus_we;
   wire       reg_wr = bus_cs & ~dack &  bus_we;
   
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
   always@(negedge sysclk or posedge reset) begin
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
   always@(negedge sysclk)
		if ((reg_wr && bus_rs == `WREG_ODR) || dma_wr)
			dout <= wdata;
   
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
   always@(negedge sysclk or posedge reset) begin
      if (reset) begin
         icr <= 0;
      end else if (reg_wr && (bus_rs == `WREG_ICR)) begin
         icr <= wdata;
      end
   end
   
   /* MR write */
   always@(negedge sysclk or posedge reset) begin
      if (reset)
        mr <= 8'b0;
      else if (reg_wr && (bus_rs == `WREG_MR))
        mr <= wdata;
   end
   
   /* TCR write */
   always@(negedge sysclk or posedge reset) begin
      if (reset)
        tcr <= 4'b0;
      else if (reg_wr && (bus_rs == `WREG_TCR))
        tcr <= wdata[3:0];
   end
   
   /* DMA start send & receive registers. We currently ignore
    * the direction.
    */
   always@(negedge sysclk or posedge reset) begin
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
   wire bsr_dmarq = scsi_req & ~dphase & dma_en;
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
		mr[`MR_ARB];
   
   /* Remains of simplified arbitration logic */
   wire icr_aip = mr[`MR_ARB];
   wire icr_la = 0;

   reg 	dma_ack;
   always @(posedge sysclk)
     dma_ack <= dphase;
   
   /* Other ORed SCSI signals */
   wire scsi_sel = icr[`ICR_A_SEL];
   wire scsi_rst = icr[`ICR_A_RST];
   wire scsi_ack = icr[`ICR_A_ACK] | dma_ack;
   wire scsi_atn = icr[`ICR_A_ATN];
   
   /* Other trivial lines set by target */
   wire scsi_cd = scsi2_cd;
   wire scsi_io = scsi2_io;
   wire scsi_msg = scsi2_msg;
   wire scsi_req = scsi2_req;

   assign din = scsi2_bsy?scsi2_dout:8'h55;
   
   // input signals from target 2
   wire scsi2_bsy, scsi2_msg, scsi2_io, scsi2_cd, scsi2_req;
   wire [7:0] scsi2_dout;

   // connect a target
   scsi #(.ID(2)) scsi2(.sysclk ( sysclk ),
			.rst    ( scsi_rst ),
			.sel    ( scsi_sel ),
			.atn    ( scsi_atn ),
			.bsy    ( scsi2_bsy ),
			.msg    ( scsi2_msg ),
			.cd     ( scsi2_cd ),
			.io     ( scsi2_io ),
			.req    ( scsi2_req ),
			.ack    ( scsi_ack ),
			.dout   ( scsi2_dout ),
			.din    ( dout ),

			// connection to io controller to read and write sectors
			// to sd card
			.io_lba ( io_lba ),
			.io_rd  ( io_rd ),
			.io_wr  ( io_wr ),
			.io_ack ( io_ack ),
			.io_dout ( io_dout ),
			.io_dout_strobe ( io_dout_strobe ),
			.io_din ( io_din ),
			.io_din_strobe ( io_din_strobe )
			);
   
   
endmodule
