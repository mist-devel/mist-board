# MINIMIG-DE1
# fpga makefile
# 2012, rok.krajnc@gmail.com


### programs ###
MAP=quartus_map
FIT=quartus_fit
ASM=quartus_asm
PGM=quartus_pgm

### project ###
PROJECT=minimig_mist


### build rules ###

# all
all:
	@echo Making FPGA programming files ...
	@make map
	@make fit
	@make asm

map:
	@echo Running mapper ...
	@$(MAP) $(PROJECT)

fit:
	@echo Running fitter ...
	@$(FIT) $(PROJECT)

asm:
	@echo Running assembler ...
	@$(ASM) $(PROJECT)

run: 
	@$(PGM) -c USB-Blaster -m jtag -o "p;./out/$(PROJECT).sof"

# clean
clean:
	@echo clean
	@rm -rf ./out/
	@rm -rf ./db/
	@rm -rf ./incremental_db/

