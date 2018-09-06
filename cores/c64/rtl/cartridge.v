module cartridge
(
	input         romL,						// romL signal in
	input         romH,						// romH signal in
	input         UMAXromH,					// romH VIC II address signal
	input         IOE,						// IOE control signal
	input         IOF,						// IOF control signal
	input         mem_write,				// memory write active
	input         mem_ce,
	output        mem_ce_out,

	input         clk32,				 		// 32mhz clock source
	input         reset,						// reset signal
	output reg    reset_out,				// reset signal

	input  [15:0] cart_id,					// cart ID or cart type
	input   [7:0] cart_exrom,				// CRT file EXROM status
	input   [7:0] cart_game,				// CRT file GAME status

	input  [15:0] cart_bank_laddr,		// bank loading address
	input  [15:0] cart_bank_size,			// length of each bank
	input  [15:0] cart_bank_num,
	input   [7:0] cart_bank_type,
	input  [24:0] cart_bank_raddr,		// chip packet address
	input         cart_bank_wr,

	input         cart_attached,			// FLAG to say cart has been loaded
	input         cart_loading,

	input  [15:0] c64_mem_address_in,	// address from cpu
	input   [7:0] c64_data_out,			// data from cpu going to sdram

	output [24:0] sdram_address_out, 	// translated address output
	output        exrom,						// exrom line
	output        game,						// game line
	output reg    IOE_ena,					// FLAG to enable IOE address relocation
	output reg    IOF_ena,					// FLAG to enable IOF address relocation
	output reg    max_ram,              // Enable whole C64 RAM in Ultimax mode

	input         freeze_key,
	output reg    nmi,
	input         nmi_ack
);

reg [24:0] addr_out;
assign     sdram_address_out = addr_out;

reg  [6:0] bank_lo;
reg  [6:0] bank_hi;
reg [12:0] mask_lo;

reg  [6:0] IOE_bank;
reg  [6:0] IOF_bank;
reg        IOE_wr_ena;
reg        IOF_wr_ena;

reg    exrom_overide;
reg    game_overide;
assign exrom = ~cart_attached | exrom_overide;
assign game  = ~cart_attached | game_overide;

(* ramstyle = "logic" *) reg [6:0] lobanks[0:63];
(* ramstyle = "logic" *) reg [6:0] hibanks[0:63];

