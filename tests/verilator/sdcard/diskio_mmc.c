#include "diskio.h"

#include "mmc.h"
#include "spi.h"

//#include "printf.h"

void mmcReadCached(u32 sector);
u32 n_actual_mmc_sector;
extern unsigned char mmc_sector_buffer[512];

void mmcReadCached(u32 sector)
{
	//debug("mmcReadCached");
	//plotnext(toatarichar(' '));
	//plotnextnumber(sector);
	//debug("\n");
	if(sector==n_actual_mmc_sector) return;
	//debug("mmcReadREAL");
	//plotnext(toatarichar(' '));
	//plotnextnumber(sector);
	//debug("\n");

	u08 ret,retry;
	//predtim nez nacte jiny, musi ulozit soucasny
	// TODO mmcWriteCachedFlush();
	//az ted nacte novy
	retry=0; //zkusi to maximalne 256x
	do
	{
		ret = mmcRead(sector);	//vraci 0 kdyz ok
		retry--;
	} while (ret && retry);
	while(ret); //a pokud se vubec nepovedlo, tady zustane zablokovany cely SDrive!
	n_actual_mmc_sector=sector;
}



/*-----------------------------------------------------------------------*/
/* Initialize Disk Drive                                                 */
/*-----------------------------------------------------------------------*/

DSTATUS disk_initialize (void)
{
	DSTATUS stat;

	//printf(" in init ");
	n_actual_mmc_sector = 0xffffffff;
	for(;;)
	{
		mmc_init();
		if (0==mmcRead(1))
			break;
	}

	//printf(" setting freq ");

	set_spi_clock_freq();

	stat = RES_OK;

	return stat;
}



/*-----------------------------------------------------------------------*/
/* Read Partial Sector                                                   */
/*-----------------------------------------------------------------------*/

DRESULT disk_readp (
	BYTE* dest,			/* Pointer to the destination object */
	DWORD sector,		/* Sector number (LBA) */
	WORD sofs,			/* Offset in the sector */
	WORD count			/* Byte count (bit15:destination) */
)
{
	DRESULT res;

	/*debug("readp:");
	plotnextnumber(sector);
	debug(" ");
	plotnextnumber((int)dest);
	debug(" ");
	plotnextnumber(sofs);
	debug(" ");
	plotnextnumber(count);
	debug(" ");
	plotnextnumber(atari_sector_buffer);
	debug(" ");
	plotnextnumber(mmc_sector_buffer);
	debug("\n");
	*/
	// Put your code here
	mmcReadCached(sector);
	for(;count>0;++sofs,--count)
	{
		unsigned char x = mmc_sector_buffer[sofs];
		//printf("char:%c loc:%d ", x,sofs);
		*dest++ = x;
	}

	res = RES_OK;

	return res;
}



/*-----------------------------------------------------------------------*/
/* Write Partial Sector                                                  */
/*-----------------------------------------------------------------------*/

DRESULT disk_writep (const BYTE* buff, DWORD sofs, DWORD count)
{
	DRESULT res;

	int i=sofs;
	int end=sofs+count;
	int pos = 0;
	for (;i!=end;++i,++pos)
	{
		mmc_sector_buffer[i] = buff[pos];
		//printf("char:%c loc:%d,", buff[pos],i);
	}

	res = RES_OK;

	return res;
}

void disk_writeflush()
{
	// Finalize write process
	int retry=16; //zkusi to maximalne 16x
	int ret;
	//printf(":WSECT:%d",n_actual_mmc_sector);
	do
	{
		ret = mmcWrite(n_actual_mmc_sector); //vraci 0 kdyz ok
		retry--;
	} while (ret && retry);
	//printf(":WD:");
}


