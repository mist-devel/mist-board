`timescale 1ns / 1ps
/*
 Copyright (c) 2012-2014, Stephen J. Leary
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
 
module data_io #(parameter ADDR_WIDTH=24, START_ADDR = 0)
(
	// io controller spi interface
	
	input		  	reset,
	
	output        	spi_clk,
	output        	spi_cs,
	output        	spi_mosi,
	input			spi_miso,

    input           enough,
	output          downloading,   // signal indicating an active download
	output [ADDR_WIDTH-1:0] size,          // number of bytes in input buffer
	 
	// external ram interface
	input 		    clk,
    input           clken, 
	output reg 		wr,
	output reg [ADDR_WIDTH-1:0] a,
	output [3:0] 	sel, 
	output [7:0]   d
);



(*KEEP="TRUE"*)assign sel = a[1:0] == 	2'b00 ? 4'b0001 :
								a[1:0] == 	2'b01 ? 4'b0010 :
								a[1:0] == 	2'b10 ? 4'b0100 : 4'b1000;
                                
assign d = data; //{data,data,data,data};

parameter SPI_ADDRESS = 24'h400000;
parameter SPI_COUNT = 24'h1f0000;
	
reg 		spi_write = 1'b0;
reg 		spi_done_r;
wire 		spi_done;

reg [7:0] 	spi_dout;
wire [7:0] 	data;

reg         downloading = 1'b0;

reg 		spi_enable = 1'b0;
reg 		spi_dummy = 1'b0;

reg [23:0]	spi_counter = 23'd0;
reg [23:0] 	spi_address = SPI_ADDRESS;
	
spi SPI(

	.CLOCK		( clk		),
	.CLKEN		( clken		),
	.nWR		( ~spi_write ),
	.nRESET		( ~reset	),
	.ENABLE		( enable	),
	
	.DONE		( spi_done		),
	
	.DI			( spi_dout	), 
	.DO			( data	),
	.DUMMY		( spi_dummy		),
	
	.SD_CLK		( spi_clk	),
	.SD_CS		( spi_cs	),
	.SD_MOSI	( spi_mosi	),
	.SD_MISO	( spi_miso	)
	
);

always @(posedge clk) begin
	
	if (reset) begin
		
		// the address in ROM to read. 
		spi_address <= SPI_ADDRESS;
		// count SPI byte cycles.
		spi_counter <= 24'd0;
		spi_write <= 1'b0;
   		spi_dummy <= 1'b0;
		spi_done_r <= 1'b1;
     
		a				<=	START_ADDR;
		wr 				<= 	1'b0;
		spi_dout	    <= 	8'hA5;
        downloading 	<=  1'b0;
		
	end else if (clken === 1'b 1) begin
		
		spi_enable  <= 1'b0;
        wr      	<= 1'b0;
		
        if (wr) begin 
            a <= a + 'd1;
        end
        
		if (spi_done_r === 1'b0 && spi_done === 1'b1) begin
			
            downloading <= 1'b0;
            
			if (!enough) begin 
                
                downloading <= 1'b1;
				spi_counter	<= spi_counter + 'd1;
							
				case (spi_counter)
				
					24'd0: begin 
						spi_write <= 1'b1;
						spi_dout <= 8'h0B;
					end
					24'd1: spi_dout <= {spi_address[23:16]};
					24'd2: spi_dout <= {spi_address[15:8]};
					24'd3: spi_dout <= {spi_address[7:0]};
					24'd4: begin 
						spi_write 	<= 1'b0;
						spi_dummy 	<= 1'b1;
					end
					
					default: begin 
						spi_dummy 	<= 1'b0;
                        wr    		<= (spi_counter > 8);
					end
                    
				endcase 
				
				spi_enable <= 1'b1;
			
			end 
		end
		
		spi_done_r <= spi_done;
		
	end
end

endmodule
