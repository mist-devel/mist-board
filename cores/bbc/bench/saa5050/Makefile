TARGET=saa5050
.PHONY: $(TARGET)

all: $(TARGET)

include ../default.mk
$(TARGET): common mif
	verilator -Wno-fatal -I$(CHIPSET)/saa5050 --cc $(@).v --trace --exe ../$(@).cpp  -Mdir $(@) -LDFLAGS "$(COMMON_LDFLAGS) -lSDL" -CFLAGS "-g $(COMMON_CFLAGS)"
	make -C $(@) -f V$(@).mk
mif:
	cp $(CHIPSET)/saa5050/saa5050.mif .
clean:: 
	rm -rf *.o $(TARGET)
distclean:: clean
	rm -rf *~ *.txt *.vcd *.mif *.orig