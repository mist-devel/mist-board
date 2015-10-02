// A simple pong game for the MIST FPGA board
// (c) 2015 Till Harbaum

// Lesson 2: A moving ball

module pong (
   input [1:0] CLOCK_27,
   output 		SDRAM_nCS,
   output reg	VGA_HS,
   output reg 	VGA_VS,
   output [5:0] VGA_R,
   output [5:0] VGA_G,
   output [5:0] VGA_B
);
					
// 640x480 60HZ VESA laut http://tinyvga.com/vga-timing/640x480@60Hz
parameter H   = 640;    // width of visible area
parameter HFP = 16;     // unused area before h sync
parameter HS  = 96;     // length of h sync
parameter HBP = 48;     // unused area after h sync

parameter V   = 480;    // height of visible area
parameter VFP = 10;     // unused area before v sync
parameter VS  = 2;      // length of v sync
parameter VBP = 33;     // unused area after v sync

reg[9:0]  h_cnt;        // horizontal pixel counter
reg[9:0]  v_cnt;        // vertical pixel counter

// deactivate unused sdram
assign SDRAM_nCS = 1;

localparam BORDER     = 8;    // height of top and bottom border
localparam BALL_SIZE  = 16;   // width and height of ball
localparam BALL_SPEED = 4;    // step width of ball per v sync

// ball starts in center of visible area
reg [9:0] ball_x = HS + HBP + (H - BALL_SIZE)/2;
reg [9:0] ball_y = VS + VBP + (V - BALL_SIZE)/2;

// balls direction of movement
reg ball_move_x = 1'b1;
reg ball_move_y = 1'b1;

// calculate new ball position each v sync
always@(posedge VGA_VS) begin
	// change horizontal movement if border has been reached
	if(ball_x <  HS+HBP)                    ball_move_x <= 1'b1;
	if(ball_x >= HS+HBP+H-BALL_SIZE)        ball_move_x <= 1'b0;
	
	// horizontal movement
	if(ball_move_x) ball_x <= ball_x + BALL_SPEED;
	else            ball_x <= ball_x - BALL_SPEED;

	// change vertical movement if border has been reached
	if(ball_y <  VS+VBP+BORDER)             ball_move_y <= 1'b1;
	if(ball_y >= VS+VBP+V-BORDER-BALL_SIZE) ball_move_y <= 1'b0;
	
	// vertical movement
	if(ball_move_y) ball_y <= ball_y + BALL_SPEED;
	else            ball_y <= ball_y - BALL_SPEED;
end

// both counters start with the begin of the sync phases

// horizontal pixel counter
always@(posedge pixel_clock) begin
	if(h_cnt==HS+HBP+H+HFP-1)   h_cnt <= 0;
	else                        h_cnt <= h_cnt + 1;

	// generation of the negative h sync signal
	VGA_HS <= (h_cnt >= HS);
end
  
// vertical pixel counter
always@(posedge pixel_clock) begin
	// the vertical state changes at the begin of each line
	if(h_cnt == 0) begin
		if(v_cnt==VS+VBP+V+VFP-1)  v_cnt <= 0; 
		else								v_cnt <= v_cnt + 1;

		// generation of the negative v sync signal
		VGA_VS <= (v_cnt >= VS);
	end
end

// signal indicating the presence of the ball at the current beam position
wire ball = (h_cnt >= ball_x) && (h_cnt < ball_x + BALL_SIZE) &&
				(v_cnt >= ball_y) && (v_cnt < ball_y + BALL_SIZE);

// top and bottom border: is being painted of the beam is horizontally within
// the playing area and vertically within the border area
wire border = (h_cnt >= HS+HBP) && (h_cnt < HS+HBP+H) &&
				 (((v_cnt >= VS+VBP)          && (v_cnt < VS+VBP+BORDER)) ||
				  ((v_cnt >= VS+VBP+V-BORDER) && (v_cnt < VS+VBP+V)));
						
wire pixel = ball || border;

// white if pixel, black otherwise
assign VGA_R = pixel?6'b111111:6'b000000;
assign VGA_G = pixel?6'b111111:6'b000000;
assign VGA_B = pixel?6'b111111:6'b000000;

// pll to generate the VGA pixel clock from the 27Mhz board clock
pll pll (
	 .inclk0(CLOCK_27[0]),
	 .c0(pixel_clock)
 );

endmodule
