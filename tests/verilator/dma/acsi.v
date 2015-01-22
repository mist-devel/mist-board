// acsi.v
//
// Atari ST ACSI implementation for the MIST baord
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2015 Till Harbaum <till@harbaum.org>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

module acsi (
	    // clocks and system interface
	input 	     clk,
	input 	     reset,

	input [7:0]  enable,
	    
	input 	     dma_ack, // IO controller answers request
	input 	     dma_nak, // IO controller rejects request
	input [7:0]  dma_status,

	
	input [2:0]  status_sel,
	output [7:0] status_byte,

        // cpu interface
        input [1:0]  cpu_addr,
        input 	     cpu_sel,
        input 	     cpu_rw,
        input [7:0]  cpu_din,
        output [7:0] cpu_dout,

	output reg   irq		 
);

// acsi always returns dma status on cpu_read
assign cpu_dout = dma_status;
   
reg [2:0] target;
reg [4:0] cmd;
reg [2:0] byte_counter;
reg [7:0] cmd_parms [4:0];
reg busy;

// acsi status as reported to the io controller
assign status_byte =
    (status_sel == 0)?{ target, cmd }:
    (status_sel == 1)?cmd_parms[0]:
    (status_sel == 2)?cmd_parms[1]:
    (status_sel == 3)?cmd_parms[2]:
    (status_sel == 4)?cmd_parms[3]:
    (status_sel == 5)?cmd_parms[4]:
    (status_sel == 6)?{ 7'b0000000, busy }:
    8'h00;

// CPU write interface
always @(negedge clk) begin
   if(reset) begin
      target <= 3'd0;
      cmd <= 5'd0;
      irq <= 1'b0;
      busy <= 1'b0;
   end else begin
      
      // DMA transfer has been ack'd by io controller
      if(dma_ack && busy) begin
	 irq <= 1'b1;   // set acsi irq			
	 busy <= 1'd0;
      end

      // DMA transfer has been rejected by io controller (no such device)
      if(dma_nak)
	busy <= 1'd0;

      // cpu is reading status register -> clear acsi irq
      // status itself is returned by the io controller with the dma_ack
      if(cpu_sel && cpu_rw)
	irq <= 1'b0;
	 
      // acsi register access
      if(cpu_sel && !cpu_rw) begin
	 if(!cpu_addr[0]) begin
	    // a0 == 0 -> first command byte
	    target <= cpu_din[7:5];
	    cmd <= cpu_din[4:0];
	    byte_counter <= 3'd0;
	    
	    // check if this acsi device is enabled
	    if(enable[cpu_din[7:5]] == 1'b1)
	      irq <= 1'b1;
	 end else begin
	    // further bytes
	    cmd_parms[byte_counter] <= cpu_din[7:0];
	    byte_counter <= byte_counter + 3'd1;
	    
	    // check if this acsi device is enabled
	    if(enable[target] == 1'b1) begin
	       // auto-ack first 5 bytes
	       if(byte_counter < 4)
		 irq <= 1'b1;
	       else
		 busy <= 1'b1;  // request io cntroller
	    end
	 end
      end
   end
end
 
endmodule // acsi
