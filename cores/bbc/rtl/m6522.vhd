--
-- A simulation model of VIC20 hardware - VIA implementation
-- Copyright (c) MikeJ - March 2003
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- Redistributions in synthesized form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- Neither the name of the author nor the names of other contributors may
-- be used to endorse or promote products derived from this software without
-- specific prior written permission.
--
-- THIS CODE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- You are responsible for any legal issues arising from your use of this code.
--
-- The latest version of this file can be found at: www.fpgaarcade.com
--
-- Email vic20@fpgaarcade.com
--
--
-- Revision list
--
--        dmb: ier bit 7 should read back as '1'
--        dmb: Fixes to sr_do_shift change that broke MMFS on the Beeb (SR mode 0)
-- version 005 Many fixes to all areas, VIA now passes all VICE tests
-- version 004 fixes to PB7 T1 control and Mode 0 Shift Register operation
-- version 003 fix reset of T1/T2 IFR flags if T1/T2 is reload via reg5/reg9 from wolfgang (WoS)
--             Ported to numeric_std and simulation fix for signal initializations from arnim laeuger
-- version 002 fix from Mark McDougall, untested
-- version 001 initial release
-- not very sure about the shift register, documentation is a bit light.

library ieee ;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

entity M6522 is
   port (
      I_RS                  : in    std_logic_vector(3 downto 0);
      I_DATA                : in    std_logic_vector(7 downto 0);
      O_DATA                : out   std_logic_vector(7 downto 0);
      O_DATA_OE_L           : out   std_logic;

      I_RW_L                : in    std_logic;
      I_CS1                 : in    std_logic;
      I_CS2_L               : in    std_logic;

      O_IRQ_L               : out   std_logic; -- note, not open drain

      -- port a
      I_CA1                 : in    std_logic;
      I_CA2                 : in    std_logic;
      O_CA2                 : out   std_logic;
      O_CA2_OE_L            : out   std_logic;

      I_PA                  : in    std_logic_vector(7 downto 0);
      O_PA                  : out   std_logic_vector(7 downto 0);
      O_PA_OE_L             : out   std_logic_vector(7 downto 0);

      -- port b
      I_CB1                 : in    std_logic;
      O_CB1                 : out   std_logic;
      O_CB1_OE_L            : out   std_logic;

      I_CB2                 : in    std_logic;
      O_CB2                 : out   std_logic;
      O_CB2_OE_L            : out   std_logic;

      I_PB                  : in    std_logic_vector(7 downto 0);
      O_PB                  : out   std_logic_vector(7 downto 0);
      O_PB_OE_L             : out   std_logic_vector(7 downto 0);

      I_P2_H                : in    std_logic; -- high for phase 2 clock  ____----__
      RESET_L               : in    std_logic;
      ENA_4                 : in    std_logic; -- clk enable
      CLK                   : in    std_logic
   );
end;

