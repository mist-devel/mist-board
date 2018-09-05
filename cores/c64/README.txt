---------------------------------------------------------------------------------
-- FPGA64_027 and 1541_SD by Dar (darfpga@aol.fr) release 0001- 26/07/2015
--
-- http://darfpga.blogspot.fr
--
-- FPGA64 is Copyrighted 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
--
-- Main features
--  15KHz(TV) / 31Khz(VGA)
--  PAL(50Hz) / NTSC(60Hz)
--  PS2 keyboard input with portA / portB joystick emulation
--  SID sound output
--
--
--  Internal emulated 1541 on raw SD card (READ ONLY) : D64 images start at 256KB boundaries
--  Use hexadecimal disk editor such as HxD (www.mh-nexus.de) to build SD card.
--  Cut D64 file and paste at 0x00000 (first), 0x40000 (second), 0x80000 (third),
--  0xC0000(fourth), 0x100000(fith), 0x140000 (sixth) and so on.
--  BE CAREFUL NOT WRITING ON YOUR OWN HARDDRIVE
--
--  Use only SIMPLE D64 files : 174 848 octets (without disk error management) 
-- 
---------------------------------------------------------------------------------
--
-- c1541_sd reads D64 data from raw SD card, produces GCR data, feeds c1541_logic
-- Raw SD data : each D64 image must start on 256KB boundaries
-- disk_num allow to select D64 image
--
-- c1541_logic    from : Mark McDougall
-- spi_controller from : Michel Stempin, Stephen A. Edwards
-- via6522        from : Arnim Laeuger, Mark McDougall, MikeJ
-- T65            from : Daniel Wallner, MikeJ, ehenciak
--
-- c1541_logic    modified for : slow down CPU (EOI ack missed by real c64)
--                             : remove IEC internal OR wired
--                             : synched atn_in (sometime no IRQ to CPU with real c64)
-- spi_controller modified for : sector start and size adapted + busy signal
-- via6522        modified for : no modification
--
---------------------------------------------------------------------------------

FPGA64_027 Keyboard specific keys :
    
    Escape : run stop
    [      : @
    ]      : *
    \      : up arrow
    '      : semi colon 
    `      : left arrow
    F9     : £
    F10    : +
    Left Alt : commodore key
    

END
