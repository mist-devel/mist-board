/////////////////////////////////////////////////////////////////////////

// Module reads bytes and writes to proper address in ram.
// Done is asserted when the whole game is loaded.
// This parses iNES headers too.
module GameLoader
(
	input         clk,
	input         reset,
	input         downloading,
	input   [7:0] filetype,
	input         is_bios,
	input   [7:0] indata,
	input         indata_clk,
	input         invert_mirroring,
	output reg [21:0] mem_addr,
	output [7:0]  mem_data,
	output        mem_write,
	output reg    bios_download,
	output [31:0] mapper_flags,
	output reg    busy,
	output reg    done,
	output reg    error,
	output reg    rom_loaded
);

initial begin
	rom_loaded <= 0;
end

reg [7:0] prgsize;
reg [3:0] ctr;
reg [7:0] ines[0:15]; // 16 bytes of iNES header
reg [21:0] bytes_left;

wire [7:0] prgrom = ines[4];	// Number of 16384 byte program ROM pages
wire [7:0] chrrom = ines[5];	// Number of 8192 byte character ROM pages (0 indicates CHR RAM)
wire has_chr_ram = (chrrom == 0);
assign mem_data = (state == S_CLEARRAM || (~copybios && state == S_COPYBIOS)) ? 8'h00 : indata;
assign mem_write = (((bytes_left != 0) && (state == S_LOADPRG || state == S_LOADCHR)
                    || (downloading && (state == S_LOADHEADER || state == S_LOADFDS || state == S_LOADNSFH || state == S_LOADNSFD))) && indata_clk)
                    || ((bytes_left != 0) && ((state == S_CLEARRAM) || (state == S_COPYBIOS) || (state == S_COPYPLAY)) && clearclk == 4'h2);

wire [2:0] prg_size = prgrom <= 1  ? 3'd0 :		// 16KB
                      prgrom <= 2  ? 3'd1 : 		// 32KB
                      prgrom <= 4  ? 3'd2 : 		// 64KB
                      prgrom <= 8  ? 3'd3 : 		// 128KB
                      prgrom <= 16 ? 3'd4 : 		// 256KB
                      prgrom <= 32 ? 3'd5 : 		// 512KB
                      prgrom <= 64 ? 3'd6 : 3'd7;// 1MB/2MB

wire [2:0] chr_size = chrrom <= 1  ? 3'd0 : 		// 8KB
                      chrrom <= 2  ? 3'd1 : 		// 16KB
                      chrrom <= 4  ? 3'd2 : 		// 32KB
                      chrrom <= 8  ? 3'd3 : 		// 64KB
                      chrrom <= 16 ? 3'd4 : 		// 128KB
                      chrrom <= 32 ? 3'd5 : 		// 256KB
                      chrrom <= 64 ? 3'd6 : 3'd7;// 512KB/1MB
  
// detect iNES2.0 compliant header
wire is_nes20 = (ines[7][3:2] == 2'b10);
// differentiate dirty iNES1.0 headers from proper iNES2.0 ones
wire is_dirty = !is_nes20 && ((ines[9][7:1] != 0)
                           || (ines[10] != 0)
                           || (ines[11] != 0)
                           || (ines[12] != 0)
                           || (ines[13] != 0)
                           || (ines[14] != 0)
                           || (ines[15] != 0));

// Read the mapper number
wire [7:0] mapper = {is_dirty ? 4'b0000 : ines[7][7:4], ines[6][7:4]};
wire [7:0] ines2mapper = {is_nes20 ? ines[8] : 8'h00};
wire [3:0] prgram = {is_nes20 ? ines[10][3:0] : 4'h0};
wire       piano = is_nes20 && (ines[15][5:0] == 6'h19);
wire has_saves = ines[6][1];

// ines[6][0] is mirroring
// ines[6][3] is 4 screen mode
// ines[8][7:4] is NES 2.0 submapper
// ines[10][3:0] is NES 2.0 PRG RAM shift size (64 << size)
assign mapper_flags = {1'b0, piano, prgram, has_saves, ines2mapper, ines[6][3], has_chr_ram, ines[6][0] ^ invert_mirroring, chr_size, prg_size, mapper};

reg [3:0] clearclk; //Wait for SDRAM
reg copybios;

typedef enum bit [3:0] { S_LOADHEADER, S_LOADPRG, S_LOADCHR, S_LOADFDS, S_ERROR, S_CLEARRAM, S_COPYBIOS, S_LOADNSFH, S_LOADNSFD, S_COPYPLAY, S_DONE } mystate;
mystate state;

wire type_bios = filetype[0];
wire type_nes = filetype[1];
wire type_fds = filetype[2];
wire type_nsf = filetype[3];

always @(posedge clk) begin
	if (downloading && (type_fds || type_nes || type_nsf))
		rom_loaded <= 1;

	if (reset) begin
		state <= S_LOADHEADER;
		busy <= 0;
		done <= 0;
		ctr <= 0;
		mem_addr <= type_fds ? 22'b11_1100_0000_0000_0001_0000 :
		            type_nsf ? 22'b00_0000_0000_0001_0000_0000   // Address for NSF Header (0x80 bytes)
		            : 22'b00_0000_0000_0000_0000_0000;  // Address for FDS : BIOS/PRG
		bios_download <= 0;
		copybios <= 0;
	end else begin
		case(state)
		// Read 16 bytes of ines header
		S_LOADHEADER:
			if (indata_clk) begin
			  error <= 0;
			  ctr <= ctr + 1'd1;
			  mem_addr <= mem_addr + 1'd1;
			  ines[ctr] <= indata;
			  bytes_left <= {prgrom, 14'b0};
			  if (ctr == 4'b1111) begin
				 // Check the 'NES' header. Also, we don't support trainers.
				 busy <= 1;
				 if ((ines[0] == 8'h4E) && (ines[1] == 8'h45) && (ines[2] == 8'h53) && (ines[3] == 8'h1A) && !ines[6][2]) begin
					mem_addr <= 0;  // Address for PRG
					state <= S_LOADPRG;
				 //FDS
				 end else if ((ines[0] == 8'h46) && (ines[1] == 8'h44) && (ines[2] == 8'h53) && (ines[3] == 8'h1A)) begin
					mem_addr <= 22'b11_1100_0000_0000_0001_0000;  // Address for FDS skip Header
					state <= S_LOADFDS;
					bytes_left <= 21'b1;
				 end else if (type_bios) begin // Bios
					state <= S_LOADFDS;
					mem_addr <= 22'b00_0000_0000_0000_0001_0000;  // Address for BIOS skip Header
					bytes_left <= 21'b1;
					bios_download <= 1;
				 end else if(type_fds) begin // FDS
					state <= S_LOADFDS;
					mem_addr <= 22'b11_1100_0000_0000_0010_0000;  // Address for FDS no Header
					bytes_left <= 21'b1;
				 end else if(type_nsf) begin // NFS
					state <= S_LOADNSFH;
					//mem_addr <= 22'b00_0000_0000_0001_0001_0000;  // Just keep copying
					bytes_left <= 21'h70; // Rest of header
				 end else begin
					state <= S_ERROR;
				 end
			  end
			end
		S_LOADPRG, S_LOADCHR: begin // Read the next |bytes_left| bytes into |mem_addr|
			 if (bytes_left != 0) begin
				if (indata_clk) begin
				  bytes_left <= bytes_left - 1'd1;
				  mem_addr <= mem_addr + 1'd1;
				end
			 end else if (state == S_LOADPRG) begin
				state <= S_LOADCHR;
				mem_addr <= 22'b10_0000_0000_0000_0000_0000; // Address for CHR
				bytes_left <= {1'b0, chrrom, 13'b0};
			 end else if (state == S_LOADCHR) begin
				done <= 1;
				busy <= 0;
			 end
			end
		S_ERROR: begin
				done <= 1;
				error <= 1;
				busy <= 0;
			end
		S_LOADFDS: begin // Read the next |bytes_left| bytes into |mem_addr|
			 if (downloading) begin
				if (indata_clk) begin
				  mem_addr <= mem_addr + 1'd1;
				end
			 end else begin
//				mem_addr <= 22'b11_1000_0000_0000_0000_0000;
//				bytes_left <= 21'h800;
				mem_addr <= 22'b11_1000_0000_0001_0000_0010; // FDS - Clear these two RAM addresses to restart BIOS
				bytes_left <= 21'h2;
				ines[4] <= 8'hFF;//no masking
				ines[5] <= 8'h00;//0x2000
				ines[6] <= 8'h40;
				ines[7] <= 8'h10;
				ines[8] <= 8'h00;
				ines[9] <= 8'h00;
				ines[10] <= 8'h00;
				ines[11] <= 8'h00;
				ines[12] <= 8'h00;
				ines[13] <= 8'h00;
				ines[14] <= 8'h00;
				ines[15] <= 8'h00;
				state <= S_CLEARRAM;
				clearclk <= 4'h0;
				copybios <= ~is_bios; // Don't copybios for bootrom0
			 end
			end
		S_CLEARRAM: begin // Read the next |bytes_left| bytes into |mem_addr|
			 clearclk <= clearclk + 4'h1;
			 if (bytes_left != 21'h0) begin
				if (clearclk == 4'hF) begin
					bytes_left <= bytes_left - 1'd1;
					mem_addr <= mem_addr + 1'd1;
				end
			 end else begin
//				mem_addr <= 22'b00_0000_0000_0000_0000_0000;
//				bytes_left <= 21'h2000;
//				state <= S_COPYBIOS;
				state <= S_DONE;
				clearclk <= 4'h0;
			 end
			end
		S_COPYBIOS: begin // Read the next |bytes_left| bytes into |mem_addr|
			 clearclk <= clearclk + 4'h1;
			 if (bytes_left != 21'h0) begin
				if (clearclk == 4'hF) begin
					bytes_left <= bytes_left - 1'd1;
					mem_addr <= mem_addr + 1'd1;
				end
			 end else begin
				state <= S_DONE;
			 end
			end
		S_LOADNSFH: begin // Read the next |bytes_left| bytes into |mem_addr|
			 if (bytes_left != 0) begin
				if (indata_clk) begin
				  bytes_left <= bytes_left - 1'd1;
				  mem_addr <= mem_addr + 1'd1;
				end
			 end else begin
				state <= S_LOADNSFD;
				//mem_addr <= {22'b01_0000_0000_0000_0000_0000; // Address for NSF Data
				mem_addr <= {10'b01_0000_0000,ines[9][3:0],ines[8]};//_0000_0000_0000; // Address for NSF Data
				bytes_left <= 21'b1;
			 end
			end
		S_LOADNSFD: begin // Read the next |bytes_left| bytes into |mem_addr|
			 if (downloading) begin
				if (indata_clk) begin
				  mem_addr <= mem_addr + 1'd1;
				end
			 end else begin
				mem_addr <= 22'b00_0000_0000_0001_1000_0000; // Address for NSF Player (0x180)
				bytes_left <= 21'h0E80;
				ines[4] <= 8'hFF;//no masking
				ines[5] <= 8'h00;//0x2000
				ines[6] <= 8'hF0;//Use Mapper 31
				ines[7] <= 8'h18;//Use NES 2.0
				ines[8] <= 8'hF0;//Use Submapper 15
				ines[9] <= 8'h00;
				ines[10] <= 8'h00;
				ines[11] <= 8'h00;
				ines[12] <= 8'h00;
				ines[13] <= 8'h00;
				ines[14] <= 8'h00;
				ines[15] <= 8'h00;
				state <= S_COPYPLAY;
				clearclk <= 4'h0;
			 end
			end
		S_COPYPLAY: begin // Read the next |bytes_left| bytes into |mem_addr|
			 clearclk <= clearclk + 4'h1;
			 if (bytes_left != 21'h0) begin
				if (clearclk == 4'hF) begin
					bytes_left <= bytes_left - 1'd1;
					mem_addr <= mem_addr + 1'd1;
				end
			 end else begin
				state <= S_DONE;
			 end
			end
		S_DONE: begin // Read the next |bytes_left| bytes into |mem_addr|
			 done <= 1;
			 busy <= 0;
			 bios_download <= 0;
			end
		endcase
	end
end
endmodule
