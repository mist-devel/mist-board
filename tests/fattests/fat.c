/*
Copyright 2005, 2006, 2007 Dennis van Weeren
Copyright 2008, 2009 Jakub Bednarski

This file is part of Minimig

Minimig is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

Minimig is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

This is a simple FAT16 handler. It works on a sector basis to allow fastest acces on disk
images.

11-12-2005 - first version, ported from FAT1618.C

JB:
2008-10-11  - added SeekFile() and cluster_mask
            - limited file create and write support added
2009-05-01  - modified LoadDirectory() and GetDirEntry() to support sub-directories (with limitation of 511 files/subdirs per directory)
            - added GetFATLink() function
            - code cleanup
2009-05-03  - modified sorting algorithm in LoadDirectory() to display sub-directories above files
2009-08-23  - modified ScanDirectory() to support page scrolling and parent dir selection
2009-11-22  - modified FileSeek()
            - added FileReadEx()
2009-12-15  - all entries are now sorted by name with extension
            - directory short names are displayed with extensions

*/

#include <stdio.h>
#include <string.h>
//#include <ctype.h>
#include "mmc.h"
#include "fat.h"
#include "swap.h"
#include "usb.h"

int tolower(int c);

#define MAX_FS  2

// 
typedef unsigned char (*rw_func_t)(unsigned long, unsigned char *);

unsigned short directory_cluster;       // first cluster of directory (0 if root)
unsigned short entries_per_cluster;     // number of directory entries per cluster

// internal global variables
unsigned char fattype;              	// volume format 
unsigned char fat32;                  // volume format is FAT32
unsigned long boot_sector;              // partition boot sector
unsigned long fat_start;                // start LBA of first FAT table
unsigned long data_start;               // start LBA of data field
unsigned long root_directory_cluster;   // root directory cluster (used in FAT32)
unsigned long root_directory_start;     // start LBA of directory table
unsigned long root_directory_size;      // size of directory region in sectors
unsigned char fat_number;               // number of FAT tables
unsigned char cluster_size;             // size of a cluster in sectors
unsigned long cluster_mask;             // binary mask of cluster number
unsigned short dir_entries;             // number of entry's in directory table
unsigned long fat_size;                 // size of fat
unsigned short info_sector;             // fat32 info sector

struct PartitionEntry partitions[4];	// lbastart and sectors will be byteswapped as necessary
int partitioncount;

unsigned char sector_buffer[1024];       // sector buffer - room for two consecutive sectors...

FATBUFFER fat_buffer;                   // buffer for caching fat entries
unsigned long buffered_fat_index;       // index of buffered FAT sector

char DirEntryLFN[MAXDIRENTRIES][261];
DIRENTRY DirEntry[MAXDIRENTRIES];
unsigned char sort_table[MAXDIRENTRIES];
unsigned char nDirEntries = 0;          // entries in DirEntry table
unsigned char iSelectedEntry = 0;       // selected entry index
unsigned long iCurrentDirectory = 0;    // cluster number of current directory, 0 for root
unsigned long iPreviousDirectory = 0;   // cluster number of previous directory

// temporary storage buffers
char t_DirEntryLFN[MAXDIRENTRIES][261];
DIRENTRY t_DirEntry[MAXDIRENTRIES];
unsigned char t_sort_table[MAXDIRENTRIES];

// external functions
extern unsigned long GetTimer(unsigned long);
extern void ErrorMessage(const char *message, unsigned char code);

// current read/write functions
rw_func_t lread = MMC_Read;
rw_func_t lwrite = MMC_Write;

int8_t fat_uses_mmc(void) {
  return(lread == MMC_Read);
}

int8_t fat_medium_present() {
  if(lread == MMC_Read) 
    return MMC_CheckCard();
  
  return(storage_devices > 0);
}

void fat_switch_to_usb(void) {
  lread = usb_storage_read;
  lwrite = usb_storage_write; 
}

// return fat sector index of a given cluster entry
#define CLUSTER2SECTOR(c) ((c) >> (fat32?7:8))
// return byte offset withing sector of a given cluster entry
#define CLUSTER2OFFSET(c) ((c) & (fat32?0x7f:0xff))

#pragma section_code_init
// read sector of FAT if not already in the buffer
RAMFUNC static char FatLoad(unsigned long index) {
  // load fat sector
  if(buffered_fat_index != index) {
    if (!lread(fat_start + index, (unsigned char*)&fat_buffer)) {
      iprintf("FAT read failed!\n");
      return(0);
    }
    // remember current buffer index
    buffered_fat_index = index;
  }
  return 1;
}

RAMFUNC unsigned long NextCluster(unsigned long cluster) {
  unsigned long fat_index = CLUSTER2SECTOR(cluster);
  unsigned short buffer_index = CLUSTER2OFFSET(cluster);

  if(!FatLoad(fat_index)) return(0);

  if (fat32) 
    return SwapBBBB(fat_buffer.fat32[buffer_index]) & 0x0FFFFFFF; // get FAT32 link

  return SwapBB(fat_buffer.fat16[buffer_index]); // get FAT16 link
}
#pragma section_no_code_init

