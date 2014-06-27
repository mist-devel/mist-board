//
// zx01_mist.v
//
// zx01/zx81 toplevel for the MiST board
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
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

module zx01_mist ( 
  // clock inputsxque
  input wire [ 2-1:0]   CLOCK_27, // 27 MHz
  // LED outputs
  output wire           LED, // LED Yellow
  // UART
  output wire           UART_TX, // UART Transmitter (MIDI out)
  input wire            UART_RX, // UART Receiver (MIDI in)
  // VGA
  output wire           VGA_HS, // VGA H_SYNC
  output wire           VGA_VS, // VGA V_SYNC
  output wire [ 6-1:0]  VGA_R, // VGA Red[5:0]
  output wire [ 6-1:0]  VGA_G, // VGA Green[5:0]
  output wire [ 6-1:0]  VGA_B, // VGA Blue[5:0]
  // SDRAM
  inout wire [ 16-1:0]  SDRAM_DQ, // SDRAM Data bus 16 Bits
  output wire [ 13-1:0] SDRAM_A, // SDRAM Address bus 13 Bits
  output wire           SDRAM_DQML, // SDRAM Low-byte Data Mask
  output wire           SDRAM_DQMH, // SDRAM High-byte Data Mask
  output wire           SDRAM_nWE, // SDRAM Write Enable
  output wire           SDRAM_nCAS, // SDRAM Column Address Strobe
  output wire           SDRAM_nRAS, // SDRAM Row Address Strobe
  output wire           SDRAM_nCS, // SDRAM Chip Select
  output wire [ 2-1:0]  SDRAM_BA, // SDRAM Bank Address
  output wire           SDRAM_CLK, // SDRAM Clock
  output wire           SDRAM_CKE, // SDRAM Clock Enable
  // MINIMIG specific
  output wire           AUDIO_L, // sigma-delta DAC output left
  output wire           AUDIO_R, // sigma-delta DAC output right
  // SPI
  inout wire            SPI_DO,
  input wire            SPI_DI,
  input wire            SPI_SCK,
  input wire            SPI_SS2,    // fpga
  input wire            SPI_SS3,    // OSD
  input wire            SPI_SS4,    // "sniff" mode
  input wire            CONF_DATA0  // SPI_SS for user_io
);

assign SDRAM_nCS = 1'b1;   // disable ram

