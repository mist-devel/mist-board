/* output_elf.c ELF output driver for vasm */
/* (c) in 2002-2012 by Frank Wille */

#include "vasm.h"
#include "output_elf.h"
#if ELFCPU
static char *copyright="vasm ELF output module 2.1 (c)2002-2012 Frank Wille";
static int be,cpu;
static unsigned elfrelsize,shtreloc;

static struct list shdrlist,symlist,relalist;
static struct StrTabList shstrlist,strlist;

static unsigned symtabidx,strtabidx,shstrtabidx;
static unsigned symindex,shdrindex;
static unsigned stabidx,stabstridx;
static taddr stabsize,stabstrsize;


static unsigned addString(struct StrTabList *sl,char *s)
{
  struct StrTabNode *sn = mymalloc(sizeof(struct StrTabNode));
  unsigned idx = sl->index;

  sn->str = s;
  addtail(&(sl->l),&(sn->n));
  sl->index += (unsigned)strlen(s) + 1;
  return idx;
}


static void init_lists(void)
{
  initlist(&shdrlist);
  initlist(&symlist);
  initlist(&relalist);
  shstrlist.index = strlist.index = 0;
  initlist(&shstrlist.l);
  initlist(&strlist.l);
  symindex = shdrindex = stabidx = stabstridx = 0;
  addString(&shstrlist,"");  /* first string is always "" */
  symtabidx = addString(&shstrlist,".symtab");
  strtabidx = addString(&shstrlist,".strtab");
  shstrtabidx = addString(&shstrlist,".shstrtab");
  addString(&strlist,"");
}


static struct Shdr32Node *addShdr32(void)
{
  struct Shdr32Node *s = mycalloc(sizeof(struct Shdr32Node));

  addtail(&shdrlist,&(s->n));
  return s;
}


static struct Shdr64Node *addShdr64(void)
{
  struct Shdr64Node *s = mycalloc(sizeof(struct Shdr64Node));

  addtail(&shdrlist,&(s->n));
  return s;
}


static struct Symbol32Node *addSymbol32(char *name)
{
  struct Symbol32Node *sn = mycalloc(sizeof(struct Symbol32Node));

  addtail(&symlist,&(sn->n));
  if (name) {
    sn->name = name;
    setval(be,sn->s.st_name,4,addString(&strlist,name));
  }
  symindex++;
  return sn;
}


static struct Symbol64Node *addSymbol64(char *name)
{
  struct Symbol64Node *sn = mycalloc(sizeof(struct Symbol64Node));

  addtail(&symlist,&(sn->n));
  if (name) {
    sn->name = name;
    setval(be,sn->s.st_name,4,addString(&strlist,name));
  }
  symindex++;
  return sn;
}


static void newSym32(char *name,elfull value,elfull size,unsigned char bind,
                     unsigned char type,unsigned shndx)
{
  struct Symbol32Node *elfsym = addSymbol32(name);

  setval(be,elfsym->s.st_value,4,value);
  setval(be,elfsym->s.st_size,4,size);
  elfsym->s.st_info[0] = ELF32_ST_INFO(bind,type);
  setval(be,elfsym->s.st_shndx,2,shndx);
}


static void newSym64(char *name,elfull value,elfull size,unsigned char bind,
                     unsigned char type,unsigned shndx)
{
  struct Symbol64Node *elfsym = addSymbol64(name);

  setval(be,elfsym->s.st_value,8,value);
  setval(be,elfsym->s.st_size,8,size);
  elfsym->s.st_info[0] = ELF64_ST_INFO(bind,type);
  setval(be,elfsym->s.st_shndx,2,shndx);
}


