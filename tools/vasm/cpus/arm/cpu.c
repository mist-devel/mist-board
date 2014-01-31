/*
** cpu.c ARM cpu-description file
** (c) in 2004,2006,2010,2011 by Frank Wille
*/

#include "vasm.h"

mnemonic mnemonics[] = {
#include "opcodes.h"
};
int mnemonic_cnt = sizeof(mnemonics)/sizeof(mnemonics[0]);

char *cpu_copyright = "vasm ARM cpu backend 0.2f (c) 2004,2006,2010,2011 Frank Wille";
char *cpuname = "ARM";
int bitsperbyte = 8;
int bytespertaddr = 4;

uint32_t cpu_type = AAANY;
int arm_be_mode = 0;  /* Little-endian is default */
int thumb_mode = 0;   /* 1: Thumb instruction set (16 bit) is active */

/* options */
static unsigned char opt_ldrpc = 0; /* LDR r,sym -> ADD / LDR */
static unsigned char opt_adr = 0;   /* ADR r,sym -> ADRL (ADD/ADD|SUB/SUB) */

/* constant data */
static const char *condition_codes = "eqnecsccmiplvsvchilsgeltgtlealnvhsloul";

static const char *addrmode_strings[] = {
  "da","ia","db","ib",
  "fa","fd","ea","ed",
  "bt","tb","sb","sh","t","b","h","s","l",NULL,"<none>"
};
enum {
  AM_DA=0,AM_IA,AM_DB,AM_IB,AM_FA,AM_FD,AM_EA,AM_ED,
  AM_BT,AM_TB,AM_SB,AM_SH,AM_T,AM_B,AM_H,AM_S,AM_L,AM_NULL,AM_NONE
};

#define NUM_SHIFTTYPES 6
static const char *shift_strings[NUM_SHIFTTYPES] = {
  "LSL","LSR","ASR","ROR","RRX","ASL"
};

static int OC_SWP,OC_NOP;
static int elfoutput = 0;       /* output will be an ELF object file */
static hashtable *regsymhash;   /* hash-table for ARM register symbols */

static section *last_section = 0;
static int last_data_type = -1; /* for mapping symbol generation */
#define TYPE_ARM 0
#define TYPE_THUMB 1
#define TYPE_DATA 2

#define THB_PREFETCH 4          /* prefetch-correction for Thumb-branches */
#define ARM_PREFETCH 8          /* prefetch-correction for ARM-branches */



operand *new_operand(void)
{
  return mycalloc(sizeof(operand));
}


int cpu_available(int idx)
{
  return (mnemonics[idx].ext.available & cpu_type) != 0;
}


static int addregsym(char *sym,int val)
/* add a new register symbol, return 0 if already exists */
{
  hashdata data;
  regsym *new;

  if (find_name_nc(regsymhash,sym,&data))
    return 0;

  data.ptr = new = mymalloc(sizeof(regsym));
  new->name = mymalloc(strlen(sym)+1);
  strcpy(new->name,sym);
  new->value = val;
  add_hashentry(regsymhash,new->name,data);
  return 1;
}


char *parse_cpu_special(char *start)
/* parse cpu-specific directives; return pointer to end of
   cpu-specific text */
{
  char *name=start,*s=start;

  if (ISIDSTART(*s)) {
    s++;
    while (ISIDCHAR(*s))
      s++;
    if (s-name==6 && !strncmp(name,".thumb",6)) {
      thumb_mode = 1;
      return s;
    }
    else if (s-name==4 && !strncmp(name,".arm",4)) {
      thumb_mode = 0;
      return s;
    }
  }
  return start;
}


char *parse_instruction(char *s,int *inst_len,char **ext,int *ext_len,
                        int *ext_cnt)
/* parse instruction and save extension locations */
{
  char *inst = s;
  int cnt = *ext_cnt;

  while (*s && !isspace((unsigned char)*s))
    s++;

  if (thumb_mode) {  /* no qualifiers in THUMB code */
    *inst_len = s - inst;
  }

  else {  /* ARM mode - we might have up to 2 different qualifiers */
    int len = s - inst;

    if (len > 2) {
      if (*inst=='b' && strncmp(inst,"bic",3) && (len==3 || len==4)) {
        *inst_len = len - 2;
      }
      else if ((*inst=='u' || *inst=='s') && *(inst+1)=='m' && len>=5) {
        *inst_len = 5;
      }
      else
        *inst_len = 3;
      len -= *inst_len;

      if (len > 0) {
        char *p = inst + *inst_len;

        if (len >= 2) {
          const char *cc = condition_codes;

          while (*cc) {
            if (*p==*cc && *(p+1)==*(cc+1))
              break;
            cc += 2;
          }
          if (*cc) {  /* matched against a condition code */
            ext[cnt] = p;
            ext_len[cnt++] = 2;
            p += 2;
            len -= 2;
          }
        }
        if (len >= 1) {
          const char **am = addrmode_strings;

          do {
            if (len==strlen(*am) && !strncmp(*am,p,len))
              break;
            am++;
          }
          while (*am);
          if (*am!=NULL || (len==1 && *p=='s')) {
            ext[cnt] = p;
            ext_len[cnt++] = len;
          }
        }
      }
      else if (len < 0)
        ierror(0);
    }
    else
      *inst_len = len;

    *ext_cnt = cnt;
  }

  return s;
}


int set_default_qualifiers(char **q,int *q_len)
/* fill in pointers to default qualifiers, return number of qualifiers */
{
  return 0;
}


static int parse_reg(char **pp)
/* parse register, return -1 on error */
{
  hashdata data;
  char *p = *pp;
  char *name = p;

  if (ISIDSTART(*p)) {
    p++;
    while (ISIDCHAR(*p))
      p++;
    if (find_namelen_nc(regsymhash,name,p-name,&data)) {
      regsym *sym = data.ptr;

      *pp = p;
      return sym->value;
    }
  }
  return -1;  /* no valid register found */
}


static int parse_reglist(char **pp)
/* parse register-list, return -1 on error */
{
  hashdata data;
  int r=0,list=0,lastreg=-1;
  char *p = *pp;
  char *name;
  regsym *sym;

  if (*p++ == '{') {
    p = skip(p);

    do {
      if (ISIDSTART(*p)) {
        name = p++;
        while (ISIDCHAR(*p))
          p++;
        if (find_namelen_nc(regsymhash,name,p-name,&data)) {
          sym = data.ptr;
          r = sym->value;
          if (lastreg >= 0) {  /* range-mode? */
            if (lastreg < r) {
              r = lastreg;
              lastreg = sym->value;
            }
            for (; r<=lastreg; list |= 1<<r++);
          }
          else
            list |= 1<<r;
          p = skip(p);
        }
        else
          return -1;
      }
      if (*p == ',') {
        lastreg = -1;
        p = skip(p+1);
      }
      else if (*p == '-') {
        lastreg = r;
        p = skip(p+1);
      }
    }
    while (*p!='\0' && *p!='}');

    if (*p) {
      *pp = ++p;
      return list;
    }
  }

  return -1;
}


