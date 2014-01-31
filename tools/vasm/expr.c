/* expr.c expression handling for vasm */
/* (c) in 2002-2012 by Volker Barthelmann */

#include "vasm.h"

char current_pc_char='$';
static char *s;

#ifndef EXPSKIP
#define EXPSKIP() s=skip(s)
#endif

static expr *expression();
static symbol *cpc;
static int make_tmp_lab;


expr *new_expr(void)
{
  expr *new=mymalloc(sizeof(*new));
  new->left=new->right=0;
  return new;
}

expr *make_expr(int type,expr *left,expr *right)
{
  expr *new=mymalloc(sizeof(*new));
  new->left=left;
  new->right=right;
  new->type=type;
  return new;
}

expr *copy_tree(expr *old)
{
  expr *new=0;

  if(old){
    new=make_expr(old->type,copy_tree(old->left),copy_tree(old->right));
    new->c=old->c;
  }
  return new;
}

expr *curpc_expr(void)
{
  expr *new=new_expr();
  if(!cpc){
    cpc=new_import(" *current pc dummy*");
    cpc->type=LABSYM;
    cpc->flags|=VASMINTERN;
  }
  new->type=SYM;
  new->c.sym=cpc;
  return new;
}

static expr *primary_expr(void)
{
  expr *new;
  char *m,*name;
  int base;

  if(*s=='('){
    s++;
    EXPSKIP();
    new=expression();
    if(*s!=')')
      general_error(6,')');
    else
      s++;
    EXPSKIP();
    return new;
  }
  if(name=get_local_label(&s)){
    symbol *sym=find_symbol(name);
    if(!sym)
      sym=new_import(name);
    if (sym->type!=EXPRESSION){
      new=new_expr();
      new->type=SYM;
      new->c.sym=sym;
    }
    else
      new=copy_tree(sym->expr);
    myfree(name);
    return new;
  }
  m=const_prefix(s,&base);
  if(base!=0){
    taddr val=0;
    s=m;
    if(base<=10){
      while(*s>='0'&&*s<base+'0')
        val=base*val+*s++-'0';
    }else if(base==16){
      while((*s>='0'&&*s<='9')||(*s>='a'&&*s<='f')||(*s>='A'&&*s<='F')){
        if(*s>='0'&&*s<='9')
          val=16*val+*s++-'0';
        else if(*s>='a'&&*s<='f')
          val=16*val+*s++-'a'+10;
        else
          val=16*val+*s++-'A'+10;
      }
    }else{
      ierror(0);
    }
    EXPSKIP();
    new=new_expr();
    new->type=NUM;
    new->c.val=val;
    return new;
  }
  if(*s==current_pc_char && !ISIDCHAR(*(s+1))){
    s++;
    EXPSKIP();
    if(make_tmp_lab){
      new=new_expr();
      new->type=SYM;
      new->c.sym=new_tmplabel(0);
      add_atom(0,new_label_atom(new->c.sym));
    }else new=curpc_expr();
    return new;
  }
  if(name=parse_identifier(&s)){
    symbol *sym;    
    EXPSKIP();
    sym=find_symbol(name);
    if(!sym){
#ifdef NARGSYM
      if(!strcmp(name,NARGSYM)){
        new=new_expr();
        new->type=NUM;
        new->c.val=cur_src->num_params; /*@@@ check for macro mode? */
        return new;
      }
#endif
      sym=new_import(name);
    }
    if (sym->type!=EXPRESSION){
      new=new_expr();
      new->type=SYM;
      new->c.sym=sym;
    }
    else
      new=copy_tree(sym->expr);
    myfree(name);
    return new;
  }
  if(*s=='\''||*s=='\"'){
    taddr val=0;
    int shift=0,cnt=0;
    char quote=*s++;
    while(*s){
      char c;
      if(*s=='\\')
        s=escape(s,&c);
      else{
        c=*s++;
        if(c==quote){
          if(*s==quote)
            s++;  /* allow """" to be recognized as " and '''' as ' */
          else break;
        }
      }
      if(++cnt>bytespertaddr){
        general_error(21);
        break;
      }
      if(BIGENDIAN){
        val=(val<<8)+c;
      }else if(LITTLEENDIAN){
        val+=c<<shift;
        shift+=8;
      }else
        ierror(0);
    }
    EXPSKIP();
    new=new_expr();
    new->type=NUM;
    new->c.val=val;
    return new;
  }
  general_error(9);
  new=new_expr();
  new->type=NUM;
  new->c.val=-1;
  return new;
}
    
