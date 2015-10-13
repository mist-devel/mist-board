module led7seg(
	input [3:0] data,
	output [6:0] segments
);

	reg [6:0] _segments;
	assign segments = ~_segments;
	
	always @(data) begin
		case (data)
			4'h0: _segments = 7'b0111111;
			4'h1: _segments = 7'b0000110;
			4'h2: _segments = 7'b1011011;
			4'h3: _segments = 7'b1001111;
			4'h4: _segments = 7'b1100110;
			4'h5: _segments = 7'b1101101;
			4'h6: _segments = 7'b1111101;
			4'h7: _segments = 7'b0000111;
			4'h8: _segments = 7'b1111111;
			4'h9: _segments = 7'b1101111;
			4'hA: _segments = 7'b1110111;
			4'hB: _segments = 7'b1111100;
			4'hC: _segments = 7'b0111001;
			4'hD: _segments = 7'b1011110;
			4'hE: _segments = 7'b1111001;
			4'hF: _segments = 7'b1110001;
		endcase
	end

endmodule