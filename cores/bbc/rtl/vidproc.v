`timescale 1 ns / 1 ns
//  BBC Micro
//
//  Copyright (c) 2011 Mike Stirling
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
//  BBC Micro "VIDPROC" Video ULA
//
//  Synchronous implementation for FPGA
//
//  (C) 2011 Mike Stirling
//  (C) 2015 Stephen Leary

module vidproc (
           input   		CLOCK,
           input   		CLKEN,
           input   		nRESET,
           input      MHZ1_CLKEN, // sync to the clock generator
           output  		CLKEN_CRTC,
           input   		ENABLE,
           input   		A0,
           input [7:0] 	DI_CPU,
           input [7:0] 	DI_RAM,
           input   		nINVERT,
           input   		DISEN,
           input   		CURSOR,
           input  		 	R_IN,
           input   		G_IN,
           input   		B_IN,
           output reg 		R,
           output reg 		G,
           output reg 		B
       );

//  Clock enable qualifies display cycles (interleaved with CPU cycles)
reg     r0_cursor0;
reg     r0_cursor1;
reg     r0_cursor2;
reg     r0_crtc_2mhz;
reg     [1:0] r0_pixel_rate;
reg     r0_teletext;
reg     r0_flash;
reg     [3:0] palette [0:15];

//  Pixel shift register
reg     [7:0] shiftreg;

//  Delayed display enable
reg     delayed_disen1, delayed_disen2;

//  Internal clock enable generation
wire    clken_pixel;
wire    clken_fetch;
wire    mhz4_clken;
reg     [3:0] clken_counter;

//  Cursor generation - can span up to 32 pixels
//  Segments 0 and 1 are 8 pixels wide
//  Segment 2 is 16 pixels wide
wire    cursor_invert;
reg     cursor_invert_delayed;
reg     cursor_active;
reg     [1:0] cursor_counter;

//  Synchronous register access, enabled on every clock
integer  V2V_colour;

always @(posedge CLOCK) begin : process_1

    if (~nRESET) begin
        r0_cursor0 <= 1'b 0;
        r0_cursor1 <= 1'b 0;
        r0_cursor2 <= 1'b 0;
        r0_crtc_2mhz <= 1'b 0;
        r0_pixel_rate <= 2'b 00;
        r0_teletext <= 1'b 0;
        r0_flash <= 1'b 0;

        for (V2V_colour = 0; V2V_colour <= 15; V2V_colour = V2V_colour + 1) begin
            palette[V2V_colour] <= {4{1'b 0}};
        end
    end
    else begin
        if (ENABLE) begin
            if (A0 === 1'b 0) begin

                //  Access control register
                r0_cursor0 <= DI_CPU[7];
                r0_cursor1 <= DI_CPU[6];
                r0_cursor2 <= DI_CPU[5];
                r0_crtc_2mhz <= DI_CPU[4];
                r0_pixel_rate <= DI_CPU[3:2];
                r0_teletext <= DI_CPU[1];
                r0_flash <= DI_CPU[0];

                //  Access palette register
            end
            else begin
                palette[DI_CPU[7:4]] <= DI_CPU[3:0];
            end
        end
    end
end

//  Clock enable generation.
//  Pixel clock can be divided by 1,2,4 or 8 depending on the value
//  programmed at r0_pixel_rate
//  00 = /8, 01 = /4, 10 = /2, 11 = /1

assign clken_pixel = r0_pixel_rate === 2'b 11 ? CLKEN :
       r0_pixel_rate === 2'b 10 ? CLKEN & clken_counter[0] :
       r0_pixel_rate === 2'b 01 ? CLKEN & clken_counter[0] & clken_counter[1] :
       CLKEN & clken_counter[0] & clken_counter[1] & ~clken_counter[2];

//  The CRT controller is always enabled in the 15th cycle, so that the result
//  is ready for latching into the shift register in cycle 3.  If 2 MHz mode is
//  selected then the CRTC is also enabled in the 7th cycle
assign CLKEN_CRTC = CLKEN & clken_counter[0] & clken_counter[1] & clken_counter[2] &
       (clken_counter[3] | r0_crtc_2mhz);

//  The result is fetched from the RAM in cycle 11 and also cycle 3 if 2 MHz
//  mode is selected.  This is used for reloading the shift register as well as
//  counting cursor pixels
assign mhz4_clken = CLKEN & ~clken_counter[2] & clken_counter[1] & clken_counter[0];
assign clken_fetch = mhz4_clken & (~clken_counter[3] | r0_crtc_2mhz);

wire [7:0]  shiftreg_nxt = clken_fetch ? DI_RAM :
     clken_pixel ? {shiftreg[6:0], 1'b 1} : shiftreg;

always @(posedge CLOCK)  begin : process_2

    if (~nRESET) begin
        clken_counter <= 0;
    end
    else if (CLKEN) begin
        if (MHZ1_CLKEN)
            clken_counter <= 0;
        else
            //  Increment internal cycle counter during each video clock
            clken_counter <= clken_counter + 1'd1;
    end
end

//  Fetch control
always @(posedge CLOCK) begin : process_3

    if (~nRESET) begin
        shiftreg <= 0;
    end
    else begin
        shiftreg <= shiftreg_nxt;
    end
end

//  Cursor generation
assign cursor_invert = cursor_active & (r0_cursor0 & ~(cursor_counter[0] | cursor_counter[1]) |
                                       (r0_cursor1 & cursor_counter[0] & ~cursor_counter[1]) |
                                       (r0_cursor2 & cursor_counter[1]));

always @(posedge CLOCK) begin : process_4

    if (~nRESET) begin
        cursor_active <= 0;
        cursor_counter <= 0;
    end
    else if (clken_fetch) begin

        if (CURSOR | cursor_active) begin
            //  Latch cursor
            cursor_active <= 1;

            //  Reset on counter wrap
            if (cursor_counter === 2'b 11) begin
                cursor_active <= 0;
            end

            //  Increment counter
            if (!cursor_active) begin

                //  Reset
                cursor_counter <= 0;

            end
            else begin
                //  Increment
                cursor_counter <= cursor_counter + 1'd1;
            end
        end
    end
end

//  Pixel generation
//  The new shift register contents are loaded during
//  cycle 11 (and 3) but will not be read here until the next cycle.
//  By running this process on every single video tick instead of at
//  the pixel rate we ensure that the resulting delay is minimal and
//  constant (running this at the pixel rate would cause
//  the display to move slightly depending on which mode was selected).


//  Look up dot value in the palette.  Bits are as follows:
//  bit 3 - FLASH
//  bit 2 - Not BLUE
//  bit 1 - Not GREEN
//  bit 0 - Not RED

wire [3:0]  palette_a = {shiftreg[7], shiftreg[5], shiftreg[3], shiftreg[1]};
wire [3:0]  dot_val   = palette[palette_a];

//  Apply flash inversion if required
wire	red_val   = dot_val[3] & r0_flash ^ ~dot_val[0];
wire 	green_val = dot_val[3] & r0_flash ^ ~dot_val[1];
wire 	blue_val  = dot_val[3] & r0_flash ^ ~dot_val[2];

//  Display enable signal delayed by one clock
reg delayed_disen;
always @(posedge CLOCK) if (mhz4_clken) delayed_disen <= DISEN;

// delayed cursor for teletext
always @(posedge CLOCK) if (CLKEN) cursor_invert_delayed <= cursor_invert;

always @(posedge CLOCK) begin

    if (~nRESET) begin
        R <= 0;
        G <= 0;
        B <= 0;
    end
    else if (CLKEN) begin

        //  To output
        //  FIXME: INVERT option
        if (!r0_teletext) begin

            //  Cursor can extend outside the bounds of the screen, so
            //  it is not affected by DISEN
            R <= red_val & delayed_disen ^ cursor_invert;
            G <= green_val & delayed_disen ^ cursor_invert;
            B <= blue_val & delayed_disen ^ cursor_invert;

        end
        else begin

            R <= R_IN ^ cursor_invert_delayed;
            G <= G_IN ^ cursor_invert_delayed;
            B <= B_IN ^ cursor_invert_delayed;

        end

    end

end

endmodule // module vidproc
