// Mappers from Loopy's Power Pak source code
//
//

//Taken from Loopy's Power Pak mapper source map45.v
module FME7_sound(
    input clk,
    input ce,
    input reset,
    input wr,
    input [15:0] ain,
    input [7:0] din,
    output [6:0] out
);
    reg [3:0] regC;
    reg [11:0] freq0,freq1,freq2;
    reg [2:0] en;
    reg [3:0] vol0,vol1,vol2;
    reg [11:0] count0,count1,count2;
    reg [4:0] duty0,duty1,duty2;
    always@(posedge clk, posedge reset) begin
        if(reset) begin
            en<=0;
        end else if (ce) begin
            if(wr) begin
                if(ain[15:13]==3'b110)  //C000
                    regC<=din[3:0];
                if(ain[15:13]==3'b111)  //E000
                case(regC)
                    0:freq0[7:0]<=din;
                    1:freq0[11:8]<=din[3:0];
                    2:freq1[7:0]<=din;
                    3:freq1[11:8]<=din[3:0];
                    4:freq2[7:0]<=din;
                    5:freq2[11:8]<=din[3:0];
                    7:en<=din[2:0];
                    8:vol0<=din[3:0];
                    9:vol1<=din[3:0];
                    10:vol2<=din[3:0];
                endcase
            end
            if(count0==freq0) begin
                count0<=0;
                duty0<=duty0+1'd1;
            end else
                count0<=count0+1'd1;

            if(count1==freq1) begin
                count1<=0;
                duty1<=duty1+1'd1;
            end else
                count1<=count1+1'd1;
            if(count2==freq2) begin
                count2<=0;
                duty2<=duty2+1'd1;
            end else
                count2<=count2+1'd1;
        end
    end
    
    wire [3:0] ch0={4{~en[0] & duty0[4]}} & vol0;
    wire [3:0] ch1={4{~en[1] & duty1[4]}} & vol1;
    wire [3:0] ch2={4{~en[2] & duty2[4]}} & vol2;
    assign out=ch0+ch1+ch2;
    
endmodule

//Taken from Loopy's Power Pak mapper source mapVRC6.v
// change ain below to set VRC6 variant
module MAPVRC6(     //signal descriptions in powerpak.v
    input m2,
    input m2_n,
    input clk20,

    input reset,
    input nesprg_we,
    output nesprg_oe,
    input neschr_rd,
    input neschr_wr,
    input [15:0] prgain,
    input [13:0] chrain,
    input [7:0] nesprgdin,
    input [7:0] ramprgdin,
    output [7:0] nesprgdout,

    output [7:0] neschrdout,
    output neschr_oe,

    output chrram_we,
    output chrram_oe,
    output wram_oe,
    output wram_we,
    output prgram_we,
    output prgram_oe,
    output [18:10] ramchraout,
    output [18:13] ramprgaout,
    output irq,
    output ciram_ce,

    output exp6,
    
    input cfg_boot,
    input [18:12] cfg_chrmask,
    input [18:13] cfg_prgmask,
    input cfg_vertical,
    input cfg_fourscreen,
    input cfg_chrram,
	 
	 input ce,// add
	 output [15:0] snd_level,
	 input mapper26

);
    //wire [15:0] ain=prgain;                             //MAP18
    //wire [15:0] ain={prgain[15:2],prgain[0],prgain[1]}; //MAP1A
    wire [15:0] ain=mapper26 ? {prgain[15:2],prgain[0],prgain[1]} :  prgain; //MAP1A : MAP18

    reg [4:0] prgbank8;
    reg [5:0] prgbankC;
    reg [7:0] chrbank0, chrbank1, chrbank2, chrbank3, chrbank4, chrbank5, chrbank6, chrbank7;
    reg [1:0] mirror;
    //reg [7:0] irqlatch;
    //reg irqM,irqE,irqA;
	 wire irql = {ain[15:12],ain[1:0]}==6'b111100;
	 wire irqc = {ain[15:12],ain[1:0]}==6'b111101;
	 wire irqa = {ain[15:12],ain[1:0]}==6'b111110;
    always@(posedge clk20) begin
        if(ce && nesprg_we) begin
            casex({ain[15:12],ain[1:0]})
                6'b1000xx:prgbank8<=nesprgdin[4:0]; //800x
                6'b1100xx:prgbankC<=nesprgdin[5:0]; //C00x
                6'b101111:mirror<=nesprgdin[3:2];   //B003
                6'b110100:chrbank0<=nesprgdin;      //D000
                6'b110101:chrbank1<=nesprgdin;      //D001
                6'b110110:chrbank2<=nesprgdin;      //D002
                6'b110111:chrbank3<=nesprgdin;      //D003
                6'b111000:chrbank4<=nesprgdin;      //E000
                6'b111001:chrbank5<=nesprgdin;      //E001
                6'b111010:chrbank6<=nesprgdin;      //E002
                6'b111011:chrbank7<=nesprgdin;      //E003
                //6'b111100:irqlatch<=nesprgdin;      //F000
                //6'b111101:{irqM,irqA}<={nesprgdin[2],nesprgdin[0]}; //F001
            endcase
        end
    end

    //bankswitch
    reg [18:13] prgbankin;
    reg [17:10] chrbank;
    always@* begin
        casex(prgain[15:13])
            3'b0xx:prgbankin=0;                         //sram
            3'b10x:prgbankin={prgbank8,prgain[13]};     //89AB
            3'b110:prgbankin=prgbankC;                  //CD
            default:prgbankin=6'b111111;                //EF
        endcase
        case(chrain[12:10])
            0:chrbank=chrbank0;
            1:chrbank=chrbank1;
            2:chrbank=chrbank2;
            3:chrbank=chrbank3;
            4:chrbank=chrbank4;
            5:chrbank=chrbank5;
            6:chrbank=chrbank6;
            7:chrbank=chrbank7;
        endcase
    end

	 vrcIRQ vrc6irq(clk20,reset,nesprg_we,irql,irqc,irqa,nesprgdin,irq,ce);
	 
//mirroring
    assign ramchraout[10]=!chrain[13] ? chrbank[10] : ((mirror==0 & chrain[10]) | (mirror==1 & chrain[11]) | (mirror==3));
    assign ramchraout[11]=chrbank[11];
    assign ciram_ce=chrain[13];

//rom size mask
    assign ramprgaout[18:13]=prgbankin[18:13] & cfg_prgmask;
    assign ramchraout[18:12]={1'b0,chrbank[17:12]} & cfg_chrmask;

//ram control
    assign chrram_we=neschr_wr & !chrain[13] & cfg_chrram;
    assign chrram_oe=neschr_rd & !chrain[13];

    assign neschr_oe=0;
    assign neschrdout=0;

    assign wram_oe=m2_n & ~nesprg_we & prgain[15:13]=='b011;
    assign wram_we=m2_n &  nesprg_we & prgain[15:13]=='b011;
    
    assign prgram_we=0;
    assign prgram_oe=~cfg_boot & m2_n & ~nesprg_we & prgain[15];

    wire config_rd = 0;
    //gamegenie gg(m2, reset, nesprg_we, prgain, nesprgdin, ramprgdin, nesprgdout, config_rd);
	 assign nesprgdout=8'b0;
    assign nesprg_oe=wram_oe | prgram_oe | config_rd;

//sound
//    wire [5:0] vrc6_out;
    assign exp6 = 0;
    wire [3:0] vrc6sq1_out;
    wire [3:0] vrc6sq2_out;
    wire [4:0] vrc6saw_out;
    vrc6sound snd(clk20, ce, reset, nesprg_we, ain, nesprgdin, vrc6sq1_out, vrc6sq2_out, vrc6saw_out);
//    vrc6sound snd(m2, reset, nesprg_we, ain, nesprgdin, vrc6_out);
//    pdm #(6) pdm_mod(clk20, vrc6_out, exp6);

ApuLookupTable lookup(clk20, 
                      {4'b0, vrc6sq1_out}+
							 {4'b0, vrc6sq2_out},
							 {3'b0, vrc6saw_out},
                      snd_level);

endmodule

module vrcIRQ(
    input clk20,
    input reset,
    input nesprg_we,
	 input irql,
	 input irqc,
	 input irqa,
    input [7:0] nesprgdin,
    output irq,
	 input ce
);
    reg [7:0] irqlatch;
    reg irqM,irqE,irqA;
    always@(posedge clk20) begin
        if(ce && nesprg_we) begin
            if (irql)
				    irqlatch<=nesprgdin;      //F000
				else if (irqc)
                {irqM,irqA}<={nesprgdin[2],nesprgdin[0]}; //F001
        end
    end

    //IRQ
    reg [7:0] irqcnt;
    reg timeout;
    reg [6:0] scalar;
    reg [1:0] line;
    wire irqclk=irqM|(scalar==0);
    wire setE=nesprg_we & irqc & nesprgdin[1];
    always@(posedge clk20) begin
        if(setE) begin
            scalar<=113;
            line<=0;
            irqcnt<=irqlatch;
        end else if(ce && irqE) begin
            if(scalar!=0)
                scalar<=scalar-1'd1;
            else begin
                scalar<=(~line[1])?7'd113:7'd112;
                line<=line[1]?2'd0:line+1'd1;
            end
            if(irqclk) begin
                if(irqcnt==255)     irqcnt<=irqlatch;
                else            irqcnt<=irqcnt+1'd1;
            end
        end
    end
    always@(posedge clk20) begin
        if(reset) begin
            irqE<=0;
            timeout<=0;
        end else if (ce) begin
            if(nesprg_we & (irqc | irqa)) //write Fxx1 or Fxx2
                timeout<=0;
            else if(irqclk & irqcnt==255)
                timeout<=1;

            if(nesprg_we & irqc) //write Fxx1
                irqE<=nesprgdin[1];
            else if(nesprg_we & irqa) //write Fxx2
                irqE<=irqA;
        end
    end

    assign irq=timeout & irqE;
endmodule


module vrc6sound(
//    input m2,
    input clk,
    input ce,
    input reset,
    input wr,
    input [15:0] ain,
    input [7:0] din,
//    output [5:0] out        //range=0..0x3D
    output [3:0] outSq1,       //range=0..0x0F
    output [3:0] outSq2,       //range=0..0x0F
    output [4:0] outSaw        //range=0..0x1F
);
    reg mode0, mode1;
    reg [3:0] vol0, vol1;
    reg [5:0] vol2;
    reg [2:0] duty0, duty1;
    reg [11:0] freq0, freq1, freq2;
    reg [11:0] div0, div1;
    reg [12:0] div2;
    reg en0, en1, en2;

    reg [3:0] duty0cnt, duty1cnt;
    reg [2:0] duty2cnt;
    reg [7:0] acc;

    always@(posedge clk, posedge reset) begin
        if(reset) begin
            en0<=0;
            en1<=0;
            en2<=0;
        end else if(ce) begin
            if(wr) begin
                case(ain)
                    16'h9000: {mode0, duty0, vol0}<=din;
                    16'h9001: freq0[7:0]<=din;
                    16'h9002: {en0, freq0[11:8]} <= {din[7],din[3:0]};

                    16'hA000: {mode1, duty1, vol1}<=din;
                    16'hA001: freq1[7:0]<=din;
                    16'hA002: {en1, freq1[11:8]} <= {din[7],din[3:0]};

                    16'hB000: vol2<=din[5:0];
                    16'hB001: freq2[7:0]<=din;
                    16'hB002: {en2, freq2[11:8]}<={din[7],din[3:0]};
                endcase
            end
            if(en0) begin
                if(div0!=0)
                    div0<=div0-1'd1;
                else begin
                    div0<=freq0;
                    duty0cnt<=duty0cnt+1'd1;
                end
            end
            if(en1) begin
                if(div1!=0)
                    div1<=div1-1'd1;
                else begin
                    div1<=freq1;
                    duty1cnt<=duty1cnt+1'd1;
                end
            end
            if(en2) begin
                if(div2!=0)
                    div2<=div2-1'd1;
                else begin
                    div2<={freq2,1'b1};
                    if(duty2cnt==6) begin
                        duty2cnt<=0;
                        acc<=0;
                    end else begin
                        duty2cnt<=duty2cnt+1'd1;
                        acc<=acc+vol2;
                    end
                end
            end
        end
    end

    wire [4:0] duty0pos=duty0cnt+{1'b1,~duty0};
    wire [4:0] duty1pos=duty1cnt+{1'b1,~duty1};
    wire [3:0] ch0=((~duty0pos[4]|mode0)&en0)?vol0:4'd0;
    wire [3:0] ch1=((~duty1pos[4]|mode1)&en1)?vol1:4'd0;
    wire [4:0] ch2=en2?acc[7:3]:5'd0;
//    assign out=ch0+ch1+ch2;
    assign outSq1=ch0;
    assign outSq2=ch1;
    assign outSaw=ch2;

endmodule

//Taken from Loopy's Power Pak mapper source mapN106.v
//fixme- sound ram is supposed to be readable (does this affect any games?)
module MAPN106(     //signal descriptions in powerpak.v
    input m2,
    input m2_n,
    input clk20,

    input reset,
    input nesprg_we,
    output nesprg_oe,
    input neschr_rd,
    input neschr_wr,
    input [15:0] prgain,
    input [13:0] chrain,
    input [7:0] nesprgdin,
    input [7:0] ramprgdin,
    output reg [7:0] nesprgdout,

    output [7:0] neschrdout,
    output neschr_oe,

    output reg chrram_we,
    output reg chrram_oe,
    output wram_oe,
    output wram_we,
    output prgram_we,
    output prgram_oe,
    output reg [18:10] ramchraout,
    output [18:13] ramprgaout,
    output irq,
    output reg ciram_ce,
    output exp6,
    
    input cfg_boot,
    input [18:12] cfg_chrmask,
    input [18:13] cfg_prgmask,
    input cfg_vertical,
    input cfg_fourscreen,
    input cfg_chrram,
	 
	 input ce,// add
	 output [15:0] snd_level
);

	assign exp6 = 0;

    reg [1:0] chr_en;
    reg [5:0] prg89,prgAB,prgCD;
    reg [7:0] chr0,chr1,chr2,chr3,chr4,chr5,chr6,chr7,chr10,chr11,chr12,chr13;
    reg mirror;
    always@(posedge clk20) begin
        if(ce && nesprg_we)
        case(prgain[15:11])
            5'b10000: chr0<=nesprgdin;              //8000
            5'b10001: chr1<=nesprgdin;
            5'b10010: chr2<=nesprgdin;              //9000
            5'b10011: chr3<=nesprgdin;
            5'b10100: chr4<=nesprgdin;              //A000
            5'b10101: chr5<=nesprgdin;
            5'b10110: chr6<=nesprgdin;              //B000
            5'b10111: chr7<=nesprgdin;
            5'b11000: chr10<=nesprgdin;             //C000
            5'b11001: chr11<=nesprgdin; 
            5'b11010: chr12<=nesprgdin;             //D000
            5'b11011: chr13<=nesprgdin;
            5'b11100: {mirror,prg89}<=nesprgdin[6:0];//E000
            5'b11101: {chr_en,prgAB}<=nesprgdin;    //E800
            5'b11110: prgCD<=nesprgdin[5:0];        //F000
            //5'b11111:                             //F800 (sound)
        endcase
    end

    //IRQ
    reg [15:0] count;
    wire [15:0] count_next=count+1'd1;
    wire countup=count[15] & ~&count[14:0];
    reg timeout;
    assign irq=timeout;
    always@(posedge clk20) begin
	   if (ce) begin
        if(prgain[15:12]==4'b0101)              timeout<=0;
        else if(count==16'hFFFF)                timeout<=1;
        if(nesprg_we & prgain[15:11]==5'b01010) count[7:0]<=nesprgdin;
        else if(countup)                        count[7:0]<=count_next[7:0];
        if(nesprg_we & prgain[15:11]==5'b01011) count[15:8]<=nesprgdin;
        else if(countup)                        count[15:8]<=count_next[15:8];          
		end
    end

    //PRG bank
    reg [18:13] prgbankin;
    always@* begin
        case(prgain[14:13])
            0:prgbankin=prg89;
            1:prgbankin=prgAB;
            2:prgbankin=prgCD;
            3:prgbankin=6'b111111;
        endcase
    end
    assign ramprgaout[18:13]=prgbankin[18:13] & cfg_prgmask & {4'b1111,{2{prgain[15]}}};

    //CHR control
    reg chrram;
    reg [17:10] chrbank;
    always@* begin
        case(chrain[13:10])
            0:chrbank=chr0;
            1:chrbank=chr1;
            2:chrbank=chr2;
            3:chrbank=chr3;
            4:chrbank=chr4;
            5:chrbank=chr5;
            6:chrbank=chr6;
            7:chrbank=chr7;
            8,12:chrbank=chr10;
            9,13:chrbank=chr11;
            10,14:chrbank=chr12;
            11,15:chrbank=chr13;
        endcase
        chrram=(~(chrain[12]?chr_en[1]:chr_en[0]))&(&chrbank[17:15]);   //ram/rom select
        if(!chrain[13]) begin
            ciram_ce=0;
            chrram_oe=neschr_rd;
            chrram_we=neschr_wr & chrram;
            ramchraout[10]=chrbank[10];
        end else begin
            ciram_ce=&chrbank[17:15] | mirror;
            chrram_oe=~ciram_ce & neschr_rd;
            chrram_we=~ciram_ce & neschr_wr & chrram;
            ramchraout[10]=mirror?chrain[10]:chrbank[10];
        end
        ramchraout[11]=chrbank[11];
        ramchraout[17:12]=chrbank[17:12] & cfg_chrmask[17:12];
        ramchraout[18]=chrram;
    end

    assign wram_oe=m2_n & ~nesprg_we & prgain[15:13]==3'b011;
    assign wram_we=m2_n &  nesprg_we & prgain[15:13]==3'b011;

    assign prgram_we=0;
    assign prgram_oe= ~cfg_boot & m2_n & ~nesprg_we & prgain[15];

    wire config_rd = 0;
    //wire [7:0] gg_out;
    //gamegenie gg(m2, reset, nesprg_we, prgain, nesprgdin, ramprgdin, gg_out, config_rd);

    //PRG data out
    wire counter_oe = m2_n & ~nesprg_we & prgain[15:12]=='b0101;
    always@* case(prgain[15:11])
        5'b01010: nesprgdout=count[7:0];
        5'b01011: nesprgdout=count[15:8];
        default: nesprgdout=nesprgdin;
    endcase

    assign nesprg_oe=wram_oe | prgram_oe | counter_oe | config_rd;

    assign neschr_oe=0;
    assign neschrdout=0;

    //sound
    wire [10:0] n106_out;
    wire [9:0] saturated=n106_out[9:0] | {10{n106_out[10]}};    //this is still too quiet for the suggested 47k resistor, but more clipping will make some games sound bad
    namco106_sound n106(ce, clk20, reset, nesprg_we, prgain, nesprgdin, n106_out);
    //pdm #(10) pdm_mod(clk20, saturated, exp6);
	 assign snd_level = {6'b0, saturated};

endmodule

module namco106_sound(
    input m2,
    input clk20,
    input reset,
    input wr,
    input [15:0] ain,
    input [7:0] din,
    output reg [10:0] out       //range is 0..0x708
);
    reg carry;
    reg autoinc;
    reg [6:0] ram_ain;
    reg [6:0] ram_aout;
    wire [7:0] ram_dout;
    reg [2:0] ch;
    reg [7:0] cnt_L[7:0];
    reg [7:0] cnt_M[7:0];
    reg [1:0] cnt_H[7:0];
    wire [2:0] sum_H=cnt_H[ch]+ram_dout[1:0]+carry;
    reg [4:0] sample_pos[7:0];
    reg [2:0] cycle;
    reg [3:0] sample;
    wire [7:0] chan_out=sample*ram_dout[3:0];   //sample*vol
    reg [10:0] out_acc;
    wire [10:0] sum=out_acc+chan_out;
    reg addr_lsb;
    wire [7:0] sample_addr=ram_dout+sample_pos[ch];

    //ram in
    always@(posedge clk20) begin
	   if (m2) begin
        if(wr & ain[15:11]==5'b11111)           //F800..FFFF
            {autoinc,ram_ain}<=din;
        else if(ain[15:11]==5'b01001 & autoinc) //4800..4FFF
            ram_ain<=ram_ain+1'd1;     
		end
    end

    //mixer FSM
    always@* case(cycle)
        0: ram_aout={1'b1,ch,3'd0};     //freq[7:0]
        1: ram_aout={1'b1,ch,3'd2};     //freq[15:8]
        2: ram_aout={1'b1,ch,3'd4};     //length, freq[17:16]
        3: ram_aout={1'b1,ch,3'd6};     //address
        4: ram_aout=sample_addr[7:1];   //sample address
        5: ram_aout={1'b1,ch,3'd7};     //volume
        default: ram_aout=7'bXXXXXXX;
    endcase
    reg [3:0] count45,cnt45;
    always@(posedge clk20)
		if (m2) begin
        count45<=(count45==14)?4'd0:count45+1'd1;
		end
    always@(posedge clk20) begin
        cnt45<=count45;
        if(cnt45[1:0]==0) cycle<=0;             // this gives 45 21.4M clocks per channel
        else if(cycle!=7) cycle<=cycle+1'd1;
        case(cycle)
            1: {carry, cnt_L[ch]}<=cnt_L[ch][7:0]+ram_dout;
            2: {carry, cnt_M[ch]}<=cnt_M[ch][7:0]+ram_dout+carry;
            3: begin
                cnt_H[ch]<=sum_H[1:0];
                if(sum_H[2])
                    sample_pos[ch]<=(sample_pos[ch]=={ram_dout[4:2]^3'b111,2'b11})?5'd0:(sample_pos[ch]+1'd1);
            end
            4: addr_lsb<=sample_addr[0];
            5: sample<=addr_lsb?ram_dout[7:4]:ram_dout[3:0];
            6: begin
                if(ch==7) begin
                    ch<=~ram_dout[6:4];
                    out_acc<=0;
                    out<=sum;
                end else begin
                    ch<=ch+1'd1;
                    out_acc<=sum;
                end
            end
        endcase
    end

  dpram #(.widthad_a(7)) modtable
    (
      .clock_a   (clk20),
      .address_a (ram_ain),
      .wren_a    (wr & ain[15:11]==5'b01001),
		.byteena_a (1),
      .data_a    (din),
      //.q_a     (),

      .clock_b   (clk20),
      .address_b (ram_aout),
      .wren_b    (0),
		.byteena_b (1),
      .data_b    (0),
      .q_b       (ram_dout)
    );
//    RAMB4_S8_S8 n106_ram(
//        .WEA(wr & ain[15:11]==5'b01001),   //cpu write 4800-4FFF
//        .ENA(1'b1),
//        .RSTA(1'b0),
//        .CLKA(m2),
//        .ADDRA({2'd0,ram_ain}),
//        .DIA(din),
//        .DOA(),
//
//        .WEB(1'b0),
//        .ENB(1'b1),
//        .RSTB(1'b0),
//        .CLKB(clk20),
//        .ADDRB({2'd0,ram_aout}),
//        .DIB(),
//        .DOB(ram_dout)
//    );

endmodule


// Loopy's FDS mapper for the Power Pak mapFDS.v
//PRG 00000-01FFF = bios
//PRG 08000-0FFFF = wram
//PRG 40000-7FFFF = disk image
module MAPFDS(              //signal descriptions in powerpak.v
    input m2,
    input m2_n,
    input clk20,

    input reset,
    input nesprg_we,
    output nesprg_oe,
    input neschr_rd,
    input neschr_wr,
    input [15:0] prgain,
    input [13:0] chrain,
    input [7:0] nesprgdin,
    input [7:0] ramprgdin,
    output reg [7:0] nesprgdout,

    output [7:0] neschrdout,
    output neschr_oe,

    output chrram_we,
    output chrram_oe,
    output wram_oe,
    output wram_we,
    output prgram_we,
    output prgram_oe,
    output [18:10] ramchraout,
    output [18:0] ramprgaout,
    output irq,
    output ciram_ce,
    output exp6,
    
    input cfg_boot,
    input [18:12] cfg_chrmask,
    input [18:13] cfg_prgmask,
    input cfg_vertical,
    input cfg_fourscreen,
    input cfg_chrram,
	 
	 input ce,// add
	 input fds_swap,
	 output prg_allow,
	 output [11:0] snd_level
);
    localparam WRITE_LO=16'hF4CD, WRITE_HI=16'hF4CE, READ_LO=16'hF4D0, READ_HI=16'hF4D1;

	 assign neschrdout = 0;
	 assign neschr_oe = 0;
	 assign exp6 = 0;

    wire disk_eject;
    reg timer_irq;
    reg [1:0] Wstate;
    reg [1:0] Rstate;
    wire [7:0] audio_dout;

    assign chrram_we=!chrain[13] & neschr_wr;
    assign chrram_oe=!chrain[13] & neschr_rd;

    assign wram_we=0; //use main ram for everything
    assign wram_oe=0;

    assign prgram_we=~cfg_boot & m2_n &  nesprg_we & (Wstate==2 | (prgain[15]^(&prgain[14:13])));       //6000-DFFF or disk write
    assign prgram_oe=~cfg_boot & m2_n & ~nesprg_we & (prgain[15] | prgain[15:13]==3);                   //6000-FFFF
    wire   fds_oe=               m2_n & ~nesprg_we & (prgain[15:12]==4) & (|prgain[7:5] | prgain[9]);   //$4xxx (except 00-1F) or 42xx

    assign nesprg_oe=prgram_oe | fds_oe;

    reg saved=0;
    reg [15:0] diskpos;
    reg [17:0] sideoffset;
    wire [17:0] romoffset;
    reg [1:0] diskside;
    wire diskend=(diskpos==65499);
    always@* case(diskside) //16+65500*diskside
        0:sideoffset=18'h00010;
        1:sideoffset=18'h0ffec;
        2:sideoffset=18'h1ffc8;
        3:sideoffset=18'h2ffa4;
    endcase
    assign romoffset=diskpos + sideoffset;

    //NES data out
    wire match0=prgain==16'h4030;       //IRQ status
    wire match1=prgain==16'h4032;       //drive status
    wire match2=prgain==16'h4033;       //power / exp
    wire match3=((prgain==READ_LO)|(prgain==WRITE_LO))&!(Wstate==2 | Rstate==2);
    wire match4=((prgain==READ_HI)|(prgain==WRITE_HI))&!(Wstate==2 | Rstate==2);
    wire match5=prgain==16'h4208;       //powerpak save flag
    wire match6=prgain[15:8]==8'h40 && |prgain[7:6];    //4040..40FF
    always@*
        case(1)
            match0: nesprgdout={7'd0, timer_irq};
            match1: nesprgdout={5'd0, disk_eject, diskend, disk_eject};
            match2: nesprgdout=8'b10000000;
            match3: nesprgdout=romoffset[7:0];
            match4: nesprgdout={3'b111,romoffset[12:8]};
            match5: nesprgdout={7'd0,saved};
            match6: nesprgdout=audio_dout;
            default: nesprgdout=ramprgdin;
        endcase
    assign prg_allow = (nesprg_we & (Wstate==2 | (prgain[15]^(&prgain[14:13]))))
                     | (~nesprg_we & ((prgain[15] & !match3 & !match4) | prgain[15:13]==3));

    reg write_en;
    reg vertical;
    reg timer_irq_en;
    reg timer_irq_repeat;
    reg diskreset;
    reg [15:0] timerlatch;
    always@(posedge clk20) begin
        if(ce & nesprg_we)
        case(prgain)
            16'h4020:
                timerlatch[7:0]<=nesprgdin;
            16'h4021:
                timerlatch[15:8]<=nesprgdin;
            16'h4022:
                begin
                    timer_irq_repeat<=nesprgdin[0];
                    timer_irq_en<=nesprgdin[1];
                end
            //16'h4024: //disk data write
            16'h4025:   //disk control
                begin
                    diskreset<=nesprgdin[1];
                    write_en<=!nesprgdin[2];
                    vertical<=!nesprgdin[3];
                    //disk_irq_en<=nesprgdin[7];
                end
            16'h4027:   //powerpak extra: disk side
                    diskside<=nesprgdin[1:0];
        endcase
    end

    //watch for disk read/write
    always@(posedge clk20) begin
		if (m2) begin
        if(write_en & ~nesprg_we & (prgain==WRITE_LO))          Wstate<=1;
        else if(~nesprg_we & (prgain==WRITE_HI) & Wstate==1)    Wstate<=2;
        else                                                    Wstate<=0;

        if(~nesprg_we & (prgain==READ_LO))                      Rstate<=1;
        else if(~nesprg_we & (prgain==READ_HI) & Rstate==1)     Rstate<=2;
        else                                                    Rstate<=0;

        if(Wstate==2) saved<=1;
		 end
    end

    //timer irq
    reg [15:0] timer;
    wire timer_irq_trip=timer_irq_en & timer==1;
    always@(posedge clk20) begin
		if (ce) begin
        if((nesprg_we & prgain==16'h4022) | (timer_irq_trip & timer_irq_repeat))
            timer<=timerlatch;
        else if(timer_irq_en & timer!=0)
            timer<=timer-1'd1;
		end

		if (m2) begin
        if(~nesprg_we & prgain==16'h4030)
            timer_irq<=0;
        else if(timer_irq_trip)
            timer_irq<=1;
		end
    end

    //disk pointer
    always@(posedge clk20) begin
		if (m2) begin
        if(diskreset)                   diskpos<=0;
        else if(Rstate==2 & !diskend)   diskpos<=diskpos+1'd1;
		 end
    end

    assign irq=timer_irq; // | disk_irq

    //disk eject:   toggle flag continuously except when select button is held
    reg [2:0] control_cnt;
    reg [21:0] clkcount;
    //reg button;
    assign disk_eject=clkcount[21] | fds_swap;
//    assign disk_eject=clkcount[21] | button;
    always@(posedge clk20) begin
		if (ce) begin
        clkcount<=clkcount+1'd1;
        if(prgain==16'h4016) begin
            if(nesprg_we)                           control_cnt<=0;
            else if(~nesprg_we & control_cnt!=7)    control_cnt<=control_cnt+1'd1;
            //if(~nesprg_we & control_cnt==2)          button<=|nesprgdin[1:0];
        end
		end
    end

    //bankswitch control: 6000-DFFF = sram, E000-FFFF = bios or disk
    reg [18:13] prgbank;
    wire [18:13] diskbank={1'b1,romoffset[17:13]};
    always@* begin
        if(prgain[15:13]==7)
            prgbank=diskbank & {6{Rstate==2|Wstate==2}};
        else
            prgbank={4'b0001,prgain[14:13]};
    end
    assign ramprgaout={prgbank,prgain[12:0]};

    //mirroring
    assign ramchraout[18:11]={6'd0,chrain[12:11]};
    assign ramchraout[10]=!chrain[13]? chrain[10]: ((vertical & chrain[10]) | (!vertical & chrain[11]));
    assign ciram_ce=chrain[13];

    //expansion audio
    //wire [11:0] snd_level;
    fds_sound sound(ce, reset, nesprg_we, prgain, nesprgdin, audio_dout, snd_level, clk20);
    //pdm #(12) pdm_mod(clk20, snd_level, exp6);
  
endmodule

//mod table supposed to be a fifo?
//sweep clips at 31 instead of 32
module fds_sound(
    input m2,
    input reset,
    input wr,
    input [15:0] ain,
    input [7:0] din,
    output reg [7:0] dout,
    output [11:0] sndout,
	 input clk
);
    reg vol_en, vol_dir, env_en, wave_en;
    reg wave_we;
    reg [1:0] mastervol;
    reg [11:0] freq, modfreq;
    reg sweep_en, sweep_dir;
    reg mod_en;
    reg [7:0] env_speed;

    always@(posedge clk, posedge reset) begin
        if(reset) begin
            vol_en<=1;
            sweep_en<=1;
            env_en<=1;
            wave_en<=1;
        end else begin
            if(m2 & wr) begin
                case(ain)
                    16'h4080:{vol_en, vol_dir}<=din[7:6];
                    16'h4082:freq[7:0]<=din;
                    16'h4083:{wave_en,env_en,freq[11:8]}<={din[7:6],din[3:0]};
                    16'h4084:{sweep_en, sweep_dir}<=din[7:6];
                    16'h4086:modfreq[7:0]<=din;
                    16'h4087:{mod_en,modfreq[11:8]}<={din[7],din[3:0]};
                    16'h4089:{wave_we,mastervol}<={din[7],din[1:0]};
                    16'h408a:env_speed<=din;
                endcase
            end
        end
    end

    //vol envelope
    reg [10:0] env_div;
    reg [5:0] vol_div;
    reg [5:0] vol, vol_speed;
    wire vol_clock=(~env_en & env_div==8 & ~vol_en &  vol_div==0);
    wire [4:0] vol_clip=vol[4:0]|{5{vol[5]}};
    always@(posedge clk) begin
		if (m2) begin
        if(~env_en) begin
            if(env_div==0)  env_div<={env_speed,3'b111};
            else        env_div<=env_div-1'd1;
            if(env_div==8 & ~vol_en) begin
                if(vol_div==0)  vol_div<=vol_speed;
                else        vol_div<=vol_div-1'd1;
            end
        end
        if(wr & ain==16'h4080 & ~din[7]) vol_speed<=din[5:0];
        if(wr & ain==16'h4080 & din[7]) vol<=din[5:0];
        else if(vol_clock) begin
            if(vol_dir & ~vol[5]) vol<=vol+1'd1;
            else if(~vol_dir & vol!=0) vol<=vol-1'd1;
        end 
		end
        
    end

    //sweep envelope
    reg [5:0] sweep_div;
    reg [5:0] sweep, sweep_speed;
    wire sweep_clock=(~env_en & env_div==8 & ~sweep_en & sweep_div==0);
    wire [4:0] sweep_clip=sweep[4:0]|{5{sweep[5]}};
    always@(posedge clk) begin
		if (m2) begin
        if(~env_en) begin
            if(env_div==8 & ~sweep_en) begin
                if(sweep_div==0) sweep_div<=sweep_speed;
                else sweep_div<=sweep_div-1'd1;
            end
        end
        if(wr & ain==16'h4084 & ~din[7]) sweep_speed<=din[5:0];
        if(wr & ain==16'h4084 & din[7]) sweep<=din[5:0];
        else if(sweep_clock) begin
            if(sweep_dir & ~sweep[5]) sweep<=sweep+1'd1;
            else if(~sweep_dir & sweep!=0) sweep<=sweep-1'd1;
        end 
		end
    end

    //modulation
    wire [2:0] mod_table_out;
    reg [4:0] mod_ptr_in;
    reg [5:0] mod_ptr_out;
    reg [15:0] mod_cnt;
    reg signed [5:0] bias, bias_inc;
    wire [16:0] mod_cnt_next=mod_cnt+modfreq;
//    RAMB4_S4_S4 modtable(
//        .WEA(wr & ain==16'h4088 & mod_en), .ENA(1'b1), .RSTA(1'b0), .CLKA(m2), .ADDRA({5'd0,mod_ptr_in}), .DIA({1'b0,din[2:0]}), .DOA(),    //write port
//        .WEB(1'b0), .ENB(1'b1 /*~mod_we & ~mod_en*/), .RSTB(1'b0), .CLKB(m2), .ADDRB({5'd0,mod_ptr_out[5:1]}), .DIB(4'd0), .DOB(mod_table_out));        //read port
    wire [7:0] modtable_outb;
	 assign mod_table_out = modtable_outb[2:0];
  dpram #(.widthad_a(5)) modtable
    (
      .clock_a   (clk),
      .address_a (mod_ptr_in),
      .wren_a    (wr & ain==16'h4088 & mod_en),
		.byteena_a (1),
      .data_a    ({5'b0,din[2:0]}),
      //.q_a     (),

      .clock_b   (clk),
      .address_b (mod_ptr_out[5:1]),
      .wren_b    (0),
		.byteena_b (1),
      .data_b    (0),
      .q_b       (modtable_outb)
    );
    always@(posedge clk) begin
		if (m2) begin
        if(wr) begin
            if(ain==16'h4087 & din[7])      mod_ptr_in<=0;
            else if(ain==16'h4088 & mod_en)     mod_ptr_in<=mod_ptr_in+1'd1;
        end

        //if(~mod_en)
            mod_cnt<=mod_cnt_next[15:0];

        if(wr & ain==16'h4087 & din[7]) mod_ptr_out<=0;
        else if(/*~mod_en &*/ mod_cnt_next[16]) mod_ptr_out<=mod_ptr_out+1'd1;

        if(wr & (ain==16'h4085 | ain==16'h4087) & din[7])
            bias<=0;
        else if(~mod_en & mod_cnt_next[16]) begin
            if(mod_table_out==4)    bias<=0;
            else            bias<=bias+bias_inc;
        end
		end
    end
    always@*
    case(mod_table_out)
        0:bias_inc=0;
        1:bias_inc=1;
        2:bias_inc=2;
        3:bias_inc=4;
        4:bias_inc=0;
        5:bias_inc=-6'd4;
        6:bias_inc=-6'd2;
        7:bias_inc=-6'd1;
    endcase
    wire [9:0] mod_sweep=(sweep_clip*bias)^10'h200;     //6x5 signed mul
    wire [21:0] mod_freq_mul; //=freq*mod_sweep;
    mul10x12 mm(clk,m2,freq,mod_sweep,mod_freq_mul);
    wire [12:0] modulated_freq=mod_freq_mul[21:9];

    //waveform step
    wire [12:0] wave_freq=mod_en?freq:modulated_freq;
    reg [15:0] wave_cnt;
    wire [16:0] wave_cnt_next=wave_cnt+wave_freq;
    reg [5:0] wave_ptr;
    always@(posedge clk) begin
		if (m2) begin
        if(~wave_en)
            wave_cnt<=wave_cnt_next[15:0];
        //if(wr & ain==16'h4083 & din[7])
        //  wave_ptr<=0;
        //else
        if(~wave_en & wave_cnt_next[16])
            wave_ptr<=wave_ptr+1'd1;
		end
    end

    //6x64 wavetable ram
    wire [7:0] outA, outB;
    wire waveaddr=ain[15:6]==10'b0100_0000_01;  //4040..407F
//    RAMB4_S8_S8 waveform(
//        .WEA(wr & wave_we & waveaddr),  //cpu write / wave read
//        .ENA(1'b1),
//        .RSTA(1'b0),
//        .CLKA(m2),      //write on posedge M2
//        .ADDRA({3'd0,wave_we?ain[5:0]:wave_ptr[5:0]}),
//        .DIA(din),
//        .DOA(outA),
//
//        .WEB(1'b0),     //cpu read
//        .ENB(waveaddr),
//        .RSTB(1'b0),
//        .CLKB(~m2),     //read on negedge M2
//        .ADDRB({3'd0,ain[5:0]}),
//        .DIB(8'd0),
//        .DOB(outB)
//    );
  dpram #(.widthad_a(6)) waveform
    (
      .clock_a   (clk),
      .address_a (wave_we?ain[5:0]:wave_ptr[5:0]),
      .wren_a    (wr & wave_we & waveaddr),
		.byteena_a (1),
      .data_a    (din),
      .q_a       (outA),

      .clock_b   (clk), //~m2
		.byteena_b (waveaddr),
      .address_b (ain[5:0]),
      .wren_b    (0),
      .data_b    (0),
      .q_b       (outB)
    );

    reg [5:0] outA_buf;
    always@(posedge clk) if(m2 & ~wave_we & ~wave_en) outA_buf<=outA[5:0];
    wire [10:0] mul_out=outA_buf*vol_clip;      //6x5 mult
// 0.8 vol
    wire [6:0] out1=(mastervol!=3)?7'd0:mul_out[10:4]; //{1100 1000 0110 0101} (approximates 1, 2/3, 1/2, 2/5.. try to match VRC6 output levels)
    wire [8:0] out2=out1+((mastervol!=2)?9'd0:mul_out[10:3]);
    wire [9:0] out4=out2+((mastervol==1)?10'd0:mul_out[10:2]);
    assign sndout=out4+((mastervol[1])?12'd0:mul_out[10:1]);
/*
// 2/3 vol
    wire [6:0] out1=(~^mastervol)?0:mul_out[10:4];  //{1010 0111 0101 0100} (approximates 1, 2/3, 1/2, 2/5.. try to match VRC6 output levels)
    wire [8:0] out2=out1+((mastervol[1])?0:mul_out[10:3]);
    wire [9:0] out4=out2+((mastervol==0)?0:mul_out[10:2]);
    assign sndout=out4+((mastervol!=0)?0:mul_out[10:1]);
*/
    always@* begin
        dout[7:6]='b01;
        if({ain[7],ain[1]}==2'b10)  dout[5:0]=vol;  //4090
        else if({ain[7],ain[1]}==2'b11) dout[5:0]=sweep;    //4092
        else                dout[5:0]=outB[5:0];
    end

endmodule

//10x12 unsigned multiplier
module mul10x12(input clk, input ce, input [11:0] in12, input [9:0] in10, output reg [21:0] out);
    reg [3:0] count;
    reg [11:0] sr1;
    reg [21:0] sr2;
    wire [10:0] sum=sr2[21:12]+(sr1[0]?in10:11'd0);
    wire [21:0] next={sum,sr2[11:1]};
    always@(posedge clk) begin
		if(ce) begin
        count<=count+1'd1;
        if(count==0) begin
            sr1<=in12;
            sr2<=0;
        end else begin
            sr1<={1'b0,sr1[11:1]};
            sr2<=next;
        end
        if(count==12)
            out<=next;
		end
    end
endmodule
