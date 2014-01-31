/* atom.c - atomic objects from source */
/* (c) in 2010-2012 by Volker Barthelmann and Frank Wille */

#include "vasm.h"


/* searches mnemonic list and tries to parse (via the cpu module)
   the operands according to the mnemonic requirements; returns an
   instruction or 0 */
instruction *new_inst(char *inst,int len,int op_cnt,char **op,int *op_len)
{
#if MAX_OPERANDS!=0
  operand ops[MAX_OPERANDS];
  int j,k,mnemo_opcnt,omitted,skipped;
#endif
  int i,inst_found=0;
  hashdata data;
  instruction *new;

  new = mymalloc(sizeof(*new));
#if HAVE_INSTRUCTION_EXTENSION
  init_instruction_ext(&new->ext);
#endif
#if MAX_OPERANDS!=0 && NEED_CLEARED_OPERANDS!=0
  /* reset operands to allow the cpu-backend to parse them only once */
  memset(ops,0,sizeof(ops));
#endif

  if (find_namelen_nc(mnemohash,inst,len,&data)) {
    i = data.idx;

    /* try all mnemonics with the same name until operands match */
    do {
      inst_found = 1;
      if (!MNEMONIC_VALID(i)) {
        i++;
        continue;  /* try next */
      }
#if MAX_OPERANDS!=0

#if ALLOW_EMPTY_OPS
      mnemo_opcnt = op_cnt<MAX_OPERANDS ? op_cnt : MAX_OPERANDS;
#else
      for (j=0; j<MAX_OPERANDS; j++)
        if (mnemonics[i].operand_type[j] == 0)
          break;
      mnemo_opcnt = j;	/* number of expected operands for this mnemonic */
#endif
      inst_found = 2;

      for (j=k=omitted=skipped=0; j<mnemo_opcnt; j++) {

        if (op_cnt+omitted < mnemo_opcnt &&
            OPERAND_OPTIONAL(&ops[j],mnemonics[i].operand_type[j])) {
          omitted++;
        }
        else {
          int rc;

          if (k >= op_cnt)  /* missing mandatory operands */
            break;

          rc = parse_operand(op[k],op_len[k],&ops[j],
                                 mnemonics[i].operand_type[j]);

          if (rc == PO_CORRUPT) {
            myfree(new);
            return 0;
          }
          if (rc == PO_NOMATCH)
              break;

          /* MATCH, move to next parsed operand */
          k++;
          if (rc == PO_SKIP) {	/* but skip next operand type from table */
            j++;
            skipped++;
          }
        }
      }

#if IGNORE_FIRST_EXTRA_OP
      if (mnemo_opcnt > 0)
#endif
      if (j<mnemo_opcnt || k<op_cnt) {
        /* No match. Try next mnemonic. */
        i++;
        continue;
      }

      /* Matched! Copy operands. */
      mnemo_opcnt -= skipped;
      for (j=0; j<mnemo_opcnt; j++) {
        new->op[j] = mymalloc(sizeof(operand));
        *new->op[j] = ops[j];
      }
      for(; j<MAX_OPERANDS; j++)
        new->op[j] = 0;
#endif /* MAX_OPERANDS!=0 */

      new->code = i;
      return new;
    }
    while (i<mnemonic_cnt && !strnicmp(mnemonics[i].name,inst,len)
           && mnemonics[i].name[len]==0);
  }

  switch (inst_found) {
    case 1:
      general_error(8);  /* instruction not supported by cpu */
      break;
    case 2:
      general_error(0);  /* illegal operand types */
      break;
    default:
      general_error(1,cnvstr(inst,len));  /* completely unknown mnemonic */
      break;
  }
  myfree(new);
  return 0;
}


dblock *new_dblock(void)
{
  dblock *new = mymalloc(sizeof(*new));

  new->size = 0;
  new->data = 0;
  new->relocs = 0;
  return new;
}


sblock *new_sblock(expr *space,int size,expr *fill)
{
  sblock *sb = mymalloc(sizeof(sblock));

  sb->space = 0;
  sb->space_exp = space;
  sb->size = size;
  if (!(sb->fill_exp = fill))
    memset(sb->fill,0,SB_MAXSIZE);
  sb->relocs = 0;
  return sb;
}


static taddr space_size(sblock *sb,section *sec,taddr pc)
{
  taddr space=0;

  if (eval_expr(sb->space_exp,&space,sec,pc) || !final_pass)
    sb->space = space;
  else
    general_error(30);  /* expression must be constant */

  if (final_pass && sb->fill_exp) {
    if (sb->size <= sizeof(taddr)) {
      /* space is filled with an expression which may also need relocations */
      symbol *base=NULL;
      taddr fill,i;

      if (!eval_expr(sb->fill_exp,&fill,sec,pc)) {
        if (find_base(sb->fill_exp,&base,sec,pc)==BASE_ILLEGAL)
          general_error(38);  /* illegal relocation */
      }
      copy_cpu_taddr(sb->fill,fill,sb->size);
      if (base && !sb->relocs) {
        /* generate relocations */
        for (i=0; i<space; i++)
          add_nreloc(&sb->relocs,base,fill,REL_ABS,
                     sb->size<<3,(i*sb->size)<<3);
      }
    }
    else
      general_error(30);  /* expression must be constant */
  }

  return space * (taddr)sb->size;
}


