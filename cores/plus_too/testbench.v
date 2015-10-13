`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   14:54:22 09/05/2011
// Design Name:   plusToo_top
// Module Name:   C:/Users/steve/Documents/PlusToo/Verilog/testbench.v
// Project Name:  plusToo
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: plusToo_top
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

`define VIA_A_Data 24'hEFFFFE
`define VIA_A_Dir 24'hEFE9FE

module testbench;

	// Inputs
	reg clk50;

	// Outputs
	wire hsync;
	wire vsync;
	wire [3:0] red;
	wire [3:0] green;
	wire [3:0] blue;

	// Instantiate the Unit Under Test (UUT)
	plusToo_top uut (
		.clk50(clk50), 
		.hsync(hsync), 
		.vsync(vsync), 
		.red(red), 
		.green(green), 
		.blue(blue)
	);
	
	initial begin
		clk50 = 1'b1;
		uut.ac0.busCycle = 0;
		uut.ac0.vt.xpos = 0;
		uut.ac0.vt.ypos = 0;
		uut.dc0.clkPhase = 0;
	end
	
	always 
		#10 clk50 = ~clk50;
	
	always @(posedge uut.clk32) begin
		if (uut.cpuAddr == `VIA_A_Data ||
			 uut.cpuAddr == `VIA_A_Dir) begin
			$display($time, " memory reference to VIA");
		end
		if (uut.loadPixels == 1'b1 && uut.memoryDataInMux == 16'hBEEF) begin
			$display($time, " loading bad pixel data");
		end		
		if (uut.cpuAddr == 24'h4001B8) begin
			$display($time, " critical error");
		end		
		if (uut._cpuAS == 0 && 
			 uut.cpuAddr >= 24'h402000 &&
			 uut.cpuAddr < 24'h800000) begin
			$display($time, " memory reference unimplemented ROM");
			$stop();
		end		
	end
	
endmodule

