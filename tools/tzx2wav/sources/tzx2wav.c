/////////////////////////////////////////////////////////////////////
// TZX to VAV Converter v0.2 for Bloodshed Dev-C++ compiler        //
// (C) 2005-2006 Francisco Javier Crespo <tzx2wav@ya.com>          //
//                                                                 //
// Originally based on source code from these works:               //
// PLAYTZX v0.60b for Watcom C compiler (C) 1997-2004 Tomaz Kac    //
// PLAYTZX Unix v0.12b (C) 2003 Tero Turtiainen / Fredrick Meunier //
/////////////////////////////////////////////////////////////////////

// List of things TO DO:
// - Friendly functions to deal with processor endianness
//   (http://www.intel.com/design/intarch/papers/endian.pdf)
// - Reorganize old original DOS-oriented code
// - Obtain C64 TZX files to be able to check valid output
// - Introduce new TZX v1.20 WIP draft specifications
// - Suggest new TZX blocks for Single Pulse bits / Manchester Encoding
// - Take care of possible buffer overflow with malformed TZX files

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <strings.h>
#include <sys/types.h>
#include <sys/stat.h>
#include "zlib.h"
#include "hardware.h"

#ifndef O_BINARY
#define O_BINARY 0
#endif

const char *build= "20060225";

#define MAJREV 1        // Major revision of the format this program supports
#define MINREV 13       // Minor revision of the format this program supports

// C64 Loader defines ...

#define ROM_S_HALF  616     // ROM Loader SHORT  Half Wave
#define ROM_M_HALF  896     // ROM Loader MEDIUM Half Wave
#define ROM_L_HALF 1176     // ROM Loader LONG   Half Wave

#define STT_0_HALF  426     // Standard Turbo Tape BIT 0 Half Wave
#define STT_1_HALF  596     // Standard Turbo Tape BIT 1 Half Wave

// Other defines ...

#define LOAMP     0x26      // Low Level Amplitude  (-3 dB)
#define HIAMP     0xDA      // High Level Amplitude (-3 dB)
#define SGNLOW    0
#define SGNHIGH   1
#define WAVBUFLEN 0x10000   // 64 KB memory buffer for WAV file
#define CSWBUFLEN 0x10000   // 64 KB memory buffer for CSW file
#define ZBUFLEN   0x04000   // 16 KB memory buffer for CSW ZLIB output

typedef struct {
  unsigned int ChunkID;
  unsigned int ChunkSize;
  unsigned int Format;
  unsigned int fmtChunkID;
  unsigned int fmtChunkSize;
  unsigned short AudioFormat;
  unsigned short NumChannels;
  unsigned int SampleRate;
  unsigned int ByteRate;
  unsigned short BlockAlign;
  unsigned short BitsPerSample;
  unsigned int dataChunkID;
  unsigned int dataChunkSize;
} WavHdr;

WavHdr header;               // WAV file header
unsigned char *wavbuf;       // Buffer for WAV file
unsigned int wavpos;         // Current position in WAV buffer
int stereo = 0;              // Stereo flag for CDDA waves

unsigned char *cswbuf;       // Buffer for CSW file
unsigned int cswpos;         // Current position in CSW buffer
z_stream zs;                 // ZLIB stream handler
unsigned char *zbuf;         // Buffer for ZLIB output
int zflush;                  // Flush state for ZLIB
unsigned int cswpulses = 0;  // Total number of pulses for CSW header
int csw = 0;                 // Create CSW file instead of WAV file

unsigned int sgn;  // Sign of the wave being played
int amp;  // Amplitude of the current signal (to be deprecated)
unsigned int freq = 44100;              // Default Sample Frequency
unsigned char ampmono[2]={0x26,0xDA};        // Amplitudes of mono wave 
unsigned char ampstereo[2][2]={{0x62,0xA5},{0x9E,0x5A}};  // Amplitudes of stereo wave

int prvi;
int n,m;
int num;
unsigned char *d;
int line=3;
int ifh;                // Input File Handle
int ofh;                // Output File Handle
unsigned int flen;      // File Length
unsigned char *mem;     // File in Memory
int pos;                // Position in File
int curr;               // Current block that is playing
int numblocks;          // Total Num. of blocks
unsigned long oflen;    // Length of output file
int block[2048];        // Array of Block starts
double cycle;           // Frequency / 3500000 (Z80 clock)

int cpc=0;              // Amstrad CPC tape ?
int sam=0;              // SAM Coupe tape ?

int id;                 // Current Block ID
int pilot;              // Len of Pilot signal (in hp's)
int sb_pilot;           // Pilot pulse
int sb_sync1;           // Sync first half-period (hp)
int sb_sync2;           // Sync second
int sb_bit0;            // Bit-0
int sb_bit1;            // Bit-1
int sb_pulse;           // Pulse in Sequence of pulses and direct recording block
int lastbyte;           // How many bits are in last byte of data ?
int pause_ms;              // Pause after current block (in milliseconds)
int skippause=0;        // Overrides pause value in last TZX block

int singlepulse;        // Flag to activate single pulse waves
int manchester;         // Flag to activate manchester encoded waves

unsigned char *data;    // Data to be played
int datalen;            // Len of ^^^
int datapos;            // Position in ^^^
int bitcount;           // How many bits to play in current byte ?
int sb_bit;             // should we play bit 0 or 1 ?
char databyte;          // Current Byte to be replayed of the data
signed short jump;      // Relative Jump 
int not_rec;            // Some blocks were not recognised ??
int files=0;            // Number of Files on the command line
char finp[255];         // Input File  (First Command Line Option)
char fout[255];         // Output File (Second Command Line Option or First with .WAV)
char errstr[255];       // Error String
int starting=1;         // starting block
int ending=0;           // ending block

int info=0;             // if info=1 then show EXTENSIVE information 
                        //    info=2 then show ONE LINE of Info per block
int pages=0;            // Waiting after each page of the info ?
int expand=0;           // Expand Groups ?
int draw=1;             // Local flag for outputing a line when in a group
int mode128=0;          // Are we working in 128k mode ? (for Stop in 48k block)

int nfreq=0;            // Did we choose new frequency with /freq switch ?
char k;
int speed;
int x,last,lastlen;

int loop_start=0;       // Position of the last Loop Start block
int loop_count=0;       // Counter of the Loop
int call_pos=0;         // Position of the last Call Sequence block
int call_num=0;         // Number of Calls in the last Call Sequence block
int call_cur=0;         // Current Call to be made
int num_sel;            // Number of Selections in the Select block
int jumparray[256];     // Array of all possible jumps in Select block

int sb_bit0_f, sb_bit0_s, sb_bit1_f, sb_bit1_s, xortype, sb_finishbyte_f,
    sb_finishbyte_s, sb_finishdata_f, sb_finishdata_s, num_lead_in, xorvalue;
int trailing, sb_trailing;
char lead_in_byte;
int endian;
char add_bit;

int inv = 0;

char tstr[255];
char tstr2[255];
char tstr3[255];
char tstr4[255];
char spdstr[255];
char pstr[255];

int numt, nump, t2;

/////////////////////////////////////////////////
// Garbage collector and error handling routines
/////////////////////////////////////////////////

void GarbageCollector (void)
{
  if (zbuf != NULL) free(zbuf);
  if (cswbuf != NULL) free(cswbuf);
  if (wavbuf != NULL) free(wavbuf);
  if (mem != NULL) free(mem);

  if (ofh != 0) close(ofh);
  if (ifh != 0) close(ifh);
}

void Error (char *errstr)
{
  GarbageCollector();  
  printf("\n-- Error: %s\n",errstr);
  exit(-1);
}

///////////////////////////////
// CSW v1.01 handling routines
///////////////////////////////

void CSW1_Init(void)
{
  // Official CSW format documentation at:
  // http://www.ramsoft.bbk.org/csw.html

  unsigned short Revision = 0x0101;
  unsigned char CompType = 1;
  unsigned int Reserved = 0;
 
  if (freq > 65535)
    Error("Sample rates > 65535 Hz cannot be used in CSW v1.01 format");
  
  ofh = open(fout, O_WRONLY | O_BINARY | O_CREAT | O_TRUNC, S_IREAD | S_IWRITE);
  if (ofh == -1)
    Error("Output file could not be created");

  cswbuf = (unsigned char *) malloc(CSWBUFLEN);
  if (cswbuf == NULL)
  {
    Error("Not enough memory to set up CSW file buffer!");
  }
  cswpos = 0;

  write(ofh,"Compressed Square Wave\032",23);
  write(ofh,&Revision,2);   // Major & Minor revision
  write(ofh,&freq,2);       // Sample Rate
  write(ofh,&CompType,1);   // Compression Type
  write(ofh,&inv,1);        // Polarity
  write(ofh,&Reserved,3);   // Reserved bytes
}

void CSW1_Write (unsigned int samples)
{
  // I/O operations are more expensive than CPU operations.
  // We are using a 64 KB memory buffer.

  if (samples < 256)
  {
    cswbuf[cswpos++] = samples;  // Store number of samples
    if (cswpos == CSWBUFLEN)
    {
      write(ofh,cswbuf,CSWBUFLEN);
      cswpos = 0;
    }
  }
  else
  {
    if ((cswpos+5) >= CSWBUFLEN)
    {
      write(ofh,cswbuf,cswpos);
      cswpos = 0;
    }     
    cswbuf[cswpos++] = 0;  // Store signal for Little Endian integer
    cswbuf[cswpos++] = (samples & 0x000000FF);
    cswbuf[cswpos++] = (samples & 0x0000FF00) >> 8;
    cswbuf[cswpos++] = (samples & 0x00FF0000) >> 16;
    cswbuf[cswpos++] = (samples & 0xFF000000) >> 24;
  }
}

