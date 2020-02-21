Loopy's NSF Player
------------------

Use asm6 to compile:

asm6 nsf.asm

Strip header:

dd if=nsf.bin of=nsf.rom bs=1 skip=16 count=4096

Convert to hex:

srec_cat nsf.rom -bin -Output nsf.hex -vmem 8
