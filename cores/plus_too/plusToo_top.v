// PlusToo_top for the MIST FPGA board

module plusToo_top( 
  // clock inputs
  input wire [ 2-1:0]   CLOCK_27, // 27 MHz
  // LED outputs
  output wire           LED, // LED Yellow
  // UART
  output wire           UART_TX, // UART Transmitter (MIDI out)
  input wire            UART_RX, // UART Receiver (MIDI in)
  // VGA
  output wire           VGA_HS, // VGA H_SYNC
  output wire           VGA_VS, // VGA V_SYNC
  output wire [ 6-1:0]  VGA_R, // VGA Red[5:0]
  output wire [ 6-1:0]  VGA_G, // VGA Green[5:0]
  output wire [ 6-1:0]  VGA_B, // VGA Blue[5:0]
  // SDRAM
  inout wire [ 16-1:0]  SDRAM_DQ, // SDRAM Data bus 16 Bits
  output wire [ 13-1:0] SDRAM_A, // SDRAM Address bus 13 Bits
  output wire           SDRAM_DQML, // SDRAM Low-byte Data Mask
  output wire           SDRAM_DQMH, // SDRAM High-byte Data Mask
  output wire           SDRAM_nWE, // SDRAM Write Enable
  output wire           SDRAM_nCAS, // SDRAM Column Address Strobe
  output wire           SDRAM_nRAS, // SDRAM Row Address Strobe
  output wire           SDRAM_nCS, // SDRAM Chip Select
  output wire [ 2-1:0]  SDRAM_BA, // SDRAM Bank Address
  output wire           SDRAM_CLK, // SDRAM Clock
  output wire           SDRAM_CKE, // SDRAM Clock Enable
  // MINIMIG specific
  output wire           AUDIO_L, // sigma-delta DAC output left
  output wire           AUDIO_R, // sigma-delta DAC output right
  // SPI
  inout wire            SPI_DO,
  input wire            SPI_DI,
  input wire            SPI_SCK,
  input wire            SPI_SS2,    // fpga
  input wire            SPI_SS3,    // OSD
  input wire            SPI_SS4,    // "sniff" mode
  input wire            CONF_DATA0  // SPI_SS for user_io
  );

// ------------------------------ Plus Too Bus Timing ---------------------------------
// for stability and maintainability reasons the whole timing has been simplyfied:
//                00           01             10           11
//    ______ _____________ _____________ _____________ _____________ ___
//    ______X_video_cycle_X______IO_____X__cpu_cycle__X___unused____X___
//                        ^                    ^      ^
//                        |                    |      |
//                      video                 cpu    cpu
//                       read                write   read
  
