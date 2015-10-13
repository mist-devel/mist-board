/* IWM 

   Mapped to $DFE1FF - $DFFFFF
	
	The 16 IWM one-bit registers are {8'hDF, 8'b111xxxx1, 8'hFF}:
		0	$0		ca0L		CA0 off (0)
		1	$200	ca0H		CA0 on (1)
		2	$400	ca1L		CA1 off (0)
		3	$600	ca1H		CA1 on (1)
		4	$800	ca2L		CA2 off (0)
		5	$A00	ca2H		CA2 on (1)
		6	$C00	ph3L		LSTRB off (low)
		7	$E00	ph3H		LSTRB on (high)
		8	$1000	mtrOff	ENABLE disk enable off
		9	$1200	mtrOn		ENABLE disk enable on
		10	$1400	intDrive	SELECT select internal drive
		11	$1600	extDrive	SELECT select external drive
		12	$1800	q6L		Q6 off
		13	$1A00	q6H		Q6 on
		14	$1C00	q7L		Q7 off, read register
		15	$1E00	q7H		Q7 on, write register
	
	Notes from IWM manual:
	Serial data is shifted in/out MSB first, with a bit transferred every 2 microseconds.
	When writing data, a 1 is written as a transition on writeData at a bit cell boundary time, and a 0 is written as no transition.
	When reading data, a falling transition within a bit cell window is considered to be a 1, and no falling transition is considered a 0.
	When reading data, the read data register will latch the shift register when a 1 is shifted into the MSB.
	The read data register will be cleared 14 fclk periods (about 2 microseconds) after a valid data read takes place-- a valid data read 
	   being defined as both /DEV being low and D7 (the MSB) outputting a one from the read data register for at least one fclk period.
*/		

