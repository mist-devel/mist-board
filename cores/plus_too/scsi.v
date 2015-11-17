/* verilator lint_off UNUSED */
/* verilator lint_off SYNCASYNCNET */

// scsi.v
// implements a target only scsi device
  
module scsi(input       sysclk,

	    // scsi interface
	    input 	  rst, // bus reset from initiator
	    input 	  sel,
	    input 	  atn, // initiator requests to send a message
	    output 	  bsy, // target holds bus
	    
	    output 	  msg,
	    output 	  cd,
	    output 	  io,
	    
	    output 	  req,
	    input 	  ack, // initiator acknowledges a request
	    
	    input [7:0]   din, // data from initiator to target
	    output [7:0]  dout, // data from target to initiator
	    
	    // interface to io controller 
	    output [31:0] io_lba,
	    output reg 	  io_rd,
	    output reg 	  io_wr,
	    input 	  io_ack,
	    
	    // data sent to io controller
            output reg [7:0]  io_dout,
            input 	  io_dout_strobe,

	    // data coming in from io controller
            input [7:0]   io_din,
            input 	  io_din_strobe

    );

   
   // SCSI device id
   parameter ID = 0; 

   `define PHASE_IDLE        3'd0
   `define PHASE_CMD_IN      3'd1
   `define PHASE_DATA_OUT    3'd2
   `define PHASE_DATA_IN     3'd3
   `define PHASE_STATUS_OUT  3'd4
   `define PHASE_MESSAGE_OUT 3'd5
   reg [2:0]  phase;

	reg cmd_in;
	always @(posedge sysclk)
		cmd_in <= (phase == `PHASE_CMD_IN);
		
   // ---------------- buffer read engine -----------------------
   // the buffer itself. Can hold one sector
   reg [7:0]  buffer_out [511:0];
   reg [8:0]  buffer_out_rptr;
   reg 	      buffer_out_read_strobe;
   
   always @(posedge io_dout_strobe or posedge cmd_cpl_strobe) begin
      if(cmd_cpl_strobe) buffer_out_rptr <= 9'd0;
      else			       begin	
			io_dout <= buffer_out[buffer_out_rptr];
			buffer_out_rptr <= buffer_out_rptr + 9'd1;
		end
   end

   
   // ---------------- buffer write engine -----------------------
   // the buffer itself. Can hold one sector
   reg [7:0]  buffer_in [511:0];
   reg [8:0]  buffer_in_wptr;
   reg 	      buffer_in_write_strobe;

	always @(posedge io_din_strobe)
		buffer_in[buffer_in_wptr] <= io_din;	

	wire cmd_cpl_strobe = cmd_in && cmd_cpl;
   always @(negedge io_din_strobe or posedge cmd_cpl_strobe) begin
      if(cmd_cpl_strobe) buffer_in_wptr <= 9'd0;
      else			       buffer_in_wptr <= buffer_in_wptr + 9'd1;
   end

   // status replies
   reg [7:0]  status;
   `define STATUS_OK 8'h00
   `define STATUS_CHECK_CONDITION 8'h02

   // message codes
   `define MSG_CMD_COMPLETE 8'h00
	
   // drive scsi signals according to phase
   assign msg = (phase == `PHASE_MESSAGE_OUT);
   assign cd = (phase == `PHASE_CMD_IN) || (phase == `PHASE_STATUS_OUT) || (phase == `PHASE_MESSAGE_OUT);
   assign io = (phase == `PHASE_DATA_OUT) || (phase == `PHASE_STATUS_OUT) || (phase == `PHASE_MESSAGE_OUT);
   assign req = (phase != `PHASE_IDLE) && !ack && !io_rd && !io_wr; 
   assign bsy = (phase != `PHASE_IDLE);

   assign dout = (phase == `PHASE_STATUS_OUT)?status:
		 (phase == `PHASE_MESSAGE_OUT)?`MSG_CMD_COMPLETE:
		 (phase == `PHASE_DATA_OUT)?cmd_dout:
		 8'h00;

   // de-multiplex different data sources
   wire [7:0] cmd_dout =
	      cmd_read?buffer_dout:
	      cmd_inquiry?inquiry_dout:
	      cmd_read_capacity?read_capacity_dout:
	      8'h00;
   
   // output of inquiry command, identify as "SEAGATE ST225N"
   wire [7:0] inquiry_dout =
	      (data_cnt == 32'd4 )?8'd32:  // length

	      (data_cnt == 32'd8 )?" ":(data_cnt == 32'd9 )?"S":
	      (data_cnt == 32'd10)?"E":(data_cnt == 32'd11)?"A":
	      (data_cnt == 32'd12)?"G":(data_cnt == 32'd13)?"A":
	      (data_cnt == 32'd14)?"T":(data_cnt == 32'd15)?"E":
	      (data_cnt == 32'd16)?" ":(data_cnt == 32'd17)?" ":
	      (data_cnt == 32'd18)?" ":(data_cnt == 32'd19)?" ":
	      (data_cnt == 32'd20)?" ":(data_cnt == 32'd21)?" ":
	      (data_cnt == 32'd22)?" ":(data_cnt == 32'd23)?" ":
	      (data_cnt == 32'd24)?" ":(data_cnt == 32'd25)?" ":

	      (data_cnt == 32'd26)?"S":(data_cnt == 32'd27)?"T":
	      (data_cnt == 32'd28)?"2":(data_cnt == 32'd29)?"2":
	      (data_cnt == 32'd30)?"5":(data_cnt == 32'd31)?"N":
	      8'h00;

   // output of read capacity command
   wire [31:0] capacity = 32'd41055;   // 40960 + 96 blocks = 20MB
   wire [7:0] read_capacity_dout =
	      (data_cnt == 32'd0 )?capacity[31:24]:
	      (data_cnt == 32'd1 )?capacity[23:16]:
	      (data_cnt == 32'd2 )?capacity[15:8]:
	      (data_cnt == 32'd3 )?capacity[7:0]:
	      (data_cnt == 32'd6 )?8'd2:             // 512 bytes per sector
	      8'h00;

   // clock data out of buffer to allow for embedded ram
   reg [7:0] buffer_dout;
   wire      buffer_out_clk = req && !io_rd;
   always @(posedge sysclk) // buffer_out_clk)
     buffer_dout <= buffer_in[data_cnt];

   // debug signals
   reg [7:0]  dbg_cmds /* synthesis noprune */;
   always @(posedge cmd_cpl or posedge rst) begin
      if(rst) dbg_cmds <= 8'd0;
		else    dbg_cmds <= dbg_cmds + 8'd1;
	end
   
   // buffer to store incoming commands
   reg [3:0]  cmd_cnt;
   reg [7:0]  cmd [9:0];

	/* ----------------------- request data from/to io controller ----------------------- */
	
	// base address of current block. Subtract one when writing since the writing happens
   // after a block has been transferred and data_cnt has thus already been increased by 512
   assign io_lba = lba + { 9'd0, data_cnt[31:9] } -
		   (cmd_write ? 32'd1 : 32'd0);
   
   reg 	      req_io_rd, req_io_wr;
   always @(posedge sysclk) begin
      // generate an io_rd signal whenever the first byte of a 512 byte block is required and io_wr whenever
      // the last byte of a 512 byte block has been revceived
     req_io_rd <= (phase == `PHASE_DATA_OUT) && cmd_read && (data_cnt[8:0] == 0) && !data_complete;
      // generate an io_wr signal whenever a 512 byte block has been received or when the status
      // phase of a write command has been reached
     req_io_wr <= (((phase == `PHASE_DATA_IN) && (data_cnt[8:0] == 0) && (data_cnt != 0)) ||
		  (phase == `PHASE_STATUS_OUT)) && cmd_write;
   end
      
	always @(posedge req_io_rd or posedge io_ack) begin
		if(io_ack) io_rd <= 1'b0;
		else 	   io_rd <= 1'b1;
	end
	  
	always @(posedge req_io_wr or posedge io_ack) begin
		if(io_ack) io_wr <= 1'b0;
		else 	   io_wr <= 1'b1;
	end
	  
   // store incoming command in buffer
   reg cmd_idle;
	always @(posedge sysclk) 
		cmd_idle <= (phase == `PHASE_IDLE);
	
	// store data on rising edge of ack, ...
   always @(posedge ack) begin
      if(phase == `PHASE_CMD_IN)
			cmd[cmd_cnt] <= din;
      if(phase == `PHASE_DATA_IN)
			buffer_out[data_cnt] <= din;
   end

	// ... advance counter on falling edge
   always @(negedge ack or posedge cmd_idle) begin
      if(cmd_idle)				cmd_cnt <= 4'd0;
      else if(cmd_cnt != 15)	cmd_cnt <= cmd_cnt + 4'd1;
	end

   // count data bytes. don't increase counter while we are waiting for data from
   // the io controller
   reg [31:0] 		 data_cnt;
	reg        data_complete;

   reg 		   data_io;
	always @(posedge sysclk)
		data_io <= (phase == `PHASE_DATA_OUT) || (phase == `PHASE_DATA_IN) || 
			   (phase == `PHASE_STATUS_OUT) || (phase == `PHASE_MESSAGE_OUT);

   // For block transfers tlen contains the number of 512 bytes blocks to transfer.
   // Most other commands have the bytes length stored in the transfer length field.
   // And some have a fixed length idependent from any header field.
   // The data transfer has finished once the data counter reaches this
   // number.
      wire [31:0] data_len =
	       cmd_read_capacity?32'd8:
	       cmd_read?{ 7'd0, tlen, 9'd0 }:   // read command length is in 512 bytes blocks
	       cmd_write?{ 7'd0, tlen, 9'd0 }:  // write command length is in 512 bytes blocks
	       { 16'd0, tlen };                 // inquiry etc have length in bytes
   
   always @(negedge ack or negedge data_io) begin
      if(!data_io) begin
			data_cnt <= 32'd0;
			data_complete <= 1'b0;
      end else begin	
			data_cnt <= data_cnt + 32'd1;
			data_complete <= (data_len - 32'd1) == data_cnt;
		end
   end

   // check whether status byte has been sent
	wire status_out = (phase == `PHASE_STATUS_OUT);
   reg status_sent;
   always @(negedge ack or negedge status_out) begin
      if(!status_out) 	status_sent <= 1'b0;
      else	      		status_sent <= 1'b1;
   end

   // check whether message byte has been sent
   reg message_sent;
	wire message_out = (phase == `PHASE_MESSAGE_OUT);
   always @(negedge ack or negedge message_out) begin
      if(!message_out) 	message_sent <= 1'b0;
      else	       		message_sent <= 1'b1;
   end

	/* ----------------------- command decoding ------------------------------- */

   wire cmd_wr_x = cmd_cpl && cmd_write && (tlen > 1);
   
   
   // parse commands
   wire [7:0] op_code = cmd[0];
   wire [2:0] cmd_group = op_code[7:5];
   wire [4:0] cmd_code = op_code[4:0];

   wire       cmd_unknown = cmd_cpl && !cmd_ok;
   
   // check if a complete command has been received
   wire       cmd_cpl = cmd6_cpl || cmd10_cpl;
   wire       cmd6_cpl = (cmd_group == 3'b000) && (cmd_cnt == 6);
   wire       cmd10_cpl = ((cmd_group == 3'b010) || (cmd_group == 3'b001)) && (cmd_cnt == 10);

   // https://en.wikipedia.org/wiki/SCSI_command
   wire       cmd_read = cmd_read6 || cmd_read10;
   wire       cmd_read6 = (op_code == 8'h08);
   wire       cmd_read10 = (op_code == 8'h28);
   wire       cmd_write = cmd_write6 || cmd_write10;
   wire       cmd_write6 = (op_code == 8'h0a);
   wire       cmd_write10 = (op_code == 8'h2a);
   wire       cmd_inquiry = (op_code == 8'h12);
   wire       cmd_format = (op_code == 8'h04);
   wire       cmd_mode_select = (op_code == 8'h15);
   wire       cmd_test_unit_ready = (op_code == 8'h00);
   wire       cmd_read_capacity = (op_code == 8'h25);

   // valid command in buffer? TODO: check for valid command parameters
   wire       cmd_ok = cmd_read || cmd_write || cmd_inquiry || cmd_test_unit_ready || 
	        cmd_read_capacity || cmd_mode_select || cmd_format;
     
   // latch parameters once command is complete
   reg [31:0] lba;
   reg [15:0] tlen;
   reg [2:0]  lun;
   
   always @(posedge sysclk) begin
		if(cmd_cpl && (phase == `PHASE_CMD_IN)) begin
			lba <= cmd6_cpl?{11'd0, lba6}:lba10;
			tlen <= cmd6_cpl?{7'd0, tlen6}:tlen10;
			lun <= cmd6_cpl?lun6:3'd0;
		end
   end
   
   // logical block address
   wire [7:0] cmd1 = cmd[1];
   wire [2:0] lun6 = cmd1[7:5];
   wire [20:0] lba6 = { cmd1[4:0], cmd[2], cmd[3] };
   wire [31:0] lba10 = { cmd[2], cmd[3], cmd[4], cmd[5] };

   // transfer length
   wire [8:0]  tlen6 = (cmd[4] == 0)?9'd256:{1'b0,cmd[4]};
   wire [15:0] tlen10 = { cmd[7], cmd[8] };


	// the 5380 changes phase in the falling edge, thus we monitor it
	// on the rising edge
   always @(posedge sysclk) begin
      if(rst) begin
			phase <= `PHASE_IDLE;
      end else begin
//			case(phase)
			if(phase == `PHASE_IDLE) begin
				if(sel && din[ID])  // own id on bus during selection?
					phase <= `PHASE_CMD_IN;
			end
			   
			else if(phase == `PHASE_CMD_IN) begin
				// check if a full command is in the buffer
				if(cmd_cpl) begin
					// is this a supported and valid command?
					if(cmd_ok) begin
						// yes, continue
						status <= `STATUS_OK;

						// continue according to command

					        // these commands return data
					        if(cmd_read || cmd_inquiry || cmd_read_capacity)
						  phase <= `PHASE_DATA_OUT;
					        // these commands receive dataa
					        else if(cmd_write || cmd_mode_select)
						  phase <= `PHASE_DATA_IN;
					        // and all other valid commands are just "ok"
						else 
					          phase <= `PHASE_STATUS_OUT;
					end else begin
						// no, report failure
						status <= `STATUS_CHECK_CONDITION;
						phase <= `PHASE_STATUS_OUT;
					end
				end
			end

			else if(phase == `PHASE_DATA_OUT) begin
				if(data_complete)
					phase <= `PHASE_STATUS_OUT;
			end

 			else if(phase == `PHASE_DATA_IN) begin
				if(data_complete)
					phase <= `PHASE_STATUS_OUT;
			end

			else if(phase == `PHASE_STATUS_OUT) begin
				if(status_sent)
					phase <= `PHASE_MESSAGE_OUT;
			end

			else if(phase == `PHASE_MESSAGE_OUT) begin
				if(message_sent)
					phase <= `PHASE_IDLE;
			end
			
			else
				phase <= `PHASE_IDLE;  // should never happen
	   
//			endcase
      end
   end
   
   
endmodule
