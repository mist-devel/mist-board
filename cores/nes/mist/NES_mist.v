// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

`timescale 1ns / 1ps


// Module reads bytes and writes to proper address in ram.
// Done is asserted when the whole game is loaded.
// This parses iNES headers too.
module GameLoader(input clk, input reset,
                  input [7:0] indata, input indata_clk, input invert_mirroring,
                  output reg [21:0] mem_addr, output [7:0] mem_data, output mem_write,
                  output [31:0] mapper_flags,
                  output reg done,
                  output reg error);
  reg [1:0] state = 0;
  reg [7:0] prgsize;
  reg [3:0] ctr;
  reg [7:0] ines[0:15]; // 16 bytes of iNES header
  reg [21:0] bytes_left;
  
  wire [7:0] prgrom = ines[4];	// Number of 16384 byte program ROM pages
  wire [7:0] chrrom = ines[5];	// Number of 8192 byte character ROM pages (0 indicates CHR RAM)
  wire has_chr_ram = (chrrom == 0);
  assign mem_data = indata;
  assign mem_write = (bytes_left != 0) && (state == 1 || state == 2) && indata_clk;
  
  wire [2:0] prg_size = prgrom <= 1  ? 0 :		// 16KB
                        prgrom <= 2  ? 1 : 		// 32KB
                        prgrom <= 4  ? 2 : 		// 64KB
                        prgrom <= 8  ? 3 : 		// 128KB
                        prgrom <= 16 ? 4 : 		// 256KB
                        prgrom <= 32 ? 5 : 		// 512KB
                        prgrom <= 64 ? 6 : 7;	// 1MB/2MB
                        
  wire [2:0] chr_size = chrrom <= 1  ? 0 : 		// 8KB
                        chrrom <= 2  ? 1 : 		// 16KB
                        chrrom <= 4  ? 2 : 		// 32KB
                        chrrom <= 8  ? 3 : 		// 64KB
                        chrrom <= 16 ? 4 : 		// 128KB
                        chrrom <= 32 ? 5 : 		// 256KB
                        chrrom <= 64 ? 6 : 7;	// 512KB/1MB
  
  // detect iNES2.0 compliant header
  wire is_nes20 = (ines[7][3:2] == 2'b10);
  // differentiate dirty iNES1.0 headers from proper iNES2.0 ones
  wire is_dirty = !is_nes20 && ((ines[8]  != 0) 
									  || (ines[9]  != 0)
									  || (ines[10] != 0)
									  || (ines[11] != 0)
									  || (ines[12] != 0)
									  || (ines[13] != 0)
									  || (ines[14] != 0)
									  || (ines[15] != 0));
  
  // Read the mapper number
  wire [7:0] mapper = {is_dirty ? 4'b0000 : ines[7][7:4], ines[6][7:4]};
  
  // ines[6][0] is mirroring
  // ines[6][3] is 4 screen mode
  assign mapper_flags = {15'b0, ines[6][3], has_chr_ram, ines[6][0] ^ invert_mirroring, chr_size, prg_size, mapper};
  
  always @(posedge clk) begin
    if (reset) begin
      state <= 0;
      done <= 0;
      ctr <= 0;
      mem_addr <= 0;  // Address for PRG
    end else begin
      case(state)
      // Read 16 bytes of ines header
      0: if (indata_clk) begin
			  error <= 0;
           ctr <= ctr + 1;
           ines[ctr] <= indata;
           bytes_left <= {prgrom, 14'b0};
           if (ctr == 4'b1111)
				 // Check the 'NES' header. Also, we don't support trainers.
             state <= (ines[0] == 8'h4E) && (ines[1] == 8'h45) && (ines[2] == 8'h53) && (ines[3] == 8'h1A) && !ines[6][2] ? 1 : 3;
         end
      1, 2: begin // Read the next |bytes_left| bytes into |mem_addr|
          if (bytes_left != 0) begin
            if (indata_clk) begin
              bytes_left <= bytes_left - 1;
              mem_addr <= mem_addr + 1;
            end
          end else if (state == 1) begin
            state <= 2;
            mem_addr <= 22'b10_0000_0000_0000_0000_0000; // Address for CHR
            bytes_left <= {1'b0, chrrom, 13'b0};
          end else if (state == 2) begin
            done <= 1;
          end
			end
		3: begin
            done <= 1;
				error <= 1;
         end
      endcase
    end
  end
endmodule


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
					  
wire [7:0] joyA;
wire [7:0] joyB;
wire [1:0] buttons;
wire [1:0] switches;
 
// the configuration string is returned to the io controller to allow
// it to control the menu on the OSD 
parameter CONF_STR = {
			"NES;NES;",
			"O1,HQ2X(VGA-Only),OFF,ON;",
			"O2,Scanlines,OFF,ON;",
			"O3,Invert mirroring,OFF,ON;",
			"O4,Hide overscan,OFF,ON;",
			"O5,Palette,FCEUX,Unsaturated-V6;",
			"T6,Reset;",
			"V,v0.8;"
};

parameter CONF_STR_LEN = 8+25+20+27+24+32+9+7;
wire [7:0] status;

wire arm_reset = status[0];
wire smoothing_osd = status[1];
wire scanlines_osd = status[2];
wire mirroring_osd = status[3];
wire overscan_osd = status[4];
wire palette2_osd = status[5];
wire reset_osd = status[6];

wire scandoubler_disable;
wire ypbpr;
wire ps2_kbd_clk, ps2_kbd_data;


user_io #(.STRLEN(CONF_STR_LEN)) user_io(
   .conf_str(CONF_STR),
   // the spi interface

   .SPI_SCK(SPI_SCK),
   .CONF_DATA0(CONF_DATA0),
   .SPI_DO(SPI_DO),   // tristate handling inside user_io
   .SPI_DI(SPI_DI),

   .switches(switches),
   .buttons(buttons),
   .scandoubler_disable(scandoubler_disable),
   .ypbpr(ypbpr),

   .joystick_0(joyA),
   .joystick_1(joyB),

   .status(status),

   .ps2_clk(ps2_clk),   // should be 10-16kHz for ps2 clock
   .ps2_kbd_clk(ps2_kbd_clk),
   .ps2_kbd_data(ps2_kbd_data)
);

wire [7:0] nes_joy_A = (reset_nes || osd_visible) ? 8'd0 : 
							  { joyB[0], joyB[1], joyB[2], joyB[3], joyB[7], joyB[6], joyB[5], joyB[4] } | kbd_joy0;
wire [7:0] nes_joy_B = (reset_nes || osd_visible) ? 8'd0 : 
							  { joyA[0], joyA[1], joyA[2], joyA[3], joyA[7], joyA[6], joyA[5], joyA[4] } | kbd_joy1;
 
  wire clock_locked;
  wire clk85;
  clk clock_21mhz(.inclk0(CLOCK_27[0]), .c0(clk85), .c1(SDRAM_CLK), .locked(clock_locked));

  // reset after download
  reg [7:0] download_reset_cnt;
  wire download_reset = download_reset_cnt != 0;
  always @(posedge CLOCK_27[0]) begin
	if(downloading)
		download_reset_cnt <= 8'd255;
	else if(download_reset_cnt != 0)
		download_reset_cnt <= download_reset_cnt - 8'd1;
 end

  // hold machine in reset until first download starts
  reg init_reset;
  always @(posedge CLOCK_27[0]) begin
	if(!clock_locked)
		init_reset <= 1'b1;
	else if(downloading)
		init_reset <= 1'b0;
  end
  
  reg [12:0] clkcnt;
  always @(posedge clk85)
	clkcnt <= clkcnt + 2'd1;
  wire clk = clkcnt[1];
  wire ps2_clk = clkcnt[12];
  
  wire [8:0] cycle;
  wire [8:0] scanline;
  wire [15:0] sample;
  wire [5:0] color;
  wire joypad_strobe;
  wire [1:0] joypad_clock;
  wire [21:0] memory_addr;
  wire memory_read_cpu, memory_read_ppu;
  wire memory_write;
  wire [7:0] memory_din_cpu, memory_din_ppu;
  wire [7:0] memory_dout;
  reg [7:0] joypad_bits, joypad_bits2;
  reg [7:0] powerpad_d3, powerpad_d4;
  reg [1:0] last_joypad_clock;
  wire [31:0] dbgadr;
  wire [1:0] dbgctr;

  reg [1:0] nes_ce;

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
  wire [7:0] loader_input;
  wire       loader_clk;
  wire [21:0] loader_addr;
  wire [7:0] loader_write_data;
  wire loader_reset = !download_reset; //loader_conf[0];
  wire loader_write;
  wire [31:0] loader_flags;
  reg [31:0] mapper_flags;
  wire loader_done, loader_fail;
  GameLoader loader(clk, loader_reset, loader_input, loader_clk, mirroring_osd,
                    loader_addr, loader_write_data, loader_write,
                    loader_flags, loader_done, loader_fail);

  always @(posedge clk)
	if (loader_done)
    mapper_flags <= loader_flags;
	 
	// LED displays loader status
	reg [12:0] led_blink;	// divide PS2 clock to around 1Hz
	always @(posedge ps2_clk) begin
		led_blink <= led_blink + 13'd1;
	end
 
	assign LED = downloading ? 0 : loader_fail ? led_blink[12] : 1;

  wire osd_visible;

  wire reset_nes = (init_reset || buttons[1] || arm_reset || reset_osd || download_reset || loader_fail);
  wire run_nes = (nes_ce == 3);	// keep running even when reset, so that the reset can actually do its job!

  // NES is clocked at every 4th cycle.
  always @(posedge clk)
    nes_ce <= nes_ce + 1;
    
  NES nes(clk, reset_nes, run_nes,
          mapper_flags,
          sample, color,
          joypad_strobe, joypad_clock, {powerpad_d4[0],powerpad_d3[0],joypad_bits2[0],joypad_bits[0]},
          5'b11111,  // enable all channels
          memory_addr,
          memory_read_cpu, memory_din_cpu,
          memory_read_ppu, memory_din_ppu,
          memory_write, memory_dout,
          cycle, scanline,
          dbgadr,
          dbgctr);

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

	if(nes_ce == 3) begin
		loader_write_mem <= loader_write_triggered;
		if(loader_write_triggered)
			loader_write_triggered <= 1'b0;
	end
end

sdram sdram (
	// interface to the MT48LC16M16 chip
	.sd_data     	( SDRAM_DQ                 ),
	.sd_addr     	( SDRAM_A                  ),
	.sd_dqm      	( {SDRAM_DQMH, SDRAM_DQML} ),
	.sd_cs       	( SDRAM_nCS                ),
	.sd_ba       	( SDRAM_BA                 ),
	.sd_we       	( SDRAM_nWE                ),
	.sd_ras      	( SDRAM_nRAS               ),
	.sd_cas      	( SDRAM_nCAS               ),

	// system interface
	.clk      		( clk85         				),
	.clkref      	( nes_ce[1]         			),
	.init         	( !clock_locked     			),

	// cpu/chipset interface
	.addr     		( downloading ? {3'b000, loader_addr_mem} : {3'b000, memory_addr} ),
	
	.we       		( memory_write || loader_write_mem	),
	.din       		( downloading ? loader_write_data_mem : memory_dout ),
	
	.oeA         	( memory_read_cpu ),
	.doutA       	( memory_din_cpu	),
	
	.oeB         	( memory_read_ppu ),
	.doutB       	( memory_din_ppu	)
);

wire downloading;

data_io data_io (
	.sck				( SPI_SCK 			),
	.ss				( SPI_SS2			),
	.sdi				( SPI_DI				),

	.downloading	( downloading		),
	.size				(						),

   // ram interface
   .clk     		( clk					),
	.wr    			( loader_clk		),
	.a					( 						),
	.d					( loader_input 	)
);

video video (
	.clk(clk),
	.sdi(SPI_DI),
	.sck(SPI_SCK),
	.ss(SPI_SS3),
		
	.color(color),
	.count_v(scanline),
	.count_h(cycle),
	.mode(scandoubler_disable),
	.ypbpr(ypbpr),
	.smoothing(!smoothing_osd),
	.scanlines(scanlines_osd),
	.overscan(overscan_osd),
	.palette(palette2_osd),
	
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	
	.osd_visible(osd_visible)
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

keyboard keyboard (
	.clk(clk),
	.reset(reset_nes),
	.ps2_kbd_clk(ps2_kbd_clk),
	.ps2_kbd_data(ps2_kbd_data),

	.joystick_0(kbd_joy0),
	.joystick_1(kbd_joy1),
	
	.powerpad(powerpad)
);
			
endmodule
