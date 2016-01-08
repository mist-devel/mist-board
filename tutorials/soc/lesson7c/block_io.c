/*------------------------------------------------------------------------/
/ block_io.c
/
/ simple block_io layer for MIST board. Can be used as a replacement for 
/ mmc.
/
/ This code is in the public domain
/ (c) 2016 by Till Harbaum
/--------------------------------------------------------------------------/
*/

#include "diskio.h"

// block io registers implemented in block_io.v
__sfr __at 0x00 LBA0Port;
__sfr __at 0x01 LBA1Port;
__sfr __at 0x02 LBA2Port;
__sfr __at 0x03 LBA3Port;
__sfr __at 0x04 ControlPort;
__sfr __at 0x05 DataPort;

/*--------------------------------------------------------------------------

   Public Functions

---------------------------------------------------------------------------*/

/*-----------------------------------------------------------------------*/
/* Initialize Disk Drive                                                 */
/*-----------------------------------------------------------------------*/

DSTATUS disk_initialize (void) {
  return RES_OK;
}

/*-----------------------------------------------------------------------*/
/* Read partial sector                                                   */
/*-----------------------------------------------------------------------*/

DRESULT disk_readp (
	BYTE *buff,		/* Pointer to the read buffer (NULL:Read bytes are forwarded to the stream) */
	DWORD sector,	/* Sector number (LBA) */
	UINT offset,	/* Byte offset to read from (0..511) */
	UINT count		/* Number of bytes to read (ofs + cnt mus be <= 512) */
)
{
  static BYTE buffer[512];
  static DWORD buffer_sector = 0xffffffff;
  BYTE *p;

  // check if sector is already in buffer
  if(buffer_sector != sector) {
    BYTE cnt;

    // need to load sector into buffer

    // write 32 bit sector address into block_io controller
    LBA0Port = (sector >> 24) & 0xff;
    LBA1Port = (sector >> 16) & 0xff;
    LBA2Port = (sector >>  8) & 0xff;
    LBA3Port = (sector >>  0) & 0xff;

    // trigger read
    ControlPort = 0x01;

    // wait for data to be ready
    while(ControlPort & 1);

    // read data
    p=buffer;
    for(cnt=0;cnt<128;cnt++) {
      *p++ = DataPort;
      *p++ = DataPort;
      *p++ = DataPort;
      *p++ = DataPort;
    }

    buffer_sector = sector;
  }

  // return data from sector buffer
  p = buffer + offset;
  while(count--)
    *buff++ = *p++;
  
  return RES_OK;
}