void CSW1_Stop(void)
{
  if (cswpos)
    write(ofh,cswbuf,cswpos);
  free(cswbuf); cswbuf = NULL;
  oflen = lseek(ofh,0,SEEK_END);
  close(ofh); ofh = 0;
}

///////////////////////////////
// CSW v2.00 handling routines
///////////////////////////////

void CSW2_Init(void)
{

  int err;
  unsigned short Revision = 2;
  unsigned char CompType = 2;
  unsigned char HeaderExt = 0;
  char cswapp[16] = "TZX2WAV v0.2";

  ofh = open(fout, O_WRONLY | O_BINARY | O_CREAT | O_TRUNC, S_IREAD | S_IWRITE);
  if (ofh == -1)
    Error("Output file could not be created");

  cswbuf = (unsigned char *) malloc(CSWBUFLEN);
  if (cswbuf == NULL)
  {
    Error("Not enough memory to set up CSW file buffer!");
  }
  cswpos = 0;
 
  zbuf = (unsigned char *) malloc(ZBUFLEN);
  if (zbuf == NULL)
  {
    Error("Not enough memory to set up CSW ZLIB buffer!");
  }

  zs.zalloc = Z_NULL;
  zs.zfree = Z_NULL;
  zs.opaque = Z_NULL;
  err = deflateInit(&zs,9);
  if (err != Z_OK)
  {
    Error("Error initializing CSW ZLIB buffer!");
  }
   
  zflush = Z_NO_FLUSH;

  write(ofh,"Compressed Square Wave\032",23);
  write(ofh,&Revision,2);   // Major & Minor revision
  write(ofh,&freq,4);       // Sample Rate
  write(ofh,&cswpulses,4);  // Total number of pulses
  write(ofh,&CompType,1);   // Compression Type
  write(ofh,&inv,1);        // Polarity
  write(ofh,&HeaderExt,1);  // Header extension bytes
  write(ofh,cswapp,16);     // Encoding Application
}

void ZLIBWrite(unsigned char *source, int length)
{
  // Compresses source data into ZLIB buffer and writes to file if full   

  int err;
  unsigned int filled;
  
  zs.avail_in = length;
  zs.next_in = source;

  do {
    zs.avail_out = ZBUFLEN;
    zs.next_out = zbuf;
    err = deflate(&zs,zflush);
    filled = ZBUFLEN - zs.avail_out;
    write (ofh,zbuf,filled);
  } while (zs.avail_out == 0);
}

void CSW2_Write (unsigned int samples)
{
  // I/O operations are more expensive than CPU operations.
  // We are using a 64 KB memory buffer.

  cswpulses++;
  if (samples < 256)
  {
    cswbuf[cswpos++] = samples;  // Store number of samples
    if (cswpos == CSWBUFLEN)
    {
      ZLIBWrite(cswbuf,CSWBUFLEN);
      cswpos = 0;
    }
  }
  else
  {
    if ((cswpos+5) >= CSWBUFLEN)
    {
      ZLIBWrite(cswbuf,cswpos);
      cswpos = 0;
    }
    cswbuf[cswpos++] = 0;  // Store signal for Little Endian integer
    cswbuf[cswpos++] = (samples & 0x000000FF);
    cswbuf[cswpos++] = (samples & 0x0000FF00) >> 8;
    cswbuf[cswpos++] = (samples & 0x00FF0000) >> 16;
    cswbuf[cswpos++] = (samples & 0xFF000000) >> 24;
  }
}

void CSW2_Stop(void)
{
  // Flushes last ZLIB buffer and updates CSW file header

  int len;
  int err;
  int done = 0;
  
  if (cswpos)
  {
    zflush = Z_FINISH;             
    ZLIBWrite(cswbuf,cswpos);
  }

  deflateEnd(&zs);
  free(zbuf); zbuf = NULL;
  free(cswbuf); cswbuf = NULL;

  lseek(ofh,0x1D,SEEK_SET);
  write(ofh,&cswpulses,4);
  oflen = lseek(ofh,0,SEEK_END);
  close(ofh); ofh = 0;
}

//////////////////////////////
// WAV file handling routines
//////////////////////////////

void WAV_Init(void)
{
  // Nice WAV format info in this web site:
  // http://ccrma.stanford.edu/courses/422/projects/WaveFormat/

  ofh = open(fout, O_WRONLY | O_BINARY | O_CREAT | O_TRUNC, S_IREAD | S_IWRITE);
  if (ofh == -1)
    Error("Output file could not be created");

  wavbuf = (unsigned char *) malloc(WAVBUFLEN);
  if (wavbuf == NULL)
    Error("Not enough memory to set up WAV file buffer!");

  header.ChunkID = 0x46464952;      // "RIFF" ID
  header.ChunkSize = 40;
  header.Format = 0x45564157;       // "WAVE" ID
  header.fmtChunkID = 0x20746D66;   // "fmt " ID
  header.fmtChunkSize = 16;
  header.AudioFormat = 1;           // PCM Linear Quantization
  header.SampleRate = freq;
  header.dataChunkID = 0x61746164;  // "data" ID
  header.dataChunkSize = 0;

  if (stereo)
  {
    header.NumChannels = 2;
    header.BitsPerSample = 16;
    header.ByteRate = freq * 4;
    header.BlockAlign = 4;
  }
  else
  {
    header.NumChannels = 1;
    header.BitsPerSample = 8;
    header.ByteRate = freq;
    header.BlockAlign = 1;
  }

  write(ofh,&header,44);
  wavpos = 0;
}

void WAV_Write (unsigned int len)
{
  // I/O operations are more expensive than CPU operations.
  // We are using a 64 KB memory buffer.

  if (amp==LOAMP) sgn=0;
  else sgn=1;

  if (stereo)
  {
    header.dataChunkSize += (len * 4);
    // 16-bit stereo samples are stored as signed integers
    // First left channel, then right channel
    while (len)
    {
      wavbuf[wavpos++] = ampstereo[sgn][0];
      wavbuf[wavpos++] = ampstereo[sgn][1];
      wavbuf[wavpos++] = ampstereo[sgn][0];
      wavbuf[wavpos++] = ampstereo[sgn][1];  
      len--;
      if (wavpos == WAVBUFLEN)
      {
        write(ofh,wavbuf,WAVBUFLEN);
        wavpos = 0;
      }
    }
  }
  else
  {  
    header.dataChunkSize += len;
    // 8-bit mono samples are unsigned integers
    while (len)
    {
      wavbuf[wavpos++] = ampmono[sgn];
      len--;
      if (wavpos == WAVBUFLEN)
      {
        write(ofh,wavbuf,WAVBUFLEN);
        wavpos = 0;
      }
    }
  }
}

void WAV_Stop(void)
{
  // Flushes last WAV memory buffer and updates WAV file header

  if (wavpos)
    write(ofh,wavbuf,wavpos);
   
  lseek(ofh,0,SEEK_SET);
  header.ChunkSize = header.dataChunkSize + 36;
  write(ofh,&header,44);
  oflen = lseek(ofh,0,SEEK_END);
  free(wavbuf); wavbuf = NULL;
  close(ofh); ofh = 0;
}

//////////////////////////////////
// Generic wave handling routines
//////////////////////////////////

unsigned int Samples (unsigned int n)
{
  // Convert a sampling value in Z80 T-States to samples for wave output 
  return ((unsigned int)(0.5 + (cycle*(double)n)));
}

void ToggleAmp(void)
{
  // Toggles the sign of the wave
  // WHOLE CONCEPT TO BE RECODED IN ToggleSgn();

  if (amp==LOAMP) amp=HIAMP;
  else amp=LOAMP;
}

void PlayWave(unsigned int len)
{
  // Generate wave data for "len" samples.
  
  if (inv)  // Reverse the signal if needed
  {
    if (amp == LOAMP) amp = HIAMP;
    else amp = LOAMP;
  }

  switch (csw)
  {
    case 1  : CSW1_Write(len); break;
    case 2  : CSW2_Write(len); break;
    default : WAV_Write(len); break;
  }
}

void PauseWave (unsigned int pause_ms)
{
  // Waits for "pause" milliseconds

  int p;
  if ((!skippause)||(curr!=(numblocks-1)))
  {
    p = (unsigned int)((((float) pause_ms)*freq)/1000.0);
    PlayWave(p);
  }
}

/////////////////////////////
// TZX Commodore 64 routines
/////////////////////////////

void PlayC64(unsigned int len)
{
  PlayWave(len);
  ToggleAmp();
  PlayWave(len);
  ToggleAmp();
}

void PlayC64ROMByte(char byte, int finish)
{
xorvalue=xortype;
while (bitcount)
    {
    if (!endian) sb_bit=byte&0x01;
    else        sb_bit=byte&0x80;
    if (sb_bit)
        {
        if (sb_bit1_f) PlayC64(sb_bit1_f);
        if (sb_bit1_s) PlayC64(sb_bit1_s);
        xorvalue^=sb_bit;
        }
    else
        {
        if (sb_bit0_f) PlayC64(sb_bit0_f);
        if (sb_bit0_s) PlayC64(sb_bit0_s);
        xorvalue^=sb_bit;
        }
    if (!endian) byte>>=1;
    else        byte<<=1;
    bitcount--;
    }
if (xortype != 0xFF)
    {
    if (xorvalue)
        {
        if (sb_bit1_f) PlayC64(sb_bit1_f);
        if (sb_bit1_s) PlayC64(sb_bit1_s);
        }
    else
        {
        if (sb_bit0_f) PlayC64(sb_bit0_f);
        if (sb_bit0_s) PlayC64(sb_bit0_s);
        }
    }
if (!finish)
    {
    if (sb_finishbyte_f) PlayC64(sb_finishbyte_f);
    if (sb_finishbyte_s) PlayC64(sb_finishbyte_s);
    }
else
    {
    if (sb_finishdata_f) PlayC64(sb_finishdata_f);
    if (sb_finishdata_s) PlayC64(sb_finishdata_s);
    }
}

