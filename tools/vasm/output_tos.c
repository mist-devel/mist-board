/* output_tos.c Atari TOS executable output driver for vasm */
/* (c) in 2009-2013 by Frank Wille */

#include "vasm.h"
#include "output_tos.h"
#if defined(VASM_CPU_M68K)
static char *copyright="vasm tos output module 0.8 (c) 2009-2013 Frank Wille";

static int tosflags = 0;
static int max_relocs_per_atom;
static section *sections[3];
static taddr secsize[3];
static taddr secoffs[3];
static taddr sdabase,lastoffs;

#define SECT_ALIGN 2  /* TOS sections have to be aligned to 16 bits */


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


static int tos_initwrite(section *sec,symbol *sym)
{
  int nsyms = 0;
  int i;

  /* find exactly one .text, .data and .bss section for a.out */
  sections[_TEXT] = sections[_DATA] = sections[_BSS] = NULL;
  secsize[_TEXT] = secsize[_DATA] = secsize[_BSS] = 0;

  for (; sec; sec=sec->next) {
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

  max_relocs_per_atom = 0;
  secoffs[_TEXT] = 0;
  secoffs[_DATA] = secsize[_TEXT] + balign(secsize[_TEXT],SECT_ALIGN);
  secoffs[_BSS] = secoffs[_DATA] + secsize[_DATA] +
                  balign(secsize[_DATA],SECT_ALIGN);
  /* define small data base as .data+32768 @@@FIXME! */
  sdabase = secoffs[_DATA] + 0x8000;

  /* count symbols */
  for (; sym; sym=sym->next) {
    /* ignore symbols preceded by a '.' and internal symbols */
    if (*sym->name!='.' && *sym->name!=' ' && !(sym->flags&VASMINTERN)) {
      nsyms++;
      if (strlen(sym->name) > DRI_NAMELEN)
        nsyms++;  /* extra symbol for long name */
    }
    else {
      if (!strcmp(sym->name," TOSFLAGS")) {
        if (tosflags == 0)  /* not defined by command line? */
          tosflags = (int)get_sym_value(sym);
      }
      sym->flags |= VASMINTERN;
    }
  }
  return no_symbols ? 0 : nsyms;
}


static void tos_header(FILE *f,unsigned long tsize,unsigned long dsize,
                        unsigned long bsize,unsigned long ssize,
                        unsigned long flags)
{
  PH hdr;

  setval(1,hdr.ph_branch,2,0x601a);
  setval(1,hdr.ph_tlen,4,tsize);
  setval(1,hdr.ph_dlen,4,dsize);
  setval(1,hdr.ph_blen,4,bsize);
  setval(1,hdr.ph_slen,4,ssize);
  setval(1,hdr.ph_magic,4,0);
  setval(1,hdr.ph_flags,4,flags);
  setval(1,hdr.ph_abs,2,0);
  fwdata(f,&hdr,sizeof(PH));
}


static void checkdefined(symbol *sym)
{
  if (sym->type == IMPORT)
    output_error(6,sym->name);
}


static taddr tos_sym_value(symbol *sym)
{
  taddr val = get_sym_value(sym);

  /* all sections form a contiguous block, so add section offset */
  if (sym->type == LABSYM)
    val += secoffs[sym->sec->idx];

  checkdefined(sym);
  return val;
}


static void write_reloc68k(atom *a,nreloc *nrel,taddr val)
{
  char *p;

  if (a->type == DATA)
    p = a->content.db->data + (nrel->offset>>3);
  else if (a->type == SPACE)
    p = (char *)a->content.sb->fill;  /* @@@ ignore offset completely? */
  else
    return;
  setbits(1,p,((nrel->offset&7)+nrel->size+7)&~7,nrel->offset&7,nrel->size,val);
}


static void do_relocs(taddr pc,atom *a)
/* Try to resolve all relocations in a DATA or SPACE atom.
   Very simple implementation which can only handle basic 68k relocs. */
{
  int rcnt = 0;
  section *sec;
  rlist *rl;

  if (a->type == DATA)
    rl = a->content.db->relocs;
  else if (a->type == SPACE)
    rl = a->content.sb->relocs;
  else
    rl = NULL;

  while (rl) {
    switch (rl->type) {
      case REL_SD:
        write_reloc68k(a,rl->reloc,
                       (tos_sym_value(((nreloc *)rl->reloc)->sym)
                        + nreloc_real_addend(rl->reloc)) - sdabase);
      case REL_PC:
        write_reloc68k(a,rl->reloc,
                       (tos_sym_value(((nreloc *)rl->reloc)->sym)
                        + nreloc_real_addend(rl->reloc)) -
                       (pc + (((nreloc *)rl->reloc)->offset>>3)));
        break;
      case REL_ABS:
        checkdefined(((nreloc *)rl->reloc)->sym);
        sec = ((nreloc *)rl->reloc)->sym->sec;
        write_reloc68k(a,rl->reloc,
                       secoffs[sec?sec->idx:0]+((nreloc *)rl->reloc)->addend);
        if (((nreloc *)rl->reloc)->size == 32)
          break;  /* only support 32-bit absolute */
      default:
        unsupp_reloc_error(rl);
        break;
    }
    rcnt++;
    if (a->type == SPACE)
      break;  /* all SPACE relocs are identical, one is enough */
    rl = rl->next;
  }

  if (rcnt > max_relocs_per_atom)
    max_relocs_per_atom = rcnt;
}


static void tos_writesection(FILE *f,section *sec,taddr sec_align)
{
  if (sec) {
    taddr pc = secoffs[sec->idx];
    taddr npc;
    int align,i;
    atom *a;

    for (a=sec->first; a; a=a->next) {
      align = a->align;
      npc = ((pc + align-1) / align) * align;
      for (i=pc; i<npc; i++)
        fw8(f,0);
      do_relocs(npc,a);
      if (a->type == DATA)
        fwdata(f,a->content.db->data,a->content.db->size);
      else if (a->type == SPACE)
        fwsblock(f,a->content.sb);
      pc = npc + atom_size(a,sec,npc);
    }
    fwalign(f,pc,sec_align);
  }
}


static void write_dri_sym(FILE *f,char *name,int type,taddr value)
{
  struct DRIsym stab;
  int longname = strlen(name) > DRI_NAMELEN;

  strncpy(stab.name,name,DRI_NAMELEN);
  setval(1,stab.type,sizeof(stab.type),longname?(type|STYP_LONGNAME):type);
  setval(1,stab.value,sizeof(stab.value),value);
  fwdata(f,&stab,sizeof(struct DRIsym));

  if (longname) {
    char rest_of_name[sizeof(struct DRIsym)];

    memset(rest_of_name,0,sizeof(struct DRIsym));
    strncpy(rest_of_name,name+DRI_NAMELEN,sizeof(struct DRIsym));
    fwdata(f,rest_of_name,sizeof(struct DRIsym));
  }
}


static void tos_symboltable(FILE *f,symbol *sym)
{
  static int labtype[] = { STYP_TEXT,STYP_DATA,STYP_BSS };
  int t;

  for (; sym; sym=sym->next) {
    if (!(sym->flags & VASMINTERN)) {
      if (sym->type == EXPRESSION)
        t = STYP_EQUATED | STYP_DEFINED;
      else if (sym->type == LABSYM)
        t = labtype[sym->sec->idx] | STYP_DEFINED;
      else if (sym->type != IMPORT)
        ierror(0);

      if (sym->flags & EXPORT)
        t |= STYP_GLOBAL;
      write_dri_sym(f,sym->name,t,get_sym_value(sym));
    }
  }
}


static int offscmp(const void *offs1,const void *offs2)
{
  return *(int *)offs1 - *(int *)offs2;
}


static int tos_writerelocs(FILE *f,section *sec)
{
  int n = 0;
  int *sortoffs = mymalloc(max_relocs_per_atom*sizeof(int));

  if (sec) {
    taddr pc = secoffs[sec->idx];
    taddr npc;
    int align;
    atom *a;
    rlist *rl;

    for (a=sec->first; a; a=a->next) {
      int offs,nrel=0;

      align = a->align;
      npc = ((pc + align-1) / align) * align;

      if (a->type == DATA)
        rl = a->content.db->relocs;
      else if (a->type == SPACE)
        rl = a->content.sb->relocs;
      else
        rl = NULL;

      while (rl) {
        if (rl->type==REL_ABS && ((nreloc *)rl->reloc)->size==32)
          sortoffs[nrel++] = ((nreloc *)rl->reloc)->offset;
        rl = rl->next;
      }

      if (nrel) {
        int i;

        /* first sort the atom's relocs */
        if (nrel > 1)
          qsort(sortoffs,nrel,sizeof(int),offscmp);

        /* write differences between them */
        n += nrel;
        for (i=0; i<nrel; i++) {
          taddr newoffs = npc + (taddr)(sortoffs[i]>>3);

          if (lastoffs) {
            /* determine 8bit difference to next relocation */
            long diff = newoffs - lastoffs;

            if (diff < 0)
              ierror(0);
            while (diff > 254) {
              fw8(f,1);
              diff -= 254;
            }
            fw8(f,(unsigned char)diff);
          }
          else  /* first entry is a 32 bits offset */
            fw32(f,newoffs,1);
          lastoffs = newoffs;
        }
      }
      pc = npc + atom_size(a,sec,npc);
    }
  }

  myfree(sortoffs);
  return n;
}


static void write_output(FILE *f,section *sec,symbol *sym)
{
  int nsyms = tos_initwrite(sec,sym);
  int nrelocs = 0;

  tos_header(f,secsize[_TEXT],secsize[_DATA],secsize[_BSS],
             nsyms*sizeof(struct DRIsym),tosflags);
  tos_writesection(f,sections[_TEXT],SECT_ALIGN);
  tos_writesection(f,sections[_DATA],SECT_ALIGN);
  if (nsyms)
    tos_symboltable(f,sym);
  nrelocs += tos_writerelocs(f,sections[_TEXT]);
  nrelocs += tos_writerelocs(f,sections[_DATA]);
  if (nrelocs)
    fw8(f,0);
  else
    fw32(f,0,1);
}


static int output_args(char *p)
{
  if (!strncmp(p,"-tos-flags=",5)) {
    tosflags = atoi(p+11);
    return 1;
  }
  return 0;
}


int init_output_tos(char **cp,void (**wo)(FILE *,section *,symbol *),
                    int (**oa)(char *))
{
  *cp = copyright;
  *wo = write_output;
  *oa = output_args;
  return 1;
}

#else

int init_output_tos(char **cp,void (**wo)(FILE *,section *,symbol *),
                    int (**oa)(char *))
{
  return 0;
}
#endif
