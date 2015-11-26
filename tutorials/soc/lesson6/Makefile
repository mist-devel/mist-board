SDCC=sdcc
CPU=z80
CODE=boot_rom
TTY=/dev/ttyUSB0
OBJ=$(CODE).rel irqvec.rel
ROM=z80_soc.rom

all: $(ROM)

bin2c: bin2c.c

irqvec.rel: irqvec.s
	sdasz80 -o $@ $<

%.rel: %.c
	$(SDCC) -m$(CPU) -c $<

$(CODE).ihx: $(OBJ)
	$(SDCC) -m$(CPU) $(OBJ)

%.hex: %.ihx
	cp $< $@

%.bin: %.hex
	srec_cat -multiple $< -intel -o $@ -binary

$(ROM): $(CODE).bin
	cp $< $@

disasm: $(CODE).bin
	z80dasm -a -t -g 0 $<

clean:
	rm -rf *~ *.asm *.ihx *.lk *.lst *.map *.noi *.rel *.sym *.bin

run: $(ROM)
	stty -F $(TTY) speed 115200 raw -echo
	timeout 1s cp $(TTY) /dev/null || /bin/true
	echo "x $(ROM) `stat -c%s $<`" > $(TTY)
	sx $< <$(TTY) >$(TTY)
	echo "r" > $(TTY)
