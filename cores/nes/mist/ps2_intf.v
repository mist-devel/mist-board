// ZX Spectrum for Altera DE1
//
// Copyright (c) 2009-2011 Mike Stirling
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//
// * Redistributions in synthesized form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of other contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written agreement from the author.
//
// * License is granted for non-commercial use only.  A fee may not be charged
//   for redistributions as source code or in synthesized/hardware form without 
//   specific prior written agreement from the author.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

// PS/2 interface (input only)
// Based loosely on ps2_ctrl.vhd (c) ALSE. http://www.alse-fr.com

// This is input-only for the time being
module ps2_intf #(parameter filter_length=8)(
   input            CLK,
   input            nRESET,
   
   // PS/2 interface (could be bi-dir)
   input            PS2_CLK,
   input            PS2_DATA,
   
   // Byte-wide data interface - only valid for one clock
   // so must be latched externally if required
   output reg [7:0] DATA,
   output reg       VALID,
   output reg       ERROR
);
   
   reg [filter_length-1:0] clk_filter;
   
   reg       ps2_clk_in;
   reg       ps2_dat_in;
   // Goes high when a clock falling edge is detected
   reg       clk_edge;
   reg [3:0] bit_count;
   reg [8:0] shiftreg;
   reg       parity;
   // Register input signals
   
   always @(negedge nRESET or posedge CLK)
      if (!nRESET) begin
         ps2_clk_in <= 1'b1;
         ps2_dat_in <= 1'b1;
         clk_filter <= 8'b11111111;
         clk_edge   <= 1'b0;
      end else begin
         // Register inputs (and filter clock)
         ps2_dat_in <= PS2_DATA;
         clk_filter <= {PS2_CLK, clk_filter[filter_length-1:1]};
         clk_edge <= 1'b0;
         
         if (clk_filter)
            // Filtered clock is high
            ps2_clk_in <= 1'b1;
         else begin
            // Filter clock is low, check for edge
            if (ps2_clk_in) clk_edge <= 1'b1;
            ps2_clk_in <= 1'b0;
         end
      end

   // Shift in keyboard data
   always @(negedge nRESET or posedge CLK) begin
      if (!nRESET) begin
         bit_count <= 4'd0;
         shiftreg  <= 9'd0;
         parity    <= 1'b0;
         DATA      <= 8'd0;
         VALID     <= 1'b0;
         ERROR     <= 1'b0;
      end else  begin
         // Clear flags
         VALID     <= 1'b0;
         ERROR     <= 1'b0;

         if (clk_edge) begin
            // We have a new bit from the keyboard for processing
            if (bit_count == 4'd0) begin
               // Idle state, check for start bit (0) only and don't
               // start counting bits until we get it
               parity <= 1'b0;
               if (!ps2_dat_in) bit_count <= bit_count + 4'd1; // This is a start bit
            end else begin
               // Running.  8-bit data comes in LSb first followed by
               // a single stop bit (1)
               if (bit_count < 4'd10) begin
                  // Shift in data and parity (9 bits)
                  bit_count <= bit_count + 4'd1;
                  shiftreg <= {ps2_dat_in, shiftreg[8:1]};
                  parity <= parity ^ ps2_dat_in;		// Calculate parity
               end else if (ps2_dat_in) begin
                  // Valid stop bit received
                  bit_count <= 4'd0;		// back to idle
                  if (parity) begin
                     // Parity correct, submit data to host
                     DATA <= shiftreg[7:0];
                     VALID <= 1'b1;
                  end else begin
                     // Error
                     ERROR <= 1'b1;
						end
               end 
               else begin
                  // Invalid stop bit
                  bit_count <= 4'd0;		// back to idle
                  ERROR <= 1'b1;
               end
				end
         end
      end
	end
   
endmodule
