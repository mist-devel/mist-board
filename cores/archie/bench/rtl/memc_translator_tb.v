`timescale 1ns / 1ps
/* memc_translator_tb.v

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
 
module memc_translator_tb;

// Inputs
reg CLK32M = 0;
reg CLK25M = 0;
reg MEMCTW = 0;
reg SPVMD = 0;
reg OSMD = 0;
reg MEMWE = 1;

reg [25:0] addr_i;
wire [25:0] addr_o;
wire		valid;
	
// Instantiate the Unit Under Test (UUT)
memc_translator UUT (
	.clkcpu ( CLK32M 	),	
	.wr     ( MEMCTW	),
	.mem_write ( MEMWE		),
	.spvmd	( SPVMD		),
	.osmd	( OSMD		),
	.addr_i	( addr_i	),
	.addr_o	( addr_o	),
	.valid	( valid		)
);


task CHECK;
input expected;
input actual;  
begin
   if (expected != actual) begin
      $display("Error: expected %b, actual %b", expected, actual);
      $finish_and_return(-1);
   end
end
endtask      
	
task SetMEMC;
input [31:0] address;
begin
	MEMCTW 	<= 1;
	SPVMD	<= 1;
	addr_i	<= address;
	#30;
	MEMCTW 	<= 0;
	#30;
end
endtask

task CheckSPVMD;
input [31:0] address;
input     expected;     
begin
	MEMCTW 	<= 0;
	SPVMD	<= 1;
	addr_i	<= address;
	#30;
	$display("Checking address %08x in Supervisor Mode: Valid = %b, Result = %08x", addr_i, valid, addr_o);
        CHECK(expected, valid);
	MEMCTW 	<= 0;
	#30;
end
endtask

task CheckOSMD;
input [31:0] address;
input expected;
begin
	MEMCTW 	<= 0;
	SPVMD	<= 0;
	OSMD	<= 1;
	addr_i	<= address;
	#30;
	$display("Checking address %08x in OS Mode: Valid = %b, Result = %08x", addr_i, valid, addr_o);
        CHECK(expected, valid);
	MEMCTW 	<= 0;
	#30;
end
endtask

task CheckUser;
input [31:0] address;
input expected;
begin
	MEMCTW 	<= 0;
	SPVMD	<= 0;
	OSMD	<= 0;
	addr_i	<= address;
	#30;
	$display("Checking address %08x in User Mode: Valid = %b, Result = %08x", addr_i, valid, addr_o);
        CHECK(expected, valid);
        MEMCTW 	<= 0;
	#30;
end
endtask

	
initial begin

	$dumpfile("memc_translator.vcd");
	$dumpvars(0, UUT);
	//$monitor ("%g %b %x %x", $time, CLK32M, MEMCTW, addr_i, addr_o);

	// Initialize Inputs
	CLK32M = 0;
	MEMCTW = 0;
	SPVMD = 0;
	
	#30;

	$display("BangCam: R2 = 0x0000007f, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f7f);
	
	$display("BangCam: R2 = 0x0000007e, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f77);
	
	$display("BangCam: R2 = 0x0000007d, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f6f);
	
	$display("BangCam: R2 = 0x0000007c, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f67);
	
	$display("BangCam: R2 = 0x0000007b, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f5f);
	
	$display("BangCam: R2 = 0x0000007a, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f57);
	
	$display("BangCam: R2 = 0x00000079, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f4f);
	
	$display("BangCam: R2 = 0x00000078, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f47);
	
	$display("BangCam: R2 = 0x00000077, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f3f);
	
	$display("BangCam: R2 = 0x00000076, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f37);
	
	$display("BangCam: R2 = 0x00000075, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f2f);
	
	$display("BangCam: R2 = 0x00000074, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f27);
	
	$display("BangCam: R2 = 0x00000073, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f1f);
	
	$display("BangCam: R2 = 0x00000072, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f17);
	
	$display("BangCam: R2 = 0x00000071, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f0f);
	
	$display("BangCam: R2 = 0x00000070, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f07);
	
	$display("BangCam: R2 = 0x0000006f, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f7e);
	
	$display("BangCam: R2 = 0x0000006e, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f76);
	
	$display("BangCam: R2 = 0x0000006d, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f6e);
	
	$display("BangCam: R2 = 0x0000006c, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f66);
	
	$display("BangCam: R2 = 0x0000006b, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f5e);
	
	$display("BangCam: R2 = 0x0000006a, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f56);
	
	$display("BangCam: R2 = 0x00000069, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f4e);
	
	$display("BangCam: R2 = 0x00000068, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f46);
	
	$display("BangCam: R2 = 0x00000067, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f3e);
	
	$display("BangCam: R2 = 0x00000066, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f36);
	
	$display("BangCam: R2 = 0x00000065, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f2e);
	
	$display("BangCam: R2 = 0x00000064, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f26);
	
	$display("BangCam: R2 = 0x00000063, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f1e);
	
	$display("BangCam: R2 = 0x00000062, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f16);
	
	$display("BangCam: R2 = 0x00000061, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f0e);
	
	$display("BangCam: R2 = 0x00000060, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f06);
	
	$display("BangCam: R2 = 0x0000005f, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f7b);
	
	$display("BangCam: R2 = 0x0000005e, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f73);
	
	$display("BangCam: R2 = 0x0000005d, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f6b);
	
	$display("BangCam: R2 = 0x0000005c, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f63);
	
	$display("BangCam: R2 = 0x0000005b, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f5b);
	
	$display("BangCam: R2 = 0x0000005a, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f53);
	
	$display("BangCam: R2 = 0x00000059, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f4b);
	
	$display("BangCam: R2 = 0x00000058, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f43);
	
	$display("BangCam: R2 = 0x00000057, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f3b);
	
	$display("BangCam: R2 = 0x00000056, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f33);
	
	$display("BangCam: R2 = 0x00000055, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f2b);
	
	$display("BangCam: R2 = 0x00000054, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f23);
	
	$display("BangCam: R2 = 0x00000053, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f1b);
	
	$display("BangCam: R2 = 0x00000052, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f13);
	
	$display("BangCam: R2 = 0x00000051, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f0b);
	
	$display("BangCam: R2 = 0x00000050, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f03);
	
	$display("BangCam: R2 = 0x0000004f, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f7a);
	
	$display("BangCam: R2 = 0x0000004e, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f72);
	
	$display("BangCam: R2 = 0x0000004d, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f6a);
	
	$display("BangCam: R2 = 0x0000004c, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f62);
	
	$display("BangCam: R2 = 0x0000004b, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f5a);
	
	$display("BangCam: R2 = 0x0000004a, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f52);
	
	$display("BangCam: R2 = 0x00000049, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f4a);
	
	$display("BangCam: R2 = 0x00000048, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f42);
	
	$display("BangCam: R2 = 0x00000047, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f3a);
	
	$display("BangCam: R2 = 0x00000046, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f32);
	
	$display("BangCam: R2 = 0x00000045, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f2a);
	
	$display("BangCam: R2 = 0x00000044, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f22);
	
	$display("BangCam: R2 = 0x00000043, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f1a);
	
	$display("BangCam: R2 = 0x00000042, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f12);
	
	$display("BangCam: R2 = 0x00000041, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f0a);
	
	$display("BangCam: R2 = 0x00000040, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f02);
	
	$display("BangCam: R2 = 0x0000003f, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f7d);
	
	$display("BangCam: R2 = 0x0000003e, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f75);
	
	$display("BangCam: R2 = 0x0000003d, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f6d);
	
	$display("BangCam: R2 = 0x0000003c, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f65);
	
	$display("BangCam: R2 = 0x0000003b, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f5d);
	
	$display("BangCam: R2 = 0x0000003a, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f55);
	
	$display("BangCam: R2 = 0x00000039, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f4d);
	
	$display("BangCam: R2 = 0x00000038, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f45);
	
	$display("BangCam: R2 = 0x00000037, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f3d);
	
	$display("BangCam: R2 = 0x00000036, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f35);
	
	$display("BangCam: R2 = 0x00000035, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f2d);
	
	$display("BangCam: R2 = 0x00000034, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f25);
	
	$display("BangCam: R2 = 0x00000033, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f1d);
	
	$display("BangCam: R2 = 0x00000032, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f15);
	
	$display("BangCam: R2 = 0x00000031, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f0d);
	
	$display("BangCam: R2 = 0x00000030, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f05);
	
	$display("BangCam: R2 = 0x0000002f, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f7c);
	
	$display("BangCam: R2 = 0x0000002e, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f74);
	
	$display("BangCam: R2 = 0x0000002d, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f6c);
	
	$display("BangCam: R2 = 0x0000002c, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f64);
	
	$display("BangCam: R2 = 0x0000002b, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f5c);
	
	$display("BangCam: R2 = 0x0000002a, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f54);
	
	$display("BangCam: R2 = 0x00000029, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f4c);
	
	$display("BangCam: R2 = 0x00000028, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f44);
	
	$display("BangCam: R2 = 0x00000027, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f3c);
	
	$display("BangCam: R2 = 0x00000026, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f34);
	
	$display("BangCam: R2 = 0x00000025, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f2c);
	
	$display("BangCam: R2 = 0x00000024, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f24);
	
	$display("BangCam: R2 = 0x00000023, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f1c);
	
	$display("BangCam: R2 = 0x00000022, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f14);
	
	$display("BangCam: R2 = 0x00000021, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f0c);
	
	$display("BangCam: R2 = 0x00000020, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f04);
	
	$display("BangCam: R2 = 0x0000001f, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f79);
	
	$display("BangCam: R2 = 0x0000001e, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f71);
	
	$display("BangCam: R2 = 0x0000001d, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f69);
	
	$display("BangCam: R2 = 0x0000001c, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f61);
	
	$display("BangCam: R2 = 0x0000001b, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f59);
	
	$display("BangCam: R2 = 0x0000001a, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f51);
	
	$display("BangCam: R2 = 0x00000019, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f49);
	
	$display("BangCam: R2 = 0x00000018, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f41);
	
	$display("BangCam: R2 = 0x00000017, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f39);
	
	$display("BangCam: R2 = 0x00000016, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f31);
	
	$display("BangCam: R2 = 0x00000015, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f29);
	
	$display("BangCam: R2 = 0x00000014, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f21);
	
	$display("BangCam: R2 = 0x00000013, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f19);
	
	$display("BangCam: R2 = 0x00000012, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f11);
	
	$display("BangCam: R2 = 0x00000011, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f09);
	
	$display("BangCam: R2 = 0x00000010, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f01);
	
	$display("BangCam: R2 = 0x0000000f, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f78);
	
	$display("BangCam: R2 = 0x0000000e, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f70);
	
	$display("BangCam: R2 = 0x0000000d, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f68);
	
	$display("BangCam: R2 = 0x0000000c, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f60);
	
	$display("BangCam: R2 = 0x0000000b, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f58);
	
	$display("BangCam: R2 = 0x0000000a, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f50);
	
	$display("BangCam: R2 = 0x00000009, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f48);
	
	$display("BangCam: R2 = 0x00000008, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f40);
	
	$display("BangCam: R2 = 0x00000007, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f38);
	
	$display("BangCam: R2 = 0x00000006, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f30);
	
	$display("BangCam: R2 = 0x00000005, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f28);
	
	$display("BangCam: R2 = 0x00000004, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f20);
	
	$display("BangCam: R2 = 0x00000003, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f18);
	
	$display("BangCam: R2 = 0x00000002, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f10);
	
	$display("BangCam: R2 = 0x00000001, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f08);
	
	$display("BangCam: R2 = 0x00000000, R3 = 0x01f08000, R11 = 0x00000003");
	SetMEMC(32'h03f08f00);
	
	$display("BangCam: R2 = 0x0000000f, R3 = 0x01f00000, R11 = 0x00000001");
	SetMEMC(32'h03f00d78);
	
	$display("BangCam: R2 = 0x00000011, R3 = 0x01c00000, R11 = 0x00000000");
	SetMEMC(32'h03c00c09);
	
	$display("BangCam: R2 = 0x00000010, R3 = 0x00000000, R11 = 0x00000000");
	SetMEMC(32'h03800001);
	
	$display("BangCam: R2 = 0x00000000, R3 = 0x01fb0000, R11 = 0x00000000");
	SetMEMC(32'h03fb0c00);
	
	$display("BangCam: R2 = 0x00000001, R3 = 0x01fb8000, R11 = 0x00000000");
	SetMEMC(32'h03fb8c08);
	
	$display("BangCam: R2 = 0x00000002, R3 = 0x01fc0000, R11 = 0x00000000");
	SetMEMC(32'h03fc0c10);
	
	$display("BangCam: R2 = 0x00000003, R3 = 0x01fc8000, R11 = 0x00000000");
	SetMEMC(32'h03fc8c18);
	
	$display("BangCam: R2 = 0x00000004, R3 = 0x01fd0000, R11 = 0x00000000");
	SetMEMC(32'h03fd0c20);
	
	$display("BangCam: R2 = 0x00000005, R3 = 0x01fd8000, R11 = 0x00000000");
	SetMEMC(32'h03fd8c28);
	
	$display("BangCam: R2 = 0x00000006, R3 = 0x01fe0000, R11 = 0x00000000");
	SetMEMC(32'h03fe0c30);
	
	$display("BangCam: R2 = 0x00000007, R3 = 0x01fe8000, R11 = 0x00000000");
	SetMEMC(32'h03fe8c38);
	
	$display("BangCam: R2 = 0x00000008, R3 = 0x01ff0000, R11 = 0x00000000");
	SetMEMC(32'h03ff0c40);
	
	$display("BangCam: R2 = 0x00000009, R3 = 0x01ff8000, R11 = 0x00000000");
	SetMEMC(32'h03ff8c48);
	
	$display("BangCam: R2 = 0x0000000a, R3 = 0x01800000, R11 = 0x00000000");
	SetMEMC(32'h03800c50);
	
	$display("BangCam: R2 = 0x0000000b, R3 = 0x01e00000, R11 = 0x00000002");
	SetMEMC(32'h03e00e58);
	
	$display("BangCam: R2 = 0x0000000c, R3 = 0x01e08000, R11 = 0x00000002");
	SetMEMC(32'h03e08e60);
	
	$display("BangCam: R2 = 0x0000000d, R3 = 0x01e10000, R11 = 0x00000002");
	SetMEMC(32'h03e10e68);
	
	$display("BangCam: R2 = 0x0000000e, R3 = 0x01e18000, R11 = 0x00000002");
	SetMEMC(32'h03e18e70);
	
	$display("BangCam: R2 = 0x00000012, R3 = 0x00008000, R11 = 0x00000000");
	SetMEMC(32'h03808011);
	
	$display("BangCam: R2 = 0x00000013, R3 = 0x00010000, R11 = 0x00000000");
	SetMEMC(32'h03810019);
	
	$display("BangCam: R2 = 0x00000014, R3 = 0x00018000, R11 = 0x00000000");
	SetMEMC(32'h03818021);
	
	$display("BangCam: R2 = 0x00000015, R3 = 0x00020000, R11 = 0x00000000");
	SetMEMC(32'h03820029);
	
	$display("BangCam: R2 = 0x00000016, R3 = 0x00028000, R11 = 0x00000000");
	SetMEMC(32'h03828031);
	
	$display("BangCam: R2 = 0x00000017, R3 = 0x00030000, R11 = 0x00000000");
	SetMEMC(32'h03830039);
	
	$display("BangCam: R2 = 0x00000018, R3 = 0x00038000, R11 = 0x00000000");
	SetMEMC(32'h03838041);
	
	$display("BangCam: R2 = 0x00000019, R3 = 0x00040000, R11 = 0x00000000");
	SetMEMC(32'h03840049);
	
	$display("BangCam: R2 = 0x0000001a, R3 = 0x00048000, R11 = 0x00000000");
	SetMEMC(32'h03848051);
	
	$display("BangCam: R2 = 0x0000001b, R3 = 0x00050000, R11 = 0x00000000");
	SetMEMC(32'h03850059);
	
	$display("BangCam: R2 = 0x0000001c, R3 = 0x00058000, R11 = 0x00000000");
	SetMEMC(32'h03858061);
	
	$display("BangCam: R2 = 0x0000001d, R3 = 0x00060000, R11 = 0x00000000");
	SetMEMC(32'h03860069);
	
	$display("BangCam: R2 = 0x0000001e, R3 = 0x00068000, R11 = 0x00000000");
	SetMEMC(32'h03868071);
	
	$display("BangCam: R2 = 0x0000001f, R3 = 0x00070000, R11 = 0x00000000");
	SetMEMC(32'h03870079);
	
	$display("BangCam: R2 = 0x00000020, R3 = 0x00078000, R11 = 0x00000000");
	SetMEMC(32'h03878004);
	
	$display("BangCam: R2 = 0x00000021, R3 = 0x00080000, R11 = 0x00000000");
	SetMEMC(32'h0388000c);
	
	$display("BangCam: R2 = 0x00000022, R3 = 0x00088000, R11 = 0x00000000");
	SetMEMC(32'h03888014);
	
	$display("BangCam: R2 = 0x00000023, R3 = 0x00090000, R11 = 0x00000000");
	SetMEMC(32'h0389001c);
	
	$display("BangCam: R2 = 0x00000024, R3 = 0x00098000, R11 = 0x00000000");
	SetMEMC(32'h03898024);
	
	$display("BangCam: R2 = 0x00000025, R3 = 0x000a0000, R11 = 0x00000000");
	SetMEMC(32'h038a002c);
	
	$display("BangCam: R2 = 0x00000026, R3 = 0x000a8000, R11 = 0x00000000");
	SetMEMC(32'h038a8034);
	
	$display("BangCam: R2 = 0x00000027, R3 = 0x000b0000, R11 = 0x00000000");
	SetMEMC(32'h038b003c);
	
	$display("BangCam: R2 = 0x00000028, R3 = 0x000b8000, R11 = 0x00000000");
	SetMEMC(32'h038b8044);
	
	$display("BangCam: R2 = 0x00000029, R3 = 0x000c0000, R11 = 0x00000000");
	SetMEMC(32'h038c004c);
	
	$display("BangCam: R2 = 0x0000002a, R3 = 0x000c8000, R11 = 0x00000000");
	SetMEMC(32'h038c8054);
	
	$display("BangCam: R2 = 0x0000002b, R3 = 0x000d0000, R11 = 0x00000000");
	SetMEMC(32'h038d005c);
	
	$display("BangCam: R2 = 0x0000002c, R3 = 0x000d8000, R11 = 0x00000000");
	SetMEMC(32'h038d8064);
	
	$display("BangCam: R2 = 0x0000002d, R3 = 0x000e0000, R11 = 0x00000000");
	SetMEMC(32'h038e006c);
	
	$display("BangCam: R2 = 0x0000002e, R3 = 0x000e8000, R11 = 0x00000000");
	SetMEMC(32'h038e8074);
	
	$display("BangCam: R2 = 0x0000002f, R3 = 0x000f0000, R11 = 0x00000000");
	SetMEMC(32'h038f007c);
	
	$display("BangCam: R2 = 0x00000030, R3 = 0x000f8000, R11 = 0x00000000");
	SetMEMC(32'h038f8005);
	
	$display("BangCam: R2 = 0x00000031, R3 = 0x00100000, R11 = 0x00000000");
	SetMEMC(32'h0390000d);
	
	$display("BangCam: R2 = 0x00000032, R3 = 0x00108000, R11 = 0x00000000");
	SetMEMC(32'h03908015);
	
	$display("BangCam: R2 = 0x00000033, R3 = 0x00110000, R11 = 0x00000000");
	SetMEMC(32'h0391001d);
	
	$display("BangCam: R2 = 0x00000034, R3 = 0x00118000, R11 = 0x00000000");
	SetMEMC(32'h03918025);
	
	$display("BangCam: R2 = 0x00000035, R3 = 0x00120000, R11 = 0x00000000");
	SetMEMC(32'h0392002d);
	
	$display("BangCam: R2 = 0x00000036, R3 = 0x00128000, R11 = 0x00000000");
	SetMEMC(32'h03928035);
	
	$display("BangCam: R2 = 0x00000037, R3 = 0x00130000, R11 = 0x00000000");
	SetMEMC(32'h0393003d);
	
	$display("BangCam: R2 = 0x00000038, R3 = 0x00138000, R11 = 0x00000000");
	SetMEMC(32'h03938045);
	
	$display("BangCam: R2 = 0x00000039, R3 = 0x00140000, R11 = 0x00000000");
	SetMEMC(32'h0394004d);
	
	$display("BangCam: R2 = 0x0000003a, R3 = 0x00148000, R11 = 0x00000000");
	SetMEMC(32'h03948055);
	
	$display("BangCam: R2 = 0x0000003b, R3 = 0x00150000, R11 = 0x00000000");
	SetMEMC(32'h0395005d);
	
	$display("BangCam: R2 = 0x0000003c, R3 = 0x00158000, R11 = 0x00000000");
	SetMEMC(32'h03958065);
	
	$display("BangCam: R2 = 0x0000003d, R3 = 0x00160000, R11 = 0x00000000");
	SetMEMC(32'h0396006d);
	
	$display("BangCam: R2 = 0x0000003e, R3 = 0x00168000, R11 = 0x00000000");
	SetMEMC(32'h03968075);
	
	$display("BangCam: R2 = 0x0000003f, R3 = 0x00170000, R11 = 0x00000000");
	SetMEMC(32'h0397007d);
	
	$display("BangCam: R2 = 0x00000040, R3 = 0x00178000, R11 = 0x00000000");
	SetMEMC(32'h03978002);
	
	$display("BangCam: R2 = 0x00000041, R3 = 0x00180000, R11 = 0x00000000");
	SetMEMC(32'h0398000a);
	
	$display("BangCam: R2 = 0x00000042, R3 = 0x00188000, R11 = 0x00000000");
	SetMEMC(32'h03988012);
	
	$display("BangCam: R2 = 0x00000043, R3 = 0x00190000, R11 = 0x00000000");
	SetMEMC(32'h0399001a);
	
	$display("BangCam: R2 = 0x00000044, R3 = 0x00198000, R11 = 0x00000000");
	SetMEMC(32'h03998022);
	
	$display("BangCam: R2 = 0x00000045, R3 = 0x001a0000, R11 = 0x00000000");
	SetMEMC(32'h039a002a);
	
	$display("BangCam: R2 = 0x00000046, R3 = 0x001a8000, R11 = 0x00000000");
	SetMEMC(32'h039a8032);
	
	$display("BangCam: R2 = 0x00000047, R3 = 0x001b0000, R11 = 0x00000000");
	SetMEMC(32'h039b003a);
	
	$display("BangCam: R2 = 0x00000048, R3 = 0x001b8000, R11 = 0x00000000");
	SetMEMC(32'h039b8042);
	
	$display("BangCam: R2 = 0x00000049, R3 = 0x001c0000, R11 = 0x00000000");
	SetMEMC(32'h039c004a);
	
	$display("BangCam: R2 = 0x0000004a, R3 = 0x001c8000, R11 = 0x00000000");
	SetMEMC(32'h039c8052);
	
	$display("BangCam: R2 = 0x0000004b, R3 = 0x001d0000, R11 = 0x00000000");
	SetMEMC(32'h039d005a);
	
	$display("BangCam: R2 = 0x0000004c, R3 = 0x001d8000, R11 = 0x00000000");
	SetMEMC(32'h039d8062);
	
	$display("BangCam: R2 = 0x0000004d, R3 = 0x001e0000, R11 = 0x00000000");
	SetMEMC(32'h039e006a);
	
	$display("BangCam: R2 = 0x0000004e, R3 = 0x001e8000, R11 = 0x00000000");
	SetMEMC(32'h039e8072);
	
	$display("BangCam: R2 = 0x0000004f, R3 = 0x001f0000, R11 = 0x00000000");
	SetMEMC(32'h039f007a);
	
	$display("BangCam: R2 = 0x00000050, R3 = 0x001f8000, R11 = 0x00000000");
	SetMEMC(32'h039f8003);
	
	$display("BangCam: R2 = 0x00000051, R3 = 0x00200000, R11 = 0x00000000");
	SetMEMC(32'h03a0000b);
	
	$display("BangCam: R2 = 0x00000052, R3 = 0x00208000, R11 = 0x00000000");
	SetMEMC(32'h03a08013);
	
	$display("BangCam: R2 = 0x00000053, R3 = 0x00210000, R11 = 0x00000000");
	SetMEMC(32'h03a1001b);
	
	$display("BangCam: R2 = 0x00000054, R3 = 0x00218000, R11 = 0x00000000");
	SetMEMC(32'h03a18023);
	
	$display("BangCam: R2 = 0x00000055, R3 = 0x00220000, R11 = 0x00000000");
	SetMEMC(32'h03a2002b);
	
	$display("BangCam: R2 = 0x00000056, R3 = 0x00228000, R11 = 0x00000000");
	SetMEMC(32'h03a28033);
	
	$display("BangCam: R2 = 0x00000057, R3 = 0x00230000, R11 = 0x00000000");
	SetMEMC(32'h03a3003b);
	
	$display("BangCam: R2 = 0x00000058, R3 = 0x00238000, R11 = 0x00000000");
	SetMEMC(32'h03a38043);
	
	$display("BangCam: R2 = 0x00000059, R3 = 0x00240000, R11 = 0x00000000");
	SetMEMC(32'h03a4004b);
	
	$display("BangCam: R2 = 0x0000005a, R3 = 0x00248000, R11 = 0x00000000");
	SetMEMC(32'h03a48053);
	
	$display("BangCam: R2 = 0x0000005b, R3 = 0x00250000, R11 = 0x00000000");
	SetMEMC(32'h03a5005b);
	
	$display("BangCam: R2 = 0x0000005c, R3 = 0x00258000, R11 = 0x00000000");
	SetMEMC(32'h03a58063);
	
	$display("BangCam: R2 = 0x0000005d, R3 = 0x00260000, R11 = 0x00000000");
	SetMEMC(32'h03a6006b);
	
	$display("BangCam: R2 = 0x0000005e, R3 = 0x00268000, R11 = 0x00000000");
	SetMEMC(32'h03a68073);
	
	$display("BangCam: R2 = 0x0000005f, R3 = 0x00270000, R11 = 0x00000000");
	SetMEMC(32'h03a7007b);
	
	$display("BangCam: R2 = 0x00000060, R3 = 0x00278000, R11 = 0x00000000");
	SetMEMC(32'h03a78006);
	
	$display("BangCam: R2 = 0x00000061, R3 = 0x00280000, R11 = 0x00000000");
	SetMEMC(32'h03a8000e);
	
	$display("BangCam: R2 = 0x00000062, R3 = 0x00288000, R11 = 0x00000000");
	SetMEMC(32'h03a88016);
	
	$display("BangCam: R2 = 0x00000063, R3 = 0x00290000, R11 = 0x00000000");
	SetMEMC(32'h03a9001e);
	
	$display("BangCam: R2 = 0x00000064, R3 = 0x00298000, R11 = 0x00000000");
	SetMEMC(32'h03a98026);
	
	$display("BangCam: R2 = 0x00000065, R3 = 0x002a0000, R11 = 0x00000000");
	SetMEMC(32'h03aa002e);
	
	$display("BangCam: R2 = 0x00000066, R3 = 0x002a8000, R11 = 0x00000000");
	SetMEMC(32'h03aa8036);
	
	$display("BangCam: R2 = 0x00000067, R3 = 0x002b0000, R11 = 0x00000000");
	SetMEMC(32'h03ab003e);
	
	$display("BangCam: R2 = 0x00000068, R3 = 0x002b8000, R11 = 0x00000000");
	SetMEMC(32'h03ab8046);
	
	$display("BangCam: R2 = 0x00000069, R3 = 0x002c0000, R11 = 0x00000000");
	SetMEMC(32'h03ac004e);
	
	$display("BangCam: R2 = 0x0000006a, R3 = 0x002c8000, R11 = 0x00000000");
	SetMEMC(32'h03ac8056);
	
	$display("BangCam: R2 = 0x0000006b, R3 = 0x002d0000, R11 = 0x00000000");
	SetMEMC(32'h03ad005e);
	
	$display("BangCam: R2 = 0x0000006c, R3 = 0x002d8000, R11 = 0x00000000");
	SetMEMC(32'h03ad8066);
	
	$display("BangCam: R2 = 0x0000006d, R3 = 0x002e0000, R11 = 0x00000000");
	SetMEMC(32'h03ae006e);
	
	$display("BangCam: R2 = 0x0000006e, R3 = 0x002e8000, R11 = 0x00000000");
	SetMEMC(32'h03ae8076);
	
	$display("BangCam: R2 = 0x0000006f, R3 = 0x002f0000, R11 = 0x00000000");
	SetMEMC(32'h03af007e);
	
	$display("BangCam: R2 = 0x00000070, R3 = 0x002f8000, R11 = 0x00000000");
	SetMEMC(32'h03af8007);
	
	$display("BangCam: R2 = 0x00000071, R3 = 0x00300000, R11 = 0x00000000");
	SetMEMC(32'h03b0000f);
	
	$display("BangCam: R2 = 0x00000072, R3 = 0x00308000, R11 = 0x00000000");
	SetMEMC(32'h03b08017);
	
	$display("BangCam: R2 = 0x00000073, R3 = 0x00310000, R11 = 0x00000000");
	SetMEMC(32'h03b1001f);
	
	$display("BangCam: R2 = 0x00000074, R3 = 0x00318000, R11 = 0x00000000");
	SetMEMC(32'h03b18027);
	
	$display("BangCam: R2 = 0x00000075, R3 = 0x00320000, R11 = 0x00000000");
	SetMEMC(32'h03b2002f);
	
	$display("BangCam: R2 = 0x00000076, R3 = 0x00328000, R11 = 0x00000000");
	SetMEMC(32'h03b28037);
	
	$display("BangCam: R2 = 0x00000077, R3 = 0x00330000, R11 = 0x00000000");
	SetMEMC(32'h03b3003f);
	
	$display("BangCam: R2 = 0x00000078, R3 = 0x00338000, R11 = 0x00000000");
	SetMEMC(32'h03b38047);
	
	$display("BangCam: R2 = 0x00000079, R3 = 0x00340000, R11 = 0x00000000");
	SetMEMC(32'h03b4004f);
	
	$display("BangCam: R2 = 0x0000007a, R3 = 0x00348000, R11 = 0x00000000");
	SetMEMC(32'h03b48057);
	
	$display("BangCam: R2 = 0x0000007b, R3 = 0x00350000, R11 = 0x00000000");
	SetMEMC(32'h03b5005f);
	
	$display("BangCam: R2 = 0x0000007c, R3 = 0x00358000, R11 = 0x00000000");
	SetMEMC(32'h03b58067);
	
	$display("BangCam: R2 = 0x0000007d, R3 = 0x00360000, R11 = 0x00000000");
	SetMEMC(32'h03b6006f);
	
	$display("BangCam: R2 = 0x0000007e, R3 = 0x00368000, R11 = 0x00000000");
	SetMEMC(32'h03b68077);
	
	$display("BangCam: R2 = 0x0000007f, R3 = 0x00370000, R11 = 0x00000000");
	SetMEMC(32'h03b7007f);

	CheckSPVMD(32'h01F01350, 1);

	CheckOSMD(32'h01F01350, 0);
	
	CheckUser(32'h01F01350, 0);
	
	
	#60;
	$finish();

	end

	always 	begin
	   #15; CLK32M = ~CLK32M;
	end
      
endmodule

