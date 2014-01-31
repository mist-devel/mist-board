/* output_hunk.c AmigaOS hunk format output driver for vasm */
/* (c) in 2002-2012 by Frank Wille */

#include "vasm.h"
#include "output_hunk.h"
#if defined(VASM_CPU_M68K) || defined(VASM_CPU_PPC)
static char *copyright="vasm hunk format output module 2.3 (c) 2002-2012 Frank Wille";

static int databss = 0;
static int exthunk;


static uint32_t strlen32(char *s)
/* calculate number of 32 bit words required for
   a string without terminator */
{
  return (strlen(s) + 3) >> 2;
}


static void fwname(FILE *f,char *name)
{
  size_t n = strlen(name);

  fwdata(f,name,n);
  fwalign(f,n,4);
}


static section *dummy_section(void)
{
  return new_section(".text","acrx3",8);
}


static uint32_t scan_attr(section *sec)
/* extract hunk-type from section attributes */
{
  uint32_t type = 0;
  char *p = sec->attr;

  if (*p != '\0') {
    while (*p) {
      switch (*p++) {
#if defined(VASM_CPU_PPC)
        case 'c': type = HUNK_PPC_CODE; break;
#else
        case 'c': type = HUNK_CODE; break;
#endif
        case 'd': type = HUNK_DATA; break;
        case 'u': type = HUNK_BSS; break;
        case 'C': type |= HUNKF_CHIP; break;
        case 'F': type |= HUNKF_FAST; break;
      }
    }
  }
  else
    type = HUNK_DATA;

  return type;
}


static section *check_symbols(section *first_sec,symbol *sym)
/* Make sure that every common symbol is referenced, otherwise there
   is no possibility to represent such a symbol in hunk format.
   Additionally we have to guarantee that at least one section exists,
   when there are any symbols. */
{
  atom *a;
  rlist *rl;
  section *sec,*first_nonbss=NULL;
  int abs_detect = 0;  /* any absolute symbol definitions present? */

  for (sec=first_sec; sec; sec=sec->next) {
    if ((scan_attr(sec) & ~HUNKF_MEMTYPE) != HUNK_BSS)
      first_nonbss = sec;

    /* remember all common-symbol references */
    for (a=sec->first; a; a=a->next) {
      if (a->type == DATA) {
        for (rl=a->content.db->relocs; rl; rl=rl->next) {
          if (rl->type==REL_ABS || rl->type==REL_PC) {
            if (((nreloc *)rl->reloc)->size==32) {
              symbol *s = ((nreloc *)rl->reloc)->sym;

              if (s->flags & COMMON)
                s->flags |= COMM_REFERENCED;
            }
          }
        }
      }
    }
  }

  /* check common symbols */
  for (; sym; sym=sym->next) {
    if (*sym->name == ' ')  /* internal symbol - will be ignored */
      sym->flags |= VASMINTERN;
    else if ((sym->flags & COMMON) && !(sym->flags & COMM_REFERENCED)) {
      /* create a dummy reference for each unreferenced common symbol */
      dblock *db = new_dblock();
      nreloc *r = new_nreloc();
      rlist *rl = mymalloc(sizeof(rlist));

      db->size = 4;
      db->data = mycalloc(db->size);
      db->relocs = rl;
      rl->next = NULL;
      rl->type = REL_ABS;
      rl->reloc = r;
      r->size = 32;
      r->sym = sym;
      if (first_nonbss == NULL) {
        first_nonbss = dummy_section();
        if (first_sec == NULL)
          first_sec = first_nonbss;
      }
      add_atom(first_nonbss,new_data_atom(db,4));
    }
    else if (sym->type==EXPRESSION && (sym->flags & EXPORT))
      abs_detect = 1;
  }

  /* find section for absolute symbols, when present */
  if (abs_detect) {
    if (first_sec == NULL)
      first_sec = dummy_section();
    first_sec->flags |= HAS_SYMBOLS;
  }

  return first_sec;
}


