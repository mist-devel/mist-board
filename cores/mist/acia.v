module acia (
	// cpu register interface
	input clk,
	input reset,
	input [7:0] din,
	input sel,
	input [1:0] addr,
	input ds,
	input rw,
	output reg [7:0] dout,
	output irq,

	output midi_out,
	input midi_in,
	
	// data from io controller to acia
   input ikbd_strobe_in,
   input [7:0] ikbd_data_in,

	// data from acia to io controller
   output ikbd_data_out_available,
   input ikbd_strobe_out,
   output [7:0] ikbd_data_out
);

localparam FIFO_ADDR_BITS = 4;
localparam FIFO_DEPTH = (1 << FIFO_ADDR_BITS);

// input FIFO to store ikbd bytes received from IO controller
reg [7:0] fifoIn [FIFO_DEPTH-1:0];
reg [FIFO_ADDR_BITS-1:0] writePin, readPin;

// output FIFO to store ikbd bytes to be sent to IO controller
reg [7:0] fifoOut [FIFO_DEPTH-1:0];
reg [FIFO_ADDR_BITS-1:0] writePout, readPout;

// timer to let bytes arrive at a reasonable speed
reg [13:0] readTimer;

reg ikbd_strobe_inD, ikbd_strobe_inD2;	
reg ikbd_cpu_data_read;
reg midi_cpu_data_read;

// the two control registers
reg [7:0] ikbd_cr;
reg [7:0] midi_cr;
	
reg [15:0] ikbd_rx_counter /* synthesis noprune */; 
	
