// http://www.computer-engineering.org/ps2mouse/

module mouse ( 
	input clk,
	input reset,

	// ps2 interface	
	input ps2_clk,
	input ps2_data,
	
	// decodes keys
	output [7:0] x,
	input clr_x,
	output [7:0] y,
	input clr_y,
	output reg [1:0] b
);

assign x = x_pos[9:2];
assign y = y_pos[9:2];
reg [9:0] x_pos;
reg [9:0] y_pos;

wire [7:0] byte;
wire valid;
wire error;

reg [1:0] cnt;

reg sign_x, sign_y;
reg [7:0] x_reg;

always @(posedge clk) begin
	if(reset) begin
		x_pos <= 10'd0;
		y_pos <= 10'd0;
		cnt <= 2'd0;
	end else begin
		// ps2 decoder has received a valid byte
		if(valid) begin
			// count through all three data bytes
			cnt <= cnt + 2'd1;
				
			if(cnt == 0) begin
				// bit 3 must be 1. Stay in state 0 otherwise
				if(!byte[3]) cnt <= 2'd0;
				b <= byte[1:0];
				sign_x <= byte[4];
				sign_y <= byte[5];
			end else if(cnt == 1) begin
				x_reg <= byte;
			end else begin
				// the ps2 packet contains a 9 bit value. We only use the upper 
				// 7. Otherwise the mouse would be too fast for our low resolution
				x_pos <= x_pos + { {2{sign_x}}, x_reg};
				y_pos <= y_pos + { {2{sign_y}},  byte};
				cnt <= 2'd0;
			end
		end
		
		// only the upper 8 bits of the 10 bit mouse position are reported byck to the
		// cpu
		if(clr_x) x_pos[9:2] <= 8'd0;
		if(clr_y) y_pos[9:2] <= 8'd0;
	end
end

// the ps2 decoder has been taken from the zx spectrum core
ps2_intf ps2_keyboard (
	.CLK		 ( clk             ),
	.nRESET	 ( !reset          ),
	
	// PS/2 interface
	.PS2_CLK  ( ps2_clk         ),
	.PS2_DATA ( ps2_data        ),
	
	// Byte-wide data interface - only valid for one clock
	// so must be latched externally if required
	.DATA		  ( byte   ),
	.VALID	  ( valid  ),
	.ERROR	  ( error  )
);


endmodule
