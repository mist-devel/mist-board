# clear dir vars if these programs are in path
AS=asasm
OBJCOPY=arm-unknown-riscos-objcopy

all: tstbug2.bin tstbug1.bin teqbug.bin rrxbug.bin andsbug.bin ldmbug.bin cmpbug.bin swpbug.bin swpbbug.bin
%.bin: %.o
	$(OBJCOPY) --image-base 0x0001000 -O binary $(^) $(@)
%.o: %.s 
	$(AS) -o $(@) $(^)	
clean:
	rm -f *.bin *.o 
