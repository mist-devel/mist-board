/*
** cpu.c 650x/651x cpu-description file
** (c) in 2002,2006,2008-2012 by Frank Wille
*/

#include "vasm.h"

mnemonic mnemonics[] = {
#include "opcodes.h"
};

int mnemonic_cnt=sizeof(mnemonics)/sizeof(mnemonics[0]);

char *cpu_copyright="vasm 6502 cpu backend 0.6 (c) 2002,2006,2008-2012 Frank Wille";
char *cpuname = "6502";
int bitsperbyte = 8;
int bytespertaddr = 2;

static uint16_t cpu_type = M6502;
static int branchopt = 0;
static int modifier;  /* set by find_base() */


int ext_unary_eval(int type,taddr val,taddr *result,int cnst)
{
  switch (type) {
    case LOBYTE:
      *result = cnst ? (val & 0xff) : val;
      return 1;
    case HIBYTE:
      *result = cnst ? ((val >> 8) & 0xff) : val;
      return 1;
    default:
      break;
  }
  return 0;  /* unknown type */
}


int ext_find_base(symbol **base,expr *p,section *sec,taddr pc)
{
  /* addr/256 equals >addr, addr%256 and addr&255 equal <addr */
  if (p->type==DIV || p->type==MOD) {
    if (p->right->type==NUM && p->right->c.val==256)
      p->type = p->type == DIV ? HIBYTE : LOBYTE;
  }
  else if (p->type==BAND && p->right->type==NUM && p->right->c.val==255)
    p->type = LOBYTE;

  if (p->type==LOBYTE || p->type==HIBYTE) {
    modifier = p->type;
    return find_base(p->left,base,sec,pc);
  }
  modifier = 0;
  return BASE_ILLEGAL;
}


int parse_operand(char *p,int len,operand *op,int required)
{
  char *start = p;
  int indir = 0;

  p = skip(p);
  if (len>0 && required!=DATAOP && check_indir(p,start+len)) {
    indir = 1;
    p = skip(p+1);
  }

  switch (required) {
    case IMMED:
      if (*p++ != '#')
        return PO_NOMATCH;
      p = skip(p);
      break;
    case INDIR:
    case INDX:
    case INDY:
      if (!indir)
        return PO_NOMATCH;
      break;
    default:
      if (indir)
        return PO_NOMATCH;
      break;
  }

  if (required < ACCU)
    op->value = parse_expr(&p);
  else
    op->value = NULL;

  switch (required) {
    case INDX:
      if (*p++ == ',') {
        p = skip(p);
        if (toupper((unsigned char)*p++) != 'X')
          return PO_NOMATCH;
      }
      else
        return PO_NOMATCH;
      break;
    case ACCU:
      if (len != 0) {
        if (len!=1 || toupper((unsigned char)*p++) != 'A')
          return PO_NOMATCH;
      }
      break;
    case DUMX:
      if (toupper((unsigned char)*p++) != 'X')
        return PO_NOMATCH;
      break;
    case DUMY:
      if (toupper((unsigned char)*p++) != 'Y')
        return PO_NOMATCH;
      break;
  }

  if (required==INDIR || required==INDX || required==INDY) {
    p = skip(p);
    if (*p++ != ')') {
      cpu_error(2);  /* missing closing parenthesis */
      return PO_CORRUPT;
    }
  }

  p = skip(p);
  if (p-start < len)
    cpu_error(1);  /* trailing garbage in operand */
  op->type = required;
  return PO_MATCH;
}


char *parse_cpu_special(char *start)
{
  return start;
}


static instruction *copy_instruction(instruction *ip)
/* copy an instruction and its operands */
{
  static instruction newip;
  static operand newop;

  newip.code = ip->code;
  if (ip->op[0] != NULL) {
    newip.op[0] = &newop;
    *newip.op[0] = *ip->op[0];
  }
  else
    newip.op[0] = NULL;

  return &newip;
}


