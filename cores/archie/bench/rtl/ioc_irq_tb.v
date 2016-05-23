`timescale 1ns / 1ps
/* ioc_irq_tb.v

 Copyright (c) 2012-2014, Stephen J. Leary
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
 
module ioc_irq_tb;

	// Inputs
	reg CLK32M = 0;
	reg CLK25M = 0;
	
	reg	[31:0]	ADDRESS = 0;
	reg	[7:0]	DIN		= 0;
	wire[7:0]	DOUT1,DOUT2,DOUT3;

	reg	[7:0]	I1 = 0;
	reg	[7:0]	I2 = 0;
	reg	[7:0]	I3 = 0;
	
	reg	[7:0]	C2 = 0;
	reg	[7:0]	C3 = 0;
	
	wire		IRQ1,IRQ2,IRQ3;
	reg	WR_RQ	= 0;
	
   // Instantiate the Unit Under Test (UUT)
   ioc_irq  #(
	.ADDRESS(2'b01),
	.PERMBITS(8'h80)
	) UUT1
   (
		.clkcpu 		( CLK32M 	),
		
		.i				( I1		),
		.irq			( IRQ1		),
		
		.addr			( {ADDRESS[6:2]}),
		.din			( DIN		),
		.dout			( DOUT1		),
		
		.write			( WR_RQ	)
		
	);
		
   // Instantiate the Unit Under Test (UUT)
   ioc_irq #(
	.ADDRESS(2'b10),
	.CANCLEAR(1'b0) 
	) UUT2
   (
		.clkcpu 		( CLK32M 	),
		
		.i				( I2		),
		.c				( C2		),
		.irq			( IRQ2		),
		
		.addr			( ADDRESS[6:2]),
		.din			( DIN		),
		.dout			( DOUT2		),
		
		.write		 	( WR_RQ	)
	);
		
   // Instantiate the Unit Under Test (UUT)
   ioc_irq  #(
   .ADDRESS(2'b11),
   .CANCLEAR(1'b0) 
	) UUT3
   (
		.clkcpu 		( CLK32M 	),
		
		.i				( I3		),
		.c				( C3		),
		.irq			( IRQ3		),
		
		.addr			( ADDRESS[6:2]),
		.din			( DIN		),
		.dout			( DOUT3		),
		
		.write		 	( WR_RQ	)
	);
	
	initial begin

		$dumpfile("ioc_irq.vcd");
		$dumpvars(0, ioc_irq_tb);
		
		#500;
		
		wait(~CLK32M);
		ADDRESS = 32'h03200010;
		
		wait(CLK32M);
		wait(~CLK32M);
		
		if(!(DOUT1==8'h80)) begin $display("fail."); $finish; end
		
		wait(CLK32M);
		wait(~CLK32M);
		
		I1 = 8'h42;
		
		wait(CLK32M);
		wait(~CLK32M);
		
		I1 = 8'h00;
		
		wait(CLK32M);
		wait(~CLK32M);
	
		if(!(DOUT1==8'hC2)) begin $display("fail."); $finish; end
		
		wait(CLK32M);
		wait(~CLK32M);
		
		WR_RQ	= 1;
		ADDRESS = 32'h03200014;
		DIN		= 8'h40;

		wait(CLK32M);
		wait(~CLK32M);
		
		ADDRESS = 32'h03200010;
		WR_RQ	= 0;
		I1 = 8'h00;
		
		$display("address: %b", ADDRESS[6:2]);
		
		wait(CLK32M);
		wait(~CLK32M);
		
		if(!(DOUT1==8'h82)) begin $display("fail."); $finish; end
		if(IRQ1) begin $display("fail."); $finish; end
		if(IRQ2) begin $display("fail."); $finish; end
		if(IRQ3) begin $display("fail."); $finish; end
		
		ADDRESS = 32'h03200018;
		WR_RQ	= 1;
		DIN		= 8'h40;
		
		wait(CLK32M);
		wait(~CLK32M);
		
		WR_RQ	= 0;
		if(IRQ1) begin $display("fail."); $finish; end
		
		wait(CLK32M);
		wait(~CLK32M);
		
		if(IRQ1) begin $display("fail."); $finish; end
		
		wait(CLK32M);
		wait(~CLK32M);
		
		if(IRQ1) begin $display("fail."); $finish; end
		
		I1	= 8'hFF;
		
		wait(CLK32M);
		wait(~CLK32M);
		
		wait(CLK32M);
		wait(~CLK32M);
		
		if(~IRQ1) begin $display("fail."); $finish; end
		if(IRQ2) begin $display("fail."); $finish; end
		if(IRQ3) begin $display("fail."); $finish; end
		I1	= 8'h00;
		
		ADDRESS = 32'h03200014;
		
		wait(CLK32M);
		wait(~CLK32M);

		if(!(DOUT1==8'h40)) begin $display("fail."); $finish; end

		wait(CLK32M);
		wait(~CLK32M);
		
		ADDRESS = 32'h03200014;
		WR_RQ	= 1;
		DIN		= 8'h40;
		
		wait(CLK32M);
		wait(~CLK32M);
		
		WR_RQ	= 0;
		if(IRQ1) begin $display("fail."); $finish; end
		if(IRQ2) begin $display("fail."); $finish; end
		if(IRQ3) begin $display("fail."); $finish; end
		
		// ok now test irq 2
		
		ADDRESS = 32'h03200020;
		
		wait(CLK32M);
		wait(~CLK32M);
		
		if(!(DOUT2==8'h00)) begin $display("fail."); $finish; end

		I2 = 8'h08;
		
		wait(CLK32M);
		wait(~CLK32M);

		if(!(DOUT2==8'h08)) begin $display("fail."); $finish; end
		
		I2 = 8'h00;
		
		ADDRESS = 32'h03200024;
		WR_RQ	= 1;
		DIN		= 8'h08;
		
		wait(CLK32M);
		wait(~CLK32M);
		
		WR_RQ	= 0;
		ADDRESS = 32'h03200020;
		
		wait(CLK32M);
		wait(~CLK32M);
		
		// verify that the clear address doesnt work for these irq sources.
		if(!(DOUT2==8'h08)) begin $display("fail."); $finish; end
					
		C2	= 8'h48;
		
		wait(CLK32M);
		wait(~CLK32M);
		
		// verify that the clear address doesnt work for these irq sources.
		if(!(DOUT2==8'h08)) begin $display("fail."); $finish; end
		
		#500;
		$finish;

		
	end
	
	always 	begin
	   #15; CLK32M = ~CLK32M;
	end
      
endmodule

