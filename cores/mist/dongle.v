module dongle (
	// cpu register interface
	input 		 clk,
	input 		 sel,
	input 		 cpu_as,
	input 		 uds,
	input 		 rw,
	input [14:0] 	 addr,
	output reg [7:0] dout,
		
	output 		 present
);

assign present = 1'b0;
   
endmodule