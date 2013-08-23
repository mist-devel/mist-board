// blitter docs:
// 
// http://mikro.naprvyraz.sk/docs/ST_E/BLITTER.TXT
// http://paradox.atari.org/files/BLIT_FAQ.TXT
// https://steem-engine.googlecode.com/svn-history/r67/branches/Seagal/steem/code/blitter.cpp

// TODO:
// - Also use bus cycle 3 to make a "turbo blitter" being twice as fast
// - Proper cooperation when DMA requests bus
// - Non-HOG mode
// - Don't spend a whole state 1 if nfsr && last_word_in_row
// - Test smudge mode

module blitter (
		input [1:0] 			bus_cycle,

		// cpu register interface
		input 		  			clk,
		input 		  			reset,

		input 		  			sel,
		input [4:0] 			addr,
		input [15:0] 			din,
		output reg [15:0] 	dout,
		input 		  			uds,
		input 		  			lds,
		input 		  			rw,
		
		// bus master interface
		output [23:1] 			bm_addr,
		output reg       		bm_write,
		output reg    			bm_read,
		output [15:0]  		bm_data_out,
		input  [15:0]  		bm_data_in,

		output reg	  			br,
		output 		  			irq

);

assign irq = busy;

// CPU controlled register set
reg [15:0] halftone_ram[15:0];

reg [15:1] src_x_inc;
reg [15:1] src_y_inc;
reg [23:1] src_addr;

reg [15:0] endmask1;
reg [15:0] endmask2;
reg [15:0] endmask3;

reg [15:1] dst_x_inc;
reg [15:1] dst_y_inc;
reg [23:1] dst_addr;

reg [15:0] x_count;
reg [15:0] x_count_latch;
reg [15:0] y_count;

reg [1:0]  hop;
reg [3:0]  op;

reg [3:0]  line_number;
reg        smudge;
reg        hog;
reg        busy;

reg [3:0]  skew;
reg        nfsr;
reg        fxsr;


// ------------------ cpu interface --------------------

