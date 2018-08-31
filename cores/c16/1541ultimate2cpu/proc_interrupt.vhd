library ieee;
use ieee.std_logic_1164.all;

entity proc_interrupt is
port (
    clock       : in  std_logic;
    clock_en    : in  std_logic;
    reset       : in  std_logic;
    
    irq_n       : in  std_logic;
    nmi_n       : in  std_logic;
    
    i_flag      : in  std_logic;
    clear_b     : out std_logic;
    
    vect_bit    : in  std_logic;
    interrupt   : out std_logic;
    vect_addr   : out std_logic_vector(3 downto 0) );

end proc_interrupt;

architecture gideon of proc_interrupt is
    signal irq_c    : std_logic := '0';
    signal nmi_c    : std_logic := '0';
    signal nmi_d    : std_logic := '0';
    signal nmi_act  : std_logic := '0';
    signal vect_h   : std_logic_vector(1 downto 0) := "00";
    type state_t is (idle, do_irq, do_nmi);
    signal state : state_t;
begin
    vect_addr  <= '1' & vect_h & vect_bit;
    interrupt  <= irq_c or nmi_act;
    
    process(clock)
    begin
        if rising_edge(clock) then
            irq_c   <= not (irq_n or i_flag);
            nmi_c   <= not nmi_n;
            clear_b <= '0';
            
            if clock_en='1' then
                nmi_d <= nmi_c;
                if nmi_d = '0' and nmi_c = '1' then -- edge
                    nmi_act <= '1';
                end if;
                
                case state is
                when idle =>
                    vect_h  <= "11"; -- FE/FF
                    if nmi_act = '1' then
                        vect_h  <= "01"; -- FA/FB
                        state   <= do_nmi;
                    elsif irq_c = '1' then
                        state   <= do_irq;
                        clear_b <= '1';
                    end if;
                
                when do_irq =>
                    if vect_bit='0' or irq_c='0' then
                        state <= idle;
                    end if;

                when do_nmi =>
                    if vect_bit='0' then
                        nmi_act <= '0';
                        state <= idle;
                    end if;

                when others =>
                    state <= idle;
                
                end case;
            end if;

            if reset='1' then
                vect_h  <= "10"; -- FC/FD 1100
                state   <= do_nmi;
                nmi_act <= '0';
            end if;
        end if;
    end process;

end gideon;
