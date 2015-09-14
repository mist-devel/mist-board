//
// gb.v
//
// Gameboy for the MIST board https://github.com/mist-devel
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//

module gb (
   input reset,
	input clk,
	
	input fast_boot,
	input [7:0] joystick,
	
	// cartridge interface
	// can adress up to 1MB ROM
	output [15:0] cart_addr,
	output cart_rd,
	output cart_wr,
	input [7:0] cart_do,
	output [7:0] cart_di,

	// audio
	output [15:0] audio_l,
	output [15:0] audio_r,
	
	// lcd interface
	output lcd_clkena,
	output [1:0] lcd_data,
	output [1:0] lcd_mode,
	output lcd_on
);

// include cpu
wire [15:0] cpu_addr;
wire [7:0] cpu_do;

wire sel_timer = (cpu_addr[15:4] == 12'hff0) && (cpu_addr[3:2] == 2'b01);
wire sel_video_reg = cpu_addr[15:4] == 12'hff4;
wire sel_video_oam = cpu_addr[15:8] == 8'hfe;
wire sel_joy  = cpu_addr == 16'hff00;                // joystick controller
wire sel_rom  = !cpu_addr[15];                       // lower 32k are rom
wire sel_cram = cpu_addr[15:13] == 3'b101;           // 8k cart ram at $a000
wire sel_vram = cpu_addr[15:13] == 3'b100;           // 8k video ram at $8000
wire sel_ie   = cpu_addr == 16'hffff;                // interupt enable
wire sel_if   = cpu_addr == 16'hff0f;                // interupt flag
wire sel_iram = (cpu_addr[15:14] == 2'b11) && (cpu_addr[15:8] != 8'hff); // 8k internal ram at $c000
wire sel_zpram = (cpu_addr[15:7] == 9'b111111111) && // 127 bytes zero pageram at $ff80
					 (cpu_addr != 16'hffff);
wire sel_audio = (cpu_addr[15:8] == 8'hff) &&        // audio reg ff10 - ff3f
					((cpu_addr[7:5] == 3'b001) || (cpu_addr[7:4] == 4'b0001));

// the boot roms sees a special $42 flag in $ff50 if it's supposed to to a fast boot
wire sel_fast = fast_boot && cpu_addr == 16'hff50 && boot_rom_enabled;
					
// http://gameboy.mongenel.com/dmg/asmmemmap.html
wire [7:0] cpu_di = 
		irq_ack?irq_vec:
		sel_fast?8'h42:         // fast boot flag
		sel_joy?joy_do:         // joystick register
		sel_timer?timer_do:     // timer registers
		sel_video_reg?video_do: // video registers
		sel_video_oam?video_do: // video object attribute memory
		sel_audio?audio_do:     // audio registers
		sel_rom?rom_do:         // boot rom + cartridge rom
		sel_cram?rom_do:        // cartridge ram
		sel_vram?vram_do:       // vram
		sel_zpram?zpram_do:     // zero page ram
		sel_iram?iram_do:       // internal ram
		sel_ie?{3'b000, ie_r}:  // interrupt enable register
		sel_if?{3'b000, if_r}:  // interrupt flag register
		8'hff;

wire cpu_wr_n;
wire cpu_rd_n;
wire cpu_iorq_n;
wire cpu_m1_n;
wire cpu_mreq_n;
	
GBse cpu (
	.RESET_n    ( !reset        ),
	.CLK_n      ( clk           ),
	.CLKEN      ( 1'b1          ),
	.WAIT_n     ( 1'b1          ),
	.INT_n      ( irq_n         ),
	.NMI_n      ( 1'b1          ),
	.BUSRQ_n    ( 1'b1          ),
   .M1_n       ( cpu_m1_n      ),
   .MREQ_n     ( cpu_mreq_n    ),
   .IORQ_n     ( cpu_iorq_n    ),
   .RD_n       ( cpu_rd_n      ),
   .WR_n       ( cpu_wr_n      ),
   .RFSH_n     (               ),
   .HALT_n     (               ),
   .BUSAK_n    (               ),
   .A          ( cpu_addr      ),
   .DI         ( cpu_di        ),
   .DO         ( cpu_do        )
);

// --------------------------------------------------------------------
// ------------------------------ audio -------------------------------
// --------------------------------------------------------------------

wire audio_rd = !cpu_rd_n && sel_audio;
wire audio_wr = !cpu_wr_n && sel_audio;
wire [7:0] audio_do;

gbc_snd audio (
	.clk				( clk 				),
	.reset			( reset				),

	.s1_read  		( audio_rd  		),
	.s1_write 		( audio_wr  		),
	.s1_addr    	( cpu_addr[5:0]	),
   .s1_readdata 	( audio_do        ),
	.s1_writedata  ( cpu_do       	),

   .snd_left 		( audio_l  			),
	.snd_right  	( audio_r  			)
);

// --------------------------------------------------------------------
// ------------------------------ inputs ------------------------------
// --------------------------------------------------------------------

wire [3:0] joy_p4 = {  !joystick[2], !joystick[3], !joystick[1], !joystick[0] };
wire [3:0] joy_p5 = {  !joystick[7], !joystick[6], !joystick[5], !joystick[4] };
reg [1:0] p54;

always @(posedge clk) begin
	if(reset)
		p54 <= 2'b11;
	else if(sel_joy && !cpu_wr_n)
		p54 <= cpu_do[5:4];
end

wire [7:0] joy_do = { 2'b11, p54,
	((!p54[0])?joy_p4:4'hf) & ((!p54[1])?joy_p5:4'hf) };

// --------------------------------------------------------------------
// ---------------------------- interrupts ----------------------------
// --------------------------------------------------------------------

// interrupt flags are set when the event happens or when the cpu writes
// the register to 1. The "highest" one active is cleared when the cpu
// runs an interrupt ack cycle or when it writes a 0 to the register

wire irq_ack = !cpu_iorq_n && !cpu_m1_n;

// latch irq vector at the begin of the irq ack
reg [7:0] irq_vec;
always @(posedge irq_ack)
	irq_vec <= 
		if_r[0]?8'h40:   // vsync
		if_r[1]?8'h48:   // lcdc
		if_r[2]?8'h50:   // timer
		if_r[3]?8'h58:   // serial
		if_r[4]?8'h60:   // input
		8'h55;

wire vs = (lcd_mode == 2'b01);
reg vsD, vsD2;
reg [3:0] inputD, inputD2;

// irq is low when an enable irq is active
wire irq_n = !(ie_r & if_r);

reg [4:0] if_r;
reg [4:0] ie_r; // writing  $ffff sets the irq enable mask
always @(posedge clk) begin
	if(reset) begin
		ie_r <= 5'h00;
		if_r <= 5'h00;
	end

	// rising edge on vs
	vsD <= vs;
	vsD2 <= vsD;
	if(vsD && !vsD2) if_r[0] <= 1'b1;

	// video irq already is a 1 clock event
	if(video_irq) if_r[1] <= 1'b1;
	
	// timer_irq already is a 1 clock event
	if(timer_irq) if_r[2] <= 1'b1;

	// falling edge on any input line P10..P13
	inputD <= joy_p4 | joy_p5; 
	inputD2 <= inputD;
	if(~inputD & inputD2) if_r[4] <= 1'b1;

	// cpu acknowledges irq. this clears the active irq with hte 
	// highest priority
	if(irq_ack) begin
		if(if_r[0] && ie_r[0]) if_r[0] <= 1'b0;
		else if(if_r[1] && ie_r[1]) if_r[1] <= 1'b0;
		else if(if_r[2] && ie_r[2]) if_r[2] <= 1'b0;
		else if(if_r[3] && ie_r[3]) if_r[3] <= 1'b0;
		else if(if_r[4] && ie_r[4]) if_r[4] <= 1'b0;
	end

	// cpu writes interrupt enable register
	if(sel_ie && !cpu_wr_n)
		ie_r <= cpu_do[4:0];

	// cpu writes interrupt flag register
	if(sel_if && !cpu_wr_n)
		if_r <= cpu_do[4:0];
end
			
// --------------------------------------------------------------------
// ------------------------------ timer -------------------------------
// --------------------------------------------------------------------

wire timer_irq;
wire [7:0] timer_do;
timer timer (
	.reset	    ( reset         ),
	.clk		    ( clk           ),

	.irq         ( timer_irq     ),
		
	.cpu_sel     ( sel_timer     ),
	.cpu_addr    ( cpu_addr[1:0] ),
	.cpu_wr      ( !cpu_wr_n     ),
	.cpu_di      ( cpu_do        ),
	.cpu_do      ( timer_do      )
);
	
// --------------------------------------------------------------------
// ------------------------------ video -------------------------------
// --------------------------------------------------------------------

// cpu tries to read or write the lcd controller registers
wire video_irq;
wire [7:0] video_do;
wire [12:0] video_addr;
wire [15:0] dma_addr;
wire video_rd, dma_rd;
wire [7:0] dma_data = (dma_addr[15:14]==2'b11)?iram_do:cart_do;

video video (
	.reset	    ( reset         ),
	.clk		    ( clk           ),

	.irq         ( video_irq     ),

	.cpu_sel_reg ( sel_video_reg ),
	.cpu_sel_oam ( sel_video_oam ),
	.cpu_addr    ( cpu_addr[7:0] ),
	.cpu_wr      ( !cpu_wr_n     ),
	.cpu_di      ( cpu_do        ),
	.cpu_do      ( video_do      ),
	
	.lcd_on      ( lcd_on        ),
	.lcd_clkena  ( lcd_clkena    ),
	.lcd_data    ( lcd_data      ),
	.mode        ( lcd_mode      ),
	
	.vram_rd     ( video_rd      ),
	.vram_addr   ( video_addr    ),
	.vram_data   ( vram_do       ),
	
	.dma_rd      ( dma_rd        ),
	.dma_addr    ( dma_addr      ),
	.dma_data    ( dma_data      )
);

// total 8k vram from $8000 to $9fff
wire cpu_wr_vram = sel_vram && !cpu_wr_n;
wire [7:0] vram_do;
wire vram_wren = video_rd?1'b0:cpu_wr_vram;
wire [12:0] vram_addr = video_rd?video_addr:cpu_addr[12:0];

vram vram (
	.clock      ( clk           ),
	.address    ( vram_addr     ),
	.wren       ( vram_wren     ),
	.data       ( cpu_do        ),
	.q          ( vram_do       )
);

// --------------------------------------------------------------------
// -------------------------- zero page ram ---------------------------
// --------------------------------------------------------------------

// 127 bytes internal zero page ram from $ff80 to $fffe
wire cpu_wr_zpram = sel_zpram && !cpu_wr_n;
wire [7:0] zpram_do;
zpram zpram (
	.clock      ( clk            ),
	.address    ( cpu_addr[6:0]  ),
	.wren       ( cpu_wr_zpram   ),
	.data       ( cpu_do         ),
	.q          ( zpram_do       )
);

// --------------------------------------------------------------------
// ------------------------- 8k internal ram --------------------------
// --------------------------------------------------------------------

wire iram_wren = dma_rd?1'b0:cpu_wr_iram;
wire [12:0] iram_addr = dma_rd?dma_addr[12:0]:cpu_addr[12:0];

wire cpu_wr_iram = sel_iram && !cpu_wr_n;
wire [7:0] iram_do;
iram iram (
	.clock      ( clk            ),
	.address    ( iram_addr[12:0]),
	.wren       ( iram_wren      ),
	.data       ( cpu_do         ),
	.q          ( iram_do        )
);

// --------------------------------------------------------------------
// ------------------------ internal boot rom -------------------------
// --------------------------------------------------------------------

// writing 01 to $ff50 disables the internal rom
reg boot_rom_enabled;
always @(posedge clk) begin
	if(reset)
		boot_rom_enabled <= 1'b1;
	else if((cpu_addr == 16'hff50) && !cpu_wr_n && cpu_do[0])
		boot_rom_enabled <= 1'b0;
end
			
// combine boot rom data with cartridge data
wire [7:0] rom_do = ((cpu_addr[14:8] == 7'h00) && boot_rom_enabled)?boot_rom_do:cart_do;

assign cart_di = cpu_do;
assign cart_addr = dma_rd?dma_addr:cpu_addr;
assign cart_rd = dma_rd || ((sel_rom || sel_cram) && !cpu_rd_n);
assign cart_wr = (sel_rom || sel_cram) && !cpu_wr_n;

wire [7:0] boot_rom_do;
boot_rom boot_rom (
	.address    ( cpu_addr[7:0] ),
	.clock      ( clk           ),
	.q          ( boot_rom_do   )
);


endmodule
