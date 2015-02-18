video tests
-----------

These tests run the entire Atari ST video subsystem through a verilator
simulation. The screen is simulated using a SDL window.

In video_tb.cpp several things can be configured:

DUMP      -- enable signal dump. Slows down simulation
VIKING    -- enable simulated viking video card
REZ       -- shifter resolution LOW=0, MID=1, HI=2
SD        -- scan doubler on/off
SL        -- scanlines 0=off -> 3=75%
PAL       -- enable 1-PAL or 0-NTSC
PAL56     -- use 56Hz PAL video modes

Different modes to be tested:
LOWREZ PAL50 without scan doubler
LOWREZ PAL50 with scan doubler
LOWREZ PAL56 without scan doubler
LOWREZ PAL56 with scan doubler
LOWREZ NTSC without scan doubler
LOWREZ NTSC with scan doubler
MIDREZ PAL50 without scan doubler
MIDREZ PAL50 with scan doubler
MIDREZ PAL56 without scan doubler
MIDREZ PAL56 with scan doubler
MIDREZ NTSC without scan doubler
MIDREZ NTSC with scan doubler
HIREZ
VIKING
