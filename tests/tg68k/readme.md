TG68K GHDL tests
================

Runs TG68K via GHDL for quick debugging and testing. All memory IO is
reported to stdout. For comparison a Musashi (the M68K CPU core of the
MAME emulator) is included.

Type "make vtest" to run tg68k and "make test" to run Musashi.

Running "make view" will open gktview with the tg68k trace.

The test routines are in the tests directory.
