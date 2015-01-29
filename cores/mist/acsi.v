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

	
	input [3:0]  status_sel,  // 10 command bytes + 1 status byte
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

// Total number of command bytes:
// cmd 0..1f  -> 6 
// cmd 20..5f -> 10
// cmd 80..9f -> 16
// cmd a0..bf -> 12

wire [7:0] cmd_code = cmd_parameter[0];
wire [3:0] parms =
	((cmd_code >= 8'h00)&&(cmd_code <= 8'h1f))?5:
	((cmd_code >= 8'h20)&&(cmd_code <= 8'h5f))?9:
	((cmd_code >= 8'h80)&&(cmd_code <= 8'h9f))?15:
	11;
   
reg [2:0] target;
reg [3:0] byte_counter;
reg [7:0] cmd_parameter [15:0];
reg busy;

// acsi status as reported to the io controller
assign status_byte =
    (status_sel == 0)?cmd_parameter[0]:
    (status_sel == 1)?cmd_parameter[1]:
    (status_sel == 2)?cmd_parameter[2]:
    (status_sel == 3)?cmd_parameter[3]:
    (status_sel == 4)?cmd_parameter[4]:
    (status_sel == 5)?cmd_parameter[5]:
    (status_sel == 6)?cmd_parameter[6]:
    (status_sel == 7)?cmd_parameter[7]:
    (status_sel == 8)?cmd_parameter[8]:
    (status_sel == 9)?cmd_parameter[9]:
    (status_sel == 10)?{ target, 4'b0000000, busy }:
    8'h00;

// CPU write interface
always @(negedge clk) begin
   if(reset) begin
      target <= 3'd0;
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

      // cpu is accessing acsi bus -> clear acsi irq
      // status itself is returned by the io controller with the dma_ack.
		if(cpu_sel)
			irq <= 1'b0;
	 
      // acsi register access
      if(cpu_sel && !cpu_rw) begin
			if(!cpu_addr[0]) begin
				// a0 == 0 -> first command byte
				target <= cpu_din[7:5];
	
				// icd command?
				if(cpu_din[4:0] == 5'h1f)
					byte_counter <= 3'd0;   // next byte will contain first command byte
				else begin
					cmd_parameter[0] <= { 3'd0, cpu_din[4:0] };
					byte_counter <= 3'd1;   // next byte will contain second command byte
	    		end
				
				// check if this acsi device is enabled
				if(enable[cpu_din[7:5]] == 1'b1)
					irq <= 1'b1;
			end else begin
			
//				if(byte_counter < 15) begin

					// further bytes
					cmd_parameter[byte_counter] <= cpu_din;
					byte_counter <= byte_counter + 3'd1;
	    
					// check if this acsi device is enabled
					if(enable[target] == 1'b1) begin
						// auto-ack first 5 bytes, 6 bytes in case of icd command
						if(byte_counter < parms)
							irq <= 1'b1;
						else
							busy <= 1'b1;  // request io cntroller
					end
				end
//			end
      end
   end
end
 
endmodule // acsi