// FindDrive() checks if a card is present and contains FAT formatted primary partition
unsigned char FindDrive(void) {
  buffered_fat_index = -1;

  fat32 = 0;  
  
  if (!lread(0, sector_buffer)) // read MBR
    return(0);
  
  boot_sector=0;
  partitioncount=1;
  
  // If we can identify a filesystem on block 0 we don't look for partitions
  if (strncmp((const char*)&sector_buffer[0x36], "FAT16   ", 8)==0) // check for FAT16
    partitioncount=0;
  if (strncmp((const char*)&sector_buffer[0x52], "FAT32   ", 8)==0) // check for FAT32
    partitioncount=0;
  
  iprintf("partitioncount = %d\n", partitioncount);
  
  if(partitioncount) {
    // We have at least one partition, parse the MBR.
    struct MasterBootRecord *mbr=(struct MasterBootRecord *)sector_buffer;
    memcpy(&partitions[0],&mbr->Partition[0],sizeof(struct PartitionEntry));
    memcpy(&partitions[1],&mbr->Partition[1],sizeof(struct PartitionEntry));
    memcpy(&partitions[2],&mbr->Partition[2],sizeof(struct PartitionEntry));
    memcpy(&partitions[3],&mbr->Partition[3],sizeof(struct PartitionEntry));
    
    if(mbr->Signature == 0xaa55) {
      // get start of first partition
      boot_sector = partitions[0].startlba;
      iprintf("Start: %ld\n",partitions[0].startlba);
      for(partitioncount=4;(partitions[partitioncount-1].sectors==0) && (partitioncount>1); --partitioncount);
      iprintf("PartitionCount: %d\n",partitioncount);
      int i;
      for(i=0;i<partitioncount;++i) {
	iprintf("Partition: %d",i);
	iprintf("  Start: %ld",partitions[i].startlba);
	iprintf("  Size: %ld\n",partitions[i].sectors);
      }
      
      if (!lread(boot_sector, sector_buffer)) // read discriptor
	return(0);

      BootPrint("Read boot sector from first partition\n");
    } else
      BootPrint("No partition signature found\n");
  }
  
  if (strncmp((const char*)&sector_buffer[0x36], "FAT16   ", 8)==0) // check for FAT16
    fattype = 16;
  
  if (strncmp((const char*)&sector_buffer[0x52], "FAT32   ", 8)==0) // check for FAT32
    fattype = 32;
  
  iprintf("partition type: 0x%02X (", sector_buffer[450]);
  switch (fattype) {
  case 0:
    iprintf("NONE");
    break;
  case 12:
    iprintf("FAT12");
    break;
  case 16:
    iprintf("FAT16");
    break;
  case 32:
    iprintf("FAT32");
    fat32 = 1;
    break;
  default:
    iprintf("UNKNOWN");
    break;
  }
  iprintf(")\n");
  
  if (fattype != 32 && fattype != 16) { // first partition filesystem type: FAT16 or FAT32
    iprintf("Unsupported partition type!\n");
    return(0);
  }
  
  if (sector_buffer[510] != 0x55 || sector_buffer[511] != 0xaa)  // check signature
    return(0);
  
  // check for near-jump or short-jump opcode
  if (sector_buffer[0] != 0xe9 && sector_buffer[0] != 0xeb)
    return(0);
  
  // check if blocksize is really 512 bytes
  if (sector_buffer[11] != 0x00 || sector_buffer[12] != 0x02)
    return(0);
  
  // check medium descriptor byte, must be 0xf8 for hard drive
  if (sector_buffer[21] != 0xf8)
    return(0);
  
  if (fat32) {
    if (strncmp((const char*)&sector_buffer[0x52], "FAT32   ", 8) != 0) // check file system type
      return(0);
    
    cluster_size = sector_buffer[0x0D]; // get cluster_size in sectors
    cluster_mask = ~(cluster_size - 1); // calculate cluster mask
    dir_entries = cluster_size << 4; // total number of dir entries (16 entries per sector)
    root_directory_size = cluster_size; // root directory size in sectors
    fat_start = boot_sector + sector_buffer[0x0E] + (sector_buffer[0x0F] << 8); // reserved sector count before FAT table (usually 32 for FAT32)
    fat_number = sector_buffer[0x10];
    fat_size = sector_buffer[0x24] + (sector_buffer[0x25] << 8) + (sector_buffer[0x26] << 16) + (sector_buffer[0x27] << 24);
    data_start = fat_start + (fat_number * fat_size);
    root_directory_cluster = sector_buffer[0x2C] + (sector_buffer[0x2D] << 8) + (sector_buffer[0x2E] << 16) + ((sector_buffer[0x2F] & 0x0F) << 24);
    root_directory_start = (root_directory_cluster - 2) * cluster_size + data_start;
    info_sector = boot_sector + (sector_buffer[0x30] + (sector_buffer[0x31] << 8));
  } else {
    // calculate drive's parameters from bootsector, first up is size of directory
    dir_entries = sector_buffer[17] + (sector_buffer[18] << 8);
    root_directory_size = ((dir_entries << 5) + 511) >> 9;
    
    // calculate start of FAT,size of FAT and number of FAT's
    fat_start = boot_sector + sector_buffer[14] + (sector_buffer[15] << 8);
    fat_size = sector_buffer[22] + (sector_buffer[23] << 8);
    fat_number = sector_buffer[16];
    
    // calculate start of directory
    root_directory_start = fat_start + (fat_number * fat_size);
    root_directory_cluster = 0; // unused
    
    // get cluster_size
    cluster_size = sector_buffer[13];
    
    // calculate cluster mask
    cluster_mask = ~(cluster_size - 1);
    
    // calculate start of data
    data_start = root_directory_start + root_directory_size;

    // fat16 does not have a info sector
    info_sector = 0;
  }
  
  // some debug output
  iprintf("fat_size: %lu\n", fat_size);
  iprintf("fat_number: %u\n", fat_number);
  iprintf("fat_start: %lu\n", fat_start);
  iprintf("root_directory_start: %lu\n", root_directory_start);
  iprintf("dir_entries: %u\n", dir_entries);
  iprintf("data_start: %lu\n", data_start);
  iprintf("cluster_size: %u\n", cluster_size);
  iprintf("cluster_mask: %08lX\n", cluster_mask);
  
  return(1);
}

unsigned char FileOpen(fileTYPE *file, const char *name) {
  unsigned long  iDirectory = 0;       // only root directory is supported
  DIRENTRY      *pEntry = NULL;        // pointer to current entry in sector buffer
  unsigned long  iDirectorySector;     // current sector of directory entries table
  unsigned long  iDirectoryCluster;    // start cluster of subdirectory or FAT32 root directory
  unsigned long  iEntry;               // entry index in directory cluster or FAT16 root directory
  unsigned long  nEntries;             // number of entries per cluster or FAT16 root directory size

  if (iDirectory) { // subdirectory
    iDirectoryCluster = iDirectory;
    iDirectorySector = data_start + cluster_size * (iDirectoryCluster - 2);
    nEntries = cluster_size << 4; // 16 entries per sector
  } else { // root directory
    iDirectoryCluster = root_directory_cluster;
    iDirectorySector = root_directory_start;
    nEntries = fat32 ?  cluster_size << 4 : root_directory_size << 4; // 16 entries per sector
  }
  
  while (1) {
    for (iEntry = 0; iEntry < nEntries; iEntry++) {
      if ((iEntry & 0x0F) == 0) { // first entry in sector, load the sector
	lread(iDirectorySector++, sector_buffer); // root directory is linear
	pEntry = (DIRENTRY*)sector_buffer;
      } else
	pEntry++;

      if (pEntry->Name[0] != SLOT_EMPTY && pEntry->Name[0] != SLOT_DELETED) { // valid entry??
	if (!(pEntry->Attributes & (ATTR_VOLUME | ATTR_DIRECTORY))) // not a volume nor directory
	  {
                    if (strncmp((const char*)pEntry->Name, name, sizeof(file->name)) == 0)
                    {
                        strncpy(file->name, (const char*)pEntry->Name, sizeof(file->name));
                        file->attributes = pEntry->Attributes;
//                        file->size = pEntry->FileSize; 																		// it only works when using little endian long representation
                        file->size = SwapBBBB(pEntry->FileSize); 		// for 68000
//                        file->size = ((file->size>>24)&0xFF)|((file->size>>8)&0xFF00)|((file->size<<8)&0xFF0000)|((file->size<<24)&0xFF000000); // for 68000 
//                        file->start_cluster = pEntry->StartCluster + (fat32 ? (pEntry->HighCluster & 0x0FFF) << 16 : 0); 	// it only works when using little endian long representation
                        file->start_cluster = SwapBB(pEntry->StartCluster) + (fat32 ? (SwapBB(pEntry->HighCluster) & 0x0FFF) << 16 : 0); 	// it only works when using little endian long representation for 68000 
//                        file->start_cluster = (((pEntry->StartCluster>>8)&0xFF)|((pEntry->StartCluster<<8)&0xFF00)) | (fat32 ? ((pEntry->HighCluster & 0x0F) << 24)|((pEntry->HighCluster & 0xFF00) << 8)  : 0);  // for 68000 
                        file->cluster =  file->start_cluster;
                        file->sector = 0;
			file->cluster_change = 0;
                        file->entry.sector = iDirectorySector - 1;
                        file->entry.index = iEntry & 0x0F;

                        iprintf("file \"%s\" found\n", name);

                        return(1);
                    }
                }
            }
        }

        if (iDirectory || fat32) // subdirectory is a linked cluster chain
        {
            iDirectoryCluster = NextCluster(iDirectoryCluster); // get next cluster in chain

            if (fat32 ? (iDirectoryCluster & 0x0FFFFFF8) == 0x0FFFFFF8 : (iDirectoryCluster & 0xFFF8) == 0xFFF8) // check if end of cluster chain
                break; // no more clusters in chain

            iDirectorySector = data_start + cluster_size * (iDirectoryCluster - 2); // calculate first sector address of the new cluster
        }
        else
            break;
    }

    iprintf("file \"%s\" not found\n", name);
    memset(file, 0, sizeof(fileTYPE));
    return(0);
}

