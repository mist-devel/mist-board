SUPPORT=../support/
CHIPSET=../../rtl

COMMON_DIR=../common
COMMON_LDFLAGS=../$(COMMON_DIR)/libcommon.a
COMMON_CFLAGS=-I../$(COMMON_DIR)

SDL_LDFLAGS=-lSDL

common: 
	make -C $(COMMON_DIR)
clean:: 
	make -C $(COMMON_DIR) clean
distclean:: 
	make -C $(COMMON_DIR) distclean