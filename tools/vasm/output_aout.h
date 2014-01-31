/* output_aout.h header file for a.out objects */
/* (c) in 2008 by Frank Wille */

/* a.out header */
struct aout_hdr {
  unsigned char a_midmag[4];
  unsigned char a_text[4];
  unsigned char a_data[4];
  unsigned char a_bss[4];
  unsigned char a_syms[4];
  unsigned char a_entry[4];
  unsigned char a_trsize[4];
  unsigned char a_drsize[4];
};

/* a_magic */
#define OMAGIC 0407    /* old impure format */
#define NMAGIC 0410    /* read-only text */
#define ZMAGIC 0413    /* demand load format */
#define QMAGIC 0314    /* not supported */

/* a_mid - machine id */
#define MID_SUN010      1       /* sun 68010/68020 binary */
#define MID_SUN020      2       /* sun 68020-only binary */
#define MID_PC386       100     /* 386 PC binary. (so quoth BFD) */
#define MID_HP200       200     /* hp200 (68010) BSD binary */
#define MID_I386        134     /* i386 BSD binary */
#define MID_M68K        135     /* m68k BSD binary with 8K page sizes */
#define MID_M68K4K      136     /* m68k BSD binary with 4K page sizes */
#define MID_NS32532     137     /* ns32532 */
#define MID_SPARC       138     /* sparc */
#define MID_PMAX        139     /* pmax */
#define MID_VAX1K       140     /* vax 1K page size binaries */
#define MID_ALPHA       141     /* Alpha BSD binary */
#define MID_MIPS        142     /* big-endian MIPS */
#define MID_ARM6        143     /* ARM6 */
#define MID_SH3         145     /* SH3 */
#define MID_POWERPC     149     /* big-endian PowerPC */
#define MID_VAX         150     /* vax */
#define MID_SPARC64     151     /* LP64 sparc */
#define MID_HP300       300     /* hp300 (68020+68881) BSD binary */
#define MID_HPUX        0x20C   /* hp200/300 HP-UX binary */
#define MID_HPUX800     0x20B   /* hp800 HP-UX binary */

/* a_flags */
#define EX_DYNAMIC      0x20
#define EX_PIC          0x10
#define EX_DPMASK       0x30

/* a_midmag macros */
#define SETMIDMAG(a,mag,mid,flag) setval(1,(a)->a_midmag,4, \
                  ((flag)&0x3f)<<26|((mid)&0x3ff)<<16|((mag)&0xffff))


/* Relocation info structures */
struct relocation_info {
  unsigned char r_address[4];
  unsigned char r_info[4];
};

#define RELB_symbolnum 0            /* ordinal number of add symbol */
#define RELS_symbolnum 24
#define RELB_reloc     24           /* the whole reloc field */
#define RELS_reloc     8

/* standard relocs: M68k, x86, ... */
#define RSTDB_pcrel     24          /* 1 if value should be pc-relative */
#define RSTDS_pcrel     1
#define RSTDB_length    25          /* log base 2 of value's width */
#define RSTDS_length    2
#define RSTDB_extern    27          /* 1 if need to add symbol to value */
#define RSTDS_extern    1
#define RSTDB_baserel   28          /* linkage table relative */
#define RSTDS_baserel   1
#define RSTDB_jmptable  29          /* relocate to jump table */
#define RSTDS_jmptable  1
#define RSTDB_relative  30          /* load address relative */
#define RSTDS_relative  1
#define RSTDB_copy      31          /* run time copy */
#define RSTDS_copy      1


/* Symbol table entry format */
struct nlist32 {
  unsigned char n_strx[4];  /* string table offset */
  unsigned char n_type;     /* type defines */
  signed char n_other;      /* spare */
  unsigned char n_desc[2];  /* used by stab entries */
  unsigned char n_value[4]; /* address/value of the symbol */
};

#define N_EXT   0x01        /* external (global) bit, OR'ed in */
#define N_TYPE  0x1e        /* mask for all the type bits */
#define N_STAB  0x0e0       /* mask for debugger symbols */

