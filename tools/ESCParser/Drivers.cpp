/*  This file is part of UKNCBTL.
    UKNCBTL is free software: you can redistribute it and/or modify it under the terms
of the GNU Lesser General Public License as published by the Free Software Foundation,
either version 3 of the License, or (at your option) any later version.
    UKNCBTL is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU Lesser General Public License for more details.
    You should have received a copy of the GNU Lesser General Public License along with
UKNCBTL. If not, see <http://www.gnu.org/licenses/>. */

#include "ESCParser.h"
#include <stdio.h>

//////////////////////////////////////////////////////////////////////
// SVG driver

//NOTE: The most recent SVG standard is 1.2 tiny. Multipage support appears in 1.2 full.
// So, currently SVG does not have multipage support, and browsers can't interpret multipage SVGs.

void OutputDriverSvg::WriteBeginning(int pagestotal)
{
    m_output << "<?xml version=\"1.0\"?>" << std::endl;
    m_output << "<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.0\">" << std::endl;
}

void OutputDriverSvg::WriteEnding()
{
    m_output << "</svg>" << std::endl;
}

void OutputDriverSvg::WriteStrike(float x, float y, float r)
{
    float cx = x / 10.0f;
    float cy = y / 10.0f;
    float cr = r / 10.0f;
    m_output << "<circle cx=\"" << cx << "\" cy=\"" << cy << "\" r=\"" << cr << "\" />" << std::endl;
}


//////////////////////////////////////////////////////////////////////
// PostScript driver

void OutputDriverPostScript::WriteBeginning(int pagestotal)
{
    m_output << "%!PS-Adobe-2.0" << std::endl;
    m_output << "%%Creator: ESCParser" << std::endl;
    m_output << "%%Pages: " << pagestotal << std::endl;

    // PS procedure used to simplify WriteStrike output
    m_output << "/dotxyr { newpath 0 360 arc fill } def" << std::endl;
}

void OutputDriverPostScript::WriteEnding()
{
    m_output << "%%EOF" << std::endl;
}

void OutputDriverPostScript::WritePageBeginning(int pageno)
{
    m_output << "%%Page: " << pageno << " " << pageno << std::endl;
    m_output << "0 850 translate 1 -1 scale" << std::endl;
    m_output << "0 setgray" << std::endl;
}

void OutputDriverPostScript::WritePageEnding()
{
    m_output << "showpage" << std::endl;
}

void OutputDriverPostScript::WriteStrike(float x, float y, float r)
{
    float cx = x / 10.0f;
    float cy = y / 10.0f;
    float cr = r / 10.0f;

    char buffer[24];
    snprintf(buffer, sizeof(buffer), "%.2f %.2f %.1f", cx, cy, cr);
    m_output << buffer << " dotxyr" << std::endl;
}


//////////////////////////////////////////////////////////////////////
