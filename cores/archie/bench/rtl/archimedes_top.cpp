
#include <verilated.h>          // Defines common routines
#include "Varchimedes_top.h"
#include "../i2cSlaveTop/Vi2cSlaveTop.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <sstream>
#include <fstream>
#include <queue>          // std::queue
#include <string>
#include <cstdlib>
#include <cstdio>
#include <SDL/SDL.h>

Varchimedes_top *uut;     // Instantiation of module
Vi2cSlaveTop *i2c;     
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

    bool PosEdge() 
    {
        return m_PosEdge;
    }
    bool NegEdge()
    {
        return m_NegEdge;
    }

private:
    bool m_NegEdge;
    bool m_PosEdge;
    bool m_LastValue;
};

int main(int argc, char** argv) {

    //The images
    SDL_Surface* screen = NULL;
    SDL_Init(SDL_INIT_VIDEO);
    //Set up screen
    screen = SDL_SetVideoMode( 800, 524, 32, SDL_SWSURFACE | SDL_RESIZABLE );

    //Update Screen
    SDL_Flip( screen );

    // Check that the window was successfully made
    if (screen == NULL) 
    {
        // In the event that the window could not be made...
        printf("Could not create window: %s\n", SDL_GetError());
        return 1;
    }

    // simulate a monitor
    int xcount = 0;
    int ycount = 0;
    int frame = 0;

    Edge vsync;
    Edge hsync;
    Edge cpuclk;
    Edge pixclk;

    main_memory = (unsigned int *) malloc(8*1024*1024); // 8MB of ram area.
    rom_memory =  main_memory + 1024*1024;
    
    std::string fileName = "ROM310";
    
    FILE *fp = fopen(fileName.c_str(), "r");
    if (fp == NULL)
    {
      std::cerr << "failed to open file:" << fileName << std::endl;
        exit(-1);
    }
    
    fseek(fp, 0L, SEEK_END);
    size_t sz = ftell(fp);
    fseek(fp, 0L, SEEK_SET);

    std::cerr << fread(rom_memory, sizeof(char), sz, fp) << std::endl;
    fclose(fp);

    Verilated::commandArgs(argc, argv);   // Remember args
    uut = new Varchimedes_top;      // Create instance
    i2c = new Vi2cSlaveTop;      // Create I2C instance

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    uut->trace(tfp, 99);
    tfp->open("archimedes_top.vcd");

    uut->RESET_I = 1;

    Uint8 *p = (Uint8 *)screen->pixels;

    bool burst = false;
    uint32_t burst_address = 0;

    while (!Verilated::gotFinish())
    {
        if (main_time > 32)
        {
            uut->RESET_I = 0;   // Deassert reset
        }

        if ((main_time % 2) == 0)
        {
            uut->CLKCPU_I = uut->CLKCPU_I ? 0 : 1;       // Toggle clock
        }

        if ((main_time % 3) == 0)
        {
            uut->CLKPIX2X_I = uut->CLKPIX2X_I ? 0 : 1;       // Toggle clock
        }

        cpuclk.Update(uut->CLKCPU_I);
        pixclk.Update(uut->CLKPIX_O);
        vsync.Update(uut->VSYNC);
        hsync.Update(uut->HSYNC);

	i2c->clk = uut->CLKCPU_I;
	i2c->rst = uut->RESET_I;
	i2c->sdaIn = uut->I2C_DOUT;
	uut->I2C_DIN = i2c->sdaOut;
	i2c->scl = uut->I2C_CLOCK;

        uut->eval();            // Evaluate model
	i2c->eval();

        // this code dumps a time section 
	// needs a clock counter in archimedes_top.v (missing)
        /*if ((uut->v__DOT__clk_count > 8137000) && (uut->v__DOT__clk_count < 8138000))
        {
            tfp->dump (main_time);
	    }*/

        if (uut->MEM_STB_O && cpuclk.PosEdge() && !(bool)uut->MEM_ACK_I)
        {
            if (uut->MEM_WE_O)
            {
                unsigned int mask = 0;
                if (uut->MEM_SEL_O & 1) mask |= 0xFF;
                if (uut->MEM_SEL_O & 2) mask |= 0xFF00;
                if (uut->MEM_SEL_O & 4) mask |= 0xFF0000;
                if (uut->MEM_SEL_O & 8) mask |= 0xFF000000;

                if ((uut->MEM_ADDR_O  << 2) >= 4*1024*1024)
                {
                    std::cerr << "Managed to write to ROM" << std::endl;
                    break;
                }

                main_memory[uut->MEM_ADDR_O] = uut->MEM_DAT_O & mask | main_memory[uut->MEM_ADDR_O] & ~mask;
            }
            else if (uut->MEM_CTI_O == 2)
            {
                uut->MEM_DAT_I = main_memory[uut->MEM_ADDR_O];
		burst = true;
		burst_address = uut->MEM_ADDR_O;
            }
	    else 
	    {
	        uut->MEM_DAT_I = main_memory[uut->MEM_ADDR_O];
	    }

            uut->MEM_ACK_I = 1;
        }

    else if (cpuclk.PosEdge())
    {
      if (uut->MEM_CYC_O && (uut->MEM_CTI_O == 2))
      {
	uut->MEM_DAT_I = main_memory[++burst_address];
	burst = false;
      }
      else 
      {
	          uut->MEM_ACK_I = 0;
      }
    }

    if (vsync.PosEdge())
    {
        SDL_Flip( screen );
        p = (Uint8 *)screen->pixels;

        std::cerr << "frame: " << frame << " " << ycount << std::endl;
        ycount = 0;
        xcount = 0;
	frame++;
    }
    else if (hsync.PosEdge())
    {
        //std::cerr << xcount << std::endl;
        ycount++;
        xcount = 0;
        // std::cerr << (uut->VSYNC ? true : false) << " sync: xcount " << xcount << " ycount " << ycount << std::endl;
        //SDL_Flip( screen );
        p = (Uint8 *)screen->pixels;
        p+= ycount * screen->w *4;
    }

    else if (pixclk.PosEdge() && (bool)uut->VSYNC && (bool) uut->HSYNC)
    {
        if ((ycount < screen->h) && (xcount <= screen->w))
        {


            *p++ = ((unsigned char)uut->VIDEO_B) << 4 | (unsigned char)uut->VIDEO_B;
            *p++ = ((unsigned char)uut->VIDEO_G) << 4 | (unsigned char)uut->VIDEO_G;
            *p++ = ((unsigned char)uut->VIDEO_R) << 4 | (unsigned char)uut->VIDEO_R;
            p++;
            //((((unsigned char)uut->VIDEO_G) & 0xc) << 1) | ((((unsigned char)uut->VIDEO_B) & 0xe) >> 1);
            xcount++;
        }
    }



    main_time++;            // Time passes...
}
    
    tfp->close();
    uut->final(); // Done simulating
    //    // (Though this example doesn't get here)
    
    //Quit SDL
    SDL_Quit();

    delete uut;
}
