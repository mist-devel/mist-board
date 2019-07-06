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
   input clk2x,

	input fast_boot,
	input [7:0] joystick,
	input isGBC,
	input isGBC_game,

	// cartridge interface
	// can adress up to 1MB ROM
	output [15:0] cart_addr,
	output cart_rd,
	output cart_wr,
	input [7:0] cart_do,
	output [7:0] cart_di,
	
	//gbc bios interface
	output [11:0] gbc_bios_addr,
	input [7:0] gbc_bios_do,
	
	// audio
	output [15:0] audio_l,
	output [15:0] audio_r,
	
	// lcd interface
	output lcd_clkena,
	output [14:0] lcd_data,
	output [1:0] lcd_mode,
	output lcd_on,
	
	output speed   //GBC
);

// include cpu
wire [15:0] cpu_addr;
wire [7:0] cpu_do;

wire sel_timer = (cpu_addr[15:4] == 12'hff0) && (cpu_addr[3:2] == 2'b01);
wire sel_video_reg = (cpu_addr[15:4] == 12'hff4) || (isGBC && (cpu_addr[15:2] == 14'h3fda));    //video and oam dma (+ ff68-ff6B when gbc)
wire sel_video_oam = cpu_addr[15:8] == 8'hfe;
wire sel_joy  = cpu_addr == 16'hff00;                // joystick controller
wire sel_sb  = cpu_addr == 16'hff01;  			        // serial SB - Serial transfer data
wire sel_sc  = cpu_addr == 16'hff02;  			        // SC - Serial Transfer Control (R/W)
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
					
//DMA can select from $0000 to $F100					
wire dma_sel_rom = !dma_addr[15];                       // lower 32k are rom
wire dma_sel_cram = dma_addr[15:13] == 3'b101;           // 8k cart ram at $a000
wire dma_sel_vram = dma_addr[15:13] == 3'b100;           // 8k video ram at $8000
wire dma_sel_iram = (dma_addr[15:14] == 2'b11) && (dma_addr[15:8] != 8'hff); // 8k internal ram at $c000

