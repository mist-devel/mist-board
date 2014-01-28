module mfp_timer(
		 input 	      CLK,
		 input 	      RST, 
                 
       input 	     DAT_WE,
       input [7:0]  DAT_I,
       output [7:0] DAT_O,

       input 	     CTRL_WE,                      
       input [4:0]  CTRL_I,
       output [4:0] CTRL_O,

		 inout 	     XCLK_I, 
       input 	     T_I, // ext. trigger in

		 output       PULSE_MODE,  // pulse mode disables input port irq
		 
       output reg   T_O,                          
       output reg   T_O_PULSE
);

reg [7:0] data, down_counter, cur_counter;
reg [3:0] control;
	
assign PULSE_MODE = pulse_mode;

wire[7:0] prescaler;         // prescaler value
reg [7:0] prescaler_counter; // prescaler counter

reg 	     count; 
   
wire      started;
                        
wire      delay_mode;     
wire      event_mode;
wire      pulse_mode;     
   
// trigger edge detect registers
reg trigger_r, trigger_r2;

// async clock edge detect
reg xclk_r, xclk_r2;

// counters work on the negative clock edge. we latch them
// on the positive edge for stable cpu read
always @(posedge CLK)
  cur_counter <= down_counter;

// generate clock from async clock input
always @(posedge XCLK_I) begin
	if(RST === 1'b1) 
      prescaler_counter <= 8'd0;
	else begin
		if(prescaler_counter >= prescaler)
			prescaler_counter <= 8'd0;
		else
			prescaler_counter <= prescaler_counter + 8'd1;
	end
end

// pulse is generate in rising edge and detected in main mfp on falling edge   
always @(posedge CLK) begin
	T_O_PULSE <= 1'b0;
	
	if (!RST && count && (down_counter === 8'd1))
		T_O_PULSE <= 1'b1;
end

always @(negedge CLK) begin
      
	if (RST === 1'b1) begin
//      T_O_PULSE <= 1'b0;
      T_O     <= 1'b0;
      control <= 4'd0;
      data    <= 8'd0;
      down_counter <= 8'd0;
      count <= 1'b0;
   end else begin
	 
      // bring trigger/xclk edges into our clock domain.
      trigger_r <= T_I;
      trigger_r2 <= trigger_r;

		xclk_r <= (prescaler_counter === 8'd0);
		xclk_r2 <= xclk_r;

//      T_O_PULSE <= 1'b0;
	 
      // if a write request comes from the main unit
      // then write the data to the appropriate register.
      if(DAT_WE) begin
         data <= DAT_I;
         down_counter <= DAT_I;
		end

		if(CTRL_WE) begin
         control <= CTRL_I[3:0];
	       
         if (CTRL_I[4] == 1'b1)
            T_O <= 1'b0;
      end 
         
		if (started) begin
			count <= 1'b0;

			// handle event mode
			if (event_mode === 1'b1)
				if ((~trigger_r2 & trigger_r) === 1'b1)
					count <= 1'b1;
	    
			// handle delay mode
			if (delay_mode === 1'b1)
				if ((~xclk_r2 & xclk_r) === 1'b1)
					count <= 1'b1;

			// handle pulse mode
			if (pulse_mode === 1'b1)
				if (((~xclk_r2 & xclk_r) === 1'b1) && T_I)
					count <= 1'b1;
	    
			if (count) begin

				// timeout pulse
				if (down_counter === 8'd1) begin
		  
					// pulse the timer out
					T_O <= ~T_O;
					down_counter <= data;
//					T_O_PULSE <= 1'b1;
		  
				end else begin
		  
					down_counter <= down_counter - 8'd1;		  
				end
         end
      end
   end     
end
   
assign prescaler = control[2:0] === 3'd1 ?  8'd04 :
                   control[2:0] === 3'd2 ?  8'd10 :
                   control[2:0] === 3'd3 ?  8'd16 :
                   control[2:0] === 3'd4 ?  8'd50 :
                   control[2:0] === 3'd5 ?  8'd64 :
                   control[2:0] === 3'd6 ?  8'd100 :
                   control[2:0] === 3'd7 ?  8'd200 : 8'd1;
   
assign delay_mode = control[3] === 1'b0;
assign pulse_mode = control[3] === 1'b1 & !event_mode;   
assign event_mode = control[3:0] === 4'b1000;
   
assign started = control[3:0] != 4'd0;
assign DAT_O = cur_counter;    
assign CTRL_O = {T_O, control};    
   
endmodule // mfp_timer
