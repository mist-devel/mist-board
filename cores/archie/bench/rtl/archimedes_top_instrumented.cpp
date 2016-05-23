#include <verilated.h>          // Defines common routines
#include "Varchimedes_top_instrumented.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <sstream>
#include <fstream>
#include <queue>          // std::queue
#include <string>
#include <cstdlib>
#include <cstdio>
#include <SDL/SDL.h>

Varchimedes_top_instrumented *uut;     // Instantiation of module
unsigned int *main_memory = NULL;
unsigned int *rom_memory = NULL;

struct cpuaccess
{
  signed char we;
  unsigned int address;
  unsigned int dat; 
  unsigned int be; // byte enable;
  unsigned int expected;
  unsigned int time;
};

    signed long long delta = 0;
    vluint64_t num_cycles = 0;

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

static std::string nextline;
unsigned int linecount = 0;

bool LoadNextLine(std::istream& instream)
{
	linecount++;
	return std::getline(instream,nextline);	
}

bool GetNextAccess(struct cpuaccess* access, std::istream& instream)
{
    bool result = false;

    std::string line = nextline;

    if (LoadNextLine(instream))
    {	
	std::cout << uut->v__DOT__clk_count << " | " << line << std::endl;
	int x = sscanf(line.c_str(), "%i, 0x%x, 0x%x, 0x%x, 0x%x, 0x%x", &(access->we), &(access->address), &(access->dat), &(access->be), &(access->expected), &(access->time));
	result = true;
    }
    
    if (access->we == 2)
      {
	access->dat -= delta;
      }
      
	
   

    return result;  
}

int main(int argc, char** argv) {
	
    int i = 0;
    
    
    cpuaccess* access =  new cpuaccess;
    
    std::queue<cpuaccess*> interrupt_queue;
    cpuaccess* interrupt_nxt =  NULL;
	
    
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
    uut = new Varchimedes_top_instrumented;      // Create instance
    
    LoadNextLine(std::cin);
    GetNextAccess(access, std::cin);

    
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    uut->trace(tfp, 99);
    tfp->open("archimedes_top_instrumented.vcd");
    
    uut->RESET_I = 1;           // Set some inputs
    uut->cpu_irq = 0;
    uut->cpu_firq = 0;
    uut->use_instrumented = 1;
    
    
    Uint8 *p = (Uint8 *)screen->pixels;
    
    int mem_wait_states = 0;

    unsigned int lock_timer = 0;
    bool locked = false;
    int ttl = -1;
    
    while (!Verilated::gotFinish()) 
    {
	locked = lock_timer > 0;
	
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
            uut->CLKPIX_I = uut->CLKPIX_I ? 0 : 1;       // Toggle clock
	}
	
        cpuclk.Update(uut->CLKCPU_I);
	pixclk.Update(uut->CLKPIX_I);
        vsync.Update(uut->VSYNC);
        hsync.Update(uut->HSYNC);
	
	uut->eval();            // Evaluate model
	
	if ((uut->v__DOT__clk_count >= 48393910) && (uut->v__DOT__clk_count <= 48394006))
	{
		tfp->dump (main_time);
	}
	

	if (uut->v__DOT__ARM__DOT__u_decode__DOT__u_decompile__DOT__inst_count  == 8576761)
	{
		delta = 0;
	}

	if (uut->MEM_STB_O && cpuclk.PosEdge() && !(bool)uut->MEM_ACK_I) 
	{
           mem_wait_states++;
	   if (mem_wait_states > 1)
	   {
		   
		   //std::cout << "MEM: " << std::hex << (uut->MEM_ADDR_O << 2) << std::endl;
		   
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
		   else
		   {
			if ((uut->iospace) && !uut->v__DOT__cpu_we && uut->v__DOT__MEMC__DOT__cpu_load)
			{
				delta = uut->v__DOT__ARM__DOT__u_decode__DOT__u_decompile__DOT__inst_count;
				delta -= (signed long long)access->time;
			        std::cout << "delta: " << (delta) << std::endl;
				
				if (abs(delta) > 20) 
				{	
					std::cerr << "Delta exceeded limits" << std::endl;
					break;
				}
				
				// read the memory access shit.
				if ((unsigned int)(uut->v__DOT__cpu_address & 0x3fffffc) != (unsigned int)access->address)
				{
					std::cerr << uut->v__DOT__ARM__DOT__u_decode__DOT__u_decompile__DOT__inst_count <<  std::hex << " ERROR: expected address: " << (unsigned int)access->address << " accessed " << (unsigned int)uut->v__DOT__cpu_address << std::dec << " line " << linecount << std::endl;
					ttl=2; // live for 10 more instructions
				}
				else
				{
				  std::cout << uut->v__DOT__ARM__DOT__u_decode__DOT__u_decompile__DOT__inst_count << std::hex << " PASS: expected address: " << (unsigned int)access->address << " result " << access->expected << std::dec << std::endl;
				}
				
				uut->MEM_DAT_I = access->expected;
				
				GetNextAccess(access, std::cin);

				// interrupt handling.
				
				while (access->we > 1)
				{			
					cpuaccess *accesscopy =  new cpuaccess;
					memcpy(accesscopy, access, sizeof(cpuaccess));
					interrupt_queue.push(accesscopy);
																		
					
					
					GetNextAccess(access, std::cin);
				}

			}
			else
			{
				uut->MEM_DAT_I = main_memory[uut->MEM_ADDR_O];
			}
			
		   }
		   
		   if (uut->v__DOT__MEMC__DOT__cpu_load)
		   {
			num_cycles++;
			
			if (ttl == 0)
			{
				break;
			}
			
			if (ttl > 0)
			{
				ttl--;
			}
		   
		   }
		   
		   mem_wait_states = 0;
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
	
	// interrupt handling
	
	if (cpuclk.PosEdge() && (interrupt_nxt == NULL))
	{
		if (!interrupt_queue.empty())
		{
			interrupt_nxt = interrupt_queue.front();
			interrupt_queue.pop();
		}
	}
	
	if (interrupt_nxt != NULL)
	{
		if ((uut->v__DOT__ARM__DOT__u_decode__DOT__u_decompile__DOT__inst_count) >= (interrupt_nxt->dat))
		{
			if (interrupt_nxt->we == 2)
			{
				uut->cpu_irq = interrupt_nxt->expected ? 1 : 0;
				std::cerr <<  uut->v__DOT__ARM__DOT__u_decode__DOT__u_decompile__DOT__inst_count << " irq state: " << (uut->cpu_irq ? 1 : 0) << " (" << interrupt_nxt->dat << ")" <<  std::endl;
			}
			
			if (interrupt_nxt->we == 3)
			{
				uut->cpu_firq = interrupt_nxt->expected ? 1 : 0;
				std::cerr <<  uut->v__DOT__ARM__DOT__u_decode__DOT__u_decompile__DOT__inst_count << " firq state: " << (uut->cpu_firq ? 1 : 0) << " (" << interrupt_nxt->dat << ")" << std::endl;
			}
		
			delete interrupt_nxt;
			interrupt_nxt = NULL;
		}
		else
		{
			
			//std::cerr <<  uut->v__DOT__ARM__DOT__u_decode__DOT__u_decompile__DOT__inst_count << " (f)irq wait state: " << "(" << interrupt_nxt->dat << ")" << std::endl;
		}
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
	
        
	
        main_time++;            // Time passes...
    }

    uut->final();               // Done simulating
    //    // (Though this example doesn't get here)
    tfp->close();
     //Quit SDL
    SDL_Quit();
    
    delete uut;
}
