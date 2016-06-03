#!/bin/bash
pushd `dirname $0` > /dev/null
PATCHDIR=`pwd -P`
popd > /dev/null
svn revert *.v
rm -f *.rej
rm -f *.orig
svn update
patch --merge  -l -p0 < $PATCHDIR/translate.patch
patch --merge  -l -p0 < $PATCHDIR/data_abt.patch
patch --merge  -l -p0 < $PATCHDIR/testbench.patch
patch --merge  -l -p0 < $PATCHDIR/decodelogic.patch
patch --merge  -l -p0 < $PATCHDIR/cachemod.patch
patch --merge  -l -p0 < $PATCHDIR/buslower.patch
for i in *.v; do cat $i | sed s/\\.v\"/\\.vh\"/g > $i.new; mv $i.new $i; done
for i in *.v; do cat $i | sed s/\`TB_ERROR/\\/\\/\`TB_ERROR/g > $i.new; mv $i.new $i; done
for i in *.v; do cat $i | sed s/\`TB_DEBUG_MESSAGE//g > $i.new; mv $i.new $i; done
for i in *.v; do cat $i | sed '/global_timescale/d' > $i.new; mv $i.new $i; done
rm -f *.orig
for i in *.v; do expand -t 4 $i > $i.new; mv $i.new $i; done
for i in *.v; do $PATCHDIR/transform $i > $i.new; mv $i.new $i; done
svn revert a23_barrel_shift_fpga.v 
svn revert a23_ram_register_bank.v
