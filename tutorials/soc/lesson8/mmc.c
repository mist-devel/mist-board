/*------------------------------------------------------------------------/
/  Bitbanging MMCv3/SDv1/SDv2 (in SPI mode) control module for PFF
/  Modified to support the Z80 SoC hardware spi interface
/-------------------------------------------------------------------------/
/
/  Copyright (C) 2014, ChaN, all right reserved.
/
/ * This software is a free software and there is NO WARRANTY.
/ * No restriction on use. You can use, modify and redistribute it for
/   personal, non-profit or commercial products UNDER YOUR RESPONSIBILITY.
/ * Redistributions of source code must retain the above copyright notice.
/
/--------------------------------------------------------------------------/
*/

#include "diskio.h"

static unsigned char buffer[512];
static DWORD buffer_sector = 0xffffffff;

// SPI data is read and written via port 0. Writing to the port starts a spi transfer, 
// reading the port returns the last byte received during a transfer but doesn't start
// a transfer by itself
__sfr __at 0x00 DataPort;

// SPI control port is a single write only port bit used for spi select (ss)
__sfr __at 0x01 ControlPort;

void dly_us(unsigned int n) {
  while(n--) {};
}

void forward(BYTE n) {
}

/*-------------------------------------------------------------------------*/
/* Platform dependent macros and functions needed to be modified           */
/*-------------------------------------------------------------------------*/

#define	INIT_PORT()	init_port()	/* Initialize MMC control port (CS/CLK/DI:output, DO:input) */
#define DLY_US(n)	dly_us(n)	/* Delay n microseconds */
#define	FORWARD(d)	forward(d)	/* Data in-time processing function (depends on the project) */

#define	CS_H()		ControlPort=1	/* Set MMC CS "high" */
#define CS_L()		ControlPort=0	/* Set MMC CS "low" */

/*--------------------------------------------------------------------------

   Module Private Functions

---------------------------------------------------------------------------*/

/* Definitions for MMC/SDC command */
#define CMD0	(0x40+0)	/* GO_IDLE_STATE */
#define CMD1	(0x40+1)	/* SEND_OP_COND (MMC) */
#define	ACMD41	(0xC0+41)	/* SEND_OP_COND (SDC) */
#define CMD8	(0x40+8)	/* SEND_IF_COND */
#define CMD16	(0x40+16)	/* SET_BLOCKLEN */
#define CMD17	(0x40+17)	/* READ_SINGLE_BLOCK */
#define CMD24	(0x40+24)	/* WRITE_BLOCK */
#define CMD55	(0x40+55)	/* APP_CMD */
#define CMD58	(0x40+58)	/* READ_OCR */

/* Card type flags (CardType) */
#define CT_MMC				0x01	/* MMC ver 3 */
#define CT_SD1				0x02	/* SD ver 1 */
#define CT_SD2				0x04	/* SD ver 2 */
#define CT_SDC				(CT_SD1|CT_SD2)	/* SD */
#define CT_BLOCK			0x08	/* Block addressing */

static
BYTE CardType;			/* b0:MMC, b1:SDv1, b2:SDv2, b3:Block addressing */

/*-----------------------------------------------------------------------*/
/* Transmit a byte to the MMC via SPI                                    */
/*-----------------------------------------------------------------------*/

#define XMIT_MMC(a)  DataPort=a

/*-----------------------------------------------------------------------*/
/* Receive a byte from the MMC (bitbanging)                              */
/*-----------------------------------------------------------------------*/

static
BYTE rcvr_mmc (void)
{
  DataPort = 0xff;
  
  // some additional delay to give spi transmitter some
  // time to finish
  __asm
    nop 
    nop 
  __endasm;

  return DataPort;
}

/*-----------------------------------------------------------------------*/
/* Skip bytes on the MMC (bitbanging)                                    */
/*-----------------------------------------------------------------------*/

static
void skip_mmc (
	UINT n		/* Number of bytes to skip */
)
{
	do {
	  DataPort = 0xff;
	} while (--n);
}



/*-----------------------------------------------------------------------*/
/* Deselect the card and release SPI bus                                 */
/*-----------------------------------------------------------------------*/

static
void release_spi (void)
{
	CS_H();
	rcvr_mmc();
}


/*-----------------------------------------------------------------------*/
/* Send a command packet to MMC                                          */
/*-----------------------------------------------------------------------*/

static
BYTE send_cmd (
	BYTE cmd,		/* Command byte */
	DWORD arg		/* Argument */
)
{
	BYTE n, res;


	if (cmd & 0x80) {	/* ACMD<n> is the command sequense of CMD55-CMD<n> */
		cmd &= 0x7F;
		res = send_cmd(CMD55, 0);
		if (res > 1) return res;
	}

	/* Select the card */
	CS_H(); rcvr_mmc();
	CS_L(); rcvr_mmc();

	/* Send a command packet */
	XMIT_MMC(cmd);					/* Start + Command index */
	XMIT_MMC((BYTE)(arg >> 24));	/* Argument[31..24] */
	XMIT_MMC((BYTE)(arg >> 16));	/* Argument[23..16] */
	XMIT_MMC((BYTE)(arg >> 8));		/* Argument[15..8] */
	XMIT_MMC((BYTE)arg);			/* Argument[7..0] */
	n = 0x01;						/* Dummy CRC + Stop */
	if (cmd == CMD0) n = 0x95;		/* Valid CRC for CMD0(0) */
	if (cmd == CMD8) n = 0x87;		/* Valid CRC for CMD8(0x1AA) */
	XMIT_MMC(n);

	/* Receive a command response */
	n = 10;								/* Wait for a valid response in timeout of 10 attempts */
	do {
		res = rcvr_mmc();
	} while ((res & 0x80) && --n);

	return res;			/* Return with the response value */
}