reg  [7:0] bank_cnt;
always @(posedge clk32) begin
	reg old_loading;
	old_loading <= cart_loading;

	if(~old_loading & cart_loading) bank_cnt <= 0;
	if(cart_bank_wr) begin
		bank_cnt <= bank_cnt + 1'd1;
		if(cart_bank_num<64) begin
			if(cart_bank_laddr <= 'h8000) begin
				lobanks[cart_bank_num[5:0]] <= cart_bank_raddr[19:13];
				if(cart_bank_size > 'h2000) hibanks[cart_bank_num[5:0]] <= cart_bank_raddr[19:13]+1'd1;
			end
			else hibanks[cart_bank_num[5:0]] <= cart_bank_raddr[19:13];
		end
	end
end

reg romL_we = 0;
reg romH_we = 0;

reg old_ioe, old_iof;
always @(posedge clk32) begin
	old_ioe <= IOE;
	old_iof <= IOF;
end

wire stb_ioe = (~old_ioe & IOE);
wire stb_iof = (~old_iof & IOF);

wire ioe_wr = stb_ioe & mem_write;
wire ioe_rd = stb_ioe & ~mem_write;

wire iof_wr = stb_iof & mem_write;
//wire iof_rd = stb_iof & ~mem_write;

reg  old_freeze = 0;
wire freeze_req = (~old_freeze & freeze_key);

reg  old_nmiack = 0;
wire freeze_ack = (nmi & ~old_nmiack & nmi_ack);

// 0018 - EXROM line status
// 0019 - GAME line status

always @(posedge clk32) begin
	reg        init_n = 0;
	reg        allow_freeze = 0;
	reg        saved_d6 = 0;
	reg [15:0] count;
	reg        count_ena;
	reg        cart_disable = 0;

	old_freeze <= freeze_key;
	if(freeze_req & allow_freeze) nmi <= 1;

	old_nmiack <= nmi_ack;
	if(freeze_ack) nmi <= 0;

	if(!reset) begin
		cart_disable <= 0;
		bank_lo <= 0;
		bank_hi <= 0;
		IOE_ena <= 0;
		IOF_ena <= 0;
		IOE_wr_ena <= 0;
		IOF_wr_ena <= 0;
		romL_we <= 0;
		romH_we <= 0;
		reset_out <= 0;
		init_n <= 0;
		allow_freeze <= 1;
		nmi <= 0;
		saved_d6 <= 0;
		mask_lo <= 13'h1FFF;
		exrom_overide <= 1;
		game_overide <= 1;
		max_ram <= 0;
	end
	else
	case(cart_id)

		// Generic 8k(exrom=0,game=1), 16k(exrom=0,game=0), ULTIMAX(exrom=1,game=0)
		0:	begin
				exrom_overide <= cart_exrom[0];
				game_overide <= cart_game[0];
				bank_lo <= lobanks[0];
				bank_hi <= hibanks[0];
			end

		// Action Replay v4+ - (32k 4x8k banks + 8K RAM)
		// controlled by DE00
		1:	begin
				if(nmi) allow_freeze <= 0;
				if(!init_n || freeze_ack) begin
					cart_disable  <= 0;
					exrom_overide <= 1;
					game_overide  <= 0;
					romL_we <= 0;
					bank_lo <= 0;
					bank_hi <= 0;
					IOF_bank <= 0;
					IOF_wr_ena <= 0;
					IOF_ena <= 1;
					if(~init_n) begin
						init_n <= 1;
						exrom_overide <= 0;
						game_overide  <= 1;
					end
				end
				else if(cart_disable) begin
					exrom_overide <= 1;
					game_overide <= 1;
					IOF_ena <= 0;
					IOF_wr_ena <= 0;
					romL_we <= 0;
					allow_freeze <= 1;
				end else begin
					if(ioe_wr) begin
						cart_disable <= c64_data_out[2];
						bank_lo <= c64_data_out[4:3];
						bank_hi <= c64_data_out[4:3];
						IOF_bank <= c64_data_out[4:3];

						if(c64_data_out[6] | allow_freeze) begin
							allow_freeze <= 1;
							game_overide  <= ~c64_data_out[0];
							exrom_overide <=  c64_data_out[1];
							IOF_wr_ena <= c64_data_out[5];
							romL_we <= c64_data_out[5];
							if(c64_data_out[5]) begin
								bank_lo <= 0;
								IOF_bank<= 0;
							end
						end
					end
				end
			end

		// Final Cart III - (64k 4x16k banks)
		// all banks @ $8000-$BFFF - switching by $DFFF
		3:	begin
				if(!init_n) begin
					init_n <= 1;
					game_overide <= 0;
					exrom_overide<= 0;
					cart_disable <= 0;
					bank_lo <= 0;
					bank_hi <= 1;
					IOE_ena <= 1;
					IOE_bank<= 0;
					IOF_ena <= 1;
					IOF_bank<= 0;
				end
				else if(!cart_disable) begin
					if(iof_wr && &c64_mem_address_in[7:0]) begin
						bank_lo <= {c64_data_out[1:0],1'd0};
						bank_hi <= {c64_data_out[1:0],1'd1};
						IOE_bank<= {c64_data_out[1:0],1'd0};
						IOF_bank<= {c64_data_out[1:0],1'd0};
						exrom_overide <= c64_data_out[4];
						game_overide  <= c64_data_out[5];
						saved_d6 <= c64_data_out[6];
						if(~freeze_key & saved_d6 & ~c64_data_out[6]) nmi <= 1;
						if(c64_data_out[6]) allow_freeze <= 1;
						cart_disable <= c64_data_out[7];
					end
				end
				if(freeze_ack) begin
					cart_disable <= 0;
					game_overide <= 0;
					allow_freeze <= 0;
				end
			end

		// Simons Basic - (game=0, exrom=0, 2 banks by 8k)
		// Read to IOE switches 8k config
		// Write to IOE switches 16k config
		4: begin
				if(!init_n) begin
					init_n <= 1;
					exrom_overide <= 0;
					game_overide <= 0;
					bank_lo <= 0;
					bank_hi <= 1;
				end
				if(ioe_wr) game_overide <= 0;
				if(ioe_rd) game_overide <= 1;
			end

		// Ocean Type 1 - (game=0, exrom=0, 128k,256k or 512k in 8k banks)
		// BANK is written to lower 6 bits of $DE00 - bit 8 is always set
		// best to mirror banks at $8000 and $A000
		5:	begin
				exrom_overide <= 0;
				game_overide  <= 0;
				if(ioe_wr) begin
					bank_lo <= c64_data_out[5:0];
					bank_hi <= c64_data_out[5:0];
				end
			end

		// PowerPlay, FunPlay
		7:	begin
				if(~init_n) begin
					init_n <= 1;
					exrom_overide <= 0;
					game_overide  <= 1;
				end

				if(ioe_wr) begin
					bank_lo <= {c64_data_out[0],c64_data_out[5:3]};
					if({c64_data_out[7:6],c64_data_out[2:1]} == 'b1011) exrom_overide <= 1;
					if({c64_data_out[7:6],c64_data_out[2:1]} == 'b0000) exrom_overide <= 0;
				end
			end

		// "Super Games"
		8:	begin
				if(~init_n) begin
					init_n <= 1;
					exrom_overide <= 0;
					game_overide  <= 0;
					bank_lo <= 0;
					bank_hi <= 1;
				end

				if(~cart_disable & iof_wr) begin
					bank_lo <= {c64_data_out[1:0],1'd0};
					bank_hi <= {c64_data_out[1:0],1'd1};
					game_overide  <= c64_data_out[2];
					exrom_overide <= c64_data_out[2];
					cart_disable  <= c64_data_out[3];
				end
			end

		// Epyx Fastload - (game=1, exrom=0, 8k bank)
		// any access to romL or $DE00 charges a capacitor
		// Once discharged the exrom drops to ON disabling cart
		10: begin
				if(!init_n) count_ena <= 0;
				if(IOE || romL) count_ena <= 1;

				if(!init_n || IOE || romL) begin
					init_n <= 1;
					game_overide  <= 1;
					exrom_overide <= 0;
					count <= 16384;
					IOF_ena <= 1;
					IOF_bank<= 0;
				end
				else
				if(count_ena) begin
					if(count) count <= count - 1'd1;
					else exrom_overide <= 1;
				end
			end

		// FINAL CARTRIDGE 1,2
		// 16k rom - IOE turns off rom / IOF turns rom on
		13: begin
				if(!init_n) begin
					init_n <= 1;

					bank_lo <= 0;
					bank_hi <= 1;
					game_overide  <= 0;
					exrom_overide <= 0;

					// Last 2 pages visible at IOE / IOF
					IOE_bank <= 0;
					IOF_bank <= 0;
					IOE_ena <= 1;
					IOF_ena <= 1;
				end

				if(freeze_ack) begin
					game_overide <= 0;
					allow_freeze <= 0;
				end

				if(IOE) begin
					game_overide  <= 1;
					exrom_overide <= 1;
					allow_freeze  <= 1;
				end

				if(IOF) begin
					game_overide  <= 0;
					exrom_overide <= 0;
				end
			end

		// C64GS - (game=1, exrom=0, 64 banks by 8k)
		// 8k config
		// Reading from IOE ($DE00 $DEFF) switches to bank 0
		15: begin
				game_overide  <= 1;
				exrom_overide <= 0;
				if(ioe_rd) bank_lo <= 0;
				if(ioe_wr) bank_lo <= c64_mem_address_in[5:0];
			end

		// Dinamic - (game=1, exrom=0, 16 banks by 8k)
		17: begin
				game_overide  <= 1;
				exrom_overide <= 0;
				if(ioe_rd) bank_lo <= c64_mem_address_in[3:0];
			end

		// Zaxxon, Super Zaxxon (game=0, exrom=0 - 4Kb + 2x8KB)
		18: begin
				mask_lo <= 'hFFF;
				game_overide  <= 0;
				exrom_overide <= 0;
				if(romL & mem_ce & ~c64_mem_address_in[12]) bank_hi <= 1;
				if(romL & mem_ce &  c64_mem_address_in[12]) bank_hi <= 2;
			end

		// Magic Desk - (game=1, exrom=0 = 4/8/16 8k banks)
		19: begin
				if(!init_n) begin
					init_n <= 1;
					game_overide  <= 1;
					exrom_overide <= 0;
					bank_lo <= 0;
				end

				if(ioe_wr) begin
					bank_lo <= c64_data_out[3:0];
					exrom_overide <= c64_data_out[7];
				end
			end

		// Super Snapshot v5 -(64k rom 8*8k banks/4*16k banks, 32k ram 4*8k banks)
		20: begin
				if(!init_n || freeze_ack) begin
					init_n  <= 1;
					romL_we <= 1;
					bank_lo <= 0;
					bank_hi <= 1;
					game_overide  <= 0;
					exrom_overide <= 1;
					IOE_bank <= 0;
					IOE_ena  <= 1;
					cart_disable <= 0;
				end
				else
				if(~cart_disable & ioe_wr) begin
					game_overide <=  c64_data_out[0] | c64_data_out[3];
					exrom_overide<= ~c64_data_out[1] | c64_data_out[3];
					bank_lo <= {c64_data_out[4], c64_data_out[2], 1'b0};
					bank_hi <= {c64_data_out[4], c64_data_out[2], 1'b1};
					IOE_bank<= {c64_data_out[4], c64_data_out[2], 1'b0};
					cart_disable <= c64_data_out[3];
					IOE_ena <= ~c64_data_out[3];

					//RAM overlay
					if(~c64_data_out[1]) bank_lo <= {c64_data_out[4], c64_data_out[2]};
					romL_we <= ~c64_data_out[1];
				end
		end

		// Comal80 - (game=0, exrom=0, 4 banks by 16k)
		21: begin
			if(!init_n) begin
				init_n <= 1;
				bank_lo <= 0;
				bank_hi <= 1;
				game_overide  <= 0;
				exrom_overide <= 0;
			end
			if(ioe_wr) begin
				case(c64_data_out[7:5])
					'b010:
						begin
							exrom_overide <= 0;
							game_overide  <= 1;
						end
					'b111:
						begin
							exrom_overide <= 1;
							game_overide  <= 1;
						end
					default:
						begin
							exrom_overide <= 0;
							game_overide  <= 0;
						end
				endcase

				bank_lo <= {c64_data_out[1:0], 1'b0};
				bank_hi <= {c64_data_out[1:0], 1'b1};
			end
		end

		// Mikro Assembler - (game=1, exrom=0, 8k)
		28: begin
				game_overide  <= 1;
				exrom_overide <= 0;
				IOE_bank <= 0;
				IOE_ena  <= 1;
				IOF_bank <= 0;
				IOF_ena  <= 1;
			end

		// EASYFLASH - 1mb 128x8k/64x16k, XBank format(33) looks the same
		// upd: original Easyflash(32) boots in ultimax mode.
		// Only one XBank(33) cart has been found: soulless-xbank. It doesn't boot in ultimax mode.
		32,
		33: begin
				if(!init_n) begin
					init_n <= 1;
					IOF_bank<= 0;
					IOF_ena <= 1;
					IOF_wr_ena <= 1;
					exrom_overide <= (cart_id==32);
					game_overide  <= 0;
					bank_lo <= lobanks[0];
					bank_hi <= hibanks[0];
				end

				if(ioe_wr) begin
					if(c64_mem_address_in[1]) begin
						game_overide  <= ~c64_data_out[0] & c64_data_out[2]; //assume jumper in boot position bit2=0 -> game=0
						exrom_overide <= ~c64_data_out[1];
					end
					else begin
						bank_lo <= lobanks[c64_data_out[5:0]];
						bank_hi <= hibanks[c64_data_out[5:0]];
					end
				end
			end

		// Kingsoft Business Basic
		54: begin
				max_ram <= 1;

				if(!init_n || ioe_rd) begin
					init_n <= 1;
					game_overide  <= 0;
					exrom_overide <= 0;
					bank_lo <= 0;
					bank_hi <= 1;
				end

				if(ioe_wr) begin
					game_overide  <= 0;
					exrom_overide <= 1;
					bank_lo <= 0;
					bank_hi <= 2;
				end
			end

		// RGCD (game=1, exrom=0, 8 banks by 8k)
		57: begin
				if(!init_n) begin
					init_n <= 1;
					game_overide  <= 1;
					exrom_overide <= 0;
					bank_lo <= 0;
				end

				if(~cart_disable & ioe_wr) begin
					bank_lo <= c64_data_out[2:0];
					if(c64_data_out[3]) begin
						cart_disable  <= 1;
						game_overide  <= 1;
						exrom_overide <= 1;
					end
				end
			end
	endcase
end

// ************************************************************************************************************
// ****** Address handling - Redirection to SDRAM CRT file
// ************************************************************************************************************

wire ioe_ce = (IOE && (mem_write ? IOE_wr_ena : IOE_ena));
wire iof_ce = (IOF && (mem_write ? IOF_wr_ena : IOF_ena));

assign mem_ce_out = mem_ce | ioe_ce | iof_ce;

//RAM banks are remapped to 64K-128K space
always @(*) begin
	addr_out = c64_mem_address_in;
	if(cart_attached) begin
		if(romH & (romH_we | ~mem_write)) addr_out[24:13] = romH_we ? {1'b1, bank_hi[2:0]} : {1'b1, bank_hi};
		if(romL & (romL_we | ~mem_write)) begin
			addr_out[24:13] = romL_we ? {1'b1, bank_lo[2:0]} : {1'b1, bank_lo};
			addr_out[12:0]  = c64_mem_address_in[12:0] & mask_lo;
		end

		if(ioe_ce) addr_out[24:13] = IOE_wr_ena ? {1'b1, IOE_bank[2:0]} : {1'b1, IOE_bank}; // read/write to DExx
		if(iof_ce) addr_out[24:13] = IOF_wr_ena ? {1'b1, IOF_bank[2:0]} : {1'b1, IOF_bank}; // read/write to DFxx

		if(UMAXromH && !mem_write) addr_out[24:12] = {1'b1, bank_hi, 1'b1}; // ULTIMAX CharROM
	end
end

endmodule
