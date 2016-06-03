TARGET=sdram
.PHONY: $(TARGET)

all: $(TARGET)

include ../default.mk
$(TARGET): common 
	verilator -Wno-fatal -I$(SUPPORT) -I$(CHIPSET)/sdram --cc $(@).v --trace --exe ../$(@).cpp  -Mdir $(@) -LDFLAGS " $(COMMON_LDFLAGS) -lSDL" -CFLAGS "-g $(COMMON_CFLAGS)"
	make -C $(@) -f V$(@).mk
clean:: 
	rm -rf *.o $(TARGET)
distclean:: clean
	rm -rf *~ *.txt *.vcd *.mif *.orig