unsigned char lfn_checksum(unsigned char *pName)
{
    unsigned char i = 11;
    unsigned char checksum = 0;

    while (i--)
        checksum = ((checksum & 1) << 7) + (checksum >> 1) + *pName++;

    return checksum;
}

int _strnicmp(const char *s1, const char *s2, size_t n)
{
    char c1, c2;
    int v;

    do
    {
        c1 = *s1++;
        c2 = *s2++;
        v = (unsigned int)tolower(c1) - (unsigned int)tolower(c2);
    }
    while (v == 0 && c1 != '\0' && --n > 0);

    return v;
}

int CompareDirEntries(DIRENTRY *pDirEntry1, char *pLFN1, DIRENTRY *pDirEntry2, char *pLFN2)
{
    const char *pStr1, *pStr2;
    int len;
    int rc;

    if ((pDirEntry1->Attributes & ATTR_DIRECTORY) && !(pDirEntry2->Attributes & ATTR_DIRECTORY)) // directories first
       return -1;

    if (!(pDirEntry1->Attributes & ATTR_DIRECTORY) && (pDirEntry2->Attributes & ATTR_DIRECTORY)) // directories first
       return 1;

    len = 260;
    if (*pLFN1)
       pStr1 = pLFN1;
    else
    {
        pStr1 = (const char*)pDirEntry1->Name;
        len = 11;
    }

    if (*pLFN2)
       pStr2 = pLFN2;
    else
    {
        pStr2 = (const char*)pDirEntry2->Name;
        len = 11;
    }

    rc = _strnicmp(pStr1, pStr2, len);

    if (rc == 0) // it might happen that both strings are equal when one is a long name and other not
    {
        if (*pLFN1)
        {
            if (!*pLFN2) // first string long, second short
                rc = 1;
        }
        else
        {
            if (*pLFN2) // first string short, second long
                rc = -1;
        }
    }
    return(rc);
}

