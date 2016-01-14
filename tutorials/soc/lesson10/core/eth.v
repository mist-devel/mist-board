// A simple system-on-a-chip (SoC) for the MiST
// (c) 2016 Till Harbaum

/* ---------------------------------- Ethernet ------------------------------------ */
									  
module eth ( 
	input					clk,
	input					reset,

	// connection to user_io/IO controller
	output [31:0]  	eth_status,             // status to be sent to io controller
	
	input          	eth_tx_read_start,      // io controller starts reading a packet from core
	input 				eth_tx_read_strobe,     // io controller reads a byte
	output reg [7:0] 	eth_tx_read_byte,
	
	input 				eth_rx_write_start,      // io controller starts sending a packet to core
	input 				eth_rx_write_strobe,     // io controller sends a byte
	input 				eth_mac_strobe,          // io controller sends byte of mac address
	input [7:0] 		eth_rx_write_byte,

	// connection to CPU
	input 				cpu_rd,
	input 				cpu_wr,
	input [4:0]			cpu_addr,
	input [7:0]			cpu_din,
	output [7:0]		cpu_dout
);

assign eth_status = { eth_cmd, 6'b000000, rx_busy, 1'b0, tx_len };

wire eth_rx_buffer_full = (eth_buffer_in_wptr != 0);
wire [7:0] eth_cmd_status = { eth_mac_ok, 5'b00000, tx_busy, eth_rx_buffer_full };

// io controller sends an additional 0 byte for padding
wire [8:0] rx_len = (eth_buffer_in_wptr - 9'd1);
reg [15:0] tx_len;
	
// cpu reads ethernet controller registers
assign cpu_dout = 
	(cpu_addr == 5'h00)?eth_cmd_status:
	(cpu_addr == 5'h01)?{ 7'h00, rx_len[8] }:
	(cpu_addr == 5'h02)?rx_len[7:0]:
	(cpu_addr == 5'h03)?eth_buffer_in_rd_data:
	(cpu_addr[4:3] == 2'b10)?eth_mac[cpu_addr[2:0]]:
	8'h00;

// various flags generated when the cpu accesses certains registers.
// these are e.f. used to clear buffers or to reset buffer pointers
reg cpu_rx_ack;
reg cpu_rd_len;
reg cpu_wr_len;
reg cpu_rd_data;
reg cpu_wr_data;
reg cpu_tx_req;

// cmd "a5" tells the io controller that a packet is ready for transmssion
// the cmd is reset to some invalid value once the io controller starts reading the packet 
reg [7:0] eth_cmd;
always @(posedge cpu_tx_req or posedge eth_tx_read_start) begin
	if(eth_tx_read_start) eth_cmd <= 8'h12;
	else                  eth_cmd <= 8'ha5;
end

// tx_busy flag being set when the cpu requests packet transmission and cleared when
// the io controller has read the last byte of the packet
reg tx_busy = 1'b0;
always @(posedge cpu_tx_req or posedge eth_buffer_has_been_read) begin
	if(eth_buffer_has_been_read) tx_busy <= 1'b0;
	else                         tx_busy <= 1'b1;
end

// rx_busy flag being set when the io comtroller writes a packet and cleared when the
// local cpu acknowledges reception
reg rx_busy = 1'b0;
always @(posedge eth_rx_write_start or posedge cpu_rx_ack) begin
	if(cpu_rx_ack) rx_busy <= 1'b0;
	else           rx_busy <= 1'b1;
end
	
always @(posedge clk) begin
	if(reset) begin
		cpu_rx_ack <= 1'b0;
		cpu_rd_len <= 1'b0;
		cpu_rd_data <= 1'b0;
		cpu_wr_len <= 1'b0;
		cpu_wr_data <= 1'b0;
		cpu_tx_req <= 1'b0;
		tx_len <= 16'd0;
	end else begin
		cpu_rx_ack <= 1'b0;
		cpu_rd_len <= 1'b0;
		cpu_rd_data <= 1'b0;
		cpu_wr_len <= 1'b0;
		cpu_wr_data <= 1'b0;
		cpu_tx_req <= 1'b0;
		
		if(cpu_rd) begin
			if(cpu_addr[4:0] == 5'h01)
				cpu_rd_len <= 1'b1;
			
			if(cpu_addr[4:0] == 5'h03)
				cpu_rd_data <= 1'b1;
		end
	
		if(cpu_wr) begin
			// cpu writes command register
			if(cpu_addr[4:0] == 5'h00) begin
				// cpu requests packet transmission
				if(cpu_din[0])
					cpu_tx_req <= 1'b1;
			
				// cpu acknowledges packet reception
				if(cpu_din[1])
					cpu_rx_ack <= 1'b1;
			end
		
			if(cpu_addr[4:0] == 5'h01) begin
				tx_len[15:8] <= cpu_din;
				cpu_wr_len <= 1'b1;
			end

			if(cpu_addr[4:0] == 5'h02) begin
				tx_len[7:0] <= cpu_din;
				cpu_wr_len <= 1'b1;
			end
			
			if(cpu_addr[4:0] == 5'h03)
				cpu_wr_data <= 1'b1;
		end
	end
end
	
// -------------------------------------------------------------------
// --------------------------- RX buffer -----------------------------
// -------------------------------------------------------------------

// buffer to store packet coming from io controller
reg [7:0] eth_buffer_in[511:0];
reg [8:0] eth_buffer_in_wptr /* synthesis noprune */;
reg [8:0] eth_buffer_in_rptr /* synthesis noprune */;

// read pointer is reset when io controller writes packet data or when cpu acks reception
wire eth_rx_reset = eth_rx_write_start || cpu_rx_ack;

always @(posedge eth_rx_write_strobe or posedge eth_rx_reset) begin
	if(eth_rx_reset)
		eth_buffer_in_wptr <= 9'd0;
	else begin
		eth_buffer_in[eth_buffer_in_wptr] <= eth_rx_write_byte;
		eth_buffer_in_wptr <= eth_buffer_in_wptr + 9'd1;
	end
end

reg [7:0] eth_buffer_in_rd_data;
always @(negedge clk)
	eth_buffer_in_rd_data <= eth_buffer_in[eth_buffer_in_rptr];

always @(posedge cpu_rd_data or posedge cpu_rd_len) begin
	if(cpu_rd_len)	eth_buffer_in_rptr <= 9'd0;
	else		      eth_buffer_in_rptr <= eth_buffer_in_rptr + 9'd1;
end

// -------------------------------------------------------------------
// --------------------------- TX buffer -----------------------------
// -------------------------------------------------------------------

// buffer to store packet coming from io controller
reg [7:0] eth_buffer_out[511:0];
reg [8:0] eth_buffer_out_wptr /* synthesis noprune */;
reg [8:0] eth_buffer_out_rptr /* synthesis noprune */;
reg eth_buffer_has_been_read /* synthesis noprune */;

// cpu writes data int the buffer
always @(posedge cpu_wr_data or posedge cpu_wr_len) begin
	if(cpu_wr_len)
		eth_buffer_out_wptr <= 9'd0;
	else begin
		eth_buffer_out[eth_buffer_out_wptr] <= cpu_din;
		eth_buffer_out_wptr <= eth_buffer_out_wptr + 9'd1;
	end
end

// io controller reads dara from the buffer
always @(negedge clk)
	eth_tx_read_byte <= eth_buffer_out[eth_buffer_out_rptr];

always @(posedge eth_tx_read_strobe or posedge cpu_wr_len) begin
	if(cpu_wr_len)	begin
		eth_buffer_out_rptr <= 9'd0;
		eth_buffer_has_been_read <= 1'b0;
	end else begin
		eth_buffer_out_rptr <= eth_buffer_out_rptr + 9'd1;
		// signal that the last byte has been read. This is used to tell
		// the local cpu that it can send another packet
		if(eth_buffer_out_rptr == (tx_len - 16'd1))
			eth_buffer_has_been_read <= 1'b1;
	end
end
	
// -------------------------------------------------------------------
// -------------------------- MAC address ----------------------------
// -------------------------------------------------------------------

// store mac address so client can use it
reg [7:0] eth_mac[5:0];
reg [2:0] eth_mac_cnt = 3'd0;
wire eth_mac_ok = (eth_mac_cnt == 6);
always @(posedge eth_mac_strobe) begin
	if(eth_mac_cnt != 6)
		eth_mac_cnt <= eth_mac_cnt + 3'd1;

	eth_mac[0] <= eth_rx_write_byte;
	eth_mac[1] <= eth_mac[0];
	eth_mac[2] <= eth_mac[1];
	eth_mac[3] <= eth_mac[2];
	eth_mac[4] <= eth_mac[3];
	eth_mac[5] <= eth_mac[4];
end

endmodule
