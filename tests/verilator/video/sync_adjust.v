//
// sync_adjust.v
//
// Ajust the video sync position to allow the user to center the
// video on screen
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

module sync_adjust (
  // system interface
  input 	   clk, // 31.875 MHz

  input [15:0] 	   adjust,
	       
  input 	   hs_in,
  input 	   vs_in,

  output reg 	   hs_out,
  output reg 	   vs_out
);

// This has to cope with 15kHz (64us). At 32MHz a counter will count
// from 0 to 2047 in that time. Thus a 11 bit counter is required
   
// Extract and sign extend adjust values
wire signed [10:0] adjust_x = { {3{ adjust[15] }}, adjust[15:8] };
wire signed [9:0]  adjust_y = { {2{ adjust[7]  }}, adjust[7:0]  };
   
// ==================================================================
// ====================== input timing analysis =====================
// ==================================================================

// total hsync time (in 32MHz cycles), hs_total reaches 2048
reg [10:0] hcnt;
reg hsD, vsD;

// hsync rise at hcnt == 0, signals relative to this:
reg [10:0] hs_rise;   
reg [10:0] hs_fall;   
reg [10:0] v_event;   

// an event ecactly half a line delayed to v_event to generate
// vcntD which is stable over any change in v_event timinig
wire [10:0] hs_max_2 = { 1'b0, hs_max[10:1] };   
wire [10:0] v_event_2 = (v_event > hs_max_2)?v_event-hs_max_2:v_event+hs_max_2;
    
reg [9:0] vcnt;
reg [9:0] vcntD;    // delayed by half a line
reg [9:0] vs_rise;   
reg [9:0] vs_fall;   

// since the counter is restarted at the falling edge, hs_fall contains
// the max counter value (total times - 1)    
wire [10:0] hs_max = hs_fall;   
wire [9:0] vs_max = vs_fall;   

always @(negedge clk) begin
   hsD <= hs_in;
   vsD <= vs_in;

   // hsync has changed
   hcnt <= hcnt + 11'd1;
   if(hsD != hs_in) begin
      if(!hs_in) begin
	 hcnt <= 11'd0;
	 hs_fall <= hcnt;
      end else
	hs_rise <= hcnt;
   end

   if(hcnt == v_event)
     vcnt <= vcnt + 10'd1;
   
   // vsync has changed
   if(vsD != vs_in) begin
      if(!vs_in) begin
	 v_event <= hcnt;
	 vcnt <= 10'd0;
	 vs_fall <= vcnt;
      end else
	vs_rise <= vcnt;
   end

   if(hcnt == v_event_2)
     vcntD <= vcnt;   
end
   
// ==================================================================
// ==================== output timing generation ====================
// ==================================================================

wire [10:0] hcnt_out_rst = (adjust_x < 0)?(10'd0-adjust_x-10'd1):(hs_max-adjust_x);
reg [10:0] hcnt_out;

wire [9:0] vcnt_out_rst = (adjust_y < 0)?(9'd0-adjust_y-9'd1):(vs_max-adjust_y);
reg [9:0] vcnt_out;

always @(posedge clk) begin
   // generate new hcnt with offset
   if(hcnt == hcnt_out_rst)
     hcnt_out <= 11'd0;
   else
     hcnt_out <= hcnt_out + 11'd1;

   // generate delayed hsync
   if(hcnt_out == hs_rise) hs_out <= 1'b1;
   if(hcnt_out == hs_fall) hs_out <= 1'b0;
 
   // generate delayed vsync timing
   if(hcnt_out == v_event) begin

      if(vcntD == vcnt_out_rst)
	vcnt_out <= 10'd0;
      else
	vcnt_out <= vcnt_out + 10'd1;
      
      // generate delayed vsync
      if(vcnt_out == vs_rise) vs_out <= 1'b1;
      if(vcnt_out == vs_fall) vs_out <= 1'b0;
   end
end
   
endmodule
