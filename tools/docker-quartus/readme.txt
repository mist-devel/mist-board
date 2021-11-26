Create a docker image for quartus 13.1

Heavily based on https://github.com/halfmanhalftaco/fpga-docker, but uses
Ubuntu 18.04 as a base image (no need for a docker hub account).

Usage:
======
Create the docker image with 'make' and start it with 'run-fpga'.

Recomended for newer distros where this old Quartus version doesn't run
flawlessly.