module fontGen(
	input [5:0] char,
	input [2:0] row,
	output reg [7:0] dataOut
);

	always @(*) begin
		case ( { char, row } )
			// 0
			{ 4'h0, 3'h0 }: dataOut = 8'b11111111;			
			{ 4'h0, 3'h1 }: dataOut = 8'b11000011;
			{ 4'h0, 3'h2 }: dataOut = 8'b10011001;
			{ 4'h0, 3'h3 }: dataOut = 8'b10010001;
			{ 4'h0, 3'h4 }: dataOut = 8'b10001001;
			{ 4'h0, 3'h5 }: dataOut = 8'b10011001;
			{ 4'h0, 3'h6 }: dataOut = 8'b11000011;
			{ 4'h0, 3'h7 }: dataOut = 8'b11111111;
			
			// 1
			{ 4'h1, 3'h0 }: dataOut = 8'b11111111;	
			{ 4'h1, 3'h1 }: dataOut = 8'b11100111;
			{ 4'h1, 3'h2 }: dataOut = 8'b11000111;
			{ 4'h1, 3'h3 }: dataOut = 8'b11100111;
			{ 4'h1, 3'h4 }: dataOut = 8'b11100111;
			{ 4'h1, 3'h5 }: dataOut = 8'b11100111;
			{ 4'h1, 3'h6 }: dataOut = 8'b10000001;
			{ 4'h1, 3'h7 }: dataOut = 8'b11111111;
	
			// 2
			{ 4'h2, 3'h0 }: dataOut = 8'b11111111;	
			{ 4'h2, 3'h1 }: dataOut = 8'b11000011;
			{ 4'h2, 3'h2 }: dataOut = 8'b10011001;
			{ 4'h2, 3'h3 }: dataOut = 8'b11110011;
			{ 4'h2, 3'h4 }: dataOut = 8'b11100111;
			{ 4'h2, 3'h5 }: dataOut = 8'b11001111;
			{ 4'h2, 3'h6 }: dataOut = 8'b10000001;
			{ 4'h2, 3'h7 }: dataOut = 8'b11111111;	
		
			// 3
			{ 4'h3, 3'h0 }: dataOut = 8'b11111111;		
			{ 4'h3, 3'h1 }: dataOut = 8'b10000001;
			{ 4'h3, 3'h2 }: dataOut = 8'b11110011;
			{ 4'h3, 3'h3 }: dataOut = 8'b11100111;
			{ 4'h3, 3'h4 }: dataOut = 8'b11110011;
			{ 4'h3, 3'h5 }: dataOut = 8'b10011001;
			{ 4'h3, 3'h6 }: dataOut = 8'b11000011;
			{ 4'h3, 3'h7 }: dataOut = 8'b11111111;
		
			// 4
			{ 4'h4, 3'h0 }: dataOut = 8'b11111111;	
			{ 4'h4, 3'h1 }: dataOut = 8'b11110011;
			{ 4'h4, 3'h2 }: dataOut = 8'b11100011;
			{ 4'h4, 3'h3 }: dataOut = 8'b11000011;
			{ 4'h4, 3'h4 }: dataOut = 8'b10010011;
			{ 4'h4, 3'h5 }: dataOut = 8'b10000001;
			{ 4'h4, 3'h6 }: dataOut = 8'b11110011;
			{ 4'h4, 3'h7 }: dataOut = 8'b11111111;
	
			// 5
			{ 4'h5, 3'h0 }: dataOut = 8'b11111111;	
			{ 4'h5, 3'h1 }: dataOut = 8'b10000001;
			{ 4'h5, 3'h2 }: dataOut = 8'b10011111;
			{ 4'h5, 3'h3 }: dataOut = 8'b10000011;
			{ 4'h5, 3'h4 }: dataOut = 8'b11111001;
			{ 4'h5, 3'h5 }: dataOut = 8'b10011001;
			{ 4'h5, 3'h6 }: dataOut = 8'b11000011;
			{ 4'h5, 3'h7 }: dataOut = 8'b11111111;
	
			// 6
			{ 4'h6, 3'h0 }: dataOut = 8'b11111111;	
			{ 4'h6, 3'h1 }: dataOut = 8'b11000011;
			{ 4'h6, 3'h2 }: dataOut = 8'b10011111;
			{ 4'h6, 3'h3 }: dataOut = 8'b10000011;
			{ 4'h6, 3'h4 }: dataOut = 8'b10011001;
			{ 4'h6, 3'h5 }: dataOut = 8'b10011001;
			{ 4'h6, 3'h6 }: dataOut = 8'b11000011;
			{ 4'h6, 3'h7 }: dataOut = 8'b11111111;
		
			// 7
			{ 4'h7, 3'h0 }: dataOut = 8'b11111111;	
			{ 4'h7, 3'h1 }: dataOut = 8'b10000001;
			{ 4'h7, 3'h2 }: dataOut = 8'b11111001;
			{ 4'h7, 3'h3 }: dataOut = 8'b11110011;
			{ 4'h7, 3'h4 }: dataOut = 8'b11100111;
			{ 4'h7, 3'h5 }: dataOut = 8'b11001111;
			{ 4'h7, 3'h6 }: dataOut = 8'b11001111;
			{ 4'h7, 3'h7 }: dataOut = 8'b11111111;
	
			// 8
			{ 4'h8, 3'h0 }: dataOut = 8'b11111111;	
			{ 4'h8, 3'h1 }: dataOut = 8'b11000011;
			{ 4'h8, 3'h2 }: dataOut = 8'b10011001;
			{ 4'h8, 3'h3 }: dataOut = 8'b11000011;
			{ 4'h8, 3'h4 }: dataOut = 8'b10011001;
			{ 4'h8, 3'h5 }: dataOut = 8'b10011001;
			{ 4'h8, 3'h6 }: dataOut = 8'b11000011;
			{ 4'h8, 3'h7 }: dataOut = 8'b11111111;
		
			// 9
			{ 4'h9, 3'h0 }: dataOut = 8'b11111111;	
			{ 4'h9, 3'h1 }: dataOut = 8'b11000011;
			{ 4'h9, 3'h2 }: dataOut = 8'b10011001;
			{ 4'h9, 3'h3 }: dataOut = 8'b11000001;
			{ 4'h9, 3'h4 }: dataOut = 8'b11111001;
			{ 4'h9, 3'h5 }: dataOut = 8'b11110011;
			{ 4'h9, 3'h6 }: dataOut = 8'b11000111;
			{ 4'h9, 3'h7 }: dataOut = 8'b11111111;
			
			// A
			{ 4'hA, 3'h0 }: dataOut = 8'b11111111;	
			{ 4'hA, 3'h1 }: dataOut = 8'b11100111;
			{ 4'hA, 3'h2 }: dataOut = 8'b11000011;
			{ 4'hA, 3'h3 }: dataOut = 8'b10011001;
			{ 4'hA, 3'h4 }: dataOut = 8'b10011001;
			{ 4'hA, 3'h5 }: dataOut = 8'b10000001;
			{ 4'hA, 3'h6 }: dataOut = 8'b10011001;
			{ 4'hA, 3'h7 }: dataOut = 8'b11111111;
	
			// B
			{ 4'hB, 3'h0 }: dataOut = 8'b11111111;	
			{ 4'hB, 3'h1 }: dataOut = 8'b10000011;
			{ 4'hB, 3'h2 }: dataOut = 8'b10011001;
			{ 4'hB, 3'h3 }: dataOut = 8'b10000011;
			{ 4'hB, 3'h4 }: dataOut = 8'b10011001;
			{ 4'hB, 3'h5 }: dataOut = 8'b10011001;
			{ 4'hB, 3'h6 }: dataOut = 8'b10000011;
			{ 4'hB, 3'h7 }: dataOut = 8'b11111111;
		
			// C
			{ 4'hC, 3'h0 }: dataOut = 8'b11111111;	
			{ 4'hC, 3'h1 }: dataOut = 8'b11000011;
			{ 4'hC, 3'h2 }: dataOut = 8'b10011001;
			{ 4'hC, 3'h3 }: dataOut = 8'b10011111;
			{ 4'hC, 3'h4 }: dataOut = 8'b10011111;
			{ 4'hC, 3'h5 }: dataOut = 8'b10011001;
			{ 4'hC, 3'h6 }: dataOut = 8'b11000011;
			{ 4'hC, 3'h7 }: dataOut = 8'b11111111;
	
			// D
			{ 4'hD, 3'h0 }: dataOut = 8'b11111111;	
			{ 4'hD, 3'h1 }: dataOut = 8'b10000111;
			{ 4'hD, 3'h2 }: dataOut = 8'b10010011;
			{ 4'hD, 3'h3 }: dataOut = 8'b10011001;
			{ 4'hD, 3'h4 }: dataOut = 8'b10011001;
			{ 4'hD, 3'h5 }: dataOut = 8'b10010011;
			{ 4'hD, 3'h6 }: dataOut = 8'b10000111;
			{ 4'hD, 3'h7 }: dataOut = 8'b11111111;
		
			// E
			{ 4'hE, 3'h0 }: dataOut = 8'b11111111;	
			{ 4'hE, 3'h1 }: dataOut = 8'b10000001;
			{ 4'hE, 3'h2 }: dataOut = 8'b10011111;
			{ 4'hE, 3'h3 }: dataOut = 8'b10000011;
			{ 4'hE, 3'h4 }: dataOut = 8'b10011111;
			{ 4'hE, 3'h5 }: dataOut = 8'b10011111;
			{ 4'hE, 3'h6 }: dataOut = 8'b10000001;
			{ 4'hE, 3'h7 }: dataOut = 8'b11111111;

			// F
			{ 4'hF, 3'h0 }: dataOut = 8'b11111111;	
			{ 4'hF, 3'h1 }: dataOut = 8'b10000001;
			{ 4'hF, 3'h2 }: dataOut = 8'b10011111;
			{ 4'hF, 3'h3 }: dataOut = 8'b10000011;
			{ 4'hF, 3'h4 }: dataOut = 8'b10011111;
			{ 4'hF, 3'h5 }: dataOut = 8'b10011111;
			{ 4'hF, 3'h6 }: dataOut = 8'b10011111;
			{ 4'hF, 3'h7 }: dataOut = 8'b11111111;
			
			default: dataOut = 8'b11111111;	
				
		endcase
	end
endmodule