static void addRel32(elfull o,elfull a,elfull i,elfull r)
{
  if (RELA) {
    struct Rela32Node *rn = mymalloc(sizeof(struct Rela32Node));

    setval(be,rn->r.r_offset,4,o);
    setval(be,rn->r.r_addend,4,a);
    setval(be,rn->r.r_info,4,ELF32_R_INFO(i,r));
    addtail(&relalist,&(rn->n));
  }
  else {
    struct Rel32Node *rn = mymalloc(sizeof(struct Rel32Node));

    setval(be,rn->r.r_offset,4,o);
    setval(be,rn->r.r_info,4,ELF32_R_INFO(i,r));
    addtail(&relalist,&(rn->n));
  }
}


static void addRel64(elfull o,elfull a,elfull i,elfull r)
{
  if (RELA) {
    struct Rela64Node *rn = mymalloc(sizeof(struct Rela64Node));

    setval(be,rn->r.r_offset,8,o);
    setval(be,rn->r.r_addend,8,a);
    setval(be,rn->r.r_info,8,ELF64_R_INFO(i,r));
    addtail(&relalist,&(rn->n));
  }
  else {
    struct Rel64Node *rn = mymalloc(sizeof(struct Rel64Node));

    setval(be,rn->r.r_offset,8,o);
    setval(be,rn->r.r_info,8,ELF64_R_INFO(i,r));
    addtail(&relalist,&(rn->n));
  }
}


static void *makeShdr32(elfull name,elfull type,elfull flags,elfull offset,
                        elfull size,elfull info,elfull align,elfull entsize)
{
  struct Shdr32Node *shn;

  shn = addShdr32();
  setval(be,shn->s.sh_name,4,name);
  setval(be,shn->s.sh_type,4,type);
  setval(be,shn->s.sh_flags,4,flags);
  setval(be,shn->s.sh_offset,4,offset);
  setval(be,shn->s.sh_size,4,size);
  setval(be,shn->s.sh_info,4,info);
  setval(be,shn->s.sh_addralign,4,align);
  setval(be,shn->s.sh_entsize,4,entsize);
  /* @@@ set sh_addr to org? */
  return shn;
}


static void *makeShdr64(elfull name,elfull type,elfull flags,elfull offset,
                        elfull size,elfull info,elfull align,elfull entsize)
{
  struct Shdr64Node *shn;

  shn = addShdr64();
  setval(be,shn->s.sh_name,4,name);
  setval(be,shn->s.sh_type,4,type);
  setval(be,shn->s.sh_flags,8,flags);
  setval(be,shn->s.sh_offset,8,offset);
  setval(be,shn->s.sh_size,8,size);
  setval(be,shn->s.sh_info,4,info);
  setval(be,shn->s.sh_addralign,8,align);
  setval(be,shn->s.sh_entsize,8,entsize);
  /* @@@ set sh_addr to org? */
  return shn;
}


static unsigned findelfsymbol(char *name)
/* find symbol with given name in symlist, return its index */
{
  /* also works for lists with Symbol64Node! */
  struct Symbol32Node *nextsym,*sym = (struct Symbol32Node *)symlist.first;
  unsigned sidx = 0;

  while (nextsym = (struct Symbol32Node *)sym->n.next) {
    if (sym->name)
      if (!strcmp(name,sym->name))
        break;
    ++sidx;
    sym = nextsym;
  }
  return nextsym ? sidx : 0;
}


static void init_ident(unsigned char *id,unsigned char class)
{
  static char elfid[4] = { 0x7f,'E','L','F' };

  memcpy(&id[EI_MAG0],elfid,4);
  id[EI_CLASS] = class;
  id[EI_DATA] = be ? ELFDATA2MSB : ELFDATA2LSB;
  id[EI_VERSION] = EV_CURRENT;
  memset(&id[EI_PAD],0,EI_NIDENT-EI_PAD);
}


static unsigned long get_sec_type(section *s)
/* scan section attributes for type */
{
  char *a = s->attr;

  if (!strncmp(s->name,".note",5))
    return SHT_NOTE;
  else if (!strcmp(s->name,".stabstr"))
    return SHT_STRTAB;

  while (*a) {
    switch (*a++) {
      case 'c':
      case 'd':
        return SHT_PROGBITS;
      case 'u':
        return SHT_NOBITS;
    }
  }
#if 0
  output_error(3,attr);  /* section attributes not suppported */
  return SHT_NULL;
#else
  return SHT_PROGBITS;
#endif
}


