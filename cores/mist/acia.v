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

reg [7:0] fifoIn [FIFO_DEPTH-1:0];
reg [FIFO_ADDR_BITS-1:0] writePin, readPin;

// 
reg [7:0] fifoOut [FIFO_DEPTH-1:0];
reg [FIFO_ADDR_BITS-1:0] writePout, readPout;

// timer to let bytes arrive at a reasonable speed
reg [13:0] readTimer;

reg ikbd_strobe_inD, ikbd_strobe_inD2;	
reg data_read;	
always @(negedge clk) begin
	if(reset)
		readTimer <= 14'd0;
	else
		if(readTimer > 0)
			readTimer <= readTimer - 14'd1;

	ikbd_strobe_inD <= ikbd_strobe_in;
	ikbd_strobe_inD2 <= ikbd_strobe_inD;
	
	// read on ikbd data register
	if(sel && ~ds && rw && (addr == 2'd1))
		data_read <= 1'b1;
	else
		data_read <= 1'b0;

	if(reset) begin
		// reset read and write counters
		readPin <= 4'd0;
		writePin <= 4'd0;
	end else begin
	   if(ikbd_strobe_inD && !ikbd_strobe_inD2) begin
			// store data in fifo
			fifoIn[writePin] <= ikbd_data_in;
			writePin <= writePin + 4'd1;
	   end 

	   if(data_read && dataInAvail) begin
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

wire [7:0] rxd;
assign rxd = fifoIn[readPin];

wire dataInAvail;
assign dataInAvail = (readPin != writePin) && (readTimer == 0);

assign irq = dataInAvail;

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
	
always @(sel, ds, rw, addr, dataInAvail, rxd, midi_tx_empty) begin
	dout = 8'h00;

	if(sel && ~ds && rw) begin
      // keyboard acia read
      if(addr == 2'd0) dout = 8'h02 | (dataInAvail?8'h81:8'h00);  // status
      if(addr == 2'd1) dout = rxd;    // data
      
      // midi acia read
      if(addr == 2'd2) dout = { 6'b000000, midi_tx_empty, 1'b0} ;  // status
      if(addr == 2'd3) dout = 8'h00;  // data
   end
end

// midi transmitter
assign midi_out = midi_tx_empty ? 1'b1: midi_tx_cnt[0];
wire midi_tx_empty = (midi_tx_cnt == 4'd0);
reg [7:0] midi_clk;
reg [3:0] midi_tx_cnt;
reg [9:0] midi_tx_data;
   
// 8MHz/256 = 31250Hz -> MIDI bit rate
always @(posedge clk)
	midi_clk <= midi_clk + 8'd1;

always @(negedge clk) begin
	if(midi_clk == 8'd0) begin
		// shift down one bit, fill with 1 bits
		midi_tx_data <= { 1'b1, midi_tx_data[9:1] };

		// decreae transmit counter
		if(midi_tx_cnt != 4'd0)
			midi_tx_cnt <= midi_tx_cnt - 4'd1;
	end
			
   if(reset) begin
      writePout <= 4'd0;
		midi_tx_cnt <= 4'd0;
   end else begin
      // keyboard acia data register writes into buffer 
      if(sel && ~ds && ~rw && addr == 2'd1) begin
         fifoOut[writePout] <= din;
			writePout <= writePout + 4'd1;
      end

      // write to midi data register
      if(sel && ~ds && ~rw && addr == 2'd1) begin
			midi_tx_data <= { 1'b1, din, 1'b0 };  // 8N1, lsb first
			midi_tx_cnt <= 4'd10;   // 10 bits to go
		end
   end
end
   
endmodule