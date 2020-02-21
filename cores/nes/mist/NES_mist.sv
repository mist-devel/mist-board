// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

`timescale 1ns / 1ps

module NES_mist(  
	// clock input
  input [1:0]   CLOCK_27, // 27 MHz
  output LED,
  
  // VGA
  output         VGA_HS, // VGA H_SYNC
  output         VGA_VS, // VGA V_SYNC
  output [ 5:0]  VGA_R, // VGA Red[5:0]
  output [ 5:0]  VGA_G, // VGA Green[5:0]
  output [ 5:0]  VGA_B, // VGA Blue[5:0]
  
  // SDRAM                                                                                                                                                         
  inout [ 16-1:0]  SDRAM_DQ, // SDRAM Data bus 16 Bits                                                                                                        
  output [ 13-1:0] SDRAM_A, // SDRAM Address bus 13 Bits                                                                                                      
  output           SDRAM_DQML, // SDRAM Low-byte Data Mask                                                                                                    
  output           SDRAM_DQMH, // SDRAM High-byte Data Mask                                                                                                   
  output           SDRAM_nWE, // SDRAM Write Enable                                                                                                           
  output           SDRAM_nCAS, // SDRAM Column Address Strobe                                                                                                 
  output           SDRAM_nRAS, // SDRAM Row Address Strobe                                                                                                    
  output           SDRAM_nCS, // SDRAM Chip Select                                                                                                            
  output [ 2-1:0]  SDRAM_BA, // SDRAM Bank Address                                                                                                            
  output           SDRAM_CLK, // SDRAM Clock                                                                                                                  
  output           SDRAM_CKE, // SDRAM Clock Enable                                                                                                             

  // audio
  output           AUDIO_L,
  output           AUDIO_R,
 
  // SPI
  inout          SPI_DO,
  input          SPI_DI,
  input          SPI_SCK,
  input          SPI_SS2,    // data_io
  input          SPI_SS3,    // OSD
  input          SPI_SS4,    // unused in this core
  input          CONF_DATA0, // SPI_SS for user_io

   // UART
	input 		  UART_RX,
	input 		  UART_TX
);

// the configuration string is returned to the io controller to allow
// it to control the menu on the OSD 
parameter CONF_STR = {
			"NES;NESFDSNSF;",
			"F,BIN,Load FDS BIOS;",
			"O12,System Type,NTSC,PAL,Dendy;",
			"O34,Scanlines,OFF,25%,50%,75%;",
			"O5,Joystick swap,OFF,ON;",
			"O6,Invert mirroring,OFF,ON;",
			"O7,Hide overscan,OFF,ON;",
			"O8,Palette,FCEUX,Unsaturated-V6;",
			"O9B,Disk side,Auto,A,B,C,D;",
			"T0,Reset;",
			"V,v2.0-test1;"
};

wire [31:0] status;

wire arm_reset = status[0];
wire [1:0] system_type = status[2:1];
wire pal_video = |system_type;
wire [1:0] scanlines = status[4:3];
wire joy_swap = status[5];
wire mirroring_osd = status[6];
wire overscan_osd = status[7];
wire palette2_osd = status[8];
wire [2:0] diskside_osd = status[11:9];

wire scandoubler_disable;
wire ypbpr;
wire no_csync;
wire ps2_kbd_clk, ps2_kbd_data;

wire [7:0] core_joy_A;
wire [7:0] core_joy_B;
wire [1:0] buttons;
wire [1:0] switches;

user_io #(.STRLEN($size(CONF_STR)>>3)) user_io(
   .clk_sys(clk),
   .conf_str(CONF_STR),
   // the spi interface

   .SPI_CLK(SPI_SCK),
   .SPI_SS_IO(CONF_DATA0),
   .SPI_MISO(SPI_DO),   // tristate handling inside user_io
   .SPI_MOSI(SPI_DI),

   .switches(switches),
   .buttons(buttons),
   .scandoubler_disable(scandoubler_disable),
   .ypbpr(ypbpr),
   .no_csync(no_csync),

   .joystick_0(core_joy_A),
   .joystick_1(core_joy_B),

   .status(status),

   .ps2_kbd_clk(ps2_kbd_clk),
   .ps2_kbd_data(ps2_kbd_data)
);

wire [7:0] joyA = joy_swap ? core_joy_B : core_joy_A;
wire [7:0] joyB = joy_swap ? core_joy_A : core_joy_B;

wire [7:0] nes_joy_A = { joyA[0], joyA[1], joyA[2], joyA[3], joyA[7], joyA[6], joyA[5], joyA[4] } | kbd_joy0;
wire [7:0] nes_joy_B = { joyB[0], joyB[1], joyB[2], joyB[3], joyB[7], joyB[6], joyB[5], joyB[4] } | kbd_joy1;
 
  wire clock_locked;
  wire clk85;
  wire clk;
  clk clock_21mhz(.inclk0(CLOCK_27[0]), .c0(clk85), .c1(clk), .locked(clock_locked));
  assign SDRAM_CLK = clk85;

  // reset after download
  reg [7:0] download_reset_cnt;
  wire download_reset = download_reset_cnt != 0;
  always @(posedge clk) begin
	if(downloading)
		download_reset_cnt <= 8'd255;
	else if(!loader_busy && download_reset_cnt != 0)
		download_reset_cnt <= download_reset_cnt - 8'd1;
 end

  // hold machine in reset until first download starts
  reg init_reset = 1;
  always @(posedge clk) begin
	if(downloading)	init_reset <= 1'b0;
  end
  
  wire [8:0] cycle;
  wire [8:0] scanline;
  wire [15:0] sample;
  wire [5:0] color;
  wire joypad_strobe;
  wire [1:0] joypad_clock;
  wire [21:0] memory_addr_cpu, memory_addr_ppu;
  wire memory_read_cpu, memory_read_ppu;
  wire memory_write_cpu, memory_write_ppu;
  wire [7:0] memory_din_cpu, memory_din_ppu;
  wire [7:0] memory_dout_cpu, memory_dout_ppu;
  reg [7:0] joypad_bits, joypad_bits2;
  reg [7:0] powerpad_d3, powerpad_d4;
  reg [1:0] last_joypad_clock;
  wire [31:0] dbgadr;
  wire [1:0] dbgctr;

  wire [1:0] nes_ce;

	always @(posedge clk) begin
		if (reset_nes) begin
			joypad_bits <= 8'd0;
			joypad_bits2 <= 8'd0;
			powerpad_d3 <= 8'd0;
			powerpad_d4 <= 8'd0;
			last_joypad_clock <= 2'b00;
		end else begin
			if (joypad_strobe) begin
				joypad_bits <= nes_joy_A;
				joypad_bits2 <= nes_joy_B;
				powerpad_d4 <= {4'b0000, powerpad[7], powerpad[11], powerpad[2], powerpad[3]};
				powerpad_d3 <= {powerpad[6], powerpad[10], powerpad[9], powerpad[5], powerpad[8], powerpad[4], powerpad[0], powerpad[1]};
			end
			if (!joypad_clock[0] && last_joypad_clock[0]) begin
				joypad_bits <= {1'b0, joypad_bits[7:1]};
			end	
			if (!joypad_clock[1] && last_joypad_clock[1]) begin
				joypad_bits2 <= {1'b0, joypad_bits2[7:1]};
				powerpad_d4 <= {1'b0, powerpad_d4[7:1]};
				powerpad_d3 <= {1'b0, powerpad_d3[7:1]};
			end	
			last_joypad_clock <= joypad_clock;
		end
  end
  
  // Loader
  wire [7:0] loader_input =  (loader_busy && !downloading) ? nsf_data : ioctl_dout;
  wire       loader_clk;
  wire [21:0] loader_addr;
  wire [7:0] loader_write_data;
  wire loader_reset = !download_reset; //loader_conf[0];
  wire loader_write;
  wire [31:0] loader_flags;
  reg [31:0] mapper_flags;
  wire loader_done, loader_fail;
	wire loader_busy;
	wire type_bios = (menu_index == 2);
	wire is_bios = 0;//type_bios;
	wire type_nes = (menu_index == 0) || (menu_index == {2'd0, 6'h1});
	wire type_fds = (menu_index == {2'd1, 6'h1});
	wire type_nsf = (menu_index == {2'd2, 6'h1});

GameLoader loader
(
	.clk              ( clk               ),
	.reset            ( loader_reset      ),
	.downloading      ( downloading       ),
	.filetype         ( {4'b0000, type_nsf, type_fds, type_nes, type_bios} ),
	.is_bios          ( is_bios           ),
	.indata           ( loader_input      ),
	.indata_clk       ( loader_clk        ),
	.invert_mirroring ( mirroring_osd     ),
	.mem_addr         ( loader_addr       ),
	.mem_data         ( loader_write_data ),
	.mem_write        ( loader_write      ),
	.bios_download    (                   ),
	.mapper_flags     ( loader_flags      ),
	.busy             ( loader_busy       ),
	.done             ( loader_done       ),
	.error            ( loader_fail       ),
	.rom_loaded       (                   )
);

  always @(posedge clk)
	if (loader_done)
    mapper_flags <= loader_flags;
	 
	// LED displays loader status
	reg [23:0] led_blink;	// divide 21MHz clock to around 1Hz
	always @(posedge clk) begin
		led_blink <= led_blink + 13'd1;
	end

// Loopy's NSF player ROM
reg [7:0] nsf_player [4096];
reg [7:0] nsf_data;
initial begin
  $readmemh("nsf.hex", nsf_player);
end
always @(posedge clk) nsf_data <= nsf_player[loader_addr[11:0]];

assign LED = downloading ? 1'b0 : loader_fail ? led_blink[23] : 1'b1;

wire reset_nes = (init_reset || buttons[1] || arm_reset || download_reset || loader_fail);

wire ext_audio = 1;
wire int_audio = 1;

wire [1:0] diskside_req;
wire [1:0] diskside = (diskside_osd == 0) ? diskside_req : (diskside_osd - 1'd1);

NES nes(
	.clk(clk),
	.reset_nes(reset_nes),
	.sys_type(system_type),
	.nes_div(nes_ce),
	.mapper_flags(mapper_flags),
	.sample(sample),
	.color(color),
	.joypad_strobe(joypad_strobe),
	.joypad_clock(joypad_clock),
	.joypad_data({powerpad_d4[0],powerpad_d3[0],joypad_bits2[0],joypad_bits[0]}),
	.mic(),
	.fds_busy(),
	.fds_eject(fds_eject),
	.diskside_req(diskside_req),
	.diskside(diskside),
	.audio_channels(5'b11111),  // enable all channels
	.cpumem_addr(memory_addr_cpu),
	.cpumem_read(memory_read_cpu),
	.cpumem_din(memory_din_cpu),
	.cpumem_write(memory_write_cpu),
	.cpumem_dout(memory_dout_cpu),
	.ppumem_addr(memory_addr_ppu),
	.ppumem_read(memory_read_ppu),
	.ppumem_write(memory_write_ppu),
	.ppumem_din(memory_din_ppu),
	.ppumem_dout(memory_dout_ppu),
	.cycle(cycle),
	.scanline(scanline),
	.int_audio(int_audio),
	.ext_audio(ext_audio)
);

assign SDRAM_CKE         = 1'b1;

// loader_write -> clock when data available
reg loader_write_mem;
reg [7:0] loader_write_data_mem;
reg [21:0] loader_addr_mem;

reg loader_write_triggered;

always @(posedge clk) begin
	if(loader_write) begin
		loader_write_triggered <= 1'b1;
		loader_addr_mem <= loader_addr;
		loader_write_data_mem <= loader_write_data;
	end

	// signal write in the PPU memory phase
	if(nes_ce == 3) begin
		loader_write_mem <= loader_write_triggered;
		if(loader_write_triggered)
			loader_write_triggered <= 1'b0;
	end
end

sdram sdram (
	// interface to the MT48LC16M16 chip
	.sd_data        ( SDRAM_DQ                 ),
	.sd_addr        ( SDRAM_A                  ),
	.sd_dqm         ( {SDRAM_DQMH, SDRAM_DQML} ),
	.sd_cs          ( SDRAM_nCS                ),
	.sd_ba          ( SDRAM_BA                 ),
	.sd_we          ( SDRAM_nWE                ),
	.sd_ras         ( SDRAM_nRAS               ),
	.sd_cas         ( SDRAM_nCAS               ),

	// system interface
	.clk            ( clk85                    ),
	.clkref         ( nes_ce[1]                ),
	.init           ( !clock_locked            ),

	// cpu/chipset interface
	.addrA     	    ( (downloading | loader_busy) ? {3'b000, loader_addr_mem} : {3'b000, memory_addr_cpu} ),
	.addrB          ( {3'b000, memory_addr_ppu} ),
	
	.weA            ( loader_write_mem || memory_write_cpu ),
	.weB            ( memory_write_ppu ),

	.dinA           ( (downloading | loader_busy) ? loader_write_data_mem : memory_dout_cpu ),
	.dinB           ( memory_dout_ppu ),

	.oeA            ( ~(downloading | loader_busy) & memory_read_cpu ),
	.doutA          ( memory_din_cpu  ),

	.oeB            ( memory_read_ppu ),
	.doutB          ( memory_din_ppu  )
);

wire downloading;
wire [7:0] menu_index;
wire [7:0] ioctl_dout;

data_io data_io (
	.clk_sys        ( clk          ),

	.SPI_SCK        ( SPI_SCK      ),
	.SPI_SS2        ( SPI_SS2      ),
	.SPI_DI         ( SPI_DI       ),

	.ioctl_download ( downloading  ),
	.ioctl_index    ( menu_index   ),

   // ram interface
	.ioctl_wr       ( loader_clk   ),
	.ioctl_dout     ( ioctl_dout )
);

wire nes_hs, nes_vs;
wire [4:0] nes_r;
wire [4:0] nes_g;
wire [4:0] nes_b;

video video (
	.clk(clk),
	.color(color),
	.count_v(scanline),
	.count_h(cycle),
	.pal_video(pal_video),
	.overscan(overscan_osd),
	.palette(palette2_osd),

	.sync_h(nes_hs),
	.sync_v(nes_vs),
	.r(nes_r),
	.g(nes_g),
	.b(nes_b)
);

mist_video #(.COLOR_DEPTH(5), .OSD_COLOR(3'd5), .SD_HCNT_WIDTH(10)) mist_video (
	.clk_sys     ( clk        ),

	// OSD SPI interface
	.SPI_SCK     ( SPI_SCK    ),
	.SPI_SS3     ( SPI_SS3    ),
	.SPI_DI      ( SPI_DI     ),

	// scanlines (00-none 01-25% 10-50% 11-75%)
	.scanlines   ( scanlines  ),

	// non-scandoubled pixel clock divider 0 - clk_sys/4, 1 - clk_sys/2
	.ce_divider  ( 1'b0       ),

	// 0 = HVSync 31KHz, 1 = CSync 15KHz
	.scandoubler_disable ( scandoubler_disable ),
	// disable csync without scandoubler
	.no_csync    ( no_csync   ),
	// YPbPr always uses composite sync
	.ypbpr       ( ypbpr      ),
	// Rotate OSD [0] - rotate [1] - left or right
	.rotate      ( 2'b00      ),
	// composite-like blending
	.blend       ( 1'b0       ),

	// video in
	.R           ( nes_r      ),
	.G           ( nes_g      ),
	.B           ( nes_b      ),

	.HSync       ( ~nes_hs    ),
	.VSync       ( ~nes_vs    ),

	// MiST video output signals
	.VGA_R       ( VGA_R      ),
	.VGA_G       ( VGA_G      ),
	.VGA_B       ( VGA_B      ),
	.VGA_VS      ( VGA_VS     ),
	.VGA_HS      ( VGA_HS     )
);

assign AUDIO_R = audio;
assign AUDIO_L = audio;
wire audio;
sigma_delta_dac sigma_delta_dac (
	.DACout(audio),
	.DACin(sample[15:8]),
	.CLK(clk),
	.RESET(reset_nes)
);

wire [7:0] kbd_joy0;
wire [7:0] kbd_joy1;
wire [11:0] powerpad;
wire fds_eject;

keyboard keyboard (
	.clk(clk),
	.reset(reset_nes),
	.ps2_kbd_clk(ps2_kbd_clk),
	.ps2_kbd_data(ps2_kbd_data),

	.joystick_0(kbd_joy0),
	.joystick_1(kbd_joy1),
	
	.powerpad(powerpad),
	.fds_eject(fds_eject)
);
			
endmodule
