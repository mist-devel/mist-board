// Ein einfaches Pong-Spiel fuer das MiST-FPGA-Board
// (c) 2015 Till Harbaum

// Lektion 2: Beweglicher Ball

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

// Ball startet im Zentrum des sichtbaren Bildschirmbereiches
reg [9:0] ball_x = HS + HBP + (H - BALL_SIZE)/2;
reg [9:0] ball_y = VS + VBP + (V - BALL_SIZE)/2;

// Bewegungsrichtung des Balls
reg ball_move_x = 1'b1;
reg ball_move_y = 1'b1;

// Berechne neue Ballposition bei jedem VSync
always@(posedge VGA_VS) begin
	// Änderung der horizontalen Bewegung, wenn der Rand erreicht ist
	if(ball_x <  HS+HBP)                    ball_move_x <= 1'b1;
	if(ball_x >= HS+HBP+H-BALL_SIZE)        ball_move_x <= 1'b0;
	
	// horizontale Ballbewegung
	if(ball_move_x) ball_x <= ball_x + BALL_SPEED;
	else            ball_x <= ball_x - BALL_SPEED;

	// Änderung der vertikalen Bewegung, wenn der Rand erreicht ist
	if(ball_y <  VS+VBP+BORDER)             ball_move_y <= 1'b1;
	if(ball_y >= VS+VBP+V-BORDER-BALL_SIZE) ball_move_y <= 1'b0;
	
	// vertikale Ballbewegung
	if(ball_move_y) ball_y <= ball_y + BALL_SPEED;
	else            ball_y <= ball_y - BALL_SPEED;
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
						
wire pixel = ball || border;

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
