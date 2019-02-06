-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Copyright 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------
--
-- 6510 wrapper for 65xx core
-- Adds 8 bit I/O port mapped at addresses $0000 to $0001
--
-- -----------------------------------------------------------------------

library IEEE;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;

-- -----------------------------------------------------------------------

entity cpu_6510 is
	port (
		clk     : in  std_logic;
		enable  : in  std_logic;
		reset   : in  std_logic;
		nmi_n   : in  std_logic;
		nmi_ack : out std_logic;
		irq_n   : in  std_logic;
		rdy     : in  std_logic;

		di      : in  unsigned(7 downto 0);
		do      : out unsigned(7 downto 0);
		addr    : out unsigned(15 downto 0);
		we      : out std_logic;

		diIO    : in  unsigned(7 downto 0);
		doIO    : out unsigned(7 downto 0)
	);
end cpu_6510;

-- -----------------------------------------------------------------------

architecture rtl of cpu_6510 is
	signal localA : std_logic_vector(23 downto 0);
	signal localDi : std_logic_vector(7 downto 0);
	signal localDo : std_logic_vector(7 downto 0);
	signal localWe : std_logic;

	signal currentIO : std_logic_vector(7 downto 0);
	signal ioDir : std_logic_vector(7 downto 0);
	signal ioData : std_logic_vector(7 downto 0);
	
	signal accessIO : std_logic;
begin

	cpu: work.T65
	port map(
		Mode    => "00",
		Res_n   => not reset,
		Enable  => enable,
		Clk     => clk,
		Rdy     => rdy,
		Abort_n => '1',
		IRQ_n   => irq_n,
		NMI_n   => nmi_n,
		SO_n    => '1',
		R_W_n   => localWe,
		A       => localA,
		DI      => localDi,
		DO      => localDo,
		NMI_ack => nmi_ack
	);

	accessIO <= '1' when localA(15 downto 1) = X"000"&"000" else '0';
	localDi  <= localDo when localWe = '0' else std_logic_vector(di) when accessIO = '0' else ioDir when localA(0) = '0' else currentIO;

	process(clk)
	begin
		if rising_edge(clk) then
			if accessIO = '1' then
				if localWe = '0' and enable = '1' then
					if localA(0) = '0' then
						ioDir <= localDo;
					else
						ioData <= localDo;
					end if;
				end if;
			end if;
			if reset = '1' then
				ioDir <= (others => '0');
			end if;
		end if;
	end process;

	process(clk)
	begin
		if rising_edge(clk) then
			for i in 0 to 7 loop
				if ioDir(i) = '0' then
					currentIO(i) <= std_logic(diIO(i));
				else
					currentIO(i) <= ioData(i);
				end if;
			end loop;
		end if;
	end process;
	
	-- Cunnect zee wires
	addr <= unsigned(localA(15 downto 0));
	do <= unsigned(localDo);
	we <= not localWe;
	doIO <= unsigned(currentIO);
end architecture;
