module debugPanel(
	input clk8,
	input [9:0] sw,
	input [3:0] key,
	input videoBusControl,
	input loadNormalPixels,
	input loadDebugPixels,
	output loadPixelsOut,
	input _dtackIn,
	input [7:0] cpuAddrHi,
	input [23:0] cpuAddr,
	input _cpuRW,
	input _cpuUDS,
	input _cpuLDS,
	input [15:0] dataControllerDataOut,
	input [15:0] cpuDataOut,
	input [21:0] memoryAddr,
	output _dtackOut,
	output [6:0] hex0,
	output [6:0] hex1,
	output [6:0] hex2,
	output [6:0] hex3,
	output driveDebugData,
	output [15:0] debugDataOut,
	input extraRomReadAck
);

	/* debug interface:
		sw0 = run/stop_and_disable_interrupts
		sw2-9 = data in
		key0 = step	
		key1 = load breakpoint addr[7:0]
		key2 = load breakpoint addr[15:8]
		key3 = load breakpoint addr[23:16]
		key0+key1 = reset
	*/
	
	wire singleStep = sw[0];
	
	// sample dataControllerDataOut only when CPU owns the bus
	// use negative edge sample, since that's when the CPU latches data
	reg [15:0] dataControllerDataOutSample;
	always @(negedge clk8) begin
		if (videoBusControl == 0)
			dataControllerDataOutSample <= dataControllerDataOut;
	end
	
	// store the previous address, sort of a previous instruction address
	reg [23:0] previousAddr;
	reg [23:0] currAddr;
	always @(negedge clk8) begin
		if (videoBusControl == 1'b0 && cpuAddr != currAddr) begin
			previousAddr <= currAddr;
			currAddr <= cpuAddr;
		end	
	end
	
	reg [23:0] breakpointAddr = 24'hDABEEF;
	always @(negedge clk8) begin
		if (singleStep == 1'b1 && key[1] == 1'b0)
			breakpointAddr[7:0] <= sw[9:2];
		else if (singleStep == 1'b1 && key[2] == 1'b0)
			breakpointAddr[15:8] <= sw[9:2];
		else if (singleStep == 1'b1 && key[3] == 1'b0)
			breakpointAddr[23:16] <= sw[9:2];	
	end
	
	// find xy position for debug panel
	assign driveDebugData = loadDebugPixels && (memoryAddr[16:0] < 17'h00200);
	assign loadPixelsOut = loadNormalPixels | driveDebugData;
	wire [4:0] pixX = memoryAddr[5:1]; // 16-bit word: 0 to 31
	wire [2:0] pixY = memoryAddr[8:6]; // row: 0 to 7
	
	// decide what characters to display
	reg [5:0] char0;
	reg [5:0] char1;
	always @(*) begin
		case (pixX)
			5'h0: begin
				char0 = 6'hA;
				char1 = 6'h3F;
			end
			5'h1: begin
				char0 = cpuAddr[23:20];
				char1 = cpuAddr[19:16];
			end
			5'h2: begin
				char0 = cpuAddr[15:12];
				char1 = cpuAddr[11:8];
			end
			5'h3: begin
				char0 = cpuAddr[7:4];
				char1 = cpuAddr[3:0];
			end
			5'h5: begin
				char0 = 6'hD;
				char1 = 6'h1;
			end
			5'h6: begin
				char0 = 6'h3F;
				char1 = dataControllerDataOutSample[15:12];
			end
			5'h7: begin
				char0 = dataControllerDataOutSample[11:8];
				char1 = dataControllerDataOutSample[7:4];
			end
			5'h8: begin
				char0 = dataControllerDataOutSample[3:0];
				char1 = 6'h3F;
			end
			5'h9: begin
				char0 = 6'h3F;
				char1 = 6'hD;
			end		
			5'hA: begin
				char0 = 6'h0;
				char1 = 6'h3F;
			end	
			5'hB: begin
				char0 = cpuDataOut[15:12];
				char1 = cpuDataOut[11:8];
			end	
			5'hC: begin
				char0 = cpuDataOut[7:4];
				char1 = cpuDataOut[3:0];
			end	
			5'hD: begin
				char0 = 6'h3F;
				char1 = _cpuRW ? 6'h1 : 6'h0;
			end
			5'hE: begin
				char0 = _cpuUDS ? 6'h1 : 6'h0;
				char1 = _cpuLDS ? 6'h1 : 6'h0;
			end			
			5'hF: begin
				char0 = 6'h3F;
				char1 = 6'hA;
			end
			5'h10: begin
				char0 = 6'hA;
				char1 = 6'h3F;				
			end
			5'h11: begin
				char0 = previousAddr[23:20];
				char1 = previousAddr[19:16];
			end
			5'h12: begin
				char0 = previousAddr[15:12];
				char1 = previousAddr[11:8];
			end
			5'h13: begin
				char0 = previousAddr[7:4];
				char1 = previousAddr[3:0];
			end			
			5'h14: begin
				char0 = 6'h3F;
				char1 = 6'h3F;
			end
			5'h15: begin
				char0 = 6'hB;
				char1 = 6'h3F;
			end			
			5'h16: begin
				char0 = breakpointAddr[23:20];
				char1 = breakpointAddr[19:16];
			end
			5'h17: begin
				char0 = breakpointAddr[15:12];
				char1 = breakpointAddr[11:8];
			end
			5'h18: begin
				char0 = breakpointAddr[7:4];
				char1 = breakpointAddr[3:0];
			end			
			default: begin
				char0 = 6'h3F;
				char1 = 6'h3F;
			end
		endcase
	end
	
	// map characters to font data
	wire [7:0] font0;
	wire [7:0] font1;
	fontGen fg0(.char(char0), .row(pixY), .dataOut(font0));
	fontGen fg1(.char(char1), .row(pixY), .dataOut(font1));
	assign debugDataOut = { font0, font1 };
	
	// display extra ROM data on 7-segment LEDs
	reg [7:0] extraRomData;
	always @(posedge clk8) begin
		if (extraRomReadAck) begin
			extraRomData <= dataControllerDataOut[7:0];
		end
	end
	
	// map the chosen data to the hex display
	led7seg ls0(.data(extraRomData[3:0]), .segments(hex0));
	led7seg ls1(.data(extraRomData[7:4]), .segments(hex1));
	led7seg ls2(.data({4'b0000}), .segments(hex2));
	led7seg ls3(.data({4'b0000}), .segments(hex3));
	
	// withhold DTACK if stopped and delay timer != 0
	reg [19:0] delayDTACK;
	assign _dtackOut = (singleStep == 1'b0 && cpuAddr != breakpointAddr) ? _dtackIn : (_dtackIn | (delayDTACK != 0));
	
	// debounce step key and set DTACK delay timer
	always @(posedge clk8) begin
		if (key[0] == 1'b1)
			delayDTACK = 20'hFFFFE;
		else
			if (delayDTACK != 0 && delayDTACK != 20'hFFFFF)
				delayDTACK = delayDTACK - 1'b1;
			else if (delayDTACK == 0 && _dtackIn == 0)
				delayDTACK = 20'hFFFFF;
	end	
	
endmodule
