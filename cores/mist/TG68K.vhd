------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- Copyright (c) 2009-2011 Tobias Gubener                                   -- 
-- Subdesign fAMpIGA by TobiFlex                                            --
--                                                                          --
-- This is the TOP-Level for TG68KdotC_Kernel to generate 68K Bus signals   --
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

entity TG68K is
   port(        
		clk           : in std_logic;
		reset         : in std_logic;
        clkena_in     : in std_logic:='1';
        IPL           : in std_logic_vector(2 downto 0):="111";
        berr          : in std_logic:='0';
        clr_berr      : out std_logic;
        dtack         : in std_logic;
        vpa           : in std_logic:='1';
        ein           : in std_logic:='1';
        addr          : buffer std_logic_vector(31 downto 0);
        data_read  	  : in std_logic_vector(15 downto 0);
        data_write 	  : out std_logic_vector(15 downto 0);
        as            : out std_logic;
        uds           : out std_logic;
        lds           : out std_logic;
        rw            : out std_logic;
        e             : out std_logic;
        vma           : buffer std_logic:='1';
        wrd           : out std_logic;
        ena7RDreg      : in std_logic:='1';
        ena7WRreg      : in std_logic:='1';
        enaWRreg      : in std_logic:='1';
        
        fromram    	  : in std_logic_vector(15 downto 0);
        ramready      : in std_logic:='0';
        cpu           : in std_logic_vector(1 downto 0);
        memcfg           : in std_logic_vector(5 downto 0);
        ramaddr    	  : out std_logic_vector(31 downto 0);
        cpustate      : out std_logic_vector(5 downto 0);
		nResetOut	  : out std_logic;
        skipFetch     : out std_logic;
        cpuDMA         : buffer std_logic;
        ramlds        : out std_logic;
        ramuds        : out std_logic;
        turbo      : in std_logic:='0'
        );
end TG68K;

ARCHITECTURE logic OF TG68K IS


COMPONENT TG68KdotC_Kernel 
	generic(
		SR_Read : integer:= 2;         --0=>user,   1=>privileged,      2=>switchable with CPU(0)
		VBR_Stackframe : integer:= 2;  --0=>no,     1=>yes/extended,    2=>switchable with CPU(0)
		extAddr_Mode : integer:= 2;    --0=>no,     1=>yes,    2=>switchable with CPU(1)
		MUL_Mode : integer := 2;	   --0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no MUL,  
		DIV_Mode : integer := 2;	   --0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no DIV,  
		BitField : integer := 2		   --0=>no,     1=>yes,    2=>switchable with CPU(1)  
		);
   port(clk               	: in std_logic;
        nReset             	: in std_logic;			--low active
        clkena_in         	: in std_logic:='1';
        data_in          	: in std_logic_vector(15 downto 0);
		IPL				  	: in std_logic_vector(2 downto 0):="111";
		IPL_autovector   	: in std_logic:='0';
		berr  	: in std_logic:='0';
		clr_berr  	: out std_logic;
		CPU             	: in std_logic_vector(1 downto 0):="00";  -- 00->68000  01->68010  11->68020(only same parts - yet)
        addr           		: buffer std_logic_vector(31 downto 0);
        data_write        	: out std_logic_vector(15 downto 0);
		nWr			  		: out std_logic;
		nUDS, nLDS	  		: out std_logic;
		nResetOut	  		: out std_logic;
        FC              	: out std_logic_vector(2 downto 0);
-- for debug		
		busstate	  	  	: out std_logic_vector(1 downto 0);	-- 00-> fetch code 10->read data 11->write data 01->no memaccess
		skipFetch	  		: out std_logic;
        regin          		: buffer std_logic_vector(31 downto 0)
        );
	END COMPONENT;


   SIGNAL cpuaddr     : std_logic_vector(31 downto 0);
   SIGNAL t_addr      : std_logic_vector(31 downto 0);
