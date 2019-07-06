--
-- HT 1080Z (TSR-80 clone) video controller PAL/VGA capable
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

entity videoctrl is
	Generic (
		H_START : integer := 42+84+81-16;
		V_START : integer := 2+28+((266-192)/2)+4
	 );
    Port (   
	        reset : in  STD_LOGIC;
		     clk42 : in  STD_LOGIC;
			   --clk7 : in  STD_LOGIC;
               a : in  STD_LOGIC_VECTOR (13 downto 0);
             din : in  STD_LOGIC_VECTOR (7 downto 0);
            dout : out STD_LOGIC_VECTOR (7 downto 0);
            mreq : in  STD_LOGIC;
            iorq : in  STD_LOGIC;
              wr : in  STD_LOGIC;
				  cs : in  STD_LOGIC;
				hz60 : in  STD_LOGIC;
				vcut : in  STD_LOGIC;
				vvga : in  STD_LOGIC;
				page : in  STD_LOGIC;
				inkp : in  STD_LOGIC;
			 paperp : in  STD_LOGIC;
			borderp : in  STD_LOGIC;
			oddline : out STD_LOGIC;
            rgbi : out STD_LOGIC_VECTOR (3 downto 0);	
				pclk : out STD_LOGIC;
           hsync : out STD_LOGIC;
           vsync : out STD_LOGIC);
end videoctrl;

architecture Behavioral of videoctrl is

type videomem is array(0 to 1023) of std_logic_vector(7 downto 0);

type charmem is array(0 to 4095) of std_logic_vector(7 downto 0);

signal vidmem : videomem:=(
others => x"00"
);

