/* dummy for fat tests */

#include <stdint.h>
#define RAMFUNC

unsigned char MMC_ReadMultiple(unsigned long lba, unsigned char *pReadBuffer, unsigned long nBlockCount);
unsigned char MMC_Read(unsigned long lba, unsigned char *pReadBuffer) RAMFUNC;
unsigned char MMC_Write(unsigned long lba, unsigned char *pWriteBuffer);
unsigned char MMC_CheckCard();
