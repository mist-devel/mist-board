--
-- VM2413.vhd
--
-- Copyright (c) 2006 Mitsutaka Okazaki (brezza@pokipoki.org)
-- All rights reserved.
--
-- Redistribution and use of this source code or any derivative works, are
-- permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice,
--    this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
-- 3. Redistributions may not be sold, nor may they be used in a commercial
--    product or activity without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
-- TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
-- CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
-- EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
-- PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
-- OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
-- WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
-- OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
-- ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

package VM2413 is

  subtype CH_TYPE is integer range 0 to 9-1;
  subtype SLOT_TYPE     is std_logic_vector( 4 downto 0 );
  subtype STAGE_TYPE    is std_logic_vector( 1 downto 0 );

  subtype REGS_VECTOR_TYPE is std_logic_vector(23 downto 0);

  type REGS_TYPE is record
    INST : std_logic_vector(3 downto 0);
    VOL : std_logic_vector(3 downto 0);
    SUS : std_logic;
    KEY : std_logic;
    BLK : std_logic_vector(2 downto 0);
    FNUM : std_logic_vector(8 downto 0);
  end record;

  function CONV_REGS_VECTOR ( regs : REGS_TYPE ) return REGS_VECTOR_TYPE;
  function CONV_REGS ( vec : REGS_VECTOR_TYPE ) return REGS_TYPE;

  subtype VOICE_ID_TYPE is integer range 0 to 37;
  subtype VOICE_VECTOR_TYPE is std_logic_vector(35 downto 0);

  type VOICE_TYPE is record
    AM, PM, EG, KR : std_logic;
    ML : std_logic_vector(3 downto 0);
    KL : std_logic_vector(1 downto 0);
    TL : std_logic_vector(5 downto 0);
    WF : std_logic;
    FB : std_logic_vector(2 downto 0);
    AR, DR, SL, RR : std_logic_vector(3 downto 0);
  end record;

  function CONV_VOICE_VECTOR ( inst : VOICE_TYPE ) return VOICE_VECTOR_TYPE;
  function CONV_VOICE ( inst_vec : VOICE_VECTOR_TYPE ) return VOICE_TYPE;

  -- Voice Parameter Types
  subtype AM_TYPE is std_logic; -- AM switch - '0':off  '1':3.70Hz
  subtype PM_TYPE is std_logic; -- PM switch - '0':stop '1':6.06Hz
  subtype EG_TYPE is std_logic; -- Envelope type - '0':release '1':sustine
  subtype KR_TYPE is std_logic; -- Keyscale Rate
  subtype ML_TYPE is std_logic_vector(3 downto 0); -- Multiple
  subtype WF_TYPE is std_logic; -- WaveForm - '0':sine '1':half-sine
  subtype FB_TYPE is std_logic_vector(2 downto 0); -- Feedback
  subtype AR_TYPE is std_logic_vector(3 downto 0); -- Attack Rate
  subtype DR_TYPE is std_logic_vector(3 downto 0); -- Decay Rate
  subtype SL_TYPE is std_logic_vector(3 downto 0); -- Sustine Level
  subtype RR_TYPE is std_logic_vector(3 downto 0); -- Release Rate

  -- F-Number, Block and Rks(Rate and key-scale) types
  subtype BLK_TYPE  is std_logic_vector(2 downto 0); -- Block
  subtype FNUM_TYPE is std_logic_vector(8 downto 0); -- F-Number
  subtype RKS_TYPE is std_logic_vector(3 downto 0);  -- Rate-KeyScale

  -- 18 bits phase counter
  subtype PHASE_TYPE is std_logic_vector (17 downto 0);
  -- Phage generator's output
  subtype PGOUT_TYPE is std_logic_vector (8 downto 0);
  -- Final linear output of opll
  subtype LI_TYPE is std_logic_vector (8 downto 0); -- Wave in Linear
  -- Total Level and Envelope output
  subtype DB_TYPE is std_logic_vector(6 downto 0);  -- Wave in dB, Reso: 0.375dB

  subtype SIGNED_LI_VECTOR_TYPE is std_logic_vector(LI_TYPE'high + 1 downto 0);
  type SIGNED_LI_TYPE is record
    sign : std_logic;
    value : LI_TYPE;
  end record;
  function CONV_SIGNED_LI_VECTOR( li : SIGNED_LI_TYPE ) return SIGNED_LI_VECTOR_TYPE;
  function CONV_SIGNED_LI( vec : SIGNED_LI_VECTOR_TYPE ) return SIGNED_LI_TYPE;

  subtype SIGNED_DB_VECTOR_TYPE is std_logic_vector(DB_TYPE'high + 1 downto 0);
  type SIGNED_DB_TYPE is record
    sign : std_logic;
    value : DB_TYPE;
  end record;
  function CONV_SIGNED_DB_VECTOR( db : SIGNED_DB_TYPE ) return SIGNED_DB_VECTOR_TYPE;
  function CONV_SIGNED_DB( vec : SIGNED_DB_VECTOR_TYPE ) return SIGNED_DB_TYPE;

  -- Envelope generator states
  subtype EGSTATE_TYPE is std_logic_vector(1 downto 0);

  constant Attack  : EGSTATE_TYPE := "01";
  constant Decay   : EGSTATE_TYPE := "10";
  constant Release : EGSTATE_TYPE := "11";
  constant Finish  : EGSTATE_TYPE := "00";

  -- Envelope generator phase
  subtype EGPHASE_TYPE is std_logic_vector(22 downto 0);

  -- Envelope data (state and phase)
  type EGDATA_TYPE is record
    state : EGSTATE_TYPE;
    phase : EGPHASE_TYPE;
  end record;

  subtype EGDATA_VECTOR_TYPE is std_logic_vector(EGSTATE_TYPE'high + EGPHASE_TYPE'high + 1 downto 0);

  function CONV_EGDATA_VECTOR( data : EGDATA_TYPE ) return EGDATA_VECTOR_TYPE;
  function CONV_EGDATA( vec : EGDATA_VECTOR_TYPE ) return EGDATA_TYPE;

  component Opll port(
    XIN     : in std_logic;
    XOUT    : out std_logic;
    XENA    : in std_logic;
    D       : in std_logic_vector(7 downto 0);
    A       : in std_logic;
    CS_n    : in std_logic;
    WE_n    : in std_logic;
    IC_n    : in std_logic;
    mixout  : out std_logic_vector(13 downto 0)
  );
  end component;

end VM2413;

package body VM2413 is

  function CONV_REGS_VECTOR ( regs : REGS_TYPE ) return REGS_VECTOR_TYPE is
  begin
    return  regs.INST & regs.VOL & "00" & regs.SUS & regs.KEY & regs.BLK & regs.FNUM;
  end CONV_REGS_VECTOR;

  function CONV_REGS ( vec : REGS_VECTOR_TYPE ) return REGS_TYPE is
  begin
    return (
      INST=>vec(23 downto 20), VOL=>vec(19 downto 16),
      SUS=>vec(13), KEY=>vec(12), BLK=>vec(11 downto 9), FNUM=>vec(8 downto 0)
      );
  end CONV_REGS;

  function CONV_VOICE_VECTOR ( inst : VOICE_TYPE ) return VOICE_VECTOR_TYPE is
  begin
    return inst.AM & inst.PM & inst.EG & inst.KR &
           inst.ML & inst.KL & inst.TL & inst.WF & inst.FB &
           inst.AR & inst.DR & inst.SL & inst.RR;
  end CONV_VOICE_VECTOR;

  function CONV_VOICE ( inst_vec : VOICE_VECTOR_TYPE ) return VOICE_TYPE is
  begin
    return (
      AM=>inst_vec(35), PM=>inst_vec(34), EG=>inst_vec(33), KR=>inst_vec(32),
      ML=>inst_vec(31 downto 28), KL=>inst_vec(27 downto 26), TL=>inst_vec(25 downto 20),
      WF=>inst_vec(19), FB=>inst_vec(18 downto 16),
      AR=>inst_vec(15 downto 12), DR=>inst_vec(11 downto 8), SL=>inst_vec(7 downto 4), RR=>inst_vec(3 downto 0)
      );
  end CONV_VOICE;

  function CONV_SIGNED_LI_VECTOR( li : SIGNED_LI_TYPE ) return SIGNED_LI_VECTOR_TYPE is
  begin
    return li.sign & li.value;
  end;

  function CONV_SIGNED_LI( vec : SIGNED_LI_VECTOR_TYPE ) return SIGNED_LI_TYPE is
  begin
    return ( sign => vec(vec'high), value=>vec(vec'high-1 downto 0) );
  end;

  function CONV_SIGNED_DB_VECTOR( db : SIGNED_DB_TYPE ) return SIGNED_DB_VECTOR_TYPE is
  begin
    return db.sign & db.value;
  end;

  function CONV_SIGNED_DB( vec : SIGNED_DB_VECTOR_TYPE ) return SIGNED_DB_TYPE is
  begin
    return ( sign => vec(vec'high), value=>vec(vec'high-1 downto 0) );
  end;

  function CONV_EGDATA_VECTOR( data : EGDATA_TYPE ) return EGDATA_VECTOR_TYPE is
  begin
    return data.state & data.phase;
  end;

  function CONV_EGDATA( vec : EGDATA_VECTOR_TYPE ) return EGDATA_TYPE is
  begin
    return ( state => vec(vec'high downto EGPHASE_TYPE'high + 1),
             phase => vec(EGPHASE_TYPE'range) );
  end;

end VM2413;
