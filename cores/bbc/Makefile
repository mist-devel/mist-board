all: mist
mist:
	$(MAKE) -C fpga/mist
clean:
	@echo cleaning up
	rm -f *~ a.out *.o
	$(MAKE) -C fpga/mist clean	
	$(MAKE) -C bench/system clean	