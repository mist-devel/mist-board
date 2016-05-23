/* ArcEM vs Amber - Clock Edge Support File
Copyright (C) 2015 Stephen J. Leary

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */
 #include "edge.h"

Edge::Edge()
{
  m_NegEdge = false;	
  m_PosEdge = false;	
  m_LastValue = false;	
}

void Edge::Update(bool value) 
{ 
  m_PosEdge = value & ~ m_LastValue;
  m_NegEdge = ~value &  m_LastValue; 
  m_LastValue = value;
}
	
bool Edge::PosEdge() 
{ 
  return m_PosEdge; 
}

bool Edge::NegEdge() 
{ 
  return m_NegEdge; 
}