int parse_operand(char *p,int len,operand *op,int optype)
/* Parses operands, reads expressions and assigns relocation types */
{
  char *start = p;

  op->type = optype;
  op->flags = 0;
  op->value = NULL;
  p = skip(p);

  if (thumb_mode) {
    if (ARMOPER(optype)) {   /* standard ARM instruction */
      return PO_NOMATCH;
    }

    else if (THREGOPER(optype)) {
      /* parse a register */
      int r;

      if (optype==TR5IN || optype==TPCPR || optype==TSPPR) {
        if (*p++ != '[')
          return PO_NOMATCH;
        p = skip(p);
      }

      if ((r = parse_reg(&p)) < 0)
        return PO_NOMATCH;
      op->value = number_expr((taddr)r);

      if ((optype==TPCRG || optype==TPCPR) && r!=15) {
        return PO_NOMATCH;
      }
      else if ((optype==TSPRG || optype==TSPPR) && r!=13) {
        return PO_NOMATCH;
      }
      else if (optype==THR02 || optype==THR05) {
        if (r<8 || r>15)
          return PO_NOMATCH;
      }
      else {
        if (r<0 || r>7)
          return PO_NOMATCH;
      }
      if (optype == TR8IN) {
        p = skip(p);
        if (*p++ != ']')
          return PO_NOMATCH;
      }
      else if (optype == TR10W) {
        if (*p++ != '!')
          return PO_NOMATCH;
      }
    }

    else if (THREGLIST(optype)) {
      taddr list = parse_reglist(&p);

      if (optype == TRLST) {
        if (list & ~0xff)
          return PO_NOMATCH;  /* only r0-r7 allowed */
      }
      else {
        if ((list&0x8000) && optype==TRLPC) {
          list = list&~0x8000 | 0x100;
        }
        else if ((list&0x4000) && optype==TRLLR) {
          list = list&~0x4000 | 0x100;
        }
        if (list & ~0x1ff)
          return PO_NOMATCH;  /* only r0-r7 / pc / lr allowed */
      }
      op->value = number_expr(list);
    }

    else {  /* just parse an expression */
      char *q;

      if (THIMMOPER(optype)) {
        if (*p++ != '#')
          return PO_NOMATCH;
        p = skip(p);
      }

      q = p;
      if (*q=='+' || *q=='-')
        q = skip(q+1);
      if (!ISIDSTART(*q) && !isdigit((unsigned char)*q))
        return PO_NOMATCH;
      op->value = parse_expr(&p);

      if (THIMMINDIR(optype)) {
        p = skip(p);
        if (*p++ != ']')
          return PO_NOMATCH;
      }
    }
  }

  else {  /* ARM mode */
    if (THUMBOPER(optype)) {   /* Thumb instruction */
      return PO_NOMATCH;
    }

    else if (STDOPER(optype)) {
      /* parse an expression (register, label, imm.) and assign to 'value' */
      if (IMMEDOPER(optype)) {
        if (*p++ != '#')
          return PO_NOMATCH;
        p = skip(p);
      }
      else if (optype==R19PR || optype==R19PO) {
        if (*p++ != '[')
          return PO_NOMATCH;
        p = skip(p);
      }

      if (UPDOWNOPER(optype)) {
        if (*p == '-') {
          p = skip(p+1);
        }
        else {
          if (*p == '+')
            p = skip(p+1);
          op->flags |= OFL_UP;
        }
      }

      if (REGOPER(optype)) {
        int r = parse_reg(&p);

        if (r >= 0)
          op->value = number_expr((taddr)r);
        else
          return PO_NOMATCH;
      }
      else {  /* an expression */
        if (ISIDSTART(*p) || isdigit((unsigned char)*p) ||
            (!UPDOWNOPER(optype) && (*p=='-' || *p=='+')))
          op->value = parse_expr(&p);
        else
          return PO_NOMATCH;
      }

      if (optype==R19PO || optype==R3UD1 || optype==IMUD1 || optype==IMCP1) {
        p = skip(p);
        if (*p++ != ']')
          return PO_NOMATCH;
      }
      if (optype==R19WB || optype==R3UD1 || optype==IMUD1 || optype==IMCP1) {
        if (*p == '!') {
          p++;
          op->flags |= OFL_WBACK;
        }
      }
    }

    else if (SHIFTOPER(optype)) {
      char *name = p;
      int i;

      p = skip_identifier(p);
      if (p == NULL)
        return PO_NOMATCH;
      for (i=0; i<NUM_SHIFTTYPES; i++) {
        if (!strnicmp(shift_strings[i],name,p-name))
          break;
      }
      if (i >= NUM_SHIFTTYPES)
        return PO_NOMATCH;
      if (i == 4) {
        /* RRX is ROR with immediate value 0 */
        op->flags |= OFL_IMMEDSHIFT;
        op->value = number_expr(0);
        i = 3;  /* ROR */
      }
      else {
        /* parse immediate or register for LSL, LSR, ASR, ROR */
        p = skip(p);
        if (i == 5)
          i = 0;  /* ASL -> LSL */
        if (*p == '#') {
          p++;
          op->flags |= OFL_IMMEDSHIFT;
          op->value = parse_expr(&p);
        }
        else if (optype == SHIFT) {
          int r = parse_reg(&p);

          if (r >= 0)
            op->value = number_expr((taddr)r);
          else
            return PO_NOMATCH;
        }
        else
          return PO_NOMATCH;  /* no shift-count in register allowed */
      }
      op->flags |= i & OFL_SHIFTOP;

      if (optype == SHIM1) {
        /* check for pre-indexed with optional write-back */
        p = skip(p);
        if (*p++ != ']')
          return PO_NOMATCH;
        if (*p == '!') {
          p++;
          op->flags |= OFL_WBACK;
        }
      }
    }

    else if (optype == CSPSR) {
      char *name = p;

      p = skip_identifier(p);
      if (p == NULL)
        return PO_NOMATCH;
      if (!strnicmp(name,"CPSR",p-name))
        op->flags &= ~OFL_SPSR;
      else if (!strnicmp(name,"SPSR",p-name))
        op->flags |= OFL_SPSR;
      else
        return PO_NOMATCH;
      op->value = number_expr(0xf);   /* all fields f,s,x,c */
    }

    else if (optype == PSR_F) {
      char *name = p;
      taddr fields = 0xf;

      p = skip_identifier(p);
      if (p==NULL || (p-name)<4)
        return PO_NOMATCH;
      if (!strnicmp(name,"CPSR",4))
        op->flags &= ~OFL_SPSR;
      else if (!strnicmp(name,"SPSR",4))
        op->flags |= OFL_SPSR;
      else
        return PO_NOMATCH;

      if ((p-name)>5 && *(name+4)=='_') {
        fields = 0;
        name += 5;
        while (name < p) {
          switch (tolower((unsigned char)*name++)) {
            case 'f': fields |= 1; break;
            case 's': fields |= 2; break;
            case 'x': fields |= 4; break;
            case 'c': fields |= 8; break;
            default: return PO_NOMATCH;
          }
        }
      }
      else if ((p-name) > 4)
        return PO_NOMATCH;
      op->value = number_expr(fields);
    }

    else if (optype == RLIST) {
      taddr list = parse_reglist(&p);

      if (list >= 0) {
        op->value = number_expr(list);
        if (*p == '^') {
          p++;
          op->flags |= OFL_FORCE;  /* set "load PSR / force user mode" flag */
        }
      }
      else
        return PO_NOMATCH;
    }

    else
      ierror(0);
  }

  return (skip(p)-start < len) ? PO_NOMATCH : PO_MATCH;
}


