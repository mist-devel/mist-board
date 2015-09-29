//  SAA5050 teletext generator
//
//  Synchronous implementation for FPGA.  Certain TV-specific functions are
//  not implemented.  e.g.
//
//  No /SI pin - 'TEXT' mode is permanently enabled
//  No remote control features (/DATA, DLIM)
//  No large character support
//  No support for box overlay (BLAN, PO, DE)
//
//  FIXME: Hold graphics not supported - this needs to be added
//
//  Copyright (c) 2011 Mike Stirling
//  Copyright (c) 2015 Stephen J. Leary (sleary@vavi.co.uk)
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

module saa5050 (
           CLOCK,
           CLKEN,
           PIXCLKEN,
           nRESET,
           DI_CLOCK,
           DI_CLKEN,
           DI,
           GLR,
           DEW,
           CRS,
           LOSE,    
		   R,
           G,
           B,
           Y);


input CLOCK;
input CLKEN;
input PIXCLKEN; 
input nRESET;
input DI_CLOCK;
input DI_CLKEN;
input [6: 0] DI;
input GLR;
input DEW;
input CRS;
input LOSE;
output R;
output G;
output B;
output Y;

//  6 MHz dot clock enable

reg R;
reg G;
reg B;
reg Y;

//  Register inputs in the bus clock domain
reg [6: 0] di_r;
reg dew_r;
reg lose_r;

//  Data input registered in the pixel clock domain
reg [6: 0] code;
wire [3: 0] line_addr;
wire [11: 0] rom_address;
wire [7: 0] rom_data;
wire    [3:0] line_addr_cmp; 
wire    [3:0] line_addr_p1; 
wire    [3:0] line_addr_m1; 
wire    [11:0] rom_address_cmp; 
wire    [7:0] rom_data_cmp; 
//  Delayed display enable derived from LOSE by delaying for one character
reg disp_enable;

//  Latched timing signals for detection of falling edges
reg dew_latch;
reg lose_latch;
reg disp_enable_latch;

//  Row and column addressing is handled externally.  We just need to
//  keep track of which of the 10 lines we are on within the character...
reg [3: 0] line_counter;

//  ... and which of the 6 pixels we are on within each line
reg [2: 0] pixel_counter;

//  We also need to count frames to implement the flash feature.
//  The datasheet says this is 0.75 Hz with a 3:1 on/off ratio, so it
//  is probably a /64 counter, which gives us 0.78 Hz
reg [5: 0] flash_counter;

//  Output shift register
reg     odd_pixel; 
reg     shift_reg_last;
reg [5: 0] shift_reg;
reg     shift_reg_cmp_last; 
reg     [5:0] shift_reg_cmp; 

//  Flash mask
wire flash;

//  Current display state
//  Foreground colour (B2, G1, R0)
reg [2: 0] fg;

//  Background colour (B2, G1, R0)
reg [2: 0] bg;
reg conceal;
reg gfx;
reg gfx_sep;
reg gfx_hold;
reg is_flash;
reg double_high;

//  Set in first row of double height
reg double_high1;

//  Set in second row of double height
reg double_high2;

saa5050_rom char_rom (.address(rom_address),
                      .clock(CLOCK),
                      .q(rom_data));
assign flash = flash_counter[5] & flash_counter[4];
//  Generate flash signal for 3:1 ratio
//  Sync inputs

