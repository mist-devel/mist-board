-- ****
-- T65(b) core. In an effort to merge and maintain bug fixes ....
--
-- See list of changes in T65 top file (T65.vhd)...
--
-- ****
-- 65xx compatible microprocessor core
--
-- FPGAARCADE SVN: $Id: T65_MCode.vhd 1234 2015-02-28 20:14:50Z wolfgang.scherr $
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
-- Limitations :
--   See in T65 top file (T65.vhd)...

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use ieee.std_logic_unsigned.all; 
use work.T65_Pack.all;

entity T65_MCode is
  port(
    Mode                    : in  std_logic_vector(1 downto 0);      -- "00" => 6502, "01" => 65C02, "10" => 65816
    IR                      : in  std_logic_vector(7 downto 0);
    MCycle                  : in  T_Lcycle;
    P                       : in  std_logic_vector(7 downto 0);
    Rdy_mod                 : in  std_logic;
    LCycle                  : out T_Lcycle;
    ALU_Op                  : out T_ALU_Op;
    Set_BusA_To             : out T_Set_BusA_To; -- DI,A,X,Y,S,P,DA,DAO,DAX,AAX
    Set_Addr_To             : out T_Set_Addr_To; -- PC Adder,S,AD,BA
    Write_Data              : out T_Write_Data;  -- DL,A,X,Y,S,P,PCL,PCH,AX,AXB,XB,YB
    Jump                    : out std_logic_vector(1 downto 0); -- PC,++,DIDL,Rel
    BAAdd                   : out std_logic_vector(1 downto 0); -- None,DB Inc,BA Add,BA Adj
    BAQuirk                 : out std_logic_vector(1 downto 0); -- None,And,Copy
    BreakAtNA               : out std_logic;
    ADAdd                   : out std_logic;
    AddY                    : out std_logic;
    PCAdd                   : out std_logic;
    Inc_S                   : out std_logic;
    Dec_S                   : out std_logic;
    LDA                     : out std_logic;
    LDP                     : out std_logic;
    LDX                     : out std_logic;
    LDY                     : out std_logic;
    LDS                     : out std_logic;
    LDDI                    : out std_logic;
    LDALU                   : out std_logic;
    LDAD                    : out std_logic;
    LDBAL                   : out std_logic;
    LDBAH                   : out std_logic;
    SaveP                   : out std_logic;
    Write                   : out std_logic
  );
end T65_MCode;

architecture rtl of T65_MCode is

  signal Branch : std_logic;
  signal ALUmore:std_logic;