static size_t prepare_sections(section *sec)
/* assign an index to each section, delete empty ones,
   returns number of sections present */
{
  size_t cnt = 0;

  for (; sec; sec=sec->next) {
    if (get_sec_size(sec) > 0 || (sec->flags & HAS_SYMBOLS))
      sec->idx = cnt++;
    else
      sec->flags |= SEC_DELETED;
  }
  return cnt;
}


static taddr file_size(section *sec)
/* determine a section's initialized data size, which occupies space in
   the executable file */
{
  taddr pc=0,zpc=0,npc;
  atom *a;

  for (a=sec->first; a; a=a->next) {
    int align = a->align;
    int zerodata = 1;
    char *d;

    npc = ((pc + align-1) / align) * align;
    if (a->type == DATA) {
      /* do we have relocations or non-zero data in this atom? */
      if (a->content.db->relocs) {
        zerodata = 0;
      }
      else {
       	for (d=a->content.db->data;
             d<a->content.db->data+a->content.db->size; d++) {
          if (*d) {
            zerodata = 0;
            break;
          }
        }
      }
    }
    else if (a->type == SPACE) {
      /* do we have relocations or non-zero data in this atom? */
      if (a->content.sb->relocs) {
        zerodata = 0;
      }
      else {
        for (d=a->content.sb->fill;
             d<(char *)a->content.sb->fill+a->content.sb->size; d++) {
          if (*d) {
            zerodata = 0;
            break;
          }
        }
      }
    }
    pc = npc + atom_size(a,sec,npc);
    if (!zerodata)
      zpc = pc;
  }
  return zpc;
}


static struct hunkreloc *convert_reloc(rlist *rl,taddr pc)
{
  nreloc *r = (nreloc *)rl->reloc;

  if (rl->type <= LAST_STANDARD_RELOC
#if defined(VASM_CPU_PPC)
      || rl->type==REL_PPCEABI_SDA2
#endif
     ) {
    if (r->sym->type == LABSYM) {
      struct hunkreloc *hr;
      uint32_t type;
      uint32_t offs = pc + (r->offset >> 3);

      switch (rl->type) {
        case REL_ABS:
          if (r->size!=32 || (r->offset&7) || r->mask!=-1)
            return NULL;
          type = HUNK_ABSRELOC32;
          break;

        case REL_PC:
          switch (r->size) {
            case 8:
              if ((r->offset&7) || r->mask!=-1)
                return NULL;
              type = HUNK_RELRELOC8;
              break;
            case 14:
              if ((r->offset&15) || r->mask!=0xfffc)
                return NULL;
              type = HUNK_RELRELOC16;
              break;
            case 16:
              if ((r->offset&7) || r->mask!=-1)
                return NULL;
              type = HUNK_RELRELOC16;
              break;
#if defined(VASM_CPU_PPC)
            case 24:
              if ((r->offset&31)!=6 || r->mask!=0x3fffffc)
                return NULL;
              type = HUNK_RELRELOC26;
              break;
#endif
            case 32:
              if ((r->offset&7) || r->mask!=-1)
                return NULL;
              type = HUNK_RELRELOC32;
              break;
          }
          break;

#if defined(VASM_CPU_PPC)
        case REL_PPCEABI_SDA2: /* treat as REL_SD for WarpOS/EHF */
#endif
        case REL_SD:
          if (r->size!=16 || (r->offset&7) || r->mask!=-1)
            return NULL;
          type = HUNK_DREL16;
          break;

        default:
          return NULL;
      }

      hr = mymalloc(sizeof(struct hunkreloc));
      hr->hunk_id = type;
      hr->hunk_offset = offs;
      hr->hunk_index = r->sym->sec->idx;
      return hr;
    }
  }

  return NULL;
}


static struct hunkxref *convert_xref(rlist *rl,taddr pc)
{
  nreloc *r = (nreloc *)rl->reloc;