static void create_mapping_symbol(int type,section *sec,taddr pc)
/* create mapping symbol ($a, $t, $d) as required by ARM ELF ABI */
{
  static char names[3][4] = { "$a","$t","$d" };
  static int types[3] = { TYPE_FUNCTION,TYPE_FUNCTION,TYPE_OBJECT };
  symbol *sym;

  if (type<TYPE_ARM || type>TYPE_DATA)
    ierror(0);
  if (elfoutput) {
    sym = mymalloc(sizeof(symbol));
    sym->type = LABSYM;
    sym->flags = types[type];
    sym->name = names[type];
    sym->sec = sec;
    sym->pc = pc;
    sym->expr = 0;
    sym->size = 0;
    sym->align = 0;
    add_symbol(sym);
  }
  last_data_type = type;
}


taddr eval_thumb_operands(instruction *ip,section *sec,taddr pc,
                          uint16_t *insn,dblock *db)
/* evaluate expressions and try to optimize THUMB instruction,
   return size of instruction */
{
  operand op;
  mnemonic *mnemo = &mnemonics[ip->code];
  int opcnt = 0;
  taddr isize = 2;

  if (insn) {
    if (pc & 1)
      cpu_error(27);  /* instruction at unaligned address */

    if (ip->op[0] == NULL) {
      /* handle inst. without operands, which don't have Thumb entries */
      if (ip->code == OC_NOP)
        *insn = 0x46c0;  /* nop => mov r0,r0 */

      return 2;
    }
    else
      *insn = (uint16_t)mnemo->ext.opcode;
  }

  for (opcnt=0; ip->op[opcnt]!=NULL && opcnt<MAX_OPERANDS; opcnt++) {
    taddr val;
    symbol *base = NULL;
    int btype;

    op = *(ip->op[opcnt]);
    if (!eval_expr(op.value,&val,sec,pc))
      btype = find_base(op.value,&base,sec,pc);

    /* do optimizations first */

    if (op.type==TPCLW || THBRANCH(op.type)) {
      /* PC-relative offsets (take prefetch into account: PC+4) */
      if (base!=NULL && btype==BASE_OK) {
        if (base->type==LABSYM && base->sec==sec) {
          /* no relocation required, can be resolved immediately */
          if (op.type == TPCLW) {
            /* bit 1 of PC is forced to 0 */
            val -= (pc&~2) + 4;
          }
          else
            val -= pc + 4;

          if (op.type == TBR08) {
            if (val<-0x100 || val>0xfe) {
              /* optimize to: B<!cc> .+4 ; B label */
              if (insn) {
                *insn++ ^= 0x100;   /* negate branch-condition */
                *insn = 0xe000;     /* B unconditional to label */
              }
              if (val < 0)
                val -= 2;  /* backward-branches are 2 bytes longer */
              isize += 2;
              op.type = TBR11;
            }
          }
          else if (op.type == TBRHL) {
            /* BL always consists of two instructions */
            isize += 2;
          }
          else if (op.type == TPCLW) {
            /* @@@ optimization makes any sense? */
            op.type = TUIMA;
            base = NULL;  /* no more checks */
          }
        }
        else {
          /* symbol is in a different section or externally declared */
          if (op.type == TBRHL) {
            val -= THB_PREFETCH;
            if (db) {
              add_nreloc_masked(&db->relocs,base,val,REL_PC,11,16+5,0xffe);
              add_nreloc_masked(&db->relocs,base,val,REL_PC,11,5,0x7ff000);
            }
          }
          else if (op.type == TPCLW) {
            /* val -= THB_PREFETCH;  @@@ only positive offsets allowed! */
            op.type = TUIMA;
            if (db)
              add_nreloc_masked(&db->relocs,base,val,REL_PC,8,8,0x3fc);
            base = NULL;  /* no more checks */
          }
          else if (insn)
            cpu_error(22); /* operation not allowed on external symbols */
        }
      }
      else if (insn)
        cpu_error(2);  /* label from current section required */
    }

    /* optimizations should be finished at this stage -
       inserts operands into the opcode now: */

    if (insn) {

      if (THREGOPER(op.type)) {
        /* insert register operand, check was already done in parse_operand */
        if (!THPCORSP(op.type)) {
          switch (op.type) {
            case TRG02:
            case THR02:
              *insn |= val&7;
              break;
            case TRG05:
            case THR05:
            case TR5IN:
              *insn |= (val&7) << 3;
              break;
            case TRG08:
            case TR8IN:
              *insn |= (val&7) << 6;
              break;
            case TRG10:
            case TR10W:
              *insn |= (val&7) << 8;
              break;
            default:
              ierror(0);
              break;
          }
        }
      }

      else if (THREGLIST(op.type)) {
        /* register list was already checked in parse_operand - just insert */
        *insn |= val;
      }

      else if (THIMMOPER(op.type) || op.type==TSWI8) {
        /* immediate operand */
        switch (op.type) {
          case TUIM3:
            if (val>=0 && val<=7) {
              *insn |= val<<6;
            }
            else
              cpu_error(25,3,(long)val);  /* immediate offset out of range */
            break;
          case TUIM5:
          case TUI5I:
            if (val>=0 && val<=0x1f) {
              *insn |= val<<6;
            }
            else
              cpu_error(25,5,(long)val);  /* immediate offset out of range */
            break;
          case TUI6I:
            if (val>=0 && val<=0x3e) {
              if ((val & 1) == 0)
                *insn |= (val&0x3e)<<5;
              else
                cpu_error(26,2);  /* offset has to be a multiple of 2 */
            }
            else
              cpu_error(25,6,(long)val);  /* immediate offset out of range */
            break;
          case TUI7I:
            if (val>=0 && val<=0x7c) {
              if ((val & 3) == 0)
                *insn |= (val&0x7c)<<4;
              else
                cpu_error(26,4);  /* offset has to be a multiple of 4 */
            }
            else
              cpu_error(25,7,(long)val);  /* immediate offset out of range */
            break;
          case TUIM8:
          case TSWI8:
            if (val>=0 && val<=0xff) {
              *insn |= val;
            }
            else
              cpu_error(25,8,(long)val);  /* immediate offset out of range */
            break;
          case TSIM9:
            if (val>=-0x1fc && val<=0x1fc) {
              if ((val & 3) == 0) {
                if (val < 0)
                  val = 0x80 - (val>>2);
                *insn |= val;
              }
              else
                cpu_error(26,4);  /* offset has to be a multiple of 4 */
            }
            else
              cpu_error(20,9,(long)val);  /* immediate offset out of range */
            break;
          case TUIMA:
          case TUIAI:
            if (val>=0 && val<=0x3fc) {
              if ((val & 3) == 0)
                *insn |= val>>2;
              else
                cpu_error(26,4);  /* offset has to be a multiple of 4 */
            }
            else
              cpu_error(25,10,(long)val);  /* immediate offset out of range */
            break;
        }

        if (base!=NULL && db!=NULL) {
          if (btype == BASE_OK) {
            if (op.type==TUIM5 || op.type==TUI5I)
              add_nreloc_masked(&db->relocs,base,val,REL_ABS,5,5,0x1f);
            else if (op.type == TSWI8)
              add_nreloc_masked(&db->relocs,base,val,REL_ABS,8,8,0xff);
            else
              cpu_error(6);  /* constant integer expression required */
          }
          else
            general_error(38);  /* illegal relocation */
        }
      }

      else if (op.type == TBR08) {
        /* only write offset, relocs and optimizations are handled above */
        if (val & 1)
          cpu_error(8,(long)val);  /* branch to unaligned address */
        *insn |= (val>>1) & 0xff;
      }

      else if (op.type == TBR11) {
        /* only write offset, relocs and optimizations are handled above */
        if (val<-0x800 || val>0x7fe)
          cpu_error(3,(long)val);  /* branch offset is out of range */
        if (val & 1)
          cpu_error(8,(long)val);  /* branch to unaligned address */
        *insn |= (val>>1) & 0x7ff;
      }

      else if (op.type == TBRHL) {
        /* split 23-bit offset over two instructions, ignoring bit 0 */
        if (val<-0x400000 || val>0x3ffffe)
          cpu_error(3,(long)val);  /* branch offset is out of range */
        if (val & 1)
          cpu_error(8,(long)val);  /* branch to unaligned address */
        *insn++ |= (val>>12) & 0x7ff;
        *insn = 0xf800 | ((val>>1) & 0x7ff);
      }

      else
        ierror(0);
    }
  }

  return isize;
}