// include the OSD into the video data path
osd #(10,0,2) osd (
   .pclk       ( clk32        ),

   // spi for OSD
   .sdi        ( SPI_DI       ),
   .sck        ( SPI_SCK      ),
   .ss         ( SPI_SS3      ),

   .red_in     ( { red, 2'b00 }   ),
   .green_in   ( { green, 2'b00 } ),
   .blue_in    ( { blue, 2'b00 }  ),
   .hs_in      ( hsync        ),
   .vs_in      ( vsync        ),

   .red_out    ( VGA_R        ),
   .green_out  ( VGA_G        ),
   .blue_out   ( VGA_B        ),
   .hs_out     ( VGA_HS       ),
   .vs_out     ( VGA_VS       )
);

// -------------------------------------------------------------------------
// ------------------------------ data_io ----------------------------------
// -------------------------------------------------------------------------

// include ROM download helper
wire dio_download;
wire dio_write;
wire [23:0] dio_addr;
wire [4:0] dio_index;
wire [15:0] dio_data;

// good floppy image sizes are 819200 bytes and 409600 bytes
reg dsk_int_ds, dsk_ext_ds;  // double sided image inserted
reg dsk_int_ss, dsk_ext_ss;  // single sided image inserted

// any known type of disk image inserted?
wire dsk_int_ins = dsk_int_ds || dsk_int_ss;
wire dsk_ext_ins = dsk_ext_ds || dsk_ext_ss;

// at the end of a download latch file size
// diskEject is set by macos on eject
always @(negedge dio_download or posedge diskEject[0]) begin
	if(diskEject[0]) begin
		dsk_int_ds <= 1'b0;
		dsk_int_ss <= 1'b0;
	end else if(dio_index == 1) begin
		dsk_int_ds <= (dio_addr == 409599);   // double sides disk, addr counts words, not bytes
		dsk_int_ss <= (dio_addr == 204799);   // single sided disk
	end
end	
	
always @(negedge dio_download or posedge diskEject[1]) begin
	if(diskEject[1]) begin
		dsk_ext_ds <= 1'b0;
		dsk_ext_ss <= 1'b0;
	end else if(dio_index == 2) begin
		dsk_ext_ds <= (dio_addr == 409599);   // double sided disk, addr counts words, not bytes
		dsk_ext_ss <= (dio_addr == 204799);   // single sided disk
	end
end

// disk images are being stored right after os rom at word offset 0x80000 and 0x100000 
wire [20:0] dio_a = 
	(dio_index == 0)?dio_addr[20:0]:                 // os rom
	(dio_index == 1)?{21'h80000 + dio_addr[20:0]}:   // first dsk image at 512k word addr
	{21'h100000 + dio_addr[20:0]};                   // second dsk image at 1M word addr
   
data_io data_io (
   // io controller spi interface
   .sck ( SPI_SCK ),
   .ss  ( SPI_SS2 ),
   .sdi ( SPI_DI  ),

   .downloading ( dio_download ),  // signal indicating an active rom download
   .index    ( dio_index ),        // 0=rom download, 1=disk image
                 
   // external ram interface
   .clk   ( download_cycle ),
   .wr    ( dio_write ),
   .addr  ( dio_addr  ),
   .data  ( dio_data  )
);
                        
// keys and switches are dummies as the mist doesn't have any ...
wire [9:0] sw = 10'd0;
wire [3:0] key = 4'd0;

// the macs video signals. To be fed into the MiSTs OSD overlay and then
// send to the VGA
wire hsync;
wire vsync;
wire [3:0] red;
wire [3:0] green;
wire [3:0] blue;
	 
// ps2 interface for mouse, to be mapped into user_io
wire mouseClk;
wire mouseData;
wire keyClk;
wire keyData;
	
	// synthesize a 32.5 MHz clock
	wire clk64;
	wire pll_locked;
	
	reg clk32; 
	always @(posedge clk64)
		clk32 <= !clk32;
	
	pll cs0(
		.inclk0	( CLOCK_27[0]	),
		.c0		( clk64			), 	
		.c1	   ( SDRAM_CLK    ),
		.locked	( pll_locked	)
	);
	
	// generate ~16kHz for ps2
	wire ps2_clk = ps2_clk_div[8];
	reg [8:0] ps2_clk_div;
	always @(posedge clk8)
		ps2_clk_div <= ps2_clk_div + 9'd1;
	
	// set the real-world inputs to sane defaults
	localparam serialIn = 1'b0,
				  configROMSize = 1'b1;  // 128K ROM

	wire [1:0] configRAMSize = status_mem?2'b11:2'b10; // 1MB/4MB
				  
	// interconnects
	// CPU
	wire clk8, _cpuReset, _cpuUDS, _cpuLDS, _cpuRW;
	wire [2:0] _cpuIPL;
	wire [7:0] cpuAddrHi;
	wire [23:0] cpuAddr;
	wire [15:0] cpuDataOut;
	
	// RAM/ROM
	wire _romOE;
	wire _ramOE, _ramWE;
	wire _memoryUDS, _memoryLDS;
	wire videoBusControl;
	wire dioBusControl;
	wire cpuBusControl;
	wire [21:0] memoryAddr;
	wire [15:0] memoryDataOut;
	
	// peripherals
	wire loadPixels, pixelOut, _hblank, _vblank;
	wire memoryOverlayOn, selectSCSI, selectSCC, selectIWM, selectVIA;	 
	wire [15:0] dataControllerDataOut;
	
	// audio
	wire snd_alt;
	wire loadSound;
	
	// floppy disk image interface
	wire dskReadAckInt;
	wire [21:0] dskReadAddrInt;
	wire dskReadAckExt;
	wire [21:0] dskReadAddrExt;
	
	// convert 1-bit pixel data to 4:4:4 RGB
	assign red[3:0] =   { pixelOut, pixelOut, pixelOut, pixelOut };
	assign green[3:0] = { pixelOut, pixelOut, pixelOut, pixelOut };
	assign blue[3:0] =  { pixelOut, pixelOut, pixelOut, pixelOut };
	
	// the configuration string is returned to the io controller to allow
	// it to control the menu on the OSD 
	parameter CONF_STR = {
        "PLUS_TOO;;",
        "F1,DSK;",
        "F2,DSK;",
		  "S3,IMG;",
		  "O4,Memory,1MB,4MB;",
		  "O5,Speed,Normal,Turbo;",
        "T6,Reset"
	};
	
	wire status_mem = status[4];
	wire status_turbo = status[5];
	wire status_reset = status[6];
	
	parameter CONF_STR_LEN = 10+7+7+7+18+22+8;

	// the status register is controlled by the on screen display (OSD)
	wire [7:0] status;
	wire [1:0] buttons;

	wire [31:0] io_lba;
	wire io_rd;
	wire io_wr;
	wire io_ack;
	wire [7:0] io_din;
	wire io_din_strobe;
	wire [7:0] io_dout;
	wire io_dout_strobe;
 
	// include user_io module for arm controller communication
	user_io #(.STRLEN(CONF_STR_LEN)) user_io ( 
		.conf_str   	( CONF_STR   	  ),

		.SPI_CLK    	( SPI_SCK    	  ),	
		.SPI_SS_IO  	( CONF_DATA0 	  ),
		.SPI_MISO   	( SPI_DO     	  ),
		.SPI_MOSI   	( SPI_DI     	  ),

      .status     	( status     	  ),
      .buttons    	( buttons     	  ),
                 
      // ps2 interface
      .ps2_clk    	( ps2_clk     	  ),
      .ps2_kbd_clk	( keyClk      	  ),
      .ps2_kbd_data	( keyData 		  ),
		.ps2_mouse_clk ( mouseClk		  ),
      .ps2_mouse_data( mouseData	     ),

		// SD/block device interface
		.sd_lba        ( io_lba         ),
		.sd_rd         ( io_rd          ),
      .sd_wr         ( io_wr          ),
      .sd_ack        ( io_ack         ),
      .sd_conf       ( 1'b0           ),
      .sd_sdhc       ( 1'b1           ),
      .sd_dout       ( io_din         ),
      .sd_dout_strobe( io_din_strobe  ),
      .sd_din        ( io_dout        ),
      .sd_din_strobe ( io_dout_strobe )
	);

	wire [1:0] cpu_busstate;
	wire cpu_clkena = cpuBusControl || (cpu_busstate == 2'b01);
	TG68KdotC_Kernel #(0,0,0,0,0,0) m68k (
        .clk            ( clk8           ),
        .nReset         ( _cpuReset      ),
        .clkena_in      ( cpu_clkena     ), 
        .data_in        ( dataControllerDataOut ),
        .IPL            ( _cpuIPL        ),
        .IPL_autovector ( 1'b1           ),
        .berr           ( 1'b0           ),
        .clr_berr       ( 1'b0           ),
        .CPU            ( 2'b00          ),   // 00=68000
        .addr           ( {cpuAddrHi, cpuAddr} ),
        .data_write     ( cpuDataOut     ),
        .nUDS           ( _cpuUDS        ),
        .nLDS           ( _cpuLDS        ),
        .nWr            ( _cpuRW         ),
        .busstate       ( cpu_busstate   ), // 00-> fetch code 10->read data 11->write data 01->no memaccess
        .nResetOut      (                ),
        .FC             (                )
);

	
	addrController_top ac0(
		.clk8(clk8), 
		.cpuAddr(cpuAddr), 
		._cpuUDS(_cpuUDS),
		._cpuLDS(_cpuLDS),
		._cpuRW(_cpuRW), 
		.turbo (status_turbo),
		.configROMSize(configROMSize), 
		.configRAMSize(configRAMSize), 
		.memoryAddr(memoryAddr),			
		._memoryUDS(_memoryUDS),
		._memoryLDS(_memoryLDS),
		._romOE(_romOE), 
		._ramOE(_ramOE), 
		._ramWE(_ramWE),
		.videoBusControl(videoBusControl),	
		.dioBusControl(dioBusControl),	
		.cpuBusControl(cpuBusControl),	
		.selectSCSI(selectSCSI),
		.selectSCC(selectSCC),
		.selectIWM(selectIWM),
		.selectVIA(selectVIA),
		.hsync(hsync), 
		.vsync(vsync),
		._hblank(_hblank),
		._vblank(_vblank),
		.loadPixels(loadPixels),
		.memoryOverlayOn(memoryOverlayOn),

		.snd_alt(snd_alt),
		.loadSound(loadSound),

		.dskReadAddrInt(dskReadAddrInt),
		.dskReadAckInt(dskReadAckInt),
		.dskReadAddrExt(dskReadAddrExt),
		.dskReadAckExt(dskReadAckExt)
	);
	
	wire [1:0] diskEject;
	
	// addional ~8ms delay in reset
	wire rom_download = dio_download && (dio_index == 0);
	wire n_reset = (rst_cnt == 0);
	reg [15:0] rst_cnt;
	reg last_mem_config;
	always @(posedge clk8) begin
		last_mem_config <= status_mem;
	
		// various sources can reset the mac
		if(!pll_locked || status[0] || status_reset || buttons[1] || 
			rom_download || (last_mem_config != status_mem)) 
			rst_cnt <= 16'd65535;
		else if(rst_cnt != 0)
			rst_cnt <= rst_cnt - 16'd1;
	end

	wire [10:0] audio;
	sigma_delta_dac dac (
		.clk ( clk32 ),
		.ldatasum ( { audio, 4'h0 } ),
		.rdatasum ( { audio, 4'h0 } ),
		.left ( AUDIO_L ),
		.right ( AUDIO_R )
	);

	dataController_top dc0(
		.clk32(clk32), 
		.clk8(clk8),  
		._systemReset(n_reset), 
		._cpuReset(_cpuReset), 
		._cpuIPL(_cpuIPL),
		._cpuUDS(_cpuUDS), 
		._cpuLDS(_cpuLDS), 
		._cpuRW(_cpuRW), 
		.cpuDataIn(cpuDataOut),
		.cpuDataOut(dataControllerDataOut), 	
		.cpuAddrRegHi(cpuAddr[12:9]),
		.cpuAddrRegMid(cpuAddr[6:4]),  // for SCSI
		.cpuAddrRegLo(cpuAddr[2:1]),		
		.selectSCSI(selectSCSI),
		.selectSCC(selectSCC),
		.selectIWM(selectIWM),
		.selectVIA(selectVIA),
		.cpuBusControl(cpuBusControl),
		.videoBusControl(videoBusControl),
		.memoryDataOut(memoryDataOut),
		.memoryDataIn(sdram_do),
		
		// peripherals
		.keyClk(keyClk), 
		.keyData(keyData), 
		.mouseClk(mouseClk),
		.mouseData(mouseData),
		.serialIn(serialIn), 
		
		// video
		._hblank(_hblank),
		._vblank(_vblank), 
		.pixelOut(pixelOut),
		.loadPixels(loadPixels),
		
		.memoryOverlayOn(memoryOverlayOn),

		.audioOut(audio),
		.snd_alt(snd_alt),
		.loadSound(loadSound),
		
		// floppy disk interface
		.insertDisk( { dsk_ext_ins, dsk_int_ins} ),
		.diskSides( { dsk_ext_ds, dsk_int_ds} ),
		.diskEject(diskEject),
		.dskReadAddrInt(dskReadAddrInt),
		.dskReadAckInt(dskReadAckInt),
		.dskReadAddrExt(dskReadAddrExt),
		.dskReadAckExt(dskReadAckExt),

		// block device interface for scsi disk
		.io_lba 			( io_lba 			),
		.io_rd 			( io_rd 				),
		.io_wr 			( io_wr 				),
		.io_ack 			( io_ack				),
		.io_din 			( io_din				),
		.io_din_strobe ( io_din_strobe	),
		.io_dout 		( io_dout			),
		.io_dout_strobe( io_dout_strobe	)
	);
		
// sdram used for ram/rom maps directly into 68k address space
wire download_cycle = dio_download && dioBusControl;

wire [24:0] sdram_addr = download_cycle?{ 4'b0001, dio_a[20:0] }:{ 3'b000, ~_romOE, memoryAddr[21:1] };

wire [15:0] sdram_din = download_cycle?dio_data:memoryDataOut;
wire [1:0] sdram_ds = download_cycle?2'b11:{ !_memoryUDS, !_memoryLDS };
wire sdram_we = download_cycle?dio_write:!_ramWE;
wire sdram_oe = download_cycle?1'b0:(!_ramOE || !_romOE);


// during rom/disk download ffff is returned so the screen is black during download
// "extra rom" is used to hold the disk image. It's expected to be byte wide and
// we thus need to properly demultiplex the word returned from sdram in that case
wire [15:0] extra_rom_data_demux = memoryAddr[0]?
	{sdram_out[7:0],sdram_out[7:0]}:{sdram_out[15:8],sdram_out[15:8]};
wire [15:0] sdram_do = download_cycle?16'hffff:
	(dskReadAckInt || dskReadAckExt)?extra_rom_data_demux:
	sdram_out;
	
wire [15:0] sdram_out;
	
assign SDRAM_CKE         = 1'b1;

sdram sdram (
	// interface to the MT48LC16M16 chip
   .sd_data        ( SDRAM_DQ                 ),
   .sd_addr        ( SDRAM_A                  ),
   .sd_dqm         ( {SDRAM_DQMH, SDRAM_DQML} ),
   .sd_cs          ( SDRAM_nCS                ),
   .sd_ba          ( SDRAM_BA                 ),
   .sd_we          ( SDRAM_nWE                ),
   .sd_ras         ( SDRAM_nRAS               ),
   .sd_cas         ( SDRAM_nCAS               ),

   // system interface
   .clk_64         ( clk64                    ),
   .clk_8          ( clk8                     ),
   .init           ( !pll_locked              ),

   // cpu/chipset interface
	// map rom to sdram word address $200000 - $20ffff
  .din            ( sdram_din                 ),
  .addr           ( sdram_addr                ),
  .ds             ( sdram_ds                  ),
  .we             ( sdram_we                  ),
  .oe             ( sdram_oe                  ),
  .dout           ( sdram_out                 )
);

endmodule