char ScanDirectory(unsigned long mode, char *extension, unsigned char options) {
    DIRENTRY *pEntry = NULL;            // pointer to current entry in sector buffer
    unsigned long iDirectorySector;     // current sector of directory entries table
    unsigned long iDirectoryCluster;
    unsigned long iEntry;               // entry index in directory
    unsigned long nEntries;
             char i;
    unsigned char x;
    unsigned char nNewEntries = 0;      // indicates if a new entry has been found (used in scroll mode)
    char rc = 0; //return code
    char find_file = 0;
    char find_dir = 0;
    char is_file = 0;

    unsigned char sequence_number = 0;
    unsigned char name_checksum = 0;
    unsigned char prev_sequence_number = 0;
    unsigned char prev_name_checksum = 0;

    char *ptr;
    static char lfn[261];
    unsigned char lfn_error = 1;
    /*
    unsigned long time;
    time = GetTimer(0);
    */
    lfn[0] = 0;

    if (mode == SCAN_INIT)
    {
        nDirEntries = 0;
        iSelectedEntry = 0;
        for (i = 0; i < MAXDIRENTRIES; i++)
            sort_table[i] = i;
    }
    else
    {
        if (nDirEntries == 0) // directory is empty so there is no point in searching for any entry
            return 0;

        if (mode == SCAN_NEXT)
        {
            if (iSelectedEntry + 1 < nDirEntries) // scroll within visible items
            {
                iSelectedEntry++;
                return 0;
            }
            if (nDirEntries < MAXDIRENTRIES)
                return 0;
        }
        else if (mode == SCAN_PREV)
        {
            if (iSelectedEntry > 0) // scroll within visible items
            {
                iSelectedEntry--;
                return 0;
            }
        }
        else if (mode ==SCAN_NEXT_PAGE)
        {
            if (iSelectedEntry + 1 < nDirEntries)
            {
                iSelectedEntry = nDirEntries - 1;
                return 0;
            }
            if (nDirEntries < MAXDIRENTRIES)
                return 0;
        }
        else if (mode == SCAN_PREV_PAGE)
        {
            if (iSelectedEntry)
            {
                iSelectedEntry = 0;
                return 0;
            }
        }

        find_file = options & FIND_FILE;
        find_dir = options & FIND_DIR;
    }

    if (iCurrentDirectory) // subdirectory
    {
        iDirectoryCluster = iCurrentDirectory;
        iDirectorySector = data_start + cluster_size * (iDirectoryCluster - 2);
        nEntries = cluster_size << 4; // 16 entries per sector
    }
    else // root directory
    {
        iDirectoryCluster = root_directory_cluster;
        iDirectorySector = root_directory_start;
        nEntries = fat32 ?  cluster_size << 4 : root_directory_size << 4; // 16 entries per sector
    }

    while (1)
    {
        for (iEntry = 0; iEntry < nEntries; iEntry++)
        {
            if ((iEntry & 0xF) == 0) // first entry in sector, load the sector
            {
                lread(iDirectorySector++, sector_buffer);
                pEntry = (DIRENTRY*)sector_buffer;
				for (i = 0; i < 16; i++) 
				{
					if (pEntry->Attributes != ATTR_LFN)
					{
						pEntry->StartCluster = SwapBB(pEntry->StartCluster);
						pEntry->HighCluster = SwapBB(pEntry->HighCluster);
						pEntry->FileSize = SwapBBBB(pEntry->FileSize);
					}
					pEntry++;
				}		
                pEntry = (DIRENTRY*)sector_buffer;
            }
            else
                pEntry++;

            if (pEntry->Name[0] != SLOT_EMPTY && pEntry->Name[0] != SLOT_DELETED) // valid entry??
            {
                if (pEntry->Attributes == ATTR_LFN) // long file name entry
                {
                    if (options & SCAN_LFN)
                    {
                        sequence_number = ((unsigned char*)pEntry)[0];
                        name_checksum = ((unsigned char*)pEntry)[13];
                        ptr  = &lfn[((sequence_number & 0x1F) - 1) * 13];

                        if (sequence_number & 0x40)
                            lfn_error = 0;
                        else
                            if ((sequence_number & 0x1F) != (prev_sequence_number & 0x1F) - 1 || name_checksum != prev_name_checksum || (sequence_number & 0x1F) > sizeof(lfn) / 13 - 1)
                                lfn_error = 1;

                        prev_sequence_number = sequence_number;
                        prev_name_checksum = name_checksum;

                        if (!lfn_error)
                        {
                            *ptr++ = ((unsigned char*)pEntry)[1];
                            *ptr++ = ((unsigned char*)pEntry)[3];
                            *ptr++ = ((unsigned char*)pEntry)[5];
                            *ptr++ = ((unsigned char*)pEntry)[7];
                            *ptr++ = ((unsigned char*)pEntry)[9]; // first 5 characters
                            *ptr++ = ((unsigned char*)pEntry)[14];
                            *ptr++ = ((unsigned char*)pEntry)[16];
                            *ptr++ = ((unsigned char*)pEntry)[18];
                            *ptr++ = ((unsigned char*)pEntry)[20];
                            *ptr++ = ((unsigned char*)pEntry)[22];
                            *ptr++ = ((unsigned char*)pEntry)[24]; // next 6 characters
                            *ptr++ = ((unsigned char*)pEntry)[28];
                            *ptr++ = ((unsigned char*)pEntry)[30]; // last 2 characters

                            if (sequence_number & 0x40) // last lfn part
                                *ptr++ = 0;
                        }
                        else
                            iprintf("LFN error!\n");
                    }
                }
                else // if not an LFN entry
                {
                    is_file = ~pEntry->Attributes & ATTR_DIRECTORY;

                    if (!(pEntry->Attributes & (ATTR_VOLUME | ATTR_HIDDEN)) && (pEntry->Name[0] != '.' || pEntry->Name[1] != ' ')) // if not VOLUME label (also filter current directory entry)
                    {
                        if ((extension[0] == '*') || (strncmp((const char*)&pEntry->Name[8], extension, 3) == 0) || (options & SCAN_DIR && pEntry->Attributes & ATTR_DIRECTORY))
                        {
                            if (mode == SCAN_INIT)
                            { // scan the directory table and return first MAXDIRENTRIES alphabetically sorted entries
                                if (nDirEntries < MAXDIRENTRIES) // initial directory scan (first 8 entries)
                                {
                                    DirEntry[nDirEntries] = *pEntry; // add new entry at first empty slot in storage buffer
                                    DirEntryLFN[nDirEntries][0] = 0;
                                    if (lfn[0])
                                        if (lfn_checksum(pEntry->Name) == name_checksum)
                                            strncpy(DirEntryLFN[nDirEntries], lfn, sizeof(lfn));

                                    nDirEntries++;
                                }
                                else
                                {
                                    if (CompareDirEntries(pEntry, lfn, &DirEntry[sort_table[MAXDIRENTRIES-1]], DirEntryLFN[sort_table[MAXDIRENTRIES-1]]) < 0) // compare new entry with the last already found
                                    {
                                        DirEntry[sort_table[MAXDIRENTRIES-1]] = *pEntry; // replace the last entry with the new one if appropriate
                                        DirEntryLFN[sort_table[MAXDIRENTRIES-1]][0] = 0;
                                        if (lfn[0])
                                            if (lfn_checksum(pEntry->Name) == name_checksum)
                                                strncpy(DirEntryLFN[sort_table[MAXDIRENTRIES-1]], lfn, sizeof(lfn));
                                    }
                                }

                                for (i = nDirEntries - 1; i > 0; i--) // one pass bubble-sorting (table is already sorted, only the new item must be placed in order)
                                {
                                    if (CompareDirEntries(&DirEntry[sort_table[i]], DirEntryLFN[sort_table[i]], &DirEntry[sort_table[i-1]], DirEntryLFN[sort_table[i-1]])<0) // compare items and swap if necessary
                                    {
                                        x = sort_table[i];
                                        sort_table[i] = sort_table[i-1];
                                        sort_table[i-1] = x;
                                    }
                                    else
                                        break; // don't check further entries as they are already sorted
                                }
                            }
                            else if (mode == SCAN_INIT_FIRST)
                            { // find a dir entry with given cluster number and store it in the buffer
                                if (pEntry->StartCluster + (fat32 ? (pEntry->HighCluster & 0x0FFF) << 16 : 0) == iPreviousDirectory)
                                { // directory entry found
                                    for (i = 0; i< MAXDIRENTRIES; i++)
                                        sort_table[i] = i; // init sorting table

                                    nDirEntries = 1;
                                    iSelectedEntry = 0;

                                    DirEntry[0] = *pEntry; // add the entry at the top of the buffer
                                    DirEntryLFN[0][0] = 0;
                                    if (lfn[0])
                                        if (lfn_checksum(pEntry->Name) == name_checksum)
                                            strncpy(DirEntryLFN[0], lfn, sizeof(lfn));

                                    rc = 1; // indicate to the caller that the directory entry has been found
                                }
                            }
                            else if (mode == SCAN_INIT_NEXT)
                            { // scan the directory table and return next MAXDIRENTRIES-1 alphabetically sorted entries (first entry is in the buffer)
                                if (CompareDirEntries(pEntry, lfn, &DirEntry[sort_table[0]], DirEntryLFN[sort_table[0]]) > 0) // compare new entry with the first one
                                {
                                    if (nDirEntries < MAXDIRENTRIES) // initial directory scan (first 8 entries)
                                    {
                                        DirEntry[nDirEntries] = *pEntry; // add new entry at first empty slot in storage buffer
                                        DirEntryLFN[nDirEntries][0] = 0;
                                        if (lfn[0])
                                            if (lfn_checksum(pEntry->Name) == name_checksum)
                                                strncpy(DirEntryLFN[nDirEntries], lfn, sizeof(lfn));

                                        nDirEntries++;
                                    }
                                    else
                                    {
                                        if (CompareDirEntries(pEntry, lfn, &DirEntry[sort_table[MAXDIRENTRIES-1]], DirEntryLFN[sort_table[MAXDIRENTRIES-1]]) < 0) // compare new entry with the last already found
                                        {
                                            DirEntry[sort_table[MAXDIRENTRIES-1]] = *pEntry; // replace the last entry with the new one if appropriate
                                            DirEntryLFN[sort_table[MAXDIRENTRIES-1]][0] = 0;
                                            if (lfn[0])
                                                if (lfn_checksum(pEntry->Name) == name_checksum)
                                                    strncpy(DirEntryLFN[sort_table[MAXDIRENTRIES-1]], lfn, sizeof(lfn));
                                        }
                                    }

                                    for (i = nDirEntries - 1; i > 0; i--) // one pass bubble-sorting (table is already sorted, only the new item must be placed in order)
                                    {
                                        if (CompareDirEntries(&DirEntry[sort_table[i]], DirEntryLFN[sort_table[i]], &DirEntry[sort_table[i-1]], DirEntryLFN[sort_table[i-1]])<0) // compare items and swap if necessary
                                        {
                                            x = sort_table[i];
                                            sort_table[i] = sort_table[i-1];
                                            sort_table[i-1] = x;
                                        }
                                        else
                                            break; // don't check further entries as they are already sorted
                                    }
                                }
                            }
                            else if (mode == SCAN_NEXT) // replace the last dir entry with the new (higher) one
                            {
                                if (nNewEntries == 0) // no entry higher than the last one has been found yet
                                {
                                    if (CompareDirEntries(pEntry, lfn, &DirEntry[sort_table[MAXDIRENTRIES-1]], DirEntryLFN[sort_table[MAXDIRENTRIES-1]]) > 0) // found entry higher than the last one
                                    {
                                        nNewEntries++;
                                        DirEntry[sort_table[0]] = *pEntry; // replace the first entry with the found one
                                        DirEntryLFN[sort_table[0]][0] = 0;
                                        if (lfn[0])
                                            if (lfn_checksum(pEntry->Name) == name_checksum)
                                                strncpy(DirEntryLFN[sort_table[0]], lfn, sizeof(lfn));

                                        // scroll entries' indices
                                        x = sort_table[0];
                                        for (i = 0; i < MAXDIRENTRIES-1; i++)
                                            sort_table[i] = sort_table[i+1];

                                        sort_table[MAXDIRENTRIES-1] = x; // last entry is the found one
                                    }
                                }
                                else // higher entry already found but we need to check the remaining ones if any of them is lower then the already found one
                                {
                                    // check if the found entry is lower than the last one and higher than the last but one, if so then replace the last one with it
                                    if (CompareDirEntries(pEntry, lfn, &DirEntry[sort_table[MAXDIRENTRIES-1]], DirEntryLFN[sort_table[MAXDIRENTRIES-1]]) < 0)
                                        if (CompareDirEntries(pEntry, lfn, &DirEntry[sort_table[MAXDIRENTRIES-2]], DirEntryLFN[sort_table[MAXDIRENTRIES-2]]) > 0)
                                        {
                                            DirEntry[sort_table[MAXDIRENTRIES-1]] = *pEntry;
                                            DirEntryLFN[sort_table[MAXDIRENTRIES-1]][0] = 0;
                                            if (lfn[0])
                                                if (lfn_checksum(pEntry->Name) == name_checksum)
                                                    strncpy(DirEntryLFN[sort_table[MAXDIRENTRIES-1]], lfn, sizeof(lfn));
                                        }
                                }
                            }
                            else if (mode == SCAN_PREV) // replace the first dir entry with the new (lower) one
                            {
                                if (nNewEntries == 0) // no entry lower than the first one has been found yet
                                {
                                    if (CompareDirEntries(pEntry, lfn, &DirEntry[sort_table[0]], DirEntryLFN[sort_table[0]]) < 0) // found entry lower than the first one
                                    {
                                        nNewEntries++;
                                        if (nDirEntries < MAXDIRENTRIES)
                                        {
                                            //sort_table[nDirEntries] = nDirEntries; // init sorting table
                                            nDirEntries++;
                                        }
                                        DirEntry[sort_table[MAXDIRENTRIES-1]] = *pEntry; // replace the last entry with the found one
                                        DirEntryLFN[sort_table[MAXDIRENTRIES-1]][0] = 0;
                                        if (lfn[0])
                                            if (lfn_checksum(pEntry->Name) == name_checksum)
                                                strncpy(DirEntryLFN[sort_table[MAXDIRENTRIES-1]], lfn, sizeof(lfn));

                                        // scroll entries' indices
                                        x = sort_table[MAXDIRENTRIES-1];
                                        for (i = MAXDIRENTRIES - 1; i > 0; i--)
                                            sort_table[i] = sort_table[i-1];

                                        sort_table[0] = x; // the first entry is the found one
                                    }
                                }
                                else // lower entry already found but we need to check the remaining ones if any of them is higher then the already found one
                                {
                                    // check if the found entry is higher than the first one and lower than the second one, if so then replace the first one with it
                                    if (CompareDirEntries(pEntry, lfn, &DirEntry[sort_table[0]], DirEntryLFN[sort_table[0]]) > 0)
                                        if (CompareDirEntries(pEntry, lfn, &DirEntry[sort_table[1]], DirEntryLFN[sort_table[1]]) < 0)
                                        {
                                            DirEntry[sort_table[0]] = *pEntry;
                                            DirEntryLFN[sort_table[0]][0] = 0;
                                            if (lfn[0])
                                                if (lfn_checksum(pEntry->Name) == name_checksum)
                                                    strncpy(DirEntryLFN[sort_table[0]], lfn, sizeof(lfn));
                                        }
                                }
                            }
                            else if (mode == SCAN_NEXT_PAGE) // find next 8 entries
                            {
                                if (CompareDirEntries(pEntry, lfn, &DirEntry[sort_table[MAXDIRENTRIES-1]], DirEntryLFN[sort_table[MAXDIRENTRIES-1]]) > 0) // compare with the last visible entry
                                {
                                    if (nNewEntries < MAXDIRENTRIES) // initial directory scan (first 8 entries)
                                    {
                                        t_DirEntry[nNewEntries] = *pEntry; // add new entry at first empty slot in storage buffer
                                        t_DirEntryLFN[nNewEntries][0] = 0;
                                        if (lfn[0])
                                            if (lfn_checksum(pEntry->Name) == name_checksum)
                                                strncpy(t_DirEntryLFN[nNewEntries], lfn, sizeof(lfn));

                                        t_sort_table[nNewEntries] = nNewEntries; // init sorting table
                                        nNewEntries++;
                                    }
                                    else
                                    {
                                        if (CompareDirEntries(pEntry, lfn, &t_DirEntry[t_sort_table[MAXDIRENTRIES-1]], t_DirEntryLFN[t_sort_table[MAXDIRENTRIES-1]]) < 0) // compare new entry with the last already found
                                        {
                                            t_DirEntry[t_sort_table[MAXDIRENTRIES-1]] = *pEntry; // replace the last entry with the new one if appropriate
                                            t_DirEntryLFN[t_sort_table[MAXDIRENTRIES-1]][0] = 0;
                                            if (lfn[0])
                                                if (lfn_checksum(pEntry->Name) == name_checksum)
                                                    strncpy(t_DirEntryLFN[t_sort_table[MAXDIRENTRIES-1]], lfn, sizeof(lfn));
                                        }
                                    }

                                    for (i = nNewEntries - 1; i > 0; i--) // one pass bubble-sorting (table is already sorted, only the new item must be placed in order)
                                    {
                                        if (CompareDirEntries(&t_DirEntry[t_sort_table[i]], t_DirEntryLFN[t_sort_table[i]], &t_DirEntry[t_sort_table[i-1]], t_DirEntryLFN[t_sort_table[i-1]]) < 0) // compare items and swap if necessary
                                        {
                                            x = t_sort_table[i];
                                            t_sort_table[i] = t_sort_table[i-1];
                                            t_sort_table[i-1] = x;
                                        }
                                        else
                                            break; // don't check further entries as they are already sorted
                                    }
                                }
                            }
                            else if (mode == SCAN_PREV_PAGE) // find next 8 entries
                            {
                                if (CompareDirEntries(pEntry, lfn, &DirEntry[sort_table[0]], DirEntryLFN[sort_table[0]]) < 0) // compare with the last visible entry
                                {
                                    if (nNewEntries < MAXDIRENTRIES) // initial directory scan (first 8 entries)
                                    {
                                        t_DirEntry[nNewEntries] = *pEntry; // add new entry at first empty slot in storage buffer
                                        t_DirEntryLFN[nNewEntries][0] = 0;
                                        if (lfn[0])
                                            if (lfn_checksum(pEntry->Name) == name_checksum)
                                                strncpy(t_DirEntryLFN[nNewEntries], lfn, sizeof(lfn));

                                        t_sort_table[nNewEntries] = nNewEntries; // init sorting table
                                        nNewEntries++;
                                    }
                                    else
                                    {
                                        if (CompareDirEntries(pEntry, lfn, &t_DirEntry[t_sort_table[MAXDIRENTRIES-1]], t_DirEntryLFN[t_sort_table[MAXDIRENTRIES-1]]) > 0) // compare new entry with the last already found
                                        {
                                            t_DirEntry[t_sort_table[MAXDIRENTRIES-1]] = *pEntry; // replace the last entry with the new one if appropriate
                                            t_DirEntryLFN[t_sort_table[MAXDIRENTRIES-1]][0] = 0;
                                            if (lfn[0])
                                                if (lfn_checksum(pEntry->Name) == name_checksum)
                                                    strncpy(t_DirEntryLFN[t_sort_table[MAXDIRENTRIES-1]], lfn, sizeof(lfn));
                                        }
                                    }
                                    for (i = nNewEntries - 1; i > 0; i--) // one pass bubble-sorting (table is already sorted, only the new item must be placed in order)
                                    {
                                        if (CompareDirEntries(&t_DirEntry[t_sort_table[i]], t_DirEntryLFN[t_sort_table[i]], &t_DirEntry[t_sort_table[i-1]], t_DirEntryLFN[t_sort_table[i-1]]) > 0) // compare items and swap if necessary
                                        {
                                            x = t_sort_table[i];
                                            t_sort_table[i] = t_sort_table[i-1];
                                            t_sort_table[i-1] = x;
                                        }
                                        else
                                            break; // don't check further entries as they are already sorted
                                    }
                                }
                            }
                            else if ((mode >= '0' && mode <= '9') || (mode >= 'A' && mode <= 'Z')) // find first entry beginning with given character
                            {
                                if (find_file)
                                    x = tolower(pEntry->Name[0]) >= tolower(mode) && is_file;
                                else if (find_dir)
                                    x = tolower(pEntry->Name[0]) >= tolower(mode) || is_file;
                                else
                                    x = (CompareDirEntries(pEntry, lfn, &DirEntry[sort_table[iSelectedEntry]], DirEntryLFN[sort_table[iSelectedEntry]]) > 0); // compare with the last visible entry

                                if (x)
                                {
                                    if (nNewEntries < MAXDIRENTRIES) // initial directory scan (first 8 entries)
                                    {
                                        t_DirEntry[nNewEntries] = *pEntry; // add new entry at first empty slot in storage buffer
                                        t_DirEntryLFN[nNewEntries][0] = 0;
                                        if (lfn[0])
                                            if (lfn_checksum(pEntry->Name) == name_checksum)
                                                strncpy(t_DirEntryLFN[nNewEntries], lfn, sizeof(lfn));

                                        t_sort_table[nNewEntries] = nNewEntries; // init sorting table
                                        nNewEntries++;
                                    }
                                    else
                                    {
                                        if (CompareDirEntries(pEntry, lfn, &t_DirEntry[t_sort_table[MAXDIRENTRIES-1]], t_DirEntryLFN[t_sort_table[MAXDIRENTRIES-1]]) < 0) // compare new entry with the last already found
                                        {
                                            t_DirEntry[t_sort_table[MAXDIRENTRIES-1]] = *pEntry; // replace the last entry with the new one if appropriate
                                            t_DirEntryLFN[t_sort_table[MAXDIRENTRIES-1]][0] = 0;
                                            if (lfn[0])
                                                if (lfn_checksum(pEntry->Name) == name_checksum)
                                                    strncpy(t_DirEntryLFN[t_sort_table[MAXDIRENTRIES-1]], lfn, sizeof(lfn));
                                        }
                                    }

                                    for (i = nNewEntries - 1; i > 0; i--) // one pass bubble-sorting (table is already sorted, only the new item must be placed in order)
                                    {
                                        if (CompareDirEntries(&t_DirEntry[t_sort_table[i]], t_DirEntryLFN[t_sort_table[i]], &t_DirEntry[t_sort_table[i-1]], t_DirEntryLFN[t_sort_table[i-1]]) < 0) // compare items and swap if necessary
                                        {
                                            x = t_sort_table[i];
                                            t_sort_table[i] = t_sort_table[i-1];
                                            t_sort_table[i-1] = x;
                                        }
                                        else
                                            break; // don't check further entries as they are already sorted
                                    }
                                }
                            }
                        }
                    }
                    lfn[0] = 0;
                }
            }
        }
        if (iCurrentDirectory || fat32) // subdirectory is a linked cluster chain
        {
            iDirectoryCluster = NextCluster(iDirectoryCluster); // get next cluster in chain

            if (fat32 ? (iDirectoryCluster & 0x0FFFFFF8) == 0x0FFFFFF8 : (iDirectoryCluster & 0xFFF8) == 0xFFF8) // check if end of chain
                break; // no more clusters in chain

            iDirectorySector = data_start + cluster_size * (iDirectoryCluster - 2); // calculate first sector address of the new cluster
        }
        else
            break;
    }
    if (nNewEntries)
    {
        if (mode == SCAN_NEXT_PAGE)
        {
            unsigned char j = 8 - nNewEntries; // number of remaining old entries to scroll
            for (i = 0; i < j; i++)
            {
                x = sort_table[i];
                sort_table[i] = sort_table[i + nNewEntries];
                sort_table[i + nNewEntries] = x;
            }
            // copy temporary buffer to display
            for (i = 0; i < nNewEntries; i++)
            {
                DirEntry[sort_table[i + j]] = t_DirEntry[t_sort_table[i]];
                strcpy(DirEntryLFN[sort_table[i + j]], t_DirEntryLFN[t_sort_table[i]]);
            }
        }
        else if (mode == SCAN_PREV_PAGE)
        { // note: temporary buffer entries are in reverse order
            unsigned char j = nNewEntries - 1;
            for (i = 7; i > j; i--)
            {
                x = sort_table[i];
                sort_table[i] = sort_table[i - nNewEntries];
                sort_table[i - nNewEntries] = x;
            }
            // copy temporary buffer to display
            for (i = 0; i < nNewEntries; i++)
            {
                DirEntry[sort_table[j - i]] = t_DirEntry[t_sort_table[i]];
                strcpy(DirEntryLFN[sort_table[j - i]], t_DirEntryLFN[t_sort_table[i]]);
            }
            nDirEntries += nNewEntries;
            if (nDirEntries > MAXDIRENTRIES)
                nDirEntries = MAXDIRENTRIES;
        }
        else if ((mode >= '0' && mode <= '9') || (mode >= 'A' && mode <= 'Z'))
        {
            if (t_DirEntry[t_sort_table[0]].Name[0] == mode)
            {
                x = 1; // if we were looking for a file we couldn't find anything other
                if (find_dir)
                { // when looking for a directory we could find a file beginning with the same character as given one
                     x = t_DirEntry[t_sort_table[0]].Attributes & ATTR_DIRECTORY;
                }
                else if (!find_file) // find_next
                { // when looking for a directory we could find a file beginning with the same character as given one
                    x = (t_DirEntry[t_sort_table[0]].Attributes & ATTR_DIRECTORY) == (DirEntry[sort_table[iSelectedEntry]].Attributes & ATTR_DIRECTORY);
                }

                if (x)
                { // first entry is what we were searching for
                    for (i = 0; i < nNewEntries; i++)
                    {
                        DirEntry[sort_table[i]] = t_DirEntry[t_sort_table[i]];
                        strcpy(DirEntryLFN[sort_table[i]], t_DirEntryLFN[t_sort_table[i]]);
                    }
                    nDirEntries = nNewEntries;
                    iSelectedEntry = 0;
                    rc = 1; // inform the caller that the search succeeded
                }
            }
        }
    }
    /*
    time = GetTimer(0) - time;
    iprintf("ScanDirectory(): %lu ms\n", time >> 20);
    */
    return rc;
}