#define ROTFAIL (0xffffff)

static uint32_t rotated_immediate(uint32_t val)
/* check if a 32-bit value can be represented as 8-bit-rotated,
   return ROTFAIL when impossible */
{
  uint32_t i,a;

  for (i=0; i<32; i+=2) {
    if ((a = val<<i | val>>(32-i)) <= 0xff)
      return (i<<7) | a;
  }
  return ROTFAIL;
}


static int negated_rot_immediate(uint32_t val,mnemonic *mnemo,
                                 uint32_t *insn)
/* check if negating the ALU-operation makes a valid 8-bit-rotated value,
   insert it into the current instruction, when successful */
{
  uint32_t neg = rotated_immediate(-val);
  uint32_t inv = rotated_immediate(~val);
  uint32_t op = (mnemo->ext.opcode & 0x01e00000) >> 21;

  switch (op) {
    /* AND <-> BIC */
    case 0: op=14; val=inv; break;
    case 14: op=0; val=inv; break;
    /* ADD <-> SUB */
    case 2: op=4; val=neg; break;
    case 4: op=2; val=neg; break;
    /* ADC <-> SBC */
    case 5: op=6; val=inv; break;
    case 6: op=5; val=inv; break;
    /* CMP <-> CMN */
    case 10: op=11; val=neg; break;
    case 11: op=10; val=neg; break;
    /* MOV <-> MVN */
    case 13: op=15; val=inv; break;
    case 15: op=13; val=inv; break;

    default: return 0;
  }

  if (val == ROTFAIL)
    return 0;

  if (insn) {
    *insn &= ~0x01e00000;
    *insn |= (op<<21) | val;
  }
  return 1;
}


static uint32_t double_rot_immediate(uint32_t val,uint32_t *hi)
/* check if a 32-bit value can be represented by combining two
   8-bit rotated values, return ROTFAIL otherwise */
{
  uint32_t i,a;

  for (i=0; i<32; i+=2) {
    if (((a = val<<i | val>>(32-i)) & 0xff) != 0) {
      if (a & 0xff00) {
        if (a & 0xffff0000)
          continue;
        *hi = ((i+24)<<7) | (a>>8);
      }
      else if (a & 0xff0000) {
        if (a & 0xff000000)
          continue;
        *hi = ((i+16)<<7) | (a>>16);
      }
      else if (a & 0xff000000)
        *hi = ((i+8)<<7) | (a>>24);
      else
        ierror(0);

      return (i<<7) | (a&0xff);
    }
  }

  return ROTFAIL;
}


static uint32_t calc_2nd_rot_opcode(uint32_t op)
/* calculates ALU operation for second instruction */
{
  if (op == 13)
    op = 12;  /* MOV + ORR */
  else if (op == 15)
    op = 1;   /* MVN + EOR */
  /* ADD and SUB stay the same */

  return op << 21;
}


