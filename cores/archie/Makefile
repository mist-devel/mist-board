MISTBOARD=fpga/mist
all: mist
mist:
	$(MAKE) -C $(MISTBOARD)
clean:
	@echo cleaning up
	rm -rf *~ a.out *.o $(MISTBOARD)/output_files $(MISTBOARD)/db $(MISTBOARD)/incremental_db $(MISTBOARD)/*.qpf
