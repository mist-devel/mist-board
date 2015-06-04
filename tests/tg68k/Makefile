CODE = testcode
SRCS = TG68K_ALU.vhd TG68K_Pack.vhd TG68KdotC_Kernel.vhd $(CODE)_defs_pack.vhd $(CODE)_pack.vhd tg68k_tb.vhd
OBJS = $(SRCS:.vhd=.o)
ROOT = tg68k_tb
VCD  = $(ROOT).vcd
GHW  = $(ROOT).ghw
TOOLS=../../../tools
PATCH = tg68k_pack_unpk.patch
ZIP = tg68k_pack_unpk.zip

all: $(GHW)

TG68KdotC_Kernel.o: TG68K_Pack.o
TG68K_ALU.o: TG68K_Pack.o
tg68k_tb.o: $(CODE)_pack.o
$(CODE)_pack.o: $(CODE)_defs_pack.o

%.o: %.vhd # work-obj93.cf
	ghdl -a $<

work-obj93.cf: $(SRCS)
	ghdl -i $(SRCS)

$(ROOT): $(OBJS)
	ghdl -e $@

clean::
	rm -f work-obj93.cf *.o $(CODE).bin $(CODE)_pack.vhd *~ *.lst *.ghw $(ROOT)

$(VCD): $(ROOT) Makefile
	ghdl -r $< --ieee-asserts=disable --stop-time=10000ns --vcd=$@

$(GHW): $(ROOT) Makefile
	ghdl -r $< --ieee-asserts=disable --stop-time=10000ns --wave=$@

#view: $(VCD)
#	gtkwave $< $(ROOT).sav

view: $(GHW)
	gtkwave $< $(ROOT).sav

%.bin: %.s
	$(TOOLS)/vasm/vasmm68k_mot -m68020 -Fbin -o $@ -L $(CODE).lst -nosym $<
	hexdump -C $@

%_pack.vhd: %.bin
	srec_cat $< -binary -o $@ --VHdl 2 testcode

zip::
	make clean
	make patch
	zip -r $(ZIP) *.vhd $(CODE)* Makefile *.sav orig

patch::
	for i in orig/*.vhd ; do diff -Nbaur $$i `basename $$i`; done >$(PATCH) | true