static int negated_double_rot_immediate(uint32_t val,uint32_t *insn)
/* check if negating the ALU-operation and/or a second ADD/SUB operation
   makes a valid 8-bit-rotated value, insert it into the current
   instruction, when successful */
{
  uint32_t op = (*insn & 0x01e00000) >> 21;

  if ((op==2 || op==4 || op==13 || op==15) && insn!=NULL) {
    /* combined instructions only possible for ADD/SUB/MOV/MVN */
    uint32_t lo,hi;

    *(insn+1) = *insn & ~0x01ef0000;
    *(insn+1) |= (*insn&0xf000) << 4;  /* Rn = Rd of first instruction */

    if ((lo = double_rot_immediate(val,&hi)) != ROTFAIL) {
      *insn++ |= hi;
      *insn |= calc_2nd_rot_opcode(op) | lo;
      return 1;
    }

    /* @@@ try negated or inverted values */
  }

  return 0;
}


static uint32_t get_condcode(instruction *ip)
/* returns condition (bit 31-28) from instruction's qualifiers */
{
  const char *cc = condition_codes;
  char *q;

  if (q = ip->qualifiers[0]) {
    uint32_t code = 0;

    while (*cc) {
      if (*q==*cc && *(q+1)==*(cc+1) && *(q+2)=='\0')
        break;
      cc += 2;
      code++;
    }
    if (*cc) {  /* condition code in qualifier valid */
      if (code == 16)  /* hs -> cs */
        code = 2;
      else if (code==17 || code==18)  /* lo/ul -> cc */
        code = 3;

      return code<<28;
    }
  }

  return 0xe0000000;  /* AL - always */
}


static int get_addrmode(instruction *ip)
/* return addressing mode from instruction's qualifiers */
{
  char *q;

  if ((q = ip->qualifiers[1]) == NULL)
    q = ip->qualifiers[0];

  if (q) {
    const char **am = addrmode_strings;
    int mode = AM_DA;

    do {
      if (!strcmp(*am,q))
        break;
      am++;
      mode++;
    }
    while (*am);

    if (*am != NULL)
      return mode;
  }

  return AM_NONE;
}


taddr eval_arm_operands(instruction *ip,section *sec,taddr pc,
                        uint32_t *insn,dblock *db)