signal chrmem : charmem:=(
 --[PATCH_START]
x"0e",x"11",x"15",x"17",x"16",x"10",x"0f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"04",x"0a",x"11",x"11",x"1f",x"11",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1e",x"09",x"09",x"0e",x"09",x"09",x"1e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"11",x"10",x"10",x"10",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1e",x"09",x"09",x"09",x"09",x"09",x"1e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1f",x"10",x"10",x"1e",x"10",x"10",x"1f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1f",x"10",x"10",x"1e",x"10",x"10",x"10",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0f",x"11",x"10",x"10",x"13",x"11",x"0f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"11",x"11",x"1f",x"11",x"11",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"04",x"04",x"04",x"04",x"04",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"01",x"01",x"01",x"01",x"01",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"12",x"14",x"18",x"14",x"12",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"10",x"10",x"10",x"10",x"10",x"10",x"1f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"1b",x"15",x"15",x"15",x"11",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"11",x"19",x"15",x"13",x"11",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"11",x"11",x"11",x"11",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1e",x"11",x"11",x"1e",x"10",x"10",x"10",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"11",x"11",x"11",x"15",x"12",x"0d",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1e",x"11",x"11",x"1e",x"14",x"12",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"11",x"10",x"0e",x"01",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1f",x"15",x"04",x"04",x"04",x"04",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"11",x"11",x"11",x"11",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"11",x"11",x"0a",x"0a",x"04",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"11",x"11",x"15",x"15",x"15",x"0a",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"11",x"0a",x"04",x"0a",x"11",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"11",x"0a",x"04",x"04",x"04",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1f",x"01",x"02",x"04",x"08",x"10",x"1f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"04",x"0e",x"15",x"04",x"04",x"04",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"10",x"08",x"04",x"02",x"01",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"04",x"04",x"04",x"04",x"15",x"0e",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"04",x"0a",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"00",x"00",x"1f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"04",x"04",x"04",x"04",x"04",x"00",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0a",x"0a",x"0a",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0a",x"0a",x"1f",x"0a",x"1f",x"0a",x"0a",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"04",x"0f",x"14",x"0e",x"05",x"1e",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"18",x"19",x"02",x"04",x"08",x"13",x"03",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"08",x"14",x"14",x"08",x"15",x"12",x"0d",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"04",x"04",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"04",x"08",x"10",x"10",x"10",x"08",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"04",x"02",x"01",x"01",x"01",x"02",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"04",x"15",x"0e",x"04",x"0e",x"15",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"04",x"04",x"1f",x"04",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"04",x"04",x"08",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"1f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"00",x"00",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"01",x"02",x"04",x"08",x"10",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"11",x"13",x"15",x"19",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"04",x"0c",x"04",x"04",x"04",x"04",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"11",x"01",x"0e",x"10",x"10",x"1f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1f",x"01",x"02",x"06",x"01",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"02",x"06",x"0a",x"1f",x"02",x"02",x"02",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1f",x"10",x"1e",x"01",x"01",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"07",x"08",x"10",x"1e",x"11",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1f",x"01",x"01",x"02",x"04",x"08",x"10",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"11",x"11",x"0e",x"11",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"11",x"11",x"0f",x"01",x"02",x"1c",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"04",x"00",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"04",x"00",x"04",x"04",x"08",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"02",x"04",x"08",x"10",x"08",x"04",x"02",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"1f",x"00",x"1f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"08",x"04",x"02",x"01",x"02",x"04",x"08",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"11",x"01",x"06",x"04",x"00",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"11",x"15",x"17",x"16",x"10",x"0f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"04",x"0a",x"11",x"11",x"1f",x"11",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1e",x"09",x"09",x"0e",x"09",x"09",x"1e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"11",x"10",x"10",x"10",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1e",x"09",x"09",x"09",x"09",x"09",x"1e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1f",x"10",x"10",x"1e",x"10",x"10",x"1f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1f",x"10",x"10",x"1e",x"10",x"10",x"10",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0f",x"11",x"10",x"10",x"13",x"11",x"0f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"11",x"11",x"1f",x"11",x"11",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"04",x"04",x"04",x"04",x"04",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"01",x"01",x"01",x"01",x"01",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"12",x"14",x"18",x"14",x"12",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"10",x"10",x"10",x"10",x"10",x"10",x"1f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"1b",x"15",x"15",x"15",x"11",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"11",x"19",x"15",x"13",x"11",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"11",x"11",x"11",x"11",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1e",x"11",x"11",x"1e",x"10",x"10",x"10",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"11",x"11",x"11",x"15",x"12",x"0d",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1e",x"11",x"11",x"1e",x"14",x"12",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0e",x"11",x"10",x"0e",x"01",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1f",x"15",x"04",x"04",x"04",x"04",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"11",x"11",x"11",x"11",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"11",x"11",x"0a",x"0a",x"04",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"11",x"11",x"15",x"15",x"15",x"0a",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"11",x"0a",x"04",x"0a",x"11",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"11",x"11",x"0a",x"04",x"04",x"04",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1f",x"01",x"02",x"04",x"08",x"10",x"1f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"1c",x"10",x"10",x"10",x"10",x"10",x"1c",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"10",x"08",x"04",x"02",x"01",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"07",x"01",x"01",x"01",x"01",x"01",x"07",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"04",x"0a",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"00",x"00",x"1f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"06",x"06",x"04",x"02",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"0e",x"01",x"0f",x"11",x"0f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"10",x"10",x"1e",x"11",x"11",x"11",x"1e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"0f",x"10",x"10",x"10",x"0f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"01",x"01",x"0f",x"11",x"11",x"11",x"0f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"0e",x"11",x"1f",x"10",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"02",x"04",x"04",x"0e",x"04",x"04",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"0f",x"11",x"11",x"11",x"0f",x"01",x"06",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"10",x"10",x"1e",x"11",x"11",x"11",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"04",x"00",x"0c",x"04",x"04",x"04",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"02",x"00",x"06",x"02",x"02",x"02",x"12",x"0c",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"08",x"08",x"09",x"0a",x"0c",x"0a",x"09",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0c",x"04",x"04",x"04",x"04",x"04",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"1a",x"15",x"15",x"15",x"15",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"1e",x"11",x"11",x"11",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"0e",x"11",x"11",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"1e",x"11",x"11",x"11",x"1e",x"10",x"10",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"0f",x"11",x"11",x"11",x"0f",x"01",x"01",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"0b",x"0c",x"08",x"08",x"08",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"0f",x"10",x"0e",x"01",x"1e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"04",x"0e",x"04",x"04",x"04",x"02",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"11",x"11",x"11",x"11",x"0e",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"11",x"11",x"11",x"0a",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"11",x"11",x"15",x"15",x"0a",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"11",x"0a",x"04",x"0a",x"11",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"11",x"11",x"11",x"11",x"0f",x"01",x"06",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"1f",x"02",x"04",x"08",x"1f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"02",x"04",x"04",x"08",x"04",x"04",x"02",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"04",x"04",x"04",x"00",x"04",x"04",x"04",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"08",x"04",x"04",x"02",x"04",x"04",x"08",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"08",x"15",x"02",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"0a",x"15",x"0a",x"15",x"0a",x"15",x"0a",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"00",x"00",x"00",x"00",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"38",x"38",x"38",x"38",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"07",x"07",x"07",x"07",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00",
x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"3f",x"00",x"00",x"00",x"00"
--[PATCH_END]
 --others => x"ff"
);

