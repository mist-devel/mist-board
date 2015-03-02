TOOLS=../../tools
PROJECT=hscnt
PRG=$(PROJECT).tos

all: $(PRG)

$(PRG): $(PROJECT).s
	$(TOOLS)/vasm/vasmm68k_mot -o $@ -Ftos -nosym $<

clean:
	rm -f $(PRG) *~

sttest: $(PRG)
	hatari -d . $(PROG)

install: $(PRG)
	mcopy -o -i ./stvidtst.st $(PRG) ::/$(PRG)
