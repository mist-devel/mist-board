PROJECT=dma
NOWARN = -Wno-UNOPTFLAT -Wno-WIDTH # --report-unoptflat # -Wno-UNOPTFLAT

all: $(PROJECT).vcd

obj_dir/stamp: $(PROJECT).v fdc.v $(PROJECT)_tb.cpp
	verilator $(NOWARN) --cc --trace --exe $(PROJECT).v $(PROJECT)_tb.cpp
	touch obj_dir/stamp

obj_dir/V$(PROJECT): obj_dir/stamp
	make -j -C obj_dir/ -f V$(PROJECT).mk V$(PROJECT)

$(PROJECT).vcd: obj_dir/V$(PROJECT)
	obj_dir/V$(PROJECT)

clean:
	rm -rf obj_dir
	rm -f  $(PROJECT).vcd
	rm -f *~ 

view: $(PROJECT).vcd
	gtkwave $< $(PROJECT).sav &