/* evaluate expressions and try to optimize ARM instruction,
   return size of instruction */
{
  operand op;
  mnemonic *mnemo = &mnemonics[ip->code];
  int am = get_addrmode(ip);
  int aa4ldst = 0;
  int opcnt = 0;
  taddr isize = 4;
  taddr chkreg = -1;

  if (insn) {
    if (pc & 3)
      cpu_error(27);  /* instruction at unaligned address */

    *insn = mnemo->ext.opcode | get_condcode(ip);

    if (mnemo->ext.flags & SETCC) {
      if (am == AM_S)
        *insn |= 0x00100000;  /* set-condition-codes flag */
    }

    if (!strcmp(mnemo->name,"ldr") || !strcmp(mnemo->name,"str")) {
      if (am==AM_T || am==AM_B || am==AM_BT || am==AM_TB) { /* std. ldr/str */
        if (am != AM_B) {
          *insn |= 0x00200000;  /* W-flag for post-indexed mode */
          *insn &= ~0x01000000; /* force post-indexed */
        }
        if (am != AM_T)
          *insn |= 0x00400000;  /* B-flag for byte-transfer */
      }
      else if (am==AM_SB || am==AM_H || am==AM_SH) {  /* arch.4 ldr/str */
        if (cpu_type & AA4UP) {
          /* take P-, I- and L-bit from previous standard instruction */
          *insn = (*insn&0xf1100000)
                  | (((*insn&0x02000000)^0x02000000)>>3) /* I-bit is flipped */
                  | 0x90;
          if (am != AM_H) {
            if (*insn & 0x00100000)  /* load */
              *insn |= 0x40;  /* signed transfer */
            else
              cpu_error(18,addrmode_strings[am]);  /* illegal addr. mode */
          }
          if (am != AM_SB)
            *insn |= 0x20;  /* halfword-transfer */
          aa4ldst = 1;
        }
        else
          cpu_error(0);  /* instruction not supported on selected arch. */
      }
      else if (am != AM_NONE)
        cpu_error(18,addrmode_strings[am]);  /* illegal addr. mode */
    }
    else if (ip->code == OC_SWP) {
      if (am == AM_B)
        *insn |= 0x00400000;  /* swap bytes */
      else if (am != AM_NONE)
        cpu_error(18,addrmode_strings[am]);  /* illegal addr. mode */
    }
  }
  else {  /* called by instruction_size() */
    if (am==AM_SB || am==AM_H || am==AM_SH)
      aa4ldst = 1;
  }

  for (opcnt=0; ip->op[opcnt]!=NULL && opcnt<MAX_OPERANDS; opcnt++) {
    taddr val;
    symbol *base = NULL;
    int btype;

    op = *(ip->op[opcnt]);
    if (!eval_expr(op.value,&val,sec,pc))
      btype = find_base(op.value,&base,sec,pc);

    /* do optimizations first */

    if (op.type==PCL12 || op.type==PCLRT ||
        op.type==PCLCP || op.type==BRA24) {
      /* PC-relative offsets (take prefetch into account: PC+8) */
      if (base!=NULL && btype==BASE_OK) {
        if (base->type==LABSYM && base->sec==sec) {
          /* no relocation required, can be resolved immediately */
          val -= pc + 8;

          switch (op.type) {
            case BRA24:
              if (val>=0x2000000 || val<-0x2000000) {
                /* @@@ optimize? to what? */
                if (insn)
                  cpu_error(3,(long)val);  /* branch offset is out of range */
              }
              break;

            case PCL12:
              if ((!aa4ldst && val<0x1000 && val>-0x1000) ||
                  (aa4ldst && val<0x100 && val>-0x100)) {
                op.type = IMUD2;  /* handle as normal #+/-Imm12 */
                if (val < 0)
                  val = -val;
                else
                  op.flags |= OFL_UP;
                base = NULL;  /* no more checks */
              }
              else {
                if (opt_ldrpc &&
                    ((!aa4ldst && val<0x100000 && val>-0x100000) ||
                     (aa4ldst && val<0x10000 && val>-0x10000))) {
                  /* ADD/SUB Rd,PC,#offset&0xff000 */
                  /* LDR/STR Rd,[Rd,#offset&0xfff] */
                  if (insn) {
                    taddr v;

                    *(insn+1) = *insn;
                    *insn &= 0xf0000000;         /* clear all except cond. */
                    if (val < 0) {
                      v = -val;
                      *insn |= 0x024f0a00;       /* SUB */
                      *(insn+1) &= ~0x00800000;  /* clear U-bit */
                    }
                    else {
                      v = val;
                      *insn |= 0x028f0a00;      /* ADD */
                      *(insn+1) |= 0x00800000;  /* set U-bit */
                    }
                    if (aa4ldst)
                      *insn |= (*(insn+1)&0xf000) | ((v&0xff00)>>8);
                    else
                      *insn |= (*(insn+1)&0xf000) | ((v&0xff000)>>12);
                    *(insn+1) &= ~0x000f0000;  /* replace PC by Rd */
                    *(insn+1) |= (*insn & 0xf000) << 4;
                    insn++;
                  }
                  if (val < 0)
                    val = -val;
                  else
                    op.flags |= OFL_UP;
                  val = aa4ldst ? (val & 0xff) : (val & 0xfff);
                  isize += 4;
                  op.type = IMUD2;
                  base = NULL;  /* no more checks */
                }
                else {
                  op.type = NOOP;
                  if (insn)
                    cpu_error(4,val);  /* PC-relative ldr/str out of range */
                }
              }
              break;

            case PCLCP:
              if (val<0x400 && val>-0x400) {
                op.type = IMCP2;  /* handle as normal #+/-Imm10>>2 */
                if (val < 0)
                  val = -val;
                else
                  op.flags |= OFL_UP;
                base = NULL;  /* no more checks */
              }
              else {
                /* no optimization, because we don't have a free register */
                op.type = NOOP;
                if (insn)
                  cpu_error(4,val);  /* PC-relative ldc/stc out of range */
              }
              break;

            case PCLRT:
              op.type = NOOP;  /* is handled here */
              if (val < 0) {
                /* use SUB instead of ADD */
                if (insn)
                  *insn ^= 0x00c00000;
                val = -val;
              }
              if ((val = rotated_immediate(val)) != ROTFAIL) {
                if (insn)
                  *insn |= val;
              }
              else if (opt_adr || am==AM_L) {
                /* ADRL or optimize ADR automatically to ADRL */
                uint32_t hi,lo;

                isize += 4;
                if ((lo = double_rot_immediate(val,&hi)) != ROTFAIL) {
                  /* ADD/SUB Rd,PC,#hi8rotated */
                  /* ADD/SUB Rd,Rd,#lo8rotated */
                  if (insn) {
                    *(insn+1) = *insn & ~0xf0000;
                    *(insn+1) |= (*insn&0xf000) << 4;
                    *insn++ |= hi;
                    *insn |= lo;
                  }
                }
                else if (insn)
                  cpu_error(5,(uint32_t)val); /* Cannot make rot.immed.*/
              }
              else if (insn)
                cpu_error(5,(uint32_t)val);  /* Cannot make rot.immed.*/
              break;

            default:
              ierror(0);
          }
        }
        else {
          /* symbol is in a different section or externally declared */
          switch (op.type) {
            case BRA24:
              val -= ARM_PREFETCH;
              if (db)
                add_nreloc_masked(&db->relocs,base,val,REL_PC,24,8,0x3fffffc);
              break;
            case PCL12:
              op.type = IMUD2;
              if (db) {
                if (val<0x1000 && val>-0x1000) {
                  add_nreloc_masked(&db->relocs,base,val,REL_PC,12,20,0x1fff);
                  base = NULL;  /* don't add another REL_ABS below */
                }
                else
                  cpu_error(22); /* operation not allowed on external symbols */
              }
              break;
            case PCLCP:
              if (db)
                cpu_error(22); /* operation not allowed on external symbols */
              break;
            case PCLRT:
              op.type = NOOP;
              if (am==AM_L && val==0) {  /* ADRL */
                isize += 4;  /* always reserve two ADD instructions */
                if (insn!=NULL && db!=NULL) {
                  *(insn+1) = *insn & ~0xf0000;
                  *(insn+1) |= (*insn&0xf000) << 4;
                  add_nreloc_masked(&db->relocs,base,val,REL_PC,8,24,0xff00);
                  add_nreloc_masked(&db->relocs,base,val,REL_PC,8,32+24,0xff);
                }
              }
              else if (val == 0) {  /* ADR */
                if (db)
                  add_nreloc_masked(&db->relocs,base,val,REL_PC,8,24,0xff);
              }
              else if (db)
                cpu_error(22); /* operation not allowed on external symbols */
              break;
            default:
              ierror(0);
          }
        }
      }
      else if (insn) {
        op.type = NOOP;
        cpu_error(2);  /* label from current section required */
      }
    }

    else if (op.type == IMROT) {
      op.type = NOOP;  /* is handled here */

      if (base == NULL) {
        uint32_t rotval;

        if ((rotval = rotated_immediate(val)) != ROTFAIL) {
          if (insn)
            *insn |= rotval;
        }
        else if (!negated_rot_immediate(val,mnemo,insn)) {
          /* rotation, negation and inversion failed - try a 2nd operation */
          isize += 4;
          if (insn) {
            if (!negated_double_rot_immediate(val,insn))
              cpu_error(7,(uint32_t)val); /* const not suitable */
          }
        }
      }
      else if (insn)
        cpu_error(6);  /* constant integer expression required */
    }

    /* optimizations should be finished at this stage -
       inserts operands into the opcode now: */

    if (insn) {

      if (REGOPER(op.type)) {
        /* insert register operand */
        if (base!=NULL || val<0 || val>15)
          cpu_error(9);  /* not a valid ARM register */

        if (REG19OPER(op.type))
          *insn |= val<<16;
        else if (REG15OPER(op.type))
          *insn |= val<<12;
        else if (REG11OPER(op.type))
          *insn |= val<<8;
        else if (REG03OPER(op.type))
          *insn |= val;

        if (op.type==R3UD1 && !(*insn&0x01000000))
          cpu_error(21);  /* post-indexed addressing mode expected */
        if (op.flags & OFL_WBACK)
          *insn |= 0x00200000;
        if (op.flags & OFL_UP)
          *insn |= 0x00800000;

        /* some more checks: */
        if ((mnemo->ext.flags&NOPC) && val==15)
          cpu_error(10);  /* PC (r15) not allowed in this mode */
        if ((mnemo->ext.flags&NOPCR03) && val==15 && REG03OPER(op.type))
          cpu_error(11);  /* PC (r15) not allowed for offset register Rm */
        if ((mnemo->ext.flags&NOPC) && val==15 && (op.flags&OFL_WBACK))
          cpu_error(12);  /* PC (r15) not allowed with write-back */

        /* check for illegal double register specifications */
        if (((mnemo->ext.flags&DIFR03) && REG03OPER(op.type)) ||
            ((mnemo->ext.flags&DIFR11) && REG11OPER(op.type)) ||
            ((mnemo->ext.flags&DIFR15) && REG15OPER(op.type)) ||
            ((mnemo->ext.flags&DIFR19) && REG19OPER(op.type))) {
          if (chkreg != -1) {
            if (val == chkreg)
              cpu_error(13,(long)val);  /* register was used multiple times */
          }
          else
            chkreg = val;
        }
      }

      else if (op.type == BRA24) {
        /* only write offset, relocs and optimizations are handled above */
        if (val & 3)
          cpu_error(8,(long)val);  /* branch to unaligned address */
        *insn |= (val>>2) & 0xffffff;
      }

      else if (op.type==IMUD1 || op.type==IMUD2) {
        if (aa4ldst) {
          /* insert splitted 8-bit immediate for signed/halfword ldr/str */
          if (val>=0 && val<=0xff) {
            *insn |= ((val&0xf0)<<4) | (val&0x0f);
          }
          else
            cpu_error(20,8,(long)val);  /* immediate offset out of range */
        }
        else {
          /* insert immediate 12-bit with up/down flag */
          if (val>=0 && val<=0xfff) {
            *insn |= val;
          }
          else
            cpu_error(20,12,(long)val);  /* immediate offset out of range */
        }

        if (op.type==IMUD1 && !(*insn&0x01000000))
          cpu_error(21);  /* post-indexed addressing mode exptected */
        if (op.flags & OFL_WBACK)
          *insn |= 0x00200000;  /* set write-back flag */
        if (op.flags & OFL_UP)
          *insn |= 0x00800000;  /* set UP-flag */

        if (base) {
          if (btype == BASE_OK) {
            if (base->type == IMPORT) {
              if (!aa4ldst) {
                /* @@@ does this make any sense? */
                *insn |= 0x00800000;  /* only UP */
                add_nreloc_masked(&db->relocs,base,val,REL_ABS,12,20,0xfff);
              }
              else
                cpu_error(22); /* operation not allowed on external symbols */
            }
            else
              cpu_error(6);  /* constant integer expression required */
          }
          else
            general_error(38);  /* illegal relocation */
        }
      }

      else if (op.type==IMCP1 || op.type==IMCP2) {
        /* insert immediate 10-bit shifted left by 2, with up/down flag */
        if (val>=0 && val<=0x3ff) {
          if ((val & 3) == 0)
            *insn |= val>>2;
          else
            cpu_error(23);  /* ldc/stc offset has to be a multiple of 4 */
        }
        else
          cpu_error(20,10,(long)val);  /* immediate offset out of range */

        if (op.flags & OFL_WBACK)
          *insn |= 0x00200000;  /* set write-back flag */
        if (op.flags & OFL_UP)
          *insn |= 0x00800000;  /* set UP-flag */

        if (base)
          cpu_error(6);  /* constant integer expression required */
      }

      else if (op.type == SWI24) {
        /* insert 24-bit immediate (SWI instruction) */
        if (val>=0 && val<0x1000000) {
          *insn |= val;
          if (base!=NULL && db!=NULL)
            add_nreloc_masked(&db->relocs,base,val,REL_ABS,24,8,0xffffff);
        }
        else
          cpu_error(16);  /* 24-bit unsigned immediate expected */
      }

      else if (SHIFTOPER(op.type)) {
        /* insert a register- or immediate shift */
        int sh_op = op.flags & OFL_SHIFTOP;

        if (aa4ldst)
          cpu_error(19);  /* signed/halfword ldr/str doesn't support shifts */
        if (op.type==SHIM1 && !(*insn&0x01000000))
          cpu_error(21);  /* post-indexed addressing mode exptected */

        if (op.flags & OFL_IMMEDSHIFT) {
          if (sh_op==1 || sh_op==2) {  /* lsr/asr permit shift-count #32 */
            if (val == 32)
              val = 0;
          }
          if (base==NULL && val>=0 && val<32) {
            *insn |= (val<<7) | ((op.flags&OFL_SHIFTOP)<<5);
            if (op.flags & OFL_WBACK)
              *insn |= 0x00200000;
          }
          else
            cpu_error(14,(long)val);  /* illegal immediate shift count */
        }
        else {  /* shift count in register */
          if (base==NULL && val>=0 && val<16) {
            *insn |= (val<<8) | ((op.flags&OFL_SHIFTOP)<<5) | 0x10;
          }
          else
            cpu_error(15);  /* not a valid shift register */
        }
      }

      else if (CPOPCODE(op.type)) {
        /* insert coprocessor operation/type */
        if (base == NULL) {
          switch (op.type) {
            case CPOP3:
              if (val>=0 && val<8)
                *insn |= val<<21;
              else
                cpu_error(24,val);  /* illegal coprocessor operation */
              break;
            case CPOP4:
              if (val>=0 && val<16)
                *insn |= val<<20;
              else
                cpu_error(24,val);  /* illegal coprocessor operation */
              break;
            case CPTYP:
              if (val>=0 && val<8)
                *insn |= val<<5;
              else
                cpu_error(24,val);  /* illegal coprocessor operation */
              break;
            default: ierror(0);
          }
        }
        else
          cpu_error(24,val);  /* illegal coprocessor operation */
      }

      else if (op.type==CSPSR || op.type==PSR_F) {
        /* insert PSR type - no checks needed */
        *insn |= val<<16;
        if (op.flags & OFL_SPSR)
          *insn |= 0x00400000;
      }

      else if (op.type == RLIST) {
        /* insert register-list field */
        if (am<AM_DA || am>AM_ED)
          cpu_error(18,addrmode_strings[am]);  /* illegal addr. mode */
        if (am>=AM_FA && am<=AM_ED) {
          /* fix stack-addressing mode */
          if (!(mnemo->ext.opcode & 0x00100000))
            am ^= 3;  /* invert P/U modes for store operations */
        }
        *insn |= ((am&3)<<23) | val;
        if (op.flags & OFL_FORCE)
          *insn |= 0x00400000;
      }

      else if (op.type != NOOP)
        ierror(0);
    }
  }

  return isize;
}