static expr *unary_expr()
{
  expr *new;
  char *m;
  int len;
  if(*s=='+'||*s=='-'||*s=='!'||*s=='~'){
    m=s++;
    EXPSKIP();
  }
  else if(len=EXT_UNARY_NAME(s)){
    m=s;
    s+=len;
    EXPSKIP();
  }else
    return primary_expr();
  if(*m=='+')
    return primary_expr();
  new=new_expr();
  if(*m=='-')
    new->type=NEG;
  else if(*m=='!')
    new->type=NOT;
  else if(*m=='~')
    new->type=CPL;
  else if(EXT_UNARY_NAME(m))
    new->type=EXT_UNARY_TYPE(m);
  new->left=primary_expr();
  return new;
}  

static expr *shift_expr()
{
  expr *left,*new;
  char m;
  left=unary_expr();
  EXPSKIP();
  while((*s=='<'||*s=='>')&&s[1]==*s){
    m=*s;
    s+=2;
    EXPSKIP();
    new=new_expr();
    if(m=='<')
      new->type=LSH;
    else
      new->type=RSH;
    new->left=left;
    new->right=unary_expr();
    left=new;
    EXPSKIP();
  }
  return left;
}

static expr *multiplicative_expr(void)
{
  expr *left,*new;
  char m;
  left=shift_expr();
  EXPSKIP();
  while(*s=='*'||*s=='/'||*s=='%'){
    m=*s++;
    EXPSKIP();
    new=new_expr();
    if(m=='/'){
      if(*s=='/'){
        s++;
        new->type=MOD;
      }
      else
        new->type=DIV;
    }
    else if(m=='*')
      new->type=MUL;
    else
      new->type=MOD;
    new->left=left;
    new->right=shift_expr();
    left=new;
    EXPSKIP();
  }
  return left;
}

static expr *and_expr(void)
{
  expr *left,*new;
  left=multiplicative_expr();
  EXPSKIP();
  while(*s=='&'&&s[1]!='&'){
    s++;
    EXPSKIP();
    new=new_expr();
    new->type=BAND;
    EXPSKIP();
    new->left=left;
    new->right=multiplicative_expr();
    left=new;
  }
  return left;
}

static expr *exclusive_or_expr(void)
{
  expr *left,*new;
  left=and_expr();
  EXPSKIP();
  while(*s=='^'||*s=='~'){
    s++;
    EXPSKIP();
    new=new_expr();
    new->type=XOR;
    EXPSKIP();
    new->left=left;
    new->right=and_expr();
    left=new;
  }
  return left;
}

static expr *inclusive_or_expr(void)
{
  expr *left,*new;
  left=exclusive_or_expr();
  EXPSKIP();
  while((*s=='|'&&s[1]!='|')||(*s=='!'&&s[1]!='=')){
    s++;
    EXPSKIP();
    new=new_expr();
    new->type=BOR;
    EXPSKIP();
    new->left=left;
    new->right=exclusive_or_expr();
    left=new;
  }
  return left;
}

static expr *additive_expr(void)
{
  expr *left,*new;
  char m;
  left=inclusive_or_expr();
  EXPSKIP();
  while(*s=='+'||*s=='-'){
    m=*s++;
    EXPSKIP();
    new=new_expr();
    if(m=='+')
      new->type=ADD;
    else
      new->type=SUB;
    new->left=left;
    new->right=inclusive_or_expr();
    left=new;
    EXPSKIP();
  }
  return left;
}

