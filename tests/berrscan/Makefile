PROJECT=berrscan

BASE=m68k-atari-mint-
GCC=${BASE}gcc

berrscan.prg: berrscan.c
	$(GCC) -Os -s -o $@ $<

sttest: berrscan.prg
	hatari -d . berrscan.prg

install: berrscan.prg
	mcopy -o -i ../test.st berrscan.prg ::/

get:
	mcopy -o -i ../test.st ::/berrscan.log ./berrscan.log
