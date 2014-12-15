/*-------------------------------------------------------------------------*/
/* PFF - Low level disk control module for PIC            (C)ChaN, 2014    */
/*-------------------------------------------------------------------------*/

#include "pff.h"
#include "diskio.h"

//#include "printf.h"

/*-------------------------------------------------------------------------*/
/* Platform dependent macros and functions needed to be modified           */
/*-------------------------------------------------------------------------*/

#include <stdio.h>

#define SELECT() mmcChipSelect(1)
#define	DESELECT() mmcChipSelect(0)

unsigned char mmc_sector_buffer[512];

extern u32 n_actual_mmc_sector;

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
#define CT_BLOCK			0x08	/* Block addressing */

BYTE CardType;


extern int debug_pos;

void disk_debug()
{
/*	{
		char buffer[512];
		set_pause_6502(1);
		freeze();
		debug_pos = 0;	

		printf("Hello world 5");
		debug_pos = 40;

		printf("Di");

		debug_pos = 80;
		disk_initialize();

		printf("Did:%02x",CardType);

		debug_pos = 120;

		n_actual_mmc_sector = -1;
		printf(" PP");
		disk_readp(&buffer[0],0,0,512);
		printf(" DD");
		hexdump_pure(&buffer[0],512);

		wait_us(10000000);
		restore();
	}
*/
}

/*-----------------------------------------------------------------------*/
/* Send a command packet to the SDC/MMC                                  */
/*-----------------------------------------------------------------------*/

static
BYTE send_cmd (
	BYTE cmd,		/* 1st byte (Start + Index) */
	DWORD arg		/* Argument (32 bits) */
)
{
	BYTE n, res;


	if (cmd & 0x80) {	/* ACMD<n> is the command sequense of CMD55-CMD<n> */
		cmd &= 0x7F;
		res = send_cmd(CMD55, 0);
		if (res > 1) return res;
	}

	/* Select the card */
	DESELECT();
	spiTransferFF();
	SELECT();
	spiTransferFF();

	/* Send a command packet */
	spiTransferByte(cmd);						/* Start + Command index */
	spiTransferByte((BYTE)(arg >> 24));		/* Argument[31..24] */
	spiTransferByte((BYTE)(arg >> 16));		/* Argument[23..16] */
	spiTransferByte((BYTE)(arg >> 8));			/* Argument[15..8] */
	spiTransferByte((BYTE)arg);				/* Argument[7..0] */
	n = 0x01;							/* Dummy CRC + Stop */
	if (cmd == CMD0) n = 0x95;			/* Valid CRC for CMD0(0) */
	if (cmd == CMD8) n = 0x87;			/* Valid CRC for CMD8(0x1AA) */
	spiTransferByte(n);

	/* Receive a command response */
	n = 10;								/* Wait for a valid response in timeout of 10 attempts */
	do {
		res = spiTransferFF();
	} while ((res & 0x80) && --n);

	//	printf("cmd(%x) = %x\n", cmd, res);

	return res;			/* Return with the response value */
}




/*--------------------------------------------------------------------------

   Public Functions

---------------------------------------------------------------------------*/

/*-----------------------------------------------------------------------*/
/* Initialize Disk Drive                                                 */
/*-----------------------------------------------------------------------*/

