// blitter docs:

module blitter (
		input 		  clk32, // 31.875 MHz
		input [3:0] 	  bus_cycle,

		// cpu register interface
		input 		  clk,
		input 		  reset,

		input 		  sel,
		input [4:0] 	  addr,
		input [15:0] 	  din,
		output reg [15:0] dout,
		input 		  uds,
		input 		  lds,
		input 		  rw,
		output 		  irq
);

assign irq = 1'b0;

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

	   // since reading them has not side effect we can return the 8 bit registers
	   // without caring for uds/lds
	   if(addr == 5'h1d) dout <= { 6'b000000, hop, 4'b0000, op };
	   if(addr == 5'h1e) dout <= { busy, hog, smudge, 1'b0, line_number, fxsr, nfsr, 2'b00, skew };
	end
end

// CPU WRITE
always @(negedge clk) begin
   if(reset) begin
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
			if(addr == 5'h1d && ~uds) hop <= din[9:8];
			if(addr == 5'h1d && ~lds) op <= din[3:0];

			if(addr == 5'h1e && ~uds) begin
				line_number <= din[11:8];
				smudge <= din[13];
				hog <= din[14];
				busy <= din[15];

			   // writing busy with 1 starts the blitter
			   
			end
			
			if(addr == 5'h1e && ~lds) begin
				skew <= din[3:0];
				nfsr <= din[6];
				fxsr <= din[7];
			end
		end
   end
end

// ----------------- blitter engine -------------------
always @(posedge clk32) begin
	if(reset) begin
	 
   end else begin

   end
end

// wire io = (bus_cycle[3:2] == 0);  // blitter does io in cycle 0 which is the same one the cpu uses

// TODO: Also use bus cycle 2 to make a "turbo blitter" being twice as fast
   
// internal registers
reg [31:0] src;       // 32 bit source read buffer
reg [15:0] dest;      // 16 bit destination read buffer
   
// ------- wire up the blitter subcomponent combinatorics --------
wire [15:0] src_skewed;
wire [15:0] src_halftoned;
wire [15:0] result;
   
// select current halftone line
wire [15:0] halftone_line = halftone_ram[line_number];

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
			 
			 .out (src_halftoned)
			 );

// apply blitter operation   
blitter_op blitter_op (
		       .op (op),
		       .in0 (src_halftoned),
		       .in1 (dest),
		       
		       .out (result)
		       );

wire  first_word_in_row = (x_count == x_count_latch);
wire  last_word_in_row = (x_count == 16'h0001);

wire [15:0] data_to_write;
   
// apply masks
masking masking (
	   .endmask1 (endmask1),
	   .endmask2 (endmask2),
	   .endmask3 (endmask3),
	   .first (first_word_in_row),
	   .last (last_word_in_row),
	   .in0 (result),
	   .in1 (dest),
	   
	   .out (data_to_write)
	   );
   
      
endmodule // blitter

// the blitter operations
module blitter_op (
	   input  [3:0] op,
	   input  [15:0] in0,
	   input  [15:0] in1,

      output reg [15:0] out
);

always @(op, in0, in1) begin
   case(op)
     0:  out = 8'h00;
     1:  out =  in0 &  in1;
     2:  out =  in0 & ~in1;
     3:  out =  in0;
     4:  out = ~in0 &  in1;
     5:  out =         in1;
     6:  out =  in0 ^  in1;
     7:  out =  in0 |  in1;
     8:  out = ~in0 & ~in1;
     9:  out = ~in0 ^  in1;
     10: out = ~in1;
     11: out =  in0 | ~in1;
     12: out = ~in0;
     13: out = ~in0 |  in1;
     14: out = ~in0 | ~in1;
     15: out = 8'hff;
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
	out = 16'h00;
   // out = in[skew+15:skew];

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

      output reg [15:0] out
);

always @(op, in0, in1) begin
   case(op)
     0:  out = 8'hff;
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