`timescale 1ns / 1ps
/* ioc.v

 Copyright (c) 2012-2015, Stephen J. Leary
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the <organization> nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
 
module ioc(
		
		input 	 		clkcpu, 	// cpu bus clock domain
		output			clk2m_en,
		output			clk8m_en,
		
		input 			por, 		// power on reset signal.

		input	[5:0]		c_in,		
		output[5:0]		c_out,
		
		output [7:1]	select, // perhiperhal select lines
		output 				sext, 	// external perhiperhal select
	
		input [1:0]		fh, // fast high interrupt.
		input	[7:0]		il, // active low interrupt lines
		input				ir, // 
	
		// "wishbone" bus
		input				wb_we,
		input				wb_stb,
		input				wb_cyc,
		
		input [6:2]		wb_adr,
		input [7:0]		wb_dat_i,
		output [7:0]	wb_dat_o,
		
		// perhaps rename but its part of an IOC bus cycle.
		input	[2:0]		wb_bank, 

		// interrupts
		output 			irq,
		output 			firq,
		
		// keyboard interface to arm controller. Data is valid
		// in rising edge of strobe
		output reg [7:0] kbd_out_data,
		output reg       kbd_out_strobe,
		input [7:0]      kbd_in_data,
		input            kbd_in_strobe
);

reg [4:0]   clken_counter;

wire [7:0]	irqa_dout, irqb_dout, firq_dout;
wire			irqa_req, irqb_req, firq_req;
wire			irqa_selected, irqb_selected, firq_selected;

wire			ctrl_selected = wb_adr[6:2] == 5'd0 /* synthesis keep */;
wire [7:0]	ctrl_dout;
reg  [5:0]	ctrl_state;

wire		serial_selected = wb_adr[6:2] == 5'd1 /* synthesis keep */;

wire write_request 	= (wb_bank == 3'b000) & wb_stb & wb_cyc & wb_we;
wire read_request 	= (wb_bank == 3'b000) & wb_stb & wb_cyc & !wb_we;

// keyboard input is valid on rising edge of kbd_in_strobe. Latch data then
// and set irq
reg [7:0] kbd_in_data_latch;
reg kbd_in_irq_ack;
reg kbd_in_irq;
// input data irq is cleared when cpu reads input port
always @(posedge clkcpu or posedge kbd_in_irq_ack) begin
	if (kbd_in_irq_ack) kbd_in_irq <= 0;
	else if (kbd_in_strobe) begin
		kbd_in_data_latch <= kbd_in_data;
		kbd_in_irq <= 1;
	end
end

// faked kbd tx timing
reg[4:0] txcount = 5'd0;
wire txdone = txcount == 5'd0 /* synthesis keep */;

// edge detect for IR 
reg ir_r;
wire ir_edge;

   // Instantiate the Unit Under Test (UUT)
   ioc_irq  #(
	.ADDRESS(2'b01),
	.PERMBITS(8'h80),
	.CANCLEAR(8'b01111111)
	) IRQA
   (
		.clkcpu 		( clkcpu 		),
		
		.i				( {1'b1, timer[1].reload, timer[0].reload, por, ir_edge, 3'b000}),
		.irq			( irqa_req		),
		.c				( 8'h00			),
		.addr			( wb_adr[6:2]	),
		.din			( wb_dat_i		),
		.dout			( irqa_dout		),
		.sel			( irqa_selected	),
		.write			( write_request	)
		
	);
		
   // Instantiate the Unit Under Test (UUT)
   ioc_irq #(
	.ADDRESS(2'b10),
	.CANCLEAR(8'b00000000) 
	) IRQB
   (
		.clkcpu 		( clkcpu 		),
		
		.i				( { kbd_in_irq,  txdone, ~il[5:0]}),
		.c				( {!kbd_in_irq, ~txdone,  il[5:0]}),
		.irq			( irqb_req		),
		
		.addr			( wb_adr[6:2]	),
		.din			( wb_dat_i		),
		.dout			( irqb_dout		),
		.sel			( irqb_selected	),		
		.write		 	( write_request	)
	);
		

   ioc_irq  #(
   .ADDRESS(2'b11),
   .CANCLEAR(8'd0) 
	) FIRQ
   (
		.clkcpu 		( clkcpu 		),
		
		.i				( {6'h00, fh[1:0]}	),
		.c				( {6'h00, ~fh[1:0]}),
		.irq			( firq_req		),
		
		.addr			( wb_adr[6:2]	),
		.din			( wb_dat_i		),
		.dout			( firq_dout		),
		.sel			( firq_selected	),

		.write		 	( write_request	)
	);


localparam TIMERS = 4;

genvar c;
generate 
	
	for (c = 0; c < TIMERS; c = c + 1) begin: timer
	
		reg[15:0]	latch_i;
		reg[15:0]	counter;
		reg[15:0]	latch_o;
		reg         reload;
		
		wire		selected = wb_adr[6] & (c[1:0] == wb_adr[5:4]);
		wire [7:0]	out		 = wb_adr[2] ? latch_o[15:8] : latch_o[7:0];
	
		initial begin 
		
			latch_i 	= 16'd0;
			counter 	= 16'd0;
			latch_o 	= 16'd0;
			reload   = 1'b0;
			
		end
	
		always @(posedge clkcpu) begin
					
			reload  <= 1'b0;
			
			if (write_request & selected) begin 
			
				case (wb_adr[3:2])
				
					2'b00:	latch_i[7:0] 	<= wb_dat_i;
					2'b01:	latch_i[15:8] 	<= wb_dat_i;
					2'b10:	counter 		<= {latch_i[15:4],4'd0};
					2'b11:	latch_o 		<= counter;
				
				endcase
			
			end else if (clk2m_en) begin
				
				counter <= counter - 15'd1;
				
				if (~|counter) begin 
			
					reload  <= 1'b1;
					counter <= {latch_i[15:4],4'd0};
			
				end
				
			end 
			
		end

	end
	
endgenerate

initial begin 

	ctrl_state = 6'h3F;

	ir_r = 1'b1;
	
end



// here we generate the ack signal and the 2mhz enable.
always @(posedge clkcpu) begin

	// generate strobe one clock cycle after data has been latched
	kbd_out_strobe <= !txdone;
	kbd_in_irq_ack <= serial_selected && read_request;

	ir_r		<= ir;
	
	if (!txdone &&(timer[3].reload)) begin 
		
		txcount <= txcount - 4'd1;
		
	end

	// increment the clock counter. 42 MHz clkcpu assumed.
	clken_counter <= clken_counter + 1'd1;
	if (clken_counter == 20) clken_counter <= 0;

	if (write_request & ctrl_selected) begin 
	
		ctrl_state <= wb_dat_i[5:0];
	
	end
	
	if (write_request & serial_selected) begin 
		// simulate a serial port write to the console.
		kbd_out_strobe <= 1'b0;
		kbd_out_data <= wb_dat_i[7:0];
		txcount <= 5'd20;
	end 

	
end

// external perhiperhal stuff. 
assign {select, sext}	  = 	   wb_bank == 3'b001 ? 8'b00000011 : 
						wb_bank == 3'b010 ? 8'b00000101 :
						wb_bank == 3'b011 ? 8'b00001001 :
						wb_bank == 3'b100 ? 8'b00010001 :
						wb_bank == 3'b101 ? 8'b00100001 :
						wb_bank == 3'b110 ? 8'b01000001 :
						wb_bank == 3'b111 ? 8'b10000001 : 8'd0;

						
assign c_out = ctrl_state;
assign ctrl_dout = { ir, 1'b1, c_in & c_out }; 

assign ir_edge = ~ir_r & ir;

assign clk2m_en = !clken_counter;
assign clk8m_en = clken_counter == 0 || clken_counter == 5 || clken_counter == 10 || clken_counter == 15;

assign wb_dat_o = 	read_request ?
					(ctrl_selected ?  ctrl_dout :
					serial_selected ? kbd_in_data_latch	:
					irqa_selected ?  irqa_dout : 
					irqb_selected ?  irqb_dout : 
					firq_selected ?  firq_dout : 
					timer[0].selected ? timer[0].out :
					timer[1].selected ? timer[1].out :
					timer[2].selected ? timer[2].out :
					timer[3].selected ? timer[3].out : 8'hFF) : 8'hFF;

assign	irq	= irqa_req | irqb_req;
assign	firq	= firq_req;
// sext is high if any bits of select are high
					
endmodule
