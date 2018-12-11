--
-- OutputGenerator.vhd
--
-- Copyright (c) 2006 Mitsutaka Okazaki (brezza@pokipoki.org)
-- All rights reserved.
--
-- Redistribution and use of this source code or any derivative works, are
-- permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice,
--      this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--      notice, this list of conditions and the following disclaimer in the
--      documentation and/or other materials provided with the distribution.
-- 3. Redistributions may not be sold, nor may they be used in a commercial
--      product or activity without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
-- TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
-- CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
-- EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
-- PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
-- OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
-- WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
-- OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
-- ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--
--
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use WORK.VM2413.ALL;

entity OutputGenerator is
    port (
        clk         : in    std_logic;
        reset       : in    std_logic;
        clkena      : in    std_logic;
        slot        : in    SLOT_TYPE;
        stage       : in    STAGE_TYPE;

        rhythm      : in    std_logic;
        opout       : in    std_logic_vector( 13 downto 0 );

        faddr       : in    CH_TYPE;
        fdata       : out   SIGNED_LI_TYPE;

        maddr       : in    SLOT_TYPE;
        mdata       : out   SIGNED_LI_TYPE
    );
end OutputGenerator;

architecture RTL of OutputGenerator is

    component FeedbackMemory
        port (
            clk     : in    std_logic;
            reset   : in    std_logic;
            wr      : in    std_logic;
            waddr   : in    CH_TYPE;
            wdata   : in    SIGNED_LI_TYPE;
            raddr   : in    CH_TYPE;
            rdata   : out   SIGNED_LI_TYPE
        );
    end component;

    component OutputMemory
        port (
            clk     : in    std_logic;
            reset   : in    std_logic;
            wr      : in    std_logic;
            addr    : in    SLOT_TYPE;
            wdata   : in    SIGNED_LI_TYPE;
            rdata   : out   SIGNED_LI_TYPE;
            addr2   : in    SLOT_TYPE;
            rdata2  : out   SIGNED_LI_TYPE
        );
    end component;

    component LinearTable
        port (
            clk      : in   std_logic;
            reset    : in   std_logic;
            addr     : in   std_logic_vector( 13 downto 0 );
            data     : out  SIGNED_LI_TYPE
        );
    end component;

    function AVERAGE ( L : SIGNED_LI_TYPE ; R : SIGNED_LI_TYPE ) return SIGNED_LI_TYPE is
        variable vL, vR : std_logic_vector(LI_TYPE'high + 2 downto 0);
    begin

        --  符号＋絶対値 → ２の補数
        if( L.sign = '0' )then
            vL := "00" & L.value;
        else
            vL := not ( "00" & L.value ) + '1';
        end if;
        if( R.sign = '0' )then
            vR := "00" & R.value;
        else
            vR := not ( "00" & R.value ) + '1';
        end if;

        vL := vL + vR;

        --  ２の補数 → 符号＋絶対値、ついでに 1/2 倍。ここで１ビット消失。
        if vL(vL'high) = '0' then -- positive
            return ( sign => '0', value => vL(vL'high-1 downto 1) );
        else -- negative
            vL := not ( vL - '1' );
            return ( sign => '1', value => vL(vL'high-1 downto 1) );
        end if;

    end;

    signal fb_wr, mo_wr : std_logic;
    signal fb_addr      : CH_TYPE;
    signal mo_addr      : SLOT_TYPE;
    signal li_data, fb_wdata, mo_wdata, mo_rdata : SIGNED_LI_TYPE;
begin

    Fmem : FeedbackMemory port map(
        clk     => clk,
        reset   => reset,
        wr      => fb_wr,
        waddr   => fb_addr,
        wdata   => fb_wdata,
        raddr   => faddr,
        rdata   => fdata
    );

    Mmem : OutputMemory port map(
        clk     => clk,
        reset   => reset,
        wr      => mo_wr,
        addr    => mo_addr,
        wdata   => mo_wdata,
        rdata   => mo_rdata,
        addr2   => maddr,
        rdata2  => mdata
    );

    Ltbl : LinearTable port map (
        clk     => clk,
        reset   => reset,
        addr    => opout,           --  0～127 (opout は FF の出力だからダイレクトに入れても問題ない）
        data    => li_data          --  0～511
    );

    process( reset, clk )
    begin
        if( reset = '1' )then
            mo_wr <= '0';
            fb_wr <= '0';
        elsif( clk'event and clk = '1' )then
            if( clkena = '1' )then
                mo_addr <= slot;

                if( stage = 0 )then
                    mo_wr   <= '0';
                    fb_wr   <= '0';

                elsif( stage = 1 )then
                    --  opout に所望の値が入ってくるステージ
                elsif( stage = 2 )then
                    --  待ち
                elsif( stage = 3 )then
                    --  LinerTable から opout で指定されたアドレスに対応する値が出てくるステージ
                    if( slot(0) = '0' )then
                        --  フィードバックメモリにはモジュレータのときしか書き込まない
                        fb_addr <= conv_integer(slot)/2;
                        fb_wdata<= AVERAGE(mo_rdata, li_data);
                        fb_wr   <= '1';
                    end if;
                    -- Store raw output
                    mo_wdata<= li_data;
                    mo_wr   <= '1';
                end if;
            end if;
        end if;
    end process;

end RTL;
