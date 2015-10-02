// A simple pong game for the MIST FPGA board
// (c) 2015 Till Harbaum

// Lesson 3: using the joystick

module pong (
   input [1:0] CLOCK_27,
   output 		SDRAM_nCS,

   // spi interface to mists io processor
	output      SPI_DO,
	input       SPI_DI,
	input       SPI_SCK,
	input       CONF_DATA0, 
	
   output reg	VGA_HS,
   output reg 	VGA_VS,
   output [5:0] VGA_R,
   output [5:0] VGA_G,
   output [5:0] VGA_B
);

wire [7:0] joystick_0;
wire [7:0] joystick_1;

// Include user_io.v submodule. This dies the major part of the communication with
// the arm io controller. We are only using the joystick here
user_io user_io ( 
	.SPI_CLK    ( SPI_SCK    ),
	.SPI_SS_IO  ( CONF_DATA0 ),
	.SPI_MISO   ( SPI_DO     ),
	.SPI_MOSI   ( SPI_DI     ),
	
	.joystick_0 ( joystick_0 ),
	.joystick_1 ( joystick_1 )
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

// vertical position of the paddles
localparam PADDLE_WIDTH  = BALL_SIZE;    // width of paddle
localparam PADDLE_HEIGHT = 4*BALL_SIZE;  // heihgt of paddle
localparam PADDLE_SPEED = 4;             // step width of paddle per v sync
reg [9:0] paddle_0_y = VS + VBP + (V - PADDLE_HEIGHT)/2;
reg [9:0] paddle_1_y = VS + VBP + (V - PADDLE_HEIGHT)/2;

// update paddle position every v sync
always@(posedge VGA_VS) begin
        // move left paddle up if it isn't already at the top
	if(joystick_0[3] && (paddle_0_y > VS + VBP + BORDER))
		paddle_0_y <= paddle_0_y - PADDLE_SPEED;

        // move left paddle down if  it isn't already at the bottom
	if(joystick_0[2] && (paddle_0_y < VS + VBP + V - BORDER - PADDLE_HEIGHT))
		paddle_0_y <= paddle_0_y + PADDLE_SPEED;

        // move right paddle up if it isn't already at the top
	if(joystick_1[3] && (paddle_1_y > VS + VBP + BORDER))
		paddle_1_y <= paddle_1_y - PADDLE_SPEED;

        // move right paddle down if  it isn't already at the bottom
	if(joystick_1[2] && (paddle_1_y < VS + VBP + V - BORDER - PADDLE_HEIGHT))
		paddle_1_y <= paddle_1_y + PADDLE_SPEED;
end

// generate collision signals
wire ball_hits_paddle_0 =
	(ball_x < HS+HBP+PADDLE_WIDTH) &&           // ball is in range of left paddle
	(ball_y > paddle_0_y - BALL_SIZE) &&        // ball is below paddles top edge
   (ball_y < paddle_0_y + PADDLE_HEIGHT);      // ball is above paddles bottom edge
	
wire ball_hits_paddle_1 =
	(ball_x > HS+HBP+H-PADDLE_WIDTH-BALL_SIZE) && // ball is in range of right paddle
	(ball_y > paddle_1_y - BALL_SIZE) &&        // ball is below paddles top edge
   (ball_y < paddle_1_y + PADDLE_HEIGHT);      // ball is above paddles bottom edge

wire ball_exits_left  = ball_x <= HS+HBP;       // ball leaves playfield to the left
wire ball_exits_right = ball_x >= HS+HBP+H-BALL_SIZE; // -"- to the right
	
reg game_running = 1'b0;      // game is running

// start/stop of game
always@(posedge VGA_VS) begin
        // check if ball has reached left or right border and stop game if yes
	if(ball_exits_left || ball_exits_right)
		game_running <= 1'b0;
	
	// any fire button starts game
	if(joystick_0[4] || joystick_1[4])
		game_running <= 1'b1;
end

// calculate new ball position each v sync
always@(posedge VGA_VS) begin
        // change horizontal movement if paddle is being hit or if the ball is
        // about to leave the playfield area
	if(ball_hits_paddle_0 || ball_exits_left)  ball_move_x <= 1'b1;
	if(ball_hits_paddle_1 || ball_exits_right) ball_move_x <= 1'b0;

	// change vertical movement if border has been reached
	if(ball_y <  VS+VBP+BORDER)             ball_move_y <= 1'b1;
	if(ball_y >= VS+VBP+V-BORDER-BALL_SIZE) ball_move_y <= 1'b0;

	// move ball as long as game runs
	if(game_running) begin
                // horizontal movement
		if(ball_move_x) ball_x <= ball_x + BALL_SPEED;
		else            ball_x <= ball_x - BALL_SPEED;

		// vertical movement
		if(ball_move_y) ball_y <= ball_y + BALL_SPEED;
		else            ball_y <= ball_y - BALL_SPEED;
	end else begin
		// center ball if game is stopped
		ball_x <= HS + HBP + (H - BALL_SIZE)/2;
		ball_y <= VS + VBP + (V - BALL_SIZE)/2;
	end
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
						
// left paddle (paddle 0) is being drawn
wire paddle_0 = (h_cnt >= HS+HBP) && (h_cnt < HS+HBP+PADDLE_WIDTH) &&
				(v_cnt >= paddle_0_y) && (v_cnt < paddle_0_y + PADDLE_HEIGHT);

// right paddle (paddle 1) is being drawn
wire paddle_1 = (h_cnt >= HS+HBP+H-PADDLE_WIDTH) && (h_cnt < HS+HBP+H) &&
				(v_cnt >= paddle_1_y) && (v_cnt < paddle_1_y + PADDLE_HEIGHT);

wire pixel = ball || border || paddle_0 || paddle_1;

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