void PlayC64TurboByte(char byte)
{
  int add_num;

  add_num = add_bit & 3;

  if (add_num && !(add_bit&4))
  {
    while(add_num)
    {
      if (add_bit & 8) PlayC64(sb_bit1);
      else PlayC64(sb_bit0);
      add_num--;
    }
  }

  while (bitcount)
  {
    if (!endian) sb_bit=byte&0x01;
     else        sb_bit=byte&0x80;
    if (sb_bit)  PlayC64(sb_bit1);
     else        PlayC64(sb_bit0);
    if (!endian) byte>>=1;
     else        byte<<=1;
    bitcount--;
  }

  if (add_num && (add_bit&4))
  {
    while(add_num)
    {
      if (add_bit&8) PlayC64(sb_bit1);
      else           PlayC64(sb_bit0);
      add_num--;
    }
  }
}

////////////////////////////////
// Game identification routines
////////////////////////////////

void GetC64ROMName(char *name, unsigned char *data)
{
  char d;

  for (n=0; n<16; n++)
  {
    d=data[14+n]; 
    if (d<32 || d>125)
      name[n]=' ';
    else
      name[n]=d;
  }
  name[n]=0;
}

void GetC64StandardTurboTapeName(char *name, unsigned char *data)
{
  char d;

  for (n=0; n<16; n++)
  {
    d=data[15+n]; 
    if (d<32 || d>125)
      name[n]=' ';
    else
      name[n]=d;
  }
  name[n]=0;
}

void IdentifyC64ROM(int pos, unsigned char *data, int type)
{
  char name[255];

  // Determine Loader type
  if ((sb_pilot == ROM_S_HALF) && (sb_sync1 == ROM_L_HALF) && (sb_sync2 == ROM_M_HALF) &&
      (sb_bit0_f == ROM_S_HALF) && (sb_bit0_s == ROM_M_HALF) && (sb_bit1_f == ROM_M_HALF) &&
      (sb_bit1_s == ROM_S_HALF) && (xortype == 0x01))
  {
    // ROM Loader
    if ((data[0]==0x89) && (data[1]==0x88) && (data[2]==0x87) && (data[3]==0x86) &&
        (data[4]==0x85) && (data[5]==0x84) && (data[6]==0x83) && (data[7]==0x82) &&
        (data[8]==0x81))
    {
      if (pos==202)
      {
        if (!type)
        {
          strcpy(name,"Header: ");
          GetC64ROMName(name+8, data);
        }
        else
        {
          strcpy(name,"ROM Header: ");
          GetC64ROMName(name+12, data);
        }
      }
      else
      {
        if (!type)
        {
          strcpy(name,"Data Block              ");
        }
        else
        {
          strcpy(name,"ROM: Data Block");
        }
      }
    }
    else
    {
      if (!type) strcpy(name,"------------------------");
      else       strcpy(name,"ROM: Last Block Repeated");
    }
    strcpy(tstr,name);
    strcpy(spdstr,"C64 ROM Data ");
    return;
  }

  if (!type) strcpy(tstr,"------------------------");
  else       strcpy(tstr,"Unknown");
  strcpy(spdstr,"C64 Data     ");
}

void IdentifyC64Turbo(int pos, unsigned char *data, int type)
{
  char name[255];

  // Determine Loader type
  if (sb_bit0 == STT_0_HALF && sb_bit1 == STT_1_HALF && lead_in_byte == 0x02)
  {
    // Standard Turbo Tape Loader
    if (data[0]==0x09 && data[1]==0x08 && data[2]==0x07 && data[3]==0x06 &&
        data[4]==0x05 && data[5]==0x04 && data[6]==0x03 && data[7]==0x02 &&
        data[8]==0x01)
    {
      if (pos==32 && data[9] != 0x00)
      {
        if (!type)
        {
          strcpy(name,"Header: ");
          GetC64StandardTurboTapeName(name+8, data);
        }
        else
        {
          strcpy(name,"TurboTape Header: ");
          GetC64StandardTurboTapeName(name+18, data);
        }
      }
      else
      {
        if (!type) strcpy(name,"------------------------");
        else       strcpy(name,"TurboTape Data Block");
      }
    }
    else
    {
      if (!type) strcpy(name,"------------------------");
      else       strcpy(name,"TurboTape Unknown");
    }
    strcpy(tstr,name);
    strcpy(spdstr,"C64 Turbo    ");
    return;
  }
  if (!type) strcpy(tstr,"------------------------");
  else       strcpy(tstr,"Unknown");
  strcpy(spdstr,"C64 Data     ");
}

void Identify(int len, unsigned char *temp, int type)
{
  int n;
  int s;

  if (cpc)
  {
    if (temp[0]==44)
    {
      if (!type) s=4;
       else s=0;
      strcpy(tstr,"    ");
      for (n=0; n<16; n++)
      {
        if (temp[n+1]) tstr[n+s]=temp[n+1];
        else tstr[n+s]=' ';
      }
      for (n=0; n<4; n++) tstr[n+s+16]=' ';
      tstr[n+s+16]=0;
    }
    else
    {
      if (!type)
        strcpy(tstr,"    ------------------  ");
      else
        strcpy(tstr,"Headerless");
    }
    return;
  }

  if (sam)
  {
    if (temp[0]==1 && (len>80 && len<84) && (temp[1]>=0x10 && temp[1]<=0x13))
    {
      if (!type)
      {
        s=14;
        switch (temp[1])
        {
          case 0x10: strcpy(tstr,"    Program : "); break;
          case 0x11: strcpy(tstr," Num. Array : "); break;
          case 0x12: strcpy(tstr,"Char. Array : "); break;
          case 0x13: strcpy(tstr,"      Bytes : "); break;
        }
      }
      else
      {
        switch (temp[1])
        {
          case 0x10: strcpy(tstr,"Program : "); s=10; break;
          case 0x11: strcpy(tstr,"Num. Array : "); s=13; break;
          case 0x12: strcpy(tstr,"Char. Array : "); s=14; break;
          case 0x13: strcpy(tstr,"Bytes : "); s=8; break;
        }
      }
      for (n=0; n<10; n++)
      {
        if (temp[n+2]>31 && temp[n+2]<127)
          tstr[n+s]=temp[n+2];
        else
          tstr[n+s]=32;
      }
      tstr[n+s]=0;
    }
    else
    {
      if (!type)
        strcpy(tstr,"    --------------------");  // Not Header
      else
        strcpy(tstr,"Headerless");
    }
    return;
  }

  if (temp[0]==0 && (len==19 || len==20) && temp[1]<4)
  {
    if (!type)
    {
      s=14;
      switch (temp[1])
      {
        case 0x00: strcpy(tstr,"    Program : "); break;
        case 0x01: strcpy(tstr," Num. Array : "); break;
        case 0x02: strcpy(tstr,"Char. Array : "); break;
        case 0x03: strcpy(tstr,"      Bytes : "); break;
      }
    }
    else
    {
      switch (temp[1])
      {
        case 0x00: strcpy(tstr,"Program : "); s=10; break;
        case 0x01: strcpy(tstr,"Num. Array : "); s=13; break;
        case 0x02: strcpy(tstr,"Char. Array : "); s=14; break;
        case 0x03: strcpy(tstr,"Bytes : "); s=8; break;
      }
    }
    for (n=0; n<10; n++)
    {
      if (temp[n+2]>31 && temp[n+2]<127)
        tstr[n+s]=temp[n+2];
      else
        tstr[n+s]=32;
    }
    tstr[n+s]=0;
  }
  else
  {
    if (!type)
      strcpy(tstr,"    --------------------");  // Not Header
    else
      strcpy(tstr,"Headerless");
  }
}

//////////////////////////////////////////////////////////
// Conversion routines to fetch bytes in Big Endian order
//////////////////////////////////////////////////////////

unsigned int Get2(unsigned char *pointer)
{
  return (pointer[0] | (pointer[1]<<8));
}

unsigned int Get3(unsigned char *pointer)
{
  return (pointer[0] | (pointer[1]<<8) | (pointer[2]<<16));
}

unsigned int Get4(unsigned char *pointer)
{
  return (pointer[0] | (pointer[1]<<8) | (pointer[2]<<16) | (pointer[3]<<24));
}

/////////////////////////
// Miscelaneous routines
/////////////////////////

char MirrorByte(char s)
{
  return((s<<7)+((s<<5)&64)+((s<<3)&32)+((s<<1)&16)+((s>>1)&8)+((s>>3)&4)+((s>>5)&2)+(s>>7));
}

int getnumber(char *s)
{
  // Returns the INT number contained in string *s

  int i;
  sscanf(s,"%d",&i); return(i);
}

void ChangeFileExtension(char *str,const char *ext)
{
  // Changes the File Extension of String *str to *ext
  
  int n;
  n=strlen(str);
  while (str[n]!='.') n--;
  n++;
  str[n]=0;
  strcat(str,ext);
}

void invalidoption(char *s)
{
  // Prints the Invalid Option error

  sprintf(errstr,"Invalid Option %s !",s);
  Error(errstr);
}

char * GetCheckSum(unsigned char *data, unsigned int len)
{
  // Calculates a XOR checksum for a block and returns a STRING containing the result
  
  unsigned int n;
  unsigned char csum = 0;

  for (n=0; n<len-1; n++)
    csum ^= data[n];
  if (csum == data[len-1])
    return("OK");
  else {
    sprintf(pstr,"Wrong, should be %d ($%02X)",csum,csum);
    return(pstr);
  }
}

void CopyString(char *destination, unsigned char *source, unsigned int len)
{
  // Could just use strcpy ... 

  unsigned int n;
  for (n=0; n<len; n++)
    destination[n]=source[n];
  destination[n]=0;
}

