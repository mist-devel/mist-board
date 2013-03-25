module mmu (
	// cpu register interface
	input 		 clk,
	input 		 reset,
	input [7:0] 	 din,
	input 		 sel,
	input 		 ds,
	input 		 rw,
	output reg [7:0] dout,
	output 		 dtack
);

// dtack
assign dtack = sel;

reg [7:0] memconfig;

always @(sel, ds, rw) begin
	dout = 8'd0;
	if(sel && ~ds && rw)
		dout = memconfig;
end

always @(negedge clk) begin
	if(reset)
		memconfig <= 8'h00;
	else begin
		if(sel && ~ds && ~rw)
			memconfig <= din;
	end
end

endmodule