TARGET=alufuzz
.PHONY: $(TARGET)
all: $(TARGET)

include ../default.mk

$(TARGET): common
	verilator -Wno-fatal -I$(SUPPORT) -I$(AMBER) --cc a23_core.v --trace --exe ../$(@).cpp  -Mdir $(@) -CFLAGS " -g $(COMMON_CFLAGS)" -LDFLAGS " -g $(COMMON_LDFLAGS)"
	make -C $(@) -f Va23_core.mk
clean:: 
	rm -rf *.o *~ $(TARGET) *.dis *.vcd *.orig
