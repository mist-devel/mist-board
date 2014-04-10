// ethernec.v
//
// Atari ST NE2000/ethernec implementation for the MiST board
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

module ethernec (
	// cpu register interface
	input 		     clk,
	input [1:0]	     sel,
	input [14:0] 	  addr,        // cpu word address!
	output [15:0]    dout,

	// ethernet status word to be read by io controller
	output [31:0]    status,
	
	// interface to allow the io controller to read frames from the tx buffer
	input            tx_begin,   // rising edge before new tx byte is sent
	input            tx_strobe,  // rising edge before each tx byte
	output reg [7:0] tx_byte,    // byte from transmit buffer 
	
	// interface to allow the io controller to write frames to the tx buffer
	input            rx_begin,   // rising edge before new rx byte is sent
	input            rx_strobe,  // rising edge before each rx byte
	input [7:0]      rx_byte,    // byte to be written to rx buffer 

	// interface to allow mac address being set by io controller
	input            mac_begin,   // rising edge before new mac is sent
	input            mac_strobe,  // rising edge before each mac byte
	input [7:0]      mac_byte     // mac address byte
);
 
// some non-zero and non-all-ones bytes as status flags
localparam STATUS_IDLE       = 8'hfe;
localparam STATUS_TX_PENDING = 8'ha5;
localparam STATUS_TX_DONE    = 8'h12;

