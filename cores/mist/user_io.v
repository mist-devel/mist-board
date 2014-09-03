module user_io( 
	   input      SPI_CLK,
	   input      SPI_SS_IO,
	   output     reg SPI_MISO,
	   input      SPI_MOSI,
	   input [7:0] CORE_TYPE,

		// ikbd tdata from io controller to acia
		output reg       ikbd_strobe_in,
		output reg [7:0] ikbd_data_in,
		
		// ikbd data from acia to io controller
		output reg       ikbd_strobe_out,
		input            ikbd_data_out_available,
		input [7:0]      ikbd_data_out,

		// four extra joysticks
		output reg [5:0] joy0, joy1, joy2, joy3,
		
		// serial data from mfp to io controller
		output reg       serial_strobe_out,
		input            serial_data_out_available,
		input [7:0]      serial_data_out,
		
		// serial data from io controller to mfp
		output reg       serial_strobe_in,
		output reg [7:0] serial_data_in,

		// parallel data from psg/ym to io controller
		output reg       parallel_strobe_out,
		input            parallel_data_out_available,
		input [7:0]      parallel_data_out,

		// midi data from acia to io controller
		output reg       midi_strobe_out,
		input            midi_data_out_available,
		input [7:0]      midi_data_out,

		// ethernet interface
		input [31:0]     eth_status,
		
		// sending mac address from io controller into core
		output reg       eth_mac_begin,
		output reg       eth_mac_strobe,
		output reg [7:0] eth_mac_byte,
		
		output reg       eth_tx_read_begin,
		output reg       eth_tx_read_strobe,
		input [7:0] 	  eth_tx_read_byte,
	
		output reg       eth_rx_write_begin,
		output reg       eth_rx_write_strobe,
		output reg [7:0] eth_rx_write_byte,

		// on-board buttons and dip switches
		output [1:0] 	  BUTTONS,
		output [1:0]     SWITCHES
);

