/* program.cpp

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
#include "verilated_vcd_c.h"
#include "Va23_core.h"

// these all need to not be name mangled by C++
extern "C"
{
#include "arm/armdefs.h"
#include "arm/armemu.h"
#include "arm/armcopro.h"
}

#include "edge.h"
#include "fuzz.h"
#include "libdisarm/disarm.h"

#include <cstdio>
#include <sstream>

vluint64_t main_time = 0;       // Current simulation time

double sc_time_stamp () {       // Called by $time in Verilog
    return main_time;           // converts to double, to match
    // what SystemC does
}

#define MEMTOP 8*1024*1024
#define EXECBASE 4*1024
#define REGCOUNT 27

void print_registers(ARMword *reg)
{
    for (int i=0; i<27; i++)
    {
        fprintf(stderr, "%s=0x%08x,", reg_names[i], reg[i]);
    }

    fprintf(stderr,"\n");
}

void copy_registers(ARMword *src, ARMword *dst)
{
    for (int i=0; i<27; i++)
    {
        dst[i] = src[i];
    }
}

bool compare_regs(ARMword *reg1, ARMword *reg2, std::string &msg)
{
    bool result = true;
    std::stringstream ss;

    ss << std::hex;

    ss << " expected,actual,bitwise difference ";

    for (int i=0; i<27; i++)
    {
        if (reg1[i] != reg2[i])
        {
            ss << " " << reg_names[i] << "(0x";
            ss << std::setfill('0') << std::setw(8) << reg1[i];
            ss << ",0x";
            ss << std::setfill('0') << std::setw(8) << reg2[i];
            ss << ",0x";
            ss << std::setfill('0') << std::setw(8) << (reg1[i] ^ reg2[i]) << ")";
            result = false;
        }
    }

    if (!result)
    {
        msg = ss.str();
    }

    return result;
}

void amber_set_registers(Va23_core *cpu, ARMword *reg)
{
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r0 = reg[0];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r1 = reg[1];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r2 = reg[2];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r3 = reg[3];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r4 = reg[4];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r5 = reg[5];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r6 = reg[6];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r7 = reg[7];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r8 = reg[8];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r9 = reg[9];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r10 = reg[10];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r11 = reg[11];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r12 = reg[12];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r13 = reg[13];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r14 = reg[14];

    cpu->v__DOT__u_execute__DOT__status_bits_mode = (reg[15] & 0x3);
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r15 = (reg[15] >> 2) & 0xFFFFFF;
    cpu->v__DOT__u_execute__DOT__status_bits_flags = (reg[15] >> 28) & 0xf;
    cpu->v__DOT__u_execute__DOT__status_bits_irq_mask = (reg[15] >> 27) & 0x1;
    cpu->v__DOT__u_execute__DOT__status_bits_firq_mask = (reg[15] >> 26) & 0x1;

    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r8_firq = reg[16];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r9_firq = reg[17];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r10_firq = reg[18];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r11_firq = reg[19];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r12_firq = reg[20];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r13_firq = reg[21];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r14_firq = reg[22];

    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r13_irq = reg[23];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r14_irq = reg[24];

    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r13_svc = reg[25];
    cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r14_svc = reg[26];
}

void amber_get_registers(Va23_core *cpu, ARMword *reg)
{
    reg[0]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r0;
    reg[1]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r1;
    reg[2]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r2;
    reg[3]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r3;
    reg[4]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r4;
    reg[5]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r5;
    reg[6]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r6;
    reg[7]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r7;
    reg[8]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r8;
    reg[9]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r9;
    reg[10]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r10;
    reg[11]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r11;
    reg[12]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r12;
    reg[13]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r13;
    reg[14]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r14;
    reg[15]=(cpu->v__DOT__u_execute__DOT__status_bits_flags << 28) |
            (cpu->v__DOT__u_execute__DOT__status_bits_irq_mask << 27) |
            (cpu->v__DOT__u_execute__DOT__status_bits_firq_mask << 26) |
            (cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r15 << 2)  |
            (cpu->v__DOT__u_execute__DOT__status_bits_mode);

    reg[16]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r8_firq;
    reg[17]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r9_firq;
    reg[18]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r10_firq;
    reg[19]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r11_firq;
    reg[20]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r12_firq;
    reg[21]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r13_firq;
    reg[22]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r14_firq;

    reg[23]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r13_irq;
    reg[24]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r14_irq;

    reg[25]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r13_svc;
    reg[26]=cpu->v__DOT__u_execute__DOT__u_register_bank__DOT__r14_svc;
}

void arcem_set_registers(ARMul_State *state, ARMword *reg)
{
    int j;

    for (int i=0; i<15; i++)
    {
        state->RegBank[USERBANK][i] = reg[i];
        state->Reg[i] = reg[i];
    }

    j = 8;

    for (int i=16; i<23; i++)
    {
        if (state->Bank == FIQBANK)
        {
            state->Reg[j] = reg[i];
        }

        state->RegBank[FIQBANK][j++] = reg[i];

    }

    j = 13;

    for (int i=23; i<25; i++)
    {
        if (state->Bank == IRQBANK)
        {
            state->Reg[j] = reg[i];
        }

        state->RegBank[IRQBANK][j++] = reg[i];
    }

    j = 13;

    for (int i=25; i<27; i++)
    {
        if (state->Bank == SVCBANK)
        {
            state->Reg[j] = reg[i];
        }

        state->RegBank[SVCBANK][j++] = reg[i];
    }

    state->Bank = reg[15] & 3;
    state->Reg[15] = reg[15];
    int i;
    switch (state->Bank) { /* restore the new registers */
    case USERBANK  :
    case IRQBANK   :
    case SVCBANK   :
        for (i = 8; i < 13; i++)
            state->Reg[i] = state->RegBank[USERBANK][i];
        state->Reg[13] = state->RegBank[state->Bank][13];
        state->Reg[14] = state->RegBank[state->Bank][14];
        break;
    case FIQBANK  :
        for (i = 8; i < 15; i++)
            state->Reg[i] = state->RegBank[FIQBANK][i];
        break;
    } /* switch */


}