static void optimize_instruction(instruction *ip,section *sec,
                                 taddr pc,int final)
{
  mnemonic *mnemo = &mnemonics[ip->code];
  operand *op = ip->op[0];
  taddr val;

  if (op != NULL) {
    if (op->value != NULL) {
      if (eval_expr(op->value,&val,sec,pc)) {
        if ((op->type==ABS || op->type==ABSX || op->type==ABSY)
            && (val>=0 && val<=0xff) && mnemo->ext.zp_opcode!=0) {
          /* we can use a zero page addressing mode */
          op->type += ZPAGE-ABS;
        }
      }
      else {
        symbol *base;
        
        if (find_base(op->value,&base,sec,pc) == BASE_OK) {
          if (op->type==REL && base->type==LABSYM && base->sec==sec) {
            taddr bd = val - (pc + 2);
    
            if ((bd<-0x80 || bd>0x7f) && branchopt) {
              /* branch dest. out of range: use a B!cc/JMP combination */
              op->type = RELJMP;
            }
          }
        }
      }
    }
  }
}


static taddr get_inst_size(instruction *ip)
{
  if (ip->op[0] != NULL) {
    switch (ip->op[0]->type) {
      case ACCU:
      case IMPLIED:
        return 1;
      case REL:
      case INDX:
      case INDY:
      case IMMED:
      case ZPAGE:
      case ZPAGEX:
      case ZPAGEY:
        return 2;
      case ABS:
      case ABSX:
      case ABSY:
      case INDIR:
        return 3;
      case RELJMP:
        return 5;
      default:
        ierror(0);
        break;
    }
  }
  return 1;
}


taddr instruction_size(instruction *ip,section *sec,taddr pc)
{
  instruction *ipcopy;

  if (ip->op[0]!=NULL && ip->op[1]!=NULL) {
    /* combine DUMX/DUMY operands into real addressing modes first */
    if (ip->op[0]->type == ABS) {
      if (ip->op[1]->type == DUMX)
        ip->op[0]->type = ABSX;
      else if (ip->op[1]->type == DUMY)
        ip->op[0]->type = ABSY;
      else
        ierror(0);
    }
    else if (ip->op[0]->type == INDIR) {
      if (ip->op[1]->type == DUMY)
        ip->op[0]->type = INDY;
      else
        ierror(0);
    }
    else
      ierror(0);
    myfree(ip->op[1]);
    ip->op[1] = NULL;
  }

  ipcopy = copy_instruction(ip);
  optimize_instruction(ipcopy,sec,pc,0);
  return get_inst_size(ipcopy);
}


static void rangecheck(taddr val,int type)
{
  switch (type) {
    case INDX:
    case INDY:
    case ZPAGE:
    case ZPAGEX:
    case ZPAGEY:
    case IMMED:
      if (val<-0x80 || val>0xff)
        cpu_error(5);  /* operand doesn't fit into 8-bits */
      break;
    case REL:
      if (val<-0x80 || val>0x7f)
        cpu_error(6);  /* branch destination out of range */
      break;
  }
}


