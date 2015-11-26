// 
// sd_card.v
//
// This file implelents a sd card for the MIST board since on the board
// the SD card is connected to the ARM IO controller and the FPGA has no
// direct connection to the SD card. This file provides a SD card like
// interface to the IO controller easing porting of cores that expect
// a direct interface to the SD card.
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the Lesser GNU General Public License as published
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
// http://elm-chan.org/docs/mmc/mmc_e.html

module sd_card (
	// link to user_io for io controller
	output [31:0] io_lba,
	output reg    io_rd,
	output reg    io_wr,
	input			  io_ack,
	output		  io_conf,
	output		  io_sdhc,
	
	// data coming in from io controller
	input	[7:0]	  io_din,
	input 		  io_din_strobe,

	// data going out to io controller
	output [7:0]  io_dout,
	input 		  io_dout_strobe,

	// configuration input
	input         allow_sdhc,
	
   input         sd_cs,
   input         sd_sck,
   input         sd_sdi,
   output reg    sd_sdo
); 

// set io_rd once read_state machine starts waiting (rising edge of req_io_rd)
// and clear it once io controller uploads something (io_ack==1) 
reg req_io_rd = 1'b0; // set when write_state is changed to RD_STATE_WAIT_IO
always @(posedge req_io_rd or posedge io_ack) begin
	if(io_ack) io_rd <= 1'b0;
	else 		  io_rd <= 1'b1;
end

reg req_io_wr = 1'b0; // set when write_state is changed to WR_STATE_BUSY
always @(posedge req_io_wr or posedge io_ack) begin
	if(io_ack) io_wr <= 1'b0;
	else 		  io_wr <= 1'b1;
end

wire [31:0] OCR = { 1'b0, io_sdhc, 30'h0 };  // bit30 = 1 -> high capaciry card (sdhc)
wire [7:0] READ_DATA_TOKEN = 8'hfe;

// number of bytes to wait after a command before sending the reply
localparam NCR=4;

localparam RD_STATE_IDLE       = 2'd0;
localparam RD_STATE_WAIT_IO    = 2'd1;
localparam RD_STATE_SEND_TOKEN = 2'd2;
localparam RD_STATE_SEND_DATA  = 2'd3;
reg [1:0] read_state = RD_STATE_IDLE;  

localparam WR_STATE_IDLE       = 3'd0;
localparam WR_STATE_EXP_DTOKEN = 3'd1;
localparam WR_STATE_RECV_DATA  = 3'd2;
localparam WR_STATE_RECV_CRC0  = 3'd3;
localparam WR_STATE_RECV_CRC1  = 3'd4;
localparam WR_STATE_SEND_DRESP = 3'd5;
localparam WR_STATE_BUSY       = 3'd6;
reg [2:0] write_state = WR_STATE_IDLE;  

reg card_is_reset = 1'b0;    // flag that card has received a reset command
reg [6:0] sbuf; 
reg cmd55;
reg new_cmd_rcvd;
reg [7:0] cmd = 8'h00;
reg [2:0] bit_cnt;           // counts bits 0-7 0-7 ...
reg [3:0] byte_cnt= 4'd15;   // counts bytes

