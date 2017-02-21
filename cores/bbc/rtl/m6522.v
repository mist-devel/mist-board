`timescale 1 ns / 1 ns // timescale for following modules
//
//  A simulation model of VIC20 hardware
//  Copyright (c) MikeJ - March 2003
//
//  All rights reserved
//
//  Redistribution and use in source and synthezised forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  Redistributions of source code must retain the above copyright notice,
//  this list of conditions and the following disclaimer.
//
//  Redistributions in synthesized form must reproduce the above copyright
//  notice, this list of conditions and the following disclaimer in the
//  documentation and/or other materials provided with the distribution.
//
//  Neither the name of the author nor the names of other contributors may
//  be used to endorse or promote products derived from this software without
//  specific prior written permission.
//
//  THIS CODE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
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
//  You are responsible for any legal issues arising from your use of this code.
//
//  The latest version of this file can be found at: www.fpgaarcade.com
//
//  Email vic20@fpgaarcade.com
//
//
//  Revision list
//
//  version 002 fix from Mark McDougall, untested
//  version 001 initial release
//  not very sure about the shift register, documentation is a bit light.

module m6522 (
           I_RS,
           I_DATA,
           O_DATA,
           O_DATA_OE_L,
           I_RW_L,
           I_CS1,
           I_CS2_L,
           O_IRQ_L,
           I_CA1,
           I_CA2,
           O_CA2,
           O_CA2_OE_L,
           I_PA,
           O_PA,
           O_PA_OE_L,
           I_CB1,
           O_CB1,
           O_CB1_OE_L,
           I_CB2,
           O_CB2,
           O_CB2_OE_L,
           I_PB,
           O_PB,
           O_PB_OE_L,
           I_P2_H,
           RESET_L,
           ENA_4,
           CLK);


input   [3:0] I_RS;
input   [7:0] I_DATA;
output reg  [7:0] O_DATA;
output   O_DATA_OE_L;
input   I_RW_L;
input   I_CS1;
input   I_CS2_L;
output   O_IRQ_L;
input   I_CA1;
input   I_CA2;
output   O_CA2;
output   O_CA2_OE_L;
input   [7:0] I_PA;
output   [7:0] O_PA;
output   [7:0] O_PA_OE_L;
input   I_CB1;
output   O_CB1;
output   O_CB1_OE_L;
input   I_CB2;
output   O_CB2;
output   O_CB2_OE_L;
input   [7:0] I_PB;
output   [7:0] O_PB;
output   [7:0] O_PB_OE_L;
input   I_P2_H;
input   RESET_L;
input   ENA_4;
input   CLK;


reg     O_CA2;
reg     O_CA2_OE_L;


//  port b
wire    O_CB1;
wire    O_CB1_OE_L;
reg     O_CB2;
reg     O_CB2_OE_L;
reg     [1:0] phase;
reg     p2_h_t1;
wire     cs;

//  registers
reg     [7:0] r_ddra;
reg     [7:0] r_ora;
reg     [7:0] r_ira;
reg     [7:0] r_ddrb;
reg     [7:0] r_orb;
reg     [7:0] r_irb;
reg     [7:0] r_t1l_l;
reg     [7:0] r_t1l_h;
reg     [7:0] r_t2l_l;
reg     [7:0] r_t2l_h;
//  not in real chip
reg     [7:0] r_sr;
reg     [7:0] r_acr;
reg     [7:0] r_pcr;
wire     [7:0] r_ifr;
reg     [6:0] r_ier;
reg     sr_write_ena;
reg     sr_read_ena;
reg     ifr_write_ena;
reg     ier_write_ena;
wire     [7:0] clear_irq;
reg     [7:0] load_data;

//  timer 1
reg     [15:0] t1c;
reg     t1c_active;
wire    t1c_done;
reg     t1_w_reset_int;
reg     t1_r_reset_int;
reg     t1_load_counter;
wire    t1_reload_counter;
reg     t1_toggle;
reg     t1_irq;

//  timer 2
reg     [15:0] t2c;
reg     t2c_active;
wire    t2c_done;
reg     t2_pb6;
reg     t2_pb6_t1;
reg     t2_w_reset_int;
reg     t2_r_reset_int;
reg     t2_load_counter;
wire    t2_reload_counter;
reg     t2_irq;
reg     t2_sr_ena;

//  shift reg
reg     [3:0] sr_cnt;
reg     sr_cb1_oe_l;
reg     sr_cb1_out;
reg     sr_drive_cb2;
reg     sr_strobe;
reg     sr_strobe_t1;
reg     sr_strobe_falling;
reg     sr_strobe_rising;
reg     sr_irq;
reg     sr_out;
reg     sr_off_delay;

//  io
reg     w_orb_hs;
reg     w_ora_hs;
reg     r_irb_hs;
reg     r_ira_hs;
reg     ca_hs_sr;
reg     ca_hs_pulse;
reg     cb_hs_sr;
reg     cb_hs_pulse;

reg     ca1_ip_reg;
reg     cb1_ip_reg;
wire    ca1_int;
wire    cb1_int;
reg     ca1_irq;
reg     cb1_irq;
reg     ca2_ip_reg;
reg     cb2_ip_reg;
wire    ca2_int;
wire    cb2_int;
reg     ca2_irq;
reg     cb2_irq;
reg     final_irq;
wire    p_timer1_done_done;
wire    p_timer2_done_done;
reg      p_timer2_ena;
reg      p_sr_dir_out;
reg      p_sr_ena;
reg      p_sr_cb1_op;
reg      p_sr_cb1_ip;
reg      p_sr_use_t2;
reg      p_sr_free_run;
reg      p_sr_sr_count_ena;

initial begin
    t2_irq = 1'b 0;
end

initial begin
    t1_irq = 1'b 0;
end


always @(posedge CLK) begin

    if (ENA_4 === 1'b 1) begin
        p2_h_t1 <= I_P2_H;

        if (p2_h_t1 === 1'b 0 & I_P2_H === 1'b 1) begin
            phase <= 2'b 11;
        end
        else begin
            phase <= phase + 1'b 1;
        end
    end
end


//  internal clock phase
assign cs = (I_CS1 === 1'b 1 & I_CS2_L === 1'b 0 & I_P2_H === 1'b 1) ? 1'b1 : 1'b0;

//  peripheral control reg (pcr)
//  0      ca1 interrupt control (0 +ve edge, 1 -ve edge)
//  3..1   ca2 operation
//         000 input -ve edge
//         001 independend interrupt input -ve edge
//         010 input +ve edge
//         011 independend interrupt input +ve edge
//         100 handshake output
//         101 pulse output
//         110 low output
//         111 high output
//  7..4   as 3..0 for cb1,cb2
//  auxiliary control reg (acr)
//  0      input latch PA (0 disable, 1 enable)
//  1      input latch PB (0 disable, 1 enable)
//  4..2   shift reg control
//         000 disable
//         001 shift in using t2
//         010 shift in using o2
//         011 shift in using ext clk
//         100 shift out free running t2 rate
//         101 shift out using t2
//         101 shift out using o2
//         101 shift out using ext clk
//  5      t2 timer control (0 timed interrupt, 1 count down with pulses on pb6)
//  7..6   t1 timer control
//         00 timed interrupt each time t1 is loaded   pb7 disable
//         01 continuous interrupts                    pb7 disable
//         00 timed interrupt each time t1 is loaded   pb7 one shot output
//         01 continuous interrupts                    pb7 square wave output
//

always @(posedge CLK) begin

    if (RESET_L === 1'b 0) begin
        r_ora <= 8'h 00;
        r_orb <= 8'h 00;
        r_ddra <= 8'h 00;
        r_ddrb <= 8'h 00;
        r_acr <= 8'h 00;
        r_pcr <= 8'h 00;
        w_orb_hs <= 1'b 0;
        w_ora_hs <= 1'b 0;
    end
    else  begin
        if (ENA_4 === 1'b 1) begin
            w_orb_hs <= 1'b 0;
            w_ora_hs <= 1'b 0;

            if (cs === 1'b 1 & I_RW_L === 1'b 0) begin
                case (I_RS)
                    4'h 0: begin
                        r_orb <= I_DATA;
                        w_orb_hs <= 1'b 1;
                    end

                    4'h 1: begin
                        r_ora <= I_DATA;
                        w_ora_hs <= 1'b 1;
                    end

                    4'h 2: begin
                        r_ddrb <= I_DATA;
                    end

                    4'h 3: begin
                        r_ddra <= I_DATA;
                    end

                    4'h B: begin
                        r_acr <= I_DATA;
                    end

                    4'h C: begin
                        r_pcr <= I_DATA;
                    end

                    4'h F: begin
                        r_ora <= I_DATA;
                    end

                    default:
                        ;

                endcase
            end

				if (r_acr[7] === 1'b1) begin
					if(t1_load_counter)
						r_orb[7] <= 1'b0; 			// writing T1C-H resets bit 7
					else if (t1_toggle === 1'b1)
						r_orb[7] <= ~r_orb[7]; 		// toggle
				end
        end
    end
end


always @(posedge CLK) begin

    //Fix incorrect power up values in timer latches
    if (RESET_L === 1'b 0) begin
        r_t1l_l <= 8'h FE;
        r_t1l_h <= 8'h FF;
        r_t2l_l <= 8'h FE;
        r_t2l_h <= 8'h FF;
    end
    else  begin

         if (ENA_4 === 1'b 1) begin
              t1_w_reset_int <= 1'b0;
              t1_load_counter <= 1'b0;
              t2_w_reset_int <= 1'b0;
              t2_load_counter <= 1'b0;
              load_data <= 8'h 00;
              sr_write_ena <= 1'b0;
              ifr_write_ena <= 1'b0;
              ier_write_ena <= 1'b0;
    
              if (cs === 1'b 1 & I_RW_L === 1'b 0) begin
                    load_data <= I_DATA;
    
                    case (I_RS)
                         4'h 4: begin
                              r_t1l_l <= I_DATA;
                         end
    
                         4'h 5: begin
                              r_t1l_h <= I_DATA;
                              t1_w_reset_int <= 1'b1;
                              t1_load_counter <= 1'b1;
                         end
    
                         4'h 6: begin
                              r_t1l_l <= I_DATA;
                         end
    
                         4'h 7: begin
                              r_t1l_h <= I_DATA;
                              t1_w_reset_int <= 1'b1;
                         end
    
                         4'h 8: begin
                              r_t2l_l <= I_DATA;
                         end
    
                         4'h 9: begin
                              r_t2l_h <= I_DATA;
                              t2_w_reset_int <= 1'b1;
                              t2_load_counter <= 1'b1;
                         end
    
                         4'h A: begin
                              sr_write_ena <= 1'b1;
                         end
    
                         4'h D: begin
                              ifr_write_ena <= 1'b1;
                         end
    
                         4'h E: begin
                              ier_write_ena <= 1'b1;
                         end
    
                         default:
                              ;
    
                    endcase
              end
         end
    end
end


assign O_DATA_OE_L = (cs === 1'b 1 & I_RW_L === 1'b 1) ? 1'b0 : 1'b1;


always @(posedge CLK) begin

    if (ENA_4 === 1'b 1) begin

        t1_r_reset_int <= 1'b0;
        t2_r_reset_int <= 1'b0;
        sr_read_ena <= 1'b0;
        r_irb_hs <= 1'b 0;
        r_ira_hs <= 1'b 0;

        if (cs === 1'b 1 & I_RW_L === 1'b 1) begin
            case (I_RS)
                4'h 0: begin
                    O_DATA <= r_irb & ~r_ddrb | r_orb & r_ddrb;
                    // when x"0" => O_DATA <= r_irb; r_irb_hs <= '1';
                    //  fix from Mark McDougall, untested
                    r_irb_hs <= 1'b 1;
                end

                4'h 1: begin
                    O_DATA <= r_ira;
                    r_ira_hs <= 1'b 1;
                end

                4'h 2: begin
                    O_DATA <= r_ddrb;
                end

                4'h 3: begin
                    O_DATA <= r_ddra;
                end

                4'h 4: begin
                    O_DATA <= t1c[7:0];
                    t1_r_reset_int <= 1'b1;
                end

                4'h 5: begin
                    O_DATA <= t1c[15:8];
                end

                4'h 6: begin
                    O_DATA <= r_t1l_l;
                end

                4'h 7: begin
                    O_DATA <= r_t1l_h;
                end

                4'h 8: begin
                    O_DATA <= t2c[7:0];
                    t2_r_reset_int <= 1'b1;
                end

                4'h 9: begin
                    O_DATA <= t2c[15:8];
                end

                4'h A: begin
                    O_DATA <= r_sr;
                    sr_read_ena <= 1'b1;
                end

                4'h B: begin
                    O_DATA <= r_acr;
                end

                4'h C: begin
                    O_DATA <= r_pcr;
                end

                4'h D: begin
                    O_DATA <= r_ifr;
                end

                4'h E: begin
                    O_DATA <= {1'b 1, r_ier};
                end

                4'h F: begin
                    O_DATA <= r_ira;
                end

                default:
                    ;

            endcase
        end
    end
end

//
//  IO
//

//  if the shift register is enabled, cb1 may be an output
//  in this case, we should listen to the CB1_OUT for the interrupt

assign cb1_in_mux = (sr_cb1_oe_l === 1'b 1) ? I_CB1 : sr_cb1_out;


//  ca1 control
assign ca1_int	= (r_pcr[0] === 1'b 0) 	? (ca1_ip_reg == 1'b1 & I_CA1 == 1'b0) : 	//  negative edge
       (ca1_ip_reg == 1'b0 & I_CA1 == 1'b1); 	//  positive edge


//  cb1 control
assign cb1_int	= (r_pcr[4] === 1'b 0)	? (cb1_ip_reg == 1'b1 & cb1_in_mux == 1'b0) : 	//  negative edge
       (cb1_ip_reg == 1'b0 & cb1_in_mux == 1'b1);


assign ca2_int 	= (r_pcr[3] === 1'b 1) 	? 	1'b0 :
       (r_pcr[2] === 1'b 1)  ? 	(ca2_ip_reg == 1'b 0 & I_CA2 == 1'b 1):
       (ca2_ip_reg == 1'b 1 & I_CA2 == 1'b 0);

assign cb2_int 	= (r_pcr[7] === 1'b 1) 	? 	1'b0 :
       (r_pcr[6] === 1'b 1)  ? 	(cb2_ip_reg == 1'b 0 & I_CB2 == 1'b 1):
       (cb2_ip_reg == 1'b 1 & I_CB2 == 1'b 0);


always @(posedge CLK) begin

    if (RESET_L === 1'b 0) begin
        O_CA2 <= 1'b 0;
        O_CA2_OE_L <= 1'b 1;
        O_CB2 <= 1'b 0;
        O_CB2_OE_L <= 1'b 1;
        ca_hs_sr <= 1'b 0;
        ca_hs_pulse <= 1'b 0;
        cb_hs_sr <= 1'b 0;
        cb_hs_pulse <= 1'b 0;
    end 
    else begin
        if (ENA_4 === 1'b 1) begin

            //  ca
            if (phase === 2'b 00 & (w_ora_hs === 1'b 1 |
                                    r_ira_hs === 1'b 1)) begin
                ca_hs_sr <= 1'b 1;
            end
            else if (ca1_int ) begin
                ca_hs_sr <= 1'b 0;
            end

            if (phase === 2'b 00) begin
                ca_hs_pulse <= w_ora_hs | r_ira_hs;
            end

            O_CA2_OE_L <= ~r_pcr[3];
            //  ca2 output
            case (r_pcr[3:1])
                3'b 000: begin
                    O_CA2 <= 1'b 0;
                    //  input
                end

                3'b 001: begin
                    O_CA2 <= 1'b 0;
                    //  input
                end

                3'b 010: begin
                    O_CA2 <= 1'b 0;
                    //  input
                end

                3'b 011: begin
                    O_CA2 <= 1'b 0;
                    //  input
                end

                3'b 100: begin
                    O_CA2 <= ~ca_hs_sr;
                    //  handshake
                end

                3'b 101: begin
                    O_CA2 <= ~ca_hs_pulse;
                    //  pulse
                end

                3'b 110: begin
                    O_CA2 <= 1'b 0;
                    //  low
                end

                3'b 111: begin
                    O_CA2 <= 1'b 1;
                    //  high
                end

                default:
                    ;

            endcase
            if (phase === 2'b 00 & w_orb_hs === 1'b 1) begin
                cb_hs_sr <= 1'b 1;
                //  cb
            end
            else if (cb1_int ) begin
                cb_hs_sr <= 1'b 0;
            end

            if (phase === 2'b 00) begin
                cb_hs_pulse <= w_orb_hs;
            end

            O_CB2_OE_L <= ~(r_pcr[7] | sr_drive_cb2);
            //  cb2 output or serial
            if (sr_drive_cb2 === 1'b 1) begin

                //  serial output
                O_CB2 <= sr_out;
            end
            else begin
                case (r_pcr[7:5])
                    3'b 000: begin
                        O_CB2 <= 1'b 0;
                        //  input
                    end

                    3'b 001: begin
                        O_CB2 <= 1'b 0;
                        //  input
                    end

                    3'b 010: begin
                        O_CB2 <= 1'b 0;
                        //  input
                    end

                    3'b 011: begin
                        O_CB2 <= 1'b 0;
                        //  input
                    end

                    3'b 100: begin
                        O_CB2 <= ~cb_hs_sr;
                        //  handshake
                    end

                    3'b 101: begin
                        O_CB2 <= ~cb_hs_pulse;
                        //  pulse
                    end

                    3'b 110: begin
                        O_CB2 <= 1'b 0;
                        //  low
                    end

                    3'b 111: begin
                        O_CB2 <= 1'b 1;
                        //  high
                    end

                    default:
                        ;

                endcase
            end
        end
    end
end

assign O_CB1 = sr_cb1_out;
assign O_CB1_OE_L = sr_cb1_oe_l;

always @(posedge CLK) begin

    if (RESET_L === 1'b 0) begin
        ca1_irq <= 1'b 0;
        ca2_irq <= 1'b 0;
        cb1_irq <= 1'b 0;
        cb2_irq <= 1'b 0;
    end
    else  begin
        if (ENA_4 === 1'b 1) begin

            //  not pretty
            if (ca1_int) begin
                ca1_irq <= 1'b 1;
            end
            else if (r_ira_hs === 1'b 1 | w_ora_hs === 1'b 1 |
                     clear_irq[1] === 1'b 1 ) begin
                ca1_irq <= 1'b 0;
            end

            if (ca2_int) begin
                ca2_irq <= 1'b 1;
            end
            else begin
                if ((r_ira_hs === 1'b 1 | w_ora_hs === 1'b 1) &
                        r_pcr[1] === 1'b 0 | clear_irq[0] === 1'b 1) begin
                    ca2_irq <= 1'b 0;
                end
            end

            if (cb1_int) begin
                cb1_irq <= 1'b 1;
            end
            else if (r_irb_hs === 1'b 1 | w_orb_hs === 1'b 1 |
                     clear_irq[4] === 1'b 1 ) begin
                cb1_irq <= 1'b 0;
            end

            if (cb2_int) begin
                cb2_irq <= 1'b 1;
            end
            else begin
                if ((r_irb_hs === 1'b 1 | w_orb_hs === 1'b 1) &
                        r_pcr[5] === 1'b 0 | clear_irq[3] === 1'b 1) begin
                    cb2_irq <= 1'b 0;
                end
            end
        end
    end
end


always @(posedge CLK) begin

    if (RESET_L === 1'b 0) begin
        ca1_ip_reg <= 1'b 0;
        cb1_ip_reg <= 1'b 0;
        ca2_ip_reg <= 1'b 0;
        cb2_ip_reg <= 1'b 0;
        r_ira <= 8'h 00;
        r_irb <= 8'h 00;
    end
    else  begin
        if (ENA_4 === 1'b 1) begin

            //  we have a fast clock, so we can have input registers
            ca1_ip_reg <= I_CA1;
            cb1_ip_reg <= cb1_in_mux;
            ca2_ip_reg <= I_CA2;
            cb2_ip_reg <= I_CB2;

            if (r_acr[0] === 1'b 0) begin
                r_ira <= I_PA;

                //  enable latching
            end
            else begin
                if (ca1_int) begin
                    r_ira <= I_PA;
                end
            end

            if (r_acr[1] === 1'b 0) begin
                r_irb <= I_PB;

                //  enable latching
            end
            else begin
                if (cb1_int) begin
                    r_irb <= I_PB;
                end
            end
        end
    end
end

assign O_PA = r_ora;
assign O_PA_OE_L = ~r_ddra;


assign O_PB_OE_L[6:0] = ~r_ddrb[6:0];
//  not clear if r_ddrb(7) must be 1 as well, an output if under t1 control
assign O_PB_OE_L[7] = (r_acr[7] === 1'b 1) ? 1'b 0 : ~r_ddrb[7];

assign O_PB[7:0] = r_orb[7:0];

//
//  Timer 1
//

//  data direction reg (ddr) 0 = input, 1 = output

assign p_timer1_done_done = t1c == 16'h 0000;
assign t1c_done = p_timer1_done_done & phase == 2'b 11;
assign t1_reload_counter = p_timer1_done_done & r_acr[6] == 1'b 1;

always @(posedge CLK) begin

    if (ENA_4 === 1'b 1) begin
        if (t1_load_counter | t1_reload_counter & phase === 2'b 11) begin
            t1c[7:0] <= r_t1l_l;
            t1c[15:8] <= r_t1l_h;
        end
        else if (phase === 2'b 11 ) begin
            t1c <= t1c - 1'b 1;
        end

        if (t1_load_counter | t1_reload_counter) begin
            t1c_active <= 1'b1;
        end
        else if (t1c_done ) begin
            t1c_active <= 1'b0;
        end

        if (RESET_L === 1'b 0) begin
            t1c_active <= 1'b0;
        end

        t1_toggle <= 1'b 0;

        if (t1c_active & t1c_done) begin
            t1_toggle <= 1'b 1;
            t1_irq <= 1'b 1;
        end
        else if (RESET_L === 1'b 0 | t1_w_reset_int | t1_r_reset_int |
                 clear_irq[6] === 1'b 1 ) begin
            t1_irq <= 1'b 0;
        end
    end
end

//
//  Timer2
//

always @(posedge CLK) begin

    if (ENA_4 === 1'b 1) begin
        if (phase === 2'b 01) begin

            //  leading edge p2_h
            t2_pb6 <= I_PB[6];
            t2_pb6_t1 <= t2_pb6;
        end
    end
end

assign p_timer2_done_done = t2c == 16'h 0000;
assign t2c_done = p_timer2_done_done & phase == 2'b 11;
assign t2_reload_counter = p_timer2_done_done;


always @(posedge CLK) begin

    if (ENA_4 === 1'b 1) begin
        if (r_acr[5] === 1'b 0) begin
            p_timer2_ena = 1'b1;
        end
        else begin
            p_timer2_ena = t2_pb6_t1 == 1'b 1 & t2_pb6 == 1'b 0;
            //  falling edge
        end

        if (t2_load_counter | t2_reload_counter & phase === 2'b 11) begin

            //  not sure if t2c_reload should be here. Does timer2 just continue to
            //  count down, or is it reloaded ? Reloaded makes more sense if using
            //  it to generate a clock for the shift register.
            t2c[7:0] <= r_t2l_l;
            t2c[15:8] <= r_t2l_h;
        end
        else begin
            if (phase === 2'b 11 & p_timer2_ena) begin

                //  or count mode
                t2c <= t2c - 1'b 1;
            end
        end

        t2_sr_ena <= t2c[7:0] == 8'h 00 & phase == 2'b 11;

        if (t2_load_counter) begin
            t2c_active <= 1'b1;
        end
        else if (t2c_done ) begin
            t2c_active <= 1'b0;
        end

        if (RESET_L === 1'b 0) begin
            t2c_active <= 1'b0;
        end

        if (t2c_active & t2c_done) begin
            t2_irq <= 1'b 1;
        end
        else if (RESET_L === 1'b 0 | t2_w_reset_int | t2_r_reset_int |
                 clear_irq[5] === 1'b 1 ) begin
            t2_irq <= 1'b 0;
        end
    end
end

//
//  Shift Register
//

always @(posedge CLK) begin

    if (RESET_L === 1'b 0) begin
        r_sr <= 8'h 00;
        sr_drive_cb2 <= 1'b 0;
        sr_cb1_oe_l <= 1'b 1;
        sr_cb1_out <= 1'b 0;
        sr_strobe <= 1'b 1;
        sr_cnt <= 4'b 0000;
        sr_irq <= 1'b 0;
        sr_out <= 1'b 1;
        sr_off_delay <= 1'b 0;
    end
    else  begin
        if (ENA_4 === 1'b 1) begin

            //  decode mode
            p_sr_dir_out = r_acr[4];
            //  output on cb2
            p_sr_cb1_op = 1'b 0;
            p_sr_cb1_ip = 1'b 0;
            p_sr_use_t2 = 1'b 0;
            p_sr_free_run = 1'b 0;

            case (r_acr[4:2])
                3'b 000: begin
                    p_sr_ena = 1'b 0;
                    p_sr_cb1_ip = 1'b 1;
                end

                3'b 001: begin
                    p_sr_ena = 1'b 1;
                    p_sr_cb1_op = 1'b 1;
                    p_sr_use_t2 = 1'b 1;
                end

                3'b 010: begin
                    p_sr_ena = 1'b 1;
                    p_sr_cb1_op = 1'b 1;
                end

                3'b 011: begin
                    p_sr_ena = 1'b 1;
                    p_sr_cb1_ip = 1'b 1;
                end

                3'b 100: begin
                    p_sr_ena = 1'b 1;
                    p_sr_use_t2 = 1'b 1;
                    p_sr_free_run = 1'b 1;
                end

                3'b 101: begin
                    p_sr_ena = 1'b 1;
                    p_sr_cb1_op = 1'b 1;
                    p_sr_use_t2 = 1'b 1;
                end

                3'b 110: begin
                    p_sr_ena = 1'b 1;
                end

                3'b 111: begin
                    p_sr_ena = 1'b 1;
                    p_sr_cb1_ip = 1'b 1;
                end

                default:
                    ;

            endcase
            if (p_sr_cb1_ip === 1'b 1) begin
                sr_strobe <= I_CB1;
                //  clock select
                //  SR still runs even in disabled mode (on rising edge of CB1).  It
                //  just doesn't generate any interrupts.
                //  Ref BBC micro advanced user guide p409
            end
            else begin
                if (sr_cnt[3] === 1'b 0 & p_sr_free_run === 1'b 0) begin
                    sr_strobe <= 1'b 1;
                end
                else begin
                    if (p_sr_use_t2 === 1'b 1 & t2_sr_ena | p_sr_use_t2 ===
                            1'b 0 & phase === 2'b 00) begin
                        sr_strobe <= ~sr_strobe;
                    end
                end
            end

            //  latch on rising edge, shift on falling edge
            if (sr_write_ena) begin
                r_sr <= load_data;
            end
            else begin
                if (p_sr_dir_out === 1'b 0) begin

                    //  input
                    if (sr_cnt[3] === 1'b 1 | p_sr_cb1_ip === 1'b 1) begin
                        if (sr_strobe_rising) begin
                            r_sr <= {r_sr[6:0], I_CB2};
                        end
                    end

                    sr_out <= 1'b 1;

                    //  output
                end
                else begin
                    if (sr_cnt[3] === 1'b 1 | sr_off_delay === 1'b 1 |
                            p_sr_cb1_ip === 1'b 1 | p_sr_free_run === 1'b 1) begin
                        if (sr_strobe_falling) begin
                            r_sr[7:1] <= r_sr[6:0];
                            r_sr[0] <= r_sr[7];
                            sr_out <= r_sr[7];
                        end
                    end
                    else begin
                        sr_out <= 1'b 1;
                    end
                end
            end

            p_sr_sr_count_ena = sr_strobe_rising;

            if (sr_write_ena | sr_read_ena) begin

                //  some documentation says sr bit in IFR must be set as well ?
                sr_cnt <= 4'b 1000;
            end
            else if (p_sr_sr_count_ena & sr_cnt[3] === 1'b 1 ) begin
                sr_cnt <= sr_cnt + 1'b 1;
            end

            if (phase === 2'b 00) begin
                sr_off_delay <= sr_cnt[3];
                //  give some hold time when shifting out
            end

            if (p_sr_sr_count_ena & sr_cnt === 4'b 1111 & p_sr_ena ===
                    1'b 1 & p_sr_free_run === 1'b 0) begin
                sr_irq <= 1'b 1;
            end
            else if (sr_write_ena | sr_read_ena | clear_irq[2] === 1'b 1 ) begin
                sr_irq <= 1'b 0;
            end

            //  assign ops
            sr_drive_cb2 <= p_sr_dir_out;
            sr_cb1_oe_l <= ~p_sr_cb1_op;
            sr_cb1_out <= sr_strobe;
        end
    end
end


always @(posedge CLK) begin

    if (ENA_4 === 1'b 1) begin
        sr_strobe_t1 <= sr_strobe;
        sr_strobe_rising <= sr_strobe_t1 == 1'b 0 & sr_strobe == 1'b 1;
        sr_strobe_falling <= sr_strobe_t1 == 1'b 1 & sr_strobe == 1'b 0;
    end
end

//
//  Interrupts
//

always @(posedge CLK) begin

    if (RESET_L === 1'b 0) begin
        r_ier <= 7'b 0000000;
    end
    else  begin
        if (ENA_4 === 1'b 1) begin
            if (ier_write_ena) begin
                if (load_data[7] === 1'b 1) begin

                    //  set
                    r_ier <= r_ier | load_data[6:0];

                    //  clear
                end
                else begin
                    r_ier <= r_ier & ~load_data[6:0];
                end
            end
        end
    end
end

assign O_IRQ_L = ~final_irq;
assign r_ifr 	= {final_irq, t1_irq, t2_irq, cb1_irq, cb2_irq, sr_irq, ca1_irq, ca2_irq};

always @(posedge CLK) begin

    if (RESET_L === 1'b 0) begin
        final_irq <= 1'b 0;
    end
    else begin
        if (ENA_4 === 1'b 1) begin
            if ((r_ifr[6:0] & r_ier[6:0]) === 7'b 0000000) begin
                final_irq <= 1'b 0;
                //  no interrupts
            end
            else begin
                final_irq <= 1'b 1;
            end
        end
    end
end


assign clear_irq = ifr_write_ena ? load_data : 8'h00;

endmodule // module M6522

