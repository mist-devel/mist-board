/* output_aout.c a.out output driver for vasm */
/* (c) in 2008-2012 by Frank Wille */

#include "vasm.h"
#include "output_aout.h"
#if MID
static char *copyright="vasm a.out output module 0.5 (c) 2008-2012 Frank Wille";

static int mid = MID;

static section *sections[3];
static taddr secsize[3];
static taddr secoffs[3];
static int sectype[] = { N_TEXT, N_DATA, N_BSS };
static int secweak[] = { N_WEAKT, N_WEAKD, N_WEAKB };

static struct SymTabList aoutsymlist; 
static struct StrTabList aoutstrlist; 
static struct list treloclist;
static struct list dreloclist;

static int isPIC = 1;

#define SECT_ALIGN 4  /* .text and .data are aligned to 32 bits */


static unsigned int get_sec_type(section *s)
/* scan section attributes for type, 0=text, 1=data, 2=bss */
{
  char *a = s->attr;

  while (*a) {
    switch (*a++) {
      case 'c':
        return _TEXT;
      case 'd':
        return _DATA;
      case 'u':
        return _BSS;
    }
  }
  output_error(3,s->attr);  /* section attributes not suppported */
  return 0;
}


static int aout_getinfo(symbol *sym)
{
  int type;

  switch (TYPE(sym)) {
    case TYPE_UNKNOWN:
    case TYPE_FILE:
    case TYPE_SECTION:  /* this will be ignored later */
      type = AUX_UNKNOWN;
      break;
    case TYPE_OBJECT:
      type = AUX_OBJECT;
      break;
    case TYPE_FUNCTION:
      type = AUX_FUNC;
      break;
    default:
      ierror(0);
      break;
  }
  return type;
}


static int aout_getbind(symbol *sym)
{
  if (sym->flags & WEAK)
    return BIND_WEAK;
  else if (sym->type!=IMPORT && !(sym->flags & EXPORT))
    return BIND_LOCAL;
  else if ((sym->type!=IMPORT && (sym->flags & EXPORT)) ||
           (sym->type==IMPORT && (sym->flags & COMMON)))
    return BIND_GLOBAL;
  else
    ierror(0);
  return -1;
}


static unsigned long aoutstd_getrinfo(rlist *rl,int xtern,char *sname,int be)
/* Convert vasm relocation type into standard a.out relocations, */
/* as used by M68k and x86 targets. */
/* For xtern=-1, return true when this relocation requires a base symbol. */
{
  nreloc *nr;
  unsigned long r=0,s=4;
  int b=0;

  if (nr = (nreloc *)rl->reloc) {
    switch (rl->type) {
      case REL_ABS: b=-1; break;
      case REL_PC: b=RSTDB_pcrel; break;
      case REL_SD: b=RSTDB_baserel; break;
    }
    if (xtern == -1)  /* just query symbol-based relocation */
      return b==RSTDB_baserel || b==RSTDB_jmptable;

    if ((nr->offset&7)==0 &&
        (nr->mask & MAKEMASK(nr->size)) == MAKEMASK(nr->size)) {
      switch (nr->size) {
        case 8: s=0; break;
        case 16: s=1; break;
        case 32: s=2; break;
      }
    }

    if (b && s<4) {
      if (b > 0)
        setbits(be,&r,sizeof(r)<<3,(unsigned)b,1,1);
      setbits(be,&r,sizeof(r)<<3,RSTDB_length,RSTDS_length,s);
      setbits(be,&r,sizeof(r)<<3,RSTDB_extern,RSTDS_extern,xtern?1:0);
      return readbits(be,&r,sizeof(r)<<3,RELB_reloc,RELS_reloc);
    }
  }

  unsupp_reloc_error(rl);
  return ~0;
}


static void aout_initwrite(section *sec)
{
  initlist(&aoutstrlist.l);
  aoutstrlist.hashtab = mycalloc(STRHTABSIZE*sizeof(struct StrTabNode *));
  aoutstrlist.nextoffset = 4;  /* first string is always at offset 4 */
  initlist(&aoutsymlist.l);
  aoutsymlist.hashtab = mycalloc(SYMHTABSIZE*sizeof(struct SymbolNode *));
  aoutsymlist.nextindex = 0;
  initlist(&treloclist);
  initlist(&dreloclist);

  /* find exactly one .text, .data and .bss section for a.out */
  sections[_TEXT] = sections[_DATA] = sections[_BSS] = NULL;
  secsize[_TEXT] = secsize[_DATA] = secsize[_BSS] = 0;

  for (; sec; sec=sec->next) {
    int i;

    /* section size is assumed to be in in (sec->pc - sec->org), otherwise
       we would have to calculate it from the atoms and store it there */
    if ((sec->pc - sec->org) > 0 || (sec->flags & HAS_SYMBOLS)) {
      i = get_sec_type(sec);
      if (!sections[i]) {
        sections[i] = sec;
        secsize[i] = get_sec_size(sec);
        sec->idx = i;  /* section index 0:text, 1:data, 2:bss */
      }
      else
        output_error(7,sec->name);
    }
  }

  secoffs[_TEXT] = 0;
  secoffs[_DATA] = secsize[_TEXT] + balign(secsize[_TEXT],SECT_ALIGN);
  secoffs[_BSS] = secoffs[_DATA] + secsize[_DATA] +
                  balign(secsize[_DATA],SECT_ALIGN);
}


