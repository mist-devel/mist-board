#ifndef MEM_H
#define MEM_H

void mem_init(char *name);
unsigned int mem_read(unsigned int addr, int ds);
void mem_write(unsigned int addr, unsigned int data, int ds);

#endif // MEM_H