static expr *relational_expr(void)
{
  expr *left,*new;
  char m1,m2=0;
  left=additive_expr();
  EXPSKIP();
  while(((*s=='<'&&s[1]!='>')||*s=='>')&&s[1]!=*s){
    m1=*s++;
    if(*s=='=')
      m2=*s++;
    EXPSKIP();
    new=new_expr();
    if(m1=='<'){
      if(m2)
        new->type=LEQ;
      else
        new->type=LT;
    }else{
      if(m2)
        new->type=GEQ;
      else
        new->type=GT;
    }
    EXPSKIP();
    new->left=left;
    new->right=additive_expr();
    left=new;
  }
  return left;
}

static expr *equality_expr(void)
{
  expr *left,*new;
  char m;
  left=relational_expr();
  EXPSKIP();
  while(*s=='='||(*s=='!'&&s[1]=='=')||(*s=='<'&&s[1]=='>')){
    m=*s++;
    if(m==*s||m!='=')
      s++;
    EXPSKIP();
    new=new_expr();
    if(m=='=')
      new->type=EQ;
    else
      new->type=NEQ;
    EXPSKIP();
    new->left=left;
    new->right=relational_expr();
    left=new;
  }
  return left;
}

static expr *logical_and_expr(void)
{
  expr *left,*new;
  left=equality_expr();
  EXPSKIP();
  while(*s=='&'&&s[1]=='&'){
    s+=2;
    EXPSKIP();
    new=new_expr();
    new->type=LAND;
    EXPSKIP();
    new->left=left;
    new->right=equality_expr();
    left=new;
  }
  return left;
}

static expr *expression()
{
  expr *left,*new;
  left=logical_and_expr();
  EXPSKIP();
  while(*s=='|'&&s[1]=='|'){
    s+=2;
    EXPSKIP();
    new=new_expr();
    new->type=LOR;
    EXPSKIP();
    new->left=left;
    new->right=logical_and_expr();
    left=new;
  }
  return left;
}

/* Tries to parse the string as a constant value. Sets pp to the
   end of the parse. Already defined absolute symbols are
   recognized. */
expr *parse_expr(char **pp)
{
  expr *tree;
  s=*pp;
  make_tmp_lab=0;
  tree=expression();
  simplify_expr(tree);
  *pp=s;
  return tree;
}

expr *parse_expr_tmplab(char **pp)
{
  expr *tree;
  s=*pp;
  make_tmp_lab=1;
  tree=expression();
  simplify_expr(tree);
  *pp=s;
  return tree;
}

void free_expr(expr *tree)
{
  if(!tree)
    return;
  free_expr(tree->left);
  free_expr(tree->right);
  myfree(tree);
}

/* Try to evaluate expression as far as possible. Subexpressions
   only containing constants or absolute symbols are simplified. */
