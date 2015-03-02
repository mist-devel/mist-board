// dma.v
//
// Atari ST dma engine for the MIST baord
// http://code.google.com/p/mist-board/
//
// This file implements a SPI client which can write data
// into any memory region. This is used to upload rom
// images as well as implementation the DMA functionality
// of the Atari ST DMA controller.
//
// This also implements the video adjustment. This has nothing
// to do with dma and should happen in user_io instead.
// But now it's here and moving it is not worth the effort.
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
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

// TODO:
// - Allow DMA transfers to ROM only for IO controller initiated transfers

// ##############DMA/WD1772 Disk controller                           ###########
// -------+-----+-----------------------------------------------------+----------
// $FF8600|     |Reserved                                             |
// $FF8602|     |Reserved                                             |
// $FF8604|word |FDC access/sector count                              |R/W
// $FF8606|word |DMA mode/status                             BIT 2 1 0|R
//        |     |Condition of FDC DATA REQUEST signal -----------' | ||
//        |     |0 - sector count null,1 - not null ---------------' ||
//        |     |0 - no error, 1 - DMA error ------------------------'|
// $FF8606|word |DMA mode/status                 BIT 8 7 6 . 4 3 2 1 .|W
//        |     |0 - read FDC/HDC,1 - write ---------' | | | | | | |  |
//        |     |0 - HDC access,1 - FDC access --------' | | | | | |  |
//        |     |0 - DMA on,1 - no DMA ------------------' | | | | |  |
//        |     |Reserved ---------------------------------' | | | |  |
//        |     |0 - FDC reg,1 - sector count reg -----------' | | |  |
//        |     |0 - FDC access,1 - HDC access ----------------' | |  |
//        |     |0 - pin A1 low, 1 - pin A1 high ----------------' |  |
//        |     |0 - pin A0 low, 1 - pin A0 high ------------------'  |
// $FF8609|byte |DMA base and counter (High byte)                     |R/W
// $FF860B|byte |DMA base and counter (Mid byte)                      |R/W
// $FF860D|byte |DMA base and counter (Low byte)                      |R/W
//        |     |Note: write address from low toward high byte        |
	 
module dma (
	    // clocks and system interface
	input 		  clk,
	input 		  reset,
	input [1:0] 	  bus_cycle,
	input 		  turbo,
	output 		  irq,
	    
	    // (this really doesn't belong here ...)
	output reg [31:0] ctrl_out,
	    // horizontal and vertical screen adjustments
	output reg [15:0] video_adj,

	    // cpu interface
        input [15:0] 	  cpu_din,
        input 		  cpu_sel,
        input [2:0] 	  cpu_addr,
        input 		  cpu_uds,
        input 		  cpu_lds,
        input 		  cpu_rw,
        output reg [15:0] cpu_dout,

	    // spi interface
	input 		  sdi,
	input 		  sck,
	input 		  ss,
	output 		  sdo,

        // additional fdc control signals provided by PSG and OSD
	input 		  fdc_wr_prot,
	input 		  drv_side,
	input [1:0] 	  drv_sel,
        // additional acsi control signals provided by OSD
	input [7:0]       acsi_enable,
	    
	// ram interface for dma engine
	output 		  ram_br,
	output reg 	  ram_read,
	output reg 	  ram_write,
	output [22:0] 	  ram_addr,
	output [15:0] 	  ram_dout,
	input [15:0] 	  ram_din
);

assign irq = fdc_irq || acsi_irq;

// for debug: count irqs
reg [7:0] fdc_irq_count;
always @(posedge fdc_irq or posedge reset) begin
	if(reset) fdc_irq_count <= 8'd0;
	else      fdc_irq_count <= fdc_irq_count + 8'd1;
end

reg [7:0] acsi_irq_count;
always @(posedge acsi_irq or posedge reset) begin
	if(reset) acsi_irq_count <= 8'd0;
	else      acsi_irq_count <= acsi_irq_count + 8'd1;
