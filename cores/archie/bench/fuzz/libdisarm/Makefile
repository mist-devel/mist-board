OBJECTS=args.o print.o parser.o
TARGET = libdisarm.a
CC=gcc

all: $(TARGET)
$(TARGET): $(OBJECTS)
	$(AR) rcs $(TARGET) $(OBJECTS)
clean:
	rm -rf *~ $(OBJECTS) $(TARGET)