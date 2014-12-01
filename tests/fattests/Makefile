PROJECT=fatwrite
OBJS = $(PROJECT).o fat.o
CFLAGS = -m32

# useful values for a 16 bit fat
FAT?=16
SIZE?=32k

all: $(PROJECT)

$(PROJECT): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS)

%.o: %.c $(DEPS)
	$(CC)  $(CFLAGS) -c -o $@ $<

disk.img: Makefile
# create file system
	dd if=/dev/zero of=part bs=512 count=$(SIZE)
	mkdosfs -F$(FAT) part
	mcopy -o -i part *.c ::/
	mcopy -o -i part *.h ::/
	mcopy -o -i part *.o ::/
	mmd -o -i part ::/TestDIR
	mmd -o -i part ::/LONGTestDIR
# prepend partition table
	dd if=/dev/zero of=ptable bs=512 count=16 2> /dev/null
	cat ptable part > $@
	echo "n\np\n1\n16\n\nt\n6\nw\n" | fdisk -c=dos -C64 -H2 -S16 $@ 
	rm part ptable

check:
	dd if=disk.img of=part bs=512 skip=16 2> /dev/null
	fsck.msdos part
	rm part

dir:
	dd if=disk.img of=part bs=512 skip=16 2> /dev/null
	mdir -i part
	rm part

TESTFILE_LONG=fatwrite
TESTFILE_SHORT=fatwrite.c

# - create a file system with some files inside
# - write a (short) file using fat.c
# - extract and verify that file
# - overwrite the file with a longer one using fat.c
# - extract and verify that file
# - do a file system check

write_test:
# write a short file
	./$(PROJECT) $(TESTFILE_SHORT) "TESTFILEDAT"
	dd if=disk.img of=part bs=512 skip=16 2> /dev/null
	mcopy -o -i part ::/TESTFILE.DAT $(TESTFILE_SHORT).x
	diff $(TESTFILE_SHORT) $(TESTFILE_SHORT).x
	rm part $(TESTFILE_SHORT).x
# overwrite short file with long file
	./$(PROJECT) $(TESTFILE_LONG) "TESTFILEDAT"
	dd if=disk.img of=part bs=512 skip=16 2> /dev/null
	mcopy -o -i part ::/TESTFILE.DAT $(TESTFILE_LONG).x
	diff $(TESTFILE_LONG) $(TESTFILE_LONG).x
	rm part $(TESTFILE_LONG).x
# and overwrite with short file again
	./$(PROJECT) $(TESTFILE_SHORT) "TESTFILEDAT"
	dd if=disk.img of=part bs=512 skip=16 2> /dev/null
	mcopy -o -i part ::/TESTFILE.DAT $(TESTFILE_SHORT).x
	diff $(TESTFILE_SHORT) $(TESTFILE_SHORT).x
	rm part $(TESTFILE_SHORT).x

test16:
	rm disk.img
	make SIZE=32k FAT=16 disk.img
	make write_test
	make check

test32:
	rm disk.img
	make SIZE=66k FAT=32 disk.img
	make write_test
	make check

test: $(PROJECT)
	make test16
	make test32

clean:
	rm -f *~ $(OBJS) $(PROJECT) disk.img
