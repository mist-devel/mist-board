`timescale 1 ns / 1 ns

//  BBC keyboard implementation with interface to PS/2
//
//  Copyright (c) 2011 Mike Stirling
//  Copyright (c) 2015 Stephen J. Leary
//
//  All rights reserved
//
//  Redistribution and use in source and synthezised forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//
//  * Redistributions in synthesized form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
//  * Neither the name of the author nor the names of other contributors may
//    be used to endorse or promote products derived from this software without
//    specific prior written agreement from the author.
//
//  * License is granted for non-commercial use only.  A fee may not be charged
//    for redistributions as source code or in synthesized/hardware form without
//    specific prior written agreement from the author.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
//  THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
//  PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//

module keyboard (

		input   CLOCK,
		input   nRESET,
		input   CLKEN_1MHZ,
		input   PS2_CLK,
		input   PS2_DATA,
		input   AUTOSCAN,
		input   [3:0] COLUMN,
		input   [2:0] ROW,
		output   KEYPRESS,
		output   INT,
		// external SHIFT key
		input    SHIFT,
		//  BREAK key output - 1 when pressed
		output reg  BREAK_OUT,
		//  DIP switch inputs
		input   [7:0] DIP_SWITCH 
);


//  Interface to PS/2 block
wire    [7:0] keyb_data;
wire    keyb_valid;
wire    keyb_error;

//  Internal signals
reg     [7:0] keys [0:15];
reg     [3:0] col;
reg     _release_;
reg     extended;
reg     ext_shift;

//  Shortcut to current key column

ps2_intf PS2 (
	.CLK		( CLOCK			),
    .nRESET		( nRESET		),
    .PS2_CLK	( PS2_CLK		),
    .PS2_DATA	( PS2_DATA		),

    .DATA		( keyb_data		),
    .VALID		( keyb_valid	)       
);

always @(posedge CLOCK) begin 

    if (nRESET === 1'b 0) begin

		col <= 'd0;;

    end else begin
        
		if (AUTOSCAN === 1'b 0) begin

            //  If autoscan disabled then transfer current COLUMN to counter
            //  immediately (don't wait for next 1 MHz cycle)
            col <= COLUMN;
			
        end  else if (CLKEN_1MHZ === 1'b 1 ) begin

            //  Otherwise increment the counter once per 1 MHz tick
            col <= col + 1'd1;
			
        end
    end
end

//  Generate interrupt if any key in currently scanned column is pressed
//  (apart from in row 0).  Output selected key status if autoscan disabled.

//  Column counts automatically when AUTOSCAN is enabled, otherwise
//  value is loaded from external input

wire [7:0] k = keys[col];
assign INT = k[7] | k[6] | k[5] | k[4] | k[3] | k[2] | k[1];
assign KEYPRESS = AUTOSCAN === 1'b0 ?  k[ROW] : 1'b0;

//  Decode PS/2 data

always @(posedge CLOCK) begin

    if (nRESET === 1'b 0) begin
	
        _release_ <= 1'b 0;
        extended <= 1'b 0;
        BREAK_OUT <= 1'b 0;
        keys[0] <= 'd0;
        keys[1] <= 'd0;
        keys[2] <= 'd0;
        keys[3] <= 'd0;
        keys[4] <= 'd0;
        keys[5] <= 'd0;
        keys[6] <= 'd0;
        keys[7] <= 'd0;
        keys[8] <= 'd0;
        keys[9] <= 'd0;

        //  These non-existent rows are used in the BBC master
        keys[10] <= 'd0;
        keys[11] <= 'd0;
        keys[12] <= 'd0;
        keys[13] <= 'd0;
        keys[14] <= 'd0;
        keys[15] <= 'd0;
		
    end else  begin

		  // map external shift key onto left shift
		  ext_shift <= SHIFT;
		  if(SHIFT || ext_shift)
				keys[0][0] <= SHIFT;

        //  Copy DIP switches through to row 0
        keys[2][0] <= DIP_SWITCH[7];
        keys[3][0] <= DIP_SWITCH[6];
        keys[4][0] <= DIP_SWITCH[5];
        keys[5][0] <= DIP_SWITCH[4];
        keys[6][0] <= DIP_SWITCH[3];
        keys[7][0] <= DIP_SWITCH[2];
        keys[8][0] <= DIP_SWITCH[1];
        keys[9][0] <= DIP_SWITCH[0];

        if (keyb_valid === 1'b 1) begin

            //  Decode keyboard input
            if (keyb_data === 8'h e0) begin

                //  Extended key code follows
                extended <= 1'b 1;

				end else if (keyb_data === 8'h f0 ) begin

                //  Release code follows
                _release_ <= 1'b 1;

                //  Cancel extended/release flags for next time
				
            end else if (extended === 1'b1) begin // Extended keys.
			
					_release_ <= 1'b 0;
					extended <= 1'b 0;
			
					//  PRNT SCRN is used for the BREAK key, which in the real BBC asserts
					//  reset.  Here we pass this out to the top level which may
					//  optionally OR it in to the system reset
					//  Decode scan codes
					
					case (keyb_data)	
					
						8'h 7c: BREAK_OUT <= ~_release_;   	 //  PRNT SCRN (BREAK)
						8'h 6B: keys[9][1] <= ~_release_;    //  LEFT
						8'h 72: keys[9][2] <= ~_release_;    //  DOWN
						8'h 75: keys[9][3] <= ~_release_;    //  UP
						8'h 74: keys[9][7] <= ~_release_;    //  RIGHT
						8'h 69: keys[9][6] <= ~_release_;    //  END (COPY)

					endcase
			
			end else begin 
			
                _release_ <= 1'b 0;
                extended <= 1'b 0;
				
                //  Decode scan codes
                case (keyb_data)
				
                    8'h 12: keys[0][0] <= ~_release_;    //  Left SHIFT
                    8'h 59: keys[0][0] <= ~_release_;    //  Right SHIFT
                    8'h 15: keys[0][1] <= ~_release_;    //  Q
                    8'h 09: keys[0][2] <= ~_release_;    //  F10 (F0)
                    8'h 16: keys[0][3] <= ~_release_;    //  1
                    8'h 58: keys[0][4] <= ~_release_;    //  CAPS LOCK
                    8'h 11: keys[0][5] <= ~_release_;    //  LEFT ALT (SHIFT LOCK)
                    8'h 0D: keys[0][6] <= ~_release_;    //  TAB
                    8'h 76: keys[0][7] <= ~_release_;    //  ESCAPE
                    8'h 14: keys[1][0] <= ~_release_;    //  LEFT/RIGHT CTRL (CTRL)
                    8'h 26: keys[1][1] <= ~_release_;    //  3
                    8'h 1D: keys[1][2] <= ~_release_;    //  W
                    8'h 1E: keys[1][3] <= ~_release_;    //  2
                    8'h 1C: keys[1][4] <= ~_release_;    //  A
                    8'h 1B: keys[1][5] <= ~_release_;    //  S
                    8'h 1A: keys[1][6] <= ~_release_;    //  Z
                    8'h 05: keys[1][7] <= ~_release_;    //  F1
                    8'h 25: keys[2][1] <= ~_release_;    //  4
                    8'h 24: keys[2][2] <= ~_release_;    //  E
                    8'h 23: keys[2][3] <= ~_release_;    //  D
                    8'h 22: keys[2][4] <= ~_release_;    //  X
                    8'h 21: keys[2][5] <= ~_release_;    //  C
                    8'h 29: keys[2][6] <= ~_release_;    //  SPACE
                    8'h 06: keys[2][7] <= ~_release_;    //  F2
                    8'h 2E: keys[3][1] <= ~_release_;    //  5
                    8'h 2C: keys[3][2] <= ~_release_;    //  T
                    8'h 2D: keys[3][3] <= ~_release_;    //  R
                    8'h 2B: keys[3][4] <= ~_release_;    //  F
                    8'h 34: keys[3][5] <= ~_release_;    //  G
                    8'h 2A: keys[3][6] <= ~_release_;    //  V
                    8'h 04: keys[3][7] <= ~_release_;    //  F3
                    8'h 0C: keys[4][1] <= ~_release_;    //  F4
                    8'h 3D: keys[4][2] <= ~_release_;    //  7
                    8'h 36: keys[4][3] <= ~_release_;    //  6
                    8'h 35: keys[4][4] <= ~_release_;    //  Y
                    8'h 33: keys[4][5] <= ~_release_;    //  H
                    8'h 32: keys[4][6] <= ~_release_;    //  B
                    8'h 03: keys[4][7] <= ~_release_;    //  F5
                    8'h 3E: keys[5][1] <= ~_release_;    //  8
                    8'h 43: keys[5][2] <= ~_release_;    //  I
                    8'h 3C: keys[5][3] <= ~_release_;    //  U
                    8'h 3B: keys[5][4] <= ~_release_;    //  J
                    8'h 31: keys[5][5] <= ~_release_;    //  N
                    8'h 3A: keys[5][6] <= ~_release_;    //  M
                    8'h 0B: keys[5][7] <= ~_release_;    //  F6
                    8'h 83: keys[6][1] <= ~_release_;    //  F7
                    8'h 46: keys[6][2] <= ~_release_;    //  9
                    8'h 44: keys[6][3] <= ~_release_;    //  O
                    8'h 42: keys[6][4] <= ~_release_;    //  K
                    8'h 4B: keys[6][5] <= ~_release_;    //  L
                    8'h 41: keys[6][6] <= ~_release_;    //  ,
                    8'h 0A: keys[6][7] <= ~_release_;    //  F8
                    8'h 4E: keys[7][1] <= ~_release_;    //  -
                    8'h 45: keys[7][2] <= ~_release_;    //  0
                    8'h 4D: keys[7][3] <= ~_release_;    //  P
                    8'h 0E: keys[7][4] <= ~_release_;    //  ` (@)
                    8'h 4C: keys[7][5] <= ~_release_;    //  ;
                    8'h 49: keys[7][6] <= ~_release_;    //  .
                    8'h 01: keys[7][7] <= ~_release_;    //  F9
                    8'h 55: keys[8][1] <= ~_release_;    //  = (^)
                    8'h 5D: keys[8][2] <= ~_release_;    //  # (_)
                    8'h 54: keys[8][3] <= ~_release_;    //  [
                    8'h 52: keys[8][4] <= ~_release_;    //  '
                    8'h 5B: keys[8][5] <= ~_release_;    //  ]
                    8'h 4A: keys[8][6] <= ~_release_;    //  /
                    8'h 61: keys[8][7] <= ~_release_;    //  \ 
                    8'h 5A: keys[9][4] <= ~_release_;    //  RETURN
                    8'h 66: keys[9][5] <= ~_release_;    //  BACKSPACE (DELETE)

                endcase
            end
        end
    end
end

endmodule // module keyboard

