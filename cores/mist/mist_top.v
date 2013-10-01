/********************************************/
/*                                          */
/********************************************/


module mist_top (
  // clock inputsxque	
  input wire [ 2-1:0] 	CLOCK_27, // 27 MHz
  // LED outputs
  output wire 		LED, // LED Yellow
  // UART
  output wire 		UART_TX, // UART Transmitter
  input wire 		UART_RX, // UART Receiver
  // VGA
  output wire 		VGA_HS, // VGA H_SYNC
  output wire 		VGA_VS, // VGA V_SYNC
  output wire [ 6-1:0] 	VGA_R, // VGA Red[5:0]
  output wire [ 6-1:0] 	VGA_G, // VGA Green[5:0]
  output wire [ 6-1:0] 	VGA_B, // VGA Blue[5:0]
  // SDRAM
  inout wire [ 16-1:0] 	SDRAM_DQ, // SDRAM Data bus 16 Bits
  output wire [ 13-1:0] SDRAM_A, // SDRAM Address bus 13 Bits
  output wire 		SDRAM_DQML, // SDRAM Low-byte Data Mask
  output wire 		SDRAM_DQMH, // SDRAM High-byte Data Mask
  output wire 		SDRAM_nWE, // SDRAM Write Enable
  output wire 		SDRAM_nCAS, // SDRAM Column Address Strobe
  output wire 		SDRAM_nRAS, // SDRAM Row Address Strobe
  output wire 		SDRAM_nCS, // SDRAM Chip Select
  output wire [ 2-1:0] 	SDRAM_BA, // SDRAM Bank Address
  output wire 		SDRAM_CLK, // SDRAM Clock
  output wire 		SDRAM_CKE, // SDRAM Clock Enable
  // MINIMIG specific
  output wire 		AUDIO_L, // sigma-delta DAC output left
  output wire 		AUDIO_R, // sigma-delta DAC output right
  // SPI
  inout wire 		SPI_DO,
  input wire 		SPI_DI,
  input wire 		SPI_SCK,
  input wire 		SPI_SS2,    // fpga
  input wire 		SPI_SS3,    // OSD
  input wire 		SPI_SS4,    // "sniff" mode
  input wire 		CONF_DATA0  // SPI_SS for user_io
);

wire [15:0] video_data;
wire video_read;
wire [22:0] video_address;
wire st_de, st_hs, st_vs;
wire [15:0] video_adj;

// on-board io
wire [1:0] buttons;

// generate dtack for all implemented peripherals
wire io_dtack = vreg_sel || mmu_sel || mfp_sel || mfp_iack || 
     acia_sel || psg_sel || dma_sel || auto_iack || blitter_sel;

