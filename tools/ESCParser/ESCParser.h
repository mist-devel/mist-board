/*  This file is part of UKNCBTL.
    UKNCBTL is free software: you can redistribute it and/or modify it under the terms
of the GNU Lesser General Public License as published by the Free Software Foundation,
either version 3 of the License, or (at your option) any later version.
    UKNCBTL is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU Lesser General Public License for more details.
    You should have received a copy of the GNU Lesser General Public License along with
UKNCBTL. If not, see <http://www.gnu.org/licenses/>. */

#ifndef _ESCPARSER_H_
#define _ESCPARSER_H_

#include <iostream>

extern unsigned short RobotronFont[];


//////////////////////////////////////////////////////////////////////
// Output drivers

enum
{
    OUTPUT_DRIVER_UNKNOWN = 0,
    OUTPUT_DRIVER_SVG = 1,
    OUTPUT_DRIVER_POSTSCRIPT = 2,
};

// Base abstract class for output drivers
class OutputDriver
{
protected:
    std::ostream& m_output;

public:
    OutputDriver(std::ostream& output) : m_output(output) { }

public:
    // Write beginning of the document
    virtual void WriteBeginning(int pagestotal) { }  // Overwrite if needed
    // Write ending of the document
    virtual void WriteEnding() { }  // Overwrite if needed
    // Write beginning of the page
    virtual void WritePageBeginning(int pageno) { }  // Overwrite if needed
    // Write ending of the page
    virtual void WritePageEnding() { }  // Overwrite if needed
    // Write strike by one pin
    virtual void WriteStrike(float x, float y, float r) = 0;  // Always overwrite
};

// Stub driver, does nothing
class OutputDriverStub : public OutputDriver
{
public:
    OutputDriverStub(std::ostream& output) : OutputDriver(output) { };

public:
    virtual void WriteStrike(float x, float y, float r) { }
};

// SVG driver, for one-page output only
class OutputDriverSvg : public OutputDriver
{
public:
    OutputDriverSvg(std::ostream& output) : OutputDriver(output) { };

public:
    virtual void WriteBeginning(int pagestotal);
    virtual void WriteEnding();
    virtual void WriteStrike(float x, float y, float r);
};

// PostScript driver with multipage support
class OutputDriverPostScript : public OutputDriver
{
public:
    OutputDriverPostScript(std::ostream& output) : OutputDriver(output) { };

public:
    virtual void WriteBeginning(int pagestotal);
    virtual void WriteEnding();
    virtual void WritePageBeginning(int pageno);
    virtual void WritePageEnding();
    virtual void WriteStrike(float x, float y, float r);
};


//////////////////////////////////////////////////////////////////////
// ESC/P interpreter

class EscInterpreter
{
private:  // Input and output
    std::istream& m_input;
    OutputDriver& m_output;

private:  // Current state
    int  m_x, m_y;      // Current position
    int  m_marginleft, m_margintop;
    int  m_shiftx, m_shifty;  // Shift for text printout
    bool m_printmode;   // false - DRAFT, true - LQ
    bool m_endofpage;
    bool m_fontsp;      // Шрифт вразрядку
    bool m_fontdo;      // Двойная печать
    bool m_fontfe;      // Жирный шрифт
    bool m_fontks;      // Сжатый шрифт
    bool m_fontel;      // Шрифт "элита"
    bool m_fontun;      // Подчеркивание
    bool m_superscript; // Верхний регистр
    bool m_subscript;   // Нижний регистр
    unsigned char m_charset;  // Номер набора символов

public:
    // Constructor
    EscInterpreter(std::istream& input, OutputDriver& output);
    // Interpret next character or escape sequense
    bool InterpretNext();
    // Interpret escape sequence
    bool InterpretEscape();
    // is the end of input stream reached
    bool IsEndOfFile() const { return m_input.eof(); }

protected:
    // Retrieve a next byte from the input
    unsigned char GetNextByte();
    // Update m_shiftx according to current font settings
    void UpdateShiftX();
    // Reset the printer settings
    void PrinterReset();
    // Print graphics
    void printGR9(int dx);
    // Print graphics
    void printGR24(int dx);
    // Print the symbol using current charset
    void PrintCharacter(unsigned char ch);
    // Draw strike made by one pin
    void DrawStrike(float x, float y);
};


//////////////////////////////////////////////////////////////////////
#endif // _ESCPARSER_H_
