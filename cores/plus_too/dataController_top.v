module dataController_top(
	// clocks:
	input clk32,					// 32.5 MHz pixel clock
	output clk8,						// 8.125 MHz CPU clock
	output clk8_en_p,
	output clk8_en_n,
	
	// system control:
	input _systemReset,

	// 68000 CPU control:
	output _cpuReset,
	output [2:0] _cpuIPL,

	// 68000 CPU memory interface:
	input [15:0] cpuDataIn,
	input [3:0] cpuAddrRegHi, // A12-A9
	input [2:0] cpuAddrRegMid, // A6-A4
	input [1:0] cpuAddrRegLo, // A2-A1
	input _cpuUDS,
	input _cpuLDS,	
	input _cpuRW,
	output [15:0] cpuDataOut,
	
	// peripherals:
	input selectSCSI,
	input selectSCC,
	input selectIWM,
	input selectVIA,
	
	// RAM/ROM:
	input videoBusControl,	
	input cpuBusControl,	
	input [15:0] memoryDataIn,
	output [15:0] memoryDataOut,
	
	// keyboard:
	input keyClk, 
	input keyData, 
	 
	// mouse:
	input mouseClk, 
	input mouseData,
	
	// serial:
	input serialIn, 
	output serialOut,	
	
	// video:
	output pixelOut,	
	input _hblank,
	input _vblank,
	input loadPixels,

	// audio
	output [10:0] audioOut,  // 8 bit audio + 3 bit volume
	output snd_alt,
	input loadSound,
	
	// misc
	output memoryOverlayOn,
	input [1:0] insertDisk,
	input [1:0] diskSides,
	output [1:0] diskEject,
	output [1:0] diskMotor,
	output [1:0] diskAct,

	output [21:0] dskReadAddrInt,
	input dskReadAckInt,
	output [21:0] dskReadAddrExt,
	input dskReadAckExt,

	// connections to io controller
	input   [1:0] img_mounted,
	input  [31:0] img_size,
	output [31:0] io_lba,
	output  [1:0] io_rd,
	output  [1:0] io_wr,
	input         io_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr
);
	
	// add binary volume levels according to volume setting
	assign audioOut = 
		(snd_vol[0]?audio_x1:11'd0) +
		(snd_vol[1]?audio_x2:11'd0) +
		(snd_vol[2]?audio_x4:11'd0);

	// three binary volume levels *1, *2 and *4, sign expanded
	wire [10:0] audio_x1 = { {3{audio_latch[7]}}, audio_latch };
	wire [10:0] audio_x2 = { {2{audio_latch[7]}}, audio_latch, 1'b0 };
	wire [10:0] audio_x4 = {    audio_latch[7]  , audio_latch, 2'b00};
	
	reg loadSoundD;
	always @(posedge clk32)
		if (clk8_en_n) loadSoundD <= loadSound;

	// read audio data and convert to signed for further volume adjustment
	reg [7:0] audio_latch;
	always @(posedge clk32) begin
		if(clk8_en_p && loadSoundD) begin
			if(snd_ena) audio_latch <= 8'h00;
			else  	 	audio_latch <= memoryDataIn[15:8] - 8'd128;
		end
	end
	
	// divide 32.5 MHz clock by four to get CPU clock
	reg [1:0] clkPhase;
	always @(posedge clk32)
		clkPhase <= clkPhase + 2'd1;
	assign clk8 = clkPhase[1];
	assign clk8_en_p = clkPhase == 2'b01;
	assign clk8_en_n = clkPhase == 2'b11;
	
	// CPU reset generation
	// For initial CPU reset, RESET and HALT must be asserted for at least 100ms = 800,000 clocks of clk8
	reg [19:0] resetDelay; // 20 bits = 1 million
	wire isResetting = resetDelay != 0;
	
	initial begin
		// force a reset when the FPGA configuration is completed
		resetDelay <= 20'hFFFFF;
	end
	
	always @(posedge clk32 or negedge _systemReset) begin
		if (_systemReset == 1'b0) begin
			resetDelay <= 20'hFFFFF;
		end
		else if (clk8_en_p && isResetting) begin
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
	wire [7:0] scsiDataOut;
	wire mouseX1, mouseX2, mouseY1, mouseY2, mouseButton;
	
	// interrupt control
	assign _cpuIPL = 
		!_viaIrq?3'b110:
		!_sccIrq?3'b101:
		3'b111;
		
	// Serial port
	assign serialOut = 0;
	
	// CPU-side data output mux
	assign cpuDataOut = selectIWM ? iwmDataOut :
							  selectVIA ? viaDataOut :
							  selectSCC ? { sccDataOut, 8'hEF } :
							  selectSCSI ? { scsiDataOut, 8'hEF } :
							  memoryDataIn;	
	
	// Memory-side
	assign memoryDataOut = cpuDataIn;

	// SCSI
	ncr5380 scsi(
		.clk(clk32),
		.ce(clk8_en_p),
		.reset(!_cpuReset),
		.bus_cs(selectSCSI && cpuBusControl),
		.bus_we(!_cpuRW),
		.bus_rs(cpuAddrRegMid),
		.dack(cpuAddrRegHi[0]),   // A9
		.wdata(cpuDataIn[15:8]),
		.rdata(scsiDataOut),

		// connections to io controller
		.img_mounted( img_mounted ),
		.img_size( img_size ),
		.io_lba ( io_lba ),
		.io_rd ( io_rd ),
		.io_wr ( io_wr ),
		.io_ack ( io_ack ),

		.sd_buff_addr(sd_buff_addr),
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_din(sd_buff_din),
		.sd_buff_wr(sd_buff_wr)
	);

	// VIA
	wire [2:0] snd_vol;
	wire snd_ena;
	
	via v(
		.clk32(clk32),
		.clk8_en_p(clk8_en_p),
		.clk8_en_n(clk8_en_n),
		._reset(_cpuReset),
		.selectVIA(selectVIA && cpuBusControl),
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
		.SEL(SEL),
		
		.snd_vol(snd_vol),
		.snd_ena(snd_ena),
		.snd_alt(snd_alt),
		
		.kbd_in_data(kbd_in_data),
		.kbd_in_strobe(kbd_in_strobe),
		.kbd_out_data(kbd_out_data),
		.kbd_out_strobe(kbd_out_strobe)
		);
		
	// IWM
	iwm i(
		.clk(clk32),
		.cep(clk8_en_p),
		.cen(clk8_en_n),
		._reset(_cpuReset),
		.selectIWM(selectIWM && cpuBusControl),
		._cpuRW(_cpuRW),
		._cpuLDS(_cpuLDS),
		.dataIn(cpuDataIn),
		.cpuAddrRegHi(cpuAddrRegHi),
		.SEL(SEL),
		.dataOut(iwmDataOut),
		.insertDisk(insertDisk),
		.diskSides(diskSides),
		.diskEject(diskEject),
		.diskMotor(diskMotor),
		.diskAct(diskAct),

		.dskReadAddrInt(dskReadAddrInt),
		.dskReadAckInt(dskReadAckInt),
		.dskReadAddrExt(dskReadAddrExt),
		.dskReadAckExt(dskReadAckExt),
		.dskReadData(memoryDataIn[7:0])
	);

	// SCC
	scc s(
		.clk(clk32),
		.cep(clk8_en_p),
		.cen(clk8_en_n),
		.reset_hw(~_cpuReset),
		.cs(selectSCC && (_cpuLDS == 1'b0 || _cpuUDS == 1'b0) && cpuBusControl),
		.we(!_cpuRW),
		.rs(cpuAddrRegLo), 
		.wdata(cpuDataIn[15:8]),
		.rdata(sccDataOut),
		._irq(_sccIrq),
		.dcd_a(mouseX1),
		.dcd_b(mouseY1),
		.wreq(sccWReq));
		
	// Video
	videoShifter vs(
		.clk32(clk32), 
		.clkPhase(clkPhase), 
		.dataIn(memoryDataIn), 
		.loadPixels(loadPixels), 
		.pixelOut(pixelOut));
	
	// Mouse
	ps2_mouse mouse(
		.sysclk(clk32),
		.clk_en(clk8_en_p),
		.reset(~_cpuReset),
		.ps2dat(mouseData),
		.ps2clk(mouseClk),
		.x1(mouseX1),
		.y1(mouseY1),
		.x2(mouseX2),
		.y2(mouseY2),
		.button(mouseButton));

	wire [7:0] kbd_in_data;
	wire kbd_in_strobe;
	wire [7:0] kbd_out_data;
	wire kbd_out_strobe;

	// Keyboard
	ps2_kbd kbd(
		.sysclk(clk32),
		.clk_en(clk8_en_p),
		.reset(~_cpuReset),
		.ps2dat(keyData),
		.ps2clk(keyClk),
		.data_out(kbd_out_data),              // data from mac
		.strobe_out(kbd_out_strobe),
		.data_in(kbd_in_data),         // data to mac
		.strobe_in(kbd_in_strobe));
		
endmodule
