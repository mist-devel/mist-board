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
	generic (
		pipelineOpcode : boolean;
		pipelineAluMux : boolean;
		pipelineAluOut : boolean
	);
	port (
		clk : in std_logic;
		enable : in std_logic;
		reset : in std_logic;
		nmi_n : in std_logic;
		nmi_ack : out std_logic;
		irq_n : in std_logic;

		di : in unsigned(7 downto 0);
		do : out unsigned(7 downto 0);
		addr : out unsigned(15 downto 0);
		we : out std_logic;

		diIO : in unsigned(7 downto 0);
		doIO : out unsigned(7 downto 0);
		
		debugOpcode : out unsigned(7 downto 0);
		debugPc : out unsigned(15 downto 0);
		debugA : out unsigned(7 downto 0);
		debugX : out unsigned(7 downto 0);
		debugY : out unsigned(7 downto 0);
		debugS : out unsigned(7 downto 0)
	);
end cpu_6510;

-- -----------------------------------------------------------------------

architecture rtl of cpu_6510 is
	signal localA : unsigned(15 downto 0);
	signal localDi : unsigned(7 downto 0);
	signal localDo : unsigned(7 downto 0);
	signal localWe : std_logic;

	signal currentIO : unsigned(7 downto 0);
	signal ioDir : unsigned(7 downto 0);
	signal ioData : unsigned(7 downto 0);
	
	signal accessIO : std_logic;
begin
	cpuInstance: entity work.cpu65xx(fast)
		generic map (
			pipelineOpcode => pipelineOpcode,
			pipelineAluMux => pipelineAluMux,
			pipelineAluOut => pipelineAluOut
		)
		port map (
			clk => clk,
			enable => enable,
			reset => reset,
			nmi_n => nmi_n,
			nmi_ack => nmi_ack,
			irq_n => irq_n,

			di => localDi,
			do => localDo,
			addr => localA,
			we => localWe,

			debugOpcode => debugOpcode,
			debugPc => debugPc,
			debugA => debugA,
			debugX => debugX,
			debugY => debugY,
			debugS => debugS
		);
		
	process(localA)
	begin
		accessIO <= '0';
		if localA(15 downto 1) = 0 then
			accessIO <= '1';
		end if;
	end process;
	
	process(di, localA, ioDir, currentIO, accessIO)
	begin
		localDi <= di;
		if accessIO = '1' then
			if localA(0) = '0' then
				localDi <= ioDir;
			else
				localDi <= currentIO;
			end if;
		end if;
	end process;
	
	process(clk)
	begin
		if rising_edge(clk) then
			if accessIO = '1' then
				if localWe = '1'
				and enable = '1' then
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
	
	process(ioDir, ioData, diIO)
	begin
		for i in 0 to 7 loop
			if ioDir(i) = '0' then
				currentIO(i) <= diIO(i);
			else
				currentIO(i) <= ioData(i);
			end if;
		end loop;
	end process;
	
	-- Cunnect zee wires
	addr <= localA;
	do <= localDo;
	we <= localWe;
	doIO <= currentIO;
end architecture;