dblock *eval_instruction(instruction *ip,section *sec,taddr pc)
{
  dblock *db = new_dblock();
  unsigned char *d;
  int optype = 0;
  taddr val;

  optimize_instruction(ip,sec,pc,1);  /* really execute optimizations now */
  db->size = get_inst_size(ip);
  d = db->data = mymalloc(db->size);

  if (ip->op[0] != NULL) {
    operand *op = ip->op[0];
    symbol *base;

    optype = (int)op->type;
    if (op->value != NULL) {
      if (!eval_expr(op->value,&val,sec,pc)) {
        modifier = 0;
        if (find_base(op->value,&base,sec,pc) == BASE_OK) {
          if (optype==REL && base->type==LABSYM && base->sec==sec) {
            /* relative branch requires no relocation */
            val = val - (pc + 2);
          }
          else {
            int type=REL_ABS,offs=8,size;
            rlist *rl;

            switch (optype) {
              case ABS:
              case ABSX:
              case ABSY:
              case INDIR:
                size = 16;
                break;
              case INDX:
              case INDY:
              case ZPAGE:
              case ZPAGEX:
              case ZPAGEY:
              case IMMED:
                size = 8;
                break;
              case RELJMP:
                size = 16;
                offs = 24;
                break;
              case REL:
                type = REL_PC;
                size = 8;
                break;
              default:
                ierror(0);
                break;
            }
            rl = add_nreloc(&db->relocs,base,val,type,size,offs);
            switch (modifier) {
              case LOBYTE:
                ((nreloc *)rl->reloc)->mask = 0xff;
                val = val & 0xff;
                break;
              case HIBYTE:
                ((nreloc *)rl->reloc)->mask = 0xff00;
                val = (val >> 8) & 0xff;
                break;
            }
          }
        }
        else
          general_error(38);  /* illegal relocation */
      }
      rangecheck(val,op->type);
    }
  }

  /* write code */
  if (optype==ZPAGE || optype==ZPAGEX || optype==ZPAGEY)
    *d++ = mnemonics[ip->code].ext.zp_opcode;
  else if (optype==RELJMP)
    *d++ = mnemonics[ip->code].ext.opcode ^ 0x20;  /* B!cc branch */
  else
    *d++ = mnemonics[ip->code].ext.opcode;

  switch (optype) {
    case ABSX:
    case ABSY:
      if (*(d-1) == 0)  /* STX/STY allow only ZeroPage addressing mode */
        cpu_error(5);   /* operand doesn't fit into 8-bits */
    case ABS:
    case INDIR:
      *d++ = val & 0xff;
      *d = (val>>8) & 0xff;
      break;
    case INDX:
    case INDY:
    case ZPAGE:
    case ZPAGEX:
    case ZPAGEY:
    case IMMED:
    case REL:
      *d = val & 0xff;
      break;
    case RELJMP:
      *d++ = 3;     /* B!cc *+3 */
      *d++ = 0x4c;  /* JMP */
      *d++ = val & 0xff;
      *d = (val>>8) & 0xff;
      break;
  }

  return db;
}


dblock *eval_data(operand *op,taddr bitsize,section *sec,taddr pc)
{
  dblock *db = new_dblock();
  taddr val;

  if (bitsize!=8 && bitsize!=16)
    cpu_error(3,bitsize);  /* data size not supported */

  db->size = bitsize >> 3;
  db->data = mymalloc(db->size);
  if (!eval_expr(op->value,&val,sec,pc)) {
    symbol *base;
    int btype;
    rlist *rl;
    
    modifier = 0;
    btype = find_base(op->value,&base,sec,pc);
    if (btype==BASE_OK || (btype==BASE_PCREL && modifier==0)) {
      rl = add_nreloc(&db->relocs,base,val,
                      btype==BASE_PCREL?REL_PC:REL_ABS,bitsize,0);
      switch (modifier) {
        case LOBYTE:
          ((nreloc *)rl->reloc)->mask = 0xff;
          val = val & 0xff;
          break;
        case HIBYTE:
          ((nreloc *)rl->reloc)->mask = 0xff00;
          val = (val >> 8) & 0xff;
          break;
      }
    }
    else
      general_error(38);  /* illegal relocation */
  }
  if (bitsize < 16) {
    if (val<-0x80 || val>0xff)
      cpu_error(5);  /* operand doesn't fit into 8-bits */
  }

  switch (db->size) {
    case 2:
      db->data[1] = (val>>8) & 0xff;
    case 1:
      db->data[0] = val & 0xff;
      break;
    default:
      ierror(0);
      break;
  }

  return db;
}


operand *new_operand()
{
  operand *new = mymalloc(sizeof(*new));
  new->type = -1;
  return new;
}


int cpu_available(int idx)
{
  return (mnemonics[idx].ext.available & cpu_type) != 0;
}


int init_cpu()
{
  return 1;
}


int cpu_args(char *p)
{
  if (!strcmp(p,"-opt-branch"))
    branchopt = 1;
  else if (!strcmp(p,"-illegal"))
    cpu_type |= ILL;
  else if (!strcmp(p,"-dtv"))
    cpu_type |= DTV;
  else
    return 0;

  return 1;
}