void ChangeDirectory(unsigned long iStartCluster)
{
    iPreviousDirectory = iCurrentDirectory;
    iCurrentDirectory = iStartCluster;
}

#pragma section_code_init
RAMFUNC unsigned char FileNextSector(fileTYPE *file)
{
    unsigned long sb;
    unsigned short i;

    // increment sector index
    file->sector++;

    // cluster's boundary crossed?
    if ((file->sector&~cluster_mask) == 0)
    {
        sb = CLUSTER2SECTOR(file->cluster);
        i = CLUSTER2OFFSET(file->cluster);

	if(!FatLoad(sb)) return 0;
        file->cluster = fat32 ? SwapBBBB(fat_buffer.fat32[i]) & 0x0FFFFFFF : SwapBB(fat_buffer.fat16[i]);
    }

    return(1);
}
#pragma section_no_code_init

static int FatSave(unsigned long index) {	
  // store FAT sector
  if (!lwrite(fat_start + index, (unsigned char*)&fat_buffer)) {
    iprintf("FAT write failed!\n");
    return(0);
  }
  
  // update FAT copies
  char i;
  for (i = 1; i < fat_number; i++) {
    if (!lwrite(fat_start + (i * fat_size) + index, (unsigned char*)&fat_buffer)) {
      iprintf("FAT copy #%d write failed!\n", i);
      return(0);
    }
  }
  return 1;
}

