TARGET=archimedes_top
I2CTARGET=i2cSlaveTop
.PHONY: $(TARGET)

all: $(TARGET)

include ../default.mk

$(TARGET): common mifs i2cSlaveTop
	verilator -O3 -Wno-fatal -I$(SUPPORT) -I$(CHIPSET) -I$(AMBER) --cc $(@).v --trace --exe  ../$(@).cpp  -Mdir $(@) -LDFLAGS "../i2cSlaveTop/Vi2cSlaveTop__ALL.a $(COMMON_LDFLAGS) $(SDL_LDFLAGS)" -CFLAGS "$(COMMON_CFLAGS)"
	make -C $(@) -f V$(TARGET).mk
mifs:
	cp $(CHIPSET)/*.mif .
	cp $(I2C)/*.mif .
$(I2CTARGET):
	verilator -O3 -Wno-fatal -I$(I2C) --cc $(I2C)/$(@).v -Mdir $(@)
	make -C $(@) -f V$(@).mk
clean:: 
	rm -rf *.o $(TARGET) $(I2CTARGET) *.vcd
distclean:: clean
	rm -rf *~ *.mif *.lu *.ul *.vcd *.txt