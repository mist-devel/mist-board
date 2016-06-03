//
// floppy.v
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

module floppy (
	// main clock
	input 	     clk,
	input 	     select,
	input 	     motor_on,
	input 	     step_in,
	input 	     step_out,

	output 	     dclk,         // data clock 
	output [6:0] track,        // number of track under head
	output [3:0] sector,       // number of sector under head, 0 = no sector
	output 	     sector_hdr,   // valid sector header under head
	output 	     sector_data,  // valid sector data under head
	       
	output 	     ready,        // drive is ready, data can be read
	output reg   index
);

// The sysclock is the value all floppy timings are derived from. 
// Default: 8 MHz
localparam SYS_CLK = 8000000;  

assign sector_hdr = (sec_state == SECTOR_STATE_HDR);
assign sector_data = (sec_state == SECTOR_STATE_DATA);
   
// a standard DD floppy has a data rate of 250kBit/s and rotates at 300RPM
localparam RATE = 250000;
localparam RPM = 300;
localparam STEPBUSY = 18;          // 18ms after step data can be read
localparam SPINUP = 500;           // drive spins up in up to 800ms
localparam SPINDOWN = 300;         // GUESSED: drive spins down in 300ms
localparam INDEX_PULSE_LEN = 5;    // fd1036 data sheet says 1~8ms
localparam SECTOR_HDR_LEN = 6;     // GUESSED: Sector header is 6 bytes
localparam TRACKS = 85;            // max allowed track

// Archimedes specific values
localparam SECTOR_LEN = 1024;      // Default sector size is 1k on Archie ...
localparam SPT = 5;                // ... with 5 sectors per track
localparam SECTOR_BASE = 0;        // number of first sector on track (archie 0, dos 1)
   
// number of physical bytes per track
localparam BPT = RATE*60/(8*RPM);

// report disk ready if it spins at full speed and head is not moving
assign ready = select && (rate == RATE) && (step_busy == 0);
   
// ================================================================
// ========================= INDEX PULSE ==========================
// ================================================================
   
// Index pulse generation. Pulse starts with the begin of index_pulse_start
// and lasts INDEX_PULSE_CYCLES system clock cycles
localparam INDEX_PULSE_CYCLES = INDEX_PULSE_LEN * SYS_CLK / 1000;
reg [15:0] index_pulse_cnt;   
always @(posedge clk) begin
   if(index_pulse_start && (index_pulse_cnt == INDEX_PULSE_CYCLES-1)) begin
      index <= 1'b0;
      index_pulse_cnt <= 16'd0;
   end else if(index_pulse_cnt == INDEX_PULSE_CYCLES-1)
     index <= 1'b1;
   else
     index_pulse_cnt <= index_pulse_cnt + 16'd1;
end
   
// ================================================================
// ======================= track handling =========================
// ================================================================

localparam STEP_BUSY_CLKS = (SYS_CLK/1000)*STEPBUSY;  // steprate is in ms

assign track = current_track;
reg [6:0] current_track = 7'd0;

reg step_inD;
reg step_outD;
reg [17:0] step_busy;
   
always @(posedge clk) begin
   step_inD <= step_in;
   step_outD <= step_out;

   if(step_busy != 0)
     step_busy <= step_busy - 18'd1;

   if(select) begin
      // rising edge of step signal starts step
      if(step_in && !step_inD) begin
	 if(current_track != 0) current_track <= current_track - 7'd1;
	 step_busy <= STEP_BUSY_CLKS;
      end

      if(step_out && !step_outD) begin
	 if(current_track != TRACKS-1) current_track <= current_track + 7'd1;
	 step_busy <= STEP_BUSY_CLKS;
      end
   end
end
   
// ================================================================
// ====================== sector handling =========================
// ================================================================

// track has BPT bytes
// SPT sectors are stored on the track
localparam SECTOR_GAP_LEN = BPT/SPT - (SECTOR_LEN + SECTOR_HDR_LEN);

assign sector = current_sector;
   
localparam SECTOR_STATE_GAP  = 2'd0;
localparam SECTOR_STATE_HDR  = 2'd1;
localparam SECTOR_STATE_DATA = 2'd2;

// we simulate an interleave of 1
reg [3:0] start_sector = SECTOR_BASE;
   
