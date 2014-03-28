// ethernec.v

module ethernec (
	// cpu register interface
	input 		  clk,
	input [1:0]	  sel,
	input 		  uds,
	input 		  lds,
	input [14:0] 	  addr,
	output reg [15:0] dout
);

// sel[0] = 0xfa0000 -> normal read
// sel[1] = 0xfb0000 -> write through address bus
wire ne_read = sel[0];
wire ne_write = sel[1];
wire [4:0] ne_addr = addr[13:9];
wire [7:0] ne_wdata = addr[8:1];

reg reset;
reg [7:0] cr;    // ne command register
reg [7:0] isr;   // ne interrupt service register

// cpu read
always @(ne_read, lds) begin
	dout = 16'd0;
	if(ne_read) begin            // $faxxxx
		if(ne_addr == 5'h00) dout[7:0] = cr;
		
		if(ne_addr == 5'h07) dout[7:0] = isr;
	 end
end

// cpu write via read
always @(negedge clk) begin
	if(ne_read && lds) begin
	
		// reset register $18-$1f
		if(ne_addr[4:3] == 2'b11) begin
			reset <= 1'b1;     // read to reset register sets reset
			isr[7] <= 1'b1;    // set reset flag in isr
		end
	end

	if(ne_write && lds) begin
		if(ne_addr == 5'h00) cr <= ne_wdata;
		if(ne_addr == 5'h07) isr <= isr & (~ne_wdata);   // writing 1 clears bit

		// reset register $18-$1f
		if(ne_addr[4:3] == 2'b11)
			reset <= 1'b0; // write to reset register clears reset
	end
end

endmodule