static taddr roffs_size(expr *offsexp,section *sec,taddr pc)
{
  taddr offs;

  eval_expr(offsexp,&offs,sec,pc);
  offs = sec->org + offs - pc;
  return offs>0 ? offs : 0;
}


/* adds an atom to the specified section; if sec==0, the current
   section is used */
void add_atom(section *sec,atom *a)
{
  taddr size;

  if (!sec) {
    sec = default_section();
    if (!sec) {
      general_error(3);
      return;
    }
  }

  a->src = cur_src;
  a->line = cur_src->line;

  if (sec->last) {
    atom *pa = sec->last;

    pa->next = a;
    /* make sure that a label on the same line gets the same alignment */
    if (pa->type==LABEL && pa->line==a->line &&
        (a->type==INSTRUCTION || a->type==DATADEF || a->type==SPACE))
      pa->align = a->align;
  }
  else
    sec->first = a;
  a->next = 0;
  sec->last = a;

  sec->pc = (sec->pc + a->align - 1) / a->align * a->align;
  size = atom_size(a,sec,sec->pc);
#if CHECK_ATOMSIZE
  a->lastsize = size;
#endif
  sec->pc += size;
  if (a->align > sec->align)
    sec->align = a->align;

  if (listena) {
    a->list = last_listing;
    if (last_listing) {
      if (!last_listing->atom)
        last_listing->atom = a;
    }
  }
  else
    a->list = 0;
}


taddr atom_size(atom *p,section *sec,taddr pc)
{
  switch(p->type) {
    case LABEL:
    case LINE:
    case OPTS:
    case PRINTTEXT:
    case PRINTEXPR:
    case RORG:
    case RORGEND:
    case ASSERT:
      return 0;
    case DATA:
      return p->content.db->size;
    case INSTRUCTION:
      return instruction_size(p->content.inst,sec,pc);
    case SPACE:
      return space_size(p->content.sb,sec,pc);
    case DATADEF:
      return (p->content.defb->bitsize+7)/8;
    case ROFFS:
      return roffs_size(p->content.roffs,sec,pc);
    default:
      ierror(0);
      break;
  }
  return 0;
}


static void print_instruction(FILE *f,instruction *p)
{
  int i;

  printf("inst %d(%s) ",p->code,mnemonics[p->code].name);
#if MAX_OPERANDS!=0
  for (i=0; i<MAX_OPERANDS; i++)
    printf("%p ",(void *)p->op[i]);
#endif
}


void print_atom(FILE *f,atom *p)
{
  size_t i;
  rlist *rl;

  switch (p->type) {
    case LABEL:
      fprintf(f,"symbol: ");
      print_symbol(f,p->content.label);
      break;
    case DATA:
      fprintf(f,"data(%lu): ",(unsigned long)p->content.db->size);
      for (i=0;i<p->content.db->size;i++)
        fprintf(f,"%02x ",(unsigned char)p->content.db->data[i]);
      for (rl=p->content.db->relocs; rl; rl=rl->next)
        print_reloc(f,rl->type,rl->reloc);
      break;
    case INSTRUCTION:
      print_instruction(f,p->content.inst);
      break;
    case SPACE:
      fprintf(f,"space(%lu,fill=",
              (unsigned long)(p->content.sb->space*p->content.sb->size));
      for (i=0; i<p->content.sb->size; i++)
        fprintf(f,"%02x%c",(unsigned char)p->content.sb->fill[i],
                (i==p->content.sb->size-1)?')':' ');
      for (rl=p->content.sb->relocs; rl; rl=rl->next)
        print_reloc(f,rl->type,rl->reloc);
      break;
    case DATADEF:
      fprintf(f,"datadef(%lu bits)",(unsigned long)p->content.defb->bitsize);
      break;
    case LINE:
      fprintf(f,"line: %d of %s",p->content.srcline,getdebugname());
      break;
#if HAVE_CPU_OPTS
    case OPTS:
      print_cpu_opts(f,p->content.opts);
      break;
#endif
    case PRINTTEXT:
      fprintf(f,"text: \"%s\"",p->content.ptext);
      break;
    case PRINTEXPR:
      fprintf(f,"expr: ");
      print_expr(f,p->content.pexpr);
      break;
    case ROFFS:
      fprintf(f,"roffs: offset ");
      print_expr(f,p->content.roffs);
      break;
    case RORG:
      fprintf(f,"rorg: relocate to 0x%llx",UNS_TADDR(*p->content.rorg));
      break;
    case RORGEND:
      fprintf(f,"rorg end");
      break;
    case ASSERT:
      fprintf(f,"assert: %s (message: %s)\n",p->content.assert->expstr,
              p->content.assert->msgstr?p->content.assert->msgstr:emptystr);
      break;
    default:
      ierror(0);
  }
}


