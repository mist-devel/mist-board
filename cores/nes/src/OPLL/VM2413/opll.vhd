--
-- Opll.vhd
--
-- Copyright (c) 2006 Mitsutaka Okazaki (brezza@pokipoki.org)
-- All rights reserved.
--
-- Redistribution and use of this source code or any derivative works, are
-- permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice,
--    this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
-- 3. Redistributions may not be sold, nor may they be used in a commercial
--    product or activity without specific prior written permission.
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

--
--  modified by t.hara
--

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;
    use work.vm2413.all;

entity opll is
    port(
        xin         : in  std_logic;
        xout        : out std_logic;
        xena        : in  std_logic;
        d           : in  std_logic_vector( 7 downto 0 );
        a           : in  std_logic;
        cs_n        : in  std_logic;
        we_n        : in  std_logic;
        ic_n        : in  std_logic;
        mixout      : out std_logic_vector(13 downto 0 )
    );
end opll;

architecture rtl of opll is
    component slotcounter
    generic (
        delay   : in    integer
    );
    port (
        clk     : in    std_logic;
        reset   : in    std_logic;
        clkena  : in    std_logic;

        slot    : out   std_logic_vector( 4 downto 0 );
        stage   : out   std_logic_vector( 1 downto 0 )
    );
    end component;

    component controller port (
        clk     : in    std_logic;
        reset   : in    std_logic;
        clkena  : in    std_logic;

        slot    : in    slot_type;
        stage   : in    stage_type;

        wr      : in    std_logic;
        addr    : in    std_logic_vector( 7 downto 0 );
        data    : in    std_logic_vector( 7 downto 0 );

        am      : out   am_type;
        pm      : out   pm_type;
        wf      : out   wf_type;
        ml      : out   ml_type;
        tl      : out   db_type;
        fb      : out   fb_type;
        ar      : out   ar_type;
        dr      : out   dr_type;
        sl      : out   sl_type;
        rr      : out   rr_type;
        blk     : out   blk_type;
        fnum    : out   fnum_type;
        rks     : out   rks_type;
        key     : out   std_logic;
        rhythm  : out   std_logic
    );
    end component;

    component envelopegenerator
    port (
        clk     : in    std_logic;
        reset   : in    std_logic;
        clkena  : in    std_logic;

        slot    : in    slot_type;
        stage   : in    stage_type;
        rhythm  : in    std_logic;

        am      : in    am_type;
        tl      : in    db_type;
        ar      : in    ar_type;
        dr      : in    dr_type;
        sl      : in    sl_type;
        rr      : in    rr_type;
        rks     : in    rks_type;
        key     : in    std_logic;

        egout   : out   std_logic_vector( 12 downto 0 )
    );
    end component;

    component phasegenerator
    port (
        clk     : in    std_logic;
        reset   : in    std_logic;
        clkena  : in    std_logic;

        slot    : in    slot_type;
        stage   : in    stage_type;
        rhythm  : in    std_logic;

        pm      : in    pm_type;
        ml      : in    ml_type;
        blk     : in    blk_type;
        fnum    : in    fnum_type;
        key     : in    std_logic;

        noise   : out   std_logic;
        pgout   : out   std_logic_vector( 17 downto 0 )
    );
    end component;

    component operator
    port (
        clk     : in    std_logic;
        reset   : in    std_logic;
        clkena  : in    std_logic;
        slot    : in    slot_type;
        stage   : in    stage_type;
        rhythm  : in    std_logic;

        wf      : in    wf_type;
        fb      : in    fb_type;

        noise   : in    std_logic;
        pgout   : in    std_logic_vector( 17 downto 0 );
        egout   : in    std_logic_vector( 12 downto 0 );

        faddr   : out   ch_type;
        fdata   : in    signed_li_type;

        opout   : out   std_logic_vector( 13 downto 0 )
    );
    end component;

    component outputgenerator
    port (
        clk     : in    std_logic;
        reset   : in    std_logic;
        clkena  : in    std_logic;
        slot    : in    slot_type;
        stage   : in    stage_type;
        rhythm  : in    std_logic;

        opout   : in    std_logic_vector( 13 downto 0 );

        faddr   : in    ch_type;
        fdata   : out   signed_li_type;

        maddr   : in    slot_type;
        mdata   : out   signed_li_type
    );
    end component;

    component temporalmixer
    port (
        clk     : in std_logic;
        reset   : in std_logic;
        clkena  : in std_logic;

        slot    : in slot_type;
        stage   : in stage_type;

        rhythm  : in std_logic;

        maddr   : out slot_type;
        mdata   : in signed_li_type;

        mixout  : out std_logic_vector(13 downto 0)
    );
    end component;

    signal reset    : std_logic;

    signal opllptr  : std_logic_vector( 7 downto 0 );
    signal oplldat  : std_logic_vector( 7 downto 0 );
    signal opllwr   : std_logic;

    signal am       : am_type;
    signal pm       : pm_type;
    signal wf       : wf_type;
    signal tl       : db_type;
    signal fb       : fb_type;
    signal ar       : ar_type;
    signal dr       : dr_type;
    signal sl       : sl_type;
    signal rr       : rr_type;
    signal ml       : ml_type;
    signal fnum     : fnum_type;
    signal blk      : blk_type;
    signal rks      : rks_type;
    signal key      : std_logic;

    signal rhythm   : std_logic;

    signal noise    : std_logic;
    signal pgout    : std_logic_vector( 17 downto 0 );  --  ������ 9bit, ������ 9bit

    signal egout    : std_logic_vector( 12 downto 0 );

    signal opout    : std_logic_vector( 13 downto 0 );


    signal faddr    : ch_type;
    signal maddr    : slot_type;
    signal fdata    : signed_li_type;
    signal mdata    : signed_li_type;

    signal state2   : std_logic_vector( 6 downto 0 );
    signal state5   : std_logic_vector( 6 downto 0 );
    signal state8   : std_logic_vector( 6 downto 0 );
    signal slot     : slot_type;
    signal slot2    : slot_type;
    signal slot5    : slot_type;
    signal slot8    : slot_type;
    signal stage    : stage_type;
    signal stage2   : stage_type;
    signal stage5   : stage_type;
    signal stage8   : stage_type;