void MakeFixedString(char *s, int i)
{
  // This will create a fixed length string from null-terminated one...

  int n=0;
  int k=0;

  while (i)
  {
    if (!s[n]) k=1;
    if (k) s[n]=' ';
    n++;
    i--;
  }
  s[n]=0;
}

void writeout(char *s)
{
  // Simple and not too accurate method of waiting after pages ...
  // PAGES SUPPORT AND ROUTINE TO BE DEPRECATED

  char k;
  if (pages)
  {
    line++;
    if (line>21)
    {
      printf("scroll?\n");
      k=getchar();
      if (k==27) Error("ESCAPE key pressed!");
      if (!k) getchar();
      printf("\n");
      line=0;
    }
  }
  printf(s);
}

int MultiLine(char *s, int spaces, char *d)
{
  // This will convert a text which has lines separated by a single LF (13 dec)
  // character to the text that can be outputed by MSDOS (LF NL) ... it will also
  // Add a number of spaces to the beginning of each line (EXCEPT the first one -
  // so you can use the Description: Text stuff ;) )
  // NOTE: Some UNIX system like LINUX can cope with just LF char (13), some
  //       other systems will need just CR char (10) ... experiment :)

  int n=0;
  int m=0;
  int i;
  int l=0;

  while (s[n])
  {
    if (s[n]==13)
    {
      d[m]=13;
      d[m+1]=10;  // Here is the MS-DOS output for line-end
      m+=2;
      for (i=0; i<spaces; i++)
      {
        d[m]=' ';
        m++;
      }
      l++;
    }
    else
    {
      d[m]=s[n];
      m++;
    }
    n++;
  }
  d[m]=0;
  return(l);
}

///////////////////////////////
// TZX Blocks Parsing routines
///////////////////////////////

void Analyse_ID10 (void)  // Standard Loading Data block
{
  pause_ms=Get2(&data[0]);
  datalen=Get2(&data[2]);
  data+=4;
  if (data[0]==0x00) pilot=8064;
    else pilot=3220;
  sb_pilot=Samples(2168);
  sb_sync1=Samples(667);
  sb_sync2=Samples(735);
  sb_bit0=Samples(885);
  sb_bit1=Samples(1710);
  lastbyte=8;
  if (info==1)
  {
    Identify(datalen,data,1);
    sprintf(pstr,"Block %03d (%05X):  10 - Standard Loading Data - %s\n",curr+1,block[curr]+10,tstr); writeout(pstr);
    sprintf(tstr,"                Length: %5d bytes\n",datalen); writeout(tstr);
    sprintf(tstr,"                  Flag: %5d ($%02X)\n",data[0],data[0]); writeout(tstr);
    sprintf(tstr,"              CheckSum: %5d ($%02X) - %s\n",data[datalen-1],data[datalen-1],GetCheckSum(data,datalen)); writeout(tstr);
    sprintf(tstr,"     Pause after block: %5d milliseconds\n\n",pause_ms); line++; writeout(tstr);
  }
}

void Analyse_ID11 (void)  // Custom Loading Data block
{
  sb_pilot=Samples(Get2(&data[0]));
  sb_sync1=Samples(Get2(&data[2]));
  sb_sync2=Samples(Get2(&data[4]));
  sb_bit0=Samples(Get2(&data[6]));
  sb_bit1=Samples(Get2(&data[8]));
  speed=(int) ((1710.0/(double) Get2(&data[8]))*100.0);
  pilot=Get2(&data[10]);
  lastbyte=(int) data[12];
  pause_ms=Get2(&data[13]);
  datalen=Get3(&data[15]);
  data+=18;
  if (info==1)
  {
    Identify(datalen,data,1);
    sprintf(pstr,"Block %03d (%05X):  11 - Custom Loading Data - %s\n",curr+1,block[curr]+10,tstr); writeout(pstr);
    sprintf(tstr,"                Length: %5d bytes\n",datalen); writeout(tstr);
    sprintf(tstr,"                  Flag: %5d ($%02X)\n",data[0],data[0]); writeout(tstr);
    if (!cpc)
      { sprintf(tstr,"              CheckSum: %5d ($%02X) - %s\n",data[datalen-1],data[datalen-1],GetCheckSum(data,datalen)); writeout(tstr); }
    sprintf(tstr,"           Pilot pulse: %5d T-States\n",Get2(data-18)); writeout(tstr);
    sprintf(tstr,"          Pilot length: %5d pulses\n",pilot); writeout(tstr);
    sprintf(tstr,"      Sync first pulse: %5d T-States\n",Get2(data-16)); writeout(tstr);
    sprintf(tstr,"     Sync second pulse: %5d T-States\n",Get2(data-14)); writeout(tstr);
    sprintf(tstr,"           Bit-0 pulse: %5d T-States\n",Get2(data-12)); writeout(tstr);
    sprintf(tstr,"           Bit-1 pulse: %5d T-States\n",Get2(data-10)); writeout(tstr);
    sprintf(tstr,"        Last byte used: %5d bits\n",lastbyte); writeout(tstr);
    sprintf(tstr,"     Pause after block: %5d milliseconds\n\n",pause_ms); line++; writeout(tstr);
  }
}

void Analyse_ID12 (void)  // Pure Tone
{
  sb_pilot=Samples(Get2(&data[0]));
  pilot=Get2(&data[2]);
  if (info!=1)
  {
    if (draw) printf("    Pure Tone             Length: %5d\n",pilot);
    if (info!=2)
    {
      while (pilot)
      {
        PlayWave(sb_pilot);
        ToggleAmp();
        pilot--; }
    }
  }
  else
  {
    sprintf(tstr,"Block %03d (%05X):  12 - Pure Tone\n",curr+1,block[curr]+10); writeout(tstr);
    sprintf(tstr,"          Pulse length: %5d T-States\n",Get2(data)); writeout(tstr);
    sprintf(tstr,"           Tone length: %5d pulses\n\n",pilot); line++; writeout(tstr);
  }
}

void Analyse_ID13 (void)  // Sequence of Pulses
{
  pilot=(int) data[0]; data++;
  if (info!=1)
  {
    if (draw) printf("    Sequence of Pulses    Length: %5d\n",pilot);
    if (info!=2)
    {
      while(pilot)
      {
        sb_pulse = Samples(Get2(&data[0]));
        PlayWave(sb_pulse);
        ToggleAmp();
        pilot--;
        data+=2;
      }
    }
  }
  else
  {
    sprintf(tstr,"Block %03d (%05X):  13 - Sequence of Pulses\n",curr+1,block[curr]+10); writeout(tstr);
    sprintf(tstr,"      Number of Pulses: %5d\n\n",pilot); line++; writeout(tstr);
  }
}

void Analyse_ID14 (void)  // Pure Data
{
  sb_pilot=pilot=sb_sync1=sb_sync2=0;
  sb_bit0=Samples(Get2(&data[0]));
  sb_bit1=Samples(Get2(&data[2]));
  speed=(int) ((1710.0/(double) Get2(&data[2]))*100.0);
  lastbyte=(int) data[4];
  pause_ms=Get2(&data[5]);
  datalen=Get3(&data[7]);
  data+=10;
  if (info==1)
  {
    sprintf(tstr,"Block %03d (%05X):  14 - Pure Data\n",curr+1,block[curr]+10); writeout(tstr);
    sprintf(tstr,"                Length: %5d bytes\n",datalen); writeout(tstr);
    sprintf(tstr,"                  Flag: %5d ($%02X)\n",data[0],data[0]); writeout(tstr);
    sprintf(tstr,"              CheckSum: %5d ($%02X) - %s\n",data[datalen-1],data[datalen-1],GetCheckSum(data,datalen)); writeout(tstr);
    sprintf(tstr,"           Bit-0 pulse: %5d T-States\n",Get2(data-10)); writeout(tstr);
    sprintf(tstr,"           Bit-1 pulse: %5d T-States\n",Get2(data-8)); writeout(tstr);
    sprintf(tstr,"        Last byte used: %5d bits\n",lastbyte); writeout(tstr);
    sprintf(tstr,"     Pause after block: %5d milliseconds\n\n",pause_ms); line++; writeout(tstr);
  }
}

void Analyse_ID15 (void)  // Direct Recording
{
  // For now the BEST way is to use the sample frequency for replay that is
  // exactly the SAME as the Original Freq. used when sampling this block !
  // i.e. NO downsampling is handled YET ... use TAPER when you need it ! ;-)

  sb_pulse=Samples(Get2(&data[0]));
  if (!sb_pulse) sb_pulse=1;       // In case sample frequency > 44100
  pause_ms=Get2(&data[2]);            // (Should work for frequencies upto 48000)
  lastbyte=(int) data[4];
  datalen=Get3(&data[5]);
  if (info!=1)
  {
    if (draw) printf("    Direct Recording      Length:%6d  Original Freq.: %5d Hz\n",
                     datalen, (int) (0.5+(3500000.0/ (double) Get2(&data[0]))));
    if (info!=2)
    {
      data=&data[8];
      datapos=0;
      // Replay Direct Recording block ... 
      while (datalen)
      {
        if (datalen!=1) bitcount=8;
        else bitcount=lastbyte;
        databyte=data[datapos];
        while (bitcount)
        {
          if (databyte&0x80) amp=HIAMP;
          else amp=LOAMP;
          PlayWave(sb_pulse);
          databyte<<=1;
          bitcount--;
        }
        datalen--;
        datapos++;
      }
      ToggleAmp();   // Changed on 26-01-2005
      if (pause_ms) PauseWave(pause_ms);
    }
  }
  else
  {
    sprintf(tstr,"Block %03d (%05X):  15 - Direct Recording\n",curr+1,block[curr]+10); writeout(tstr);
    sprintf(tstr,"                Length:%6d bytes\n",datalen); writeout(tstr);
    sprintf(tstr,"    Original Frequency: %5d T-States/Sample (%5d Hz)\n",
    Get2(data),(int) (0.5+(3500000.0/ (double) Get2(data)))); writeout(tstr);
    sprintf(tstr,"        Last byte used: %5d samples\n",lastbyte); writeout(tstr);
    sprintf(tstr,"     Pause after block: %5d milliseconds\n\n",pause_ms); line++; writeout(tstr);
  }
}

