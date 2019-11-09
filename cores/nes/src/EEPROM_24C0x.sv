// 24C01, 24C02 EEPROM support
// by GreyRogue for NES MiSTer

module EEPROM_24C0x 
  (//Replace type_24C01 with EEPROM size and command size (Test State y/n and address bytes)?
   input type_24C01,          //24C01 is 128 bytes/no Test State?, 24C02 is 256 bytes/Test State
   input clk, input ce, input reset,
   input SCL,                 // Serial Clock
   input SDA_in,              // Serial Data (same pin as below, split for convenience)
   output reg SDA_out,        // Serial Data (same pin as above, split for convenience)
   input [2:0] E_id,          // Chip Enable ID
   input WC_n,                // ~Write Control
   input [7:0] data_from_ram, // Data read from RAM
   output [7:0] data_to_ram,  // Data written to RAM
   output [7:0] ram_addr,     // RAM Address
   output reg ram_read,       // RAM read
   output reg ram_write,      // RAM write
   input ram_done);           // RAM access done

typedef enum bit [2:0] { STATE_STANDBY, STATE_TEST, STATE_ADDRESS, STATE_WRITE, STATE_READ } mystate;
mystate state;

  reg [9:0] command;
  reg [7:0] address;
  reg [8:0] data; // 8 bits data, plus ack bit
  reg last_SCL;
  reg last_SDA;
  //Some 24C01 documents show it working with a test state, instead of combined address/read/write.
  //If these are used, NoTestState needs to be an input to the module, not just derived from the type.
  wire NoTestState = type_24C01;

  always @(posedge clk) if (reset) begin
    state <= STATE_STANDBY;
	 command <= 0;
	 last_SCL <= 0;
	 last_SDA <= 0;
	 SDA_out <= 1;  //NoAck
    ram_read <= 0;
    ram_write <= 0;
  end else if (ce) begin
	 last_SCL <= SCL;
	 last_SDA <= SDA_in;
    if (ram_write && ram_done) begin
	   ram_write <= 0;
		address[3:0] <= address[3:0] + 4'b1; //Increment wraps at 16 byte boundary
    end
    if (ram_read && ram_done) begin
	   ram_read <= 0;
		data <= {data_from_ram, 1'b1};  //NoAck at end
		address <= address + 8'b1;
    end
    if (SCL && last_SCL && !SDA_in && last_SDA) begin
		if (NoTestState)
		  state <= STATE_ADDRESS;
		else
	     state <= STATE_TEST;
		command <= 10'd2;
    end else if (SCL && last_SCL && SDA_in && !last_SDA) begin
      state <= STATE_STANDBY;
		command <= 10'd0;
    end else if (state == STATE_STANDBY) begin
	   // Do nothing
    end else if (SCL && !last_SCL) begin
	   command <= {command[8:0], SDA_in };
    end else if (!SCL && last_SCL) begin
		SDA_out <= 1;  //NoAck
		if (state == STATE_READ) begin
		  SDA_out <= data[8];
		  if (!ram_read) begin
		    data[8:1] <= data[7:0];
		  end
		end
	   if (command[9]) begin
		  if (state == STATE_TEST) begin
		    if (command[7:1] == {4'b1010, E_id}) begin
			   if (command[0]) begin
				  state <= STATE_READ;
				  ram_read <= 1;
				end else begin
				  state <= STATE_ADDRESS;
				end
				SDA_out <= 0; //Ack
			 end
          command <= 10'd1;
		  end else if (state == STATE_ADDRESS) begin
		    if (NoTestState) begin
		      address <= {1'b0,command[7:1]};
				if (command[0]) begin
				  state <= STATE_READ;
				  ram_read <= 1;
				end else begin
			     state <= STATE_WRITE;
				end
			 end else begin
		      address <= command[7:0];
			   state <= STATE_WRITE;
			 end
		    SDA_out <= 0; //Ack
          command <= 10'd1;
		  end else if (state == STATE_WRITE) begin
		    data <= {command[7:0], 1'b0};
			 if (!WC_n) begin
				ram_write <= 1;
		      SDA_out <= 0; //Ack
			 end
          command <= 10'd1;
		  end else if (state == STATE_READ) begin
		    ram_read <= 1;
			 SDA_out <= 1; //NoAck
          command <= 10'd1;
		  end
		end
	 end
  end

  assign ram_addr = (type_24C01==1) ? {1'b0, address[6:0]} : address;
  assign data_to_ram = data[8:1];

endmodule

