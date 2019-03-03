//
// fdc1772.v
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

// TODO: 
// - Don't directly set track register but control it with the step commands
// - 30ms settle time after step before data can be read
// - some parts are hard coded for archie floppy format (not dos)

module fdc1772 (
		input 	      clkcpu, // system cpu clock.
		input 	      clk8m_en,

		// external set signals 
		input [3:0]   floppy_drive,
		input 	      floppy_side, 
		input 	      floppy_motor,
		input 	      floppy_inuse,
		input 	      floppy_density,
		input 	      floppy_reset,

		// interrupts
		output 	      floppy_firq, // floppy fast irq
		output 	      floppy_drq, // data request interrupt

		// "wishbone bus" the ack is externally generated currently. 
		input 	      wb_cyc,
		input 	      wb_stb,
		input 	      wb_we,

		input [15:2]  wb_adr, // la
		input [7:0]   wb_dat_i, // bd
		output reg [7:0]  wb_dat_o, // bd 

		// place any signals that need to be passed up to the top after here.
		input      [1:0] img_mounted, // signaling that new image has been mounted
		input            img_wp,      // write protect. latched at img_mounted
		input     [31:0] img_size,    // size of image in bytes
		output    [31:0] sd_lba,
		output reg [1:0] sd_rd,
		output reg [1:0] sd_wr,
		input            sd_ack,
		input      [8:0] sd_buff_addr,
		input      [7:0] sd_dout,
		output     [7:0] sd_din,
		input            sd_dout_strobe,
		input            sd_din_strobe
);

localparam CLK = 32000000;
localparam CLK_EN = 8000000;

// -------------------------------------------------------------------------
// --------------------- IO controller status handling ---------------------
// -------------------------------------------------------------------------

assign sd_lba = { 4'd10*track[6:0] + (floppy_side ? 0 : 4'd5) + sector[3:0], s_odd };

reg [1:0] floppy_ready = 0;
reg [1:0] floppy_wp = 1;

