TARGET=libcommon.a
.PHONY: $(TARGET) arm libdisarm
all: $(TARGET)

OBJECTS=edge.o 

$(TARGET): $(OBJECTS) arm libdisarm
	$(AR) rvs $(TARGET) $(OBJECTS) arm/*.o libdisarm/*.o
arm:
	make -C arm
libdisarm:
	make -C libdisarm
clean: 
	rm -rf *.o $(TARGET)
	make -C arm clean
	make -C libdisarm clean
distclean: clean
	rm -rf *~ *.mif *.lu *.ul *.vcd *.txt *.orig
