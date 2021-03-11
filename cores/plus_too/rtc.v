/* PRAM - RTC implementation for plus_too */

module rtc (
	input         clk,
	input         reset,

	input  [63:0] rtc, // sec, min, hour, date, month, year, day (BCD)
	input         _cs,
	input         ck,
	input         dat_i,
	output reg    dat_o
);

function [7:0] bcd2bin;
	input [7:0] bcd;
	begin
		bcd2bin = 10*bcd[7:4] + bcd[3:0];
	end
endfunction

reg   [2:0] bit_cnt;
reg         ck_d;
reg   [7:0] din;
reg   [7:0] cmd;
reg   [7:0] dout;
reg         cmd_mode;
reg         receiving;
reg  [31:0] secs;
reg   [7:0] ram[20];

initial begin
	ram[5'h00] = 8'hA8;
	ram[5'h01] = 8'h00;
	ram[5'h02] = 8'h00;
	ram[5'h03] = 8'h22;
	ram[5'h04] = 8'hCC;
	ram[5'h05] = 8'h0A;
	ram[5'h06] = 8'hCC;
	ram[5'h07] = 8'h0A;
	ram[5'h08] = 8'h00;
	ram[5'h09] = 8'h00;
	ram[5'h0A] = 8'h00;
	ram[5'h0B] = 8'h00;
	ram[5'h0C] = 8'h00;
	ram[5'h0D] = 8'h02;
	ram[5'h0E] = 8'h63;
	ram[5'h0F] = 8'h00;
	ram[5'h10] = 8'h03;
	ram[5'h11] = 8'h88;
	ram[5'h12] = 8'h00;
	ram[5'h13] = 8'h6C;
end

integer     sec_cnt;

wire  [7:0] year =  bcd2bin(rtc[47:40]);
wire  [3:0] month = rtc[35:32] + (rtc[36] ? 4'd10 : 4'd0);
wire  [4:0] day   = bcd2bin(rtc[29:24]);
reg   [8:0] yoe; // year of era
reg  [10:0] doy; // day of year
reg  [20:0] doe; // day of era
reg  [23:0] days;

always @(*) begin
	//    Days from epoch (01/01/1904)
	//    y -= m <= 2;
	//    const Int era = (y >= 0 ? y : y-399) / 400;
	//    const unsigned yoe = static_cast<unsigned>(y - era * 400);      // [0, 399]
	//    const unsigned doy = (153*(m + (m > 2 ? -3 : 9)) + 2)/5 + d-1;  // [0, 365]
	//    const unsigned doe = yoe * 365 + yoe/4 - yoe/100 + doy;         // [0, 146096]
	//    return era * 146097 + static_cast<Int>(doe) - 719468;
	yoe = (month <= 2) ? year - 1'd1 : year;
	doy = (8'd153*(month + ((month > 2) ? -3 : 9)) + 4'd2)/4'd5 + day-1'd1;
	doe = yoe * 9'd365 + yoe/4 - yoe/100 + doy;
	days = 5 * 146097 + doe - 719468 + 24107;
end

always @(posedge clk) begin
	if (reset) begin
		bit_cnt <= 0;
		receiving <= 1;
		cmd_mode <= 1;
		dat_o <= 1;
		sec_cnt <= 0;
	end 
	else begin

//		sec_cnt <= sec_cnt + 1'd1;
//		if (sec_cnt == 31999999) begin
//			sec_cnt <= 0;
//			secs <= secs + 1'd1;
//		end

		secs <= bcd2bin(rtc[7:0]) +
		        bcd2bin(rtc[15:8]) * 60 +
		        bcd2bin(rtc[23:16]) * 3600 +
	          days * 3600*24;

		if (_cs) begin
			bit_cnt <= 0;
			receiving <= 1;
			cmd_mode <= 1;
			dat_o <= 1;
		end
		else begin
			ck_d <= ck;

			// transmit at the falling edge
			if (ck_d & ~ck & !receiving)
				dat_o <= dout[7-bit_cnt];
			// receive at the rising edge of ck
			if (~ck_d & ck) begin
				bit_cnt <= bit_cnt + 1'd1;
				if (receiving)
					din <= {din[6:0], dat_i};

				if (bit_cnt == 7) begin
					if (receiving && cmd_mode) begin
						// command byte received
						cmd_mode <= 0;
						receiving <= ~din[6];
						cmd <= {din[6:0], dat_i};
						casez ({din[5:0], dat_i})
							7'b00?0001: dout <= secs[7:0];
							7'b00?0101: dout <= secs[15:8];
							7'b00?1001: dout <= secs[23:16];
							7'b00?1101: dout <= secs[31:24];
							7'b010??01: dout <= ram[{3'b100, din[2:1]}];
							7'b1????01: dout <= ram[din[4:1]];
							default: ;
						endcase
					end
					if (receiving && !cmd_mode) begin
						// data byte received
						casez (cmd[6:0])
							7'b0000001: secs[7:0] <= {din[6:0], dat_i};
							7'b0000101: secs[15:8] <= {din[6:0], dat_i};
							7'b0001001: secs[23:16] <= {din[6:0], dat_i};
							7'b0001101: secs[31:24] <= {din[6:0], dat_i};
							7'b010??01: ram[{3'b100, cmd[3:2]}] <= {din[6:0], dat_i};
							7'b1????01: ram[cmd[5:2]] <= {din[6:0], dat_i};
							default: ;
						endcase
					end
				end
			end
		end
	end
end

endmodule