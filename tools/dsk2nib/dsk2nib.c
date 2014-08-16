/***********************************************************************
 *
 * Apple ][ .dsk file to .nib file format converter
 *
 * Stephen A. Edwards, sedwards@cs.columbia.edu
 *
 * Adapted from the "dsk2pdb" program supplied with the PalmApple/Appalm ][
 *
 ***********************************************************************
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

typedef	unsigned char BYTE;

#define VOLUME_NUMBER 254

#define TRACKS 35
#define SECTORS 16
#define SECTOR_SIZE 256
#define DOS_TRACK_BYTES (SECTORS * SECTOR_SIZE)

#define RAW_TRACK_BYTES 0x1A00


FILE *disk_file;
BYTE dos_track[SECTORS * SECTOR_SIZE];

BYTE raw_track[RAW_TRACK_BYTES];
BYTE *target; /* Where to write in the raw_track buffer */

#define write_byte(x) (*target++ = (x))

BYTE GCR_encoding_table[64] = {
  0x96, 0x97, 0x9A, 0x9B, 0x9D, 0x9E, 0x9F, 0xA6,
  0xA7, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF, 0xB2, 0xB3,
  0xB4, 0xB5, 0xB6, 0xB7, 0xB9, 0xBA, 0xBB, 0xBC,
  0xBD, 0xBE, 0xBF, 0xCB, 0xCD, 0xCE, 0xCF, 0xD3,
  0xD6, 0xD7, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE,
  0xDF, 0xE5, 0xE6, 0xE7, 0xE9, 0xEA, 0xEB, 0xEC,
  0xED, 0xEE, 0xEF, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6,
  0xF7, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF };

int	Swap_Bit[4] = { 0, 2, 1, 3 }; /* swap lower 2 bits */
BYTE	GCR_buffer[256];
BYTE	GCR_buffer2[86];

/* physical sector no. to DOS 3.3 logical sector no. table */
int	Logical_Sector[16] = {
  0x0, 0x7, 0xE, 0x6, 0xD, 0x5, 0xC, 0x4,
  0xB, 0x3, 0xA, 0x2, 0x9, 0x1, 0x8, 0xF };

/*
 * write an FM encoded value, used in writing address fields
 */
void FM_encode( BYTE data )
{
  write_byte( (data >> 1) | 0xAA );
  write_byte( data | 0xAA );
}

/*
 * Write 0xFF sync bytes
 */
void write_sync( int length )
{
  while( length-- ) write_byte( 0xFF );
}

void write_address_field( int volume, int track, int sector )
{
  /*
   * write address mark
   */
  write_byte( 0xD5 );
  write_byte( 0xAA );
  write_byte( 0x96 );

  /*
   * write Volume, Track, Sector & Check-sum
   */
  FM_encode( volume );
  FM_encode( track );
  FM_encode( sector );
  FM_encode( volume ^ track ^ sector );

  /*
   * write epilogue
   */
  write_byte( 0xDE );
  write_byte( 0xAA );
  write_byte( 0xEB );
}

/*
 * 6-and-2 group encoding: the heart of the "nibblization" procedure
 */
void encode62( BYTE *page )
{
  int i, j;

  /* 86 * 3 = 258, so the first two byte are encoded twice */
  GCR_buffer2[0] = Swap_Bit[page[1] & 0x03];
  GCR_buffer2[1] = Swap_Bit[page[0] & 0x03];

  /* save higher 6 bits in GCR_buffer and lower 2 bits in GCR_buffer2 */
  for( i = 255, j = 2; i >= 0; i--, j = j == 85? 0: j + 1 ) {
    GCR_buffer2[j] = (GCR_buffer2[j] << 2) | Swap_Bit[page[i] & 0x03];
    GCR_buffer[i] = page[i] >> 2;
  }

  /* clear off higher 2 bits of GCR_buffer2 set in the last call */
  for( i = 0; i < 86; i++ )
    GCR_buffer2[i] &= 0x3f;
}

void write_data_field(BYTE *page)
{
  int	i;
  BYTE	last, checksum;

  encode62(page);

  /* write prologue */
  write_byte( 0xD5 );
  write_byte( 0xAA );
  write_byte( 0xAD );

  /* write GCR encoded data */
  for ( i = 0x55, last = 0 ; i >= 0 ; --i ) {
    checksum = last ^ GCR_buffer2[i];
    write_byte( GCR_encoding_table[checksum] );
    last = GCR_buffer2[i];
  }
  for ( i = 0 ; i < 256 ; ++i ) {
    checksum = last ^ GCR_buffer[i];
    write_byte( GCR_encoding_table[checksum] );
    last = GCR_buffer[i];
  }

  /* write checksum and epilogue */
  write_byte( GCR_encoding_table[last] );
  write_byte( 0xDE );
  write_byte( 0xAA );
  write_byte( 0xEB );
}

int main(int argc, char **argv)
{
  char nibname[256], *p;
  FILE *nib_file;
  int track;

  if (argc < 2) {
    fprintf(stderr, "Usage: %s <DSK file> [NIB file]\n", argv[0]);    
    exit(1);
  }

  if (!(disk_file = fopen(argv[1], "rb"))) {
    fprintf(stderr, "Unable to mount disk file \"%s\"\n", argv[1]);
    exit(1);
  }

  if (argc > 2) {
    strcpy(nibname, argv[2]);
  } else {
    /* Strip leading pathname from DSK name */
    for (p = argv[1]; *p; p++) {
      if (*p == '/' || *p == '\\')
	argv[1] = p + 1;
    }
    strcpy(nibname, argv[1]);
    /* Strip trailing .dsk, if any, from DSK name */
    p = nibname + strlen(nibname);
    if (p[-4] == '.' &&
	(p[-3] == 'd' || p[-3] == 'D') &&
	(p[-2] == 's' || p[-2] == 'S') &&
	(p[-1] == 'k' || p[-1] == 'K')) p[-4] = 0;
    strcat(nibname, ".nib");
  }

  if (!(nib_file = fopen(nibname, "wb"))) {
    fprintf(stderr, "Unable to write \"%s\"\n", nibname);
    exit(1);
  }

  /* Read, convert, and write each track */

  for (track = 0 ; track < TRACKS ; ++track ) {
    int sector;

    fseek( disk_file, track * DOS_TRACK_BYTES, 0L );
    if ( fread(dos_track, 1, DOS_TRACK_BYTES, disk_file) != DOS_TRACK_BYTES ) {
      fprintf(stderr, "Unexpected end of disk data\n");
      exit(1);
    }

    target = raw_track;

    for ( sector = 0 ; sector < SECTORS ; sector ++ ) {
      write_sync( 38 );    /* Inter-sector gap */
      write_address_field( VOLUME_NUMBER, track, sector );
      write_sync( 8 );
      write_data_field( dos_track + Logical_Sector[sector] * SECTOR_SIZE );
    }

    /* Pad rest of buffer with sync bytes */
    
    while (target != &raw_track[RAW_TRACK_BYTES])
      write_byte( 0xff );

    if ( fwrite(raw_track, 1, RAW_TRACK_BYTES, nib_file) != RAW_TRACK_BYTES) {
      fprintf(stderr, "Error writing .nib file\n");
      exit(1);
    }
  }

  fclose(disk_file);
  fclose(nib_file);

  return 0;
}

/* Local Variables: */
/* compile-command: "cc -O -Wall -pedantic -ansi -o dsk2nib dsk2nib.c" */
/* End: */
