module addrController_top(
	// clocks:
	input clk8,						// 8.125 MHz CPU clock
	
	// system config:
	input configROMSize,			// 0 = 64K ROM, 1 = 128K ROM
	input [1:0] configRAMSize,	// 0 = 128K, 1 = 512K, 2 = 1MB, 3 = 4MB RAM

	// 68000 CPU memory interface:
	input [23:0] cpuAddr,
	input _cpuAS,
	input _cpuUDS,
	input _cpuLDS,
	input _cpuRW,	
	output _cpuDTACK,	
	
	// RAM/ROM:
	output [21:0] memoryAddr,
	output _memoryUDS,
	output _memoryLDS,	
	output _romCS,
	output _romOE,
	output _romWE,
	output _ramCS,
	output _ramOE,	
	output _ramWE,	
	output videoBusControl,
	
	// peripherals:
	output selectSCC,
	output selectIWM,
	output selectVIA,
	output selectInterruptVectors,
	
	// video:
	output hsync,
	output vsync,
	output _hblank,
	output _vblank,
	output loadNormalPixels,
	output loadDebugPixels,
	
	// audio:
	output loadSound,
	
	// misc
	input memoryOverlayOn,
	
	// extra/debug ROM interface
	input [21:0] extraRomReadAddr,
	output extraRomReadAck
);

	// interleaved RAM access for CPU and video
	reg [1:0] busCycle;
	always @(posedge clk8) begin
		busCycle <= busCycle + 1'b1;
	end
	// video controls memory bus during the first clock of the four-clock cycle
	assign videoBusControl = busCycle == 2'b00;
		
	// DTACK generation	
	// TODO: delay DTACK for once full bus cycle when RAM is accessed, to match Mac Plus memory timing
	// TODO: according to datasheet, /DTACK should continue to be asserted through the final bus cycle too
	assign _cpuDTACK = ~(_cpuAS == 1'b0 && busCycle == 2'b10 && videoBusControl == 1'b0);
	
	// interconnects
	wire selectRAM, selectROM;
	wire [21:0] videoAddr;
	
	// RAM/ROM control signals
	wire videoControlActive = _hblank == 1'b1 || loadSound;
	assign _romCS = ~((videoBusControl == 1'b1 && videoControlActive == 1'b0) || (videoBusControl == 1'b0 && selectROM == 1'b1));
	assign _romOE = ~((videoBusControl == 1'b1 && videoControlActive == 1'b0) || (videoBusControl == 1'b0 && selectROM == 1'b1 && _cpuRW == 1'b1)); 
	assign _romWE = 1'b1;
	assign _ramCS = ~((videoBusControl == 1'b1 && videoControlActive == 1'b1) || (videoBusControl == 1'b0 && selectRAM == 1'b1));
	assign _ramOE = ~((videoBusControl == 1'b1 && videoControlActive == 1'b1) || (videoBusControl == 1'b0 && selectRAM == 1'b1 && _cpuRW == 1'b1));
	assign _ramWE = ~(videoBusControl == 1'b0 && selectRAM && _cpuRW == 1'b0);
	assign _memoryUDS = videoBusControl ? 1'b0 : _cpuUDS;
	assign _memoryLDS = videoBusControl ? 1'b0 : _cpuLDS;
	wire [21:0] addrMux = videoBusControl ? videoAddr : cpuAddr[21:0];
	wire [21:0] macAddr;
	assign macAddr[15:0] = addrMux[15:0];
	
	// simulate smaller RAM/ROM sizes
	assign macAddr[16] = selectROM == 1'b1 && configROMSize == 1'b0 ? 1'b0 :  // force A16 to 0 for 64K ROM access
									addrMux[16]; 
	assign macAddr[17] = selectRAM == 1'b1 && configRAMSize == 2'b00 ? 1'b0 : // force A17 to 0 for 128K RAM access
									selectROM == 1'b1 && configROMSize == 1'b1 ? 1'b0 :  // force A17 to 0 for 128K ROM access
									selectROM == 1'b1 && configROMSize == 1'b0 ? 1'b1 :  // force A17 to 1 for 64K ROM access (64K ROM image is at $20000)
									addrMux[17]; 
	assign macAddr[18] = selectRAM == 1'b1 && configRAMSize == 2'b00 ? 1'b0 : // force A18 to 0 for 128K RAM access
									selectROM == 1'b1 ? 1'b0 : 								  // force A18 to 0 for ROM access
									addrMux[18]; 
	assign macAddr[19] = selectRAM == 1'b1 && configRAMSize[1] == 1'b0 ? 1'b0 : // force A19 to 0 for 128K or 512K RAM access
									selectROM == 1'b1 ? 1'b0 : 								  // force A19 to 0 for ROM access
									addrMux[19]; 
	assign macAddr[20] = selectRAM == 1'b1 && configRAMSize != 2'b11 ? 1'b0 : // force A20 to 0 for all but 4MB RAM access
									selectROM == 1'b1 ? 1'b0 : 								  // force A20 to 0 for ROM access
									addrMux[20]; 
	assign macAddr[21] = selectRAM == 1'b1 && configRAMSize != 2'b11 ? 1'b0 : // force A21 to 0 for all but 4MB RAM access
									selectROM == 1'b1 ? 1'b0 : 								  // force A21 to 0 for ROM access
									addrMux[21]; 
	
	assign extraRomReadAck = videoBusControl == 1'b1 && videoControlActive == 1'b0;
	assign memoryAddr = videoBusControl == 1'b1 && videoControlActive == 1'b0 ? extraRomReadAddr : macAddr;
	
	// address decoding
	wire selectSCCByAddress;
	addrDecoder ad(
		.address(cpuAddr),
		.enable(!videoBusControl),
		._cpuAS(_cpuAS),
		.memoryOverlayOn(memoryOverlayOn),
		.selectRAM(selectRAM),
		.selectROM(selectROM),
		.selectSCC(selectSCCByAddress),
		.selectIWM(selectIWM),
		.selectVIA(selectVIA),
		.selectInterruptVectors(selectInterruptVectors));
		
	/* SCC register access is a mess. Reads and writes can have side-effects that alter the meaning of subsequent reads
		and writes to the same address. It's not safe to do multiple reads of the same address, or multiple writes of the
		same value to the same address. So we need to be sure we only perform one read or write per 4-clock CPU bus cycle.
		
		To complicate things, the CPU latches read data half-way through the last clock of the cycle, then deasserts the
		address, address strobe, and data for the remainder of the cycle (although RW remains valid). This behavior may
		be specified to TG68 and not shared by the real 68000.
		
		For writes to the SCC, we enable SCC only on clock 2, to guarantee one write per bus cycle.
		
		For reads, it's more difficult. If we enable SCC only on clock 2, then it won't be enabled during clock 3 when the 
		CPU latches the data, so the read will fail. If we enable it only on clock 3, then the AS won't be asserted all
		the way to the end of the clock, so the read side-effect will fail. If we enable it on clock 2 and 3, then the 
		CPU will read the post-side-effect value instead of the pre-side-effect value.
		
		The solution used here is to enable reads on clock 2 (when the side-effect is performed), and for the first half
		of clock 3, and to apply a one cycle delay to CPU data reads from the SCC. Reads only enable for the first half
		of clock 3 in case a later 68000 variant continues to assert AS all the way to the end of the clock, to ensure
		side-effects are not applied again.
		
		Another solution would be to create a custom clock for the SCC, whose positive edge is the negative edge of
		clock 3 of the bus cycle.
	*/
	assign selectSCC = selectSCCByAddress && (busCycle == 2'b10 || // reads and writes enable on clock 2
															(_cpuRW == 1'b1 && busCycle == 2'b11 && clk8)); // reads enable on first half of clock 3 
	
	// video
	videoTimer vt(
		.clk8(clk8), 
		.busCycle(busCycle), 
		.videoAddr(videoAddr), 
		.hsync(hsync), 
		.vsync(vsync), 
		._hblank(_hblank),
		._vblank(_vblank), 
		.loadNormalPixels(loadNormalPixels), 
		.loadDebugPixels(loadDebugPixels),
		.loadSound(loadSound));
		
endmodule
