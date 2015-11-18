PROJECT=floppy_track_encoder

all: $(PROJECT).vcd

obj_dir/stamp: $(PROJECT).v $(PROJECT)_tb.cpp
	verilator -Wall --cc --trace --exe $(PROJECT).v $(PROJECT)_tb.cpp
	touch obj_dir/stamp

obj_dir/V$(PROJECT): obj_dir/stamp
	make -j -C obj_dir/ -f V$(PROJECT).mk V$(PROJECT)

$(PROJECT).vcd: obj_dir/V$(PROJECT)
	obj_dir/V$(PROJECT)

clean:
	rm -rf obj_dir
	rm -f  $(PROJECT).vcd
	rm -f *~ 

run: obj_dir/V$(PROJECT)
	obj_dir/V$(PROJECT)

view: $(PROJECT).vcd
	gtkwave $< $(PROJECT).sav &
