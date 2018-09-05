library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library work;
use work.pkg_6502_defs.all;
use work.pkg_6502_decode.all;

entity proc_registers is
generic (
    vector_page  : std_logic_vector(15 downto 4) := X"FFF" );
port (
    clock        : in  std_logic;
    clock_en     : in  std_logic;
    reset        : in  std_logic;
                 
    -- package pins
    data_in      : in  std_logic_vector(7 downto 0);
    data_out     : out std_logic_vector(7 downto 0);

    so_n         : in  std_logic := '1';
    
    -- data from "data_oper"
    alu_data     : in  std_logic_vector(7 downto 0);
    mem_data     : in  std_logic_vector(7 downto 0);
    new_flags    : in  std_logic_vector(7 downto 0);
    
    -- from implied handler
    set_a        : in  std_logic;
    set_x        : in  std_logic;
    set_y        : in  std_logic;
    set_s        : in  std_logic;
    set_data     : in  std_logic_vector(7 downto 0);
    
    -- interrupt pins
    interrupt    : in  std_logic;
    vect_addr    : in  std_logic_vector(3 downto 0);
    set_b        : in  std_logic;
    clear_b      : in  std_logic;
    
    -- from processor state machine and decoder
    sync         : in  std_logic; -- latch ireg
    latch_dreg   : in  std_logic;
    vect_bit     : in  std_logic;
    reg_update   : in  std_logic;
    copy_d2p     : in  std_logic;
    a_mux        : in  t_amux;
    dout_mux     : in  t_dout_mux;
    pc_oper      : in  t_pc_oper;
    s_oper       : in  t_sp_oper;
    adl_oper     : in  t_adl_oper;
    adh_oper     : in  t_adh_oper;

    -- outputs to processor state machine
    i_reg        : out std_logic_vector(7 downto 0) := X"00";
    index_carry  : out std_logic;
    pc_carry     : out std_logic;
    branch_taken : out boolean;

    -- register outputs
    addr_out     : out std_logic_vector(15 downto 0) := X"FFFF";
    
    d_reg        : out std_logic_vector(7 downto 0) := X"00";
    a_reg        : out std_logic_vector(7 downto 0) := X"00";
    x_reg        : out std_logic_vector(7 downto 0) := X"00";
    y_reg        : out std_logic_vector(7 downto 0) := X"00";
    s_reg        : out std_logic_vector(7 downto 0) := X"00";
    p_reg        : out std_logic_vector(7 downto 0) := X"00";
    pc_out       : out std_logic_vector(15 downto 0) );
end proc_registers;

architecture gideon of proc_registers is
--    signal a_reg        : std_logic_vector(7 downto 0);
    signal dreg         : std_logic_vector(7 downto 0) := X"00";
    signal a_reg_i      : std_logic_vector(7 downto 0) := X"00";
    signal x_reg_i      : std_logic_vector(7 downto 0) := X"00";
    signal y_reg_i      : std_logic_vector(7 downto 0) := X"00";
    signal selected_idx : std_logic_vector(7 downto 0) := X"00";
    signal i_reg_i      : std_logic_vector(7 downto 0) := X"00";
    signal s_reg_i      : std_logic_vector(7 downto 0) := X"00";
    signal p_reg_i      : std_logic_vector(7 downto 0) := X"30";
    signal pcl, pch     : std_logic_vector(7 downto 0) := X"FF";
    signal adl, adh     : std_logic_vector(7 downto 0) := X"00";
    signal pc_carry_i   : std_logic;
    signal pc_carry_d   : std_logic;
    signal branch_flag  : std_logic;
    signal reg_out      : std_logic_vector(7 downto 0);
    signal vect         : std_logic_vector(3 downto 0) := "1111";
    signal dreg_zero    : std_logic;
    
    alias  C_flag : std_logic is p_reg_i(0);
    alias  Z_flag : std_logic is p_reg_i(1);
    alias  I_flag : std_logic is p_reg_i(2);
    alias  D_flag : std_logic is p_reg_i(3);
    alias  B_flag : std_logic is p_reg_i(4);
    alias  V_flag : std_logic is p_reg_i(6);
    alias  N_flag : std_logic is p_reg_i(7);

