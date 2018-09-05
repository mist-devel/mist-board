library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library work;
use work.pkg_6502_defs.all;

entity proc_core is
generic (
    vector_page  : std_logic_vector(15 downto 4) := X"FFF";
    support_bcd  : boolean := true );
port(
    clock        : in  std_logic;
    clock_en     : in  std_logic;
    reset        : in  std_logic;

    irq_n        : in  std_logic := '1';
    nmi_n        : in  std_logic := '1';
    so_n         : in  std_logic := '1';
    
    sync_out     : out std_logic;
    pc_out       : out std_logic_vector(15 downto 0);
    inst_out     : out std_logic_vector(7 downto 0);
    addr_out     : out std_logic_vector(16 downto 0);
    data_in      : in  std_logic_vector(7 downto 0);
    data_out     : out std_logic_vector(7 downto 0);
    read_write_n : out std_logic );

end proc_core;

architecture structural of proc_core is
    signal index_carry  : std_logic;
    signal pc_carry     : std_logic;
    signal branch_taken : boolean;
    signal i_reg        : std_logic_vector(7 downto 0);
    signal d_reg        : std_logic_vector(7 downto 0);
    signal a_reg        : std_logic_vector(7 downto 0);
    signal x_reg        : std_logic_vector(7 downto 0);
    signal y_reg        : std_logic_vector(7 downto 0);
    signal s_reg        : std_logic_vector(7 downto 0);
    signal p_reg        : std_logic_vector(7 downto 0);

    signal latch_dreg   : std_logic;
    signal reg_update   : std_logic;
    signal copy_d2p     : std_logic;
    signal sync         : std_logic;
    signal rwn          : std_logic;
    signal vect_bit     : std_logic;
    signal a_mux        : t_amux;
    signal pc_oper      : t_pc_oper;
    signal s_oper       : t_sp_oper;
    signal adl_oper     : t_adl_oper;
    signal adh_oper     : t_adh_oper;
    signal dout_mux     : t_dout_mux;

    signal alu_out      : std_logic_vector(7 downto 0);
    signal mem_out      : std_logic_vector(7 downto 0);
    signal impl_out     : std_logic_vector(7 downto 0);
    
    signal set_a        : std_logic;
    signal set_x        : std_logic;
    signal set_y        : std_logic;
    signal set_s        : std_logic;
    
    signal vect_addr    : std_logic_vector(3 downto 0);
    signal interrupt    : std_logic;

    signal new_flags    : std_logic_vector(7 downto 0);
    signal n_out        : std_logic;
    signal v_out        : std_logic;
    signal c_out        : std_logic;
    signal z_out        : std_logic;
    signal d_out        : std_logic;
    signal i_out        : std_logic;
    signal set_b        : std_logic;
    signal clear_b      : std_logic;
    signal a16          : std_logic;
begin
    inst_out <= i_reg; -- for debug only

    new_flags(7) <= n_out;
    new_flags(6) <= v_out;
    new_flags(5) <= '1';
    new_flags(4) <= p_reg(4);
    new_flags(3) <= d_out;
    new_flags(2) <= i_out;
    new_flags(1) <= z_out;
    new_flags(0) <= c_out;

    ctrl: entity work.proc_control
    port map (
        clock        => clock,
        clock_en     => clock_en,
        reset        => reset,
                                    
        interrupt    => interrupt,
        i_reg        => i_reg,
        index_carry  => index_carry,
        pc_carry     => pc_carry,
        branch_taken => branch_taken,

        sync         => sync,
        latch_dreg   => latch_dreg,
        reg_update   => reg_update,
        set_b        => set_b,
        copy_d2p     => copy_d2p,
        vect_bit     => vect_bit,
        a16          => a16,
        rwn          => rwn,
        a_mux        => a_mux,
        dout_mux     => dout_mux,
        pc_oper      => pc_oper,
        s_oper       => s_oper,
        adl_oper     => adl_oper,
        adh_oper     => adh_oper );

    oper: entity work.data_oper
    generic map (
        support_bcd => support_bcd )
    port map (
        inst       => i_reg,
                              
        n_in       => p_reg(7),
        v_in       => p_reg(6),
        z_in       => p_reg(1),
        c_in       => p_reg(0),
        d_in       => p_reg(3),
        i_in       => p_reg(2),

        data_in    => d_reg,
        a_reg      => a_reg,
        x_reg      => x_reg,
        y_reg      => y_reg,
        s_reg      => s_reg,
                              
        alu_out    => alu_out,
        mem_out    => mem_out,
        impl_out   => impl_out,
                              
        set_a      => set_a,
        set_x      => set_x,
        set_y      => set_y,
        set_s      => set_s,
                              
        n_out      => n_out,
        v_out      => v_out,
        z_out      => z_out,
        c_out      => c_out,
        d_out      => d_out,
        i_out      => i_out );

    regs: entity work.proc_registers
    generic map (
        vector_page  => vector_page )
    port map (
        clock        => clock,
        clock_en     => clock_en,
        reset        => reset,
                     
        -- package pins
        data_in      => data_in,
        data_out     => data_out,
        so_n         => so_n,
    
        -- data from "data_oper"
        alu_data     => alu_out,
        mem_data     => mem_out,
        new_flags    => new_flags,
        
        -- from implied handler
        set_a        => set_a,
        set_x        => set_x,
        set_y        => set_y,
        set_s        => set_s,
        set_data     => impl_out,
        
        -- from interrupt controller
        vect_addr    => vect_addr,
        interrupt    => interrupt,
        set_b        => set_b,
        clear_b      => clear_b,
        
        -- from processor state machine and decoder
        sync         => sync,
        latch_dreg   => latch_dreg,
        vect_bit     => vect_bit,
        reg_update   => reg_update,
        copy_d2p     => copy_d2p,
        a_mux        => a_mux,
        dout_mux     => dout_mux,
        pc_oper      => pc_oper,
        s_oper       => s_oper,
        adl_oper     => adl_oper,
        adh_oper     => adh_oper,
    
        -- outputs to processor state machine
        i_reg        => i_reg,
        index_carry  => index_carry,
        pc_carry     => pc_carry,
        branch_taken => branch_taken,
    
        -- register outputs
        addr_out     => addr_out(15 downto 0),
        
        d_reg        => d_reg,
        a_reg        => a_reg,
        x_reg        => x_reg,
        y_reg        => y_reg,
        s_reg        => s_reg,
        p_reg        => p_reg,
        pc_out       => pc_out );

    intr: entity work.proc_interrupt
    port map (
        clock       => clock,
        clock_en    => clock_en,
        reset       => reset,
        
        irq_n       => irq_n,
        nmi_n       => nmi_n,
        
        i_flag      => p_reg(2),
        clear_b     => clear_b,
        
        vect_bit    => vect_bit,
        interrupt   => interrupt,
        vect_addr   => vect_addr );
    
    read_write_n <= rwn;
    addr_out(16) <= a16;
    sync_out     <= sync;
end structural;
