// A simple system-on-a-chip (SoC) for the MiST
// (c) 2015 Till Harbaum

module spi ( 
	input reset,
	input clk,

	// CPU interface
   input  sel,
   input  wr,
   input  addr,       // only 1 address bit required
   input [7:0] din,
   output [7:0] dout,

	// SPI/SD card interface
	output reg spi_ss,
	output reg spi_sck,
	output spi_sdo,
	input  spi_sdi
);

// SPI SS bit is just a cpu controlled output port
always @(negedge clk) begin
        if(reset)
                spi_ss <= 1'b1;
        else begin
					  // ss is written on io addr 1
                if(sel && wr && addr) 
                        spi_ss <= din[0];
        end
end

// data is being sent with msb first
assign spi_sdo = spi_tx_byte[7];

reg [3:0] spi_state_cnt;
reg [7:0] spi_tx_byte;
reg [7:0] spi_rx_byte;
always @(negedge clk) begin
	if(reset) begin
		spi_state_cnt <= 4'd0;
		spi_sck <= 1'b0;
	end else begin
		if(sel && wr && !addr) begin
			spi_state_cnt <= 4'd15;
			spi_tx_byte <= din;
		end else begin
			// rising spi clock on odd states
			spi_sck <= spi_state_cnt[0];
 
			// read input bit on rising clock edge, shift output bit on falling edge
			if(spi_state_cnt[0])
				spi_rx_byte <= { spi_rx_byte[6:0], spi_sdi };
			else
				spi_tx_byte <= { spi_tx_byte[6:0], 1'b0 };
		
			// decrease state counter
			if(spi_state_cnt != 0)
				spi_state_cnt <= spi_state_cnt - 4'd1;
		end
	end
end

assign dout = spi_rx_byte;

endmodule
