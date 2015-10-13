module ramAdapter(
	 // CPU interface
	 input clk8,
    input [20:0] addr, // word address
	 output [15:0] dataOut,
    input _OE,
    input _CS,
    input _UDS,
    input _LDS,
	 
	 // external interface to 8-bit Flash
	 output [21:0] flashAddr, // byte address
	 input [7:0] flashData,
	 output flashCE,
	 output flashOE
);

endmodule
