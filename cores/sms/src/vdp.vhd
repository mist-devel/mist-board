library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vdp is
	port (
		cpu_clk:			in  STD_LOGIC;
		vdp_clk:			in  STD_LOGIC;
		RD_n:				in  STD_LOGIC;
		WR_n:				in  STD_LOGIC;
		IRQ_n:			out STD_LOGIC;
		A:					in  STD_LOGIC_VECTOR (7 downto 0);
		D_in:				in  STD_LOGIC_VECTOR (7 downto 0);
		D_out:			out STD_LOGIC_VECTOR (7 downto 0);
		x:					unsigned(8 downto 0);
		y:					unsigned(7 downto 0);
		color:			out std_logic_vector (5 downto 0));
end vdp;

architecture Behavioral of vdp is
	
	component vdp_main is
	port (
		clk:					in  std_logic;			
		vram_A:				out std_logic_vector(13 downto 0);
		vram_D:				in  std_logic_vector(7 downto 0);
		cram_A:				out std_logic_vector(4 downto 0);
		cram_D:				in  std_logic_vector(5 downto 0);
			
		x:						unsigned(8 downto 0);
		y:						unsigned(7 downto 0);
			
		color:				out std_logic_vector (5 downto 0);
					
		display_on:			in  std_logic;
		mask_column0:		in  std_logic;
		overscan:			in  std_logic_vector (3 downto 0);

		bg_address:			in  std_logic_vector (2 downto 0);
		bg_scroll_x:		in  unsigned(7 downto 0);
		bg_scroll_y:		in  unsigned(7 downto 0);
		disable_hscroll:	in  std_logic;
			
		spr_address:		in  std_logic_vector (5 downto 0);
		spr_high_bit:		in  std_logic;
		spr_shift:			in  std_logic;	
		spr_tall:			in  std_logic);	
	end component;
	
	component vdp_cram is
	port (
		cpu_clk:			in  STD_LOGIC;
		cpu_WE:			in  std_logic;
		cpu_A:			in  std_logic_vector(4 downto 0);
		cpu_D:			in  std_logic_vector(5 downto 0);
		vdp_clk:			in  STD_LOGIC;
		vdp_A:			in  std_logic_vector(4 downto 0);
		vdp_D:			out std_logic_vector(5 downto 0));
	end component;
	
	-- helper bits
	signal data_write:		std_logic;
	signal address_ff:		std_logic := '0';
	signal to_cram:			boolean := false;
	
	-- vram and cram lines for the cpu interface
	signal xram_cpu_A:		std_logic_vector(13 downto 0);
	signal vram_cpu_WE:		std_logic;
	signal cram_cpu_WE:		std_logic;
	signal vram_cpu_D_out:	std_logic_vector(7 downto 0);	
	signal xram_cpu_A_incr:	std_logic := '0';
	
	-- vram and cram lines for the video interface
	signal vram_vdp_A:		std_logic_vector(13 downto 0);
	signal vram_vdp_D:		std_logic_vector(7 downto 0);	
	signal cram_vdp_A:		std_logic_vector(4 downto 0);
	signal cram_vdp_D:		std_logic_vector(5 downto 0);
			
	-- control bits
	signal display_on:		std_logic := '1';
	signal disable_hscroll:	std_logic := '0';
	signal mask_column0:		std_logic := '0';
	signal overscan:			std_logic_vector (3 downto 0) := "0000";	
	signal irq_frame_en:		std_logic := '0';
	signal irq_line_en:		std_logic := '0';
	signal irq_line_count:	unsigned(7 downto 0) := (others=>'1');	
	signal bg_address:		std_logic_vector (2 downto 0) := (others=>'0');
	signal bg_scroll_x:		unsigned(7 downto 0) := (others=>'0');
	signal bg_scroll_y:		unsigned(7 downto 0) := (others=>'0');
	signal spr_address:		std_logic_vector (5 downto 0) := (others=>'0');
	signal spr_shift:			std_logic := '0';
	signal spr_tall:			std_logic := '0';
	signal spr_high_bit:		std_logic := '0';

	-- various counters
	signal last_y0:			std_logic := '0';
	signal vbi_done:			std_logic := '0';
	signal virq_flag:			std_logic := '0';
	signal reset_virq_flag:	boolean := false;
	signal irq_counter:		unsigned(5 downto 0) := (others=>'0');
	signal hbl_counter:		unsigned(7 downto 0) := (others=>'0');
	signal vbl_irq:			std_logic;
	signal hbl_irq:			std_logic;
	