begin

  with IR(7 downto 5) select
    Branch <= not P(Flag_N) when "000",
                  P(Flag_N) when "001",
              not P(Flag_V) when "010",
                  P(Flag_V) when "011",
              not P(Flag_C) when "100",
                  P(Flag_C) when "101",
              not P(Flag_Z) when "110",
                  P(Flag_Z) when others;

  process (IR, MCycle, P, Branch, Mode, Rdy_mod)
  begin
    lCycle      <= Cycle_1;
    Set_BusA_To <= Set_BusA_To_ABC;
    Set_Addr_To <= Set_Addr_To_PBR;
    Write_Data  <= Write_Data_DL;
    Jump        <= (others => '0');
    BAAdd       <= "00";
    BAQuirk     <= "00";
    BreakAtNA   <= '0';
    ADAdd       <= '0';
    PCAdd       <= '0';
    Inc_S       <= '0';
    Dec_S       <= '0';
    LDA         <= '0';
    LDP         <= '0';
    LDX         <= '0';
    LDY         <= '0';
    LDS         <= '0';
    LDDI        <= '0';
    LDALU       <= '0';
    LDAD        <= '0';
    LDBAL       <= '0';
    LDBAH       <= '0';
    SaveP       <= '0';
    Write       <= '0';
    AddY        <= '0';
    ALUmore     <= '0';

    case IR(7 downto 5) is
      when "100" => -- covers $8x,$9x
        case IR(1 downto 0) is
          when "00" => -- IR: $80,$84,$88,$8C,$90,$94,$98,$9C
            Set_BusA_To <= Set_BusA_To_Y;
            if IR(4 downto 2)="111" then   --  SYA ($9C)
              if Rdy_mod = '0' then
                Write_Data <= Write_Data_YB;
              else
                Write_Data <= Write_Data_Y;
              end if;
            else
              Write_Data <= Write_Data_Y;
            end if;
          when "10" => -- IR: $82,$86,$8A,$8E,$92,$96,$9A,$9E
            Set_BusA_To <= Set_BusA_To_X;
            if IR(4 downto 2)="111" then   --  SXA ($9E)
              if Rdy_mod = '0' then
                Write_Data <= Write_Data_XB;
              else
                Write_Data <= Write_Data_X;
              end if;
            else
              Write_Data <= Write_Data_X;
            end if;
          when "11" => -- IR: $83,$87,$8B,$8F,$93,$97,$9B,$9F
            if IR(4 downto 2)="110" then   --  SHS ($9B)
              Set_BusA_To <= Set_BusA_To_AAX;
              LDS <= '1';
            else
              Set_BusA_To <= Set_BusA_To_ABC;
            end if;
            if IR(4 downto 2)="111" or IR(4 downto 2)="110" or IR(4 downto 2)="100" then   --  SHA ($9F, $93), SHS ($9B)
              if Rdy_mod = '0' then
                Write_Data <= Write_Data_AXB;
              else
                Write_Data <= Write_Data_AX;
              end if;
            else
              Write_Data <= Write_Data_AX;
            end if;
          when others => -- IR: $81,$85,$89,$8D,$91,$95,$99,$9D
            Write_Data <= Write_Data_ABC;
        end case;
      when "101" => -- covers $Ax,$Bx
        Set_BusA_To <= Set_BusA_To_DI;
        case IR(1 downto 0) is
          when "00" => -- IR: $A0,$A4,$A8,$AC,$B0,$B4,$B8,$BC
            if IR(4) /= '1' or IR(2) /= '0' then--only for $A0,$A4,$A8,$AC or $B4,$BC
              LDY <= '1';
            end if;
          when "01" => -- IR: $A1,$A5,$A9,$AD,$B1,$B5,$B9,$BD
            LDA <= '1';
          when "10" => -- IR: $A2,$A6,$AA,$AE,$B2,$B6,$BA,$BE
            LDX <= '1';
          when others => -- IR: $A3,$A7,$AB,$AF,$B3,$B7,$BB,$BF (undoc)
            LDX <= '1';
            LDA <= '1';
            if IR(4 downto 2)="110" then   --  LAS (BB)
              Set_BusA_To <= Set_BusA_To_S;
              LDS <= '1';
            end if;
        end case;
      when "110" => -- covers $Cx,$Dx
        case IR(1 downto 0) is
          when "00" => -- IR: $C0,$C4,$C8,$CC,$D0,$D4,$D8,$DC
            if IR(4) = '0' then--only for $Cx
              LDY <= '1';
            end if;
            Set_BusA_To <= Set_BusA_To_Y;
          when others => -- IR: $C1,$C5,$C9,$CD,$D1,$D5,$D9,$DD, $C2,$C6,$CA,$CE,$D2,$D6,$DA,$DE, $C3,$C7,$CB,$CF,$D3,$D7,$DB,$DF
            Set_BusA_To <= Set_BusA_To_ABC;
        end case;
      when "111" => -- covers $Ex,$Fx
        case IR(1 downto 0) is
        when "00" => -- IR: $E0,$E4,$E8,$EC,$F0,$F4,$F8,$FC
          if IR(4) = '0' then -- only $Ex
            LDX <= '1';
          end if;
          Set_BusA_To <= Set_BusA_To_X;
        when others => -- IR: $E1,$E5,$E9,$ED,$F1,$F5,$F9,$FD, $E2,$E6,$EA,$EE,$F2,$F6,$FA,$FE, $E3,$E7,$EB,$EF,$F3,$F7,$FB,$FF
          Set_BusA_To <= Set_BusA_To_ABC;
        end case;
      when others =>
    end case;

    if IR(7 downto 6) /= "10" and IR(1) = '1' and (mode="00" or IR(0)='0') then--covers $0x-$7x, $Cx-$Fx x=2,3,6,7,A,B,E,F, for 6502 undocs
      if IR=x"eb" then
        Set_BusA_To <= Set_BusA_To_ABC; -- alternate SBC ($EB)
      else
        Set_BusA_To <= Set_BusA_To_DI;
      end if;
    end if;

    case IR(4 downto 0) is
      -- IR: $00,$20,$40,$60,$80,$A0,$C0,$E0
      --     $08,$28,$48,$68,$88,$A8,$C8,$E8
      --     $0A,$2A,$4A,$6A,$8A,$AA,$CA,$EA
      --     $18,$38,$58,$78,$98,$B8,$D8,$F8
      --     $1A,$3A,$5A,$7A,$9A,$BA,$DA,$FA
      when "00000" | "01000" | "01010" | "11000" | "11010" =>
        -- Implied
        case IR is
          when x"00" =>
            -- BRK ($00)
            lCycle <= Cycle_6;
            case MCycle is
              when Cycle_1 =>
                Set_Addr_To <= Set_Addr_To_SP;
                Write_Data <= Write_Data_PCH;
                Write <= '1';
              when Cycle_2 =>
                Dec_S <= '1';
                Set_Addr_To <= Set_Addr_To_SP;
                Write_Data <= Write_Data_PCL;
                Write <= '1';
              when Cycle_3 =>
                Dec_S <= '1';
                Set_Addr_To <= Set_Addr_To_SP;
                Write_Data <= Write_Data_P;
                Write <= '1';
              when Cycle_4 =>
                Dec_S <= '1';
                Set_Addr_To <= Set_Addr_To_BA;
              when Cycle_5 =>
                LDDI <= '1';
                Set_Addr_To <= Set_Addr_To_BA;
              when Cycle_6 =>
                Jump <= "10";
              when others =>
            end case;
          when x"20" => -- JSR ($20)
            lCycle <= Cycle_5;
            case MCycle is
              when Cycle_1 =>
                Jump <= "01";
                LDDI <= '1';
                Set_Addr_To <= Set_Addr_To_SP;
              when Cycle_2 =>
                Set_Addr_To <= Set_Addr_To_SP;
                Write_Data <= Write_Data_PCH;
                Write <= '1';
              when Cycle_3 =>
                Dec_S <= '1';
                Set_Addr_To <= Set_Addr_To_SP;
                Write_Data <= Write_Data_PCL;
                Write <= '1';
              when Cycle_4 =>
                Dec_S <= '1';
              when Cycle_5 =>
                Jump <= "10";
              when others =>
              end case;
            when x"40" => -- RTI ($40)
              lCycle <= Cycle_5;
              case MCycle is
              when Cycle_1 =>
                Set_Addr_To <= Set_Addr_To_SP;
              when Cycle_2 =>
                Inc_S <= '1';
                Set_Addr_To <= Set_Addr_To_SP;
              when Cycle_3 =>
                Inc_S <= '1';
                Set_Addr_To <= Set_Addr_To_SP;
                Set_BusA_To <= Set_BusA_To_DI;
              when Cycle_4 =>
                LDP <= '1';
                Inc_S <= '1';
                LDDI <= '1';
                Set_Addr_To <= Set_Addr_To_SP;
              when Cycle_5 =>
                Jump <= "10";
              when others =>
            end case;
          when x"60" => -- RTS ($60)
            lCycle <= Cycle_5;
            case MCycle is
              when Cycle_1 =>
                Set_Addr_To <= Set_Addr_To_SP;
              when Cycle_2 =>
                Inc_S <= '1';
                Set_Addr_To <= Set_Addr_To_SP;
              when Cycle_3 =>
                Inc_S <= '1';
                LDDI <= '1';
                Set_Addr_To <= Set_Addr_To_SP;
              when Cycle_4 =>
                Jump <= "10";
              when Cycle_5 =>
                Jump <= "01";
              when others =>
              end case;
            when x"08" | x"48" | x"5a" | x"da" => -- PHP, PHA, PHY*, PHX*  ($08,$48,$5A,$DA)
              lCycle <= Cycle_2;
              if Mode = "00" and IR(1) = '1' then--2 cycle nop
                lCycle <= Cycle_1;
              end if;
              case MCycle is
              when Cycle_1 =>
                if mode/="00" or IR(1)='0' then --wrong on 6502
                  Write <= '1';
                  case IR(7 downto 4) is
                  when "0000" =>
                    Write_Data <= Write_Data_P;
                  when "0100" =>
                    Write_Data <= Write_Data_ABC;
                  when "0101" =>
                    if Mode /= "00" then
                      Write_Data <= Write_Data_Y;
                    else
                      Write <= '0';
                    end if;
                  when "1101" =>
                    if Mode /= "00" then
                      Write_Data <= Write_Data_X;
                    else
                      Write <= '0';
                    end if;
                  when others =>
                  end case;
                  Set_Addr_To <= Set_Addr_To_SP;
                end if;
              when Cycle_2 =>
                Dec_S <= '1';
              when others =>
            end case;
          when  x"28" | x"68" | x"7a" | x"fa" => -- PLP, PLA, PLY*, PLX* ($28,$68,$7A,$FA)
            lCycle <= Cycle_3;
            if Mode = "00" and IR(1) = '1' then--2 cycle nop
              lCycle <= Cycle_1;
            end if;
            case IR(7 downto 4) is
              when "0010" =>--plp
                LDP <= '1';
              when "0110" =>--pla
                LDA <= '1';
              when "0111" =>--ply not for 6502
                if Mode /= "00" then
                  LDY <= '1';
                end if;
              when "1111" =>--plx not for 6502
                if Mode /= "00" then
                  LDX <= '1';
                end if;
              when others =>
            end case;
            case MCycle is
              when Cycle_sync =>
                if Mode /= "00" or IR(1) = '0' then--wrong on 6502
                  SaveP <= '1';
                end if;
              when Cycle_1 =>
                if Mode /= "00" or IR(1) = '0' then--wrong on 6502
                  Set_Addr_To <= Set_Addr_To_SP;
                  LDP <= '0';
                end if;
              when Cycle_2 =>
                Inc_S <= '1';
                Set_Addr_To <= Set_Addr_To_SP;
                LDP <= '0';
              when Cycle_3 =>
                Set_BusA_To <= Set_BusA_To_DI;
              when others =>
            end case;
          when x"a0" | x"c0" | x"e0" => -- LDY, CPY, CPX ($A0,$C0,$E0)
            -- Immediate
            case MCycle is
              when Cycle_sync =>
              when Cycle_1 =>
                Jump <= "01";
              when others =>
            end case;
          when x"88" => -- DEY ($88)
            LDY <= '1';
            case MCycle is
              when Cycle_sync =>
              when Cycle_1 =>
                Set_BusA_To <= Set_BusA_To_Y;
              when others =>
            end case;
          when x"ca" => -- DEX ($CA)
            LDX <= '1';
            case MCycle is
              when Cycle_sync =>
              when Cycle_1 =>
                Set_BusA_To <= Set_BusA_To_X;
              when others =>
            end case;
          when x"1a" | x"3a" => -- INC*, DEC* ($1A,$3A)
            if Mode /= "00" then
              LDA <= '1'; -- A
            else
              lCycle <= Cycle_1;--undoc 2 cycle nop
            end if;
            case MCycle is
              when Cycle_sync =>
              when Cycle_1 =>
                Set_BusA_To <= Set_BusA_To_S;
              when others =>
            end case;
          when x"0a" | x"2a" | x"4a" | x"6a" => -- ASL, ROL, LSR, ROR ($0A,$2A,$4A,$6A)
            LDA <= '1'; -- A
            Set_BusA_To <= Set_BusA_To_ABC;
            case MCycle is
              when Cycle_sync =>
              when Cycle_1 =>
              when others =>
            end case;
          when x"8a" | x"98" => -- TYA, TXA ($8A,$98)
            LDA <= '1';
            case MCycle is
              when Cycle_sync =>
              when Cycle_1 =>
              when others =>
            end case;
          when x"aa" | x"a8" => -- TAX, TAY ($AA,$A8)
            case MCycle is
              when Cycle_sync =>
              when Cycle_1 =>
                Set_BusA_To <= Set_BusA_To_ABC;
              when others =>
            end case;
          when x"9a" => -- TXS ($9A)
            LDS <= '1'; -- will be set only in Cycle_sync
          when x"ba" => -- TSX ($BA)
            LDX <= '1';
            case MCycle is
              when Cycle_sync =>
              when Cycle_1 =>
                Set_BusA_To <= Set_BusA_To_S;
              when others =>
            end case;
          when x"80" => -- undoc: NOP imm2 ($80)
            case MCycle is
              when Cycle_sync =>
              when Cycle_1 =>
                Jump <= "01";
              when others =>
            end case;
          when others => -- others ($0A,$EA, $18,$38,$58,$78,$B8,$C8,$D8,$E8,$F8)
            case MCycle is
              when Cycle_sync =>
              when others =>
            end case;
        end case;

      -- IR: $01,$21,$41,$61,$81,$A1,$C1,$E1
      --     $03,$23,$43,$63,$83,$A3,$C3,$E3
      when "00001" | "00011" =>
        -- Zero Page Indexed Indirect (d,x)
        lCycle <= Cycle_5;
        if IR(7 downto 6) /= "10" then -- ($01,$21,$41,$61,$C1,$E1,$03,$23,$43,$63,$C3,$E3)
          LDA <= '1';
          if Mode="00" and IR(1)='1' then
            lCycle <= Cycle_7;
          end if;
        end if;
        case MCycle is
          when Cycle_1 =>
            Jump <= "01";
            LDAD <= '1';
            Set_Addr_To <= Set_Addr_To_ZPG;
          when Cycle_2 =>
            ADAdd <= '1';
            Set_Addr_To <= Set_Addr_To_ZPG;
          when Cycle_3 =>
            BAAdd <= "01";
            LDBAL <= '1';
            Set_Addr_To <= Set_Addr_To_ZPG;
          when Cycle_4 =>
            LDBAH <= '1';
            if IR(7 downto 5) = "100" then
              Write <= '1';
            end if;
            Set_Addr_To <= Set_Addr_To_BA;
          when Cycle_5=>
            if Mode="00" and IR(1)='1' and IR(7 downto 6)/="10" then
              Set_Addr_To <= Set_Addr_To_BA;
              Write <= '1';
              LDDI<='1';
            end if;
          when Cycle_6=>
              Write <= '1';
              LDALU<='1';
              SaveP<='1';
              Set_Addr_To <= Set_Addr_To_BA;
          when Cycle_7 =>
            ALUmore <= '1';
            Set_BusA_To <= Set_BusA_To_ABC;
          when others =>
        end case;

      -- IR: $09,$29,$49,$69,$89,$A9,$C9,$E9
      when "01001" =>
        -- Immediate
        if IR(7 downto 5)/="100" then -- all except undoc. NOP imm2 (not $89)
          LDA <= '1';
        end if;
        case MCycle is
          when Cycle_1 =>
            Jump <= "01";
          when others =>
        end case;

      -- IR: $0B,$2B,$4B,$6B,$8B,$AB,$CB,$EB
      when "01011" =>
        if Mode="00" then
        -- Immediate undoc for 6500
          case IR(7 downto 5) is 
            when "010"|"011"|"000"|"001" =>--ALR,ARR
              Set_BusA_To<=Set_BusA_To_DA;
              LDA <= '1';
            when "100" =>--XAA
              Set_BusA_To<=Set_BusA_To_DAX;
              LDA <= '1';
            when "110" =>--SAX (SBX)
              Set_BusA_To<=Set_BusA_To_AAX;
              LDX <= '1';
            when "101" =>--OAL
              Set_BusA_To<=Set_BusA_To_DAO;
              LDA <= '1';
            when others=>
              LDA <= '1';
          end case;
          case MCycle is
            when Cycle_1 =>
              Jump <= "01";
            when others =>
          end case;
        end if;

      -- IR: $02,$22,$42,$62,$82,$A2,$C2,$E2
      --     $12,$32,$52,$72,$92,$B2,$D2,$F2
      when "00010" | "10010" =>
        -- Immediate, SKB, KIL
        case MCycle is
          when Cycle_sync =>
          when Cycle_1 =>
            if IR = "10100010" then
              -- LDX ($A2)
              Jump <= "01";
              LDX <= '1'; -- Moved, Lorenz test showed X changing on SKB (NOPx)
            elsif IR(7 downto 4)="1000" or IR(7 downto 4)="1100" or IR(7 downto 4)="1110" then
              -- undoc: NOP imm2
              Jump <= "01";
            else
              -- KIL !!!
            end if;
          when others =>
        end case;

      -- IR: $04,$24,$44,$64,$84,$A4,$C4,$E4
      when "00100" =>
        -- Zero Page
        lCycle <= Cycle_2;
        case MCycle is
          when Cycle_sync =>
            if IR(7 downto 5) = "001" then--24=BIT zpg
              SaveP <= '1';
            end if;
          when Cycle_1 =>
            Jump <= "01";
            LDAD <= '1';
            if IR(7 downto 5) = "100" then--84=sty zpg (the only write in this group)
              Write <= '1';
            end if;
            Set_Addr_To <= Set_Addr_To_ZPG;
          when Cycle_2 =>
          when others =>
        end case;

      -- IR: $05,$25,$45,$65,$85,$A5,$C5,$E5
      --     $06,$26,$46,$66,$86,$A6,$C6,$E6
      --     $07,$27,$47,$67,$87,$A7,$C7,$E7
      when "00101" | "00110" | "00111" =>
        -- Zero Page
        if IR(7 downto 6) /= "10" and IR(1) = '1' and (mode="00" or IR(0)='0') then--covers 0x-7x,cx-fx x=2,3,6,7,a,b,e,f, for 6502 undocs
          -- Read-Modify-Write
          lCycle <= Cycle_4;
          if Mode="00" and IR(0)='1' then
            LDA<='1';
          end if;
          case MCycle is
            when Cycle_1 =>
              Jump <= "01";
              LDAD <= '1';
              Set_Addr_To <= Set_Addr_To_ZPG;
            when Cycle_2 =>
              LDDI <= '1';
              if Mode="00"  then--The old 6500 writes back what is just read, before changing. The 65c does another read
                Write <= '1';
              end if;
              Set_Addr_To <= Set_Addr_To_ZPG;
            when Cycle_3 =>
              LDALU <= '1';
              SaveP <= '1';
              Write <= '1';
              Set_Addr_To <= Set_Addr_To_ZPG;
            when Cycle_4 =>
              if Mode="00" and IR(0)='1' then
                Set_BusA_To<=Set_BusA_To_ABC;
                ALUmore <= '1'; -- For undoc DCP/DCM support
                LDDI <= '1';    -- requires DIN to reflect DOUT!
              end if;
            when others =>
          end case;
        else
          lCycle <= Cycle_2;
          if IR(7 downto 6) /= "10" then
            LDA <= '1';
          end if;
          case MCycle is
            when Cycle_sync =>
            when Cycle_1 =>
              Jump <= "01";
              LDAD <= '1';
              if IR(7 downto 5) = "100" then
                Write <= '1';
              end if;
              Set_Addr_To <= Set_Addr_To_ZPG;
            when Cycle_2 =>
            when others =>
          end case;
        end if;

      -- IR: $0C,$2C,$4C,$6C,$8C,$AC,$CC,$EC
      when "01100" =>
        -- Absolute
        if IR(7 downto 6) = "01" and IR(4 downto 0) = "01100" then -- JMP ($4C,$6C)
          if IR(5) = '0' then
            lCycle <= Cycle_2;
            case MCycle is
              when Cycle_1 =>
                Jump <= "01";
                LDDI <= '1';
              when Cycle_2 =>
                Jump <= "10";
              when others =>
            end case;
          else
            lCycle <= Cycle_4;
            case MCycle is
              when Cycle_1 =>
                Jump <= "01";
                LDDI <= '1';
                LDBAL <= '1';
              when Cycle_2 =>
                LDBAH <= '1';
                if Mode /= "00" then
                  Jump <= "10";
                end if;
                if Mode = "00" then
                  Set_Addr_To <= Set_Addr_To_BA;
                end if;
              when Cycle_3 =>
                LDDI <= '1';
                if Mode = "00" then
                  Set_Addr_To <= Set_Addr_To_BA;
                  BAAdd <= "01";      -- DB Inc
                else
                  Jump <= "01";
                end if;
              when Cycle_4 =>
                Jump <= "10";
              when others =>
            end case;
          end if;
        else
          lCycle <= Cycle_3;
          case MCycle is
            when Cycle_sync =>
              if IR(7 downto 5) = "001" then--2c-BIT
                SaveP <= '1';
              end if;
            when Cycle_1 =>
              Jump <= "01";
              LDBAL <= '1';
            when Cycle_2 =>
              Jump <= "01";
              LDBAH <= '1';
              if IR(7 downto 5) = "100" then--80, sty, the only write in this group
                Write <= '1';
              end if;
              Set_Addr_To <= Set_Addr_To_BA;
            when Cycle_3 =>
            when others =>
          end case;
        end if;

      -- IR: $0D,$2D,$4D,$6D,$8D,$AD,$CD,$ED
      --     $0E,$2E,$4E,$6E,$8E,$AE,$CE,$EE
      --     $0F,$2F,$4F,$6F,$8F,$AF,$CF,$EF
      when "01101" | "01110" | "01111" =>
        -- Absolute
        if IR(7 downto 6) /= "10" and IR(1) = '1' and (mode="00" or IR(0)='0') then -- ($0E,$2E,$4E,$6E,$CE,$EE, $0F,$2F,$4F,$6F,$CF,$EF)
          -- Read-Modify-Write
          lCycle <= Cycle_5;
          if Mode="00" and IR(0) = '1' then
            LDA <= '1';
          end if;
          case MCycle is
            when Cycle_1 =>
              Jump <= "01";
              LDBAL <= '1';
            when Cycle_2 =>
              Jump <= "01";
              LDBAH <= '1';
              Set_Addr_To <= Set_Addr_To_BA;
            when Cycle_3 =>
              LDDI <= '1';
              if Mode="00" then--The old 6500 writes back what is just read, before changing. The 65c does another read
                Write <= '1';
              end if;
              Set_Addr_To <= Set_Addr_To_BA;
            when Cycle_4 =>
              Write <= '1';
              LDALU <= '1';
              SaveP <= '1';
              Set_Addr_To <= Set_Addr_To_BA;
            when Cycle_5 =>
              if Mode="00" and IR(0)='1' then
                ALUmore <= '1'; -- For undoc DCP/DCM support
                Set_BusA_To<=Set_BusA_To_ABC;
              end if;
            when others =>
          end case;
        else
          lCycle <= Cycle_3;
          if IR(7 downto 6) /= "10" then -- all but $8D, $8E, $8F, $AD, $AE, $AF ($AD does set LDA in an earlier case statement)
            LDA <= '1';
          end if;
          case MCycle is
            when Cycle_sync =>
            when Cycle_1 =>
              Jump <= "01";
              LDBAL <= '1';
            when Cycle_2 =>
              Jump <= "01";
              LDBAH <= '1';
              if IR(7 downto 5) = "100" then--8d
                Write <= '1';
              end if;
              Set_Addr_To <= Set_Addr_To_BA;
            when Cycle_3 =>
            when others =>
          end case;
        end if;

      -- IR: $10,$30,$50,$70,$90,$B0,$D0,$F0
      when "10000" =>
        -- Relative
              -- This circuit dictates when the last
              -- microcycle occurs for the branch depending on
              -- whether or not the branch is taken and if a page
              -- is crossed...
        if (Branch = '1') then
                 lCycle <= Cycle_3; -- We're done @ T3 if branching...upper
                          -- level logic will stop at T2 if no page cross
                          -- (See the Break signal)
        else
                 lCycle <= Cycle_1;
        end if;
              -- This decodes the current microcycle and takes the
              -- proper course of action...
        case MCycle is
                -- On the T1 microcycle, increment the program counter
                -- and instruct the upper level logic to fetch the offset
                -- from the Din bus and store it in the data latches. This
                -- will be the last microcycle if the branch isn't taken.
          when Cycle_1 =>
            Jump <= "01"; -- Increments the PC by one (PC will now be PC+2)
                          -- from microcycle T0.
            LDDI <= '1';  -- Tells logic in top level (T65.vhd) to route
                          -- the Din bus to the memory data latch (DL)
                          -- so that the branch offset is fetched.
                -- In microcycle T2, tell the logic in the top level to
                -- add the offset.  If the most significant byte of the
                -- program counter (i.e. the current "page") does not need
                -- updating, we are done here...the Break signal at the
                -- T65.vhd level takes care of that...
          when Cycle_2 =>
            Jump    <= "11"; -- Tell the PC Jump logic to use relative mode.
            PCAdd   <= '1';  -- This tells the PC adder to update itself with
                             -- the current offset recently fetched from
                             -- memory.
                -- The following is microcycle T3 :
                -- The program counter should be completely updated
                -- on this cycle after the page cross is detected.
                -- We don't need to do anything here...
          when Cycle_3 =>
          when others => null; -- Do nothing.
        end case;

      -- IR: $11,$31,$51,$71,$91,$B1,$D1,$F1
      --     $13,$33,$53,$73,$93,$B3,$D3,$F3
      when "10001" | "10011" =>
        lCycle <= Cycle_5;
        if IR(7 downto 6) /= "10" then -- ($11,$31,$51,$71,$D1,$F1,$13,$33,$53,$73,$D3,$F3)
          LDA <= '1';
          if Mode="00" and IR(1)='1' then
            lCycle <= Cycle_7;
          end if;
        end if;
        case MCycle is
          when Cycle_1 =>
            Jump <= "01";
            LDAD <= '1';
            Set_Addr_To <= Set_Addr_To_ZPG;
          when Cycle_2 =>
            LDBAL <= '1';
            BAAdd <= "01";  -- DB Inc
            Set_Addr_To <= Set_Addr_To_ZPG;
          when Cycle_3 =>
            Set_BusA_To <= Set_BusA_To_Y;
            BAAdd <= "10";  -- BA Add
            LDBAH <= '1';
            Set_Addr_To <= Set_Addr_To_BA;
          when Cycle_4 =>
            BAAdd <= "11";  -- BA Adj
            if IR(7 downto 5) = "100" then
              Write <= '1';
              if IR(3 downto 0) = x"3" then
                BAQuirk <= "10"; -- COPY
              end if;
            elsif IR(1)='0' or IR=x"B3" then -- Dont do this on $x3, except undoc LAXiy $B3 (says real CPU and Lorenz tests)
              BreakAtNA <= '1';
            end if;
              Set_Addr_To <= Set_Addr_To_BA;
          when Cycle_5 =>
            if Mode="00" and IR(1)='1' and IR(7 downto 6)/="10" then
              Set_Addr_To <= Set_Addr_To_BA;
              LDDI<='1';
              Write <= '1';
            end if;
          when Cycle_6 =>
            LDALU<='1';
            SaveP<='1';
            Write <= '1';
            Set_Addr_To <= Set_Addr_To_BA;
          when Cycle_7 =>
            ALUmore <= '1';
            Set_BusA_To<=Set_BusA_To_ABC;
          when others =>
        end case;

      -- IR: $14,$34,$54,$74,$94,$B4,$D4,$F4
      --     $15,$35,$55,$75,$95,$B5,$D5,$F5
      --     $16,$36,$56,$76,$96,$B6,$D6,$F6
      --     $17,$37,$57,$77,$97,$B7,$D7,$F7
      when "10100" | "10101" | "10110" | "10111" =>
        -- Zero Page, X
        if IR(7 downto 6) /= "10" and IR(1) = '1' and (Mode="00" or IR(0)='0') then -- ($16,$36,$56,$76,$D6,$F6, $17,$37,$57,$77,$D7,$F7)
          -- Read-Modify-Write
          if Mode="00" and IR(0)='1' then
            LDA<='1';
          end if;
          lCycle <= Cycle_5;
          case MCycle is
            when Cycle_1 =>
              Jump <= "01";
              LDAD <= '1';
              Set_Addr_To <= Set_Addr_To_ZPG;
            when Cycle_2 =>
              ADAdd <= '1';
              Set_Addr_To <= Set_Addr_To_ZPG;
            when Cycle_3 =>
              LDDI <= '1';
              if Mode="00" then -- The old 6500 writes back what is just read, before changing. The 65c does another read
                Write <= '1';
              end if;
              Set_Addr_To <= Set_Addr_To_ZPG;
            when Cycle_4 =>
              LDALU <= '1';
              SaveP <= '1';
              Write <= '1';
              Set_Addr_To <= Set_Addr_To_ZPG;
              if Mode="00" and IR(0)='1' then
                LDDI<='1';
              end if;
            when Cycle_5 =>
              if Mode="00" and IR(0)='1' then
                ALUmore <= '1'; -- For undoc DCP/DCM support
                Set_BusA_To<=Set_BusA_To_ABC;
              end if;
            when others =>
          end case;
        else
          lCycle <= Cycle_3;
          if IR(7 downto 6) /= "10" and IR(0)='1' then -- dont LDA on undoc skip
            LDA <= '1';
          end if;
          case MCycle is
            when Cycle_sync =>
            when Cycle_1 =>
              Jump <= "01";
              LDAD <= '1';
              Set_Addr_To <= Set_Addr_To_ZPG;
            when Cycle_2 =>
              ADAdd <= '1';
              -- Added this check for Y reg. use, added undocs
              if (IR(3 downto 1) = "011") then -- ($16,$36,$56,$76,$96,$B6,$D6,$F6,$17,$37,$57,$77,$97,$B7,$D7,$F7)
                AddY <= '1';
              end if;
              if IR(7 downto 5) = "100" then -- ($14,$34,$15,$35,$16,$36,$17,$37) the only write instruction
                Write <= '1';
              end if;
              Set_Addr_To <= Set_Addr_To_ZPG;
            when Cycle_3 => null;
            when others =>
          end case;
        end if;

      -- IR: $19,$39,$59,$79,$99,$B9,$D9,$F9
      --     $1B,$3B,$5B,$7B,$9B,$BB,$DB,$FB
      when "11001" | "11011" =>
        -- Absolute Y
        lCycle <= Cycle_4;
        if IR(7 downto 6) /= "10" then
          LDA <= '1';
          if Mode="00" and IR(1)='1' then
            lCycle <= Cycle_6;
          end if;
        end if;
        case MCycle is
          when Cycle_1 =>
            Jump <= "01";
            LDBAL <= '1';
          when Cycle_2 =>
            Jump <= "01";
            Set_BusA_To <= Set_BusA_To_Y;
            BAAdd <= "10";  -- BA Add
            LDBAH <= '1';
            Set_Addr_To <= Set_Addr_To_BA;
          when Cycle_3 =>
            BAAdd <= "11";  -- BA adj
            if IR(7 downto 5) = "100" then--99/9b
              Write <= '1';
              if IR(3 downto 0) = x"B" then
                BAQuirk <= "01"; -- AND
              end if;
            elsif IR(1)='0' or IR=x"BB" then -- Dont do this on $xB, except undoc $BB (says real CPU and Lorenz tests)
              BreakAtNA <= '1';
            end if;
            Set_Addr_To <= Set_Addr_To_BA;
          when Cycle_4 => -- just for undoc
            if Mode="00" and IR(1)='1' and IR(7 downto 6)/="10" then
              Set_Addr_To <= Set_Addr_To_BA;
              LDDI<='1';
              Write <= '1';
            end if;
          when Cycle_5 =>
            Write <= '1';
            LDALU<='1';
            Set_Addr_To <= Set_Addr_To_BA;
            SaveP<='1';
          when Cycle_6 =>
            ALUmore <= '1';
            Set_BusA_To <= Set_BusA_To_ABC;
          when others =>
        end case;

      -- IR: $1C,$3C,$5C,$7C,$9C,$BC,$DC,$FC
      --     $1D,$3D,$5D,$7D,$9D,$BD,$DD,$FD
      --     $1E,$3E,$5E,$7E,$9E,$BE,$DE,$FE
      --     $1F,$3F,$5F,$7F,$9F,$BF,$DF,$FF
      when "11100" | "11101" | "11110" | "11111" =>
        -- Absolute X
        if IR(7 downto 6) /= "10" and IR(1) = '1' and (Mode="00" or IR(0)='0') then -- ($1E,$3E,$5E,$7E,$DE,$FE, $1F,$3F,$5F,$7F,$DF,$FF)
          -- Read-Modify-Write
          lCycle <= Cycle_6;
          if Mode="00" and IR(0)='1' then
            LDA <= '1';
          end if;
          case MCycle is
            when Cycle_1 =>
              Jump <= "01";
              LDBAL <= '1';
            when Cycle_2 =>
              Jump <= "01";
              Set_BusA_To <= Set_BusA_To_X;
              BAAdd <= "10";      -- BA Add
              LDBAH <= '1';
              Set_Addr_To <= Set_Addr_To_BA;
            when Cycle_3 =>
              BAAdd <= "11";      -- BA adj
              Set_Addr_To <= Set_Addr_To_BA;
            when Cycle_4 =>
              LDDI <= '1';
              if Mode="00" then--The old 6500 writes back what is just read, before changing. The 65c does another read
                Write <= '1';
              end if;
              Set_Addr_To <= Set_Addr_To_BA;
            when Cycle_5 =>
              LDALU <= '1';
              SaveP <= '1';
              Write <= '1';
              Set_Addr_To <= Set_Addr_To_BA;
            when Cycle_6 =>
              if Mode="00" and IR(0)='1' then
                ALUmore <= '1';
                Set_BusA_To <= Set_BusA_To_ABC;
              end if;
            when others =>
          end case;
        else -- ($1C,$3C,$5C,$7C,$9C,$BC,$DC,$FC, $1D,$3D,$5D,$7D,$9D,$BD,$DD,$FD, $9E,$BE,$9F,$BF)
          lCycle <= Cycle_4;--Or 3 if not page crossing
          if IR(7 downto 6) /= "10" then
            if Mode/="00" or IR(4)='0' or IR(1 downto 0)/="00" then
              LDA <= '1';
            end if;
          end if;
          case MCycle is
            when Cycle_sync =>
            when Cycle_1 =>
              Jump <= "01";
              LDBAL <= '1';
            when Cycle_2 =>
              Jump <= "01";
              -- special case $BE which uses Y reg as index!!
              if(IR(7 downto 6)="10" and IR(4 downto 1)="1111") then
                Set_BusA_To <= Set_BusA_To_Y;
              else
                Set_BusA_To <= Set_BusA_To_X;
              end if;
              BAAdd <= "10";      -- BA Add
              LDBAH <= '1';
              Set_Addr_To <= Set_Addr_To_BA;
            when Cycle_3 =>
              BAAdd <= "11";      -- BA adj
              if IR(7 downto 5) = "100" then -- ($9C,$9D,$9E,$9F)
                Write <= '1';
                case IR(1 downto 0) is
                when "00"|"10" => BAQuirk <= "01"; -- AND
                when "11" => BAQuirk <= "10"; -- COPY
                when others => null;
                end case;
              else
                BreakAtNA <= '1';
              end if;
              Set_Addr_To <= Set_Addr_To_BA;
            when Cycle_4 =>
            when others =>
          end case;
        end if;
      when others =>
    end case;
  end process;

  process (IR, MCycle, Mode,ALUmore)
  begin
    -- ORA, AND, EOR, ADC, NOP, LD, CMP, SBC
    -- ASL, ROL, LSR, ROR, BIT, LD, DEC, INC
    case IR(1 downto 0) is
      when "00" =>
        case IR(4 downto 2) is
        -- IR: $00,$20,$40,$60,$80,$A0,$C0,$E0
        --     $04,$24,$44,$64,$84,$A4,$C4,$E4
        --     $0C,$2C,$4C,$6C,$8C,$AC,$CC,$EC
        when "000" | "001" | "011" =>
          case IR(7 downto 5) is
            when "110" | "111" => -- CP ($C0,$C4,$CC,$E0,$E4,$EC)
              ALU_Op <= ALU_OP_CMP;
            when "101" => -- LD ($A0,$A4,$AC)
              ALU_Op <= ALU_OP_EQ2;
            when "001" => -- BIT ($20,$24,$2C - $20 is ignored, as its a jmp)
              ALU_Op <= ALU_OP_BIT;
            when others => -- other, NOP/ST ($x0,$x4,$xC)
              ALU_Op <= ALU_OP_EQ1;
          end case;

        -- IR: $08,$28,$48,$68,$88,$A8,$C8,$E8
        when "010" =>
          case IR(7 downto 5) is
            when "111" | "110" => -- IN ($C8,$E8)
              ALU_Op <= ALU_OP_INC;
            when "100" => -- DEY ($88)
              ALU_Op <= ALU_OP_DEC;
            when others => -- LD
              ALU_Op <= ALU_OP_EQ2;
          end case;

        -- IR: $18,$38,$58,$78,$98,$B8,$D8,$F8
        when "110" =>
          case IR(7 downto 5) is
            when "100" => -- TYA ($98)
              ALU_Op <= ALU_OP_EQ2;
            when others =>
              ALU_Op <= ALU_OP_EQ1;
          end case;

        -- IR: $10,$30,$50,$70,$90,$B0,$D0,$F0
        --     $14,$34,$54,$74,$94,$B4,$D4,$F4
        --     $1C,$3C,$5C,$7C,$9C,$BC,$DC,$FC
        when others =>
          case IR(7 downto 5) is
            when "101" => -- LD ($B0,$B4,$BC)
              ALU_Op <= ALU_OP_EQ2;
            when others =>
              ALU_Op <= ALU_OP_EQ1;
          end case;
        end case;

      when "01" => -- OR
        case(to_integer(unsigned(IR(7 downto 5)))) is
          when 0=> -- IR: $01,$05,$09,$0D,$11,$15,$19,$1D
            ALU_Op<=ALU_OP_OR;
          when 1=> -- IR: $21,$25,$29,$2D,$31,$35,$39,$3D
            ALU_Op<=ALU_OP_AND;
          when 2=> -- IR: $41,$45,$49,$4D,$51,$55,$59,$5D
            ALU_Op<=ALU_OP_EOR;
          when 3=> -- IR: $61,$65,$69,$6D,$71,$75,$79,$7D
            ALU_Op<=ALU_OP_ADC; 
          when 4=>-- IR: $81,$85,$89,$8D,$91,$95,$99,$9D
            ALU_Op<=ALU_OP_EQ1; -- STA
          when 5=> -- IR: $A1,$A5,$A9,$AD,$B1,$B5,$B9,$BD
            ALU_Op<=ALU_OP_EQ2; -- LDA
          when 6=> -- IR: $C1,$C5,$C9,$CD,$D1,$D5,$D9,$DD
            ALU_Op<=ALU_OP_CMP;
          when others=> -- IR: $E1,$E5,$E9,$ED,$F1,$F5,$F9,$FD
            ALU_Op<=ALU_OP_SBC;
        end case;

      when "10" =>
        case(to_integer(unsigned(IR(7 downto 5)))) is
          when 0=> -- IR: $02,$06,$0A,$0E,$12,$16,$1A,$1E
            ALU_Op<=ALU_OP_ASL;
            if IR(4 downto 2) = "110" and Mode/="00" then -- 00011010,$1A -> INC acc, not on 6502
              ALU_Op <= ALU_OP_INC;
            end if;
          when 1=> -- IR: $22,$26,$2A,$2E,$32,$36,$3A,$3E
            ALU_Op<=ALU_OP_ROL;
            if IR(4 downto 2) = "110" and Mode/="00" then -- 00111010,$3A -> DEC acc, not on 6502
              ALU_Op <= ALU_OP_DEC;
            end if;
          when 2=> -- IR: $42,$46,$4A,$4E,$52,$56,$5A,$5E
            ALU_Op<=ALU_OP_LSR;
          when 3=> -- IR: $62,$66,$6A,$6E,$72,$76,$7A,$7E
            ALU_Op<=ALU_OP_ROR;
          when 4=> -- IR: $82,$86,$8A,$8E,$92,$96,$9A,$9E
            ALU_Op<=ALU_OP_BIT;
            if IR(4 downto 2) = "010" then   -- 10001010, $8A -> TXA
              ALU_Op <= ALU_OP_EQ2;
            else                             -- 100xxx10, $82,$86,$8E,$92,$96,$9A,$9E
              ALU_Op <= ALU_OP_EQ1;
            end if;
          when 5=> -- IR: $A2,$A6,$AA,$AE,$B2,$B6,$BA,$BE
            ALU_Op<=ALU_OP_EQ2; -- LDX
          when 6=> -- IR: $C2,$C6,$CA,$CE,$D2,$D6,$DA,$DE
            ALU_Op<=ALU_OP_DEC;
          when others=> -- IR: $E2,$E6,$EA,$EE,$F2,$F6,$FA,$FE
            ALU_Op<=ALU_OP_INC;
        end case;

      when others => -- "11" undoc double alu ops
        case(to_integer(unsigned(IR(7 downto 5)))) is
          -- IR: $A3,$A7,$AB,$AF,$B3,$B7,$BB,$BF
          when 5 =>
            if IR=x"bb" then--LAS
              ALU_Op <= ALU_OP_AND;
            else
              ALU_Op <= ALU_OP_EQ2;
            end if;

          -- IR: $03,$07,$0B,$0F,$13,$17,$1B,$1F
          --     $23,$27,$2B,$2F,$33,$37,$3B,$3F
          --     $43,$47,$4B,$4F,$53,$57,$5B,$5F
          --     $63,$67,$6B,$6F,$73,$77,$7B,$7F
          --     $83,$87,$8B,$8F,$93,$97,$9B,$9F
          --     $C3,$C7,$CB,$CF,$D3,$D7,$DB,$DF
          --     $E3,$E7,$EB,$EF,$F3,$F7,$FB,$FF
          when others =>
            if IR=x"6b" then -- ARR
              ALU_Op<=ALU_OP_ARR;
            elsif IR=x"8b" then -- ARR
              ALU_Op<=ALU_OP_XAA;   -- we can't use the bit operation as we don't set all flags...
            elsif IR=x"0b" or IR=x"2b" then -- ANC
              ALU_Op<=ALU_OP_ANC;
            elsif IR=x"eb" then -- alternate SBC
              ALU_Op<=ALU_OP_SBC;
            elsif ALUmore='1'  then 
              case(to_integer(unsigned(IR(7 downto 5)))) is
                when 0=>
                  ALU_Op<=ALU_OP_OR;
                when 1=>
                  ALU_Op<=ALU_OP_AND;
                when 2=>
                  ALU_Op<=ALU_OP_EOR;
                when 3=>
                  ALU_Op<=ALU_OP_ADC;
                when 4=>
                  ALU_Op<=ALU_OP_EQ1; -- STA
                when 5=>
                  ALU_Op<=ALU_OP_EQ2; -- LDA
                when 6=>
                  ALU_Op<=ALU_OP_CMP;
                when others=>
                  ALU_Op<=ALU_OP_SBC;
              end case;
            else
              case(to_integer(unsigned(IR(7 downto 5)))) is
                when 0=>
                  ALU_Op<=ALU_OP_ASL;
                when 1=>
                  ALU_Op<=ALU_OP_ROL;
                when 2=>
                  ALU_Op<=ALU_OP_LSR;
                when 3=>
                  ALU_Op<=ALU_OP_ROR;
                when 4=>
                  ALU_Op<=ALU_OP_BIT;
                when 5=>
                  ALU_Op<=ALU_OP_EQ2; -- LDX
                when 6=>
                  ALU_Op<=ALU_OP_DEC;
                  if IR(4 downto 2)="010" then  -- $6B
                    ALU_Op<=ALU_OP_SAX; -- special SAX (SBX) case
                  end if;
                when others=>
                   ALU_Op<=ALU_OP_INC;
              end case;
            end if;
        end case;
    end case;
  end process;

end;
