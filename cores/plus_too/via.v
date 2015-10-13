/* VIA
	
	This implementation assumes the I/O data directions and PCR edge triggers used in the Macintosh,
	and ignores most writes to the VIA data direction registers and the PCR.
	
	The 16 VIA registers are mapped to addresses {8'hEF, 8'b111xxxx1, 8'hFE}:
			0	$0		vBufB		register B
			1	$200	?????		register A (controls handshake)
			2	$400	vDirB		register B direction register
			3	$600	vDirA		register A direction register
			4	$800	vT1C		timer 1 counter (low-order byte) - for sound?
			5	$A00	vT1CH		timer 1 counter (high-order byte)
			6	$C00	vT1L		timer 1 latch (low-order byte)
			7	$E00	vT1LH		timer 1 latch (high-order byte)
			8	$1000	vT2C		timer 2 counter (low-order byte) - W: writes T2L-L R: read T2C-L and clear interrupt flag
			9	$1200	vT2CH		timer 2 counter (high-order byte) - W: write T2C-H, transfer T2L-L to T2C-L, clear interrupt flag R: read T2C-H
			10	$1400	vSR		shift register (keyboard)
			11	$1600	vACR		auxiliary control register
			12	$1800	vPCR		peripheral control register
			13	$1A00	vIFR		interrupt flag register
			14	$1C00	vIER		interrupt enable register
			15	$1E00	vBufA		register A (no handshake)
			
	Register A:
		Bit(s)  Name             Dir	Description

		7       vSCCWReq         in	SCC wait/request
		6       vPage2           out	Alternate screen buffer (1 = main buffer)
		5       vHeadSel         out	Disk SEL line
		4       vOverlay         out	ROM low-memory overlay (1 = overlay on)
		3       vSndPg2          out	Alternate sound buffer (1 = main buffer)
		0-2     vSound (mask)    out	Sound volume

	Register B:
		Bit   Name       Dir		Description

		7     vSndEnb    out		Sound enable/disable
		6     vH4        in		Horizontal blanking
		5     vY2        in		Mouse Y2
		4     vX2        in		Mouse X2
		3     vSW        in		Mouse switch
		2     rTCEnb     out		Real-time clock serial enable (active low I think)
		1     rTCClk     out		Real-time clock data-clock line
		0     rTCData    in/out	Real-time clock serial data

	Interrupt flag and enable registers:
		IFR bit 7: remains set (and the IRQ line to the processor is held low) as long as any enabled VIA
					  interrupt is occurring. 
		IER bit 7: "enable/disable":  If bit 7 is a 1, each 1 in bits 0-6 enables the corresponding interrupt; 
					  if bit 7 is a 0, each 1 in bits 0-6 disables that interrupt. In either case, 0's in bits 0-6 do not
					  change the status of those interrupts. Bit 7 is always read as a 1. 
					  
		Bit   Interrupting device

		7     IRQ (IFR) or enable (IER)
		6     Timer 1 timeout
		5     Timer 2 timeout
		4     Keyboard clock (CB1)
		3     Keyboard data bit (CB2)
		2     Keyboard data ready (completion of 8 shifts) (SR)
		1     Vertical blanking interrupt (CA1)
		0     One-second interrupt (CA2)

	Peripheral control register:
		Bit	Description
		
		5-7	CB2 control (keyboard data bit)
		4		CB1 control (keyboard clock)
		1-3	CA2 control (one-second interrupt)
		0		CA1 control (vertical blanking interrupt)
		
		1-bit controls: 0 = negative edge trigger (normal Macintosh mode), 1 = positive edge trigger
		3-bit controls: 
			000	set IFR on negative edge, clear IFR on read/write from register A/B. Normal Macintosh mode.
			001	set IFR on negative edge
			010	set IFR on positive edge, clear IFR on read/write from register A/B
			011	set IFR on positive edge
			100-111 not used in Macintosh (output mode)	
		
	Auxiliary control register:
		Bit	Description
		6-7	T1 control, 00 = one-shot mode, output to PB7 disabled, 11 = free running mode, output to PB7 enabled
		5		T2 control, 0 = interval timer in one-shot mode (Mac mode), 1 = counts a predetermined number of pulses on pin PB6 (not used)
		2-4	shift register control
		1		PB latch enable
		0		PA latch enable
		
	Timer 2:
		For Macintosh, always operates as a one-shot inerval timer.
		8	$1000	vT2C		W: write T2L-L R: read T2C-L and clear interrupt flag
		9	$1200	vT2CH		W: write T2C-H, transfer T2L-L to T2C-L, clear interrupt, arms timer flag R: read T2C-H		
*/