end

// filter spi clock. the 8 bit gate delay is ~2.5ns in total
wire [7:0] spi_sck_D = { spi_sck_D[6:0], sck } /* synthesis keep */;
wire spi_sck = (spi_sck && spi_sck_D != 8'h00) || 
     (!spi_sck && spi_sck_D == 8'hff);

reg [5:0]  cnt;   // bit counter (counting spi bits, rolling from 39 to 8)
reg [4:0]  bcnt;  // payload byte counter
reg [30:0] sbuf;  // receive buffer (buffer used to assemble spi bytes/words)
reg [7:0]  cmd;   // command byte (first byte of spi transmission)
   
// word address given bei io controller
reg 	    data_io_addr_strobe;

// dma sector count and mode registers
reg [7:0]  dma_scnt;   
reg [15:0] dma_mode;

// ============= FDC submodule ============   

// select signal for the fdc controller registers   
wire    fdc_reg_sel = cpu_sel && !cpu_lds && (cpu_addr == 3'h2) && (dma_mode[4:3] == 2'b00);
wire    fdc_irq;   
wire [7:0] fdc_status_byte;
wire [7:0] fdc_dout;
   
fdc fdc( .clk         ( clk                   ),  
	 .reset       ( reset                 ),
	 
	 .irq         ( fdc_irq               ),

	 // external floppy control signals
	 .drv_sel     ( drv_sel               ),
	 .drv_side    ( drv_side              ),
	 .wr_prot     ( fdc_wr_prot				),

	 // signals from/to io controller
	 .dma_ack     ( dma_ack               ),
	 .status_sel  ( bcnt-4'd4             ),
	 .status_byte ( fdc_status_byte       ),
	 
	 // cpu interfaces, passed trough dma in st
	 .cpu_sel     ( fdc_reg_sel           ),
	 .cpu_addr    ( dma_mode[2:1]         ),
	 .cpu_rw      ( cpu_rw                ),
	 .cpu_din     ( cpu_din[7:0]          ),
	 .cpu_dout    ( fdc_dout              )
);
   
// ============= ACSI submodule ============   

// select signal for the acsi controller access (write only, status comes from io controller)
wire    acsi_reg_sel = cpu_sel && !cpu_lds && (cpu_addr == 3'h2) && (dma_mode[4:3] == 2'b01);
wire    acsi_irq;   
wire [7:0] acsi_status_byte;
wire [7:0] acsi_dout;
 
acsi acsi(.clk        ( clk                   ),  
	 .reset       ( reset                 ),
	 
	 .irq         ( acsi_irq              ),

	  // acsi target enable
	 .enable      ( acsi_enable           ),

	 // signals from/to io controller
	 .dma_ack     ( dma_ack               ),
  	 .dma_nak     ( dma_nak               ),
	 .dma_status  ( dma_status            ),
	  
	 .status_sel  ( bcnt-4'd9             ),
	 .status_byte ( acsi_status_byte      ),
	 
	 // cpu interface, passed through dma in st
	 .cpu_sel     ( acsi_reg_sel          ),
	 .cpu_addr    ( dma_mode[2:1]         ),
	 .cpu_rw      ( cpu_rw                ),
	 .cpu_din     ( cpu_din[7:0]          ),
	 .cpu_dout    ( acsi_dout             )
);

// ============= CPU read interface ============
always @(cpu_sel, cpu_rw, cpu_addr, dma_mode, dma_addr, dma_scnt) begin
   cpu_dout = 16'h0000;

   if(cpu_sel && cpu_rw) begin
      
      // register $ff8604
      if(cpu_addr == 3'h2) begin
         if(dma_mode[4] == 1'b0) begin
            // controller access register
            if(dma_mode[3] == 1'b0)
					cpu_dout = { 8'h00, fdc_dout };
				else
					cpu_dout = { 8'h00, acsi_dout };
         end else
           cpu_dout = { 8'h00, dma_scnt };  // sector count register
      end
      
      // DMA status register $ff8606
      // bit 0 = 1: DMA_OK, bit 2 = state of FDC DRQ
      if(cpu_addr == 3'h3) cpu_dout = { 14'd0, dma_scnt != 0, 1'b1 };
      
      // dma address read back at $ff8609-$ff860d
      if(cpu_addr == 3'h4) cpu_dout = { 8'h00, dma_addr[22:15]     };
      if(cpu_addr == 3'h5) cpu_dout = { 8'h00, dma_addr[14:7]      };
      if(cpu_addr == 3'h6) cpu_dout = { 8'h00, dma_addr[6:0], 1'b0 };
   end
end

// ============= CPU write interface ============
// flags indicating the cpu is writing something. valid on rising edge
reg cpu_address_write_strobe;  
reg cpu_scnt_write_strobe;  
reg cpu_mode_write_strobe;  
reg cpu_dma_mode_direction_toggle;
   
always @(negedge clk) begin
   if(reset) begin
      cpu_address_write_strobe <= 1'b0;      
      cpu_scnt_write_strobe <= 1'b0;      
      cpu_mode_write_strobe <= 1'b0;
      cpu_dma_mode_direction_toggle <= 1'b0;
   end else begin
      cpu_address_write_strobe <= 1'b0;      
      cpu_scnt_write_strobe <= 1'b0;      
      cpu_mode_write_strobe <= 1'b0;
      cpu_dma_mode_direction_toggle <= 1'b0;

      // cpu writes ...
      if(cpu_sel && !cpu_rw && !cpu_lds) begin

	 // ... sector count register
	 if((cpu_addr == 3'h2) && (dma_mode[4] == 1'b1))
	   cpu_scnt_write_strobe <= 1'b1;
	 
	 // ... dma mode register
	 if(cpu_addr == 3'h3) begin
	   dma_mode <= cpu_din;
	    cpu_mode_write_strobe <= 1'b1;

	   // check if cpu toggles direction bit (bit 8)
	   if(dma_mode[8] != cpu_din[8])
	     cpu_dma_mode_direction_toggle <= 1'b1;
	 end
	 
	 // ... dma address
         if((cpu_addr == 3'h4) || (cpu_addr == 3'h5) || (cpu_addr == 3'h6))
	   // trigger address engine latch
	   cpu_address_write_strobe <= 1'b1;      
      end
   end
end
   
	   
// SPI data io and strobe
// TODO: these don't belong here
reg [15:0] io_data_in;
reg io_data_in_strobe;       // data from IOC ready to be stored in fifo
reg io_data_out_strobe;
reg io_data_out_inc_strobe;

// ======================== BUS cycle handler ===================
   
// specify which bus cycles to use
wire cycle_advance   = (bus_cycle == 2'd0) || (turbo && (bus_cycle == 2'd2));
wire cycle_io        = (bus_cycle == 2'd1) || (turbo && (bus_cycle == 2'd3));

// latch bus cycle information to use at the end of the cycle (posedge clk)
reg cycle_advance_L, cycle_io_L;
always @(negedge clk) begin
	cycle_advance_L <= cycle_advance;
	cycle_io_L <= cycle_io;
end

// =======================================================================
// ============================= DMA FIFO ================================
// =======================================================================

// 32 byte dma fifo (actually a 16 word fifo)
reg [15:0] fifo [15:0];
reg [3:0] fifo_wptr;         // word pointers
reg [3:0] fifo_rptr;
wire [3:0] fifo_ptr_diff = fifo_wptr - fifo_rptr; 
reg [2:0] fifo_read_cnt;     // fifo read transfer word counter
reg [2:0] fifo_write_cnt;    // fifo write transfer word counter
  
// fifo is ready to be re-filled if it is empty
// -> we don't use this as the fifo is not refilled fast enough in non-turbo
wire    fifo_not_full  = fifo_ptr_diff < 4'd7; // (turbo?4'd1:4'd2);
// fifo is considered full if 8 words (16 bytes) are present
wire fifo_full      = (fifo_wptr - fifo_rptr) > 4'd7;

// Reset fifo via the dma mode direction bit toggling or when
// IO controller sets address
wire fifo_reset = cpu_dma_mode_direction_toggle || data_io_addr_strobe;

reg fifo_read_in_progress, fifo_write_in_progress;
assign ram_br = fifo_read_in_progress || fifo_write_in_progress || ioc_br_clk; 

reg ioc_br_clk;
always @(negedge clk)
   if(cycle_advance) 
		ioc_br_clk <= ioc_br;

// ============= FIFO WRITE ENGINE ==================
// rising edge after ram has been read
reg ram_read_done;
always @(posedge clk) ram_read_done <= ram_read;

// state machine for DMA ram read access
// this runs on negative clk to generate a proper bus request
// in the middle of the advance cycle

// start condition for fifo write
wire fifo_write_start = dma_in_progress && dma_direction_out && 
     fifo_write_cnt == 0 && fifo_not_full;

always @(negedge clk or posedge fifo_reset) begin
   if(fifo_reset == 1'b1) begin
      fifo_write_cnt <= 3'd0;
      fifo_write_in_progress <= 1'b0;
   end else begin
      if(cycle_advance) begin      
	 // start dma read engine if 8 more words can be stored
	 if(fifo_write_start) begin
	    fifo_write_cnt <= 3'd7;
	    fifo_write_in_progress <= 1'b1;
	 end else begin
	    if(fifo_write_cnt != 0)
	      fifo_write_cnt <= fifo_write_cnt - 3'd1;
	    else
	      fifo_write_in_progress <= 1'b0;
	 end
      end
   end
end
   
// ram control signals need to be stable over the whole 8 Mhz cycle
always @(posedge clk)
   ram_read <= (cycle_advance_L && fifo_write_in_progress)?1'b1:1'b0;

wire io_data_in_strobe_clk;
spi2clk io_data_in_strobe2clk (
	.clk   ( clk                   ),
	.in    ( io_data_in_strobe     ),
	.out   ( io_data_in_strobe_clk )
);
	   
wire [15:0] fifo_data_in = dma_direction_out?ram_din:io_data_in;
wire fifo_data_in_strobe = dma_direction_out?ram_read_done:io_data_in_strobe_clk;
   
// write to fifo on rising edge of fifo_data_in_strobe
always @(posedge fifo_data_in_strobe or posedge fifo_reset) begin
   if(fifo_reset == 1'b1)
     fifo_wptr <= 4'd0;
   else begin
      fifo[fifo_wptr] <= fifo_data_in;
      fifo_wptr <= fifo_wptr + 4'd1;
   end
end

// ============= FIFO READ ENGINE ==================

// start condition for fifo read
wire fifo_read_start = dma_in_progress && !dma_direction_out && 
     fifo_read_cnt == 0 && fifo_full;
   
// state machine for DMA ram write access
always @(negedge clk or posedge fifo_reset) begin
   if(fifo_reset == 1'b1) begin
      // not reading from fifo, not writing into ram
      fifo_read_cnt <= 3'd0;
      fifo_read_in_progress <= 1'b0;
   end else begin
      if(cycle_advance) begin
	 // start dma read engine if 8 more words can be stored
	 if(fifo_read_start) begin 
	    fifo_read_cnt <= 3'd7;
	    fifo_read_in_progress <= 1'b1;
	 end else begin
	    if(fifo_read_cnt != 0)
	      fifo_read_cnt <= fifo_read_cnt - 3'd1;
	    else
	      fifo_read_in_progress <= 1'b0;
	 end
      end
   end
end

// ram control signals need to be stable over the whole 8 Mhz cycle
always @(posedge clk)
   ram_write <= (cycle_advance_L && fifo_read_in_progress)?1'b1:1'b0;

// a signal half a 8mhz cycle earlier than ram_write to prefetch the data
// from the fifo right before ram write
wire fifo_read_prep = fifo_read_start || (fifo_read_cnt != 0);
   
reg ram_write_prep;
always @(negedge clk)
   ram_write_prep <= (cycle_advance && fifo_read_prep)?1'b1:1'b0;

// Bring data out strobe from SPI clock domain into DMAs local clock
// domain to make sure fifo write and read run on the same clock and
// signals derived from the fifo counters are thus glitch free. This
// delays the generation of the fifos "not full" signal slighlty which
// in turn requires reloading the fifo even if it still contains one
// word in non-turbo (2MHz). Waiting for the fifo to become empty
// would not reload the first word from memory fast enough. In turbo
// (4Mhz) mode this is no problem and the first word from memory
// is being read before it has to be ready for SPI transmission
wire io_data_out_inc_strobe_clk;
spi2clk io_data_out_inc_strobe2clk (
	.clk   ( clk                        ),
	.in    ( io_data_out_inc_strobe     ),
	.out   ( io_data_out_inc_strobe_clk )
);

reg [15:0] fifo_data_out;
wire fifo_data_out_strobe = dma_direction_out?io_data_out_strobe:ram_write_prep;
wire fifo_data_out_strobe_clk = dma_direction_out?io_data_out_inc_strobe_clk:ram_write; 

always @(posedge fifo_data_out_strobe) 
   fifo_data_out <= fifo[fifo_rptr];

always @(posedge fifo_data_out_strobe_clk or posedge fifo_reset) begin
   if(fifo_reset == 1'b1) fifo_rptr <= 4'd0;
   else                   fifo_rptr <= fifo_rptr + 4'd1;
end

// use fifo output directly as ram data
assign ram_dout = fifo_data_out;

// ==========================================================================
// =============================== internal registers =======================
// ==========================================================================
  
// ================================ DMA sector count ========================
// - register is decremented by one after 512 bytes being transferred
// - cpu can write this register directly
// - io controller can write this via the set_address command
   
// CPU write access to even addresses 
wire cpu_write = cpu_sel && !cpu_rw && !cpu_lds;

// Delay the write_strobe a little bit as sector_cnt is included in 
// dma_scnt_write_strobe and in turn resets sector_strobe. As a result
// sector_strobe would be a very short spike only.
wire dma_scnt_write_strobe_clk;
spi2clk dma_scnt_write_strobe2clk (
	.clk   ( !clk                       ),
	.in    ( dma_scnt_write_strobe      ),
	.out   ( dma_scnt_write_strobe_clk  )
);

// keep track of bytes to decrement sector count register
// after 512 bytes (256 words)
reg [7:0] word_cnt;
reg       sector_done;   
reg 	  sector_strobe;
reg 	  sector_strobe_prepare;

always @(negedge clk or posedge dma_scnt_write_strobe_clk) begin
   if(dma_scnt_write_strobe_clk) begin
      word_cnt <= 8'd0;
      sector_strobe_prepare <= 1'b0;
      sector_strobe <= 1'b0;
      sector_done <= 1'b0;
   end else begin
      if(cycle_io) begin
	 sector_strobe_prepare <= 1'b0;
	 sector_strobe <= 1'b0;

	 // wait a little after the last word
	 if(sector_done) begin
	    sector_done <= 1'b0;
	    sector_strobe_prepare <= 1'b1;
	    // trigger scnt decrement
	    sector_strobe <= 1'b1;
	 end
      end

      // and ram read or write increases the word counter by one
      if(ram_write || ram_read) begin
	 word_cnt <= word_cnt + 8'd1;
	 if(word_cnt == 255) begin
	    sector_done <= 1'b1;
	    // give multiplexor some time ahead ...
	    sector_strobe_prepare <= 1'b1;
	 end
      end
   end 
end

// cpu and io controller can write the scnt register and it's decremented 
// after 512 bytes
wire dma_scnt_write_strobe = 
     cpu_scnt_write_strobe || data_io_addr_strobe || sector_strobe;
wire fifo_in_progress = fifo_read_in_progress || fifo_write_in_progress; 
wire cpu_writes_scnt = cpu_write && (cpu_addr == 3'h2) && (dma_mode[4] == 1'b1);
// sector counter doesn't count below 0
wire [7:0] dma_scnt_dec = (dma_scnt != 0)?(dma_scnt-8'd1):8'd0;   
// multiplex new sector count data
wire [7:0] dma_scnt_next = sector_strobe_prepare?dma_scnt_dec:
	   cpu_writes_scnt?cpu_din[7:0]:sbuf[30:23];

// cpu or io controller set the sector count register
always @(posedge dma_scnt_write_strobe)
	dma_scnt <= dma_scnt_next;
   
// DMA in progress flag:
// - cpu writing the sector count register starts the DMA engine if
//   dma enable bit 6 in mode register is clear
// - io controller setting the address starts the dma engine
// - changing sector count to 0 (cpu, io controller or counter) stops DMA
// - cpu writing toggling dma direction stops dma
reg dma_in_progress;
wire dma_stop = cpu_dma_mode_direction_toggle;

// dma can be started if sector is not zero and if dma is enabled
// by a zero in bit 6 of dma mode register
wire cpu_starts_dma = cpu_writes_scnt && (cpu_din[7:0] != 0) && !dma_mode[6];
wire ioc_starts_dma = ioc_writes_addr && (sbuf[30:23] != 0);
   
always @(posedge dma_scnt_write_strobe or posedge dma_stop) begin
   if(dma_stop) dma_in_progress <= 1'b0;
   else         dma_in_progress <= cpu_starts_dma || ioc_starts_dma || (sector_strobe && dma_scnt_next != 0);   
end

// ========================== DMA direction flag ============================
reg dma_direction_out;  // == 1 when transferring from fpga to io controller
wire cpu_writes_mode = cpu_write && (cpu_addr == 3'h3);
wire dma_direction_set = data_io_addr_strobe || cpu_dma_mode_direction_toggle;

// bit 8 == 0 -> dma read -> dma_direction_out, io ctrl address bit 23 = dir
wire dma_direction_out_next = cpu_writes_mode?cpu_din[8]:sbuf[22];
   
// cpu or io controller set the dma direction   
always @(posedge dma_direction_set)
  dma_direction_out <= dma_direction_out_next;
   
// ================================= DMA address ============================
// address can be changed through three events:
// - cpu writes single address bytes into three registers
// - io controller writes address via spi
// - dma engine runs and address is incremented

// dma address is stored in three seperate registers as 
// otherwise verilator complains about signals having multiple driving blocks
reg [7:0] dma_addr_h;
reg [7:0] dma_addr_m;
reg [6:0] dma_addr_l;
wire [22:0] dma_addr = { dma_addr_h, dma_addr_m, dma_addr_l };
   
reg dma_addr_inc;
always @(posedge clk)
   dma_addr_inc <= ram_write || ram_read;

wire cpu_writes_addr = cpu_write && ((cpu_addr == 6) || (cpu_addr == 5) || (cpu_addr == 4));
wire ioc_writes_addr = (ss == 0) && (cmd == MIST_SET_ADDRESS);
wire dma_addr_write_strobe = dma_addr_inc || data_io_addr_strobe;

// address to be set by next write strobe
wire [22:0] dma_addr_next = 
	    cpu_writes_addr?{ cpu_din[7:0], cpu_din[7:0], cpu_din[7:1] }:
	    ioc_writes_addr?{ sbuf[21:0], sdi }:
	    (dma_addr + 23'd1);

// dma address low byte
wire dma_addr_write_strobe_l = dma_addr_write_strobe || (cpu_address_write_strobe && (cpu_addr == 3'h6));
always @(posedge dma_addr_write_strobe_l)
  dma_addr_l <= dma_addr_next[6:0];
   
// dma address mid byte
wire dma_addr_write_strobe_m = dma_addr_write_strobe || (cpu_address_write_strobe && (cpu_addr == 3'h5));
always @(posedge dma_addr_write_strobe_m)
  dma_addr_m <= dma_addr_next[14:7];
   
// dma address hi byte
wire dma_addr_write_strobe_h = dma_addr_write_strobe || (cpu_address_write_strobe && (cpu_addr == 3'h4));
always @(posedge dma_addr_write_strobe_h)
  dma_addr_h <= dma_addr_next[22:15];

// dma address is used directly to address the ram   
assign ram_addr = dma_addr;

// dma status interface
reg [7:0] dma_status;     // sent with ack, only used by acsi
reg io_dma_ack, io_dma_nak;
   
wire dma_ack, dma_nak;
spi2clk dma_ack2clk (
		.clk     ( clk			),
		.in		( io_dma_ack   ),
		.out     ( dma_ack      )
);

spi2clk dma_nak2clk (
		.clk     ( clk			),
		.in		( io_dma_nak   ),
		.out     ( dma_nak      )
);
   
// dma status byte as signalled to the io controller
wire [7:0] dma_io_status =
	   (bcnt == 0)?dma_addr[22:15]:
	   (bcnt == 1)?dma_addr[14:7]:
	   (bcnt == 2)?{ dma_addr[6:0], dma_direction_out }:
	   (bcnt == 3)?dma_scnt:
	   // 5 bytes FDC status
	   ((bcnt >= 4)&&(bcnt <= 8))?fdc_status_byte:
	   // 11 bytes ACSI status
	   ((bcnt >= 9)&&(bcnt <= 19))?acsi_status_byte:
		// DMA debug signals
	   (bcnt == 20)?8'ha5:
	   (bcnt == 21)?{ fifo_rptr, fifo_wptr}:
	   (bcnt == 22)?{ 4'd0, fdc_irq, acsi_irq, ioc_br_clk, dma_in_progress }:
	   (bcnt == 23)?dma_status:
	   (bcnt == 24)?dma_mode[8:1]:
	   (bcnt == 25)?fdc_irq_count:
	   (bcnt == 26)?acsi_irq_count:
	   8'h00;
   
// ====================================================================
// ===================== SPI client to IO controller ==================
// ====================================================================

// the following must match the codes in tos.h
localparam MIST_SET_ADDRESS  = 8'h01;
localparam MIST_WRITE_MEMORY = 8'h02;
localparam MIST_READ_MEMORY  = 8'h03;
localparam MIST_SET_CONTROL  = 8'h04;
localparam MIST_GET_DMASTATE = 8'h05;  // reads state of dma and floppy controller
localparam MIST_ACK_DMA      = 8'h06;  // acknowledge a dma command
localparam MIST_SET_VADJ     = 8'h09;
localparam MIST_NAK_DMA      = 8'h0a;  // reject a dma command

// ===================== SPI transmitter ==================

reg [3:0] sdo_bit;
always @(negedge sck)
  sdo_bit <= 4'd7 - cnt[3:0];
   
wire sdo_fifo = fifo_data_out[sdo_bit];
wire sdo_dmastate = dma_io_status[sdo_bit[2:0]];
 
assign sdo = (cmd==MIST_READ_MEMORY)?sdo_fifo:sdo_dmastate;
   
// ===================== SPI receiver ==================

reg ioc_br = 1'b0;
 
always@(posedge spi_sck, posedge ss) begin
   if(ss == 1'b1) begin
      cmd <= 8'd0;
      cnt <= 6'd0;
      bcnt <= 4'd0;
      io_dma_ack <= 1'b0;
      io_dma_nak <= 1'b0;
      io_data_in_strobe <= 1'b0;
      io_data_out_strobe <= 1'b0;
      io_data_out_inc_strobe <= 1'b0;
      data_io_addr_strobe <= 1'b0;
   end else begin
      io_dma_ack <= 1'b0;
      io_dma_nak <= 1'b0;
      io_data_in_strobe <= 1'b0;
      io_data_out_strobe <= 1'b0;
      io_data_out_inc_strobe <= 1'b0;
      data_io_addr_strobe <= 1'b0;

      // shift bits in. stop shifting after payload 
      if(cmd == MIST_SET_ADDRESS) begin
	 // set address is 8+32 bits
	 if(cnt < 39) 
	   sbuf <= { sbuf[29:0], sdi};   
      end else if(cmd == MIST_WRITE_MEMORY) begin
	 if((cnt != 23) && (cnt != 39)) 
	   sbuf <= { sbuf[29:0], sdi};   
      end else 
	sbuf <= { sbuf[29:0], sdi};
      
      // 0:7 is command, 8:15 and 16:23 is payload bytes
      if(cnt < 39)
	cnt <= cnt + 6'd1;
      else
	cnt <= 6'd8;
      
      // count payload bytes
      if((cnt == 15) || (cnt == 23) || (cnt == 31) || (cnt == 39))
	bcnt <= bcnt + 4'd1;
      
      if(cnt == 5'd7) begin
	 cmd <= {sbuf[6:0], sdi}; 

	 if({sbuf[6:0], sdi } == 8'h07)
		ioc_br <= 1'b1;

	 if({sbuf[6:0], sdi } == 8'h08)
		ioc_br <= 1'b0;

		// send nak
	 if({sbuf[6:0], sdi } == MIST_NAK_DMA)
	   io_dma_nak <= 1'b1;

	 // read first byte from fifo once the read command is recognized
	 if({sbuf[6:0], sdi } == MIST_READ_MEMORY)
	   io_data_out_strobe <= 1'b1;
      end
      
      // handle "payload"
	 
      // set address
      if((cmd == MIST_SET_ADDRESS) && (cnt == 39))
	data_io_addr_strobe <= 1'b1;

      // read ram
      if(cmd == MIST_READ_MEMORY) begin
	 // read word from fifo 
	 if((cnt == 23)||(cnt == 39))
	   io_data_out_strobe <= 1'b1;

	 // increment fifo read pointer
	 if((cnt == 8)||(cnt == 24))
	   io_data_out_inc_strobe <= 1'b1;
      end
      
      // write ram
      if(cmd == MIST_WRITE_MEMORY) begin 	 
	 // received one word, store it in fifo
	 if((cnt == 23)||(cnt == 39)) begin
	    io_data_in <= { sbuf[14:0], sdi };
	    io_data_in_strobe <= 1'b1;
	 end
      end
      
      // dma_ack
      if((cmd == MIST_ACK_DMA) && (cnt == 15)) begin
	 io_dma_ack <= 1'b1;
	 dma_status <= { sbuf[6:0], sdi };
      end

      // set control register
      if((cmd == MIST_SET_CONTROL) && (cnt == 39))
	ctrl_out <= { sbuf, sdi };
      
      // set video offsets
      if((cmd == MIST_SET_VADJ) && (cnt == 5'd23))
	video_adj <= { sbuf[14:0], sdi };
   end
end

endmodule

// ===========================================================
// Module used to bring rising edges into the clk clock domain
// ===========================================================
module spi2clk (
	   input in,
		input clk,
		output reg out
);

// set latch on rising edge of input signal. Clear it on rising edge
// of output signal
reg latch;
always @(posedge in or posedge out) begin
   if(out) latch <= 1'b0;
   else    latch <= 1'b1;
end

// move latched signal to output. This in turn clears the latch,
// so out will be reset in the next clk edge
always @(posedge clk)
  out <= latch;
   
endmodule // masking
