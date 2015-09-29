#!/bin/bash
TOOLS=../../../../tools

if [ "$#" -ne 1 ]; then
    echo "Test name missing"
    exit
fi

cp tos_template.s tos_$1.s
perl -i -pe "s/test.s/..\/tests\/$1.s/" tos_$1.s

echo "Assembling test $1"
${TOOLS}/vasm/vasmm68k_mot -m68020 -o tos_$1.tos -Ftos -nosym tos_$1.s

echo "Running in hatari"
hatari -d . tos_$1.tos
