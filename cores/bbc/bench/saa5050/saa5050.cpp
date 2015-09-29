#include <verilated.h>          // Defines common routines
#include "Vsaa5050.h"
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

Vsaa5050 *uut;     // Instantiation of module

vluint64_t main_time = 0;       // Current simulation time
// This is a 64-bit integer to reduce wrap over issues and
// allow modulus.  You can also use a double, if you wish.
double sc_time_stamp () {       // Called by $time in Verilog
    return main_time;           // converts to double, to match
    // what SystemC does
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

    bool vcdTrace = false;
    VerilatedVcdC* tfp = NULL;

    //The images
    SDL_Surface* screen = NULL;
    SDL_Init(SDL_INIT_VIDEO);
    //Set up screen
    screen = SDL_SetVideoMode( 420, 356, 32, SDL_SWSURFACE | SDL_RESIZABLE );

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

    Edge clock32;
    Edge clock24;

    Verilated::commandArgs(argc, argv);   // Remember args
    uut = new Vsaa5050;      // Create instance
    uut->eval();
    uut->eval();

    if (vcdTrace)
    {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        uut->trace(tfp, 99);
        std::string vcdname =  "saa5050.vcd";
        tfp->open(vcdname.c_str());
    }

    uut->nRESET = 0;
    uut->eval();


    Uint8 *p = (Uint8 *)screen->pixels;

    const char data[] = "Hello World. I'm an SAA5050! @moo !£^&%&()";
    int charcount = 0;
    int count = 0;

    while (!Verilated::gotFinish())
    {

        if (main_time > 32)
        {
            uut->nRESET = 1;   // Deassert reset
        }

       if ((main_time % 3) == 0)
        {
            uut->DI_CLOCK = uut->DI_CLOCK ? 0 : 1;       // Toggle clock
        }

        if ((main_time % 4) == 0)
        {
            uut->CLOCK = uut->CLOCK ? 0 : 1;       // Toggle clock
        }


        uut->CLKEN  = ((main_time % 8) < 2) ? 1 : 0;

        uut->GLR = (xcount < 10) ? 0 : 1;
        uut->DEW = (ycount < 10) ? 1 : 0;

        uut->LOSE = isEnabled(xcount, ycount) ? 1 : 0;

        uut->eval();            // Evaluate model

        if (tfp != NULL)
        {
            tfp->dump (main_time);
        }

        clock24.Update(uut->CLOCK);
        clock32.Update(uut->DI_CLOCK);
        
        if (clock24.PosEdge() && uut->CLKEN)
        {
            if (uut->LOSE)
            {
                count++;

                uut->DI_CLKEN = (count == 8) ? 1 : 0;

                if (uut->DI_CLKEN)
                {
                    uut->DI = data[charcount++];
                    count = 0;
                }
            }
            else
            {
                uut->DI_CLKEN;
            }
        }


        if (ycount >= 356)
        {
            SDL_Flip( screen );
            p = (Uint8 *)screen->pixels;
            // print out the number of lines processed.
            std::cerr << ycount << std::endl;
            ycount = 0;
            xcount = 0;
            count = 0;
            charcount = 0;
        }
        else if (xcount >= 420)
        {
            while( SDL_PollEvent( &event ) )
            {
                /* We are only worried about SDL_KEYDOWN and SDL_KEYUP events */
                switch( event.type )
                {
                case SDL_KEYDOWN:
                    if (event.key.keysym.sym == SDLK_v)
                    {
                        // printVideoRegister();
                    }
                    break;
                default:
                    break;
                }
            }

            ycount++;
            xcount = 0;

            charcount = 0;

            p = (Uint8 *)screen->pixels;
            p+= ycount * screen->w *4;
        }
        else if (clock24.PosEdge() && uut->CLKEN) // && (bool)uut->vsync && (bool) uut->hsync)
        {
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
