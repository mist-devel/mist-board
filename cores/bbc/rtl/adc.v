`timescale 1ns / 1ps

module adc (
           input CLOCK,
           input CLKEN,
           input nRESET,
           input ENABLE,
           input R_nW,
			  input [1:0] A,
           input RS,
           input [7:0] DI,
           output reg [7:0] DO,
			  
			  input [7:0] ch0,
			  input [7:0] ch1,
			  input [7:0] ch2,
			  input [7:0] ch3
);

reg [3:0] status;
wire [1:0] CH = status[1:0];

wire [7:0] cur_val = 8'h7f - 
	((CH == 0)?ch0:
	 (CH == 1)?ch1:
	 (CH == 2)?ch2:
	  ch3);

always @(posedge CLOCK) begin 

    if (nRESET === 1'b 0) begin

        //  Reset registers to defaults
        DO <= 'd0;
		  status <= 4'h0;
    end
    else begin
        if (ENABLE === 1'b 1) begin
            if (R_nW === 1'b 1) begin

                //  Read
                case (A)
						  // status
                    2'b 00: DO <= { 4'h4, status };   // not busy, conversion ended

						  // hi
                    2'b 01: DO <= cur_val;

						  // lo
                    2'b 10: DO <= 8'h00;
                    3'b 11: DO <= 8'h00; 
                endcase
	           end
            else begin
                case (A)
                    2'b 00:
							  status <= DI[3:0];
                endcase
            end
        end
    end
end

endmodule