module iwm(
	input clk8,
	input _reset,
	input selectIWM,
	input _cpuRW,
	input _cpuLDS,	
	input [15:0] dataIn,
	input [3:0] cpuAddrRegHi,
	input SEL, // from VIA
	output [15:0] dataOut,
	input [1:0] insertDisk,
	output [1:0] diskInDrive,
	
	output [21:0] extraRomReadAddr,
	input extraRomReadAck,
	input [7:0] extraRomReadData
);

	wire [7:0] dataInLo = dataIn[7:0];
	reg [7:0] dataOutLo;
	assign dataOut = { 8'hBE, dataOutLo };
	
	// IWM state
	reg ca0, ca1, ca2, lstrb, selectExternalDrive, q6, q7;
	reg ca0Next, ca1Next, ca2Next, lstrbNext, selectExternalDriveNext, q6Next, q7Next;
	wire advanceDriveHead; // prevents overrun when debugging, does not exit on a real Mac!
	reg [7:0] writeData;
	reg [7:0] readDataLatch;
	wire _iwmBusy, _writeUnderrun;
	assign _iwmBusy = 1'b1; // for writes, a value of 1 here indicates the IWM write buffer is empty
	assign _writeUnderrun = 1'b1;

	// floppy disk drives 
	reg diskEnableExt, diskEnableInt;
	reg diskEnableExtNext, diskEnableIntNext;
	wire newByteReadyInt;
	wire [7:0] readDataInt;
	wire senseInt = readDataInt[7]; // bit 7 doubles as the sense line here
	wire newByteReadyExt;
	wire [7:0] readDataExt;
	wire senseExt = readDataExt[7]; // bit 7 doubles as the sense line here
	
	floppy floppyInt(
		.clk8(clk8),
		._reset(_reset),
		.ca0(ca0),
		.ca1(ca1),
		.ca2(ca2),
		.SEL(SEL),
		.lstrb(lstrb),
		._enable(~diskEnableInt),
		.writeData(writeData),
		.readData(readDataInt),
		.useDiskImage(1'b1),
		.advanceDriveHead(advanceDriveHead),
		.newByteReady(newByteReadyInt),
		.insertDisk(insertDisk[0]),
		.diskInDrive(diskInDrive[0]),
		.extraRomReadAddr(extraRomReadAddr),
		.extraRomReadAck(extraRomReadAck),
		.extraRomReadData(extraRomReadData));
	floppy floppyExt(
		.clk8(clk8),
		._reset(_reset),
		.ca0(ca0),
		.ca1(ca1),
		.ca2(ca2),
		.SEL(SEL),
		.lstrb(lstrb),
		._enable(~diskEnableExt),
		.writeData(writeData),
		.readData(readDataExt),
		.useDiskImage(1'b0),
		.advanceDriveHead(advanceDriveHead),
		.newByteReady(newByteReadyExt),
		.insertDisk(insertDisk[1]),
		.diskInDrive(diskInDrive[1]));
	
	wire [7:0] readData = selectExternalDrive ? readDataExt : readDataInt;
	wire newByteReady = selectExternalDrive ? newByteReadyExt : newByteReadyInt;
	
	reg [4:0] iwmMode;
	/* IWM mode register: S C M H L
 	 S	Clock speed:
			0 = 7 MHz
			1 = 8 MHz
		Should always be 1 for Macintosh.
	 C	Bit cell time:
			0 = 4 usec/bit (for 5.25 drives)
			1 = 2 usec/bit (for 3.5 drives) (Macintosh mode)
	 M	Motor-off timer:
			0 = leave drive on for 1 sec after program turns
			    it off
			1 = no delay (Macintosh mode)
		Should be 0 for 5.25 and 1 for 3.5.
	 H	Handshake protocol:
			0 = synchronous (software must supply proper
			    timing for writing data)
			1 = asynchronous (IWM supplies timing) (Macintosh Mode)
		Should be 0 for 5.25 and 1 for 3.5.
	 L	Latch mode:
			0 = read-data stays valid for about 7 usec
			1 = read-data stays valid for full byte time (Macintosh mode)
		Should be 0 for 5.25 and 1 for 3.5.
	*/

	// any read/write access to IWM bit registers will change their values
	always @(*) begin
		ca0Next <= ca0;
		ca1Next <= ca1;
		ca2Next <= ca2;
		lstrbNext <= lstrb;
		diskEnableExtNext <= diskEnableExt;
		diskEnableIntNext <= diskEnableInt;
		selectExternalDriveNext <= selectExternalDrive;
		q6Next <= q6;
		q7Next <= q7;
		
		if (selectIWM == 1'b1 && _cpuLDS == 1'b0) begin
			case (cpuAddrRegHi[3:1])
				3'h0: // ca0
					ca0Next <= cpuAddrRegHi[0];
				3'h1: // ca1
					ca1Next <= cpuAddrRegHi[0];
				3'h2: // ca2
					ca2Next <= cpuAddrRegHi[0];
				3'h3: // lstrb
					lstrbNext <= cpuAddrRegHi[0];
				3'h4: // disk enable
					if (selectExternalDrive)
						diskEnableExtNext <= cpuAddrRegHi[0];
					else
						diskEnableIntNext <= cpuAddrRegHi[0];
				3'h5: // external drive
					selectExternalDriveNext <= cpuAddrRegHi[0];
				3'h6: // Q6 
					q6Next <= cpuAddrRegHi[0];
				3'h7: // Q7 
					q7Next <= cpuAddrRegHi[0];
			endcase
		end
	end
	
	// update IWM bit registers
	always @(posedge clk8 or negedge _reset) begin
		if (_reset == 1'b0) begin
			ca0 <= 0;
			ca1 <= 0;
			ca2 <= 0;
			lstrb <= 0;
			diskEnableExt <= 0;
			diskEnableInt <= 0;
			selectExternalDrive <= 0;
			q6 <= 0;
			q7 <= 0;
		end
		else begin
			ca0 <= ca0Next;
			ca1 <= ca1Next;
			ca2 <= ca2Next;
			lstrb <= lstrbNext;
			diskEnableExt <= diskEnableExtNext;
			diskEnableInt <= diskEnableIntNext;
			selectExternalDrive <= selectExternalDriveNext;
			q6 <= q6Next;
			q7 <= q7Next;
		end
	end
	
	// read IWM state
	always @(*) begin
		dataOutLo = 8'hEF;
		
		if (_cpuRW == 1'b1 && selectIWM == 1'b1 && _cpuLDS == 1'b0) begin
			// reading any IWM address returns state as selected by Q7 and Q6
			case ({q7Next,q6Next}) 
				2'b00: // data-in register (from disk drive) - MSB is 1 when data is valid
					dataOutLo <= readDataLatch;
				2'b01: // IWM status register - read only
					dataOutLo <= { (selectExternalDriveNext ? senseExt : senseInt), 1'b0, diskEnableExt & diskEnableInt, iwmMode }; 
				2'b10: // handshake - read only
					dataOutLo <= { _iwmBusy, _writeUnderrun, 6'b000000 };
				2'b11: // IWM mode register when not enabled (write-only), or (write?) data register when enabled
					dataOutLo <= 0;
			endcase
		end	
	end
	
	// write IWM state
	always @(posedge clk8 or negedge _reset) begin
		if (_reset == 1'b0) begin		
			iwmMode <= 0;
			writeData <= 0;
		end
		else begin
			if (_cpuRW == 0 && selectIWM == 1'b1 && _cpuLDS == 1'b0) begin
				// writing to any IWM address modifies state as selected by Q7 and Q6
				case ({q7Next,q6Next})
					2'b11: begin
						if (diskEnableExt | diskEnableInt)
							writeData <= dataInLo;
						else
							iwmMode <= dataInLo[4:0];
					end
				endcase
			end
		end
	end
	
	// Manage incoming bytes from the disk drive
	wire iwmRead = (_cpuRW == 1'b1 && selectIWM == 1'b1 && _cpuLDS == 1'b0);
	reg iwmReadPrev;
	reg [3:0] readLatchClearTimer; 
	always @(posedge clk8 or negedge _reset) begin
		if (_reset == 1'b0) begin	
			readDataLatch <= 0;
			readLatchClearTimer <= 0;
			iwmReadPrev <= 0;
		end 
		else begin
			// a countdown timer governs how long after a data latch read before the latch is cleared
			if (readLatchClearTimer != 0) begin
				readLatchClearTimer <= readLatchClearTimer - 1'b1;
			end

			// the conclusion of a valid CPU read from the IWM will start the timer to clear the latch
			if (iwmReadPrev && !iwmRead && readDataLatch[7]) begin
				readLatchClearTimer <= 4'hD; // clear latch 14 clocks after the conclusion of a valid read
			end
			
			// when the drive indicates that a new byte is ready, latch it
			// NOTE: the real IWM must self-synchronize with the incoming data to determine when to latch it
			if (newByteReady) begin
				readDataLatch <= readData;
			end
			else if (readLatchClearTimer == 1'b1) begin
				readDataLatch <= 0;
			end
			
			iwmReadPrev <= iwmRead;
		end
	end
	assign advanceDriveHead = readLatchClearTimer == 1'b1; // prevents overrun when debugging, does not exist on a real Mac!
endmodule
