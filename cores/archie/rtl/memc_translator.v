`timescale 1ns / 1ps
/* memc_translator.v

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
 
module memc_translator
(
		input 			clkcpu,
		
		input			wr,		// write to the page table
		input [1:0]		page_size,
		input			spvmd,
		input			osmd,
		input			mem_write,
		
		input	[25:0]	addr_i,
		output  [25:0]	addr_o,
		output			valid
);

localparam PAGE_TABLE_SIZE = 128;

// Memory protection truth table.
//      |  00  |  01  |  10  |  11  |
// -----|------|------|------|------|
// SPVMD| R/W  | R/W  | R/W  | R/W  |
//  OSMD| R/W  | R/W  |  R   |  R   |
// USRMD| R/W  |  R   |  -   |  -   |
// 		|------|------|------|------|

// address translation table.

// TODO: other memory sizes?
// if the OS uses different memory sizes at startup i'll implement it
// otherwise i'll make it fixed at synth time.
 
// ppn swizzle for 32K page size. 
// could potentially get 16Mb here by making 512 pages.
wire [6:0] ppn =  page_size == 2'b00 ? {addr_i[6:0]} :
						page_size == 2'b01 ? {addr_i[0], addr_i[6:1]} : 
						page_size == 2'b10 ? {addr_i[1:0], addr_i[6:2]} :
										         {addr_i[1], addr_i[2], addr_i[0], addr_i[6:3]};

genvar c;
generate
	for (c = 0; c < PAGE_TABLE_SIZE; c = c + 1) begin: pgentry
		
		reg[14:0] 	r	= 	0; 				// register for this table entry.
		
		wire 		prot		= spvmd | (osmd & ~mem_write) | (osmd & mem_write & r[14]) | ~r[14] & r[13] & ~mem_write | ~r[14] & ~r[13];
		
		wire		en	= 	r[12:3] == addr_i[24:15] & prot; // lookup logic when this table is active.
		wire 		sel	= 	ppn[6:0] == c[6:0]; // select logic for this page table (for writing table)
		wire [25:0]	addr = 	{4'b0000, c[6:0], addr_i[14:0]};
		
		always @(posedge clkcpu) begin
		
			if (wr & sel) begin 
	
				// code to program the table
				r <= {addr_i[9:8], addr_i[11:10], addr_i[22:12]};
				$display("writing to table entry %d := %x (%x)", c,  {addr_i[9:8], addr_i[11:10], addr_i[22:12]}, addr_i);
				
			end 
			
		end
		
    end

endgenerate

// 128 to 1 decode. 
assign addr_o = pgentry[0].en ? pgentry[0].addr : 
		pgentry[1].en ? pgentry[1].addr : 
		pgentry[2].en ? pgentry[2].addr : 
		pgentry[3].en ? pgentry[3].addr : 
		pgentry[4].en ? pgentry[4].addr : 
		pgentry[5].en ? pgentry[5].addr : 
		pgentry[6].en ? pgentry[6].addr : 
		pgentry[7].en ? pgentry[7].addr : 
		pgentry[8].en ? pgentry[8].addr : 
		pgentry[9].en ? pgentry[9].addr : 
		pgentry[10].en ? pgentry[10].addr : 
		pgentry[11].en ? pgentry[11].addr : 
		pgentry[12].en ? pgentry[12].addr : 
		pgentry[13].en ? pgentry[13].addr : 
		pgentry[14].en ? pgentry[14].addr : 
		pgentry[15].en ? pgentry[15].addr : 
		pgentry[16].en ? pgentry[16].addr : 
		pgentry[17].en ? pgentry[17].addr : 
		pgentry[18].en ? pgentry[18].addr : 
		pgentry[19].en ? pgentry[19].addr : 
		pgentry[20].en ? pgentry[20].addr : 
		pgentry[21].en ? pgentry[21].addr : 
		pgentry[22].en ? pgentry[22].addr : 
		pgentry[23].en ? pgentry[23].addr : 
		pgentry[24].en ? pgentry[24].addr : 
		pgentry[25].en ? pgentry[25].addr : 
		pgentry[26].en ? pgentry[26].addr : 
		pgentry[27].en ? pgentry[27].addr : 
		pgentry[28].en ? pgentry[28].addr : 
		pgentry[29].en ? pgentry[29].addr : 
		pgentry[30].en ? pgentry[30].addr : 
		pgentry[31].en ? pgentry[31].addr : 
		pgentry[32].en ? pgentry[32].addr : 
		pgentry[33].en ? pgentry[33].addr : 
		pgentry[34].en ? pgentry[34].addr : 
		pgentry[35].en ? pgentry[35].addr : 
		pgentry[36].en ? pgentry[36].addr : 
		pgentry[37].en ? pgentry[37].addr : 
		pgentry[38].en ? pgentry[38].addr : 
		pgentry[39].en ? pgentry[39].addr : 
		pgentry[40].en ? pgentry[40].addr : 
		pgentry[41].en ? pgentry[41].addr : 
		pgentry[42].en ? pgentry[42].addr : 
		pgentry[43].en ? pgentry[43].addr : 
		pgentry[44].en ? pgentry[44].addr : 
		pgentry[45].en ? pgentry[45].addr : 
		pgentry[46].en ? pgentry[46].addr : 
		pgentry[47].en ? pgentry[47].addr : 
		pgentry[48].en ? pgentry[48].addr : 
		pgentry[49].en ? pgentry[49].addr : 
		pgentry[50].en ? pgentry[50].addr : 
		pgentry[51].en ? pgentry[51].addr : 
		pgentry[52].en ? pgentry[52].addr : 
		pgentry[53].en ? pgentry[53].addr : 
		pgentry[54].en ? pgentry[54].addr : 
		pgentry[55].en ? pgentry[55].addr : 
		pgentry[56].en ? pgentry[56].addr : 
		pgentry[57].en ? pgentry[57].addr : 
		pgentry[58].en ? pgentry[58].addr : 
		pgentry[59].en ? pgentry[59].addr : 
		pgentry[60].en ? pgentry[60].addr : 
		pgentry[61].en ? pgentry[61].addr : 
		pgentry[62].en ? pgentry[62].addr : 
		pgentry[63].en ? pgentry[63].addr : 
		pgentry[64].en ? pgentry[64].addr : 
		pgentry[65].en ? pgentry[65].addr : 
		pgentry[66].en ? pgentry[66].addr : 
		pgentry[67].en ? pgentry[67].addr : 
		pgentry[68].en ? pgentry[68].addr : 
		pgentry[69].en ? pgentry[69].addr : 
		pgentry[70].en ? pgentry[70].addr : 
		pgentry[71].en ? pgentry[71].addr : 
		pgentry[72].en ? pgentry[72].addr : 
		pgentry[73].en ? pgentry[73].addr : 
		pgentry[74].en ? pgentry[74].addr : 
		pgentry[75].en ? pgentry[75].addr : 
		pgentry[76].en ? pgentry[76].addr : 
		pgentry[77].en ? pgentry[77].addr : 
		pgentry[78].en ? pgentry[78].addr : 
		pgentry[79].en ? pgentry[79].addr : 
		pgentry[80].en ? pgentry[80].addr : 
		pgentry[81].en ? pgentry[81].addr : 
		pgentry[82].en ? pgentry[82].addr : 
		pgentry[83].en ? pgentry[83].addr : 
		pgentry[84].en ? pgentry[84].addr : 
		pgentry[85].en ? pgentry[85].addr : 
		pgentry[86].en ? pgentry[86].addr : 
		pgentry[87].en ? pgentry[87].addr : 
		pgentry[88].en ? pgentry[88].addr : 
		pgentry[89].en ? pgentry[89].addr : 
		pgentry[90].en ? pgentry[90].addr : 
		pgentry[91].en ? pgentry[91].addr : 
		pgentry[92].en ? pgentry[92].addr : 
		pgentry[93].en ? pgentry[93].addr : 
		pgentry[94].en ? pgentry[94].addr : 
		pgentry[95].en ? pgentry[95].addr : 
		pgentry[96].en ? pgentry[96].addr : 
		pgentry[97].en ? pgentry[97].addr : 
		pgentry[98].en ? pgentry[98].addr : 
		pgentry[99].en ? pgentry[99].addr : 
		pgentry[100].en ? pgentry[100].addr : 
		pgentry[101].en ? pgentry[101].addr : 
		pgentry[102].en ? pgentry[102].addr : 
		pgentry[103].en ? pgentry[103].addr : 
		pgentry[104].en ? pgentry[104].addr : 
		pgentry[105].en ? pgentry[105].addr : 
		pgentry[106].en ? pgentry[106].addr : 
		pgentry[107].en ? pgentry[107].addr : 
		pgentry[108].en ? pgentry[108].addr : 
		pgentry[109].en ? pgentry[109].addr : 
		pgentry[110].en ? pgentry[110].addr : 
		pgentry[111].en ? pgentry[111].addr : 
		pgentry[112].en ? pgentry[112].addr : 
		pgentry[113].en ? pgentry[113].addr : 
		pgentry[114].en ? pgentry[114].addr : 
		pgentry[115].en ? pgentry[115].addr : 
		pgentry[116].en ? pgentry[116].addr : 
		pgentry[117].en ? pgentry[117].addr : 
		pgentry[118].en ? pgentry[118].addr : 
		pgentry[119].en ? pgentry[119].addr : 
		pgentry[120].en ? pgentry[120].addr : 
		pgentry[121].en ? pgentry[121].addr : 
		pgentry[122].en ? pgentry[122].addr : 
		pgentry[123].en ? pgentry[123].addr : 
		pgentry[124].en ? pgentry[124].addr : 
		pgentry[125].en ? pgentry[125].addr : 
		pgentry[126].en ? pgentry[126].addr : 
		pgentry[127].en ? pgentry[127].addr : 26'hZZZZZZZ;

assign valid = 	pgentry[0].en | pgentry[1].en | pgentry[2].en | pgentry[3].en | pgentry[4].en | pgentry[5].en | pgentry[6].en | pgentry[7].en | 
				pgentry[8].en | pgentry[9].en | pgentry[10].en | pgentry[11].en | pgentry[12].en | pgentry[13].en | pgentry[14].en | pgentry[15].en | 
				pgentry[16].en | pgentry[17].en | pgentry[18].en | pgentry[19].en | pgentry[20].en | pgentry[21].en | pgentry[22].en | pgentry[23].en | 
				pgentry[24].en | pgentry[25].en | pgentry[26].en | pgentry[27].en | pgentry[28].en | pgentry[29].en | pgentry[30].en | pgentry[31].en | 
				pgentry[32].en | pgentry[33].en | pgentry[34].en | pgentry[35].en | pgentry[36].en | pgentry[37].en | pgentry[38].en | pgentry[39].en | 
				pgentry[40].en | pgentry[41].en | pgentry[42].en | pgentry[43].en | pgentry[44].en | pgentry[45].en | pgentry[46].en | pgentry[47].en | 
				pgentry[48].en | pgentry[49].en | pgentry[50].en | pgentry[51].en | pgentry[52].en | pgentry[53].en | pgentry[54].en | pgentry[55].en | 
				pgentry[56].en | pgentry[57].en | pgentry[58].en | pgentry[59].en | pgentry[60].en | pgentry[61].en | pgentry[62].en | pgentry[63].en | 
				pgentry[64].en | pgentry[65].en | pgentry[66].en | pgentry[67].en | pgentry[68].en | pgentry[69].en | pgentry[70].en | pgentry[71].en | 
				pgentry[72].en | pgentry[73].en | pgentry[74].en | pgentry[75].en | pgentry[76].en | pgentry[77].en | pgentry[78].en | pgentry[79].en | 
				pgentry[80].en | pgentry[81].en | pgentry[82].en | pgentry[83].en | pgentry[84].en | pgentry[85].en | pgentry[86].en | pgentry[87].en | 
				pgentry[88].en | pgentry[89].en | pgentry[90].en | pgentry[91].en | pgentry[92].en | pgentry[93].en | pgentry[94].en | pgentry[95].en | 
				pgentry[96].en | pgentry[97].en | pgentry[98].en | pgentry[99].en | pgentry[100].en | pgentry[101].en | pgentry[102].en | pgentry[103].en | 
				pgentry[104].en | pgentry[105].en | pgentry[106].en | pgentry[107].en | pgentry[108].en | pgentry[109].en | pgentry[110].en | pgentry[111].en | 
				pgentry[112].en | pgentry[113].en | pgentry[114].en | pgentry[115].en | pgentry[116].en | pgentry[117].en | pgentry[118].en | pgentry[119].en | 
				pgentry[120].en | pgentry[121].en | pgentry[122].en | pgentry[123].en | pgentry[124].en | pgentry[125].en | pgentry[126].en | pgentry[127].en;
		
endmodule