void mmc_init (void)
{
	BYTE n, cmd, ty, ocr[4];
	UINT tmr;

	// initialize SPI interface
	spiInit();

	DESELECT();
	for (n = 10; n; n--) spiTransferFF();	/* 80 Dummy clocks with CS=H */

	ty = 0;
	if (send_cmd(CMD0, 0) == 1) {			/* Enter Idle state */
		if (send_cmd(CMD8, 0x1AA) == 1) {	/* SDv2 */
		  for (n = 0; n < 4; n++) {
		    ocr[n] = spiTransferFF();		/* Get trailing return value of R7 resp */
		    //		    printf("OCR[%d]=%x\n", n, ocr[n]);
		  }
			if (ocr[2] == 0x01 && ocr[3] == 0xAA) {			/* The card can work at vdd range of 2.7-3.6V */
				for (tmr = 10000; tmr && send_cmd(ACMD41, 1UL << 30); tmr--) wait_us(100);	/* Wait for leaving idle state (ACMD41 with HCS bit) */
				if (tmr && send_cmd(CMD58, 0) == 0) {		/* Check CCS bit in the OCR */
				  for (n = 0; n < 4; n++) {
				    ocr[n] = spiTransferFF();
				    //				    printf("OCR[%d]=%x\n", n, ocr[n]);
				  }
					ty = (ocr[0] & 0x40) ? CT_SD2 | CT_BLOCK : CT_SD2;	/* SDv2 (HC or SC) */
				}
			}
		} else {							/* SDv1 or MMCv3 */
			if (send_cmd(ACMD41, 0) <= 1) 	{
				ty = CT_SD1; cmd = ACMD41;	/* SDv1 */
			} else {
				ty = CT_MMC; cmd = CMD1;	/* MMCv3 */
			}
			for (tmr = 10000; tmr && send_cmd(cmd, 0); tmr--) wait_us(100);	/* Wait for leaving idle state */
			if (!tmr || send_cmd(CMD16, 512) != 0)			/* Set R/W block length to 512 */
				ty = 0;
		}
	}
	CardType = ty;
	DESELECT();
	spiTransferFF();

	//	printf("TYPE=%x\n", ty);
}



/*-----------------------------------------------------------------------*/
/* Read partial sector                                                   */
/*-----------------------------------------------------------------------*/

u08 mmcRead(u32 sector)
{
	BYTE rc;
	UINT bc;
	int res = 0;

	//	printf("mr:%x",sector);

	if (!(CardType & CT_BLOCK)) sector *= 512;	/* Convert to byte address if needed */

	if (send_cmd(CMD17, sector) == 0) {		/* READ_SINGLE_BLOCK */

		bc = 40000;
		do {							/* Wait for data packet */
			rc = spiTransferFF();
		} while (rc == 0xFF && --bc);

		if (rc == 0xFE) {				/* A data packet arrived */
			bc = 514 - 512;

			u08 *buffer=mmc_sector_buffer;	//natvrdo!

			spiReceiveData(buffer,buffer+512);
			//			hexdump(buffer, 512, 0);

			/* Skip remaining bytes and CRC */
			do spiTransferFF(); while (--bc); // checksum
		}
	}
	else
	{
		res = 1;
	}

	DESELECT();
	spiTransferFF();
	//	printf("done\n");
	return res;
}



/*-----------------------------------------------------------------------*/
/* Write partial sector                                                  */
/*-----------------------------------------------------------------------*/

u08 mmcWrite(u32 sc)
{
	u08 *buff=mmc_sector_buffer;	//natvrdo!

	WORD wc;

	SELECT();

	if (!(CardType & CT_BLOCK)) sc *= 512;	/* Convert to byte address if needed */
	if (send_cmd(CMD24, sc) == 0) {			/* WRITE_SINGLE_BLOCK */
		spiTransferByte(0xFF); spiTransferByte(0xFE);		/* Data block header */
		wc = 512;							/* Set byte counter */

		while (wc) {		/* Send data bytes to the card */
			spiTransferByte(*buff++);
			wc--; 
		}

		DWORD bc = 2;
		while (bc--) spiTransferByte(0);	/* Fill left bytes and CRC with zeros */
		if ((spiTransferFF() & 0x1F) == 0x05) {	/* Receive data resp and wait for end of write process in timeout of 500ms */
			for (bc = 5000; spiTransferFF() != 0xFF && bc; bc--) wait_us(100);	/* Wait ready */
		}
		DESELECT();
		spiTransferFF();
	}
	return 0;
}
