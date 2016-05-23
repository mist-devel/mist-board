#include <verilated.h>          // Defines common routines
#include "Va23_fetch.h"
#include "verilated_vcd_c.h"

#define TRACE

#include "edge.h"

#include <stdexcept>
#include <iostream>
#include <sstream>
#include <fstream>
#include <string>
#include <cstdlib>
#include <cstdio>

typedef uint32_t ARMword; /* must be 32 bits wide */

Va23_fetch *uut;     // Instantiation of module
unsigned char *main_memory = NULL;

vluint64_t main_time = 0;       // Current simulation time
// This is a 64-bit integer to reduce wrap over issues and
// allow modulus.  You can also use a double, if you wish.
double sc_time_stamp () {       // Called by $time in Verilog
    return main_time;           // converts to double, to match
    // what SystemC does
}

void dosetup(Va23_fetch *uut)
{
	uut->i_system_rdy = 1;
}

int dowrite(Va23_fetch *uut, VerilatedVcdC* tfp, ARMword address, ARMword data)
{
    main_time = 0;

    uut->eval();            // Evaluate model
	tfp->dump (main_time++);
    uut->eval();            // Evaluate model
	tfp->dump (main_time++);

    uut->i_address = address;
	uut->i_address_valid = 1;
    uut->i_write_enable = 1;
	uut->i_data_access = 1;
    uut->i_write_data = data;
    Edge clk;
    int writes = 0;
	int wait = 2;

    while (!Verilated::gotFinish())
    {
        if ((main_time % 2) == 0)
        {
            uut->i_clk = uut->i_clk ? 0 : 1;       // Toggle clock
        }

        clk.Update(uut->i_clk);

        uut->eval();            // Evaluate model

#ifdef TRACE
        tfp->dump (main_time);
#endif

        if (uut->o_wb_stb && uut->o_wb_cyc && clk.PosEdge())
        {
            // wishbone cycle.
            if (uut->o_wb_we != 1)
            {
                throw std::runtime_error("Attempted read during write");
            }
            else
            {
                writes++;
				if (wait == 0)
				{
					uut->i_wb_ack = 1;
					uut->i_address_valid = 0;
					uut->i_write_enable = 0;
				}
				wait--;
			}
        }
        else if (clk.PosEdge())
        {
            uut->i_wb_ack = 0;
        }

        main_time++;            // Time passes...

        if (main_time > 1000)
        {
            std::cerr << "Failed"<< std::endl;
            return -1;
        }

    }

    return writes;
}


ARMword doread(Va23_fetch *uut, VerilatedVcdC* tfp, ARMword address)
{
    main_time = 0;
    uut->i_address = address;
    uut->i_write_enable = 0;
    Edge clk;
    int writes = 0;

    while (!Verilated::gotFinish())
    {
        if ((main_time % 2) == 0)
        {
            uut->i_clk = uut->i_clk ? 0 : 1;       // Toggle clock
        }

        clk.Update(uut->i_clk);

        uut->eval();            // Evaluate model

#ifdef TRACE
		tfp->dump (main_time);
#endif

        if (uut->o_wb_stb && uut->o_wb_cyc && clk.PosEdge())
        {
            // wishbone cycle.
            if (uut->o_wb_we == 1)
            {
                throw std::runtime_error("Attempted read during write");
            }
            else
            {
                writes++;
                uut->i_wb_ack = 1;
            }
        }
        else if (clk.PosEdge())
        {
            uut->i_wb_ack = 0;
            uut->i_wb_dat = 0xDEADBEEF;
        }


        if (uut->o_fetch_stall == 0)
        {
            return uut->o_read_data;
        }
        main_time++;            // Time passes...

        if (main_time > 1000)
        {
            std::cerr << "Failed"<< std::endl;
            return -1;
        }
    }

    return 0;
}


int main(int argc, char** argv) {

    Edge clk;

    Verilated::commandArgs(argc, argv);   // Remember args
    VerilatedVcdC* tfp = NULL;
    uut = new Va23_fetch;      // Create instance

    // initialise random numbers
    std::srand(234234234);

#ifdef TRACE
    Verilated::traceEverOn(true);
    tfp = new VerilatedVcdC;
    uut->trace(tfp, 99);
    std::string exename = argv[0];
    std::string vcdname = exename + ".vcd";
    tfp->open(vcdname.c_str());
    std::cerr << vcdname << std::endl;
#endif
	
	dosetup(uut);
	
    uut->i_cache_enable = 1;
    uut->i_cache_flush = 0;
    uut->i_cacheable_area = 0x0000FFFF;

    if (dowrite(uut, tfp, 0x1234, 0x1234) != 1)
    {
        std::cerr << "Failed " << std::endl;
    }


#ifdef TRACE
    tfp->close();
#endif

    uut->final();               // Done simulating


    delete uut;

}
