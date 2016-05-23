#!/usr/bin/python
import sys
trace = open(sys.argv[1])

def parseAddress(line):
    if line.find(":") > 0:
        print line.split()[1].replace(":","")

def parseRead(line):
    if line.find("read") > 0:
        tokens = line.replace(',','').split()
        print tokens[1],tokens[3],tokens[4],tokens[5],tokens[6],tokens[7]
    if line.find("write") > 0:
        tokens = line.replace(',','').split()
        print tokens[1],tokens[3],tokens[4],tokens[5],tokens[6],tokens[7]
    if line.find("jump") > 0:
        tokens = line.replace(',','').split()[6:]
        regs = ""
        for i in range(0,28,2):
            regs = regs + "%s %s" % (tokens[i], tokens[i+1])
            #if i < 26:
            regs = regs + ","
        regs += "%s %s" % (tokens[30], tokens[31])
        print regs

for line in trace:
    parseAddress(line)
    parseRead(line)

trace.close()
