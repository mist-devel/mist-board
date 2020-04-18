module addrController_top(
	// clocks:
	input clk,
	input clk8_en_p, // 8.125 MHz CPU clock enables
	input clk8_en_n,

	// system config:
	input turbo,               // 0 = normal, 1 = faster
	input configROMSize,			// 0 = 64K ROM, 1 = 128K ROM
	input [1:0] configRAMSize,	// 0 = 128K, 1 = 512K, 2 = 1MB, 3 = 4MB RAM

	// 68000 CPU memory interface:
	input [23:0] cpuAddr,
	input _cpuUDS,
	input _cpuLDS,
	input _cpuRW,	
	
	// RAM/ROM:
	output [21:0] memoryAddr,
	output _memoryUDS,
	output _memoryLDS,	
	output _romOE,
	output _ramOE,	
	output _ramWE,	
	output videoBusControl,
	output dioBusControl,
	output cpuBusControl,
	
	// peripherals:
	output selectSCSI,
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

	localparam SIZE = 20'd135408;  // 168*806 clk8 events per frame
	localparam STEP = 20'd5920;    // one step every 16*370 clk8 events
	
	reg [21:0] audioAddr; 
	reg [19:0] snd_div;
	
	reg sndReadAckD;
	always @(posedge clk)
		if (clk8_en_n) sndReadAckD <= sndReadAck;
	
	reg vblankD, vblankD2;
	always @(posedge clk) begin
		if(clk8_en_p && sndReadAckD) begin
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
	reg [1:0] extra_slot_count;
	reg [1:0] subCycle;

	always @(posedge clk)
		if (clk8_en_p) busCycle <= busCycle + 2'd1;

	reg extra_slot_advance;
	always @(posedge clk)
		if (clk8_en_n) extra_slot_advance <= (busCycle == 2'b11);

	// allocate memory slots in the extra cycle
	always @(posedge clk) begin
		if(clk8_en_p && extra_slot_advance) begin
			extra_slot_count <= extra_slot_count + 2'd1;
			
			// the subcycle counter counts 0-1-2-0-1-2 and is used to give
			// the cpu 2 out of three bus cycles for a speed close to a real mac
			
			// Update: Counter now runs 0-1-2-3-0-1-2... so the CPU runs 3 out of
			// 4 cycles. Making it slower (e.g. 2/3) will cause the floppy ot stop
			// working reliably. Making it faster will cause scsi to stop working ...
			
	//		if(subCycle == 2'd2) subCycle <= 2'd0;
	//		else  
			subCycle <= subCycle + 2'd1;
		end
	end

	// video controls memory bus during the first clock of the four-clock cycle
	assign videoBusControl = (busCycle == 2'b00);
	// cpu controls memory bus during the third clock of the four-clock cycle
	assign cpuBusControl = turbo?cpuBusControl_fast:cpuBusControl_normal;
	wire cpuBusControl_normal = (busCycle == 2'b01) && (subCycle != 2'd2);
	wire cpuBusControl_fast = (busCycle == 2'b01) || (busCycle == 2'b11);

	wire extraBusControl = (busCycle == 2'b10);
		
	// interconnects
	wire selectRAM, selectROM;
	wire [21:0] videoAddr;
	
	// RAM/ROM control signals
	wire videoControlActive = _hblank;

	wire extraRomRead = dskReadAckInt || dskReadAckExt;
	assign _romOE = ~(extraRomRead || (cpuBusControl && selectROM && _cpuRW)); 
	
	wire extraRamRead = sndReadAck;
	assign _ramOE = ~((videoBusControl && videoControlActive) || (extraRamRead) ||
						(cpuBusControl && selectRAM && _cpuRW));
	assign _ramWE = ~(cpuBusControl && selectRAM && !_cpuRW);
	
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
	addrDecoder ad(
		.address(cpuAddr),
		.memoryOverlayOn(memoryOverlayOn),
		.selectRAM(selectRAM),
		.selectROM(selectROM),
		.selectSCSI(selectSCSI),
		.selectSCC(selectSCC),
		.selectIWM(selectIWM),
		.selectVIA(selectVIA));

	// video
	videoTimer vt(
		.clk(clk),
		.clk_en(clk8_en_p),
		.busCycle(busCycle), 
		.videoAddr(videoAddr), 
		.hsync(hsync), 
		.vsync(vsync), 
		._hblank(_hblank),
		._vblank(_vblank), 
		.loadPixels(loadPixels));
		
endmodule
