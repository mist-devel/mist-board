#ifndef _ARMCOPRO_H_
#define _ARMCOPRO_H_

typedef enum ArmProcessorType {
  Processor_ARM2,                 // ARM 2                                                                                                                                    
  Processor_ARM250,               // ARM 2AS                                                                                                                                  
  Processor_ARM3                  // ARM 2AS                                                                                                                                  
} ArmProcessorType;

unsigned ARMul_CoProInit(ARMul_State *state, ArmProcessorType ptype);
void ARMul_CoProExit(ARMul_State *state);
void ARMul_CoProAttach(ARMul_State *state, unsigned number,
                              ARMul_CPInits *init, ARMul_CPExits *exits,
                              ARMul_LDCs *ldc, ARMul_STCs *stc,
                              ARMul_MRCs *mrc, ARMul_MCRs *mcr,
                              ARMul_CDPs *cdp,
                              ARMul_CPReads *reads, ARMul_CPWrites *writes);
void ARMul_CoProDetach(ARMul_State *state, unsigned number);

#endif
