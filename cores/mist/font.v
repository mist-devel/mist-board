module font (
	     input clk,
	     input [9:0]  a,
	     output reg [7:0] d
	     );

always @(posedge clk)
  d <= rom[a];
  
reg [7:0] rom [0:767];

initial $readmemh("font8x8.memh",rom);

endmodule // font

