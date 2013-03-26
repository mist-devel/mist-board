------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- Copyright (c) 2009-2011 Tobias Gubener                                   -- 
-- Subdesign fAMpIGA by TobiFlex                                            --
--                                                                          --
-- This source file is free software: you can redistribute it and/or modify --
-- it under the terms of the GNU General Public License as published        --
-- by the Free Software Foundation, either version 3 of the License, or     --
-- (at your option) any later version.                                      --
--                                                                          --
-- This source file is distributed in the hope that it will be useful,      --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of           --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            --
-- GNU General Public License for more details.                             --
--                                                                          --
-- You should have received a copy of the GNU General Public License        --
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.    --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------
 
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity sdram is
port
	(
	sdata		: inout std_logic_vector(15 downto 0);
	sdaddr		: out std_logic_vector(12 downto 0);
	dqm			: out std_logic_vector(1 downto 0);
	sd_cs		: out std_logic_vector(3 downto 0);
	ba			: buffer std_logic_vector(1 downto 0);
	sd_we		: out std_logic;
	sd_ras		: out std_logic;
	sd_cas		: out std_logic;

	sysclk		: in std_logic;
	reset_in	: in std_logic;
	
	hostWR		: in std_logic_vector(15 downto 0);
	hostAddr	: in std_logic_vector(23 downto 0);
	hostState	: in std_logic_vector(2 downto 0);
	hostL		: in std_logic;
	hostU		: in std_logic;
	cpuWR		: in std_logic_vector(15 downto 0);
	cpuAddr		: in std_logic_vector(24 downto 1);
	cpuU		: in std_logic;
	cpuL		: in std_logic;
	cpustate	: in std_logic_vector(5 downto 0); -- clkena & slower(1 downto 0) & ramcs & state;
	cpu_dma		: in std_logic;
	chipWR		: in std_logic_vector(15 downto 0);
	chipAddr	: in std_logic_vector(23 downto 1);
	chipU		: in std_logic;
	chipL		: in std_logic;
	chipRW		: in std_logic;
	chip_dma	: in std_logic;
	c_7m		: in std_logic;
	
	hostRD		: out std_logic_vector(15 downto 0);
	hostena		: buffer std_logic;
	cpuRD		: out std_logic_vector(15 downto 0);
	cpuena		: out std_logic;
	chipRD		: out std_logic_vector(15 downto 0);
	reset_out	: out std_logic;
	enaRDreg	: out std_logic;
	enaWRreg	: buffer std_logic;
	ena7RDreg	: out std_logic;
	ena7WRreg	: out std_logic
--	c_7m		: out std_logic
	);
end;

architecture rtl of sdram is


signal initstate	:std_logic_vector(3 downto 0);
signal cas_sd_cs	:std_logic_vector(3 downto 0);
signal cas_sd_ras	:std_logic;
signal cas_sd_cas	:std_logic;
signal cas_sd_we 	:std_logic;
signal cas_dqm		:std_logic_vector(1 downto 0);
signal init_done	:std_logic;
signal datain		:std_logic_vector(15 downto 0);
signal datawr		:std_logic_vector(15 downto 0);
signal casaddr		:std_logic_vector(24 downto 0);
signal sdwrite 		:std_logic;
signal sdata_reg	:std_logic_vector(15 downto 0);

-- signal hostCycle	:std_logic;
signal zmAddr		:std_logic_vector(24 downto 0);
signal zena			:std_logic;
signal zcache		:std_logic_vector(63 downto 0);
signal zcache_addr	:std_logic_vector(23 downto 0);
signal zcache_fill	:std_logic;
signal zcachehit	:std_logic;
signal zvalid		:std_logic_vector(3 downto 0);
signal zequal		:std_logic;
signal hostStated		:std_logic_vector(1 downto 0);
signal hostRDd	:std_logic_vector(15 downto 0);

signal cena			:std_logic;
signal ccache		:std_logic_vector(63 downto 0);
signal ccache_addr	:std_logic_vector(24 downto 0);
signal ccache_fill	:std_logic;
signal ccachehit	:std_logic;
signal cvalid		:std_logic_vector(3 downto 0);
signal cequal		:std_logic;
signal cpuStated	:std_logic_vector(1 downto 0);
signal cpuRDd		:std_logic_vector(15 downto 0);

