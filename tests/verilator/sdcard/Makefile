PROJECT=sd_card
NOWARN = -Wno-UNOPTFLAT # --report-unoptflat # -Wno-UNOPTFLAT
XTRA_OBJS = mmc2.o utils.o diskio_mmc.o pff.o pff_file.o
ODIR = obj_dir
XTRA_OBJS_PATH=$(addprefix $(ODIR)/, $(XTRA_OBJS))

# useful values for a 16 bit fat
FAT?=16
SIZE?=32k

all: $(PROJECT).vcd

$(ODIR)/%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

$(ODIR)/stamp: $(PROJECT).v $(PROJECT)_tb.cpp
	verilator $(NOWARN) --cc --trace --exe $(PROJECT).v $(PROJECT)_tb.cpp $(XTRA_OBJS)
	touch $(ODIR)/stamp

$(ODIR)/V$(PROJECT): $(ODIR)/stamp $(XTRA_OBJS_PATH)
	make -j -C $(ODIR)/ -f V$(PROJECT).mk V$(PROJECT)

$(PROJECT).vcd: $(ODIR)/V$(PROJECT) card.img
	$(ODIR)/V$(PROJECT)

run: $(ODIR)/V$(PROJECT) card.img
	$(ODIR)/V$(PROJECT)

clean:
	rm -rf $(ODIR)
	rm -f  $(PROJECT).vcd
	rm -f *~  

card.img: Makefile
# create file system
	dd if=/dev/zero of=part bs=512 count=$(SIZE)
	mkdosfs -F$(FAT) part
	mmd -o -i part ::/atari800
	mmd -o -i part ::/atari800/rom
	mcopy -o -i part sd_card.v ::/atari800/rom/atarixl.rom
# prepend partition table
	dd if=/dev/zero of=ptable bs=512 count=16 2> /dev/null
	cat ptable part > $@
	echo "n\np\n1\n16\n\nt\n6\nw\n" | fdisk -c=dos -C64 -H2 -S16 $@ 
	rm part ptable

view: $(PROJECT).vcd
	gtkwave $< $(PROJECT).sav &