void arcem_get_registers(ARMul_State *state, ARMword *reg)
{
    int j;

    switch (state->Bank) { /* save away the old registers */
    case USERBANK  :
    case IRQBANK   :
    case SVCBANK   :
        for (int i = 8; i < 13; i++)
            state->RegBank[USERBANK][i] = state->Reg[i];
        state->RegBank[state->Bank][13] = state->Reg[13];
        state->RegBank[state->Bank][14] = state->Reg[14];
        break;
    case FIQBANK   :
        for (int i = 8; i < 15; i++)
            state->RegBank[FIQBANK][i] = state->Reg[i];
        break;

    }

    for (int i=0; i<8; i++)
    {
        reg[i] = state->Reg[i];
    }

    for (int i=8; i<15; i++)
    {
        reg[i] = state->RegBank[USERBANK][i];
    }

    j = 8;

    for (int i=16; i<23; i++)
    {
        reg[i] = state->RegBank[FIQBANK][j++];
    }

    j = 13;

    for (int i=23; i<25; i++)
    {
        reg[i] = state->RegBank[IRQBANK][j++];
    }

    j = 13;

    for (int i=25; i<27; i++)
    {
        reg[i] = state->RegBank[SVCBANK][j++];
    }

    reg[15] = state->Reg[15];
}

void reset_memory(std::string fileName, ARMword *memory)
{

    FILE *fp = fopen(fileName.c_str(), "r");
    if (fp == NULL)
    {
        std::cerr << "failed to open file: " << fileName << std::endl;
        exit(-1);
    }

    fseek(fp, 0L, SEEK_END);
    size_t sz = ftell(fp);
    fseek(fp, 0L, SEEK_SET);

    std::memset(memory, 0, MEMTOP);
    std::cerr << fread((memory+(EXECBASE/4)), sizeof(char), sz, fp) << std::endl;
    fclose(fp);

    // assemble an instruction to move away from the vector area.
    ARMword branchinst = 0xea000000 | ((EXECBASE - 8) >>2);

    // we branch away from the vector area to make the test fairer.
    memory[0] = branchinst;
}

