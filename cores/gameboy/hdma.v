module hdma(
	input  reset,
   input  clk,    // 8 Mhz cpu clock
	
	// cpu register interface
	input        sel_reg,
	input  [3:0] addr,
	input        wr,
	output [7:0] dout,
	input  [7:0] din,
	
	input [1:0] lcd_mode, 
	
	// dma connection
	output hdma_rd,
	output [15:0] hdma_source_addr,
	output [15:0] hdma_target_addr

);

//ff51-ff55 HDMA1-5 (GBC)
reg [7:0] hdma_source_h;		// ff51
reg [3:0] hdma_source_l;		// ff52 only top 4 bits used
reg [4:0] hdma_target_h;	   // ff53 only lowest 5 bits used
reg [3:0] hdma_target_l;	   // ff54 only top 4 bits used
reg hdma_mode; 					// ff55 bit 7  - 1=General Purpose DMA 0=H-Blank DMA
reg hdma_enabled;					// ff55 !bit 7 when read
reg [7:0] hdma_length;			// ff55 bit 6:0 - dma transfer length (hdma_length+1)*16 bytes
reg hdma_active;

// it takes about 8us to transfer a block of 16 bytes. -> 500ns per byte -> 2Mhz
// 32 cycles in Normal Speed Mode, and 64 'fast' cycles in Double Speed Mode
reg [13:0] hdma_cnt; 
reg [5:0]  hdma_16byte_cnt; //16bytes*4

