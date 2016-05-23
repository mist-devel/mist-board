/* (c) Peter Howkins 2006 - see Readme file for copying info
   with assistance from Tom Walker */
#include "armdefs.h"
#include "cp15.h"

/* VLSI ARM3 VL86C020 */
#define ARM3_CPU_ID                 0x41560300
/* 41 = ARM, 56 = VLSI, 03 = ARM3, 00 = Revision 0 */

#define ARM3_CP15_REG_0_RO_PROCESSOR_ID      0
#define ARM3_CP15_REG_1_WO_FLUSH_CACHE       1
#define ARM3_CP15_REG_2_RW_MISC_CONTROL      2
#define ARM3_CP15_REG_3_RW_CACHABLE_AREAS    3
#define ARM3_CP15_REG_4_RW_UPDATABLE_AREAS   4
#define ARM3_CP15_REG_5_RW_DISRUPTIVE_AREAS  5

struct
{
  ARMword uControlRegister;
  ARMword uCachableAreas;
  ARMword uUpdatableAreas;
  ARMword uDisruptiveAreas;
} ARM3_CP15_Registers;


/**
 * ARM3_Initialise
 *
 * Initialise the ARM3 cpu control coprocessor.
 *
 * @param hState Emulator state
 * @returns Bool of successful initialisation
 */
unsigned ARM3_Initialise(ARMul_State *hState)
{
  ARM3_CP15_Registers.uControlRegister = 0;

  return TRUE;
}

/**
 * ARM3_MRCs
 *
 * Read a value from one of the registers on the
 * ARM3 cpu control coprocessor.
 *
 * @param hState  Emulator state
 * @param uType   Unused
 * @param instr   The raw MRC instruction value (including the CP register number)
 * @param puValue Place to write the value of the CP register
 * @returns ARMul_DONE on success ARMul_CANT when not allowed
 */
unsigned ARM3_MRCs(ARMul_State *hState, unsigned uType, ARMword instr, ARMword *puValue)
{
  unsigned uReg = BITS(16, 19); /* coprocessor register number is stored in the instruction */

  if(ARM3_RegisterRead(hState, uReg, puValue)) {
    return ARMul_DONE;
  } else {
    return ARMul_CANT;
  }
}

/**
 * ARM3_MCRs
 *
 * Write a value to one of the registers on the
 * ARM3 cpu control coprocessor.
 *
 * @param hState Emulator state
 * @param uType  Unused
 * @param instr  The raw MRC instruction value (including the CP register number)
 * @param uValue Value to write to CP register
 * @returns ARMul_DONE on success ARMul_CANT when not allowed
 */
unsigned ARM3_MCRs(ARMul_State *hState, unsigned uType, ARMword instr, ARMword uValue)
{
  unsigned uReg = BITS(16, 19); /* coprocessor register number is stored in the instruction */

  if(ARM3_RegisterWrite(hState, uReg, uValue)) {
    return ARMul_DONE;
  } else {
    return ARMul_CANT;
  }
}

/**
 * ARM3_RegisterRead
 *
 * Read a value from one of the registers on the
 * ARM3 cpu control coprocessor. This is the interface
 * used by the RDI system.
 *
 * @param hState  Emulator state
 * @param uReg    Coprocessor register
 * @param puValue Place to write the value of the CP register
 * @returns TRUE on success, FALSE on disallowed reads
 */
unsigned ARM3_RegisterRead(ARMul_State *hState, unsigned uReg, ARMword *puValue)
{
  switch (uReg) {
    case ARM3_CP15_REG_0_RO_PROCESSOR_ID:
      *puValue = ARM3_CPU_ID;
      break;

    case ARM3_CP15_REG_1_WO_FLUSH_CACHE:
      /* flush cache is a write only register */
      return FALSE;

    case ARM3_CP15_REG_2_RW_MISC_CONTROL:
      *puValue = ARM3_CP15_Registers.uControlRegister;
      break;

    case ARM3_CP15_REG_3_RW_CACHABLE_AREAS:
      *puValue = ARM3_CP15_Registers.uCachableAreas;
      break;

    case ARM3_CP15_REG_4_RW_UPDATABLE_AREAS:
      *puValue = ARM3_CP15_Registers.uUpdatableAreas;
      break;

    case ARM3_CP15_REG_5_RW_DISRUPTIVE_AREAS:
      *puValue = ARM3_CP15_Registers.uDisruptiveAreas;
      break;

    default:
      *puValue = 0;
  }

  return TRUE;
}

/**
 * ARM3_RegisterWrite
 *
 * Write a value to one of the registers on the
 * ARM3 cpu control coprocessor. This is the interface
 * used by the RDI system.
 *
 * @param hState Emulator state
 * @param uReg   Coprocessor register
 * @param uValue Value to write to CP register
 * @returns TRUE on success, FALSE on disallowed reads
 */
unsigned ARM3_RegisterWrite(ARMul_State *hState, unsigned uReg, ARMword uValue)
{
  switch (uReg)
  {
    case ARM3_CP15_REG_0_RO_PROCESSOR_ID:
      /* PROCESSOR ID is read only register */
      return FALSE;

    case ARM3_CP15_REG_1_WO_FLUSH_CACHE:
      /* flush our non-existant cache */
      break;

    case ARM3_CP15_REG_2_RW_MISC_CONTROL:
    {
      /* Bit 0 = Is the cache On or Off? true if On
         Bit 1 = UserMode addr and Non UserMode addr the same? true on MEMC
         Bit 2 = Processor in 'Monitor Mode'? false in normal operation
         Bit X = All other bits resevered */

      /* IMPROVE should we alter the speed of the emulator based on the
         value of the Cache On or Off bit? */

      ARM3_CP15_Registers.uControlRegister = uValue;
      break;
    }
    
    case ARM3_CP15_REG_3_RW_CACHABLE_AREAS:
      ARM3_CP15_Registers.uCachableAreas = uValue;
      break;
    
    case ARM3_CP15_REG_4_RW_UPDATABLE_AREAS:
      ARM3_CP15_Registers.uUpdatableAreas = uValue;
      break;
    
    case ARM3_CP15_REG_5_RW_DISRUPTIVE_AREAS:
      ARM3_CP15_Registers.uDisruptiveAreas = uValue;
      break;
  }

  return TRUE;
}