`define INT_ONESEC		0  
`define INT_VBLANK		1  
`define INT_KEYREADY		2
`define INT_KEYBIT		3
`define INT_KEYCLK		4
`define INT_T2				5
`define INT_T1				6

module via(
	input clk8,
	input _reset,
	input selectVIA,
	input _cpuRW,
	input _cpuUDS,	
	input [15:0] dataIn,
	input [3:0] cpuAddrRegHi,
	input _hblank,
	input _vblank,
	input mouseY2,
	input mouseX2,
	input mouseButton,
	input rtcData,
	input sccWReq,
	output _irq,
	output [15:0] dataOut,
	output memoryOverlayOn,
	output SEL // to IWM
);

	wire [7:0] dataInHi = dataIn[15:8];
	reg [7:0] dataOutHi;
	assign dataOut = { dataOutHi, 8'hEF };
	
	reg [7:0] viaADataOut;
	reg [7:0] viaBDataOut;
	reg viaB0DDR;
	reg [6:0] viaIFR;
	reg [6:0] viaIER;
	reg [7:0] viaACR;
	reg [15:0] viaTimer1Count;
	reg [15:0] viaTimer1Latch;
	reg [15:0] viaTimer2Count;
	reg [7:0] viaTimer2LatchLow;
	reg viaTimer2Armed;
	
	// divide by 10 clock divider for the VIA timers: 0.78336 MHz
	reg [3:0] clkDiv;
	always @(posedge clk8) begin
		if (clkDiv == 4'h9)
			clkDiv <= 0;
		else
			clkDiv <= clkDiv + 1'b1;
	end
	wire timerStrobe = (clkDiv == 0);
	
	// store previous vblank value, for edge detection
	reg _lastVblank;
	always @(posedge clk8) begin
		_lastVblank <= _vblank;
	end
	
	// count vblanks, and set 1 second interrupt after 60 vblanks
	reg [5:0] vblankCount;
	always @(posedge clk8) begin
		if (_vblank == 1'b0 && _lastVblank == 1'b1) begin
			if (vblankCount != 59) begin
				vblankCount <= vblankCount + 1'b1;
			end
			else begin
				vblankCount <= 6'h0;
			end
		end
	end
	assign _irq = (viaIFR & viaIER) == 0 ? 1'b1 : 1'b0;
	
	// register write
	wire loadT2 = selectVIA == 1'b1 && _cpuUDS == 1'b0 && _cpuRW == 1'b0 && cpuAddrRegHi == 4'h9;
	always @(posedge clk8 or negedge _reset) begin
		if (_reset == 1'b0) begin
			viaB0DDR <= 1'b1;
			viaADataOut <= 8'b01111111;
			viaBDataOut <= 8'b11111111;
			viaIFR <= 7'b0000000;
			viaIER <= 7'b0000000;
			viaACR <= 8'b00000000;
			viaTimer1Count <= 16'h0000;
			viaTimer1Latch <= 16'h0000;
			viaTimer2Count <= 16'h0000;
			viaTimer2LatchLow <= 8'h00;
			viaTimer2Armed <= 0;
		end
		else begin
			if (selectVIA == 1'b1 && _cpuUDS == 1'b0) begin
				if (_cpuRW == 1'b0) begin
					// normal register writes
					case (cpuAddrRegHi)
						4'h0: // B
							viaBDataOut <= dataInHi;
						4'h2: // B DDR
							viaB0DDR <= dataInHi[0];
						// 4'h3: ignore A DDR
						4'h4: // timer 1 count low
							viaTimer1Count[7:0] <= dataInHi;
						4'h5: // timer 1 count high
							viaTimer1Count[15:8] <= dataInHi;
						4'h6: // timer 1 latch low
							viaTimer1Latch[7:0] <= dataInHi;
						4'h7: // timer 1 latch high
							viaTimer1Latch[15:8] <= dataInHi;
						4'h8: // timer 2 latch low
							viaTimer2LatchLow <= dataInHi;
						4'h9: begin // timer 2 count high
							viaTimer2Count[15:8] <= dataInHi;
							viaTimer2Count[7:0] <= viaTimer2LatchLow;
							viaTimer2Armed = 1'b1;
							viaIFR[`INT_T2] <= 1'b0;
						end
						4'hB: // Aux control register
							viaACR <= dataInHi;		
						// 4'hC: ignore PCR
						4'hD: // IFR
							viaIFR <= viaIFR & ~dataInHi[6:0];
						4'hE: // IER
							if (dataInHi[7])
								viaIER <= viaIER | dataInHi[6:0];
							else
								viaIER <= viaIER & ~dataInHi[6:0];
						4'hF: // A		
							viaADataOut <= dataInHi;
					endcase
				end
				else begin
					// interrupt flag modifications due to register reads
					case (cpuAddrRegHi)
						4'h0: begin // reading (and writing?) register B clears KEYCLK and KEYBIT interrupt flags
							viaIFR[`INT_KEYCLK] <= 1'b0;
							viaIFR[`INT_KEYBIT] <= 1'b0;
						end
						4'h8: // reading T2C-L clears the T2 interrupt flag
							viaIFR[`INT_T2] <= 1'b0; 
						4'hF: begin // reading (and writing?) register A clears VBLANK and ONESEC interrupt flags
							viaIFR[`INT_ONESEC] <= 1'b0;
							viaIFR[`INT_VBLANK] <= 1'b0;
						end
					endcase
				end
			end
			// external interrupts
			if (_vblank == 1'b0 && _lastVblank == 1'b1) begin
				viaIFR[`INT_VBLANK] <= 1'b1; // set vblank interrupt
				if (vblankCount == 59) 	
					viaIFR[`INT_ONESEC] <= 1'b1; // set one second interrupt after 60 vblanks
			end				
			// timer 2
			if (timerStrobe && !loadT2) begin
				if (viaTimer2Armed && viaTimer2Count == 0) begin
					viaIFR[`INT_T2] <= 1'b1;
					viaTimer2Armed <= 0;
				end
				viaTimer2Count <= viaTimer2Count - 1'b1;
			end
		end
	end
	
	// register read
	always @(*) begin
		dataOutHi = 8'hBE;
		
		if (_cpuRW == 1'b1 && selectVIA == 1'b1 && _cpuUDS == 1'b0) begin
			case (cpuAddrRegHi)
				4'h0: // B
					// TODO: clear CB1 and CB2 interrupts
					dataOutHi = { viaBDataOut[7], ~_hblank, mouseY2, mouseX2, mouseButton, viaBDataOut[2:1], viaB0DDR == 1'b1 ? viaBDataOut[0] : rtcData };
				4'h2: // B DDR
					dataOutHi = { 7'b1000011, viaB0DDR };
				4'h3: // A DDR
					dataOutHi = 8'b01111111;
				4'h4: // timer 1 count low
					dataOutHi = viaTimer1Count[7:0];
				4'h5: // timer 1 count high
					dataOutHi = viaTimer1Count[15:8];
				4'h6: // timer 1 latch low
					dataOutHi = viaTimer1Latch[7:0];
				4'h7: // timer 1 latch high
					dataOutHi = viaTimer1Latch[15:8];
				4'h8: // timer 2 count low
					dataOutHi = viaTimer2Count[7:0]; 
				4'h9: // timer 2 count high
					dataOutHi = viaTimer2Count[15:8];	
				4'hB: // Aux control register
					dataOutHi = viaACR;
				4'hC: // PCR
					dataOutHi = 0; 					
				4'hD: // IFR
					dataOutHi = { viaIFR & viaIER == 0 ? 1'b0 : 1'b1, viaIFR };
				4'hE: // IER
					dataOutHi = { 1'b1, viaIER };			
				4'hF: // A
					// TODO: clear CA1 and CA2 interrupts
					dataOutHi = { sccWReq, viaADataOut[6:0] };
				default:
					dataOutHi = 8'hBE;
			endcase
		end	
	end
	
	assign memoryOverlayOn = viaADataOut[4];
	assign SEL = viaADataOut[5];
	
endmodule
