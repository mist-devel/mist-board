module led(
	input CLOCK_27,
	output reg LED
	);
	
	reg [31:0] counter;	
	reg clk;
	
	always@(posedge CLOCK_27) begin
		if (counter > 6750000) begin
			counter <= 0;
			clk <= !clk;
		end
		else
			counter <= counter + 32'd1;
	end

	always@(posedge clk) begin
	  LED <= !LED;
	end
	
endmodule