static taddr get_sec_flags(char *a)
/* scan section attributes for flags (read, write, alloc, execute) */
{
  taddr f = 0;

  while (*a) {
    switch (*a++) {
      case 'a':
        f |= SHF_ALLOC;
        break;
      case 'w':
        f |= SHF_WRITE;
        break;
      case 'x':
        f |= SHF_EXECINSTR;
        break;
    }
  }
  return f;
}


static unsigned char get_sym_info(symbol *s)
/* determine symbol-info: function, object, section, etc. */
{
  switch (TYPE(s)) {
    case TYPE_OBJECT:
      return STT_OBJECT;
    case TYPE_FUNCTION:
      return STT_FUNC;
    case TYPE_SECTION:
      return STT_SECTION;
    case TYPE_FILE:
      return STT_FILE;
  }
  return STT_NOTYPE;
}


static unsigned get_sym_index(symbol *s)
{
  if (s->flags & COMMON)
    return SHN_COMMON;
  if (s->type == IMPORT)
    return SHN_UNDEF;
  if (s->sec)
    return (unsigned)s->sec->idx;
  return SHN_ABS;
}


static taddr get_reloc_type(rlist **rl,
                            taddr *roffset,taddr *addend,symbol **refsym)
{
  rlist *rl2;
  taddr mask,offset;
  int size;
  taddr t = 0;

  *roffset = 0;
  *addend = 0;
  *refsym = NULL;

#ifdef VASM_CPU_M68K
#include "elf_reloc_68k.h"
#endif

#ifdef VASM_CPU_PPC
#include "elf_reloc_ppc.h"
#endif

#ifdef VASM_CPU_ARM
#include "elf_reloc_arm.h"
#endif

#ifdef VASM_CPU_X86
  if (bytespertaddr == 8) {
#include "elf_reloc_x86_64.h"
  }
  else {
#include "elf_reloc_386.h"
  }
#endif

  if (t)
    *roffset = offset>>3;
  else
    unsupp_reloc_error(*rl);

  return t;
}


static taddr make_relocs(rlist *rl,taddr pc,
                         void (*newsym)(char *,elfull,elfull,unsigned char,
                                        unsigned char,unsigned),
                         void (*addrel)(elfull,elfull,elfull,elfull))
/* convert all of an atom's relocations into ELF32/ELF64 relocs */
{
  taddr ro = 0;

  if (rl) {
    do {
      taddr rtype,offset,addend;
      symbol *refsym;

      if (rtype = get_reloc_type(&rl,&offset,&addend,&refsym)) {

        if (refsym->type == LABSYM) {
          /* this is a local relocation */
          addrel(pc+offset,addend,refsym->sec->idx,rtype);
          ro += elfrelsize;
        }
        else if (refsym->type == IMPORT) {
          /* this is an external symbol reference */
          unsigned idx = findelfsymbol(refsym->name);

          if (idx == 0) {
            /* create a new symbol, which can be referenced */
            idx = symindex;
            newsym(refsym->name,0,0,STB_GLOBAL,STT_NOTYPE,0);
          }
          addrel(pc+offset,addend,idx,rtype);
          ro += elfrelsize;
        }
        else
          ierror(0);
      }
    }
    while (rl = rl->next);
  }

  return ro;
}


