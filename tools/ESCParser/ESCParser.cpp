/*  This file is part of UKNCBTL.
    UKNCBTL is free software: you can redistribute it and/or modify it under the terms
of the GNU Lesser General Public License as published by the Free Software Foundation,
either version 3 of the License, or (at your option) any later version.
    UKNCBTL is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU Lesser General Public License for more details.
    You should have received a copy of the GNU Lesser General Public License along with
UKNCBTL. If not, see <http://www.gnu.org/licenses/>. */

#define _CRT_SECURE_NO_WARNINGS

#include "ESCParser.h"
#include <iostream>
#include <fstream>
#include <string.h>

//////////////////////////////////////////////////////////////////////
// Globals

const char* g_InputFileName = 0;
int g_OutputDriverType = OUTPUT_DRIVER_POSTSCRIPT;
OutputDriver* g_pOutputDriver = 0;


//////////////////////////////////////////////////////////////////////


bool ParseCommandLine(int argc, char* argv[])
{
    for (int argn = 1; argn < argc; argn++)
    {
        const char* arg = argv[argn];
        if (arg[0] == '-' || arg[0] == '/')
        {
            if (strcmp(arg + 1, "svg") == 0)
                g_OutputDriverType = OUTPUT_DRIVER_SVG;
            else if (strcmp(arg + 1, "ps") == 0)
                g_OutputDriverType = OUTPUT_DRIVER_POSTSCRIPT;
            else
            {
                std::cerr << "Unknown option: " << arg << std::endl;
                return false;
            }
        }
        else
        {
            if (g_InputFileName == 0)
                g_InputFileName = arg;
        }
    }

    // Parsed options validation
    if (g_InputFileName == 0)
    {
        std::cerr << "Input file is not specified." << std::endl;
        return false;
    }

    return true;
}

// Print usage info
void PrintUsage()
{
    std::cerr << "Usage:" << std::endl
            << "\tESCParser [options] InputFile > OutputFile" << std::endl
            << "Options:" << std::endl
            << "\t-ps\tPostScript output with multipage support" << std::endl
            << "\t-svg\tSVG output, no multipage support" << std::endl;
}

int main(int argc, char* argv[])
{
    std::cerr << "ESCParser utility  by Nikita Zimin  " << __DATE__ << " " << __TIME__ << std::endl;

    if (!ParseCommandLine(argc, argv))
    {
        PrintUsage();
        return -1;
    }

    // Choose a proper output driver
    switch (g_OutputDriverType)
    {
    case OUTPUT_DRIVER_SVG:
        g_pOutputDriver = new OutputDriverSvg(std::cout);
        break;
    case OUTPUT_DRIVER_POSTSCRIPT:
        g_pOutputDriver = new OutputDriverPostScript(std::cout);
        break;
    default:
        std::cerr << "Output driver type is not defined." << std::endl;
        return -1;
    }

    // First run: calculate total page count
    int pagestotal = 1;
    {
        // Prepare the input stream
        std::ifstream input(g_InputFileName, std::ifstream::in | std::ifstream::binary);
        if (input.fail())
        {
            std::cerr << "Failed to open the input file." << std::endl;
            return -1;
        }

        // Prepare stub driver
        OutputDriverStub driverstub(std::cout);

        // Run the interpreter to count the pages
        EscInterpreter intrpr1(input, driverstub);
        while (true)
        {
            if (!intrpr1.InterpretNext())
            {
                if (intrpr1.IsEndOfFile())
                    break;

                pagestotal++;
            }
        }
    }

    std::cerr << "Pages total: " << pagestotal << std::endl;

    // Second run: output the pages
    {
        // Prepare the input stream
        std::ifstream input(g_InputFileName, std::ifstream::in | std::ifstream::binary);
        if (input.fail())
        {
            std::cerr << "Failed to open the input file." << std::endl;
            return -1;
        }

        // Prepare the output driver
        g_pOutputDriver->WriteBeginning(pagestotal);
        int pageno = 1;
        std::cerr << "Page " << pageno << std::endl;
        g_pOutputDriver->WritePageBeginning(pageno);

        // Initialize the interpreter
        EscInterpreter intrpr(input, *g_pOutputDriver);

        // Run the interpreter to produce the pages
        while (true)
        {
            if (!intrpr.InterpretNext())
            {
                g_pOutputDriver->WritePageEnding();

                if (intrpr.IsEndOfFile())
                    break;

                pageno++;
                std::cerr << "Page " << pageno << std::endl;

                g_pOutputDriver->WritePageBeginning(pageno);
            }
        }

        g_pOutputDriver->WriteEnding();
    }

    // Cleanup
    delete g_pOutputDriver;
    g_pOutputDriver = 0;

    return 0;
}


//////////////////////////////////////////////////////////////////////
