// Copyright 2006, 2007 Dennis van Weeren
//
// This file is part of Minimig
//
// Minimig is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Minimig is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
//
// This is Gary
// It is the equivalent of Gary in a real Amiga
// Gary handles the address decoding and cpu/chip bus multiplexing
// Gary handles kickstart area and bootrom overlay
// Gary handles CIA e clock synchronization
//
// 20-12-2005	- started coding
// 21-12-2005	- done more coding
// 25-12-2005	- changed blitter nasty handling
// 15-01-2006	- fixed sensitivity list
// 12-11-2006	- debugging for new Minimig rev1.0 board
// 17-11-2006	- removed debugging and added decode for $C0000 ram
// ----------
// JB:
// 2008-10-06	- added decoders for IDE and GAYLE register range
// 2008-10-15	- signal name change cpuok -> dbr
// 2009-05-23	- better timing model for CIA interface
// 2009-05-24	- clean-up & renaming
// 2009-05-25	- ram, cpu and custom chips bus multiplexer
// 2009-09-01	- fixed sel_kick
// 2010-08-15	- clean-up
//
// SB:
// 2010-10-18 - added special memory config like in A500 Rev.6 with 512kb + 512kb of memory
//
// AMR:
// 2012-03-23  - Added select for Akiko

module gary
(
	input 	[23:1] cpu_address_in,	//cpu address bus input
	input	[20:1] dma_address_in,	//agnus dma memory address input
	output	[18:1] ram_address_out, //ram address bus output
	input	[15:0] cpu_data_out,
	output	[15:0] cpu_data_in,
	input	[15:0] custom_data_out,
	output	[15:0] custom_data_in,
	input	[15:0] ram_data_out,
	output	[15:0] ram_data_in,
  input a1k,
	input	cpu_rd,					//cpu read
	input	cpu_hwr,				//cpu high write
	input	cpu_lwr,				//cpu low write
	
	input	ovl,					//overlay kickstart rom over chipram
	input	boot,					//overlay bootrom over chipram
	input	dbr,					//Agns takes the bus
	input	dbwe,					//Agnus does a write cycle
	output	dbs,					//data bus slow down
	output	xbs,					//cross bridge select, active dbr prevents access
	
	input	[3:0] memory_config,	//selected memory configuration
  input ecs,            // ECS chipset enable
	input	hdc_ena,				//enables hdd interface
	
	output	ram_rd,					//bus read
	output	ram_hwr,				//bus high write
	output	ram_lwr,				//bus low write
	
	output 	sel_reg,  				//select chip register bank
	output 	reg [3:0] sel_chip, 	//select chip memory
	output	reg [2:0] sel_slow,		//select slowfast memory ($C0000)
	output 	reg sel_kick,		    //select kickstart rom
	output	sel_boot,				//select boot room
	output	sel_cia,				//select CIA space
	output 	sel_cia_a,				//select cia A
	output 	sel_cia_b, 				//select cia B
	output	sel_rtc,				//select $DCxxxx
	output	sel_ide,				//select $DAxxxx
	output	sel_gayle				//select $DExxxx
);

wire	[2:0] t_sel_slow;
wire	sel_xram;
wire	sel_bank_1; 				// $200000-$3FFFFF

//--------------------------------------------------------------------------------------

assign ram_data_in = dbr ? custom_data_out : cpu_data_out;

assign custom_data_in = dbr ? ram_data_out : cpu_rd ? 16'hFFFF : cpu_data_out;

assign cpu_data_in = dbr ? 16'h00_00 : custom_data_out | ram_data_out | {16{sel_bank_1}};

//read write control signals
assign ram_rd  = dbr ? ~dbwe : cpu_rd;
assign ram_hwr = dbr ?  dbwe : cpu_hwr;
assign ram_lwr = dbr ?  dbwe : cpu_lwr;

//--------------------------------------------------------------------------------------

// ram address multiplexer (512KB bank)		
assign ram_address_out = dbr ? dma_address_in[18:1] : cpu_address_in[18:1];

//--------------------------------------------------------------------------------------