--   SIGNAL data_write  : std_logic_vector(15 downto 0);
--   SIGNAL t_data      : std_logic_vector(15 downto 0);
   SIGNAL r_data      : std_logic_vector(15 downto 0);
   SIGNAL cpuIPL      : std_logic_vector(2 downto 0);
   SIGNAL addr_akt_s  : std_logic;
   SIGNAL addr_akt_e  : std_logic;
   SIGNAL data_akt_s  : std_logic;
   SIGNAL data_akt_e  : std_logic;
   SIGNAL as_s        : std_logic;
   SIGNAL as_e        : std_logic;
   SIGNAL uds_s       : std_logic;
   SIGNAL uds_e       : std_logic;
   SIGNAL lds_s       : std_logic;
   SIGNAL lds_e       : std_logic;
   SIGNAL rw_s        : std_logic;
   SIGNAL rw_e        : std_logic;
   SIGNAL vpad        : std_logic;
   SIGNAL waitm       : std_logic;
   SIGNAL clkena_e    : std_logic;
   SIGNAL S_state     : std_logic_vector(1 downto 0);
   SIGNAL S_stated     : std_logic_vector(1 downto 0);
   SIGNAL decode	  : std_logic;
   SIGNAL wr	      : std_logic;
   SIGNAL uds_in	  : std_logic;
   SIGNAL berr_in	  : std_logic;
   SIGNAL clr_berr_in	  : std_logic;
   SIGNAL lds_in	  : std_logic;
   SIGNAL state       : std_logic_vector(1 downto 0);
   SIGNAL clkena	  : std_logic;
--   SIGNAL n_clk		  : std_logic;
   SIGNAL vmaena	  : std_logic;
   SIGNAL vmaenad	  : std_logic;
   SIGNAL state_ena	  : std_logic;
   SIGNAL sync_state3 : std_logic;
   SIGNAL eind	      : std_logic;
   SIGNAL eindd	      : std_logic;
   SIGNAL sel_fast: std_logic;
   SIGNAL slower       : std_logic_vector(3 downto 0);


	type sync_states is (sync0, sync1, sync2, sync3, sync4, sync5, sync6, sync7, sync8, sync9);
	signal sync_state		: sync_states;
	
   SIGNAL datatg68      : std_logic_vector(15 downto 0);
   SIGNAL ramcs	      : std_logic;

BEGIN  
       clr_berr <= clr_berr_in;
--	n_clk <= NOT clk;
--	wrd <= data_akt_e OR data_akt_s;
	wrd <= wr;
	addr <= cpuaddr;-- WHEN addr_akt_e='1' ELSE t_addr WHEN addr_akt_s='1' ELSE "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ";
--	data <= data_write WHEN data_akt_e='1' ELSE t_data WHEN data_akt_s='1' ELSE "ZZZZZZZZZZZZZZZZ";
--	datatg68 <= fromram WHEN sel_fast='1' ELSE r_data; 
	datatg68 <= fromram WHEN sel_fast='1' ELSE r_data; --  WHEN sel_autoconfig='0' ELSE autoconfig_data&r_data(11 downto 0); 
--	toram <= data_write;
	
--TH	sel_fast <= '1' when state/="01" AND (cpuaddr(23 downto 21)="001" OR cpuaddr(23 downto 21)="010" OR cpuaddr(23 downto 21)="011" OR cpuaddr(23 downto 21)="100") ELSE '0'; --$200000 - $9FFFFF
--	sel_fast <= '1' when cpuaddr(23 downto 21)="001" OR cpuaddr(23 downto 21)="010" ELSE '0'; --$200000 - $5FFFFF
--	sel_fast <= '1' when cpuaddr(23 downto 19)="11111" ELSE '0'; --$F800000;--

--	sel_fast <= '0'; -- off
	sel_fast <= '1' when turbo='1' AND cpuaddr(23 downto 22)="00" AND state/="01" ELSE '0'; --$000000 - $3fffff
--	sel_fast <= '1' when (cpuaddr(23 downto 22)="00"  OR cpuaddr(23 downto 17)="1111110" OR cpuaddr(23 downto 16)="11111110" OR cpuaddr(23 downto 17)="1111101" OR cpuaddr(23 downto 18)="111000") AND state/="01" ELSE '0'; --$000000 - $3fffff
	
	ramcs <= (NOT sel_fast) or slower(0);-- OR (state(0) AND NOT state(1));
--	cpuDMA <= NOT ramcs;
	cpuDMA <= sel_fast;
	cpustate <= clkena&slower(1 downto 0)&ramcs&state;
	ramlds <= lds_in;
	ramuds <= uds_in;
