OBJECTS=armemu.o eventq.o armcopro.o cp15.o armsupp.o arminit.o
CFLAGS :=  -Iinclude -I. -D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -DHOSTFS_SUPPORT -DEXTNROM_SUPPORT
TARGET = libarm.a
CC=gcc
ifeq ($(DEBUG),yes)
CFLAGS += -O0 -g 
else
CFLAGS = -O3 -funroll-loops -fexpensive-optimizations -ffast-math -fomit-frame-pointer -frerun-cse-after-loop
endif

all: $(TARGET)
$(TARGET): $(OBJECTS)
	$(AR) rcs $(TARGET) $(OBJECTS)
clean:
	rm -rf *~ $(OBJECTS) $(TARGET)