void Analyse_ID16 (void)  // C64 ROM Type Data Block
{
  data+=4;
  sb_pilot=Get2(&data[0]);
  pilot=Get2(&data[2]);
  sb_sync1=Get2(&data[4]);
  sb_sync2=Get2(&data[6]);
  sb_bit0_f=Get2(&data[8]);
  sb_bit0_s=Get2(&data[10]);
  sb_bit1_f=Get2(&data[12]);
  sb_bit1_s=Get2(&data[14]);
  xortype=(int)(data[16]);
  sb_finishbyte_f=Get2(&data[17]);
  sb_finishbyte_s=Get2(&data[19]);
  sb_finishdata_f=Get2(&data[21]);
  sb_finishdata_s=Get2(&data[23]);
  sb_trailing=Get2(&data[25]);
  trailing=Get2(&data[27]);
  lastbyte=(int)(data[29]);
  endian=data[30];
  pause_ms=Get2(&data[31]);
  datalen=Get3(&data[33]);
  data+=36;
  IdentifyC64ROM(datalen, data, 1);
  if (info==1)
  {
    sprintf(pstr,"Block %03d (%05X):  16 - C64 ROM Type Data - %s\n",curr+1,block[curr]+10,tstr); writeout(pstr);
    sprintf(tstr,"                Length: %5d bytes\n",datalen); writeout(tstr);
    sprintf(tstr,"                  Flag: %5d ($%02X)\n",data[0],data[0]); writeout(tstr);
    if (pilot)
      { sprintf(tstr,"           Pilot pulse: %5d T-States, length: %5d pulses\n",sb_pilot,pilot); writeout(tstr); }
    else
      { sprintf(tstr,"           Pilot pulse:  None\n"); writeout(tstr); }
    sprintf(tstr,"           Sync pulses: %5d & %5d T-States\n",sb_sync1,sb_sync2); writeout(tstr);
    sprintf(tstr,"          Bit-0 pulses: %5d & %5d T-States\n",sb_bit0_f,sb_bit0_s); writeout(tstr);
    sprintf(tstr,"          Bit-1 pulses: %5d & %5d T-States\n",sb_bit1_f,sb_bit1_s); writeout(tstr);
    sprintf(tstr,"        Last byte used: %5d bits\n",lastbyte); writeout(tstr);
    if (xortype != 0xFF)
      { sprintf(tstr,"         Byte XOR Type: %d XOR all bits\n",xortype); writeout(tstr); }
    else
      { sprintf(tstr,"         Byte XOR Type:  None\n"); writeout(tstr); }
    sprintf(tstr,"    Finish Byte pulses: %5d & %5d T-States\n",sb_finishbyte_f,sb_finishbyte_s); writeout(tstr);
    sprintf(tstr,"    Finish Data pulses: %5d & %5d T-States\n",sb_finishdata_f,sb_finishdata_s); writeout(tstr);
    if (trailing)
      { sprintf(tstr,"   Trailing Tone pulse: %5d T-States, length: %5d pulses\n",sb_trailing,trailing); writeout(tstr); }
    else
      { sprintf(tstr,"   Trailing Tone pulse:  None\n"); writeout(tstr); }
    if (endian)
      strcpy(pstr, "MSb");
    else
      strcpy(pstr, "LSb");
    sprintf(tstr,"             Endianess:   %s\n",pstr); writeout(tstr);
    sprintf(tstr,"     Pause after block: %5d milliseconds\n\n",pause_ms); line++; writeout(tstr);
    sprintf(tstr,"     First: %02X , Last: %02X, Len: %d\n\n",data[0], data[datalen-1], datalen); line++; writeout(tstr);
  }
}

void Analyse_ID17 (void)  // C64 Turbo Tape Data Block
{
  data+=4;
  sb_bit0=Get2(&data[0]);
  sb_bit1=Get2(&data[2]);
  add_bit=data[4];
  num_lead_in=Get2(&data[5]);
  lead_in_byte=data[7];
  lastbyte=(int) data[8];
  endian=data[9];
  trailing=Get2(&data[10]);
  sb_trailing=data[12];
  pause_ms=Get2(&data[13]);
  datalen=Get3(&data[15]);
  data+=18;
  IdentifyC64Turbo(datalen, data, 1);
  if (info==1)
  {
    sprintf(pstr,"Block %03d (%05X):  17 - C64 Turbo Tape Type Data - %s\n",curr+1,block[curr]+10,tstr); writeout(pstr);
    sprintf(tstr,"                Length: %5d bytes\n",datalen); writeout(tstr);
    sprintf(tstr,"                  Flag: %5d ($%02X)\n",data[0],data[0]); writeout(tstr);
    if (num_lead_in)
      { sprintf(tstr,"         Lead In Bytes: %5d, Value: %3d ($%02X)\n",num_lead_in,lead_in_byte,lead_in_byte); writeout(tstr); }
    else
      { sprintf(tstr,"         Lead In Bytes:  None\n"); writeout(tstr); }
    sprintf(tstr,"           Bit-0 pulse: %5d T-States\n",sb_bit0); writeout(tstr);
    sprintf(tstr,"           Bit-1 pulse: %5d T-States\n",sb_bit1); writeout(tstr);
    if (add_bit&3)
    {
      if (add_bit&4)
        strcpy(pstr, "After");
      else
        strcpy(pstr, "Before");
      sprintf(tstr,"       Additional Bits: %5d %s Byte, Value %1d\n",add_bit&3, pstr, (add_bit>>3)&1); writeout(tstr);
	}
    else
      { sprintf(tstr,"       Additional Bits:  None\n"); writeout(tstr); }

    sprintf(tstr,"        Last byte used: %5d bits\n",lastbyte); writeout(tstr);
    if (endian)
      strcpy(pstr, "MSb");
    else
      strcpy(pstr, "LSb");
    sprintf(tstr,"             Endianess:   %s\n",pstr); writeout(tstr);
    if (trailing)
      { sprintf(tstr,"        Trailing Bytes: %5d, Value: %3d ($%02X)\n",trailing,sb_trailing,sb_trailing); writeout(tstr); }
    else
      { sprintf(tstr,"        Trailing Bytes:  None\n"); writeout(tstr); }
    sprintf(tstr,"     Pause after block: %5d milliseconds\n\n",pause_ms); line++; writeout(tstr);
  }
}

void Analyse_ID20 (void)  // Pause or Stop the Tape command
{
  pause_ms=Get2(&data[0]);
  amp=LOAMP;
  if (pause_ms)
  {
    if (info!=1)
    {
      if (draw) printf("    Pause                 Length: %2.3fs\n",((float) pause_ms)/1000.0);
      if (info!=2)
      {
        PauseWave(pause_ms);
        amp=LOAMP;
      }
    }
    else
    {
       sprintf(tstr,"Block %03d (%05X):  20 - Pause (Silence)\n",curr+1,block[curr]+10);
       writeout(tstr);
       sprintf(tstr,"              Duration: %5d milliseconds\n\n",pause_ms);
       line++;
       writeout(tstr);
    }
  }
  else
  {
    if (info!=1)
    {
      if (draw) printf("    Stop the tape command!\n");
      if (info!=2)
      {
        PauseWave(5000); // 5 seconds of pause in "Stop Tape" wave output
        amp=LOAMP;
      }
    }
    else
    {
      sprintf(tstr,"Block %03d (%05X):  20 - Stop the Tape Command\n\n",curr+1,block[curr]+10);
      line++;
      writeout(tstr);
    }
  }
}

void Analyse_ID21 (void) // Group Start
{
  CopyString(pstr,&data[1],data[0]);
  if (info!=1)
  {
    if (draw) printf("    Group: %s\n",pstr);
  }
  else
  {
    sprintf(tstr,"Block %03d (%05X):  21 - Group: %s\n\n",curr+1,block[curr]+10, pstr);
    line++;
    writeout(tstr);
  }
  if (!expand) draw=0;
}

void Analyse_ID22 (void)  // Group End
{
  if (info!=1)
  {
    if (draw) printf("    Group End\n");
  }
  else
  {
    sprintf(tstr,"Block %03d (%05X):  22 - Group End\n\n",curr+1,block[curr]+10);
    line++;
    writeout(tstr);
  }
  draw=1;
}

void Analyse_ID23 (void)  // Jump To Relative
{
  jump = (signed short)(data[0]+data[1]*256);
  if (info!=1)
  {
    if (draw) printf("    Jump Relative: %d (To Block %d)\n",jump,curr+jump+1);
    if (!info)
    {
      curr+=jump;
      curr--;
    }
  }
  else
  {
    sprintf(tstr,"Block %03d (%05X):  23 - Jump Relative: %d (To Block %d)\n\n",curr+1,block[curr]+10, jump, curr+jump+1);
    line++;
    writeout(tstr);
  }
}

void Analyse_ID24 (void)  // Loop Start
{
  loop_start=curr;
  loop_count=Get2(&data[0]);
  if (info!=1)
  {
    if (draw) printf("    Loop Start, Counter: %d\n",loop_count);
  }
  else
  {
    sprintf(tstr,"Block %03d (%05X):  24 - Loop Start, Counter: %d\n\n",curr+1,block[curr]+10, loop_count-1);
    line++;
    writeout(tstr);
  }
}

