--
-- HT 1080Z (TSR-80 clone) ps2 keyboard
--
--
-- Copyright (c) 2016-2017 Jozsef Laszlo (rbendr@gmail.com)
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



library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

	
entity ps2kbd is
    Port ( 
	   RESET : in  STD_LOGIC;
 	   KBCLK : in  STD_LOGIC;
	   KBDAT : in  STD_LOGIC;
		SWRES : out STD_LOGIC;
	     CLK : in  STD_LOGIC;
		    A : in  STD_LOGIC_VECTOR(7 downto 0);
		 DOUT : out STD_LOGIC_VECTOR(7 downto 0);
		 PAGE : out STD_LOGIC;		 
		 VCUT : out STD_LOGIC;
       INKP : out STD_LOGIC;
	  PAPERP : out STD_LOGIC;
	 BORDERP : out STD_LOGIC	 
		  );
			  
end ps2kbd;

architecture Behavioral of ps2kbd is

type keys is array(0 to 7) of std_logic_vector(7 downto 0);
 
signal keypress : std_logic:='0';
signal extkey   : std_logic:='0';

signal hasRead  : std_logic;

signal keybits : keys;
signal keysout : keys;
signal lastkc : std_logic;

signal kbdsign : std_logic;
signal kbddata : std_logic_vector(7 downto 0);
signal swreset : std_logic := '1';

signal pageReg : std_logic := '0';
signal vcutReg : std_logic := '0';