--	ramaddr(23 downto 0) <= cpuaddr(23 downto 0);
--	ramaddr(24) <= sel_fast;
--	ramaddr(31 downto 25) <= cpuaddr(31 downto 25);
--TH  ramaddr(23 downto 0) <= cpuaddr(23) & sel_fast & cpuaddr(21 downto 0);
--TH  ramaddr(31 downto 24) <= cpuaddr(31 downto 24);
   ramaddr <= cpuaddr;

pf68K_Kernel_inst: TG68KdotC_Kernel 
	generic map(
		SR_Read => 2,         	--0=>user,   1=>privileged,      2=>switchable with CPU(0)
		VBR_Stackframe => 2,  	--0=>no,     1=>yes/extended,    2=>switchable with CPU(0)
		extAddr_Mode => 2,    	--0=>no,     1=>yes,    2=>switchable with CPU(1)
		MUL_Mode => 2,	   		--0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no MUL,  
		DIV_Mode => 2		  	 --0=>16Bit,  1=>32Bit,  2=>switchable with CPU(1),  3=>no DIV,  
		)
  PORT MAP(
        clk => clk,               	-- : in std_logic;
        nReset => reset,            -- : in std_logic:='1';			--low active
        clkena_in => clkena,	        -- : in std_logic:='1';
--        data_in => r_data,       -- : in std_logic_vector(15 downto 0);
--        data_in => data_read,       -- : in std_logic_vector(15 downto 0);
        data_in => datatg68,       -- : in std_logic_vector(15 downto 0);
		IPL => cpuIPL,				  	-- : in std_logic_vector(2 downto 0):="111";
		IPL_autovector => '0', -- TH 	-- : in std_logic:='0';
        addr => cpuaddr,           	-- : buffer std_logic_vector(31 downto 0);
        data_write => data_write,     -- : out std_logic_vector(15 downto 0);
		berr => berr_in,
		clr_berr => clr_berr_in,
		busstate => state,	  	  	-- : buffer std_logic_vector(1 downto 0);	
        regin => open,          	-- : out std_logic_vector(31 downto 0);
		nWr => wr,			  	-- : out std_logic;
		nUDS => uds_in,
		nLDS => lds_in,	  			-- : out std_logic;
		nResetOut => nResetOut,
		CPU => cpu,
		skipFetch => skipFetch 		-- : out std_logic
        );
 

	PROCESS (clk)
	BEGIN
		IF rising_edge(clk) THEN
			IF reset='0' THEN
				vmaena <= '0';
				vmaenad <= '0';
				sync_state3 <= '0';
			ELSIF ena7RDreg='1' THEN
				vmaena <= '0';
				sync_state3 <= '0';
				IF state/="01" OR state_ena='1' THEN
					vmaenad <= vmaena;
				END IF;
				IF sync_state=sync5 THEN
					e <= '1';
				END IF;
				IF sync_state=sync3 THEN
					sync_state3 <= '1';
				END IF;
				IF sync_state=sync9 THEN
					e <= '0';
					vmaena <= NOT vma;
				END IF;
			END IF;
		END IF;	
		IF rising_edge(clk) THEN
			S_stated <= S_state;
			IF ena7WRreg='1' THEN
				eind <= ein;
				eindd <= eind;
				CASE sync_state IS
					WHEN sync0  => sync_state <= sync1;
					WHEN sync1  => sync_state <= sync2;
					WHEN sync2  => sync_state <= sync3;
					WHEN sync3  => sync_state <= sync4;
								   vma <= vpa;
					WHEN sync4  => sync_state <= sync5;
					WHEN sync5  => sync_state <= sync6;
					WHEN sync6  => sync_state <= sync7;
					WHEN sync7  => sync_state <= sync8;
					WHEN sync8  => sync_state <= sync9;
					WHEN OTHERS => sync_state <= sync0;
								   vma <= '1';
				END CASE;	
				IF eind='1' AND eindd='0' THEN
					sync_state <= sync7;
				END IF;			
			END IF;	
		END IF;	
	END PROCESS;
				
	
	PROCESS (clk)
	BEGIN
		state_ena <= '0';
		IF clkena_in='1' AND enaWRreg='1' AND (state="01" OR (ena7RDreg='1' AND clkena_e='1') OR ramready='1') THEN
			clkena <= '1';
		ELSE 
			clkena <= '0';
		END IF;	
		IF state="01" THEN
			state_ena <= '1';
		END IF;	
		IF rising_edge(clk) THEN
        	IF clkena='1' THEN
				slower <= "0111";
			ELSE 
				slower(3 downto 0) <= '0'&slower(3 downto 1); -- enaWRreg&slower(3 downto 1);
