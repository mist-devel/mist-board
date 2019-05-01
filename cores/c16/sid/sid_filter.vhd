-------------------------------------------------------------------------------
--
-- (C) COPYRIGHT 2010 Gideon's Logic Architectures'
--
-------------------------------------------------------------------------------
-- 
-- Author: Gideon Zweijtzer (gideon.zweijtzer (at) gmail.com)
--
-- Note that this file is copyrighted, and is not supposed to be used in other
-- projects without written permission from the author.
--
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.my_math_pkg.all;

entity sid_filter is
generic (
    g_divider   : natural := 221 );
port (
    clock       : in  std_logic;
    reset       : in  std_logic;
	 enable      : in  std_logic;
    
    filt_co     : in  unsigned(10 downto 0);
    filt_res    : in  unsigned(3 downto 0);

    valid_in    : in  std_logic := '0';
    error_out   : out std_logic;     
    input       : in  signed(17 downto 0);
    high_pass   : out signed(17 downto 0);
    band_pass   : out signed(17 downto 0);
    low_pass    : out signed(17 downto 0);

    valid_out   : out std_logic );
end sid_filter;

architecture dsvf of sid_filter is
    signal filter_q : signed(17 downto 0);
    signal filter_f : signed(17 downto 0);
    signal input_sc : signed(17 downto 0);
    signal filt_ram : std_logic_vector(15 downto 0);
    signal xa       : signed(17 downto 0);
    signal xb       : signed(17 downto 0);
    signal sum_b    : signed(17 downto 0);
    signal sub_a    : signed(17 downto 0);
    signal sub_b    : signed(17 downto 0);
    signal x_reg    : signed(17 downto 0) := (others => '0');
    signal bp_reg   : signed(17 downto 0);
    signal hp_reg   : signed(17 downto 0);
    signal lp_reg   : signed(17 downto 0);
    signal temp_reg : signed(17 downto 0);
    signal error    : std_logic := '0';
    signal divider  : integer range 0 to g_divider-1;

    signal instruction  : std_logic_vector(7 downto 0);
    type t_byte_array is array(natural range <>) of std_logic_vector(7 downto 0);
    constant c_program  : t_byte_array := (X"80", X"12", X"81", X"4C", X"82", X"20");
	
    type t_word_array is array(1023 downto 0) of signed(15 downto 0);
    constant coef : t_word_array := 
	 (
			 X"fff6", X"ffe5", X"ffd4", X"ffc3", X"ffb2", X"ffa0", X"ff8f", X"ff7e",
			 X"ff6d", X"ff5c", X"ff4a", X"ff39", X"ff28", X"ff17", X"ff06", X"fef4",
			 X"fee3", X"fed2", X"fec1", X"feb0", X"fe9e", X"fe8d", X"fe7c", X"fe6b",
			 X"fe5a", X"fe48", X"fe37", X"fe26", X"fe15", X"fe04", X"fdf2", X"fde1",
			 X"fdd0", X"fdbf", X"fdae", X"fd9c", X"fd8b", X"fd7a", X"fd69", X"fd58",
			 X"fd46", X"fd35", X"fd24", X"fd13", X"fd02", X"fcf0", X"fcdf", X"fcce",
			 X"fcbd", X"fcac", X"fc9a", X"fc89", X"fc78", X"fc67", X"fc56", X"fc44",
			 X"fc33", X"fc22", X"fc11", X"fc00", X"fbee", X"fbdd", X"fbcc", X"fbbb",
			 X"fb99", X"fb76", X"fb54", X"fb32", X"fb10", X"faee", X"facc", X"faaa",
			 X"fa88", X"fa65", X"fa43", X"fa21", X"f9ff", X"f9dd", X"f9bb", X"f999",
			 X"f976", X"f954", X"f932", X"f910", X"f8ee", X"f8cc", X"f8aa", X"f888",
			 X"f865", X"f843", X"f821", X"f7ff", X"f7dd", X"f7bb", X"f799", X"f776",
			 X"f754", X"f732", X"f710", X"f6ee", X"f6cc", X"f6aa", X"f688", X"f665",
			 X"f643", X"f621", X"f5ff", X"f5dd", X"f5bb", X"f599", X"f576", X"f554",
			 X"f532", X"f510", X"f4ee", X"f4cc", X"f4aa", X"f488", X"f465", X"f443",
			 X"f421", X"f3ff", X"f3dd", X"f3bb", X"f399", X"f376", X"f354", X"f332",
			 X"f2f4", X"f2b5", X"f276", X"f238", X"f1f9", X"f1bb", X"f17c", X"f13e",
			 X"f0ff", X"f0c0", X"f082", X"f043", X"f005", X"efc6", X"ef88", X"ef49",
			 X"ef0a", X"eecc", X"ee8d", X"ee4f", X"ee10", X"edd2", X"ed93", X"ed54",
			 X"ed16", X"ecd7", X"ec99", X"ec5a", X"ec1b", X"ebdd", X"eb9e", X"eb60",
			 X"eb21", X"eae3", X"eaa4", X"ea65", X"ea27", X"e9e8", X"e9aa", X"e96b",
			 X"e92d", X"e8ee", X"e8af", X"e871", X"e832", X"e7f4", X"e7b5", X"e777",
			 X"e738", X"e6f9", X"e6bb", X"e67c", X"e63e", X"e5ff", X"e5c0", X"e582",
			 X"e543", X"e505", X"e4c6", X"e488", X"e449", X"e40a", X"e3cc", X"e38d",
			 X"e338", X"e2e3", X"e28d", X"e238", X"e1e3", X"e18d", X"e138", X"e0e3",
			 X"e08d", X"e038", X"dfe3", X"df8d", X"df38", X"dee3", X"de8d", X"de38",
			 X"dde3", X"dd8d", X"dd38", X"dce3", X"dc8d", X"dc38", X"dbe3", X"db8d",
			 X"db38", X"dae3", X"da8d", X"da38", X"d9e3", X"d98d", X"d938", X"d8e3",
			 X"d88d", X"d838", X"d7e3", X"d78d", X"d738", X"d6e3", X"d68d", X"d638",
			 X"d5e3", X"d58d", X"d538", X"d4e3", X"d48d", X"d438", X"d3e3", X"d38d",
			 X"d338", X"d2e3", X"d28d", X"d238", X"d1e3", X"d18d", X"d138", X"d0e3",
			 X"d08d", X"d038", X"cfe3", X"cf8d", X"cf38", X"cee3", X"ce8d", X"ce38",
			 X"cdaa", X"cd1c", X"cc8d", X"cbff", X"cb71", X"cae3", X"ca54", X"c9c6",
			 X"c938", X"c8aa", X"c81c", X"c78d", X"c6ff", X"c671", X"c5e3", X"c554",
			 X"c4c6", X"c438", X"c3aa", X"c31c", X"c28d", X"c1ff", X"c171", X"c0e3",
			 X"c054", X"bfc6", X"bf38", X"beaa", X"be1c", X"bd8d", X"bcff", X"bc71",
			 X"bbe3", X"bb54", X"bac6", X"ba38", X"b9aa", X"b91c", X"b88d", X"b7ff",
			 X"b771", X"b6e3", X"b654", X"b5c6", X"b538", X"b4aa", X"b41c", X"b38d",
			 X"b2ff", X"b271", X"b1e3", X"b154", X"b0c6", X"b038", X"afaa", X"af1c",
			 X"ae8d", X"adff", X"ad71", X"ace3", X"ac54", X"abc6", X"ab38", X"aaaa",
			 X"aa1c", X"a98d", X"a8ff", X"a871", X"a7e3", X"a755", X"a6c6", X"a638",
			 X"a5aa", X"a51c", X"a48d", X"a3ff", X"a371", X"a2e3", X"a255", X"a1c6",
			 X"a138", X"a0aa", X"a01c", X"9f8d", X"9eff", X"9e71", X"9de3", X"9d55",
			 X"9cc6", X"9c38", X"9baa", X"9b1c", X"9a8d", X"99ff", X"9971", X"98e3",
			 X"9855", X"97c6", X"9738", X"96aa", X"961c", X"958d", X"94ff", X"9471",
			 X"93e3", X"9355", X"92c6", X"9238", X"91aa", X"911c", X"908d", X"8fff",
			 X"8f71", X"8ee3", X"8e55", X"8dc6", X"8d38", X"8caa", X"8c1c", X"8b8d",
			 X"8aff", X"8a71", X"89e3", X"8955", X"88c6", X"8838", X"87aa", X"871c",
			 X"8699", X"8616", X"8593", X"8510", X"848d", X"840b", X"8388", X"8305",
			 X"8282", X"81ff", X"817c", X"80fa", X"8077", X"7ff4", X"7f71", X"7eee",
			 X"7e6b", X"7de8", X"7d66", X"7ce3", X"7c60", X"7bdd", X"7b5a", X"7ad7",
			 X"7a55", X"79d2", X"794f", X"78cc", X"7849", X"77c6", X"7744", X"76c1",
			 X"763e", X"75bb", X"7538", X"74b5", X"7432", X"73b0", X"732d", X"72aa",
			 X"7227", X"71a4", X"7121", X"709f", X"701c", X"6f99", X"6f16", X"6e93",
			 X"6e10", X"6d8e", X"6d0b", X"6c88", X"6c05", X"6b82", X"6aff", X"6a7c",
			 X"69fa", X"6977", X"68f4", X"6871", X"67ee", X"676b", X"66e9", X"6666",
			 X"65dd", X"6555", X"64cc", X"6444", X"63bb", X"6333", X"62aa", X"6221",
			 X"6199", X"6110", X"6088", X"5fff", X"5f77", X"5eee", X"5e66", X"5ddd",
			 X"5d55", X"5ccc", X"5c44", X"5bbb", X"5b33", X"5aaa", X"5a21", X"5999",
			 X"5910", X"5888", X"57ff", X"5777", X"56ee", X"5666", X"55dd", X"5555",
			 X"54b5", X"5416", X"5377", X"52d8", X"5238", X"5199", X"50fa", X"505a",
			 X"4fbb", X"4f1c", X"4e7d", X"4ddd", X"4d3e", X"4c9f", X"4bff", X"4b60",
			 X"4ac8", X"4a31", X"4999", X"4901", X"486a", X"47d2", X"473a", X"46a2",
			 X"460b", X"4573", X"44db", X"4444", X"438e", X"42d8", X"4222", X"416b",
			 X"54b9", X"5381", X"5248", X"5110", X"4fff", X"4eee", X"4ddd", X"4ccc",
			 X"4c16", X"4b60", X"4aaa", X"49f4", X"493e", X"4888", X"47d2", X"471c",
			 X"467d", X"45dd", X"453e", X"449f", X"43ff", X"4360", X"42c1", X"4222",
			 X"4182", X"40e3", X"4044", X"3fa4", X"3f05", X"3e66", X"3dc6", X"3d27",
			 X"3caa", X"3c2d", X"3bb0", X"3b33", X"3ab5", X"3a38", X"39bb", X"393e",
			 X"38c1", X"3844", X"37c7", X"3749", X"36cc", X"364f", X"35d2", X"3555",
			 X"34d8", X"345a", X"33dd", X"3360", X"32e3", X"3266", X"31e9", X"316b",
			 X"30ee", X"3071", X"2ff4", X"2f77", X"2efa", X"2e7d", X"2dff", X"2d82",
			 X"2d1c", X"2cb5", X"2c4f", X"2be9", X"2b82", X"2b1c", X"2ab5", X"2a4f",
			 X"29e9", X"2982", X"291c", X"28b5", X"284f", X"27e9", X"2782", X"271c",
			 X"26b5", X"264f", X"25e9", X"2582", X"251c", X"24b5", X"244f", X"23e9",
			 X"2382", X"231c", X"22b5", X"224f", X"21e9", X"2182", X"211c", X"20b5",
			 X"2066", X"2016", X"1fc7", X"1f77", X"1f27", X"1ed8", X"1e88", X"1e38",
			 X"1de9", X"1d99", X"1d49", X"1cfa", X"1caa", X"1c5a", X"1c0b", X"1bbb",
			 X"1b6c", X"1b1c", X"1acc", X"1a7d", X"1a2d", X"19dd", X"198e", X"193e",
			 X"18ee", X"189f", X"184f", X"17ff", X"17b0", X"1760", X"1711", X"16c1",
			 X"1692", X"1664", X"1635", X"1606", X"15d8", X"15a9", X"157a", X"154c",
			 X"151d", X"14ee", X"14c0", X"1491", X"1462", X"1434", X"1405", X"13d7",
			 X"13a8", X"1379", X"134b", X"131c", X"12ed", X"12bf", X"1290", X"1261",
			 X"1233", X"1204", X"11d5", X"11a7", X"1178", X"1149", X"111b", X"10ec",
			 X"10bd", X"108f", X"1060", X"1032", X"1003", X"0fd4", X"0fa6", X"0f77",
			 X"0f48", X"0f1a", X"0eeb", X"0ebc", X"0e8e", X"0e5f", X"0e30", X"0e02",
			 X"0dd3", X"0da4", X"0d76", X"0d47", X"0d19", X"0cea", X"0cbb", X"0c8d",
			 X"0c5e", X"0c2f", X"0c01", X"0bd2", X"0ba3", X"0b75", X"0b46", X"0b17",
			 X"0b03", X"0aee", X"0ada", X"0ac5", X"0ab1", X"0a9c", X"0a88", X"0a74",
			 X"0a5f", X"0a4b", X"0a36", X"0a22", X"0a0d", X"09f9", X"09e4", X"09d0",
			 X"09bb", X"09a7", X"0992", X"097e", X"0969", X"0955", X"0940", X"092c",
			 X"0917", X"0903", X"08ee", X"08da", X"08c5", X"08b1", X"089c", X"0888",
			 X"0874", X"085f", X"084b", X"0836", X"0822", X"080d", X"07f9", X"07e4",
			 X"07d0", X"07bb", X"07a7", X"0792", X"077e", X"0769", X"0755", X"0740",
			 X"072c", X"0717", X"0703", X"06ee", X"06da", X"06c5", X"06b1", X"069d",
			 X"0688", X"0674", X"065f", X"064b", X"0636", X"0622", X"060d", X"05f9",
			 X"05f2", X"05eb", X"05e4", X"05dd", X"05d7", X"05d0", X"05c9", X"05c2",
			 X"05bb", X"05b4", X"05ae", X"05a7", X"05a0", X"0599", X"0592", X"058b",
			 X"0585", X"057e", X"0577", X"0570", X"0569", X"0562", X"055c", X"0555",
			 X"054e", X"0547", X"0540", X"053a", X"0533", X"052c", X"0525", X"051e",
			 X"0517", X"0511", X"050a", X"0503", X"04fc", X"04f5", X"04ee", X"04e8",
			 X"04e1", X"04da", X"04d3", X"04cc", X"04c5", X"04bf", X"04b8", X"04b1",
			 X"04aa", X"04a3", X"049d", X"0496", X"048f", X"0488", X"0481", X"047a",
			 X"0474", X"046d", X"0466", X"045f", X"0458", X"0451", X"044b", X"0444",
			 X"0441", X"043e", X"043b", X"0438", X"0436", X"0433", X"0430", X"042d",
			 X"042a", X"0427", X"0424", X"0422", X"041f", X"041c", X"0419", X"0416",
			 X"0413", X"0411", X"040e", X"040b", X"0408", X"0405", X"0402", X"03ff",
			 X"03fd", X"03fa", X"03f7", X"03f4", X"03f1", X"03ee", X"03ec", X"03e9",
			 X"03e6", X"03e3", X"03e0", X"03dd", X"03db", X"03d8", X"03d5", X"03d2",
			 X"03cf", X"03cc", X"03c9", X"03c7", X"03c4", X"03c1", X"03be", X"03bb",
			 X"03b8", X"03b6", X"03b3", X"03b0", X"03ad", X"03aa", X"03a7", X"03a4",
			 X"03a2", X"039f", X"039c", X"0399", X"0396", X"0393", X"0391", X"038e",
			 X"038d", X"038b", X"038a", X"0389", X"0388", X"0387", X"0386", X"0385",
			 X"0383", X"0382", X"0381", X"0380", X"037f", X"037e", X"037d", X"037c",
			 X"037a", X"0379", X"0378", X"0377", X"0376", X"0375", X"0374", X"0372",
			 X"0371", X"0370", X"036f", X"036e", X"036d", X"036c", X"036a", X"0369",
			 X"0368", X"0367", X"0366", X"0365", X"0364", X"0362", X"0361", X"0360",
			 X"035f", X"035e", X"035d", X"035c", X"035b", X"0359", X"0358", X"0357",
			 X"0356", X"0355", X"0354", X"0353", X"0351", X"0350", X"034f", X"034e",
			 X"034d", X"034c", X"034b", X"0349", X"0348", X"0347", X"0346", X"0345",
			 X"0344", X"0344", X"0343", X"0343", X"0342", X"0341", X"0341", X"0340",
			 X"0340", X"033f", X"033f", X"033e", X"033e", X"033d", X"033c", X"033c",
			 X"033b", X"033b", X"033a", X"033a", X"0339", X"0338", X"0338", X"0337",
			 X"0337", X"0336", X"0336", X"0335", X"0334", X"0334", X"0333", X"0333",
			 X"0332", X"0332", X"0331", X"0330", X"0330", X"032f", X"032f", X"032e",
			 X"032e", X"032d", X"032c", X"032c", X"032b", X"032b", X"032a", X"032a",
			 X"0329", X"0328", X"0328", X"0327", X"0327", X"0326", X"0326", X"0325",
			 X"0324", X"0324", X"0323", X"0323", X"0322", X"0322", X"0321", X"0320"
	 );

    alias  xa_select    : std_logic is instruction(0);
    alias  xb_select    : std_logic is instruction(1);
    alias  sub_a_sel    : std_logic is instruction(2);
    alias  sub_b_sel    : std_logic is instruction(3);
    alias  sum_to_lp    : std_logic is instruction(4);
    alias  sum_to_bp    : std_logic is instruction(5);
    alias  sub_to_hp    : std_logic is instruction(6);
    alias  mult_enable  : std_logic is instruction(7);

