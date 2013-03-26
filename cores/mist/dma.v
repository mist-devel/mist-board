module dma (
	// cpu register interface
	input clk,
	input reset,
	input [15:0] din,
	input sel,
	input [2:0] addr,
	input uds,
	input lds,
	input rw,
	output reg [15:0] dout,

	// output to mfp
	output irq,
	
	// input from system config
	input fdc_wr_prot,
	
	// connection to data_io (arm controller spi interface)
	input [4:0] dio_idx,
	output reg [7:0] dio_data,
	input dio_ack,
	
	// input from psg
	input drv_side,
	input [1:0] drv_sel
);

// ------------- data_io (arm controller) interface ------

always @(dio_idx, base, scnt, fdc_cmd, fdc_track, fdc_sector, 
	fdc_data, drv_sel, drv_side, fdc_busy) begin
	dio_data = 8'h00;
 	
	case (dio_idx)
		0: dio_data = base[23:16];
		1: dio_data = base[15:8];
		2: dio_data = base[7:0];
		3: dio_data = scnt;
		4: dio_data = fdc_cmd;
		5: dio_data = fdc_track;
		6: dio_data = fdc_sector;
		7: dio_data = fdc_data;
		8: dio_data = { 4'b0000, drv_sel, drv_side, fdc_busy };
		default: dio_data = 8'h00;
	endcase
end
// ------------------ cpu interface --------------------

reg fdc_busy;

assign irq = !fdc_busy;

reg [15:0] mode;

// fdc registers
reg [7:0] fdc_cmd;
reg [7:0] fdc_track;
reg [7:0] fdc_sector;
reg [7:0] fdc_data;

// dma base address register and sector counter
reg [23:0] base;
reg [7:0] scnt;

// virtual head is over track 0
wire track0;
assign track0 = (fdc_track == 8'd0);

reg step_dir;

// status byte returned by the fdc when reading register 0
wire [7:0] fdc_status;
assign fdc_status = { 
	!(motor_on == 0), fdc_wr_prot, 3'b000, 
	(fdc_cmd[7]==1'b0)?track0:1'b0, 1'b0, fdc_busy };

wire [15:0] dma_status;
assign dma_status = { 14'd0, !(scnt == 0), 1'b1 };   // bit 0 = 1: DMA_OK

// timer to simulate motor-on
reg [15:0] motor_on;

always @(sel, rw, addr, mode, base, fdc_data, fdc_sector, fdc_status, fdc_track,
	dma_status, scnt) begin
	dout = 16'h0000;

	if(sel && rw) begin
		if((addr == 3'h2) && (mode[4] == 1'b0)) begin
			// controller access register
			if(mode[3] == 1'b0) begin
				// fdc
				if(mode[2:1] == 2'b00)  // status register
					dout = { 8'h00, fdc_status };
				if(mode[2:1] == 2'b01)  // track register
					dout = { 8'h00, fdc_track };
				if(mode[2:1] == 2'b10)  // sector register
					dout = { 8'h00, fdc_sector };
				if(mode[2:1] == 2'b11)  // data register
					dout = { 8'h00, fdc_data };
			end
		end

		if(addr == 3'h3)
			dout = dma_status;
			
		// sector count register
		if((addr == 3'h2) && (mode[4] == 1'b1)) 
			dout = { 8'h00, scnt };

		// dma base address read back
		if(addr == 3'h4)
			dout = { 8'h00, base[23:16] };				
		if(addr == 3'h5)
			dout = { 8'h00, base[15:8] };				
		if(addr == 3'h6)
			dout = { 8'h00, base[7:0] };
   end
end
   
reg dio_ackD, dio_ackD2;
always @(posedge clk)
	dio_ackD <= dio_ack;

always @(negedge clk) begin
   if(reset) begin
      mode <= 16'd0;
		fdc_cmd <= 8'd0;
		fdc_track <= 8'd0;
		fdc_sector <= 8'd0;
		fdc_data <= 8'd0;
		base <= 24'h000000;
		scnt <= 8'h00;
		fdc_busy <= 1'b0;
		motor_on <= 16'd0;
   end else begin
		// rising edge on ack -> clear busy flag
		dio_ackD2 <= dio_ackD;
		if(dio_ackD && !dio_ackD2) begin
			scnt <= 8'h00;     // all sectors transmitted
			fdc_busy <= 1'b0;
		end

		// let "motor" run for some time
		if(motor_on != 0)
			motor_on <= motor_on - 16'd1;
						
		// dma control and mode register
      if(sel && ~rw) begin
			if(~lds && (addr == 3'h2) && (mode[4] == 1'b0)) begin
				// controller access register
				if(mode[3] == 1'b0) begin
					// fdc register write
					if(mode[2:1] == 2'b00) begin       // command register
						fdc_cmd <= din[7:0];

				      // all TYPE I and TYPE II commands start the motor
						if((din[7] == 1'b0) || (din[7:6] == 2'b10))
							motor_on <= 16'hffff;

						// ------------- TYPE I commands -------------
						
						if(din[7:4] == 4'b0000)         // RESTORE
							fdc_track <= 8'd0;
							
						if(din[7:4] == 4'b0001)         // SEEK
							fdc_track <= fdc_data;
							
						if(din[7:4] == 4'b0011) begin   // STEP with update flag
							if(step_dir == 1'b1)
								fdc_track <= fdc_track + 8'd1;
							else
								fdc_track <= fdc_track - 8'd1;
						end

						if(din[7:4] == 4'b0101) begin   // STEP-IN with update flag
							step_dir <= 1'b1;
							fdc_track <= fdc_track + 8'd1;
						end
						
						if(din[7:4] == 4'b0111) begin   // STEP-OUT with update flag
							step_dir <= 1'b0;
							fdc_track <= fdc_track - 8'd1;
						end

						// ------------- TYPE II commands -------------
						if(din[7:5] == 3'b100)         // read sector
							fdc_busy <= 1'b1;
							
						if(din[7:5] == 3'b101)         // write sector
							if(!fdc_wr_prot)
								fdc_busy <= 1'b1;

						// ------------- TYPE III commands ------------
	
						// these aren't supported yet
//						if(din[7:4] == 4'b1100)         // read address
//							fdc_busy <= 1'b1;

//						if(din[7:4] == 4'b1110)         // read track
//							fdc_busy <= 1'b1;

//						if(din[7:4] == 4'b1111)         // write track
//							if(!fdc_wr_prot)
//							  fdc_busy <= 1'b1;

						// ------------- TYPE IV commands -------------
						if(din[7:4] == 4'b1101)         // force intrerupt
							fdc_busy <= 1'b0;
	
					end if(mode[2:1] == 2'b01)         // track register
						fdc_track <= din[7:0];
					if(mode[2:1] == 2'b10)             // sector register
						fdc_sector <= din[7:0];
					if(mode[2:1] == 2'b11)             // data register
						fdc_data <= din[7:0];
				end
			end
			
			// sector count register
			if(~lds && (addr == 3'h2) && (mode[4] == 1'b1))
				scnt <= din[7:0];

			if(addr == 3'h3)
				mode <= din;
				
			if(~lds && (addr == 3'h4))
				base[23:16] <= din[7:0];				
			if(~lds && (addr == 3'h5))
				base[15:8] <= din[7:0];
			if(~lds && (addr == 3'h6))
				base[7:0] <= din[7:0];
      end
   end
end
   
endmodule