SDCC=sdcc
CPU=z80
CODE=boot_rom
TTY=/dev/ttyUSB0
OBJ=$(CODE).rel irqvec.rel font.rel pff.rel mmc.rel
ROM=z80_soc.rom
YM_DEINT=ym_deint

all: $(ROM)

bin2c: bin2c.c

font.part: font.fnt
	dd if=$< of=$@ bs=1 count=768 skip=256

font.c: font.part bin2c
	./bin2c font.part font.c "const unsigned char font[]"

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
	rm -rf *~ *.asm *.ihx *.lk *.lst *.map *.noi *.rel *.sym *.bin bin2c *.part

$(YM_DEINT): $(YM_DEINT).c
	gcc -o $@ $<

song.ym: song_201.ym $(YM_DEINT)
	./$(YM_DEINT) $< $@

song_update: song.ym
	stty -F $(TTY) speed 115200 raw -echo
	timeout 1s cp $(TTY) /dev/null || /bin/true
	echo "x $< `stat -c%s $<`" > $(TTY)
	sx $< <$(TTY) >$(TTY)

run: $(ROM)
	stty -F $(TTY) speed 115200 raw -echo
	timeout 1s cp $(TTY) /dev/null || /bin/true
	echo "x $< `stat -c%s $<`" > $(TTY)
	sx $< <$(TTY) >$(TTY)
	echo "r" > $(TTY)

core_update:
	stty -F $(TTY) speed 115200 raw -echo
	timeout 1s cp $(TTY) /dev/null || /bin/true
	echo "x core.rbf `stat -c%s soc.rbf`" > $(TTY)
	sx soc.rbf <$(TTY) >$(TTY)
	echo "r" > $(TTY)

reset:
	echo "r" > $(TTY)
