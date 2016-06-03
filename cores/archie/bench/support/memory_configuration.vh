//////////////////////////////////////////////////////////////////
//                                                              //
//  Memory configuration and Wishbone address decoding          //
//                                                              //
//  This file is part of the Amber project                      //
//  http://www.opencores.org/project,amber                      //
//                                                              //
//  Description                                                 //
//  This module provides a set of functions that are used to    //
//  decode memory addresses so other modules know if an address //
//  is for example in main memory, or boot memory, or a UART    //
//                                                              //
//  Author(s):                                                  //
//      - Conor Santifort, csantifort.amber@gmail.com           //
//                                                              //
//////////////////////////////////////////////////////////////////
//                                                              //
// Copyright (C) 2010 Authors and OPENCORES.ORG                 //
//                                                              //
// This source file may be used and distributed without         //
// restriction provided that this copyright statement is not    //
// removed from the file and that any derivative work contains  //
// the original copyright notice and the associated disclaimer. //
//                                                              //
// This source file is free software; you can redistribute it   //
// and/or modify it under the terms of the GNU Lesser General   //
// Public License as published by the Free Software Foundation; //
// either version 2.1 of the License, or (at your option) any   //
// later version.                                               //
//                                                              //
// This source is distributed in the hope that it will be       //
// useful, but WITHOUT ANY WARRANTY; without even the implied   //
// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      //
// PURPOSE.  See the GNU Lesser General Public License for more //
// details.                                                     //
//                                                              //
// You should have received a copy of the GNU Lesser General    //
// Public License along with this source; if not, download it   //
// from http://www.opencores.org/lgpl.shtml                     //
//                                                              //
//////////////////////////////////////////////////////////////////

// e.g. 24 for 32MBytes, 26 for 128MBytes
localparam MAIN_MSB             = 26; 

// e.g. 13 for 4k words
localparam BOOT_MSB             = 13;  

localparam MAIN_BASE            	= 32'h0000_0000; /*  Main Memory            */
localparam PHYS_BASE            	= 32'h0200_0000; /*  Physical Memory        */
localparam IO_BASE            	= 32'h0300_0000; /*  Physical Memory        */
localparam ROM_BASE          		= 32'h0340_0000; /*  Uncachable Boot Memory */
localparam ROM_TOP          		= 32'h0400_0000; /*  Uncachable Boot Memory */

function in_rom_mem;
    input [31:0] address;
begin
in_rom_mem  =  (address >= ROM_BASE && 
					 address < (ROM_TOP));
end
endfunction


function in_main_mem;
    input [31:0] address;
begin
in_main_mem  = (address >= MAIN_BASE   && 
                address < (IO_BASE));
end
endfunction


// Used in fetch.v and l2cache.v to allow accesses to these addresses
// to be cached
function in_cachable_mem;
    input [31:0] address;
begin
    in_cachable_mem = 0; 
end
endfunction