signal dcache		:std_logic_vector(63 downto 0);
signal dcache_addr	:std_logic_vector(24 downto 0);
signal dcache_fill	:std_logic;
signal dcachehit	:std_logic;
signal dvalid		:std_logic_vector(3 downto 0);
signal dequal		:std_logic;

signal hostSlot_cnt	:std_logic_vector(7 downto 0);
signal reset_cnt	:std_logic_vector(7 downto 0);
signal reset		:std_logic;
signal reset_sdstate	:std_logic;

signal c_7md		:std_logic;
signal c_7mdd		:std_logic;
signal c_7mdr		:std_logic;
-- signal cpuCycle		:std_logic;
-- signal chipCycle	:std_logic;

signal refreshcnt : std_logic_vector(8 downto 0);
signal refresh_pending : std_logic;

type sdram_states is (ph0,ph1,ph2,ph3,ph4,ph5,ph6,ph7,ph8,ph9,ph10,ph11,ph12,ph13,ph14,ph15);
signal sdram_state		: sdram_states;
type pass_states is (nop,ras,cas);
signal pass		: pass_states;

type slot_type is (refresh,chip,cpu_readcache,cpu_writecache,host,idle);
signal slot1_type : slot_type := idle;
signal slot2_type : slot_type := idle;
signal slot1_bank : std_logic_vector(1 downto 0);
signal slot2_bank : std_logic_vector(1 downto 0);

signal cache_req : std_logic;
signal readcache_fill : std_logic;
signal cache_fill_1 : std_logic;
signal cache_fill_2 : std_logic;

COMPONENT TwoWayCache
	GENERIC ( WAITING : INTEGER := 0; WAITRD : INTEGER := 1; WAITFILL : INTEGER := 2; FILL2 : INTEGER := 3;
		 FILL3 : INTEGER := 4; FILL4 : INTEGER := 5; FILL5 : INTEGER := 6; PAUSE1 : INTEGER := 7 );
		
	PORT
	(
		clk		:	 IN STD_LOGIC;
		reset	: IN std_logic;
		ready : out std_logic;
		cpu_addr		:	 IN STD_LOGIC_VECTOR(31 DOWNTO 0);
		cpu_req		:	 IN STD_LOGIC;
		cpu_ack		:	 OUT STD_LOGIC;
		cpu_wr_ack		:	 OUT STD_LOGIC;
		cpu_rw		:	 IN STD_LOGIC;
		cpu_rwl	: in std_logic;
		cpu_rwu : in std_logic;
		data_from_cpu		:	 IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		data_to_cpu		:	 OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		sdram_addr		:	 OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
		data_from_sdram		:	 IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		data_to_sdram		:	 OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		sdram_req		:	 OUT STD_LOGIC;
		sdram_fill		:	 IN STD_LOGIC;
		sdram_rw		:	 OUT STD_LOGIC
	);
END COMPONENT;

-- Write buffer signals

signal writebuffer_req : std_logic;
signal writebuffer_ena : std_logic;
-- signal writebufferCycle : std_logic;
signal writebuffer_dqm : std_logic_vector(1 downto 0);
signal writebufferAddr : std_logic_vector(24 downto 1);
signal writebufferWR : std_logic_vector(15 downto 0);
signal writebufferWR_reg : std_logic_vector(15 downto 0);
signal writebuffer_cache_ack : std_logic;
signal writebuffer_hold : std_logic; -- 1 during write access, cleared to indicate that the buffer can accept the next word.

type writebuffer_states is (waiting,write1,write2,write3);
signal writebuffer_state : writebuffer_states;

signal cpuAddr_mangled : std_logic_vector(24 downto 1);

-- Let's try some bank-interleaving.
-- For addresses in the upper 16 meg we shift bits around
-- so that one bank bit comes from addr(3).  This should allow
-- bank interleaving to make things more efficient.

begin

-- Turns out this is counter-productive
--cpuAddr_mangled<=cpuAddr(24)&cpuAddr(3)&cpuAddr(22 downto 4)&cpuAddr(23)&cpuAddr(2 downto 1)
--	when cpuAddr(24)='1' else cpuAddr;

