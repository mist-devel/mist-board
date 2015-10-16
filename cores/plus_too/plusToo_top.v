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
//    ______X_video_cycle_X____unused___X__cpu_cycle__X___unused____X___
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

// disk image is being stored right after os rom at word offset 0x10000 
wire [20:0] dio_a = (dio_index == 0)?dio_addr[20:0]:{21'h10000 + dio_addr[20:0]};
   
data_io data_io (
   // io controller spi interface
   .sck ( SPI_SCK ),
   .ss  ( SPI_SS2 ),
   .sdi ( SPI_DI  ),

   .downloading ( dio_download ),  // signal indicating an active rom download
   .index    ( dio_index ),        // 0=rom download, 1=disk image
                 
   // external ram interface
   .clk   ( clk8      ),
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

// various debug signals for the DE1/DE2. These don't exist on the MIST
// and will be optimized away ...
wire [6:0] hex0;
wire [6:0] hex1;
wire [6:0] hex2;
wire [6:0] hex3;
wire [7:0] ledg;
	 
// ps2 interface for mouse, to be mapped into user_io
wire mouseClk;
wire mouseData;
wire keyClk;
wire keyData;

	 // NO REAL LOGIC SHOULD GO IN THIS MODULE!
	// It may not exist in the hand-built Plus Too.
	// Only interconnections and interfaces specific to the dev board should go here
	
assign SDRAM_CLK = !clk64;
	
	// synthesize a 32.5 MHz clock
	wire clk64;
	wire pll_locked;
	
	reg clk32; 
	always @(posedge clk64)
		clk32 <= !clk32;
	
	pll cs0(
		.inclk0	( CLOCK_27[0]	),
		.c0		( clk64			), 	
		.locked	( pll_locked	)
	);
	
	// generate ~16kHz for ps2
	wire ps2_clk = ps2_clk_div[8];
	reg [8:0] ps2_clk_div;
	always @(posedge clk8)
		ps2_clk_div <= ps2_clk_div + 9'd1;
	
	// set the real-world inputs to sane defaults
	localparam serialIn = 1'b0,
				  interruptButton = 1'b0,
				  configROMSize = 1'b1, // 128K ROM
				  configRAMSize = 2'b01; // 512K RAM
				  
	// interconnects
	// CPU
	wire clk8, _cpuReset, _cpuAS, _cpuUDS, _cpuLDS, _cpuRW, _cpuDTACK;
	wire [2:0] _cpuIPL;
	wire [7:0] cpuAddrHi;
	wire [23:0] cpuAddr;
	wire [15:0] cpuDataOut;
	
	// RAM/ROM
	wire _romCS, _romOE;
	wire _ramCS, _ramOE, _ramWE;
	wire _memoryUDS, _memoryLDS;
	wire videoBusControl;
	wire [21:0] memoryAddr;
	wire [15:0] memoryDataOut;
	wire memoryDriveData;
	wire [15:0] memoryDataInMux;
	
	// peripherals
	wire loadSound, loadNormalPixels, loadDebugPixels, pixelOut, _hblank, _vblank;
	wire memoryOverlayOn, selectSCC, selectIWM, selectVIA, selectInterruptVectors;	 
	wire [15:0] dataControllerDataOut;
	wire dataControllerDriveData;
	
	// debug panel
	wire _debugDTACK, driveDebugData, loadPixels, extraRomReadAck;
	wire [15:0] debugDataOut;
	wire [21:0] extraRomReadAddr;
	
	// LED debug lights
	assign ledg = { 2'b00, diskInDrive[1], diskInDrive[1], diskInDrive[0], diskInDrive[0], 2'b00 };
	
	// convert 1-bit pixel data to 4:4:4 RGB
	// force pixels in debug area to appear green
	assign red[3:0] = _vblank == 1'b0 ? 4'h0 : { pixelOut, pixelOut, pixelOut, pixelOut };
	assign green[3:0] = { pixelOut, pixelOut, pixelOut, pixelOut };
	assign blue[3:0] = _vblank == 1'b0 ? 4'h0 : { pixelOut, pixelOut, pixelOut, pixelOut };
	
	// memory-side data input mux
	// In a hand-built system, both RAM and ROM data will be on the same physical pins,
	// making this mux unnecessary
	assign memoryDataInMux = driveDebugData ? debugDataOut :
									sdram_do;

	// the configuration string is returned to the io controller to allow
	// it to control the menu on the OSD 
	parameter CONF_STR = {
        "PLUS_TOO;;",
        "F1,BIN;",
        "T2,Reset"
	};
	
	parameter CONF_STR_LEN = 10+7+8;

	// the status register is controlled by the on screen display (OSD)
	wire [7:0] status;
	wire [1:0] buttons;

	// include user_io module for arm controller communication
	user_io #(.STRLEN(CONF_STR_LEN)) user_io ( 
		.conf_str   	( CONF_STR   	),

		.SPI_CLK    	( SPI_SCK    	),	
		.SPI_SS_IO  	( CONF_DATA0 	),
		.SPI_MISO   	( SPI_DO     	),
		.SPI_MOSI   	( SPI_DI     	),

      .status     	( status     	),
      .buttons    	( buttons     	),
                 
      // ps2 interface
      .ps2_clk    	( ps2_clk     	),
      .ps2_kbd_clk	( keyClk      	),
      .ps2_kbd_data	( keyData 		),
		.ps2_mouse_clk ( mouseClk		),
      .ps2_mouse_data( mouseData	   )
	);


	debugPanel dp(
		.clk8(clk8),
		.sw(sw),
		.key(key),
		.videoBusControl(videoBusControl),
		.loadNormalPixels(loadNormalPixels),
		.loadDebugPixels(loadDebugPixels),
		.loadPixelsOut(loadPixels),
		._dtackIn(_cpuDTACK),
		.cpuAddrHi(cpuAddrHi),
		.cpuAddr(cpuAddr),
		._cpuRW(_cpuRW),
		._cpuUDS(_cpuUDS),
		._cpuLDS(_cpuLDS),
		.dataControllerDataOut(dataControllerDataOut),
		.cpuDataOut(cpuDataOut),
		.memoryAddr(memoryAddr),
		._dtackOut(_debugDTACK),
		.hex0(hex0),
		.hex1(hex1),
		.hex2(hex2),
		.hex3(hex3),
		.driveDebugData(driveDebugData),
		.debugDataOut(debugDataOut),
		.extraRomReadAck(extraRomReadAck));
	
	wire [2:0] _debugIPL = sw[0] == 1'b1 ? 3'b111 : _cpuIPL; // suppress interrupts when sw0 on	

/*	
	TG68 m68k(
		.clk(clk8), 
		.reset(_cpuReset), 
		.clkena_in(1'b1),
		.data_in(dataControllerDataOut), 
		.IPL(_debugIPL), 
		.dtack(_debugDTACK), 
		.addr({cpuAddrHi, cpuAddr}), 
		.data_out(cpuDataOut), 
		.as(_cpuAS), 
		.uds(_cpuUDS), 
		.lds(_cpuLDS), 
		.rw(_cpuRW), 
		.drive_data(cpuDriveData)); 
*/	

   assign _cpuAS = !(cpu_busstate != 2'b01);
	wire [1:0] cpu_busstate;
	wire cpu_clkena = (!_debugDTACK) || (cpu_busstate == 2'b01);
	TG68KdotC_Kernel #(0,0,0,0,0,0) m68k (
        .clk            ( clk8           ),
        .nReset         ( _cpuReset      ),
        .clkena_in      ( cpu_clkena     ), 
        .data_in        ( dataControllerDataOut ),
        .IPL            ( _debugIPL      ),
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
		._cpuAS(_cpuAS), 
		._cpuUDS(_cpuUDS),
		._cpuLDS(_cpuLDS),
		._cpuRW(_cpuRW), 
		._cpuDTACK(_cpuDTACK), 
		.configROMSize(configROMSize), 
		.configRAMSize(configRAMSize), 
		.memoryAddr(memoryAddr),			
		._memoryUDS(_memoryUDS),
		._memoryLDS(_memoryLDS),
		._romCS(_romCS),
		._romOE(_romOE), 
		._ramCS(_ramCS), 
		._ramOE(_ramOE), 
		._ramWE(_ramWE),
		.videoBusControl(videoBusControl),	
		.selectSCC(selectSCC),
		.selectIWM(selectIWM),
		.selectVIA(selectVIA),
		.selectInterruptVectors(selectInterruptVectors),
		.hsync(hsync), 
		.vsync(vsync),
		._hblank(_hblank),
		._vblank(_vblank),
		.loadNormalPixels(loadNormalPixels),
		.loadDebugPixels(loadDebugPixels),
		.loadSound(loadSound), 
		.memoryOverlayOn(memoryOverlayOn),
		
		.extraRomReadAddr(extraRomReadAddr),
		.extraRomReadAck(extraRomReadAck));
	
	wire [1:0] diskInDrive;
	
	// addional ~8ms delay in reset
	wire n_reset = (rst_cnt == 0);
	reg [15:0] rst_cnt;
	always @(posedge clk8) begin
		// various source can reset the mac
		if(!pll_locked || status[0] || status[2] || buttons[1] || dio_download) 
			rst_cnt <= 16'd65535;
		else if(rst_cnt != 0)
			rst_cnt <= rst_cnt - 16'd1;
	end
	
	dataController_top dc0(
		.clk32(clk32), 
		.clk8out(clk8),
		.clk8(clk8),  
		._systemReset(n_reset), 
		._cpuReset(_cpuReset), 
		._cpuIPL(_cpuIPL),
		._cpuUDS(_cpuUDS), 
		._cpuLDS(_cpuLDS), 
		._cpuRW(_cpuRW), 
		.cpuDataIn(cpuDataOut),
		.cpuDataOut(dataControllerDataOut), 	
		.cpuDriveData(dataControllerDriveData),
		.cpuAddrRegHi(cpuAddr[12:9]),
		.cpuAddrRegLo(cpuAddr[2:1]),		
		.selectSCC(selectSCC),
		.selectIWM(selectIWM),
		.selectVIA(selectVIA),
		.selectInterruptVectors(selectInterruptVectors),
		.videoBusControl(videoBusControl),
		.memoryDataOut(memoryDataOut),
		.memoryDataIn(memoryDataInMux),
		.memoryDriveData(memoryDriveData),
		.keyClk(keyClk), 
		.keyData(keyData), 
		.mouseClk(mouseClk),
		.mouseData(mouseData),
		.serialIn(serialIn), 
		._hblank(_hblank),
		._vblank(_vblank), 
		.pixelOut(pixelOut), 
		.loadPixels(loadPixels), 
		.loadSound(loadSound),
		.interruptButton(1'b1), 
		.memoryOverlayOn(memoryOverlayOn),
		.insertDisk( 2'b01 ),
		.diskInDrive(diskInDrive),
		
		.extraRomReadAddr(extraRomReadAddr),
		.extraRomReadAck(extraRomReadAck));
		
	// ram/rom maps directly into 68k address space

// multiplex sdram between mac and the rom downloader
// 4MB RAM
// wire [24:0] sdram_addr = dio_download?{ 3'b001, dio_a[20:0] }:{ 2'b00, ~_romOE, memoryAddr[21:1] };

wire [20:0] memoryAddrEx = 
	extraRomReadAck?memoryAddr[21:1]:              // full access to floppy image
//	memoryAddr[21:1];                              // CPU access not masked giving 4MB ram
	{ 3'b000, memoryAddr[18:1]} ;                  // CPU access masked for 512k ram

wire [24:0] sdram_addr = dio_download?{ 4'b0001, dio_a[20:0] }:{ 3'b000, ~_romOE, memoryAddrEx };

wire [15:0] sdram_din = dio_download?dio_data:memoryDataOut;
wire [1:0] sdram_ds = dio_download?2'b11:{ !_memoryUDS, !_memoryLDS };
wire sdram_we = dio_download?dio_write:!_ramWE;
wire sdram_oe = dio_download?1'b0:(!_ramOE || !_romOE);


// during rom/disk download ffff is returned so the screen is black during download
// "extra rom" is used to hold the disk image. It's expected to be byte wide and
// we thus need to properly demultiplex the word returned from sdram in that case
wire [15:0] extra_rom_data_demux = memoryAddr[0]?
	{sdram_out[7:0],sdram_out[7:0]}:{sdram_out[15:8],sdram_out[15:8]};
wire [15:0] sdram_do = dio_download?16'hffff:
	extraRomReadAck?extra_rom_data_demux:
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
