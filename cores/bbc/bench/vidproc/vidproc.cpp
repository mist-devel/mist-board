#include <verilated.h>          // Defines common routines
#include "Vvidproc.h"
#include "verilated_vcd_c.h"

#include "edge.h"

#include <iostream>
#include <sstream>
#include <fstream>
#include <string>
#include <cstdlib>
#include <cstdio>
#include <stdexcept>

#include <SDL/SDL.h>

Vvidproc *uut;     // Instantiation of module

vluint64_t main_time = 0;       // Current simulation time
// This is a 64-bit integer to reduce wrap over issues and
// allow modulus.  You can also use a double, if you wish.
double sc_time_stamp () {       // Called by $time in Verilog
    return main_time;           // converts to double, to match
    // what SystemC does
}

int loadDataFile(std::string fileName, int* data, int size)
{
    int i = 0;
    std::ifstream input(fileName.c_str());
    std::string line;

    while(std::getline(input, line))
    {
        unsigned int x;
        std::stringstream ss;
        ss << std::hex << line;
        ss >> x;

        if (i < size)
        {
            data[i++] = x;
        }
        else
        {
            throw std::runtime_error("bounds of array exceeded.");
        }
    }

    return i;
}

void setPalette()
{
    uut->v__DOT__palette[0] = 0x7;
    uut->v__DOT__palette[1] = 0x1;
    uut->v__DOT__palette[2] = 0x2;
    uut->v__DOT__palette[3] = 0x3;
    uut->v__DOT__palette[4] = 0x4;
    uut->v__DOT__palette[5] = 0x5;
    uut->v__DOT__palette[6] = 0x6;
    uut->v__DOT__palette[7] = 0x7;
    uut->v__DOT__palette[8] = 0x8;
    uut->v__DOT__palette[9] = 0x9;
    uut->v__DOT__palette[10] = 0xA;
    uut->v__DOT__palette[11] = 0xB;
    uut->v__DOT__palette[12] = 0xC;
    uut->v__DOT__palette[13] = 0xD;
    uut->v__DOT__palette[14] = 0xE;
    uut->v__DOT__palette[15] = 0xF;
}


void printVideoRegister()
{
    //reg [15:0]		vidc_cr; // control register.
    //std::cout << std::hex << "vidc_cr = 0x" << uut->v__DOT__vidc_cr << std::dec << ";" << std::endl;

    //reg [12:0] 		vidc_palette[0:15];	// palette register.
    for (int i=0; i<16; i++)
    {
        std::cout << "palette[" << i << "] = 0x" << std::hex << (int)uut->v__DOT__palette[i] << std::dec << ";" << std::endl;
    }
}

bool isCursor(int x, int y)
{
    return (x > 32) && (x < 64) && (y > 30) && (y < 38); 
}

bool isEnabled(int x, int y)
{
    int xstart = 50;
    int ystart = 50;
    return (x >= xstart) && (x < xstart+320) && (y >= ystart) && (y < ystart+256); 
}

int main(int argc, char** argv) 
{
    // SDL events
    SDL_Event event;
    srand(12345);

    int mem_delay = 4;
    int screen_data[38404*2];
    int screen_idx = 0;

    bool vcdTrace = true;
    VerilatedVcdC* tfp = NULL;

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

    Edge clock;
    Edge clken;

    std::string fileName = "vidproc.dat";

    if (argc > 1)
    {
        fileName = std::string(argv[1]);
    }

    Verilated::commandArgs(argc, argv);   // Remember args
    uut = new Vvidproc;      // Create instance
    uut->eval();
    uut->eval();

    //loadDataFile(fileName, (int *)screen_data, sizeof(screen_data));

    if (vcdTrace)
    {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        uut->trace(tfp, 99);
        std::string vcdname =  "vidproc.vcd";
        tfp->open(vcdname.c_str());
    }

    uut->nRESET = 0;
    uut->eval();

    setPalette();
    
    uut->eval();

    Uint8 *p = (Uint8 *)screen->pixels;

    while (!Verilated::gotFinish())
    {
        if (main_time > 32)
        {
            uut->nRESET = 1;   // Deassert reset
            setPalette();
        }

        if (main_time >= 2)
        {
            uut->CLOCK = uut->CLOCK ? 0 : 1;       // Toggle clock
        }
                
        uut->CLKEN  = ((main_time % 8) < 2) ? 1 : 0;
        uut->DISEN = isEnabled(xcount, ycount) ? 1 : 0;

        uut->eval();            // Evaluate model

        if (tfp != NULL)
        {
            tfp->dump (main_time);
        }

        clock.Update(uut->CLOCK);
        clken.Update(uut->CLKEN);

        if (clock.PosEdge())
        {
            uut->DI_RAM = 0x1;
        }


        if (ycount >= 480)
        {
            SDL_Flip( screen );
            p = (Uint8 *)screen->pixels;
            // print out the number of lines processed.
            std::cerr << ycount << std::endl;
            ycount = 0;
            xcount = 0;
            screen_idx = 0;
        }
        else if (xcount >= 640)
        {
            while( SDL_PollEvent( &event ) )
            {
                /* We are only worried about SDL_KEYDOWN and SDL_KEYUP events */
                switch( event.type )
                {
                case SDL_KEYDOWN:
                    if (event.key.keysym.sym == SDLK_v)
                    {
                        printVideoRegister();
                    }
                    break;
                default:
                    break;
                }
            }

            ycount++;
            xcount = 0;
            p = (Uint8 *)screen->pixels;
            p+= ycount * screen->w *4;
        }
        else if (clken.PosEdge()) // && (bool)uut->vsync && (bool) uut->hsync)
        {
            
            uut->CURSOR = isCursor(xcount, ycount);
            
            if ((ycount < screen->h) && (xcount <= screen->w))
            {
                *p++ = ((unsigned char)uut->R) ? 0xFFFF : 0; //<< 4 | (unsigned char)uut->video_b;
                *p++ = ((unsigned char)uut->G) ? 0xFFFF : 0; //<< 4 | (unsigned char)uut->video_g;
                *p++ = ((unsigned char)uut->B) ? 0xFFFF : 0; //<< 4 | (unsigned char)uut->video_r;
                p++;

                xcount++;
            }
        }

        main_time++;            // Time passes...
    }

    uut->final();               // Done simulating

    if (tfp != NULL)
    {
        tfp->close();
        delete tfp;
    }

    //Quit SDL
    SDL_Quit();

    delete uut;
}
