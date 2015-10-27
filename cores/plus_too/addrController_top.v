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
	output _romOE,
	output _ramOE,	
	output _ramWE,	
	output videoBusControl,
	output dioBusControl,
	
	// peripherals:
	output selectSCC,
	output selectIWM,
	output selectVIA,
	
	// video:
	output hsync,
	output vsync,
	output _hblank,
	output _vblank,
	output loadPixels,
		
	input  snd_alt,
	output loadSound,
		
	// misc
	input memoryOverlayOn,
	
	// interface to read dsk image from ram
	input [21:0] dskReadAddrInt,
	output dskReadAckInt,
	input [21:0] dskReadAddrExt,
	output dskReadAckExt
);

	// -------------- audio engine (may be moved into seperate module) ---------------
	assign loadSound = sndReadAck;

	localparam SIZE = 20'd67704;   // 168*608/2 clk8 events per frame
	localparam STEP = 20'd5920;    // one step every 16*370 clk8 events
	
	reg [21:0] audioAddr; 
	reg [19:0] snd_div;
	
	reg sndReadAckD;
	always @(negedge clk8)
		sndReadAckD <= sndReadAck;
	
	reg vblankD, vblankD2;
	always @(posedge clk8) begin
		if(sndReadAckD) begin
			vblankD <= _vblank;
			vblankD2 <= vblankD;
		
			// falling adge of _vblank = begin of vblank phase
			if(vblankD2 && !vblankD) begin
				audioAddr <= snd_alt?22'h3FA100:22'h3FFD00;
				snd_div <= 20'd0;
			end else begin
				if(snd_div >= SIZE-1) begin
					snd_div <= snd_div - SIZE + STEP;
					audioAddr <= audioAddr + 22'd2;
				end else
					snd_div <= snd_div + STEP;
			end
		end
	end
	
	assign dioBusControl = extraBusControl;

	// interleaved RAM access for CPU and video
	reg [1:0] busCycle;
	always @(posedge clk8)
		busCycle <= busCycle + 2'd1;
	
	// video controls memory bus during the first clock of the four-clock cycle
	assign videoBusControl = (busCycle == 2'b00);
	// cpu controls memory bus during the third clock of the four-clock cycle
	wire cpuBusControl = (busCycle == 2'b10);

	//
	wire extraBusControl = (busCycle == 2'b01);
	
	// DTACK generation	
	// TODO: delay DTACK for once full bus cycle when RAM is accessed, to match Mac Plus memory timing
	// TODO: according to datasheet, /DTACK should continue to be asserted through the final bus cycle too
	assign _cpuDTACK = ~(_cpuAS == 1'b0 && cpuBusControl);
	
	// interconnects
	wire selectRAM, selectROM;
	wire [21:0] videoAddr;
	
	// RAM/ROM control signals
	wire videoControlActive = _hblank;

	wire extraRomRead = dskReadAckInt || dskReadAckExt;
	assign _romOE = ~(extraRomRead || (cpuBusControl && selectROM == 1'b1 && _cpuRW == 1'b1)); 
	
	wire extraRamRead = sndReadAck;
	assign _ramOE = ~((videoBusControl && videoControlActive == 1'b1) || (extraRamRead) ||
						(cpuBusControl && selectRAM == 1'b1 && _cpuRW == 1'b1));
	assign _ramWE = ~(cpuBusControl && selectRAM && _cpuRW == 1'b0);
	
	assign _memoryUDS = cpuBusControl ? _cpuUDS : 1'b0;
	assign _memoryLDS = cpuBusControl ? _cpuLDS : 1'b0;
	wire [21:0] addrMux = sndReadAck ? audioAddr : videoBusControl ? videoAddr : cpuAddr[21:0];
	wire [21:0] macAddr;
	assign macAddr[15:0] = addrMux[15:0];

	// video and sound always addresses ram
	wire ram_access = (cpuBusControl && selectRAM) || videoBusControl || sndReadAck;
	wire rom_access = (cpuBusControl && selectROM);
	
	// simulate smaller RAM/ROM sizes
	assign macAddr[16] = rom_access && configROMSize == 1'b0 ? 1'b0 :     // force A16 to 0 for 64K ROM access
									addrMux[16]; 
	assign macAddr[17] = ram_access && configRAMSize == 2'b00 ? 1'b0 :   // force A17 to 0 for 128K RAM access
									rom_access && configROMSize == 1'b1 ? 1'b0 :  // force A17 to 0 for 128K ROM access
									rom_access && configROMSize == 1'b0 ? 1'b1 :  // force A17 to 1 for 64K ROM access (64K ROM image is at $20000)
									addrMux[17]; 
	assign macAddr[18] = ram_access && configRAMSize == 2'b00 ? 1'b0 :   // force A18 to 0 for 128K RAM access
									rom_access ? 1'b0 : 								   // force A18 to 0 for ROM access
									addrMux[18]; 
	assign macAddr[19] = ram_access && configRAMSize[1] == 1'b0 ? 1'b0 : // force A19 to 0 for 128K or 512K RAM access
									rom_access ? 1'b0 : 								   // force A19 to 0 for ROM access
									addrMux[19]; 
	assign macAddr[20] = ram_access && configRAMSize != 2'b11 ? 1'b0 :   // force A20 to 0 for all but 4MB RAM access
									rom_access ? 1'b0 : 								   // force A20 to 0 for ROM access
									addrMux[20]; 
	assign macAddr[21] = ram_access && configRAMSize != 2'b11 ? 1'b0 :   // force A21 to 0 for all but 4MB RAM access
									rom_access ? 1'b0 : 								   // force A21 to 0 for ROM access
									addrMux[21]; 
	
	// allocate memory slots in the extra cycle
	reg [2:0] extra_slot_count;
	always @(posedge clk8)
		if(busCycle == 2'b11) 
			extra_slot_count <= extra_slot_count + 2'd1;
			
	// floppy emulation gets extra slots 0 and 1
	assign dskReadAckInt = (extraBusControl == 1'b1) && (extra_slot_count == 0);
	assign dskReadAckExt = (extraBusControl == 1'b1) && (extra_slot_count == 1);
	// audio gets extra slot 2
	assign sndReadAck    = (extraBusControl == 1'b1) && (extra_slot_count == 2);

	assign memoryAddr = 
		dskReadAckInt ? dskReadAddrInt + 22'h100000:   // first dsk image at 1MB
		dskReadAckExt ? dskReadAddrExt + 22'h200000:   // second dsk image at 2MB
		macAddr;

	// address decoding
	wire selectSCCByAddress;
	wire selectIWMByAddress;
	wire selectVIAByAddress;
	addrDecoder ad(
		.address(cpuAddr),
		.enable(!videoBusControl),
		._cpuAS(_cpuAS),
		.memoryOverlayOn(memoryOverlayOn),
		.selectRAM(selectRAM),
		.selectROM(selectROM),
		.selectSCC(selectSCCByAddress),
		.selectIWM(selectIWMByAddress),
		.selectVIA(selectVIAByAddress));
		
	/* TH: The following isn't 100% true anymore but kept for now for documentation purposes ...
	
		SCC register access is a mess. Reads and writes can have side-effects that alter the meaning of subsequent reads
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
	assign selectSCC = selectSCCByAddress && cpuBusControl;
	assign selectIWM = selectIWMByAddress && cpuBusControl;
	assign selectVIA = selectVIAByAddress && cpuBusControl;
	
	// video
	videoTimer vt(
		.clk8(clk8), 
		.busCycle(busCycle), 
		.videoAddr(videoAddr), 
		.hsync(hsync), 
		.vsync(vsync), 
		._hblank(_hblank),
		._vblank(_vblank), 
		.loadPixels(loadPixels));
		
endmodule
