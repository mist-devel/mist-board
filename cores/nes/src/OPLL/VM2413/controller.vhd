--
-- Controller.vhd
-- The core controller module of VM2413
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
-- [Description]
--
-- The Controller is the beginning module of the OPLL slot calculation.
-- It manages register accesses from I/O and sends proper voice parameters
-- to the succeding PhaseGenerator and EnvelopeGenerator modules.
-- The one cycle of the Controller consists of 4 stages as follows.
--
-- 1st stage:
--   * Prepare to read the register value for the current slot from RegisterMemory.
--   * Prepare to read the voice parameter for the current slot from VoiceMemory.
--   * Prepare to read the user-voice data from VoiceMemory.
--
-- 2nd stage:
--   * Wait for RegisterMemory and VoiceMemory
--
-- 3rd clock stage:
--   * Update register value if wr='1' and addr points the current OPLL channel.
--   * Update voice parameter if wr='1' and addr points the voice parameter area.
--   * Write register value to RegisterMemory.
--   * Write voice parameter to VoiceMemory.
--
-- 4th stage:
--   * Send voice and register parameters to PhaseGenerator and EnvelopeGenerator.
--   * Increment the number of the current slot.
--
-- Each stage is completed in one clock. Thus the Controller traverses all 18 opll
-- slots in 72 clocks.
--

--
--  modified by t.hara
--

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;
    use work.vm2413.all;

entity controller is port (

    clk     : in    std_logic;
    reset   : in    std_logic;
    clkena  : in    std_logic;

    slot    : in    std_logic_vector( 4 downto 0 );
    stage   : in    std_logic_vector( 1 downto 0 );

    wr      : in    std_logic;
    addr    : in    std_logic_vector( 7 downto 0 );
    data    : in    std_logic_vector( 7 downto 0 );

    -- output parameters for phasegenerator and envelopegenerator
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

    -- slot_out : out slot_id
);
end controller;

