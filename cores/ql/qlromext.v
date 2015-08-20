// Logic for the QLROMEXT board of the QL-SD interface
// Copyright (C) 2011 Adrian Ives and Peter Graf
// 
// This hardware description is free; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
// 
// This hardware description is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.


// Version: 0.082
// Target: CPLD LC4064V


// Control Register addresses
// The position and ordering of IF_ENABLE and IF_DISABLE are
// important because of Minerva's extended memory test (which, for
// some unfathomable reason checks the ROM cartridge space for RAM!)
// This order ensures that the interface remains disabled during the
// check; preventing anything from being placed on the data bus or
// any spurious signals from being sent to the SD Card

`define IF_ENABLE       16'hFEE0  // 65248
`define IF_DISABLE      16'hFEE1  // 65249
`define IF_RESET        16'hFEE2  // 65250

`define SPI_READ        16'hFEE4  // 65252

`define SPI_XFER_FAST   16'hFEE6  // 65254
`define SPI_XFER_SLOW   16'hFEE8  // 65256
`define SPI_XFER_OFF    16'hFEEA  // 65258

`define SPI_DESELECT    16'hFEF0  // 65264
`define SPI_SELECT1     16'hFEF1  // 65265
`define SPI_SELECT2     16'hFEF2  // 65266
`define SPI_SELECT3     16'hFEF3  // 65267

`define SPI_CLR_MOSI    16'hFEF4  // 65368
`define SPI_SET_MOSI    16'hFEF5  // 65369
`define SPI_CLR_SCLK    16'hFEF6  // 65370
`define SPI_SET_SCLK    16'hFEF7  // 65371

// SPI background transfer shift register write page
// If the interface is enabled and background
// transfers are switched on then any write to
// this page will load the shift register from
// the bottom eight bits of the Address Bus and
// transfer the byte over SPI in the background

`define SPI_XFER        8'hFF     // $FF00,65280

// SPI Background Transfer Finite State Machine codes
`define STATE_0         3'b000     // Inactive
`define STATE_1         3'b001     // Prologue
`define STATE_2         3'b010     // Dividing
`define STATE_3         3'b011     // Shifting
`define STATE_4         3'b100     // Shifted
`define STATE_5         3'b101     // Epilogue

// Clock divider for slow speed background transfers
`define SLOW_CLK_DIVIDER	64	// This should give an approximate SPI clock of 25MHZ/64 = 390.625KHZ

module qlromext(clk, clk_bus, romoel, d, a, gl, sd_cs1l, sd_cs2l, sd_clk, sd_do, sd_di, io1, io2, io3, io4);

input [15:0] a;
input clk, clk_bus, romoel, sd_do, io2;
output [7:0] d;
output gl, sd_cs1l, sd_cs2l, sd_clk, sd_di, io1, io3, io4;

wire [15:0] a /* synthesis syn_keep=1 */ ;
wire [7:0] d;
reg gl;
wire clk /* synthesis syn_keep=1 */ ;
wire romoel /* synthesis syn_keep=1 */ ;
wire sd_do /* synthesis syn_keep=1 */ ;
wire io2 /* synthesis syn_keep=1 */ ;

// It's a bit of a waste of time setting initial values of registers
// to anything other than 0 because the synthesis tool doesn't appear
// to translate them into logic. By default, all CPLD registers are
// set to 0 at power up.

reg interface_enabled = 0;	// Determines whether the interface is enabled

// SPI Slave Selects
reg ss1 = 1;
reg ss2 = 1;
reg ss3 = 1;

// Foreground SPI bits
reg fg_mosi = 1;
reg fg_sclk = 1;

// Background SPI bits
reg bg_mosi = 1;
reg bg_sclk = 1;

// SPI background transfer control
reg spi_bg_enabled = 0;         // If true, background transfers are enabled
reg [2:0] spi_state = `STATE_0; // Background transfer current state
reg spi_xfer_running = 0;       // If true, an SPI background transfer is in progress
reg spi_fast = 0;               // If true, the maximum SPI clock rate (25MHZ) is used for
                                // background SPI transfers
reg [7:0] spi_shiftreg = 0;     // SPI Shift Register
reg [3:0] spi_counter = 0;      // 4 bit counter used to control SPI bit shifting
reg [6:0] spi_divider = 0;      // 7 bit counter used to divide the clock for slow SPI background transfers

// Connect the SPI signals
assign sd_di = (spi_xfer_running) ? bg_mosi : fg_mosi;
assign sd_clk = (spi_xfer_running) ? bg_sclk : fg_sclk;
assign io1 = (spi_xfer_running) ? bg_mosi : fg_mosi;
assign io3 = (spi_xfer_running) ? bg_sclk : fg_sclk;
assign sd_cs1l = (interface_enabled) ? ss1 : 1;
assign sd_cs2l = (interface_enabled) ? ss2 : 1;
assign io4 = (interface_enabled) ? ss3 : 1;
wire miso = (ss3) ? sd_do : io2 /* synthesis syn_keep=1 */ ;

