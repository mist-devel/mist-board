#include <verilated.h>          // Defines common routines
#include "Vbbc.h"
#include "verilated_vcd_c.h"

#include "edge.h"

#include <iostream>
#include <sstream>
#include <fstream>
#include <string>
#include <cstdlib>
#include <cstdio>
#include <stdexcept>
#include <ctype.h>
#include <SDL/SDL.h>

Vbbc *uut;     // Instantiation of module
SDL_Event event;

vluint64_t main_time = 0;       // Current simulation time
// This is a 64-bit integer to reduce wrap over issues and
// allow modulus.  You can also use a double, if you wish.
double sc_time_stamp () {       // Called by $time in Verilog
    return main_time;           // converts to double, to match
    // what SystemC does
}

void SetKeyState(int x, int y, bool state)
{
    unsigned char b = 1<<y;

    if (state)
    {
        uut->v__DOT__KEYB__DOT__keys[x] = uut->v__DOT__KEYB__DOT__keys[x] | b;
    }
    else
    {
        uut->v__DOT__KEYB__DOT__keys[x] = uut->v__DOT__KEYB__DOT__keys[x]  & ~b;
    }

}

void EmuKeyboard(SDLKey key, bool state)
{
    int val = state ? 1 : 0;
    //key = tolower(key);
    std::cout << key << " " << state << std::endl;
    switch (key)
    {
    case SDLK_LEFT:
        SetKeyState(0,0, state);
        break;
    case SDLK_RIGHT:
        SetKeyState(0,0, state);
        break;
    case SDLK_q:
        SetKeyState(0,1, state);
        break;
    case SDLK_F10:
        SetKeyState(0,2, state);
        break;
    case SDLK_1:
        SetKeyState(0,3, state);
        break;
    case SDLK_CAPSLOCK:
        SetKeyState(0,4, state);
        break;
//case SDLK_LEFT: SetKeyState(0,5, state); break;
//case SDLK_RIGHT: SetKeyState(0,6, state); break;
    case SDLK_ESCAPE:
        SetKeyState(0,7, state);
        break;
    case SDLK_3:
        SetKeyState(1,1, state);
        break;
    case SDLK_w:
        SetKeyState(1,2, state);
        break;
    case SDLK_2:
        SetKeyState(1,3, state);
        break;
    case SDLK_a:
        SetKeyState(1,4, state);
        break;
    case SDLK_s:
        SetKeyState(1,5, state);
        break;
    case SDLK_z:
        SetKeyState(1,6, state);
        break;
    case SDLK_F1:
        SetKeyState(1,7, state);
        break;
    case SDLK_4:
        SetKeyState(2,1, state);
        break;
    case SDLK_e:
        SetKeyState(2,2, state);
        break;
    case SDLK_d:
        SetKeyState(2,3, state);
        break;
    case SDLK_x:
        SetKeyState(2,4, state);
        break;
    case SDLK_c:
        SetKeyState(2,5, state);
        break;
    case SDLK_SPACE:
        SetKeyState(2,6, state);
        break;
    case SDLK_F2:
        SetKeyState(2,7, state);
        break;
    case SDLK_5:
        SetKeyState(3,1, state);
        break;
    case SDLK_t:
        SetKeyState(3,2, state);
        break;
    case SDLK_r:
        SetKeyState(3,3, state);
        break;
    case SDLK_f:
        SetKeyState(3,4, state);
        break;
    case SDLK_g:
        SetKeyState(3,5, state);
        break;
    case SDLK_v:
        SetKeyState(3,6, state);
        break;
    case SDLK_F3:
        SetKeyState(3,7, state);
        break;
    case SDLK_F4:
        SetKeyState(4,1, state);
        break;
    case SDLK_7:
        SetKeyState(4,2, state);
        break;
    case SDLK_6:
        SetKeyState(4,3, state);
        break;
    case SDLK_y:
        SetKeyState(4,4, state);
        break;
    case SDLK_h:
        SetKeyState(4,5, state);
        break;
    case SDLK_b:
        SetKeyState(4,6, state);
        break;
    case SDLK_F5:
        SetKeyState(4,7, state);
        break;
    case SDLK_8:
        SetKeyState(5,1, state);
        break;
    case SDLK_i:
        SetKeyState(5,2, state);
        break;
    case SDLK_u:
        SetKeyState(5,3, state);
        break;
    case SDLK_j:
        SetKeyState(5,4, state);
        break;
    case SDLK_n:
        SetKeyState(5,5, state);
        break;
    case SDLK_m:
        SetKeyState(5,6, state);
        break;
    case SDLK_F6:
        SetKeyState(5,7, state);
        break;
    case SDLK_F7:
        SetKeyState(6,1, state);
        break;
    case SDLK_9:
        SetKeyState(6,2, state);
        break;
    case SDLK_o:
        SetKeyState(6,3, state);
        break;
    case SDLK_k:
        SetKeyState(6,4, state);
        break;
    case SDLK_l:
        SetKeyState(6,5, state);
        break;
    case SDLK_F8:
        SetKeyState(6,7, state);
        break;
    case SDLK_0:
        SetKeyState(7,2, state);
        break;
    case SDLK_p:
        SetKeyState(7,3, state);
        break;
    case SDLK_F9:
        SetKeyState(7,7, state);
        break;
    case SDLK_RETURN:
        SetKeyState(9,4, state);
        break;
    case SDLK_BACKSPACE:
        SetKeyState(9,5, state);
        break;
    case SDLK_PRINT:
        uut->v__DOT__keyb_break = state;
    default:
        break;
    }
}