wire         floppy_present = (floppy_drive == 4'b1110)?floppy_ready[0]:
	                          (floppy_drive == 4'b1101)?floppy_ready[1]:0;

wire floppy_write_protected = (floppy_drive == 4'b1110)?floppy_wp[0]:
	                          (floppy_drive == 4'b1101)?floppy_wp[1]:1;

always @(posedge clkcpu) begin
	reg [1:0] img_mountedD;

	img_mountedD <= img_mounted;
	if (~img_mountedD[0] && img_mounted[0]) begin
		floppy_ready[0] <= |img_size;
		floppy_wp[0] <= img_wp;
	end
	if (~img_mountedD[1] && img_mounted[1]) begin
		floppy_ready[1] <= |img_size;
		floppy_wp[1] <= img_wp;
	end
end

// -------------------------------------------------------------------------
// ---------------------------- IRQ/DRQ handling ---------------------------
// -------------------------------------------------------------------------
reg irq;
reg irq_set;

// floppy_reset and read of status register clears irq
reg cpu_read_status;
always @(posedge clkcpu)
  cpu_read_status <= wb_stb && wb_cyc && !wb_we && 
		     (wb_adr[3:2] == FDC_REG_CMDSTATUS);
   
wire irq_clr = !floppy_reset || cpu_read_status;
   
always @(posedge clkcpu or posedge irq_clr) begin
	reg irq_setD;

	if(irq_clr) irq <= 1'b0;
	else begin
		irq_setD <= irq_set;
		if(~irq_setD & irq_set) irq <= 1'b1;
	end
end
   
assign floppy_firq = irq;
   
reg drq;
reg drq_set;

reg cpu_rw_data;
always @(posedge clkcpu)
  cpu_rw_data <= wb_stb && wb_cyc && (wb_adr[3:2] == FDC_REG_DATA);

wire drq_clr = !floppy_reset || cpu_rw_data;

always @(posedge clkcpu or posedge drq_clr) begin
   if(drq_clr) drq <= 1'b0;
   else if(drq_set) drq <= 1'b1;
end

assign floppy_drq = drq;

// -------------------------------------------------------------------------
// -------------------- virtual floppy drive mechanics ---------------------
// -------------------------------------------------------------------------

// -------------------------------------------------------------------------
// ------------------------------- floppy 0 --------------------------------
// -------------------------------------------------------------------------
wire fd0_index;
wire fd0_ready;
wire [6:0] fd0_track;
wire [3:0] fd0_sector;
wire fd0_sector_hdr;
wire fd0_sector_data;
wire fd0_dclk;

floppy #(.SYS_CLK(CLK)) floppy0 (
		.clk         ( clkcpu          ),

		// control signals into floppy
		.select      (!floppy_drive[0] ),
		.motor_on    ( motor_on        ),
		.step_in     ( step_in         ),
		.step_out    ( step_out        ),

		// status signals generated by floppy
		.dclk_en     ( fd0_dclk        ),
		.track       ( fd0_track       ),
		.sector      ( fd0_sector      ),
		.sector_hdr  ( fd0_sector_hdr  ),
	 	.sector_data ( fd0_sector_data ),
		.ready       ( fd0_ready       ),
		.index       ( fd0_index       )
);

// -------------------------------------------------------------------------
// ------------------------------- floppy 1 --------------------------------
// -------------------------------------------------------------------------
wire fd1_index;
wire fd1_ready;
wire [6:0] fd1_track;
wire [3:0] fd1_sector;
wire fd1_sector_hdr;
wire fd1_sector_data;
wire fd1_dclk;

floppy #(.SYS_CLK(CLK)) floppy1 (
		.clk         ( clkcpu          ),

		// control signals into floppy
		.select      (!floppy_drive[1] ),
		.motor_on    ( motor_on        ),
		.step_in     ( step_in         ),
		.step_out    ( step_out        ),

		// status signals generated by floppy
		.dclk_en     ( fd1_dclk        ),
		.track       ( fd1_track       ),
		.sector      ( fd1_sector      ),
		.sector_hdr  ( fd1_sector_hdr  ),
	 	.sector_data ( fd1_sector_data ),
		.ready       ( fd1_ready       ),
		.index       ( fd1_index       )
);

// -------------------------------------------------------------------------
// ------------------------------- floppy 2 --------------------------------
// -------------------------------------------------------------------------
wire fd2_index;
wire fd2_ready;
wire [6:0] fd2_track;
wire [3:0] fd2_sector;
wire fd2_sector_hdr;
wire fd2_sector_data;
wire fd2_dclk;

floppy #(.SYS_CLK(CLK)) floppy2 (
		.clk         ( clkcpu          ),

		// control signals into floppy
		.select      (!floppy_drive[2] ),
		.motor_on    ( motor_on        ),
		.step_in     ( step_in         ),
		.step_out    ( step_out        ),

		// status signals generated by floppy
		.dclk_en     ( fd2_dclk        ),
		.track       ( fd2_track       ),
		.sector      ( fd2_sector      ),
		.sector_hdr  ( fd2_sector_hdr  ),
	 	.sector_data ( fd2_sector_data ),
		.ready       ( fd2_ready       ),
		.index       ( fd2_index       )
);

// -------------------------------------------------------------------------
// ------------------------------- floppy 3 --------------------------------
// -------------------------------------------------------------------------
wire fd3_index;
wire fd3_ready;
wire [6:0] fd3_track;
wire [3:0] fd3_sector;
wire fd3_sector_hdr;
wire fd3_sector_data;
wire fd3_dclk;

floppy #(.SYS_CLK(CLK)) floppy3 (
		.clk         ( clkcpu          ),

		// control signals into floppy
		.select      (!floppy_drive[3] ),
		.motor_on    ( motor_on        ),
		.step_in     ( step_in         ),
		.step_out    ( step_out        ),

		// status signals generated by floppy
		.dclk_en     ( fd3_dclk        ),
		.track       ( fd3_track       ),
		.sector      ( fd3_sector      ),
		.sector_hdr  ( fd3_sector_hdr  ),
	 	.sector_data ( fd3_sector_data ),
		.ready       ( fd3_ready       ),
		.index       ( fd3_index       )
);

