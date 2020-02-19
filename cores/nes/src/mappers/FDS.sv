//Famicom Disk System

module MapperFDS(
	input        clk,         // System clock
	input        ce,          // M2 ~cpu_clk
	input        enable,      // Mapper enabled
	input [31:0] flags,       // Cart flags
	input [15:0] prg_ain,     // prg address
	inout [21:0] prg_aout_b,  // prg address out
	input        prg_read,    // prg read
	input        prg_write,   // prg write
	input  [7:0] prg_din,     // prg data in
	inout  [7:0] prg_dout_b,  // prg data out
	inout        prg_allow_b, // Enable access to memory for the specified operation.
	input [13:0] chr_ain,     // chr address in
	inout [21:0] chr_aout_b,  // chr address out
	input        chr_read,    // chr ram read
	inout        chr_allow_b, // chr allow write
	inout        vram_a10_b,  // Value for A10 address line
	inout        vram_ce_b,   // True if the address should be routed to the internal 2kB VRAM.
	inout        irq_b,       // IRQ
	input [15:0] audio_in,    // Inverted audio from APU
	inout [15:0] audio_b,     // Mixed audio output
	inout [15:0] flags_out_b, // flags {0, 0, 0, 0, 0, prg_conflict, prg_open_bus, has_chr_dout}
	// Special ports
	inout [1:0] diskside_auto_b,
	input [1:0] diskside,
	input       fds_busy,
	input       fds_eject
);

assign prg_aout_b      = enable ? prg_aout : 22'hZ;
assign prg_dout_b      = enable ? prg_dout : 8'hZ;
assign prg_allow_b     = enable ? prg_allow : 1'hZ;
assign chr_aout_b      = enable ? chr_aout : 22'hZ;
assign chr_allow_b     = enable ? chr_allow : 1'hZ;
assign vram_a10_b      = enable ? vram_a10 : 1'hZ;
assign vram_ce_b       = enable ? vram_ce : 1'hZ;
assign irq_b           = enable ? irq : 1'hZ;
assign flags_out_b     = enable ? flags_out : 16'hZ;
assign audio_b         = enable ? 16'hFFFF - audio[16:1] : 16'hZ;
assign diskside_auto_b = enable ? diskside_auto : 2'hZ;

wire [21:0] prg_aout, chr_aout;
wire prg_allow;
wire chr_allow;
wire vram_a10;
wire vram_ce;
wire [7:0] prg_dout;
reg [15:0] flags_out = 0;
wire irq;
wire [1:0] diskside_auto;

wire nesprg_oe;
wire [7:0] neschrdout;
wire neschr_oe;
wire wram_oe;
wire wram_we;
wire prgram_we;
wire chrram_oe;
wire prgram_oe;
wire exp6;
reg [7:0] m2;
wire m2_n = 1;//~ce;  //m2_n not used as clk.  Invert m2 (ce).

always @(posedge clk) begin
	m2[7:1] <= m2[6:0];
	m2[0] <= ce;
end

MAPFDS fds(m2[7], m2_n, clk, ~enable, prg_write, nesprg_oe, 0,
	1, prg_ain, chr_ain, prg_din, 8'b0, prg_dout,
	neschrdout, neschr_oe, chr_allow, chrram_oe, wram_oe, wram_we, prgram_we,
	prgram_oe, chr_aout[18:10], prg_aout[18:0], irq, vram_ce, exp6,
	0, 7'b1111111, 6'b111111, flags[14], flags[16], flags[15],
	ce, prg_allow, audio_exp, diskside_auto, diskside, fds_busy, fds_eject);

assign chr_aout[21:19] = 3'b100;
assign chr_aout[9:0] = chr_ain[9:0];
assign vram_a10 = chr_aout[10];
assign prg_aout[21:19] = prg_aout[18] ? 3'b111 : 3'b000;  //Switch to Cart Ram for Disk access
//assign prg_aout[12:0] = prg_ain[12:0];

wire [11:0] audio_exp;

// XXX: This needs to be replaced with a proper ~2000hz LPF
lpf_aud fds_lpf
(
	.CLK(clk),
	.CE(ce),
	.IDATA(16'hFFFF - {1'b0, audio_exp[11:0], audio_exp[11:9]}),
	.ODATA(audio_exp_f)
);

