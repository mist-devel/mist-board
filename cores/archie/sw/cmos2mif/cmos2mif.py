#!/usr/bin/python

import sys

if len(sys.argv) < 2: 
    print "Usage: %s hexcmos" % (sys.argv[0])
    sys.exit(-1)

data = {}
# initialise the dest
for byte in range(0, 256):
    data[byte] = 0

# read hexcmos
with open(sys.argv[1]) as f:
    content = f.readlines()
    checksum = 1
    i = 0
    for line in content:
        x =  line.strip()
        
        if len(x) == 1:
            x = "0"+x
        y = int(x,16)
        checksum+=y
        
        dest = i + 64
        
        if (dest > 255):
            dest -= 240
        
        data[dest] = y
        i+=1

        if (i == 239):
            break

checksum = checksum % 256

sys.stderr.write("CSUM: %02x\n" % (checksum,))
fo = open("cmos.mif","w")

data[63] = checksum

for i in range(0, 255):
    sys.stdout.write("%02x\n" % (data[i],))    
