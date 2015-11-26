SDCC=sdcc
CPU=z80
CODE=boot_rom

all: $(CODE).hex

%.ihx: %.c
	$(SDCC) -m$(CPU) $<

%.hex: %.ihx
	mv $< $@

%.bin: %.hex
	srec_cat $< -intel -o $@ -binary

disasm: $(CODE).bin
	z80dasm -a -t -g 0 $<

clean:
	rm -rf *~ *.asm *.ihx *.lk *.lst *.map *.noi *.rel *.sym
