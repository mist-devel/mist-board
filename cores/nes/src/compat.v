// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.
module MUXCY(output O, input CI, input DI, input S);
  assign O = S ? CI : DI;
endmodule
module MUXCY_L(output LO, input CI, input DI, input S);
  assign LO = S ? CI : DI;
endmodule
module MUXCY_D(output LO, output O, input CI, input DI, input S);
  assign LO = S ? CI : DI;
  assign O = LO;
endmodule
module XORCY(output O, input CI, input LI);
  assign O = CI ^ LI;
endmodule
module XOR2(output O, input I0, input I1);
  assign O = I0 ^ I1;
endmodule