//
// ste_dma_snd.v
// 
// Atari STE dma sound implementation for the MiST board
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
 
module ste_dma_snd (
	// system interface
	input             clk,
	input             reset,
  
	// cpu register interface
	input [15:0]      din,
	input             sel,
	input [4:0]       addr,
	input             uds,
	input             lds,
	input             rw,
	output reg [15:0] dout,

	// memory interface
	input 				clk32,     // 31.875 MHz
	input [1:0] 		bus_cycle, // bus-cycle
	input					hsync,     // to synchronize with video
	output            read,
	output [22:0]     saddr,
	input [63:0]      data,
	
	// audio	
	output reg [7:0]  audio_l,
	output reg [7:0]  audio_r,
	
	output            xsint,
	output 				xsint_d
);
// ---------------------------------------------------------------------------
// --------------------------- internal state counter ------------------------
// ---------------------------------------------------------------------------

reg [1:0] t /* synthesis noprune */ ;
always @(posedge clk32) begin
	// 32Mhz counter synchronous to 8 Mhz clock
	// force counter to pass state 0 exactly after the rising edge of clk (8Mhz)
	if(((t == 2'd3)  && ( clk == 0)) ||
		((t == 2'd0) && ( clk == 1)) ||
		((t != 2'd3) && (t != 2'd0)))
			t <= t + 2'd1;
end

// create internal bus_cycle signal which is stable on the positive clock
// edge and extends the previous state by half a 32 Mhz clock cycle
reg [3:0] bus_cycle_L;
always @(negedge clk32)
	bus_cycle_L <= { bus_cycle, t };

assign saddr = snd_adr;   // drive data
assign read = (bus_cycle == 0) && hsync && !fifo_full && dma_enable;

// ---------------------------------------------------------------------------
// ------------------------------ clock generation ---------------------------
// ---------------------------------------------------------------------------

// dma sound internally works on a 2MHz clock
reg [1:0] sclk;
always @(posedge clk)
	sclk <= sclk + 2'd1;

wire clk_2 = sclk[1];  // 2Mhz

// generate audio sample rate base == 50kHz == 2Mhz/40
reg abase;
reg [4:0] acnt;

always @(posedge clk_2) begin
	if(acnt == 5'd19) begin	
		acnt <= 5'd0;
		abase <= ~abase;
	end else
		acnt <= acnt + 5'd1;
end	

// generate current audio clock
reg [2:0] aclk_cnt;
always @(posedge abase)
	aclk_cnt <= aclk_cnt + 3'd1;

wire aclk =  (mode[1:0] == 2'b11)?abase:        // 50 kHz
				((mode[1:0] == 2'b10)?aclk_cnt[0]:  // 25 kHz
				((mode[1:0] == 2'b01)?aclk_cnt[1]:  // 12.5 kHz
					aclk_cnt[2]));                   // 6.25 kHz

// ---------------------------------------------------------------------------
// ------------------------------- irq generation ----------------------------
// ---------------------------------------------------------------------------

// 74ls164
reg [7:0] xsint_delay;
always @(posedge clk_2 or negedge xsint) begin
	if(!xsint) xsint_delay <= 8'h00;            // async reset
	else       xsint_delay <= {xsint_delay[6:0], xsint};
end
 
assign xsint_d = xsint_delay[7];

// dma sound  
reg [1:0] ctrl;
reg [22:0] snd_bas, snd_adr, snd_end;
reg [22:0] snd_end_latched;
reg [7:0] mode;

// micro wire
reg [15:0] mw_data_reg, mw_mask_reg;

// ---------------------------------------------------------------------------
// ----------------------------- CPU register read ---------------------------
// ---------------------------------------------------------------------------

always @(sel, rw, addr, ctrl, snd_bas, snd_adr, snd_end, mode, mw_data_reg, mw_mask_reg) begin
	dout = 16'h0000;
	
	if(sel && rw) begin
		// control register
		if(addr == 5'h00) dout[1:0] = { ctrl[1], xsint }; 

		// frame start address
		if(addr == 5'h01) dout[7:0] = snd_bas[22:15]; 
		if(addr == 5'h02) dout[7:0] = snd_bas[14:7];
		if(addr == 5'h03) dout[7:1] = snd_bas[6:0];
	
		// frame address counter
		if(addr == 5'h04) dout[7:0] = snd_adr[22:15]; 
		if(addr == 5'h05) dout[7:0] = snd_adr[14:7];
		if(addr == 5'h06) dout[7:1] = snd_adr[6:0];

		// frame end address
		if(addr == 5'h07) dout[7:0] = snd_end_latched[22:15]; 
		if(addr == 5'h08) dout[7:0] = snd_end_latched[14:7];
		if(addr == 5'h09) dout[7:1] = snd_end_latched[6:0];

		// sound mode register
		if(addr == 5'h10) dout[7:0] = mode; 
		
		// mircowire
		if(addr == 5'h11) dout = mw_data_reg; 
		if(addr == 5'h12) dout = mw_mask_reg; 
		
	end
end

// ---------------------------------------------------------------------------
// ----------------------------- CPU register write --------------------------
// ---------------------------------------------------------------------------

reg [6:0] mw_cnt;   // micro wire shifter counter

// micro wire outputs
reg mw_clk;
reg mw_data;
reg mw_done;

reg dma_start;

always @(negedge clk) begin
	if(reset) begin
		ctrl <= 2'b00;         // default after reset: dma off
		mw_cnt <= 7'h00;        // no micro wire transfer in progress
		dma_start <= 1'b0;
	end else begin
		// writing bit 0 of the ctrl register to 1 starts the dma engine
		dma_start <= sel && !rw && !lds && (addr == 5'h00) && din[0];
	
		if(sel && !rw) begin	
			if(!lds) begin
				// control register
				if(addr == 5'h00) ctrl <= din[1:0];

				// frame start address
				if(addr == 5'h01) snd_bas[22:15] <= din[7:0]; 
				if(addr == 5'h02) snd_bas[14:7] <= din[7:0];
				if(addr == 5'h03) snd_bas[6:0] <= din[7:1];
	
				// frame address counter is read only

				// frame end address
				if(addr == 5'h07) snd_end[22:15] <= din[7:0]; 
				if(addr == 5'h08) snd_end[14:7] <= din[7:0];
				if(addr == 5'h09) snd_end[6:0] <= din[7:1];

				// sound mode register
				if(addr == 5'h10) mode <= din[7:0];
			end

			// micro wire has a 16 bit interface
			if(addr == 5'h12) mw_mask_reg <= din; 
		end
	end

	// ----------- micro wire interface -----------
	
	// writing the data register triggers the transfer
	if((sel && !rw && (addr == 5'h11)) || (mw_cnt != 0)) begin

		if(sel && !rw && (addr == 5'h11)) begin
			// first bit is evaluated imediately					
			mw_data_reg <= { din[14:0], 1'b0 }; 
			mw_data <= din[15];
			mw_cnt <= 7'h7f;
		end else if(mw_cnt[2:0] == 3'b000) begin
			// send/shift next bit every 8 clocks -> 1 MBit/s
			mw_data_reg <= { mw_data_reg[14:0], 1'b0 }; 
			mw_data <= mw_data_reg[15];
		end

		// rotate mask on first access and on every further 8 clocks 
		if((sel && !rw && (addr == 5'h11)) || (mw_cnt[2:0] == 3'b000)) begin
			mw_mask_reg <= { mw_mask_reg[14:0], mw_mask_reg[15]}; 
			// notify client of valid bits
			mw_clk <= mw_mask_reg[15];
		end

		// decrease shift counter
		if(mw_cnt != 0) 
			mw_cnt <= mw_cnt - 7'd1;

		// indicate end of transfer
		mw_done <= (mw_cnt == 7'h01);
	end	
end

// ---------------------------------------------------------------------------
// --------------------------------- audio fifo ------------------------------
// ---------------------------------------------------------------------------

localparam FIFO_ADDR_BITS = 2;    // four words
localparam FIFO_DEPTH = (1 << FIFO_ADDR_BITS);
reg [15:0] fifo [FIFO_DEPTH-1:0];
reg [FIFO_ADDR_BITS-1:0] writeP, readP;
wire fifo_empty = (readP == writeP);
wire fifo_full = (readP == (writeP + 2'd1));

reg [11:0] fifo_underflow /* synthesis noprune */;

// ---------------------------------------------------------------------------
// -------------------------------- audio engine -----------------------------
// ---------------------------------------------------------------------------

reg byte;   // byte-in-word toggle flag
wire [15:0] fifo_out = fifo[readP];
wire [7:0] mono_byte = (!byte)?fifo_out[7:0]:fifo_out[15:8];  // TODO: check byte order!!

// empty the fifo at the correct rate
always @(posedge aclk) begin
	if(reset) begin
		readP <= 2'd0;
		fifo_underflow <= 12'd0;
	end else begin
		// no audio playing: silence
		if(!ctrl[0]) begin
			audio_l <= 8'd0;
			audio_r <= 8'd0;
			byte <= 1'b0;
		end else begin
			// audio enabled and data in fifo? play it!
			if(!fifo_empty) begin
				if(!mode[7]) begin
					audio_l <= fifo_out[15:8] + 8'd128;   // high byte == left channel
					audio_r <= fifo_out[ 7:0] + 8'd128;   // low byte == right channel
				end else begin
					audio_l <= mono_byte + 8'd128;
					audio_r <= mono_byte + 8'd128;
					byte <= !byte;
				end
	
				// increase fifo read pointer everytime in stereo mode and every
				// second byte in mono mode
				if(!mode[7] || byte)
					readP <= readP + 2'd1;	
			end else
				// for debugging: monitor if fifo runs out of data
				fifo_underflow <= fifo_underflow + 12'd1;
		end
	end
end

// ---------------------------------------------------------------------------
// ------------------------------- memory engine -----------------------------
// ---------------------------------------------------------------------------

// The memory engine is very similar to the one used by the video/shifter 
// implementation and access the ram while video doesn't need it (in the hsync)

reg dma_enable;  // flag indicating dma engine is active

// the "dma_enable" signal is permanently active while playing. The adress counter will
// reach snd_end, but this will not generate a bus transfer and thus xsint is
// released for that event
reg frame_done;
assign xsint = dma_enable && (snd_adr != snd_end_latched);
// assign xsint = dma_enable && !frame_done;

reg [7:0] frame_cnt /* synthesis noprune */;

always @(posedge clk32) begin
	if(reset) begin
		dma_enable <= 1'b0;
		writeP <= 2'd0;
		frame_cnt <= 8'h00;
	end else begin

		if(!ctrl[0]) begin
			dma_enable <= 1'b0;  // stop dma_enable
			frame_cnt <= 8'h00;
		end else begin
			// dma not enabled enabled, but should be playing? -> start dma
			if(!dma_enable) begin
				if(dma_start) begin
					// start
					dma_enable <= 1'b1;   // start dma
					snd_adr <= snd_bas;   // load audio start address
					snd_end_latched <= snd_end;
					frame_cnt <= frame_cnt + 8'h01;
				end
			end else begin

				// address will reach end address in next step. indicate end of frame
				frame_done <= (snd_adr == snd_end_latched-23'd1);
 
				// fifo not full? read something during hsync using the video cycle
				// bus_cycle_L = 3 is the end of the video cycle
				if((!fifo_full) && hsync && (bus_cycle_L == 3)) begin
						
 					if(snd_adr != snd_end_latched) begin
						// read right word from ram using the 64 bit memory interface
						case(snd_adr[1:0])
							2'd0: fifo[writeP] <= data[15: 0];
							2'd1: fifo[writeP] <= data[31:16];
							2'd2: fifo[writeP] <= data[47:32];
							2'd3: fifo[writeP] <= data[63:48];
						endcase
						
						writeP <= writeP + 2'd1;     // advance fifo ptr
						snd_adr <= snd_adr + 23'd1;  // advance address counter
					end else begin
						// check if we just loaded the last sample
						if(ctrl == 2'b11) begin	
							snd_adr <= snd_bas;   // load audio start address
							snd_end_latched <= snd_end;
							frame_cnt <= frame_cnt + 8'h01;
						end else 
							dma_enable <= 1'b0;          // else just stop dma
					end
				end
			end
		end
	end
end

endmodule