reg [7:0] statusCode;
assign status = { statusCode, 5'h00, tbcr == tx_w_cnt, isr[1:0], tbcr };
				
// ----- bus interface signals as wired up on the ethernec/netusbee ------
// sel[0] = 0xfa0000 -> normal read
// sel[1] = 0xfb0000 -> write through address bus
wire ne_read = sel[0] /* synthesis keep */;
wire ne_write = sel[1] /* synthesis keep */;
wire [4:0] ne_addr = addr[12:8] /* synthesis keep */;
wire [7:0] ne_wdata = addr[7:0] /* synthesis keep */;
reg [7:0] ne_rdata;
assign dout = { ne_rdata, 8'h00 };

// ---------- ne2000 internal registers -------------
reg reset /* synthesis noprune */;
reg [7:0]  cr;             // ne command register
reg [7:0]  isr;            // ne interrupt service register
reg [7:0]  imr;            // interrupt mask register
reg [7:0]  curr;           // current page register
reg [7:0]  bnry;           // boundary page
reg [7:0]  dcr;            
reg [7:0]  rcr;            // receiver control register
reg [7:0]  tcr;            // transmitter control register
reg [7:0]  tpsr;
reg [7:0]  pstart;         // rx buffer ring start page
reg [7:0]  pstop;          // rx buffer ring stop page
reg [7:0]  par [5:0];      // 6 byte mac address register
reg [7:0]  mar [7:0];      // 8 byte multicast hash register
reg [15:0] rbcr;           // receiver byte count register
reg [15:0] rsar;           // receiver address register
reg [15:0] tbcr;           // transmitter byte count register


wire [1:0] ps = cr[7:6];  // register page select

// ------------- rx/tx buffers ------------
localparam FRAMESIZE = 1536;
 
reg [7:0] rx_buffer [FRAMESIZE+3:0];   // 1 ethernet frame + 4 bytes header
reg [15:0] rx_r_cnt, rx_w_cnt;         // receive buffer byte counter

reg [7:0] tx_buffer [FRAMESIZE-1:0];   // 1 ethernet frame
reg [15:0] tx_w_cnt, tx_r_cnt;         // transmit buffer byte counter

// ------------- io controller read access to tx buffer ------------
always @(posedge tx_strobe or negedge tx_begin) begin
	if(!tx_begin)
		tx_r_cnt <= 16'd0;
	else begin
		tx_byte <= tx_buffer[tx_r_cnt];
		tx_r_cnt <= tx_r_cnt + 16'd1;
	end
end

// whenver tx buffer has been read set tx irq
reg tx_doneD, tx_doneD2;
wire tx_done = tx_doneD && !tx_doneD2;
always @(posedge clk) begin	
	tx_doneD <= !tx_begin;
	tx_doneD2 <= tx_doneD;
end

// ------------- set local mac address ------------

// mac address from io controller
reg [7:0] mac [5:0] /* synthesis noprune */;
reg [2:0] mac_cnt /* synthesis noprune */;
reg [2:0] mac_import;

always @(negedge mac_strobe or posedge mac_begin) begin
	if(mac_begin)
		mac_cnt <= 3'd0;
	else begin
		if(mac_cnt < 6) begin
			mac[mac_cnt] <= mac_byte;
			mac_cnt <= mac_cnt + 3'd1;
		end
	end
end

// cpu register read
always @(ne_read) begin
	ne_rdata <= 8'd0;
	if(ne_read) begin            // $faxxxx
		// cr, dma and reset are always available
		if(ne_addr == 5'h00)    ne_rdata <= cr;

		// register page 0
		if(ps == 2'd0) begin
			if(ne_addr == 5'h04) ne_rdata <= 8'h23;   // tsr: tx ok
			if(ne_addr == 5'h07) ne_rdata <= isr;
		end
		
		// register page 1
		if(ps == 2'd1) begin
			if(ne_addr == 5'h07) ne_rdata <= curr;
		end

		// read dma register $10 - $17
		if(ne_addr[4:3] == 2'b10)
			ne_rdata <= rx_buffer[rx_r_cnt];

	end
end

// register to delay receive counter increment by one cycle so this 
// does happen after the read cycle has finished
reg rx_inc;
reg tx_inc;

// cpu write via read
always @(negedge clk) begin
	rx_inc <= 1'b0;
	tx_inc <= 1'b0;

	if(rx_inc && (rx_r_cnt < FRAMESIZE))
		rx_r_cnt <= rx_r_cnt + 16'd1;

	if(tx_inc && (tx_w_cnt < FRAMESIZE))
		tx_w_cnt <= tx_w_cnt + 16'd1;

		// signal end of transmission if tx buffer has been read by
	// io controller
	if(tx_done) begin
		isr[1] <= 1'b1;  // PTX
		statusCode <= STATUS_TX_DONE;
	end
	
	// after reset copy mac address into receive buffer
	if(mac_import < 6) begin	
		rx_buffer[mac_import] <= mac[mac_import];
		mac_import <= mac_import + 1'd1;
	end

	// if cpu reads have internal side effects then ths is handled
	// here (and not in the "register read" block above)
	if(ne_read) begin
		// register page 0
		if(ps == 2'd0) begin
		end
		
		// register page 1
		if(ps == 2'd1) begin
		end

		// read dma register $10-$17
		if(ne_addr[4:3] == 2'b10)
			rx_inc <= 1'b1;
		
		// read reset register $18-$1f
		if(ne_addr[4:3] == 2'b11) begin
			reset <= 1'b1;      // read to reset register sets reset
			isr[7] <= 1'b1;     // set reset flag in isr
			
			mac_import <= 3'd0; // trigger mac address import
			statusCode <= STATUS_IDLE;
		end
	end

	if(ne_write) begin
		if(ne_addr == 5'h00) begin	
			cr <= ne_wdata;
			
			// writing the command register may actually start things ...

			// check for remote read
			if(ne_wdata[5:3] == 3'd1) begin
				// this resets the receive counter, so data is being
				// read from the beginning of the buffer	
				rx_r_cnt <= 16'h0000;			
			end

			// check for remote write
			if(ne_wdata[5:3] == 3'd2) begin
				// this resets the transmit counter, so data is being
				// written to the beginning of the buffer	
				tx_w_cnt <= 16'h0000;
			end

			// check if TX bit was set
			if(ne_wdata[2]) begin
				// tx buffer is now full and its contents need to be sent to
				// the io controller which in turn forwards it to its own nic

				// number of bytes to be transmitted is in tbcr, tx_w_cnt should
				// contain the same value since this is the number of write
				// cycles performed on the tx buffer
				statusCode <= STATUS_TX_PENDING;
				
				// once the io controller has sent the packet bit 2 in the isr
				// is being set. This will cause the ne2000 driver on atari side
				// to start filling the tx buffer again
			end
			
		end
			
		// register page 0
		if(ps == 2'd0) begin
			if(ne_addr == 5'h01) pstart <= ne_wdata;
			if(ne_addr == 5'h02) pstop <= ne_wdata;
			if(ne_addr == 5'h03) bnry <= ne_wdata;
			if(ne_addr == 5'h04) tpsr <= ne_wdata;
			if(ne_addr == 5'h05) tbcr[7:0] <= ne_wdata;
			if(ne_addr == 5'h06) tbcr[15:8] <= ne_wdata;
			if(ne_addr == 5'h07) isr <= isr & (~ne_wdata);   // writing 1 clears bit
			if(ne_addr == 5'h08) rsar[7:0] <= ne_wdata;
			if(ne_addr == 5'h09) rsar[15:8] <= ne_wdata;
			if(ne_addr == 5'h0a) rbcr[7:0] <= ne_wdata;
			if(ne_addr == 5'h0b) rbcr[15:8] <= ne_wdata;
			if(ne_addr == 5'h0c) rcr <= ne_wdata;
			if(ne_addr == 5'h0d) tcr <= ne_wdata;
			if(ne_addr == 5'h0e) dcr <= ne_wdata;
			if(ne_addr == 5'h0f) imr <= ne_wdata;
		end
		
		// register page 1
		if(ps == 2'd1) begin
			if((ne_addr >= 5'h01) && (ne_addr < 5'h07)) 
				par[ne_addr-5'd1] <= ne_wdata;
				
			if(ne_addr == 5'h07) curr <= ne_wdata;
			
			if((ne_addr >= 5'h08) && (ne_addr < 5'h10)) 
				mar[ne_addr-5'd8] <= ne_wdata;
		end

		// write to dma register $10-$17
		if(ne_addr[4:3] == 2'b10) begin
			// prevent writing over end of buffer (whatever then happens ...)
			if(tx_w_cnt < FRAMESIZE) begin
				// store byte in buffer
				tx_buffer[tx_w_cnt] <= ne_wdata;
			
				// increase byte counter
//				tx_w_cnt <= tx_w_cnt + 16'd1;  
				tx_inc <= 1'b1;
			end
		end
		
		// reset register $18-$1f
		if(ne_addr[4:3] == 2'b11)
			reset <= 1'b0; // write to reset register clears reset

	end
end

endmodule