reg [31:0] lba;
assign io_lba = io_sdhc?lba:{9'd0, lba[31:9]};

reg [7:0] reply;
reg [7:0] reply0, reply1, reply2, reply3;
reg [3:0] reply_len;

// falling edge of io_ack signals that a sector to be read has been written into
// the sector buffer by the io controller. This signal is kept set as long
// as the read state machine is in the "wait for io controller" state (state 1)
wire rd_wait_io = (read_state != RD_STATE_IDLE);
reg rd_io_ack_i = 1'b0;
always @(negedge io_ack or negedge rd_wait_io) begin
	if(!rd_wait_io) rd_io_ack_i <= 1'b0;
	else            rd_io_ack_i <= 1'b1;
end
 
wire wr_wait_io = (write_state == WR_STATE_BUSY);
reg wr_io_ack_i = 1'b0;
always @(negedge io_ack or negedge wr_wait_io) begin
	if(!wr_wait_io) wr_io_ack_i <= 1'b0;
	else            wr_io_ack_i <= 1'b1;
end

// bring xx_io_ack into sd cards clock domain
reg wr_io_ack;
reg rd_io_ack;
always @(posedge sd_sck) begin	
	rd_io_ack <= rd_io_ack_i;
	wr_io_ack <= wr_io_ack_i;
end

// ------------------------- SECTOR BUFFER -----------------------

// the buffer itself. Can hold one sector
reg [7:0] buffer [511:0];

// ---------------- buffer read engine -----------------------
reg [8:0] buffer_rptr;
reg buffer_read_strobe;
wire buffer_dout_strobe = buffer_read_strobe || io_dout_strobe;
reg [7:0] buffer_dout;
assign io_dout = buffer_dout;

// buffer_rptr is increased in a diferent clock domain than it's
// evaluated. These single bit registers bring certain states from
// one domain into the other one in a safe (atomic) way
reg buffer_read_sector_done;
reg buffer_read_ciscid_done;

always @(posedge buffer_dout_strobe or posedge new_cmd_rcvd) begin
	if(new_cmd_rcvd == 1) begin
		buffer_rptr <= 9'd0;
		buffer_read_sector_done <= 1'b0;
		buffer_read_ciscid_done <= 1'b0;
	end else begin
		buffer_dout <= buffer[buffer_rptr];
		buffer_rptr <= buffer_rptr + 9'd1;
		if(buffer_rptr == 511) buffer_read_sector_done <= 1'b1;
		if(buffer_rptr == 15)  buffer_read_ciscid_done <= 1'b1;
	end
end

// ---------------- buffer write engine -----------------------
reg [8:0] buffer_wptr;
reg buffer_write_strobe;
wire buffer_din_strobe = io_din_strobe || buffer_write_strobe;
wire [7:0] buffer_din = (cmd == 8'h51)?io_din:{sbuf, sd_sdi};

always @(posedge buffer_din_strobe or posedge new_cmd_rcvd) begin
	if(new_cmd_rcvd == 1)
		buffer_wptr <= 9'd0;
	else begin
		buffer[buffer_wptr] <= buffer_din;	
		buffer_wptr <= buffer_wptr + 9'd1;
	end
end

wire [7:0] WRITE_DATA_RESPONSE = 8'h05;

// ------------------------- CSD/CID BUFFER ----------------------
assign io_conf = (csd_wptr == 0);  // csd_wptr still 0 -> configuration required

// the 32 bytes as sent from the io controller
reg [7:0] cid [15:0];
reg [7:0] csd [15:0];
reg [7:0] conf;

reg [7:0] cid_byte;
reg [7:0] csd_byte;
reg [5:0] csd_wptr = 6'd0;

// conf[0]==1 -> io controller is using an sdhc card
wire io_has_sdhc = conf[0];
assign io_sdhc = allow_sdhc && io_has_sdhc;

always @(posedge io_din_strobe) begin
	// if io controller sends data without asserting io_ack, then it's
	// updating the config
	if(!io_ack && (csd_wptr <= 32)) begin
	
		if(csd_wptr < 16)                       // first 16 bytes are cid
			cid[csd_wptr[3:0]] <= io_din;	
		if((csd_wptr >= 16) && (csd_wptr < 32)) // then comes csd
			csd[csd_wptr[3:0]] <= io_din;	
		if(csd_wptr == 32)                      // finally a config byte
			conf <= io_din;	
			
		csd_wptr	<= csd_wptr + 6'd1;
	end
end
 
always @(posedge buffer_dout_strobe) begin
	cid_byte <= cid[buffer_rptr[3:0]];
	csd_byte <= csd[buffer_rptr[3:0]];
end
 	
// ----------------- spi transmitter --------------------
// advance transmitter state machine on falling sck edge, so data is valid on the 
// rising edge
always@(negedge sd_sck) begin
	if(sd_cs == 0) begin
		buffer_read_strobe <= 1'b0;
		sd_sdo <= 1'b1;				// default: send 1's (busy/wait)
		req_io_rd <= 1'b0;
		
		if(byte_cnt == 5+NCR) begin
			sd_sdo <= reply[~bit_cnt];

			if(bit_cnt == 7) begin
				// these three commands all have a reply_len of 0 and will thus
				// not send more than a single reply byte
				
				// CMD9: SEND_CSD
				// CMD10: SEND_CID
				if((cmd == 8'h49)||(cmd == 8'h4a))
					read_state <= RD_STATE_SEND_TOKEN;      // jump directly to data transmission
						
				// CMD17: READ_SINGLE_BLOCK
				if(cmd == 8'h51) begin
					read_state <= RD_STATE_WAIT_IO;         // start waiting for data from io controller
					req_io_rd <= 1'b1;                      // trigger request to io controller
				end
			end
		end
		else if((reply_len > 0) && (byte_cnt == 5+NCR+1))
			sd_sdo <= reply0[~bit_cnt];
		else if((reply_len > 1) && (byte_cnt == 5+NCR+2))
			sd_sdo <= reply1[~bit_cnt];
		else if((reply_len > 2) && (byte_cnt == 5+NCR+3))
			sd_sdo <= reply2[~bit_cnt];
		else if((reply_len > 3) && (byte_cnt == 5+NCR+4))
			sd_sdo <= reply3[~bit_cnt];
		else
			sd_sdo <= 1'b1;

		// ---------- read state machine processing -------------

		case(read_state)
			RD_STATE_IDLE: ;
				// don't do anything

			// waiting for io controller to return data
			RD_STATE_WAIT_IO: begin
				if(rd_io_ack && (bit_cnt == 7)) 
					read_state <= RD_STATE_SEND_TOKEN;
			end

			// send data token
			RD_STATE_SEND_TOKEN: begin
				sd_sdo <= READ_DATA_TOKEN[~bit_cnt];
	
				if(bit_cnt == 7) begin
					read_state <= RD_STATE_SEND_DATA;   // next: send data
					buffer_read_strobe <= 1'b1;         // trigger read of first data byte
				end
			end
					
			// send data
			RD_STATE_SEND_DATA: begin
				if(cmd == 8'h51) 							// CMD17: READ_SINGLE_BLOCK
					sd_sdo <= buffer_dout[~bit_cnt];
				else if(cmd == 8'h49) 					// CMD9: SEND_CSD
					sd_sdo <= csd_byte[~bit_cnt];
				else if(cmd == 8'h4a) 					// CMD10: SEND_CID
					sd_sdo <= cid_byte[~bit_cnt];
				else
					sd_sdo <= 1'b1;

				if(bit_cnt == 7) begin
					// sent 512 sector data bytes?
					if((cmd == 8'h51) && buffer_read_sector_done) // (buffer_rptr == 0))
						read_state <= RD_STATE_IDLE;   // next: send crc. It's ignored so return to idle state
						
					// sent 16 cid/csd data bytes?
					else if(((cmd == 8'h49)||(cmd == 8'h4a)) && buffer_read_ciscid_done) // && (buffer_rptr == 16))
						read_state <= RD_STATE_IDLE;   // return to idle state
						
					else
						buffer_read_strobe <= 1'b1;    // not done yet -> trigger read of next data byte
				end
			end
		endcase
					
		// ------------------ write support ----------------------
		// send write data response
		if(write_state == WR_STATE_SEND_DRESP) 
			sd_sdo <= WRITE_DATA_RESPONSE[~bit_cnt];
			
		// busy after write until the io controller sends ack
		if(write_state == WR_STATE_BUSY) 
			sd_sdo <= 1'b0;
   end
end

// spi receiver  
reg illegal_write_state /* synthesis noprune */;

always @(posedge sd_sck or posedge sd_cs) begin
	// cs is active low
	if(sd_cs == 1) begin
		bit_cnt <= 3'd0;
	end else begin 
		illegal_write_state <= 1'b0;
		new_cmd_rcvd <= 1'b0;
		buffer_write_strobe <= 1'b0;
		req_io_wr <= 1'b0;
		bit_cnt <= bit_cnt + 3'd1;
		
		// assemble byte
		if(bit_cnt != 7)
			sbuf[6:0] <= { sbuf[5:0], sd_sdi };
		else begin
			// finished reading one byte
			// byte counter runs against 15 byte boundary
			if(byte_cnt != 15)
				byte_cnt <= byte_cnt + 4'd1;			

			// byte_cnt > 6 -> complete command received
			// first byte of valid command is 01xxxxxx
			// don't accept new commands once a write or read command has been accepted
 			if((byte_cnt > 5) && (write_state == WR_STATE_IDLE) && 
				(read_state == RD_STATE_IDLE)  && sbuf[6:5] == 2'b01) begin
				byte_cnt <= 4'd0;			
				cmd <= { sbuf, sd_sdi};
				new_cmd_rcvd <= 1'b1;

			   // set cmd55 flag if previous command was 55
			   cmd55 <= (cmd == 8'h77);
			end

			// parse additional command bytes
			if(byte_cnt == 0) lba[31:24] <= { sbuf, sd_sdi};
			if(byte_cnt == 1) lba[23:16] <= { sbuf, sd_sdi};
			if(byte_cnt == 2) lba[15:8]  <= { sbuf, sd_sdi};
			if(byte_cnt == 3) lba[7:0]   <= { sbuf, sd_sdi};			

			// last byte received, evaluate
			if(byte_cnt == 4) begin		
		
				// default:
				reply <= 8'h04;     // illegal command
				reply_len <= 4'd0;  // no extra reply bytes
				
				// CMD0: GO_IDLE_STATE
				if(cmd == 8'h40) begin
					card_is_reset <= 1'b1;
					reply <= 8'h01;    // ok, busy
				end

				// every other command is only accepted after a reset
				else if(card_is_reset) begin
					// CMD1: SEND_OP_COND
					if(cmd == 8'h41)
						reply <= 8'h00;    // ok, not busy
					
					// CMD8: SEND_IF_COND (V2 only)
					else if(cmd == 8'h48) begin
						reply <= 8'h01;    // ok, busy
						reply0 <= 8'h00;
						reply1 <= 8'h00;
						reply2 <= 8'h01;
						reply3 <= 8'hAA;
						reply_len <= 4'd4;
					end
				
					// CMD9: SEND_CSD
					else if(cmd == 8'h49)
						reply <= 8'h00;    // ok
				
					// CMD10: SEND_CID
					else if(cmd == 8'h4a)
						reply <= 8'h00;    // ok
				
					// CMD16: SET_BLOCKLEN
					else if(cmd == 8'h50) begin
						// we only support a block size of 512
						if(lba == 32'd512)
							reply <= 8'h00;    // ok
						else
							reply <= 8'h40;    // parmeter error
					end

					// CMD17: READ_SINGLE_BLOCK
					else if(cmd == 8'h51)
						reply <= 8'h00;    // ok

					// CMD24: WRITE_BLOCK
					else if(cmd == 8'h58) begin
						reply <= 8'h00;    // ok
						write_state <= WR_STATE_EXP_DTOKEN;  // expect data token
					end

					// ACMD41: APP_SEND_OP_COND
					else if(cmd55 && (cmd == 8'h69))
						reply <= 8'h00;    // ok, not busy
	
					// CMD55: APP_COND
					else if(cmd == 8'h77)
						reply <= 8'h01;    // ok, busy

					// CMD58: READ_OCR
					else if(cmd == 8'h7a) begin
						reply <= 8'h00;    // ok
					
						reply0 <= OCR[31:24];   // bit 30 = 1 -> high capacity card 
						reply1 <= OCR[23:16];
						reply2 <= OCR[15:8];
						reply3 <= OCR[7:0];
						reply_len <= 4'd4;
					end
				end
			end
			
			// ---------- handle write -----------
			case(write_state) 
				// don't do anything in idle state
				WR_STATE_IDLE: ;
				
				// waiting for data token
				WR_STATE_EXP_DTOKEN:
					if({ sbuf, sd_sdi} == 8'hfe )
						write_state <= WR_STATE_RECV_DATA;

				// transfer 512 bytes
				WR_STATE_RECV_DATA: begin
					// push one byte into local buffer
					buffer_write_strobe <= 1'b1;

					// all bytes written?
					if(buffer_wptr == 511)
						write_state <= WR_STATE_RECV_CRC0;
				end
	
				// transfer 1st crc byte
				WR_STATE_RECV_CRC0:
					write_state <= WR_STATE_RECV_CRC1;

				// transfer 2nd crc byte
				WR_STATE_RECV_CRC1:
					write_state <= WR_STATE_SEND_DRESP;
	
				// send data response
				WR_STATE_SEND_DRESP: begin
					write_state <= WR_STATE_BUSY;
					req_io_wr <= 1'b1;               // trigger write request to io ontroller
				end
				
				// wait for io controller to accept data
				WR_STATE_BUSY:
					if(wr_io_ack)
						write_state <= WR_STATE_IDLE;
						
				default:
					illegal_write_state <= 1'b1;
			endcase
		end
	end
end

endmodule