unsigned long ClusterAllocate() {
  // free cluster is marked as 0x0000
  // last cluster in chain is 0xFFFF
  unsigned long fat_index = 0; // first sector of FAT
  unsigned long buffer_index = 2;  // two first entries are reserved
  while (fat_index < fat_size) {

    if(!FatLoad(fat_index))
      return(0);

    // one sector can hold 128 fat32 entries or 256 fat 16 entries
    unsigned long buffer_size = fat32 ? 128 : 256;
    while (buffer_index < buffer_size) { // search through all entries in current sector
      
      if ((fat32 ? fat_buffer.fat32[buffer_index] : fat_buffer.fat16[buffer_index]) == 0) {
	// empty cluster found
	unsigned long cluster = (fat_index << (fat32 ? 7 : 8)) + buffer_index;  // calculate cluster number

	iprintf("Empty cluster: %lu\n", cluster);
	
	// mark cluster as used
	if (fat32) fat_buffer.fat32[buffer_index] = SwapBBBB(0x0FFFFFFF); // FAT32 EOC
	else	   fat_buffer.fat16[buffer_index] = SwapBB(0xFFFF);       // FAT16 EOC

	if(!FatSave(fat_index))
	  return(0);
	
	// we have a free cluster in "cluster"
	return cluster;
      }
      buffer_index++;
    }
    buffer_index = 0; // go to the start of sector
    fat_index++; // go to the next sector of FAT
  }
  return 0;  // this will never be reached
}