static taddr prog_sec_hdrs(section *sec,taddr soffset,
                           void *(*makeshdr)(elfull,elfull,elfull,elfull,
                                             elfull,elfull,elfull,elfull),
                           void (*newsym)(char *,elfull,elfull,
                                          unsigned char,unsigned char,
                                          unsigned))
{
  section *secp;
  void *shn;

  /* generate section headers for program sections */
  for (secp=sec; secp; secp=secp->next) {
    if (get_sec_size(secp)>0 || (secp->flags & HAS_SYMBOLS)) {
      unsigned long type = get_sec_type(secp);

      secp->idx = ++shdrindex;

      if (!strcmp(secp->name,".stabstr")) {
        stabstridx = shdrindex;
        stabstrsize = get_sec_size(secp);
      }
      else if (!strcmp(secp->name,".stab")) {
        stabidx = shdrindex;
        stabsize = (get_sec_size(secp) / 12) - 1;  /* 12: sizeof(nlist32) */
      }

      shn = makeshdr(addString(&shstrlist,secp->name),
                     type,get_sec_flags(secp->attr),soffset,
                     get_sec_size(secp),0,secp->align,0);

      if (type != SHT_NOBITS)
        soffset += get_sec_size(secp);

      /* add section base symbol */
      newsym(NULL,0,0,STB_LOCAL,STT_SECTION,shdrindex);
    }
    else
      secp->idx = 0;
  }

  return soffset;
}


static unsigned build_symbol_table(symbol *first,
                                   void (*newsym)(char *,elfull,elfull,
                                                  unsigned char,unsigned char,
                                                  unsigned))
{
  symbol *symp;
  unsigned firstglobal;

  /* file name symbol, when defined */
  if (filename)
    newsym(filename,0,0,STB_LOCAL,STT_FILE,SHN_ABS);

  if (!no_symbols)  /* symbols with local binding first */
    for (symp=first; symp; symp=symp->next)
      if (*symp->name!='.' && *symp->name!=' ' && !(symp->flags&VASMINTERN))
        if (symp->type!=IMPORT && !(symp->flags & (EXPORT|WEAK)))
          newsym(symp->name,get_sym_value(symp),get_sym_size(symp),
                 STB_LOCAL,get_sym_info(symp),get_sym_index(symp));

  firstglobal = symindex;  /* now the global and weak symbols */

  for (symp=first; symp; symp=symp->next)
    if (*symp->name != '.'  && !(symp->flags&VASMINTERN))
      if ((symp->type!=IMPORT && (symp->flags & (EXPORT|WEAK))) ||
          (symp->type==IMPORT && (symp->flags & (COMMON|WEAK))))
        newsym(symp->name,get_sym_value(symp),get_sym_size(symp),
               (symp->flags & WEAK) ? STB_WEAK : STB_GLOBAL,
               get_sym_info(symp),get_sym_index(symp));

  return firstglobal;
}


static void make_reloc_sections(section *sec,
                                void (*newsym)(char *,elfull,elfull,
                                               unsigned char,unsigned char,
                                               unsigned),
                                void (*addrel)(elfull,elfull,elfull,elfull),
                                void *(*makeshdr)(elfull,elfull,elfull,elfull,
                                                  elfull,elfull,elfull,elfull))
{
  taddr roffset = 0;
  section *secp;

  /* ".rela.xxx" or ".rel.xxx" relocation sections */
  for (secp=sec; secp; secp=secp->next) {
    if (secp->idx) {
      atom *a;
      taddr pc=0,npc,basero=roffset;

      for (a=secp->first; a; a=a->next) {
        int align = a->align;

        npc = ((pc + align-1) / align) * align;
        if (a->type == DATA)
          roffset += make_relocs(a->content.db->relocs,npc,newsym,addrel);
        if (a->type == SPACE)
          roffset += make_relocs(a->content.sb->relocs,npc,newsym,addrel);
        pc = npc + atom_size(a,secp,npc);
      }

      if (basero != roffset) {  /* were there any relocations? */
        /* create .relaXX section header */
        char *sname = mymalloc(strlen(secp->name) + 6);

        if (RELA)
          sprintf(sname,".rela%s",secp->name);
        else
          sprintf(sname,".rel%s",secp->name);

        makeshdr(addString(&shstrlist,sname),shtreloc,0,
                 basero, /* relative offset - will be fixed later! */
                 roffset-basero,secp->idx,bytespertaddr,elfrelsize);
        ++shdrindex;
      }
    }
  }
}


