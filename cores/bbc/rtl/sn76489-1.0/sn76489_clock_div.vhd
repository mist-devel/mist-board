-------------------------------------------------------------------------------
--
-- Synthesizable model of TI's SN76489AN.
--
-- $Id: sn76489_clock_div.vhd,v 1.4 2005/10/10 21:51:27 arnim Exp $
--
-- Clock Divider Circuit
--
-------------------------------------------------------------------------------
--
-- Copyright (c) 2005, Arnim Laeuger (arnim.laeuger@gmx.net)
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
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
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
-- Please report bugs to the author, but before you do so, please
-- make sure that this is not a derivative work and that
-- you have the latest version of this file.
--
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity sn76489_clock_div is

  generic (
    clock_div_16_g : integer := 1
  );
  port (
    clock_i    : in  std_logic;
    clock_en_i : in  std_logic;
    res_n_i    : in  std_logic;
    clk_en_o   : out boolean
  );

end sn76489_clock_div;


library ieee;
use ieee.numeric_std.all;

architecture rtl of sn76489_clock_div is

  signal cnt_s,
         cnt_q  : unsigned(3 downto 0);

begin

  -----------------------------------------------------------------------------
  -- Process seq
  --
  -- Purpose:
  --   Implements the sequential counter element.
  --
  seq: process (clock_i, res_n_i)
  begin
    if res_n_i = '0' then
      cnt_q <= (others => '0');
    elsif clock_i'event and clock_i = '1' then
      cnt_q <= cnt_s;
    end if;
  end process seq;
  --
  -----------------------------------------------------------------------------


  -----------------------------------------------------------------------------
  -- Process comb
  --
  -- Purpose:
  --   Implements the combinational counter logic.
  --
  comb: process (clock_en_i,
                 cnt_q)
  begin
    -- default assignments
    cnt_s    <= cnt_q;
    clk_en_o <= false;

    if clock_en_i = '1' then

      if cnt_q = 0 then
        clk_en_o <= true;

        if clock_div_16_g = 1 then
          cnt_s  <= to_unsigned(15, cnt_q'length);
        elsif clock_div_16_g = 0 then
          cnt_s  <= to_unsigned( 1, cnt_q'length);
        else
          -- pragma translate_off
          assert false
            report "Generic clock_div_16_g must be either 0 or 1."
            severity failure;
          -- pragma translate_on
        end if;

      else
        cnt_s    <= cnt_q - 1;

      end if;

    end if;

  end process comb;
  --
  -----------------------------------------------------------------------------

end rtl;