begin
    dreg_zero <= '1' when dreg=X"00" else '0';
    
    process(clock)
        variable pcl_t : std_logic_vector(8 downto 0);
        variable adl_t : std_logic_vector(8 downto 0);
    begin
        if rising_edge(clock) then
        	if clock_en='1' then
	            -- Data Register
	            if latch_dreg='1' then
	                dreg <= data_in;
	            end if;
	            
	            -- Flags Register
	            if copy_d2p = '1' then
	                p_reg_i <= dreg;
	            elsif reg_update='1' then
	                p_reg_i <= new_flags;
	            end if;
	
	            if vect_bit='0' then
	                I_flag <= '1';
	            end if;
	
	            if set_b='1' then
	                B_flag <= '1';
	            elsif clear_b='1' then
	                B_flag <= '0';
	            end if;
	
	            if so_n='0' then -- only 1 bit is affected, so no syncronization needed
	                V_flag <= '1';
	            end if;                
	
	            -- Instruction Register
	            if sync='1' then
	                i_reg_i <= data_in;
	
	                -- Fix for PLA only :(
	                if load_a(i_reg_i) then
	                    a_reg_i <= dreg;
	                    N_flag <= dreg(7);
	                    Z_flag <= dreg_zero;
	                end if;
	            end if;
	            
	            -- Logic for the Program Counter
	            pc_carry_i <= '0';
	            case pc_oper is
	            when increment =>
	                if pcl = X"FF" then
	                    pch <= pch + 1;
	                end if;
	                pcl <= pcl + 1;
	            
	            when copy =>
	                pcl <= dreg;
	                pch <= data_in;
	            
	            when from_alu =>
	                pcl_t := ('0' & pcl) + (dreg(7) & dreg); -- sign extended 1 bit
	                pcl <= pcl_t(7 downto 0);
	                pc_carry_i <= pcl_t(8);
	                pc_carry_d <= dreg(7);
	                            
	            when others => -- keep (and fix)
	                if pc_carry_i='1' then
	                    if pc_carry_d='1' then
	                        pch <= pch - 1;
	                    else
	                        pch <= pch + 1;
	                    end if;
	                end if;
	            end case;
	                            
	            -- Logic for the Address register
	            case adl_oper is
	            when increment =>
	                adl <= adl + 1;
	            
	            when add_idx =>
	                adl_t := ('0' & dreg) + ('0' & selected_idx);
	                adl <= adl_t(7 downto 0);
	                index_carry <= adl_t(8);
	                                
	            when load_bus =>
	                adl <= data_in;
	            
	            when copy_dreg =>
	                adl <= dreg;
	                
	            when others =>
	                null;
	            
	            end case;
	            
	            case adh_oper is
	            when increment =>
	                adh <= adh + 1;
	            
	            when clear =>
	                adh <= (others => '0');
	            
	            when load_bus =>
	                adh <= data_in;
	            
	            when others =>
	                null;
	            end case;
	            
	            -- Logic for ALU register
	            if reg_update='1' then
	                if set_a='1' then
	                    a_reg_i <= set_data;
	                elsif store_a_from_alu(i_reg_i) then
	                    a_reg_i <= alu_data;
	                end if;
	            end if;
	            
	            -- Logic for Index registers
	            if reg_update='1' then
	                if set_x='1' then
	                    x_reg_i <= set_data;
	                elsif load_x(i_reg_i) then
	                    x_reg_i <= alu_data; --dreg; -- alu is okay, too (they should be the same)
	                end if;
	            end if;
	            
	            if reg_update='1' then
	                if set_y='1' then
	                    y_reg_i <= set_data;
	                elsif load_y(i_reg_i) then
	                    y_reg_i <= dreg;
	                end if;
	            end if;
	
	            -- Logic for the Stack Pointer
	            if set_s='1' then
	                s_reg_i <= set_data;
	            else
	                case s_oper is
	                when increment =>
	                    s_reg_i <= s_reg_i + 1;
	                
	                when decrement =>
	                    s_reg_i <= s_reg_i - 1;
	                
	                when others =>
	                    null;
	                end case;
	            end if;
			end if;
            -- Reset
            if reset='1' then
                p_reg_i     <= X"34"; -- I=1
                index_carry <= '0';
            end if;
        end if;
    end process;

    with i_reg_i(7 downto 6) select branch_flag <=
        N_flag when "00",
        V_flag when "01",
        C_flag when "10",
        Z_flag when "11",
        '0' when others;
    
    branch_taken <= (branch_flag xor not i_reg_i(5))='1';

    with a_mux select addr_out <=
        vector_page & vect_addr when 0,
        adh & adl               when 1,
        X"01" & s_reg_i         when 2,
        pch & pcl               when 3;
        
    with i_reg_i(1 downto 0) select reg_out <=
        y_reg_i when "00",
        a_reg_i when "01",
        x_reg_i when "10",
        a_reg_i and x_reg_i when others;

    with dout_mux select data_out <=
        dreg when reg_d,
        a_reg_i  when reg_accu,
        reg_out  when reg_axy,
        p_reg_i or X"20" when reg_flags,
        pcl      when reg_pcl,
        pch      when reg_pch,
        mem_data when shift_res,
        X"FF"    when others;

    selected_idx <= y_reg_i when select_index_y(i_reg_i) else x_reg_i; 
    
    pc_carry <= pc_carry_i;
    s_reg    <= s_reg_i;
    p_reg    <= p_reg_i;
    i_reg    <= i_reg_i;
    a_reg    <= a_reg_i;
    x_reg    <= x_reg_i;
    y_reg    <= y_reg_i;
    d_reg    <= dreg;
    pc_out   <= pch & pcl;
end gideon;