void execute_amber(ARMword *memory, ARMword *registers)
{
    Edge cpuclk;
    Va23_core *uut;                 // Instantiation of module

    // reset the simulation time
    main_time = 0;

    remove( "amber.dis" );

    // create a new core instance
    uut = new Va23_core;
    uut->i_system_rdy = 0;

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    uut->trace (tfp, 99);
    tfp->open ("amber.vcd");

    // we evaluate here to make all the default values apply before we
    // change them to our fuzzed values
    uut->eval();

    // apply the fuzzed register values.
    amber_set_registers(uut, registers);

    while (!Verilated::gotFinish())
    {
        if (main_time > 32)
        {
            uut->i_system_rdy = 1;   // Deassert reset
        }

        if ((main_time % 2) == 0)
        {
            uut->i_clk = uut->i_clk ? 0 : 1;       // Toggle clock
        }

        cpuclk.Update(uut->i_clk);

        uut->eval();            // Evaluate model
        tfp->dump(main_time);

        if (uut->o_wb_stb && cpuclk.PosEdge() && !(bool)uut->i_wb_ack)
        {
            if (uut->v__DOT__u_decode__DOT__next_interrupt == 7) // SWIs stop the fuzzing.
            {
                if ((uut->v__DOT__u_decode__DOT__instruction & 0xffffff) == 0xffffff)
                {
                    break;
                }
            }

            if (uut->o_wb_we)
            {
                unsigned int mask = 0;
                if (uut->o_wb_sel & 1) mask |= 0xFF;
                if (uut->o_wb_sel & 2) mask |= 0xFF00;
                if (uut->o_wb_sel & 4) mask |= 0xFF0000;
                if (uut->o_wb_sel & 8) mask |= 0xFF000000;

                if (uut->o_wb_adr < MEMTOP)
                {
                    memory[uut->o_wb_adr >> 2] = uut->o_wb_dat & mask | memory[uut->o_wb_adr >> 2] & ~mask;
                }
            }
            else
            {
                if (uut->o_wb_adr < MEMTOP)
                {
                    uut->i_wb_dat = memory[uut->o_wb_adr >> 2];
                }
                else
                {
                    uut->i_wb_dat = 0;
                }
            }

            uut->i_wb_ack = 1;

        }
        else if (cpuclk.PosEdge())
        {
            uut->i_wb_ack = 0;
        }

        main_time++;            // Time passes..
    }

    amber_get_registers(uut, registers);

    uut->final();
    tfp->close();
    delete uut;

}

void execute_arcem(ARMword *memory, ARMword *registers)
{
    ARMul_State *emu_state = NULL;

    registers[15] = registers[15] & ~(0x3fffffc);

    emu_state = ARMul_NewState();
    ARMul_Reset(emu_state);
    arcem_set_registers(emu_state, registers);

    emu_state->Memory = memory;

    ARMul_DoProg(emu_state);

    emu_state->Reg[15] -= 4;

    arcem_get_registers(emu_state, registers);

    /* Close and Finalise */
    ARMul_CoProExit(emu_state);

}

void rand_registers(ARMword *regs)
{
    for (int i=0; i < 27; i++)
    {
        regs[i] = std::rand();
    }

    //regarcem[15] = regarcem[15] & ~(0x3ffffff);
}

int main(int argc, char** argv)
{
    int result = 0;
    std::cerr << "Executing % on Amber/ArcEM Comparison" << std::endl;
    Verilated::commandArgs(argc, argv);   // Remember args
    ARMul_EmulateInit();

    std::string fileName;

    if (argc > 1)
    {
        fileName = std::string(argv[1]);
    }

    ARMword *memory = new ARMword[MEMTOP];
    ARMword *initial = new ARMword[REGCOUNT];
    ARMword *regarcem = new ARMword[REGCOUNT];
    ARMword *regamber = new ARMword[REGCOUNT];
    std::memset(memory, 0, REGCOUNT);
    std::srand(3241234);

    rand_registers(initial);
    initial[15] = 0x60000003;
    copy_registers(initial, regarcem);
    copy_registers(initial, regamber);

    reset_memory(fileName, memory);
    execute_amber(memory, regamber);
    reset_memory(fileName, memory);
    execute_arcem(memory, regarcem);

    std::string msg;

    if (!compare_regs(regarcem, regamber, msg))
    {
        std::cerr << "Failed." << std::endl;
        std::cerr << "errors:\t" << msg << std::endl;
    }
    else
    {
        std::cerr << "Passed." << std::endl;
    }

    std::cerr << std::endl << "initial: ";
    print_registers(initial);
    std::cerr << std::endl << "arcem: ";
    print_registers(regarcem);
    std::cerr << std::endl << "amber: ";
    print_registers(regamber);
    result = -1;

    delete [] memory;
    delete [] regamber;
    delete [] regarcem;

    return result;
}
