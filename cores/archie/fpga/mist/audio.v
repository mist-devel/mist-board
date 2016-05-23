//
// audio.v
// 
// Archie audio subsystem implementation for the MiST board
// http://code.google.com/p/mist-board/
// 
// Copyright (c) 2015 Stephen Leary <stephen@vavi.co.uk> 
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

module audio(
	input  	rst,
	input 	clk,      // 32 MHz

	input	[15:0] audio_data_r,
	input	[15:0] audio_data_l,
	
	output 	audio_r,
	output 	audio_l
);

sigma_delta_dac sigma_delta_dac_l (
	.DACout 		(audio_l),
	.DACin		(audio_data_l[15:0]),
	.CLK 			(clk),
	.RESET 		(rst)
);

sigma_delta_dac sigma_delta_dac_r (
	.DACout     (audio_r),
	.DACin    	(audio_data_r[15:0]),
	.CLK      	(clk),
	.RESET    	(rst)
);

endmodule