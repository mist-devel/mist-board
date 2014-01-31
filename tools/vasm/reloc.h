/* reloc.h  reloc header file for vasm */
/* (c) in 2002,2005-2008,2010,2011 by Volker Barthelmann and Frank Wille */

#ifndef RELOC_H
#define RELOC_H

/* part of standard relocations */

#ifndef FIRST_STANDARD_RELOC
#define FIRST_STANDARD_RELOC 0
#endif

#define REL_NONE FIRST_STANDARD_RELOC
#define REL_ABS (REL_NONE+1)         /* standard absolute relocation */
#define REL_PC  (REL_ABS+1)          /* PC-relative */
#define REL_GOT (REL_PC+1)           /* symbol's pointer in global off.table */
#define REL_GOTPC (REL_GOT+1)        /* global offset table PC-relative */
#define REL_GOTOFF (REL_GOTPC+1)     /* offset to global offset table */
#define REL_GLOBDAT (REL_GOTOFF+1)   /* global data */
#define REL_PLT (REL_GLOBDAT+1)      /* procedure linkage table */
#define REL_PLTPC (REL_PLT+1)        /* procedure linkage table PC-relative */
#define REL_PLTOFF (REL_PLTPC+1)     /* offset to procedure linkage table */
#define REL_SD (REL_PLTOFF+1)        /* small data base relative */
#define REL_UABS (REL_SD+1)          /* unaligned absolute addr. relocation */
#define REL_LOCALPC (REL_UABS+1)     /* pc-relative to local symbol */
#define REL_LOADREL (REL_LOCALPC+1)  /* relative to load addr., no symbol */
#define REL_COPY (REL_LOADREL+1)     /* copy from shared object */
#define REL_JMPSLOT (REL_COPY+1)     /* procedure linkage table entry */
#define REL_SECOFF (REL_JMPSLOT+1)   /* symbol's offset to start of section */
#define LAST_STANDARD_RELOC REL_SECOFF

/* standard reloc struct */
typedef struct nreloc {
  int offset;     /* offset to beginning of data atom in bits */
  int size;       /* size of relocation in bits */
  taddr mask;     /* mask value */
  taddr addend;   /* addend */
  symbol *sym;
} nreloc;

typedef struct rlist {
  struct rlist *next;
  void *reloc;
  int type;
} rlist;

#define MAKEMASK(x) ((1LL<<(x))-1LL)


nreloc *new_nreloc(void);
rlist *add_nreloc(rlist **,symbol *,taddr,int,int,int);
rlist *add_nreloc_masked(rlist **,symbol *,taddr,int,int,int,taddr);
void do_pic_check(rlist *);
taddr nreloc_real_addend(nreloc *);
void unsupp_reloc_error(rlist *);
void print_reloc(FILE *,int,nreloc *);

#endif