static unsigned long aout_addstr(char *s)
/* add a new symbol name to the string table and return its offset */
{
  struct StrTabNode **chain = &aoutstrlist.hashtab[hashcode(s)%STRHTABSIZE];
  struct StrTabNode *sn;

  if (*s == '\0')
    return 0;

  /* search string in hash table */
  while (sn = *chain) {
    if (!strcmp(s,sn->str))
      return (sn->offset);  /* it's already in, return offset */
    chain = &sn->hashchain;
  }

  /* new string table entry */
  *chain = sn = mymalloc(sizeof(struct StrTabNode));
  sn->hashchain = NULL;
  sn->str = s;
  sn->offset = aoutstrlist.nextoffset;
  addtail(&aoutstrlist.l,&sn->n);
  aoutstrlist.nextoffset += strlen(s) + 1;
  return sn->offset;
}


static unsigned long aout_addsym(char *name,taddr value,int bind,
                                 int info,int type,int desc,int be)
/* add a new symbol, return its symbol table index */
{
  struct SymbolNode **chain = &aoutsymlist.hashtab[hashcode(name)%SYMHTABSIZE];
  struct SymbolNode *sym;

  while (sym = *chain)
    chain = &sym->hashchain;
  /* new symbol table entry */
  *chain = sym = mycalloc(sizeof(struct SymbolNode));

  if (!name)
    name = emptystr;
  sym->name = name;
  sym->index = aoutsymlist.nextindex++;
  setval(be,sym->s.n_strx,4,aout_addstr(name));
  sym->s.n_type = type;
  /* GNU binutils don't use BIND_LOCAL/GLOBAL in a.out files! We do! */
  sym->s.n_other = ((bind&0xf)<<4) | (info&0xf);
  setval(be,sym->s.n_desc,2,desc);
  setval(be,sym->s.n_value,4,value);
  addtail(&aoutsymlist.l,&sym->n);
  return sym->index;
}


static int aout_findsym(char *name,int be)
/* find a symbol by its name, return symbol table index or -1 */
{
  struct SymbolNode **chain = &aoutsymlist.hashtab[hashcode(name)%SYMHTABSIZE];
  struct SymbolNode *sym;

  while (sym = *chain) {
    if (!strcmp(name,sym->name))
      return ((int)sym->index);
    chain = &sym->hashchain;
  }
  return (-1);
}


static void aout_symconvert(symbol *sym,int symbind,int syminfo,int be)
/* convert vasm symbol into a.out symbol(s) */
{
  taddr val = get_sym_value(sym);
  taddr size = get_sym_size(sym);
  int ext = (symbind == BIND_GLOBAL) ? N_EXT : 0;
  int type = 0;

  if (TYPE(sym) == TYPE_SECTION) {
    return;   /* section symbols are ignored in a.out! */
  }
  else if (TYPE(sym) == TYPE_FILE) {
    type = N_FN | N_EXT;  /* special case: file name symbol */
    size = 0;
  }
  else {
    if (sym->flags & COMMON) {
      /* common symbol */
      #if 0 /* GNU binutils prefers N_UNDF with val!=0 instead of N_COMM! */
      type = N_COMM | ext;
      #else
      type = N_UNDF | N_EXT;
      #endif
    }
    else if (sym->flags & WEAK) {
      /* weak symbol */
      switch (sym->type) {
        case LABSYM: type=secweak[sym->sec->idx]; break;
        case IMPORT: type=N_WEAKU; break;
        case EXPRESSION: type=N_WEAKA; break;
        default: ierror(0); break;
      }
    }
    else if (sym->sec) {
      /* address symbol */
      type = sectype[sym->sec->idx] | ext;
      val += secoffs[sym->sec->idx];  /* a.out requires to add sec. offset */
    }
    else if (sym->type==EXPRESSION) {
      if (sym->flags & EXPORT) {
        /* absolute symbol */
        type = N_ABS | ext;
      }
      else
        return;  /* ignore local expressions */
    }
    /* @@@ else if (indirect symbols?) {
      aout_addsym(sym->name,0,symbind,0,N_INDR|ext,0,be);
      aout_addsym(sym->indir_name,0,0,0,N_UNDF|N_EXT,0,be);
      return;
    }*/
    else
      ierror(0);
  }

  aout_addsym(sym->name,val,symbind,syminfo,type,0,be);
  if (size) {
    /* append N_SIZE symbol declaring the previous symbol's size */
    aout_addsym(sym->name,size,symbind,syminfo,N_SIZE,0,be);
  }
}


