/* archimedes_top.cpp

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
#include "Varchimedes_top.h"
#include "edge.h"
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

void printVideoRegister()
{
    //reg [15:0]		vidc_cr; // control register.
    std::cout << std::hex << "vidc_cr = 0x" << uut->v__DOT__VIDC__DOT__vidc_cr << std::dec << ";" << std::endl;

    //reg [12:0] 		vidc_palette[0:15];	// palette register.
    for (int i=0; i<16; i++)
    {
        std::cout << "vidc_palette[" << i << "] = 0x" << std::hex << uut->v__DOT__VIDC__DOT__vidc_palette[i] << std::dec << ";" << std::endl;
    }

    //reg [12:0]		vidc_border; 			// border register.
    std::cout << "vidc_border = 0x" << std::hex << uut->v__DOT__VIDC__DOT__vidc_border << std::dec << ";" << std::endl;

    //reg [12:0]		cur_palette[1:3]; 	// border register.
    for (int i=1; i<4; i++)
    {
        std::cout << "cur_palette[" << i << "] = 0x" << std::hex << uut->v__DOT__VIDC__DOT__vidc_palette[i] << std::dec << ";" << std::endl;
    }

    std::cout << std::hex << "vidc_vcr = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_vcr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_vswr = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_vswr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_vbsr = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_vbsr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_vdsr = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_vdsr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_vder = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_vder << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_vber = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_vber << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hcr = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_hcr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hswr = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_hswr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hbsr = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_hbsr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hdsr = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_hdsr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hder = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_hder << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hber = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_hber << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hcsr = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_hcsr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hcer = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_hcer << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hcsr = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_vcsr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_vcer = 0x" << uut->v__DOT__VIDC__DOT__TIMING__DOT__vidc_vcer << std::dec << ";" << std::endl;

}

int main(int argc, char** argv)
{
    // SDL events
    SDL_Event event;

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

    if (argc > 1)
    {
        fileName = argv[1];
    }

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
            while( SDL_PollEvent( &event ) )
            {
                /* We are only worried about SDL_KEYDOWN and SDL_KEYUP events */
                switch( event.type )
                {
                case SDL_KEYDOWN:
                    if (event.key.keysym.sym == SDLK_v)
                    {
                        printf( "Key press detected\n" );
                        printVideoRegister();
                    }
                    break;
                default:
                    break;
                }
            }

            //std::cerr << xcount << std::endl;
            ycount++;
            xcount = 0;
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
