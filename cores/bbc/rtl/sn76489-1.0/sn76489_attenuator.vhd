-------------------------------------------------------------------------------
--
-- Synthesizable model of TI's SN76489AN.
--
-- $Id: sn76489_attenuator.vhd,v 1.7 2006/02/27 20:30:10 arnim Exp $
--
-- Attenuator Module
--
-------------------------------------------------------------------------------
--
-- Copyright (c) 2005, 2006, Arnim Laeuger (arnim.laeuger@gmx.net)
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
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL; 

entity sn76489_attenuator is

  port (
    attenuation_i : in  std_logic_vector(0 to 3);
    factor_i      : in  std_logic;
    product_o     : out std_logic_vector(0 to 7)
  );

end sn76489_attenuator;


architecture rtl of sn76489_attenuator is
    type     volume_t is array (natural range 0 to 15) of natural;
    constant volume_c : volume_t := (31, 25, 20, 16, 12, 10, 8, 6, 5, 4, 3, 2, 2, 2, 1, 0);
begin

  -----------------------------------------------------------------------------
  -- Process attenuate
  --
  -- Purpose:
  --   Determine the attenuation and generate the resulting product.
  --
  --   The maximum attenuation value is 31 which corresponds to volume off.
  --   As described in the data sheet, the maximum "playing" attenuation is
  --     28 = 16 + 8 + 4
  --
  --   The table for the volume constants is derived from the following
  --   formula (each step is 2dB voltage):
  --     v(0)   = 31
  --     v(n+1) = v(n) * 0.79432823
  --

  product_o <= conv_std_logic_vector(volume_c(conv_integer(attenuation_i)), product_o'length) when factor_i = '1'
          else (others => '0');

end rtl;
