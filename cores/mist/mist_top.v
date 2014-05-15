/********************************************/
/*                                          */
/********************************************/

module mist_top ( 
  // clock inputsxque	
  input wire [ 2-1:0] 	CLOCK_27, // 27 MHz
  // LED outputs
  output wire 		LED, // LED Yellow
  // UART
  output wire 		UART_TX, // UART Transmitter (MIDI out)
  input wire 		UART_RX, // UART Receiver (MIDI in)
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

// enable additional ste/megaste features
wire ste = system_ctrl[23] || system_ctrl[24];
wire mste = system_ctrl[24];
wire steroids = system_ctrl[23] && system_ctrl[24];  // a STE on steroids

// ethernec is enabled by the io controller whenever a USB 
// ethernet interface is detected
wire ethernec_present = system_ctrl[25];

// usb target port on io controller is used for redirection of
// 0=nothing 1=rs232 2=printer 3=midi
wire [1:0] usb_redirection = system_ctrl[27:26];

wire video_read;
wire [22:0] video_address;
wire st_de, st_hs, st_vs;
wire [15:0] video_adj;

// generate dtack for all implemented peripherals
wire io_dtack = vreg_sel || mmu_sel || mfp_sel || mfp_iack || 
     acia_sel || psg_sel || dma_sel || auto_iack || blitter_sel || 
	  ste_joy_sel || ste_dma_snd_sel || mste_ctrl_sel || vme_sel || 
	  rom_sel[1] || rom_sel[0]; 

// the original tg68k did not contain working support for bus fault exceptions. While earlier
// TOS versions cope with that, TOS versions with blitter support need this to work as this is
// required to properly detect that a blitter is not present.
// a bus error is now generated once no dtack is seen for 63 clock cycles.
wire tg68_clr_berr;
wire tg68_berr = (dtack_timeout == 4'd15);
	
// count bus errors for debugging purposes. we can thus trigger for a
// certain bus error
reg [3:0] berr_cnt_out /* synthesis noprune */;
reg [3:0] berr_cnt;
reg berrD;
always @(negedge clk_8) begin
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

reg bus_ok, cpu_cycle_L;
always @(negedge clk_8) begin
	// bus error if cpu owns bus, but no dtack, nor ram access,
	// nor fast cpu cycle nor cpu does internsal processing
	bus_ok <= tg68_dtack || br || cpu2mem || (tg68_busstate == 2'b01);
	cpu_cycle_L <= cpu_cycle;
end

reg berr_reset;
always @(negedge clk_32) begin
	if(reset)
		berr_reset <= 1'b1;
	else if(clkenaD)
		berr_reset <= tg68_clr_berr;
end

reg [3:0] dtack_timeout;
always @(posedge clk_32 or posedge berr_reset) begin
//	if(reset || tg68_clr_berr) begin
	if(berr_reset) begin
		dtack_timeout <= 4'd0;
	end else begin
		if(cpu_cycle_L) begin
			// timeout only when cpu owns the bus and when
			// neither dtack nor another bus master are active
			
			// also ram areas should never generate a
			// bus error for reading. But rom does for writing
			if(dtack_timeout != 4'd15) begin
				if(bus_ok)
					dtack_timeout <= 4'd0;
				else if(clkcnt == 3) // increase timout at the end of the cpu cycle
					dtack_timeout <= dtack_timeout + 4'd1;
			end 
		end
	end 
end
 
// no tristate busses exist inside the FPGA. so bus request doesn't do
// much more than halting the cpu by suppressing dtack
wire br = data_io_br || blitter_br; // dma/blitter are only other bus masters

// request interrupt ack from mfp for IPL == 6
wire mfp_iack = cpu_cycle && cpu2iack && tg68_as && (tg68_adr[3:1] == 3'b110);

// the tg68k core doesn't reliably support mixed usage of autovector and non-autovector
// interrupts.
// For the atari we've fixed the non-autovector support inside the kernel and switched
// entirely to non-autovector interrupts. This means that we now have to provide
// the vectors for those interrupts that oin the ST are autovector ones. This needs
// to be done for IPL2 (hbi) and IPL4 (vbi)
wire auto_iack = cpu_cycle && cpu2iack && tg68_as &&
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

wire io_sel = cpu_cycle && cpu2io && tg68_as ;

// romport interface at $fa0000 - $fbffff
wire rom_sel_all = ethernec_present && cpu_cycle && tg68_as && tg68_rw && ({tg68_adr[23:17], 1'b0} == 8'hfa);
wire [1:0] rom_sel = { rom_sel_all && tg68_adr[16], rom_sel_all && !tg68_adr[16] };
wire [15:0] rom_data_out;

// mmu 8 bit interface at $ff8000 - $ff8001
wire mmu_sel  = io_sel && ({tg68_adr[15:1], 1'd0} == 16'h8000);
wire [7:0] mmu_data_out;

// mega ste cache controller 8 bit interface at $ff8e20 - $ff8e21
// STEroids mode does not have this config, it always runs full throttle
wire mste_ctrl_sel = !steroids && mste && io_sel && ({tg68_adr[15:1], 1'd0} == 16'h8e20);
wire [7:0] mste_ctrl_data_out;

// vme controller 8 bit interface at $ffff8e00 - $ffff8e0f
// (requierd to enable Mega STE cpu speed/cache control)
wire vme_sel = !steroids && mste && io_sel && ({tg68_adr[15:4], 4'd0} == 16'h8e00);

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
				ste_joy_data_out | ste_dma_snd_data_out | rom_data_out |
				{8'h00, io_data_out_8l} | {io_data_out_8u, 8'h00};

wire init = ~pll_locked;

/* -------------------------- Viking video card -------------------- */

// viking/sm194 is enabled and max 8MB memory may be enabled. In steroids mode
// video memory is moved to $e80000 and all stram up to 14MB may be used
wire viking_mem_ok = MEM512K || MEM1M || MEM2M || MEM4M || MEM8M;
wire viking_enable = (system_ctrl[28] && viking_mem_ok) || steroids;

// check for cpu access to 0xcxxxxx with viking enabled to switch video
// output once the driver loads. 256 accesses to the viking memory range
// are considered a valid sign that the driver is working. Without driver
// others may also probe that area which is why we want to see 256 accesses
reg [7:0] viking_in_use;

always @(posedge clk_32) begin
	if(peripheral_reset)
		viking_in_use <= 8'h00;
	else
		// cpu writes to $c0xxxx or $e80000
		if(clkena && !br && (tg68_busstate == 2'b11) && viking_enable && 
			(tg68_adr[23:18] == (steroids?6'b111010:6'b110000)) && (viking_in_use != 8'hff))
			viking_in_use <= viking_in_use + 8'h01;
end

// video output multiplexer to switch between shifter and viking
wire viking_active = (viking_in_use == 8'hff) && !osd_enable;
assign VGA_HS = viking_active?viking_hs:shifter_hs;
assign VGA_VS = viking_active?viking_vs:shifter_vs;
assign VGA_R = viking_active?viking_r:shifter_r;
assign VGA_G = viking_active?viking_g:shifter_g;
assign VGA_B = viking_active?viking_b:shifter_b;

wire viking_hs, viking_vs;
wire [5:0] viking_r, viking_g, viking_b;

wire [22:0] viking_address;
wire viking_read;

viking viking (
	.pclk         	(clk_128    ),    // pixel 
	.bus_cycle   	(bus_cycle  ),
	
	// memory interface
	.himem		(steroids      ),
	.bclk      	(clk_8      	),    // system bus clock = 8Mhz
   .addr       (viking_address ),
	.data       (ram_data_out_64),
	.read       (viking_read    ),

	// video output 
	.hs		(viking_hs			),
	.vs		(viking_vs			),
	.r    	(viking_r        	),
	.g    	(viking_g       	),
	.b    	(viking_b        	)
);

wire osd_enable;
wire shifter_hs, shifter_vs;
wire [5:0] shifter_r, shifter_g, shifter_b;

video video (
	.clk         	(clk_32     ),
   .clk27       	(CLOCK_27[0]),
	.bus_cycle   	(bus_cycle  ),
	
	// spi for OSD
   .sdi           (SPI_DI    	),
   .sck           (SPI_SCK   	),
   .ss            (SPI_SS3   	),
	.osd_enable    (osd_enable ),

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
	.data       (ram_data_out_64),
	.read       (video_read    ),
	
	.hs			(shifter_hs		),
	.vs			(shifter_vs		),
	.video_r    (shifter_r    	),
	.video_g    (shifter_g    	),
	.video_b    (shifter_b    	),

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

// input 0 is busy from printer which is pulled up when the printer cannot accept further data
// if no printer redirection is being used this is wired to the extra joystick ports provided
// by the "gauntlet2 adapter". If no extra joystick ports are present this will return 1
wire mfp_io0 = (usb_redirection == 2'd2)?parallel_fifo_full:~joy0[4];

// inputs 1,2 and 6 are inputs from serial which have pullups before an inverter
wire [7:0] mfp_gpio_in = {mfp_io7, 1'b0, !dma_irq, !acia_irq, !blitter_irq, 2'b00, mfp_io0};
wire [1:0] mfp_timer_in = {st_de, ste?ste_dma_snd_xsirq_delayed:parallel_fifo_full};

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

	// the midi irq hack is only enabled if usb redirection is set to midi
	.midi_irq_hack (usb_redirection == 3'd3),
	
	// serial/rs232 interface io-controller<->mfp
	.serial_data_out_available 	(serial_data_from_mfp_available),
	.serial_strobe_out 				(serial_strobe_from_mfp),
	.serial_data_out 	   			(serial_data_from_mfp),
	.serial_strobe_in 				(serial_strobe_to_mfp),
	.serial_data_in 	   			(serial_data_to_mfp),

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
	
	// physical MIDI interface
	.midi_out (UART_TX      ),
	.midi_in  (UART_RX      ),
	 
	// ikbd interface
	.ikbd_data_out_available 	(ikbd_data_from_acia_available),
	.ikbd_strobe_out 				(ikbd_strobe_from_acia),
	.ikbd_data_out 	   		(ikbd_data_from_acia),
	.ikbd_strobe_in 				(ikbd_strobe_to_acia),
	.ikbd_data_in 	   			(ikbd_data_to_acia),

	// redirected midi interface
	.midi_data_out_available 	(midi_data_from_acia_available),
	.midi_strobe_out 				(midi_strobe_from_acia),
	.midi_data_out 	   		(midi_data_from_acia)
);

wire [23:1] blitter_master_addr;
wire blitter_master_write;
wire blitter_master_read;
wire blitter_irq;
wire blitter_br;
wire [15:0] blitter_master_data_out;

reg blitter_bg;

// give bus to blitter
always @(posedge clk_8) begin
	blitter_bg <= blitter_br;
end

blitter blitter (
	.bus_cycle 	(bus_cycle        ),

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
	.bg        (blitter_bg       ),
	.irq       (blitter_irq      ),
	
	.turbo     (steroids         )
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
	.dout     (ste_joy_data_out)
);

ethernec ethernec (
	.clk        (clk_8       ),
	.sel        (rom_sel     ),
	.addr       (tg68_adr[15:1]),
	.dout       (rom_data_out),
	
	.status     (eth_status),
	
	.mac_begin  (eth_mac_begin),
	.mac_strobe (eth_mac_strobe),
	.mac_byte   (eth_mac_byte),
	
	.tx_begin   (eth_tx_read_begin),
	.tx_strobe  (eth_tx_read_strobe),
	.tx_byte    (eth_tx_read_byte),
	
	.rx_begin   (eth_rx_write_begin),
	.rx_strobe  (eth_rx_write_strobe),
	.rx_byte    (eth_rx_write_byte)
);

wire [22:0] ste_dma_snd_addr;
wire ste_dma_snd_read;
wire [7:0] ste_audio_out_l, ste_audio_out_r;

ste_dma_snd ste_dma_snd (
	// cpu interface
	.clk      	(clk_8             ),
	.reset    	(reset             ),
	.din      	(tg68_dat_out      ),
	.sel      	(ste_dma_snd_sel   ),
	.addr     	(tg68_adr[5:1]     ),
	.uds      	(tg68_uds          ),
	.lds      	(tg68_lds          ),
	.rw       	(tg68_rw           ),
	.dout     	(ste_dma_snd_data_out),

	// memory interface
	.clk32	  	(clk_32            ),
	.bus_cycle 	(bus_cycle         ),
	.hsync		(st_hs             ),
	.saddr      (ste_dma_snd_addr  ),
	.read       (ste_dma_snd_read  ),
	.data       (ram_data_out_64   ),

	.audio_l    (ste_audio_out_l   ),
	.audio_r    (ste_audio_out_r	 ),

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

wire parallel_fifo_full;

// ------ fifo to store printer data coming from psg ---------
io_fifo #(.DEPTH(4)) parallel_out_fifo (
	.reset 				(reset),		

	.in_clk  			(clk_8),
	.in 					(port_b_out),
	.in_strobe 			(port_a_out[5]),
	.in_enable		 	(1'b0),

	.out_clk  			(clk_8),
	.out 					(parallel_data_out),
	.out_strobe 		(parallel_strobe_out),
	.out_enable		 	(1'b0),

	.full					(parallel_fifo_full),
	.data_available 	(parallel_data_out_available)
);

reg [1:0] sclk;
always @ (posedge clk_8)
	sclk <= sclk + 2'd1;

wire [7:0] port_a_out;
wire [7:0] port_b_out;
assign floppy_side = port_a_out[0];
assign floppy_sel = port_a_out[2:1];

wire [7:0] ym_audio_out_l, ym_audio_out_r;

// extra joysticks are wired to the printer port
// using the "gauntlet2 interface", fire of 
// joystick 0 is connected to the mfp I0 (busy)
wire [7:0] port_b_in = { ~joy0[0], ~joy0[1], ~joy0[2], ~joy0[3], 
								 ~joy1[0], ~joy1[1], ~joy1[2], ~joy1[3]}; 
wire [7:0] port_a_in = { 2'b11, ~joy1[4], 5'b11111 }; 

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
	.I_IOA           		( port_a_in 				),
	.O_IOA              	( port_a_out				),
	.O_IOA_OE_L      		(								),

	// port b
	.I_IOB               ( port_b_in					),
	.O_IOB              	( port_b_out				),
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
reg [3:0] clk_cnt;
reg [1:0] bus_cycle;

always @ (posedge clk_32, negedge pll_locked) begin
	if (!pll_locked) begin
		clk_cnt <= #1 4'b0010;
		bus_cycle <= 2'd0;
	end else begin 
		clk_cnt <=  #1 clk_cnt + 4'd1;
		if(clk_cnt[1:0] == 2'd1) begin
			bus_cycle <= bus_cycle + 2'd1;
		end
	end
end

assign clk_8 = clk_cnt[1];

// bus cycle counter for debugging
reg [31:0] cycle_counter /* synthesis noprune */;
always @ (posedge clk_8) begin
	if(reset)
		cycle_counter <= 32'd0;
	else
		cycle_counter <= cycle_counter + 32'd1;
end

 
// tg68 bus interface. These are the signals which are latched
// for the 8MHz bus.
wire [15:0] tg68_dat_in;
reg [15:0] tg68_dat_out;
reg [31:0] tg68_adr;
wire [2:0] tg68_IPL;
wire       tg68_dtack;
reg        tg68_uds;
reg        tg68_lds;
reg        tg68_rw;
reg [2:0]  tg68_fc;

wire reset = system_ctrl[0];

// ------------- generate VBI (IPL = 4) --------------
reg vsD, vsD2, vbi;
wire vbi_ack = cpu2iack && cpu_cycle && tg68_as && (tg68_adr[3:1] == 3'b100);

always @(negedge clk_8) begin
	vsD <= st_vs;
	vsD2 <= vsD;           // delay by one

	if(reset || vbi_ack)
		vbi <= 1'b0;
	else if(vsD && !vsD2)
		vbi <= 1'b1;
end

// ------------- generate HBI (IPL = 2) --------------
reg hsD, hsD2, hbi;
wire hbi_ack = cpu2iack && cpu_cycle && tg68_as && (tg68_adr[3:1] == 3'b010);

always @(negedge clk_8) begin
	hsD <= st_hs;
	hsD2 <= hsD;           // delay by one

	if(reset || hbi_ack)
		hbi <= 1'b0;
	else if(hsD && !hsD2)
		hbi <= 1'b1;
end

wire mfp_irq;

reg [2:0] ipl;
always @(posedge clk_128) begin
	if(reset)
		ipl <= 3'b111;
 else begin
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
	 
reg clkena;
reg iCacheStore;
reg dCacheStore;
reg cacheUpdate;
reg cacheRead;
reg cpuDoes8MhzCycle;

// latch 68k signals before each 8mhz cycle to meet 8Mhz timing
// requirements
wire [15:0] tg68_dat_out_S;
wire [31:0] tg68_adr_S;
wire [2:0]  tg68_fc_S;
wire        tg68_uds_S;
wire        tg68_lds_S;
wire        tg68_rw_S;

reg         tg68_as;

// the tg68 can itself generate a reset signal
wire tg68_reset;  
wire peripheral_reset = reset || !tg68_reset;

// 32MHz counter running synchronous to the 8Mhz clock. This is used to
// synchronize the 32MHz cpu to the 8MHz system bus
reg [1:0] clkcnt;
always @(posedge clk_32) begin
	// count 0..3 within a 8MHz cycle 
	if(((clkcnt == 3) && ( clk_8 == 0)) ||
		((clkcnt == 0) && ( clk_8 == 1)) ||
		((clkcnt != 3) && (clkcnt != 0)))
			clkcnt <= clkcnt + 2'd1;
end

// generate signal indicating the CPU may run from cache (cpu is active, 
// performs a read and the caches are able to provide the requested data)
wire cacheReady = steroids && cache_hit;

// a clkena delayed by 180 deg is being used to 
// read from the cache
reg clkenaD;
always @(posedge clk_32)
	clkenaD <= clkena;

// the TG68 core works on the rising clock edge. We thus prepare everything
// on the falling clock edge
always @(negedge clk_32) begin
	// default: cpu does not run
	clkena <= 1'b0;
	iCacheStore <= 1'b0;
	dCacheStore <= 1'b0;
	cacheUpdate <= 1'b0;
	 
	if(br || reset)
		tg68_as <= 1'b0; 

	// run cpu if it owns the bus
	if(!reset && !br) begin
	
		if(clkcnt == 3) begin
			// 8Mhz cycle must not start directly after the cpu has been clocked
			// as the address may not be stable then

			// cpuDoes8MhzCycle has same timing as tg68_as
			if(tg68_busstate != 2'b01) cpuDoes8MhzCycle <= 1'b1; 

			// tg68 core does not provide a as signal, so we generate it
			tg68_as <= (tg68_busstate != 2'b01); 

			// writes are always full 8 Mhz cycles, reads only if caches cannot provide
			// the required data
	
			// all other output signals are simply latched to make sure
			// they don't change within a 8Mhz cycle even if the CPU
			// advances. This would be a problem if e.g. The CPU would try
			// to start a bus cycle while the 8Mhz cycle is in progress
			tg68_dat_out <= tg68_dat_out_S;
			tg68_adr <= tg68_adr_S;
			tg68_uds <= tg68_uds_S;
			tg68_lds <= tg68_lds_S;
			tg68_rw <= tg68_rw_S;
			tg68_fc <= tg68_fc_S;	
		end

		cacheRead <= cacheReady;

		// cpu does internal processing -> let it do this immediately
		// or cpu wants to read and the requested data is available from the cache -> run immediately
		if((tg68_busstate == 2'b01) || ((tg68_busstate[0] == 1'b0) && cacheReady)) begin
			clkena <= 1'b1; 
			cpuDoes8MhzCycle <= 1'b0;
		end else 
		
		begin
			// this ends a normal 8MHz bus cycle. This requires that the 
			// cpu/chipset had the entire cycle and not e.g. started just in
			// the middle. This is verified using the cpuDoes8MhzCycle signal
			// which is invalidated whenever the cpu uses a internal cycle or 
			// runs from cache
 
			// clkcnt == 14 -> clkena in cycle 15 -> cpu runs in cycle 15
			if((clkcnt == 3) && cpuDoes8MhzCycle && cpu_cycle && (tg68_dtack || tg68_berr)) begin
				clkena <= 1'b1;
				cpuDoes8MhzCycle <= 1'b0;
											
				if(cacheable && tg68_dtack) begin
					case(tg68_busstate)
						0: iCacheStore <= 1'b1;  // store data in instruction cache on cpu instruction read
						2: dCacheStore <= 1'b1;  // store data in data cache on cpu data read
						3: cacheUpdate <= 1'b1;  // update cache on data write
					endcase
				end
			end
		end		
	end
end

// TODO: generate cacheUpdate from ram_wr, so other bus masters also trigger this
// same goes for cache lds/uds and the address used for update16 !!!!

wire [1:0] tg68_busstate;

// feed data from cache into the cpu
wire [15:0] cache_data_out = data_cache_hit?data_cache_data_out:inst_cache_data_out;
wire [15:0] cpu_data_in = cacheRead?cache_data_out:system_data_out;


TG68KdotC_Kernel #(2,2,2,2,2,2) tg68k (
	.clk          	(clk_32 			),
	.nReset       	(~reset			),
	.clkena_in		(clkena			), 
	.data_in       (cpu_data_in	),
	.IPL				(ipl           ),
	.IPL_autovector(1'b0          ),
	.berr         	(tg68_berr     ),
	.clr_berr     	(tg68_clr_berr ),
	.CPU           (system_ctrl[5:4] ),  // 00=68000
   .addr         	(tg68_adr_S    ),
	.data_write   	(tg68_dat_out_S),
	.nUDS          (tg68_uds_S    ),
	.nLDS          (tg68_lds_S    ),
	.nWr           (tg68_rw_S     ),
	.busstate	 	(tg68_busstate ), // 00-> fetch code 10->read data 11->write data 01->no memaccess
	.nResetOut	   (tg68_reset    ),
	.FC            (tg68_fc_S     )
);

/* ------------------------------------------------------------------------------ */
/* ---------------------------------- cpu cache --------------------------------- */
/* ------------------------------------------------------------------------------ */

wire cache_hit = cacheable && (data_cache_hit || inst_cache_hit);
 
// Any type of memory that may use a cache. Since it's a pure read cache we don't
// have to differentiate between ram and rom. Cartridge is not cached since me might
// attach dongles there someday
wire cacheable = ((tg68_adr_S[23:22] == 2'b00) ||       // ordinary 4MB
					   (tg68_adr_S[23:22] == 2'b01) ||       // 8MB 
					   (tg68_adr_S[23:22] == 2'b10) ||       // 12MB
	               (tg68_adr_S[23:21] == 3'b110) ||      // 14MB 
						(tg68_adr_S[23:18] == 6'b111000) ||   // 256k TOS
						(tg68_adr_S[23:17] == 7'b1111110) ||  // first 128k of 192k TOS
		 				(tg68_adr_S[23:16] == 8'b11111110) ); // second 64k of 192k TOS
					   
wire data_cache_hit;
wire [15:0] data_cache_data_out;

cache data_cache (
	.clk_128  		( clk_128					),
	.clk_8    		( clk_8						),
	.reset 			( reset						), 
	.flush			( br							), 

	// use the tg68_*_S signals here to quickly react on cpu requests
	.strobe        ( clkenaD               ),
	.addr     		( tg68_adr_S[23:1]		),
	.ds        		( { ~tg68_lds_S, ~tg68_uds_S } ),

	// the interface to the cpus read interface is pretty simple
	.hit				( data_cache_hit 			),
	.dout				( data_cache_data_out	),

	// interface to update entire cache lines on ram read
	.store         ( dCacheStore				),
	.din64         ( ram_data_out_64       ),
	
	// this is a write through cache. Thus the cpus write access to ram
	// is not intercepted but only used to update matching cache lines
	.update        ( cacheUpdate           ),
	.din16         ( ram_data_in           )
);

wire inst_cache_hit;
wire [15:0] inst_cache_data_out;

cache instruction_cache (
	.clk_128  		( clk_128					),
	.clk_8    		( clk_8						),
	.reset 			( reset						), 
	.flush			( br							), 

	// use the tg68_*_S signals here to quickly react on cpu requests
	.strobe        ( clkenaD               ),
	.addr     		( tg68_adr_S[23:1]		),
	.ds        		( { ~tg68_lds_S, ~tg68_uds_S } ),

	// the interface to the cpus read interface is pretty simple
	.hit				( inst_cache_hit 			),
	.dout				( inst_cache_data_out	),

	// interface to update entire cache lines on ram read
	.store         ( iCacheStore				),
	.din64         ( ram_data_out_64       ),
	
	// this is a write through cache. Thus the cpus write access to ram
	// is not intercepted but only used to update matching cache lines
	.update        ( cacheUpdate           ),
	.din16         ( ram_data_in           )
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

// ordinary ram from 0x000000 to 0x400000, more if enabled
wire cpu2ram = (!cpu2lowrom) && (
								  (tg68_adr[23:22] == 2'b00)     ||  // ordinary 4MB
	((MEM14M || MEM8M) &&  (tg68_adr[23:22] == 2'b01))    ||  // 8MB 
	(MEM14M            && ((tg68_adr[23:22] == 2'b10)     ||  // 12MB
	                       (tg68_adr[23:21] == 3'b110)))  ||  // 14MB
	(steroids          &&  (tg68_adr[23:19] == 5'b11101)) ||  // 512k at $e80000 for STEroids
	(viking_enable     &&  (tg68_adr[23:18] == 6'b110000))    // 256k at 0xc00000 for viking card
);

// 256k tos from 0xe00000 to 0xe40000
wire cpu2tos256k = (tg68_adr[23:18] == 6'b111000);

// 192k tos from 0xfc0000 to 0xff0000
wire cpu2tos192k = (tg68_adr[23:17] == 7'b1111110)  || 
		 				 (tg68_adr[23:16] == 8'b11111110);

// 128k cartridge from 0xfa0000 to 0xfbffff
wire cpu2cart = ({tg68_adr[23:17], 1'b0} == 8'hfa) && !ethernec_present;

// all rom areas
wire cpu2rom = cpu2lowrom || cpu2tos192k || cpu2tos256k || cpu2cart;
	 
// cpu to any type of mem (rw on ram, read on rom)
wire cpu2mem = cpu2ram || (tg68_rw && cpu2rom);
							
// io from 0xff0000
wire cpu2io = (tg68_adr[23:16] == 8'hff);

// irq ack happens
wire cpu2iack = (tg68_fc == 3'b111);
					  
// generate dtack (for st ram and rom on read, no dtack for rom write)
assign tg68_dtack = ((cpu2mem && cpu_cycle && tg68_as) || io_dtack ) && !br;

/* ------------------------------------------------------------------------------ */
/* ------------------------------- bus multiplexer ------------------------------ */
/* ------------------------------------------------------------------------------ */

// singnal indicating if cpu should use a second cpu slot for 16Mhz like operation
// steroids (STEroid) always runs at max speed
wire second_cpu_slot = (mste && enable_16mhz) || steroids;

// Two of the four cycles are being used. One for video (+STE audio) and one for
// cpu, DMA and Blitter. A third is optionally being used for faster CPU
wire video_cycle = (bus_cycle == 0);
wire cpu_cycle = (bus_cycle == 1) || (second_cpu_slot && (bus_cycle == 3));
wire viking_cycle = (bus_cycle == 2);

// ----------------- RAM address --------------
wire [22:0] video_cycle_addr = (st_hs && ste)?ste_dma_snd_addr:video_address;
wire [22:0] cpu_cycle_addr = data_io_br?data_io_addr:(blitter_br?blitter_master_addr:tg68_adr[23:1]);
wire [22:0] ram_address = viking_cycle?viking_address:(video_cycle?video_cycle_addr:cpu_cycle_addr);

// ----------------- RAM read -----------------
// memory access during the video cycle is shared between video and ste_dma_snd
wire video_cycle_oe = (st_hs && ste)?ste_dma_snd_read:video_read;
// memory access during the cpu cycle is shared between blitter and cpu
wire cpu_cycle_oe = data_io_br?data_io_read:(blitter_br?blitter_master_read:(cpu_cycle && tg68_as && tg68_rw && cpu2mem));
wire ram_oe = viking_cycle?viking_read:(video_cycle?video_cycle_oe:(cpu_cycle?cpu_cycle_oe:1'b0));

// ----------------- RAM write -----------------
wire cpu_cycle_wr = data_io_br?data_io_write:(blitter_br?blitter_master_write:(cpu_cycle && tg68_as && ~tg68_rw && cpu2ram));
wire ram_wr = (viking_cycle||video_cycle)?1'b0:(cpu_cycle?cpu_cycle_wr:1'b0);

wire [15:0] ram_data_out;
wire [15:0] system_data_out = cpu2mem?ram_data_out:io_data_out;
wire [15:0] ram_data_in = data_io_br?data_io_dout:(blitter_br?blitter_master_data_out:tg68_dat_out);

// data strobe
wire ram_uds = video_cycle?1'b1:((blitter_br||data_io_br)?1'b1:~tg68_uds);
wire ram_lds = video_cycle?1'b1:((blitter_br||data_io_br)?1'b1:~tg68_lds);
 
// sdram controller has 64 bit output
wire [63:0] ram_data_out_64;

// select right word of 64 bit ram output for those devices that only want 16 bits
// this is only used for the cpu and other bus masters opoerating within the cpu 
// cycle but neither video nor dma audio use it. They are both fed with 64 bits
assign ram_data_out =
 	 (cpu_cycle_addr[1:0] == 2'd0)?ram_data_out_64[15:0]:
	((cpu_cycle_addr[1:0] == 2'd1)?ram_data_out_64[31:16]:
	((cpu_cycle_addr[1:0] == 2'd2)?ram_data_out_64[47:32]:
	                               ram_data_out_64[63:48]));

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
	.dout       	( ram_data_out_64  			)
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

// connection to transfer midi data from acia to io controller
wire [7:0] midi_data_from_acia;
wire midi_strobe_from_acia;
wire midi_data_from_acia_available;

// connection to transfer serial/rs232 data from mfp to io controller
wire [7:0] serial_data_from_mfp;
wire serial_strobe_from_mfp;
wire serial_data_from_mfp_available;
wire [7:0] serial_data_to_mfp;
wire serial_strobe_to_mfp;

// connection to transfer parallel data from psg to io controller
wire [7:0] parallel_data_out;
wire parallel_strobe_out;
wire parallel_data_out_available;

// extra joystick interface
wire [5:0] joy0, joy1;

// connection between io controller and ethernet controller
//   mac address transfer io controller -> ethernec
wire [31:0] eth_status;
wire [7:0] eth_mac_byte;
wire eth_mac_strobe, eth_mac_begin;
wire [7:0] eth_tx_read_byte;
wire eth_tx_read_strobe, eth_tx_read_begin;
wire [7:0] eth_rx_write_byte;
wire eth_rx_write_strobe, eth_rx_write_begin;

//// user io has an extra spi channel outside minimig core ////
user_io user_io(
		// the spi interface
		.SPI_CLK                	(SPI_SCK),
		.SPI_SS_IO						(CONF_DATA0),
		.SPI_MISO						(user_io_sdo),
		.SPI_MOSI						(SPI_DI),
		
		// ikbd interface
      .ikbd_strobe_out				(ikbd_strobe_from_acia),
      .ikbd_data_out					(ikbd_data_from_acia),
      .ikbd_data_out_available	(ikbd_data_from_acia_available),
      .ikbd_strobe_in				(ikbd_strobe_to_acia),
      .ikbd_data_in					(ikbd_data_to_acia),

		// extra joysticks
		.joy0                  		(joy0),
		.joy1                  		(joy1),
		
		// serial/rs232 interface
      .serial_strobe_out			(serial_strobe_from_mfp),
      .serial_data_out				(serial_data_from_mfp),
      .serial_data_out_available	(serial_data_from_mfp_available),
      .serial_strobe_in				(serial_strobe_to_mfp),
      .serial_data_in				(serial_data_to_mfp),
		
		// parallel interface
      .parallel_strobe_out			(parallel_strobe_out),
      .parallel_data_out			(parallel_data_out),
      .parallel_data_out_available(parallel_data_out_available),

		// midi interface
      .midi_strobe_out				(midi_strobe_from_acia),
      .midi_data_out					(midi_data_from_acia),
      .midi_data_out_available	(midi_data_from_acia_available),

		// ethernet
		.eth_status                (eth_status),
		.eth_mac_begin					(eth_mac_begin),
		.eth_mac_strobe				(eth_mac_strobe),
		.eth_mac_byte					(eth_mac_byte),
		.eth_tx_read_begin			(eth_tx_read_begin),
		.eth_tx_read_strobe			(eth_tx_read_strobe),
		.eth_tx_read_byte				(eth_tx_read_byte),
		.eth_rx_write_begin			(eth_rx_write_begin),
		.eth_rx_write_strobe			(eth_rx_write_strobe),
		.eth_rx_write_byte			(eth_rx_write_byte),
		
		.CORE_TYPE						(8'ha3)    // mist core id
);

wire [22:0] data_io_addr;
wire [15:0] data_io_dout;
wire data_io_write, data_io_read;
wire data_io_br;
 
data_io data_io (
		// system control
		.clk_8 		(clk_8			),
		.reset		(init          ),
		.bus_cycle  (bus_cycle     ),
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