static void aout_addsymlist(symbol *sym,int bind,int type,int be)
/* add all symbols with specified bind and type to the a.out symbol list */
{
  for (; sym; sym=sym->next) {
    /* ignore symbols preceded by a '.' and internal symbols */
    if ((sym->type!=IMPORT || (sym->flags&WEAK))
        && *sym->name != '.' && *sym->name!=' ' && !(sym->flags&VASMINTERN)) {
      int syminfo = aout_getinfo(sym);
      int symbind = aout_getbind(sym);

      if (symbind == bind && (!type || (syminfo == type))) {
        aout_symconvert(sym,symbind,syminfo,be);
      }
    }
  }
}


static void aout_addreloclist(struct list *rlst,unsigned long raddr,
                              unsigned long rindex,unsigned long rinfo,int be)
/* add new relocation_info to .text or .data reloc-list */
{
  struct RelocNode *rn = mymalloc(sizeof(struct RelocNode));

  setval(be,rn->r.r_address,4,raddr);
  setbits(be,rn->r.r_info,32,RELB_symbolnum,RELS_symbolnum,rindex);
  setbits(be,rn->r.r_info,32,RELB_reloc,RELS_reloc,rinfo);
  addtail(rlst,&rn->n);

  if (isPIC && !readbits(be,rn->r.r_info,32,RSTDB_pcrel,1)
      && !readbits(be,rn->r.r_info,32,RSTDB_baserel,1)) {
    /* the relocation is probably absolute, so it is no PIC anymore */
    isPIC = 0;
  }
}


static unsigned long aout_convert_rlist(int be,atom *a,int secid,
                                        struct list *rlst,taddr pc,
                          unsigned long (*getrinfo)(rlist *,int,char *,int))
/* convert all of an atom's relocs into a.out relocations */
{
  unsigned long rsize = 0;
  rlist *rl;

  if (a->type == DATA)
    rl = a->content.db->relocs;
  else if (a->type == SPACE)
    rl = a->content.sb->relocs;
  else
    rl = NULL;

  if (!rl)
    return 0;  /* no relocs or not the right atom type */

  do {
    nreloc *r = (nreloc *)rl->reloc;
    symbol *refsym = r->sym;
    taddr val = get_sym_value(refsym);
    taddr add = nreloc_real_addend(r);
#if SDAHACK
    int based = getrinfo(rl,-1,sections[secid]->name,be) != 0;
#endif

    if (refsym->type == LABSYM) {
      /* this is a local relocation */
      int rsecid = refsym->sec->idx;

      aout_addreloclist(rlst,pc+(r->offset>>3),sectype[rsecid],
                        getrinfo(rl,0,sections[secid]->name,be),
                        be);
#if SDAHACK
      if (!based)  /* @@@ 'based' does not really happen in Unix */
#endif
        val += secoffs[rsecid];
      rsize += sizeof(struct relocation_info);
    }
    else if (refsym->type == IMPORT) {
      /* this is an external symbol reference */
      int symidx;

      if ((symidx = aout_findsym(refsym->name,be)) == -1)
        symidx = aout_addsym(refsym->name,0,0,0,N_UNDF|N_EXT,0,be);
      aout_addreloclist(rlst,pc+(r->offset>>3),symidx,
                        getrinfo(rl,1,sections[secid]->name,be),
                        be);
      rsize += sizeof(struct relocation_info);
    }
    else
      ierror(0);

    /* patch addend for a.out */
    if (rl->type == REL_PC)
      val -= pc + (r->offset >> 3);
    if (a->type == DATA)
      setval(be,a->content.db->data+(r->offset>>3),r->size>>3,val+add);
    else if (a->type==SPACE && a->content.sb->space!=0) {
      setval(be,a->content.sb->fill,r->size>>3,val+add);
      a->content.sb->space = 0;  /* we only need to patch 'fill' once */
    }
  }
  while (rl = rl->next);

  return rsize;
}


static unsigned long aout_addrelocs(int be,int secid,struct list *rlst,
                        unsigned long (*getrinfo)(rlist *,int,char *,int))
