// Ein einfaches System-on-a-chip (SOC)
// (c) 2015 Till Harbaum

// Einfacher VGA-Controller mit 160x100 Pixeln. Der zugrunde liegende VGA-Modus 
// von 640x400 Pixel wird durch Zusammenfassung von je view Zeilen uns Spalten
// zu 160x100 Pixel "Retro-Auflösung". Das Abdunkeln jeder zweiten Zeile erzeugt
// Röhren-Fernseher-artige "Scanlines"

// http://tinyvga.com/vga-timing/640x400@70Hz

module vga (
   // Pixeltakt
   input  pclk,
	
	// Prozessorschnittstelle
	input  cpu_clk,
	input  cpu_wr,
	input [13:0] cpu_addr,
	input [7:0] cpu_data,
	
	// Ausgang zum VGA-Bildschirm
   output reg	hs,
   output reg 	vs,
   output [5:0] r,
   output [5:0] g,
   output [5:0] b
);
					
// 640x400 70HZ VESA laut http://tinyvga.com/vga-timing/640x400@70Hz
parameter H   = 640;    // Breite des sichtbaren Bereiches
parameter HFP = 16;     // Nicht nutzbarer Bereich vor H-Sync
parameter HS  = 96;     // Breite des H-Sync
parameter HBP = 48;     // Nicht nutzbarer Bereich nach H-Sync

parameter V   = 400;    // Höhe des sichtbaren Bereiches
parameter VFP = 12;     // Nicht nutzbarer Bereich vor V-Sync
parameter VS  = 2;      // Höhe des V-Sync
parameter VBP = 35;     // Nicht nutzbarer Bereich nach V-Sync

reg[9:0]  h_cnt;        // horizontaler Pixelzaehler
reg[9:0]  v_cnt;        // vertikaler Pixelzaehler

// Beide Zaehler starten mit dem Beginn des sichtbaren Bildbereiches

// horizontaler Pixelzaehler
always@(posedge pclk) begin
	if(h_cnt==H+HFP+HS+HBP-1)   h_cnt <= 10'd0;
	else                        h_cnt <= h_cnt + 10'd1;

	// Erzeugung des negativen H-Sync-Signals
	if(h_cnt == H+HFP)    hs <= 1'b0;
	if(h_cnt == H+HFP+HS) hs <= 1'b1;
end

// vertikaler Pixelzaehler
always@(posedge pclk) begin
	// der vertikale Zustand aendert sich am Anfang jeder Zeile
	if(h_cnt == H+HFP) begin
		if(v_cnt==VS+VBP+V+VFP-1)  v_cnt <= 10'd0; 
		else								v_cnt <= v_cnt + 10'd1;

		// Erzeugung des positiven V-Sync-Signals
		if(v_cnt == V+VFP)    vs <= 1'b1;
		if(v_cnt == V+VFP+VS) vs <= 1'b0;
	end
end

// 16000 Bytes interner Videospeicher fuer 160x100 Pixel je 8 Bit (RGB 332)
reg [7:0] vmem [160*100-1:0];

reg [13:0] video_counter;
reg [7:0] pixel;

// VRAM schreiben vis CPU-Schnittstelle
always @(posedge cpu_clk)
	if(cpu_wr) 
		vmem[cpu_addr] <= cpu_data;

// VRAM lesen zur Bilddarstellung
always@(posedge pclk) begin
	// Videozaehler wird zu Beginn des V-Sync zurueckgeetzt, ansonsten
	// im sichtbaren Bereich bei jedem vierten Pixel hochgezaehlt. Am Ende
	// der ersten drei von vier Zeilen wird der Zaehler wieder um eine Zeile
	// zurueck gesetzt, da jeweils vier der 400 VGA-Zeilen gleich angezeigt 
	// werden, um auf 100 Pixelzeilen zu kommen

	// sichtbarer Bildbereich?
	if((v_cnt < V) && (h_cnt < H)) begin
		// Videozaehler nach jedem vierten Pixel erhoehen
		if(h_cnt[1:0] == 2'd3)
			video_counter <= video_counter + 14'd1;
		
		pixel <= vmem[video_counter];               // Speicherinhalt lesen
	end else begin
		// Zaehlermanipulation am Ende der Zeile ausserhalb
		// des sichtbaren Bereiches
		if(h_cnt == H+HFP) begin
			// am Beginn des V-Sync Videozaehler zurueck setzen. Am Ende der
			// ersten drei von vier Zeilen den Zaehler eine Zeile zurueck setzen,
			// um jede Zeile insgesamt viermal auszugeben
			if(v_cnt == V+VFP)
				video_counter <= 14'd0;
			else if((v_cnt < V) && (v_cnt[1:0] != 2'd3))
				video_counter <= video_counter - 14'd160;
		end
			
		pixel <= 8'h00;   // Farbe ausserhalb des sichtbaren Bereiches: schwarz
	end
end

// Aufteilen der 8 RGB-Bits auf die drei Grundfarben, jede zweite Zeile abdunkeln
// fuer "Scanlines"
assign r = v_cnt[0]?{ pixel[7:5],  3'b000 }:{ 1'b0, pixel[7:5],  2'b00 };
assign g = v_cnt[0]?{ pixel[4:2],  3'b000 }:{ 1'b0, pixel[4:2],  2'b00 };
assign b = v_cnt[0]?{ pixel[1:0], 4'b0000 }:{ 1'b0, pixel[1:0], 3'b000 };

endmodule
