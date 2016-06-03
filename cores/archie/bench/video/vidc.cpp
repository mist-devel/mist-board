#include <verilated.h>          // Defines common routines
#include "Vvidc.h"
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

Vvidc *uut;     // Instantiation of module

vluint64_t main_time = 0;       // Current simulation time
// This is a 64-bit integer to reduce wrap over issues and
// allow modulus.  You can also use a double, if you wish.
double sc_time_stamp () {       // Called by $time in Verilog
    return main_time;           // converts to double, to match
    // what SystemC does
}

void setMode27()
{
    uut->v__DOT__vidc_cr = 0x18bb;
    uut->v__DOT__vidc_palette[0] = 0xfff;
    uut->v__DOT__vidc_palette[1] = 0xddd;
    uut->v__DOT__vidc_palette[2] = 0xbbb;
    uut->v__DOT__vidc_palette[3] = 0x999;
    uut->v__DOT__vidc_palette[4] = 0x777;
    uut->v__DOT__vidc_palette[5] = 0x555;
    uut->v__DOT__vidc_palette[6] = 0x333;
    uut->v__DOT__vidc_palette[7] = 0x0;
    uut->v__DOT__vidc_palette[8] = 0x940;
    uut->v__DOT__vidc_palette[9] = 0xee;
    uut->v__DOT__vidc_palette[10] = 0xc0;
    uut->v__DOT__vidc_palette[11] = 0xd;
    uut->v__DOT__vidc_palette[12] = 0xbee;
    uut->v__DOT__vidc_palette[13] = 0x85;
    uut->v__DOT__vidc_palette[14] = 0xbf;
    uut->v__DOT__vidc_palette[15] = 0xfb0;
    uut->v__DOT__vidc_border = 0x777;
    uut->v__DOT__cur_palette[0] = 0xff0;
    uut->v__DOT__cur_palette[1] = 0x900;
    uut->v__DOT__cur_palette[2] = 0xf;
    uut->v__DOT__TIMING__DOT__vidc_vcr = 0x20c;
    uut->v__DOT__TIMING__DOT__vidc_vswr = 0x1;
    uut->v__DOT__TIMING__DOT__vidc_vbsr = 0x21;
    uut->v__DOT__TIMING__DOT__vidc_vdsr = 0x21;
    uut->v__DOT__TIMING__DOT__vidc_vder = 0x201;
    uut->v__DOT__TIMING__DOT__vidc_vber = 0x201;
    uut->v__DOT__TIMING__DOT__vidc_hcr = 0x31e;
    uut->v__DOT__TIMING__DOT__vidc_hswr = 0x5e;
    uut->v__DOT__TIMING__DOT__vidc_hbsr = 0x8e;
    uut->v__DOT__TIMING__DOT__vidc_hdsr = 0x88;
    uut->v__DOT__TIMING__DOT__vidc_hder = 0x308;
    uut->v__DOT__TIMING__DOT__vidc_hber = 0x30e;
    uut->v__DOT__TIMING__DOT__vidc_hcsr = 0x88;
    uut->v__DOT__TIMING__DOT__vidc_hcer = 0x0;
    uut->v__DOT__TIMING__DOT__vidc_vcsr = 0x21;
    uut->v__DOT__TIMING__DOT__vidc_vcer = 0x37;
}

