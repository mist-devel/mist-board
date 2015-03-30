//
// audio.v
// 
// Atari audio subsystem implementation for the MiST board
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

module audio (
	// system interface
	input  	reset,
	input 	clk_32,      // 32 MHz
	input 	clk_8,       
	input [1:0] bus_cycle,   // bus-cycle for sync
	

	// cpu interface
	input [15:0] din,
	input [15:0] addr,
	output [15:0] dout,
	input uds,
	input lds,
	input rw,
	input psg_sel,
	input ste_dma_snd_sel,

	// ste dma interface
	input					hsync,     // to synchronize with video
	output            dma_read,
	output [22:0]     dma_addr,
	input [63:0]      dma_data,
	
	input psg_stereo,
	
	// psg has gpios
	output floppy_side,
	output [1:0] floppy_sel,
	// extra joystick map to parallel port
	input [5:0] joy0,
	input [5:0] joy1,
	
	output [7:0] parallel_data_out,
	input parallel_strobe_out,
	output parallel_data_out_available,
	
	output 				xsint,
	output 				xsint_d,
	
	output audio_r,
	output audio_l
);
	
// 2Mhz clock for PSG and STE DMA audio delay buffer
reg [1:0] sclk;
always @ (posedge clk_8)
	sclk <= sclk + 2'd1;

wire clk_2 = sclk[1];
	
wire [7:0] port_a_out;
wire [7:0] port_b_out;
assign floppy_side = port_a_out[0];
assign floppy_sel = port_a_out[2:1];

wire [7:0] ym_audio_out_l, ym_audio_out_r;

// extra joysticks are wired to the printer port
// using the "gauntlet2 interface", fire of 
// joystick 0 is connected to the mfp I0 (busy)
wire [7:0] port_b_in = { ~joy0[0], ~joy0[1], ~joy0[2], ~joy0[3], 
								 ~joy1[0], ~joy1[1], ~joy1[2], ~joy1[3]}; 
wire [7:0] port_a_in = { 2'b11, ~joy1[4], 5'b11111 }; 

assign dout = psg_sel?{psg_dout,8'h00}:ste_dma_snd_sel?ste_dma_snd_data_out:16'h0000;
wire [15:0] ste_dma_snd_data_out;
wire [7:0] psg_dout;

YM2149 ym2149 (
	.I_DA						( din[15:8]					),
	.O_DA						( psg_dout				   ),
	.O_DA_OE_L           (								),

	// control
	.I_A9_L              ( 1'b0						),
	.I_A8                ( 1'b1						),
	.I_BDIR              ( psg_sel && !rw	      ),
	.I_BC2               ( 1'b1						),
	.I_BC1              	( psg_sel && !addr[1]   ),
	.I_SEL_L             ( 1'b1						),

	.O_AUDIO_L           (ym_audio_out_l			),
	.O_AUDIO_R           (ym_audio_out_r			),

	.stereo 					(psg_stereo	      		),
	
	// port a
	.I_IOA           		( port_a_in 				),
	.O_IOA              	( port_a_out				),
	.O_IOA_OE_L      		(								),

	// port b
	.I_IOB               ( port_b_in					),
	.O_IOB              	( port_b_out				),
	.O_IOB_OE_L         	(								),
  
	//
	.ENA                	( 1'b1						), 
	.RESET_L            	( !reset 					),
	.CLK                	( clk_2  					),	// 2 MHz
	.CLK8              	( clk_8  					)	// 8 MHz CPU bus clock
);

wire parallel_fifo_full;

// ------ fifo to store printer data coming from psg ---------
io_fifo #(.DEPTH(4)) parallel_out_fifo (
	.reset 				(reset),		

	.in_clk  			(clk_8),
	.in 					(port_b_out),
	.in_strobe 			(port_a_out[5]),
	.in_enable		 	(1'b0),

	.out_clk  			(clk_8),
	.out 					(parallel_data_out),
	.out_strobe 		(parallel_strobe_out),
	.out_enable		 	(1'b0),

	.full					(parallel_fifo_full),
	.data_available 	(parallel_data_out_available)
);

wire [7:0] ste_audio_out_r;
wire [7:0] ste_audio_out_l;

ste_dma_snd ste_dma_snd (
	// cpu interface
	.clk      	(clk_8             ),
	.reset    	(reset             ),
	.din      	(din               ),
	.sel      	(ste_dma_snd_sel   ),
	.addr     	(addr[5:1]         ),
	.uds      	(uds          ),
	.lds      	(lds          ),
	.rw       	(rw           ),
	.dout     	(ste_dma_snd_data_out),

	// memory interface
	.clk32	  	(clk_32            ),
	.bus_cycle 	(bus_cycle         ),
	.hsync		(hsync             ),
	.saddr      (dma_addr  ),
	.read       (dma_read  ),
	.data       (dma_data  ),

	.audio_l    (ste_audio_out_l   ),
	.audio_r    (ste_audio_out_r	 ),

	.xsint     	( xsint ),
	.xsint_d   	( xsint_d )   // 4 usec delayed
);

// audio output processing

// simple mixer for ste and ym audio. result is 9 bits
// this will later be handled by the lmc1992
wire [8:0] audio_mix_l = { 1'b0, ym_audio_out_l} + { 1'b0, ste_audio_out_l };
wire [8:0] audio_mix_r = { 1'b0, ym_audio_out_r} + { 1'b0, ste_audio_out_r };

// limit audio to 8 bit range
wire [7:0] audio_out_l = audio_mix_l[8]?8'd255:audio_mix_l[7:0];
wire [7:0] audio_out_r = audio_mix_r[8]?8'd255:audio_mix_r[7:0];

sigma_delta_dac sigma_delta_dac_l (
	.DACout 		(audio_l),
	.DACin		(audio_out_l),
	.CLK 			(clk_32),
	.RESET 		(reset)
);

sigma_delta_dac sigma_delta_dac_r (
	.DACout     (audio_r),
	.DACin    	(audio_out_r),
	.CLK      	(clk_32),
	.RESET    	(reset)
);

endmodule
