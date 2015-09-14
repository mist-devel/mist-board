library IEEE;
use IEEE.std_logic_1164.all;
library work;
use work.T80_Pack.all;

entity Z80 is port
   (
     clk        	: in std_logic;
     clk_en				: in std_logic;
     reset        : in std_logic;

     addr         : out std_logic_vector(15 downto 0);
     datai        : in std_logic_vector(7 downto 0);
     datao        : out std_logic_vector(7 downto 0);

     m1           : out std_logic;
     mem_rd       : out std_logic;
     mem_wr       : out std_logic;
     io_rd        : out std_logic;
     io_wr        : out std_logic;

     wait_n       : in std_logic := '1';
     busrq_n      : in std_logic := '1';
     intreq       : in std_logic := '0';
     intvec       : in std_logic_vector(7 downto 0);
     intack       : out std_logic;
     nmi          : in std_logic := '0'
   );
end Z80;

architecture SYN of Z80 is

	component T80se is
		generic
		(
	  	Mode : integer := 0;    -- 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
	    T2Write : integer := 1  -- 0 => WR_n active in T3, /=0 => WR_n active in T2
	  );
	  port
		(
	  	RESET_n     : in std_logic;
	    CLK_n       : in std_logic;
			CLKEN				: in std_logic;
	    WAIT_n      : in std_logic;
	    INT_n       : in std_logic;
	    NMI_n       : in std_logic;
	    BUSRQ_n     : in std_logic;
	    M1_n        : out std_logic;
	    MREQ_n      : out std_logic;
	    IORQ_n      : out std_logic;
	    RD_n        : out std_logic;
	    WR_n        : out std_logic;
	    RFSH_n      : out std_logic;
	    HALT_n      : out std_logic;
	    BUSAK_n     : out std_logic;
	    A           : out std_logic_vector(15 downto 0);
	    DI          : in std_logic_vector(7 downto 0);
	    DO          : out std_logic_vector(7 downto 0)
	  );
	end component T80se;
	
	-- Signal Declarations
	
	signal reset_n      : std_logic;
	signal int_n        : std_logic;
	signal nmi_n        : std_logic;
	
	signal z80_m1       : std_logic;
	signal z80_memreq   : std_logic;
	signal z80_ioreq    : std_logic;
	signal z80_rd       : std_logic;
	signal z80_wr       : std_logic;
	signal z80_datai    : std_logic_vector(7 downto 0);
	
	-- derived signals (outputs we need to read)
	signal z80_memrd    : std_logic;
	signal z80_iord     : std_logic;
	signal fetch        : std_logic;
	
	begin

	  -- simple inversions
	  reset_n <= not reset;
	  int_n <= not intreq;
	  nmi_n <= not nmi;
	
	  -- direct-connect (outputs we need to read)
	  m1 <= z80_m1;
	  mem_rd <= z80_memrd;
	  io_rd <= z80_iord;
	
	  -- memory signals
	  z80_memrd <= z80_memreq nor z80_rd;
	  mem_wr <= z80_memreq nor z80_wr;
	
	  -- io signals
	  z80_iord <= z80_ioreq nor z80_rd;
	  io_wr <= z80_ioreq nor z80_wr;
	
	  -- other signals
	  fetch <= z80_m1 nor z80_memreq;
	  intack <= z80_m1 nor z80_ioreq;
	
	  -- data in mux
	  z80_datai <= intvec when ((z80_memrd or z80_iord) = '0') else
	               datai;
	
	  Z80_uP : T80se
	    generic map
	    (
	      Mode => 0      -- Z80
	    )
	    port map
	    (
	      RESET_n     => reset_n,
	      CLK_n       => clk,
				CLKEN				=> clk_en,
	      WAIT_n      => wait_n,
	      INT_n       => int_n,
	      NMI_n       => nmi_n,
	      BUSRQ_n     => busrq_n,
	      M1_n        => z80_m1,
	      MREQ_n      => z80_memreq,
	      IORQ_n      => z80_ioreq,
	      RD_n        => z80_rd,
	      WR_n        => z80_wr,
	      RFSH_n      => open,
	      HALT_n      => open,
	      BUSAK_n     => open,
	      A           => addr,
	      DI          => z80_datai,
	      DO          => datao
	    );

end architecture SYN;