void simplify_expr(expr *tree)
{
  taddr val;
  if(!tree)
    return;
  simplify_expr(tree->left);
  simplify_expr(tree->right);
  if((tree->left&&tree->left->type!=NUM)||
     (tree->right&&tree->right->type!=NUM))
    return;
  switch(tree->type){
  case ADD:
    val=(tree->left->c.val+tree->right->c.val);
    break;
  case SUB:
    val=(tree->left->c.val-tree->right->c.val);
    break;
  case MUL:
    val=(tree->left->c.val*tree->right->c.val);
    break;
  case DIV:
    if(tree->right->c.val==0){
      general_error(41);
      val=0;
    }else
      val=(tree->left->c.val/tree->right->c.val);
    break;
  case MOD:
    if(tree->right->c.val==0){
      general_error(41);
      val=0;
    }else
      val=(tree->left->c.val%tree->right->c.val);
    break;
  case NEG:
    val=(-tree->left->c.val);
    break;
  case CPL:
    val=(~tree->left->c.val);
    break;
  case LAND:
    val=-(tree->left->c.val&&tree->right->c.val);
    break;
  case LOR:
    val=-(tree->left->c.val||tree->right->c.val);
    break;
  case BAND:
    val=(tree->left->c.val&tree->right->c.val);
    break;
  case BOR:
    val=(tree->left->c.val|tree->right->c.val);
    break;
  case XOR:
    val=(tree->left->c.val^tree->right->c.val);
    break;
  case NOT:
    val=(!tree->left->c.val);
    break;
  case LSH:
    val=(tree->left->c.val<<tree->right->c.val);
    break;
  case RSH:
    val=(tree->left->c.val>>tree->right->c.val);
    break;
  case LT:
    val=-(tree->left->c.val<tree->right->c.val);
    break;
  case GT:
    val=-(tree->left->c.val>tree->right->c.val);
    break;
  case LEQ:
    val=-(tree->left->c.val<=tree->right->c.val);
    break;
  case GEQ:
    val=-(tree->left->c.val>=tree->right->c.val);
    break;
  case NEQ:
    val=-(tree->left->c.val!=tree->right->c.val);
    break;
  case EQ:
    val=-(tree->left->c.val==tree->right->c.val);
    break;
  case SYM:
    if(tree->c.sym->type==EXPRESSION&&tree->c.sym->expr->type==NUM){
      val=tree->c.sym->expr->c.val;
      break;
    }else 
      return;
  default:
#ifdef EXT_UNARY_EVAL
    if (tree->left && EXT_UNARY_EVAL(tree->type,tree->left->c.val,&val,1))
      break;
#endif
    return;
  }
  free_expr(tree->left);
  free_expr(tree->right);
  tree->type=NUM;
  tree->left=tree->right=0;
  tree->c.val=val;
}

/* Evaluate an expression using current values of all symbols.
   Result is written to *result. The return value specifies
   whether the result is constant (i.e. only depending on
   constants or absolute symbols). */
int eval_expr(expr *tree,taddr *result,section *sec,taddr pc)
{
  taddr val,lval,rval;
  symbol *lsym,*rsym;
  int cnst=1;

  if(!tree)
    ierror(0);
  if(tree->left&&!eval_expr(tree->left,&lval,sec,pc))
    cnst=0;
  if(tree->right&&!eval_expr(tree->right,&rval,sec,pc))
    cnst=0;

  switch(tree->type){
  case ADD:
    val=(lval+rval);
    break;
  case SUB:
    find_base(tree->left,&lsym,sec,pc);
    find_base(tree->right,&rsym,sec,pc);
    /* l2-l1 is constant when both have a valid symbol-base, and both
       symbols are LABSYMs from the same section, e.g. (sym1+x)-(sym2-y) */
    if(cnst==0&&lsym!=NULL&&rsym!=NULL)
       cnst=lsym->type==LABSYM&&rsym->type==LABSYM&&lsym->sec==rsym->sec;
    /* Difference between symbols from different section or between an
       external symbol and a symbol from the current section can be
       represented by a REL_PC, so we calculate the addend. */
    if(lsym!=NULL&&rsym!=NULL&&rsym->type==LABSYM&&
       rsym->sec==sec&&lsym->sec!=NULL&&
       ((lsym->type==LABSYM&&lsym->sec!=rsym->sec)||lsym->type==IMPORT))
      val=(pc-rval+lval-lsym->sec->org);
    else
      val=(lval-rval);
    break;
  case MUL:
    val=(lval*rval);
    break;
  case DIV:
    if(rval==0){
      general_error(41);
      val=0;
    }else
      val=(lval/rval);
    break;
  case MOD:
    if(rval==0){
      general_error(41);
      val=0;
    }else
      val=(lval%rval);
    break;
  case NEG:
    val=(-lval);
    break;
  case CPL:
    val=(~lval);
    break;
  case LAND:
    val=-(lval&&rval);
    break;
  case LOR:
    val=-(lval||rval);
    break;
  case BAND:
    val=(lval&rval);
    break;
  case BOR:
    val=(lval|rval);
    break;
  case XOR:
    val=(lval^rval);
    break;
  case NOT:
    val=(!lval);
    break;
  case LSH:
    val=(lval<<rval);
    break;
  case RSH:
    val=(lval>>rval);
    break;
  case LT:
    val=-(lval<rval);
    break;
  case GT:
    val=-(lval>rval);
    break;
  case LEQ:
    val=-(lval<=rval);
    break;
  case GEQ:
    val=-(lval>=rval);
    break;
  case NEQ:
    val=-(lval!=rval);
    break;
  case EQ:
    val=-(lval==rval);
    break;
  case SYM:
    if(tree->c.sym->type==EXPRESSION){
      if(tree->c.sym->flags&INEVAL)
        general_error(18,tree->c.sym->name);
      tree->c.sym->flags|=INEVAL;
      cnst=eval_expr(tree->c.sym->expr,&val,sec,pc);
      tree->c.sym->flags&=~INEVAL;
    }else if(tree->c.sym->type==LABSYM){
      if(tree->c.sym==cpc&&sec!=0){
        cpc->sec=sec;
        cpc->pc=pc;
      }
      val=tree->c.sym->pc;
      cnst=sec==NULL?0:(sec->flags&UNALLOCATED)!=0;
    }else{
      /* IMPORT */
      cnst=0;
      val=0;
    }
    break;
  case NUM:
    val=tree->c.val;
    break;
  default:
#ifdef EXT_UNARY_EVAL
    if (EXT_UNARY_EVAL(tree->type,lval,&val,cnst))
      break;
#endif
    ierror(0);
  }
  *result=val;
  return cnst;
}