cpuAddr_mangled<=cpuAddr;

	process (sysclk, reset_in) begin
		if reset_in = '0' THEN
			reset_cnt <= "00000000";
			reset <= '0';
			reset_sdstate <= '0';
		elsif (sysclk'event and sysclk='1') THEN
				IF reset_cnt="00101010"THEN
					reset_sdstate <= '1';
				END IF;
				IF reset_cnt="10101010"THEN
					if sdram_state=ph15 then 
						reset <= '1';
					end if;
				ELSE
					reset_cnt <= reset_cnt+1;
					reset <= '0';
				END IF;
		end if;
	end process;		
-------------------------------------------------------------------------
-- SPIHOST cache
-------------------------------------------------------------------------
	hostena <= '1' when zena='1' or hostState(1 downto 0)="01" OR zcachehit='1' else '0'; 

	-- Map host processor's address space to 0x400000
	zmAddr <= "00" & NOT hostAddr(22) & hostAddr(21 downto 0);
	
	process (sysclk, zmAddr, hostAddr, zcache_addr, zcache, zequal, zvalid, hostRDd) 
	begin
		if zmAddr(23 downto 3)=zcache_addr(23 downto 3) THEN
			zequal <='1';
		else	
			zequal <='0';
		end if;	
		zcachehit <= '0';
		if zequal='1' and zvalid(0)='1' and hostStated(1)='0' THEN
			case (hostAddr(2 downto 1)&zcache_addr(2 downto 1)) is
				when "0000"|"0101"|"1010"|"1111"=>
					zcachehit <= zvalid(0);
					hostRD <= zcache(63 downto 48);
				when "0100"|"1001"|"1110"|"0011"=>
					zcachehit <= zvalid(1);
					hostRD <= zcache(47 downto 32);
				when "1000"|"1101"|"0010"|"0111"=>
					zcachehit <= zvalid(2);
					hostRD <= zcache(31 downto 16);
				when "1100"|"0001"|"0110"|"1011"=>
					zcachehit <= zvalid(3);
					hostRD <= zcache(15 downto 0);
				when others=> null;
			end case;	
		else	
			hostRD <= hostRDd;
		end if;	
	end process;		
		
	
--Datenbernahme
	process (sysclk, reset) begin
		if reset = '0' THEN
			zcache_fill <= '0';
			zena <= '0';
			zvalid <= "0000";
		elsif (sysclk'event and sysclk='1') THEN
				if enaWRreg='1' THEN
					zena <= '0';
				end if;
				if sdram_state=ph9 AND slot1_type=host THEN 
					hostRDd <= sdata_reg;
				end if;
				if sdram_state=ph11 AND slot1_type=host THEN 
--					if zmAddr=casaddr then and cas_sd_cas='0' then
						zena <= '1';
--					end if;
				end if;
				hostStated <= hostState(1 downto 0);
				if zequal='1' and hostState(1 downto 0)="11" THEN
					zvalid <= "0000";
				end if;
					case sdram_state is	
						when ph7 =>	
										if hostStated(1)='0' AND slot1_type=host THEN	--only instruction cache
											zcache_addr <= casaddr(23 downto 0);
											zcache_fill <= '1';
											zvalid <= "0000";
										end if;
						when ph9 =>	
										if zcache_fill='1' THEN
											zcache(63 downto 48) <= sdata_reg;
										end if;
						when ph10 =>	
										if zcache_fill='1' THEN
											zcache(47 downto 32) <= sdata_reg;
										end if;
						when ph11 =>	
										if zcache_fill='1' THEN
											zcache(31 downto 16) <= sdata_reg;
										end if;
						when ph12 =>	
										if zcache_fill='1' THEN
											zcache(15 downto 0) <= sdata_reg;
											zvalid <= "1111";
										end if;
										zcache_fill <= '0';
						when others =>	null;
					end case;	
			end if;
	end process;
	
-------------------------------------------------------------------------
-- cpu cache
-------------------------------------------------------------------------

mytwc : component TwoWayCache
	PORT map
	(
		clk => sysclk,
		reset => reset,
		ready => open,
		cpu_addr => "0000000"&cpuAddr_mangled&'0',
		cpu_req => not cpustate(2),
		cpu_ack => ccachehit,
		cpu_wr_ack => writebuffer_cache_ack,
		cpu_rw => NOT cpuState(1) OR NOT cpuState(0),
		cpu_rwl => cpuL,
		cpu_rwu => cpuU,
		data_from_cpu => cpuWR,
		data_to_cpu => cpuRD,
		sdram_addr(31 downto 3) => open,
		sdram_addr(2 downto 0) => open,
		data_from_sdram => sdata_reg,
		data_to_sdram => open,
		sdram_req => cache_req,
		sdram_fill => readcache_fill,
		sdram_rw => open
	);

-- Write buffer, enables CPU to continue while a write is in progress.

	process(sysclk, reset) begin
		if reset='0' then
			writebuffer_req<='0';
			writebuffer_ena<='0';
			writebuffer_state<=waiting;
		elsif rising_edge(sysclk) then

			case writebuffer_state is
				when waiting =>
					-- CPU write cycle, no cycle already pending.
					if cpuState(2 downto 0)="011" then
						writebufferAddr<=cpuAddr_mangled(24 downto 1);
						writebufferWR<=cpuWR;
						writebuffer_dqm<=cpuU & cpuL;
						writebuffer_req<='1';
						if writebuffer_cache_ack='1' then
							writebuffer_ena<='1';
							writebuffer_state<=write2;
						end if;
					end if;
				when write2 =>
					if writebuffer_hold='1' then	-- The SDRAM controller has picked up the request
						writebuffer_req<='0';
						writebuffer_state<=write3;
					end if;
				when write3 =>
					if writebuffer_hold='0' then	-- Wait for write cycle to finish, so it's safe to update the signals.
						writebuffer_state<=waiting;
					end if;
				when others =>
					writebuffer_state<=waiting;
			end case;
			
			if cpuState(2)='1' then -- the CPU has unpaused, so clear the ack signal.
				writebuffer_ena<='0';
			end if;
		end if;
	end process;
	
	cpuena <= '1' when cena='1' or ccachehit='1' or writebuffer_ena='1' else '0'; 
	readcache_fill<='1' when
		(cache_fill_1='1' and slot1_type=cpu_readcache) or
		(cache_fill_2='1' and slot2_type=cpu_readcache)
			else '0';

--	cpuena <= '1' when cena='1' or ccachehit='1' or dcachehit='1' else '0'; 
--	
--	process (sysclk, cpuAddr, ccache_addr, ccache, cequal, cvalid, cpuRDd) 
--	begin
--		if cpuAddr(24 downto 3)=ccache_addr(24 downto 3) THEN
--			cequal <='1';
--		else	
--			cequal <='0';
--		end if;	
--
--		if cpuAddr(24 downto 3)=dcache_addr(24 downto 3) THEN
--			dequal <='1';
--		else	
--			dequal <='0';
--		end if;	
--
--		ccachehit <= '0';
--		dcachehit <= '0';
--
--		if cequal='1' and cvalid(0)='1' and cpuStated(1)='0' THEN -- instruction cache
--			case (cpuAddr(2 downto 1)&ccache_addr(2 downto 1)) is
--				when "0000"|"0101"|"1010"|"1111"=>
--					ccachehit <= cvalid(0);
--					cpuRD <= ccache(63 downto 48);
--				when "0100"|"1001"|"1110"|"0011"=>
--					ccachehit <= cvalid(1);
--					cpuRD <= ccache(47 downto 32);
--				when "1000"|"1101"|"0010"|"0111"=>
--					ccachehit <= cvalid(2);
--					cpuRD <= ccache(31 downto 16);
--				when "1100"|"0001"|"0110"|"1011"=>
--					ccachehit <= cvalid(3);
--					cpuRD <= ccache(15 downto 0);
--				when others=> null;
--			end case;
--		elsif dequal='1' and dvalid(0)='1' and cpuStated(1 downto 0)="10" THEN -- Read data
--			case (cpuAddr(2 downto 1)&dcache_addr(2 downto 1)) is
--				when "0000"|"0101"|"1010"|"1111"=>
--					dcachehit <= dvalid(0);
--					cpuRD <= dcache(63 downto 48);
--				when "0100"|"1001"|"1110"|"0011"=>
--					dcachehit <= dvalid(1);
--					cpuRD <= dcache(47 downto 32);
--				when "1000"|"1101"|"0010"|"0111"=>
--					dcachehit <= dvalid(2);
--					cpuRD <= dcache(31 downto 16);
--				when "1100"|"0001"|"0110"|"1011"=>
--					dcachehit <= dvalid(3);
--					cpuRD <= dcache(15 downto 0);
--				when others=> null;
--			end case;	
--		else
--			cpuRD <= cpuRDd;
--		end if;	
--	end process;		
--		
--	
----Datenbernahme
--	process (sysclk, reset) begin
--		if reset = '0' THEN
--			ccache_fill <= '0';
--			cena <= '0';
--			dcache_fill <= '0';
--			cvalid <= "0000";
--			dvalid <= "0000";
--		elsif (sysclk'event and sysclk='1') THEN
--				if cpuState(5)='1' THEN
--					cena <= '0';
--				end if;
--				if sdram_state=ph9 AND cpuCycle='1' THEN 
--					cpuRDd <= sdata_reg;
--				end if;
--				if sdram_state=ph11 AND cpuCycle='1' THEN 
--					if cpuAddr=casaddr(24 downto 1) and cas_sd_cas='0' then
--						cena <= '1';
--					end if;
--				end if;
--				cpuStated <= cpuState(1 downto 0);
--
--				-- Invalidate caches on write
--				if cequal='1' and cpuState(1 downto 0)="11" THEN
--					cvalid <= "0000";
--				end if;
--				if dequal='1' and cpuState(1 downto 0)="11" THEN
--					dvalid <= "0000";
--				end if;
--
--				case sdram_state is	
--						when ph7 =>	
--							if cpuCycle='1' then
--								if cpuStated(1)='0' THEN	-- instruction cache
--									ccache_addr <= casaddr;
--									ccache_fill <= '1';
--									cvalid <= "0000";
--								elsif cpuStated(1 downto 0)="10" THEN	-- data cache
--									dcache_addr <= casaddr;
--									dcache_fill <= '1';
--									dvalid <= "0000";
--								end if;
--							end if;
--						when ph9 =>	
--							if ccache_fill='1' THEN
--								ccache(63 downto 48) <= sdata_reg;
--							end if;
--							if dcache_fill='1' THEN
--								dcache(63 downto 48) <= sdata_reg;
--							end if;
--						when ph10 =>	
--							if ccache_fill='1' THEN
--								ccache(47 downto 32) <= sdata_reg;
--							end if;
--							if dcache_fill='1' THEN
--								dcache(47 downto 32) <= sdata_reg;
--							end if;
--						when ph11 =>	
--							if ccache_fill='1' THEN
--								ccache(31 downto 16) <= sdata_reg;
--							end if;
--							if dcache_fill='1' THEN
--								dcache(31 downto 16) <= sdata_reg;
--							end if;
--						when ph12 =>	
--							if ccache_fill='1' THEN
--								ccache(15 downto 0) <= sdata_reg;
--								cvalid <= "1111";
--							end if;
--							if dcache_fill='1' THEN
--								dcache(15 downto 0) <= sdata_reg;
--								dvalid <= "1111";
--							end if;
--							ccache_fill <= '0';
--							dcache_fill <= '0';
--						when others =>	null;
--					end case;
--			end if;
--	end process;		

	
-------------------------------------------------------------------------
-- chip cache
-------------------------------------------------------------------------
	process (sysclk, sdata_reg)
    begin
		if (sysclk'event and sysclk='1') THEN
			if sdram_state=ph9 AND slot1_type=chip THEN 
				chipRD <= sdata_reg;
			end if;
		end if;
	end process;		
	
	
-------------------------------------------------------------------------
-- SDRAM Basic
-------------------------------------------------------------------------
	reset_out <= init_done;

	process (sysclk, reset, sdwrite, datain) begin
		IF sdwrite='1' THEN
			sdata <= datawr;
--			sdata <= datain;
		ELSE
			sdata <= "ZZZZZZZZZZZZZZZZ";
		END IF;
		if (sysclk'event and sysclk='0') THEN
			c_7md <= c_7m;
		END IF;

		if (sysclk'event and sysclk='1') THEN

			if sdram_state=ph2 THEN
				case slot1_type is
					when chip =>
						datawr <= chipWR;
					when cpu_writecache =>
						datawr <= writebufferWR_reg;
					when others =>
						datawr <= hostWR;			
				END case;
			END IF;

			if sdram_state=ph10 THEN
				case slot2_type is
					when chip =>
						datawr <= chipWR;
					when cpu_writecache =>
						datawr <= writebufferWR_reg;
					when others =>
						datawr <= hostWR;			
				END case;
			END IF;

			sdata_reg <= sdata;
			c_7mdd <= c_7md;
			c_7mdr <= c_7md AND NOT c_7mdd;
			if reset_sdstate = '0' then
				sdwrite <= '0';
				enaRDreg <= '0';
				enaWRreg <= '0';
				ena7RDreg <= '0';
				ena7WRreg <= '0';
			ELSE	
				sdwrite <= '0';
				enaRDreg <= '0';
				enaWRreg <= '0';
				ena7RDreg <= '0';
				ena7WRreg <= '0';
				case sdram_state is	--LATENCY=3
					when ph2 =>	enaWRreg <= '1';
					when ph3 =>	sdwrite <= '1';
					when ph4 =>	sdwrite <= '1';
					when ph5 => sdwrite <= '1';
					when ph6 =>	enaWRreg <= '1';
								ena7RDreg <= '1';
					when ph10 => enaWRreg <= '1';
					when ph11 => sdwrite<= '1';	-- Access slot 2
					when ph12 => sdwrite<= '1';
					when ph13 => sdwrite<= '1';
					when ph14 => enaWRreg <= '1';
								ena7WRreg <= '1';
					when others => null;
				end case;	
			END IF;	
			if reset = '0' then
				initstate <= (others => '0');
				init_done <= '0';
			ELSE	
				case sdram_state is	--LATENCY=3
					when ph15 => if initstate /= "1111" THEN
									initstate <= initstate+1;
								else
									init_done <='1';	
								end if;
					when others => null;
				end case;	
			END IF;	
			IF c_7mdr='1' THEN
				sdram_state <= ph2;
			ELSE
				case sdram_state is	--LATENCY=3
					when ph0 =>	sdram_state <= ph1;
					when ph1 =>	sdram_state <= ph2;
					when ph2 =>	sdram_state <= ph3;
					when ph3 =>	sdram_state <= ph4;
					when ph4 =>	sdram_state <= ph5;
					when ph5 =>	sdram_state <= ph6;
					when ph6 =>	sdram_state <= ph7;
					when ph7 => sdram_state <= ph8;
					when ph8 =>	sdram_state <= ph9;
					when ph9 =>	sdram_state <= ph10;
					when ph10 => sdram_state <= ph11;
					when ph11 => sdram_state <= ph12;
					when ph12 => sdram_state <= ph13;
					when ph13 => sdram_state <= ph14;
					when ph14 => sdram_state <= ph15;
					when others => sdram_state <= ph0;
				end case;	
			END IF;	
		END IF;	
	end process;		

-- Address bits will be allocated as follows:
-- 24 downto 23: bank
-- 22 downto 10: row
-- 9 downto 1: column
	
	process (sysclk, initstate, pass, hostAddr, datain, init_done, casaddr, cpuU, cpuL) begin
		
		if (sysclk'event and sysclk='1') THEN
			if reset='0' then
				refresh_pending<='0';
				slot1_type<=idle;
				slot2_type<=idle;
			end if;
			sd_cs <="1111";
			sd_ras <= '1';
			sd_cas <= '1';
			sd_we <= '1';
			sdaddr <= "XXXXXXXXXXXXX";
			ba <= "00";
			dqm <= "00";
			cache_fill_1<='0';
			cache_fill_2<='0';

			if cpuState(5)='1' then
				cena<='0';
			end if;
			
			if init_done='0' then
				if sdram_state =ph1 then
					case initstate is
						when "0010" => --PRECHARGE
							sdaddr(10) <= '1'; 	--all banks
							sd_cs <="0000";
							sd_ras <= '0';
							sd_cas <= '1';
							sd_we <= '0';
						when "0011"|"0100"|"0101"|"0110"|"0111"|"1000"|"1001"|"1010"|"1011"|"1100" => --AUTOREFRESH
							sd_cs <="0000"; 
							sd_ras <= '0';
							sd_cas <= '0';
							sd_we <= '1';
						when "1101" => --LOAD MODE REGISTER
							sd_cs <="0000";
							sd_ras <= '0';
							sd_cas <= '0';
							sd_we <= '0';
							sdaddr <= "0001000110010"; --BURST=4 LATENCY=3
						when others =>	null;	--NOP
					end case;
				END IF;
			else		
	
-- Time slot control	
				case sdram_state is
					when ph0 =>
						cache_fill_2 <='1'; -- slot 2
						
					when ph1 =>
						cache_fill_2 <='1'; -- slot 2

--						cpuCycle <= '0';
--						chipCycle <= '0';
--						hostCycle <= '0';
--						writebufferCycle <= '0';
						cas_sd_cs <= "1110"; 
						cas_sd_ras <= '1';
						cas_sd_cas <= '1';
						cas_sd_we <= '1';

						IF hostSlot_cnt /= "00000000" THEN
							hostSlot_cnt <= hostSlot_cnt-1;
						END IF;
						if refreshcnt = "000000000" then
							refresh_pending<='1';
						else
							refreshcnt <= refreshcnt-1;
						end if;
						
-- 					We give the chipset first priority...
--						(This includes anything on the "motherboard" - chip RAM, slow RAM and Kickstart, turbo modes notwithstanding

						IF chip_dma='0' OR chipRW='0' THEN
							slot1_type<=chip; -- chipCycle <= '1';
							sdaddr <= chipAddr(22 downto 10);
							ba <= "00"; -- Always bank zero for chipset accesses, so we can interleave Fast RAM access
							slot1_bank<="00";
							cas_dqm <= chipU& chipL;
							sd_cs <= "1110"; 	--ACTIVE
							sd_ras <= '0';
							casaddr <= '0'&chipAddr&'0';	
--							datain <= chipWR;
							cas_sd_cas <= '0';
							cas_sd_we <= chipRW;

-- 					Next in line is refresh...
--						(A refresh cycle blocks both access slots)
						elsif refresh_pending='1' and slot2_type=idle then
							sd_cs <="0000"; --AUTOREFRESH
							sd_ras <= '0';
							sd_cas <= '0';
							refreshcnt <= "111111111";
							slot1_type<=refresh;
							refresh_pending<='0';

--		--					The Amiga CPU gets next bite of the cherry, unless the OSD CPU has been cycle-starved...
--		--					ELSIF cpuState(2)='0' AND cpuState(5)='0'
--						-- Request from write buffer.
						ELSIF (writebuffer_req='1')
							and (hostslot_cnt/="00000000" or (hostState(2)='1' or hostena='1'))
							and (slot2_type=idle or slot2_bank/=writebufferAddr(24 downto 23))
								then
							-- We only yeild to the OSD CPU if it's both cycle-starved and ready to go.
							slot1_type<=cpu_writecache;
							sdaddr <= writebufferAddr(22 downto 10);
							ba <= writebufferAddr(24 downto 23);
							slot1_bank<=writebufferAddr(24 downto 23);
							cas_dqm <= writebuffer_dqm;
							sd_cs <= "1110"; --ACTIVE
							sd_ras <= '0';
							casaddr <= writebufferAddr(24 downto 1)&'0';
							cas_sd_we <= '0';
--							datain <= writebufferWR;
							writebufferWR_reg <= writebufferWR;
							cas_sd_cas <= '0';
							writebuffer_hold<='1';	-- Let the write buffer know we're about to write.

						-- Request from read cache
						ELSIF (cache_req='1')
							and (hostslot_cnt/="00000000" or (hostState(2)='1' or hostena='1'))
							and (slot2_type=idle or slot2_bank/=cpuAddr_mangled(24 downto 23))
								then
							-- We only yeild to the OSD CPU if it's both cycle-starved and ready to go.
							slot1_type<=cpu_readcache;
							sdaddr <= cpuAddr_mangled(22 downto 10);
							ba <= cpuAddr_mangled(24 downto 23);
							slot1_bank<=cpuAddr_mangled(24 downto 23);
							cas_dqm <= cpuU& cpuL;
							sd_cs <= "1110"; --ACTIVE
							sd_ras <= '0';
							casaddr <= cpuAddr_mangled(24 downto 1)&'0';
--							if (cpuState(1) and cpuState(0))='1' then	-- Write cycle
--								casaddr <= cpuAddr(24 downto 1)&'0';
--							cas_sd_we <= '0';
--							else
----								casaddr <= cpuAddr(24 downto 3)&"000";
							cas_sd_we <= '1';
--							end if;
--							datain <= cpuWR;
							cas_sd_cas <= '0';
						ELSIF hostState(2)='0' AND hostena='0' THEN
							hostSlot_cnt <= "00001111";
							slot1_type<=host;
							sdaddr <= zmAddr(22 downto 10);
							ba <= "00"; -- Always bank zero for SPI host CPU
							slot1_bank<="00";
							cas_dqm <= hostU& hostL;
							sd_cs <= "1110"; --ACTIVE
							sd_ras <= '0';
							casaddr <= zmAddr;
--							datain <= hostWR;
							cas_sd_cas <= '0';
							IF hostState="011" THEN
								cas_sd_we <= '0';
							END IF;
--						elsif slot2_type=idle then
----							If no-one else wants this cycle we refresh the RAM.
--							sd_cs <="0000"; --AUTOREFRESH
--							sd_ras <= '0';
--							sd_cas <= '0';
--							refreshcnt <= "111111111";
--							slot1_type<=refresh;
						else
							slot1_type<=idle;
						END IF;

					when ph2 =>
						cache_fill_2 <='1'; -- slot 2

					when ph3 =>
						cache_fill_2 <='1'; -- slot 2

					when ph4 =>
						sdaddr <=  '0'&'0' & '1' & '0' & casaddr(9 downto 1);--auto precharge
						ba <= casaddr(24 downto 23);
						sd_cs <= cas_sd_cs; 
						IF cas_sd_we='0' THEN
							dqm <= cas_dqm;
						END IF;
						sd_ras <= cas_sd_ras;
						sd_cas <= cas_sd_cas;
						sd_we  <= cas_sd_we;
						writebuffer_hold<='0'; -- Indicate to WriteBuffer that it's safe to accept the next write.
						
					when ph8 =>
						cache_fill_1<='1';
					when ph9 =>
						cache_fill_1<='1';

--						Access slot 2, RAS
						cas_sd_cs <= "1110"; 
						cas_sd_ras <= '1';
						cas_sd_cas <= '1';
						cas_sd_we <= '1';

						slot2_type<=idle;
						if refresh_pending='0' and slot1_type/=refresh then
							IF writebuffer_req='1'  and writebufferAddr(24 downto 23)/="00" -- Reserve bank 0 for slot 1
								and (slot1_type=idle or slot1_bank/=writebufferAddr(24 downto 23))
									then
								-- We only yeild to the OSD CPU if it's both cycle-starved and ready to go.
								slot2_type<=cpu_writecache;
								sdaddr <= writebufferAddr(22 downto 10);
								ba <= writebufferAddr(24 downto 23);
								slot2_bank <= writebufferAddr(24 downto 23);
								cas_dqm <= writebuffer_dqm;
								sd_cs <= "1110"; --ACTIVE
								sd_ras <= '0';
								casaddr <= writebufferAddr(24 downto 1)&'0';
								cas_sd_we <= '0';
--								datain <= writebufferWR;
								writebufferWR_reg <= writebufferWR;
								cas_sd_cas <= '0';
								writebuffer_hold<='1';	-- Let the write buffer know we're about to write.
							-- Request from read cache
							ELSIF cache_req='1' and cpuAddr(24 downto 23)/="00" -- Reserve bank 0 for slot 1
								and (slot1_type=idle or slot1_bank/=cpuAddr_mangled(24 downto 23))
								then
								slot2_type<=cpu_readcache;
								sdaddr <= cpuAddr_mangled(22 downto 10);
								ba <= cpuAddr_mangled(24 downto 23);
								slot2_bank <= cpuAddr_mangled(24 downto 23);
								cas_dqm <= cpuU& cpuL;
								sd_cs <= "1110"; --ACTIVE
								sd_ras <= '0';
								casaddr <= cpuAddr_mangled(24 downto 1)&'0';
								cas_sd_we <= '1';
								cas_sd_cas <= '0';
							end if;
						end if;

					when ph10 =>
						cache_fill_1<='1';
					when ph11 =>
						cache_fill_1<='1';
						
					-- Slot 2 CAS
					when ph12 =>
						sdaddr <=  '0'&'0' & '1' & '0' & casaddr(9 downto 1);--auto precharge
						ba <= casaddr(24 downto 23);
						sd_cs <= cas_sd_cs; 
						IF cas_sd_we='0' THEN
							dqm <= cas_dqm;
						END IF;
						sd_ras <= cas_sd_ras;
						sd_cas <= cas_sd_cas;
						sd_we  <= cas_sd_we;
						writebuffer_hold<='0'; -- Indicate to WriteBuffer that it's safe to accept the next write.
						
					when others =>
						null;
				end case;
			end if;
		END IF;	
	END process;
END;

--                Slot 1                       Slot 2
-- ph0 	(read)								(Read 0 in sdata)

-- ph1	Slot alloc, RAS (read)			Read0		

-- ph2	... (read)							Read1

-- ph3	... (write)							Read2 (read3 in sdata)

-- ph4	CAS, write0 (write) 				Read3

-- ph5	write1 (write)

-- ph6	write2 (write)

-- ph7	write3 (read)

-- ph8   (read0 in sdata) (rd)		

-- ph9	read0 in sdata_reg (rd)			Slot alloc, RAS

-- ph10	read1	(read)						...

-- ph11	read2 (rd3 in sdata, wr)		...

-- ph12	read3 (write)						CAS, write 0

-- ph13	(write)								write1

-- ph14	(write)								write2

-- ph15	(read)								write3
