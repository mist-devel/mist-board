`timescale 1ns / 1ps
/* podules.v

 Copyright (c) 2015, Stephen J. Leary
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
 
module podules(

	input           clkcpu,   // system cpu clock.
	input           clk8m_en, // goes high in sync with 32m clock to give simulated 8mhz
	input           clk2m_en, // goes high in sync with 32m clock to give simulated 2mhz
	
	input           rst_i,    // reset 
	
	input     [1:0] speed_i,  // podule access speed. (redundant except for address decode).
	
	// "wishbone bus" the ack is externally generated currently. 
	input           wb_cyc,
	input           wb_stb,
	input           wb_we,
	
	input    [15:2] wb_adr,   // la
	input    [15:0] wb_dat_i, // bd
	output   [15:0] wb_dat_o, // bd 

	// place any signals that need to be passed up to the top after here. 
	output          ide_sel,
	input    [15:0] ide_din
);

localparam PODULE0 = 2'b00;
localparam PODULE1 = 2'b01;
localparam PODULE2 = 2'b10;
localparam PODULE3 = 2'b11;

wire [1:0]  podule_addr = wb_adr[15:14];
wire [3:0]	podule_select = podule_addr == PODULE0 ? 4'b0001 : 
                            podule_addr == PODULE1 ? 4'b0010 :
                            podule_addr == PODULE2 ? 4'b0100 :
                            podule_addr == PODULE3 ? 4'b1000 : 4'd0;

wire [15:0] pod0_dat;
wire [15:0] pod1_dat;
wire [15:0] pod2_dat;
wire [15:0] pod3_dat;

// emulate a simple podule as a test for *PODULES
// assign pod0_dat  = wb_adr[13:2] == 12'd0 ? {8'd0, 8'b0_1010_000} : 16'hFFFF;

// RISC Developments IDE Interface in Podule 0

reg   [7:0] rd_rom[16384];
reg   [2:0] rd_page;
reg   [7:0] rd_rom_q;

initial begin
	   $readmemh("riscdevide_rom.hex", rd_rom);
	   rd_page <= 0;
end

assign ide_sel = wb_stb && wb_cyc && podule_select[PODULE0] && wb_adr[13:10] == 4'hA;
wire   page_sel = wb_stb && wb_cyc && podule_select[PODULE0] && wb_we && wb_adr[13:2] == 12'h800;

always @(posedge clkcpu) begin 
	if (page_sel) rd_page <= wb_dat_i[2:0];
	rd_rom_q <= rd_rom[{rd_page, wb_adr[12:2]}];
end

assign pod0_dat = ide_sel ? ide_din : {8'd0, rd_rom_q};

assign wb_dat_o = podule_select[PODULE0] ? pod0_dat : 16'hFFFF;

endmodule
