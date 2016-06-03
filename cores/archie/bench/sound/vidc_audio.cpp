/* vidc_audio.cpp

 Copyright (c) 2015, Stephen J. Leary
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the <organization> nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <verilated.h>          // Defines common routines
#include "Vvidc_audio.h"
#include "verilated_vcd_c.h"

#include "edge.h"

#include <iostream>
#include <sstream>
#include <fstream>
#include <string>
#include <cstdlib>
#include <cstdio>

Vvidc_audio *uut;     // Instantiation of module
unsigned char *main_memory = NULL;

vluint64_t main_time = 0;       // Current simulation time
// This is a 64-bit integer to reduce wrap over issues and
// allow modulus.  You can also use a double, if you wish.
double sc_time_stamp () {       // Called by $time in Verilog
    return main_time;           // converts to double, to match
    // what SystemC does
}

int main(int argc, char** argv) {
	
    Edge cpuclk;
    Edge audclk;
	  
    std::string fileName;

    if (argc > 1)
    {
	fileName = std::string(argv[1]);
    }

    std::cerr << fileName << std::endl;

    FILE *fp = fopen(fileName.c_str(), "r");
    if (fp == NULL)
    {
        std::cerr << "failed to open file: " << fileName << std::endl;
	exit(-1);
    }
    
    fseek(fp, 0L, SEEK_END);
    size_t sz = ftell(fp);
    fseek(fp, 0L, SEEK_SET);
    
    //main_memory = (unsigned char *) ((uintptr_t) malloc(sz*sizeof(unsigned char) +15) & (uintptr_t) ~0xF);
    //std::cerr << fread(main_memory, sizeof(unsigned char), sz, fp) << std::endl;
    //fclose(fp);
 
    Verilated::commandArgs(argc, argv);   // Remember args
    uut = new Vvidc_audio;      // Create instance
  
    //Verilated::traceEverOn(true);
    //VerilatedVcdC* tfp = new VerilatedVcdC;
    //uut->trace(tfp, 99);
    //std::string vcdname = fileName + ".vcd";
    //tfp->open(vcdname.c_str());

    uut->aud_rst = 1; 

    for (int i=i;i<8;i++)
      {
	uut->v__DOT__vidc_sir[i] = (i&1) ? 0 : 7;
      }
    bool side = false;
    size_t pointer = 0;
    
    uut->eval();            // Evaluate model

    while (!Verilated::gotFinish()) 
    {
        if (main_time > 32) 
	{
            uut->aud_rst = 0;   // Deassert reset
        }

        if ((main_time % 2) == 0) 
	{
            uut->aud_clk = uut->aud_clk ? 0 : 1;       // Toggle clock	    
        }

        audclk.Update(uut->aud_clk);
	
	uut->eval();            // Evaluate model
	//tfp->dump (main_time);
	
	if (uut->aud_en && audclk.PosEdge())
	{

	  unsigned char data;
	  if (fread(&data, sizeof(unsigned char), 1, fp) < 1)
	    {
	      break;
	    }
	  uut->aud_data = data;

	    if (side)
	      {
		std::cout.write((const char *)&(uut->aud_left), sizeof(short));
	      }
	    else
	      {
		std::cout.write((const char *)&(uut->aud_right), sizeof(short));
	      }
	    side = !side;
	}

	if (pointer >= sz)
	{
	    break;
	}
	
        main_time++;            // Time passes...
    }

    uut->final();               // Done simulating
    //tfp->close();
    delete uut;
    
}