//chipram, kickstart and bootrom address decode
always @(dbr or dma_address_in or cpu_address_in or cpu_rd or boot or ovl or t_sel_slow or ecs or memory_config)
begin
	if (dbr)//agnus only accesses chipram
	begin
		sel_chip[0] = ~dma_address_in[20] & ~dma_address_in[19];
		sel_chip[1] = ~dma_address_in[20] &  dma_address_in[19];
		sel_chip[2] =  dma_address_in[20] & ~dma_address_in[19];
		sel_chip[3] =  dma_address_in[20] &  dma_address_in[19];
		sel_slow[0] = ( ecs && memory_config==4'b0100 && dma_address_in[20:19]==2'b01) ? 1'b1 : 1'b0;
		sel_slow[1] = 1'b0;
		sel_slow[2] = 1'b0;
		sel_kick    = 1'b0;
	end
	else
	begin
		sel_chip[0] = cpu_address_in[23:19]==5'b0000_0 && ((boot && cpu_address_in[18:14]!=5'b000_00) || (!boot && !ovl)) ? 1'b1 : 1'b0;
		sel_chip[1] = cpu_address_in[23:19]==5'b0000_1 ? 1'b1 : 1'b0;
		sel_chip[2] = cpu_address_in[23:19]==5'b0001_0 ? 1'b1 : 1'b0;
		sel_chip[3] = cpu_address_in[23:19]==5'b0001_1 ? 1'b1 : 1'b0;
		sel_slow[0] = t_sel_slow[0];
		sel_slow[1] = t_sel_slow[1];
		sel_slow[2] = t_sel_slow[2];
		sel_kick    = (cpu_address_in[23:19]==5'b1111_1 && (cpu_rd || boot)) || (!boot && cpu_rd && ovl && cpu_address_in[23:19]==5'b0000_0) ? 1'b1 : 1'b0; //$F80000 - $FFFFF
	end
end

assign t_sel_slow[0] = cpu_address_in[23:19]==5'b1100_0 ? 1'b1 : 1'b0; //$C00000 - $C7FFFF
assign t_sel_slow[1] = cpu_address_in[23:19]==5'b1100_1 ? 1'b1 : 1'b0; //$C80000 - $CFFFFF
assign t_sel_slow[2] = cpu_address_in[23:19]==5'b1101_0 ? 1'b1 : 1'b0; //$D00000 - $D7FFFF

// 512kb extra rom area at $e0 and $f0 write able only at a1k chipset mode
//assign t_sel_slow[2] = (cpu_address_in[23:19]==5'b1110_0 || cpu_address_in[23:19]==5'b1111_0) && (a1k | cpu_rd) ? 1'b1 : 1'b0; //$E00000 - $E7FFFF & $F00000 - $F7FFFF

assign sel_xram = ((t_sel_slow[0] & (memory_config[2] | memory_config[3]))
        | (t_sel_slow[1] & memory_config[3])
        | (t_sel_slow[2] & memory_config[2] & memory_config[3]));

assign sel_rtc = (cpu_address_in[23:16]==8'b1101_1100) ? 1'b1 : 1'b0;   //RTC registers at $DC0000 - $DCFFFF

assign sel_ide = hdc_ena && cpu_address_in[23:16]==8'b1101_1010 ? 1'b1 : 1'b0;		//IDE registers at $DA0000 - $DAFFFF	

assign sel_gayle = hdc_ena && cpu_address_in[23:12]==12'b1101_1110_0001 ? 1'b1 : 1'b0;		//GAYLE registers at $DE1000 - $DE1FFF

assign sel_reg = cpu_address_in[23:21]==3'b110 ? ~(sel_xram | sel_rtc | sel_ide | sel_gayle) : 1'b0;		//chip registers at $DF0000 - $DFFFFF

assign sel_cia = cpu_address_in[23:21]==3'b101 ? 1'b1 : 1'b0;

//cia a address decode
assign sel_cia_a = sel_cia & ~cpu_address_in[12];

//cia b address decode
assign sel_cia_b = sel_cia & ~cpu_address_in[13];

assign sel_boot = cpu_address_in[23:12]==0 && boot ? 1'b1 : 1'b0;

assign sel_bank_1 = cpu_address_in[23:21]==3'b001 ? 1'b1 : 1'b0;

//data bus slow down

assign dbs = cpu_address_in[23:21]==3'b000 || cpu_address_in[23:20]==4'b1100 || cpu_address_in[23:19]==5'b1101_0 || cpu_address_in[23:16]==8'b1101_1111 ? 1'b1 : 1'b0;

assign xbs = ~(sel_cia | sel_gayle | sel_ide);

endmodule