#define EOC   (fat32?0x0FFFFFFF:0xFFFF)

// Get next sector. Expand cluster chain in required
unsigned char FileNextSectorExpand(fileTYPE *file) {
  unsigned long cur_cluster = file->cluster;
  unsigned char retval = FileNextSector(file);
  if(retval) {
    // check if cluster is end of chain
    if(file->cluster == EOC) {
      
      // allocate a new cluster ...
      file->cluster = ClusterAllocate();
      if(file->cluster) {
	file->cluster_change++;

	// ... and append it to chain
	
	// save new cluster in previous cluster entry
	unsigned long fat_index = CLUSTER2SECTOR(cur_cluster);
	unsigned short buffer_index = CLUSTER2OFFSET(cur_cluster);
	
	if(!FatLoad(fat_index)) return(0);
	
	if (fat32) fat_buffer.fat32[buffer_index] = file->cluster;
	else 	   fat_buffer.fat16[buffer_index] = file->cluster;
	
	if(!FatSave(fat_index)) return(0);
      }
    }
  }
  return retval;
}

unsigned char FileSeek(fileTYPE *file, unsigned long offset, unsigned long origin)
{
// offset in sectors (512 bytes)
// origin can be set to SEEK_SET or SEEK_CUR
    if (origin == SEEK_CUR)
        offset += file->sector;

    if (file->sector > offset) // current filepointer is beyond requested position
    { // so move it backwards
        if ((file->sector^offset) & cluster_mask) // moving backwards within current cluster?
        { // different clusters, so go to the start of file
            file->cluster = file->start_cluster;
            file->sector = 0;
        }
        else
        { // same clusters, move filepointer backwards within current cluster
            file->sector = offset;
        }
    }
    
    // moving forward
    while ((file->sector^offset) & cluster_mask)  // compare clusters
    { // different clusters, get next one
	file->cluster = NextCluster(file->cluster);

	// end of chain reached
	if(file->cluster == EOC)
	  return 0;

        file->sector += cluster_size; // move file pointer to next cluster
    }

    file->sector = offset; // same clusters

    return(1);
}

#pragma section_code_init
RAMFUNC unsigned char FileRead(fileTYPE *file, unsigned char *pBuffer) 
{
    unsigned long sb;

    sb = data_start;                         // start of data in partition
    sb += cluster_size * (file->cluster-2);  // cluster offset
    sb += file->sector & ~cluster_mask;      // sector offset in cluster

    if (!lread(sb, pBuffer)) // read sector from drive
        return(0);
    else
        return(1);
}
#pragma section_no_code_init

unsigned char FileReadEx(fileTYPE *file, unsigned char *pBuffer, unsigned long nSize)
{
    unsigned long sb;
    unsigned long bc; // block count of single multisector read operation

    while (nSize)
    {
        sb = data_start;                         // start of data in partition
        sb += cluster_size * (file->cluster-2);  // cluster offset
        sb += file->sector & ~cluster_mask;      // sector offset in cluster
        bc = cluster_size - (file->sector & ~cluster_mask); // sector offset in the cluster
        if (nSize < bc)
            bc = nSize;

	// !!!!!!!!
	if (!MMC_ReadMultiple(sb, pBuffer, bc))
	  return 0;

        if (!FileSeek(file, bc, SEEK_CUR))
            return 0;

        nSize -= bc;
    }

    return 1;
}

unsigned char FileWrite(fileTYPE *file,unsigned char *pBuffer)
{
    unsigned long sector;

    if(!lwrite) return 0;  // error

    sector = data_start;                       // start of data in partition
    sector += cluster_size * (file->cluster-2);  // cluster offset
    sector += file->sector & ~cluster_mask;    // sector offset in cluster

    if (!lwrite(sector, pBuffer)) // write sector from drive
        return(0);
    else
        return(1);
}

