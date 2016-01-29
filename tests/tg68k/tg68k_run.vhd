-- https://raw.githubusercontent.com/rkrajnc/minimig-de1/master/bench/cpu_cache_sdram/cpu_cache_sdram_tb.v
-- http://www.asic-world.com/vhdl/first1.html

library ieee;
use work.mem_if.all;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;
use std.textio.all;

-- `timescale 1us/1ns
    
entity tg68k_run is
end;

architecture tg68k_run of tg68k_run is

  -- include tg68k
component TG68KdotC_Kernel
generic(
  SR_Read : integer:= 2;         --0=>user,   1=>privileged,      2=>switchable with CPU(0)
  VBR_Stackframe : integer:= 2;  --0=>no,     1=>yes/extended,    2=>switchable with CPU(0)
  extAddr_Mode : integer:= 2;    --0=>no,     1=>yes,    2=>switchable with CPU(1)
  MUL_Mode : integer := 2;	   --0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no MUL,  
  DIV_Mode : integer := 2;	   --0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no DIV,  
  BitField : integer := 2;		   --0=>no,     1=>yes,    2=>switchable with CPU(1)  
  BarrelShifter : integer := 2		   --0=>no,     1=>yes,    2=>switchable with CPU(1)  
  );
  port (clk               	: in std_logic;
        nReset                  : in std_logic;   --low active
        clkena_in               : in std_logic;
        data_in                 : in std_logic_vector(15 downto 0);
        IPL                     : in std_logic_vector(2 downto 0):="111";
        IPL_autovector          : in std_logic;
        berr                    : in std_logic;   -- only 68000 sp dummy
        CPU                     : in std_logic_vector(1 downto 0);
        addr_out                : out std_logic_vector(31 downto 0);
        data_write              : out std_logic_vector(15 downto 0);
        nWr                     : out std_logic;
        nUDS, nLDS              : out std_logic;
        busstate                : out std_logic_vector(1 downto 0);
        nResetOut               : out std_logic;
        FC                      : out std_logic_vector(2 downto 0);
        clr_berr                : out std_logic;
        -- for debug
        skipFetch               : out std_logic;
        regin_out               : out std_logic_vector(31 downto 0)
   );
end component ;

signal   clk      : std_logic := '0';
signal   reset_n  : std_logic := '1';
signal   din      : std_logic_vector(15 downto 0);
signal   dout     : std_logic_vector(15 downto 0);
signal   addr     : std_logic_vector(31 downto 0);
signal   busstate : std_logic_vector(1 downto 0);
signal   uds_n    : std_logic;
signal   lds_n    : std_logic;

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
      addr_out => addr,
      nUDS => uds_n,
      nLDS => lds_n,
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
    variable c : std_logic;
    variable bs : std_logic_vector(1 downto 0);
    variable ds : std_logic_vector(1 downto 0);
    variable a : std_logic_vector(31 downto 0);
    variable do : std_logic_vector(15 downto 0);
    variable di : std_logic_vector(15 downto 0);
  begin
    -- wire memory
    c := clk;
    bs := busstate;
    a := addr;
    di := dout;
    ds := not lds_n & not uds_n;
    mem_if_c(c,bs,ds,a,di,do);
    din <= do;    
  end process memory;

end tg68k_run;