wire [15:0] audio_exp_f;
wire [16:0] audio = audio_in + audio_exp_f;

endmodule

// Loopy's FDS mapper for the Power Pak mapFDS.v
//PRG 00000-01FFF = bios
//PRG 08000-0FFFF = wram
//PRG 40000-7FFFF = disk image
module MAPFDS(              //signal descriptions in powerpak.v
	input m2,
	input m2_n,
	input clk20,

	input reset,
	input nesprg_we,
	output nesprg_oe,
	input neschr_rd,
	input neschr_wr,
	input [15:0] prgain,
	input [13:0] chrain,
	input [7:0] nesprgdin,
	input [7:0] ramprgdin,
	output reg [7:0] nesprgdout,

	output [7:0] neschrdout,
	output neschr_oe,

	output chrram_we,
	output chrram_oe,
	output wram_oe,
	output wram_we,
	output prgram_we,
	output prgram_oe,
	output [18:10] ramchraout,
	output [18:0] ramprgaout,
	output irq,
	output ciram_ce,
	output exp6,

	input cfg_boot,
	input [18:12] cfg_chrmask,
	input [18:13] cfg_prgmask,
	input cfg_vertical,
	input cfg_fourscreen,
	input cfg_chrram,

	input ce,// add
	output prg_allow,
	output [11:0] snd_level,
	output reg [1:0] diskside_auto,
	input [1:0] diskside,
	input fds_busy,
	input fds_eject
);

	localparam WRITE_LO=16'hF4CD, WRITE_HI=16'hF4CE, READ_LO=16'hF4D0, READ_HI=16'hF4D1;

	assign neschrdout = 0;
	assign neschr_oe = 0;
	assign exp6 = 0;

	wire disk_eject;
	reg timer_irq;
	reg [1:0] Wstate;
	reg [1:0] Rstate;
	wire [7:0] audio_dout;

	assign chrram_we=!chrain[13] & neschr_wr;
	assign chrram_oe=!chrain[13] & neschr_rd;

	assign wram_we=0; //use main ram for everything
	assign wram_oe=0;

	assign prgram_we=~cfg_boot & m2_n &  nesprg_we & (Wstate==2 | (prgain[15]^(&prgain[14:13])));       //6000-DFFF or disk write
	assign prgram_oe=~cfg_boot & m2_n & ~nesprg_we & (prgain[15] | prgain[15:13]==3);                   //6000-FFFF
	wire   fds_oe=               m2_n & ~nesprg_we & (prgain[15:12]==4) & (|prgain[7:5] | prgain[9]);   //$4xxx (except 00-1F) or 42xx

	assign nesprg_oe=prgram_oe | fds_oe;

	reg saved=0;
	reg [15:0] diskpos;
	reg [17:0] sideoffset;
	wire [17:0] romoffset;

// Loopy's patched bios use a trick to catch requested diskside for games
// using standard bios load process.
// Unlicensed games sometimes doesn't use standard bios load process. This
// break automatic diskside trick.
// diskside_manual to be manage from OSD user input allow to add diskswap capabilities.
// (automatic fds_eject should be preferably stopped before changing diskside_manual)

//	reg [1:0] diskside_auto;
//	wire[1:0] diskside;
//	assign diskside = diskside_auto + diskside_manual;
	wire diskend=(diskpos==65499);
	always@* case(diskside) //16+65500*diskside
		0:sideoffset=18'h00010;
		1:sideoffset=18'h0ffec;
		2:sideoffset=18'h1ffc8;
		3:sideoffset=18'h2ffa4;
	endcase
	assign romoffset=diskpos + sideoffset;

// Unlicensed fds games use NMI trick to skip protection. Rationale is to load
// a file starting @$2000 with $90 or $80 to enable NMI. This file should be at
// least 256 bytes length to allow NMI to occure before end of load. PC is then
// transfered to a special loader. This is ok with real hardware.
// But with loopy's patched bios the 256 bytes file is loaded too fast and no NMI
// occure early enough.
// Here proposed solution is to create an infinite loop at the end of normal
// load subroutine if @$2000 was written during load subroutine. Infinite loop
// give enough time for NMI to occure. (Generaly observed NMI enabling file is
// the last file of 'normal' loading process to be loaded). @2000.7 is checked to
// ensure the NMI is being turned on ($90 or $80 mentioned above).

	// manage infinite loop trap at the end ($E233) of LoadFiles subroutine
