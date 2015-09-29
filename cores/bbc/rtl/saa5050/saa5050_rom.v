//
// saa5050_rom.v
// 
// Copyright (c) 2015 Stephen J. Leary (sleary@vavi.co.uk) 
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


module saa5050_rom
       (
           input			clock,
           input [MEM_BITS-1:0]    address, // Port A address input
           output [7:0]		q
       );

parameter	MEM_BITS	= 12;
localparam 	MEM_SIZE	= 2**MEM_BITS;

reg [MEM_BITS-1:0]	address_latched;
reg [7:0]			mem_data [0:MEM_SIZE-1];

initial begin
    $readmemh("saa5050.mif", mem_data);
end

always @(posedge clock) begin

    address_latched <= address;

end

assign q = mem_data[address_latched];

endmodule
