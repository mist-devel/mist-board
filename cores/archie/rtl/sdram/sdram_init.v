/*	sdram_init.v

	Copyright (c) 2013-2014, Stephen J. Leary
	All rights reserved.

	Redistribution and use in source and binary forms, with or without
	modification, are permitted provided that the following conditions are met:
		 * Redistributions of source code must retain the above copyright
			notice, this list of conditions and the following disclaimer.
		 * Redistributions in binary form must reproduce the above copyright
			notice, this list of conditions and the following disclaimer in the
			documentation and/or other materials provided with the distribution.
		 * Neither the name of the Stephen J. Leary nor the
			names of its contributors may be used to endorse or promote products
			derived from this software without specific prior written permission.

	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
	ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
	WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
	DISCLAIMED. IN NO EVENT SHALL STEPHEN J. LEARY BE LIABLE FOR ANY
	DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
	(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
	LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
	ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
	(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
	SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
*/



module sdram_init(
	
	input				sd_clk,
	input				sd_rst,
	output	reg [3:0] 	sd_cmd,
	output 	reg [12:0]	sd_a,    // 13 bit multiplexed address bus
	output 				sd_rdy
);

`include "sdram_defines.v"

parameter MODE = 0;

reg [3:0] t;
reg [4:0] reset;

initial begin 

	t			= 4'd0;
	reset 		= 5'h1f;
	sd_a		= 13'd0;
	sd_cmd 		= CMD_INHIBIT; 

end

always @(posedge sd_clk) begin

	sd_cmd <= CMD_INHIBIT;  // default: idle

	if (sd_rst) begin 
	
		t			<= 4'd0;
		reset 	<= 5'h1f;
		sd_a		<= 13'd0;
	
	end else if (!sd_rdy) begin
	
		t <= t + 4'd1;
		
		if (t ==4'hF) begin 
			reset <= reset - 5'd1;		
		end
		
		if (t == 4'h0) begin 

			if(reset == 13) begin
				$display("precharging all banks");
				sd_cmd 		<= CMD_PRECHARGE;
				sd_a[10] 	<= 1'b1;      // precharge all banks
			end
				
			if(reset == 2) begin
				sd_cmd 		<= CMD_LOAD_MODE;
				sd_a 		<= MODE;
			end
			
			if(reset == 1) begin
				$display("loading mode");
				sd_cmd 		<= CMD_LOAD_MODE;
				sd_a 		<= MODE;
			end
			
		end
		
	end
	
end

assign	sd_rdy	= reset == 5'd0;

endmodule