// -------------------------------------------------------------------------
// ----------------------------- floppy demux ------------------------------
// -------------------------------------------------------------------------

wire fd_index = 			(!floppy_drive[0])?fd0_index:
								(!floppy_drive[1])?fd1_index:
								(!floppy_drive[2])?fd2_index:
								(!floppy_drive[3])?fd3_index:
								1'b0;

wire fd_ready = 			(!floppy_drive[0])?fd0_ready:
								(!floppy_drive[1])?fd1_ready:
								(!floppy_drive[2])?fd2_ready:
								(!floppy_drive[3])?fd3_ready:
								1'b0;

wire [6:0] fd_track = 	(!floppy_drive[0])?fd0_track:
								(!floppy_drive[1])?fd1_track:
								(!floppy_drive[2])?fd2_track:
								(!floppy_drive[3])?fd3_track:
								7'd0;

wire [3:0] fd_sector = 	(!floppy_drive[0])?fd0_sector:
								(!floppy_drive[1])?fd1_sector:
								(!floppy_drive[2])?fd2_sector:
								(!floppy_drive[3])?fd3_sector:
								4'd0;

wire fd_sector_hdr = 	(!floppy_drive[0])?fd0_sector_hdr:
								(!floppy_drive[1])?fd1_sector_hdr:
								(!floppy_drive[2])?fd2_sector_hdr:
								(!floppy_drive[3])?fd3_sector_hdr:
								1'b0;

wire fd_sector_data = 	(!floppy_drive[0])?fd0_sector_data:
								(!floppy_drive[1])?fd1_sector_data:
								(!floppy_drive[2])?fd2_sector_data:
								(!floppy_drive[3])?fd3_sector_data:
								1'b0;

wire fd_dclk_en =		(!floppy_drive[0])?fd0_dclk:
								(!floppy_drive[1])?fd1_dclk:
								(!floppy_drive[2])?fd2_dclk:
								(!floppy_drive[3])?fd3_dclk:
								1'b0;

wire fd_track0 = (fd_track == 0);

// -------------------------------------------------------------------------
// ----------------------- internal state machines -------------------------
// -------------------------------------------------------------------------

// --------------------------- Motor handling ------------------------------
   
// if motor is off and type 1 command with "spin up sequnce" bit 3 set
// is received then the command is executed after the motor has
// reached full speed for 5 rotations (800ms spin-up time + 5*200ms =
// 1.8sec) If the floppy is idle for 10 rotations (2 sec) then the
// motor is switched off again
localparam MOTOR_IDLE_COUNTER = 10;
reg [3:0] motor_timeout_index;
reg indexD;
reg busy;
reg step_in, step_out;
reg [3:0] motor_spin_up_sequence;

// consider spin up done either if the motor is not supposed to spin at all or
// if it's supposed to run and has left the spin up sequence
wire motor_spin_up_done = (!motor_on) || (motor_on && (motor_spin_up_sequence == 0));

// ---------------------------- step handling ------------------------------

localparam STEP_PULSE_LEN = 1;
localparam STEP_PULSE_CLKS = (STEP_PULSE_LEN * CLK_EN)/1000;
reg [15:0] step_pulse_cnt;

