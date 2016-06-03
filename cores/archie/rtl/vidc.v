`timescale 1ns / 1ps
/* vidc.v

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
module vidc(
	
	    input 	 		clkcpu, // cpu bus clock domain
	    input 	 		clkpix2x, // pixel clock domain
        output			clkpix,
		
		// "wishbone" interface
	    input 	 	 	rst_i,
        input			vidw, 	// write to a register.		
	    input [31:0] 	cpu_dat,
	
	    // dma control.
	    input [31:0]	viddat, 
	    input 	 		vidak,
	    output 		 	vidrq,
		
        input 	 		sndak,
	    output 		 	sndrq,
        
	    output 	 		flybk,
	    
	    // video outputs
	    output 	 		hsync,
	    output 	 		vsync,
	
	    output [3:0] 	video_r,
	    output [3:0] 	video_g,
	    output [3:0] 	video_b,
		 
		output [15:0] 	audio_l,
	    output [15:0] 	audio_r
);

wire			cur_enabled;
reg			    cur_enabled_r;
wire			enabled;
wire			border;

// registers 
reg [12:0] 		vidc_palette[0:15];	// palette register.
reg [15:0]		vidc_cr; 				// control register.
reg [12:0]		vidc_border; 			// border register.
reg [12:0]		cur_palette[1:3]; 	// border register.

// audio clock domain signals
wire [7:0] 		snd_sam_data;
wire			snd_sam_en;

// pixel clock domain signals
//delayed enable.
reg				enabled_d1;
reg				enabled_d2;

reg 				pix_load;
wire 				pix_ack;
wire [7:0] 		pix_data;
reg  [2:0] 		pix_shift_count;
reg  [7:0] 		pix_data_latch = 8'd0;

// cursor pixel clock signals
reg 				csr_load;
wire 				csr_ack;
reg [3:0] 		csr_load_count;
wire [7:0] 		csr_data;
reg  [2:0] 		csr_shift_count;
reg  [7:0] 		csr_data_latch = 8'd0;

// dmacon
wire		cur_load;
wire		vid_load;
wire		snd_load;

// internal data request lines
wire		currq_int;
wire		vidrq_int;

// produce the correct pixel clock by dividing. 
vidc_divider CLOCKS(
	.clkpix2x	( clkpix2x		),
	.clk_select	( vidc_cr[1:0]	),
	.clkpix		( clkpix			)
);

vidc_timing TIMING(
	
	.clkcpu		( clkcpu		),
	.wr			( vidw		),
	.cpu_dat 	( cpu_dat	),

	.clkpix		( clkpix		),
	.rst			( rst_i		),
	
	.o_hsync		( hsync		),
	.o_vsync		( vsync		),
	.o_flyback	( flybk		),
	.o_enabled	( enabled	),
	.o_cursor	( cur_enabled	),
	.o_border	( border		)
);

// this module does the math for a DMA channel
vidc_dmachannel VIDEODMA (

	.rst		( flybk | rst_i	),
	.clkcpu		( clkcpu		),
	.clkdev		( clkpix		),
	
	.cpu_data	( viddat		),
	.ak			( vidak			),
	.rq			( vidrq_int		),
	
	.busy		( vid_load		),
	.stall		( ~hsync		),
	
	.dev_data	( pix_data		),
	.dev_ak		( pix_ack		)

);

// this module does the math for a DMA channel
vidc_dmachannel #(.FIFO_SIZE(2)) CURSORDMA (

	.rst		( flybk | rst_i	),
	.clkcpu		( clkcpu		),
	.clkdev		( clkpix		),
	
	.cpu_data	( viddat		),
	
	.ak			( vidak 		),
	.rq			( currq_int		),
	
	.busy		( cur_load		),
	.stall		( hsync | vid_load	),

	.dev_data	( csr_data		),
	.dev_ak		( csr_ack		)

);

// this module does the math for a DMA channel
vidc_dmachannel SOUNDDMA (

	.rst		( rst_i			),
	.clkcpu		( clkcpu		),
	.clkdev		( clkpix		),
	
	.cpu_data	( viddat		),
	.ak			( sndak			),
	.rq			( sndrq			),
	
	.busy		( snd_load		),
	.stall		( 1'b0			), 
	
	.dev_data	( snd_sam_data	),
	.dev_ak		( snd_sam_en	)

);

vidc_audio AUDIOMIXER(

    .cpu_clk    ( clkcpu    ),
    .cpu_wr     ( vidw      ),
    .cpu_data   ( cpu_dat   ),
    
    .aud_clk    ( clkpix    ),
    .aud_rst    ( rst_i     ),
    .aud_data   ( snd_sam_data ),
    .aud_en     ( snd_sam_en ),

    .aud_right  ( audio_r   ),
    .aud_left   ( audio_l   )
    
 );

integer c;

initial begin 

	// clear the palette. 
	for (c = 0; c < 16; c = c + 1) begin
	
		vidc_palette[c] = 13'd0;
 	
	end

	vidc_cr				= 16'hFFF0;
	
	pix_shift_count		= 3'd0;
	pix_data_latch		= 8'd0;
	pix_load			= 1'b0;
	
	csr_shift_count		= 3'd0;
	csr_data_latch		= 8'd0;
	csr_load_count		= 'd0;
	csr_load		   	= 1'b0;
	
end

localparam 	VIDEO_PALETTE 	= 6'b00xxxx;
localparam  VIDEO_CONTROL 	= 6'b111000; 
localparam  VIDEO_BORDER 	= 6'b010000; 
localparam  CURSOR_PALETTE = 6'b0100xx; 

// DMA interface control
// this is in the cpu clock domain. 
always @(posedge clkcpu) begin

	// register write control.
	if (vidw == 1'b1) begin 
	
		casex (cpu_dat[31:26])  
					
			VIDEO_PALETTE: begin // palette registers. 00-3CH
				
				vidc_palette[cpu_dat[29:26]] <= cpu_dat[12:0];
				
			end

			CURSOR_PALETTE: begin // cursor palette
				if (cpu_dat[27:26] == 2'b00) begin
					vidc_border <= cpu_dat[12:0];
				end else begin 
					cur_palette[cpu_dat[27:26]] <= cpu_dat[12:0];
				end
			end
			
			VIDEO_CONTROL: begin // control register.
				
				vidc_cr	<= cpu_dat[15:0];
				
			end

		endcase
	
	end

end 

// pixel clock domain logic. 
// this simulates the DAC.
always @(posedge clkpix) begin

	cur_enabled_r <= cur_enabled;
	pix_load 		<= pix_ack;
	csr_load			<= csr_ack;
	
	enabled_d1		<= enabled;
	enabled_d2		<= enabled_d1;
	
	if (flybk == 1'b1) begin 
	
		pix_data_latch <= 8'd0;
		
	end
	
	if (hsync == 1'b0) begin
	
		pix_shift_count <= 3'b111;
		csr_shift_count <= 3'b111;
		csr_load_count <= 'd0;
		
	end else if (enabled == 1'b1) begin

		case ({vidc_cr[3:2]})
			2'b00: begin 
				pix_data_latch <= {1'b0, pix_data_latch[7:1]};
				pix_shift_count <= pix_shift_count + 3'd1;
			end
			
			2'b01: begin 
				pix_data_latch <= {2'b00, pix_data_latch[7:2]};
				pix_shift_count <= pix_shift_count + 3'd2;
			end
			
			2'b10: begin
				pix_data_latch <= {4'b00, pix_data_latch[7:4]};
				pix_shift_count <= pix_shift_count + 3'd4;
			end
			
			default: begin
				pix_data_latch <= 8'd0;						 
			end
		endcase
		
	end
	
	if (cur_enabled_r) begin 
			
			csr_data_latch <= {2'b00, csr_data_latch[7:2]};
			csr_shift_count <= csr_shift_count + 3'd2;
		
	end

	if (pix_load == 1'b1) begin
		
		pix_data_latch <= pix_data;
			
	end
	
	if (csr_load) begin 
		
		csr_load_count <= csr_load_count + 'd1;
		csr_data_latch <= csr_data;
	
	end

end

// eqn is CE + DE + ABC + BCD (where {E,D} = {vidc_cr[3:2]} and {C,B,A} = pix_shift_count)
assign  pix_ack = enabled & ((pix_shift_count[2] & vidc_cr[3]) | ( vidc_cr[2] & vidc_cr[3]) | (pix_shift_count[0] & pix_shift_count[1] & pix_shift_count[2]) | (pix_shift_count[1] & pix_shift_count[2] &  vidc_cr[2]));
assign	csr_ack = cur_enabled & (csr_shift_count[2] & csr_shift_count[0] ) & ~csr_load & ~csr_load_count[3];

// TODO: fix 8 bits per pixel colours.
wire [3:0] pix_lookup = vidc_cr[3:2] == 2'b00 ? {3'd0, pix_data_latch[0]} :
								vidc_cr[3:2] == 2'b01 ? {2'd0, pix_data_latch[1:0]} : pix_data_latch[3:0];

wire [1:0] csr_lookup = csr_data_latch[1:0];
								
								
wire [12:0] vidc_colour = cur_enabled & (csr_lookup != 2'd0) ? cur_palette[csr_lookup]   :
								  enabled_d2 ? vidc_palette[pix_lookup] : 
								  border  ? vidc_border : 
									13'd0;

// render a hicolour pixel if in hicolour mode, enabled and the cursor isnt being displayed.
wire     hicolour = (vidc_cr[3:2] == 2'b11) & enabled_d2 & !(cur_enabled & (csr_lookup != 2'd0));
								
assign 	video_r[3]	= hicolour ? pix_data_latch[4] : vidc_colour[3];
assign	video_r[2:0] 	= vidc_colour[2:0];

assign 	video_g[3:2]	= hicolour ? pix_data_latch[6:5] : vidc_colour[7:6];
assign	video_g[1:0] 	= vidc_colour[5:4];

assign 	video_b[3]	= hicolour ? pix_data_latch[7] : vidc_colour[11];
assign	video_b[2:0]	= vidc_colour[10:8];

// this demux's the two dma channels that share the vidrq. 
assign vidrq = hsync ? vidrq_int : ~vid_load & currq_int;

endmodule
