Tests
=====

Code used to test parts of the Plus Too code.

floppy_track_encoder
--------------------

Verilator simulation of the initial versions of the live floppy GCR encoder. The simulation runs the encoder against a pre-encoded file created using the encoding tool from the original Plus Too project. The latest encoder used in the MIST port of the Plus Too core has been further improved and does generate a signal different from the original one due to sector interleaving and shorter inter sector gaps.

minivmac-scsi-hdl
-----------------

This is a version of the MiniVMac emulator linked agains a verilator simulation of the ncr5380 and the SCSI implementions of the MIST version of the Plus Too core. This allows to run the actual SCSI related hardware code inside the emulator. MiniVMAC can fully access the SCSI harddisk implemented this way, can read and write data, boot from SCSI disk and even use the MacOS setup tool to format the SCSI disk and install a SCSI driver and the OS itself.