always @(posedge DI_CLOCK) begin

    if (nRESET === 1'b 0) begin
        di_r <= {7{1'b 0}};
        dew_r <= 1'b 0;
        lose_r <= 1'b 0;
    
    end else if (DI_CLKEN === 1'b 1 ) begin
        di_r <= DI;
        dew_r <= DEW;
        lose_r <= LOSE;
    end
end

//  Register data into pixel clock domain

always @(posedge CLOCK) begin

    if (nRESET === 1'b 0) begin
        code <= {7{1'b 0}};
    
    end else if (CLKEN === 1'b 1 ) begin
        code <= di_r;
    end
end

//  Generate character rom address in pixel clock domain
//  This is done combinatorially since all the inputs are already
//  registered and the address is re-registered by the ROM
assign line_addr = double_high === 1'b 0 ? line_counter :
       double_high2 === 1'b 0 ? {1'b 0, line_counter[3 : 1]} :
       {1'b 0, line_counter[3 : 1]} + 4'd5;
assign rom_address = double_high === 1'b 0 & double_high2 === 1'b 1 ? {12{1'b 0}} :
       {gfx, code, line_addr};
assign line_addr_p1 = double_high === 1'b 0 ? line_counter + 1 :
       double_high2 === 1'b 0 ? {1'b 0, line_counter[3:1]} + 1 :
       {1'b 0, line_counter[3:1]} + 1 + 5;
assign line_addr_m1 = double_high === 1'b 0 ? line_counter - 1 :
       double_high2 === 1'b 0 ? {1'b 0, line_counter[3:1]} - 1 :
       {1'b 0, line_counter[3:1]} - 1 + 5;
assign line_addr_cmp = CRS === 1'b 1 ? line_addr_p1 :
       line_addr_m1;
assign rom_address_cmp = double_high === 1'b 0 & double_high2 === 1'b 1 ? {12{1'b 0}} :
       {gfx, code, line_addr_cmp};

//  Character row and pixel counters

always @(posedge CLOCK) begin

    if (nRESET === 1'b 0) begin
        dew_latch <= 1'b 0;
        lose_latch <= 1'b 0;
        disp_enable <= 1'b 0;
        disp_enable_latch <= 1'b 0;
        double_high1 <= 1'b 0;
        double_high2 <= 1'b 0;
        line_counter <= {4{1'b 0}};
        pixel_counter <= {3{1'b 0}};
        flash_counter <= {6{1'b 0}};
    
    end else if (CLKEN === 1'b 1 ) begin

        //  Register syncs for edge detection
        dew_latch <= dew_r;
        lose_latch <= lose_r;
        disp_enable_latch <= disp_enable;

        //  When first entering double-height mode start on top row
        if (double_high === 1'b 1 & double_high1 === 1'b 0 &
                double_high2 === 1'b 0) begin
            double_high1 <= 1'b 1;
        end

        //  Count pixels between 0 and 5
        if (pixel_counter === 5) begin

            //  Start of next character and delayed display enable
            pixel_counter <= {3{1'b 0}};
            disp_enable <= lose_latch;
        
        end else begin
            pixel_counter <= pixel_counter + 1;
        end

        //  Rising edge of LOSE is the start of the active line
        if (lose_r === 1'b 1 & lose_latch === 1'b 0) begin

            //  Reset pixel counter - small offset to make the output
            //  line up with the cursor from the video ULA
            pixel_counter <= 3'b 011;
        end

        //  Count frames on end of VSYNC (falling edge of DEW)
        if (dew_r === 1'b 0 & dew_latch === 1'b 1) begin
            flash_counter <= flash_counter + 1;
        end

        if (dew_r === 1'b 1) begin

            //  Reset line counter and double height state during VSYNC
            line_counter <= {4{1'b 0}};
            double_high1 <= 1'b 0;
            double_high2 <= 1'b 0;

            //  Count lines on end of active video (falling edge of disp_enable)
        
        end else begin
            if (disp_enable === 1'b 0 & disp_enable_latch === 1'b 1) begin
                if (line_counter === 9) begin
                    line_counter <= {4{1'b 0}};

                    //  Keep track of which row we are on for double-height
                    //  The double_high flag can be cleared before the end of a row, but if
                    //  double height characters are used anywhere on a row then the double_high1
                    //  flag will be set and remain set until the next row.  This is used
                    //  to determine that the bottom half of the characters should be shown if
                    //  double_high is set once again on the row below.
                    double_high1 <= 1'b 0;
                    double_high2 <= double_high1;
                end
                else begin
                    line_counter <= line_counter + 1;
                end
            end
        end
    end
end

//  Shift register

always @(posedge CLOCK) begin

    if (nRESET === 1'b 0) begin
	 
        shift_reg <= {6{1'b 0}};
    
    end else if (CLKEN === 1'b 1 ) begin
        
        if (disp_enable === 1'b 1 & pixel_counter === 0) begin

            //  Load the shift register with the ROM bit pattern
            //  at the start of each character while disp_enable is asserted.
            shift_reg <= rom_data[5: 0];
            shift_reg_cmp <= rom_data_cmp[5:0];

            //  If bit 7 of the ROM data is set then this is a graphics
            //  character and separated/hold graphics modes apply.
            //  We don't just assume this to be the case if gfx=1 because
            //  these modes don't apply to caps even in graphics mode
            if (rom_data[7] === 1'b 1) begin

                //  Apply a mask for separated graphics mode
                if (gfx_sep === 1'b 1) begin
                    shift_reg[5] <= 1'b 0;
                    shift_reg[2] <= 1'b 0;

                    if (line_counter === 2 | line_counter === 6 |
                            line_counter === 9) begin
                        shift_reg <= {6{1'b 0}};
                    end
                end
            end

			if (rom_data_cmp[7] === 1'b 1) begin
			
                //  Apply a mask for separated graphics mode
                if (gfx_sep === 1'b 1) begin
                    shift_reg_cmp[5] <= 1'b 0;
                    shift_reg_cmp[2] <= 1'b 0;

                    if (line_counter === 1 | line_counter === 5 |
                            line_counter === 8) begin
                        shift_reg_cmp <= {6{1'b 0}};
                    end
                end
            end            //  Pump the shift register
        end else begin
			shift_reg_last <= shift_reg[5];
            shift_reg <= {shift_reg[4: 0], 1'b 0};
			shift_reg_cmp_last <= shift_reg_cmp[5];
            shift_reg_cmp <= {shift_reg_cmp[4:0], 1'b 0};
        end
    end
end

//  Control character handling

always @(posedge CLOCK) begin

    if (nRESET === 1'b 0) begin
        fg <= {3{1'b 1}};
        bg <= {3{1'b 0}};
        conceal <= 1'b 0;
        gfx <= 1'b 0;
        gfx_sep <= 1'b 0;
        gfx_hold <= 1'b 0;
        is_flash <= 1'b 0;
        double_high <= 1'b 0;
    
    end else if (CLKEN === 1'b 1 ) begin
        
        if (disp_enable === 1'b 0) begin

            //  Reset to start of line defaults
            fg <= 3'b111;
            bg <= 'd0;
            conceal <= 1'b 0;
            gfx <= 1'b 0;
            gfx_sep <= 1'b 0;
            gfx_hold <= 1'b 0;
            is_flash <= 1'b 0;
            double_high <= 1'b 0;
        
        end else if (pixel_counter === 0 ) begin

            //  Latch new control codes at the start of each character
            if (code[6: 5] === 2'b 00) begin
				
                if (code[3] === 1'b 0) begin

                    //  Colour and graphics setting clears conceal mode
                    conceal <= 1'b 0;

                    //  Select graphics or alpha mode
                    gfx <= code[4];

                    //  0 would be black but is not allowed so has no effect,
                    //  otherwise set the colour
                    if (code[2: 0] !== 3'b 000) begin
                        fg <= code[2: 0];
                    end
                
                end else begin
                
                    case (code[4: 0])
						  
                        5'b 01000: is_flash <= 1'b1; 		//  FLASH
                        5'b 01001: is_flash <= 1'b0; 		//  STEADY
                        5'b 01100: double_high <= 1'b0; 	//  NORMAL HEIGHT
                        5'b 01101: double_high <= 1'b1; 	//  DOUBLE HEIGHT
                        5'b 11000: conceal <= 1'b1; 		//  CONCEAL
                        5'b 11001: gfx_sep <= 1'b0; 		//  CONTIGUOUS GFX
                        5'b 11010: gfx_sep <= 1'b1; 		//  SEPARATED GFX
                        5'b 11100: bg <= 'd0; 				//  BLACK BACKGROUND
                        5'b 11101: bg <= fg; 				//  NEW BACKGROUND
                        5'b 11110: gfx_hold <= 1'b1; 		//  HOLD GFX
                        5'b 11111: gfx_hold <= 1'b0; 		//  RELEASE GFX

                    endcase
                    
                end
            end
        end
    end
end

//  Output pixel calculation.
wire  pixel = 	double_high === 1'b 1 ?	 shift_reg[5] & ~(flash & is_flash | conceal) : 
				odd_pixel 	=== 1'b 0 ?	 (shift_reg[5] | shift_reg_cmp[5] & shift_reg[4] & ~shift_reg_cmp[4]) &  ~(flash & is_flash | conceal) :
										 (shift_reg[5] | shift_reg_cmp[5] & shift_reg_last & ~shift_reg_cmp_last) & ~(flash & is_flash | conceal);
				
always @(posedge CLOCK) begin

    if (nRESET === 1'b 0) begin

        R <= 1'b 0;
        G <= 1'b 0;
        B <= 1'b 0;

    end else if (PIXCLKEN === 1'b 1 ) begin

        //  Generate mono output
        Y <= pixel;
        odd_pixel <= ~odd_pixel;

        //  Generate colour output
        if (pixel === 1'b 1) begin

            R <= fg[0];
            G <= fg[1];
            B <= fg[2];

        end else begin

            R <= bg[0];
            G <= bg[1];
            B <= bg[2];

        end

    end
    
end

endmodule // module saa5050

