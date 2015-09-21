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

Once installed Quartus will allow you to import the [led.qar](https://github.com/mist-devel/mist-board/raw/master/tutorials/led/led.qar) archive.

Selecting "Start Compilation" from the Processing menu will create the led.rbf
file. Putting this under the name "core.rbf" on sd card and booting the
mist from that card should result in the FPGA led blinking once a second.



