// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

module Mac(input clk, input use_accum, input [17:0] A, input [17:0] B, input [17:0] D, output [47:0] P);
  wire [7:0] OPMODE = use_accum ? 8'b00011001 : 8'b00010001;
   DSP48A1 #(
      .A0REG(0),              // First stage A input pipeline register (0/1)
      .A1REG(0),              // Second stage A input pipeline register (0/1)
      .B0REG(0),              // First stage B input pipeline register (0/1)
      .B1REG(0),              // Second stage B input pipeline register (0/1)
      .CARRYINREG(0),         // CARRYIN input pipeline register (0/1)
      .CARRYINSEL("OPMODE5"), // Specify carry-in source, "CARRYIN" or "OPMODE5" 
      .CARRYOUTREG(0),        // CARRYOUT output pipeline register (0/1)
      .CREG(0),               // C input pipeline register (0/1)
      .DREG(0),               // D pre-adder input pipeline register (0/1)
      .MREG(0),               // M pipeline register (0/1)
      .OPMODEREG(0),          // Enable=1/disable=0 OPMODE input pipeline registers
      .PREG(1),               // P output pipeline register (0/1)
      .RSTTYPE("SYNC")        // Specify reset type, "SYNC" or "ASYNC" 
   )
   
   DSP48A1_inst (
      // Cascade Ports: 18-bit (each) output: Ports to cascade from one DSP48 to another
//      .BCOUT(BCOUT),           // 18-bit output: B port cascade output
//      .PCOUT(PCOUT),           // 48-bit output: P cascade output (if used, connect to PCIN of another DSP48A1)
      // Data Ports: 1-bit (each) output: Data input and output ports
//      .CARRYOUT(CARRYOUT),     // 1-bit output: carry output (if used, connect to CARRYIN pin of another
//                               // DSP48A1)

//      .CARRYOUTF(CARRYOUTF),   // 1-bit output: fabric carry output
//      .M(M),                   // 36-bit output: fabric multiplier data output
      .P(P),                   // 48-bit output: data output
      // Cascade Ports: 48-bit (each) input: Ports to cascade from one DSP48 to another
//      .PCIN(0),             // 48-bit input: P cascade input (if used, connect to PCOUT of another DSP48A1)
      // Control Input Ports: 1-bit (each) input: Clocking and operation mode
      .CLK(clk),               // 1-bit input: clock input
      .OPMODE(OPMODE),         // 8-bit input: operation mode input
      // Data Ports: 18-bit (each) input: Data input and output ports
      .A(A),                   // 18-bit input: A data input
      .B(B),                   // 18-bit input: B data input (connected to fabric or BCOUT of adjacent DSP48A1)
  //    .C(C),                   // 48-bit input: C data input
 //     .CARRYIN(CARRYIN),       // 1-bit input: carry input signal (if used, connect to CARRYOUT pin of another
 //                              // DSP48A1)

      .D(D),                 // 18-bit input: B pre-adder data input
      // Reset/Clock Enable Input Ports: 1-bit (each) input: Reset and enable input ports
      .CEA(1'b0),              // 1-bit input: active high clock enable input for A registers
      .CEB(1'b0),              // 1-bit input: active high clock enable input for B registers
      .CEC(1'b0),              // 1-bit input: active high clock enable input for C registers
      .CECARRYIN(1'b0),        // 1-bit input: active high clock enable input for CARRYIN registers
      .CED(1'b0),              // 1-bit input: active high clock enable input for D registers
      .CEM(1'b0),              // 1-bit input: active high clock enable input for multiplier registers
      .CEOPMODE(1'b0),         // 1-bit input: active high clock enable input for OPMODE registers
      .CEP(1'b1),              // 1-bit input: active high clock enable input for P registers
      .RSTA(1'b0),             // 1-bit input: reset input for A pipeline registers
      .RSTB(1'b0),             // 1-bit input: reset input for B pipeline registers
      .RSTC(1'b0),             // 1-bit input: reset input for C pipeline registers
      .RSTCARRYIN(1'b0),       // 1-bit input: reset input for CARRYIN pipeline registers
      .RSTD(1'b0),             // 1-bit input: reset input for D pipeline registers
      .RSTM(1'b0),             // 1-bit input: reset input for M pipeline registers
      .RSTOPMODE(1'b0),        // 1-bit input: reset input for OPMODE pipeline registers
      .RSTP(1'b0)              // 1-bit input: reset input for P pipeline registers
   );
endmodule

module Add24(input [4:0] a, input [4:0] b, output [4:0] r);
  wire [5:0] t = a + b;
  wire [1:0] u = t[5:3] == 0 ? 0 : 
                 t[5:3] == 1 ? 1 : 
                 t[5:3] == 2 ? 2 : 
                 t[5:3] == 3 ? 0 : 
                 t[5:3] == 4 ? 1 : 
                 t[5:3] == 5 ? 2 : 
                 t[5:3] == 6 ? 0 : 1;
  assign r = {u, t[2:0]};
endmodule

module FirFilter(input clk, input [15:0] sample_in, output [15:0] sample_out, output sample_now);
  reg [15:0] X[0:1023];  // Samples are only 16 bits.
  reg [17:0] B[0:511];   // Coefficients are 18 bits.
  integer i;
  // IIR Coefficients
  initial begin
    for(i = 0;i < 1024; i = i + 1) X[i] = 0;
B[0]=0; B[1]=-13; B[2]=-25; B[3]=-38;
B[4]=-50; B[5]=-63; B[6]=-75; B[7]=-87;
B[8]=-100; B[9]=-112; B[10]=-124; B[11]=-136;
B[12]=-148; B[13]=-160; B[14]=-172; B[15]=-184;
B[16]=-195; B[17]=-206; B[18]=-217; B[19]=-227;
B[20]=-238; B[21]=-248; B[22]=-257; B[23]=-266;
B[24]=-275; B[25]=-284; B[26]=-292; B[27]=-299;
B[28]=-306; B[29]=-312; B[30]=-318; B[31]=-323;
B[32]=-328; B[33]=-332; B[34]=-335; B[35]=-337;
B[36]=-339; B[37]=-340; B[38]=-340; B[39]=-340;
B[40]=-338; B[41]=-335; B[42]=-332; B[43]=-328;
B[44]=-322; B[45]=-316; B[46]=-309; B[47]=-300;
B[48]=-291; B[49]=-281; B[50]=-269; B[51]=-256;
B[52]=-243; B[53]=-228; B[54]=-212; B[55]=-195;
B[56]=-178; B[57]=-159; B[58]=-138; B[59]=-117;
B[60]=-95; B[61]=-72; B[62]=-48; B[63]=-23;
B[64]=3; B[65]=29; B[66]=57; B[67]=85;
B[68]=114; B[69]=144; B[70]=174; B[71]=205;
B[72]=236; B[73]=268; B[74]=300; B[75]=333;
B[76]=365; B[77]=398; B[78]=430; B[79]=463;
B[80]=495; B[81]=527; B[82]=558; B[83]=589;
B[84]=620; B[85]=650; B[86]=679; B[87]=707;
B[88]=734; B[89]=760; B[90]=785; B[91]=808;
B[92]=830; B[93]=850; B[94]=869; B[95]=886;
B[96]=901; B[97]=914; B[98]=925; B[99]=933;
B[100]=940; B[101]=944; B[102]=945; B[103]=944;
B[104]=941; B[105]=935; B[106]=925; B[107]=914;
B[108]=899; B[109]=881; B[110]=861; B[111]=837;
B[112]=810; B[113]=781; B[114]=748; B[115]=712;
B[116]=673; B[117]=631; B[118]=587; B[119]=539;
B[120]=488; B[121]=435; B[122]=378; B[123]=319;
B[124]=258; B[125]=193; B[126]=127; B[127]=58;
B[128]=-13; B[129]=-86; B[130]=-161; B[131]=-238;
B[132]=-316; B[133]=-396; B[134]=-477; B[135]=-559;
B[136]=-642; B[137]=-726; B[138]=-810; B[139]=-894;
B[140]=-978; B[141]=-1062; B[142]=-1145; B[143]=-1228;
B[144]=-1309; B[145]=-1390; B[146]=-1469; B[147]=-1546;
B[148]=-1621; B[149]=-1694; B[150]=-1764; B[151]=-1832;
B[152]=-1896; B[153]=-1957; B[154]=-2015; B[155]=-2069;
B[156]=-2119; B[157]=-2164; B[158]=-2205; B[159]=-2241;
B[160]=-2272; B[161]=-2298; B[162]=-2319; B[163]=-2333;
B[164]=-2343; B[165]=-2346; B[166]=-2343; B[167]=-2333;
B[168]=-2318; B[169]=-2295; B[170]=-2267; B[171]=-2231;
B[172]=-2189; B[173]=-2139; B[174]=-2083; B[175]=-2020;
B[176]=-1950; B[177]=-1873; B[178]=-1789; B[179]=-1698;
B[180]=-1600; B[181]=-1496; B[182]=-1385; B[183]=-1268;
B[184]=-1145; B[185]=-1015; B[186]=-880; B[187]=-739;
B[188]=-592; B[189]=-440; B[190]=-283; B[191]=-122;
B[192]=44; B[193]=213; B[194]=387; B[195]=563;
B[196]=743; B[197]=924; B[198]=1108; B[199]=1294;
B[200]=1480; B[201]=1668; B[202]=1855; B[203]=2042;
B[204]=2229; B[205]=2414; B[206]=2597; B[207]=2778;
B[208]=2956; B[209]=3131; B[210]=3302; B[211]=3468;
B[212]=3630; B[213]=3786; B[214]=3935; B[215]=4078;
B[216]=4214; B[217]=4343; B[218]=4463; B[219]=4574;
B[220]=4676; B[221]=4769; B[222]=4851; B[223]=4923;
B[224]=4984; B[225]=5033; B[226]=5070; B[227]=5096;
B[228]=5108; B[229]=5108; B[230]=5095; B[231]=5068;
B[232]=5027; B[233]=4972; B[234]=4904; B[235]=4821;
B[236]=4723; B[237]=4611; B[238]=4485; B[239]=4344;
B[240]=4188; B[241]=4018; B[242]=3833; B[243]=3634;
B[244]=3421; B[245]=3194; B[246]=2954; B[247]=2700;
B[248]=2433; B[249]=2153; B[250]=1861; B[251]=1557;
B[252]=1242; B[253]=915; B[254]=579; B[255]=233;
B[256]=-122; B[257]=-485; B[258]=-857; B[259]=-1235;
B[260]=-1619; B[261]=-2008; B[262]=-2402; B[263]=-2800;
B[264]=-3200; B[265]=-3602; B[266]=-4004; B[267]=-4407;
B[268]=-4808; B[269]=-5208; B[270]=-5603; B[271]=-5995;
B[272]=-6381; B[273]=-6761; B[274]=-7133; B[275]=-7496;
B[276]=-7850; B[277]=-8193; B[278]=-8523; B[279]=-8840;
B[280]=-9144; B[281]=-9431; B[282]=-9702; B[283]=-9956;
B[284]=-10191; B[285]=-10406; B[286]=-10600; B[287]=-10773;
B[288]=-10922; B[289]=-11048; B[290]=-11149; B[291]=-11224;
B[292]=-11273; B[293]=-11294; B[294]=-11287; B[295]=-11251;
B[296]=-11185; B[297]=-11088; B[298]=-10960; B[299]=-10801;
B[300]=-10609; B[301]=-10385; B[302]=-10127; B[303]=-9836;
B[304]=-9510; B[305]=-9150; B[306]=-8756; B[307]=-8327;
B[308]=-7863; B[309]=-7365; B[310]=-6831; B[311]=-6263;
B[312]=-5660; B[313]=-5023; B[314]=-4352; B[315]=-3647;
B[316]=-2909; B[317]=-2137; B[318]=-1334; B[319]=-498;
B[320]=368; B[321]=1265; B[322]=2191; B[323]=3146;
B[324]=4129; B[325]=5139; B[326]=6174; B[327]=7235;
B[328]=8318; B[329]=9424; B[330]=10552; B[331]=11699;
B[332]=12864; B[333]=14047; B[334]=15245; B[335]=16457;
B[336]=17682; B[337]=18918; B[338]=20163; B[339]=21416;
B[340]=22676; B[341]=23939; B[342]=25206; B[343]=26474;
B[344]=27741; B[345]=29005; B[346]=30265; B[347]=31520;
B[348]=32766; B[349]=34004; B[350]=35229; B[351]=36442;
B[352]=37640; B[353]=38821; B[354]=39984; B[355]=41127;
B[356]=42248; B[357]=43345; B[358]=44418; B[359]=45464;
B[360]=46482; B[361]=47470; B[362]=48426; B[363]=49350;
B[364]=50239; B[365]=51094; B[366]=51911; B[367]=52690;
B[368]=53430; B[369]=54129; B[370]=54787; B[371]=55402;
B[372]=55974; B[373]=56501; B[374]=56983; B[375]=57419;
B[376]=57808; B[377]=58150; B[378]=58444; B[379]=58690;
B[380]=58887; B[381]=59035; B[382]=59134; B[383]=59183;
  end
  
  reg [4:0] s = 0;
  reg [4:0] xo = 0;
  reg [3:0] t = 0;
  wire [47:0] P;          // Output from MAC unit

 // wire [4:0] outp = (xo + t) % 24, outn = (xo + 23 - t) % 24;
  wire [4:0] outp, outn;
  Add24 add24(xo, {1'b0, t}, outp);
  Add24 sub24(xo, 5'd23 - {1'b0, t}, outn);

  // Various addresses
  wire [8:0] a1 = {t, s};
  wire [9:0] a2 = {outp, s}, a3 = {outn, ~s};
  // Temp storage from blockram.
  reg [17:0] next_B = 0;
  reg [15:0] next_X0 = 0, next_X1 = 0;
  // Output sample is delayed two clocks. One is for fetching
  // from blockram, and one is in multiplier.
  reg delay1 = 0, delay2 = 0;
  assign sample_now = !delay2;
  assign sample_out = P[37:22];
  // Clock 0 => Read from RAM into temp registers
  // Clock 1 => Multiply and accumulate into P reg.
  // Clock 2 => Output is available 
  Mac mac(.clk(clk), .use_accum(delay2), 
          .A(next_B),
          .B({next_X0[15], next_X0[15], next_X0}),
          .D({next_X1[15], next_X1[15], next_X1}),
          .P(P));
  wire [5:0] new_s = s + (t == 4'd11);
  wire [4:0] new_xo = xo - 5'd1;
  always @(posedge clk) begin
    //$write("xo:%d s:%d t:%d a1:%d a2:%d a3:%d (%d %d) P:%d(%d)\n", xo, s, t, a1, a2, a3, outp, outn, $signed(P), delay2);
    t <= (t == 4'd11) ? 0 : t + 4'd1;
    s <= new_s[4:0];
    {next_B, next_X0, next_X1} <= {B[a1], X[a2], X[a3]};
    if (t == 0)
      X[a3] <= sample_in;
    if (new_s[5])
      xo <= {new_xo[4:3] == 2'b11 ? 2'b10 : new_xo[4:3], new_xo[2:0]};
    delay2 <= delay1;
    delay1 <= !new_s[5];
  end
endmodule  // FirFilter
