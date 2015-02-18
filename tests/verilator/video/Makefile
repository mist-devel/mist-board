PROJECT=video
NOWARN = -Wno-UNOPTFLAT -Wno-WIDTH -Wno-COMBDLY -Wno-CASEINCOMPLETE # --report-unoptflat # -Wno-UNOPTFLAT
SRC = osd.v  scandoubler.v  shifter.v  video_modes.v viking.v sync_adjust.v $(PROJECT).v $(PROJECT)_tb.cpp

all: $(PROJECT).vcd

obj_dir/stamp: $(SRC)
	verilator $(NOWARN) --cc --trace -CFLAGS `sdl-config --cflags` --exe $(PROJECT).v $(PROJECT)_tb.cpp -LDFLAGS "`sdl-config --libs`"
	touch obj_dir/stamp

obj_dir/V$(PROJECT): obj_dir/stamp
	make -j -C obj_dir/ -f V$(PROJECT).mk V$(PROJECT)

$(PROJECT).vcd: obj_dir/V$(PROJECT)
	obj_dir/V$(PROJECT)

clean:
	rm -rf obj_dir
	rm -f  $(PROJECT).vcd
	rm -f *~ 

check:
	for i in *.v ; do cmp $$i ../../hdl/mist/$$i ; done 

view: $(PROJECT).vcd
	gtkwave $< $(PROJECT).sav &
