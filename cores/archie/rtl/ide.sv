//
// ide.sv
//
// Copyright (c) 2019 György Szombathelyi
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

module ide (
	input             clk, // system clock.
	input             reset,

	input             ide_sel,
	input             ide_we,
	input       [2:0] ide_reg,
	input      [15:0] ide_dat_i,
	output reg [15:0] ide_dat_o,

	// place any signals that need to be passed up to the top after here.
	output reg        ide_req,
	input             ide_err,
	input             ide_ack,

	input       [2:0] ide_reg_o_adr,
	output reg  [7:0] ide_reg_o,
	input             ide_reg_we,
	input       [2:0] ide_reg_i_adr,
	input       [7:0] ide_reg_i,

	input       [8:0] ide_data_addr,
	output      [7:0] ide_data_o,
	input       [7:0] ide_data_i,
	input             ide_data_rd,
	input             ide_data_we
);

assign ide_req = ide_cmd_req | ide_sector_req;

reg [7:0] taskfile[8];
reg [7:0] status;

// read from Task File Registers
always @(*) begin
	reg [7:0] ide_dat_b;
	//cpu read
	ide_dat_b = (ide_reg == 3'd7) ? { status[7:1], ide_err } : taskfile[ide_reg];
	ide_dat_o = 16'hFFFF;
	if (ide_sel && !ide_we) begin
		ide_dat_o = (ide_reg == 3'd0) ? data_out : { ide_dat_b, ide_dat_b };
	end

	// IO controller read
	ide_reg_o  = taskfile[ide_reg_o_adr];
end

reg ide_cmd_req;
// write to Task File Registers
always @(posedge clk) begin
	ide_cmd_req <= 0;
	// cpu write
	if (ide_sel && ide_we) begin
		taskfile[ide_reg] <= ide_dat_i[7:0];
		// writing to the command register triggers the IO controller
		if (ide_reg == 3'd7) ide_cmd_req <= 1;
	end

	// IO controller write
	if (ide_reg_we) taskfile[ide_reg_i_adr] <= ide_reg_i;
end

reg ide_sector_req;

// status register handling
always @(posedge clk) begin
	reg [7:0] sector_count;

	if (reset) begin
		status <= 8'h48;
		ide_sector_req <= 0;
		sector_count <= 8'd1;
	end else begin
		// write to command register starts the execution
		if (ide_sel && ide_we && ide_reg == 3'd7) begin
			sector_count <= taskfile[2];
			case (taskfile[7])
				8'h30, 8'hc5: status <= 8'h08; // request data
				default: status <= 8'h80; // busy
			endcase
		end

		if (ide_ack) begin
			case (taskfile[7])
				8'hec : status <= 8'h08; // ready to transfer
				8'h20, 8'h30, 8'hc4, 8'hc5: ;
				default: status <= 8'h40; // ready
			endcase
		end

		// sector buffer - IO controller side
		if ((ide_data_rd | ide_data_we) & ide_data_addr == 9'h1ff) status <= 8'h08; // sector buffer consumed/filled, ready to transfer
		if (ide_data_rd | ide_data_we) ide_sector_req <= 0;

		// sector buffer - CPU side
		if (ide_sel_d && ~ide_sel && ide_reg == 3'd0 && data_addr == 8'hff) begin
			status <= 8'h40; // ready
			case (taskfile[7])
				8'h20, 8'hc4: // reads
				begin
					sector_count <= sector_count - 1'd1;
					if (sector_count != 1) ide_sector_req <= 1; // request the next sector
				end
				8'h30, 8'hc5:
				begin
					ide_sector_req <= 1; // write, signals the write buffer is ready
					status <= 8'h80; // busy
				end
				default: ;
			endcase

		end
	end
end

reg   [7:0] data_addr;
wire [15:0] data_out;
reg         ide_sel_d;

// read/write data register
always @(posedge clk) begin
	ide_sel_d <= ide_sel;
	if (ide_sel && ide_we && ide_reg == 3'd7) data_addr <= 0;
	if (ide_sel_d && ~ide_sel && ide_reg == 3'd0) data_addr <= data_addr + 1'd1;
end

// mixed-width sector buffer
ide_dpram ide_databuf (
	.clock     ( clk            ),

	.address_a ( data_addr      ),
	.data_a    ( ide_dat_i      ),
	.wren_a    ( ide_sel && ide_we && ide_reg == 3'd0 ),
	.q_a       ( data_out       ),

	.address_b ( ide_data_addr  ),
	.data_b    ( ide_data_i     ),
	.wren_b    ( ide_data_we    ),
	.q_b       ( ide_data_o     )
);

endmodule


module ide_dpram
(
	input             clock,

	input       [7:0] address_a,
	input      [15:0] data_a,
	input             wren_a,
	output reg [15:0] q_a,

	input       [8:0] address_b,
	input       [7:0] data_b,
	input             wren_b,
	output reg  [7:0] q_b
);

reg [1:0][7:0] ram[256];

always @(posedge clock) begin
	if(wren_a) begin
		ram[address_a] <= data_a;
		q_a <= data_a;
	end else begin
		q_a <= ram[address_a];
	end
end

always @(posedge clock) begin
	if(wren_b) begin
		ram[address_b[8:1]][address_b[0]] <= data_b;
		q_b <= data_b;
	end else begin
		q_b <= ram[address_b[8:1]][address_b[0]];
	end
end

endmodule
