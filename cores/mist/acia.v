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
	
	// data from io controller to ikbd acia
   input ikbd_strobe_in,
   input [7:0] ikbd_data_in,

	// data from ikbd acia to io controller
   output ikbd_data_out_available,
   input ikbd_strobe_out,
   output [7:0] ikbd_data_out,

	// data from midi acia to io controller
   output midi_data_out_available,
   input midi_strobe_out,
   output [7:0] midi_data_out
);

// --- ikbd output fifo ---
// filled by the CPU when writing to the acia data register
// emptied by the io controller when reading via SPI
io_fifo ikbd_out_fifo (
	.reset 				(reset),		

	.in_clk   			(!clk),          // latch incoming data on negedge
	.in 					(din),
	.in_strobe 			(1'b0),
	.in_enable			(sel && ~ds && ~rw && (addr == 2'd1)),   // ikbd acia data write

	.out_clk          (clk),
	.out 					(ikbd_data_out),
	.out_strobe 		(ikbd_strobe_out),
	.out_enable 		(1'b0),

	.data_available 	(ikbd_data_out_available)
);

// --- ikbd input fifo ---
// filled by the io controller when writing via SPI
// emptied by the CPU when reading the acia data register
io_fifo ikbd_in_fifo (
	.reset 				(reset || (ikbd_cr[1:0] == 2'b11)),

	.in_clk   			(!clk),          // latch incoming data on negedge
	.in 					(ikbd_data_in),
	.in_strobe 			(ikbd_strobe_in),
	.in_enable			(1'b0),

	.out_clk          (!clk),
	.out 					(ikbd_rx_data),
	.out_strobe 		(1'b0),
	.out_enable       (ikbd_cpu_data_read && ikbd_rx_data_available),

	.data_available 	(ikbd_rx_data_available)
);

// --- midi output fifo ---
// filled by the CPU when writing to the acia data register
// emptied by the io controller when reading via SPI
// This happens in parallel to the real midi generation, so 
// physical and USB MIDI can be used at the same time
io_fifo midi_out_fifo (
	.reset 				(reset),		

	.in_clk   			(!clk),          // latch incoming data on negedge
	.in 					(din),
	.in_strobe 			(1'b0),
	.in_enable			(sel && ~ds && ~rw && (addr == 2'd3)),  // midi acia data write

	.out_clk          (clk),
	.out 					(midi_data_out),
	.out_strobe 		(midi_strobe_out),
	.out_enable 		(1'b0),

	.data_available 	(midi_data_out_available)
);
// timer to let bytes arrive at a reasonable speed
reg [13:0] readTimer;

// delay the cpu read to be able to do things afterwards like e.g. incrementing 
// the fifo pointers
reg ikbd_cpu_data_read;

// the two control registers
reg [7:0] ikbd_cr;
reg [7:0] midi_cr;
	
always @(negedge clk) begin
	if(reset) begin
		readTimer <= 14'd0;
	end else begin
		if(readTimer > 0)
			readTimer <= readTimer - 14'd1;

		// read on ikbd data register
		ikbd_cpu_data_read <= 1'b0;
		if(sel && ~ds && rw && (addr == 2'd1))
			ikbd_cpu_data_read <= 1'b1;

		if(ikbd_cpu_data_read && ikbd_rx_data_available) begin
			// Some programs (e.g. bolo) need a pause between two ikbd bytes.
			// The ikbd runs at 7812.5 bit/s 1 start + 8 data + 1 stop bit. 
			// One byte is 1/718.25 seconds. A pause of ~1ms is thus required
			// 8000000/718.25 = 11138.18
			readTimer <= 14'd15000;
		end
   end
end 
 
// ------------------ cpu interface --------------------

wire [7:0] ikbd_status = { ikbd_irq, 6'b000001, cpu_ikbd_rx_data_available};
wire [7:0] ikbd_rx_data;
wire ikbd_rx_data_available;

wire ikbd_irq = ikbd_cr[7] && cpu_ikbd_rx_data_available;  // rx irq

// the cpu is only being told that data is available if the timer has run down. This
// to prevent the CPU from being flooded with data at more then 7812.5bit/s
wire cpu_ikbd_rx_data_available = ikbd_rx_data_available && (readTimer == 0);

// in a real ST the irqs are active low open collector outputs and are simply wired
// tegether ("wired or")
assign irq = ikbd_irq || midi_irq;

// ---------------- send acia data to io controller ------------

always @(sel, ds, rw, addr, ikbd_rx_data_available, ikbd_rx_data, ikbd_irq, 
		midi_rx_data, midi_rx_data_available, midi_tx_empty, midi_irq) begin
	dout = 8'h00;

	if(sel && ~ds && rw) begin
      // keyboard acia read
      if(addr == 2'd0) dout = ikbd_status;
      if(addr == 2'd1) dout = ikbd_rx_data;
      
      // midi acia read
      if(addr == 2'd2) dout = midi_status;
      if(addr == 2'd3) dout = midi_rx_data;
   end
end

// ------------------------------ MIDI UART ---------------------------------
wire midi_irq = (midi_cr[7] && midi_rx_data_available) ||    // rx irq
	((midi_cr[6:5] == 2'b01) && midi_tx_empty);               // tx irq

wire [7:0] midi_status = { midi_irq, 1'b0 /* parity err */, midi_rx_overrun, midi_rx_frame_error,
									2'b00 /* CTS & DCD */, midi_tx_empty, midi_rx_data_available};

// MIDI runs at 31250bit/s which is exactly 1/256 of the 8Mhz system clock
   
// 8MHz/256 = 31250Hz -> MIDI bit rate
reg [7:0] midi_clk;
always @(posedge clk)
	midi_clk <= midi_clk + 8'd1;

// --------------------------- midi receiver -----------------------------
reg [7:0] midi_rx_cnt;         // bit + sub-bit counter
reg [7:0] midi_rx_shift_reg;   // shift register used during reception
reg [7:0] midi_rx_data;  
reg [3:0] midi_rx_filter;      // filter to reduce noise
reg midi_rx_frame_error;
reg midi_rx_overrun;
reg midi_rx_data_available;
reg midi_in_filtered;

always @(negedge clk) begin
	if(reset) begin
		midi_rx_cnt <= 8'd0;
		midi_rx_data_available <= 1'b0;
		midi_rx_filter <= 4'b1111;
		midi_rx_overrun <= 1'b0;
		midi_rx_frame_error <= 1'b0;
   end else begin
	
		// read on midi data register
		if(sel && ~ds && rw && (addr == 2'd3)) begin
			midi_rx_data_available <= 1'b0;   // read on midi data clears rx status
			midi_rx_overrun <= 1'b0;
		end
			
		// midi acia master reset
		if(midi_cr[1:0] == 2'b11) begin
			midi_rx_cnt <= 8'd0;
			midi_rx_data_available <= 1'b0;
			midi_rx_filter <= 4'b1111;
			midi_rx_overrun <= 1'b0;
			midi_rx_frame_error <= 1'b0;
		end

		// 1/16 system clock == 16 times midi clock
		if(midi_clk[3:0] == 4'd0) begin
			midi_rx_filter <= { midi_rx_filter[2:0], midi_in};
		
			// midi input must be stable for 4 cycles to change state
			if(midi_rx_filter == 4'b0000) midi_in_filtered <= 1'b0;
			if(midi_rx_filter == 4'b1111) midi_in_filtered <= 1'b1;

			// receiver not running
			if(midi_rx_cnt == 8'd0) begin
				// seeing start bit?
				if(midi_in_filtered == 1'b0) begin
					// expecing 10 bits starting half a bit time from now
					midi_rx_cnt <= { 4'd9, 4'd7 };
				end
			end else begin
				// receiver is running
				midi_rx_cnt <= midi_rx_cnt - 8'd1;

			   // received a bit
				if(midi_rx_cnt[3:0] == 4'd0) begin
					// in the middle of the bit -> shift new bit into msb
					midi_rx_shift_reg <= { midi_in_filtered, midi_rx_shift_reg[7:1] };
				end

				// receiving last (stop) bit
				if(midi_rx_cnt[7:0] == 8'd1) begin
					if(midi_in_filtered == 1'b1) begin
						// copy data into rx register 
						midi_rx_data <= midi_rx_shift_reg;  // pure data w/o start and stop bits
						midi_rx_data_available <= 1'b1;
						midi_rx_frame_error <= 1'b0;
					end else
						// report frame error via status register
						midi_rx_frame_error <= 1'b1;

					// data hasn't been read yet? -> overrun
					if(midi_rx_data_available)
						midi_rx_overrun <= 1'b1;
					
				end
			end
		end
	end
end   

// --------------------------- midi transmitter -----------------------------
assign midi_out = midi_tx_empty ? 1'b1: midi_tx_shift_reg[0];
reg midi_tx_empty;
reg [7:0] midi_tx_cnt;
reg [7:0] midi_tx_data;
reg midi_tx_data_valid;
reg [10:0] midi_tx_shift_reg;
  
always @(negedge clk) begin

	// 16 times midi clock
	if(midi_clk[3:0] == 4'd0) begin
		if(midi_tx_cnt[3:0] == 4'h0) begin
			// shift down one bit, fill with 1 bits
			midi_tx_shift_reg <= { 1'b1, midi_tx_shift_reg[10:1] };
		end

		// decreae transmit counter
		if(midi_tx_cnt != 8'd0) begin
			midi_tx_cnt <= midi_tx_cnt - 8'd1;
			if(midi_tx_cnt == 1)
				midi_tx_empty <= 1'b1;
		end

		// restart immediately if another byte is in tx buffer 
		if((midi_tx_cnt == 8'd1) && midi_tx_data_valid) begin
			midi_tx_shift_reg <= { 1'b1, midi_tx_data, 1'b0, 1'b1 };  // 8N1, lsb first
			midi_tx_cnt <= { 4'd10, 4'd1 };   // 10 bits to go
			midi_tx_data_valid <= 1'b0;
		end
	end

	if(reset) begin
		midi_tx_cnt <= 8'd0;
		midi_tx_empty <= 1'b1;
		midi_tx_data_valid <= 1'b0;
   end else begin
      if(sel && ~ds && ~rw) begin

			// write to ikbd control register
			if(addr == 2'd0)
				ikbd_cr <= din;

			// keyboard acia data register omn addr 2 writes happen in the fifo 
			// ...
			
			// write to midi control register
			if(addr == 2'd2)
				midi_cr <= din;

			// write to midi data register
			if(addr == 2'd3) begin
				if(midi_tx_cnt == 8'd0) begin
					// transmitter idle? start immediately ...
					midi_tx_shift_reg <= { 1'b1, din, 1'b0, 1'b1 };  // 8N1, lsb first
					midi_tx_cnt <= { 4'd10, 4'd1 };   // 10 bits to go
					midi_tx_empty <= 1'b0;
				end else begin
					// ... otherwise store in data buffer
					midi_tx_data <= din;
					midi_tx_data_valid <= 1'b1;
				end
			end
		end
   end
end
   
endmodule