architecture RTL of M6522 is

   signal phase             : std_logic_vector(1 downto 0):="00";
   signal p2_h_t1           : std_logic;
   signal cs                : std_logic;

   -- registers
   signal r_ddra            : std_logic_vector(7 downto 0);
   signal r_ora             : std_logic_vector(7 downto 0);
   signal r_ira             : std_logic_vector(7 downto 0);

   signal r_ddrb            : std_logic_vector(7 downto 0);
   signal r_orb             : std_logic_vector(7 downto 0);
   signal r_irb             : std_logic_vector(7 downto 0);

   signal r_t1l_l           : std_logic_vector(7 downto 0);
   signal r_t1l_h           : std_logic_vector(7 downto 0);
   signal r_t2l_l           : std_logic_vector(7 downto 0);
   signal r_t2l_h           : std_logic_vector(7 downto 0); -- not in real chip
   signal r_sr              : std_logic_vector(7 downto 0);
   signal r_acr             : std_logic_vector(7 downto 0);
   signal r_pcr             : std_logic_vector(7 downto 0);
   signal r_ifr             : std_logic_vector(7 downto 0);
   signal r_ier             : std_logic_vector(6 downto 0);

   signal sr_write_ena      : boolean;
   signal sr_read_ena       : boolean;
   signal ifr_write_ena     : boolean;
   signal ier_write_ena     : boolean;
   signal clear_irq         : std_logic_vector(7 downto 0);
   signal load_data         : std_logic_vector(7 downto 0);

   -- timer 1
   signal t1c               : std_logic_vector(15 downto 0) := (others => '1'); -- simulators may not catch up w/o init here...
   signal t1c_active        : boolean;
   signal t1c_done          : boolean;
   signal t1_w_reset_int    : boolean;
   signal t1_r_reset_int    : boolean;
   signal t1_load_counter   : boolean;
   signal t1_reload_counter : boolean;
   signal t1_int_enable     : boolean := false;
   signal t1_toggle         : std_logic;
   signal t1_irq            : std_logic := '0';
   signal t1_pb7            : std_logic := '1';
   signal t1_pb7_en_c         : std_logic;
   signal t1_pb7_en_d      : std_logic;

   -- timer 2
   signal t2c               : std_logic_vector(15 downto 0) := (others => '1'); -- simulators may not catch up w/o init here...
   signal t2c_active        : boolean;
   signal t2c_done          : boolean;
   signal t2_pb6            : std_logic;
   signal t2_pb6_t1         : std_logic;
   signal t2_cnt_clk        : std_logic := '1';
   signal t2_w_reset_int    : boolean;
   signal t2_r_reset_int    : boolean;
   signal t2_load_counter   : boolean;
   signal t2_reload_counter : boolean;
   signal t2_int_enable     : boolean := false;
   signal t2_irq            : std_logic := '0';
   signal t2_sr_ena         : boolean;

   -- shift reg
   signal sr_cnt            : std_logic_vector(3 downto 0);
   signal sr_cb1_oe_l       : std_logic;
   signal sr_cb1_out        : std_logic;
   signal sr_drive_cb2      : std_logic;
   signal sr_strobe         : std_logic;
   signal sr_do_shift       : boolean := false;
   signal sr_strobe_t1      : std_logic;
   signal sr_strobe_falling : boolean;
   signal sr_strobe_rising  : boolean;
   signal sr_irq            : std_logic;
   signal sr_out            : std_logic;
   signal sr_active         : boolean;

   -- io
   signal w_orb_hs          : std_logic;
   signal w_ora_hs          : std_logic;
   signal r_irb_hs          : std_logic;
   signal r_ira_hs          : std_logic;

   signal ca_hs_sr          : std_logic;
   signal ca_hs_pulse       : std_logic;
   signal cb_hs_sr          : std_logic;
   signal cb_hs_pulse       : std_logic;

   signal cb1_in_mux        : std_logic;
   signal ca1_ip_reg_c      : std_logic;
   signal ca1_ip_reg_d      : std_logic;
   signal cb1_ip_reg_c      : std_logic;
   signal cb1_ip_reg_d      : std_logic;
   signal ca1_int           : boolean;
   signal cb1_int           : boolean;
   signal ca1_irq           : std_logic;
   signal cb1_irq           : std_logic;

   signal ca2_ip_reg_c      : std_logic;
   signal ca2_ip_reg_d      : std_logic;
   signal cb2_ip_reg_c      : std_logic;
   signal cb2_ip_reg_d      : std_logic;
   signal ca2_int           : boolean;
   signal cb2_int           : boolean;
   signal ca2_irq           : std_logic;
   signal cb2_irq           : std_logic;

   signal final_irq         : std_logic;
