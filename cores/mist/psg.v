module psg (
	// cpu register interface
	input clk,
	input reset,
	input [7:0] din,
	input sel,
	input [7:0] addr,
	input ds,
	input rw,
	output reg [7:0] dout,
	output dtack,	

	output drv_side,
	output [1:0] drv_sel
);

// port a is partly used to select the floppy
assign drv_side = port_a[0];
assign drv_sel = { port_a[2], port_a[1] };

// ------------------ cpu interface --------------------

reg [7:0] port_a;
reg [3:0] reg_sel;

// dtack
assign dtack = sel;

always @(sel, ds, rw, addr) begin
   dout = 8'h00;

	if(sel && ~ds && rw) begin
		// read from selected register
		if(addr == 8'h00 && reg_sel == 4'd14)
			dout = port_a;
   end
end
   
always @(negedge clk) begin
   if(reset) begin
      reg_sel <= 4'd0;
      port_a <= 8'd0;
   end else begin
      // keyboard acia data register writes into buffer 
      if(sel && ~ds && ~rw) begin
			// register select
			if(addr == 8'h00)
				reg_sel <= din[3:0];
				
			// write to selected register
			if(addr == 8'h02 && reg_sel == 4'd14)
				port_a <= din;
      end
   end
end
   
endmodule