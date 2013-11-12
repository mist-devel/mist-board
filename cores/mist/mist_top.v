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

wire ste = system_ctrl[23];
wire mste = system_ctrl[24];

wire video_read;
wire [22:0] video_address;
wire st_de, st_hs, st_vs;
wire [15:0] video_adj;

// on-board io
wire [1:0] buttons;

// generate dtack for all implemented peripherals
wire io_dtack = vreg_sel || mmu_sel || mfp_sel || mfp_iack || 
     acia_sel || psg_sel || dma_sel || auto_iack || blitter_sel || 
	  ste_joy_sel || ste_dma_snd_sel || mste_ctrl_sel || vme_sel; 

// the original tg68k did not contain working support for bus fault exceptions. While earlier
// TOS versions cope with that, TOS versions with blitter support need this to work as this is
// required to properly detect that a blitter is not present.
// a bus error is now generated once no dtack is seen for 63 clock cycles.
wire tg68_clr_berr;
wire tg68_berr = (dtack_timeout == 3'd7);
	
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

reg [2:0] dtack_timeout;
always @(posedge clk_8) begin
	if(reset || tg68_clr_berr) begin
		dtack_timeout <= 3'd0;
	end else begin
		if(cpu_cycle) begin
			// timeout only when cpu owns the bus and when
			// neither dtack nor another bus master are active
			if(dtack_timeout != 3'd7) begin
				if(!tg68_dtack || br || tg68_as)
					dtack_timeout <= 3'd0;
				else
					dtack_timeout <= dtack_timeout + 3'd1;
			end 
		end
	end
end
		
// no tristate busses exist inside the FPGA. so bus request doesn't do
// much more than halting the cpu by suppressing dtack
`define BRWIRE
`ifdef BRWIRE
wire br = data_io_br || blitter_br; // dma/blitter are only other bus masters
`else
reg br;
always @(negedge clk_8)
	if(video_cycle)
		br <= data_io_br || blitter_br;
`endif
	
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
// $fffffa40 - $fffffa7f  - FPU
// $fffffc20 - $fffffc3f  - RTC
// $ffff8e00 - $ffff8e0f  - VME  (only fake implementation)

wire io_sel = cpu_cycle && cpu2io && address_strobe ;
 
// mmu 8 bit interface at $ff8000 - $ff8001
wire mmu_sel  = io_sel && ({tg68_adr[15:1], 1'd0} == 16'h8000);
wire [7:0] mmu_data_out;

// mega ste cache controller 8 bit interface at $ff8e20 - $ff8e21
wire mste_ctrl_sel = mste & io_sel && ({tg68_adr[15:1], 1'd0} == 16'h8e20);
wire [7:0] mste_ctrl_data_out;

// vme controller 8 bit interface at $ffff8e00 - $ffff8e0f
// (requierd to enable Mega STE cpu speed/cache control)
wire vme_sel = mste & io_sel && ({tg68_adr[15:4], 4'd0} == 16'h8e00);

// video controller 16 bit interface at $ff8200 - $ff827f
wire vreg_sel = io_sel && ({tg68_adr[15:7], 7'd0} == 16'h8200);
wire [15:0] vreg_data_out;

// ste joystick 16 bit interface at $ff9200 - $ff923f
wire ste_joy_sel = ste && io_sel && ({tg68_adr[15:6], 6'd0} == 16'h9200);
wire [15:0] ste_joy_data_out;

// ste dma snd 8 bit interface at $ff8900 - $ff893f
wire ste_dma_snd_sel = ste && io_sel && ({tg68_adr[15:6], 6'd0} == 16'h8900);
wire [15:0] ste_dma_snd_data_out;

// mfp 8 bit interface at $fffa00 - $fffa3f
wire mfp_sel  = io_sel && ({tg68_adr[15:6], 6'd0} == 16'hfa00);
wire [7:0] mfp_data_out;

// acia 8 bit interface at $fffc00 - $fffc07
wire acia_sel = io_sel && ({tg68_adr[15:8], 8'd0} == 16'hfc00);
wire [7:0] acia_data_out;

// blitter 16 bit interface at $ff8a00 - $ff8a3f, STE always has a blitter
wire blitter_sel = (system_ctrl[19] || ste) && io_sel && ({tg68_adr[15:8], 8'd0} == 16'h8a00);
wire [15:0] blitter_data_out;

//  psg 8 bit interface at $ff8800 - $ff8803
wire psg_sel  = io_sel && ({tg68_adr[15:8], 8'd0} == 16'h8800);
wire [7:0] psg_data_out;

//  dma 16 bit interface at $ff8600 - $ff860f
wire dma_sel  = io_sel && ({tg68_adr[15:4], 4'd0} == 16'h8600);
wire [15:0] dma_data_out;

// de-multiplex the various io data output ports into one 
wire [7:0] io_data_out_8u = acia_data_out | psg_data_out;
wire [7:0] io_data_out_8l = mmu_data_out | mfp_data_out | auto_vector | mste_ctrl_data_out;
wire [15:0] io_data_out = vreg_data_out | dma_data_out | blitter_data_out | 
				ste_joy_data_out | ste_dma_snd_data_out |
				{8'h00, io_data_out_8l} | {io_data_out_8u, 8'h00};

wire init = ~pll_locked;

video video (
	.clk         	(clk_32        ),
   .clk27       	(CLOCK_27[0]),
	.bus_cycle   	(bus_cycle     ),
	
	// spi for OSD
   .sdi           (SPI_DI    	),
   .sck           (SPI_SCK   	),
   .ss            (SPI_SS3   	),

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

	// configuration signals
	.adjust     (video_adj    	),
	.pal56      (~system_ctrl[9]),
   .scanlines  (system_ctrl[21:20]),
	.ste			(ste				),
	
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

// mega ste cache/cpu clock controller
wire enable_16mhz;
mste_ctrl mste_ctrl (
	// cpu register interface
	.clk      (clk_8       ),
	.reset    (reset       ),
	.din      (tg68_dat_out[7:0]),
	.sel      (mste_ctrl_sel ),
	.ds       (tg68_lds    ),
	.rw       (tg68_rw     ),
	.dout     (mste_ctrl_data_out),
	
	.enable_cache (),
	.enable_16mhz (enable_16mhz)
);

wire acia_irq, dma_irq;

// the STE delays the xsirq by 1/250000 second before feeding it into timer_a
wire ste_dma_snd_xsirq, ste_dma_snd_xsirq_delayed;

// mfp io7 is mono_detect which in ste is xor'd with the dma sound irq
wire mfp_io7 = system_ctrl[8] ^ (ste?ste_dma_snd_xsirq:1'b0);

// input 0 is busy from printer port which has a pullup
// inputs 1,2 and 6 are inputs from serial which have pullups before an inverter
wire [7:0] mfp_gpio_in = {mfp_io7, 1'b0, !dma_irq, !acia_irq, !blitter_irq, 3'b001 };
wire [1:0] mfp_timer_in = {st_de, ste?ste_dma_snd_xsirq_delayed:1'b1};

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
	.clk_ext   (clk_mfp       ),  // 2.457MHz clock
	.t_i       (mfp_timer_in  ),  // timer a/b inputs
	.i         (mfp_gpio_in   )   // gpio-in
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
   
ste_joystick ste_joystick (
	.clk      (clk_8       ),
	.reset    (reset       ),
	.din      (tg68_dat_out),
	.sel      (ste_joy_sel ),
	.addr     (tg68_adr[5:1]),
	.uds      (tg68_uds    ),
	.lds      (tg68_lds    ),
	.rw       (tg68_rw     ),
	.dout     (ste_joy_data_out),
);

wire [22:0] ste_dma_snd_addr;
wire ste_dma_snd_read;
wire [7:0] ste_audio_out_l, ste_audio_out_r;

ste_dma_snd ste_dma_snd (
	// cpu interface
	.clk      	(clk_8       ),
	.reset    	(reset       ),
	.din      	(tg68_dat_out),
	.sel      	(ste_dma_snd_sel ),
	.addr     	(tg68_adr[5:1]),
	.uds      	(tg68_uds    ),
	.lds      	(tg68_lds    ),
	.rw       	(tg68_rw     ),
	.dout     	(ste_dma_snd_data_out),

	// memory interface
	.clk32	  	(clk_32      ),
	.bus_cycle 	(bus_cycle   ),
	.hsync		(st_hs       ),
	.saddr      (ste_dma_snd_addr ),
	.read       (ste_dma_snd_read ),
	.data       (ram_data_out  ),

	.audio_l    (ste_audio_out_l   ),
	.audio_r    (ste_audio_out_r	),

	.xsint     	(ste_dma_snd_xsirq ),
	.xsint_d   	(ste_dma_snd_xsirq_delayed )   // 4 usec delayed
);

// audio output processing

// simple mixer for ste and ym audio. result is 9 bits
// this will later be handled by the lmc1992
wire [8:0] audio_mix_l = { 1'b0, ym_audio_out_l} + { 1'b0, ste_audio_out_l };
wire [8:0] audio_mix_r = { 1'b0, ym_audio_out_r} + { 1'b0, ste_audio_out_r };

// limit audio to 8 bit range
wire [7:0] audio_out_l = audio_mix_l[8]?8'd255:audio_mix_l[7:0];
wire [7:0] audio_out_r = audio_mix_r[8]?8'd255:audio_mix_r[7:0];

sigma_delta_dac sigma_delta_dac_l (
	.DACout 		(AUDIO_L),
	.DACin		(audio_out_l),
	.CLK 			(clk_32),
	.RESET 		(reset)
);

sigma_delta_dac sigma_delta_dac_r (
	.DACout     (AUDIO_R),
	.DACin    	(audio_out_r),
	.CLK      	(clk_32),
	.RESET    	(reset)
);

//// ym2149 sound chip ////
reg [1:0] sclk;
always @ (posedge clk_8)
	sclk <= sclk + 2'd1;

wire [7:0] port_a_out;
assign floppy_side = port_a_out[0];
assign floppy_sel = port_a_out[2:1];

wire [7:0] ym_audio_out_l, ym_audio_out_r;

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

	.O_AUDIO_L           (ym_audio_out_l			),
	.O_AUDIO_R           (ym_audio_out_r			),

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
	.CLK                	( sclk[1]  					),	// 2 MHz
	.CLK8              	( clk_8  					)	// 8 MHz CPU bus clock
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

/* -------------------------------------------------------------------------- */
/* ------------------------------  TG68 CPU interface  ---------------------- */
/* -------------------------------------------------------------------------- */
	
reg [3:0] clkcnt;
reg trigger /* synthesis noprune*/;

// signal indicating that the cpu is making use of the current 8mhz cycle
// this means that the cpu owns the bus and either a normal bus cycle
// ends or a bus error has happened.
wire cpu_uses_8mhz_cycle = cpu_cycle && !br && (!tg68_dtack || tg68_berr || (tg68_busstate == 2'b01));
 
wire cpu_req_bus = !(tg68_busstate == 2'b01);

// the 128 Mhz cpu clock is gated by clkena. Since the CPU cannot run at full 128MHz
// speed a certain amount of idle cycles have to be inserted between two subsequent
// cpu clocks. This idle time is implemented using the cpu_throttle counter. The burst 
// counter indicates how many non memory using cpu steps may be performed faster than
// the 8/16 Mhz raster. Value 1 is closest to the speed of a real 68k
reg [3:0] cpu_throttle;
reg [3:0] burst;
 
reg clkena;
reg [15:0] cpu_data_in_R;

always @(posedge clk_128) begin
	// count 0..15 within a 8MHz cycle 
	if(((clkcnt == 15) && ( clk_8 == 0)) ||
		((clkcnt ==  0) && ( clk_8 == 1)) ||
		((clkcnt != 15) && (clkcnt != 0)))
			clkcnt <= clkcnt + 4'd1;

	// default: cpu does not run
	clkena <= 1'b0;
	trigger <= 1'b0;

	// only run cpu if throttle counter has run down
	if(cpu_throttle == 4'd0) begin

		// cpu does internal processing -> let it do this immediately
		
		// don't let this happen in the cpu cycle as this may result in a 
		// read/write state which suddenly happens right in the middle of
		// the ongoing cpu cycle
		if(tg68_busstate == 2'b01 && !cpu_cycle && (burst != 0)) begin	
			clkena <= 1'b1;
			cpu_throttle <= 4'd7;
			burst <= burst - 4'd1;
		end
		
		else
		// cpu does io -> force it to wait for end of its bus cycle
		begin
			// three cases:
			// cpu addresses ram (incl. rom) -> terminate transfer early
			// cpu addresses io -> terminate transfer after current cycle
			// ...

			// DEBUG: read data earlier
			if((clkcnt == 14) && cpu_cycle && tg68_rw && !tg68_as && !br)
				cpu_data_in_R <= cpu_data_in;
			
			if(clkcnt == 15) begin	
				if(cpu_cycle && tg68_rw && !tg68_as && !br) begin
					// DEBUG: and notify if it has changed (which it shouldn't)
					if(cpu_data_in_R != cpu_data_in) trigger <= 1'b1;
					
					cpu_data_in_R <= cpu_data_in;
				end

				if(cpu_uses_8mhz_cycle) begin
					clkena <= 1'b1;
					cpu_throttle <= 4'd7;
					burst <= 4'd1;  // allow for one subsequent cpu internal step
				end
			end
		end		
	end else
		cpu_throttle <= cpu_throttle - 4'd1;
end

wire [1:0] tg68_busstate;

wire address_strobe = cpu_cycle && !tg68_as && !br;
// assign tg68_as = ~(!tg68_uds || !tg68_lds);
assign tg68_as = ~(tg68_busstate != 2'b01);

TG68KdotC_Kernel tg68k (
//TG68KdotC_Kernel #(2,2,2,2,2,2) tg68k (
	.clk          	(clk_128 		),
	.nReset       	(~reset			),
	.clkena_in		(clkena			), 
	.data_in       (cpu_data_in_R	),
	.IPL				(ipl           ),
	.IPL_autovector (1'b0         ),
	.berr         	(tg68_berr     ),
	.clr_berr     	(tg68_clr_berr ),
	.CPU           (system_ctrl[5:4] ),  // 00=68000
   .addr         	(tg68_adr      ),
	.data_write   	(tg68_dat_out  ),
	.nUDS          (tg68_uds      ),
	.nLDS          (tg68_lds      ),
	.nWr           (tg68_rw       ),
	.busstate	 	(tg68_busstate ), // 00-> fetch code 10->read data 11->write data 01->no memaccess
	.nResetOut	   (              ),
	.FC            (              )
);

/* ------------------------------------------------------------------------------ */
/* ----------------------------- memory area mapping ---------------------------- */
/* ------------------------------------------------------------------------------ */

wire MEM512K = (system_ctrl[3:1] == 3'd0);
wire MEM1M   = (system_ctrl[3:1] == 3'd1);
wire MEM2M   = (system_ctrl[3:1] == 3'd2);
wire MEM4M   = (system_ctrl[3:1] == 3'd3);
wire MEM8M   = (system_ctrl[3:1] == 3'd4);
wire MEM14M  = (system_ctrl[3:1] == 3'd5);

// rom is also at 0x000000 to 0x000007
wire cpu2lowrom = (tg68_adr[23:3] == 21'd0);
 
// ram from 0x000000 to 0x400000
wire cpu2ram = (!cpu2lowrom) && (
								  (tg68_adr[23:22] == 2'b00) ||   // ordinary 4MB
	((MEM14M || MEM8M) &&  (tg68_adr[23:22] == 2'b01)) ||  // 8MB 
	(MEM14M            && ((tg68_adr[23:22] == 2'b10) ||   // 12MB
	                       (tg68_adr[23:21] == 3'b110)))); // 14MB 

wire cpu2ram14 = (!cpu2lowrom) && (
                 (tg68_adr[23:22] == 2'b00) ||  // ordinary 4MB
					  (tg68_adr[23:22] == 2'b01) ||  // 8MB 
					  (tg68_adr[23:22] == 2'b10) ||  // 12MB
	              (tg68_adr[23:21] == 3'b110));  // 14MB 

// 256k tos from 0xe00000 to 0xe40000
wire cpu2tos256k = (tg68_adr[23:18] == 6'b111000) || 
							cpu2lowrom;

// 192k tos from 0xfc0000 to 0xff0000
wire cpu2tos192k = (tg68_adr[23:17] == 7'b1111110)  || 
		 				 (tg68_adr[23:16] == 8'b11111110) || 
							cpu2lowrom;

// 128k cartridge from 0xfa0000 to 0xfbffff
wire cpu2cart = ({tg68_adr[23:17], 1'b0} == 8'hfa);

// cpu to any type of mem (rw on ram, read on rom)
wire cpu2mem = cpu2ram14 || (tg68_rw && (cpu2tos192k || cpu2tos256k || cpu2cart));
							
// io from 0xff0000
wire cpu2io = (tg68_adr[23:16] == 8'hff);

// irq ack happens on 0xfffffX
wire cpu2iack = (tg68_adr[23:4] == 20'hfffff);


// generate dtack (for st ram only and rom, no dtack for rom write)
assign tg68_dtack = ~(((cpu2mem && address_strobe) || io_dtack ) && !br);

/* ------------------------------------------------------------------------------ */
/* ------------------------------- bus multiplexer ------------------------------ */
/* ------------------------------------------------------------------------------ */

// singnal indicating if cpu should use a second cpu slot for 16Mhz like operation
wire second_cpu_slot = mste && enable_16mhz;

// Two of the four cycles are being used. One for video (+STE audio) and one for
// cpu, DMA and Blitter. A third is optionally being used for faster CPU
wire video_cycle = (bus_cycle[3:2] == 0);
wire cpu_cycle = (bus_cycle[3:2] == 1) || (second_cpu_slot && (bus_cycle[3:2] == 3));

// ----------------- RAM address --------------
wire [22:0] video_cycle_addr = (st_hs&&ste)?ste_dma_snd_addr:video_address;
wire [22:0] cpu_cycle_addr = data_io_br?data_io_addr:(blitter_br?blitter_master_addr:tg68_adr[23:1]);
wire [22:0] ram_address = video_cycle?video_cycle_addr:cpu_cycle_addr;

// ----------------- RAM read -----------------
// memory access during the video cycle is shared between video and ste_dma_snd
wire video_cycle_oe = (st_hs && ste)?ste_dma_snd_read:video_read;
// memory access during the cpu cycle is shared between blitter and cpu
wire cpu_cycle_oe = data_io_br?data_io_read:(blitter_br?blitter_master_read:(address_strobe && tg68_rw && cpu2mem));
wire ram_oe = video_cycle?video_cycle_oe:(cpu_cycle?cpu_cycle_oe:1'b0);

// ----------------- RAM write -----------------
wire video_cycle_wr = 1'b0;
wire cpu_cycle_wr = data_io_br?data_io_write:(blitter_br?blitter_master_write:(address_strobe && ~tg68_rw && cpu2ram));
wire ram_wr = video_cycle?video_cycle_wr:(cpu_cycle?cpu_cycle_wr:1'b0);

wire [15:0] ram_data_out;
wire [15:0] cpu_data_in = cpu2mem?ram_data_out:io_data_out;
wire [15:0] ram_data_in = data_io_br?data_io_dout:(blitter_br?blitter_master_data_out:tg68_dat_out);

// data strobe
wire ram_uds = video_cycle?1'b1:((blitter_br||data_io_br)?1'b1:~tg68_uds);
wire ram_lds = video_cycle?1'b1:((blitter_br||data_io_br)?1'b1:~tg68_lds);
 
assign SDRAM_CKE         = 1'b1;

sdram sdram (
	// interface to the MT48LC16M16 chip
	.sd_data     	( SDRAM_DQ                 ),
	.sd_addr     	( SDRAM_A                  ),
	.sd_dqm      	( {SDRAM_DQMH, SDRAM_DQML} ),
	.sd_cs       	( SDRAM_nCS                ),
	.sd_ba       	( SDRAM_BA                 ),
	.sd_we       	( SDRAM_nWE                ),
	.sd_ras      	( SDRAM_nRAS               ),
	.sd_cas      	( SDRAM_nCAS               ),

	// system interface
	.clk_128      	( clk_128          			),
	.clk_8        	( clk_8            			),
	.init         	( init             			),

	// cpu/chipset interface
	.din       		( ram_data_in      			),
	.addr     		( { 1'b0, ram_address } 	),
	.ds        		( { ram_uds, ram_lds } 		),
	.we       		( ram_wr           			),
	.oe         	( ram_oe           			),
	.dout       	( ram_data_out     			),
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

wire [22:0] data_io_addr;
wire [15:0] data_io_dout;
wire data_io_write, data_io_read;
wire data_io_br;

data_io data_io (
		// system control
		.clk_8 		(clk_8			),
		.reset		(init          ),
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
		.read 	 	(data_io_read	),
		.write 	 	(data_io_write	),
		.addr		 	(data_io_addr	),
		.data_out 	(data_io_dout 	),
		.data_in  	(ram_data_out	)
);
  
			
endmodule

