Plus Too for MiST
=================

This is the source code of the MiST port of the Plus Too project. The
original files can be founf at:

http://www.bigmessowires.com/2012/12/15/plus-too-files/

Changes
-------

All changes made to the original source code are due to the porting process
itself. No functional changes have been made (yet). Major changes were:

- Use of SDRAM for RAM as well as ROM and floppy image buffer
  - SDRAM clocking at 130 MHz
  - ROM upload using the MISTs IO controller
  - Floppy image upload using the MISTs IO controller
- Use of MiSTs on screen display for floppy image selection
- Use of MiSTS PS2 mouse emulation
  - Need to disable all parts dealing with mouse inialization

Binaries are available at https://github.com/mist-devel/mist-binaries/tree/master/cores/plustoo.