architecture rtl of controller is

    component registermemory
        port (
            clk     : in    std_logic;
            reset   : in    std_logic;
            addr    : in    std_logic_vector(  3 downto 0 );
            wr      : in    std_logic;
            idata   : in    std_logic_vector( 23 downto 0 );
            odata   : out   std_logic_vector( 23 downto 0 )
        );
    end component;

    component voicememory port (
        clk     : in std_logic;
        reset   : in std_logic;
        idata   : in voice_type;
        wr       : in std_logic;
        rwaddr : in voice_id_type;
        roaddr : in voice_id_type;
        odata   : out voice_type;
        rodata : out voice_type );
    end component;

    -- the array which caches instrument number of each channel.
    type inst_array is array (ch_type'range) of integer range 0 to 15;
    signal inst_cache : inst_array;

    type kl_array is array (0 to 15) of std_logic_vector(5 downto 0);
    constant kl_table : kl_array := (
        "000000", "011000", "100000", "100101",
        "101000", "101011", "101101", "101111",
        "110000", "110010", "110011", "110100",
        "110101", "110110", "110111", "111000"
    ); -- 0.75db/step, 6db/oct

    -- signals for the read-only access ports of voicememory module.
    signal slot_voice_addr      : voice_id_type;
    signal slot_voice_data      : voice_type;

    -- signals for the read-write access ports of voicememory module.
    signal user_voice_wr        : std_logic;
    signal user_voice_addr      : voice_id_type;
    signal user_voice_rdata     : voice_type;
    signal user_voice_wdata     : voice_type;

    -- signals for the registermemory module.
    signal regs_wr              : std_logic;
    signal regs_addr            : std_logic_vector(  3 downto 0 );
    signal regs_rdata           : std_logic_vector( 23 downto 0 );
    signal regs_wdata           : std_logic_vector( 23 downto 0 );

    signal rflag                : std_logic_vector(  7 downto 0 );
    signal w_channel            : std_logic_vector(  3 downto 0 );
--  signal w_is_carrier         : std_logic;

begin   -- rtl

    --  レジスタ設定値を保持するためのメモリ
    u_register_memory : RegisterMemory
    port map (
        clk     => clk,
        reset   => reset,
        addr    => regs_addr,
        wr      => regs_wr,
        idata   => regs_wdata,
        odata   => regs_rdata
    );

    vmem : voicememory port map (
        clk, reset, user_voice_wdata, user_voice_wr, user_voice_addr, slot_voice_addr,
        user_voice_rdata, slot_voice_data );

    --  レジスタアドレスラッチ (第１ステージ)
    process( reset, clk )
    begin
        if( reset = '1' )then
            regs_addr   <= (others => '0');
        elsif( clk'event and clk = '1' )then
            if clkena='1' then
                if( stage = "00" )then
                    regs_addr <= slot( 4 downto 1 );
                else
                    --  hold
                end if;
            end if;
        end if;
    end process;

    --  現在のスロットの音色データ読み出しアドレスラッチ (第１ステージ)
    process( reset, clk )
    begin
        if( reset = '1' )then
            slot_voice_addr <= 0;
        elsif( clk'event and clk = '1' )then
            if clkena='1' then
                if( stage = "00" )then
                    if( rflag(5) = '1' and w_channel >= "0110" )then
                        --  リズムモードで ch6 以降
                        slot_voice_addr <= conv_integer(slot) - 12 + 32;
                    else
                        slot_voice_addr <= inst_cache(conv_integer(slot)/2) * 2 + conv_integer(slot) mod 2;
                    end if;
                else
                    --  hold
                end if;
            end if;
        end if;
    end process;

    w_channel       <= slot( 4 downto 1 );
--  w_is_carrier    <= slot( 0 );

    process (clk, reset)

        variable kflag : std_logic;
        variable tll : std_logic_vector(db_type'high+1 downto 0);
        variable kll : std_logic_vector(db_type'high+1 downto 0);

        variable regs_tmp       : std_logic_vector(23 downto 0);
        variable user_voice_tmp : voice_type;

        variable fb_buf : fb_type;
        variable wf_buf : wf_type;

        variable extra_mode : std_logic;
        variable vindex : voice_id_type;

    begin   -- process

        if(reset = '1') then

            key <= '0';
            rhythm <= '0';
            tll := (others=>'0');
            kll := (others=>'0');
            kflag := '0';
            rflag <= (others=>'0');
            user_voice_wr <= '0';
            user_voice_addr <= 0;
            regs_wr <='0';
            ar  <= (others=>'0');
            dr  <= (others=>'0');
            sl  <= (others=>'0');
            rr  <= (others=>'0');
            tl  <= (others=>'0');
            fb  <= (others=>'0');
            wf  <= '0';
            ml  <= (others=>'0');
            fnum <= (others=>'0');
            blk <= (others=>'0');
            key <= '0';
            rks <= (others=>'0');
            rhythm <= '0';
            extra_mode := '0';
            vindex := 0;

        elsif clk'event and clk='1' then if clkena='1' then

            case stage is
            --------------------------------------------------------------------------
            -- 1st stage (setting up a read request for register and voice memories.)
            --------------------------------------------------------------------------
            when "00" =>

--              if extra_mode = '0' then
                    -- alternately read modulator or carrior.
                     vindex := conv_integer(slot) mod 2;
--              else
--                  if vindex = voice_id_type'high then
--                      vindex:= 0;
--                  else
--                      vindex:= vindex + 1;
--                  end if;
--              end if;

                user_voice_addr <= vindex;
                regs_wr <= '0';
                user_voice_wr <='0';

            --------------------------------------------------------------------------
            -- 2nd stage (just a wait for register and voice memories.)
            --------------------------------------------------------------------------
            when "01" =>
                null;

            --------------------------------------------------------------------------
            -- 3rd stage (updating a register and voice parameters.)
            --------------------------------------------------------------------------
            when "10" =>

                if wr='1' then

--                  if ( extra_mode = '0' and conv_integer(addr) < 8 ) or
--                       ( extra_mode = '1' and ( conv_integer(addr) - 64 ) / 8 = vindex / 2 ) then
                    if( extra_mode = '0' and conv_integer(addr) < 8 )then

                        -- update user voice parameter.
                        user_voice_tmp := user_voice_rdata;

                        case addr(2 downto 1) is
                            when "00" =>
                                if conv_integer(addr(0 downto 0)) = (vindex mod 2) then
                                    user_voice_tmp.am := data(7);
                                    user_voice_tmp.pm := data(6);
                                    user_voice_tmp.eg := data(5);
                                    user_voice_tmp.kr := data(4);
                                    user_voice_tmp.ml := data(3 downto 0);
                                    user_voice_wr <= '1';
                                end if;

                            when "01" =>
                                if addr(0)='0' and (vindex mod 2 = 0) then
                                    user_voice_tmp.kl := data(7 downto 6);
                                    user_voice_tmp.tl := data(5 downto 0);
                                    user_voice_wr <= '1';
                                elsif addr(0)='1' and (vindex mod 2 = 0) then
                                    user_voice_tmp.wf := data(3);
                                    user_voice_tmp.fb := data(2 downto 0);
                                    user_voice_wr <= '1';
                                elsif addr(0)='1' and (vindex mod 2 = 1) then
                                    user_voice_tmp.kl := data(7 downto 6);
                                    user_voice_tmp.wf := data(4);
                                    user_voice_wr <= '1';
                                end if;

                            when "10" =>
                                if conv_integer(addr(0 downto 0)) = (vindex mod 2) then
                                    user_voice_tmp.ar := data(7 downto 4);
                                    user_voice_tmp.dr := data(3 downto 0);
                                    user_voice_wr <= '1';
                                end if;

                            when "11" =>
                                if conv_integer(addr(0 downto 0)) = (vindex mod 2) then
                                    user_voice_tmp.sl := data(7 downto 4);
                                    user_voice_tmp.rr := data(3 downto 0);
                                    user_voice_wr <= '1';
                                end if;
                        end case;

                        user_voice_wdata <= user_voice_tmp;

                    elsif conv_integer(addr) = 14 then

                        rflag <= data;

                    elsif conv_integer(addr) < 16 then

                        null;

                    elsif conv_integer(addr) <= 63 then

                        if( conv_integer(addr(3 downto 0) ) = conv_integer(slot) / 2 ) then
                            regs_tmp := regs_rdata;
                            case addr( 5 downto 4 ) is
                                when "01" => -- 10h～18h の場合（下位 F-Number）
                                    regs_tmp(7 downto 0) := data;               --  F-Number
                                    regs_wr <= '1';
                                when "10" => -- 20h～28h の場合（Sus, Key, Block, F-Number MSB）
                                    regs_tmp(13) := data(5);                    --  Sus
                                    regs_tmp(12) := data(4);                    --  Key
                                    regs_tmp(11 downto 9) := data(3 downto 1);  --  Block
                                    regs_tmp(8) := data(0);                     --  F-Number
                                    regs_wr <= '1';
                                when "11" => -- 30h～38h の場合（Inst, Vol）
                                    regs_tmp(23 downto 20) := data(7 downto 4); --  Inst
                                    regs_tmp(19 downto 16) := data(3 downto 0); --  Vol
                                    regs_wr <='1';
                                when others =>
                                    null;
                            end case;
                            regs_wdata <= regs_tmp;
                        end if;

                    elsif conv_integer(addr) = 240 then

                        if data(7 downto 0) = "10000000" then
                            extra_mode := '1';
                        else
                            extra_mode := '0';
                        end if;

                    end if;

                end if;

            --------------------------------------------------------------------------
            -- 4th stage (updating a register and voice parameters.)
            --------------------------------------------------------------------------
            when "11" =>

                -- output slot number (for explicit synchonization with other units).
                -- slot_out <= slot;

                -- updating insturument cache
                inst_cache(conv_integer(slot)/2) <= conv_integer(regs_rdata(23 downto 20));

                rhythm <= rflag(5);

                -- updating rhythm status and key flag
                if rflag(5) = '1' and 12 <= slot then
                    case slot is
                        when "01100" | "01101" => -- bd
                            kflag := rflag(4);
                        when "01110" =>                 -- hh
                            kflag := rflag(0);
                        when "01111" =>                 -- sd
                            kflag := rflag(3);
                        when "10000" =>                 -- tom
                            kflag := rflag(2);
                        when "10001" =>                 -- cym
                            kflag := rflag(1);
                        when others => null;
                    end case;
                else
                    kflag := '0';
                end if;

                kflag := kflag or regs_rdata(12);

                -- calculate key-scale attenuation amount.
                kll := (("0"&kl_table(conv_integer(regs_rdata(8 downto 5))))
                         - ("0"&("111"-regs_rdata(11 downto 9))&"000")) & '0';

                if kll(kll'high) ='1' or slot_voice_data.kl = "00" then
                    kll := (others=>'0');
                else
                    kll := shr(kll, "11" - slot_voice_data.kl );
                end if;

                -- calculate base total level from volume register value.
                if rflag(5) = '1' and (slot = "01110" or slot = "10000") then -- hh and cym
                    tll := ('0' & regs_rdata(23 downto 20) & "000");
                elsif( slot(0) = '0' )then
                    tll := ('0' & slot_voice_data.tl & '0'); -- mod
                else
                    tll := ('0' & regs_rdata(19 downto 16) & "000");         -- car
                end if;

                tll := tll + kll;

                if tll(tll'high) ='1' then
                    tl <= (others=>'1');
                else
                    tl <= tll(tl'range);
                end if;

                -- output rks, f-number, block and key-status.
                fnum <= regs_rdata(8 downto 0);
                blk <= regs_rdata(11 downto 9);
                key <= kflag;

                if rflag(5) = '1' and 14 <= slot then
                    if slot_voice_data.kr = '1' then
                        rks <= "0101";
                    else
                        rks <= "00" & regs_rdata(11 downto 10);
                    end if;
                else
                    if slot_voice_data.kr = '1' then
                        rks <= regs_rdata(11 downto 9) & regs_rdata(8);
                    else
                        rks <= "00" & regs_rdata(11 downto 10);
                    end if;
                end if;

                -- output voice parameters
                -- note that wf and fb output must keep its value
                -- at least 3 clocks since the operator module will fetch
                -- the wf and fb 2 clocks later of this stage.
                am <= slot_voice_data.am;
                pm <= slot_voice_data.pm;
                ml <= slot_voice_data.ml;
                wf_buf := slot_voice_data.wf;
                fb_buf := slot_voice_data.fb;
                wf <= wf_buf;
                fb <= fb_buf;
                ar <= slot_voice_data.ar;
                dr <= slot_voice_data.dr;
                sl <= slot_voice_data.sl;

                -- output release rate (depends on the sustine and envelope type).
                if( kflag = '1' ) then -- key on
                    if slot_voice_data.eg = '1' then
                        rr <= "0000";
                    else
                        rr <= slot_voice_data.rr;
                    end if;
                else -- key off
                    if (slot(0) = '0') and not ( rflag(5) = '1' and (7 <= conv_integer(slot)/2) ) then
                        rr  <= "0000";
                    elsif regs_rdata(13) = '1' then
                        rr  <= "0101";
                    elsif slot_voice_data.eg = '0' then
                        rr  <= "0111";
                    else
                        rr  <= slot_voice_data.rr;
                    end if;
                end if;

            end case;

        end if; end if;

    end process;

end rtl;