//CGB
wire sel_vram_bank = (cpu_addr==16'hff4f);
wire sel_iram_bank = (cpu_addr==16'hff70);				
wire sel_hdma = (cpu_addr[15:4]==12'hff5) && 
					((cpu_addr[3:0]!=4'd0)&&(cpu_addr[3:0]< 4'd6)); //HDMA FF51-FF55 
wire sel_key1 = cpu_addr == 16'hff4d;  			      // KEY1 - CGB Mode Only - Prepare Speed Switch
wire sel_rp = cpu_addr == 16'hff56; //FF56 - RP - CGB Mode Only - Infrared Communications Port

//HDMA can select from $0000 to $7ff0 or A000-DFF0
wire hdma_sel_rom = !hdma_source_addr[15];                  // lower 32k are rom
wire hdma_sel_cram = hdma_source_addr[15:13] == 3'b101;     // 8k cart ram at $a000
wire hdma_sel_iram = hdma_source_addr[15:13] == 3'b110;     // 8k internal ram at $c000-$dff0


// the boot roms sees a special $42 flag in $ff50 if it's supposed to to a fast boot
wire sel_fast = fast_boot && cpu_addr == 16'hff50 && boot_rom_enabled;

wire [7:0] sc_r = {sc_start,6'h3F,sc_shiftclock};
				
// http://gameboy.mongenel.com/dmg/asmmemmap.html
wire [7:0] cpu_di = 
		irq_ack?irq_vec:
		sel_fast?8'h42:         // fast boot flag
		sel_if?{3'b111, if_r}:  // interrupt flag register
		isGBC&&sel_rp?8'h02:
	   isGBC&&sel_iram_bank?{5'h1f,iram_bank}:
	   isGBC&&sel_vram_bank?{7'h7f,vram_bank}:
	   isGBC&&sel_hdma?{hdma_do}:  //hdma GBC
	   isGBC&&sel_key1?{cpu_speed,6'h3f,prepare_switch}: //key1 cpu speed register(GBC)
		sel_joy?joy_do:         // joystick register
		sel_sb?8'hFF:				// serial transfer data register
		sel_sc?sc_r:				// serial transfer control register
		sel_timer?timer_do:     // timer registers
		sel_video_reg?video_do: // video registers
		(sel_video_oam&&!(lcd_mode==3 || lcd_mode==2))?video_do: // video object attribute memory
		sel_audio?audio_do:                                // audio registers
		sel_rom?rom_do:                                    // boot rom + cartridge rom
		sel_cram?rom_do:                                   // cartridge ram
		(sel_vram&&lcd_mode!=3)?(isGBC&&vram_bank)?vram1_do:vram_do:       // vram (GBC bank 0+1)
		sel_zpram?zpram_do:     // zero page ram
		sel_iram?iram_do:       // internal ram
		sel_ie?{3'b000, ie_r}:  // interrupt enable register
		8'hff;

wire cpu_wr_n;
wire cpu_rd_n;
wire cpu_iorq_n;
wire cpu_m1_n;
wire cpu_mreq_n;

wire cpu_clken = isGBC ? !hdma_active:1'b1;  //when hdma is enabled stop CPU (GBC)
wire cpu_stop;
	
GBse cpu (
	.RESET_n    ( !reset        ),
	.CLK_n      ( clk_cpu       ),
	.CLKEN      ( cpu_clken     ),
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
   .DO         ( cpu_do        ),
	.STOP       ( cpu_stop      )
);

// --------------------------------------------------------------------
// --------------------- Speed Toggle KEY1 (GBC)-----------------------
// --------------------------------------------------------------------
wire clk_cpu = cpu_speed?clk2x:clk;
//wire clk_cpu = clk;
reg cpu_speed; // - 0 Normal mode (4MHz) - 1 Double Speed Mode (8MHz)
reg prepare_switch; // set to 1 to toggle speed
assign speed = cpu_speed;

always @(posedge clk2x) begin
   if(reset) begin
			cpu_speed <= 1'b0;
			prepare_switch <= 1'b0;
	end else if (sel_key1 && !cpu_wr_n && isGBC)begin
		prepare_switch <= cpu_do[0];
	end
	
	if (isGBC && prepare_switch && cpu_stop) begin
		cpu_speed <= !cpu_speed;
		prepare_switch <= 1'b0;
	end
	
end

// --------------------------------------------------------------------
// ------------------------------ audio -------------------------------
// --------------------------------------------------------------------

wire audio_rd = !cpu_rd_n && sel_audio;
wire audio_wr = !cpu_wr_n && sel_audio;
wire [7:0] audio_do;

gbc_snd audio (
	.clk				( clk2x 				),
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
// -----------------------serial port(dummy)---------------------------
// --------------------------------------------------------------------

reg [3:0] serial_counter;
reg sc_start,sc_shiftclock;

reg serial_irq;
reg [8:0] serial_clk_div; //8192Hz

always @(posedge clk_cpu) begin
	serial_irq <= 1'b0;
   if(reset) begin
		  sc_start <= 1'b0;
		  sc_shiftclock <= 1'b0;
	end else if (sel_sc && !cpu_wr_n) begin	 //cpu write
		sc_start <= cpu_do[7];
		sc_shiftclock <= cpu_do[0];
		if (cpu_do[7]) begin 						//enable transfer
			serial_clk_div <= 9'h1FF;
			serial_counter <= 4'd8;
		end 
	end else if (sc_start && sc_shiftclock) begin // serial transfer and serial clock enabled
		
		serial_clk_div <= serial_clk_div - 9'd1;
		
		if (serial_clk_div == 9'd0  && serial_counter)
				serial_counter <= serial_counter - 4'd1;
		
		if (!serial_counter) begin
			serial_irq <= 1'b1; 	//trigger interrupt
			sc_start <= 1'b0; 	//reset transfer state
			serial_clk_div <= 9'h1FF;
		   serial_counter <= 4'd8;
		end	
	
	end
	
end

			

// --------------------------------------------------------------------
// ------------------------------ inputs ------------------------------
// --------------------------------------------------------------------

wire [3:0] joy_p4 = ~{ joystick[2], joystick[3], joystick[1], joystick[0] } | {4{p54[0]}};
wire [3:0] joy_p5 = ~{ joystick[7], joystick[6], joystick[5], joystick[4] } | {4{p54[1]}};
reg  [1:0] p54;

always @(posedge clk_cpu) begin
	if(reset) p54 <= 2'b00;
	else if(sel_joy && !cpu_wr_n)	p54 <= cpu_do[5:4];
end

wire [7:0] joy_do = { 2'b11, p54, joy_p4 & joy_p5 };

// --------------------------------------------------------------------
// ---------------------------- interrupts ----------------------------
// --------------------------------------------------------------------

// interrupt flags are set when the event happens or when the cpu writes
// the register to 1. The "highest" one active is cleared when the cpu
// runs an interrupt ack cycle or when it writes a 0 to the register

wire irq_ack = !cpu_iorq_n && !cpu_m1_n;

// irq vector
wire [7:0] irq_vec = 
			if_r[0]&&ie_r[0]?8'h40:   // vsync
			if_r[1]&&ie_r[1]?8'h48:   // lcdc
			if_r[2]&&ie_r[2]?8'h50:   // timer
			if_r[3]&&ie_r[3]?8'h58:   // serial
			if_r[4]&&ie_r[4]?8'h60:   // input
			8'h55;

//wire vs = (lcd_mode == 2'b01);
//reg vsD, vsD2;
reg [7:0] inputD, inputD2;

// irq is low when an enable irq is active
wire irq_n = !(ie_r & if_r);

reg [4:0] if_r;
reg [4:0] ie_r; // writing  $ffff sets the irq enable mask
always @(negedge clk_cpu) begin //negedge to trigger interrupt earlier
	reg old_ack = 0;
	
	if(reset) begin
		ie_r <= 5'h00;
		if_r <= 5'h00;
	end

	// rising edge on vs
//	vsD <= vs;
//	vsD2 <= vsD;
	if(vblank_irq) if_r[0] <= 1'b1;

	// video irq already is a 1 clock event
	if(video_irq) if_r[1] <= 1'b1;
	
	// timer_irq already is a 1 clock event
	if(timer_irq) if_r[2] <= 1'b1;
	
	// serial irq already is a 1 clock event
	if(serial_irq) if_r[3] <= 1'b1;

	// falling edge on any input line P10..P13
	inputD <= {joy_p4, joy_p5};
	inputD2 <= inputD;
	if(~inputD & inputD2) if_r[4] <= 1'b1;

	// cpu acknowledges irq. this clears the active irq with hte 
	// highest priority
	old_ack <= irq_ack;
	
	if(old_ack & ~irq_ack) begin
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
	.clk		    ( clk_cpu       ), //2x in fast mode

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
wire video_irq,vblank_irq;
wire [7:0] video_do;
wire [12:0] video_addr;
wire [15:0] dma_addr;
wire video_rd, dma_rd;
wire [7:0] dma_data = dma_sel_iram?iram_do:dma_sel_vram?(isGBC&&vram_bank)?vram1_do:vram_do:cart_do;


video video (
	.reset	    ( reset         ),
	.clk		    ( clk           ),
	.clk_reg     ( clk_cpu       ),   //can be 2x in cgb double speed mode
	.isGBC       ( isGBC         ),

	.isGBC_game  ( isGBC_game|boot_rom_enabled ),  //enable GBC mode during bootstrap rom

	.irq         ( video_irq     ),
	.vblank_irq  ( vblank_irq    ),


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
	
	// vram connection bank1 (GBC)
	.vram1_data  ( vram1_do      ),
	
	.dma_rd      ( dma_rd        ),
	.dma_addr    ( dma_addr      ),
	.dma_data    ( dma_data      )
		
);

// total 8k/16k (CGB) vram from $8000 to $9fff
wire cpu_wr_vram = sel_vram && !cpu_wr_n && lcd_mode!=3;

reg vram_bank; //0-1 FF4F - VBK

wire [7:0] vram_do,vram1_do;
wire [7:0] vram_di = (hdma_rd&&isGBC)?
								hdma_sel_iram?iram_do:
								is_hdma_cart_addr?cart_do:
								8'hFF:
							cpu_do;

 
wire vram_wren = video_rd?1'b0:!vram_bank&&((hdma_rd&&isGBC)||cpu_wr_vram);
wire vram1_wren = video_rd?1'b0:vram_bank&&((hdma_rd&&isGBC)||cpu_wr_vram);

wire [12:0] vram_addr = video_rd?video_addr:(hdma_rd&&isGBC)?hdma_target_addr[12:0]:(dma_rd&&dma_sel_vram)?dma_addr[12:0]:cpu_addr[12:0];


spram #(13) vram0 (
	.clock      ( clk_cpu               ),
	.address    ( vram_addr             ),
	.wren       ( vram_wren             ),
	.data       ( vram_di               ),
	.q          ( vram_do               )
);

//separate 8k for vbank1 for gbc because of BG reads
spram #(13) vram1 (
	.clock      ( clk_cpu               ),
	.address    ( vram_addr             ),
	.wren       ( vram1_wren            ),
	.data       ( vram_di               ),
	.q          ( vram1_do              )
);

//GBC VRAM banking
always @(posedge clk_cpu) begin
	if(reset)
		vram_bank <= 1'd0;
	else if((cpu_addr == 16'hff4f) && !cpu_wr_n && isGBC)
		vram_bank <= cpu_do[0];
end

// --------------------------------------------------------------------
// -------------------------- HDMA engine(GBC) ------------------------
// --------------------------------------------------------------------

wire [15:0] hdma_source_addr;
wire [15:0] hdma_target_addr;
wire [7:0] hdma_do;
wire hdma_rd;
wire hdma_active;

hdma hdma(
	.reset	          ( reset         ),
	.clk		          ( clk2x         ),
	.speed				 ( cpu_speed     ),
	
	// cpu register interface
	.sel_reg 	       ( sel_hdma      ),
	.addr			       ( cpu_addr[3:0] ),
	.wr			       ( !cpu_wr_n 	  ),
	.dout			       ( hdma_do       ),
	.din               ( cpu_do        ),
	
	.lcd_mode          ( lcd_mode      ),
	
	// dma connection
	.hdma_rd           ( hdma_rd          ),
	.hdma_active       ( hdma_active      ),
	.hdma_source_addr  ( hdma_source_addr ),
	.hdma_target_addr  ( hdma_target_addr ) 
	
);

// --------------------------------------------------------------------
// -------------------------- zero page ram ---------------------------
// --------------------------------------------------------------------

// 127 bytes internal zero page ram from $ff80 to $fffe
wire cpu_wr_zpram = sel_zpram && !cpu_wr_n;
wire [7:0] zpram_do;
spram #(7) zpram (
	.clock      ( clk_cpu        ),
	.address    ( cpu_addr[6:0]  ),
	.wren       ( cpu_wr_zpram   ),
	.data       ( cpu_do         ),
	.q          ( zpram_do       )
);

// --------------------------------------------------------------------
// ------------------------ 8k/32k(GBC) internal ram  -----------------
// --------------------------------------------------------------------

reg  [2:0] iram_bank; //1-7 FF70 - SVBK
wire iram_wren = (dma_rd&&dma_sel_iram)||(isGBC&&hdma_rd&&hdma_sel_iram)?1'b0:cpu_wr_iram;

wire [14:0] iram_addr = (isGBC&&hdma_rd&&hdma_sel_iram)?               //hdma transfer?
									(hdma_source_addr[12])?{iram_bank,hdma_source_addr[11:0]}:  //bank 1-7 D000-DFFF
									{3'd0,hdma_source_addr[11:0]}:					               //bank 0									
								(dma_rd&&dma_sel_iram)?								  //dma transfer?
									(dma_addr[12])?{iram_bank,dma_addr[11:0]}:  //bank 1-7
									{3'd0,dma_addr[11:0]}:					        //bank 0
								//cpu 
								(cpu_addr[12])?{iram_bank,cpu_addr[11:0]}:	  //bank 1-7
								{3'd0,cpu_addr[11:0]};						  		  //bank 0				
								

wire cpu_wr_iram = sel_iram && !cpu_wr_n;
wire [7:0] iram_do;
spram #(15) iram (
	.clock      ( clk_cpu        ),
	.address    ( iram_addr      ),
	.wren       ( iram_wren      ),
	.data       ( cpu_do         ),
	.q          ( iram_do        )
);

//GBC WRAM banking
always @(posedge clk_cpu) begin
	if(reset)
		iram_bank <= 3'd1;
	else if((cpu_addr == 16'hff70) && !cpu_wr_n && isGBC) begin
		if (cpu_do[2:0]==3'd0) // 0 -> 1;
			iram_bank <= 3'd1;
		else
			iram_bank <= cpu_do[2:0];
	end
end

// --------------------------------------------------------------------
// ------------------------ internal boot rom -------------------------
// --------------------------------------------------------------------

// writing 01(GB) or 11(GBC) to $ff50 disables the internal rom
reg boot_rom_enabled;
always @(posedge clk) begin
	if(reset)
		boot_rom_enabled <= 1'b1;
	else if((cpu_addr == 16'hff50) && !cpu_wr_n)
          if ((isGBC && cpu_do[7:0]==8'h11) || (!isGBC && cpu_do[0]))
		          boot_rom_enabled <= 1'b0;
end
			
// combine boot rom data with cartridge data

wire [7:0] rom_do = isGBC? //GameBoy Color?
                        (((cpu_addr[14:8] == 7'h00) || (hdma_rd&& hdma_source_addr[14:8] == 7'h00))&& boot_rom_enabled)?gbc_bios_do:         //0-FF bootrom 1st part
                        ((cpu_addr[14:9] == 6'h00) || (hdma_rd&& hdma_source_addr[14:9] == 6'h00))? cart_do:                                 //100-1FF Cart Header
                        (((cpu_addr[14:12] == 3'h0) || (hdma_rd&& hdma_source_addr[14:12] == 3'h0)) && boot_rom_enabled)?gbc_bios_do:        //200-8FF bootrom 2nd part
                        cart_do:                                                            //rest of card
                    ((cpu_addr[14:8] == 7'h00) && boot_rom_enabled)?boot_rom_do:cart_do;    //GB


wire is_dma_cart_addr = (dma_sel_rom || dma_sel_cram); //rom or external ram
wire is_hdma_cart_addr = (hdma_sel_rom || hdma_sel_cram); //rom or external ram

assign cart_di = cpu_do;
assign cart_addr = (isGBC&&hdma_rd&&is_hdma_cart_addr)?hdma_source_addr:(dma_rd&&is_dma_cart_addr)?dma_addr:cpu_addr;
assign cart_rd = (isGBC&&hdma_rd&&is_hdma_cart_addr) || (dma_rd&&is_dma_cart_addr) || ((sel_rom || sel_cram) && !cpu_rd_n);
assign cart_wr = (sel_rom || sel_cram) && !cpu_wr_n && !hdma_rd;

assign gbc_bios_addr = hdma_rd?hdma_source_addr[11:0]:cpu_addr[11:0];

wire [7:0] boot_rom_do;
boot_rom boot_rom (
	.address ( cpu_addr[7:0] ),
	.clock   ( clk           ),
	.q       ( boot_rom_do   )
);

endmodule
