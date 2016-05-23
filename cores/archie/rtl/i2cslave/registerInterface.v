//////////////////////////////////////////////////////////////////////
////                                                              ////
//// registerInterface.v                                          ////
////                                                              ////
//// This file is part of the i2cSlave opencores effort.
//// <http://www.opencores.org/cores//>                           ////
////                                                              ////
//// Module Description:                                          ////
//// You will need to modify this file to implement your 
//// interface.
//// Add your control and status bytes/bits to module inputs and outputs,
//// and also to the I2C read and write process blocks  
////                                                              ////
//// To Do:                                                       ////
//// 
////                                                              ////
//// Author(s):                                                   ////
//// - Steve Fielding, sfielding@base2designs.com                 ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2008 Steve Fielding and OPENCORES.ORG          ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE. See the GNU Lesser General Public License for more  ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from <http://www.opencores.org/lgpl.shtml>                   ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
//
`include "i2cSlave_define.v"


module registerInterface (
 input 	      clk,
 input [7:0]  addr,
 input [7:0]  dataIn,
 input 	      writeEn,
 output reg [7:0] dataOut
);

   localparam MEM_DEPTH = 256;
   
   
reg [7:0] 	  memory[0:MEM_DEPTH-1];

integer 	  i;
   
initial begin

   $readmemh("cmos.mif", memory);
   
end
   
// --- I2C Read
always @(posedge clk) begin
  casex (addr)
    8'h02: dataOut <= 8'h33; // sec
    8'h03: dataOut <= 8'h33; // mins
    8'h04: dataOut <= 8'h11; // hour
    8'h05: dataOut <= 8'he9; // year
    8'h06: dataOut <= 8'h81; // month/week
    8'h0x: dataOut <= 8'h00; // everything else < 16
    default: dataOut <= memory[addr];
  endcase
end

// --- I2C Write
always @(posedge clk) begin
  if (writeEn == 1'b1) begin
     memory[addr] <= dataIn;
  end
end

endmodule


 
