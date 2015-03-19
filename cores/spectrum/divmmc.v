// divmmc

module divmmc (
	input        	reset_n,
	input        	clk,
	input        	clken,

	// Bus interface
	input          enable,
	input  [15:0] 	a,
	input          wr_n,
	input          rd_n,
	input          mreq_n,
	input          m1_n,
	input  [7:0]  	din,
	output [7:0]  	dout,
	
	// memory state
	output reg     paged_in,
	output [3:0]   sram_page,
	output         mapram,
	output         conmem,
	
	// SD card interface
	output reg     sd_cs,
	output         sd_sck,
	output         sd_mosi,
	input          sd_miso
);

reg m1_trigger;

assign sram_page = ctrl[3:0];
assign mapram = ctrl[6];
assign conmem = ctrl[7];
reg [7:0] ctrl;

// Control del modulo SPI
reg spi_tx_strobe;
reg spi_rx_strobe;

reg [7:0] acc_cnt /* synthesis noprune */;
always @(posedge enable or negedge reset_n) begin
	if(reset_n == 1'b0)
		acc_cnt <= 8'd0;
	else
		acc_cnt <= acc_cnt + 8'd1;
end

always @(posedge clk) begin
	if(reset_n == 1'b0) begin
		m1_trigger <= 1'b0;
		paged_in <= 1'b0;
		ctrl <= 8'h00;
		sd_cs <= 1'b1;
	end else begin
		spi_rx_strobe = 1'b0;
		spi_tx_strobe = 1'b0;
			
		if (a[3:0]==4'h3 && enable && !wr_n)
			ctrl <= din;
			
		if(a[3:0]==4'h7 && enable && !wr_n)
			sd_cs <= din[0];

		// SPI read/write
		if(enable && a[3:0]==4'hb) begin
			if(wr_n) spi_rx_strobe = 1'b1;
			else     spi_tx_strobe = 1'b1;
		end

		if (!mreq_n && !rd_n && !m1_n && 
			((a==16'h0000) || (a==16'h0008) || (a==16'h0038) ||
			 (a==16'h0066) || (a==16'h04C6) || (a==16'h0562))) begin
			// activate automapper after this cycle
			m1_trigger <= 1'b1;
		end else if (!mreq_n && !rd_n && !m1_n && a[15:8]==8'h3D) begin
			// activate automapper immediately
			paged_in <= 1'b1;
			m1_trigger <= 1'b1;
		end else if (!mreq_n && !rd_n && !m1_n && {a[15:3],3'd0} == 16'h1ff8) begin
			// deactivate automapper after this cycle
			m1_trigger <= 1'b0;
		end
	
		if (m1_n==1'b1)
			paged_in <= m1_trigger;
	end
end

spi mi_spi (
   .clk(clk),
   .tx_strobe(spi_tx_strobe),
   .rx_strobe(spi_rx_strobe),
   .din(din),
   .dout(dout),
   
   .spi_clk(sd_sck),
   .spi_di(sd_miso),
   .spi_do(sd_mosi)
);

endmodule
