`timescale 1ns / 1ps
/* vidc_audio.v

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
 
module vidc_audio
(

 // cpu side - used to write registers
 input             cpu_clk, // cpu clock
 input             cpu_wr, // write to video register.
 input [31:0]      cpu_data, // data to write (data bus).

 // audio/data side of the bus
 input             aud_clk,
 input             aud_ce,
 input             aud_rst,
 input [7:0]       aud_data,
 output reg        aud_en,
 
 // actual audio out signal
 output reg [15:0] aud_right,
 output reg [15:0] aud_left
 );     
 
localparam  SOUND_SAMFREQ       = 4'b1100;
localparam  SOUND_REGISTERS     = 5'b01100;   

wire		aud_1mhz_en;
reg  [4:0]	aud_1mhz_count;

reg [2:0] channel;
   
reg [2:0]   vidc_sir[0:7];
reg [8:0]   vidc_sfr;
wire [2:0]  vidc_mixer = vidc_sir[channel];
   
reg [15:0] mulaw_table[0:255];

// 1mhz pulse counter.
reg [7:0] aud_delay_count;
   
initial begin
   
   // load the u-law table
   $readmemh("vidc_mulaw.mif", mulaw_table);   
   
   
  channel = 3'd0;
        
  aud_delay_count   = 8'b11111111;
  aud_1mhz_count 	= 5'd0;
   
end

  
always @(posedge cpu_clk) begin
   
   if (cpu_wr) begin 
      
      if ({cpu_data[31:29],cpu_data[25:24]} == SOUND_REGISTERS) begin

         $display("Writing the stereo image registers: 0x%08x", cpu_data);
         vidc_sir[{cpu_data[28:26]}] <= cpu_data[2:0];

      end

      if (cpu_data[31:28] == SOUND_SAMFREQ) begin
         
         $display("VIDC SFR: %x", cpu_data[7:0]);
         if (cpu_data[8]) begin
            vidc_sfr <= cpu_data[8:0];
         end
      end
         
   end
   
end

reg [7:0] aud_data_l, aud_data_r;
always @(posedge aud_clk) begin
	aud_left  <= mulaw_table[aud_data_l];
	aud_right <= mulaw_table[aud_data_r];
end

always @(posedge aud_clk) begin

	if(aud_ce) begin
		aud_en <= 1'b0;
		aud_1mhz_count <= aud_1mhz_count + 1'd1;
		if (aud_rst) begin

			channel <= 3'd0;

			aud_delay_count   <= 8'b11111111;
			aud_1mhz_count 	<= 5'd0;

		end else if (aud_1mhz_en) begin

			aud_1mhz_count 	<= 5'd0;
			aud_delay_count <= aud_delay_count - 1'd1;

			if (aud_delay_count == 8'd0) begin

				channel <= channel + 1'd1;

				if ((vidc_mixer[2] == 1'b0) | (channel[1:0] == 2'b00)) aud_data_l <= aud_data;
				if (vidc_mixer[2] == 1'b1)                             aud_data_r <= aud_data;

				aud_en <= 1'b1;
				aud_delay_count <= vidc_sfr[7:0];

			end
		end
	end
end

// this is the trigger for the 1mhz enable pulse.
assign aud_1mhz_en = &aud_1mhz_count[3:2]; // 24 now we're using the 24mhz clock.

endmodule
