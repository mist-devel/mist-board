
module blockram  #
(
   parameter init_file        = "UNUSED",
   parameter mem_size 		   = 8
)
(
		   input 		clka,
		   input [3:0] 		wea, // Port A write enable
		   input [31:0] 	dina, // Port A data input
		   input [mem_size-1:0] addra, // Port A address input
		   output [31:0] 	douta
);

   reg [mem_size-1:0] 			addra_latched;
   reg [31:0] 				mem_data [0:(1<<mem_size)-1];

   initial 
     begin 
	if (init_file != "UNUSED") begin
	   $readmemh(init_file, mem_data);
		end
     end
   
   always @(posedge clka)
     begin
	
	addra_latched <= addra;
	
	if (wea[0]) 
	  mem_data[addra][7:0] <= dina[7:0];
	if (wea[1]) 
	  mem_data[addra][15:8] <= dina[15:8];
	if (wea[2]) 
	  mem_data[addra][23:16] <= dina[23:16];
	if (wea[3]) 
	  mem_data[addra][31:24] <= dina[31:24];
	
     end
   
   assign douta = mem_data[addra_latched];

endmodule // ALTERA_MF_MEMORY_INITIALIZATION