unsigned char FileCreate(unsigned long iDirectory, fileTYPE *file)
{
    // TODO: deleted entries are not empty, they have to be cleared first
    /*
    find empty dir entry
    find empty cluster in fat
    mark cluster in fat as used
    update fat copy
    update dir entry
    */

    if(!lwrite) return 0;  // error

    DIRENTRY *pEntry = NULL;            // pointer to current entry in sector buffer
    unsigned long iDirectorySector;     // current sector of directory entries table
    unsigned long iDirectoryCluster;    // start cluster of subdirectory or FAT32 root directory
    unsigned long iEntry;               // entry index in directory cluster or FAT16 root directory
    unsigned long nEntries;             // number of entries per cluster or FAT16 root directory size

    if (iDirectory) // subdirectory
    {
        iDirectoryCluster = iDirectory;
        iDirectorySector = data_start + cluster_size * (iDirectoryCluster-2);
        nEntries = cluster_size << 4; // 16 entries per sector
    }
    else // root directory
    {
        iDirectoryCluster = root_directory_cluster;
        iDirectorySector = root_directory_start;
        nEntries = fat32 ?  cluster_size << 4 : root_directory_size << 4; // 16 entries per sector
    }

    while (1)
    {
        for (iEntry = 0; iEntry < nEntries; iEntry++)
        {
            if ((iEntry & 0x0F) == 0) // first entry in sector, load the sector
            {
                lread(iDirectorySector++, sector_buffer); // read directory sector
                pEntry = (DIRENTRY*)sector_buffer;
            }
            else
                pEntry++;


            if (pEntry->Name[0] == SLOT_EMPTY)
            {
                iprintf("Empty entry found in sector %lu at index %lu\n", iDirectorySector-1, iEntry&0x0F);

		unsigned long cluster = ClusterAllocate();
		if(cluster) {
		  // initialize direntry
		  memset((void*)pEntry, 0, sizeof(DIRENTRY));
		  memcpy((void*)pEntry->Name, file->name, 11);
		  pEntry->Attributes = file->attributes;
		  pEntry->CreateDate = SwapBB(FILEDATE(2009, 9, 1));
		  pEntry->CreateTime = SwapBB(FILETIME(0, 0, 0));
		  pEntry->AccessDate = SwapBB(FILEDATE(2009, 9, 1));
		  pEntry->ModifyDate = SwapBB(FILEDATE(2009, 9, 1));
		  pEntry->ModifyTime = SwapBB(FILETIME(0, 0, 0));
		  pEntry->StartCluster = (unsigned short)SwapBB(cluster); // for 68000
		  pEntry->HighCluster = fat32 ? (unsigned short)SwapBB(cluster >> 16) : 0; // for 68000
		  pEntry->FileSize = SwapBBBB(file->size); // for 68000
		  
		  // store dir entry
		  if (!lwrite(iDirectorySector - 1, sector_buffer)) {
		    iprintf("FileCreate(): directory write failed!\n");
		    return(0);
		  }
		  
		  file->start_cluster = cluster;
		  file->cluster = cluster;
		  file->sector = 0;
		  file->cluster_change = 1;   // one data cluster was already allocated
		  file->entry.sector = iDirectorySector - 1;
		  file->entry.index = iEntry & 0x0F;
		  
		  return(1);
		}
            }
        }

        if (iDirectory || fat32) // subdirectory is a linked cluster chain
        {
            iDirectoryCluster = NextCluster(iDirectoryCluster); // get next cluster in chain

            if (fat32 ? (iDirectoryCluster & 0x0FFFFFF8) == 0x0FFFFFF8 : (iDirectoryCluster & 0xFFF8) == 0xFFF8) // check if end of chain
                break; // no more clusters in chain

            iDirectorySector = data_start + cluster_size * (iDirectoryCluster - 2); // calculate first sector address of the new cluster
        }
        else
            break;
    }

    ErrorMessage("   Can\'t create config file!", 0);
    return(0);
}

// changing of allocated cluster number is not supported - new size must be within current cluster number
unsigned char UpdateEntry(fileTYPE *file) {
  DIRENTRY *pEntry;

  if(!lwrite) return 0;  // error

  if (!lread(file->entry.sector, sector_buffer)) {
    iprintf("UpdateEntry(): directory read failed!\n");
    return(0);
  }
  
  pEntry = (DIRENTRY*)sector_buffer;
  pEntry += file->entry.index;
  memcpy((void*)pEntry->Name, file->name, 11);
  pEntry->Attributes = file->attributes;
  pEntry->FileSize = SwapBBBB(file->size); // for 68000
  
  if (!lwrite(file->entry.sector, sector_buffer)) {
    iprintf("UpdateEntry(): directory write failed!\n");
    return(0);
  }
  
  return(1);
}

unsigned char FileWriteEnd(fileTYPE *file) {
  // check if current cluster is the end of the chain
  unsigned long marker = EOC;

  if(file->cluster != EOC) {
    do {
      unsigned long next_cluster = NextCluster(file->cluster);
      // NextCluster has made sure the right fat sector is already loaded
      
      unsigned long fat_index = CLUSTER2SECTOR(file->cluster);
      unsigned short buffer_index = CLUSTER2OFFSET(file->cluster);
      
      // mark cluster as used
      if(fat32) fat_buffer.fat32[buffer_index] = marker;
      else      fat_buffer.fat16[buffer_index] = marker;

      if(!FatSave(fat_index))
	return(0);

      // has a cluster been freed?
      if(!marker) file->cluster_change--;
      
      file->cluster = next_cluster;
      marker = 0;
    } while(file->cluster != EOC);
  }

  // update fat32 info sector
  if(info_sector && file->cluster_change) {
    struct InfoSector *isec = (struct InfoSector*)sector_buffer;

    if (!lread(info_sector, sector_buffer)) {
      iprintf("info_sector read failed!\n");
      return(0);
    }
    
    // check for valid info sector signs and markers
    if((isec->boot_sign != SwapBB(0xaa55)) ||
       (isec->magic != SwapBBBB(0x41615252)) ||         // RRaA
       (isec->signature != SwapBBBB(0x61417272)) ||     // rrAa
       (isec->free_clusters == SwapBBBB(0xffffffff)))   // free_clusters unused
      info_sector = 0;   // no valid info sector
    else {
      isec->free_clusters = SwapBBBB(SwapBBBB(isec->free_clusters) - file->cluster_change);
      
      // update info_sector
      if (!lwrite(info_sector, sector_buffer)) {
	iprintf("info_sector write failed!\n");
	return(0);
      }
    }
  }

  return(1);
}

// start a new file or use existing one
unsigned char FileNew(fileTYPE *file, char *name, int size) {
  if(FileOpen(file, name) != 0) {
    iprintf("File exists, using it\n");

    // adjust file size if required
    if(file->size != size) {
      file->size = size;
      if (!UpdateEntry(file)) {
	iprintf("File size update failed\n");
	return 0;
      }
    }
  } else {
    iprintf("File does not exist, creating it\n");
    strncpy(file->name, name, 11);
    file->attributes = 0;
    file->size = size;
    if(!FileCreate(0, file)) {
      iprintf("File creation failed\n");
      return 0;
    }
  }
  return 1;
}