// CPU READ
always @(sel, rw, addr, src_y_inc, src_x_inc, src_addr, endmask1, endmask2, endmask3, 
		dst_x_inc, dst_y_inc, dst_addr, x_count, y_count, hop, op, busy, hog,
		smudge, line_number, fxsr, nfsr, skew) begin
	dout = 16'h0000;

	if(sel && rw) begin
	   if((addr >= 5'h00) && (addr <= 5'h0f)) dout <= halftone_ram[addr];
	   
	   if(addr == 5'h10) dout <= { src_x_inc, 1'b0 };
	   if(addr == 5'h11) dout <= { src_y_inc, 1'b0 };
	   if(addr == 5'h12) dout <= { 8'h00, src_addr[23:16] };
	   if(addr == 5'h13) dout <= { src_addr [15:1], 1'b0 };

	   if(addr == 5'h14) dout <= endmask1;
	   if(addr == 5'h15) dout <= endmask2;
	   if(addr == 5'h16) dout <= endmask3;
			
	   if(addr == 5'h17) dout <= { dst_x_inc, 1'b0 };
	   if(addr == 5'h18) dout <= { dst_y_inc, 1'b0 };
	   if(addr == 5'h19) dout <= { 8'h00, dst_addr[23:16] };
	   if(addr == 5'h1a) dout <= { dst_addr [15:1], 1'b0 };

	   if(addr == 5'h1b) dout <= x_count;
	   if(addr == 5'h1c) dout <= y_count;

	   // since reading them has no side effect we can return the 8 bit registers
	   // without caring for uds/lds
	   if(addr == 5'h1d) dout <= { 6'b000000, hop, 4'b0000, op };
	   if(addr == 5'h1e) dout <= { busy, hog, smudge, 1'b0, line_number, fxsr, nfsr, 2'b00, skew };
	end
end

// the state machine runs through most states for every word it processes
// state 0: Blitter has just been started, wait 1 bus cycle before updating counters
// state 1: normal source read cycle
// state 2: destination read cycle
// state 3: destination write cycle
// state 4: extra source read cycle (fxsr)
reg [2:0] state;

always @(negedge clk) begin

	// ---------- böitter cpu register write interfce ............
	if(reset) begin
		busy <= 1'b0; 
		state <= 3'd0;
   end else begin
      if(sel && ~rw) begin
			// ------ 16/32 bit registers, not byte adressable ----------
			if((addr >= 5'h00) && (addr <= 5'h0f))	halftone_ram[addr] <= din;

			if(addr == 5'h10) src_x_inc <= din[15:1];
			if(addr == 5'h11) src_y_inc <= din[15:1];
			if(addr == 5'h12) src_addr [23:16]<= din[7:0];
			if(addr == 5'h13) src_addr [15:1]<= din[15:1];

			if(addr == 5'h14) endmask1 <= din;
			if(addr == 5'h15) endmask2 <= din;
			if(addr == 5'h16) endmask3 <= din;
			
			if(addr == 5'h17) dst_x_inc <= din[15:1];
			if(addr == 5'h18) dst_y_inc <= din[15:1];
			if(addr == 5'h19) dst_addr [23:16]<= din[7:0];
			if(addr == 5'h1a) dst_addr [15:1]<= din[15:1];

			if(addr == 5'h1b) begin 
			   x_count <= din;
			   x_count_latch <= din;  // x_count is latched to be reloaded at each end of line
			end

			if(addr == 5'h1c) y_count <= din;

			// ------ 8 bit registers ----------
			// uds -> even bytes via d15:d8
			// lds -> odd bytes via d7:d0
			if((addr == 5'h1d) && ~uds) hop <= din[9:8];
			if((addr == 5'h1d) && ~lds) op <= din[3:0];

			if((addr == 5'h1e) && ~uds) begin
				line_number <= din[11:8];
				smudge <= din[13];
				hog <= din[14];

			   // writing busy with 1 starts the blitter, but only if y_count != 0
			   if(din[15] && (y_count != 0)) begin
					busy  <= 1'b1;
					state <= 3'd0;

					// make sure the predicted x_count is one steap ahead of the 
					// real x_count
					if(x_count != 1) x_count_next <= x_count - 1'd1;
					else             x_count_next <= x_count_latch;
				end 
			end
			
			if((addr == 5'h1e) && ~lds) begin
				skew <= din[3:0];
				nfsr <= din[6];
				fxsr <= din[7];
			end
		end
   end
	
	// --------- blitter state machine -------------
	
	br <= busy;  // hog mode: grab bus immediately as long as we need it
	
	// busy->br is written by the cpu and anly becomes active if y_count != 0
	if(br && (bus_cycle == 2'd0)) begin

		// init/setup state
		if(state == 3'd0) begin
			if(skip_src_read) state <= 3'd2;  // skip source read
			else if(fxsr)     state <= 3'd4;  // first extra source read
			else              state <= 3'd1;  // normal source read
		end
		
		// first extra source read (fxsr)
		if(state == 3'd4) begin
			if(src_x_inc[15] == 1'b0) 	src <= { src[15:0],  bm_data_in};
			else								src <= { bm_data_in, src[31:16]};

			src_addr <= src_addr + { {8{src_x_inc[15]}}, src_x_inc };
			state <= 3'd1;
		end  
		 
		if(state == 3'd1) begin
			// don't do the read of the last word in a row if nfsr is set
			if(nfsr && last_word_in_row) begin
				// no final source read, but shifting anyway
				if(src_x_inc[15] == 1'b0) 	src[31:16] <= src[15:0];
				else								src[15:0] <= src[31:16];
				
				src_addr <= src_addr + { {8{src_y_inc[15]}}, src_y_inc } - { {8{src_x_inc[15]}}, src_x_inc };

			end else begin
				if(src_x_inc[15] == 1'b0) 	src <= { src[15:0],  bm_data_in};
				else								src <= { bm_data_in, src[31:16]};

				if(x_count != 1) 	// do signed add by sign expanding XXX_x_inc
					src_addr <= src_addr + { {8{src_x_inc[15]}}, src_x_inc };
				else 					// we are at the end of a line
					src_addr <= src_addr + { {8{src_y_inc[15]}}, src_y_inc };
			end 

			// jump directly to destination write if no destination read is required
			if(dest_required)	state <= 3'd2;
			else              state <= 3'd3;
		end

		if(state == 3'd2) begin
			dest <= bm_data_in;
			
			state <= 3'd3;
		end

		// don't update counters and adresses if still in setup phase
		if(state == 3'd3) begin
		
			// y_count != 0 means blitter is (still) active	
			if(y_count != 0) begin

				if(x_count != 1) begin 
					// we are at the begin or within a line (have not reached the end yet)

					// do signed add by sign expanding XXX_x_inc
					dst_addr <= dst_addr + { {8{dst_x_inc[15]}}, dst_x_inc };
		
					x_count <= x_count - 8'd1;
				end else begin
					// we are at the end of a line but not finished yet

					// do signed add by sign expanding XXX_y_inc
					dst_addr <= dst_addr + { {8{dst_y_inc[15]}}, dst_y_inc };
					if(dst_y_inc[15]) line_number <= line_number + 4'd1;
					else              line_number <= line_number - 4'd1;
			
					x_count <= x_count_latch;
					y_count <= y_count - 8'd1;
				end
				
				// also advance the predicted next x_count
				if(x_count_next != 1) x_count_next <= x_count_next - 1'd1;
				else                  x_count_next <= x_count_latch;
				
			end else begin
				// y_count reached zero -> end of blitter operation
				busy <= 1'b0;
			end

			if(skip_src_read) begin                             // skip source read (state 1)
				if(next_dest_required)				state <= 3'd2;  //   but dest needs to be read
				else              					state <= 3'd3;  //   also dest needs to be read
			end
			else if(last_word_in_row && fxsr)	state <= 3'd4;  // extra state 4
			else											state <= 3'd1;  // normal source read state
		end
	end
end

// source read takes place in state 1 (normal source read) and 4 (fxsr)
assign bm_addr = ((state == 1)||(state == 4))?src_addr:dst_addr;

// ----------------- blitter busmaster engine -------------------
always @(posedge clk) begin
	bm_read <= 1'b0;
	bm_write <= 1'b0;

	if(br && (y_count != 0) && (bus_cycle == 2'd0)) begin
		if(state == 3'd1)      bm_read  <= 1'b1;
		else if(state == 3'd2) bm_read  <= 1'b1;
		else if(state == 3'd3) bm_write <= 1'b1;
		else if(state == 3'd4) bm_read  <= 1'b1;  // fxsr state
	end
end

// internal registers

// predicts what the next x_count will be. Is needed to determine the first state in the nect
// blitter cycle e.g. to know whether we can skip the source/dest read of the next cycle
reg [15:0] x_count_next;

reg [31:0] src;       // 32 bit source read buffer
reg [15:0] dest;      // 16 bit destination read buffer
   
// ------- wire up the blitter subcomponent combinatorics --------
wire [15:0] src_skewed;
wire [15:0] src_halftoned;
wire [15:0] result;
   
// select current halftone line
wire [15:0] halftone_line = halftone_ram[smudge?src_skewed[3:0]:line_number];

wire skip_src_read = (no_src_hop || no_src_op) && !smudge;
wire no_src_hop;  // hop doesn't require source read
wire no_src_op;   // op     -"-
wire no_dest_op;  // op doesn't require dest read
 
// shift/select 16 bits of source
shift shift (
	     .skew (skew),
	     .in (src),
	     
	     .out (src_skewed)
	    );

// apply halftone operation
halftone_op halftone_op (
			 .op (hop),
			 .in0 (halftone_line),
			 .in1 (src_skewed),
			 
			 .no_src (no_src_hop),
			 .out (src_halftoned)
			 );

		 	 
// apply blitter operation   
blitter_op blitter_op (
	       .op (op),
	       .in0 (src_halftoned),
	       .in1 (dest),
		       
			 .no_src (no_src_op),
			 .no_dest (no_dest_op),
	       .out (result)
	       );

// check if current column is first or last word in the row
wire first_word_in_row = (x_count == x_count_latch);
wire last_word_in_row = (x_count == 16'h0001);

// check if next column is first or last word in the row
wire next_is_first_word_in_row = (x_count_next == x_count_latch);
wire next_is_last_word_in_row = (x_count_next == 16'h0001);

// check if the current mask requires to read the destination first
wire mask_requires_dest =
	first_word_in_row?(endmask1 != 16'hffff):
	(last_word_in_row?(endmask3 != 16'hffff):
	(endmask2 != 16'hffff));

// check if the next words mask requires to read the destination first
wire next_mask_requires_dest =
	next_is_first_word_in_row?(endmask1 != 16'hffff):
	(next_is_last_word_in_row?(endmask3 != 16'hffff):
	(endmask2 != 16'hffff));

// the requirement to read the destination first may either come from the
// operation or from the fact that masking takes place
wire dest_required = mask_requires_dest || !no_dest_op;
wire next_dest_required = next_mask_requires_dest || !no_dest_op;
	
// apply masks
masking masking (
	   .endmask1 (endmask1),
	   .endmask2 (endmask2),
	   .endmask3 (endmask3),
	   .first (first_word_in_row),
	   .last (last_word_in_row),
	   .in0 (result),
	   .in1 (dest),
	   
	   .out (bm_data_out)
	   );
   
      
endmodule // blitter

// the blitter operations
module blitter_op (
	   input  [3:0] op,
	   input  [15:0] in0,
	   input  [15:0] in1,

	   output reg no_src,
	   output reg no_dest,
      output reg [15:0] out
);

always @(op, in0, in1) begin
	// return 1 for all ops that don't use in0 (src)
	no_src = (op == 0) || (op == 5) || (op == 10) || (op == 15);
	no_dest = (op == 0) || (op == 3) || (op == 12) || (op == 15);

   case(op)
     0:  out = 16'h0000;
     1:  out =  in0 &  in1;
     2:  out =  in0 & ~in1;
     3:  out =  in0;
     4:  out = ~in0 &  in1;
     5:  out =         in1;
     6:  out =  in0 ^  in1;
     7:  out =  in0 |  in1;
     8:  out = ~in0 & ~in1;
     9:  out = ~in0 ^  in1;
     10: out =        ~in1;
     11: out =  in0 | ~in1;
     12: out = ~in0;
     13: out = ~in0 |  in1;
     14: out = ~in0 | ~in1;
     15: out = 16'hffff;
   endcase; // case (op)
end
   
endmodule // blitter_op

// the blitter barrel shifter
module shift (
	   input  [3:0] skew,
	   input  [31:0] in,
      output reg [15:0] out
);

always @(skew, in) begin
	out = 16'h0000;

   case(skew)
     0:  out =  in[15:0];
     1:  out =  in[16:1];
     2:  out =  in[17:2];
     3:  out =  in[18:3];
     4:  out =  in[19:4];
     5:  out =  in[20:5];
     6:  out =  in[21:6];
     7:  out =  in[22:7];
     8:  out =  in[23:8];
     9:  out =  in[24:9];
     10: out =  in[25:10];
     11: out =  in[26:11];
     12: out =  in[27:12];
     13: out =  in[28:13];
     14: out =  in[29:14];
     15: out =  in[30:15];
   endcase; // case (skew)
end
   
endmodule // shift

// the halftone operations
module halftone_op (
	   input  [1:0] op,
	   input  [15:0] in0,
	   input  [15:0] in1,

	   output reg no_src,
      output reg [15:0] out
);

always @(op, in0, in1) begin
	// return 1 for all ops that don't use in1 (src)
	no_src = (op == 0) || (op == 1);

   case(op)
     0:  out = 16'hffff;
     1:  out = in0;
     2:  out = in1;
     3:  out = in0 & in1;
   endcase; // case (op)
end
   
endmodule // halftone_op

// masking 
module masking (
	   input [15:0]  endmask1,
	   input [15:0]  endmask2,
	   input [15:0]  endmask3,

	   input 	 first,
	   input 	 last,
		
	   input [15:0]  in0,
	   input [15:0]  in1,
	   output reg [15:0] out
);

always @(endmask1, endmask2, endmask3, first, last, in0, in1) begin
   // neither first nor last: endmask2
   out = (in0 &  endmask2) | (in1 & ~endmask2);

   // first (last may also be applied): endmask1
   if(first)     out = (in0 &  endmask1) | (in1 & ~endmask1);
   // last and not first: endmask3
   else if(last) out = (in0 &  endmask3) | (in1 & ~endmask3);
end
   
endmodule // masking