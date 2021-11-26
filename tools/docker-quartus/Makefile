TOOL=quartus131

INSTALLER_URL=http://download.altera.com/akdlm/software/acdsinst/13.1/162/ib_tar/Quartus-web-13.1.0.162-linux.tar
UPDATE_URL=http://download.altera.com/akdlm/software/acdsinst/13.1.4/182/update/QuartusSetup-13.1.4.182.run
INSTALLER=Quartus-web-13.1.0.162-linux.tar
UPDATE=QuartusSetup-13.1.4.182.run
INSTALLER_CHECKSUM=BA705F9D15F3A43AB7E86D297F394EE3
UPDATE_CHECKSUM=172C8CD0EB631B988516F1182054F976

FILES=$(INSTALLER) $(UPDATE) Dockerfile

all: container-image-built

${INSTALLER}:
#	curl -O $(INSTALLER_URL)
	wget $(INSTALLER_URL)
	@SUM=$$(md5sum $(INSTALLER) | awk '{print toupper($$1)}'); \
        if [ "$$SUM" != "$(INSTALLER_CHECKSUM)" ]; then echo "Installer checksum doesn't match."; exit 1; fi
	
${UPDATE}:
#	curl -O $(UPDATE_URL)
	wget $(UPDATE_URL)
	@SUM=$$(md5sum $(UPDATE) | awk '{print toupper($$1)}'); \
        if [ "$$SUM" != "$(UPDATE_CHECKSUM)" ]; then echo "Updater checksum doesn't match."; exit 1; fi	

container-image-built: $(FILES)
	@docker rmi fpga:$(TOOL) &>/dev/null || true
	@docker build -t fpga:$(TOOL) --build-arg "TOOL=$(TOOL)" .
	@touch $@

.PHONY: clean
clean:
	docker rmi fpga:$(TOOL) >&/dev/null || true
	rm -f container-image-built
