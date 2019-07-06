library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity ram16k is
    Port ( clk : in  STD_LOGIC;
           a : in  STD_LOGIC_VECTOR (13 downto 0);
           din : in  STD_LOGIC_VECTOR (7 downto 0);
           dout : out  STD_LOGIC_VECTOR (7 downto 0);
           wr : in  STD_LOGIC);
end ram16k;

architecture Behavioral of ram16k is

type
  ramarray is array(0 to 16383) of std_logic_vector(7 downto 0);

signal 
  mem : ramarray;
begin

process(clk)
begin
  if rising_edge(clk) then
    dout <= mem(conv_integer(a));
	 if wr='0' then
	   mem(conv_integer(a)) <= din;
	 end if;
  end if;
end process;

end Behavioral;

