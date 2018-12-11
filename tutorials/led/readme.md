LED
===

This is the verilog pendant to a "Hello World" for the MIST FPGA
board.

This code lets the "Core LED" on the board blink once a second.

This example was published as part of the first article in a series
of three in the german computer magazine c't:

http://www.heise.de/ct/ausgabe/2015-21-Mit-FPGAs-Retro-Chips-implementieren-Teil-1-2811231.html

Getting started
---------------

This example can be used under Windows as well as under Linux.

First of all you need to download the quartus web edition for your operating
system from https://dl.altera.com/?edition=web Please make sure you download
vesion 13.1 as newer versions don't support the Cyclone III FPGA anymore.

To install & run Quartus 13.1 on a modern (64 bits) distribution, you will need to
install 32 bits versions of the following libraries: 
libc6, libstdc++6, libx11-6, libxext6, libxau6, libxdmcp6, libfreetype6, libfontconfig1,
libexpat1, libxrender1, libsm6. For example, on Ubuntu, enter this in a terminal:
```
$ sudo apt install libc6:i386 libstdc++6:i386 libx11-6:i386 libxext6:i386 libxau6:i386 libxdmcp6:i386 libfreetype6:i386 libfontconfig1:i386 libexpat1:i386 libxrender1:i386 libsm6:i386
```
libpng12 is also needed but not available anymore. On Ubuntu, you can get it here instead:

- 32bit: https://packages.ubuntu.com/xenial/i386/libpng12-0/download
- 64bit: https://packages.ubuntu.com/xenial/amd64/libpng12-0/download

Finally, the setup.sh file for Quartus 13.1 shall be run with:
```
$ bash setup.sh
```
Quartus itself can be run with the command (omit --64bit for the 32bit version):
```
$ ~/altera/13.1/quartus/bin/quartus --64bit
```

Once installed Quartus will allow you to import the [led.qar](https://github.com/mist-devel/mist-board/raw/master/tutorials/led/led.qar) archive. Use the qar import by selecting "Restore Archived Project..." from the "Project" menu.

Selecting "Start Compilation" from the "Processing" menu will create the led.rbf
file. Putting this under the name "core.rbf" on sd card and booting the
mist from that card should result in the FPGA led blinking once a second.

![https://github.com/mist-devel/mist-board/raw/master/tutorials/led/quartus.png](https://github.com/mist-devel/mist-board/raw/master/tutorials/led/quartus.png)

Using signaltap
---------------

Signaltap is a very useful tool when developing cores. It allows you to observe
signals directly on the running FPGA. 

You need a cheap usb blaster cable to use this feature. Searching for "usb blaster"
on ebay or amazon should give plenty of matching results.

The blaster cable is connected to the PC via USB. For more information see the
[Wiki](https://github.com/mist-devel/mist-board/wiki/UsingAByteBlaster). You also
need to add a matching connector to your MIST board. Althoug the board is prepared
for this connector you still need to get it soldered to the board. 
