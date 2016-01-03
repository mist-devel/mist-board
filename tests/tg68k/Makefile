CODE = tests/testsuite
TG68K_RUN = tg68k_run
M68K_RUN = m68k_run
SRCS = TG68K_ALU.vhd TG68K_Pack.vhd TG68KdotC_Kernel.vhd $(TG68K_RUN).vhd mem_if.vhd
OBJS = $(SRCS:.vhd=.o) mem_if_c.o mem.o
GHW  = $(TG68K_RUN).ghw
TOOLS=../../tools
ZIP = tg68k_run.zip
PATCH = tg68k.patch
M68K_RUN_OBJS = $(M68K_RUN).o mem.o m68kcpu.o m68kops.o m68kopnz.o m68kopac.o m68kopdm.o 

all: $(M68K_RUN) $(TG68K_RUN)

TG68KdotC_Kernel.o: TG68K_Pack.o
TG68K_ALU.o: TG68K_Pack.o
tg68k_run.o: mem_if.o

%.o: %.vhd # work-obj93.cf
	ghdl -a --ieee=synopsys -fexplicit $<

work-obj93.cf: $(SRCS)
	ghdl -i $(SRCS)

$(TG68K_RUN): $(OBJS) mem_if_c.o mem.o
	ghdl -e -Wl,mem_if_c.o -Wl,mem.o --ieee=synopsys -fexplicit $@

%.o: Musashi/%.c
	gcc -o $@ -c $<

m68kcpu.o: Musashi/m68kops.h
Musashi/m68kops.c: Musashi/m68kops.h
Musashi/m68kopnz.c: Musashi/m68kops.h
Musashi/m68kopdm.c: Musashi/m68kops.h
Musashi/m68kopac.c: Musashi/m68kops.h

$(CODE).bin: $(CODE).s tests/bcd.s tests/bfxxx.s tests/cmpi_d16_pc.s tests/pack.s tests/trace.s tests/magic.s 

Musashi/m68kops.h: Musashi/m68kmake Musashi/m68k_in.c
	cd Musashi; ./m68kmake

$(M68K_RUN): $(M68K_RUN_OBJS)
	gcc -o $(M68K_RUN) $(M68K_RUN_OBJS)

test: $(M68K_RUN) $(CODE).bin
	./$(M68K_RUN) $(CODE).bin

vtest: $(TG68K_RUN) $(CODE).bin
	ghdl -r $(TG68K_RUN) --ieee-asserts=disable --stop-time=2000000ns --wave=$(GHW)

clean::
	rm -f work-obj93.cf *.o Musashi/m68kop* $(CODE).bin *~ *.lst *.ghw $(TG68K_RUN) ghwreplay Musashi/m68kmake $(M68K_RUN)

$(GHW): $(TG68K_RUN) Makefile
	ghdl -r $< --ieee-asserts=disable --stop-time=20000ns --wave=$@

disasm: $(CODE).bin
	$(TOOLS)/m68kdis/m68kdis -020 $(CODE).bin
	cat `basename $(CODE).bin.s`

view: $(GHW)
	gtkwave $< $(TG68K_RUN).sav

%.bin: %.s
	$(TOOLS)/vasm/vasmm68k_mot -m68020 -Fbin -o $@ -L $(CODE).lst -nosym $<
	hexdump -C $@

zip::
	make clean
	make patch
	zip -r $(ZIP) *.c *.h *.vhd $(CODE).s Makefile *.sav orig Musashi

patch::
	for i in orig/*.vhd ; do diff -Nbaur $$i `basename $$i`; done >$(PATCH) | true
