TARGET=vidc
.PHONY: $(TARGET)

all: $(TARGET)

include ../default.mk
$(TARGET): common mifs
	verilator -Wno-fatal -I$(CHIPSET) --cc $(@).v --trace --exe ../$(@).cpp  -Mdir $(@) -LDFLAGS " $(COMMON_LDFLAGS) -lSDL" -CFLAGS "-g $(COMMON_CFLAGS)"
	make -C $(@) -f V$(@).mk
mifs:
	cp $(CHIPSET)/*.mif .
clean:: 
	rm -rf *.o $(TARGET)
distclean:: clean
	rm -rf *~ *.txt *.vcd *.mif *.orig