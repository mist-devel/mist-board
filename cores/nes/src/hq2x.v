// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

module DiffCheck(input [14:0] rgb1, input [14:0] rgb2, output result);
  wire [5:0] r = rgb1[4:0] - rgb2[4:0];
  wire [5:0] g = rgb1[9:5] - rgb2[9:5];
  wire [5:0] b = rgb1[14:10] - rgb2[14:10];
  wire [6:0] t = $signed(r) + $signed(b);
  wire [6:0] gx = {g[5], g};
  wire [7:0] y = $signed(t) + $signed(gx);
  wire [6:0] u = $signed(r) - $signed(b);
  wire [7:0] v = $signed({g, 1'b0}) - $signed(t);
  // if y is inside (-24..24)
  wire y_inside = (y < 8'h18 || y >= 8'he8);
  // if u is inside (-4, 4)
  wire u_inside = (u < 7'h4 || u >= 7'h7c);
  // if v is inside (-6, 6)
  wire v_inside = (v < 8'h6 || v >= 8'hfA);
  assign result = !(y_inside && u_inside && v_inside);
endmodule

module InnerBlend(input [8:0] Op, input [4:0] A, input [4:0] B, input [4:0] C, output [4:0] O);
  wire OpOnes = Op[4];
  wire [7:0] Amul = A * Op[7:5];
  wire [6:0] Bmul = B * Op[3:2];
  wire [6:0] Cmul = C * Op[1:0];
  wire [7:0] At =  Amul;
  wire [7:0] Bt = (OpOnes == 0) ? {Bmul, 1'b0} : {3'b0, B};
  wire [7:0] Ct = (OpOnes == 0) ? {Cmul, 1'b0} : {3'b0, C};
  wire [8:0] Res = {At, 1'b0} + Bt + Ct;
  assign O = Op[8] ? A : Res[8:4];
endmodule

module Blend(input [5:0] rule, input disable_hq2x,
             input [14:0] E, input [14:0] A, input [14:0] B, input [14:0] D, input [14:0] F, input [14:0] H, output [14:0] Result);
  reg [1:0] input_ctrl;
  reg [8:0] op;
  localparam BLEND0 = 9'b1_xxx_x_xx_xx; // 0: A
  localparam BLEND1 = 9'b0_110_0_10_00; // 1: (A * 12 + B * 4) >> 4
  localparam BLEND2 = 9'b0_100_0_10_10; // 2: (A * 8 + B * 4 + C * 4) >> 4
  localparam BLEND3 = 9'b0_101_0_10_01; // 3: (A * 10 + B * 4 + C * 2) >> 4
  localparam BLEND4 = 9'b0_110_0_01_01; // 4: (A * 12 + B * 2 + C * 2) >> 4
  localparam BLEND5 = 9'b0_010_0_11_11; // 5: (A * 4 + (B + C) * 6) >> 4
  localparam BLEND6 = 9'b0_111_1_xx_xx; // 6: (A * 14 + B + C) >> 4
  localparam AB = 2'b00;
  localparam AD = 2'b01;
  localparam DB = 2'b10;
  localparam BD = 2'b11;
  wire is_diff;
  DiffCheck diff_checker(rule[1] ? B : H,
                         rule[0] ? D : F,
                         is_diff);
  always @* begin
    case({!is_diff, rule[5:2]})
    1,17:  {op, input_ctrl} = {BLEND1, AB};
    2,18:  {op, input_ctrl} = {BLEND1, DB};
    3,19:  {op, input_ctrl} = {BLEND1, BD};
    4,20:  {op, input_ctrl} = {BLEND2, DB};
    5,21:  {op, input_ctrl} = {BLEND2, AB};
    6,22:  {op, input_ctrl} = {BLEND2, AD};

    8: {op, input_ctrl} = {BLEND0, 2'bxx};
    9: {op, input_ctrl} = {BLEND0, 2'bxx};
    10: {op, input_ctrl} = {BLEND0, 2'bxx};
    11: {op, input_ctrl} = {BLEND1, AB};
    12: {op, input_ctrl} = {BLEND1, AB};
    13: {op, input_ctrl} = {BLEND1, AB};
    14: {op, input_ctrl} = {BLEND1, DB};
    15: {op, input_ctrl} = {BLEND1, BD};

    24: {op, input_ctrl} = {BLEND2, DB};
    25: {op, input_ctrl} = {BLEND5, DB};
    26: {op, input_ctrl} = {BLEND6, DB};
    27: {op, input_ctrl} = {BLEND2, DB};
    28: {op, input_ctrl} = {BLEND4, DB};
    29: {op, input_ctrl} = {BLEND5, DB};
    30: {op, input_ctrl} = {BLEND3, BD};
    31: {op, input_ctrl} = {BLEND3, DB};
    default: {op, input_ctrl} = 11'bx;
    endcase
    
    // Setting op[8] effectively disables HQ2X because blend will always return E.
    if (disable_hq2x)
      op[8] = 1;
  end
  // Generate inputs to the inner blender. Valid combinations.
  // 00: E A B
  // 01: E A D 
  // 10: E D B
  // 11: E B D
  wire [14:0] Input1 = E;
  wire [14:0] Input2 = !input_ctrl[1] ? A :
                       !input_ctrl[0] ? D : B;
  wire [14:0] Input3 = !input_ctrl[0] ? B : D;
  InnerBlend inner_blend1(op, Input1[4:0],   Input2[4:0],   Input3[4:0],   Result[4:0]);
  InnerBlend inner_blend2(op, Input1[9:5],   Input2[9:5],   Input3[9:5],   Result[9:5]);
  InnerBlend inner_blend3(op, Input1[14:10], Input2[14:10], Input3[14:10], Result[14:10]);
endmodule

module Hq2x(input clk,
            input [14:0] inputpixel,
            input disable_hq2x,
            input reset_frame,
            input reset_line,
            input [9:0] read_x,
            output frame_available,
            output reg [14:0] outpixel);
reg [5:0] hqTable[0:255];
initial begin
hqTable[0] = 19; hqTable[1] = 19; hqTable[2] = 26; hqTable[3] = 11;
hqTable[4] = 19; hqTable[5] = 19; hqTable[6] = 26; hqTable[7] = 11;
hqTable[8] = 23; hqTable[9] = 15; hqTable[10] = 47; hqTable[11] = 35;
hqTable[12] = 23; hqTable[13] = 15; hqTable[14] = 55; hqTable[15] = 39;
hqTable[16] = 19; hqTable[17] = 19; hqTable[18] = 26; hqTable[19] = 58;
hqTable[20] = 19; hqTable[21] = 19; hqTable[22] = 26; hqTable[23] = 58;
hqTable[24] = 23; hqTable[25] = 15; hqTable[26] = 35; hqTable[27] = 35;
hqTable[28] = 23; hqTable[29] = 15; hqTable[30] = 7; hqTable[31] = 35;
hqTable[32] = 19; hqTable[33] = 19; hqTable[34] = 26; hqTable[35] = 11;
hqTable[36] = 19; hqTable[37] = 19; hqTable[38] = 26; hqTable[39] = 11;
hqTable[40] = 23; hqTable[41] = 15; hqTable[42] = 55; hqTable[43] = 39;
hqTable[44] = 23; hqTable[45] = 15; hqTable[46] = 51; hqTable[47] = 43;
hqTable[48] = 19; hqTable[49] = 19; hqTable[50] = 26; hqTable[51] = 58;
hqTable[52] = 19; hqTable[53] = 19; hqTable[54] = 26; hqTable[55] = 58;
hqTable[56] = 23; hqTable[57] = 15; hqTable[58] = 51; hqTable[59] = 35;
hqTable[60] = 23; hqTable[61] = 15; hqTable[62] = 7; hqTable[63] = 43;
hqTable[64] = 19; hqTable[65] = 19; hqTable[66] = 26; hqTable[67] = 11;
hqTable[68] = 19; hqTable[69] = 19; hqTable[70] = 26; hqTable[71] = 11;
hqTable[72] = 23; hqTable[73] = 61; hqTable[74] = 35; hqTable[75] = 35;
hqTable[76] = 23; hqTable[77] = 61; hqTable[78] = 51; hqTable[79] = 35;
hqTable[80] = 19; hqTable[81] = 19; hqTable[82] = 26; hqTable[83] = 11;
hqTable[84] = 19; hqTable[85] = 19; hqTable[86] = 26; hqTable[87] = 11;
hqTable[88] = 23; hqTable[89] = 15; hqTable[90] = 51; hqTable[91] = 35;
hqTable[92] = 23; hqTable[93] = 15; hqTable[94] = 51; hqTable[95] = 35;
hqTable[96] = 19; hqTable[97] = 19; hqTable[98] = 26; hqTable[99] = 11;
hqTable[100] = 19; hqTable[101] = 19; hqTable[102] = 26; hqTable[103] = 11;
hqTable[104] = 23; hqTable[105] = 61; hqTable[106] = 7; hqTable[107] = 35;
hqTable[108] = 23; hqTable[109] = 61; hqTable[110] = 7; hqTable[111] = 43;
hqTable[112] = 19; hqTable[113] = 19; hqTable[114] = 26; hqTable[115] = 11;
hqTable[116] = 19; hqTable[117] = 19; hqTable[118] = 26; hqTable[119] = 58;
hqTable[120] = 23; hqTable[121] = 15; hqTable[122] = 51; hqTable[123] = 35;
hqTable[124] = 23; hqTable[125] = 61; hqTable[126] = 7; hqTable[127] = 43;
hqTable[128] = 19; hqTable[129] = 19; hqTable[130] = 26; hqTable[131] = 11;
hqTable[132] = 19; hqTable[133] = 19; hqTable[134] = 26; hqTable[135] = 11;
hqTable[136] = 23; hqTable[137] = 15; hqTable[138] = 47; hqTable[139] = 35;
hqTable[140] = 23; hqTable[141] = 15; hqTable[142] = 55; hqTable[143] = 39;
hqTable[144] = 19; hqTable[145] = 19; hqTable[146] = 26; hqTable[147] = 11;
hqTable[148] = 19; hqTable[149] = 19; hqTable[150] = 26; hqTable[151] = 11;
hqTable[152] = 23; hqTable[153] = 15; hqTable[154] = 51; hqTable[155] = 35;
hqTable[156] = 23; hqTable[157] = 15; hqTable[158] = 51; hqTable[159] = 35;
hqTable[160] = 19; hqTable[161] = 19; hqTable[162] = 26; hqTable[163] = 11;
hqTable[164] = 19; hqTable[165] = 19; hqTable[166] = 26; hqTable[167] = 11;
hqTable[168] = 23; hqTable[169] = 15; hqTable[170] = 55; hqTable[171] = 39;
hqTable[172] = 23; hqTable[173] = 15; hqTable[174] = 51; hqTable[175] = 43;
hqTable[176] = 19; hqTable[177] = 19; hqTable[178] = 26; hqTable[179] = 11;
hqTable[180] = 19; hqTable[181] = 19; hqTable[182] = 26; hqTable[183] = 11;
hqTable[184] = 23; hqTable[185] = 15; hqTable[186] = 51; hqTable[187] = 39;
hqTable[188] = 23; hqTable[189] = 15; hqTable[190] = 7; hqTable[191] = 43;
hqTable[192] = 19; hqTable[193] = 19; hqTable[194] = 26; hqTable[195] = 11;
hqTable[196] = 19; hqTable[197] = 19; hqTable[198] = 26; hqTable[199] = 11;
hqTable[200] = 23; hqTable[201] = 15; hqTable[202] = 51; hqTable[203] = 35;
hqTable[204] = 23; hqTable[205] = 15; hqTable[206] = 51; hqTable[207] = 39;
hqTable[208] = 19; hqTable[209] = 19; hqTable[210] = 26; hqTable[211] = 11;
hqTable[212] = 19; hqTable[213] = 19; hqTable[214] = 26; hqTable[215] = 11;
hqTable[216] = 23; hqTable[217] = 15; hqTable[218] = 51; hqTable[219] = 35;
hqTable[220] = 23; hqTable[221] = 15; hqTable[222] = 7; hqTable[223] = 35;
hqTable[224] = 19; hqTable[225] = 19; hqTable[226] = 26; hqTable[227] = 11;
hqTable[228] = 19; hqTable[229] = 19; hqTable[230] = 26; hqTable[231] = 11;
hqTable[232] = 23; hqTable[233] = 15; hqTable[234] = 51; hqTable[235] = 35;
hqTable[236] = 23; hqTable[237] = 15; hqTable[238] = 7; hqTable[239] = 43;
hqTable[240] = 19; hqTable[241] = 19; hqTable[242] = 26; hqTable[243] = 11;
hqTable[244] = 19; hqTable[245] = 19; hqTable[246] = 26; hqTable[247] = 11;
hqTable[248] = 23; hqTable[249] = 15; hqTable[250] = 7; hqTable[251] = 35;
hqTable[252] = 23; hqTable[253] = 15; hqTable[254] = 7; hqTable[255] = 43;
end

reg [14:0] Prev0, Prev1, Prev2, Curr0, Curr1, Curr2, Next0, Next1, Next2;
reg [14:0] A, B, D, F, G, H;
reg [7:0] pattern, nextpatt;
reg [1:0] i;
reg [7:0] y;
reg [1:0] yshort; // counts only lines 0-3, then stays on 3.
reg [8:0] offs;
reg first_pixel;
reg [14:0] inbuf[0:511];   // 2 lines of input pixels
reg [14:0] outbuf[0:2047]; // 4 lines of output pixels


wire curbuf = y[0];
reg last_line;
wire prevbuf = (yshort <= 1) ? curbuf : !curbuf;
wire writebuf = !curbuf;
reg writestep;

wire diff0, diff1;
DiffCheck diffcheck0(Curr1, (i == 0) ? Prev0 : (i == 1) ? Curr0 : (i == 2) ? Prev2 : Next1, diff0);
DiffCheck diffcheck1(Curr1, (i == 0) ? Prev1 : (i == 1) ? Next0 : (i == 2) ? Curr2 : Next2, diff1);
wire [7:0] new_pattern = {diff1, diff0, pattern[7:2]};
always @(posedge clk)
  pattern <= new_pattern;

wire less_254 = (offs >= 510) || (offs < 254);
wire [8:0] inbuf_rd_addr = {i[0] == 0 ? prevbuf : curbuf, offs[7:0]};

always @(posedge clk) begin
  if (i == 0 && less_254) Curr2 <= inbuf[inbuf_rd_addr];
  if (i == 1 && less_254) begin
    Prev2 <= Curr2;
    Curr2 <= inbuf[inbuf_rd_addr];
  end
  if (i == 2 && less_254) begin
    Next2 <= last_line ? Curr2 : inputpixel;
    inbuf[{writebuf, offs[7:0]}] <= inputpixel;
  end
end

wire [14:0] X = (i == 0) ? A : (i == 1) ? Prev1 : (i == 2) ? Next1 : G;
wire [14:0] blend_result;
Blend blender(hqTable[nextpatt], disable_hq2x, Curr0, X, B, D, F, H, blend_result);

always @(posedge clk) begin
  if (!offs[8])
    outbuf[{curbuf, i[1], offs[7:0], i[1]^i[0]}] <= blend_result;
  if (!writestep) begin
    nextpatt <= {nextpatt[5], nextpatt[3], nextpatt[0], nextpatt[6], nextpatt[1], nextpatt[7], nextpatt[4], nextpatt[2]};
    {B, F, H, D} <= {F, H, D, B};
  end else begin
    nextpatt <= {new_pattern[7:6], new_pattern[3], new_pattern[5], new_pattern[2], new_pattern[4], new_pattern[1:0]};
    {A, G} <= {Prev0, Next0};
    {B, F, H, D} <= {Prev1, Curr2, Next1, Curr0};
    {Prev0, Prev1} <= {first_pixel ? Prev2 : Prev1, Prev2};
    {Curr0, Curr1} <= {first_pixel ? Curr2 : Curr1, Curr2};
    {Next0, Next1} <= {first_pixel ? Next2 : Next1, Next2};
  end
end

reg last_reset_line;
initial last_reset_line = 0;

always @(posedge clk) begin
  outpixel <= outbuf[{!curbuf, read_x}];
  if (writestep) begin
    offs <= offs + 9'b1;
    first_pixel <= 0;
  end
  i <= i + 2'b1;
  writestep <= (i == 2);
  if (reset_line) begin
    offs <= -2;
    first_pixel <= 1;
    i <= 0;
    writestep <= 0;
    // Increment Y only once.
    if (!last_reset_line) begin
      y <= y + 8'b1;
      yshort <= (yshort == 3) ? yshort : (yshort + 2'b1);
      last_line <= ((y + 8'b1) >= 240);
    end
    
    
  end
  if (reset_frame) begin
    y <= 0;
    yshort <= 0;
    last_line <= 0;
  end
  last_reset_line <= reset_line;
end
assign frame_available = (i == 0) && first_pixel && (yshort == 2) && !reset_line;
endmodule  // Hq2x
