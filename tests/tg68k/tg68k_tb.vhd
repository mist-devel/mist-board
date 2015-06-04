-- https://raw.githubusercontent.com/rkrajnc/minimig-de1/master/bench/cpu_cache_sdram/cpu_cache_sdram_tb.v
-- http://www.asic-world.com/vhdl/first1.html

library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;
use std.textio.all;
use work.testcode_pack.all;

-- `timescale 1us/1ns
    
entity tg68k_tb is
end;

architecture tg68k_tb of tg68k_tb is

  -- include tg68k
component TG68KdotC_Kernel
generic(
  SR_Read : integer:= 2;         --0=>user,   1=>privileged,      2=>switchable with CPU(0)
  VBR_Stackframe : integer:= 2;  --0=>no,     1=>yes/extended,    2=>switchable with CPU(0)
  extAddr_Mode : integer:= 2;    --0=>no,     1=>yes,    2=>switchable with CPU(1)
  MUL_Mode : integer := 2;	   --0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no MUL,  
  DIV_Mode : integer := 2;	   --0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no DIV,  
  BitField : integer := 2		   --0=>no,     1=>yes,    2=>switchable with CPU(1)  
  );
  port (clk               	: in std_logic;
        nReset                  : in std_logic;   --low active
        clkena_in               : in std_logic;
        data_in                 : in std_logic_vector(15 downto 0);
        IPL                     : in std_logic_vector(2 downto 0):="111";
        IPL_autovector          : in std_logic;
        berr                    : in std_logic;   -- only 68000 sp dummy
        CPU                     : in std_logic_vector(1 downto 0);
        addr                    : buffer std_logic_vector(31 downto 0);
        data_write              : out std_logic_vector(15 downto 0);
        nWr                     : out std_logic;
        nUDS, nLDS              : out std_logic;
        busstate                : out std_logic_vector(1 downto 0);
        nResetOut               : out std_logic;
        FC                      : out std_logic_vector(2 downto 0);
        clr_berr                : out std_logic;
        -- for debug
        db_OP1out               : out std_logic_vector(31 downto 0);
        db_OP2out               : out std_logic_vector(31 downto 0);
        skipFetch               : out std_logic;
        regin                   : buffer std_logic_vector(31 downto 0)
   );
end component ;

signal   clk      : std_logic := '0';
signal   reset_n  : std_logic := '1';
signal   din      : std_logic_vector(15 downto 0);
signal   dout     : std_logic_vector(15 downto 0);
signal   addr     : std_logic_vector(31 downto 0);
signal   busstate : std_logic_vector(1 downto 0);

type ram_t is array(0 to 255) of std_logic_vector(15 downto 0);
signal ram : ram_t;

begin

  -- wire up cpu
  tg68k : TG68KdotC_Kernel 
    port map (
      clk => clk,
      nReset => reset_n,
      clkena_in => '1',
      data_in => din,
      data_write => dout,
      IPL => "111",
      IPL_autovector => '0',
      berr => '0',
      CPU => "11",  -- 00=68000, 11=68020
      addr => addr,
      busstate => busstate
      );

-- generate a 32mhz clock
  clock : process
  begin
    wait for 30 ns; clk  <= not clk;
  end process clock;

  stimulus : process
  begin
    report "start";

    reset_n <= '0';
    wait for 125 ns; reset_n <= '1';
    
    assert false report "tg68k out of reset"
      severity note;
    
    wait;
  end process stimulus;

  memory : process (clk)
    variable c_str : line;
  begin
    if (clk = '0' and clk'event) then
      if(busstate = "11") then 
        if(unsigned(addr) >= x"55aa0000" and unsigned(addr) < (x"55aa0000"+512)) then
          ram(to_integer((unsigned(addr) - x"55aa0000"))/2) <= dout;
        end if;
      elsif(busstate = "00" or busstate = "10") then 
        if (unsigned(addr) < 256) then
          case addr is
            when x"00000000" => din <= x"55aa";  -- stack at 55aa0100
            when x"00000002" => din <= x"0100";
            when x"00000004" => din <= x"00fc";  -- tos rom base -> fc0000
            when x"00000006" => din <= x"0000";
            when x"00000024" => din <= x"00fc";  -- trace vector -> fc0100
            when x"00000026" => din <= x"0100";
            when others      => din <= x"0000";
          end case;
        elsif(unsigned(addr) >= x"00fc0000" and unsigned(addr) < (x"00fc0000"+512)) then
          din <= testcode_rom(to_integer((unsigned(addr) - x"00fc0000"))/2);
        elsif(unsigned(addr) >= x"55aa0000" and unsigned(addr) < (x"55aa0000"+512)) then
          din <= ram(to_integer((unsigned(addr) - x"55aa0000"))/2);
        else
          din <= (others=>'-');
        end if;
      end if;
    end if;
  end process memory;
  
end tg68k_tb;

