
module sid_envelope
(
	input            clock,
	input            ce_1m,

	input            reset,
	input            gate,
	input     [ 7:0] att_dec,
	input     [ 7:0] sus_rel,

	output reg [7:0] envelope
);

// Internal Signals
reg  [ 1:0] state;
reg         gate_edge;
reg  [14:0] rate_counter;
reg  [14:0] rate_period;
wire [14:0] adsrtable [0:15];
reg  [ 7:0] exponential_counter;
reg  [ 7:0] exponential_counter_period;
reg         hold_zero;
reg         envelope_pipeline;

`define ST_ATTACK  2'b00
`define ST_DEC_SUS 2'b01
`define ST_RELEASE 2'b10

assign adsrtable[4'h0] = 15'h007f;
assign adsrtable[4'h1] = 15'h3000;
assign adsrtable[4'h2] = 15'h1e00;
assign adsrtable[4'h3] = 15'h0660;
assign adsrtable[4'h4] = 15'h0182;
assign adsrtable[4'h5] = 15'h5573;
assign adsrtable[4'h6] = 15'h000e;
assign adsrtable[4'h7] = 15'h3805;
assign adsrtable[4'h8] = 15'h2424;
assign adsrtable[4'h9] = 15'h2220;
assign adsrtable[4'ha] = 15'h090c;
assign adsrtable[4'hb] = 15'h0ecd;
assign adsrtable[4'hc] = 15'h010e;
assign adsrtable[4'hd] = 15'h23f7;
assign adsrtable[4'he] = 15'h5237;
assign adsrtable[4'hf] = 15'h64a8;

// State Logic
always @(posedge clock) begin
	if (reset)
		state <= `ST_RELEASE;
	else if(ce_1m) begin
		if (gate_edge != gate)
			if (gate) state <= `ST_ATTACK;
			else state <= `ST_RELEASE;

			if (((rate_counter == rate_period) &&
				(state == `ST_ATTACK ||
				(exponential_counter + 1'b1) == exponential_counter_period) &&
				(!hold_zero)))
				case (state)
					`ST_ATTACK: if (envelope + 1'b1 == 8'hff) state <= `ST_DEC_SUS;
				endcase
	end
end

// Gate Switch Detection
always @(posedge clock) begin
	if (reset) gate_edge <= 1'b0;
	else if(ce_1m) begin
		if (gate_edge != gate) gate_edge <= gate;
	end
end

// Envelope
always @(posedge clock) begin
	if (reset)
		envelope <= 8'h00;
	else if(ce_1m) begin
		if (envelope_pipeline) envelope <= envelope - 1'b1;
		if (((rate_counter == rate_period) &&
         (state == `ST_ATTACK ||
         (exponential_counter + 1'b1) == exponential_counter_period) &&
         (!hold_zero)))
			case (state)
				 `ST_ATTACK: envelope <= envelope + 1'b1;
				`ST_DEC_SUS: if (envelope != {2{sus_rel[7:4]}} && exponential_counter_period == 1) envelope <= envelope - 1'b1;
				`ST_RELEASE: if (exponential_counter_period == 1) envelope <= envelope - 1'b1;            
			endcase      
	end
end

// Envelope Pipeline
always @(posedge clock) begin
	if (reset)
		envelope_pipeline <= 1'b0;
	else if(ce_1m) begin
		if (gate_edge != gate)
			if (gate) envelope_pipeline <= 1'b0;
			if (envelope_pipeline) envelope_pipeline <= 1'b0;
			if (((rate_counter == rate_period) &&
				(state == `ST_ATTACK ||
				(exponential_counter + 1'b1) == exponential_counter_period) &&
				(!hold_zero)))
				case (state)
					`ST_DEC_SUS: if (envelope != {2{sus_rel[7:4]}} && exponential_counter_period != 1) envelope_pipeline <= 1'b1;
					`ST_RELEASE: if(exponential_counter_period != 1) envelope_pipeline <= 1'b1;
				endcase
	end
end

// Exponential Counter
always @(posedge clock) begin
	if (reset)
		exponential_counter <= 8'h00;
	else if(ce_1m) begin
      if (rate_counter == rate_period) begin
			exponential_counter <= exponential_counter + 1'b1;
			if (state == `ST_ATTACK || (exponential_counter + 1'b1) == exponential_counter_period) exponential_counter <= 8'h00;
		end
	end
end

// Exponential Counter Period
always @(posedge clock) begin
	if (reset) begin
		hold_zero <= 1'b1;
		exponential_counter_period <= 8'h00;
	end
	else if(ce_1m) begin
		if (gate_edge != gate) if (gate) hold_zero <= 1'b0;
		if ((envelope_pipeline) || ((rate_counter == rate_period) &&
         (state == `ST_ATTACK ||
         (exponential_counter + 1'b1) == exponential_counter_period) &&
         (!hold_zero)))
			begin
				case (state == `ST_ATTACK ? envelope + 1'b1 : envelope - 1'b1)
					8'hff: exponential_counter_period <= 8'd1;
					8'h5d: exponential_counter_period <= 8'd2;
					8'h36: exponential_counter_period <= 8'd4;
					8'h1a: exponential_counter_period <= 8'd8;
					8'h0e: exponential_counter_period <= 8'd16;
					8'h06: exponential_counter_period <= 8'd30;
					8'h00: begin
						exponential_counter_period <= 8'd1;
						hold_zero <= 1'b1;
					end
				endcase
			end
	end
end

// Rate Counter
always @(posedge clock) begin
	if (reset) rate_counter <= 15'h7fff;
	else if(ce_1m) begin
		if (rate_counter == rate_period) rate_counter <= 15'h7fff;
		else rate_counter <= {rate_counter[1] ^ rate_counter[0], rate_counter[14:1]};
	end
end

// Rate Period
always @(posedge clock) begin
	if (reset)
		rate_period <= adsrtable[sus_rel[3:0]];
	else if(ce_1m) begin
		if (gate_edge != gate) begin
			if (gate) rate_period <= adsrtable[att_dec[7:4]];
			else rate_period <= adsrtable[sus_rel[3:0]];
		end
		case (state)
			 `ST_ATTACK: rate_period <= adsrtable[att_dec[7:4]];
			`ST_DEC_SUS: rate_period <= adsrtable[att_dec[3:0]];
			    default: rate_period <= adsrtable[sus_rel[3:0]];
      endcase
	end
end

endmodule
