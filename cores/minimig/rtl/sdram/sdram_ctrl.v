//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
//                                                                          --
// Copyright (c) 2009 Tobias Gubener                                        -- 
// Subdesign fAMpIGA by TobiFlex                                            --
//                                                                          --
// This source file is free software: you can redistribute it and/or modify --
// it under the terms of the GNU General Public License as published        --
// by the Free Software Foundation, either version 3 of the License, or     --
// (at your option) any later version.                                      --
//                                                                          --
// This source file is distributed in the hope that it will be useful,      --
// but WITHOUT ANY WARRANTY; without even the implied warranty of           --
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            --
// GNU General Public License for more details.                             --
//                                                                          --
// You should have received a copy of the GNU General Public License        --
// along with this program.  If not, see <http://www.gnu.org/licenses/>.    --
//                                                                          --
//----------------------------------------------------------------------------
//----------------------------------------------------------------------------


module sdram_ctrl (
  inout  wire [ 16-1:0] sdata,
  output reg  [ 12-1:0] sdaddr,
  output reg            sd_we,
  output reg            sd_ras,
  output reg            sd_cas,
  output reg  [  4-1:0] sd_cs,
  output reg  [  2-1:0] dqm,
  output reg  [  2-1:0] ba,

  input  wire           sysclk,
  input  wire           reset,

  input  wire [ 16-1:0] zdatawr,
  input  wire [ 24-1:0] zAddr,
  input  wire [  3-1:0] zstate,
  input  wire [ 16-1:0] datawr,
  input  wire [ 24-1:0] rAddr,
  input  wire           rwr,
  input  wire           dwrL,
  input  wire           dwrU,
  input  wire           ZwrL,
  input  wire           ZwrU,
  input  wire           dma,
  input  wire           cpu_dma,
  input  wire           c_28min,

  output reg  [ 16-1:0] dataout,
  output reg  [ 16-1:0] zdataout,
  output reg            c_14m,
  output wire           zena_o,
  output reg            c_28m,
  output reg            c_7m,
  output wire           reset_out,
  output reg            pulse,
  output reg            enaRDreg,
  output reg            enaWRreg,
  output reg            ena7RDreg,
  output reg            ena7WRreg
);



reg [3:0] initstate;
reg [3:0] cas_sd_cs;
reg cas_sd_ras;
reg cas_sd_cas;
reg cas_sd_we;
reg [1:0] cas_dqm;
reg init_done;
reg [15:0] datain;
reg [23:0] casaddr;
reg sdwrite;
reg [15:0] sdata_reg;
reg Z_cycle;
reg zena;
reg [63:0] zcache;
reg [23:0] zcache_addr;
reg zcache_fill;
reg zcachehit;
reg [3:0] zvalid;
wire zequal;
reg [1:0] zstated;
reg [15:0] zdataoutd;
reg R_cycle;
wire rvalid;
reg [15:0] rdataout;

parameter [3:0]
  ph0 = 0,
  ph1 = 1,
  ph2 = 2,
  ph3 = 3,
  ph4 = 4,
  ph5 = 5,
  ph6 = 6,
  ph7 = 7,
  ph8 = 8,
  ph9 = 9,
  ph10 = 10,
  ph11 = 11,
  ph12 = 12,
  ph13 = 13,
  ph14 = 14,
  ph15 = 15;

reg [3:0] sdram_state;

parameter [1:0]
  nop = 0,
  ras = 1,
  cas = 2;

wire [1:0] pass;



//-----------------------------------------------------------------------
// SPIHOST cache
//-----------------------------------------------------------------------
assign zena_o = ((zena == 1'b1) && (zAddr == casaddr) && (cas_sd_cas == 1'b0)) || (zstate[1:0] == 2'b01) || (zcachehit == 1'b1) ? 1'b1 : 1'b0;

assign zequal = 1'b0;

always @(*) begin
  if(zequal == 1'b1 && zvalid[0] == 1'b1) begin
    case(zAddr[2:1] - zcache_addr[2:1])
      2'b00 : begin
        zcachehit = zvalid[0];
        zdataout  = zcache[63:48];
      end
      2'b01 : begin
        zcachehit = zvalid[1];
        zdataout  = zcache[47:32];
      end
      2'b10 : begin
        zcachehit = zvalid[2];
        zdataout  = zcache[31:16];
      end
      2'b11 : begin
        zcachehit = zvalid[3];
        zdataout  = zcache[15:0];
      end
      default : begin
        zcachehit = 1'b0;
        zdataout  = zdataoutd;
      end
    endcase
  end else begin
    zcachehit = 1'b0;
    zdataout  = zdataoutd;
  end
end


