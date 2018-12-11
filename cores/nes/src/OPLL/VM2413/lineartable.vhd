--
-- LinearTable.vhd
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

-- ----------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_signed.all;

entity linear_table_mul is
    port (
        i0      : in    std_logic_vector( 5 downto 0 );     --  符号無し 6bit (小数部  6bit)
        i1      : in    std_logic_vector( 9 downto 0 );     --  符号付き10bit (整数部 10bit)
        o       : out   std_logic_vector( 9 downto 0 )      --  符号付き10bit (整数部 10bit)
    );
end linear_table_mul;

architecture rtl of linear_table_mul is
    signal w_mul    : std_logic_vector( 16 downto 0 );      --  符号付き17bit (整数部16bit)
begin

    w_mul   <= ('0' & i0) * i1;
    o       <= w_mul( 15 downto 6 );        --  MSBカット, 小数部下位 6bitカット
end rtl;

-- ----------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;
    use work.vm2413.all;

entity LinearTable is
    port (
        clk     : in    std_logic;
        reset   : in    std_logic;
        addr    : in    std_logic_vector( 13 downto 0 );    --  整数部 8bit, 小数部 6bit
        data    : out   signed_li_type
    );
end LinearTable;

architecture rtl of lineartable is

    component linear_table_mul
        port (
            i0      : in    std_logic_vector( 5 downto 0 );
            i1      : in    std_logic_vector( 9 downto 0 );
            o       : out   std_logic_vector( 9 downto 0 )
        );
    end component;

    type log2lin_type is array ( 0 to 127 ) of std_logic_vector( 8 downto 0 );
    constant log2lin_data : log2lin_type := (
        "111111111","111101001","111010100","111000000",
        "110101101","110011011","110001010","101111001",
        "101101001","101011010","101001011","100111101",
        "100110000","100100011","100010111","100001011",
        "100000000","011110101","011101010","011100000",
        "011010111","011001110","011000101","010111101",
        "010110101","010101101","010100110","010011111",
        "010011000","010010010","010001011","010000110",
        "010000000","001111010","001110101","001110000",
        "001101011","001100111","001100011","001011110",
        "001011010","001010111","001010011","001001111",
        "001001100","001001001","001000110","001000011",
        "001000000","000111101","000111011","000111000",
        "000110110","000110011","000110001","000101111",
        "000101101","000101011","000101001","000101000",
        "000100110","000100100","000100011","000100001",
        "000100000","000011110","000011101","000011100",
        "000011011","000011001","000011000","000010111",
        "000010110","000010101","000010100","000010100",
        "000010011","000010010","000010001","000010000",
        "000010000","000001111","000001110","000001110",
        "000001101","000001101","000001100","000001011",
        "000001011","000001010","000001010","000001010",
        "000001001","000001001","000001000","000001000",
        "000001000","000000111","000000111","000000111",
        "000000110","000000110","000000110","000000101",
        "000000101","000000101","000000101","000000101",
        "000000100","000000100","000000100","000000100",
        "000000100","000000011","000000011","000000011",
        "000000011","000000011","000000011","000000011",
        "000000010","000000010","000000010","000000010",
        "000000010","000000010","000000010","000000000"
    );

    signal ff_sign      : std_logic;
    signal ff_weight    : std_logic_vector(  5 downto 0 );
    signal ff_data0     : std_logic_vector(  8 downto 0 );
    signal ff_data1     : std_logic_vector(  8 downto 0 );

    signal w_addr1      : std_logic_vector( 12 downto 6 );
    signal w_data       : std_logic_vector(  8 downto 0 );
    signal w_sub        : std_logic_vector(  9 downto 0 );  --  符号付き
    signal w_mul        : std_logic_vector(  9 downto 0 );
    signal w_inter      : std_logic_vector(  9 downto 0 );
begin
    w_addr1 <= (addr( 12 downto 6 ) + 1) when( addr( 12 downto 6 ) /= "1111111" )else
               "1111111";

    process( clk )
    begin
        if( clk'event and clk = '1' )then
            --  アドレス指定された次のサイクルで対応する値が出てくる（1cycle delay）
            ff_data0 <= log2lin_data( conv_integer( addr(12 downto 6) ) );
            ff_data1 <= log2lin_data( conv_integer( w_addr1           ) );
        end if;
    end process;

    process( clk )
    begin
        if( clk'event and clk = '1' )then
            ff_sign     <= addr( 13 );
            ff_weight   <= addr( 5 downto 0 );
        end if;
    end process;

    --  補間    (※符号をまたがる場所では 0 になるから ff_sign は気にしない）
    --  o = i0 * (1 - k) + i1 * w = i0 - w * i0 + w * i1 = i0 + w * (i1 - i0)
    w_sub   <=  ('0' & ff_data1) - ('0' & ff_data0);

    u_linear_table_mul: linear_table_mul
    port map (
        i0      => ff_weight,
        i1      => w_sub,
        o       => w_mul
    );

    w_inter <= ('0' & ff_data0) + w_mul;

    process( clk )
    begin
        if( clk'event and clk = '1' )then
            data <= (
                sign    => ff_sign,
                value   => w_inter( 8 downto 0 )
            );
        end if;
    end process;
end rtl;
