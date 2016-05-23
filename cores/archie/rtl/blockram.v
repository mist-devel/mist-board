/* blockram.v

 Copyright (c) 2012-2015, Stephen J. Leary
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the <organization> nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
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
