`timescale 1ns / 1ps
/*Copyright (c) 2012, Stephen J Leary
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the author nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL STEPHEN J LEARY BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
module address_decode(

		input [15:0] cpu_a,
		input [3:0]  romsel,
		
		output    ddr_enable,
		//  Memory enables
		output    ram_enable, 
		//  0x0000
		output    rom_enable, 
		//  0x8000 (BASIC/sideways ROMs)
		output    mos_enable, 
		//  0xC000

		//  IO region enables
		output    io_fred,
		//  0xFC00 (1 MHz bus)
		output    io_jim,
		//  0xFD00 (1 MHz bus)
		output    io_sheila, 
		//  0xFE00 (System peripherals)

		//  SHIELA
		output     crtc_enable, 
		//  0xFE00-FE07
		output     acia_enable, 
		//  0xFE08-FE0F
		output     serproc_enable, 
		//  0xFE10-FE1F
		output     vidproc_enable, 
		//  0xFE20-FE2F
		output     romsel_enable,
		//  0xFE30-FE3F
		output     sys_via_enable, 
		//  0xFE40-FE5F
		output     user_via_enable, 
		//  0xFE60-FE7F
		output     fddc_enable,
		//  0xFE80-FE9F
		output     adlc_enable, 
		//  0xFEA0-FEBF (Econet)
		output     adc_enable, 
		//  0xFEC0-FEDF
		output     tube_enable, 
		//  0xFEE0-FEFF
		output    mhz1_enable 
    );

//  Set for access to any 1 MHz peripheral

//  Address decoding
//  0x0000 = 32 KB SRAM
//  0x8000 = 16 KB BASIC/Sideways ROMs
//  0xC000 = 16 KB MOS ROM
// 
//  IO regions are mapped into a hole in the MOS.  There are three regions:
//  0xFC00 = FRED
//  0xFD00 = JIM
//  0xFE00 = SHEILA
assign ddr_enable = (!romsel[3] & (cpu_a[15:14] === 2'b10));
assign ram_enable = ~cpu_a[15]; 
assign rom_enable = cpu_a[15] & ~cpu_a[14]; 
assign mos_enable = cpu_a[15] & cpu_a[14] & ~(io_fred | io_jim | io_sheila); 
assign io_fred = cpu_a[15:8] === 8'b 11111100 ? 1'b 1 : 1'b 0; 
assign io_jim = cpu_a[15:8] === 8'b 11111101 ? 1'b 1 : 1'b 0; 
assign io_sheila = cpu_a[15:8] === 8'b 11111110 ? 1'b 1 : 1'b 0; 

//  The following IO regions are accessed at 1 MHz and hence will stall the
//  CPU accordingly
assign mhz1_enable = io_fred | io_jim | adc_enable | sys_via_enable | 
      user_via_enable | serproc_enable | acia_enable | crtc_enable; 

//  SHEILA address demux
//  All the system peripherals are mapped into this page as follows:
//  0xFE00 - 0xFE07 = MC6845 CRTC
//  0xFE08 - 0xFE0F = MC6850 ACIA (Serial/Tape)
//  0xFE10 - 0xFE1F = Serial ULA
//  0xFE20 - 0xFE2F = Video ULA
//  0xFE30 - 0xFE3F = Paged ROM select latch
//  0xFE40 - 0xFE5F = System VIA (6522)
//  0xFE60 - 0xFE7F = User VIA (6522)
//  0xFE80 - 0xFE9F = 8271 Floppy disc controller
//  0xFEA0 - 0xFEBF = 68B54 ADLC for Econet
//  0xFEC0 - 0xFEDF = uPD7002 ADC
//  0xFEE0 - 0xFEFF = Tube ULA

assign crtc_enable = io_sheila & (cpu_a[7:3] === 'd0);
assign acia_enable = io_sheila & (cpu_a[7:3] === 'd1);

assign serproc_enable   = io_sheila & (cpu_a[7:4] === 'b0001);
assign vidproc_enable   = io_sheila & (cpu_a[7:4] === 'b0010);
assign romsel_enable    = io_sheila & (cpu_a[7:4] === 'b0011);

assign sys_via_enable   = io_sheila & (cpu_a[7:5] === 'b010);
assign user_via_enable  = io_sheila & (cpu_a[7:5] === 'b011);

assign fddc_enable      = io_sheila & (cpu_a[7:5] === 'b100);
assign adlc_enable      = io_sheila & (cpu_a[7:5] === 'b101);
assign adc_enable       = io_sheila & (cpu_a[7:5] === 'b110);
assign tube_enable      = io_sheila & (cpu_a[7:5] === 'b111);

endmodule