reg [1:0] sec_state;
reg [9:0] sec_byte_cnt;  // counting bytes within sectors
reg [3:0] current_sector = SECTOR_BASE;
  
always @(posedge byte_clk) begin
   if(index_pulse_start) begin
      sec_byte_cnt <= SECTOR_GAP_LEN-1;
      sec_state <= SECTOR_STATE_GAP;     // track starts with gap
      current_sector <= start_sector;    // track starts with sector 1
   end else begin
      if(sec_byte_cnt == 0) begin
	 case(sec_state)
	   SECTOR_STATE_GAP: begin
	      sec_state <= SECTOR_STATE_HDR;
	      sec_byte_cnt <= SECTOR_HDR_LEN-1;
	   end
	   
	   SECTOR_STATE_HDR: begin
	      sec_state <= SECTOR_STATE_DATA;
	      sec_byte_cnt <= SECTOR_LEN-1;
	   end
	   
	   SECTOR_STATE_DATA: begin
	      sec_state <= SECTOR_STATE_GAP;
	      sec_byte_cnt <= SECTOR_GAP_LEN-1;
	      if(current_sector == SECTOR_BASE+SPT-1) 
		current_sector <= SECTOR_BASE;
	      else
 	        current_sector <= sector + 4'd1;
	   end

	   default:
	     sec_state <= SECTOR_STATE_GAP;
	      
	 endcase
      end else
	sec_byte_cnt <= sec_byte_cnt - 10'd1;
   end
end
   
// ================================================================
// ========================= BYTE CLOCK ===========================
// ================================================================

// An ed floppy at 300rpm with 1MBit/s has max 31.250 bytes/track
// thus we need to support up to 31250 events
reg [14:0] byte_cnt;
reg 	   index_pulse_start;   
always @(posedge byte_clk) begin
   index_pulse_start <= 1'b0;

   if(byte_cnt == BPT-1) begin
      byte_cnt <= 0;
      index_pulse_start <= 1'b1;      
   end else
     byte_cnt <= byte_cnt + 1;
end

// Make byte clock from bit clock.
// When a DD disk spins at 300RPM every 32us a byte passes the disk head
assign dclk = byte_clk;
wire byte_clk = clk_cnt2[2];
reg [2:0] clk_cnt2;
always @(posedge data_clk)
  clk_cnt2 <= clk_cnt2 + 1;

// ================================================================
// ===================== SPIN VIRTUAL DISK ========================
// ================================================================

// number of system clock cycles after which disk has reached
// full speed
localparam SPIN_UP_CLKS = SYS_CLK/1000*SPINUP;
localparam SPIN_DOWN_CLKS = SYS_CLK/1000*SPINDOWN;
reg [31:0] spin_up_counter;
   
// internal motor on signal that is only true if the drive is selected
wire motor_on_sel = motor_on && select;
   
// data rate determines rotation speed
reg [31:0] rate = 0;
reg motor_onD;

always @(posedge clk) begin
   motor_onD <= motor_on_sel;

   // reset spin_up counter whenever motor state changes
   if(motor_onD != motor_on_sel)
     spin_up_counter <= 32'd0;
   else begin
      spin_up_counter <= spin_up_counter + RATE;
      
      if(motor_on_sel) begin
	 // spinning up
	 if(spin_up_counter > SPIN_UP_CLKS) begin
	    if(rate < RATE)
	      rate <= rate + 32'd1;
	    spin_up_counter <= spin_up_counter - (SPIN_UP_CLKS - RATE);
	 end
      end else begin
	 // spinning down
	 if(spin_up_counter > SPIN_DOWN_CLKS) begin
	    if(rate > 0)
	      rate <= rate - 32'd1;
	    spin_up_counter <= spin_up_counter - (SPIN_DOWN_CLKS - RATE);
	 end
      end // else: !if(motor_on)
   end // else: !if(motor_onD != motor_on)
end
   
// Generate a data clock from the system clock. This depends on motor
// speed and reaches the full rate when the disk rotates at 300RPM. No
// valid data can be read until the disk has reached it's full speed.
reg data_clk;
reg [31:0] clk_cnt;
always @(posedge clk) begin
   if(clk_cnt + rate > SYS_CLK/2) begin
      clk_cnt <= clk_cnt - (SYS_CLK/2 - rate);
      data_clk <= !data_clk;
   end else
     clk_cnt <= clk_cnt + rate;
end   
   
endmodule