begin

    xout    <= xin;
    reset   <= not ic_n;

    --  CPU�A�N�Z�X���� ------------------------------------------------------
    process( xin, reset )
    begin
        if( reset ='1' )then
            opllwr  <= '0';
            opllptr <= (others =>'0');
        elsif( xin'event and xin = '1' )then
            if( xena = '1' )then
                if(    cs_n = '0' and we_n = '0' and a = '0' )then
                    --  �����W�X�^�A�h���X�w�背�W�X�^ �ւ̏�������
                    opllptr <= d;
                    opllwr  <= '0';
                elsif( cs_n = '0' and we_n = '0' and a = '1' )then
                    --  �����W�X�^ �ւ̏�������
                    oplldat <= d;
                    opllwr  <= '1';
                end if;
            end if;
        end if;
    end process;

    --  �^�C�~���O�W�F�l���[�^ -----------------------------------------------
    s0: slotcounter
    generic map(
        delay   => 0
    )
    port map(
        clk     => xin,
        reset   => reset,
        clkena  => xena,
        slot    => slot,
        stage   => stage
    );

    s2: slotcounter
    generic map(
        delay   => 2
    )
    port map(
        clk     => xin,
        reset   => reset,
        clkena  => xena,
        slot    => slot2,
        stage   => stage2
    );

    s5: slotcounter
    generic map(
        delay   => 5
    )
    port map(
        clk     => xin,
        reset   => reset,
        clkena  => xena,
        slot    => slot5,
        stage   => stage5
    );

    s8: slotcounter
    generic map(
        delay   => 8
    )
    port map(
        clk     => xin,
        reset   => reset,
        clkena  => xena,
        slot    => slot8,
        stage   => stage8
    );

    -- no delay
    ct: controller port map (
        xin,reset,xena, slot, stage, opllwr,opllptr,oplldat,
        am,pm,wf,ml,tl,fb,ar,dr,sl,rr,blk,fnum,rks,key,rhythm);

    -- 2 stages delay
    eg: envelopegenerator port map (
        xin,reset,xena,
        slot2, stage2, rhythm,
        am, tl, ar, dr, sl, rr, rks, key,
        egout
    );

    pg: phasegenerator port map (
        xin,reset,xena,
        slot2, stage2, rhythm,
        pm, ml, blk, fnum, key,
        noise, pgout
    );

    -- 5 stages delay
    op: operator port map (
        xin,reset,xena,
        slot5, stage5, rhythm,
        wf, fb, noise, pgout, egout, faddr, fdata, opout
    );

    -- 8 stages delay
    og: outputgenerator port map (
        xin, reset, xena, slot8, stage8, rhythm,
        opout, faddr, fdata, maddr, mdata
    );

    -- independent from delay
    tm: temporalmixer port map (
        xin, reset, xena,
        slot, stage, rhythm,
        maddr, mdata,
        mixout
    );

end rtl;

