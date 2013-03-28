### programs ###
MAP=quartus_map
FIT=quartus_fit
ASM=quartus_asm
PGM=quartus_pgm

### project ###
PROJECT=mist

TODAY = `date +"%m/%d/%y"`

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

run2: 
	@$(PGM) -c USB-Blaster\(Altera\) -m jtag -o "p;./out/$(PROJECT).sof"

# clean
clean:
	@echo clean
	@rm -rf ./out/
	@rm -rf ./db/
	@rm -rf ./incremental_db/

release:
	make
	cd ./out; cp mist.rbf core.rbf ; cp ../../../../tos/system.fnt .; zip ../../../../www/mist.zip core.rbf system.fnt ; rm core.rbf system.fnt
	cp ../../../www/files.html files.tmp
	sed -e "s|Mist core updated on [0-9/]*.|Mist core updated on $(TODAY).|g" files.tmp > ../../../www/files.html
	rm files.tmp
