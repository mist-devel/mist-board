.PHONY: fuzz rrxfuzz arm disarm ldstfuzz
AMBER=../../../rtl/amber/
DISARM_LDFLAGS=../libdisarm/libdisarm.a
all: rrxfuzz fuzz program ldstfuzz 

include ../default.mk

fuzz: arm disarm common
	verilator -Wno-fatal -I$(SUPPORT) -I$(AMBER) --cc a23_core.v --trace --exe ../$(@).cpp  -Mdir $(@) -CFLAGS " -g -I../ $(COMMON_CFLAGS)" -LDFLAGS " -g $(DISARM_LDFLAGS) ../arm/*.o $(COMMON_LDFLAGS)"
	make -C $(@) -f Va23_core.mk
rrxfuzz: arm disarm common
	verilator -Wno-fatal -I$(SUPPORT) -I$(AMBER) --cc a23_core.v --trace --exe ../$(@).cpp  -Mdir $(@) -CFLAGS " -g -I../ $(COMMON_CFLAGS)" -LDFLAGS " -g $(DISARM_LDFLAGS) $(COMMON_LDFLAGS) ../arm/*.o"
	make -C $(@) -f Va23_core.mk
ldstfuzz: arm disarm common
	verilator -Wno-fatal -I$(SUPPORT) -I$(AMBER) --cc a23_core.v --trace --exe ../$(@).cpp  -Mdir $(@) -CFLAGS " -g -I../ $(COMMON_CFLAGS)" -LDFLAGS " -g $(DISARM_LDFLAGS) $(COMMON_LDFLAGS) ../arm/*.o"
	make -C $(@) -f Va23_core.mk
program: arm disarm common
	verilator -DA23_DECOMPILE -Wno-fatal -I$(SUPPORT) -I$(AMBER) --cc a23_core.v --trace --exe ../$(@).cpp  -Mdir $(@) -CFLAGS " -g -I../ $(COMMON_CFLAGS)" -LDFLAGS " -g $(DISARM_LDFLAGS) $(COMMON_LDFLAGS) ../arm/*.o"
	make -C $(@) -f Va23_core.mk
bugs:
	make -C bugs
arm: 
	make -C arm DEBUG=yes
disarm:
	make -C libdisarm
clean:: 
	rm -rf *.o *~ fuzz ldstfuzz rrxfuzz program *.dis *.vcd *.orig
	make -C arm clean
	make -C libdisarm clean
	make -C bugs clean