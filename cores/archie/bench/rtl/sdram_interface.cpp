#include <verilated.h>          // Defines common routines
#include "Vsdram_interface.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <sstream>
#include <fstream>
#include <string>
#include <cstdlib>
#include <cstdio>

Vsdram_interface *uut;     // Instantiation of module

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

int delay = 0;

int main(int argc, char** argv) {

    Edge cpuclk;
    Edge ramclk;
	
    Verilated::commandArgs(argc, argv);   // Remember args
    uut = new Vsdram_interface;      // Create instance
  
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    uut->trace(tfp, 99);
    tfp->open("sdram.vcd");
    
    while (!Verilated::gotFinish()) 
    {
        if ((main_time % 2) == 0) 
	{
            uut->DRAM_CLK = uut->DRAM_CLK ? 0 : 1;       // Toggle clock	    
        }

        if ((main_time % 8) == 0) 
	{
            uut->wb_clk = uut->wb_clk ? 0 : 1;       // Toggle clock	    
        }

        cpuclk.Update(uut->wb_clk);
        ramclk.Update(uut->DRAM_CLK);
	
	uut->eval();            // Evaluate model
	tfp->dump (main_time);

	if (uut->wb_ready) 
	{
	  if (cpuclk.PosEdge())
	    {
	      delay++;
	      if (uut->wb_ack) 
		{
		  delay = 0;
		  std::cout << uut->wb_dat_o << std::endl;
		  uut->wb_stb = 0;
		  uut->wb_cyc = 0;
		  uut->wb_we = 0;
		}
	      else if (delay > 8)
		{
		  uut->wb_stb = 1;
		  uut->wb_cyc = 1;
		  uut->wb_we = 0;
		}


	    }
	}
	
        main_time++;            // Time passes...
    }

    uut->final();               // Done simulating
    tfp->close();
    delete uut;
    
}