assign hdma_rd = hdma_active;
assign hdma_source_addr = { hdma_source_h,hdma_source_l,4'd0} + hdma_cnt[13:2];
assign hdma_target_addr = { 3'b100,hdma_target_h,hdma_target_l,4'd0} + hdma_cnt[13:2];

reg [1:0] hdma_state;
parameter active=2'd0,blocksent=2'd1,wait_h=2'd2;

always @(posedge clk) begin
	if(reset) begin
		hdma_active <= 1'b0;
		hdma_state <= wait_h;
		hdma_enabled <= 1'b0;
		hdma_source_h <= 8'hFF;
		hdma_source_l <= 4'hF;
		hdma_target_h <= 5'h1F;
		hdma_target_l <= 4'hF;		
	end else begin
	   if(sel_reg && wr) begin
		
			case (addr)
				4'd1: hdma_source_h <= din;
				4'd2: hdma_source_l <= din[7:4];
				4'd3: hdma_target_h <= din[4:0];
				4'd4: hdma_target_l <= din[7:4];
	
			 
				// writing the hdma register engages the dma engine
				4'h5: begin
							if (hdma_mode == 1 && hdma_enabled && !din[7]) begin  //terminate an active H-Blank transfer by writing zero to Bit 7 of FF55
								hdma_state <= wait_h;
								hdma_active <= 1'b0;
								hdma_enabled <= 1'b0;
							end else begin															  //normal trigger
								hdma_enabled <= 1'b1;
								hdma_mode <= din[7];
								hdma_length <= {1'b0,din[6:0]} + 8'd1;  
								hdma_cnt <= 14'd0; 
								hdma_16byte_cnt <= 6'h3f;
								if (din[7] == 1) hdma_state <= wait_h;
							end
						end
		    endcase
		end
		
		if (hdma_enabled) begin
			if(hdma_mode==0) begin 				                    //mode 0 GDMA do the transfer in one go			
				if(hdma_length != 0) begin
					hdma_active <= 1'b1;
					hdma_cnt <= hdma_cnt + 1'd1;
					hdma_16byte_cnt <= hdma_16byte_cnt - 1'd1;
					if (!hdma_16byte_cnt) begin
							hdma_length <= hdma_length - 1'd1;
							if (hdma_length == 1) begin
								hdma_active <= 1'b0;
								hdma_enabled <= 1'b0;
								hdma_length <= 8'h80; //7f+1
							end
				   end	
				end 

			end else begin        			                       //mode 1 HDMA transfer 1 block (16bytes) in each H-Blank only
				case (hdma_state)
					
					wait_h:    begin 
								    if (lcd_mode == 2'b00 ) 	// Mode 00:  h-blank
									   hdma_state <= active;
								    hdma_16byte_cnt <= 6'h3f;
									 hdma_active <= 1'b0;
							     end
				   
					blocksent: begin
									 if (hdma_length == 0) begin //check if finished
										hdma_enabled <= 1'b0;
										hdma_length <= 8'h80; //7f+1
                            end
									 if (lcd_mode == 2'b11) // wait for mode 3, mode before h-blank
										hdma_state <= wait_h;	
								  end

					active:    begin
									if(hdma_length != 0) begin
										hdma_active <= 1'b1;
										hdma_cnt <= hdma_cnt + 1'd1;
										hdma_16byte_cnt <= hdma_16byte_cnt - 1'd1;
										if (!hdma_16byte_cnt) begin
												hdma_length <= hdma_length - 1'd1;
												hdma_state <= blocksent;
												hdma_active <= 1'b0;
										end
									end else begin
										hdma_active <= 1'b0;
										hdma_enabled <= 1'b0;
										hdma_length <= 8'h80; //7f+1
									end
								 end
				endcase 	
			end
		end
	end
end


wire [7:0] length_m1 = hdma_length - 8'd1;

assign dout =  sel_reg?
					(addr==4'd5)?hdma_enabled?{1'b0,length_m1[6:0]}:
					{1'b1,length_m1[6:0]}:
					8'hFF:
				8'hFF;

endmodule

`timescale 1 ns/100 ps  // time-unit = 1 ns, precision = 100 ps

module hdma_tb;

   // duration for each bit = 125 * timescale = 125 * 1 ns  = 125ns // 8MHz
   localparam period = 125;  

	reg  reset = 1'd1;
	reg  clk = 1'd0;
	
	// cpu register interface
	reg        sel_reg = 1'd0;
	reg  [3:0] addr    = 4'd0;
	reg        wr      = 1'd0;
	wire [7:0] dout;
	reg  [7:0] din     = 8'd0;
	
	reg [1:0] lcd_mode = 2'd0; 
	
	// dma connection
	wire hdma_rd;
	wire [15:0] hdma_source_addr;
	wire [15:0] hdma_target_addr;
	
	
	
	hdma hdma(
		.reset	          ( reset         ),
		.clk		          ( clk           ),
		
		// cpu register interface
		.sel_reg 	       ( sel_reg       ),
		.addr			       ( addr          ),
		.wr			       ( wr	           ),
		.dout			       ( dout       ),
		.din               ( din           ),
		
		.lcd_mode          ( lcd_mode      ),
		
		// dma connection
		.hdma_rd           ( hdma_rd          ),
		.hdma_source_addr  ( hdma_source_addr ),
		.hdma_target_addr  ( hdma_target_addr ) 
		
	);
	
	always #62 clk <= !clk;
	initial begin
		reset <= 1'b0;
		sel_reg <= 1'b1;
		addr <= 4'd4;
		
		#1000 
		
		sel_reg <= 1'b1;
		addr <= 4'd1; // source h
		din <= 8'h20;
		wr <= 1'd1;
		
		#period  
		 wr <= 1'd0;	
		
		#period
	
		sel_reg <= 1'b1;
		addr <= 4'd2; // source l
		din <= 8'h40;
		wr <= 1'd1;
		
		#period
		wr <= 1'd0;	
		
		#period
	
		sel_reg <= 1'b1;
		addr <= 4'd3; // target h
		din <= 8'h82;
		wr <= 1'd1;
		#period
		wr <= 1'd0;	
		
		#period 
	
		sel_reg <= 1'b1;
		addr <= 4'd4; // target l
		din <= 8'h00;
		wr <= 1'd1;
		
		#period
		wr <= 1'd0;	
		
		#period
		$display("GDMA");
		sel_reg <= 1'b1;
		addr <= 4'd5; // trigger GDMA with length 
		din <= 8'h01;  // 20h bytes
		wr <= 1'd1;
		#period
		wr <= 1'd0;	
		
		#8000	
		
		lcd_mode <= 2'd1; 
		#2000
		
		lcd_mode <= 2'd0; 
		#8000
		
		$display("HDMA");
		sel_reg <= 1'b1;
		addr <= 4'd5; // trigger HDMA with length 
		din <= 8'h82;  // 30h bytes
		wr <= 1'd1;
		
		#period
		wr <= 1'd0;	
		
		#16000	
		
		lcd_mode <= 2'd2; 
		#2000
		
		lcd_mode <= 2'd3; 
		#2000
		
		lcd_mode <= 2'd0; 
		#16000

		lcd_mode <= 2'd2; 
		#2000
		
		lcd_mode <= 2'd3; 
		#2000
		
		lcd_mode <= 2'd0; 
		#16000
		
		sel_reg <= 1'b1;
		addr <= 4'd5;
		$display("Check FF55");
				
		#1000 

		$display("HDMA with cancel");
		sel_reg <= 1'b1;
		addr <= 4'd5; // trigger HDMA with length 
		din <= 8'h82;  // 30h bytes
		wr <= 1'd1;
		
		#period
		wr <= 1'd0;
		
		#16000	
		
		lcd_mode <= 2'd2; 
		#2000
		
		lcd_mode <= 2'd3; 
		#2000
		
      $display("canceling");
		sel_reg <= 1'b1;
		addr <= 4'd5; // trigger HDMA with length 
		din <= 8'h00;  // stop
		wr <= 1'd1;
		
		#period
		wr <= 1'd0;	
		
		#16000	
		
		sel_reg <= 1'b1;
		addr <= 4'd5;
		$display("Check FF55");
		
		lcd_mode <= 2'd2; 
		#2000
		
		lcd_mode <= 2'd3; 
		#2000
		$display("Test Complete");
	end  
  
endmodule