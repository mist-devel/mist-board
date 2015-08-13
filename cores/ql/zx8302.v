//
// zx8302.v
//
// ZX8302 for Sinclair QL for the MiST
// https://github.com/mist-devel
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//

module zx8302 (
		input          clk,       // 21 mhz
      input          reset,
      input          init,
		
		// interrupts
		output [2:0]   ipl,

		// sdram interface for microdrive emulation
		output [24:0]  mdv_addr,
		input [15:0]   mdv_din,
		output         mdv_read,
		input          mdv_men,
		input          video_cycle,

		// interface to watch MDV cartridge upload
		input [24:0]   mdv_dl_addr,
		input          mdv_download,

		output         led,
		
		// vertical synv 
		input          vs,
		
		input          ps2_kbd_clk,
		input          ps2_kbd_data,
		
      // bus interface
		input				clk_bus,
		input				cpu_sel,
		input				cpu_wr,
		input [1:0] 	cpu_addr,      // a[5,1]
		input [1:0] 	cpu_ds,
		input [15:0]   cpu_din,
		output [15:0]  cpu_dout
		
);

// ---------------------------------------------------------------------------------
// ----------------------------- CPU register write --------------------------------
// ---------------------------------------------------------------------------------

reg [7:0] mctrl;
reg ipc_bit_strobe;
wire ipc_reply_bit;

// cpu is writing io registers
always @(negedge clk_bus) begin
	irq_ack <= 5'd0;
	ipc_bit_strobe <= 1'b0;
	
	// cpu writes to 0x18XXX area
	if(cpu_sel && cpu_wr) begin
		// even addresses have lds=0 and use the lower 8 data bus bits
		if(!cpu_ds[1]) begin
			// cpu writes microdrive control register
			if(cpu_addr == 2'b10)
				mctrl <= cpu_din[15:8];
		end

		// odd addresses have lds=0 and use the lower 8 data bus bits
		if(!cpu_ds[0]) begin
			// 18003 - IPCWR
			// (host sends a single bit to ipc)
			if(cpu_addr == 2'b01) begin
				// data is ----XEDS
				// S = start bit (should be 0)
				// D = data bit (0/1)
				// E = stop bit (should be 1)
				// X = extra stopbit (should be 1)
				
				// QL will always write 11D0 here with one exception: At startup it sends
				// one single bit through the start bit by writing 0001. Thus we ignore
				// anything which doesn't match the 11D0 pattern
				if((cpu_din[3:2]== 2'b11)&&(cpu_din[0]==1'b0))
					ipc_bit_strobe <= 1'b1;
			end

			// cpu writes interrupt register
			if(cpu_addr == 2'b10) begin
				irq_mask <= cpu_din[7:5];
				irq_ack <= cpu_din[4:0];
			end
		end
	end
end

// ---------------------------------------------------------------------------------
// ----------------------------- CPU register read ---------------------------------
// ---------------------------------------------------------------------------------

// status register read
// bit 0       Network port
// bit 1       Transmit buffer full
// bit 2       Receive buffer full
// bit 3       Microdrive GAP
// bit 4       SER1 DTR
// bit 5       SER2 CTS
// bit 6       IPC busy
// bit 7       COMDATA

wire [7:0] io_status = { ipc_reply_bit, ipc_busy, 2'b00,
		mdv_gap, mdv_rx_ready, mdv_tx_empty, 1'b0 };

assign cpu_dout =
	// 18000/18001 and 18002/18003
	(cpu_addr == 2'b00)?rtc[46:31]:
	(cpu_addr == 2'b01)?rtc[30:15]:

	// 18020/18021 and 18022/18023
	(cpu_addr == 2'b10)?{io_status, irq_pending}:
	(cpu_addr == 2'b11)?{mdv_byte, mdv_byte}:

	16'h0000;	

// ---------------------------------------------------------------------------------
// -------------------------------------- IPC --------------------------------------
// ---------------------------------------------------------------------------------
	
ipc ipc (	
	.reset    	    ( reset          ),
	.clk_bus        ( clk_bus        ),

	.ipc_bit_strobe ( ipc_bit_strobe ),
	.ipc_bit        ( cpu_din[1]     ),
	.ipc_reply_bit  ( ipc_reply_bit  ),
	.ipc_busy       ( ipc_busy       ),
	
	.ps2_kbd_clk    ( ps2_kbd_clk    ),
	.ps2_kbd_data   ( ps2_kbd_data   )
);
	
// ---------------------------------------------------------------------------------
// -------------------------------------- IRQs -------------------------------------
// ---------------------------------------------------------------------------------

wire [7:0] irq_pending = {1'b0, (mdv_sel == 0), clk64k,
		1'b0, vsync_irq, 1'b0, 1'b0, gap_irq };
reg [2:0] irq_mask;
reg [4:0] irq_ack;


// any pending irq raises ipl to 2
assign ipl = (irq_pending[4:0] == 0)?3'b111:3'b101;

// vsync irq is set whenever vsync rises
reg vsync_irq;
wire vsync_irq_reset = reset || irq_ack[3];
always @(posedge vs or posedge vsync_irq_reset) begin
	if(vsync_irq_reset) 	vsync_irq <= 1'b0;
	else	      	     	vsync_irq <= 1'b1;
end

// toggling the mask will also trigger irqs ...
wire gap_irq_in = mdv_gap && irq_mask[0];
reg gap_irq;
wire gap_irq_reset = reset || irq_ack[0];
always @(posedge gap_irq_in or posedge gap_irq_reset) begin
	if(gap_irq_reset) 	gap_irq <= 1'b0;
	else	      	     	gap_irq <= 1'b1;
end



// ---------------------------------------------------------------------------------
// ----------------------------------- microdrive ----------------------------------
// ---------------------------------------------------------------------------------

wire mdv_gap;
wire mdv_tx_empty;
wire mdv_rx_ready;
wire [7:0] mdv_byte;

assign led = !mdv_sel[0];

mdv mdv (
   .clk      ( clk       ),
	.reset    ( init         ),
	
	.sel      ( mdv_sel[0]   ),

   // control bits	
	.gap      ( mdv_gap      ),
	.tx_empty ( mdv_tx_empty ),
	.rx_ready ( mdv_rx_ready ),
	.dout     ( mdv_byte     ),
	
	.download ( mdv_download ),
	.dl_addr  ( mdv_dl_addr  ),

	// ram interface to read image
   .mem_ena  ( mdv_men      ),
   .mem_cycle( video_cycle  ),
	.mem_clk  ( clk_bus      ),
	.mem_addr ( mdv_addr     ),
	.mem_read ( mdv_read     ),  
	.mem_din  ( mdv_din      )	
);

// the microdrive control register mctrl generates the drive selection
reg [7:0] mdv_sel;

always @(negedge mctrl[1])
	mdv_sel <= { mdv_sel[6:0], mctrl[0] };

// ---------------------------------------------------------------------------------
// -------------------------------------- RTC --------------------------------------
// ---------------------------------------------------------------------------------

// PLL for the real time clock (rtc)
reg [46:0] rtc;
always @(posedge clk64k)
	rtc <= rtc + 47'd1;

wire clk64k;
pll_rtc pll_rtc (
	 .inclk0(clk),
	 .c0(clk64k)           // 65536Hz
);

	
endmodule
