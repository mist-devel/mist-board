PROJECT=sd_card
NOWARN = # --report-unoptflat # -Wno-UNOPTFLAT
XTRA_OBJS = mmc2.o utils.o diskio_mmc.o pff.o pff_file.o
ODIR = obj_dir
XTRA_OBJS_PATH=$(addprefix $(ODIR)/, $(XTRA_OBJS))

all: $(PROJECT).vcd

$(ODIR)/%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

$(ODIR)/stamp: $(PROJECT).v $(PROJECT)_tb.cpp
	verilator $(NOWARN) --cc --trace --exe $(PROJECT).v $(PROJECT)_tb.cpp $(XTRA_OBJS)
	touch $(ODIR)/stamp

$(ODIR)/V$(PROJECT): $(ODIR)/stamp $(XTRA_OBJS_PATH)
	make -j -C $(ODIR)/ -f V$(PROJECT).mk V$(PROJECT)

$(PROJECT).vcd: $(ODIR)/V$(PROJECT)
	$(ODIR)/V$(PROJECT)

run: $(ODIR)/V$(PROJECT)
	$(ODIR)/V$(PROJECT)

clean:
	rm -rf $(ODIR)
	rm -f  $(PROJECT).vcd
	rm -f *~  

view: $(PROJECT).vcd
	gtkwave $< $(PROJECT).sav &