taddr instruction_size(instruction *ip,section *sec,taddr pc)
/* Calculate the size of the current instruction; must be identical
   to the data created by eval_instruction. */
{
  if (mnemonics[ip->code].ext.flags & THUMB)
    return eval_thumb_operands(ip,sec,pc,NULL,NULL);

  /* ARM mode */
  return eval_arm_operands(ip,sec,pc,NULL,NULL);
}


dblock *eval_instruction(instruction *ip,section *sec,taddr pc)
/* Convert an instruction into a DATA atom including relocations,
   if necessary. */
{
  dblock *db = new_dblock();
  int inst_type;

  if (sec != last_section) {
    last_section = sec;
    last_data_type = -1;
  }
  inst_type = (mnemonics[ip->code].ext.flags & THUMB) ? TYPE_THUMB : TYPE_ARM;

  if (inst_type == TYPE_THUMB) {
    uint16_t insn[2];

    if (db->size = eval_thumb_operands(ip,sec,pc,insn,db)) {
      unsigned char *d = db->data = mymalloc(db->size);
      int i;

      for (i=0; i<db->size/2; i++)
        d = setval(arm_be_mode,d,2,insn[i]);
    }
  }

  else {  /* ARM mode */
    uint32_t insn[2];

    if (db->size = eval_arm_operands(ip,sec,pc,insn,db)) {
      unsigned char *d = db->data = mymalloc(db->size);
      int i;

      for (i=0; i<db->size/4; i++)
        d = setval(arm_be_mode,d,4,insn[i]);
    }
  }

  if (inst_type != last_data_type)
    create_mapping_symbol(inst_type,sec,pc);

  return db;
}