// data transfer //
always @(posedge sysclk or negedge reset) begin
  if(reset == 1'b0) begin
    zcache_fill <= 1'b0;
    zena <= 1'b0;
    zvalid <= 4'b0000;
  end else begin
    if((sdram_state == ph10) && (Z_cycle == 1'b1)) begin
      zdataoutd <= sdata_reg;
    end
    zstated <= zstate[1:0];
    if((zequal == 1'b1) && (zstate == 2'b11)) begin
      zvalid <= 4'b0000;
    end
    case(sdram_state)
      ph7 : begin
        zena <= Z_cycle;
      end
      ph8 : begin
        // only instruction cache
        if((cas_sd_we == 1'b1) && (zstated[1] == 1'b0) && (Z_cycle == 1'b1)) begin
          zcache_addr <= casaddr;
          zcache_fill <= 1'b1;
          zvalid <= 4'b0000;
        end
      end
      ph10 : begin
        if(zcache_fill == 1'b1) begin
          zcache[63:48] <= sdata_reg;
        end
      end
      ph11 : begin
        if(zcache_fill == 1'b1) begin
          zcache[47:32] <= sdata_reg;
        end
      end
      ph12 : begin
        if(zcache_fill == 1'b1) begin
          zcache[31:16] <= sdata_reg;
        end
      end
      ph13 : begin
        if(zcache_fill == 1'b1) begin
          zcache[15:0] <= sdata_reg;
        end
        zcache_fill <= 1'b0;
      end
      ph15 : begin
        zena <= 1'b0;
        zvalid <= 4'b1111;
      end
      default: begin
        if((zequal == 1'b1) && (zstate == 2'b11)) zvalid <= 4'b0000;
      end
    endcase
  end
end



//-----------------------------------------------------------------------
// Main cache
//-----------------------------------------------------------------------
always @(*) begin
  dataout = rdataout;
end

always @(posedge sysclk) begin
  if((sdram_state == ph10) && (R_cycle == 1'b1)) begin
    rdataout <= sdata_reg;
  end
end



//-----------------------------------------------------------------------
// SDRAM Basic
//-----------------------------------------------------------------------
assign reset_out = init_done;

assign sdata = (sdwrite) ? datain : 16'bzzzzzzzzzzzzzzzz;

/*
always @(*) begin
  if(sdwrite == 1'b1)
    sdata <= datain;
  else
    sdata <= 16'bzzzzzzzzzzzzzzzz;
end
*/

always @(posedge sysclk) begin
  // sample SDRAM data
  sdata_reg <= sdata;
end

always @(posedge sysclk or negedge reset) begin
  if(reset == 1'b0) begin
    initstate <= {4{1'b0}};
    init_done <= 1'b0;
    sdram_state <= ph0;
    sdwrite <= 1'b0;
    enaRDreg <= 1'b0;
    enaWRreg <= 1'b0;
    ena7RDreg <= 1'b0;
    ena7WRreg <= 1'b0;
  end else begin
    sdwrite <= 1'b0;
    enaRDreg <= 1'b0;
    enaWRreg <= 1'b0;
    ena7RDreg <= 1'b0;
    ena7WRreg <= 1'b0;
    case(sdram_state)
      // LATENCY=3
      ph0 : begin
        sdram_state <= ph1;
      end
      ph1 : begin
        if(c_28min == 1'b1) begin
          sdram_state <= ph2;
          c_28m <= 1'b0;
          pulse <= 1'b0;
        end
        else begin
          sdram_state <= ph1;
        end
      end
      ph2 : begin
        if(c_28min == 1'b0) begin
          sdram_state <= ph3;
          enaRDreg <= 1'b1;
        end
        else begin
          sdram_state <= ph2;
        end
      end
      ph3 : begin
        sdram_state <= ph4;
        c_14m <= 1'b0;
        c_28m <= 1'b1;
      end
      ph4 : begin
        sdram_state <= ph5;
        sdwrite <= 1'b1;
      end
      ph5 : begin
        sdram_state <= ph6;
        sdwrite <= 1'b1;
        c_28m <= 1'b0;
        pulse <= 1'b1;
      end
      ph6 : begin
        sdram_state <= ph7;
        sdwrite <= 1'b1;
        enaWRreg <= 1'b1;
        ena7RDreg <= 1'b1;
      end
      ph7 : begin
        sdram_state <= ph8;
        c_7m <= 1'b0;
        c_14m <= 1'b1;
        c_28m <= 1'b1;
      end
      ph8 : begin
        sdram_state <= ph9;
      end
      ph9 : begin
        sdram_state <= ph10;
        c_28m <= 1'b0;
        pulse <= 1'b0;
      end
      ph10 : begin
        sdram_state <= ph11;
        enaRDreg <= 1'b1;
      end
      ph11 : begin
        sdram_state <= ph12;
        c_14m <= 1'b0;
        c_28m <= 1'b1;
      end
      ph12 : begin
        sdram_state <= ph13;
      end
      ph13 : begin
        sdram_state <= ph14;
        c_28m <= 1'b0;
        pulse <= 1'b1;
      end
      ph14 : begin
        sdram_state <= ph15;
        enaWRreg <= 1'b1;
        ena7WRreg <= 1'b1;
      end
      ph15 : begin
        sdram_state <= ph0;
        c_7m <= 1'b1;
        c_14m <= 1'b1;
        c_28m <= 1'b1;
        if(initstate != 4'b1111) initstate <= initstate + 4'd1;
        else init_done <= 1'b1;
      end
      default : begin
        sdram_state <= ph0;
        sdwrite <= 1'b0;
        enaRDreg <= 1'b0;
        enaWRreg <= 1'b0;
        ena7RDreg <= 1'b0;
        ena7WRreg <= 1'b0;
      end
    endcase
  end
end


always @(posedge sysclk) begin
  sd_cs <= 4'b1111;
  sd_ras <= 1'b1;
  sd_cas <= 1'b1;
  sd_we <= 1'b1;
  sdaddr <= 12'bxxxxxxxxxxxx;
  ba <= 2'b00;
  dqm <= 2'b00;
  if(init_done == 1'b0) begin
    if(sdram_state == ph2) begin
      case(initstate)
        4'b0010 : begin
          //PRECHARGE
          sdaddr[10] <= 1'b1;
          //all banks
          sd_cs <= 4'b0000;
          sd_ras <= 1'b0;
          sd_cas <= 1'b1;
          sd_we <= 1'b0;
        end
        4'b0011, 4'b0100, 4'b0101, 4'b0110, 4'b0111, 4'b1000, 4'b1001, 4'b1010, 4'b1011, 4'b1100 : begin
          //AUTOREFRESH
          sd_cs <= 4'b0000;
          sd_ras <= 1'b0;
          sd_cas <= 1'b0;
          sd_we <= 1'b1;
        end
        4'b1101 : begin
          //LOAD MODE REGISTER
          sd_cs <= 4'b0000;
          sd_ras <= 1'b0;
          sd_cas <= 1'b0;
          sd_we <= 1'b0;
          //sdaddr <= 12b001000100010; // BURST=4 LATENCY=2
          sdaddr <= 12'b001000110010; // BURST=4 LATENCY=3
          //sdaddr <= 12'b001000110000; // noBURST LATENCY=3
        end
        default : begin
          //NOP
          //sd_cs <= 4'b1111;
          //sd_ras <= 1'b1;
          //sd_cas <= 1'b1;
          //sd_we <= 1'b1;
          //sdaddr <= 12'bxxxxxxxxxxxx;
          //ba <= 2'b00;
          //dqm <= 2'b00;
        end
      endcase
    end
  end else begin
    // time slot control          
    if(sdram_state == ph2) begin
      R_cycle <= 1'b0;
      Z_cycle <= 1'b0;
      cas_sd_cs <= 4'b1110; 
      cas_sd_ras <= 1'b1;
      cas_sd_cas <= 1'b1;
      cas_sd_we <= 1'b1;
      if((dma == 1'b0) || (cpu_dma == 1'b0)) begin
        R_cycle <= 1'b1;
        sdaddr <= rAddr[20:9];
        ba <= rAddr[22:21];
        cas_dqm <= {dwrU,dwrL};
        sd_cs <= 4'b1110; // active
        sd_ras <= 1'b0;
        casaddr <= rAddr;
        datain <= datawr;
        cas_sd_cas <= 1'b0;
        cas_sd_we <= rwr;
      end else if((zstate[2] == 1'b1) || (zena_o == 1'b1)) begin // refresh cycle
        sd_cs <= 4'b0000; // autorefresh
        sd_ras <= 1'b0;
        sd_cas <= 1'b0;
      end else begin
        Z_cycle <= 1'b1;
        sdaddr <= zAddr[20:9];
        ba <= zAddr[22:21];
        cas_dqm <= {ZwrU,ZwrL};
        sd_cs <= 4'b1110; // active
        sd_ras <= 1'b0;
        casaddr <= zAddr;
        datain <= zdatawr;
        cas_sd_cas <= 1'b0;
        if(zstate == 3'b011) cas_sd_we <= 1'b0;
      end
    end 
    if(sdram_state == ph5) begin
      sdaddr <= {1'b0, 1'b1, 1'b0, casaddr[23], casaddr[8:1]}; // auto precharge
      ba <= casaddr[22:21];
      sd_cs <= cas_sd_cs;
      if(!cas_sd_we) dqm <= cas_dqm;
      sd_ras <= cas_sd_ras;
      sd_cas <= cas_sd_cas;
      sd_we <= cas_sd_we;
    end
  end
end



endmodule