always @(negedge clk) begin
	if(reset) begin
		readTimer <= 14'd0;
		ikbd_rx_counter <= 16'd0;
	end else
		if(readTimer > 0)
			readTimer <= readTimer - 14'd1;

	ikbd_strobe_inD <= ikbd_strobe_in;
	ikbd_strobe_inD2 <= ikbd_strobe_inD;
	
	// read on ikbd data register
	ikbd_cpu_data_read <= 1'b0;
	if(sel && ~ds && rw && (addr == 2'd1)) begin
		ikbd_cpu_data_read <= 1'b1;
		ikbd_rx_counter <= ikbd_rx_counter + 16'd1;
	end

  	// read on midi data register
	midi_cpu_data_read <= 1'b0;
	if(sel && ~ds && rw && (addr == 2'd3))
		midi_cpu_data_read <= 1'b1;

	if(reset) begin
		// reset read and write counters
		readPin <= 4'd0;
		writePin <= 4'd0;
	end else begin

		// ikbd acia master reset
		if(ikbd_cr[1:0] == 2'b11) begin
			readPin <= 4'd0;
			writePin <= 4'd0;
		end
			
		// store bytes received from IO controller via SPI
	   if(ikbd_strobe_inD && !ikbd_strobe_inD2) begin
			// store data in fifo
			fifoIn[writePin] <= ikbd_data_in;
			writePin <= writePin + 4'd1;
	   end 

	   if(ikbd_cpu_data_read && ikbd_rx_data_available) begin
			readPin <= readPin + 4'd1;
		
			// Some programs (e.g. bolo) need a pause between two ikbd bytes.
			// The ikbd runs at 7812.5 bit/s 1 start + 8 data + 1 stop bit. 
			// One byte is 1/718.25 seconds. A pause of ~1ms is thus required
			// 8000000/718.25 = 11138.18
			readTimer <= 14'd11138;
		end
   end
end

// ------------------ cpu interface --------------------

wire ikbd_irq = ikbd_cr[7] && ikbd_rx_data_available;  // rx irq

wire [7:0] ikbd_rx_data = fifoIn[readPin];

wire ikbd_rx_data_available;
assign ikbd_rx_data_available = (readPin != writePin) && (readTimer == 0);

// in a real ST the irqs are active low open collector outputs and are simply wired
// tegether ("wired or")
assign irq = ikbd_irq || midi_irq;

assign ikbd_data_out_available = (readPout != writePout);
assign ikbd_data_out = fifoOut[readPout];

// ---------------- send acia data to io controller ------------
reg ikbd_strobe_outD, ikbd_strobe_outD2;
always @(posedge clk) begin
	ikbd_strobe_outD <= ikbd_strobe_out;
	ikbd_strobe_outD2 <= ikbd_strobe_outD;

	if(reset)
		readPout <= 4'd0;
	else
		if(ikbd_strobe_outD && !ikbd_strobe_outD2)
			readPout <= readPout + 4'd1;
end

always @(sel, ds, rw, addr, ikbd_rx_data_available, ikbd_rx_data, ikbd_irq, 
		midi_rx_data, midi_rx_data_available, midi_tx_empty, midi_irq) begin
	dout = 8'h00;

	if(sel && ~ds && rw) begin
      // keyboard acia read
      if(addr == 2'd0) dout = { ikbd_irq, 6'b000001, ikbd_rx_data_available };
      if(addr == 2'd1) dout = ikbd_rx_data;
      
      // midi acia read
      if(addr == 2'd2) dout = { midi_irq, 5'b00000, midi_tx_empty, midi_rx_data_available};
      if(addr == 2'd3) dout = midi_rx_data;
   end
end

// ------------------------------ MIDI UART ---------------------------------
wire midi_irq = (midi_cr[7] && midi_rx_data_available) ||    // rx irq
	((midi_cr[6:5] == 2'b01) && midi_tx_empty);               // tx irq

// MIDI runs at 31250bit/s which is exactly 1/256 of the 8Mhz system clock
   
// 8MHz/256 = 31250Hz -> MIDI bit rate
reg [7:0] midi_clk;
always @(posedge clk)
	midi_clk <= midi_clk + 8'd1;

// --------------------------- midi receiver -----------------------------
reg [7:0] midi_rx_cnt;         // bit + sub-bit counter
reg [9:0] midi_rx_shift_reg;   // shift register used during reception
reg [7:0] midi_rx_data;  
reg [3:0] midi_rx_filter;      // filter to reduce noise
reg midi_rx_data_available;
reg midi_in_filtered;

always @(negedge clk) begin
	if(reset) begin
		midi_rx_cnt <= 8'd0;
		midi_rx_data_available <= 1'b0;
		midi_rx_filter <= 4'b1111;
   end else begin
      if(midi_cpu_data_read)
			midi_rx_data_available <= 1'b0;   // read on midi data clears rx status
      
		// midi acia master reset
		if(midi_cr[1:0] == 2'b11) begin
			midi_rx_cnt <= 8'd0;
			midi_rx_data_available <= 1'b0;
			midi_rx_filter <= 4'b1111;
		end

		// 1/16 system clock == 16 times midi clock
		if(midi_clk[3:0] == 4'd0) begin
			midi_rx_filter <= { midi_rx_filter[2:0], midi_in};
		
			// midi in mist be stable for 4 cycles to change state
			if(midi_rx_filter == 4'b0000) midi_in_filtered <= 1'b0;
			if(midi_rx_filter == 4'b1111) midi_in_filtered <= 1'b1;

			// receiver not running
			if(midi_rx_cnt == 8'd0) begin
				if(midi_in_filtered == 1'b0) begin
					// expecing 10 bits starting half a bit time from now
					midi_rx_cnt <= { 4'd10, 4'd7 };
				end
			end else begin
				// receiver is running
				midi_rx_cnt <= midi_rx_cnt - 8'd1;
				
				if(midi_rx_cnt[3:0] == 4'd0) begin
					// in the middle of the bit -> shift new bit into msb
					midi_rx_shift_reg <= { midi_in_filtered, midi_rx_shift_reg[9:1] };
				end

				// last bit received
				if(midi_rx_cnt[7:0] == 8'd1) begin
					// copy data into rx register 
					midi_rx_data <= midi_rx_shift_reg[8:1];  // pure data w/o start and stop bits
					midi_rx_data_available <= 1'b1;
					
					// todo: check data[0] for frame error (stop bit)
				end
			end
		end
	end
end   

// --------------------------- midi transmitter -----------------------------
assign midi_out = midi_tx_empty ? 1'b1: midi_tx_shift_reg[0];
wire midi_tx_empty = (midi_tx_cnt == 4'd0);
reg [7:0] midi_tx_cnt;
reg [7:0] midi_tx_data;
reg midi_tx_data_valid;
reg [10:0] midi_tx_shift_reg;
 
// counter register writes for debugging
reg [7:0] midi_reg_data_cnt /* synthesis noprune */;
reg [7:0] midi_reg_ctrl_cnt /* synthesis noprune */;
 
always @(negedge clk) begin

	// 16 times midi clock
	if(midi_clk[3:0] == 4'd0) begin
		if(midi_tx_cnt[3:0] == 4'h0) begin
			// shift down one bit, fill with 1 bits
			midi_tx_shift_reg <= { 1'b1, midi_tx_shift_reg[10:1] };
		end

		// decreae transmit counter
		if(midi_tx_cnt != 8'd0)
			midi_tx_cnt <= midi_tx_cnt - 8'd1;

		// restart immediately if another byte is in tx buffer 
		if((midi_tx_cnt == 8'd1) && midi_tx_data_valid) begin
			midi_tx_shift_reg <= { 1'b1, midi_tx_data, 1'b0, 1'b1 };  // 8N1, lsb first
			midi_tx_cnt <= { 4'd10, 4'd1 };   // 10 bits to go
			midi_tx_data_valid <= 1'b0;
		end
	end

	if(reset) begin
		midi_reg_data_cnt <= 8'd0;
		midi_reg_ctrl_cnt <= 8'd0;

      writePout <= 4'd0;
		midi_tx_cnt <= 8'd0;
		midi_tx_data_valid <= 1'b0;
   end else begin
      if(sel && ~ds && ~rw) begin

			// write to ikbd control register
			if(addr == 2'd0)
				ikbd_cr <= din;

			// keyboard acia data register writes into buffer 
			if(addr == 2'd1) begin
				fifoOut[writePout] <= din;
				writePout <= writePout + 4'd1;
			end

			// write to midi control register
			if(addr == 2'd2) begin
				midi_cr <= din;
				midi_reg_ctrl_cnt <= midi_reg_ctrl_cnt + 8'd1;
			end

			// write to midi data register
			if(addr == 2'd3) begin
				if(midi_tx_cnt == 8'd0) begin
					// transmitter idle? start immediately ...
					midi_tx_shift_reg <= { 1'b1, din, 1'b0, 1'b1 };  // 8N1, lsb first
					midi_tx_cnt <= { 4'd10, 4'd1 };   // 10 bits to go
				end else begin
					// ... otherwise store in data buffer
					midi_tx_data <= din;
					midi_tx_data_valid <= 1'b1;
				end
				
				midi_reg_data_cnt <= midi_reg_data_cnt + 8'd1;				
			end
		end
   end
end
   
endmodule