dblock *eval_data(operand *op,taddr bitsize,section *sec,taddr pc)
/* Create a dblock (with relocs, if necessary) for size bits of data. */
{
  dblock *db = new_dblock();
  taddr val;

  if (sec != last_section) {
    last_section = sec;
    last_data_type = -1;
  }

  if ((bitsize & 7) || bitsize > 32)
    cpu_error(17,bitsize);  /* data size not supported */

  if (op->type != DATA_OP)
    ierror(0);

  db->size = bitsize >> 3;
  db->data = mymalloc(db->size);

  if (!eval_expr(op->value,&val,sec,pc)) {
    symbol *base;
    int btype;

    btype = find_base(op->value,&base,sec,pc);
    if (base)
      add_nreloc(&db->relocs,base,val,
                 btype==BASE_PCREL?REL_PC:REL_ABS,bitsize,0);
    else
      general_error(38);  /* illegal relocation */
  }

  switch (db->size) {
    case 1:
      db->data[0] = val & 0xff;
      break;
    case 2:
    case 4:
      setval(arm_be_mode,db->data,db->size,val);
      break;
    default:
      ierror(0);
      break;
  }

  if (last_data_type != TYPE_DATA)
    create_mapping_symbol(TYPE_DATA,sec,pc);

  return db;
}


int init_cpu()
{
  char r[4];
  int i;

  for (i=0; i<mnemonic_cnt; i++) {
    if (!strcmp(mnemonics[i].name,"swp"))
      OC_SWP = i;
    else if (!strcmp(mnemonics[i].name,"nop"))
      OC_NOP = i;
  }

  if (!strcmp(output_format,"elf"))
    elfoutput = 1;

  /* define register symbols */
  regsymhash = new_hashtable(REGSYMHTSIZE);
  for (i=0; i<16; i++) {
    sprintf(r,"r%d",i);
    addregsym(r,i);
    sprintf(r,"c%d",i);
    addregsym(r,i);
    sprintf(r,"p%d",i);
    addregsym(r,i);
  }
  /* ATPCS synonyms */
  for (i=0; i<8; i++) {
    if (i < 4) {
      sprintf(r,"a%d",i+1);
      addregsym(r,i);
    }
    sprintf(r,"v%d",i+1);
    addregsym(r,i+4);
  }
  /* well known aliases */
  addregsym("wr",7);
  addregsym("sb",9);
  addregsym("sl",10);
  addregsym("fp",11);
  addregsym("ip",12);
  addregsym("sp",13);
  addregsym("lr",14);
  addregsym("pc",15);

  return 1;
}


int cpu_args(char *p)
{
  if (!strncmp(p,"-m",2)) {
    p += 2;
    if (!strcmp(p,"2")) cpu_type = ARM2;
    else if (!strcmp(p,"250")) cpu_type = ARM250;
    else if (!strcmp(p,"3")) cpu_type = ARM3;
    else if (!strcmp(p,"6")) cpu_type = ARM6;
    else if (!strcmp(p,"600")) cpu_type = ARM600;
    else if (!strcmp(p,"610")) cpu_type = ARM610;
    else if (!strcmp(p,"7")) cpu_type = ARM7;
    else if (!strcmp(p,"710")) cpu_type = ARM710;
    else if (!strcmp(p,"7500")) cpu_type = ARM7500;
    else if (!strcmp(p,"7d")) cpu_type = ARM7d;
    else if (!strcmp(p,"7di")) cpu_type = ARM7di;
    else if (!strcmp(p,"7dm")) cpu_type = ARM7dm;
    else if (!strcmp(p,"7dmi")) cpu_type = ARM7dmi;
    else if (!strcmp(p,"7tdmi")) cpu_type = ARM7tdmi;
    else if (!strcmp(p,"8")) cpu_type = ARM8;
    else if (!strcmp(p,"810")) cpu_type = ARM810;
    else if (!strcmp(p,"9")) cpu_type = ARM9;
    else if (!strcmp(p,"920")) cpu_type = ARM920;
    else if (!strcmp(p,"920t")) cpu_type = ARM920t;
    else if (!strcmp(p,"9tdmi")) cpu_type = ARM9tdmi;
    else if (!strcmp(p,"sa1")) cpu_type = SA1;
    else if (!strcmp(p,"strongarm")) cpu_type = STRONGARM;
    else if (!strcmp(p,"strongarm110")) cpu_type = STRONGARM110;
    else if (!strcmp(p,"strongarm1100")) cpu_type = STRONGARM1100;
    else return 0;
  }
  else if (!strncmp(p,"-a",2)) {
    p += 2;
    if (!strcmp(p,"2")) cpu_type = AA2;
    else if (!strcmp(p,"3")) cpu_type = AA3;
    else if (!strcmp(p,"3m")) cpu_type = AA3M;
    else if (!strcmp(p,"4")) cpu_type = AA4;
    else if (!strcmp(p,"4t")) cpu_type = AA4T;
    else return 0;
  }
  else if (!strcmp(p,"-little"))
    arm_be_mode = 0;
  else if (!strcmp(p,"-big"))
    arm_be_mode = 1;
  else if (!strcmp(p,"-thumb"))
    thumb_mode = 1;
  else if (!strcmp(p,"-opt-ldrpc"))
    opt_ldrpc = 1;
  else if (!strcmp(p,"-opt-adr"))
    opt_adr = 1;

  return 1;
}
