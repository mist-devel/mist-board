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
    input         clk_sys,
    // link to user_io for io controller
    output [31:0] sd_lba,
    output reg    sd_rd,
    output reg    sd_wr,
    input         sd_ack,
    input         sd_ack_conf,
    output        sd_conf,
    output        sd_sdhc,

    input         img_mounted,
    input  [31:0] img_size,

    output reg    sd_busy = 0,
    // data coming in from io controller
    input   [7:0] sd_buff_dout,
    input         sd_buff_wr,

    // data going out to io controller
    output  [7:0] sd_buff_din,

    input   [8:0] sd_buff_addr,

    // configuration input
    input         allow_sdhc,

    input         sd_cs,
    input         sd_sck,
    input         sd_sdi,
    output reg    sd_sdo
);

wire [31:0] OCR = { 1'b1, sd_sdhc, 6'h0, 9'h1f, 15'h0 };  // bit31 = finished powerup
                                                          // bit30 = 1 -> high capaciry card (sdhc)
                                                          // 15-23 supported voltage range
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
reg [7:0] cmd = 8'h00;
reg [2:0] bit_cnt = 3'd0;    // counts bits 0-7 0-7 ...
reg [3:0] byte_cnt= 4'd15;   // counts bytes

reg [39:0] args;
assign sd_lba = sd_sdhc?args[39:8]:{9'd0, args[39:17]};

reg [7:0] reply;
reg [7:0] reply0, reply1, reply2, reply3;
reg [3:0] reply_len;

// ------------------------- SECTOR BUFFER -----------------------

// the buffer itself. Can hold one sector
reg  [8:0] buffer_ptr;
wire [7:0] buffer_dout;
reg  [7:0] buffer_din;
reg        buffer_write_strobe;

sd_card_dpram #(8, 9) buffer_dpram
(
    .clock_a      (clk_sys),
    .address_a    (sd_buff_addr),
    .data_a       (sd_buff_dout),
    .wren_a       (sd_buff_wr & sd_ack),
    .q_a          (sd_buff_din),

    .clock_b      (clk_sys),
    .address_b    (buffer_ptr),
    .data_b       (buffer_din),
    .wren_b       (buffer_write_strobe),
    .q_b          (buffer_dout)
);

wire [7:0] WRITE_DATA_RESPONSE = 8'h05;

// ------------------------- CSD/CID BUFFER ----------------------
reg  [7:0] conf;
assign     sd_conf = sd_configuring;

reg        sd_configuring = 1;
reg  [4:0] conf_buff_ptr;
reg  [7:0] conf_byte;
reg[255:0] csdcid;

// conf[0]==1 -> io controller is using an sdhc card
wire sd_has_sdhc = conf[0];
assign sd_sdhc = allow_sdhc && sd_has_sdhc;

always @(posedge clk_sys) begin
    reg old_mounted;

    if (sd_buff_wr & sd_ack_conf) begin
        if (sd_buff_addr == 32) begin
            conf <= sd_buff_dout;
            sd_configuring <= 0;
        end
        else csdcid[(31-sd_buff_addr) << 3 +:8] <= sd_buff_dout;
    end
    conf_byte <= csdcid[(31-conf_buff_ptr) << 3 +:8];

    old_mounted <= img_mounted;
    if (~old_mounted & img_mounted) begin
        // update card size in case of a virtual SD image
        if (sd_sdhc)
            // CSD V1.0 size = (c_size + 1) * 512K
            csdcid[69:48] <= {9'd0, img_size[31:19] };
        else begin
            // CSD V2.0 no. of blocks = c_size ** (c_size_mult + 2)
            csdcid[49:47] <= 3'd7; //c_size_mult
            csdcid[73:62] <= img_size[29:18]; //c_size
        end
    end
end

always@(posedge clk_sys) begin

    reg       old_sd_sck;
    reg [5:0] ack;

    ack <= {ack[4:0], sd_ack};
    if(ack[5:4] == 'b01) { sd_rd, sd_wr } <= 2'b00;
    if(ack[5:4] == 'b10) sd_busy <= 0;

    buffer_write_strobe <= 0;
    if (buffer_write_strobe) buffer_ptr <= buffer_ptr + 1'd1;

    old_sd_sck <= sd_sck;
    // advance transmitter state machine on falling sck edge, so data is valid on the 
    // rising edge
    // ----------------- spi transmitter --------------------
    if(sd_cs == 0 && old_sd_sck && ~sd_sck) begin

        sd_sdo <= 1'b1;    // default: send 1's (busy/wait)

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
                    sd_rd <= 1;                      // trigger request to io controller
                    sd_busy <= 1;
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
            buffer_ptr <= 0;
            if(~sd_busy && (bit_cnt == 7)) 
                read_state <= RD_STATE_SEND_TOKEN;
        end

        // send data token
        RD_STATE_SEND_TOKEN: begin
            sd_sdo <= READ_DATA_TOKEN[~bit_cnt];

            if(bit_cnt == 7) begin
                read_state <= RD_STATE_SEND_DATA;   // next: send data
                conf_buff_ptr <= (cmd == 8'h4a) ? 5'h0 : 5'h10;
            end
        end

        // send data
        RD_STATE_SEND_DATA: begin
            if(cmd == 8'h51)        // CMD17: READ_SINGLE_BLOCK
                sd_sdo <= buffer_dout[~bit_cnt];
            else if(cmd == 8'h49) begin     // CMD9: SEND_CSD
                sd_sdo <= conf_byte[~bit_cnt];
            end
            else if(cmd == 8'h4a)      // CMD10: SEND_CID
                sd_sdo <= conf_byte[~bit_cnt];
            else
                sd_sdo <= 1'b1;

            if(bit_cnt == 7) begin
                // sent 512 sector data bytes?
                if((cmd == 8'h51) && &buffer_ptr) // (buffer_ptr ==511))
                    read_state <= RD_STATE_IDLE;   // next: send crc. It's ignored so return to idle state

                // sent 16 cid/csd data bytes?
                else if(((cmd == 8'h49)||(cmd == 8'h4a)) && conf_buff_ptr[3:0] == 4'h0f) // && (buffer_rptr == 16))
                    read_state <= RD_STATE_IDLE;   // return to idle state

                else begin
                    buffer_ptr <= buffer_ptr + 1'd1;
                    conf_buff_ptr<= conf_buff_ptr+ 1'd1;
                end
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

    // spi receiver
    // cs is active low
    if(sd_cs == 1) begin
        bit_cnt <= 3'd0;
    end else if (~old_sd_sck & sd_sck) begin
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

                // set cmd55 flag if previous command was 55
                cmd55 <= (cmd == 8'h77);
            end

            // parse additional command bytes
            if(byte_cnt == 0) args[39:32] <= { sbuf, sd_sdi};
            if(byte_cnt == 1) args[31:24] <= { sbuf, sd_sdi};
            if(byte_cnt == 2) args[23:16] <= { sbuf, sd_sdi};
            if(byte_cnt == 3) args[15:8]  <= { sbuf, sd_sdi};
            if(byte_cnt == 4) args[7:0]   <= { sbuf, sd_sdi};

            // last byte received, evaluate
            if(byte_cnt == 5) begin

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
                    case(cmd)
                    // CMD1: SEND_OP_COND
                    8'h41: reply <= 8'h00;    // ok, not busy

                    // CMD8: SEND_IF_COND (V2 only)
                    8'h48: begin
                        reply <= 8'h01;    // ok, busy
                        reply0 <= 8'h00;
                        reply1 <= 8'h00;
                        reply2 <= { 4'b0, args[19:16] };
                        reply3 <= args[15:8];
                        reply_len <= 4'd4;
                    end

                    // CMD9: SEND_CSD
                    8'h49: reply <= 8'h00;    // ok

                    // CMD10: SEND_CID
                    8'h4a: reply <= 8'h00;    // ok

                    // CMD16: SET_BLOCKLEN
                    8'h50:
                        // we only support a block size of 512
                        if(args[39:8] == 32'd512)
                            reply <= 8'h00;    // ok
                        else
                            reply <= 8'h40;    // parmeter error

                    // CMD17: READ_SINGLE_BLOCK
                    8'h51: reply <= 8'h00;    // ok

                    // CMD24: WRITE_BLOCK
                    8'h58: begin
                        reply <= 8'h00;    // ok
                        write_state <= WR_STATE_EXP_DTOKEN;  // expect data token
                    end

                    // ACMD41: APP_SEND_OP_COND
                    8'h69: if(cmd55) begin
                        reply <= 8'h00;    // ok, not busy
                    end

                    // CMD55: APP_COND
                    8'h77: reply <= 8'h01;    // ok, busy

                    // CMD58: READ_OCR
                    8'h7a: begin
                        reply <= 8'h00;    // ok

                        reply0 <= OCR[31:24];   // bit 30 = 1 -> high capacity card 
                        reply1 <= OCR[23:16];
                        reply2 <= OCR[15:8];
                        reply3 <= OCR[7:0];
                        reply_len <= 4'd4;
                    end
                    endcase
                end
            end

            // ---------- handle write -----------
            case(write_state)
            // don't do anything in idle state
            WR_STATE_IDLE: ;

            // waiting for data token
            WR_STATE_EXP_DTOKEN:
            if({ sbuf, sd_sdi} == 8'hfe ) begin
                write_state <= WR_STATE_RECV_DATA;
                buffer_ptr <= 9'd0;
            end

            // transfer 512 bytes
            WR_STATE_RECV_DATA: begin
                // push one byte into local buffer
                buffer_write_strobe <= 1'b1;
                buffer_din <= { sbuf, sd_sdi };

                // all bytes written?
                if(&buffer_ptr)
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
                sd_wr <= 1;               // trigger write request to io ontroller
                sd_busy <= 1;
            end

            // wait for io controller to accept data
            WR_STATE_BUSY:
            if(~sd_busy)
                write_state <= WR_STATE_IDLE;

            default: ;
            endcase
        end
    end
end

endmodule

module sd_card_dpram #(parameter DATAWIDTH=8, ADDRWIDTH=9)
(
    input                   clock_a,
    input   [ADDRWIDTH-1:0] address_a,
    input   [DATAWIDTH-1:0] data_a,
    input                   wren_a,
    output reg [DATAWIDTH-1:0] q_a,

    input                   clock_b,
    input   [ADDRWIDTH-1:0] address_b,
    input   [DATAWIDTH-1:0] data_b,
    input                   wren_b,
    output reg [DATAWIDTH-1:0] q_b
);

reg [DATAWIDTH-1:0] ram[0:(1<<ADDRWIDTH)-1];

always @(posedge clock_a) begin
    q_a <= ram[address_a];
    if(wren_a) begin
        q_a <= data_a;
        ram[address_a] <= data_a;
    end
end

always @(posedge clock_b) begin
    q_b <= ram[address_b];
    if(wren_b) begin
        q_b <= data_b;
        ram[address_b] <= data_b;
    end
end

endmodule