int main(int argc, char** argv)
{
    // SDL events

    srand(12345);
    
    char main_memory[65536];

    bool vcdTrace = false;
    VerilatedVcdC* tfp = NULL;

    //The images
    SDL_Surface* screen = NULL;
    SDL_Init(SDL_INIT_VIDEO);
    //Set up screen
    screen = SDL_SetVideoMode( 800, 600, 32, SDL_SWSURFACE | SDL_RESIZABLE );
    SDL_WM_SetCaption("BBC B Verilog Simulation - RGB Video Out" ,NULL);
    SDL_EnableKeyRepeat(500, 750);
    
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

    Edge clk32m;
    Edge clk24m;

    Edge vsync;
    Edge hsync;
    
    
    std::string fileName = "bbc.rom";

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

    std::cerr << fread((char *)(main_memory + 32768), sizeof(char), sz, fp) << std::endl;
    fclose(fp);

    Verilated::commandArgs(argc, argv);   // Remember args
    uut = new Vbbc;      // Create instance
    uut->eval();

    if (vcdTrace)
    {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        uut->trace(tfp, 99);
        std::string vcdname =  "bbc.vcd";
        tfp->open(vcdname.c_str());
    }

    uut->RESET_I = 1;
    uut->eval();

    Uint8 *p = (Uint8 *)screen->pixels;

    unsigned char mode = 7;

    if (argc > 1)
    {
        mode = (unsigned char) atoi(argv[1]);
    }

    uut->DIP_SWITCH = 0x0;

    while (!Verilated::gotFinish())
    {
        if (main_time > 32)
        {
            uut->RESET_I = 0;   // Deassert reset
        }

        if ((main_time % 3) == 0)
        {
            uut->CLK32M_I = uut->CLK32M_I ? 0 : 1;       // Toggle clock
        }

        if ((main_time % 4) == 0)
        {
            uut->CLK24M_I = uut->CLK24M_I ? 0 : 1;       // Toggle clock
        }

        uut->eval();            // Evaluate model

        if (tfp != NULL)
        {
            tfp->dump (main_time);
        }

        clk32m.Update(uut->CLK32M_I);
        clk24m.Update(uut->CLK24M_I);

        hsync.Update(uut->HSYNC);
        vsync.Update(uut->VSYNC);
        
        if (clk32m.PosEdge())
        {
            uut->MEM_DI = main_memory[uut->MEM_ADR];
            uut->VID_DI = main_memory[uut->VID_ADR];
            
            if (uut->MEM_WE) 
            {
                main_memory[uut->MEM_ADR] = uut->MEM_DO;
            }
        }
        

        if (vsync.PosEdge())
        {
            if (ycount > 2)
            {
                SDL_Flip( screen );
                SDL_FillRect(screen, NULL, 0x000000);
                std::cerr << ycount << std::endl;
            }

            p = (Uint8 *)screen->pixels;
            // print out the number of lines processed.
            ycount = 0;
            xcount = 0;
        }
        else if (hsync.PosEdge())
        {
            while( SDL_PollEvent( &event ) )
            {
                /* We are only worried about SDL_KEYDOWN and SDL_KEYUP events */
                switch( event.type )
                {
                case SDL_KEYDOWN:

                    EmuKeyboard(event.key.keysym.sym, true);
                    if (event.key.keysym.sym == SDLK_v)
                    {
                        //printVideoRegister();
                    }
                    break;
                case SDL_KEYUP:

                    EmuKeyboard(event.key.keysym.sym, false);
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
        else if (clk32m.PosEdge() && (bool) uut->VIDEO_CLKEN && (bool) !uut->HSYNC && (bool) !uut->VSYNC)
        {

            if ((ycount < screen->h) && (xcount <= screen->w))
            {
                if ((unsigned char)uut->VIDEO_R) *p++ = 0xFF;
                else p++;
                if ((unsigned char)uut->VIDEO_G) *p++ = 0xFF;
                else p++;
                if ((unsigned char)uut->VIDEO_B) *p++ = 0xFF;
                else p++;

                //       *p++ = ((unsigned char)uut->VIDEO_R) ? 0xFFFF : 0; //<< 4 | (unsigned char)uut->video_b;
                //     *p++ = ((unsigned char)uut->VIDEO_G) ? 0xFFFF : 0; //<< 4 | (unsigned char)uut->video_g;
                //   *p++ = ((unsigned char)uut->VIDEO_B) ? 0xFFFF : 0; //<< 4 | (unsigned char)uut->video_r;
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
