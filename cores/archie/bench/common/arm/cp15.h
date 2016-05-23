/* (c) Peter Howkins 2006 - see Readme file for copying info */
/*
  Coprocessor 15 on an ARM processor is reserved by ARM to be the
  CPU control processor. Introduced with the ARM3 it allowed control
  of cache. Later ARMs use it to control the MMU as well.

  To succesfully emulate an ARM3 or later you need coprocessor 15
  emulation.

  ARM3 cp15 description
  http://www.home.marutan.net/arcemdocs/arm3.txt

  ARM3/ARM610/ARM710/SA110 cp15 description
  http://www.heyrick.co.uk/assembler/coprocmnd.html

  MCR and MRC instruction formats
  http://www.pinknoise.demon.co.uk/ARMinstrs/ARMinstrs.html#CoproOp

 */

 
/**
 * ARM3_Initialise
 *
 * Initialise the ARM3 cpu control coprocessor.
 *
 * @param hState Emulator state
 * @returns Bool of successful initialisation
 */
unsigned ARM3_Initialise(ARMul_State *state);

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
unsigned ARM3_MRCs(ARMul_State *state, unsigned type, ARMword instr, ARMword *value);

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
unsigned ARM3_MCRs(ARMul_State *state, unsigned type, ARMword instr, ARMword value);

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
unsigned ARM3_RegisterRead(ARMul_State *state, unsigned reg, ARMword *value);

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
unsigned ARM3_RegisterWrite(ARMul_State *state, unsigned reg, ARMword value);
