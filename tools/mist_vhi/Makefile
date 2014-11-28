TOOLS=..
MIST_VHI=mist_vhi

all: $(MIST_VHI).prg

$(MIST_VHI).prg: $(MIST_VHI).s
	$(TOOLS)/vasm/vasmm68k_mot -o $@ -Ftos -nosym $<

clean:
	rm -f $(MIST_VHI).prg *~

install: $(MIST_VHI).prg
	mcopy -o -i ../mist_vhi.st $(MIST_VHI).prg ::/AUTO/MIST_VHI.PRG
