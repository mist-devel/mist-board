# MINIMIG-DE1
# top makefile
# 2012, rok.krajnc@gmail.com


### paths ###
REL_DIR=rel
AMIGA_BOOT_DIR=fw/amiga_boot
FPGA_DIR=fpga/altera

TODAY = `date +"%m/%d/%y"`

### files ###
CTRL_FW=$(CTRL_FW_DIR)/bin/de1_boot.bin
CTRL_BOOT=$(CTRL_BOOT_DIR)/bin/de1_boot.bin
AMIGA_BOOT=$(AMIGA_BOOT_DIR)/bin/amiga_boot.v
FPGA=$(FPGA_DIR)/out/minimig_mist.rbf

### build rules ###
BUILD_OPT=clean all

# all
all:
	@echo Building all ...
	@mkdir -p $(REL_DIR)
	@make amiga_boot
	@make fpga

amiga_boot: Makefile 
	@echo Building amiga boot firmware in $(AMIGA_BOOT_DIR) ...
	@$(MAKE) -C $(AMIGA_BOOT_DIR) $(BUILD_OPT)
	@cp $(AMIGA_BOOT) $(REL_DIR)/

fpga: Makefile 
	@echo Building FPGA in $(FPGA_DIR) ...
	@$(MAKE) -C $(FPGA_DIR) $(BUILD_OPT)

# clean
clean:
	@echo Clearing release dir ...
	@rm -rf $(REL_DIR)
	@$(MAKE) -C $(AMIGA_BOOT_DIR) clean
	@$(MAKE) -C $(FPGA_DIR) clean

release:
	make
	cd $(FPGA_DIR)/out; cp minimig_mist.rbf core.rbf ; zip ../../../../../../www/minimig_mist.zip core.rbf ; rm core.rbf
	cp ../../../www/files.html files.tmp
	sed -e "s|Minimig core updated on [0-9/]*.|Minimig core updated on $(TODAY).|g" files.tmp > ../../../www/files.html
	rm files.tmp