// the step rate is only valid for command type I
wire [15:0] step_rate_clk = 
	   (cmd[1:0]==2'b00)?(2*CLK_EN/1000-1):    // 2ms
	   (cmd[1:0]==2'b01)?(3*CLK_EN/1000-1):    // 3ms
	   (cmd[1:0]==2'b10)?(5*CLK_EN/1000-1):    // 5ms
	   (6*CLK_EN/1000-1);                      // 6ms
	   
reg [15:0] step_rate_cnt;

// flag indicating that a "step" is in progress
wire step_busy = (step_rate_cnt != 0);
reg [7:0] step_to;

always @(posedge clkcpu) begin
   reg data_transfer_can_start;

   if(!floppy_reset) begin
      motor_on <= 1'b0;
      busy <= 1'b0;
      step_in <= 1'b0;
      step_out <= 1'b0;
      irq_set <= 1'b0;
      sd_card_read <= 0;
      sd_card_write <= 0;
      data_transfer_start <= 1'b0;
      data_transfer_can_start <= 0;
   end else if (clk8m_en) begin
      sd_card_read <= 0;
      sd_card_write <= 0;
      irq_set <= 1'b0;
      data_transfer_start <= 1'b0;

      // disable step signal after 1 msec
      if(step_pulse_cnt != 0) 
	step_pulse_cnt <= step_pulse_cnt - 16'd1;
      else begin
 	 step_in <= 1'b0;
 	 step_out <= 1'b0;
      end
   
      // step rate timer
      if(step_rate_cnt != 0) 
	step_rate_cnt <= step_rate_cnt - 16'd1;

      // just received a new command
      if(cmd_rx) begin
	 busy <= 1'b1;

	 // type I commands can wait for the disk to spin up
	 if(cmd_type_1 && cmd[3] && !motor_on) begin
	    motor_on <= 1'b1;
	    motor_spin_up_sequence <= 6;   // wait for 6 full rotations
	 end

	 // handle "forced interrupt"
	 if(cmd[7:4] == 4'b1101) begin
	    busy <= 1'b0;
	    if(cmd[3]) irq_set <= 1'b1;
	 end
      end

      // execute command if motor is not supposed to be running or
      // wait for motor spinup to finish
      if(busy && motor_spin_up_done && !step_busy) begin

	 // ------------------------ TYPE I -------------------------
	 if(cmd_type_1) begin
	    // all type 1 commands are step commands and step_to has been set
	    if(fd_track == step_to) begin
	       busy <= 1'b0;   // done if reached track 0
	       motor_timeout_index <= MOTOR_IDLE_COUNTER - 1;
	       irq_set <= 1'b1; // emit irq when command done
	    end else begin
	       // do the step
	       if(step_to < fd_track) step_in  <= 1'b1;
	       else                   step_out  <= 1'b1;
	       
	       // update track register
//	       if( (!cmd[6] && !cmd[5]) ||               // restore/seek
//		       ((cmd[6] || cmd[5]) && cmd[4])) begin // step(in/out) with update flag
//		      if(step_to < fd_track) track <= track - 1'd0;
//		      else                   track <= track + 1'd0;
//	       end
		 
	       step_pulse_cnt <= STEP_PULSE_CLKS-1;
	       step_rate_cnt <= step_rate_clk;
	    end
	 end // if (cmd_type_1)

	 // ------------------------ TYPE II -------------------------
	 if(cmd_type_2) begin
		if(!floppy_present) begin
			// no image selected -> send irq immediately
			busy <= 1'b0;
			motor_timeout_index <= MOTOR_IDLE_COUNTER - 1;
			irq_set <= 1'b1; // emit irq when command done
		end else begin
			// read sector
			if(cmd[7:5] == 3'b100) begin
				if (fifo_cpuptr == 0) sd_card_read <= 1;
				// we are busy until the right sector header passes under 
				// the head and the sd-card controller indicates the sector
				// is in the fifo
				if(sd_card_done) data_transfer_can_start <= 1;
				if(fd_ready && fd_sector_hdr && (fd_sector == sector) && data_transfer_can_start) begin
					data_transfer_can_start <= 0;
					data_transfer_start <= 1;
				end

				if(data_transfer_done) begin
					busy <= 1'b0;
					motor_timeout_index <= MOTOR_IDLE_COUNTER - 1;
					irq_set <= 1'b1; // emit irq when command done
				end
			end

			// write sector
			if(cmd[7:5] == 3'b101) begin
				if (fifo_cpuptr == 0) data_transfer_start <= 1'b1;
				if (data_transfer_done) sd_card_write <= 1;
				if (sd_card_done) begin
					busy <= 1'b0;
					motor_timeout_index <= MOTOR_IDLE_COUNTER - 1;
					irq_set <= 1'b1; // emit irq when command done
				end
			end
		end
	end

	 // ------------------------ TYPE III -------------------------
	 if(cmd_type_3) begin
		if(!floppy_present) begin
			// no image selected -> send irq immediately
			busy <= 1'b0; 
			motor_timeout_index <= MOTOR_IDLE_COUNTER - 1;
			irq_set <= 1'b1; // emit irq when command done
		end else begin
			// read address
			if(cmd[7:4] == 4'b1100) begin
				// we are busy until the next setor header passes under the head
				if(fd_ready && fd_sector_hdr)
					data_transfer_start <= 1'b1;

				if(data_transfer_done) begin
					busy <= 1'b0;
					motor_timeout_index <= MOTOR_IDLE_COUNTER - 1;
					irq_set <= 1'b1; // emit irq when command done
				end
			end
		end
	 end
  end
	 
      // stop motor if there was no command for 10 index pulses
      indexD <= fd_index;
      if(indexD && !fd_index) begin
	 // led motor timeout run once fdc is not busy anymore
	 if(!busy) begin
	    if(motor_timeout_index != 0)
	      motor_timeout_index <= motor_timeout_index - 4'd1;
	    else
	      motor_on <= 1'b0;
	 end

	 if(motor_spin_up_sequence != 0)
	   motor_spin_up_sequence <= motor_spin_up_sequence - 4'd1;
      end
   end
end

// floppy delivers data at a floppy generated rate (usually 250kbit/s), so the start and stop
// signals need to be passed forth and back from cpu clock domain to floppy data clock domain
reg data_transfer_start;
reg data_transfer_done;

// ==================================== FIFO ==================================

// 1 kB buffer used to receive a sector as fast as possible from from the io
// controller. The internal transfer afterwards then runs at 250000 Bit/s
reg [10:0] fifo_cpuptr;
reg        s_odd; //odd sector
wire [7:0] fifo_q;

fdc1772_dpram fifo
(
	.clock(clkcpu),

	.address_a({s_odd, sd_buff_addr}),
	.data_a(sd_dout),
	.wren_a(sd_dout_strobe & sd_ack),
	.q_a(sd_din),

	.address_b(fifo_cpuptr),
	.data_b(data_in),
	.wren_b(data_in_strobe),
	.q_b(fifo_q)
);

// ------------------ SD card control ------------------------
localparam SD_IDLE = 0;
localparam SD_READ = 1;
localparam SD_WRITE = 2;

reg [1:0] sd_state;
reg       sd_card_write;
reg       sd_card_read;
reg       sd_card_done;

always @(posedge clkcpu) begin
	reg sd_ackD;
	reg sd_card_readD;
	reg sd_card_writeD;

	sd_card_readD <= sd_card_read;
	sd_card_writeD <= sd_card_write;
	sd_ackD <= sd_ack;
	if (sd_ack) {sd_rd, sd_wr} <= 0;
	if (clk8m_en) sd_card_done <= 0;

	case (sd_state)
	SD_IDLE:
	begin
		s_odd <= 0;
		if (~sd_card_readD & sd_card_read) begin
			sd_rd <= ~{ floppy_drive[1], floppy_drive[0] };
			sd_state <= SD_READ;
		end
		else if (~sd_card_writeD & sd_card_write) begin
			sd_wr <= ~{ floppy_drive[1], floppy_drive[0] };
			sd_state <= SD_WRITE;
		end
	end

	SD_READ:
	begin
		if (sd_ackD & ~sd_ack) begin
			if (s_odd) begin
				sd_state <= SD_IDLE;
				sd_card_done <= 1; // to be on the safe side now, can be issued earlier
			end else begin
				s_odd <= 1;
				sd_rd <= ~{ floppy_drive[1], floppy_drive[0] };
			end
		end
	end

	SD_WRITE:
	begin
		if (sd_ackD & ~sd_ack) begin
			if (s_odd) begin
				sd_state <= SD_IDLE;
				sd_card_done <= 1;
			end else begin
				s_odd <= 1;
				sd_wr <= ~{ floppy_drive[1], floppy_drive[0] };
			end
		end
	end

	default: ;
	endcase
end

// -------------------- CPU data read/write -----------------------

always @(posedge clkcpu) begin
   reg        data_transfer_startD;
   reg [10:0] data_transfer_cnt;

   // reset fifo read pointer on reception of a new command
   if(cmd_rx)
     fifo_cpuptr <= 11'd0;

   drq_set <= 1'b0;
   if (clk8m_en) data_transfer_done <= 0;
   data_transfer_startD <= data_transfer_start;
   // received request to read data
   if(~data_transfer_startD & data_transfer_start) begin

      // read_address command has 6 data bytes
      if(cmd[7:4] == 4'b1100)
			data_transfer_cnt <= 11'd6+11'd1;

      // read/write sector has 1024 data bytes
      if(cmd[7:6] == 2'b10)
			data_transfer_cnt <= 11'd1024+11'd1;
   end

   // write sector data arrived from CPU
   if(cmd[7:5] == 3'b101 && data_in_strobe) fifo_cpuptr <= fifo_cpuptr + 1'd1;

   if(fd_dclk_en) begin
      if(data_transfer_cnt != 0) begin
			if(data_transfer_cnt != 1) begin
				drq_set <= 1'b1;
				
				// read_address
				if(cmd[7:4] == 4'b1100) begin
					case(data_transfer_cnt)
						7: data_out <= fd_track;
						6: data_out <= { 7'b0000000, floppy_side };
						5: data_out <= fd_sector;
						4: data_out <= 8'd3; // TODO: sec size 0=128, 1=256, 2=512, 3=1024
						3: data_out <= 8'ha5;
						2: data_out <= 8'h5a;
					endcase // case (data_read_cnt)
				end
	    
				// read sector
				if(cmd[7:5] == 3'b100) begin
					if(fifo_cpuptr != 11'd1024) begin
						data_out <= fifo_q;
						fifo_cpuptr <= fifo_cpuptr + 11'd1;
					end
				end
			end
	    
			// count down and stop after last byte
			data_transfer_cnt <= data_transfer_cnt - 11'd1;
			if(data_transfer_cnt == 1)
				data_transfer_done <= 1'b1;
		end
   end
end
   
// the status byte
wire [7:0] status = { motor_on, 
		      floppy_write_protected,              // wrprot
		      cmd_type_1?motor_spin_up_done:1'b0,  // data mark
		      !floppy_present,                     // record not found
		      1'b0,                                // crc error
		      cmd_type_1?(fd_track == 0):1'b0,
		      cmd_type_1?~fd_index:floppy_drq,
		      busy } /* synthesis keep */;

reg [7:0] track;
reg [7:0] sector;
reg [7:0] data_in;
reg [7:0] data_out;

reg step_dir;
reg motor_on;

// ---------------------------- command register -----------------------   
reg [7:0] cmd;
wire cmd_type_1 = (cmd[7] == 1'b0);
wire cmd_type_2 = (cmd[7:6] == 2'b10);
wire cmd_type_3 = (cmd[7:5] == 3'b111) || (cmd[7:4] == 4'b1100);
wire cmd_type_4 = (cmd[7:4] == 4'b1101);

localparam FDC_REG_CMDSTATUS    = 0;
localparam FDC_REG_TRACK        = 1;
localparam FDC_REG_SECTOR       = 2;
localparam FDC_REG_DATA         = 3;

// CPU register read
always @(wb_stb, wb_cyc, wb_adr, wb_we) begin
   wb_dat_o = 8'h00;

   if(wb_stb && wb_cyc && !wb_we) begin
      case(wb_adr[3:2])
        FDC_REG_CMDSTATUS: wb_dat_o = status;
        FDC_REG_TRACK:     wb_dat_o = track;
        FDC_REG_SECTOR:    wb_dat_o = sector;
        FDC_REG_DATA:      wb_dat_o = data_out;
      endcase
   end
end

// cpu register write
reg cmd_rx;
reg cmd_rx_i;
reg last_stb;
reg data_in_strobe;

always @(posedge clkcpu) begin
   if(!floppy_reset) begin
      // clear internal registers
      cmd <= 8'h00;
      track <= 8'h00;
      sector <= 8'h00;

      // reset state machines and counters
      cmd_rx_i <= 1'b0;
      cmd_rx <= 1'b0;
      last_stb <= 1'b0;
      data_in_strobe <= 0;
   end else begin
      data_in_strobe <= 0;
      last_stb <= wb_stb;

		// cmd_rx is delayed to make sure all signals (the cmd!) are stable when
		// cmd_rx is evaluated
		cmd_rx <= cmd_rx_i;

      // command reception is ack'd by fdc going busy
      if(busy)
			cmd_rx_i <= 1'b0;

      // only react if stb just raised
      if(!last_stb && wb_stb && wb_cyc && wb_we) begin
			if(wb_adr[3:2] == FDC_REG_CMDSTATUS) begin       // command register
            cmd <= wb_dat_i;
				cmd_rx_i <= 1'b1;
	    
            // ------------- TYPE I commands -------------
            if(wb_dat_i[7:4] == 4'b0000) begin               // RESTORE
					step_to <= 8'd0;
					track <= 8'd0;
            end
            
            if(wb_dat_i[7:4] == 4'b0001) begin               // SEEK
					step_to <= data_in;
					track <= data_in;
            end
            
            if(wb_dat_i[7:5] == 3'b001) begin                // STEP
					step_to <= (step_dir == 1)?(track + 8'd1):(track - 8'd1);
					if(wb_dat_i[4]) track <= (step_dir == 1)?(track + 8'd1):(track - 8'd1);
            end
            
            if(wb_dat_i[7:5] == 3'b010) begin                // STEP-IN
					step_to <= track + 8'd1;
               step_dir <= 1'b1;
					if(wb_dat_i[4]) track <= track + 8'd1;
            end
	    
            if(wb_dat_i[7:5] == 3'b011) begin                // STEP-OUT
					step_to <= track - 8'd1;
               step_dir <= 1'b0;
					if(wb_dat_i[4]) track <= track - 8'd1;
            end
            
            // ------------- TYPE II commands -------------
            if(wb_dat_i[7:5] == 3'b100) begin                // read sector
            end

            if(wb_dat_i[7:5] == 3'b101) begin                // write sector
            end
            
            // ------------- TYPE III commands ------------
            if(wb_dat_i[7:4] == 4'b1100) begin               // read address
				end
	       
            if(wb_dat_i[7:4] == 4'b1110) begin               // read track
				end
            
            if(wb_dat_i[7:4] == 4'b1111) begin               // write track
				end
	       
            // ------------- TYPE IV commands -------------
            if(wb_dat_i[7:4] == 4'b1101) begin               // force intrerupt
            end
         end
	 
         if(wb_adr[3:2] == FDC_REG_TRACK)                    // track register
           track <= wb_dat_i;
         
         if(wb_adr[3:2] == FDC_REG_SECTOR)                   // sector register
           sector <= wb_dat_i;

         if(wb_adr[3:2] == FDC_REG_DATA) begin               // data register
           data_in_strobe <= 1;
           data_in <= wb_dat_i;
         end
      end
   end
end

endmodule

module fdc1772_dpram #(parameter DATAWIDTH=8, ADDRWIDTH=10)
(
        input                   clock,

        input   [ADDRWIDTH-1:0] address_a,
        input   [DATAWIDTH-1:0] data_a,
        input                   wren_a,
        output reg [DATAWIDTH-1:0] q_a,

        input   [ADDRWIDTH-1:0] address_b,
        input   [DATAWIDTH-1:0] data_b,
        input                   wren_b,
        output reg [DATAWIDTH-1:0] q_b
);

reg [DATAWIDTH-1:0] ram[0:(1<<ADDRWIDTH)-1];

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
                ram[address_b] <= data_b;
                q_b <= data_b;
        end else begin
                q_b <= ram[address_b];
        end
end

endmodule
