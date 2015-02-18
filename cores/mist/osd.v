//
// osd.v
// 
// On Screen Display implementation for the MiST board
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
//

module osd (
  input        clk, // 31.875 MHz

  // SPI interface for OSD
  input        sck,
  input        ss,
  input        sdi,

  input        hs,
  input        vs,
  
  input [5:0]  r_in,  // Red[5:0]
  input [5:0]  g_in,  // Green[5:0]
  input [5:0]  b_in,  // Blue[5:0]

  output [5:0] r_out, // Red[5:0]
  output [5:0] g_out, // Green[5:0]
  output [5:0] b_out  // Blue[5:0]
);

// combine input and OSD into a overlayed signal
assign r_out = !oe?r_in:{pixel, pixel, pixel, r_in[5:3]};
assign g_out = !oe?g_in:{pixel, pixel,  1'b1, g_in[5:3]};
assign b_out = !oe?b_in:{pixel, pixel, pixel, b_in[5:3]};

reg enabled;

// ---------------------------------------------------------------------------
// ------------------------- video timing analysis ---------------------------
// ---------------------------------------------------------------------------

// System clock is 32Mhz. Slowest hsync is 15Khz/64us. Hcounter must thus be
// able to run to 2048
reg [10:0] 	hcnt;
reg [10:0] 	vcnt;

reg [10:0] 	hs_high;
reg [10:0] 	hs_low;
wire 		hs_pol = hs_high < hs_low;
wire [10:0] 	dsp_width = hs_pol?hs_low:hs_high;
   
reg [10:0] 	vs_high;
reg [10:0] 	vs_low;
wire 		vs_pol = vs_high < vs_low;
wire [10:0] 	dsp_height = vs_pol?vs_low:vs_high;
   
reg hsD, vsD;
always @(negedge clk) begin
   // check if hsync has changed
   hsD <= hs;
   if(hsD != hs) begin
      if(hs)  hs_low  <= hcnt;
      else    hs_high <= hcnt;
      hcnt <= 11'd0;

      if(hs == hs_pol) begin
	 // check if vsync has changed
	 vsD <= vs;
	 if(vsD != vs) begin
	    if(vs)  vs_low  <= vcnt;
	    else    vs_high <= vcnt;
	    vcnt <= 11'd0;
	 end else
	   vcnt <= vcnt + 11'd1;
      end
   end else
     hcnt <= hcnt + 11'd1;
end
   
// ---------------------------------------------------------------------------
// -------------------------------- spi client -------------------------------
// ---------------------------------------------------------------------------

// this core supports only the display related OSD commands
// of the minimig

reg [7:0]       sbuf;
reg [7:0]       cmd;
reg [4:0]       cnt;
reg [10:0]      bcnt;

reg [7:0] buffer [2047:0];  // the OSD buffer itself

// the OSD has its own SPI interface to the io controller
always@(posedge sck, posedge ss) begin
  if(ss == 1'b1) begin
      cnt <= 5'd0;
      bcnt <= 11'd0;
  end else begin
    sbuf <= { sbuf[6:0], sdi};

    // 0:7 is command, rest payload
    if(cnt < 15)
      cnt <= cnt + 4'd1;
    else
      cnt <= 4'd8;

      if(cnt == 7) begin
       cmd <= {sbuf[6:0], sdi};
      
      // lower three command bits are line address
      bcnt <= { sbuf[1:0], sdi, 8'h00};

      // command 0x40: OSDCMDENABLE, OSDCMDDISABLE
      if(sbuf[6:3] == 4'b0100)
        enabled <= sdi;
    end

    // command 0x20: OSDCMDWRITE
    if((cmd[7:3] == 5'b00100) && (cnt == 15)) begin
      buffer[bcnt] <= {sbuf[6:0], sdi};
      bcnt <= bcnt + 11'd1;
    end
  end
end

// ---------------------------------------------------------------------------
// ------------------------------- OSD position ------------------------------
// ---------------------------------------------------------------------------

wire expand_x = ((dsp_width > 1000)&&(dsp_height < 1000))?1:0;
wire expand_y = (dsp_height > 400)?1:0;
   
wire [10:0] width  = expand_x?10'd512:10'd256;
wire [10:0] height = expand_y?10'd128:10'd64;

wire [10:0] border_x = expand_x?10'd4:10'd4;
wire [10:0] border_y = expand_y?10'd4:10'd2;

wire [10:0] pos_x = (dsp_width - width)>>1;
wire [10:0] pos_y = (dsp_height - height)>>1;

wire oe = enabled && (
  (hcnt >= pos_x - border_x) &&
  (hcnt < (pos_x + width + border_x)) &&
  (vcnt >= pos_y - border_y) &&
  (vcnt < (pos_y + height + border_y)));

wire content_area =
  (hcnt >= pos_x) && (hcnt < (pos_x + width - 1)) &&
  (vcnt >= pos_y) && (vcnt < (pos_y + height - 1));

// one pixel offset for delay by byte register
wire [7:0] ihcnt = (expand_x?((hcnt-pos_x)>>1):(hcnt-pos_x))+8'd1;
wire [6:0] ivcnt =  expand_y?((vcnt-pos_y)>>1):(vcnt-pos_y);

wire pixel = content_area?buffer_byte[ivcnt[2:0]]:1'b0;

reg [7:0] buffer_byte; 
always @(posedge clk)
  buffer_byte <= buffer[{ivcnt[5:3], ihcnt}];
  
endmodule
