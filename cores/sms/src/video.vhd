library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity video is
	Port (
		clk8:				in  std_logic;
		pal:				in  std_logic;
		x: 				out unsigned(8 downto 0);
		y:					out unsigned(7 downto 0);
		color:			in  std_logic_vector(5 downto 0);
		hsync:			out std_logic;
		vsync:			out std_logic;
		red:				out std_logic_vector(1 downto 0);
		green:			out std_logic_vector(1 downto 0);
		blue:				out std_logic_vector(1 downto 0));
end video;

architecture Behavioral of video is

	component ntsc_video is
	port (
		clk8:				in  std_logic;
		x: 				out unsigned(8 downto 0);
		y:					out unsigned(7 downto 0);
		color:			in  std_logic_vector(5 downto 0);
		hsync:			out std_logic;
		vsync:			out std_logic;
		red:				out std_logic_vector(1 downto 0);
		green:			out std_logic_vector(1 downto 0);
		blue:				out std_logic_vector(1 downto 0));
	end component;

	component pal_video is
	port (
		clk8:				in  std_logic;
		x: 				out unsigned(8 downto 0);
		y:					out unsigned(7 downto 0);
		color:			in  std_logic_vector(5 downto 0);
		hsync:			out std_logic;
		vsync:			out std_logic;
		red:				out std_logic_vector(1 downto 0);
		green:			out std_logic_vector(1 downto 0);
		blue:				out std_logic_vector(1 downto 0));
	end component;
	
	signal ntsc_x:			unsigned(8 downto 0);
	signal ntsc_y:			unsigned(7 downto 0);
	signal ntsc_hsync:	std_logic;
	signal ntsc_vsync:	std_logic;
	signal ntsc_red:		std_logic_vector(1 downto 0);
	signal ntsc_green:	std_logic_vector(1 downto 0);
	signal ntsc_blue:		std_logic_vector(1 downto 0);

	signal pal_x:			unsigned(8 downto 0);
	signal pal_y:			unsigned(7 downto 0);
	signal pal_hsync:		std_logic;
	signal pal_vsync:		std_logic;
	signal pal_red:		std_logic_vector(1 downto 0);
	signal pal_green:		std_logic_vector(1 downto 0);
	signal pal_blue:		std_logic_vector(1 downto 0);

begin

	x <= pal_x when pal='1' else ntsc_x;
	y <= pal_y when pal='1' else ntsc_y;
	
	hsync <= pal_hsync when pal='1' else ntsc_hsync;
	vsync <= pal_vsync when pal='1' else ntsc_vsync;
	red <= pal_red when pal='1' else ntsc_red;
	green <= pal_green when pal='1' else ntsc_green;
	blue <= pal_blue when pal='1' else ntsc_blue;
	
	ntsc_inst: ntsc_video
	port map (
		clk8			=> clk8,
		x	 			=> ntsc_x,
		y				=> ntsc_y,
		color			=> color,
		
		hsync			=> ntsc_hsync,
		vsync			=> ntsc_vsync,
		red			=> ntsc_red,
		green			=> ntsc_green,
		blue			=> ntsc_blue
	);

	pal_inst: pal_video
	port map (
		clk8			=> clk8,
		x	 			=> pal_x,
		y				=> pal_y,
		color			=> color,
		
		hsync			=> pal_hsync,
		vsync			=> pal_vsync,
		red			=> pal_red,
		green			=> pal_green,
		blue			=> pal_blue
	);
	
end Behavioral;

