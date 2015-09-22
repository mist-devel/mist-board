library ieee; use ieee.std_logic_1164.all; 

package mem_if is
  procedure mem_if_c (
    
  clk: in std_logic;
  bs: in std_logic_vector(1 downto 0);
  ds: in std_logic_vector(1 downto 0);
  addr: in std_logic_vector(31 downto 0);
  di: in std_logic_vector(15 downto 0);
  do: out std_logic_vector(15 downto 0)
  );
    attribute foreign of mem_if_c :
      procedure is "VHPIDIRECT mem_if_c";
end mem_if;

package body mem_if is
  procedure mem_if_c (
    clk: in std_logic;
    bs: in std_logic_vector(1 downto 0);
    ds: in std_logic_vector(1 downto 0);
    addr: in std_logic_vector(31 downto 0);
    di: in std_logic_vector(15 downto 0);
    do: out std_logic_vector(15 downto 0)
  )     is
  begin
    assert false report "VHPI" severity failure;
  end mem_if_c;
end mem_if;
