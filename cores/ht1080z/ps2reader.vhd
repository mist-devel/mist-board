----------------------------------------------------------------------------------
-- Company: 		Digilent Inc.
-- Engineer: 		Claudia Goga
-- 
-- Create Date:    22:33:35 11/25/06 
-- Module Name:    PS2_Reader - Behavioral 
-- Target Devices: CoolRunner2 CPLD
-- Tool versions:  Xilinx ISE v7.1i 
-- Description: 
--		This module reads scan codes from the PS2 Port. Every time a 
--		new scan code is entirely received it enables the fRd signal for one
--		main clock period.
--
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;


entity ps2reader is
    Port ( mclk  : in std_logic;                        -- System Clock 
	 		  PS2C : in std_logic;                         -- PS2 Clock
           PS2D : in std_logic;                         -- PS2 data
			  rst: in std_logic;                           -- Reset BTN0
			  Ps2Dout : out std_logic_vector(7 downto 0);  -- out data
           fRd : out std_logic);                        -- data valid flag
end ps2reader;

architecture Behavioral of ps2reader is

------------------------------------------------------------------------
--				 SIGNAL and CONSTANT DECLARATIONS
------------------------------------------------------------------------
--The constants below define state codes for the PS2 Keyboard 
--reader using ONE HOT encoding.

constant idle:         std_logic_vector (5 downto 0):="000000";
constant shift_data:   std_logic_vector (5 downto 0):="000001";
constant check_parity: std_logic_vector (5 downto 0):="000010";
constant check_stopbit:std_logic_vector (5 downto 0):="000100";
constant frame_error:  std_logic_vector (5 downto 0):="001000";
constant parity_error: std_logic_vector (5 downto 0):="010000";
constant end_char:     std_logic_vector (5 downto 0):="100000";

--state register and next state register for the FSM
signal state, next_state: std_logic_vector (5 downto 0):=idle;

signal D_PS2C: std_logic:='0';                     -- debounced PS2C
signal Q1, Q2: std_logic:='0';

--shift register; stores the received bits
signal REG: std_logic_vector(7 downto 0):=X"00";

signal ptysum: std_logic:='0';	                  -- parity sum
signal ptycheck: std_logic:='0';	                  -- parity check bit

signal cnt: integer range 0 to 7:=0;               -- counter

--The attributes below prevent the ISE compiler from 
--optimizing the state machines. The states will be implemented as 
--described in the constant declarations above.

attribute fsm_extract : string;
attribute fsm_extract of state: signal is "no"; 
attribute fsm_extract of next_state: signal is "no"; 

attribute fsm_encoding : string;
attribute fsm_encoding of state: signal is "user"; 
attribute fsm_encoding of next_state: signal is "user"; 

attribute signal_encoding : string;
attribute signal_encoding of state: signal is "user"; 
attribute signal_encoding of next_state: signal is "user";

begin

----------------------------------------------------------------------
--				 MODULE IMPLEMENTATION
----------------------------------------------------------------------

----------------- Sample Keyboard Inputs -----------------------------

debounce: process (mclk, PS2C, Q1, Q2)
begin
	if mclk'event and mclk='1' then
		 Q1<=PS2C;
		 Q2<=Q1;
	end if;
end process debounce;

D_PS2C<= (NOT Q1) and Q2;

----------------- Synchronization Process ----------------------------

regstate: process (mclk, next_state, rst)
begin
	if rst='1' then
			 state<=idle;	                     -- state machine reset
	elsif mclk'EVENT and mclk='1' then
			 state<=next_state;
	end if;
end process regstate;

-------------------- State Transitions -------------------------------

transition: process (state, D_PS2C, PS2D, cnt, ptycheck)
begin
case state is
	when idle=>-- idle
		if D_PS2C='1' and PS2D='0' then        -- check start bit
			 next_state<=shift_data;
		else
			 next_state<=idle;
		end if;

	when shift_data=>                         -- shift in data
		if D_PS2C='1' and cnt=7 then
			 next_state<=check_parity;          -- go and check parity
		else
			 next_state<=shift_data;
		end if;

	when check_parity=>                       -- check parity
		if D_PS2C='1' and PS2D=ptycheck then
			 next_state<=check_stopbit;         -- valid parity bit 
			 									         -- go and check stopbit
		elsif D_PS2C='1' then
			 next_state<=parity_error;          -- parity error
		else
			 next_state<=check_parity;
		end if;

	when check_stopbit=>                      -- check stopbit;
		if D_PS2C='1' and PS2D='1' then
			 next_state<=end_char;              -- valid stopbit, end Char
		elsif D_PS2C='1' then
			 next_state<=frame_error;           -- Frame Error
		else
			 next_state<=check_stopbit;
		end if;

	when frame_error=>                        -- Frame Error	
		next_state<=idle;

	when parity_error=>                       -- Parity Error
		next_state<=idle;  

	when end_char=>                           -- end Char
		next_state<=idle;

	when others => next_state<=idle;
end case;
end process transition;


------Counting bits and registering when state=shift_data--------------- 

regin: process (mclk, D_PS2C, PS2D, cnt, ptysum, state)
begin
if state/=shift_data then 
		cnt<=0;
		ptysum<='0';
elsif mclk'EVENT and mclk='1' then
	if D_PS2C='1' then
		ptysum<=ptysum XOR PS2D;                 -- calculating the parity sum
		REG(7 downto 0)<=PS2D&REG(7 downto 1);   -- shifting data into register
														      
		if cnt=7 then
			cnt<=0;
		else
			cnt<=cnt+1;
		end if;
	end if;
end if;
end process regin;

------------------PARITIY SUM-------------------------------------------

parity_sum: process (mclk, D_PS2C, PS2D, cnt, state, ptysum)
begin
if mclk'EVENT and mclk='1' then
	if state=shift_data and D_PS2C='1' and cnt=7 then
			ptycheck<=(NOT ptysum) XOR PS2D;       --parity check bit
	end if;
end if;
end process parity_sum; 

----------------OUTPUT ASSIGNEMENT--------------------------------------

Ps2Dout<=REG;
fRd<='1' when state=end_char else '0';

end Behavioral;