-- 0  1    2
-- 21 10.5 5.25
signal clkdiv : std_logic_vector(2 downto 0);
alias   clk21 : std_logic is clkdiv(0);
alias clk10_5 : std_logic is clkdiv(1);
alias clk5_25 : std_logic is clkdiv(2);

signal clk21_en   : std_logic;
signal clk10_5_en : std_logic;
signal clk5_25_en : std_logic;

signal hctr : std_logic_vector(9 downto 0);
signal vctr : std_logic_vector(8 downto 0);
signal vpos : std_logic_vector(3 downto 0); -- line pos in a chr 0..11
signal hpos : std_logic_vector(2 downto 0); -- pixel pos in a chr 0..5
signal hstart : std_logic_vector(9 downto 0);
signal vstart : std_logic_vector(8 downto 0);
signal vend : std_logic_vector(8 downto 0);

signal pxclk : std_logic;
signal pxclk_en : std_logic;
signal xpxclk : std_logic;
signal xpxclk_en : std_logic;

signal hact,vact : std_logic;


signal border : std_logic_vector(3 downto 0) := "0010";
signal  paper : std_logic_vector(3 downto 0) := "0000";
signal    ink : std_logic_vector(3 downto 0) := "1000";
signal  pixel : std_logic_vector(3 downto 0);

signal screen : std_logic;
signal hblank,vblank,blank : std_logic;

signal vaVert : std_logic_vector(3 downto 0); -- vertical line
signal vaHoriz : std_logic_vector(5 downto 0); -- horizontal columnt pos

signal chraddr : std_logic_vector(11 downto 0); -- character bitmap data address in the charmem
signal chrCode : std_logic_vector(7 downto 0);
signal chrGrap : std_logic_vector(7 downto 0);
signal shiftReg : std_logic_vector(7 downto 0);

signal xpxsel : std_logic_vector(1 downto 0);
signal     v1 : std_logic;

signal rinkp,rpaperp,rborderp : std_logic; 

begin
 
--pxclk <= clk10_5;
--xpxclk <= clk10_5 when vcut='0' else clk5_25;
--hstart <= conv_std_logic_vector(H_START,10);
--vstart <= conv_std_logic_vector(V_START,9); 
--vend <= conv_std_logic_vector(311,9); 

pxclk <= clk10_5 when vvga='0' else clk21;
pxclk_en <= clk10_5_en when vvga='0' else clk21_en;
xpxsel <= vvga & vcut;
with xpxsel select xpxclk <=
  clk10_5 when "00",
  clk5_25 when "01",
    clk21 when "10",
  clk10_5 when others;

with xpxsel select xpxclk_en <=
  clk10_5_en when "00",
  clk5_25_en when "01",
			'1' when "10",
  clk10_5_en when others;

hstart <= conv_std_logic_vector(H_START,10) when vvga='0' else conv_std_logic_vector(H_START,10);
vstart <= conv_std_logic_vector(V_START,9) when hz60='0' else conv_std_logic_vector(V_START-30,9);
vend <= conv_std_logic_vector(311,9) when hz60='0' else conv_std_logic_vector(262,9); 

process(clk42)
begin
  if rising_edge(clk42) then
    clkdiv <= clkdiv + 1;  
  end if;
end process;

clk10_5_en <= '1' when clkdiv(1 downto 0) = "01" else '0';
clk21_en   <= '1' when clkdiv(0) = '0' else '0';
clk5_25_en <= '1' when clkdiv = "011" else '0';

process(RESET,clk42)
begin
 if RESET='0' then
   ink <= "1000";
	paper <= "0000";
	border <= "0000";
 elsif rising_edge(clk42) then
  if clk10_5_en = '1' then
		rinkp <= INKP;
		rpaperp <= PAPERP;
		rborderp <= BORDERP;
		if rinkp='0' and INKP='1' then
		  ink <= ink+1;
		end if;
		if rpaperp='0' and PAPERP='1' then
		  paper <= paper+1;
		end if;
		if rborderp='0' and BORDERP='1' then
		  border <= border+1;
		end if;					  
			
	 if iorq='0' and wr='0' and a(7 downto 2)="000000" then
	   case a(1 downto 0) is
		  when "00"=> ink<=din(3 downto 0);
		  when "01"=> paper<=din(3 downto 0);
		  when "10"=> border<=din(3 downto 0);		  
		  when others=>null;
		end case;
	 end if;
  end if;  
 end if;
end process;