// filter spi clock. the 8 bit gate delay is ~2.5ns in total
wire [7:0] spi_sck_D = { spi_sck_D[6:0], SPI_CLK } /* synthesis keep */;
wire spi_sck = (spi_sck && spi_sck_D != 8'h00) || (!spi_sck && spi_sck_D == 8'hff);

	reg [1:0] 			byte_cnt;
   reg [6:0]         sbuf;
   reg [7:0]         cmd;
   reg [3:0] 	      bit_cnt;       // 0..15
   reg [3:0] 	      but_sw;

	// counter runs 0..7,8..15,8..15,8..15
	wire [2:0] tx_bit = ~(bit_cnt[2:0]);
	
	assign BUTTONS = but_sw[1:0];
	assign SWITCHES = but_sw[3:2];
   
   always@(negedge spi_sck) begin
      if(bit_cnt <= 7)
		  SPI_MISO <= CORE_TYPE[7-bit_cnt];
		else begin
			// ikbd acia->io controller
			if(cmd == 3) begin
				if(!byte_cnt[0])
					SPI_MISO <= ikbd_data_out_available;
				else
					SPI_MISO <= ikbd_data_out[tx_bit];
			end
			
			// serial mfp->io controller
			if(cmd == 5) begin
				if(!byte_cnt[0])
					SPI_MISO <= serial_data_out_available;
				else
					SPI_MISO <= serial_data_out[tx_bit];
			end
			
			// parallel psg/ym->io controller
			if(cmd == 6) begin
				if(!byte_cnt[0])
					SPI_MISO <= parallel_data_out_available;
				else
					SPI_MISO <= parallel_data_out[tx_bit];
			end
			
			// midi->io controller
			if(cmd == 8) begin
				if(!byte_cnt[0])
					SPI_MISO <= midi_data_out_available;
				else
					SPI_MISO <= midi_data_out[tx_bit];
			end
			
			// ethernet status
			if(cmd == 8'h0a)
				SPI_MISO <= eth_status[{~byte_cnt, tx_bit}];

			// read ethernet tx buffer
			if(cmd == 8'h0b)
				SPI_MISO <= eth_tx_read_byte[tx_bit];
		end
	end
		
   always@(posedge spi_sck, posedge SPI_SS_IO) begin
		if(SPI_SS_IO == 1) begin
        bit_cnt <= 4'd0;
		  byte_cnt <= 2'd0;
		  
		  // ikbd (kbd, joysticks, mouse)
		  ikbd_strobe_in <= 1'b0;
		  ikbd_strobe_out <= 1'b0;
		  
		  // USB redirection ports (serial/parallel/midi)
		  serial_strobe_out <= 1'b0;
		  parallel_strobe_out <= 1'b0;
		  midi_strobe_out <= 1'b0;
		  
		  // ethernet
		  eth_mac_begin <= 1'b0;
		  eth_mac_strobe <= 1'b0;
		  eth_tx_read_begin <= 1'b0;
		  eth_tx_read_strobe <= 1'b0;
		  eth_rx_write_begin <= 1'b0;
		  eth_rx_write_strobe <= 1'b0;
		  
		end else begin
			sbuf[6:1] <= sbuf[5:0];
			sbuf[0] <= SPI_MOSI;

			// count 0-7 8-15 8-15 8-15
			if(bit_cnt != 4'd15)
				bit_cnt <= bit_cnt + 4'd1;
			else begin
				bit_cnt <= 4'd8;
				byte_cnt <= byte_cnt + 2'd1;
			end

			// command byte finished
	      if(bit_cnt == 7) begin
			   cmd[7:1] <= sbuf; 
				cmd[0] <= SPI_MOSI;
				
				// just finished the mac command byte? -> set begin flag
				if( { sbuf, SPI_MOSI} == 8'h09 )
					eth_mac_begin <= 1'b1;
					
				if( { sbuf, SPI_MOSI} == 8'h0b ) begin
					eth_tx_read_begin <= 1'b1;
					eth_tx_read_strobe <= 1'b1;
				end
				
				if( { sbuf, SPI_MOSI} == 8'h0c )
					eth_rx_write_begin <= 1'b1;
		   end	

			if(bit_cnt == 9) begin
				ikbd_strobe_in <= 1'b0;
				ikbd_strobe_out <= 1'b0;
				
				serial_strobe_in <= 1'b0;
				serial_strobe_out <= 1'b0;
				parallel_strobe_out <= 1'b0;
				midi_strobe_out <= 1'b0;
				
				eth_mac_strobe <= 1'b0;
				eth_tx_read_strobe <= 1'b0;
				eth_rx_write_strobe <= 1'b0;
			end
			
			// payload byte finished
	      if(bit_cnt == 15) begin
				eth_mac_begin <= 1'b0;

				if(cmd == 1) begin
					 but_sw[3:1] <= sbuf[2:0]; 
					 but_sw[0] <= SPI_MOSI; 
				end

				// send ikbd byte to acia
			   if(cmd == 2) begin
					 ikbd_data_in <= { sbuf, SPI_MOSI }; 
					 ikbd_strobe_in <= 1'b1;
				end

				// give strobe after second ikbd byte (byte_cnt[0] == 1)
			   if((cmd == 3) && byte_cnt[0])
					 ikbd_strobe_out <= 1'b1;

				// send serial byte to mfp
			   if(cmd == 4) begin
					 serial_data_in <= { sbuf, SPI_MOSI }; 
					 serial_strobe_in <= 1'b1;
				end
				
				// give strobe after second serial byte (byte_cnt[0]==1)
			   if((cmd == 5) && byte_cnt[0])
					 serial_strobe_out <= 1'b1;
					 
				// give strobe after second parallel byte (byte_cnt[0]==1)
			   if((cmd == 6) && byte_cnt[0])
					 parallel_strobe_out <= 1'b1;
					 
				// give strobe after second midi byte (byte_cnt[0]==1)
			   if((cmd == 8) && byte_cnt[0])
					 midi_strobe_out <= 1'b1;
					 
				// send mac address byte to ethernet controller
			   if(cmd == 9) begin
					 eth_mac_byte <= { sbuf, SPI_MOSI }; 
					 eth_mac_strobe <= 1'b1;
				end
				  
				// give strobe after each eth byte read
			   if(cmd == 8'h0b)
					 eth_tx_read_strobe <= 1'b1;
					 
				// give strobe after each eth byte written
			   if(cmd == 8'h0c) begin
					 eth_rx_write_byte <= { sbuf, SPI_MOSI }; 
					 eth_rx_write_strobe <= 1'b1;
//					 eth_rx_write_begin <= 1'b1;
				end

				// four extra joysticks ...
				if(cmd == 8'h10)
					 joy0 <= { sbuf[4:0], SPI_MOSI }; 

				if(cmd == 8'h11)
					 joy1 <= { sbuf[4:0], SPI_MOSI }; 

				if(cmd == 8'h12)
					 joy2 <= { sbuf[4:0], SPI_MOSI }; 

				if(cmd == 8'h13)
					 joy3 <= { sbuf[4:0], SPI_MOSI }; 

			 end
		end
	end
      
endmodule
