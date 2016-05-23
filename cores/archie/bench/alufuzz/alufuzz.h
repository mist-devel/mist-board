#ifndef _ALUFUZZ_H_
#define _ALUFUZZ_H_


#include <string>
#include <iostream>
#include <iomanip>

#define fhex(_v) std::setw(_v) << std::hex << std::setfill('0')


#define NOP 0xe1a00000
#define TERMSWI 0xefffffff

static const char *const reg_names[] = {"r0","r1","r2","r3","r4","r5","r6","r7","r8","r9","r10","r11","r12","r13","r14","r15",
								"r8_firq","r9_firq","r10_firq","r11_firq","r12_firq","r13_firq","r14_firq",
								"r13_irq","r14_irq","r13_svc","r14_svc"};

static const char *const aluop[] = {
	"and", "eor", "sub", "rsb", "add", "adc", "sbc", "rsc",
	"tst", "teq", "cmp", "cmn", "orr", "mov", "bic", "mvn"
};

#endif
