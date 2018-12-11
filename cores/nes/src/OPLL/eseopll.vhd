--
-- eseopll.vhd
-- A simple wrapper module for fitting VM2413 to ESE-MSX SYSTEM
--
-- Copyright (c) 2006 Mitsutaka Okazaki (brezza@pokipoki.org)
-- All rights reserved.
--
-- Redistribution and use of this source code or any derivative works, are
-- permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice,
--    this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
-- 3. Redistributions may not be sold, nor may they be used in a commercial
--    product or activity without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
-- TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
-- CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
-- EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
-- PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
-- OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
-- WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
-- OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
-- ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--
--
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use WORK.VM2413.ALL;

entity eseopll is
  port(
    clk21m  : in std_logic;
    reset   : in std_logic;
    clkena  : in std_logic;
    enawait : in std_logic;
    req     : in std_logic;
    ack     : out std_logic;
    wrt     : in std_logic;
    adr     : in std_logic_vector(15 downto 0);
    dbo     : in std_logic_vector(7 downto 0);
    wav     : out std_logic_vector(13 downto 0)
 );
end eseopll;

architecture RTL of eseopll is

  signal XIN  : std_logic;
  signal D    : std_logic_vector(7 downto 0);
  signal A    : std_logic;
  signal CS_n : std_logic;
  signal WE_n : std_logic;
  signal IC_n : std_logic;
  signal MO   : std_logic_vector(9 downto 0);
  signal RO   : std_logic_vector(9 downto 0);

  signal counter : integer range 0 to 72*6;

  signal A_buf    : std_logic;
  signal dbo_buf  : std_logic_vector(7 downto 0);
  signal CS_n_buf : std_logic;
  signal WE_n_buf : std_logic;

begin

  IC_n <= not reset;

  process (clk21m, reset)

  begin

    if reset = '1' then

      counter <= 0;

    elsif clk21m'event and clk21m = '1' then

      if counter /= 0 then
        counter <= counter - 1;
        ack <= '0';
      else
        if req = '1' then
          if enawait = '1' then
            if adr(0) = '0' then
              counter <= 4*6;
            else
              counter <= 72*6;
            end if;
          end if;
          A_buf <= adr(0);
          dbo_buf <= dbo;
          CS_n_buf <= not req;
          WE_n_buf <= not wrt;
        end if;
        ack <= req;
      end if;

      if (clkena = '1') then

        A    <= A_buf;
        D    <= dbo_buf;
        CS_n <= CS_n_buf;
        WE_n <= WE_n_buf;

      end if;

    end if;

  end process;

  U1 : opll port map (clk21m, open, clkena, D, A, CS_n, WE_n, IC_n, wav);

end RTL;