  if (rl->type <= LAST_STANDARD_RELOC
#if defined(VASM_CPU_PPC)
      || rl->type==REL_PPCEABI_SDA2
#endif
     ) {
    if (r->sym->type == IMPORT) {
      struct hunkxref *xref;
      uint32_t type,size=0;
      uint32_t offs = pc + (r->offset >> 3);
      int com = (r->sym->flags & COMMON) != 0;

      switch (rl->type) {
        case REL_ABS:
          if ((r->offset&7) || r->mask!=-1 || (com && r->size!=32))
            return NULL;
          switch (r->size) {
            case 8:
              type = EXT_ABSREF8;
              break;
            case 16:
              type = EXT_ABSREF16;
              break;
            case 32:
              if (com) {
                type = EXT_ABSCOMMON;
                size = get_sym_size(r->sym);
              }
              else
                type = EXT_ABSREF32;
              break;
          }
          break;

        case REL_PC:
          switch (r->size) {
            case 8:
              if ((r->offset&7) || r->mask!=-1 || com)
                return NULL;
              type = EXT_RELREF8;
              break;
            case 14:
              if ((r->offset&15) || r->mask!=0xfffc || com)
                return NULL;
              type = EXT_RELREF16;
              break;
            case 16:
              if ((r->offset&7) || r->mask!=-1 || com)
                return NULL;
              type = EXT_RELREF16;
              break;
#if defined(VASM_CPU_PPC)
            case 24:
              if ((r->offset&31)!=6 || r->mask!=0x3fffffc || com)
                return NULL;
              type = EXT_RELREF26;
              break;
#endif
            case 32:
              if ((r->offset&7) || r->mask!=-1)
                return NULL;
              if (com) {
                type = EXT_RELCOMMON;
                size = get_sym_size(r->sym);
              }
              else
                type = EXT_RELREF32;
              break;
          }
          break;

#if defined(VASM_CPU_PPC)
        case REL_PPCEABI_SDA2: /* treat as REL_SD for WarpOS/EHF */
#endif
        case REL_SD:
          if (r->size!=16 || (r->offset&7) || r->mask!=-1)
            return NULL;
          type = EXT_DEXT16;
          break;

        default:
          return NULL;
      }

      xref = mymalloc(sizeof(struct hunkxref));
      xref->name = r->sym->name;
      xref->type = type;
      xref->size = size;
      xref->offset = offs;
      return xref;
    }
  }

  return NULL;
}


static void process_relocs(rlist *rl,struct list *reloclist,
                           struct list *xreflist,section *sec,taddr pc)
/* convert an atom's rlist into relocations and xrefs */
{
  if (rl == NULL)
    return;

  do {
    struct hunkreloc *hr = convert_reloc(rl,pc);

    if (hr!=NULL && (xreflist!=NULL || hr->hunk_id==HUNK_ABSRELOC32)) {
      addtail(reloclist,&hr->n);       /* add new relocation */
    }
    else {
      struct hunkxref *xref = convert_xref(rl,pc);

      if (xref) {
        if (xreflist)
          addtail(xreflist,&xref->n);  /* add new external reference */
        else
          output_error(8,xref->name,sec->name,xref->offset,rl->type);
      }
      else
        unsupp_reloc_error(rl);  /* reloc not supported */
    }
  }
  while (rl = rl->next);
}


static void reloc_hunk(FILE *f,uint32_t type,struct list *reloclist)
/* write all section-offsets for one relocation type */
{
  int headerflag = 0;

  for (;;) {
    struct hunkreloc *r,*next;
    int idx;
    uint32_t n;

    for (r=(struct hunkreloc *)reloclist->first,idx=-1,n=0;
         r->n.next; r=(struct hunkreloc *)r->n.next) {
      if (r->hunk_id == type) {
        if (idx < 0)
          idx = r->hunk_index;
        if (r->hunk_index == idx)
          n++;
      }
    }
    if (n > 0) {
      if (!headerflag) {
        fw32(f,type,1);
        headerflag = 1;
      }
      fw32(f,n,1);
      fw32(f,(uint32_t)idx,1);
      r = (struct hunkreloc *)reloclist->first;
      while (next = (struct hunkreloc *)r->n.next) {
        if (r->hunk_id==type && r->hunk_index==idx) {
          fw32(f,r->hunk_offset,1);
          remnode(&r->n);
          myfree(r);
        }
        r = next;
      }
    }
    else
      break;  /* no more relocations for this type found */
  }
  if (headerflag)
    fw32(f,0,1);
}


