#!/bin/bash
if [ $# -lt 1 ]; then
    echo "Please provide a asm file name, e.g. bfext"
    exit
fi

while true; do
    ./randomize $1.s $1_rnd.s
    ../../tools/vasm/vasmm68k_mot -m68020 -Fbin -no-opt -o $1.bin -L $1.lst -nosym $1_rnd.s
    if [ $? -ne 0 ]; then
	echo "ASM failed"
	exit
    fi
    RESULT=$1.tg68k.result TG68K_BIN=$1.bin ./tg68k_run --wave=tg68k_run.ghw --ieee-asserts=disable > /dev/null
    RESULT=$1.musashi.result ./m68k_run $1.bin > /dev/null
    diff $1.tg68k.result $1.musashi.result
    if [ $? -ne 0 ]; then
	echo "Test failed"
	../../tools/m68kdis/m68kdis -020 $1.bin
	cat $1.bin.s
	exit
    fi

    if [ $# -eq 2 ]; then
	echo "Force stop"
	exit
    fi

done