begin

   p_phase : process
   begin
      -- internal clock phase
      wait until rising_edge(CLK);
      if (ENA_4 = '1') then
         p2_h_t1 <= I_P2_H;
         if (p2_h_t1 = '0') and (I_P2_H = '1') then
            phase <= "11";
         else
            phase <= std_logic_vector(unsigned(phase) + 1);
         end if;
      end if;
   end process;

   p_cs : process(I_CS1, I_CS2_L, I_P2_H)
   begin
      cs <= '0';
      if (I_CS1 = '1') and (I_CS2_L = '0') and (I_P2_H = '1') then
         cs <= '1';
      end if;
   end process;

   -- peripheral control reg (pcr)
   -- 0      ca1 interrupt control (0 +ve edge, 1 -ve edge)
   -- 3..1   ca2 operation
   --        000 input -ve edge
   --        001 independend interrupt input -ve edge
   --        010 input +ve edge
   --        011 independend interrupt input +ve edge
   --        100 handshake output
   --        101 pulse output
   --        110 low output
   --        111 high output
   -- 7..4   as 3..0 for cb1,cb2

   -- auxiliary control reg (acr)
   -- 0      input latch PA (0 disable, 1 enable)
   -- 1      input latch PB (0 disable, 1 enable)
   -- 4..2   shift reg control
   --        000 disable
   --        001 shift in using t2
   --        010 shift in using o2
   --        011 shift in using ext clk
   --        100 shift out free running t2 rate
   --        101 shift out using t2
   --        101 shift out using o2
   --        101 shift out using ext clk
   -- 5      t2 timer control (0 timed interrupt, 1 count down with pulses on pb6)
   -- 7..6   t1 timer control
   --        00 timed interrupt each time t1 is loaded   pb7 disable
   --        01 continuous interrupts                    pb7 disable
   --        00 timed interrupt each time t1 is loaded   pb7 one shot output
   --        01 continuous interrupts                    pb7 square wave output
   --

   p_write_reg_reset : process(RESET_L, CLK)
   begin
      if (RESET_L = '0') then
         r_ora   <= x"00";    r_orb   <= x"00";
         r_ddra  <= x"00";    r_ddrb  <= x"00";
         r_acr   <= x"00";    r_pcr   <= x"00";

         w_orb_hs <= '0';
         w_ora_hs <= '0';
      elsif rising_edge(CLK) then
         if (ENA_4 = '1') then
            w_orb_hs <= '0';
            w_ora_hs <= '0';
            if (cs = '1') and (I_RW_L = '0') then
               case I_RS is
                  when x"0" => r_orb     <= I_DATA; w_orb_hs <= '1';
                  when x"1" => r_ora     <= I_DATA; w_ora_hs <= '1';
                  when x"2" => r_ddrb    <= I_DATA;
                  when x"3" => r_ddra    <= I_DATA;

                  when x"B" => r_acr     <= I_DATA;
                  when x"C" => r_pcr     <= I_DATA;
                  when x"F" => r_ora     <= I_DATA;

                  when others => null;
               end case;
            end if;

            -- Set timer PB7 state, only on rising edge of setting ACR(7)
            if ((t1_pb7_en_d = '0') and (t1_pb7_en_c = '1')) then
               t1_pb7 <= '1';
            end if;

            if t1_load_counter then
               t1_pb7 <= '0'; -- Reset internal timer 1 PB7 state on every timer load
            elsif t1_toggle = '1' then
               t1_pb7 <= not t1_pb7;
            end if;
         end if;
      end if;
   end process;

   p_write_reg : process (RESET_L, CLK) is
   begin
      if (RESET_L = '0') then
         -- The spec says, this is not reset.
         -- Fact is that the 1541 VIA1 timer won't work,
         -- as the firmware ONLY sets the r_t1l_h latch!!!!
         r_t1l_l   <= (others => '1'); -- All latches default to FFFF
         r_t1l_h   <= (others => '1');
         r_t2l_l   <= (others => '1');
         r_t2l_h   <= (others => '1');
      elsif rising_edge(CLK) then
         if (ENA_4 = '1') then
            t1_w_reset_int  <= false;
            t1_load_counter <= false;

            t2_w_reset_int  <= false;
            t2_load_counter <= false;

            load_data <= x"00";
            sr_write_ena <= false;
            ifr_write_ena <= false;
            ier_write_ena <= false;

            if (cs = '1') and (I_RW_L = '0') then
               load_data <= I_DATA;
               case I_RS is
                  when x"4" => r_t1l_l   <= I_DATA;
                  when x"5" => r_t1l_h   <= I_DATA; t1_w_reset_int  <= true;
                                                    t1_load_counter <= true;

                  when x"6" => r_t1l_l   <= I_DATA;
                  when x"7" => r_t1l_h   <= I_DATA; t1_w_reset_int  <= true;

                  when x"8" => r_t2l_l   <= I_DATA;
                  when x"9" => r_t2l_h   <= I_DATA; t2_w_reset_int  <= true;
                                                    t2_load_counter <= true;

                  when x"A" =>                      sr_write_ena    <= true;
                  when x"D" =>                      ifr_write_ena   <= true;
                  when x"E" =>                      ier_write_ena   <= true;

                  when others => null;
               end case;
            end if;
         end if;
      end if;
   end process;

   p_oe : process(cs, I_RW_L)
   begin
      O_DATA_OE_L <= '1';
      if (cs = '1') and (I_RW_L = '1') then
         O_DATA_OE_L <= '0';
      end if;
   end process;

   p_read : process(cs, I_RW_L, I_RS, r_irb, r_ira, r_ddrb, r_ddra, t1c, r_t1l_l,
      r_t1l_h, t2c, r_sr, r_acr, r_pcr, r_ifr, r_ier, r_ora, r_orb, t1_pb7_en_d, t1_pb7)
      variable orb : std_logic_vector(7 downto 0);
   begin
      t1_r_reset_int <= false;
      t2_r_reset_int <= false;
      sr_read_ena <= false;
      r_irb_hs <= '0';
      r_ira_hs <= '0';
      O_DATA <= x"00"; -- default
      orb := (r_irb and not r_ddrb) or (r_orb and r_ddrb);

      -- If PB7 under timer control, assign value from timer
      if (t1_pb7_en_d = '1') then
         orb(7) := t1_pb7;
      end if;

      if (cs = '1') and (I_RW_L = '1') then
         case I_RS is
            when x"0" => O_DATA <= orb; r_irb_hs <= '1';
            when x"1" => O_DATA <= (r_ira and not r_ddra) or (r_ora and r_ddra); r_ira_hs <= '1';
            when x"2" => O_DATA <= r_ddrb;
            when x"3" => O_DATA <= r_ddra;
            when x"4" => O_DATA <= t1c( 7 downto 0);  t1_r_reset_int <= true;
            when x"5" => O_DATA <= t1c(15 downto 8);
            when x"6" => O_DATA <= r_t1l_l;
            when x"7" => O_DATA <= r_t1l_h;
            when x"8" => O_DATA <= t2c( 7 downto 0);  t2_r_reset_int <= true;
            when x"9" => O_DATA <= t2c(15 downto 8);
            when x"A" => O_DATA <= r_sr;              sr_read_ena    <= true;
            when x"B" => O_DATA <= r_acr;
            when x"C" => O_DATA <= r_pcr;
            when x"D" => O_DATA <= r_ifr;
            -- DMB: ier bit 7 should read back as '1'
            when x"E" => O_DATA <= ('1' & r_ier);
            when x"F" => O_DATA <= r_ira;
            when others => null;
         end case;
      end if;

   end process;

   --
   -- IO
   --

   p_ca1_cb1_sel : process(sr_cb1_oe_l, sr_cb1_out, I_CB1)
   begin
      -- if the shift register is enabled, cb1 may be an output
      -- in this case we should NOT listen to the input as 
      -- CB1 interrupts are not generated by the shift register 
      if (sr_cb1_oe_l = '1') then
         cb1_in_mux <= I_CB1;
      else
         cb1_in_mux <= '1';
      end if;
   end process;

   p_ca1_cb1_int : process(r_pcr, ca1_ip_reg_c, ca1_ip_reg_d, cb1_ip_reg_c, cb1_ip_reg_d)
   begin
      if (r_pcr(0) = '0') then -- ca1 control
         -- negative edge
         ca1_int <= (ca1_ip_reg_d = '1') and (ca1_ip_reg_c = '0');
      else
         -- positive edge
         ca1_int <= (ca1_ip_reg_d = '0') and (ca1_ip_reg_c = '1');
      end if;

      if (r_pcr(4) = '0') then -- cb1 control
         -- negative edge
         cb1_int <= (cb1_ip_reg_d = '1') and (cb1_ip_reg_c = '0');
      else
         -- positive edge
         cb1_int <= (cb1_ip_reg_d = '0') and (cb1_ip_reg_c = '1');
      end if;
   end process;

   p_ca2_cb2_int : process(r_pcr, ca2_ip_reg_c, ca2_ip_reg_d, cb2_ip_reg_c, cb2_ip_reg_d)
   begin
      ca2_int <= false;
      if (r_pcr(3) = '0') then -- ca2 input
         if (r_pcr(2) = '0') then -- ca2 edge
         -- negative edge
         ca2_int <= (ca2_ip_reg_d = '1') and (ca2_ip_reg_c = '0');
         else
         -- positive edge
         ca2_int <= (ca2_ip_reg_d = '0') and (ca2_ip_reg_c = '1');
         end if;
      end if;

      cb2_int <= false;
      if (r_pcr(7) = '0') then -- cb2 input
         if (r_pcr(6) = '0') then -- cb2 edge
            -- negative edge
            cb2_int <= (cb2_ip_reg_d = '1') and (cb2_ip_reg_c = '0');
         else
            -- positive edge
            cb2_int <= (cb2_ip_reg_d = '0') and (cb2_ip_reg_c = '1');
         end if;
      end if;
   end process;

   p_ca2_cb2 : process(RESET_L, CLK)
   begin
      if (RESET_L = '0') then
         O_CA2       <= '1'; -- Pullup is default
         O_CA2_OE_L  <= '1';
         O_CB2       <= '1'; -- Pullup is default
         O_CB2_OE_L  <= '1';

         ca_hs_sr <= '0';
         ca_hs_pulse <= '0';
         cb_hs_sr <= '0';
         cb_hs_pulse <= '0';
      elsif rising_edge(CLK) then
         if (ENA_4 = '1') then
               -- ca
            if (phase = "00") and ((w_ora_hs = '1') or (r_ira_hs = '1')) then
               ca_hs_sr <= '1';
            elsif ca1_int then
               ca_hs_sr <= '0';
            end if;

            if (phase = "00") then
               ca_hs_pulse <= w_ora_hs or r_ira_hs;
            end if;

            O_CA2_OE_L <= not r_pcr(3); -- ca2 output
            case r_pcr(3 downto 1) is
               when "000" => O_CA2 <= I_CA2; -- input, output follows input
               when "001" => O_CA2 <= I_CA2; -- input, output follows input
               when "010" => O_CA2 <= I_CA2; -- input, output follows input
               when "011" => O_CA2 <= I_CA2; -- input, output follows input
               when "100" => O_CA2 <= not (ca_hs_sr); -- handshake
               when "101" => O_CA2 <= not (ca_hs_pulse); -- pulse
               when "110" => O_CA2 <= '0'; -- low
               when "111" => O_CA2 <= '1'; -- high
               when others => null;
            end case;

            -- cb
            if (phase = "00") and (w_orb_hs = '1') then
               cb_hs_sr <= '1';
            elsif cb1_int then
               cb_hs_sr <= '0';
            end if;

            if (phase = "00") then
               cb_hs_pulse <= w_orb_hs;
            end if;

            O_CB2_OE_L <= not (r_pcr(7) or sr_drive_cb2); -- cb2 output or serial
            if (sr_drive_cb2 = '1') then -- serial output
               O_CB2 <= sr_out;
            else
               case r_pcr(7 downto 5) is
                  when "000" => O_CB2 <= I_CB2; -- input, output follows input
                  when "001" => O_CB2 <= I_CB2; -- input, output follows input
                  when "010" => O_CB2 <= I_CB2; -- input, output follows input
                  when "011" => O_CB2 <= I_CB2; -- input, output follows input
                  when "100" => O_CB2 <= not (cb_hs_sr); -- handshake
                  when "101" => O_CB2 <= not (cb_hs_pulse); -- pulse
                  when "110" => O_CB2 <= '0'; -- low
                  when "111" => O_CB2 <= '1'; -- high
                  when others => null;
               end case;
            end if;
         end if;
      end if;
   end process;

   O_CB1      <= sr_cb1_out;
   O_CB1_OE_L <= sr_cb1_oe_l;

   p_ca_cb_irq : process(RESET_L, CLK)
   begin
      if (RESET_L = '0') then
         ca1_irq <= '0';
         ca2_irq <= '0';
         cb1_irq <= '0';
         cb2_irq <= '0';
      elsif rising_edge(CLK) then
         if (ENA_4 = '1') then
            -- not pretty
            if ca1_int then
               ca1_irq <= '1';
            elsif (r_ira_hs = '1') or (w_ora_hs = '1') or (clear_irq(1) = '1') then
               ca1_irq <= '0';
            end if;

            if ca2_int then
               ca2_irq <= '1';
            else
               if (((r_ira_hs = '1') or (w_ora_hs = '1')) and (r_pcr(1) = '0')) or
                  (clear_irq(0) = '1') then
                  ca2_irq <= '0';
               end if;
            end if;

            if cb1_int then
               cb1_irq <= '1';
            elsif (r_irb_hs = '1') or (w_orb_hs = '1') or (clear_irq(4) = '1') then
               cb1_irq <= '0';
            end if;

            if cb2_int then
               cb2_irq <= '1';
            else
               if (((r_irb_hs = '1') or (w_orb_hs = '1')) and (r_pcr(5) = '0')) or
                  (clear_irq(3) = '1') then
                  cb2_irq <= '0';
               end if;
            end if;
         end if;
      end if;
   end process;

   p_input_reg : process(RESET_L, CLK)
   begin
      if (RESET_L = '0') then
         ca1_ip_reg_c <= '0';
         ca1_ip_reg_d <= '0';
         
         cb1_ip_reg_c <= '0';
         cb1_ip_reg_d <= '0';

         ca2_ip_reg_c <= '0';
         ca2_ip_reg_d <= '0';
         
         cb2_ip_reg_c <= '0';
         cb2_ip_reg_d <= '0';

         r_ira <= x"00";
         r_irb <= x"00";

      elsif rising_edge(CLK) then
         if (ENA_4 = '1') then
            -- we have a fast clock, so we can have input registers
            ca1_ip_reg_c <= I_CA1;
            ca1_ip_reg_d <= ca1_ip_reg_c;

            cb1_ip_reg_c <= cb1_in_mux;
            cb1_ip_reg_d <= cb1_ip_reg_c;

            ca2_ip_reg_c <= I_CA2;
            ca2_ip_reg_d <= ca2_ip_reg_c;

            cb2_ip_reg_c <= I_CB2;
            cb2_ip_reg_d <= cb2_ip_reg_c;

            if (r_acr(0) = '0') then
               r_ira <= I_PA;
            else -- enable latching
               if ca1_int then
                  r_ira <= I_PA;
               end if;
            end if;

            if (r_acr(1) = '0') then
               r_irb <= I_PB;
            else -- enable latching
               if cb1_int then
                  r_irb <= I_PB;
               end if;
            end if;
         end if;
      end if;
   end process;

   p_buffers : process(r_ddra, r_ora, r_ddrb, r_acr, r_orb, t1_pb7_en_d, t1_pb7)
   begin
      -- data direction reg (ddr) 0 = input, 1 = output
      O_PA      <= r_ora;
      O_PA_OE_L <= not r_ddra;

      -- If PB7 is timer driven output set PB7 to the timer state, otherwise use value in ORB register
      if (t1_pb7_en_d = '1') then
         O_PB <= t1_pb7 & r_orb(6 downto 0);
      else
         O_PB <= r_orb;
      end if;

      -- NOTE: r_ddrb(7) must be set to enable T1 output on PB7 - [various datasheets specify this]
      O_PB_OE_L <= not r_ddrb; 
   end process;

   --
   -- Timer 1
   --

   -- Detect change in r_acr(7), timer 1 mode for PB7
   p_pb7_enable : process
   begin
      wait until rising_edge(CLK);
      if (ENA_4 = '1') then
         t1_pb7_en_c <= r_acr(7);
         t1_pb7_en_d <= t1_pb7_en_c;
      end if;
   end process;

   p_timer1_done : process
      variable done : boolean;
   begin
      wait until rising_edge(CLK);
      if (ENA_4 = '1') then
         done := (t1c = x"0000");
         t1c_done <= done and (phase = "11");
         if (phase = "11") and not t1_load_counter then -- Don't set reload if T1L-H written
            t1_reload_counter <= done;
         elsif t1_load_counter then                     -- Cancel a reload when T1L-H written
            t1_reload_counter <= false;
         end if;
         if t1_load_counter then -- done reset on load!
            t1c_done <= false;
         end if;
      end if;
   end process;

   p_timer1 : process
   begin
      wait until rising_edge(CLK);
      if (ENA_4 = '1') then
         if t1_load_counter or (t1_reload_counter and phase = "11") then
            t1c( 7 downto 0) <= r_t1l_l;
            t1c(15 downto 8) <= r_t1l_h;
            -- There is a need to write to Latch HI to enable interrupts for both continuous and one-shot modes
            if t1_load_counter then
               t1_int_enable <= true;
            end if;
         elsif (phase="11") then
            t1c <= std_logic_vector(unsigned(t1c) - 1);
         end if;

         if t1_load_counter or t1_reload_counter then
            t1c_active <= true;
         elsif t1c_done then
            t1c_active <= false;
         end if;

         t1_toggle <= '0';
         if t1c_active and t1c_done then
            if t1_int_enable then -- Set interrupt only if T1L-H has been written
               t1_toggle <= '1';
               t1_irq <= '1';
               if (r_acr(6) = '0') then -- Disable further interrupts if in one shot mode
                  t1_int_enable <= false; 
               end if;
            end if;
         elsif t1_w_reset_int or t1_r_reset_int or (clear_irq(6) = '1') then
            t1_irq <= '0';
         end if;
         if t1_load_counter then -- irq reset on load!
            t1_irq <= '0';
         end if;
      end if;
   end process;

   --
   -- Timer2
   --

   p_timer2_pb6_input : process
   begin
      wait until rising_edge(CLK);
      if (ENA_4 = '1') then
         if (phase = "01") then -- leading edge p2_h
            t2_pb6    <= I_PB(6);
            t2_pb6_t1 <= t2_pb6;
         end if;
      end if;
   end process;

   -- Ensure we don't start counting until the P2 clock after r_acr is changed
   p_timer2_ena : process
   begin
      wait until rising_edge(I_P2_H);
      if r_acr(5) = '0' then
         t2_cnt_clk <= '1';
      else
         t2_cnt_clk <= '0';
      end if;
   end process;
 
   p_timer2_done : process
      variable done : boolean;
      variable done_sr : boolean;
   begin
      wait until rising_edge(CLK);
      if (ENA_4 = '1') then
         done := (t2c = x"0000");               -- Normal timer expires at 0000
         done_sr := (t2c(7 downto 0) = x"00");  -- Shift register expires on low byte = 00
         t2c_done <= done and (phase = "11");
         if (phase = "11") then
            t2_reload_counter <= done_sr;        -- Timer 2 is only reloaded when used for the shift register
         end if;
         if t2_load_counter then -- done reset on load!
            t2c_done <= false;
         end if;
      end if;
   end process;

   p_timer2 : process
      variable ena : boolean;
   begin
      wait until rising_edge(CLK);
      if (ENA_4 = '1') then
         if (t2_cnt_clk ='1') then
            ena := true;
            t2c_active <= true;
            t2_int_enable <= true;
         else
            ena := (t2_pb6_t1 = '1') and (t2_pb6 = '0'); -- falling edge
         end if;

         -- Shift register reload is only active when shift register mode using T2 is enabled
         if t2_reload_counter and (phase="11") and ((r_acr(4 downto 2) = "001") or (r_acr(4 downto 2) = "100") or (r_acr(4 downto 2) = "101")) then
            t2c(7 downto 0) <= r_t2l_l; -- For shift register only low latch is loaded!
         elsif t2_load_counter then
            t2_int_enable <= true;
            t2c( 7 downto 0) <= r_t2l_l;
            t2c(15 downto 8) <= r_t2l_h;
         else
            if (phase="11") and ena then -- or count mode
               t2c <= std_logic_vector(unsigned(t2c) - 1);
            end if;
         end if;

         -- Shift register strobe on T2 occurs one P2H clock after timer expires
         -- so enable the strobe when we roll over to FF
         t2_sr_ena <= (t2c(7 downto 0) = x"FF") and (phase = "11");

         if t2_load_counter then
            t2c_active <= true;
         elsif t2c_done then
            t2c_active <= false;
         end if;

         if t2c_active and t2c_done and t2_int_enable then
            t2_int_enable <= false;
            t2_irq <= '1';
         elsif t2_w_reset_int or t2_r_reset_int or (clear_irq(5) = '1') then
            t2_irq <= '0';
         end if;
         if t2_load_counter then -- irq reset on load!
            t2_irq <= '0';
         end if;
      end if;
   end process;
  
   --
   -- Shift Register
   --

   p_sr : process(RESET_L, CLK)
      variable dir_out      : std_logic;
      variable ena          : std_logic;
      variable cb1_op       : std_logic;
      variable cb1_ip       : std_logic;
      variable use_t2       : std_logic;
      variable free_run     : std_logic;
      variable sr_count_ena : boolean;
   begin
      if (RESET_L = '0') then
         r_sr <= x"00";
         sr_drive_cb2 <= '0';
         sr_cb1_oe_l <= '1';
         sr_cb1_out <= '0';
         sr_do_shift <= false;
         sr_strobe <= '1';
         sr_cnt <= "0000";
         sr_irq <= '0';
         sr_out <= '0';
         sr_active <= false;
      elsif rising_edge(CLK) then
         if (ENA_4 = '1') then
            -- decode mode
            dir_out  := r_acr(4); -- output on cb2
            cb1_op   := '0';
            cb1_ip   := '0';
            use_t2   := '0';
            free_run := '0';

            -- DMB: SR still runs even in disabled mode (on rising edge of CB1).
            -- It just doesn't generate any interrupts.
            -- Ref BBC micro advanced user guide p409
                    
            case r_acr(4 downto 2) is
               -- DMB: in disabled mode, configure cb1 as an input
               when "000" => ena := '0'; cb1_ip := '1';                                  -- 0x00 Mode 0 SR disabled
               when "001" => ena := '1'; cb1_op := '1'; use_t2 := '1';                   -- 0x04 Mode 1 Shift in under T2 control
               when "010" => ena := '1'; cb1_op := '1';                                  -- 0x08 Mode 2 Shift in under P2 control
               when "011" => ena := '1'; cb1_ip := '1';                                  -- 0x0C Mode 3 Shift in under control of ext clock
               when "100" => ena := '1'; cb1_op := '1'; use_t2 := '1'; free_run := '1';  -- 0x10 Mode 4 Shift out free running under T2 control
               when "101" => ena := '1'; cb1_op := '1'; use_t2 := '1';                   -- 0x14 Mode 5 Shift out under T2 control
               when "110" => ena := '1'; cb1_op := '1';                                  -- 0x18 Mode 6 Shift out under P2 control
               when "111" => ena := '1'; cb1_ip := '1';                                  -- 0x1C Mode 7 Shift out under control of ext clock
               when others => null;
            end case;

            -- clock select
            -- DMB: in disabled mode, strobe from cb1
            if (cb1_ip = '1') then
               sr_strobe <= I_CB1;
            else
               if (sr_cnt(3) = '0') and (free_run = '0') then
                  sr_strobe <= '1';
               else
                  if ((use_t2 = '1') and t2_sr_ena) or
                     ((use_t2 = '0') and (phase = "00")) then
                     sr_strobe <= not sr_strobe;
                  end if;
               end if;
            end if;

            -- latch on rising edge, shift on falling edge of P2
            if sr_write_ena then
               r_sr <= load_data;
               sr_out <= r_sr(7);
 
            else
               -- DMB: allow shifting in all modes
               if (dir_out = '0') then
                  -- input
                  if (sr_cnt(3) = '1') or (cb1_ip = '1') then
                     if sr_strobe_rising then
                        sr_do_shift <= true;
                        r_sr(0) <= I_CB2;
                     -- DMB: Added sr_stroble_falling to avoid premature shift
                     -- (fixes issue with MMFS on the Beeb in SR mode 0)
                     elsif sr_do_shift and sr_strobe_falling then
                        sr_do_shift <= false;
                        r_sr(7 downto 1) <= r_sr(6 downto 0);
                     end if;
                  end if;
               else
                  -- output
                  if (sr_cnt(3) = '1') or (cb1_ip = '1') or (free_run = '1') then
                     if sr_strobe_falling then
                        sr_out <= r_sr(7);
                        sr_do_shift <= true;
                     -- DMB: Added sr_stroble_falling to avoid premature shift
                     -- (fixes issue with MMFS on the Beeb in SR mode 0)
                     elsif sr_do_shift and sr_strobe_rising then
                        sr_do_shift <= false;
                        r_sr <= r_sr(6 downto 0) & r_sr(7);
                     end if;
                  end if;
               end if;
            end if;
        
            -- Set shift enabled flag, note does not get set for free_run mode !
            if (ena = '1') and (sr_cnt(3) = '1') then
               sr_active <= true;
            elsif (ena = '1') and (sr_cnt(3) = '0') and (phase="11") then
               sr_active <= false;
            end if;

            sr_count_ena := sr_strobe_rising;

            -- DMB: reseting sr_count when not enabled cause the sr to
            -- start running immediately it was enabled, which is incorrect
            -- and broke the latest SmartSPI ROM on the BBC Micro
            if (ena = '1') and (sr_write_ena or sr_read_ena) and (not sr_active) then
               -- some documentation says sr bit in IFR must be set as well ?
               sr_cnt <= "1000";
            elsif sr_count_ena and (sr_cnt(3) = '1') then
               sr_cnt <= std_logic_vector(unsigned(sr_cnt) + 1);
            end if;

            if sr_count_ena and (sr_cnt = "1111") and (ena = '1') and (free_run = '0') then
               sr_irq <= '1';
            elsif sr_write_ena or sr_read_ena or (clear_irq(2) = '1') then
               sr_irq <= '0';
            end if;

            -- assign ops
            sr_drive_cb2 <= dir_out;
            sr_cb1_oe_l  <= not cb1_op;
            sr_cb1_out   <= sr_strobe;
         end if;
      end if;
   end process;

   p_sr_strobe_rise_fall : process
   begin
      wait until rising_edge(CLK);
      if (ENA_4 = '1') then
         sr_strobe_t1 <= sr_strobe;
         sr_strobe_rising  <= (sr_strobe_t1 = '0') and (sr_strobe = '1');
         sr_strobe_falling <= (sr_strobe_t1 = '1') and (sr_strobe = '0');
      end if;
   end process;
  
   --
   -- Interrupts
   --

   p_ier : process(RESET_L, CLK)
   begin
      if (RESET_L = '0') then
         r_ier <= "0000000";
      elsif rising_edge(CLK) then
         if (ENA_4 = '1') then
            if ier_write_ena then
               if (load_data(7) = '1') then
                  -- set
                  r_ier <= r_ier or load_data(6 downto 0);
               else
                  -- clear
                  r_ier <= r_ier and not load_data(6 downto 0);
               end if;
            end if;
         end if;
      end if;
   end process;

   p_ifr : process(t1_irq, t2_irq, final_irq, ca1_irq, ca2_irq, sr_irq,
                  cb1_irq, cb2_irq)
   begin
      r_ifr(7) <= final_irq;
      r_ifr(6) <= t1_irq;
      r_ifr(5) <= t2_irq;
      r_ifr(4) <= cb1_irq;
      r_ifr(3) <= cb2_irq;
      r_ifr(2) <= sr_irq;
      r_ifr(1) <= ca1_irq;
      r_ifr(0) <= ca2_irq;

      O_IRQ_L <= not final_irq;
   end process;

   p_irq : process(RESET_L, CLK)
   begin
      if (RESET_L = '0') then
         final_irq <= '0';
      elsif rising_edge(CLK) then
         if (ENA_4 = '1') then
            if ((r_ifr(6 downto 0) and r_ier(6 downto 0)) = "0000000") then
               final_irq <= '0'; -- no interrupts
            else
               final_irq <= '1';
            end if;
         end if;
      end if;
   end process;

   p_clear_irq : process(ifr_write_ena, load_data)
   begin
      clear_irq <= x"00";
      if ifr_write_ena then
         clear_irq <= load_data;
      end if;
   end process;

end architecture RTL;