atom *clone_atom(atom *a)
{
  atom *new = mymalloc(sizeof(atom));
  void *p;

  memcpy(new,a,sizeof(atom));

  switch (a->type) {
    /* INSTRUCTION and DATADEF have to be cloned as well, because they will
       be deallocated and transformed into DATA during assemble() */
    case INSTRUCTION:
      p = mymalloc(sizeof(instruction));
      memcpy(p,a->content.inst,sizeof(instruction));
      new->content.inst = p;
      break;
    case DATADEF:
      p = mymalloc(sizeof(defblock));
      memcpy(p,a->content.defb,sizeof(defblock));
      new->content.defb = p;
      break;
    default:
      break;
  }

  new->next = 0;
  new->src = NULL;
  new->line = 0;
  new->list = NULL;
  return new;
}


atom *new_inst_atom(instruction *p)
{
  atom *new = mymalloc(sizeof(*new));

  new->next = 0;
  new->type = INSTRUCTION;
  new->align = INST_ALIGN;
  new->content.inst = p;
  return new;
}


atom *new_data_atom(dblock *p,taddr align)
{
  atom *new = mymalloc(sizeof(*new));

  new->next = 0;
  new->type = DATA;
  new->align = align;
  new->content.db=p;
  return new;
}


atom *new_label_atom(symbol *p)
{
  atom *new = mymalloc(sizeof(*new));

  new->next = 0;
  new->type = LABEL;
  new->align = 1;
  new->content.label = p;
  return new;
}


atom *new_space_atom(expr *space,int size,expr *fill)
{
  atom *new = mymalloc(sizeof(*new));
  int i;

  if (size<1)
    ierror(0);  /* usually an error in syntax-module */
  new->next = 0;
  new->type = SPACE;
  new->align = 1;
  new->content.sb = new_sblock(space,size,fill);
  return new;
}  


atom *new_datadef_atom(taddr bitsize,operand *op)
{
  atom *new = mymalloc(sizeof(*new));
  new->next = 0;
  new->type = DATADEF;
  new->align = DATA_ALIGN(bitsize);
  new->content.defb = mymalloc(sizeof(*new->content.defb));
  new->content.defb->bitsize = bitsize;
  new->content.defb->op = op;
  return new;
}


atom *new_srcline_atom(int line)
{
  atom *new = mymalloc(sizeof(*new));

  new->next = 0;
  new->type = LINE;
  new->align = 1;
  new->content.srcline = line;
  return new;
}


atom *new_opts_atom(void *o)
{
  atom *new = mymalloc(sizeof(*new));

  new->next = 0;
  new->type = OPTS;
  new->align = 1;
  new->content.opts = o;
  return new;
}


atom *new_text_atom(char *txt)
{
  atom *new = mymalloc(sizeof(*new));

  new->next = 0;
  new->type = PRINTTEXT;
  new->align = 1;
  new->content.ptext = txt ? txt : "";
  return new;
}


atom *new_expr_atom(expr *x)
{
  atom *new = mymalloc(sizeof(*new));

  new->next = 0;
  new->type = PRINTEXPR;
  new->align = 1;
  new->content.pexpr = x;
  return new;
}


atom *new_roffs_atom(expr *offs)
{
  atom *new = mymalloc(sizeof(*new));

  new->next = 0;
  new->type = ROFFS;
  new->align = 1;
  new->content.roffs = offs;
  return new;
}


atom *new_rorg_atom(taddr raddr)
{
  atom *new = mymalloc(sizeof(*new));
  taddr *newrorg = mymalloc(sizeof(taddr));

  *newrorg = raddr;
  new->next = 0;
  new->type = RORG;
  new->align = 1;
  new->content.rorg = newrorg;
  return new;
}


atom *new_rorgend_atom(void)
{
  atom *new = mymalloc(sizeof(*new));

  new->next = 0;
  new->type = RORGEND;
  new->align = 1;
  return new;
}


atom *new_assert_atom(expr *aexp,char *exp,char *msg)
{
  atom *new = mymalloc(sizeof(*new));

  new->next = 0;
  new->type = ASSERT;
  new->align = 1;
  new->content.assert = mymalloc(sizeof(*new->content.assert));
  new->content.assert->assert_exp = aexp;
  new->content.assert->expstr = exp;
  new->content.assert->msgstr = msg;
  return new;
}