//	 reg previous_is_E1F9;
	reg infinite_loop_on_E233 = 0;
	reg within_loader = 0;
//	 reg loader_write_in_2000 = 0;
always@(posedge clk20)
		if(reset) begin
			// on reset activate infinite loop trap
		end
		else begin
				if ((m2) && (ramprgaout[18]==1'b0))begin

					// detect enter / leave LoadFile subroutine
					if(prgain==16'hE1FA) within_loader <= 1;
					if(prgain==16'hE235) within_loader <= 0;

					// deactivate infinite loop at LoadFile subroutine
					if(prgain==16'hE1FA) infinite_loop_on_E233 <= 0;

					// activate infinite loop if @$2000 is written with NMI (bit 7) high during FileLoad subroutine
					if((prgain==16'h2000) && (within_loader == 1) && (nesprgdin[7])) infinite_loop_on_E233 <= 1;
				end

		end

//NES data out
wire match0=prgain==16'h4030;       //IRQ status
wire match1=prgain==16'h4032;       //drive status
wire match2=prgain==16'h4033;       //power / exp
wire match3=((prgain==READ_LO)|(prgain==WRITE_LO))&!(Wstate==2 | Rstate==2);
wire match4=((prgain==READ_HI)|(prgain==WRITE_HI))&!(Wstate==2 | Rstate==2);
wire match5=prgain==16'h4208;       //powerpak save flag
wire match6=prgain[15:8]==8'h40 && |prgain[7:6];    //4040..40FF
wire match7=(prgain==16'hE233) & infinite_loop_on_E233 & (ramprgaout[18]==1'b0);
wire match8=(prgain==16'hE234) & infinite_loop_on_E233 & (ramprgaout[18]==1'b0);
wire match9=(prgain==16'hE235) & infinite_loop_on_E233 & (ramprgaout[18]==1'b0);
wire match10=prgain==16'h4029;      //MiSTer Busy
always@*
	case(1)
		match0: nesprgdout={7'd0, timer_irq};
		match1: nesprgdout={5'd0, disk_eject, diskend, disk_eject};
		match2: nesprgdout=8'b10000000;
		match3: nesprgdout=romoffset[7:0];
		match4: nesprgdout={3'b111,romoffset[12:8]};
		match5: nesprgdout={7'd0,saved};
		match6: nesprgdout=audio_dout;
		match7: nesprgdout=8'h4C;  // when infinite loop is active replace jsr $E778 with jmp $E233
		match8: nesprgdout=8'h33;
		match9: nesprgdout=8'hE2;
		match10:nesprgdout={7'd0,~fds_busy};//MiSTer busy (zero = busy)
		default: nesprgdout=ramprgdin;
	endcase
assign prg_allow = (nesprg_we & (Wstate==2 | (prgain[15]^(&prgain[14:13]))))
				| (~nesprg_we & ((prgain[15] & !match3 & !match4 & !match7 & !match8 & !match9) | prgain[15:13]==3));

	reg write_en;
	reg vertical;
	reg timer_irq_en;
	reg timer_irq_repeat;
	reg diskreset;
	reg disk_reg_en;
	reg [15:0] timerlatch;
	reg [15:0] timer;
	always@(posedge clk20) begin
		if(reset) begin
			diskside_auto <= 2'd0;
		end

		if (ce) begin
			if (timer_irq_en) begin
				if (timer == 0) begin
					timer_irq <= 1;
					timer <= timerlatch;
					if (~timer_irq_repeat) begin
						timer_irq_en <= 0;
					end
				end else begin
					timer <= timer - 1'd1;
				end
		end

		if(nesprg_we)
			case(prgain)
				16'h4020: timerlatch[7:0]<=nesprgdin;

				16'h4021: timerlatch[15:8]<=nesprgdin;

				16'h4022: begin
					timer_irq_repeat<=nesprgdin[0];
					timer_irq_en<=nesprgdin[1] & disk_reg_en;

					if (nesprgdin[1] & disk_reg_en) begin
						timer <= timerlatch;
					end else begin
						timer_irq <= 0;
					end
				end

				16'h4023: begin
					disk_reg_en <=nesprgdin[0];
					if (~nesprgdin[0]) begin
						timer_irq_en <= 0;
						timer_irq <= 0;
					end
				end

				//16'h4024: //disk data write
				16'h4025: begin // disk control
					diskreset<=nesprgdin[1];
					write_en<=!nesprgdin[2];
					vertical<=!nesprgdin[3];
					//disk_irq_en<=nesprgdin[7];
				end

				16'h4027:   //powerpak extra: disk side
					diskside_auto<=nesprgdin[1:0];
			endcase
	end

	if (m2) begin
		if (~nesprg_we & prgain==16'h4030)
			timer_irq <= 0;
	end
end

//watch for disk read/write
always@(posedge clk20) begin
	if (m2) begin
		if(write_en & ~nesprg_we & (prgain==WRITE_LO))
			Wstate<=1;
		else if(~nesprg_we & (prgain==WRITE_HI) & Wstate==1)
			Wstate<=2;
		else 
			Wstate<=0;

		if(~nesprg_we & (prgain==READ_LO))
			Rstate<=1;
		else if(~nesprg_we & (prgain==READ_HI) & Rstate==1)
			Rstate<=2;
		else
			Rstate<=0;

		if(Wstate==2)
			saved<=1;
	end
end

//disk pointer
always@(posedge clk20) begin
	if (m2) begin
		if(diskreset)
			diskpos<=0;
		else if(Rstate==2 & !diskend)
			diskpos<=diskpos+1'd1;
	end
end

assign irq=timer_irq; // | disk_irq

//disk eject:   toggle flag continuously except when select button is held
//reg [2:0] control_cnt; //use fds_eject instead
//reg [21:0] clkcount;

//assign disk_eject=clkcount[21] | fds_eject;
assign disk_eject=fds_eject;

//always@(posedge clk20) begin
//	if (ce) begin
//		clkcount<=clkcount+1'd1;
//		if(prgain==16'h4016) begin
//			if(nesprg_we)                           control_cnt<=0;
//			else if(~nesprg_we & control_cnt!=7)    control_cnt<=control_cnt+1'd1;
//			//if(~nesprg_we & control_cnt==2)          button<=|nesprgdin[1:0];
//		end
//	end
//end

//bankswitch control: 6000-DFFF = sram, E000-FFFF = bios or disk
reg [18:13] prgbank;
wire [18:13] diskbank={1'b1,romoffset[17:13]};

always@* begin
	if(prgain[15:13]==7)
		prgbank=diskbank & {6{Rstate==2|Wstate==2}};
	else
		prgbank={4'b0001,prgain[14:13]};
end

assign ramprgaout={prgbank,prgain[12:0]};

//mirroring
assign ramchraout[18:11]={6'd0,chrain[12:11]};
assign ramchraout[10]=!chrain[13]? chrain[10]: ((vertical & chrain[10]) | (!vertical & chrain[11]));
assign ciram_ce=chrain[13];

//expansion audio
fds_audio fds_audio
(
	.clk(clk20),
	.m2(ce),
	.reset(reset),
	.wr(nesprg_we),
	.addr_in(prgain),
	.data_in(nesprgdin),
	.data_out(audio_dout),
	.audio_out(snd_level)
);

endmodule

// FDS Audio module by Kitrinx
// Based on the amazing research by Loopy from Jan, 2019

module fds_audio(
	input            clk,
	input            m2,
	input            reset,
	input            wr,
	input     [15:0] addr_in,
	input      [7:0] data_in,
	output reg [7:0] data_out,
	output    [11:0] audio_out
);

// Volume Envelope
reg  [5:0] vol_speed;
reg  [5:0] vol_gain;
reg  [5:0] vol_pwm_lat;
reg        vol_dir;
reg        vol_disable;

// Sweep Envelope
reg [5:0]  sweep_speed;
reg [5:0]  sweep_gain;
reg        sweep_dir;
reg        sweep_disable;

// Modulator
reg [11:0] mod_frequency;
reg [17:0] mod_accum;
reg        mod_step;
reg  [2:0] mod_table[0:31];
reg signed [6:0] mod_bias;
reg signed [6:0] mod_incr;
reg        mod_disable;

// Wave Table
reg        wave_wren;
reg [23:0] wave_accum;
reg  [5:0] wave_table[0:63];
reg  [5:0] wave_latch;
reg [11:0] wave_frequency;
reg        wave_disable; // high: Envelopes 4x faster and stops mod table accum.

// Timing
reg        env_disable;
reg  [7:0] env_speed = 8'hE8;
reg [11:0] vol_env_ticks, sweep_env_ticks;
reg  [5:0] vol_ticks, sweep_ticks;
reg  [1:0] master_vol;

// Master timer
reg [3:0] cycles;

wire [12:0] mod_acc_next = mod_accum[11:0] + mod_frequency;

// Loopy's magical modulation math
wire signed [11:0] temp = mod_bias * $signed({1'b0, sweep_gain});
wire signed [11:0] temp2 = $signed((|temp[3:0] & ~temp[11]) ? temp + 12'sh20 : temp);
wire signed [11:0] temp3 = temp2 + 12'sh400;
wire [19:0] wave_pitch = $unsigned(temp3[11:4]) * wave_frequency;

// Volume math
wire [11:0] mul_out = wave_latch * (vol_pwm_lat[5] ? 6'd32 : vol_pwm_lat);

wire [15:0] level_out;
assign audio_out = level_out[11:0];

always_comb begin
	case (master_vol)
		2'b00: level_out = mul_out;
		2'b01: level_out = {mul_out, 1'b0} / 16'd3;
		2'b10: level_out = mul_out[11:1];
		2'b11: level_out = {mul_out, 1'b0} / 16'd5;
		default: level_out = mul_out;
	endcase

	if (addr_in >= 'h4040 && addr_in < 'h4080) begin
		if (wave_wren)
			data_out = wave_table[addr_in[5:0]];
		else
			data_out = wave_table[wave_accum[23:18]];
	end else begin
		case (addr_in)
			'h4090: data_out = {2'b01, vol_gain};
			'h4091: data_out = wave_accum[19:12];
			'h4092: data_out = {2'b01, sweep_gain};
			'h4093: data_out = {1'b0, mod_accum[11:5]};
			'h4094: data_out = wave_pitch[11:4];
			'h4095: data_out = {cycles, mod_incr[3:0]};
			'h4096: data_out = {2'b01, wave_table[wave_accum[23:18]]};
			'h4097: data_out = {1'b0, mod_bias};
			default: data_out = 8'b0100_0000;
		endcase
	end

	case (mod_table[mod_accum[17:13]])
		3'h0: mod_incr = 0;
		3'h1: mod_incr = 7'sd1;
		3'h2: mod_incr = 7'sd2;
		3'h3: mod_incr = 7'sd4;
		3'h4: mod_incr = -7'sd4;
		3'h5: mod_incr = -7'sd4;
		3'h6: mod_incr = -7'sd2;
		3'h7: mod_incr = -7'sd1;
		default: mod_incr = 0;
	endcase
end

always_ff @(posedge clk) begin
reg old_m2;

old_m2 <= m2;
if (reset) begin
	sweep_disable <= 1'b1;
	env_disable <= 1'b1;
	wave_disable <= 1'b1;
	mod_disable <= 1'b1;
	wave_accum <= 0;
	mod_accum <= 0;
	{cycles, sweep_ticks, sweep_env_ticks, vol_ticks, vol_env_ticks, master_vol} <= 0;
end else if (~old_m2 & m2) begin
	//**** Timings ****//
	cycles <= wave_disable ? 4'h0 : cycles + 1'b1;

	if (&cycles && ~wave_disable) begin
		wave_accum <= wave_accum + wave_pitch;
		if (~mod_disable)
			mod_accum <= mod_accum + mod_frequency;
	end

	//**** Envelopes ****//
	if (~env_disable && env_speed) begin

		//**** Volume Envelope ****//
		if (~vol_disable) begin
			if (vol_env_ticks >= {env_speed, 3'b111}) begin
				vol_env_ticks <= 0;
				if (vol_ticks == vol_speed) begin
					vol_ticks <= 0;
					if (vol_dir && ~vol_gain[5])
						vol_gain <= vol_gain + 1'b1;
					else if (~vol_dir && vol_gain)
						vol_gain <= vol_gain - 1'b1;
				end else
					vol_ticks <= vol_ticks + 1'b1;
			end else
				vol_env_ticks <= vol_env_ticks + (~wave_disable ? 1'b1 : 4'd4);
		end

		//**** Sweep Envelope ****//
		if (~sweep_disable) begin
			if (sweep_env_ticks >= {env_speed, 3'b111}) begin
				sweep_env_ticks <= 0;
				if (sweep_ticks == sweep_speed) begin
					sweep_ticks <= 0;
					if (sweep_dir && ~sweep_gain[5])
						sweep_gain <= sweep_gain + 1'b1;
					else if (~sweep_dir && sweep_gain)
						sweep_gain <= sweep_gain - 1'b1;
				end else
					sweep_ticks <= sweep_ticks + 1'b1;
			end else
				sweep_env_ticks <= sweep_env_ticks + (~wave_disable ? 1'b1 : 4'd4);
		end
	end

	//**** Modulation ****//
	if ((&cycles && mod_acc_next[12]) || mod_step) begin
		if (mod_table[mod_accum[17:13]] == 3'h4) begin
			mod_bias <= 0;
		end else begin
			mod_bias <= mod_bias + mod_incr;
		end
	end

	//**** Latches ****//
	if (~|wave_accum[23:18])
		vol_pwm_lat <= vol_gain;

	if (~wave_wren)
		wave_latch <= wave_table[wave_accum[23:18]];

	//**** Registers ****//
	if (wr) begin
		if (addr_in >= 'h4040 && addr_in < 'h4080) begin
			if (wave_wren)
				wave_table[addr_in[5:0]] <= data_in[5:0];
		end
		case (addr_in)
			16'h4080: begin
				{vol_disable, vol_dir, vol_speed} <= data_in;
				if (data_in[7]) vol_gain <= data_in[5:0];
				vol_ticks <= 0;
				vol_env_ticks <= 0;
			end

			16'h4082: wave_frequency[7:0] <= data_in;

			16'h4083: begin
				wave_frequency[11:8] <= data_in[3:0];
				wave_disable <= data_in[7];
				env_disable <= data_in[6];

				if (data_in[7]) begin
					wave_accum <= 0;
					cycles <= 0;
				end

				if (data_in[6]) begin // Reset envelopes
					vol_ticks <= 0;
					sweep_ticks <= 0;
					vol_env_ticks <= 0;
					sweep_env_ticks <= 0;
				end
			end

			16'h4084: begin
				{sweep_disable, sweep_dir, sweep_speed} <= data_in;
				if (data_in[7]) sweep_gain <= data_in[5:0];
				sweep_ticks <= 0;
				sweep_env_ticks <= 0;
			end

			16'h4085: mod_bias <= data_in[6:0];

			16'h4086: mod_frequency[7:0] <= data_in;

			16'h4087: begin
				mod_frequency[11:8] <= data_in[3:0];
				mod_disable <= data_in[7];
				mod_step <= data_in[6];

				if (data_in[7])
					mod_accum[12:0] <= 0;
			end

			16'h4088: begin
				if (mod_disable) begin
					mod_table[mod_accum[17:13]] <= data_in[2:0];
					mod_accum[17:13] <= mod_accum[17:13] + 1'b1;
				end
			end

			16'h4089: begin
				wave_wren <= data_in[7];
				master_vol <= data_in[1:0];
			end

			16'h408A: begin
				env_speed <= data_in;
				vol_ticks <= 0;
				sweep_ticks <= 0;
				vol_env_ticks <= 0; // Undocumented, but I believe this is right.
				sweep_env_ticks <= 0;
			end
		endcase
	end
end // if m2
end

endmodule


module lpf_aud
(
	input         CLK,
	input         CE,
	input  [15:0] IDATA,
	output reg [15:0] ODATA
);

reg [511:0] acc;
reg [20:0] sum;

always @(*) begin
	integer i;
	sum = 0;
	for (i = 0; i < 32; i = i+1) sum = sum + {{5{acc[(i*16)+15]}}, acc[i*16 +:16]};
end

always @(posedge CLK) begin
	if(CE) begin
		acc <= {acc[495:0], IDATA};
		ODATA <= sum[20:5];
	end
end

endmodule