void setMode28()
{
uut->v__DOT__vidc_cr = 0x18bf;
uut->v__DOT__vidc_palette[0] = 0x0;
uut->v__DOT__vidc_palette[1] = 0x111;
uut->v__DOT__vidc_palette[2] = 0x222;
uut->v__DOT__vidc_palette[3] = 0x333;
uut->v__DOT__vidc_palette[4] = 0x4;
uut->v__DOT__vidc_palette[5] = 0x115;
uut->v__DOT__vidc_palette[6] = 0x226;
uut->v__DOT__vidc_palette[7] = 0x337;
uut->v__DOT__vidc_palette[8] = 0x400;
uut->v__DOT__vidc_palette[9] = 0x511;
uut->v__DOT__vidc_palette[10] = 0x622;
uut->v__DOT__vidc_palette[11] = 0x733;
uut->v__DOT__vidc_palette[12] = 0x404;
uut->v__DOT__vidc_palette[13] = 0x515;
uut->v__DOT__vidc_palette[14] = 0x626;
uut->v__DOT__vidc_palette[15] = 0x737;
uut->v__DOT__vidc_border = 0x777;
    uut->v__DOT__cur_palette[0] = 0xff0;
    uut->v__DOT__cur_palette[1] = 0x900;
    uut->v__DOT__cur_palette[2] = 0xf;
uut->v__DOT__TIMING__DOT__vidc_vcr = 0x20c;
uut->v__DOT__TIMING__DOT__vidc_vswr = 0x1;
uut->v__DOT__TIMING__DOT__vidc_vbsr = 0x21;
uut->v__DOT__TIMING__DOT__vidc_vdsr = 0x21;
uut->v__DOT__TIMING__DOT__vidc_vder = 0x201;
uut->v__DOT__TIMING__DOT__vidc_vber = 0x201;
uut->v__DOT__TIMING__DOT__vidc_hcr = 0x31e;
uut->v__DOT__TIMING__DOT__vidc_hswr = 0x5e;
uut->v__DOT__TIMING__DOT__vidc_hbsr = 0x8e;
uut->v__DOT__TIMING__DOT__vidc_hdsr = 0x8a;
uut->v__DOT__TIMING__DOT__vidc_hder = 0x30a;
uut->v__DOT__TIMING__DOT__vidc_hber = 0x30e;
uut->v__DOT__TIMING__DOT__vidc_hcsr = 0x1b4;
uut->v__DOT__TIMING__DOT__vidc_hcsr = 0x110;
uut->v__DOT__TIMING__DOT__vidc_vcer = 0x126;
uut->v__DOT__TIMING__DOT__vidc_vcsr = 0x110;

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


void printVideoRegister()
{
    //reg [15:0]		vidc_cr; // control register.
    std::cout << std::hex << "vidc_cr = 0x" << uut->v__DOT__vidc_cr << std::dec << ";" << std::endl;

    //reg [12:0] 		vidc_palette[0:15];	// palette register.
    for (int i=0; i<16; i++)
    {
        std::cout << "vidc_palette[" << i << "] = 0x" << std::hex << uut->v__DOT__vidc_palette[i] << std::dec << ";" << std::endl;
    }

    //reg [12:0]		vidc_border; 			// border register.
    std::cout << "vidc_border = 0x" << std::hex << uut->v__DOT__vidc_border << std::dec << ";" << std::endl;

    //reg [12:0]		cur_palette[1:3]; 	// border register.
    for (int i=1; i<4; i++)
    {
        std::cout << "cur_palette[" << i << "] = 0x" << std::hex << uut->v__DOT__vidc_palette[i] << std::dec << ";" << std::endl;
    }

    std::cout << std::hex << "vidc_vcr = 0x" << uut->v__DOT__TIMING__DOT__vidc_vcr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_vswr = 0x" << uut->v__DOT__TIMING__DOT__vidc_vswr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_vbsr = 0x" << uut->v__DOT__TIMING__DOT__vidc_vbsr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_vdsr = 0x" << uut->v__DOT__TIMING__DOT__vidc_vdsr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_vder = 0x" << uut->v__DOT__TIMING__DOT__vidc_vder << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_vber = 0x" << uut->v__DOT__TIMING__DOT__vidc_vber << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hcr = 0x" << uut->v__DOT__TIMING__DOT__vidc_hcr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hswr = 0x" << uut->v__DOT__TIMING__DOT__vidc_hswr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hbsr = 0x" << uut->v__DOT__TIMING__DOT__vidc_hbsr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hdsr = 0x" << uut->v__DOT__TIMING__DOT__vidc_hdsr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hder = 0x" << uut->v__DOT__TIMING__DOT__vidc_hder << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hber = 0x" << uut->v__DOT__TIMING__DOT__vidc_hber << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hcsr = 0x" << uut->v__DOT__TIMING__DOT__vidc_hcsr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hcer = 0x" << uut->v__DOT__TIMING__DOT__vidc_hcer << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_hcsr = 0x" << uut->v__DOT__TIMING__DOT__vidc_vcsr << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_vcer = 0x" << uut->v__DOT__TIMING__DOT__vidc_vcer << std::dec << ";" << std::endl;
    std::cout << std::hex << "vidc_vcer = 0x" << uut->v__DOT__TIMING__DOT__vidc_vcsr << std::dec << ";" << std::endl;

}

int main(int argc, char** argv) 
{
    // SDL events
    SDL_Event event;

    int mem_delay = 4;
    int cursor_data[44];
    int cursor_idx = 0;
    int screen_data[38404*2];
    int screen_idx = 0;

    bool dma_request_r = false;
    bool cursor_burst = false;
    int vidc_burst_remaining = 0;

    bool vcdTrace = false;
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

    Edge vsync;
    Edge hsync;
    Edge pixclk;
    Edge cpuclk;

    std::string fileName = "video.dat";

    if (argc > 1)
    {
        fileName = std::string(argv[1]);
    }

    Verilated::commandArgs(argc, argv);   // Remember args
    uut = new Vvidc;      // Create instance
    uut->eval();
    uut->eval();

    setMode28();

    loadDataFile("cursor.dat", (int *)cursor_data, sizeof(cursor_data));
    loadDataFile(fileName, (int *)screen_data, sizeof(screen_data));

    if (vcdTrace)
    {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        uut->trace(tfp, 99);
        std::string vcdname = fileName + ".vcd";
        tfp->open(vcdname.c_str());
    }

    uut->rst_i = 1;

    uut->eval();

    Uint8 *p = (Uint8 *)screen->pixels;

    while (!Verilated::gotFinish())
    {
        if (main_time > 32)
        {
            uut->rst_i = 0;   // Deassert reset
        }

        uut->clkpix2x = uut->clkpix2x ? 0 : 1;       // Toggle clock

        if (main_time >= 2)
        {
            uut->clkcpu = uut->clkcpu ? 0 : 1;       // Toggle clock
        }

        cpuclk.Update(uut->clkcpu);
        pixclk.Update(uut->clkpix);
        vsync.Update(uut->vsync);
        hsync.Update(uut->hsync);

        uut->eval();            // Evaluate model

        if (tfp != NULL)
        {
	  //    tfp->dump (main_time);
        }

        if (cpuclk.PosEdge())
        {
            if (dma_request_r && (vidc_burst_remaining == 0))
            {
                vidc_burst_remaining = 4;
                cursor_burst = (uut->hsync == 0);
                mem_delay = 4;
            }

            dma_request_r = uut->vidrq && ~uut->flybk;

            if (uut->vidak == 0)
            {
                if ((vidc_burst_remaining > 0) && (mem_delay == 0))
                {

                    uut->vidak = 1;
                    mem_delay = 4;
                    
                    if (cursor_burst)
                    {
                        uut->viddat = cursor_data[cursor_idx++];
                        cursor_idx = cursor_idx >= sizeof(cursor_data) ? 0 : cursor_idx;
                    }
                    else
                    {
		      uut->viddat = screen_data[screen_idx++];
		      screen_idx = screen_idx >= sizeof(screen_data) ? 0 : screen_idx;
                    }

                    vidc_burst_remaining--;
                }
                else
                {
                    mem_delay--;
                }
            }
            else
            {
                uut->vidak = 0;
            }
        }


        if (vsync.NegEdge())
        {
            SDL_Flip( screen );
            p = (Uint8 *)screen->pixels;
            // print out the number of lines processed.
            std::cerr << ycount << std::endl;
            ycount = 0;
            xcount = 0;
            vidc_burst_remaining == 0;
            cursor_idx = 0;
	    screen_idx = 0;
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

            ycount++;
            xcount = 0;
            p = (Uint8 *)screen->pixels;
            p+= ycount * screen->w *4;
        }
        else if (hsync.NegEdge())
        {
            vidc_burst_remaining == 0;
        }
        else if (pixclk.PosEdge() && (bool)uut->vsync && (bool) uut->hsync)
        {
            if ((ycount < screen->h) && (xcount <= screen->w))
            {
	      *p++ = ((unsigned char)uut->video_b) << 4 | (unsigned char)uut->video_b;
	      *p++ = ((unsigned char)uut->video_g) << 4 | (unsigned char)uut->video_g;
	      *p++ = ((unsigned char)uut->video_r) << 4 | (unsigned char)uut->video_r;
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