static void linedebug_hunk(FILE *f,struct list *ldblist,int num)
{
  if (num > 0) {
    struct hunkline *hl;
    uint32_t srcname_len = strlen32(getdebugname());

    fw32(f,HUNK_DEBUG,1);
    fw32(f,srcname_len + num*2 + 3,1);
    fw32(f,0,1);
    fw32(f,0x4c494e45,1);  /* "LINE" */
    fw32(f,srcname_len,1);
    fwname(f,getdebugname());

    for (hl=(struct hunkline *)ldblist->first;
         hl->n.next; hl=(struct hunkline *)hl->n.next) {
      fw32(f,hl->line,1);
      fw32(f,hl->offset,1);
    }
  }
}


static void extheader(FILE *f)
{
  if (!exthunk) {
    exthunk = 1;
    fw32(f,HUNK_EXT,1);
  }
}


static void exttrailer(FILE *f)
{
  if (exthunk)
    fw32(f,0,1);
}


static void ext_refs(FILE *f,struct list *xreflist)
/* write all external references from a section into a HUNK_EXT hunk */
{
  while (xreflist->first->next) {
    struct hunkxref *x,*next;
    uint32_t n,type,size;
    char *name;

    extheader(f);
    x = (struct hunkxref *)xreflist->first;
    name = x->name;
    type = x->type;
    size = x->size;

    for (n=0,x=(struct hunkxref *)xreflist->first;
         x->n.next; x=(struct hunkxref *)x->n.next) {
      if (!strcmp(x->name,name) && x->type==type)
        n++;
    }
    fw32(f,(type<<24) | strlen32(name),1);
    fwname(f,name);
    if (type==EXT_ABSCOMMON || type==EXT_RELCOMMON)
      fw32(f,size,1);
    fw32(f,n,1);

    x = (struct hunkxref *)xreflist->first;
    while (next = (struct hunkxref *)x->n.next) {
      if (!strcmp(x->name,name) && x->type==type) {
        fw32(f,x->offset,1);
        remnode(&x->n);
        myfree(x);
      }
      x = next;
    }
  }
}


static void ext_defs(FILE *f,symbol *sym,int symtype,int global,
                     size_t idx,uint32_t xtype)
{
  int header = 0;

  for (; sym; sym=sym->next) {
    if (!(sym->flags & VASMINTERN)) {
      if (sym->type==symtype && (sym->flags&global)==global &&
          (symtype==EXPRESSION ? 1 : sym->sec->idx==idx)) {
        if (!header) {
          header = 1;
          if (xtype == EXT_SYMB)
            fw32(f,HUNK_SYMBOL,1);
          else
            extheader(f);
        }
        fw32(f,(xtype<<24) | strlen32(sym->name),1);
        fwname(f,sym->name);
        fw32(f,(uint32_t)get_sym_value(sym),1);
      }
    }
  }
  if (header && xtype==EXT_SYMB)
    fw32(f,0,1);
}