process(clk42)
begin
  if rising_edge(clk42) then
    chrCode <= vidmem(conv_integer( vaVert & vaHoriz ));
	 chrGrap <= chrmem(conv_integer( chrCode & vpos ));
	 dout <= vidmem(conv_integer( a(9 downto 0) ));
	 if cs='0' and wr='0' then
	   vidmem(conv_integer( a(9 downto 0) )) <= din;
	 end if;
	end if;
end process;

-- h and v counters
-- 10.5 MHz pixelclock => 672 pixels per scan line
-- 312 scanlines
-- 64*6 pixels active screen = 384 pixels
-- visible area: 52*10.5 = 546
-- Horizontal: |42T-hsync|84T-porch|81T-border|384T-screen|81T-border|
process(clk42)
begin
  if rising_edge(clk42) then
    if pxclk_en = '1' then
     if hctr=671 then
	    hctr<="0000000000";
		 v1 <= not v1; 
		 if vctr>=vend then
		   vctr<="000000000";
			v1 <= '0';
		 else
			--vctr<=vctr+1;
			if v1='1' or vvga='0' then 
			  vctr<=vctr+1;
			end if; 
		 end if;
	  else
	    hctr<=hctr+1;
	  end if;
	 end if;
  end if;
end process;

--process(pxclk)
--begin
-- if falling_edge(pxclk) then
--	
--	-- 12*10.5
--	if hctr<126 or hctr>654 then
--	  hblank <= '0';
--	else
--	  hblank <= '1';
--	end if;
--	
--	if hctr<42 then -- 4*10.5
--	  hsync <= '0';
--	else
--	  hsync <= '1';
--	end if;
--	
--	if vctr<6 or vctr>309 then
--	  vblank <= '0';
--	else
--	  vblank <= '1';
--	end if;
--
--	if vctr<2 then
--	  vsync <= '0';
--	else
--	  vsync <= '1';
--	end if;
--		
-- end if;	 	 
--end process;

process(clk42)
begin
 if rising_edge(clk42) then
  if pxclk_en = '1' then
	if vvga='0' then
		-- 12*10.5
		if hctr<126 or hctr>654 then
		  hblank <= '0';
		else
		  hblank <= '1';
		end if;
	else
	   -- VGA 6us
		-- 
		--if hctr<64 or hctr>662 then
		if hctr<120 or hctr>654 then
		  hblank <= '0';
		else
		  hblank <= '1';
		end if;	
	end if;
	
	if vvga='0' then	
		if hctr<42 then -- 4*10.5
		  hsync <= '0';
		else
		  hsync <= '1';
		end if;
		
		if vctr<6 or vctr>309 then
		  vblank <= '0';
		else
		  vblank <= '1';
		end if;

   else
		if hctr<79 then -- 4*21
		  hsync <= '0';
		else
		  hsync <= '1';
		end if;	
		
		if vctr<16 or vctr>257 then
		  vblank <= '0';
		else
		  vblank <= '1';
		end if;
		
   end if;
	

	if vctr<2 then
	  vsync <= '0';
	else
	  vsync <= '1';
	end if;
  end if;		
 end if;	 	 
end process; 

hact <= '1' when hctr>=hstart and hctr<hstart+384 else '0';
vact <= '1' when vctr>=vstart and vctr<vstart+192 else '0';


process(clk42)
begin
  if rising_edge(clk42) then   
   if xpxclk_en = '1' then
    if hact='1' and vact='1' then
	   if hpos=5 then
		  hpos <= "000";
		  vaHoriz <= vaHoriz+1;
		  shiftReg <= chrGrap;
		else
		  shiftReg <= shiftReg(6 downto 0) & '0';
		  hpos <= hpos+1;
		end if;
	   screen<= '1';
	 else
	   screen<= '0';
		hpos <= "101";
		vaHoriz <= (page and vcut) & "00000"; 
		shiftReg <= "00000000"; -- keep it clear
		if vctr=0 then
		  -- new frame
		  vaVert<= "0000";
		  vpos <= "0000";
		elsif vact='1' and hctr=hstart+384+2 and (v1='1' or vvga='0') then
		  -- end of a scanline
		  if vpos=11 then
		    vpos <= "0000";
			 vaVert <= vaVert+1;
		  else
		    vpos <= vpos+1;
		  end if;
		end if;
	 end if;
	end if;
  end if;
end process; 

pixel <= border when screen='0' else paper when shiftReg(5)='0' else ink;
blank <= hblank and vblank;
rgbi <= pixel when blank='1' else "0000";
pclk <= clk10_5 when vvga='0' else clk21;
oddline <= v1;

end Behavioral;

