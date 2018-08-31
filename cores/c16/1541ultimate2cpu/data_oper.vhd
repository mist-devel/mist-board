
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

library work;
use work.pkg_6502_decode.all;

-- this module puts the alu, shifter and bit/compare unit together

entity data_oper is
generic (
    support_bcd : boolean := true );
port (
    inst            : in  std_logic_vector(7 downto 0);
    
    n_in            : in  std_logic;
    v_in            : in  std_logic;
    z_in            : in  std_logic;
    c_in            : in  std_logic;
    d_in            : in  std_logic;
    i_in            : in  std_logic;
    
    data_in         : in  std_logic_vector(7 downto 0);
    a_reg           : in  std_logic_vector(7 downto 0);
    x_reg           : in  std_logic_vector(7 downto 0);
    y_reg           : in  std_logic_vector(7 downto 0);
    s_reg           : in  std_logic_vector(7 downto 0);
    
    alu_out         : out std_logic_vector(7 downto 0);
    mem_out         : out std_logic_vector(7 downto 0);
    impl_out        : out std_logic_vector(7 downto 0);
    
    set_a           : out std_logic;
    set_x           : out std_logic;
    set_y           : out std_logic;
    set_s           : out std_logic;

    n_out           : out std_logic;
    v_out           : out std_logic;
    z_out           : out std_logic;
    c_out           : out std_logic;
    d_out           : out std_logic;
    i_out           : out std_logic );
end data_oper;        

architecture gideon of data_oper is
    signal shift_sel : std_logic_vector(1 downto 0) := "00";
    signal shift_din : std_logic_vector(7 downto 0) := X"00";
    signal shift_dout: std_logic_vector(7 downto 0) := X"00";
    signal alu_data_a: std_logic_vector(7 downto 0) := X"00";
    signal row0_n    : std_logic;
    signal row0_v    : std_logic;
    signal row0_z    : std_logic;
    signal row0_c    : std_logic;

    signal shft_n    : std_logic;
    signal shft_z    : std_logic;
    signal shft_c    : std_logic;

    signal alu_n     : std_logic;
    signal alu_v     : std_logic;
    signal alu_z     : std_logic;
    signal alu_c     : std_logic;

    signal impl_n    : std_logic;
    signal impl_z    : std_logic;
    signal impl_c    : std_logic;
    signal impl_v    : std_logic;
    signal impl_i    : std_logic;
    signal impl_d    : std_logic;

    signal shift_en  : std_logic;
    signal alu_en    : std_logic;
    signal impl_en   : std_logic;
    signal impl_flags: boolean;
begin
    shift_sel <= shifter_in_select(inst);
    with shift_sel select shift_din <=
        data_in           when "01",
        a_reg             when "10",
        data_in and a_reg when "11",
        X"FF"             when others;

    shift_en <= '1' when is_shift(inst) else '0';
    alu_en   <= '1' when is_alu(inst) else '0';
    
    row0: entity work.bit_cpx_cpy 
    port map (
        operation  => inst(7 downto 5),
        enable     => '1',
        
        n_in       => n_in,
        v_in       => v_in,
        z_in       => z_in,
        c_in       => c_in,
        
        data_in    => data_in,
        a_reg      => a_reg,
        x_reg      => x_reg,
        y_reg      => y_reg,
        
        n_out      => row0_n,
        v_out      => row0_v,
        z_out      => row0_z,
        c_out      => row0_c );

    shft: entity work.shifter
    port map (
        operation  => inst(7 downto 5),
        enable     => shift_en,
        
        c_in       => c_in,
        n_in       => n_in,
        z_in       => z_in,
        
        data_in    => shift_din,
        
        c_out      => shft_c,
        n_out      => shft_n,
        z_out      => shft_z,
        
        data_out   => shift_dout );
        
    alu_data_a <= a_reg and x_reg when x_to_alu(inst) else a_reg;

    alu1: entity work.alu
    generic map (
        support_bcd => support_bcd )
    port map (
        operation   => inst(7 downto 5),
        enable      => alu_en,
    
        n_in        => shft_n,
        v_in        => v_in,
        z_in        => shft_z,
        c_in        => shft_c,
        d_in        => d_in,
        
        data_a      => alu_data_a,
        data_b      => shift_dout,
        
        n_out       => alu_n,
        v_out       => alu_v,
        z_out       => alu_z,
        c_out       => alu_c,
        
        data_out    => alu_out );
    
    mem_out <= shift_dout;    

    impl_en    <= '1' when is_implied(inst) else '0';
    impl_flags <= is_implied(inst) and (inst(4)='1' or inst(7)='1');
    
    impl: entity work.implied
    port map (
        inst      => inst,
        enable    => impl_en,
        
        c_in      => c_in,
        i_in      => i_in,
        n_in      => n_in,
        z_in      => z_in,
        d_in      => d_in,
        v_in      => v_in,
        
        reg_a     => a_reg,
        reg_x     => x_reg,
        reg_y     => y_reg,
        reg_s     => s_reg,
        
        i_out     => impl_i,
        d_out     => impl_d,
        c_out     => impl_c,
        n_out     => impl_n,
        z_out     => impl_z,
        v_out     => impl_v,
        
        set_a     => set_a,
        set_x     => set_x,
        set_y     => set_y,
        set_s     => set_s,
        
        data_out  => impl_out );
    
    n_out <= impl_n when impl_flags else row0_n when inst(1 downto 0)="00" else alu_n;
    v_out <= impl_v when impl_flags else row0_v when inst(1 downto 0)="00" else alu_v;
    z_out <= impl_z when impl_flags else row0_z when inst(1 downto 0)="00" else alu_z;
    c_out <= impl_c when impl_flags else row0_c when inst(1 downto 0)="00" else alu_c;
    i_out <= impl_i when impl_flags else i_in;
    d_out <= impl_d when impl_flags else d_in;
     
end gideon;