signal inkpulse, paperpulse, borderpulse : std_logic;
 
 
begin

  ps2rd : entity work.ps2reader
  port map (
	 mclk => CLK,
	 PS2C => KBCLK, 
	 PS2D => KBDAT,
	 rst => RESET,
	 Ps2Dout => kbddata,
	 fRd => kbdsign
  );
    
  process(RESET,CLK,kbdsign,kbddata)
  variable kk : std_logic_vector(6 downto 0);
  variable ix : integer;
  begin
   if RESET='1' then
	   keypress <= '0';
		keybits(0) <= "00000000";
		keybits(1) <= "00000000";
		keybits(2) <= "00000000";
		keybits(3) <= "00000000";
		keybits(4) <= "00000000";
		keybits(5) <= "00000000";
		keybits(6) <= "00000000";
		keybits(7) <= "00000000";
		
		swreset <= '1';
		pageReg <= '0';
		vcutReg <= '0';
	elsif rising_edge(CLK) then
		if kbdsign = '1' then
			if kbddata=x"F0" then
			  keypress <= '0'; -- released  
			  --if shifrpress='1' then
			--		keybits(7)(0)<='0';
			--		shifrpress<='0';
			  --end if;
			elsif kbddata=x"E0" then
			  extkey<='1';
			else
			  keypress <= '1'; -- pressed
			  
			  -- this is for ps2 read. we convert 0x83 to 0x02 (keyboard F2)
			  kk:= kbddata(6 downto 0);
			  if kbddata=x"83" then 
			    kk:="0000010"; -- keyboard F7 code 0x83 converted to 0x02
			  end if;			

				
			  
			  case '0' & kk is
			  							 
				when x"03" => inkpulse <= keypress; -- F1
				when x"0b" => paperpulse <= keypress; -- F2
				when x"02" => borderpulse <= keypress; -- F3 
				
				when x"78"=> swreset <=	not keypress; -- F11
				
				when x"01"=> --F9
							if keypress='1' then
							   vcutReg <= not vcutReg;
							end if;
				
				when x"09"=> --F10				
							if keypress='1' then
							   pageReg <= not pageReg;
							end if;
				
				-- \|
				when x"5d"=> keybits(0)(0)<=keypress;
				-- A
				when x"1c"=> keybits(0)(1)<=keypress;
				-- B
				when x"32"=> keybits(0)(2)<=keypress;
				-- C
				when x"21"=> keybits(0)(3)<=keypress;
				-- D
				when x"23"=> keybits(0)(4)<=keypress;
				-- E
				when x"24"=> keybits(0)(5)<=keypress;
				-- F
				when x"2b"=> keybits(0)(6)<=keypress;
				-- G
				when x"34"=> keybits(0)(7)<=keypress;

				-- H
				when x"33"=> keybits(1)(0)<=keypress;
				-- I
				when x"43"=> keybits(1)(1)<=keypress;
				-- J
				when x"3B"=> keybits(1)(2)<=keypress;
				-- K
				when x"42"=> keybits(1)(3)<=keypress;
				-- L
				when x"4B"=> keybits(1)(4)<=keypress;
				-- M
				when x"3A"=> keybits(1)(5)<=keypress;
				-- N
				when x"31"=> keybits(1)(6)<=keypress;
				-- O
				when x"44"=> keybits(1)(7)<=keypress;

				-- P
				when x"4D"=> keybits(2)(0)<=keypress;
				-- Q
				when x"15"=> keybits(2)(1)<=keypress;
				-- R
				when x"2D"=> keybits(2)(2)<=keypress;
				-- S
				when x"1B"=> keybits(2)(3)<=keypress;
				-- T
				when x"2C"=> keybits(2)(4)<=keypress;
				-- U
				when x"3C"=> keybits(2)(5)<=keypress;
				-- V
				when x"2A"=> keybits(2)(6)<=keypress;
				-- W
				when x"1D"=> keybits(2)(7)<=keypress;

				-- X
				when x"22"=> keybits(3)(0)<=keypress;
				-- Y
				when x"35"=> keybits(3)(1)<=keypress;
				-- Z
				when x"1A"=> keybits(3)(2)<=keypress;
				-- F2
				when x"06"=> keybits(3)(4)<=keypress;
				-- F3
				when x"04"=> keybits(3)(5)<=keypress;
				-- F4
				when x"0C"=> keybits(3)(6)<=keypress;
				-- F1
				when x"05"=> keybits(3)(7)<=keypress;

				-- 0
				when x"45"=> keybits(4)(0)<=keypress;
				-- 1
				when x"16"=> keybits(4)(1)<=keypress;
				-- 2
				when x"1E"=> keybits(4)(2)<=keypress;
				-- 3
				when x"26"=> keybits(4)(3)<=keypress;
				-- 4
				when x"25"=> keybits(4)(4)<=keypress;
				-- 5
				when x"2E"=> keybits(4)(5)<=keypress;
				-- 6
				when x"36"=> keybits(4)(6)<=keypress;
				-- 7
				when x"3D"=> keybits(4)(7)<=keypress;

				-- 8
				when x"3E"=> keybits(5)(0)<=keypress;
				-- 9
				when x"46"=> keybits(5)(1)<=keypress;
				-- *:
				when x"0E"|x"4e" => keybits(5)(2)<=keypress;
				-- +;
				when x"4C"=> keybits(5)(3)<=keypress;
				-- <,
				when x"41"=> keybits(5)(4)<=keypress;
				-- =-
				when x"55"|x"7b"=> keybits(5)(5)<=keypress;
				-- >.
				when x"49"=> keybits(5)(6)<=keypress;
				-- ?/
				when x"4A"=> keybits(5)(7)<=keypress;

				-- NL
				when x"5A"=> keybits(6)(0)<=keypress;
				-- CLR
				when x"6C"=> keybits(6)(1)<=keypress;
				-- BRK
				when x"76"=> keybits(6)(2)<=keypress;
				-- up-arrow
				when x"75"=> keybits(6)(3)<=keypress;
				-- dn-arrow
				when x"72"=> keybits(6)(4)<=keypress;
				-- lf-arrow and backspace
				when x"6B"|x"66"=> keybits(6)(5)<=keypress;
				-- rg-arrow
				when x"74"=> keybits(6)(6)<=keypress;
				-- SPA
				when x"29"=> keybits(6)(7)<=keypress;

				-- L-SHIFT R-SHIFT
				when x"12"|x"59"=> keybits(7)(0)<=keypress;
				
				-- numpad *
				when x"7c"=> keybits(5)(2)<=keypress;
								 keybits(7)(0)<=keypress;
				-- numpad +
				when x"79"=> keybits(5)(3)<=keypress;
								 keybits(7)(0)<=keypress;

			   when others =>
				  null;
			  end case;
			  extkey<='0';
			end if; 
     end if;	  
	end if;
  end process;
    	 
  SWRES <= swreset;
  VCUT <= vcutReg;
  PAGE <= pageReg;
  
  keysout(0) <= keybits(0) when A(0)='1' else x"00";
  keysout(1) <= keybits(1) when A(1)='1' else x"00";
  keysout(2) <= keybits(2) when A(2)='1' else x"00";
  keysout(3) <= keybits(3) when A(3)='1' else x"00";
  keysout(4) <= keybits(4) when A(4)='1' else x"00";
  keysout(5) <= keybits(5) when A(5)='1' else x"00";
  keysout(6) <= keybits(6) when A(6)='1' else x"00";
  keysout(7) <= keybits(7) when A(7)='1' else x"00";
  DOUT <= keysout(0) or keysout(1) or keysout(2) or keysout(3) or keysout(4) or keysout(5) or keysout(6) or keysout(7);

  INKP <= inkpulse;
  PAPERP <= paperpulse;
  BORDERP <= borderpulse; 
  
end Behavioral;
