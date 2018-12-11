--
-- AttackTable.vhd
-- Envelope attack shaping table for VM2413
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

-------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_signed.all;

entity attack_table_mul is
    port(
        i0      : in    std_logic_vector(  7 downto 0 );    --  符号無し 8bit (整数部 0bit, 小数部 8bit)
        i1      : in    std_logic_vector(  7 downto 0 );    --  符号付き 8bit (整数部 8bit)
        o       : out   std_logic_vector( 13 downto 0 )     --  符号付き14bit (整数部 8bit, 小数部 6bit)
    );
end attack_table_mul;

architecture rtl of attack_table_mul is
    signal w_mul    : std_logic_vector( 16 downto 0 );
begin

    w_mul   <= ('0' & i0) * i1;
    o       <= w_mul( 15 downto 2 );        --  bit16 は bit15 と同じなのでカット。bit1～0 (小数部) は切り捨て。
end rtl;

-------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;
    use ieee.std_logic_arith;

entity AttackTable is
    port(
        clk     : in    std_logic;
        clkena  : in    std_logic;
        addr    : in    std_logic_vector( 21 downto 0 );    --  小数部 15bit
        data    : out   std_logic_vector( 12 downto 0 )     --  小数部  6bit
    );
end AttackTable;

architecture rtl of attacktable is

    component attack_table_mul
        port(
            i0      : in    std_logic_vector(  7 downto 0 );    --  符号無し 8bit (整数部 0bit, 小数部 8bit)
            i1      : in    std_logic_vector(  7 downto 0 );    --  符号付き 8bit (整数部 8bit)
            o       : out   std_logic_vector( 13 downto 0 )     --  符号付き 8bit (整数部 8bit, 小数部 6bit)
        );
    end component;

    type ar_adjust_array is array ( 0 to 127 ) of std_logic_vector( 6 downto 0 );
    constant ar_adjust : ar_adjust_array :=(
        "0000000", "0000000", "0000000", "0000000", "0000000", "0000001", "0000001", "0000001",
        "0000001", "0000001", "0000010", "0000010", "0000010", "0000010", "0000011", "0000011",
        "0000011", "0000011", "0000100", "0000100", "0000100", "0000100", "0000100", "0000101",
        "0000101", "0000101", "0000110", "0000110", "0000110", "0000110", "0000111", "0000111",
        "0000111", "0000111", "0001000", "0001000", "0001000", "0001001", "0001001", "0001001",
        "0001001", "0001010", "0001010", "0001010", "0001011", "0001011", "0001011", "0001100",
        "0001100", "0001100", "0001101", "0001101", "0001101", "0001110", "0001110", "0001110",
        "0001111", "0001111", "0001111", "0010000", "0010000", "0010001", "0010001", "0010001",
        "0010010", "0010010", "0010011", "0010011", "0010100", "0010100", "0010101", "0010101",
        "0010101", "0010110", "0010110", "0010111", "0010111", "0011000", "0011000", "0011001",
        "0011010", "0011010", "0011011", "0011011", "0011100", "0011101", "0011101", "0011110",
        "0011110", "0011111", "0100000", "0100001", "0100001", "0100010", "0100011", "0100100",
        "0100100", "0100101", "0100110", "0100111", "0101000", "0101001", "0101010", "0101011",
        "0101100", "0101101", "0101111", "0110000", "0110001", "0110011", "0110100", "0110110",
        "0111000", "0111001", "0111011", "0111101", "1000000", "1000010", "1000101", "1001000",
        "1001011", "1010000", "1010100", "1011010", "1100010", "1101100", "1110101", "1111111"
    );

    signal ff_w     : std_logic_vector(  7 downto 0 );
    signal ff_d1    : std_logic_vector(  6 downto 0 );
    signal ff_d2    : std_logic_vector(  6 downto 0 );

    signal w_addr1  : std_logic_vector(  6 downto 0 );
    signal w_addr2  : std_logic_vector(  6 downto 0 );
    signal w_sub    : std_logic_vector(  7 downto 0 );  --  符号付き
    signal w_mul    : std_logic_vector( 13 downto 0 );  --  符号付き
    signal w_inter  : std_logic_vector( 13 downto 0 );
begin

    w_addr1 <= addr( 21 downto 15 );
    w_addr2 <= (others => '1') when( addr( 21 downto 15 ) = "1111111" )else
               w_addr1 + 1;

    process( clk )
    begin
        if( clk'event and clk = '1' )then
            if( clkena = '1' )then
                ff_d1 <= ar_adjust( conv_integer( w_addr1 ) );
                ff_d2 <= ar_adjust( conv_integer( w_addr2 ) );
            end if;
        end if;
    end process;

    process( clk )
    begin
        if( clk'event and clk = '1' )then
            if( clkena = '1' )then
                ff_w <= addr( 14 downto 7 );    --  データ自体のビット数が 7bit なので 8bit で十分
            end if;
        end if;
    end process;

    --  補間    (※符号をまたがる場所では 0 になるから ff_sign は気にしない）
    --  o = i1 * (1 - k) + i2 * w = i1 - w * i1 + w * i2 = i1 + w * (i2 - i1)
    w_sub   <= ('0' & ff_d2) - ('0' & ff_d1);

    u_attack_table_mul: attack_table_mul
    port map (
        i0      => ff_w,
        i1      => w_sub,
        o       => w_mul
    );

    w_inter <= ('0' & ff_d1 & "000000") + w_mul;

    process( clk )
    begin
        if( clk'event and clk = '1' )then
            if( clkena = '1' )then
                data <=w_inter( 12 downto 0 );  --  MSB は必ず 0
            end if;
        end if;
    end process;

end rtl;
