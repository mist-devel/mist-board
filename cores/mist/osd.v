//
// osd.v
// 
// On Screen Display implementation for the MiST board
// http://code.google.com/p/mist-board/
// 
// Copyright (c) 2013 Till Harbaum <till@harbaum.org> 
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
  input clk,     // 31.875 MHz

  // SPI interface for OSD
  input         sck,
  input         ss,
  input         sdi,

  output reg 	osd_enable,

  // current video beam position
  input [9:0]   hcnt,
  input [9:0]   vcnt,
  
  input [5:0]   in_r, // Red[5:0]
  input [5:0]   in_g, // Green[5:0]
  input [5:0]   in_b, // Blue[5:0]

  output [5:0]  out_r, // Red[5:0]
  output [5:0]  out_g, // Green[5:0]
  output [5:0]  out_b  // Blue[5:0]
);

assign out_r = !oe?in_r:{osd_pixel, osd_pixel, osd_pixel, in_r[5:3]};
assign out_g = !oe?in_g:{osd_pixel, osd_pixel,      1'b1, in_g[5:3]};
assign out_b = !oe?in_b:{osd_pixel, osd_pixel, osd_pixel, in_b[5:3]};

// ---------------------------------------------------------------------------
// -------------------------------- spi client -------------------------------
// ---------------------------------------------------------------------------

// this core supports only the display related OSD commands
// of the minimig

reg [7:0]       sbuf;
reg [7:0]       cmd;
reg [4:0]       cnt;
reg [10:0]      bcnt;

reg [7:0] osd_buffer [2047:0];  // the OSD buffer itself

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
        osd_enable <= sdi;
    end

    // command 0x20: OSDCMDWRITE
    if((cmd[7:3] == 5'b00100) && (cnt == 15)) begin
      osd_buffer[bcnt] <= {sbuf[6:0], sdi};
      bcnt <= bcnt + 11'd1;
    end
  end
end

localparam OSD_WIDTH  = 10'd256;
localparam OSD_HEIGHT = 10'd128;   // pixels are doubled vertically

localparam OSD_POS_X  = (10'd640 - OSD_WIDTH)>>1;
localparam OSD_POS_Y  = (10'd400 - OSD_HEIGHT)>>1;

localparam OSD_BORDER  = 10'd2;

wire oe    = osd_enable && (
  (hcnt >=  OSD_POS_X-OSD_BORDER) &&
  (hcnt <  (OSD_POS_X + OSD_WIDTH + OSD_BORDER)) &&
  (vcnt >=  OSD_POS_Y - OSD_BORDER) &&
  (vcnt <  (OSD_POS_Y + OSD_HEIGHT + OSD_BORDER)));

wire osd_content_area =
  (hcnt >=  OSD_POS_X) &&
  (hcnt <  (OSD_POS_X + OSD_WIDTH)) &&
  (vcnt >=  OSD_POS_Y) &&
  (vcnt <  (OSD_POS_Y + OSD_HEIGHT));

wire [7:0] osd_hcnt = hcnt - OSD_POS_X + 7'd1;  // one pixel offset for osd_byte register
wire [6:0] osd_vcnt = vcnt - OSD_POS_Y;

wire osd_pixel = osd_content_area?osd_byte[osd_vcnt[3:1]]:1'b0;

reg [7:0] osd_byte; 
always @(posedge clk)
  osd_byte <= osd_buffer[{osd_vcnt[6:4], osd_hcnt}];
  
endmodule