// reset geenration
reg [7:0] reset_cnt;
always @(posedge clk) begin
	if(!pll_locked || status[0])
		reset_cnt <= 8'h0;
	else if(reset_cnt != 8'd255)
		reset_cnt <= reset_cnt + 8'd1;
end 

wire reset = (reset_cnt != 8'd255);

// pll to generate appropriate clock
wire clk13;
wire pll_locked;
clock clock (
  .areset       (1'b0             ), // async reset input
  .inclk0       (CLOCK_27[0]      ), // input clock (27MHz)
  .c0           (clk13            ), // output clock c0 (13MHz)
  .locked       (pll_locked       )  // pll locked output
);

// The 13Mhz is required for the scan doubler. The zx01 itself
// runs at 6.5 MHz which is generated from the 13MHz
reg clk;
always @(posedge clk13)
	clk <= !clk;

// ------------- interface to arm controller -----------------

wire [1:0] buttons /* synthesis keep */;
wire [1:0] switches /* synthesis keep */;

// devide 6.5MHz clock by 2^9 giving ~12.7kHz
reg [8:0] clk_div;
wire clk_12k = clk_div[8];
always @(posedge clk) 
	clk_div <= clk_div + 9'd1;

wire ps2_clk;
wire ps2_data;

wire [7:0] status;

user_io user_io(
	// the spi interface
   .SPI_CLK     	(SPI_SCK			),
   .SPI_SS_IO   	(CONF_DATA0		),
   .SPI_MISO    	(SPI_DO			),   // tristate handling inside user_io
   .SPI_MOSI    	(SPI_DI			),

   .SWITCHES 		(switches		),
   .BUTTONS 		(buttons			),

	// two joysticks supports
	.JOY0				(              ),
	.JOY1				(              ),

	// status byte (bit 0 = io controller reset)
	.status			( status       ),

	// ps2 keyboard interface
	.clk				(clk_12k			),   // should be 10-16kHz for ps2 clock
	.ps2_data      (ps2_data		),
	.ps2_clk       (ps2_clk  		)
);

// ----------------------- Quick'n dirty scan doubler ---------------------------
// This reveals a problem of the zx01: The video timing isn't perfect,
// the hsync jumps in line 1 and in line 32 relative to the end of
// the vsync (top level line_cnt[]). 
// This is causing the "shifted" line 32 at the top of the screen on
// a Dell 1908FP. It's unknown how other screens react on this.
// HSync comes 8 pixels late in line 1 and another 8 pixels late in 
// line 32

// - ZX81 video basics
// The ZX81 video runs at 6.5Mhz Pixel clock, but most of the video
// state machine incl. the CPU runs at phi = 3.25MHz
// The total display width is 207 phi clocks. At 3.25 Mhz this is 15.7kHz
// Display starts at phi = 40 and ends at phi = 168 giving a total of 256
// pixels horizontally

// route cores vga output through OSD, extra parameters can be given to
// fine tune the OSD position in x and y direction. The third parameter
// adjusts the OSD color (0=dark grey, 1=blue, 2=green, 3=cyan, 4=red,
// 5=purple, 6=yellow, 7=light grey)
osd #(15,0,5) osd (
	.pclk			( clk13			),

	// spi for OSD
   .sdi        ( SPI_DI       ),
   .sck        ( SPI_SCK      ),
   .ss         ( SPI_SS3      ),
	
	.red_in		( video6			),
	.green_in	( video6			),
	.blue_in		( video6			),
	.hs_in		( ~hs				),
	.vs_in		( ~vs				),
	
	.red_out		( VGA_R			),
	.green_out	( VGA_G			),
	.blue_out	( VGA_B			),
	.hs_out		( VGA_HS			),
	.vs_out		( VGA_VS			)
);	

wire [5:0] video6 = { vb, vb, vb, vb, vb, vb};

// "video bit" forced black outside horizontal display enable (h_de)
// and vsync (vs). Also the "transistor inverter" present in the zx01 
// is implemented here
wire vb = v_de && h_de && ~sd_video;

// video and csync output from the zx01
wire video;
wire csync;

// column counter running at 13MHz, twice the zx81 pixel clock
reg [8:0] sd_col;

// column counter running at 13MHz, but counting through a whole zx81 line
reg [9:0] zx_col;

// counter to determine sync lengths in the composity sync signal
// used to differentiate between hsync and vsync
reg [7:0] sync_len;
reg vs, csD;

// horizontal display goes from 40 to 168. We add 16 border pixels left and right
wire h_de = (sd_col >= 2*32) && (sd_col < 2*182);   // 176

// vertical display goes from line 32 to 224.We add 16 border pixels top and bottom
wire v_de = (line_cnt >= 16) && (line_cnt < 272);    // 240  

wire hs = sd_col >= 2*192;

// debug signal indicating that the scandoubler adjusted its hsync phase. This
// signal should only occur once at stargup. The fact that it also triggers in
// line 1 and line 32
reg trigger /* synthesis noprune */;
// line counter also for debug purposes
reg [9:0] line_cnt /* synthesis noprune */;

// enough space for two complete lines (incl. border and sync),
// each being 414 physical pixels wide
reg line_buffer[1023:0];

// toggle bit to switch between both line buffers
reg sd_toggle;

// video output of scan doubler
reg sd_video;

// scan doublers hsync/vsync generator runs on 6.5MHz
always @(posedge clk13) begin
	trigger <= 1'b0;

	csD <= csync;

	if(csync) begin
		sync_len <= 8'd0;
		vs <= 1'b0;
	end else begin
		// count sync pulse length. Stop counting at 255
		if(sync_len < 255)
			sync_len <= sync_len + 8'd1;

		// if counter passes 80 then we are seeing a vsync
		if(sync_len == 80) begin
			vs <= 1'b1;
			line_cnt <= 10'd0;
		end
	end

	// reset scan doubler column counter on rising edge of csync (end of sync) or
	// every 414 pixels
	if((sd_col == 413) ||(csync && !csD && sync_len < 80)) begin
		// trigger whenever we adjust hsync position. This should happen only once, otherwise
		// there are short/long lines
		if(sd_col != 413)
			trigger <= 1'b1;
	 
		sd_col <= 9'd0;
	end else
		sd_col <= sd_col + 9'd1;
		
   // change toggle bit at the end of each zx line
	if(csync && !csD) begin
		sd_toggle <= !sd_toggle;
		line_cnt <= line_cnt + 10'd1;
	end
			
	// zx81 column counter
	if((csync && !csD && sync_len < 80)) begin
		zx_col <= 10'd0;
	end else 
		zx_col <= zx_col + 10'd1;

	// fetch one line at half the scan doubler frequency
	if(zx_col[0])
		line_buffer[{sd_toggle, zx_col[9:1]}] = video;
		
	// output other line at full scan doubler frequency
	sd_video <= line_buffer[{!sd_toggle, sd_col}];
end
	
wire tape_data;
	
zx01 zx01 (
	.n_reset    (~reset     	),
	.clock		(clk       		),
   .kbd_clk		(ps2_clk      	),
	.kbd_data	(ps2_data		),
	.v_inv    	(switches[1]	),
	.usa_uk		(1'b0				),
	.video    	(video			),
	.tape_in		(tape_data		),
	.tape_out	(csync      	),

	// ignore LCD interface
	.d_lcd		(           	),
	.s				(           	),
	.cp1			(           	),
	.cp2      	(					)
);

// create 500kHz from 13 Mhz
reg [4:0] clk_cnt;
wire clk_500k = clk_cnt < 13;
always @(posedge clk13) begin
	clk_cnt <= clk_cnt + 5'd1;
	if(clk_cnt == 5'd25)
		clk_cnt <= 5'd0;
end

// tape transfers distort video, so we need a different kind
// of feedback
// we thus route type_data to led and to audio
assign LED = !tape_data;

// use a pwm to reduce audio output volume
reg [7:0] aclk;
always @(posedge clk13) 
	aclk <= aclk + 8'd1;

// limit volume to 1/8 => pwm < 32 
wire tape_audio = tape_data && (aclk < 32);
assign AUDIO_L = tape_audio;
assign AUDIO_R = tape_audio;
	
tape tape (
	// spi interface to io controller
   .sdi        ( SPI_DI       ),
   .sck        ( SPI_SCK      ),
   .ss         ( SPI_SS2      ),

	.clk        ( clk_500k     ),
	.play       ( buttons[1]   ),
   .tape_out   ( tape_data    )
);

endmodule
