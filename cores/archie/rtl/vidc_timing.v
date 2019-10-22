`timescale 1ns / 1ps
/* vidc_timing.v

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
 
module vidc_timing(

		input 			clkcpu, 	// cpu clock
		input 			wr, 		// write to video register.
		input [31:0]	cpu_dat,	// data to write (data bus).
		
		input 			clkvid,
		input			cevid,
		input			rst,

		output        o_vsync,
		output        o_hsync, 

		output        o_cursor,
		output        o_enabled,
		output        o_border,
		output        o_flyback
    );

reg [9:0] hcount;
reg [9:0] vcount;

// register locations
localparam  VIDEO_HCR 	= 6'b100000; 
localparam  VIDEO_HSWR 	= 6'b100001; 
localparam  VIDEO_HBSR 	= 6'b100010; 
localparam  VIDEO_HDSR 	= 6'b100011; 
localparam  VIDEO_HDER 	= 6'b100100; 
localparam  VIDEO_HBER 	= 6'b100101; 

localparam  VIDEO_VCR 	= 6'b101000; 
localparam  VIDEO_VSWR 	= 6'b101001; 
localparam  VIDEO_VBSR 	= 6'b101010; 
localparam  VIDEO_VDSR 	= 6'b101011; 
localparam  VIDEO_VDER 	= 6'b101100; 
localparam  VIDEO_VBER 	= 6'b101101; 

localparam  VIDEO_VCSR 	= 6'b101110; 
localparam  VIDEO_VCER 	= 6'b101111; 
localparam  VIDEO_HCSR 	= 6'b100110; 

// vertical registers 
reg [9:0]		vidc_vcr;  // vertical cycle register
reg [9:0]		vidc_vswr; // vertical sync width
reg [9:0]		vidc_vbsr; // vertical border start
reg [9:0]		vidc_vdsr; // vertical display start
reg [9:0]		vidc_vder; // vertical display end
reg [9:0]		vidc_vber; // vertical border end

// horizontal registers 
reg [9:0]		vidc_hcr;  //  horizontal cycle register
reg [9:0]		vidc_hswr; // horizontal sync width
reg [9:0]		vidc_hbsr; // horizontal border start
reg [9:0]		vidc_hdsr; // horizontal display start
reg [9:0]		vidc_hder; // horizontal display end
reg [9:0]		vidc_hber; // horizontal border end

// cursor registers 
reg [10:0]		vidc_hcsr; // horizontal cursor start
reg [9:0]		vidc_vcsr; // vertical cursor start
reg [9:0]		vidc_vcer; // vertical cursor end

initial begin 

	vidc_vcr		= 10'd0; // vertical cycle register
	vidc_vswr	= 10'd0; // vertical sync width
	vidc_vbsr	= 10'd0; // vertical border start
	vidc_vdsr	= 10'd0; // vertical display start
	vidc_vder	= 10'd0; // vertical display end
	vidc_vber	= 10'd0; // vertical border end

	vidc_hcr    = 10'd0; // horizontal cycle register
	vidc_hswr	= 10'd0; // horizontal sync width
	vidc_hbsr	= 10'd0; // horizontal border start
	vidc_hdsr	= 10'd0; // horizontal display start
	vidc_hder	= 10'd0; // horizontal display end
	vidc_hber	= 10'd0; // horizontal border end
	
	vidc_hcsr	= 11'd0; // horizontal cursor start
	vidc_vcsr	= 10'd0;  // vertical cursor start
	vidc_vcer	= 10'd0;  // vertical cursor end

end 

always @(posedge clkcpu) begin

	if (wr) begin 
	
			$display("Writing the timing registers: 0x%08x", cpu_dat);
		
			case (cpu_dat[31:26])  
				
				// verical timing
				VIDEO_VCR: 		vidc_vcr  <= cpu_dat[23:14];
				VIDEO_VSWR: 	vidc_vswr <= cpu_dat[23:14];
				VIDEO_VBSR: 	vidc_vbsr <= cpu_dat[23:14];
				VIDEO_VBER: 	vidc_vber <= cpu_dat[23:14];
				VIDEO_VDSR: 	vidc_vdsr <= cpu_dat[23:14];
				VIDEO_VDER: 	vidc_vder <= cpu_dat[23:14];
				
				// horizontal timing
				VIDEO_HCR: 		vidc_hcr  <= {cpu_dat[22:14], 1'b0};
				VIDEO_HSWR: 	vidc_hswr <= {cpu_dat[22:14], 1'b0};
				VIDEO_HBSR: 	vidc_hbsr <= {cpu_dat[22:14], 1'b0};
				VIDEO_HBER: 	vidc_hber <= {cpu_dat[22:14], 1'b0};
				VIDEO_HDSR: 	vidc_hdsr <= {cpu_dat[22:14], 1'b0};
				VIDEO_HDER: 	vidc_hder <= {cpu_dat[22:14], 1'b0};
				
				VIDEO_HCSR: 	vidc_hcsr <= cpu_dat[23:13];
					
				VIDEO_VCSR: 	vidc_vcsr <= cpu_dat[23:14];
				VIDEO_VCER: 	vidc_vcer <= cpu_dat[23:14];
				
				default:		vidc_vcr <= vidc_vcr;
			endcase
			
	end

end

reg vborder;
reg hborder;
reg vdisplay;
reg hdisplay;
reg vflyback;
reg vcursor;
reg hcursor;
reg hsync;
reg vsync;

assign o_cursor = hcursor & vcursor;
assign o_flyback = vflyback;
assign o_enabled = hdisplay & vdisplay;
assign o_border = hborder & vborder;
assign o_vsync = ~vsync;
assign o_hsync = ~hsync;

always @(posedge clkvid) begin

	if (rst) begin
		hcount <= 0;
		vcount <= 0;
		hborder <= 0;
		vborder <= 0;
		hsync <= 0;
		vsync <= 0;
		vflyback <= 0;
		hdisplay <= 0;
		vdisplay <= 0;
		hcursor <= 0;
		vcursor <= 0;
	end else
	if (cevid) begin
		// video frame control

		hcount <= hcount + 1'd1;
		if (hcount == vidc_hbsr) hborder <= 1;
		if (hcount == vidc_hber) hborder <= 0;
		if (hcount == vidc_hdsr) hdisplay <= 1;
		if (hcount == vidc_hder) hdisplay <= 0;
		if ({1'b0, hcount} == vidc_hcsr) hcursor <= 1;
		if (hcount == vidc_hswr) hsync <= 0;

		if (hcount == vidc_hcr) begin
			hcount <= 0;
			hcursor <= 0;
			hsync <= 1;

			vcount <= vcount + 1'd1;
			if (vcount == vidc_vbsr) vborder <= 1;
			if (vcount == vidc_vber) vborder <= 0;
			if (vcount == vidc_vdsr) vdisplay <= 1;
			if (vcount == vidc_vder) begin
				vdisplay <= 0;
				vflyback <= 1;
			end
			if (vcount == vidc_vcsr) vcursor <= 1;
			if (vcount == vidc_vcer) vcursor <= 0;
			if (vcount == vidc_vswr) begin
				vsync <= 0;
				vflyback <= 0;
			end

			if (vcount == vidc_vcr) begin
				vcount <= 0;
				vflyback <= 1; // turn vflayback on even if vder is crazy-programmed
				vsync <= 1;
			end
		end

	end
end

endmodule
