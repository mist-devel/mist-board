`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    09:29:12 07/19/2012 
// Design Name: 
// Module Name:    spi 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////

module spi (
   
	input   	CLOCK,
	input   	nRESET, 
	input   	CLKEN,
	input   	ENABLE, 

	input   	nWR,
	input [7:0] DI, 
	output[7:0] DO, 
	input		DUMMY,

	output reg 	DONE,

	output   	SD_CS,
	output   	SD_CLK,
	
	output		SD_MOSI, 
	input		SD_MISO

);
 
reg     [4:0] counter; 

assign 	SD_MOSI = shift_reg[8];


//  Shift register has an extra bit because we write on the
//  falling edge and read on the rising edge
reg     [8:0] shift_reg; 
reg     [7:0] in_reg; 
reg	  		  quad_mode;
reg			  dummy;

assign DO = in_reg;

//  SD card outputs from clock divider and shift register
assign SD_CLK = counter[0]; 

//  SPI write

always @(posedge CLOCK) begin 
   
	if (nRESET === 1'b 0) begin
	
		shift_reg <= {9{1'b 1}};   
		in_reg <= {8{1'b 1}};   
		counter <= 5'b 01111;   //  Idle
		DONE <= 1'b0;
		dummy <= 1'b0;

   end else if (CLKEN === 1'b 1) begin

		DONE <= 1'b0;

		if (((counter === 5'b 01111) & !dummy) | ((counter === 5'b10001) & dummy)) begin
		
			//  Store previous shift register value in input register
			in_reg <= shift_reg[7:0];   
			DONE <= 1'b1;

			//  Idle - check for a bus access
			if (ENABLE === 1'b 1) begin

				//  Write loads shift register with data
				//  Read loads it with all 1s
				if (nWR === 1'b 1) begin
					shift_reg <= {9{1'b 1}};  
				end else begin
					shift_reg <= {DI, 1'b 1}; 			
				end
				
				dummy <= DUMMY;
				counter <= 5'b 00000;  //  Initiates transfer
				
			end

		//  Transfer in progress
		end else begin
		
			counter <= counter + 4'd1;   
		
			if (counter[0] === 1'b 0) begin
				
				shift_reg[0] <= SD_MISO;   
				
				//  Output next bit on falling edge
			end else begin
			
				shift_reg <= {shift_reg[7:0], 1'b 1};

			end
			
		end
	end
end

assign SD_CS = !nRESET;

endmodule // module flash


