TARGET=a23_fetch
.PHONY: $(TARGET)

all: $(TARGET)

include ../default.mk

$(TARGET): common
	verilator -DA23_DEBUG_CACHE -Wno-fatal -I$(AMBER) -I$(SUPPORT) --cc $(@).v --trace --exe ../$(@).cpp  -Mdir $(@) -LDFLAGS "$(COMMON_LDFLAGS)" -CFLAGS "$(COMMON_CFLAGS)"
	make -C $(@) -f V$(TARGET).mk

clean:: 
	rm -rf *.o $(TARGET)
distclean:: clean
	rm -rf *~ *.vcd *.txt *.orig