void print_expr(FILE *f,expr *p)
{
  simplify_expr(p);
  if(p->type==NUM)
    fprintf(f,"%lu",(unsigned long)p->c.val);
  else
    fprintf(f,"complex expression");
}

/* Tests, if an expression is based only on one non-absolute
   symbol plus constants. Returns that symbol or zero.
   Note: Does not find all possible solutions. */
int find_base(expr *p,symbol **base,section *sec,taddr pc)
{
  if(base)
    *base=NULL;
  if(p->type==SYM){
    if(p->c.sym==cpc&&sec!=NULL){
      cpc->sec=sec;
      cpc->pc=pc;
    }
    if(p->c.sym->type==EXPRESSION)
      return find_base(p->c.sym->expr,base,sec,pc);
    else{
      if(base)
        *base=p->c.sym;
      return BASE_OK;
    }
  }
  if(p->type==ADD){
    taddr val;
    if(eval_expr(p->left,&val,sec,pc)&&
       find_base(p->right,base,sec,pc)==BASE_OK)
      return BASE_OK;
    if(eval_expr(p->right,&val,sec,pc)&&
       find_base(p->left,base,sec,pc)==BASE_OK)
      return BASE_OK;
  }
  if(p->type==SUB){
    taddr val;
    symbol *pcsym;
    if(eval_expr(p->right,&val,sec,pc)&&
       find_base(p->left,base,sec,pc)==BASE_OK)
      return BASE_OK;
    if(find_base(p->left,base,sec,pc)==BASE_OK&&
       find_base(p->right,&pcsym,sec,pc)==BASE_OK) {
      if(pcsym->type==LABSYM&&pcsym->sec==sec&&
         ((*base)->type==LABSYM||(*base)->type==IMPORT))
        return BASE_PCREL;
    }
  }
#ifdef EXT_FIND_BASE
  return EXT_FIND_BASE(base,p,sec,pc);
#else
  return BASE_ILLEGAL;
#endif
}

expr *number_expr(taddr val)
{
  expr *new=new_expr();
  new->type=NUM;
  new->c.val=val;
  return new;
}

taddr parse_constexpr(char **s)
{
  expr *tree;
  taddr val = 0;

  if (tree = parse_expr(s)) {
    simplify_expr(tree);
    if (tree->type == NUM)
      val = tree->c.val;
    else
      general_error(30);  /* expression must be a constant */
    free_expr(tree);
  }
  return val;
}
