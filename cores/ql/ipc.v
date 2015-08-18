//
// ipc.v
//
// Sinclair QL for the MiST
// https://github.com/mist-devel
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

module ipc (
	input 		 reset,
	input        clk_sys,

	// synchronous serial connection
	output       comctrl,
	input        comdata_in,
	output       comdata_out,

	output       audio,
	output [1:0] ipl,

	input [4:0]  js0,
	input [4:0]  js1,
	
	input 		 ps2_kbd_clk,
	input 		 ps2_kbd_data
);

// ---------------------------------------------------------------------------------
// -------------------------------------- KBD --------------------------------------
// ---------------------------------------------------------------------------------

wire [63:0] kbd_matrix;

keyboard keyboard (
        .reset    ( reset        ),
        .clk      ( clk11        ),

        .ps2_clk  ( ps2_kbd_clk  ),
        .ps2_data ( ps2_kbd_data ),

		  .js0      ( js0          ),
		  .js1      ( js1          ),
		  
		  .matrix   ( kbd_matrix   )
);

// ---------------------------------------------------------------------------------
// ----------------------------------- 8049 clock ----------------------------------
// ---------------------------------------------------------------------------------

wire clk11;
wire pll_locked;
pll_ipc pll_ipc (
	 .inclk0 ( clk_sys    ),
	 .locked ( pll_locked ),
	 .c0     ( clk11      )           // 11 MHz
);

// make sure IPC clock is stable before it starts
wire ipc_reset = reset || !pll_locked;

// ---------------------------------------------------------------------------------
// -------------------------------------- 8049 -------------------------------------
// ---------------------------------------------------------------------------------

assign audio = t8049_p2_o[1];
assign ipl = t8049_p2_o[3:2];

wire [7:0] t8049_p1_o;
wire [7:0] t8049_db_i;

wire [7:0] t8049_p2_o;
wire [7:0] t8049_p2_i = { comdata_out && comdata_in, 7'b0000000 };

assign comdata_out = t8049_p2_o[7];

t8049_notri #(0) t8049 (
	.xtal_i    ( clk11      ),
   .xtal_en_i ( 1'b1       ),
   .reset_n_i ( !ipc_reset ),
	.t0_i      ( 1'b0       ),
   .t1_i      ( 1'b0       ),
   .int_n_i   ( 1'b1       ),
   .wr_n_o    ( comctrl    ),
   .ea_i      ( 1'b0       ),
   .db_i      ( t8049_db_i ),
   .p1_i      ( 8'h00      ),
   .p1_o      ( t8049_p1_o ),
   .p2_i      ( t8049_p2_i ),
   .p2_o      ( t8049_p2_o )
);

assign t8049_db_i = 
	(t8049_p1_o[0]?kbd_matrix[ 7: 0]:8'h00)|
	(t8049_p1_o[1]?kbd_matrix[15: 8]:8'h00)|
	(t8049_p1_o[2]?kbd_matrix[23:16]:8'h00)|
	(t8049_p1_o[3]?kbd_matrix[31:24]:8'h00)|
	(t8049_p1_o[4]?kbd_matrix[39:32]:8'h00)|
	(t8049_p1_o[5]?kbd_matrix[47:40]:8'h00)|
	(t8049_p1_o[6]?kbd_matrix[55:48]:8'h00)|
	(t8049_p1_o[7]?kbd_matrix[63:56]:8'h00);

endmodule
