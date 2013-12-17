// Empty dongle module. Just a placeholder ...

module dongle (
	// cpu register interface
	input 			clk,
	input 			sel,
	input 			cpu_as,
	input 			uds,
	input 			rw,
	input [14:0] 	addr,
	output[7:0] 	dout,
		
	output 			present
);

assign present = 1'b0;
assign dout = 8'h00;

endmodule