/* symbol types */
#define N_UNDF  0x00        /* undefined */
#define N_ABS   0x02        /* absolute address */
#define N_TEXT  0x04        /* text segment */
#define N_DATA  0x06        /* data segment */
#define N_BSS   0x08        /* bss segment */
#define N_INDR  0x0a        /* alias definition */
#define N_SIZE  0x0c        /* pseudo type, defines a symbol's size */
#define N_WEAKU 0x0d        /* GNU: Weak undefined symbol */
#define N_WEAKA 0x0e        /* GNU: Weak absolute symbol */
#define N_WEAKT 0x0f        /* GNU: Weak text symbol */
#define N_WEAKD 0x10        /* GNU: Weak data symbol */
#define N_WEAKB 0x11        /* GNU: Weak bss symbol */
#define N_COMM  0x12        /* common reference */
#define N_SETA  0x14        /* absolute set element symbol */
#define N_SETT  0x16        /* text set element symbol */
#define N_SETD  0x18        /* data set element symbol */
#define N_SETB  0x1a        /* bss set element symbol */
#define N_SETV  0x1c        /* set vector symbol */
#define N_FN    0x1e        /* file name (N_EXT on) */
#define N_WARN  0x1e        /* warning message (N_EXT off) */

/* debugging symbols */
#define N_GSYM          0x20    /* global symbol */
#define N_FNAME         0x22    /* F77 function name */
#define N_FUN           0x24    /* procedure name */
#define N_STSYM         0x26    /* data segment variable */
#define N_LCSYM         0x28    /* bss segment variable */
#define N_MAIN          0x2a    /* main function name */
#define N_PC            0x30    /* global Pascal symbol */
#define N_RSYM          0x40    /* register variable */
#define N_SLINE         0x44    /* text segment line number */
#define N_DSLINE        0x46    /* data segment line number */
#define N_BSLINE        0x48    /* bss segment line number */
#define N_SSYM          0x60    /* structure/union element */
#define N_SO            0x64    /* main source file name */
#define N_LSYM          0x80    /* stack variable */
#define N_BINCL         0x82    /* include file beginning */
#define N_SOL           0x84    /* included source file name */
#define N_PSYM          0xa0    /* parameter variable */
#define N_EINCL         0xa2    /* include file end */
#define N_ENTRY         0xa4    /* alternate entry point */
#define N_LBRAC         0xc0    /* left bracket */
#define N_EXCL          0xc2    /* deleted include file */
#define N_RBRAC         0xe0    /* right bracket */
#define N_BCOMM         0xe2    /* begin common */
#define N_ECOMM         0xe4    /* end common */
#define N_ECOML         0xe8    /* end common (local name) */
#define N_LENG          0xfe    /* length of preceding entry */

/* n_other & 0x0f */
#define AUX_UNKNOWN     0
#define AUX_OBJECT      1
#define AUX_FUNC        2
#define AUX_LABEL       3
#define AUX_IGNORE   0xff   /* vlink-specific, used to ignore this symbol */
/* n_other & 0xf0 >> 4 */
#define BIND_LOCAL      0   /* not used? */
#define BIND_GLOBAL     1   /* not used? */
#define BIND_WEAK       2


/* vasm specific - used to generate a.out files */

#define STRHTABSIZE 0x10000
#define SYMHTABSIZE 0x10000
#define _TEXT 0
#define _DATA 1
#define _BSS 2

struct StrTabNode {
  struct node n;
  struct StrTabNode *hashchain;
  char *str;
  unsigned long offset;
};

struct StrTabList {
  struct list l;
  struct StrTabNode **hashtab;
  unsigned long nextoffset;
};

struct SymbolNode {
  struct node n;
  struct SymbolNode *hashchain;
  char *name;
  struct nlist32 s;
  unsigned long index;
};

struct SymTabList {
  struct list l;
  struct SymbolNode **hashtab;
  unsigned long nextindex;
};

struct RelocNode {
  struct node n;
  struct relocation_info r;
};


#if defined(VASM_CPU_M68K)
#define MID MID_SUN020
#elif defined(VASM_CPU_PPC)
#define MID MID_POWERPC
#elif defined(VASM_CPU_ARM)
#define MID MID_ARM6
#elif defined(VASM_CPU_X86)
#define MID MID_PC386
#else
#define MID (0)
#endif