static void write_section_data(FILE *f,section *sec)
{
  section *secp;

  for (secp=sec; secp; secp=secp->next) {
    if (secp->idx && get_sec_type(secp)!=SHT_NOBITS) {
      atom *a;
      taddr pc=0,npc;
      unsigned n;
      int align;

      if (secp->idx == stabidx) {
        /* patch compilation unit header */
        a = secp->first;
        if (a->content.db->size == 12) {
          unsigned char *p = a->content.db->data;

          setval(be,p,4,1);  /* refers to first string from .stabstr */
          setval(be,p+4,4,stabsize);
          setval(be,p+8,4,stabstrsize);
        }
      }

      for (a=secp->first; a; a=a->next) {
        align = a->align;
        npc = ((pc + align-1) / align) * align;
        for (n=npc-pc; n>0; n--)
          fw8(f,0);

        if (a->type == DATA) {
          fwdata(f,a->content.db->data,a->content.db->size);
        }
        else if (a->type == SPACE) {
          fwsblock(f,a->content.sb);
        }

        pc = npc + atom_size(a,secp,npc);
      }
    }
  }
}


static void write_strtab(FILE *f,struct StrTabList *strl)
{
  struct StrTabNode *stn;

  while (stn = (struct StrTabNode *)remhead(&(strl->l)))
    fwdata(f,stn->str,strlen(stn->str)+1);
}


static void write_ELF64(FILE *f,section *sec,symbol *sym)
{
  struct Elf64_Ehdr header;
  unsigned firstglobal,align1,align2,i;
  taddr soffset=sizeof(struct Elf64_Ehdr);
  struct Shdr64Node *shn;
  struct Symbol64Node *elfsym;

  elfrelsize = RELA ? sizeof(struct Elf64_Rela) : sizeof(struct Elf64_Rel);

  /* initialize ELF header */
  memset(&header,0,sizeof(struct Elf64_Ehdr));
  init_ident(header.e_ident,ELFCLASS64);
  setval(be,header.e_type,2,ET_REL);
  setval(be,header.e_machine,2,cpu);
  setval(be,header.e_version,4,EV_CURRENT);
  setval(be,header.e_ehsize,2,sizeof(struct Elf64_Ehdr));
  setval(be,header.e_shentsize,2,sizeof(struct Elf64_Shdr));

  init_lists();
  addShdr64();        /* first section header is always zero */
  addSymbol64(NULL);  /* first symbol is empty */

  /* make program section headers, symbols and relocations */
  soffset = prog_sec_hdrs(sec,soffset,makeShdr64,newSym64);
  firstglobal = build_symbol_table(sym,newSym64);
  make_reloc_sections(sec,newSym64,addRel64,makeShdr64);

  /* ".shstrtab" section header string table */
  ++shdrindex;
  makeShdr64(shstrtabidx,SHT_STRTAB,0,
             soffset,shstrlist.index,0,1,0);
  soffset += shstrlist.index;
  align1 = ((soffset + 3) & ~3) - soffset;
  soffset += align1;

  /* set last values in ELF header */
  setval(be,header.e_shoff,8,soffset);  /* remember offset of Shdr table */
  soffset += (shdrindex+3)*sizeof(struct Elf64_Shdr);
  setval(be,header.e_shstrndx,2,shdrindex);
  setval(be,header.e_shnum,2,shdrindex+3);

  /* ".symtab" symbol table */
  ++shdrindex;
  shn = makeShdr64(symtabidx,SHT_SYMTAB,0,soffset,
                   symindex*sizeof(struct Elf64_Sym),
                   firstglobal,8,sizeof(struct Elf64_Sym));
  setval(be,shn->s.sh_link,4,shdrindex+1);  /* associated .strtab section */
  soffset += symindex * sizeof(struct Elf64_Sym);

  /* ".strtab" string table */
  makeShdr64(strtabidx,SHT_STRTAB,0,soffset,strlist.index,0,1,0);
  soffset += strlist.index;
  align2 = ((soffset + 3) & ~3) - soffset;
  soffset += align2;  /* offset for first Reloc-entry */

  /* write ELF header */
  fwdata(f,&header,sizeof(struct Elf64_Ehdr));

  /* write initialized section contents */
  write_section_data(f,sec);

  /* write .shstrtab string table */
  write_strtab(f,&shstrlist);

  /* write section headers */
  for (i=0; i<align1; i++)
    fw8(f,0);
  i = 0;
  while (shn = (struct Shdr64Node *)remhead(&shdrlist)) {
    if (i == stabidx) {
      /* set link to stabstr table for .stab section */
      setval(be,shn->s.sh_link,4,stabstridx);
    }
    if (readval(be,shn->s.sh_type,4) == shtreloc) {
      /* set correct offset and link to symtab */
      setval(be,shn->s.sh_offset,8,readval(be,shn->s.sh_offset,8)+soffset);
      setval(be,shn->s.sh_link,4,shdrindex); /* index of associated symtab */
    }
    fwdata(f,&(shn->s),sizeof(struct Elf64_Shdr));
    i++;
  }

  /* write symbol table */
  while (elfsym = (struct Symbol64Node *)remhead(&symlist))
    fwdata(f,&(elfsym->s),sizeof(struct Elf64_Sym));

  /* write .strtab string table */
  write_strtab(f,&strlist);

  /* write relocations */
  for (i=0; i<align2; i++)
    fw8(f,0);
  if (RELA) {
    struct Rela64Node *rn;

    while (rn = (struct Rela64Node *)remhead(&relalist))
      fwdata(f,&(rn->r),sizeof(struct Elf64_Rela));
  }
  else {
    struct Rel64Node *rn;

    while (rn = (struct Rel64Node *)remhead(&relalist))
      fwdata(f,&(rn->r),sizeof(struct Elf64_Rel));
  }
}