// the original tg68k did not contain working support for bus fault exceptions. While earlier
// TOS versions cope with that, TOS versions with blitter support need this to work as this is
// required to properly detect that a blitter is not present.
// a bus error is now generated once no dtack is seen for 63 clock cycles.
wire tg68_clr_berr;
wire tg68_berr = (dtack_timeout == 3'd7); //  || cpu_write_illegal;
	
// count bus errors for debugging purposes. we can thus trigger for a
// certain bus error
reg [3:0] berr_cnt_out /* synthesis noprune */;
reg [3:0] berr_cnt;
reg berrD;
always @(posedge clk_8) begin
	berrD <= tg68_berr;

	if(reset) begin
		berr_cnt <= 4'd0;
	end else begin
		berr_cnt_out <= 4'd0;
		if(tg68_berr && !berrD) begin
			berr_cnt_out <= berr_cnt + 4'd1;
			berr_cnt <= berr_cnt + 4'd1;
		end
	end
end

// the following is just to prevent optimization			
//assign UART_TX = (berr_cnt_out == 4'd0);

wire cpu_write = cpu_cycle && cpu2io && address_strobe && !tg68_rw;

// it's illegal to write to certain memory areas
// TODO: Still the write itself would succeed. That must not happen
wire cpu_write_illegal = cpu_write && 
     (tg68_adr[23:3] === 21'd0);     // the first two long words $0 and $4

	  
reg [2:0] dtack_timeout;
always @(posedge clk_8) begin
	if(reset) begin
		dtack_timeout <= 3'd0;
	end else begin
		if(cpu_cycle) begin
			// timeout only when cpu owns the bus and when
			// neither dtack nor fast ram are active
			if(dtack_timeout != 3'd7) begin
				if(!tg68_dtack || br || tg68_cpuena || tg68_as)
					dtack_timeout <= 3'd0;
				else
					dtack_timeout <= dtack_timeout + 3'd1;
			end else
				// release bus error when cpu core asks us to do so
				if(tg68_clr_berr)
					dtack_timeout <= 3'd0;
		end
	end
end
		
// no tristate busses exist inside the FPGA. so bus request doesn't do
// much more than halting the cpu by suppressing dtack
wire br = data_io_br || blitter_br; //  && (tg68_cpustate[1:0] == 2'b00) ;   // dma is only other bus master (yet)
wire data_io_br;

// request interrupt ack from mfp for IPL == 6
wire mfp_iack = cpu_cycle && cpu2iack && address_strobe && (tg68_adr[3:1] == 3'b110);

// the tg68k core with the wrapper of the minimig doesn't support non-autovector
// interrupts. Also the existing support for them inside the tg68 kernel is/was broken.
// For the atari i've fixed the non-autovector support inside the kernel and switched
// entirely to non-autovector interrupts. This means that i now have to provide
// the vectors for those interrupts that oin the ST are autovector ones. This needs
// to be done for IPL2 (hbi) and IPL4 (vbi)
wire auto_iack = cpu_cycle && cpu2iack && address_strobe && 
     ((tg68_adr[3:1] == 3'b100) || (tg68_adr[3:1] == 3'b010));
wire [7:0] auto_vector_vbi = (auto_iack && (tg68_adr[3:1] == 3'b100))?8'h1c:8'h00;
wire [7:0] auto_vector_hbi = (auto_iack && (tg68_adr[3:1] == 3'b010))?8'h1a:8'h00;
   
wire [7:0] auto_vector = auto_vector_vbi | auto_vector_hbi;
 
// interfaces not implemented:
// $fff00000 - $fff000ff  - IDE  
// $ffff8780 - $ffff878f  - SCSI
// $ffff8901 - $ffff893f  - STE DMA audio
// $ffff9200 - $ffff923f  - STE joystick ports
// $fffffa40 - $fffffa7f  - FPU
// $fffffc20 - $fffffc3f  - RTC

wire io_sel = cpu_cycle && cpu2io && address_strobe ;
 
// mmu 8 bit interface at $ff8000 - $ff8801
wire mmu_sel  = io_sel && ({tg68_adr[15:1], 1'd0} == 16'h8000);
wire [7:0] mmu_data_out;

// video controller 16 bit interface at $ff8200 - $ff827f
wire vreg_sel = io_sel && ({tg68_adr[15:7], 7'd0} == 16'h8200);
wire [15:0] vreg_data_out;

// mfp 8 bit interface at $fffa00 - $fffa3f
wire mfp_sel  = io_sel && ({tg68_adr[15:6], 6'd0} == 16'hfa00);
wire [7:0] mfp_data_out;

// acia 8 bit interface at $fffc00 - $fffc07
wire acia_sel = io_sel && ({tg68_adr[15:8], 8'd0} == 16'hfc00);
wire [7:0] acia_data_out;

// blitter 16 bit interface at $ff8a00 - $ff8a3f
wire blitter_sel = system_ctrl[19] && io_sel && ({tg68_adr[15:8], 8'd0} == 16'h8a00);
wire [15:0] blitter_data_out;

//  psg 8 bit interface at $ff8800 - $ff8803
wire psg_sel  = io_sel && ({tg68_adr[15:8], 8'd0} == 16'h8800);
wire [7:0] psg_data_out;

//  dma 16 bit interface at $ff8600 - $ff860f
wire dma_sel  = io_sel && ({tg68_adr[15:4], 4'd0} == 16'h8600);
wire [15:0] dma_data_out;

// de-multiplex the various io data output ports into one 
wire [7:0] io_data_out_8u = acia_data_out | psg_data_out;
wire [7:0] io_data_out_8l = mmu_data_out | mfp_data_out | auto_vector;
wire [15:0] io_data_out = vreg_data_out | dma_data_out | blitter_data_out |
			{8'h00, io_data_out_8l} | {io_data_out_8u, 8'h00};

wire init = ~pll_locked;

video video (
	.clk         (clk_32        ),
   .clk27       (CLOCK_27[0]),
	.bus_cycle   (bus_cycle     ),
	
	// spi for OSD
   .sdi            (SPI_DI    ),
   .sck            (SPI_SCK   ),
   .ss             (SPI_SS3   ),

	// cpu register interface
	.reg_clk      (clk_8       ),
	.reg_reset    (reset       ),
	.reg_din      (tg68_dat_out),
	.reg_sel      (vreg_sel    ),
	.reg_addr     (tg68_adr[6:1]),
	.reg_uds      (tg68_uds    ),
	.reg_lds      (tg68_lds    ),
	.reg_rw       (tg68_rw     ),
	.reg_dout     (vreg_data_out),
	
   .vaddr      (video_address ),
	.data       (ram_data_out  ),
	.read       (video_read    ),
	
	.hs			(VGA_HS			),
	.vs			(VGA_VS			),
	.video_r    (VGA_R        	),
	.video_g    (VGA_G        	),
	.video_b    (VGA_B        	),

	.adjust     (video_adj    	),
	.pal56      (~system_ctrl[9]),
   .scanlines  (system_ctrl[21:20]),
	
	// signals not affected by scan doubler required for
	// irq generation
	.st_hs		(st_hs      	),
	.st_vs		(st_vs      	),
	.st_de		(st_de      	)
);

mmu mmu (
	// cpu register interface
	.clk      (clk_8       ),
	.reset    (reset       ),
	.din      (tg68_dat_out[7:0]),
	.sel      (mmu_sel     ),
	.ds       (tg68_lds    ),
	.rw       (tg68_rw     ),
	.dout     (mmu_data_out)
);

wire acia_irq, dma_irq;

mfp mfp (
	// cpu register interface
	.clk      (clk_8       ),
	.reset    (reset       ),
	.din      (tg68_dat_out[7:0]),
	.sel      (mfp_sel     ),
	.addr     (tg68_adr[5:1]),
	.ds       (tg68_lds    ),
	.rw       (tg68_rw     ),
	.dout     (mfp_data_out),
	.irq	    (mfp_irq     ),
	.iack	    (mfp_iack    ),

	// serial/rs232 interface
	.serial_data_out_available 	(serial_data_from_mfp_available),
	.serial_strobe_out 				(serial_strobe_from_mfp),
	.serial_data_out 	   			(serial_data_from_mfp),
	
	// input signals
	.clk_ext     (clk_mfp     ),
	.de          (st_de       ),
	.dma_irq     (dma_irq     ),
	.acia_irq    (acia_irq    ),
	.blitter_irq (blitter_irq ),
	.mono_detect (system_ctrl[8])
); 

acia acia (
	// cpu interface
	.clk      (clk_8       ),
	.reset    (reset       ),
	.din      (tg68_dat_out[15:8]),
	.sel      (acia_sel    ),
	.addr     (tg68_adr[2:1]),
	.ds       (tg68_uds    ),
	.rw       (tg68_rw     ),
	.dout     (acia_data_out),
	.irq      (acia_irq     ),
	
	// MIDI interface
	.midi_out (UART_TX      ),
	.midi_in  (UART_RX      ),
	
	// ikbd interface
	.ikbd_data_out_available 	(ikbd_data_from_acia_available),
	.ikbd_strobe_out 				(ikbd_strobe_from_acia),
	.ikbd_data_out 	   		(ikbd_data_from_acia),
	.ikbd_strobe_in 				(ikbd_strobe_to_acia),
	.ikbd_data_in 	   			(ikbd_data_to_acia)
);

wire [23:1] blitter_master_addr;
wire blitter_master_write;
wire blitter_master_read;
wire blitter_br;
wire blitter_irq;
wire [15:0] blitter_master_data_out;

blitter blitter (
	.bus_cycle 	(bus_cycle_8  ),

	// cpu interface
	.clk       	(clk_8            ),
	.reset     	(reset            ),
	.din       	(tg68_dat_out     ),
	.sel       	(blitter_sel      ),
	.addr      	(tg68_adr[5:1]    ),
	.uds       	(tg68_uds         ),
	.lds       	(tg68_lds         ),
	.rw        	(tg68_rw          ),
	.dout      	(blitter_data_out ),

	.bm_addr   	(blitter_master_addr),
	.bm_write	(blitter_master_write),
	.bm_data_out (blitter_master_data_out),
	.bm_read    (blitter_master_read),
   .bm_data_in (ram_data_out),

	.br_in     (data_io_br       ),
	.br_out    (blitter_br       ),
	.irq       (blitter_irq      )
);
   

//// ym2149 sound chip ////
reg [1:0] sclk;
always @ (posedge clk_8)
	sclk <= sclk + 2'd1;

wire [7:0] port_a_out;
assign floppy_side = port_a_out[0];
assign floppy_sel = port_a_out[2:1];

wire [7:0] audio_out_l,audio_out_r;
//assign AUDIO_R = AUDIO_L;

sigma_delta_dac sigma_delta_dac_l (
	.DACout 		(AUDIO_L),
	.DACin		(audio_out_l),
	.CLK 			(clk_32),
	.RESET 		(reset)
);

sigma_delta_dac sigma_delta_dac_r (
  .DACout     (AUDIO_R),
  .DACin    (audio_out_r),
  .CLK      (clk_32),
  .RESET    (reset)
);

YM2149 ym2149 (
	.I_DA						( tg68_dat_out[15:8]		),
	.O_DA						( psg_data_out				),
	.O_DA_OE_L           (								),

	// control
	.I_A9_L              ( 1'b0						),
	.I_A8                ( 1'b1						),
	.I_BDIR              ( psg_sel && !tg68_rw	),
	.I_BC2               ( 1'b1						),
	.I_BC1              	( psg_sel && !tg68_adr[1]),
	.I_SEL_L             ( 1'b1						),

	.O_AUDIO_L           (audio_out_l				),
	.O_AUDIO_R           (audio_out_r				),

	.stereo 					(system_ctrl[22]			),
	
	// port a
	.I_IOA           		( 8'd0 						),
	.O_IOA              	( port_a_out				),
	.O_IOA_OE_L      		(								),

	// port b
	.I_IOB               ( 8'd0						),
	.O_IOB              	(								),
	.O_IOB_OE_L         	(								),
  
	//
	.ENA                	( 1'b1						), 
	.RESET_L            	( !reset 					),
	.CLK                	( sclk[1]  					)	// 2 MHz
);
  
wire dma_dio_ack;
wire [4:0] dma_dio_idx;
wire [7:0] dma_dio_data;

// floppy_sel is active low
wire wr_prot = (floppy_sel == 2'b01)?system_ctrl[7]:system_ctrl[6];

dma dma (
	// cpu interface
	.clk      (clk_8       ),
	.reset    (reset       ),
	.din      (tg68_dat_out[15:0]),
	.sel      (dma_sel    ),
	.addr     (tg68_adr[3:1]),
	.uds      (tg68_uds    ),
	.lds      (tg68_lds    ),
	.rw       (tg68_rw     ),
	.dout     (dma_data_out),
	
	.irq      (dma_irq     ),

	// system control interface
	.fdc_wr_prot (wr_prot),
	.acsi_enable (system_ctrl[17:10]),
	
	// data_io (arm controller imterface)
	.dio_idx  (dma_dio_idx ),
	.dio_data (dma_dio_data),
	.dio_ack  (dma_dio_ack ),

	// floppy interface
	.drv_sel  (floppy_sel  ),
	.drv_side (floppy_side )
);

wire [1:0] floppy_sel;
wire floppy_side;
assign LED = (floppy_sel == 2'b11);

// clock generation
wire pll_locked;
wire clk_8;
wire clk_32;
wire clk_128;
wire clk_mfp;
    
// use pll
clock clock (
  .areset       (1'b0             ), // async reset input
  .inclk0       (CLOCK_27[0]      ), // input clock (27MHz)
  .c0           (clk_128          ), // output clock c0 (128MHz)
  .c1           (clk_32           ), // output clock c1 (32MHz)
  .c2           (SDRAM_CLK        ), // output clock c2 (128MHz)
  .c3           (clk_mfp          ), // output clock c3 (2.4576MHz)
  .locked       (pll_locked       )  // pll locked output
);

//// 8MHz clock ////
wire [3:0] bus_cycle;
reg [3:0] clk_cnt;
reg [1:0] bus_cycle_8;


always @ (posedge clk_32, negedge pll_locked) begin

	if (!pll_locked) begin
		clk_cnt <= #1 4'b0010;
		bus_cycle_8 <= 2'd3;
	end else begin 
		clk_cnt <=  #1 clk_cnt + 4'd1;
		if(clk_cnt[1:0] == 2'd2) begin
			bus_cycle_8 <= bus_cycle_8 + 2'd1;
		end
	end
end

assign clk_8 = clk_cnt[1];
assign bus_cycle = clk_cnt - 4'd2;

// bus cycle counter for debugging
reg [31:0] cycle_counter /* synthesis noprune */;
always @ (posedge clk_8) begin
	if(reset)
		cycle_counter <= 32'd0;
	else
		cycle_counter <= cycle_counter + 32'd1;
end

			// SDRAM
assign SDRAM_CKE         = 1'b1;
assign SDRAM_nCS         = sdram_cs[0];
assign SDRAM_DQML        = sdram_dqm[0];
assign SDRAM_DQMH        = sdram_dqm[1];

wire [  4-1:0] sdram_cs;
wire [  2-1:0] sdram_dqm;

// host sdram interface used for io data up/download
wire [2:0] host_state;
wire [22:0] host_addr;
wire [15:0] host_dataWR;
wire [15:0] host_dataRD;
 
// tg68
wire [ 16-1:0] tg68_dat_in;
wire [ 16-1:0] tg68_dat_out;
wire [ 32-1:0] tg68_adr;
wire [  3-1:0] tg68_IPL;
wire           tg68_dtack;
wire           tg68_as;
wire           tg68_uds;
wire           tg68_lds;
wire           tg68_rw;
wire           tg68_ena7RD;
wire           tg68_ena7WR;
wire           tg68_enaWR;
wire [ 16-1:0] tg68_cout;
wire           tg68_cpuena;
wire [ 32-1:0] tg68_cad;
wire [  6-1:0] tg68_cpustate /* synthesis noprune */;
wire           tg68_cdma;
wire           tg68_clds;
wire           tg68_cuds;

wire reset = system_ctrl[0];

// ------------- generate VBI (IPL = 4) --------------
wire vbi_ack; 
assign vbi_ack = cpu2iack && address_strobe && (tg68_adr[3:1] == 3'b100);

reg vsD, vsD2, vsI, vbi;
always @(negedge clk_8)
	vsD <= st_vs;

always @(posedge clk_8) begin
	vsD2 <= vsD;           // delay by one
	vsI <= vsD && !vsD2;   // create single event

	if(reset || vbi_ack)
		vbi <= 1'b0;
	else if(vsI)
		vbi <= 1'b1;
end

// ------------- generate HBI (IPL = 2) --------------
wire hbi_ack; 
assign hbi_ack = cpu2iack && address_strobe && (tg68_adr[3:1] == 3'b010);

reg hsD, hsD2, hsI, hbi;
always @(negedge clk_8)
	hsD <= st_hs;

always @(posedge clk_8) begin
	hsD2 <= hsD;           // delay by one
	hsI <= hsD && !hsD2;   // create single event

	if(reset || hbi_ack)
		hbi <= 1'b0;
	else if(hsI)
		hbi <= 1'b1;
end

wire mfp_irq;
reg [2:0] ipl;
always @(posedge clk_8) begin
	if(reset) begin
		ipl <= 3'b111;
	end else begin

		// ipl[0] is tied high on the atari
		if(mfp_irq)   ipl <= 3'b001;  // mfp has IPL 6
		else if(vbi)  ipl <= 3'b011;  // vbi has IPL 4
		else if(hbi)  ipl <= 3'b101;  // hbi has IPL 2
		else	   	  ipl <= 3'b111;
	end
end
	
//// TG68K main CPU ////
TG68K tg68k (
  .clk          (clk_128          ),
  .reset        (~reset           ),
  .clkena_in    (1'b1             ),
  .IPL          (ipl              ),  // 3'b111
  .dtack        (tg68_dtack       ),
  .vpa          (1'b1             ),
  .ein          (1'b1             ),
  .addr         (tg68_adr         ),
  .data_read    (cpu_data_in      ),
  .data_write   (tg68_dat_out     ),
  .as           (tg68_as          ),
  .uds          (tg68_uds         ),
  .lds          (tg68_lds         ),
  .rw           (tg68_rw          ),
  .berr         (tg68_berr        ),
  .clr_berr     (tg68_clr_berr    ),
  .e            (                 ),
  .vma          (                 ),
  .wrd          (                 ),
  .ena7RDreg    (tg68_ena7RD      ),
  .ena7WRreg    (tg68_ena7WR      ),
  .enaWRreg     (tg68_enaWR       ),
  .fromram      (tg68_cout        ),
  .ramready     (tg68_cpuena      ),
  .cpu          (system_ctrl[5:4] ),  // 00=68000
  .ramaddr      (tg68_cad         ),
  .cpustate     (tg68_cpustate    ),
  .nResetOut    (                 ),
  .skipFetch    (                 ),
  .cpuDMA       (tg68_cdma        ),
  .ramlds       (tg68_clds        ),
  .ramuds       (tg68_cuds        ),
  .turbo        (system_ctrl[18]  )
);

// 
wire [15:0] cpu_data_in;
assign cpu_data_in = cpu2mem?ram_data_out:io_data_out;

// cpu/video stram multiplexing
wire [22:0] ram_address;
wire [15:0] ram_data_out;

wire video_cycle = (bus_cycle[3:2] == 0);
wire cpu_cycle = (bus_cycle[3:2] == 1); // || (bus_cycle[3:2] == 3);

assign ram_address = video_cycle?video_address:(blitter_br?blitter_master_addr:tg68_adr[23:1]);
assign video_data = ram_data_out;

// TODO: put 0x000000 to 0x000007 into tos section so it's write protected
wire MEM512K = (system_ctrl[3:1] == 3'd0);
wire MEM1M   = (system_ctrl[3:1] == 3'd1);
wire MEM2M   = (system_ctrl[3:1] == 3'd2);
wire MEM4M   = (system_ctrl[3:1] == 3'd3);
wire MEM8M   = (system_ctrl[3:1] == 3'd4);
wire MEM14M  = (system_ctrl[3:1] == 3'd5);

// ram from 0x000000 to 0x400000
wire cpu2ram = (tg68_adr[23:22] == 2'b00) ||              // ordinary 4MB
	((MEM14M || MEM8M) &&  (tg68_adr[23:22] == 2'b01)) ||  // 8MB 
	(MEM14M            && ((tg68_adr[23:22] == 2'b10) ||   // 12MB
	                       (tg68_adr[23:21] == 3'b110)));  // 14MB 

wire cpu2ram14 = (tg68_adr[23:22] == 2'b00) ||  // ordinary 4MB
					  (tg68_adr[23:22] == 2'b01) ||  // 8MB 
					  (tg68_adr[23:22] == 2'b10) ||  // 12MB
	              (tg68_adr[23:21] == 3'b110);   // 14MB 

// 256k tos from 0xe00000 to 0xe40000
wire cpu2tos256k = (tg68_adr[23:18] == 6'b111000);

// 192k tos from 0xfc0000 to 0xff0000
wire cpu2tos192k = (tg68_adr[23:17] == 7'b1111110) || 
		 				 (tg68_adr[23:16] == 8'b11111110);

// 128k cartridge from 0xfa0000 to 0xfc0000
wire cpu2cart = (tg68_adr[23:17] == 7'b1111101);

// cpu to any type of mem (rw on ram, read on rom)
wire cpu2mem = cpu2ram14 || (tg68_rw && (cpu2tos192k || cpu2tos256k || cpu2cart));
							
// io from 0xff0000
wire cpu2io = (tg68_adr[23:16] == 8'b11111111);

// irq ack happens on 0xfffffX
wire cpu2iack = (tg68_adr[23:4] == 20'hfffff);

// data strobe!
// wire address_strobe = ~tg68_uds || ~tg68_lds;
reg address_strobe;
always @(posedge clk_8)
//	address_strobe <= (video_cycle) && (~tg68_lds || ~tg68_uds);
	address_strobe <= video_cycle && ~tg68_as && !br;

// generate dtack (for st ram only and rom), TODO: no dtack for rom write
assign tg68_dtack = ~(((cpu2mem && address_strobe) || io_dtack ) && !br);

wire ram_oe = video_cycle?~video_read:
	(cpu_cycle?~(blitter_br?blitter_master_read:(address_strobe && tg68_rw && cpu2mem)):1'b1);
//	(cpu_cycle?~(address_strobe && tg68_rw && cpu2mem):1'b1);

wire ram_wr = cpu_cycle?~(blitter_br?blitter_master_write:(address_strobe && ~tg68_rw && cpu2ram)):1'b1;

wire [15:0] ram_data_in = blitter_br?blitter_master_data_out:tg68_dat_out;

// data strobe
wire ram_uds = video_cycle?1'b0:(blitter_br?1'b0:tg68_uds);
wire ram_lds = video_cycle?1'b0:(blitter_br?1'b0:tg68_lds);
 
//// sdram ////
sdram sdram (
  .sdata        (SDRAM_DQ         ),
  .sdaddr       (SDRAM_A          ),
  .dqm          (sdram_dqm        ),
  .sd_cs        (sdram_cs         ),
  .ba           (SDRAM_BA         ),
  .sd_we        (SDRAM_nWE        ),
  .sd_ras       (SDRAM_nRAS       ),
  .sd_cas       (SDRAM_nCAS       ),
  .sysclk       (clk_128          ),
  .reset_in     (~init            ),
  
  .hostWR       (host_dataWR      ),
  .hostAddr     ({host_addr,1'b0} ),
  .hostState    (host_state       ),
  .hostL        (1'b0             ),
  .hostU        (1'b0             ),
  .hostRD       (host_dataRD      ),
  .hostena      (                 ),

  // fast ram interface
  .cpuWR        (tg68_dat_out     ),
  .cpuAddr      (tg68_cad[24:1]   ),
  .cpuU         (tg68_cuds        ),
  .cpuL         (tg68_clds        ),
  .cpustate     (tg68_cpustate    ),
  .cpu_dma      (tg68_cdma        ),
  .cpuRD        (tg68_cout        ),
  .cpuena       (tg68_cpuena      ),
  .enaRDreg     (                 ),
  .enaWRreg     (tg68_enaWR       ),
  .ena7RDreg    (tg68_ena7RD      ),
  .ena7WRreg    (tg68_ena7WR      ),

  // chip/slow ram interface
  .chipWR       (ram_data_in      ),
  .chipAddr     (ram_address      ),
  .chipU        (ram_uds          ),
  .chipL        (ram_lds          ),
  .chipRW       (ram_wr           ),
  .chip_dma     (ram_oe           ),
  .c_7m         (clk_8            ),
  .chipRD       (ram_data_out         ),

  .reset_out    (                 )
);

// multiplex spi_do, drive it from user_io if that's selected, drive
// it from minimig if it's selected and leave it open else (also
// to be able to monitor sd card data directly)
wire data_io_sdo;
wire user_io_sdo;

assign SPI_DO = (CONF_DATA0 == 1'b0)?user_io_sdo:
	((SPI_SS2 == 1'b0)?data_io_sdo:1'bZ);

wire [31:0] system_ctrl;

// connection to transfer ikbd data from io controller to acia
wire [7:0] ikbd_data_to_acia;
wire ikbd_strobe_to_acia;

// connection to transfer ikbd data from acia to io controller
wire [7:0] ikbd_data_from_acia;
wire ikbd_strobe_from_acia;
wire ikbd_data_from_acia_available;

// connection to transfer serial/rs232 data from mfp to io controller
wire [7:0] serial_data_from_mfp;
wire serial_strobe_from_mfp;
wire serial_data_from_mfp_available;

//// user io has an extra spi channel outside minimig core ////
user_io user_io(
		.SPI_CLK(SPI_SCK),
		.SPI_SS_IO(CONF_DATA0),
		.SPI_MISO(user_io_sdo),
		.SPI_MOSI(SPI_DI),
		.BUTTONS(buttons),
		
		// ikbd interface
      .ikbd_strobe_out(ikbd_strobe_from_acia),
      .ikbd_data_out(ikbd_data_from_acia),
      .ikbd_data_out_available(ikbd_data_from_acia_available),
      .ikbd_strobe_in(ikbd_strobe_to_acia),
      .ikbd_data_in(ikbd_data_to_acia),
		
		// serial/rs232 interface
      .serial_strobe_out(serial_strobe_from_mfp),
      .serial_data_out(serial_data_from_mfp),
      .serial_data_out_available(serial_data_from_mfp_available),
		
		.CORE_TYPE(8'ha3)    // mist core id
);

data_io data_io (
		// system control
		.clk_8 		(clk_8			),
		.reset		(init	   		),
		.bus_cycle  (bus_cycle[3:2]),
		.ctrl_out   (system_ctrl   ),

		// spi
		.sdi   		(SPI_DI			),
		.sck  		(SPI_SCK			),
		.ss    		(SPI_SS2			),
		.sdo			(data_io_sdo	),

		.video_adj	(video_adj		),
		
		// dma status interface
		.dma_idx    (dma_dio_idx   ),
		.dma_data   (dma_dio_data  ),
		.dma_ack    (dma_dio_ack   ),
		.br         (data_io_br    ),

		// ram interface
		.state 	 	(host_state		),
		.addr		 	(host_addr		),
		.data_out 	(host_dataWR	),
		.data_in  	(host_dataRD	)
);
  
			
endmodule