void Analyse_ID25 (void)  // Loop End
{
  if (info!=1)
  {
    if (info!=2)
    {
      loop_count--;
      if (loop_count>0)
      {
        if (draw) printf("    Loop End, Still To Go %d Time(s)!\n",loop_count);
        curr=loop_start;
      }
      else
      {
        if (draw) printf("    Loop End, Finished\n");
      }
    }
    else
    {
      if (draw) printf("    Loop End\n");
    }
  }
  else
  {
    sprintf(tstr,"Block %03d (%05X):  25 - Loop End\n\n",curr+1,block[curr]+10);
    line++;
    writeout(tstr);
  }
}

void Analyse_ID26 (void)  // Call Sequence
{
  call_pos=curr;
  call_num=Get2(&data[0]);
  call_cur=0;
  if (info==1)
  {
    sprintf(tstr,"Block %03d (%05X):  26 - Call Sequence, Number of Calls : %d\n\n",curr+1,block[curr]+10,call_num);
    line++;
    writeout(tstr);
  }
  else
  {
    if (info==2)
    {
      if (draw) printf("    Call Sequence, Number of Calls : %d\n",call_num);
    }
    else
    {
      jump = (signed short)(data[2]+data[3]*256);
      if (draw) printf("    Call Sequence, Number of Calls : %d, First: %d (To Block %d)\n",call_num,jump,curr+jump+1);
      curr+=jump;
      curr--;
    }
  }
}

void Analyse_ID27 (void)  // Return from Sequence
{
  call_cur++;
  if (info==1)
  {
    sprintf(tstr,"Block %03d (%05X):  27 - Return from Call\n\n",curr+1,block[curr]+10);
    line++;
    writeout(tstr);
  }
  else
  {
    if (info==2)
    {
      if (draw) printf("    Return from Call\n");
    }
    else
    {
      if (call_cur==call_num)
      {
        if (draw) printf("    Return from Call, Last Call Finished\n");
        curr=call_pos;
      }
      else
      {
        curr = call_pos;
        data = &mem[block[curr]+1];
        jump = (signed short)(data[call_cur*2+2]+data[call_cur*2+3]*256);
        if (draw) printf("    Return from Call, Calls Left: %d, Next: %d (To Block %d)\n",
                         call_num-call_cur, jump, curr+jump+1);
        curr+=jump;
        curr--;
      }
    }
  }
}

void Analyse_ID28 (void)  // Select Block
{
  num_sel=data[2];
  if (info==2)
  {
    if (draw)
    {
      sprintf(tstr,"    Select block");
      MakeFixedString(tstr, 69);
      strcpy(tstr+52," (-v for more)");
      printf("%s\n",tstr);
    }
  }
  else
  {
    if (info==1)
    {
      sprintf(tstr,"Block %03d (%05X):  28 - Select Block\n",curr+1,block[curr]+10);
      writeout(tstr);
      data+=3;
      for (n=0; n<num_sel; n++)
      {
        jump = (signed short)(data[0]+data[1]*256);
        CopyString(spdstr,&data[3],data[2]);
        sprintf(tstr,"%5d - Jump: %03d (To Block %04d) : %s\n",n+1,jump,curr+jump+1,spdstr);
        writeout(tstr);
        data+=3+data[2];
      }
      sprintf(tstr,"\n");
      writeout(tstr);
    }
    else
    {
      printf("    Select :\n");
      data+=3;
      for (n=0; n<num_sel; n++)
      {
        jump = (signed short)(data[0]+data[1]*256);
        jumparray[n]=jump;
        CopyString(spdstr,&data[3],data[2]);
        printf("%5d : %s\n",n+1,spdstr);
        data+=3+data[2];
      }
      printf(">> Press the number!\n");
      PauseWave(5000);   // Why?!?!?!?!
      amp=LOAMP;
      k=getchar();
      if (k==27) Error("ESCAPE key pressed!");
      k-=48;
      if (k<1 || k>num_sel) printf("Illegal Selection... Continuing...\n");
      else
      {
        curr+=jumparray[k-1];
        curr--;
      }
    }
  }
}

void Analyse_ID2A (void)  // Stop the tape if in 48k mode
{
  if (info==1)
  {
    sprintf(tstr,"Block %03d (%05X):  2A - Stop the tape if in 48k mode\n\n",curr+1,block[curr]+10);
    line++;
    writeout(tstr);
    return;
  }
  if (info==2)
  {
    if (draw) printf("    Stop the tape if in 48k mode!\n");
    return;
  }
  if (mode128)
  {
    if (draw) printf("    Stop the tape only in 48k mode!\n");
  }
  else
  {
    if (draw) printf("    Stop the tape in 48k mode!\n");
    PauseWave(5000);
    amp=LOAMP;
  }
}

void Analyse_ID30 (void)  // Description
{
  CopyString(pstr,&data[1],data[0]);
  if (info!=1)
  {
    if (draw) printf("    Description: %s\n",pstr);
  }
  else
  {
    sprintf(tstr,"Block %03d (%05X):  30 - Description: %s\n\n",curr+1,block[curr]+10, pstr);
    line++;
    writeout(tstr);
  }
}

void Analyse_ID31 (void)  // Message
{
  CopyString(pstr,&data[2],data[1]);
  if (info!=1)
  {
    // Pause in Message block is ignored ...
    if (draw) printf("    Message: %s\n",pstr);
  }
  else
  {
    line+=MultiLine(pstr,34,spdstr);
    sprintf(tstr,"Block %03d (%05X):  31 - Message: %s\n",curr+1,block[curr]+10, spdstr);
    writeout(tstr);
    sprintf(tstr,"               Duration: %d seconds\n\n",data[0]);
    line++;
    writeout(tstr);
  }
}

void Analyse_ID32 (void)  // Archive Info
{
  if (info!=1)
  {
    if (draw)
    {
      if (data[3]==0)
      {
        CopyString(spdstr,&data[5],data[4]);
        sprintf(tstr,"    Title: %s",spdstr);
        MakeFixedString(tstr, 69);
        strcpy(tstr+52," (-v for more)");
        printf("%s\n",tstr);
      }
      else
      {
        sprintf(tstr,"    Archive Info");
        MakeFixedString(tstr, 69);
        strcpy(tstr+52," (-v for more)");
        printf("%s\n",tstr);
      }
    }
  }
  else
  {
    num=data[2];
    data+=3;
    sprintf(tstr,"Block %03d (%05X):  32 - Archive Info:\n",curr+1,block[curr]+10);
    writeout(tstr);
    while(num)
    {
      switch (data[0])
      {
        case 0:  sprintf(pstr,"         Title:"); break;
        case 1:  sprintf(pstr,"     Publisher:"); break;
        case 2:  sprintf(pstr,"     Author(s):"); break;
        case 3:  sprintf(pstr,"  Release Date:"); break;
        case 4:  sprintf(pstr,"      Language:"); break;
        case 5:  sprintf(pstr,"     Game Type:"); break;
        case 6:  sprintf(pstr,"         Price:"); break;
        case 7:  sprintf(pstr,"        Loader:"); break;
        case 8:  sprintf(pstr,"        Origin:"); break;
        default: sprintf(pstr,"      Comments:"); break;
      }
      CopyString(spdstr,&data[2],data[1]);
      line+=MultiLine(spdstr,16,tstr);
      sprintf(spdstr,"%s %s\n",pstr,tstr);
      writeout(spdstr);
      data+=data[1]+2;
      num--;
    }
    sprintf(tstr,"\n");
    writeout(tstr);
  }
}

void Analyse_ID33 (void)  // Hardware Info
{
  if (data[1]==0 && data[2]>0x14 && data[2]<0x1a && data[3]==1) cpc=1;
  if (data[1]==0 && data[2]==0x09 && data[3]==1) sam=1;
  if (info!=1)
  {
    if (draw)
    {
      if (data[1]!=0 || data[3]!=1)
      {
        sprintf(tstr, "    Hardware Type");
        MakeFixedString(tstr, 69);
        strcpy(tstr+52," (-v for more)");
        printf("%s\n",tstr);
      }
      else
      {
        printf("    This tape is made for %s !\n",hwids[0][data[2]]);
      }
    }
  }
  else
  {
    num=data[0];
    data+=1;
    sprintf(tstr,"Block %03d (%05X):  33 - Hardware Info:\n",curr+1,block[curr]+10);
    writeout(tstr);
    for (n=0; n<4; n++)
    {
      prvi=1;
      d=data;
      for (m=0; m<num; m++)
      {
        if (d[2]==n)
        {
          if (prvi)
          {
            prvi=0;
            switch (n)
            {
              case 0: sprintf(pstr,"  Runs on the following hardware:\n"); writeout(pstr); break;
              case 1: sprintf(pstr,"  Uses the following hardware:\n"); writeout(pstr); break;
              case 2: sprintf(pstr,"  Runs on but doesn't use the following hardware:\n"); writeout(pstr); break;
              case 3: sprintf(pstr,"  Doesn't run on the following hardware:\n"); writeout(pstr); break;
            }
          }
          if (!prvi && last==d[0])
          {
            for (x=0; x<lastlen; x++) spdstr[x]=' ';
            spdstr[x]=0;
            sprintf(pstr,"      %s  %s\n",spdstr,hwids[d[0]][d[1]]);
            writeout(pstr);
          }
          else
          {
            sprintf(pstr,"      %s: %s\n",hwtypes[d[0]],hwids[d[0]][d[1]]);
            writeout(pstr);
          }
          lastlen=strlen(hwtypes[d[0]]);
          last=d[0];
        }
        d+=3;
      }
    }
    sprintf(tstr,"\n");
    writeout(tstr);
  }
}

void Analyse_ID34 (void)  // Emulation info
{
  if (info!=1)
  {
    if (draw) printf("    Information for emulators.\n");
  }
  else
  {
    sprintf(tstr,"Block %03d (%05X):  34 - Emulation Info\n\n",curr+1,block[curr]+10);
    line++;
    writeout(tstr);
  }
}

