-- ****
-- T65(b) core. In an effort to merge and maintain bug fixes ....
--
-- Ver 313 WoS January 2015
--   Fixed issue that NMI has to be first if issued the same time as a BRK instruction is latched in
--   Now all Lorenz CPU tests on FPGAARCADE C64 core (sources used: SVN version 1021) are OK! :D :D :D
--   This is just a starting point to go for optimizations and detailed fixes (the Lorenz test can't find)
--
-- Ver 312 WoS January 2015
--   Undoc opcode timing fixes for $B3 (LAX iy) and $BB (LAS ay)
--   Added comments in MCode section to find handling of individual opcodes more easily
--   All "basic" Lorenz instruction test (individual functional checks, CPUTIMING check) work now with 
--       actual FPGAARCADE C64 core (sources used: SVN version 1021).
--
-- Ver 305, 306, 307, 308, 309, 310, 311 WoS January 2015
--   Undoc opcode fixes (now all Lorenz test on instruction functionality working, except timing issues on $B3 and $BB):
--     SAX opcode
--     SHA opcode
--     SHX opcode
--     SHY opcode
--     SHS opcode
--     LAS opcode
--     alternate SBC opcode
--     fixed NOP with immediate param (caused Lorenz trap test to fail)
--     IRQ and NMI timing fixes (in conjuction with branches)
--
-- Ver 304 WoS December 2014
--   Undoc opcode fixes:
--     ARR opcode
--     ANE/XAA opcode
--   Corrected issue with NMI/IRQ prio (when asserted the same time)
--
-- Ver 303 ost(ML) July 2014
--   (Sorry for some scratchpad comments that may make little sense)
--   Mods and some 6502 undocumented instructions.
--   Not correct opcodes acc. to Lorenz tests (incomplete list):
--     NOPN    (nop)
--     NOPZX   (nop + byte 172)
--     NOPAX   (nop + word da  ...  da:  byte 0)
--     ASOZ    (byte $07 + byte 172)
--
-- Ver 303,302 WoS April 2014
--     Bugfixes for NMI from foft
--     Bugfix for BRK command (and its special flag)
--
-- Ver 300,301 WoS January 2014
--     More merging
--     Bugfixes by ehenciak added, started tidyup *bust*
--
-- MikeJ March 2005
--      Latest version from www.fpgaarcade.com (original www.opencores.org)
-- ****
--
-- 65xx compatible microprocessor core
--
-- FPGAARCADE SVN: $Id: T65.vhd 1347 2015-05-27 20:07:34Z wolfgang.scherr $
--
-- Copyright (c) 2002...2015
--               Daniel Wallner (jesus <at> opencores <dot> org)
--               Mike Johnson   (mikej <at> fpgaarcade <dot> com)
--               Wolfgang Scherr (WoS <at> pin4 <dot> at>
--               Morten Leikvoll ()
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
-- Please report bugs to the author(s), but before you do so, please
-- make sure that this is not a derivative work and that
-- you have the latest version of this file.
--
-- ----- IMPORTANT NOTES -----
--
-- Limitations:
--   65C02 and 65C816 modes are incomplete (and definitely untested after all 6502 undoc fixes)
--      65C02 supported : inc, dec, phx, plx, phy, ply
--      65D02 missing : bra, ora, lda, cmp, sbc, tsb*2, trb*2, stz*2, bit*2, wai, stp, jmp, bbr*8, bbs*8
--   Some interface signals behave incorrect
--   NMI interrupt handling not nice, needs further rework (to cycle-based encoding).
--
-- Usage:
--   The enable signal allows clock gating / throttling without using the ready signal.
--   Set it to constant '1' when using the Clk input as the CPU clock directly.
--
--   TAKE CARE you route the DO signal back to the DI signal while R_W_n='0',
--   otherwise some undocumented opcodes won't work correctly.
--   EXAMPLE:
--      CPU : entity work.T65
--          port map (
--              R_W_n   => cpu_rwn_s,
--              [....all other ports....]
--              DI      => cpu_din_s,
--              DO      => cpu_dout_s
--          );
--      cpu_din_s <= cpu_dout_s when cpu_rwn_s='0' else 
--                   [....other sources from peripherals and memories...]
--
-- ----- IMPORTANT NOTES -----
--

library IEEE;
  use IEEE.std_logic_1164.all;
  use IEEE.numeric_std.all;
  use work.T65_Pack.all;

entity T65 is
  port(
    Mode    : in  std_logic_vector(1 downto 0); -- "00" => 6502, "01" => 65C02, "10" => 65C816
    BCD_en  : in  std_logic := '1';             -- '0' => 2A03/2A07, '1' => others

    Res_n   : in  std_logic;
    Clk     : in  std_logic;
    Enable  : in  std_logic := '1';

    A       : out std_logic_vector(23 downto 0);
    DI      : in  std_logic_vector(7 downto 0);
    DO      : out std_logic_vector(7 downto 0);

    Rdy     : in  std_logic := '1';
    Abort_n : in  std_logic := '1';
    IRQ_n   : in  std_logic := '1';
    NMI_n   : in  std_logic := '1';
    SO_n    : in  std_logic := '1';
    R_W_n   : out std_logic;
    Sync    : out std_logic;
    EF      : out std_logic;
    MF      : out std_logic;
    XF      : out std_logic;
    ML_n    : out std_logic;
    VP_n    : out std_logic;
    VDA     : out std_logic;
    VPA     : out std_logic;

    DEBUG   : out T_t65_dbg;
    NMI_ack : out std_logic
  );
end T65;

architecture rtl of T65 is

  -- Registers
  signal ABC, X, Y          : std_logic_vector(15 downto 0);
  signal P, AD, DL          : std_logic_vector(7 downto 0) :=  x"00";
  signal PwithB             : std_logic_vector(7 downto 0);--ML:New way to push P with correct B state to stack
  signal BAH                : std_logic_vector(7 downto 0);
  signal BAL                : std_logic_vector(8 downto 0);
  signal PBR                : std_logic_vector(7 downto 0);
  signal DBR                : std_logic_vector(7 downto 0);
  signal PC                 : unsigned(15 downto 0);
  signal S                  : unsigned(15 downto 0);
  signal EF_i               : std_logic;
  signal MF_i               : std_logic;
  signal XF_i               : std_logic;

  signal IR                 : std_logic_vector(7 downto 0);
  signal MCycle             : std_logic_vector(2 downto 0);

  signal Mode_r             : std_logic_vector(1 downto 0);
  signal BCD_en_r           : std_logic;
  signal ALU_Op_r           : T_ALU_Op;
  signal Write_Data_r       : T_Write_Data;
  signal Set_Addr_To_r      : T_Set_Addr_To;
  signal PCAdder            : unsigned(8 downto 0);

  signal RstCycle           : std_logic;
  signal IRQCycle           : std_logic;
  signal NMICycle           : std_logic;

  signal SO_n_o             : std_logic;
  signal IRQ_n_o            : std_logic;
  signal NMI_n_o            : std_logic;
  signal NMIAct             : std_logic;

  signal Break              : std_logic;

  -- ALU signals
  signal BusA               : std_logic_vector(7 downto 0);
  signal BusA_r             : std_logic_vector(7 downto 0);
  signal BusB               : std_logic_vector(7 downto 0);
  signal BusB_r             : std_logic_vector(7 downto 0);
  signal ALU_Q              : std_logic_vector(7 downto 0);
  signal P_Out              : std_logic_vector(7 downto 0);

  -- Micro code outputs
  signal LCycle             : std_logic_vector(2 downto 0);
  signal ALU_Op             : T_ALU_Op;
  signal Set_BusA_To        : T_Set_BusA_To;
  signal Set_Addr_To        : T_Set_Addr_To;
  signal Write_Data         : T_Write_Data;
  signal Jump               : std_logic_vector(1 downto 0);
  signal BAAdd              : std_logic_vector(1 downto 0);
  signal BreakAtNA          : std_logic;
  signal ADAdd              : std_logic;
  signal AddY               : std_logic;
  signal PCAdd              : std_logic;
  signal Inc_S              : std_logic;
  signal Dec_S              : std_logic;
  signal LDA                : std_logic;
  signal LDP                : std_logic;
  signal LDX                : std_logic;
  signal LDY                : std_logic;
  signal LDS                : std_logic;
  signal LDDI               : std_logic;
  signal LDALU              : std_logic;
  signal LDAD               : std_logic;
  signal LDBAL              : std_logic;
  signal LDBAH              : std_logic;
  signal SaveP              : std_logic;
  signal Write              : std_logic;

  signal Res_n_i        : std_logic;
  signal Res_n_d        : std_logic;

  signal really_rdy     : std_logic;
  signal WRn_i          : std_logic;

  signal NMI_entered    : std_logic;

begin
  NMI_ack <= NMIAct;
 
  -- gate Rdy with read/write to make an "OK, it's really OK to stop the processor 
  really_rdy <= Rdy or not(WRn_i);
  Sync <= '1' when MCycle = "000" else '0';
  EF <= EF_i;
  MF <= MF_i;
  XF <= XF_i;
  R_W_n <= WRn_i;
  ML_n <= '0' when IR(7 downto 6) /= "10" and IR(2 downto 1) = "11" and MCycle(2 downto 1) /= "00" else '1';
  VP_n <= '0' when IRQCycle = '1' and (MCycle = "101" or MCycle = "110") else '1';
  VDA <= '1' when Set_Addr_To_r /= Set_Addr_To_PBR else '0';
  VPA <= '1' when Jump(1) = '0' else '0';

  -- debugging signals
  DEBUG.I <= IR;
  DEBUG.A <= ABC(7 downto 0);
  DEBUG.X <= X(7 downto 0);
  DEBUG.Y <= Y(7 downto 0);
  DEBUG.S <= std_logic_vector(S(7 downto 0));
  DEBUG.P <= P;

  mcode : entity work.T65_MCode
    port map(
--inputs
      Mode        => Mode_r,
      IR          => IR,
      MCycle      => MCycle,
      P           => P,
--outputs
      LCycle      => LCycle,
      ALU_Op      => ALU_Op,
      Set_BusA_To => Set_BusA_To,
      Set_Addr_To => Set_Addr_To,
      Write_Data  => Write_Data,
      Jump        => Jump,
      BAAdd       => BAAdd,
      BreakAtNA   => BreakAtNA,
      ADAdd       => ADAdd,
      AddY        => AddY,
      PCAdd       => PCAdd,
      Inc_S       => Inc_S,
      Dec_S       => Dec_S,
      LDA         => LDA,
      LDP         => LDP,
      LDX         => LDX,
      LDY         => LDY,
      LDS         => LDS,
      LDDI        => LDDI,
      LDALU       => LDALU,
      LDAD        => LDAD,
      LDBAL       => LDBAL,
      LDBAH       => LDBAH,
      SaveP       => SaveP,
      Write       => Write
      );

  alu : entity work.T65_ALU
    port map(
      Mode => Mode_r,
      BCD_en => BCD_en_r,
      Op => ALU_Op_r,
      BusA => BusA_r,
      BusB => BusB,
      P_In => P,
      P_Out => P_Out,
      Q => ALU_Q
      );

  -- the 65xx design requires at least two clock cycles before
  -- starting its reset sequence (according to datasheet)
  process (Res_n, Clk)
  begin
    if Res_n = '0' then
      Res_n_i <= '0';
      Res_n_d <= '0';
    elsif Clk'event and Clk = '1' then
      Res_n_i <= Res_n_d;
      Res_n_d <= '1';
    end if;
  end process;

  process (Res_n_i, Clk)
  begin
    if Res_n_i = '0' then
      PC <= (others => '0');  -- Program Counter
      IR <= "00000000";
      S <= (others => '0');       -- Dummy
      PBR <= (others => '0');
      DBR <= (others => '0');

      Mode_r <= (others => '0');
      BCD_en_r <= '1';
      ALU_Op_r <= ALU_OP_BIT;
      Write_Data_r <= Write_Data_DL;
      Set_Addr_To_r <= Set_Addr_To_PBR;

      WRn_i <= '1';
      EF_i <= '1';
      MF_i <= '1';
      XF_i <= '1';

    elsif Clk'event and Clk = '1' then  
      if (Enable = '1') then
        if (really_rdy = '1') then
          WRn_i <= not Write or RstCycle;

          PBR <= (others => '1'); -- Dummy
          DBR <= (others => '1'); -- Dummy
          EF_i <= '0';    -- Dummy
          MF_i <= '0';    -- Dummy
          XF_i <= '0';    -- Dummy

          if MCycle  = "000" then
            Mode_r <= Mode;
            BCD_en_r <= BCD_en;

            if IRQCycle = '0' and NMICycle = '0' then
              PC <= PC + 1;
            end if;

            if IRQCycle = '1' or NMICycle = '1' then
              IR <= "00000000";
            else
              IR <= DI;
            end if;

            if LDS = '1' then -- LAS won't work properly if not limited to machine cycle 0
              S(7 downto 0) <= unsigned(ALU_Q);
            end if;
          end if;

          ALU_Op_r <= ALU_Op;
          Write_Data_r <= Write_Data;
          if Break = '1' then
            Set_Addr_To_r <= Set_Addr_To_PBR;
          else
            Set_Addr_To_r <= Set_Addr_To;
          end if;

          if Inc_S = '1' then
            S <= S + 1;
          end if;
          if Dec_S = '1' and (RstCycle = '0' or Mode="00") then  -- 6502 only?
            S <= S - 1;
          end if;

          if IR = "00000000" and MCycle = "001" and IRQCycle = '0' and NMICycle = '0' then
            PC <= PC + 1;
          end if;
          --
          -- jump control logic
          --
          case Jump is
            when "01" =>
              PC <= PC + 1;
            when "10" =>
              PC <= unsigned(DI & DL);
            when "11" =>
              if PCAdder(8) = '1' then
                if DL(7) = '0' then
                  PC(15 downto 8) <= PC(15 downto 8) + 1;
                else
                  PC(15 downto 8) <= PC(15 downto 8) - 1;
                end if;
              end if;
              PC(7 downto 0) <= PCAdder(7 downto 0);
            when others => null;
          end case;
        end if;
      end if;
    end if;
  end process;

  PCAdder <= resize(PC(7 downto 0),9) + resize(unsigned(DL(7) & DL),9) when PCAdd = '1'
         else "0" & PC(7 downto 0);

  process (Res_n_i, Clk)
    variable tmpP:std_logic_vector(7 downto 0);--Lets try to handle loading P at mcycle=0 and set/clk flags at same cycle
  begin
    if Res_n_i = '0' then
      P <= x"00"; -- ensure we have nothing set on reset
    elsif Clk'event and Clk = '1' then
      tmpP:=P;
      if (Enable = '1') then
        if (really_rdy = '1') then
          if MCycle = "000" then
            if LDA = '1' then
              ABC(7 downto 0) <= ALU_Q;
            end if;
            if LDX = '1' then
              X(7 downto 0) <= ALU_Q;
            end if;
            if LDY = '1' then
              Y(7 downto 0) <= ALU_Q;
            end if;
            if (LDA or LDX or LDY) = '1' then
              tmpP:=P_Out;
            end if;
          end if;
          if SaveP = '1' then
            tmpP:=P_Out;
          end if;
          if LDP = '1' then
            tmpP:=ALU_Q;
          end if;
          if IR(4 downto 0) = "11000" then
            case IR(7 downto 5) is
            when "000" =>--0x18(clc)
              tmpP(Flag_C) := '0';
            when "001" =>--0x38(sec)
              tmpP(Flag_C) := '1';
            when "010" =>--0x58(cli)
              tmpP(Flag_I) := '0';
            when "011" =>--0x78(sei)
              tmpP(Flag_I) := '1';
            when "101" =>--0xb8(clv)
              tmpP(Flag_V) := '0';
            when "110" =>--0xd8(cld)
              tmpP(Flag_D) := '0';
            when "111" =>--0xf8(sed)
              tmpP(Flag_D) := '1';
            when others =>
            end case;
          end if;
          tmpP(Flag_B) := '1';
          if IR = "00000000" and MCycle = "100" and RstCycle = '0' then
            --This should happen after P has been pushed to stack
            tmpP(Flag_I) := '1';
          end if;
          if RstCycle = '1' then
            tmpP(Flag_I) := '1';
            tmpP(Flag_D) := '0';
          end if;
          tmpP(Flag_1) := '1';

          P<=tmpP;--new way

          if IR(4 downto 0)/="10000" or Jump/="01" then -- delay interrupts during branches (checked with Lorenz test and real 6510), not best way yet, though - but works...
            IRQ_n_o <= IRQ_n;
          end if;
        end if;
        -- detect nmi even if not rdy
        if IR(4 downto 0)/="10000" or Jump/="01" then -- delay interrupts during branches (checked with Lorenz test and real 6510) not best way yet, though - but works...
          NMI_n_o <= NMI_n;
        end if;
      end if;
      -- act immediately on SO pin change
      -- The signal is sampled on the trailing edge of phi1 and must be externally synchronized (from datasheet)
      SO_n_o <= SO_n;
		if SO_n_o = '1' and SO_n = '0' then
          P(Flag_V) <= '1';
      end if;

    end if;
  end process;

---------------------------------------------------------------------------
--
-- Buses
--
---------------------------------------------------------------------------

  process (Res_n_i, Clk)
  begin
    if Res_n_i = '0' then
      BusA_r <= (others => '0');
      BusB <= (others => '0');
      BusB_r <= (others => '0');
      AD <= (others => '0');
      BAL <= (others => '0');
      BAH <= (others => '0');
      DL <= (others => '0');
    elsif Clk'event and Clk = '1' then
      if (Enable = '1') then
        NMI_entered <= '0';
        if (really_rdy = '1') then
          BusA_r <= BusA;
          BusB <= DI;

          -- not really nice, but no better way found yet !
          if Set_Addr_To_r = Set_Addr_To_PBR or Set_Addr_To_r = Set_Addr_To_ZPG then
            BusB_r <= std_logic_vector(unsigned(DI(7 downto 0)) + 1); -- required for SHA
          end if;

          case BAAdd is
          when "01" =>
            -- BA Inc
            AD <= std_logic_vector(unsigned(AD) + 1);
            BAL <= std_logic_vector(unsigned(BAL) + 1);
          when "10" =>
            -- BA Add
            BAL <= std_logic_vector(resize(unsigned(BAL(7 downto 0)),9) + resize(unsigned(BusA),9));
          when "11" =>
            -- BA Adj
            if BAL(8) = '1' then
              BAH <= std_logic_vector(unsigned(BAH) + 1);
            end if;
          when others =>
          end case;

          -- modified to use Y register as well
          if ADAdd = '1' then
            if (AddY = '1') then
              AD <= std_logic_vector(unsigned(AD) + unsigned(Y(7 downto 0)));
            else
              AD <= std_logic_vector(unsigned(AD) + unsigned(X(7 downto 0)));
            end if;
          end if;

          if IR = "00000000" then
            BAL <= (others => '1');
            BAH <= (others => '1');
            if RstCycle = '1' then
              BAL(2 downto 0) <= "100";
            elsif NMICycle = '1' or (NMIAct = '1' and MCycle="100") or NMI_entered='1' then
              BAL(2 downto 0) <= "010";
              if MCycle="100" then
                NMI_entered <= '1';
              end if;
            else
              BAL(2 downto 0) <= "110";
            end if;
            if Set_addr_To_r = Set_Addr_To_BA then
              BAL(0) <= '1';
            end if;
          end if;

          if LDDI = '1' then
            DL <= DI;
          end if;
          if LDALU = '1' then
            DL <= ALU_Q;
          end if;
          if LDAD = '1' then
            AD <= DI;
          end if;
          if LDBAL = '1' then
            BAL(7 downto 0) <= DI;
          end if;
          if LDBAH = '1' then
            BAH <= DI;
          end if;
        end if;
      end if;
    end if;
  end process;

  Break <= (BreakAtNA and not BAL(8)) or (PCAdd and not PCAdder(8));

  with Set_BusA_To select
    BusA <=
      DI                                    when Set_BusA_To_DI,
      ABC(7 downto 0)                       when Set_BusA_To_ABC,
      X(7 downto 0)                         when Set_BusA_To_X,
      Y(7 downto 0)                         when Set_BusA_To_Y,
      std_logic_vector(S(7 downto 0))       when Set_BusA_To_S,
      P                                     when Set_BusA_To_P,
      ABC(7 downto 0) and DI                when Set_BusA_To_DA,
      (ABC(7 downto 0) or x"ee") and DI     when Set_BusA_To_DAO,--ee for OAL instruction. constant may be different on other platforms.TODO:Move to generics
      (ABC(7 downto 0) or x"ee") and DI and X(7 downto 0)    when Set_BusA_To_DAX,--XAA, ee for OAL instruction. constant may be different on other platforms.TODO:Move to generics
      ABC(7 downto 0) and X(7 downto 0)     when Set_BusA_To_AAX,--SAX, SHA
      (others => '-')                       when Set_BusA_To_DONTCARE;--Can probably remove this

  with Set_Addr_To_r select
    A <=
      "0000000000000001" & std_logic_vector(S(7 downto 0))                            when Set_Addr_To_SP,
      DBR & "00000000" & AD                                                           when Set_Addr_To_ZPG,
      "00000000" & BAH & BAL(7 downto 0)                                              when Set_Addr_To_BA,
      PBR & std_logic_vector(PC(15 downto 8)) & std_logic_vector(PCAdder(7 downto 0)) when Set_Addr_To_PBR;

  -- This is the P that gets pushed on stack with correct B flag. I'm not sure if NMI also clears B, but I guess it does.
  PwithB<=(P and x"ef") when (IRQCycle='1' or NMICycle='1') else P;

  with Write_Data_r select
    DO <=
      DL                                  when Write_Data_DL,
      ABC(7 downto 0)                     when Write_Data_ABC,
      X(7 downto 0)                       when Write_Data_X,
      Y(7 downto 0)                       when Write_Data_Y,
      std_logic_vector(S(7 downto 0))     when Write_Data_S,
      PwithB                              when Write_Data_P,
      std_logic_vector(PC(7 downto 0))    when Write_Data_PCL,
      std_logic_vector(PC(15 downto 8))   when Write_Data_PCH,
      ABC(7 downto 0) and X(7 downto 0)   when Write_Data_AX,
      ABC(7 downto 0) and X(7 downto 0) and BusB_r(7 downto 0) when Write_Data_AXB, -- no better way found yet...
      X(7 downto 0) and BusB_r(7 downto 0) when Write_Data_XB, -- no better way found yet...
      Y(7 downto 0) and BusB_r(7 downto 0) when Write_Data_YB, -- no better way found yet...
      (others=>'-')                       when Write_Data_DONTCARE;--Can probably remove this


-------------------------------------------------------------------------
--
-- Main state machine
--
-------------------------------------------------------------------------

  process (Res_n_i, Clk)
  begin
    if Res_n_i = '0' then
      MCycle <= "001";
      RstCycle <= '1';
      IRQCycle <= '0';
      NMICycle <= '0';
      NMIAct <= '0';
    elsif Clk'event and Clk = '1' then
      if (Enable = '1') then
        if (really_rdy = '1') then
          if MCycle = LCycle or Break = '1' then
            MCycle <= "000";
            RstCycle <= '0';
            IRQCycle <= '0';
            NMICycle <= '0';
            if NMIAct = '1' and IR/=x"00" then -- delay NMI further if we just executed a BRK
              NMICycle <= '1';
              NMIAct <= '0'; -- reset NMI edge detector if we start processing the NMI
            elsif IRQ_n_o = '0' and P(Flag_I) = '0' then
              IRQCycle <= '1';
            end if;
          else
            MCycle <= std_logic_vector(unsigned(MCycle) + 1);
          end if;
        end if;
        --detect NMI even if not rdy    
        if NMI_n_o = '1' and (NMI_n = '0' and (IR(4 downto 0)/="10000" or Jump/="01")) then -- branches have influence on NMI start (not best way yet, though - but works...)
          NMIAct <= '1';
        end if;
        -- we entered NMI during BRK instruction
        if NMI_entered='1' then
          NMIAct <= '0';
        end if;
      end if;
    end if;
  end process;

end;
