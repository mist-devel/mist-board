-- -----------------------------------------------------------------------
--
-- Syntiac's generic VHDL support files.
--
-- -----------------------------------------------------------------------
-- Copyright 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------
--
-- gen_rwram.vhd
--
-- -----------------------------------------------------------------------
--
-- generic ram.
--
-- -----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

-- -----------------------------------------------------------------------

entity gen_ram is
	generic (
		dWidth : integer := 8;
		aWidth : integer := 10
	);
	port (
		clk : in std_logic;
		we : in std_logic;
		addr : in unsigned((aWidth-1) downto 0);
		d : in unsigned((dWidth-1) downto 0);
		q : out unsigned((dWidth-1) downto 0)
	);
end entity;

-- -----------------------------------------------------------------------

architecture rtl of gen_ram is
	subtype addressRange is integer range 0 to ((2**aWidth)-1);
	type ramDef is array(addressRange) of unsigned((dWidth-1) downto 0);
	signal ram: ramDef;

	signal rAddrReg : unsigned((aWidth-1) downto 0);
	signal qReg : unsigned((dWidth-1) downto 0);
begin
-- -----------------------------------------------------------------------
-- Signals to entity interface
-- -----------------------------------------------------------------------
	q <= qReg;

-- -----------------------------------------------------------------------
-- Memory write
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			if we = '1' then
				ram(to_integer(addr)) <= d;
			end if;
		end if;
	end process;
	
-- -----------------------------------------------------------------------
-- Memory read
-- -----------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			qReg <= ram(to_integer(rAddrReg));
			rAddrReg <= addr;
		end if;
	end process;
end architecture;