void Analyse_ID35 (void)  // Custom Info
{
  CopyString(pstr,data,16);
  if (info!=1)
  {
    if (draw)
    {
      if (strcmp(pstr,"POKEs           "))
        printf("    Custom Info: %s\n",pstr);
        // Only Name of Custom info except POKEs is used ...
      else
      {
        sprintf(tstr,"    Custom Info: %s",pstr); 
        MakeFixedString(tstr, 69);
        strcpy(tstr+52," (-v for more)");
        printf("%s\n",tstr);
      }
    }
  }
  else
  {
    sprintf(tstr,"Block %03d (%05X):  35 - Custom Info: %s\n",curr+1,block[curr]+10,pstr);
    writeout(tstr);
    if (!strcmp(pstr,"POKEs           "))
    {
      data+=20;
      if (data[0])
      {
        sprintf(pstr,"  Description:");
        CopyString(spdstr,&data[1],data[0]);
        line+=MultiLine(spdstr,15,tstr)+1;
        sprintf(spdstr,"%s %s\n\n",pstr,tstr);
        writeout(spdstr);
      }
      data+=data[0]+1;
      numt=data[0];
      data++;
      sprintf(pstr,"          Trainer Description                       Poke Val Org Page\n");
      writeout(pstr);
      sprintf(pstr,"         -------------------------------------------------------------\n");
      writeout(pstr);
      while (numt)
      {
        CopyString(pstr,&data[1],data[0]);
        data+=data[0]+1;
        nump=data[0];
        data++;
        for (n=0; n<nump; n++)
        {
          sprintf(spdstr,"          %s",pstr);
          MakeFixedString(spdstr,48);
          if (data[0]&8) strcpy(tstr2,"   -");
            else sprintf(tstr2,"%4d",data[0]&7);
          if (data[0]&32) strcpy(tstr,"  -");
            else sprintf(tstr,"%3d",data[4]);
          if (data[0]&16) strcpy(tstr3,"  -");
            else sprintf(tstr3,"%3d",data[3]);
          if (n>0) strcpy(tstr4,"+");
            else strcpy(tstr4," ");
          sprintf(pstr,"%s %s %5d %s %s %s\n",spdstr, tstr4, Get2(&data[1]), tstr3, tstr, tstr2);
          writeout(pstr);
          data+=5;
          pstr[0]=0;
        }
        numt--;
      }
    }
    sprintf(tstr,"\n");
    writeout(tstr);
  }
}

void Analyse_ID40 (void)  // Snapshot
{
  if (info!=1)
  {
    if (draw) printf("    Snapshot               (Not Supported yet)\n");
  }
  else
  {
    sprintf(tstr,"Block %03d (%05X):  40 - Snapshot\n\n",curr+1,block[curr]+10);
    line++;
    writeout(tstr);
    switch (data[0])
    {
      case 0  : sprintf(pstr,"Type: Z80"); break;
      case 1  : sprintf(pstr,"Type: SNA"); break;
      default : sprintf(pstr,"Unknown Type"); break;
    }
    sprintf(tstr,"                      %s\n\n",pstr);
    line++;
    writeout(tstr);
  }
}

void Analyse_ID5A (void)  // ZXTape!
{
  if (info!=1)
  {
    if (draw) printf("    Start of the new tape  (Merged Tapes)\n");
  }
  else
  {
    sprintf(tstr,"Block %03d (%05X):  5A - Merget Tapes\n\n",curr+1,block[curr]+10);
    line++;
    writeout(tstr);
  }
}

void Analyse_Unknown (void)  // Unknown blocks
{
  if (info!=1)
  {
    if (draw) printf("    Unknown block %02X !\n", id);
  }
  else
  {
    sprintf(tstr,"Block %03d (%05X):  %02X Unknown Block \n\n",curr+1,block[curr]+10,id);
    line++;
    writeout(tstr);
  }
}

////////////////////////
// Main TZX2WAV program
////////////////////////

