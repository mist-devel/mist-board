#!/usr/bin/python
import sys
lastline = False
last = ""
for line in sys.stdin:
    thisline = line.startswith("r0 ")
    swi = lastline and (line.strip() == "8")
    inter = lastline and (line.strip() == "18")
    if (inter or swi or (thisline and lastline)):
        last = line.strip()
        lastline = thisline
        continue
    lastline = thisline
    print last
    last = line.strip()
