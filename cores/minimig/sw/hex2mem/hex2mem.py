#!/usr/bin/env python

# hex2mem.py
# 2012, rok.krajnc@gmail.com


"""Converts ordinary (non-intel format) hex files into Verilog ROMs."""


from __future__ import with_statement
import sys
import os
import math
from optparse import OptionParser


# main
def main():
  """main function"""

  # handle command-line options
  usage = "Usage: %prog [options] in.hex out.v"
  parser = OptionParser(usage=usage)
  parser.add_option("-a", "--address-bits",    dest="aw",     action="store",      default=0,     help="Force use of this many address bits")
  parser.add_option("-s", "--memory-size",     dest="ms",     action="store",      default=0,     help="Force length of memory (number of rows)")
  parser.add_option("-w", "--memory-width",    dest="mw",     action="store",      default=0,     help="Force width of memory (width of a row)")
  parser.add_option("-n", "--no-pad",          dest="nopad",  action="store_true", default=False, help="Do not pad output")
  parser.add_option("-p", "--pad-with-zeroes", dest="padval", action="store_true", default=False, help="Pad with zeroes instead of ones")
  (options, args) = parser.parse_args()

  # parse args
  if (len(args) != 2) : parser.error("Invalid number of arguments.\n")
  fin = args[0]
  fon = args[1]
  modulename = os.path.splitext(os.path.basename(fon))[0]

  # check that files exist
  if (not os.path.isfile(fin)):
    sys.stderr.write("ERROR: could not open source file %s. Cannot continue.\n" % fin)
    sys.exit(-1)

  # test if output file is writeable
  if (not os.access(os.path.dirname(fon), os.W_OK | os.X_OK)):
    sys.stderr.write("ERROR: output directory %s is not writeable, or no such path exists.\n" % os.path.dirname(fon))
    sys.exit(-1)

  # open & read input file
  with open(fin, 'r') as fi:
    dat = fi.readlines()
  dat = [line.strip() for line in dat]

  # calculate needed address width
  aw = int(math.ceil(math.log(len(dat), 2)))
  if options.aw != 0:
    if int(options.aw) < aw:
      sys.stderr.write("ERROR: requested number of address bits is less than required (requested: %d, required: %d).\n" % (int(options.aw), aw))
      sys.exit(-1)
    else:
      aw = int(options.aw)

  # check memory size
  if options.nopad:
    ms = len(dat)
  else:
    ms = 2**aw
  if options.ms != 0:
    if int(options.ms) < ms:
      sys.stderr.write("ERROR: requested memory size is less than required (requested: %d, required: %d).\n" % (int(options.ms), ms))
      sys.exit(-1)
    else:
      ms = int(options.ms)

  # check memory width
  mw = len(max(dat, key=len))
  if options.mw != 0:
    if int(options.mw) < mw:
      sys.stderr.write("ERROR: requested memory width is less than required (requested: %d, required: %d).\n" % (int(options.mw), mw))
      sys.exit(-1)
    else:
      mw = int(options.mw)

  # write Verilog memory file
  # the Verilog code follows Altera guidelines for inferring ROM functions from HDL code (Altera Recommended HDL Coding Styles)
  fmt = "    %d'h%%0%dx : q <= #1 %d'h%%0%dx;\n" % (aw, int(math.ceil((aw+3)/4)), (mw*4), mw)

  with open(fon, 'w') as fo:
    # header
    fo.write(     "/* %s */\n" % os.path.basename(fon))
    fo.write(     "/* AUTO-GENERATED FILE, DO NOT EDIT! */\n")
    fo.write(     "/* generated from %s assembler file */\n\n\n" % fin)
    fo.write(     "module %s (\n" % modulename)
    fo.write(     "  input  wire           clock,\n")
    fo.write(     "  input  wire [ %02d-1:0] address,\n" % (aw))
    fo.write(     "  output reg  [ %02d-1:0] q\n" % (mw*4))
    fo.write(     ");\n\n\n")
    # data
    fo.write(     "always @ (posedge clock) begin\n")
    fo.write(     "  case(address)\n")
    for idx, data in enumerate(dat):
      fo.write(   fmt % (idx, int(data, 16)))
    # padding
    for i in range(ms-idx-1):
      idx = idx+1
      if options.padval:
        fo.write( fmt % (idx, 0))
      else:
        fo.write( fmt % (idx, (1<<(mw*4))-1))
    # footer
    fo.write(     "  endcase\n")
    fo.write(     "end\n\n\n")
    fo.write(     "endmodule\n\n")
 
  # done
  print ("File %s written successfully, using %dx%d memory (%d bits), will be probably inferred into %d Altera M4Ks." % (fon, idx+1, mw*4, (idx+1)*mw*4, int(math.ceil((idx+1)*mw*4/4096))))

# END main


# start
if __name__ == "__main__":
  main()
# END start