int main(int argc, char *argv[])
{
  printf("\n=================================================\r\n");
  printf(" TZX to VAV Converter v0.2 Beta (Build %s)\r\n",build);
  printf("=================================================\r\n");
  if (argc<2)
  {
    printf("\nUsage: TZX2WAV [switches] FILE.TZX [FILE.WAV|CSW]\n\n");
    printf("Switches: -f n   Set sampling frequency to n Hz (default 44100)\n");
    printf("          -s     Generate a 16 bits stereo WAV file\n");
    printf("          -r     Reverse the sign of output wave data\n");
    printf("          -c1    Create a CSW v1.01 file instead of a WAV file\n");
    printf("          -c2    Create a CSW v2.00 file instead of a WAV file\n");
    printf("          -i     Show information on TZX file structure\n");
    printf("          -v     Display a verbose report of TZX file structure\n");
    printf("          -x     Expand TZX groups in information output\n"); 
    printf("          -b n   Start conversion at block n\n");
    printf("          -e n   End conversion after block n\n");
    printf("          -p     Override pause settings in the last block\n");
    printf("          -128   Work in 128K mode\n");
    exit(-1);
  }

  // Check for command line options

  for (n=1; n<argc; n++)
  {
    if (argv[n][0]=='-')
    {
      switch (argv[n][1])
      {
        case 'v': info = 1; break;
        case 'i': info = 2; break;
        case 'b': starting = getnumber(argv[n+1]); n++; break;
        case 'e': ending = getnumber(argv[n+1]); n++; break;
        case 'f': nfreq = getnumber(argv[n+1]); n++; break;
        case 'x': expand = 1; break;
        case '1': mode128 = 1; break;
        case 'p': skippause = 1; break;
        case 'r': inv = 1; break;
        case 'c': switch (argv[n][2])
                  {
                    case '1': csw = 1; break;
                    case '2': csw = 2; break;
                    default : invalidoption(argv[n]);
                  }
        case 's': stereo = 1; break;
        default : invalidoption(argv[n]);
      }
    }
    else
    {
      files++;
      switch (files)
      {
        case 1  : strcpy(finp,argv[n]); break;
        case 2  : strcpy(fout,argv[n]); break;
        default : Error("Too Many files on command line!");
      }
    }
  }

  if (files==0)
    Error("No Files specified !");

  if (files==1)
  {
    strcpy(fout,finp);
    ChangeFileExtension(fout,csw?"CSW":"WAV");
  }

  if (nfreq)
    freq = nfreq;

  if ((ifh = open(finp, O_RDONLY | O_BINARY)) == -1)
    Error("Input file not found");

  flen = lseek(ifh, 0, SEEK_END);
  lseek(ifh, 0, SEEK_SET);

  mem = (unsigned char *) malloc(flen);
  if (mem == NULL)
    Error("Not enough memory to load the file!");

  // Start reading file...

  read(ifh,mem,10);
  mem[7]=0;

  if (strcmp((const char*)mem,"ZXTape!"))
    Error("File is not in ZXTape format!");

  printf("\nZXTape file revision %d.%02d\n",mem[8],mem[9]);
  if (!mem[8]) Error("Development versions of ZXTape format are not supported!");
  if (mem[8]>MAJREV) { printf("\n-- Warning: Some blocks may not be recognised and used!\n"); line+=2; }
  if (mem[8]==MAJREV && mem[9]>MINREV) { printf("\n-- Warning: Some of the data might not be properly recognised!\n"); line+=2; }
  read(ifh,mem,flen-10);
  numblocks=0; pos=0;
  not_rec=0;

  // Go through the file and record block starts ...
  // (not necessary, could just go right through it)

  while(pos < flen-10)
  {
    block[numblocks]=pos;
    pos++;
    switch(mem[pos-1])
    {
      case 0x10: pos+=Get2(&mem[pos+0x02])+0x04; break;
      case 0x11: pos+=Get3(&mem[pos+0x0F])+0x12; break;
      case 0x12: pos+=0x04; break;
      case 0x13: pos+=(mem[pos+0x00]*0x02)+0x01; break;
      case 0x14: pos+=Get3(&mem[pos+0x07])+0x0A; break;
      case 0x15: pos+=Get3(&mem[pos+0x05])+0x08; break;
      case 0x16: pos+=Get4(&mem[pos+0x00])+0x04; break;
      case 0x17: pos+=Get4(&mem[pos+0x00])+0x04; break;

      case 0x20: pos+=0x02; break;
      case 0x21: pos+=mem[pos+0x00]+0x01; break;
      case 0x22: break;
      case 0x23: pos+=0x02; break;
      case 0x24: pos+=0x02; break;
      case 0x25: break;
      case 0x26: pos+=Get2(&mem[pos+0x00])*0x02+0x02; break;
      case 0x27: break;
      case 0x28: pos+=Get2(&mem[pos+0x00])+0x02; break;

      case 0x2A: pos+=0x04; break;

      case 0x30: pos+=mem[pos+0x00]+0x01; break;
      case 0x31: pos+=mem[pos+0x01]+0x02; break;
      case 0x32: pos+=Get2(&mem[pos+0x00])+0x02; break;
      case 0x33: pos+=(mem[pos+0x00]*0x03)+0x01; break;
      case 0x34: pos+=0x08; break;
      case 0x35: pos+=Get4(&mem[pos+0x10])+0x14; break;

      case 0x40: pos+=Get3(&mem[pos+0x01])+0x04; break;

      case 0x5A: pos+=0x09; break;

      default :  pos+=Get4(&mem[pos+0x00])+0x04;
                 not_rec=1;
    }
    numblocks++;
  }

  printf("Number of Blocks: %d\n",numblocks);

  if (not_rec)
  {
   printf("\n-- Warning: Some blocks were *NOT* recognised!\n");
   line+=2;
  }

  curr=0;

  if (starting>1)
  {
    if (starting>numblocks)
    {
      Error("Invalid Starting Block");
    }
    curr=starting-1;
  }

  if (ending>0)
  {
    if (ending>numblocks || ending<starting)
    {
      Error("Invalid Ending Block");
    }
    numblocks=ending;
  }

  if (!info)
  {
    printf("\nCreating ");
    if (csw) printf("CSW v%d",csw);
    else printf("WAV %s",stereo ? "stereo":"mono");
    printf(" file using %d Hz frequency ...\n\n",freq);
  }
  else printf("\n");

  if (!info)
  {
    switch (csw)
    {
      case 1  : CSW1_Init(); break;
      case 2  : CSW2_Init(); break;
      default : WAV_Init();
    }
  }

  amp=LOAMP;
  singlepulse=0;
  manchester=0;
  cycle=(double) freq/3500000.0;   // This is for the conversion later ...
  if (info==2) line++;

  ///////////////////////////////////////////////////// 
  // Start replay of blocks (Main loop of the program)
  /////////////////////////////////////////////////////
  
  while (curr<numblocks)
  {
    if (!info)
    {
      if (draw) printf("Block %03d:",curr+1);
    }
    else
    {
      if (info==2 && draw)
      {
        // PAGES SUPPORT AND ROUTINE TO BE DEPRECATED
        if (pages)
        {
          line++;
          if (line>22)
          {
            printf("scroll?\n");
            k=getchar();
            if (k==27) Error("ESCAPE key pressed!");
            if (!k) getchar();
            line=0;
          }
        }
        printf("%03d-%05X:",curr+1,block[curr]+10);
      }
    }
    id=mem[block[curr]];
    data=&mem[block[curr]+1];
    switch (id)
    {
      case 0x10: Analyse_ID10();  // Standard Loading Data block
                 break;
      case 0x11: Analyse_ID11();  // Custom Loading Data block
                 break;
      case 0x12: Analyse_ID12();  // Pure Tone
                 break;
      case 0x13: Analyse_ID13();  // Sequence of Pulses
                 break;
      case 0x14: Analyse_ID14();  // Pure Data
                 break;
      case 0x15: Analyse_ID15();  // Direct Recording
                 break;
      case 0x16: Analyse_ID16();  // C64 ROM Type Data Block
                 break;
      case 0x17: Analyse_ID17();  // C64 Turbo Tape Data Block
                 break;
      case 0x20: Analyse_ID20();  // Pause or Stop the Tape command
                 break;
      case 0x21: Analyse_ID21();  // Group Start
                 break;
      case 0x22: Analyse_ID22();  // Group End
                 break;
      case 0x23: Analyse_ID23();  // Jump To Relative
                 break;
      case 0x24: Analyse_ID24();  // Loop Start
                 break;
      case 0x25: Analyse_ID25();  // Loop End
                 break;
      case 0x26: Analyse_ID26();  // Call Sequence
                 break;
      case 0x27: Analyse_ID27();  // Return from Sequence
                 break;
      case 0x28: Analyse_ID28();  // Select Block
                 break;
      case 0x2A: Analyse_ID2A();  // Stop the tape if in 48k mode
                 break;
      case 0x30: Analyse_ID30();  // Description
                 break;
      case 0x31: Analyse_ID31();  // Message
                 break;
      case 0x32: Analyse_ID32();  // Archive Info
                 break;
      case 0x33: Analyse_ID33();  // Hardware Info
                 break;
      case 0x34: Analyse_ID34();  // Emulation info
                 break;
      case 0x35: Analyse_ID35();  // Custom Info
                 break;
      case 0x40: Analyse_ID40();  // Snapshot
                 break;
      case 0x5A: Analyse_ID5A();  // ZXTape!
                 break;
      default :  Analyse_Unknown(); // Unknown blocks
    }

    // TZX file blocks analysis finished
    // Now we start generating the sound waves
        
    if (info!=1 && (id==0x10 || id==0x11 || id==0x14)) // One of the data blocks ...
    {
      if (id!=0x14)   Identify(datalen,data,0);
      else            strcpy(tstr,"    Pure Data           ");
      if (id==0x10)   sprintf(spdstr,"Normal Speed");
      else            sprintf(spdstr," Speed: %3d%%", speed);
      sprintf(pstr,"Pause: %5d ms",pause_ms);
      if (draw) printf("%s  Length:%6d %s %s\n",tstr,datalen,spdstr,pstr);
      if (info!=2)
      {
        while (pilot)  // Play PILOT TONE
        {
          PlayWave(sb_pilot);
          ToggleAmp();
          pilot--;
        }
        if (sb_sync1)  // Play first SYNC pulse
        {
          PlayWave(sb_sync1);
          ToggleAmp();
        }
        if (sb_sync2)  // Play second SYNC pulse
        {
          PlayWave(sb_sync2);
          ToggleAmp();
        }
        datapos=0;
        while (datalen)  // Play actual DATA
        {
          if (datalen!=1) bitcount=8;
          else bitcount=lastbyte;
          databyte=data[datapos];
          while (bitcount)
          {
            if (databyte&0x80) sb_bit=sb_bit1;
            else sb_bit=sb_bit0;
            PlayWave(sb_bit);   // Play first pulse of the bit
            ToggleAmp();
            if (!singlepulse)
            {
              PlayWave(sb_bit); // Play second pulse of the bit
              ToggleAmp();
            }
            databyte<<=1;
            bitcount--;
          }
          datalen--; datapos++;
        }
        singlepulse=0;   // Reset flag for next TZX blocks

        // If there is pause after block present then make first millisecond the oposite
        // pulse of last pulse played and the rest in LOAMP ... otherwise don't do ANY pause
        if (pause_ms)
        {
          PauseWave(1);
          amp=LOAMP;
          if (pause_ms>1) PauseWave(pause_ms-1);
        }
      }
    }
    
    if (info!=1 && id==0x16)  // C64 ROM data block ...
    {
      IdentifyC64ROM(datalen, data, 0);
      sprintf(pstr,"Pause: %5d ms",pause_ms);
      if (draw) printf(" %s Length:%6d %s %s\n",tstr,datalen,spdstr,pstr);
      if (info!=2)
      {
        sb_pilot=Samples(sb_pilot);
        sb_sync1=Samples(sb_sync1); sb_sync2=Samples(sb_sync2);
        sb_bit1_f=Samples(sb_bit1_f); sb_bit1_s=Samples(sb_bit1_s);
        sb_bit0_f=Samples(sb_bit0_f); sb_bit0_s=Samples(sb_bit0_s);
        sb_finishbyte_f=Samples(sb_finishbyte_f);
        sb_finishbyte_s=Samples(sb_finishbyte_s);
        sb_finishdata_f=Samples(sb_finishdata_f);
        sb_finishdata_s=Samples(sb_finishdata_s);
        sb_trailing=Samples(sb_trailing);
        num_lead_in=0;
        amp=LOAMP;        // This might be just opposite !!!!
        while (pilot)     // Play PILOT TONE
        {
          PlayC64(sb_pilot);
          pilot--;
        }
        if (sb_sync1) PlayC64(sb_sync1);  // Play SYNC PULSES
        if (sb_sync2) PlayC64(sb_sync2);
        datapos=0;
        while (datalen)   // Play actual DATA
        {
          if (datalen!=1)
          {
            bitcount=8;
            PlayC64ROMByte(data[datapos],0);
          }
          else
          {
            bitcount=lastbyte;
            PlayC64ROMByte(data[datapos],1);
          }			 
          databyte=data[datapos];
          datalen--; datapos++;
        }
        while (trailing)  // Play TRAILING TONE
        {
          PlayC64(sb_trailing);
          trailing--;
        }

        // If there is pause after block present then make first millisecond the oposite
        // pulse of last pulse played and the rest in LOAMP ... otherwise don't do ANY pause

        if (pause_ms)
		{
          PauseWave(pause_ms/2);
          ToggleAmp();
          PauseWave((pause_ms/2)+(pause_ms%2));
          ToggleAmp();
		}
      }
    }

    if (info!=1 && id==0x17)    // C64 Turbo Tape data block ...
    {
      IdentifyC64Turbo(datalen, data, 0);
      sprintf(pstr,"Pause: %5d ms",pause_ms);
      if (draw) printf(" %s Length:%6d %s %s\n",tstr,datalen,spdstr,pstr);
      if (info!=2)
      {
        sb_bit1=Samples(sb_bit1);
        sb_bit0=Samples(sb_bit0);
        amp=LOAMP;           // This might be just opposite !!!!
        while (num_lead_in)  // Play Lead In bytes
        {
          bitcount=8;
          PlayC64TurboByte(lead_in_byte);
          num_lead_in--;
        }
        datapos=0;
        while (datalen)      // Play actual DATA
        {
          if (datalen!=1) bitcount=8;
          else bitcount=lastbyte;
          PlayC64TurboByte(data[datapos]);
          databyte=data[datapos];
          datalen--; datapos++;
        }
        while (trailing)     // Play Trailing bytes
        {
          bitcount=8;
          PlayC64TurboByte((unsigned char)sb_trailing);
          trailing--;
        }

        // If there is pause after block present then make first millisecond the oposite
        // pulse of last pulse played and the rest in LOAMP ... otherwise don't do ANY pause

        if (pause_ms)
        {
          PauseWave(pause_ms/2);
          ToggleAmp();
          PauseWave((pause_ms/2)+(pause_ms%2));
          ToggleAmp();
        }
      }
    }
    
    curr++; // We continue to replay the next TZX block
  } // This is the main loop end

  if (!info)
  {
    PauseWave(200);  // Finish always with 200 ms of pause after the last block
    switch (csw)
    {
      case 1  : CSW1_Stop(); break;
      case 2  : CSW2_Stop(); break;
      default : WAV_Stop();
    }
    printf("\n%d bytes successfuly written to file.\n",oflen);
  }

  GarbageCollector();
  exit(0);

} // End of TZX2WAV main program