// --------------------------------------
// Control the Data Bus
// --------------------------------------
wire [7:0] data_out = (spi_bg_enabled) ? spi_shiftreg : { 7'b0000000, miso };
assign d = (interface_enabled && ( a == `SPI_READ ))?data_out:8'h00;

// --------------------------------------
// Process changes on the Address Bus
// --------------------------------------
always @(negedge clk_bus) begin
	if(!romoel) begin
      case (a)

      `IF_ENABLE :
        begin
          // Enable the interface
          interface_enabled <= 1;
        end

      `IF_DISABLE :
        begin
          // Disable the interface
          interface_enabled <= 0;
        end

      `IF_RESET :
        begin
          // Reset the interface
          fg_mosi <= 1;
          fg_sclk <= 1;
          ss1 <= 1;
          ss2 <= 1;
          ss3 <= 1;
          spi_fast <= 0;
          spi_bg_enabled <= 0;
        end

      `SPI_XFER_FAST :
        begin
          // Enable SPI background transfers at full speed
          // SPI_READ now gets the SPI Shift Register
          spi_fast <= 1;
          spi_bg_enabled <= 1;
        end

      `SPI_XFER_SLOW :
        begin
          // Enable SPI background transfers at low speed
          // SPI_READ now gets the SPI Shift Register
          spi_fast <= 0;
          spi_bg_enabled <= 1;
        end

      `SPI_XFER_OFF :
        begin
          // Disable SPI background transfers
          // SPI_READ now gets foreground MISO
          spi_bg_enabled <= 0;
        end

      `SPI_DESELECT :
        begin
          // Clear all slave selects
          ss1 <= 1;
          ss2 <= 1;
          ss3 <= 1;
        end

      `SPI_SELECT1 :
        begin
          // Select SPI Slave #1
          ss1 <= 0;
          ss2 <= 1;
          ss3 <= 1;
        end

      `SPI_SELECT2 :
        begin
          // Select SPI Slave #2
          ss1 <= 1;
          ss2 <= 0;
          ss3 <= 1;
        end

      `SPI_SELECT3 :
        begin
          // Select SPI Slave #3
          ss1 <= 1;
          ss2 <= 1;
          ss3 <= 0;
        end

      `SPI_SET_MOSI :
        begin
          // Bit-banged SPI; Set MOSI=1
          fg_mosi <= 1;
        end

      `SPI_CLR_MOSI :
        begin
          // Bit-banged SPI; Set MOSI=0
          fg_mosi <= 0;
        end

      `SPI_SET_SCLK :
        begin
          // Bit-banged SPI; Set SCLK=1
          fg_sclk <= 1;
        end

      `SPI_CLR_SCLK :
        begin
          // Bit-banged SPI; Set SCLK=0
          fg_sclk <= 0;
        end
      endcase
	end
end

// --------------------------------------
// Handle SPI background transfers
// Finite State Machine using spi_state
// --------------------------------------

reg xfer_start;
always @(negedge clk_bus)
	xfer_start <= interface_enabled && spi_bg_enabled && !romoel && (a[15:8] == `SPI_XFER);

always @(posedge clk)
begin
  case (spi_state)
  `STATE_0:
    // Inactive
    // Stay in this state while:
    //   The interface is disabled
    //   Background transfers are disabled
    //   An access to the SPI_XFER address page is not detected
    begin
      spi_state <= xfer_start ? `STATE_1 : `STATE_0 ;
    end

  `STATE_1:
    // Prologue
    // Initialise registers for the transfer
    begin
      spi_shiftreg <= a[7:0];	// Load the SPI shift register from the bottom 8 bits of the Address Bus
      bg_mosi <= 1;
      bg_sclk <= 1;		// Set background I/O lines to high
      spi_counter <= 0;		// Reset shift counter
      spi_divider <= `SLOW_CLK_DIVIDER;	// Reset clock divider
      spi_xfer_running <= 1;	// Signal that a background transfer is running
				// This selects the background SPI output lines
      spi_state <= (spi_fast) ? `STATE_3 : `STATE_2;	// Select the next state according to the transfer speed
    end

  `STATE_2:
    // Dividing
    // Enter this state before transitioning SCLK when the transfer speed is set to slow
    begin
      spi_divider <= spi_divider - 1;
      spi_state <= (spi_divider == 0) ? `STATE_3 : `STATE_2 ;	// Remain in this state until the clock divider count is satisfied
    end

  `STATE_3:
    // Shifting
    // Transition SCLK and shift the next bit across the SPI bus
    begin
      bg_sclk <= !bg_sclk;
      spi_counter <= spi_counter + 1;
      if (bg_sclk)
        // SPI clock went low to high; output the next bit
        bg_mosi <= spi_shiftreg[7];
      else
        // SPI clock went high to low; input the next bit
        spi_shiftreg <= { spi_shiftreg[6:0], miso };
      spi_divider <= `SLOW_CLK_DIVIDER;	// Always reset the clock divider ahead of next SCLK transition
      if (spi_counter == 15)
        spi_state <= `STATE_4;		// If the byte has been shifted move to next state
      else
        spi_state <= (spi_fast) ? `STATE_3 : `STATE_2 ;	// Else next state depends upon transfer speed
    end

  `STATE_4:
    // Shifted
    // Shift has completed; reset registers
    begin
      spi_xfer_running <= 0;	// Signal transfer ended
      bg_mosi <= 1;		// Reset MOSI
      spi_state <= `STATE_5;	// Next state is Epilogue
    end

  `STATE_5:
    // Epilogue
    // Wait for the access to the SPI_XFER address page to end
    begin
      spi_state <= (!romoel && (a[15:8] == `SPI_XFER)) ? `STATE_5 : `STATE_0 ;
    end
  endcase
end

endmodule
