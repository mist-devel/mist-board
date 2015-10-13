module dataController_top(
	// clocks:
	input clk32,					// 32.5 MHz pixel clock
	input clk8,						// 8.125 MHz CPU clock
	output clk8out,				// this module generates the 8.125MHz clock used for itself and other modules
	
	// system control:
	input _systemReset,

	// 68000 CPU control:
	output _cpuReset,
	output [2:0] _cpuIPL,

	// 68000 CPU memory interface:
	input [15:0] cpuDataIn,
	input [3:0] cpuAddrRegHi, // A12-A9
	input [1:0] cpuAddrRegLo, // A2-A1
	input _cpuUDS,
	input _cpuLDS,	
	input _cpuRW,
	output [15:0] cpuDataOut,
	output cpuDriveData,
	
	// peripherals:
	input selectSCC,
	input selectIWM,
	input selectVIA,
	input selectInterruptVectors,
	
	// RAM/ROM:
	input videoBusControl,	
	input [15:0] memoryDataIn,
	output [15:0] memoryDataOut,
	output memoryDriveData,
	
	// keyboard:
	input keyClk, 					// need pull-up
	input keyData, 				// need pull-up
	 
	// mouse:
	inout mouseClk, 				// need pull-up
	inout mouseData, 				// need pull-up
	
	// serial:
	input serialIn, 				// need pull-up
	output serialOut,	
	
	// video:
	output pixelOut,	
	input _hblank,
	input _vblank,
	input loadPixels,

	// audio:
	input loadSound,	
	output sound,	
	
	// debugging:
	input interruptButton,
	
	// misc
	output memoryOverlayOn,
	input [1:0] insertDisk,
	output [1:0] diskInDrive,
	
	output [21:0] extraRomReadAddr,
	input extraRomReadAck
);
	
	// divide 32.5 MHz clock by four to get CPU clock
	reg [1:0] clkPhase;
	always @(posedge clk32) begin
		clkPhase <= clkPhase + 1'b1;
	end
	assign clk8out = clkPhase[1];
	
	// CPU reset generation
	// For initial CPU reset, RESET and HALT must be asserted for at least 100ms = 800,000 clocks of clk8
	reg [19:0] resetDelay; // 20 bits = 1 million
	wire isResetting = resetDelay != 0;
	
	initial begin
		// force a reset when the FPGA configuration is completed
		resetDelay <= 20'hFFFFF;
	end
	
	always @(posedge clk8 or negedge _systemReset) begin
		if (_systemReset == 1'b0) begin
			resetDelay <= 20'hFFFFF;
		end
		else if (isResetting) begin
			resetDelay <= resetDelay - 1'b1;
		end
	end
	assign _cpuReset = isResetting ? 1'b0 : 1'b1;
	
	// interconnects
	wire SEL;
	wire _viaIrq, _sccIrq, sccWReq;
	wire [15:0] viaDataOut;
	wire [15:0] iwmDataOut;
	wire [7:0] sccDataOut;
	wire mouseX1, mouseX2, mouseY1, mouseY2, mouseButton;
	
	// interrupt control
	assign _cpuIPL = { interruptButton, _sccIrq, ~(_sccIrq & ~_viaIrq) };
	
	// Sound
	assign sound = 0;
	
	// Serial port
	assign serialOut = 0;
	
	// CPU-side data output mux
	assign cpuDataOut = selectIWM ? iwmDataOut :
							  selectVIA ? viaDataOut :
							  selectSCC ? { sccDataOutDelayed, 8'hEF } :
							  selectInterruptVectors ? { 13'h3, cpuAddrRegLo } : // use A3-A1 to construct an interrupt vector number offset from $18
							  memoryDataIn;	
	assign cpuDriveData = _cpuRW == 1'b1;
	
	// Memory-side
	assign memoryDataOut = cpuDataIn;
	assign memoryDriveData = _cpuRW == 1'b0 && videoBusControl == 1'b0;
	
	// VIA
	via v(
		.clk8(clk8),
		._reset(_cpuReset),
		.selectVIA(selectVIA),
		._cpuRW(_cpuRW),
		._cpuUDS(_cpuUDS),	
		.dataIn(cpuDataIn),
		.cpuAddrRegHi(cpuAddrRegHi),
		._hblank(_hblank),
		._vblank(_vblank),
		.mouseY2(mouseY2),
		.mouseX2(mouseX2),
		.mouseButton(mouseButton),
		.sccWReq(sccWReq),
		._irq(_viaIrq),
		.dataOut(viaDataOut),
		.memoryOverlayOn(memoryOverlayOn),
		.SEL(SEL));
	
	// IWM
	iwm i(
		.clk8(clk8),
		._reset(_cpuReset),
		.selectIWM(selectIWM),
		._cpuRW(_cpuRW),
		._cpuLDS(_cpuLDS),
		.dataIn(cpuDataIn),
		.cpuAddrRegHi(cpuAddrRegHi),
		.SEL(SEL),
		.dataOut(iwmDataOut),
		.insertDisk(insertDisk),
		.diskInDrive(diskInDrive),
		
		.extraRomReadAddr(extraRomReadAddr),
		.extraRomReadAck(extraRomReadAck),
		.extraRomReadData(memoryDataIn[7:0]));

	// SCC
	scc s(
		.sysclk(clk8),
	   .reset_hw(~_cpuReset),
	   .cs(selectSCC && (_cpuLDS == 1'b0 || _cpuUDS == 1'b0)),
	   .we(~_cpuRW), 
	   .rs(cpuAddrRegLo), 
	   .wdata(cpuDataIn[15:8]),
	   .rdata(sccDataOut),
	   ._irq(_sccIrq),
		.dcd_a(mouseX1),
		.dcd_b(mouseY1),
		.wreq(sccWReq));
	
	// apply a one cycle delay to CPU data reads from the SCC: 
	// see comment about SCC register access in addrController_top.v
	reg [7:0] sccDataOutDelayed;
	always @(posedge clk8) begin
		sccDataOutDelayed <= sccDataOut;
	end
	
	// Video
	videoShifter vs(
		.clk32(clk32), 
		.clkPhase(clkPhase), 
		.dataIn(memoryDataIn), 
		.loadPixels(loadPixels), 
		.pixelOut(pixelOut));
	
	// Mouse
	ps2_mouse mouse(
		.sysclk(clk8),
		.reset(~_cpuReset),
		.ps2dat(mouseData),
		.ps2clk(mouseClk),
		.x1(mouseX1),
		.y1(mouseY1),
		.x2(mouseX2),
		.y2(mouseY2),
		.button(mouseButton));

endmodule