static void write_object(FILE *f,section *sec,symbol *sym)
{
  int wrotesec = 0;

  sec = check_symbols(sec,sym);
  prepare_sections(sec);

  /* write header */
  fw32(f,HUNK_UNIT,1);
  fw32(f,strlen32(filename),1);
  fwname(f,filename);

  if (sec) {
    for (; sec; sec=sec->next) {
      if (!(sec->flags & SEC_DELETED)) {
        uint32_t type;
        atom *a;
        struct list reloclist,xreflist,linedblist;
        int num_linedb = 0;

        wrotesec = 1;
        initlist(&reloclist);
        initlist(&xreflist);
        initlist(&linedblist);

        /* section name */
        if (strlen(sec->name)) {
          fw32(f,HUNK_NAME,1);
          fw32(f,strlen32(sec->name),1);
          fwname(f,sec->name);
        }

        /* section type */
        if (!(type = scan_attr(sec))) {
          output_error(3,sec->attr);  /* section attributes not suppported */
          type = HUNK_DATA;  /* default */
        }
        fw32(f,type,1);
        fw32(f,(get_sec_size(sec)+3)>>2,1);  /* size */

        if ((type & ~HUNKF_MEMTYPE) != HUNK_BSS) {
          /* write contents */
          taddr pc=0,npc;
          int i;

          for (a=sec->first; a; a=a->next) {
            int align = a->align;
            rlist *rl;

            npc = ((pc + align-1) / align) * align;
            for (i=pc; i<npc; i++)
              fw8(f,0);

            if (a->type == DATA) {
              fwdata(f,a->content.db->data,a->content.db->size);
              process_relocs(a->content.db->relocs,
                             &reloclist,&xreflist,sec,npc);
            }
            else if (a->type == SPACE) {
              fwsblock(f,a->content.sb);
              process_relocs(a->content.sb->relocs,
                             &reloclist,&xreflist,sec,npc);
            }
            else if (a->type == LINE) {
              struct hunkline *ldebug = mymalloc(sizeof(struct hunkline));

              ldebug->line = (uint32_t)a->content.srcline;
              ldebug->offset = (uint32_t)npc;
              addtail(&linedblist,&ldebug->n);
              ++num_linedb;
            }

            pc = npc + atom_size(a,sec,npc);
          }
          fwalign(f,pc,4);
        }

        /* relocation hunks */
        reloc_hunk(f,HUNK_ABSRELOC32,&reloclist);
        reloc_hunk(f,HUNK_RELRELOC8,&reloclist);
        reloc_hunk(f,HUNK_RELRELOC16,&reloclist);
        reloc_hunk(f,HUNK_RELRELOC26,&reloclist);
        reloc_hunk(f,HUNK_RELRELOC32,&reloclist);
        reloc_hunk(f,HUNK_DREL16,&reloclist);

        /* external references and global definitions */
        exthunk = 0;
        ext_refs(f,&xreflist);
        if (sec->idx == 0)  /* absolute definitions into first hunk */
          ext_defs(f,sym,EXPRESSION,EXPORT,0,EXT_ABS);
        ext_defs(f,sym,LABSYM,EXPORT,sec->idx,EXT_DEF);
        exttrailer(f);

        if (!no_symbols) {
          /* symbol table */
          ext_defs(f,sym,LABSYM,0,sec->idx,EXT_SYMB);
          /* line-debug */
          linedebug_hunk(f,&linedblist,num_linedb);
        }
        fw32(f,HUNK_END,1);
      }
    }
  }
  if (!wrotesec) {
    /* there was no section at all - dummy section size 0 */
#if defined(VASM_CPU_PPC)
    fw32(f,HUNK_PPC_CODE,1);
#else
    fw32(f,HUNK_CODE,1);
#endif
    fw32(f,0,1);
    fw32(f,HUNK_END,1);
  }
}


