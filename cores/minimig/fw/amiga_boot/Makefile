# MINIMIG-DE1
# amiga boot firmware
# 2012, rok.krajnc@gmail.com


### paths ###
# clear dir vars if these programs are in path
VASM_DIR    = ../../sw/vasm/
HEX2MEM_DIR = ../../sw/hex2mem/
HEX2MIF_DIR = ../../sw/hex2mif/


### programs ###
VASM    = $(VASM_DIR)vasmm68k_mot
XXD     = xxd
HEX2MEM = $(HEX2MEM_DIR)hex2mem.py
HEX2MIF = $(HEX2MIF_DIR)hex2mif.py


### flags ###
ASMFLAGS=-m68000 -showopt -Fbin
XXDFLAGS=-ps -c 2
HEXFLAGS=-a 8 -s 256 -w 4


### variables ###
BUILD_USER=\"$(USER)\"
BUILD_T=$$(date +%Y-%m-%d)
BUILD_TIME=\"$(BUILD_T)\"
BUILD_N=$$(cat build_num.txt)
BUILD_NUM=\"$(BUILD_N)\"
BUILD_R=$$(git rev-parse --verify HEAD)
BUILD_REV=\"$(BUILD_R)\"

BINDIR=bin
OBJDIR=obj


### files ###

# asm sources
ASM_SOURCES=amiga_boot.asm


### build rules ###

# all
all:
	@echo Making amiga_boot firmware ...
	@make bin
	@make bin/amiga_boot.v
	@make bin/amiga_boot.mif

bin:
	@echo $@
	@mkdir -p $(BINDIR)

bin/amiga_boot.bin : Makefile bin $(ASM_SOURCES)
	@echo $@
	@$(VASM) $(ASMFLAGS) $(ASM_SOURCES) -o $@

bin/amiga_boot.hex : Makefile bin bin/amiga_boot.bin
	@echo $@
	@$(XXD) $(XXDFLAGS) $(@:.hex=.bin) > $@

bin/amiga_boot.v : Makefile bin bin/amiga_boot.hex
	@echo $@
	@$(HEX2MEM) $(HEXFLAGS) $(@:.v=.hex) $@

bin/amiga_boot.mif : bin/amiga_boot.hex
	@echo $@
	@$(HEX2MIF) -w 16 $(@:.mif=.hex) $@

# clean
clean:
	@echo clean
	@rm -rf ./$(BINDIR)

