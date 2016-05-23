`timescale 1 ps / 1 ps

module sram_byte_en 
#(
parameter DATA_WIDTH    = 128,
parameter ADDRESS_WIDTH = 7
)
(
input                           i_clk,
input      [DATA_WIDTH-1:0]     i_write_data,
input                           i_write_enable,
input      [ADDRESS_WIDTH-1:0]  i_address,
input      [DATA_WIDTH/8-1:0]   i_byte_enable,
output 	   [DATA_WIDTH-1:0]     o_read_data
);

wire [DATA_WIDTH-1:0] sub_wire0;
assign o_read_data = sub_wire0;

altsyncram	altsyncram_component (
		.address_a (i_address),
		.byteena_a (i_byte_enable),
		.clock0 (i_clk),
		.data_a (i_write_data),
		.wren_a (i_write_enable),
		.q_a (sub_wire0),
		.aclr0 (1'b0),
		.aclr1 (1'b0),
		.address_b (1'b1),
		.addressstall_a (1'b0),
		.addressstall_b (1'b0),
		.byteena_b (1'b1),
		.clock1 (1'b1),
		.clocken0 (1'b1),
		.clocken1 (1'b1),
		.clocken2 (1'b1),
		.clocken3 (1'b1),
		.data_b (1'b1),
		.eccstatus (),
		.q_b (),
		.rden_a (1'b1),
		.rden_b (1'b1),
		.wren_b (1'b0));
		
defparam
altsyncram_component.byte_size = 8,
altsyncram_component.clock_enable_input_a = "BYPASS",
altsyncram_component.clock_enable_output_a = "BYPASS",
altsyncram_component.intended_device_family = "Cyclone III",
altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
altsyncram_component.lpm_type = "altsyncram",
altsyncram_component.numwords_a = 2**ADDRESS_WIDTH,
altsyncram_component.operation_mode = "SINGLE_PORT",
altsyncram_component.outdata_aclr_a = "NONE",
altsyncram_component.outdata_reg_a = "CLOCK0",
altsyncram_component.power_up_uninitialized = "FALSE",
altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
altsyncram_component.widthad_a = ADDRESS_WIDTH,
altsyncram_component.width_a = DATA_WIDTH,
altsyncram_component.width_byteena_a = DATA_WIDTH/8;

endmodule