begin
    -- Derive the actual 'f' and 'q' parameters
    i_q_table: entity work.Q_table
    port map (
        Q_reg       => filt_res,
        filter_q    => filter_q ); -- 2.16 format

    process(clock)
    begin
        if rising_edge(clock) then
				if(enable = '1') then
					filter_f <= "00" & coef(to_integer(filt_co(10 downto 1)));
				else
					filter_f <= "001111111111111111";
				end if;
        end if;
    end process;

    --input_sc <= input;
    input_sc <= shift_right(input, 1);

    -- operations to execute the filter:
    -- bp_f      = f * bp_reg      
    -- q_contrib = q * bp_reg      
    -- lp        = bp_f + lp_reg   
    -- temp      = input - lp      
    -- hp        = temp - q_contrib
    -- hp_f      = f * hp          
    -- bp        = hp_f + bp_reg   
    -- bp_reg    = bp              
    -- lp_reg    = lp              

    -- x_reg     = f * bp_reg           -- 10000000 -- 80
    -- lp_reg    = x_reg + lp_reg       -- 00010010 -- 12
    -- q_contrib = q * bp_reg           -- 10000001 -- 81
    -- temp      = input - lp           -- 00000000 -- 00 (can be merged with previous!)
    -- hp_reg    = temp - q_contrib     -- 01001100 -- 4C
    -- x_reg     = f * hp_reg           -- 10000010 -- 82
    -- bp_reg    = x_reg + bp_reg       -- 00100000 -- 20

    
    -- now perform the arithmetic
    xa    <= filter_f when xa_select='0' else filter_q;
    xb    <= bp_reg   when xb_select='0' else hp_reg;
    sum_b <= bp_reg   when xb_select='0' else lp_reg;
    sub_a <= input_sc when sub_a_sel='0' else temp_reg;
    sub_b <= lp_reg   when sub_b_sel='0' else x_reg;
    
    process(clock)
        variable x_result   : signed(35 downto 0);
        variable sum_result : signed(17 downto 0);
        variable sub_result : signed(17 downto 0);
    begin
        if rising_edge(clock) then
            x_result := xa * xb;
            if mult_enable='1' then
                x_reg <= x_result(33 downto 16);
                if (x_result(35 downto 33) /= "000") and (x_result(35 downto 33) /= "111") then
                    error <= not error;
                end if;
            end if;

            sum_result := sum_limit(x_reg, sum_b);
            temp_reg   <= sum_result;
            if sum_to_lp='1' then
                lp_reg <= sum_result;
            end if;
            if sum_to_bp='1' then
                bp_reg <= sum_result;
            end if;
            
            sub_result := sub_limit(sub_a, sub_b);
            temp_reg   <= sub_result;
            if sub_to_hp='1' then
                hp_reg <= sub_result;
            end if;

            -- control part
            instruction <= (others => '0');
            if reset='1' then
                hp_reg <= (others => '0');            
                lp_reg <= (others => '0');            
                bp_reg <= (others => '0');            
                divider <= 0;
            elsif divider = g_divider-1 then
                divider <= 0;
            else
                divider <= divider + 1;
                if divider < c_program'length then
                    instruction <= c_program(divider);
                end if;
            end if;
            if divider = c_program'length then
                valid_out <= '1';
            else
                valid_out <= '0';
            end if;
        end if;
    end process;

    high_pass <= hp_reg;
    band_pass <= bp_reg;
    low_pass  <= lp_reg;
    error_out <= error;
end dsvf;