static void write_ELF32(FILE *f,section *sec,symbol *sym)
{
  struct Elf32_Ehdr header;
  unsigned firstglobal,align1,align2,i;
  taddr soffset=sizeof(struct Elf32_Ehdr);
  struct Shdr32Node *shn;
  struct Symbol32Node *elfsym;

  elfrelsize = RELA ? sizeof(struct Elf32_Rela) : sizeof(struct Elf32_Rel);

  /* initialize ELF header */
  memset(&header,0,sizeof(struct Elf32_Ehdr));
  init_ident(header.e_ident,ELFCLASS32);
  setval(be,header.e_type,2,ET_REL);
  setval(be,header.e_machine,2,cpu);
  setval(be,header.e_version,4,EV_CURRENT);
#ifdef VASM_CPU_ARM
  setval(be,header.e_flags,4,0x04000000);  /* EABI version 4 */
#endif
  setval(be,header.e_ehsize,2,sizeof(struct Elf32_Ehdr));
  setval(be,header.e_shentsize,2,sizeof(struct Elf32_Shdr));

  init_lists();
  addShdr32();        /* first section header is always zero */
  addSymbol32(NULL);  /* first symbol is empty */

  /* make program section headers, symbols and relocations */
  soffset = prog_sec_hdrs(sec,soffset,makeShdr32,newSym32);
  firstglobal = build_symbol_table(sym,newSym32);
  make_reloc_sections(sec,newSym32,addRel32,makeShdr32);

  /* ".shstrtab" section header string table */
  ++shdrindex;
  makeShdr32(shstrtabidx,SHT_STRTAB,0,
             soffset,shstrlist.index,0,1,0);
  soffset += shstrlist.index;
  align1 = ((soffset + 3) & ~3) - soffset;
  soffset += align1;

  /* set last values in ELF header */
  setval(be,header.e_shoff,4,soffset);  /* remember offset of Shdr table */
  soffset += (shdrindex+3)*sizeof(struct Elf32_Shdr);
  setval(be,header.e_shstrndx,2,shdrindex);
  setval(be,header.e_shnum,2,shdrindex+3);

  /* ".symtab" symbol table */
  ++shdrindex;
  shn = makeShdr32(symtabidx,SHT_SYMTAB,0,soffset,
                   symindex*sizeof(struct Elf32_Sym),
                   firstglobal,4,sizeof(struct Elf32_Sym));
  setval(be,shn->s.sh_link,4,shdrindex+1);  /* associated .strtab section */
  soffset += symindex * sizeof(struct Elf32_Sym);

  /* ".strtab" string table */
  makeShdr32(strtabidx,SHT_STRTAB,0,soffset,strlist.index,0,1,0);
  soffset += strlist.index;
  align2 = ((soffset + 3) & ~3) - soffset;
  soffset += align2;  /* offset for first Reloc-entry */

  /* write ELF header */
  fwdata(f,&header,sizeof(struct Elf32_Ehdr));

  /* write initialized section contents */
  write_section_data(f,sec);

  /* write .shstrtab string table */
  write_strtab(f,&shstrlist);

  /* write section headers */
  for (i=0; i<align1; i++)
    fw8(f,0);
  i = 0;
  while (shn = (struct Shdr32Node *)remhead(&shdrlist)) {
    if (i == stabidx) {
      /* set link to stabstr table for .stab section */
      setval(be,shn->s.sh_link,4,stabstridx);
    }
    if (readval(be,shn->s.sh_type,4) == shtreloc) {
      /* set correct offset and link to symtab */
      setval(be,shn->s.sh_offset,4,readval(be,shn->s.sh_offset,4)+soffset);
      setval(be,shn->s.sh_link,4,shdrindex); /* index of associated symtab */
    }
    fwdata(f,&(shn->s),sizeof(struct Elf32_Shdr));
    i++;
  }

  /* write symbol table */
  while (elfsym = (struct Symbol32Node *)remhead(&symlist))
    fwdata(f,&(elfsym->s),sizeof(struct Elf32_Sym));

  /* write .strtab string table */
  write_strtab(f,&strlist);

  /* write relocations */
  for (i=0; i<align2; i++)
    fw8(f,0);
  if (RELA) {
    struct Rela32Node *rn;

    while (rn = (struct Rela32Node *)remhead(&relalist))
      fwdata(f,&(rn->r),sizeof(struct Elf32_Rela));
  }
  else {
    struct Rel32Node *rn;

    while (rn = (struct Rel32Node *)remhead(&relalist))
      fwdata(f,&(rn->r),sizeof(struct Elf32_Rel));
  }
}


static void write_output(FILE *f,section *sec,symbol *sym)
{
  int bits;

  cpu = ELFCPU;    /* cpu ID */
  be = BIGENDIAN;  /* true for big endian */
  bits = bytespertaddr * bitsperbyte;
  shtreloc = RELA ? SHT_RELA : SHT_REL;

  if (bits==32 && cpu!=EM_NONE)
    write_ELF32(f,sec,sym);
  else if (bits==64 && cpu!=EM_NONE)
    write_ELF64(f,sec,sym);
  else
    output_error(1,cpuname);  /* output module doesn't support cpu */
}


static int output_args(char *p)
{
  return 0;
}


int init_output_elf(char **cp,void (**wo)(FILE *,section *,symbol *),
                    int (**oa)(char *))
{
  *cp = copyright;
  *wo = write_output;
  *oa = output_args;
  return 1;
}

#else

int init_output_elf(char **cp,void (**wo)(FILE *,section *,symbol *),
                    int (**oa)(char *))
{
  return 0;
}

#endif
