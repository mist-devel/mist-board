// Ein einfaches Pong-Spiel fuer das MiST-FPGA-Board
// (c) 2015 Till Harbaum

// Lektion 3: Joystick

module pong (
   input [1:0] CLOCK_27,
   output 		SDRAM_nCS,

   // SPI-Schnittstelle zum IO-Prozessor
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

// Einbindung des user_io.v-Submoduls. Dieses erledigt einen grossen Teil der
// Kommunikation mit dem ARM-IO-Controller des MiST. Wir verwenden hier nur die
// Joysticks
user_io user_io ( 
	.SPI_CLK    ( SPI_SCK    ),
	.SPI_SS_IO  ( CONF_DATA0 ),
	.SPI_MISO   ( SPI_DO     ),
	.SPI_MOSI   ( SPI_DI     ),
	
	.joystick_0 ( joystick_0 ),
	.joystick_1 ( joystick_1 )
);


				
// 640x480 60HZ VESA laut http://tinyvga.com/vga-timing/640x480@60Hz
parameter H   = 640;    // Breite des sichtbaren Bereiches
parameter HFP = 16;     // Nicht nutzbarer Bereich vor H-Sync
parameter HS  = 96;     // Breite des H-Sync
parameter HBP = 48;     // Nicht nutzbarer Bereich nach H-Sync

parameter V   = 480;    // Höhe des sichtbaren Bereiches
parameter VFP = 10;     // Nicht nutzbarer Bereich vor V-Sync
parameter VS  = 2;      // Höhe des V-Sync
parameter VBP = 33;     // Nicht nutzbarer Bereich nach V-Sync

reg[9:0]  h_cnt;        // horizontaler Pixelzaehler
reg[9:0]  v_cnt;        // vertikaler Pixelzaehler

// Deaktivieren des unbenutzten SDRAMs
assign SDRAM_nCS = 1;

localparam BORDER     = 8;    // Höhe des oberen/unteren Randes
localparam BALL_SIZE  = 16;   // Breite und Höse des Balls
localparam BALL_SPEED = 4;    // Schrittweite des Balles pro V-Sync

// Ballposition
reg [9:0] ball_x, ball_y;

// Bewegungsrichtung des Balls
reg ball_move_x = 1'b1;
reg ball_move_y = 1'b1;

// vertikale Position der Paddles

localparam PADDLE_WIDTH  = BALL_SIZE;    // Breite des Spielerpaddles
localparam PADDLE_HEIGHT = 4*BALL_SIZE;  // Höhe des Spielerpaddles
localparam PADDLE_SPEED = 4;             // Schrittweite des Paddles pro V-Sync
reg [9:0] paddle_0_y = VS + VBP + (V - PADDLE_HEIGHT)/2;
reg [9:0] paddle_1_y = VS + VBP + (V - PADDLE_HEIGHT)/2;

// aktualisiere Paddle-Position in jedem V-Sync
always@(posedge VGA_VS) begin
	// bewege linkes Paddle zum oberen Rand, wenn es dort noch nicht angekommen ist
	if(joystick_0[3] && (paddle_0_y > VS + VBP + BORDER))
		paddle_0_y <= paddle_0_y - PADDLE_SPEED;

	// bewege linkes Paddle zum unteren Rand, wenn es dort noch nicht angekommen ist
	if(joystick_0[2] && (paddle_0_y < VS + VBP + V - BORDER - PADDLE_HEIGHT))
		paddle_0_y <= paddle_0_y + PADDLE_SPEED;

	// bewege rechtes Paddle zum oberen Rand, wenn es dort noch nicht angekommen ist
	if(joystick_1[3] && (paddle_1_y > VS + VBP + BORDER))
		paddle_1_y <= paddle_1_y - PADDLE_SPEED;

	// bewege rechtes Paddle zum unteren Rand, wenn es dort noch nicht angekommen ist
	if(joystick_1[2] && (paddle_1_y < VS + VBP + V - BORDER - PADDLE_HEIGHT))
		paddle_1_y <= paddle_1_y + PADDLE_SPEED;
end

// erzeuge Kollisionssignale
wire ball_hits_paddle_0 =
	(ball_x < HS+HBP+PADDLE_WIDTH) &&           // Ball ist im Bereich des linken Paddles
	(ball_y > paddle_0_y - BALL_SIZE) &&        // Ball ist niedriger als Oberkante des Paddles
   (ball_y < paddle_0_y + PADDLE_HEIGHT);      // Ball ist hoeher als Unterkante des Paddles
	
wire ball_hits_paddle_1 =
	(ball_x > HS+HBP+H-PADDLE_WIDTH-BALL_SIZE) && // Ball ist im Bereich des rechten Paddles
	(ball_y > paddle_1_y - BALL_SIZE) &&        // Ball ist niedriger als Oberkante des Paddles
   (ball_y < paddle_1_y + PADDLE_HEIGHT);      // Ball ist hoeher als Unterkante des Paddles

wire ball_exits_left  = ball_x <= HS+HBP;       // Ball verlaesst Spielfeld nach links
wire ball_exits_right = ball_x >= HS+HBP+H-BALL_SIZE; // -"- nach rechts
	
reg game_running = 1'b0;      // Spiel ist gestartet

// start/stop des Spiels
always@(posedge VGA_VS) begin
	// Teste, ob de Ball den linke oder rechten Rand erreicht hat und stoppe
	// des Spiel falls ja
	if(ball_exits_left || ball_exits_right)
		game_running <= 1'b0;
	
	// jeder Feuer-Button startet des Spiel
	if(joystick_0[4] || joystick_1[4])
		game_running <= 1'b1;
end

// Berechne neue Ballposition bei jedem VSync
always@(posedge VGA_VS) begin
	// Aenderung der horizontalen Bewegung, wenn ein Paddle getroffen wird oder
	// wenn der Ball das Spielfeld zu verlassen droht
	if(ball_hits_paddle_0 || ball_exits_left)  ball_move_x <= 1'b1;
	if(ball_hits_paddle_1 || ball_exits_right) ball_move_x <= 1'b0;

	// Änderung der vertikalen Bewegung, wenn der Rand erreicht ist
	if(ball_y <  VS+VBP+BORDER)             ball_move_y <= 1'b1;
	if(ball_y >= VS+VBP+V-BORDER-BALL_SIZE) ball_move_y <= 1'b0;

	// bewege Ball solange Spiel laeuft
	if(game_running) begin
		// horizontale Ballbewegung
		if(ball_move_x) ball_x <= ball_x + BALL_SPEED;
		else            ball_x <= ball_x - BALL_SPEED;

		// vertikale Ballbewegung
		if(ball_move_y) ball_y <= ball_y + BALL_SPEED;
		else            ball_y <= ball_y - BALL_SPEED;
	end else begin
		// Spiel ist gestoppt: Ball in die Mitte
		ball_x <= HS + HBP + (H - BALL_SIZE)/2;
		ball_y <= VS + VBP + (V - BALL_SIZE)/2;
	end
end

// Beide Zaehler starten mit dem Beginn des Sync-Impulses

// horizontaler Pixelzaehler
always@(posedge pixel_clock) begin
	if(h_cnt==HS+HBP+H+HFP-1)   h_cnt <= 0;
	else                        h_cnt <= h_cnt + 1;

	// Erzeugung des negativen H-Sync-Signals
	VGA_HS <= (h_cnt >= HS);
end
  
// vertikaler Pixelzaehler
always@(posedge pixel_clock) begin
	// der vertikale Zustand aendert sich am Anfang jeder Zeile
	if(h_cnt == 0) begin
		if(v_cnt==VS+VBP+V+VFP-1)  v_cnt <= 0; 
		else								v_cnt <= v_cnt + 1;

		// Erzeugung des negativen V-Sync-Signals
		VGA_VS <= (v_cnt >= VS);
	end
end

// Signal, das anzeigt, wenn der Elektronenstrahl gerade den Ball zeichnet
wire ball = (h_cnt >= ball_x) && (h_cnt < ball_x + BALL_SIZE) &&
				(v_cnt >= ball_y) && (v_cnt < ball_y + BALL_SIZE);

// Oberer und unterer Rand wird gezeichnet: Elektronenstrahl befindet sich 
// im horizontalen Spielfeldbereich und entweder innerhalb des oberen  
// Randbereiches oder des unteren 
wire border = (h_cnt >= HS+HBP) && (h_cnt < HS+HBP+H) &&
				 (((v_cnt >= VS+VBP)          && (v_cnt < VS+VBP+BORDER)) ||
				  ((v_cnt >= VS+VBP+V-BORDER) && (v_cnt < VS+VBP+V)));
						
// linkes Paddle (paddle 0) wird vom Elektronenstrahl gezeichnet
wire paddle_0 = (h_cnt >= HS+HBP) && (h_cnt < HS+HBP+PADDLE_WIDTH) &&
				(v_cnt >= paddle_0_y) && (v_cnt < paddle_0_y + PADDLE_HEIGHT);

// rechtes Paddle (paddle 1) wird vom Elektronenstrahl gezeichnet
wire paddle_1 = (h_cnt >= HS+HBP+H-PADDLE_WIDTH) && (h_cnt < HS+HBP+H) &&
				(v_cnt >= paddle_1_y) && (v_cnt < paddle_1_y + PADDLE_HEIGHT);

wire pixel = ball || border || paddle_0 || paddle_1;

// Weiss, wenn "pixel" sonst schwarz
assign VGA_R = pixel?6'b111111:6'b000000;
assign VGA_G = pixel?6'b111111:6'b000000;
assign VGA_B = pixel?6'b111111:6'b000000;

// PLL, um aus den 27MHz den VGA-Pixeltakt zu erzeugen
pll pll (
	 .inclk0(CLOCK_27[0]),
	 .c0(pixel_clock)
 );

endmodule