begin
		
	vdp_main_inst: vdp_main
	port map(
		clk				=> vdp_clk,
		vram_A			=> vram_vdp_A,
		vram_D			=> vram_vdp_D,
		cram_A			=> cram_vdp_A,
		cram_D			=> cram_vdp_D,
				
		x					=> x,
		y					=> y,
		color				=> color,
						
		display_on		=> display_on,
		mask_column0	=> mask_column0,
		overscan			=> overscan,

		bg_address		=> bg_address,
		bg_scroll_x		=> bg_scroll_x,
		bg_scroll_y		=> bg_scroll_y,
		disable_hscroll=>disable_hscroll,
				
		spr_address		=> spr_address,
		spr_high_bit	=> spr_high_bit,
		spr_shift		=> spr_shift,
		spr_tall			=> spr_tall);

    
  vdp_vram_inst : entity work.dpram
    generic map
    (
      init_file		=> "vram.mif",
      widthad_a		=> 14
    )
    port map
    (
      clock_a			=> cpu_clk,
      address_a		=> xram_cpu_A(13 downto 0),
      wren_a			=> vram_cpu_WE,
      data_a			=> D_in,
      q_a					=> vram_cpu_D_out,

      clock_b			=> not vdp_clk,
      address_b		=> vram_vdp_A,
      wren_b			=> '0',
      data_b			=> (others => '0'),
      q_b					=> vram_vdp_D
    );

	vdp_cram_inst: vdp_cram
	port map (
		cpu_clk			=> cpu_clk,
		cpu_WE			=> cram_cpu_WE,
		cpu_A 			=> xram_cpu_A(4 downto 0),
		cpu_D				=> D_in(5 downto 0),
		vdp_clk			=> vdp_clk,
		vdp_A				=> cram_vdp_A,
		vdp_D				=> cram_vdp_D);
		
		
	data_write <= not WR_n and not A(0);
	cram_cpu_WE <= data_write when to_cram else '0';
	vram_cpu_WE <= data_write when not to_cram else '0';

	process (cpu_clk)
	begin
		if rising_edge(cpu_clk) then
			if WR_n='0' then
				if A(0)='0' then
					xram_cpu_A_incr <= '1';
					
				else
					if address_ff='0' then
						xram_cpu_A(7 downto 0) <= D_in;
					else
						xram_cpu_A(13 downto 8) <= D_in(5 downto 0);
						to_cram <= D_in(7 downto 6)="11";
						case D_in is
						when "10000000" =>
							disable_hscroll<= xram_cpu_A(6);
							mask_column0	<= xram_cpu_A(5);
							irq_line_en		<= xram_cpu_A(4);
							spr_shift		<= xram_cpu_A(3);
						when "10000001" =>
							display_on		<= xram_cpu_A(6);
							irq_frame_en	<= xram_cpu_A(5);
							spr_tall			<= xram_cpu_A(1);
						when "10000010" =>
							bg_address		<= xram_cpu_A(3 downto 1);
						when "10000101" =>
							spr_address		<= xram_cpu_A(6 downto 1);
						when "10000110" =>
							spr_high_bit	<= xram_cpu_A(2);
						when "10000111" =>
							overscan			<= xram_cpu_A(3 downto 0);
						when "10001000" =>
							bg_scroll_x		<= unsigned(xram_cpu_A(7 downto 0));
						when "10001001" =>
							bg_scroll_y		<= unsigned(xram_cpu_A(7 downto 0));
						when "10001010" =>
							irq_line_count	<= unsigned(xram_cpu_A(7 downto 0));
						when others =>
						end case;
					end if;
					address_ff <= not address_ff;
				end if;
				
			elsif RD_n='0' then
				case A(7 downto 6)&A(0) is
				when "010" =>
					D_out <= std_logic_vector(y);
				when "011" =>
					D_out <= "11111111"; -- std_logic_vector(x(7 downto 0));  -- bad in VGA mode ...
				when "100" =>
					D_out <= vram_cpu_D_out;
					xram_cpu_A_incr <= '1';
				when "101" =>
					D_out(7) <= virq_flag;
					D_out(6 downto 0) <= (others=>'0');
					reset_virq_flag <= true;
				when others =>
				end case;
				
			elsif xram_cpu_A_incr='1' then
				xram_cpu_A <= std_logic_vector(unsigned(xram_cpu_A) + 1);
				xram_cpu_A_incr <= '0';
				
			else
				reset_virq_flag <= false;
			end if;
		end if;
	end process;
		
	
	process (vdp_clk)
	begin
		if rising_edge(vdp_clk) then
			-- we need to make sure we only send one vbi per image since the 
			-- y counter repeats within the image and the value 192 occurs twice
			if y=0 then
				vbi_done <= '0';
			end if;
			
			if x=256 and y=192 and not (last_y0=std_logic(y(0))) then
				if(vbi_done='0') then
					vbl_irq <= irq_frame_en;
					vbi_done <= '1';
				end if;
			else
				vbl_irq <= '0';
			end if;
		end if;
	end process;
	
	process (vdp_clk)
	begin
		if rising_edge(vdp_clk) then
			if x=256 and not (last_y0=std_logic(y(0))) then
				last_y0 <= std_logic(y(0));
				if y<192 then
					if hbl_counter=0 then
						hbl_irq <= irq_line_en;
						hbl_counter <= irq_line_count;
					else
						hbl_counter <= hbl_counter-1;
					end if;
				else
					hbl_counter <= irq_line_count;
				end if;
			else
				hbl_irq <= '0';
			end if;
		end if;
	end process;
	
	process (vdp_clk)
	begin
		if rising_edge(vdp_clk) then
			if vbl_irq='1' then
				virq_flag <= '1';
			elsif reset_virq_flag then
				virq_flag <= '0';
			end if;
		end if;
	end process;
	
	process (vdp_clk)
	begin
		if rising_edge(vdp_clk) then
			if vbl_irq='1' or hbl_irq='1' then
				irq_counter <= (others=>'1');
			elsif irq_counter>0 then
				irq_counter <= irq_counter-1;
			end if;
		end if;
	end process;
	IRQ_n <= '0' when irq_counter>0 else '1';

	
end Behavioral;
