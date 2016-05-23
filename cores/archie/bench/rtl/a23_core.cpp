#include <verilated.h>          // Defines common routines
#include "Va23_core.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <sstream>
#include <fstream>
#include <string>
#include <cstdlib>
#include <cstdio>

Va23_core *uut;     // Instantiation of module
unsigned int *main_memory = NULL;
unsigned int *rom_memory = NULL;

vluint64_t main_time = 0;       // Current simulation time
// This is a 64-bit integer to reduce wrap over issues and
// allow modulus.  You can also use a double, if you wish.
double sc_time_stamp () {       // Called by $time in Verilog
    return main_time;           // converts to double, to match
    // what SystemC does
}

class Edge
{
public:
	Edge()
	{
		m_NegEdge = false;	
		m_PosEdge = false;	
		m_LastValue = false;	
	}

	void Update(bool value) 
	{ 
		m_PosEdge = value & ~ m_LastValue;
		m_NegEdge = ~value &  m_LastValue; 
		m_LastValue = value;
	}
	
	bool PosEdge() { return m_PosEdge; }
	bool NegEdge() { return m_NegEdge; }
	
private:
	bool m_NegEdge;
	bool m_PosEdge;
	bool m_LastValue;
};

#define MEMTOP 8*1024*1024

int main(int argc, char** argv) {
	
    Edge vsync;
    Edge hsync;
    Edge cpuclk;
    Edge pixclk;
	
    main_memory = (unsigned int *) malloc(MEMTOP); // 8MB of ram area. 
  
    std::string fileName;

    if (argc > 1)
      {
	fileName = std::string(argv[1]);
      }

    std::cout << fileName << std::endl;

    FILE *fp = fopen(fileName.c_str(), "r");
    if (fp == NULL)
    {
        std::cerr << "failed to open file: " << fileName << std::endl;
	exit(-1);
    }
    
    fseek(fp, 0L, SEEK_END);
    size_t sz = ftell(fp);
    fseek(fp, 0L, SEEK_SET);
    
    std::cerr << fread(main_memory, sizeof(char), sz, fp) << std::endl;
    fclose(fp);
 
    Verilated::commandArgs(argc, argv);   // Remember args
    uut = new Va23_core;      // Create instance
  
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    uut->trace(tfp, 99);
    std::string vcdname = fileName + ".vcd";
    tfp->open(vcdname.c_str());
    
    uut->i_irq = 0;
    uut->i_firq = 0;
    
    while (!Verilated::gotFinish()) 
    {
        if (main_time > 32) 
	{
            uut->i_system_rdy = 1;   // Deassert reset
        }

        if ((main_time % 2) == 0) 
	{
            uut->i_clk = uut->i_clk ? 0 : 1;       // Toggle clock	    
        }

        cpuclk.Update(uut->i_clk);
	
	uut->eval();            // Evaluate model
	tfp->dump (main_time);
	
	if (uut->o_wb_stb && cpuclk.PosEdge() && !(bool)uut->i_wb_ack) 
	{
	   if (uut->o_wb_we)
	   {
		unsigned int mask = 0;
		if (uut->o_wb_sel & 1) mask |= 0xFF;
		if (uut->o_wb_sel & 2) mask |= 0xFF00;
		if (uut->o_wb_sel & 4) mask |= 0xFF0000;
		if (uut->o_wb_sel & 8) mask |= 0xFF000000;
		
		if (uut->o_wb_adr < MEMTOP)
		{
			main_memory[uut->o_wb_adr >> 2] = uut->o_wb_dat & mask | main_memory[uut->o_wb_adr >> 2] & ~mask;
		}
	   }
	   else
	   {
		if (uut->o_wb_adr < MEMTOP)
		{
			uut->i_wb_dat = main_memory[uut->o_wb_adr >> 2];
		}
		else
		{
		    uut->i_wb_dat = 0;
		}
	   }
	   
	   uut->i_wb_ack = 1;
  
	}
	else if (cpuclk.PosEdge())
	{
	   uut->i_wb_ack = 0;
	}

        main_time++;            // Time passes...
	
	if (uut->o_wb_adr >= sz-4)
	{	
	  //std::cerr << main_time << std::endl;
	  //break;
	}
    }

    uut->final();               // Done simulating
    tfp->close();
    delete uut;
    
}
