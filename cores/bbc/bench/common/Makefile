TARGET=libcommon.a
.PHONY: $(TARGET)
all: $(TARGET)

OBJECTS=edge.o 

$(TARGET): $(OBJECTS)
	$(AR) rvs $(TARGET) $(OBJECTS)
clean: 
	rm -rf *.o $(TARGET)
distclean: clean
	rm -rf *~ *.mif *.lu *.ul *.vcd *.txt *.orig