/*--------------------------------------------------------------------------

   Public Functions

---------------------------------------------------------------------------*/


/*-----------------------------------------------------------------------*/
/* Initialize Disk Drive                                                 */
/*-----------------------------------------------------------------------*/

DSTATUS disk_initialize (void)
{
	BYTE n, cmd, ty, buf[4];
	UINT tmr;

	CS_H();
	skip_mmc(10);			/* Dummy clocks */

	ty = 0;
	if (send_cmd(CMD0, 0) == 1) {			/* Enter Idle state */
		if (send_cmd(CMD8, 0x1AA) == 1) {	/* SDv2 */
			for (n = 0; n < 4; n++) buf[n] = rcvr_mmc();	/* Get trailing return value of R7 resp */
			if (buf[2] == 0x01 && buf[3] == 0xAA) {			/* The card can work at vdd range of 2.7-3.6V */
				for (tmr = 1000; tmr; tmr--) {				/* Wait for leaving idle state (ACMD41 with HCS bit) */
					if (send_cmd(ACMD41, 1UL << 30) == 0) break;
					DLY_US(1000);
				}
				if (tmr && send_cmd(CMD58, 0) == 0) {		/* Check CCS bit in the OCR */
					for (n = 0; n < 4; n++) buf[n] = rcvr_mmc();
					ty = (buf[0] & 0x40) ? CT_SD2 | CT_BLOCK : CT_SD2;	/* SDv2 (HC or SC) */
				}
			}
		} else {							/* SDv1 or MMCv3 */
			if (send_cmd(ACMD41, 0) <= 1) 	{
				ty = CT_SD1; cmd = ACMD41;	/* SDv1 */
			} else {
				ty = CT_MMC; cmd = CMD1;	/* MMCv3 */
			}
			for (tmr = 1000; tmr; tmr--) {			/* Wait for leaving idle state */
				if (send_cmd(cmd, 0) == 0) break;
				DLY_US(1000);
			}
			if (!tmr || send_cmd(CMD16, 512) != 0)			/* Set R/W block length to 512 */
				ty = 0;
		}
	}
	CardType = ty;
	release_spi();

	return ty ? 0 : STA_NOINIT;
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
        BYTE *buff_sec = buffer;
	DRESULT res;
	BYTE d;
	UINT bc, tmr;

	if (!(CardType & CT_BLOCK)) sector *= 512;	/* Convert to byte address if needed */

	// check if sector is already in sector buffer
	if(buffer_sector == sector) {
	  buff_sec += offset;  // skip to requested bytes
	  while(count--)
	    *buff++ = *buff_sec++;

	  return RES_OK;
	}

	res = RES_ERROR;
	if (send_cmd(CMD17, sector) == 0) {		/* READ_SINGLE_BLOCK */

		tmr = 1000;
		do {							/* Wait for data packet in timeout of 100ms */
			DLY_US(100);
			d = rcvr_mmc();
		} while (d == 0xFF && --tmr);

		if (d == 0xFE) {				/* A data packet arrived */
			// if the whole sector is being read we assume that it
			// will not be needed again and we won't cache it
		        if((!offset) && (count == 512)) {
			  BYTE c;
			  for(c=0;c<64;c++) {
			    *buff++ = rcvr_mmc();
			    *buff++ = rcvr_mmc();
			    *buff++ = rcvr_mmc();
			    *buff++ = rcvr_mmc();
			    *buff++ = rcvr_mmc();
			    *buff++ = rcvr_mmc();
			    *buff++ = rcvr_mmc();
			    *buff++ = rcvr_mmc();
			  }
			  skip_mmc(2);

			} else {
			  bc = 512 - offset - count;

			  /* Skip leading bytes (store in buffer only) */
			  while(offset--)
			    *buff_sec++ = rcvr_mmc();
			  
			  /* Receive a part of the sector */
			  if (buff) {	/* Store data to the memory */
			    do
			      *buff_sec++ = *buff++ = rcvr_mmc();
			    while (--count);
			  } else {	/* Forward data to the outgoing stream */
			    do {
			      *buff_sec++ = d = rcvr_mmc();
			      FORWARD(d);
			    } while (--count);
			  }

			  /* Skip trailing bytes (store in buffer only) */
			  while(bc--)
			    *buff_sec++ = rcvr_mmc();
			
			  /* and skip crc */
			  skip_mmc(2);

			  buffer_sector = sector;
			}

			res = RES_OK;
		}
	}

	release_spi();

	return res;
}

