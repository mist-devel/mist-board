#!/usr/bin/python
import sys

trace = sys.stdin #open(sys.argv[1])

first = True
count = 0;

def parseRead(line):
    global count
    if line.find("read") == 0 or line.find("set") == 0:
        tokens = line.replace(',','').split()
        
        if (tokens[0] == 'set'):
            tokens[2]  = int(tokens[2]);
            tokens[3]  = int(tokens[3],16);
            offset = 0
            if (tokens[1] == 'irq'):
                #         addr dat     be  expected offset
                print "2, 0x0, 0x%08x, 0x0, 0x%x, 0x%08x"   % (tokens[3], tokens[2], tokens[3])
            if (tokens[1] == 'firq'):
                print "3, 0x0, 0x%08x, 0x0, 0x%x, 0x%08x"   % (tokens[3], tokens[2], tokens[3])
        
        if (tokens[0] == 'read'):
            tokens[1] = int(tokens[1],16);
            tokens[3] = int(tokens[3],16);
            tokens[5] = int(tokens[5],16);
            if (tokens[1] >= 0x3000000) and (tokens[1] < 0x3800000):
                count+=1
                print "0, 0x%08x, 0x0, 0xf, 0x%08x, 0x%08x"   % (tokens[1],tokens[3], tokens[5])
                #print "\tCheckMEM(26'h%07x,32'h%08x);" % (tokens[1],tokens[3])
                
#print "struct cpuaccess cpuaccesses[] = {"
for line in trace:
    try:
        parseRead(line)
    except:
        pass
    #if count > 10000000:
    #break


trace.close()