/* creates a.out relocations for a single section (.text or .data) */
{
  unsigned long rtabsize=0;

  if (sections[secid]) {
    atom *a;
    taddr pc=0,npc;

    for (a=sections[secid]->first; a; a=a->next) {
      int align = a->align;

      npc = ((pc + align-1) / align) * align;
      rtabsize += aout_convert_rlist(be,a,secid,rlst,npc,getrinfo);
      pc = npc + atom_size(a,sections[secid],npc);
    }
  }
  return rtabsize;
}


static void aout_header(FILE *f,unsigned long mag,unsigned long flag,
                        unsigned long tsize,unsigned long dsize,
                        unsigned long bsize,unsigned long syms,
                        unsigned long entry,unsigned long trsize,
                        unsigned long drsize,int be)
/* write an a.out header */
{
  struct aout_hdr h;

  SETMIDMAG(&h,mag,mid,flag);
  setval(be,h.a_text,4,tsize);
  setval(be,h.a_data,4,dsize);
  setval(be,h.a_bss,4,bsize);
  setval(be,h.a_syms,4,syms);
  setval(be,h.a_entry,4,entry);
  setval(be,h.a_trsize,4,trsize);
  setval(be,h.a_drsize,4,drsize);
  fwdata(f,&h,sizeof(struct aout_hdr));
}


static void aout_writesection(FILE *f,section *sec,taddr sec_align)
{
  if (sec) {
    atom *a;
    taddr pc=0,npc;
    int align,i;

    for (a=sec->first; a; a=a->next) {
      align = a->align;
      npc = ((pc + align-1) / align) * align;
      for (i=pc; i<npc; i++)
        fw8(f,0);
      if (a->type == DATA)
        fwdata(f,a->content.db->data,a->content.db->size);
      else if (a->type == SPACE)
        fwsblock(f,a->content.sb);
      pc = npc + atom_size(a,sec,npc);
    }
    fwalign(f,pc,sec_align);
  }
}


void aout_writerelocs(FILE *f,struct list *l)
{
  struct RelocNode *rn;

  while (rn = (struct RelocNode *)remhead(l))
    fwdata(f,&rn->r,sizeof(struct relocation_info));
}


void aout_writesymbols(FILE *f)
{
  struct SymbolNode *sym;

  while (sym = (struct SymbolNode *)remhead(&aoutsymlist.l))
    fwdata(f,&sym->s,sizeof(struct nlist32));
}


void aout_writestrings(FILE *f,int be)
{
  if (aoutstrlist.nextoffset > 4) {
    struct StrTabNode *stn;

    fw32(f,aoutstrlist.nextoffset,be);
    while (stn = (struct StrTabNode *)remhead(&aoutstrlist.l))
      fwdata(f,stn->str,strlen(stn->str)+1);
  }
}


static void write_output(FILE *f,section *sec,symbol *sym)
{
  int be = BIGENDIAN;
  unsigned long trsize,drsize;

  aout_initwrite(sec);
  aout_addsymlist(sym,BIND_GLOBAL,0,be);
  aout_addsymlist(sym,BIND_WEAK,0,be);
  if (!no_symbols) {
    aout_addsymlist(sym,BIND_LOCAL,0,be);
    /* @@@ stabs??? aout_debugsyms(???,be); */
  }
  trsize = aout_addrelocs(be,_TEXT,&treloclist,aoutstd_getrinfo);
  drsize = aout_addrelocs(be,_DATA,&dreloclist,aoutstd_getrinfo);

  aout_header(f,OMAGIC,isPIC?EX_PIC:0,
              secsize[_TEXT] + balign(secsize[_TEXT],SECT_ALIGN),
              secsize[_DATA] + balign(secsize[_DATA],SECT_ALIGN),
              secsize[_BSS],
              aoutsymlist.nextindex * sizeof(struct nlist32),
              0,trsize,drsize,be);
  aout_writesection(f,sections[_TEXT],SECT_ALIGN);
  aout_writesection(f,sections[_DATA],SECT_ALIGN);
  aout_writerelocs(f,&treloclist);
  aout_writerelocs(f,&dreloclist);
  aout_writesymbols(f);
  aout_writestrings(f,be);
}


static int output_args(char *p)
{
  if (!strncmp(p,"-mid=",5)) {
    mid = atoi(p+5);
    return 1;
  }
  return 0;
}


int init_output_aout(char **cp,void (**wo)(FILE *,section *,symbol *),
                     int (**oa)(char *))
{
  *cp = copyright;
  *wo = write_output;
  *oa = output_args;
  return 1;
}

#else

int init_output_aout(char **cp,void (**wo)(FILE *,section *,symbol *),
                     int (**oa)(char *))
{
  return 0;
}
#endif