static void write_exec(FILE *f,section *sec,symbol *sym)
{
  size_t sec_cnt;
  section *s;

  sec = check_symbols(sec,sym);
  sec_cnt = prepare_sections(sec);

  /* write header */
  fw32(f,HUNK_HEADER,1);
  fw32(f,0,1);

  if (sec_cnt) {
    fw32(f,sec_cnt,1);    /* number of sections - no overlay support */
    fw32(f,0,1);          /* first section index: 0 */
    fw32(f,sec_cnt-1,1);  /* last section index: sec_cnt - 1 */

    /* write section sizes and memory flags */
    for (s=sec; s; s=s->next) {
      if (!(s->flags & SEC_DELETED))
      	fw32(f,(scan_attr(s)&HUNKF_MEMTYPE)|((get_sec_size(s)+3)>>2),1);
    }

    /* section hunk loop */
    for (; sec; sec=sec->next) {
      if (!(sec->flags & SEC_DELETED)) {
      	uint32_t type;
        atom *a;
        struct list reloclist,linedblist;
        int num_linedb = 0;

        initlist(&reloclist);
        initlist(&linedblist);

        /* write hunk-type and size */
        if (!(type = scan_attr(sec) & ~HUNKF_MEMTYPE)) {
          output_error(3,sec->attr);  /* section attributes not suppported */
          type = HUNK_DATA;  /* default */
        }
        fw32(f,type,1);

        if (type != HUNK_BSS) {
          /* write contents */
          taddr pc,npc,size;
          int i;

          size = databss ? file_size(sec) : get_sec_size(sec);
          fw32(f,(size+3)>>2,1);
          for (a=sec->first,pc=0; a!=NULL&&pc<size; a=a->next) {
            int align = a->align;
            rlist *rl;

            npc = ((pc + align-1) / align) * align;
            for (i=pc; i<npc; i++)
              fw8(f,0);

            if (a->type == DATA) {
              fwdata(f,a->content.db->data,a->content.db->size);
              process_relocs(a->content.db->relocs,&reloclist,NULL,sec,npc);
            }
            else if (a->type == SPACE) {
              fwsblock(f,a->content.sb);
              process_relocs(a->content.sb->relocs,&reloclist,NULL,sec,npc);
            }
            else if (a->type == LINE) {
              struct hunkline *ldebug = mymalloc(sizeof(struct hunkline));

              ldebug->line = (uint32_t)a->content.srcline;
              ldebug->offset = (uint32_t)npc;
              addtail(&linedblist,&ldebug->n);
              ++num_linedb;
            }

            pc = npc + atom_size(a,sec,npc);
          }
          fwalign(f,pc,4);
        }
        else /* HUNK_BSS */
          fw32(f,(get_sec_size(sec)+3)>>2,1);

        reloc_hunk(f,HUNK_ABSRELOC32,&reloclist);

        if (!no_symbols) {
          /* symbol table */
          ext_defs(f,sym,LABSYM,0,sec->idx,EXT_SYMB);
          /* line-debug */
          linedebug_hunk(f,&linedblist,num_linedb);
        }
        fw32(f,HUNK_END,1);
      }
    }
  }
  else {
    /* no sections: create single code hunk with size 0 */
    fw32(f,1,1);
    fw32(f,1,0);
    fw32(f,1,0);
    fw32(f,1,0);
    fw32(f,HUNK_CODE,1);
    fw32(f,0,1);
    fw32(f,HUNK_END,1);
  }
}


static int object_args(char *p)
{
  return 0;
}


static int exec_args(char *p)
{
  if (!strcmp(p,"-databss")) {
    databss = 1;
    return 1;
  }
  return 0;
}


int init_output_hunk(char **cp,void (**wo)(FILE *,section *,symbol *),
                     int (**oa)(char *))
{
  *cp = copyright;
  *wo = write_object;
  *oa = object_args;
  return 1;
}


int init_output_hunkexe(char **cp,void (**wo)(FILE *,section *,symbol *),
                        int (**oa)(char *))
{
  *cp = copyright;
  *wo = write_exec;
  *oa = exec_args;
  return 1;
}

#else

int init_output_hunk(char **cp,void (**wo)(FILE *,section *,symbol *),
                     int (**oa)(char *))
{
  return 0;
}


int init_output_hunkexe(char **cp,void (**wo)(FILE *,section *,symbol *),
                        int (**oa)(char *))
{
  return 0;
}
#endif
