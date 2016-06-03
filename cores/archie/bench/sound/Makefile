TARGET=vidc_audio
.PHONY: $(TARGET) mu255 conv

all: $(TARGET)

include ../default.mk

$(TARGET): common mifs llama.ac
	verilator -O3 -Wno-fatal -I$(CHIPSET) --cc $(@).v --trace --exe  ../$(@).cpp  -Mdir $(@) -LDFLAGS "$(COMMON_LDFLAGS)" -CFLAGS "$(COMMON_CFLAGS)"
	make -C $(@) -f V$(TARGET).mk
	time ./vidc_audio/Vvidc_audio start.ac | play -t raw -r 22k -e unsigned -b 16 -c 1 -
	time ./vidc_audio/Vvidc_audio llama.ac | play -t raw -r 22k -e unsigned -b 16 -c 2 -
mifs: mu255
	./mu255 > vidc_mulaw.mif 
llama.ac: conv
	sox llama.wav -c 2 llama.ul && cat llama.ul | ./conv > llama.ac
mu255:
	gcc -o $(@) $(@).c
conv: 
	gcc -o $(@) $(@).c
clean:: 
	rm -rf *.o $(TARGET) llama.ac *.vcd conv mu255
distclean:: clean
	rm -rf *~ *.mif *.lu *.ul *.vcd *.txt *.orig
