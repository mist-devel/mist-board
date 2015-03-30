// fdc.v
//
// Atari ST floppy implementation for the MIST baord
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
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

module fdc (
	    // clocks and system interface
	input 		 clk,
	input 		 reset,

	    // write protection of currently selected floppy
	input [1:0] 	 drv_sel,
	input 		 drv_side,
	input 		 wr_prot,
	    
	input 		 dma_ack,
	input [2:0] 	 status_sel,
	output [7:0]     status_byte,

	    // cpu interface
        input [1:0] 	 cpu_addr,
        input 		 cpu_sel,
        input 		 cpu_rw,
        input [7:0] 	 cpu_din,
        output [7:0] cpu_dout,

	output reg 	 irq		 
);

// fdc_busy is a counter. counts down from 2 to 0. stays at 3 since that
// means that the fdc is waiting for the arm io controller
localparam STATE_IDLE     = 2'd0;
localparam STATE_IRQ      = 2'd1;
localparam STATE_INT_WAIT = 2'd2;
localparam STATE_IO_WAIT  = 2'd3;

reg [1:0] state;  // fdc busy state

// the fdc registers
reg [7:0] cmd;     // write only
reg [7:0] track;
reg [7:0] sector;
reg [7:0] data;

// fdc status as reported to the io controller
assign status_byte =
    (status_sel == 0)?cmd:
    (status_sel == 1)?track:
    (status_sel == 2)?sector:
    (status_sel == 3)?8'h00: // data:
    (status_sel == 4)?{ 4'b0000, drv_sel, drv_side, state == STATE_IO_WAIT }:
    8'h00;

reg step_dir;

reg [31:0] delay;

wire cmd_type_1 = (cmd[7] == 1'b0);
wire cmd_type_2 = (cmd[7:6] == 2'b10);

// ---------------- floppy motor simulation -------------

// timer to simulate motor-on. This runs for x/8000000 seconds after each command
reg motor_start;
reg [31:0] motor_on_counter;
wire motor_on = (motor_on_counter != 0);

// motor_on_counter > 16000000 means the motor is spinning up
wire motor_spin_up_done = motor_on && (motor_on_counter <= 16000000);

always @(posedge clk or posedge motor_start) begin
   if(motor_start)
     // motor runs for 2 seconds if it was already on. it rus for one
     // more second if if wasn't on yet (spin up)
     motor_on_counter <= motor_on?32'd16000000:32'd24000000;
   else begin
      // let "motor" run
      if(motor_on_counter != 0)
	motor_on_counter <= motor_on_counter - 32'd1;
   end
end
		
// -------------- index pulse generation ----------------

// floppy rotates at 300rpm = 5rps -> generate 5 index pulses per second
wire index_pulse = index_pulse_cnt > 32'd1500000;  // 1/16 rotation
reg [31:0] index_pulse_cnt;
always @(posedge clk) begin
   if(!motor_on)
     index_pulse_cnt <= 32'd0;
   else begin
      if(index_pulse_cnt != 0)
			index_pulse_cnt <= index_pulse_cnt - 32'd1;
      else
			index_pulse_cnt <= 32'd1600000;  // 8000000/5
   end
end

// status byte returned by the fdc when reading register 0
wire [7:0] status = { 
  motor_on,
  wr_prot,
  cmd_type_1?motor_spin_up_done:1'b0,
  2'b00 /* track not found/crc err */, 
  cmd_type_1?(track == 0):1'b0,
  cmd_type_1?index_pulse:(state!=STATE_IDLE),
  state != STATE_IDLE 
};

// CPU register read
assign cpu_dout = 
	(cpu_sel && cpu_rw)?(
		(cpu_addr == 0)?status:
		(cpu_addr == 1)?track:
		(cpu_addr == 2)?sector:
		data):8'h00;

// CPU register write
always @(negedge clk or posedge reset) begin
   if(reset) begin
      // clear internal registers
      cmd <= 8'h00;
      track <= 8'h00;
      sector <= 8'h00;
      data <= 8'h00;

      // reset state machines and counters
      state <= STATE_IDLE;
      irq <= 1'b0;
      motor_start <= 1'b0;
      delay <= 32'd0;

   end else begin
      motor_start <= 1'b0;

      // DMA transfer has been ack'd by io controller
      if(dma_ack) begin
			// fdc waiting for io controller
			if(state == STATE_IO_WAIT)
				state <= STATE_IRQ;  // jump to end of busy phase
      end
      
      // fdc may be waiting internally (e.g. for step completion)
      if(state == STATE_INT_WAIT) begin
			// count down and go into irq state if done
			if(delay != 0)
				delay <= delay - 32'd1;
			else
				state <= STATE_IRQ;
		end
			
		// fdc is ending busy phase
		if(state == STATE_IRQ) begin
			irq <= 1'b1;
			state <= STATE_IDLE;
		end

		// cpu is reading status register or writing command register -> clear fdc irq
		if(cpu_sel && (cpu_addr == 0))
			irq <= 1'b0;
	 
		if(cpu_sel && !cpu_rw) begin
			// fdc register write
			if(cpu_addr == 0) begin       // command register
				cmd <= cpu_din;
				state <= STATE_INT_WAIT;
				delay <= 31'd0;

				// all TYPE I and TYPE II commands start the motor
				if((cpu_din[7] == 1'b0) || (cpu_din[7:6] == 2'b10))
					motor_start <= 1'b1;
	    
				// ------------- TYPE I commands -------------
				if(cpu_din[7:4] == 4'b0000) begin  	        // RESTORE
					track <= 8'd0;
					delay <= 31'd200000;		        // 25ms delay
				end
	    
				if(cpu_din[7:4] == 4'b0001) begin  	        // SEEK
					track <= data;
					delay <= 31'd200000;			// 25ms delay
				end
	    
				if(cpu_din[7:5] == 3'b001) begin		// STEP
					delay <= 31'd20000;			// 2.5ms delay
					if(cpu_din[4])                           // update flag
						track <= (step_dir == 1)?(track + 8'd1):(track - 8'd1);
				end
	    
				if(cpu_din[7:5] == 3'b010) begin            // STEP-IN
					delay <= 31'd20000;			// 2.5ms delay
					step_dir <= 1'b1;
					if(cpu_din[4])                           // update flag
						track <= track + 8'd1;
				end

				if(cpu_din[7:5] == 3'b011) begin            // STEP-OUT
					delay <= 31'd20000;			// 2.5ms delay
					step_dir <= 1'b0;
					if(cpu_din[4])                           // update flag
						track <= track - 8'd1;
				end
	    
				// ------------- TYPE II commands -------------
				if(cpu_din[7:5] == 3'b100) begin            // read sector
					state <= STATE_IO_WAIT;
				end
							
				if(cpu_din[7:5] == 3'b101)                  // write sector
					if(!wr_prot)
						state <= STATE_IO_WAIT;
	    
				// ------------- TYPE III commands ------------
	    		if(cpu_din[7:4] == 4'b1100)                 // read address
					state <= STATE_IO_WAIT;
	    
				if(cpu_din[7:4] == 4'b1110)                 // read track
					state <= STATE_IO_WAIT;
	    
				if(cpu_din[7:4] == 4'b1111)                 // write track
					if(!wr_prot)
						state <= STATE_IO_WAIT;
	    
				// ------------- TYPE IV commands -------------
				if(cpu_din[7:4] == 4'b1101) begin           // force intrerupt
					if(cpu_din[3:0] == 4'b0000)
						state <= STATE_IDLE;                    // immediately
					else
						state <= STATE_IRQ;                     // with irq
				end
			end // if (cpu_addr == 0)
	 
			if(cpu_addr == 1)             // track register
				track <= cpu_din;
	 
			if(cpu_addr == 2)             // sector register
				sector <= cpu_din;
	 
			if(cpu_addr == 3)             // data register
				data <= cpu_din;   

      end // if (cpu_sel && !cpu_rw)
   end // else: !if(reset)
end // always @ (negedge clk or posedge reset)
   
endmodule

   
