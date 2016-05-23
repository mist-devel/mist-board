#include <verilated.h>          // Defines common routines
#include "Varchimedes_top_nocpu.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <sstream>
#include <fstream>
#include <string>
#include <cstdlib>
#include <cstdio>
#include <SDL/SDL.h>

Varchimedes_top_nocpu *uut;     // Instantiation of module
unsigned int *main_memory = NULL;
unsigned int *rom_memory = NULL;

struct cpuaccess
{
  signed char we;
  unsigned int address;
  unsigned int dat; 
  unsigned int be; // byte enable;
  unsigned int expected;
};

vluint64_t main_time = 0;       // Current simulation time
// This is a 64-bit integer to reduce wrap over issues and
// allow modulus.  You can also use a double, if you wish.
double sc_time_stamp () {       // Called by $time in Verilog
    return main_time;           // converts to double, to match
    // what SystemC does
}

void MEMAccess(struct cpuaccess* access)
{
	uut->cpu_address = access->address;
	uut->cpu_we = (unsigned char) access->we;
	uut->cpu_dat_o = access->dat;
	uut->cpu_stb = 1;
	uut->cpu_cyc = 1;
	uut->cpu_sel = access->be;
}

bool GetNextAccess(struct cpuaccess* access, std::istream& instream)
{
    bool result = false;

    std::string line;    
    
    if (std::getline(instream,line))
    {
	std::string	cell;
	std::stringstream          lineStream(line);
	
	int x = sscanf(line.c_str(), "%i, 0x%x, 0x%x, 0x%x, %i", &(access->we), &(access->address), &(access->dat), &(access->be), &(access->expected));
	
	/*
	std::getline(lineStream, cell, ',');
	access->we = atoi(cell.c_str());
	std::getline(lineStream, cell, ',');
	std::stringstream ss;
	ss << std::hex << cell;
	ss >> access->address;
	std::getline(lineStream, cell, ',');
	ss.str("");
	ss.clear();
	ss << std::hex << cell;
	ss >> access->dat;
	std::getline(lineStream, cell, ',');
	ss.str("");
	ss.clear();
	ss << std::hex << cell;
	ss >> access->be;
	std::getline(lineStream, cell, ',');
	ss.str("");
	ss.clear();
	ss << std::hex << cell;
	ss >> access->expected;*/
	result = true;
    }

    return result;  
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

int main(int argc, char** argv) {
	
    int i = 0;

    cpuaccess* access =  new cpuaccess;
    
     //The images
    SDL_Surface* screen = NULL;
    SDL_Init(SDL_INIT_VIDEO);
    //Set up screen
    screen = SDL_SetVideoMode( 800, 524, 32, SDL_SWSURFACE | SDL_RESIZABLE );
   
    //Update Screen
    SDL_Flip( screen );

     // Check that the window was successfully made
    if (screen == NULL) {
        // In the event that the window could not be made...
        printf("Could not create window: %s\n", SDL_GetError());
        return 1;
    }
    
    // simulate a monitor
    int screenwidth = 0;
    int screenheight = 0;
    
    int xcount = 0;
    int ycount = 0;
    
    Edge vsync;
    Edge hsync;
    Edge cpuclk;
    Edge pixclk;

    main_memory = (unsigned int *) malloc(8*1024*1024); // 8MB of ram area. 
    rom_memory =  main_memory + 1024*1024;
    
    std::string fileName = "../ROM310";
    if (argc > 1)
      {
	fileName = argv[1];
      }

    FILE *fp = fopen(fileName.c_str(), "r");
    if (fp == NULL)
    {
	std::cerr << "failed to open file" << std::endl;
	exit(-1);
    }
    
    std::cerr << fread(rom_memory, sizeof(char), 2*1024*1024, fp) << std::endl;
    fclose(fp);
 
    Verilated::commandArgs(argc, argv);   // Remember args
    uut = new Varchimedes_top_nocpu;      // Create instance
    
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    uut->trace(tfp, 99);
    tfp->open("nocpu.vcd");
    
    uut->RESET_I = 1;           // Set some inputs
    uut->cpu_spvmd = 1;
    Uint8 *p = (Uint8 *)screen->pixels;
    
    int mem_wait_states = 0;
    
    while (!Verilated::gotFinish()) 
    {
        if (main_time > 320) 
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
	pixclk.Update(uut->CLKPIX2X_I);
        vsync.Update(uut->VSYNC);
        hsync.Update(uut->HSYNC);
	
	uut->eval();            // Evaluate model
	
	if (uut->MEM_STB_O && cpuclk.PosEdge() && !(bool)uut->MEM_ACK_I) 
	{
           mem_wait_states++;
	   if (mem_wait_states > 0)
	   {
		   mem_wait_states = 0;
		   //std::cout << "MEM: " << std::hex << (uut->MEM_ADDR_O << 2) << std::endl;
		   
		   if (uut->MEM_WE_O)
		   {
			unsigned int mask = 0;
			if (uut->cpu_sel & 1) mask |= 0xFF;
			if (uut->cpu_sel & 2) mask |= 0xFF00;
			if (uut->cpu_sel & 4) mask |= 0xFF0000;
			if (uut->cpu_sel & 8) mask |= 0xFF000000;
	
			if ((uut->MEM_ADDR_O << 2) > 4*1024*1024)
			{
				std::cerr << "Managed to write to ROM" << std::endl;
				exit(-2);
			}

			main_memory[uut->MEM_ADDR_O] = uut->MEM_DAT_O & mask | main_memory[uut->MEM_ADDR_O] & ~mask;
		   }
		   else
		   {
			uut->MEM_DAT_I = main_memory[uut->MEM_ADDR_O];
		   }
	   
		   uut->MEM_ACK_I = 1;
	   }
	   else
	   {
		uut->MEM_ACK_I = 0;
	   }

	}
	else if (cpuclk.PosEdge())
	{
	   uut->MEM_ACK_I = 0;
	}
	
	if (cpuclk.PosEdge() && (uut->cpu_stb == 0) && (uut->RESET_I == 0)) 
	{
		if (GetNextAccess(access, std::cin))
		{
			MEMAccess(access);
		}
		else
		{
			std::cout << "finished instrumenting" << std::endl;
			break;
		}
	}
	else if (cpuclk.PosEdge() && (uut->cpu_ack))
	{
	  
	  
		if (uut->cpu_we)
		{
		  //std::cout << std::dec << main_time << ": " << i << ": write " << std::hex << uut->cpu_address << " data " << std::hex << uut->cpu_dat_o << " be " << (unsigned int) uut->cpu_sel << std::dec << std::endl;
		}
		else
		{
			//std::cout << std::dec << main_time << ": " << i << ": read " << std::hex << uut->cpu_address << " data " << std::hex << uut->cpu_dat_i << " expected " << std::hex << access->expected << std::dec << std::endl;
	
			if (access->expected != uut->cpu_dat_i)
			{
				std::cout << "Incorrect result on read" << std:: endl;
				break;
			}
		}
		
		uut->cpu_stb = 0;
		uut->cpu_cyc = 0;
		i++;
	}
	else if (cpuclk.PosEdge() && (uut->cpu_err)) 
	{
		std::cout << "Unexpected data abort address:" << std::hex << uut->cpu_address << std::endl;
		break;
	}

	
	if (vsync.PosEdge()) 
	{
	   SDL_Flip( screen );
	   p = (Uint8 *)screen->pixels; 
	   
	   std::cerr << ycount << std::endl;
	   ycount = 0;
	   xcount = 0;
	   
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
	
        
	//tfp->dump (main_time);	
        main_time++;            // Time passes...
    }

    uut->final();               // Done simulating
    //    // (Though this example doesn't get here)

     //Quit SDL
    SDL_Quit();
    
    delete uut;
}