--				slower(0) <= NOT slower(3) AND NOT slower(2);
			END IF;	
		END IF;	
	END PROCESS;
				
PROCESS (clk, reset, state, as_s, as_e, rw_s, rw_e, uds_s, uds_e, lds_s, lds_e)
	BEGIN
		IF state="01" THEN 
			as <= '1';
			rw <= '1';
			uds <= '1';
			lds <= '1';
		ELSE
			as <= (as_s AND as_e) OR sel_fast;
--			rw <= rw_s AND rw_e;
--			uds <= uds_s AND uds_e;
--			lds <= lds_s AND lds_e;
--			as <= as_s OR sel_fast;
			rw <= rw_s;
			uds <= uds_s;
			lds <= lds_s;
		END IF;
		IF reset='0' THEN
			S_state <= "00";
			as_s <= '1';
			rw_s <= '1';
			uds_s <= '1';
			lds_s <= '1';
			addr_akt_s <= '0';
			data_akt_s <= '0';
		ELSIF rising_edge(clk) THEN
        	IF ena7WRreg='1' THEN
				as_s <= '1';
				rw_s <= '1';
				uds_s <= '1';
				lds_s <= '1';
				addr_akt_s <= '0';
				data_akt_s <= '0';
					CASE S_state IS
						WHEN "00" => IF state/="01" AND sel_fast='0' THEN
									 as_s <= '0';
									 rw_s <= wr;
									 uds_s <= uds_in;
									 lds_s <= lds_in;
									 S_state <= "01";
									 END IF;
						WHEN "01" => as_s <= '0';
									 rw_s <= wr;
									 uds_s <= uds_in;
									 lds_s <= lds_in;
									 S_state <= "10";
									 t_addr <= cpuaddr;
--									 t_data <= data_write;
						WHEN "10" =>
									 addr_akt_s <= '1';
									 data_akt_s <= NOT wr;
									 r_data <= data_read;
									 IF waitm='0' OR (vma='0' AND sync_state=sync9) THEN
										S_state <= "11";
									 ELSE	
										 as_s <= '0';
										 rw_s <= wr;
										 uds_s <= uds_in;
										 lds_s <= lds_in;
									 END IF;
						WHEN "11" =>
									 S_state <= "00";
						WHEN OTHERS => null;			
					END CASE;
			END IF;
		END IF;	
		IF reset='0' THEN
			as_e <= '1';
			rw_e <= '1';
			uds_e <= '1';
			lds_e <= '1';
			clkena_e <= '0';
			addr_akt_e <= '0';
			data_akt_e <= '0';
			berr_in <= '0';
		ELSIF rising_edge(clk) THEN
        	IF ena7RDreg='1' THEN
				as_e <= '1';
				rw_e <= '1';
				uds_e <= '1';
				lds_e <= '1';
				clkena_e <= '0';
				addr_akt_e <= '0';
				data_akt_e <= '0';
				CASE S_state IS
					WHEN "00" => addr_akt_e <= '1';
								 cpuIPL <= IPL;
								 IF sel_fast='0' THEN
									 IF state/="01" THEN
										as_e <= '0';
									 END IF;
									 rw_e <= wr;
									 data_akt_e <= NOT wr;
									 IF wr='1' THEN
										 uds_e <= uds_in;
										 lds_e <= lds_in;					
									 END IF;
								 END IF;
					WHEN "01" => addr_akt_e <= '1';
								 data_akt_e <= NOT wr;
									as_e <= '0';
									 rw_e <= wr;
									 uds_e <= uds_in;
									 lds_e <= lds_in;					
					WHEN "10" => rw_e <= wr;
								 addr_akt_e <= '1';
								 data_akt_e <= NOT wr;
								 cpuIPL <= IPL;
								 waitm <= dtack AND NOT berr;
								 berr_in <= berr;
					WHEN OTHERS => --null;			
									 clkena_e <= '1';
				END CASE;
			END IF;
		END IF;	
	END PROCESS;
END;	
