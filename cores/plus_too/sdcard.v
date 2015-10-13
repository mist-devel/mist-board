module sdcard(
	input clk8,
	input _reset,
	input selectIWM
);

	spiMaster sdcard_intf(
		// host interface
		.clk_i(clk8),
		.rst_i(),
		.address_i(), 	// input [7:0]
		.data_i(), 		// input [7:0]
		.data_o(),		// output [7:0]
		.strobe_i(),	// input
		.we_i(),			// input
		.ack_o(),		// output

		// SPI logic clock	
		spiSysClk(),

		//SPI bus
		spiClkOut(),
		spiDataIn(),
		spiDataOut(),
		spiCS_n());

endmodule
