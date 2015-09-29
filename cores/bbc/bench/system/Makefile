TARGET=bbc
.PHONY: $(TARGET)

all: $(TARGET)

include ../default.mk
$(TARGET): common mifs
	verilator -DSIM -Wno-fatal -I$(CHIPSET) -I$(SUPPORT) -I$(CHIPSET)/saa5050 --cc $(@).v --trace --exe ../$(@).cpp  -Mdir $(@) -LDFLAGS "$(COMMON_LDFLAGS) -lSDL" -CFLAGS "-O3 $(COMMON_CFLAGS)"
	make -C $(@) -f V$(@).mk
mifs:
	cp $(CHIPSET)/saa5050/*.mif .
clean:: 
	rm -rf *.o $(TARGET)
distclean:: clean
	rm -rf *~ *.txt *.vcd *.mif *.orig
