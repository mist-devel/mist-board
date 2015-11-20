Plus Too for MiST
=================

This is the source code of the MiST port of the Plus Too project. The
original files can be found at the [Plus Too project page](http://www.bigmessowires.com/2012/12/15/plus-too-files/).

Changes
-------

Initial changes made to the original source code are due to the porting process
itself. Major changes were:

- Use of SDRAM for RAM as well as ROM and floppy image buffer
  - SDRAM clocking at 130 MHz
  - ROM upload using the MISTs IO controller
  - Floppy image upload using the MISTs IO controller
- Use of MiSTs on screen display for floppy image selection
- Use of MiSTs PS2 mouse emulation
  - Need to disable all parts dealing with mouse inialization

Functional changes:

- tg68k cpu core updated to latest version
- floppy disk images use 400k or 800k dsk format
- support for second floppy disk
- SDRAM clock reduced to 65MHz
- PS2 keyboard support
- removed debug overlay
- removed irq vector generation
- various timing simplifications
- fix mouse counter wrapping
- Basic sound support
- SCSI interface + SCSI hdd support
- CPU Turbo mode (ca factor 2.5)

Usage
-----

The Alt key is mapped to the Mac's command key, and the Windows key is mapped to the Mac's option key.


Binaries are available at the [binaries repository](https://github.com/mist-devel/mist-binaries/tree/master/cores/plus_too).
