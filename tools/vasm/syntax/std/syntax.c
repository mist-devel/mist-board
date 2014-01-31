/* syntax.c  syntax module for vasm */
/* (c) in 2002-2013 by Volker Barthelmann and Frank Wille */

#include "vasm.h"

/* The syntax module parses the input (read_next_line), handles
   assembly-directives (section, data-storage etc.) and parses
   mnemonics. Assembly instructions are split up in mnemonic name,
   qualifiers and operands. new_inst returns a matching instruction,
   if one exists.
   Routines for creating sections and adding atoms to sections will
   be provided by the main module.
*/

char *syntax_copyright="vasm std syntax module 3.8a (c) 2002-2013 Volker Barthelmann";
hashtable *dirhash;

static char textname[]=".text",textattr[]="acrx";
static char dataname[]=".data",dataattr[]="adrw";
static char sdataname[]=".sdata",sdataattr[]="adrw";
static char sdata2name[]=".sdata2",sdata2attr[]="adr";
static char rodataname[]=".rodata",rodataattr[]="adr";
static char bssname[]=".bss",bssattr[]="aurw";
static char sbssname[]=".sbss",sbssattr[]="aurw";
static char tocdname[]=".tocd",tocdattr[]="adrw";
static char stabname[]=".stab",stabattr[]="dr";
static char stabstrname[]=".stabstr",stabstrattr[]="dr";

#if defined(VASM_CPU_C16X) || defined(VASM_CPU_M68K) || defined(VASM_CPU_650X) || defined(VASM_CPU_ARM) || defined(VASM_CPU_Z80)
char commentchar=';';
#else
char commentchar='#';
#endif
char *defsectname = textname;
char *defsecttype = "acrwx";

static char endmname[] = ".endm";
static char reptname[] = ".rept";
static char endrname[] = ".endr";
static struct namelen dendm_dirlist[] = {
  { 5,&endmname[0] }, { 0,0 }
};
static struct namelen drept_dirlist[] = {
  { 5,&reptname[0] }, { 0,0 }
};
static struct namelen dendr_dirlist[] = {
  { 5,&endrname[0] }, { 0,0 }
};
static struct namelen endm_dirlist[] = {
  { 4,&endmname[1] }, { 0,0 }
};
static struct namelen rept_dirlist[] = {
  { 4,&reptname[1] }, { 0,0 }
};
static struct namelen endr_dirlist[] = {
  { 4,&endrname[1] }, { 0,0 }
};

static int nodotneeded=0;
static int alloccommon=0;
static taddr sdlimit=-1; /* max size of common data in .sbss section */

#define MAXCONDLEV 63
static char cond[MAXCONDLEV+1];
static int clev,ifnesting;

#define LOCAL (RSRVD_S<<0)      /* symbol flag for local binding */


char *skip(char *s)
{
  while (isspace((unsigned char )*s))
    s++;
  return s;
}

/* check for end of line, issue error, if not */
void eol(char *s)
{
  s = skip(s);
  if (*s!='\0' && *s!=commentchar)
    syntax_error(6);
}

char *skip_operand(char *s)
{
  int par_cnt=0;
  char c;

  while(1){
    c = *s;
    if(START_PARENTH(c)) par_cnt++;
    if(END_PARENTH(c)){
      if(par_cnt>0)
        par_cnt--;
      else
        syntax_error(3);
    }
    if(!c||c==commentchar||(c==','&&par_cnt==0))
      break;
    s++;
  }
  if(par_cnt!=0)
    syntax_error(4);
  return s;
}

static char *get_label(char **start)
{
  char *labname=NULL;
  char *s=*start;

  if(labname=get_local_label(&s)){   /* local label? */
    if(*s!=':'){
      myfree(labname);
      labname=NULL;
    }
    else *start=s+1;
  }
  else if(ISIDSTART(*s)){            /* or global label? */
    s++;
    while(ISIDCHAR(*s)) s++;
    if(*s==':'){
      labname=cnvstr(*start,s-*start);
      *start=s+1;
    }
  }
  return labname;
}

static void prident(char *p,int len)
{
  int olen=len;
  while(len--)
    putchar(*p++);
  printf("(len=%d)",olen);
}

static taddr comma_constexpr(char **s)
{
  *s = skip(*s);
  if (**s == ',') {
    *s = skip(*s + 1);
    return parse_constexpr(s);
  }
  syntax_error(9);  /* comma expected */
  return 0;
}

static void add_const_datadef(section *s,taddr val,int size,int align)
{
  char buf[32];
  int len;
  operand *op;

  if (size <= 32) {
    len = sprintf(buf,"%ld",(long)val);
    op = new_operand();
    if (parse_operand(buf,len,op,DATA_OPERAND(size))) {
      atom *a = new_datadef_atom(size,op);

      a->align = align;
      add_atom(s,a);
    }
    else
      syntax_error(8);
  }
  else
    ierror(0);
}

static void handle_section(char *s)
{
  char *name,*attr;

  if(!(name=parse_name(&s)))
    return;
  if(*s==','){
    s=skip(s+1);
    attr=s;
    if(*s!='\"')
      syntax_error(7);
    else
      s++;
    attr=s;
    while(*s&&*s!='\"')
      s++;    
    attr=cnvstr(attr,s-attr);
    s=skip(s+1);
  }else{
    attr="";
    if(!strcmp(name,textname)) attr=textattr;
    if(!strcmp(name,dataname)) attr=dataattr;
    if(!strcmp(name,sdataname)) attr=sdataattr;
    if(!strcmp(name,sdata2name)) attr=sdata2attr;
    if(!strcmp(name,rodataname)) attr=rodataattr;
    if(!strcmp(name,bssname)) attr=bssattr;
    if(!strcmp(name,sbssname)) attr=sbssattr;
    if(!strcmp(name,tocdname)) attr=tocdattr;
  }

  new_section(name,attr,1);
  switch_section(name,attr);
  eol(s);
}

static void handle_org(char *s)
{
  if (*s == current_pc_char) {    /*  "* = * + <expr>" reserves bytes */
    s = skip(s+1);
    if (*s == '+') {
      add_atom(0,new_space_atom(parse_expr_tmplab(&s),1,0));
    }
    else {
      syntax_error(18);  /* syntax error */
      return;
    }
  }
  else {
    new_org(parse_constexpr(&s));
  }
  eol(s);
}

static void handle_file(char *s)
{
  char *name;
  if(*s!='\"'){
    syntax_error(7);
    return;
  }
  name=++s;
  while(*s&&*s!='\"')
    s++;
  if(*s!='\"')
    syntax_error(7);
  name=cnvstr(name,s-name);
  setfilename(name);
  eol(++s);
}

static int oplen(char *e,char *s)
{
  while(s!=e&&isspace((unsigned char)e[-1]))
    e--;
  return e-s;
}

static void handle_data(char *s,int size,int noalign)
{
  for (;;) {
    char *opstart = s;
    operand *op;
    dblock *db = NULL;

    if ((size==8 || size==16) && *s=='\"') {
      if (db = parse_string(&opstart,*s,size)) {
        add_atom(0,new_data_atom(db,1));
        s = opstart;
      }
    }
    if (!db) {
      op = new_operand();
      s = skip_operand(s);
      if (parse_operand(opstart,s-opstart,op,DATA_OPERAND(size))) {
        atom *a;

        a = new_datadef_atom(size,op);
        if (noalign)
          a->align=1;
        add_atom(0,a);
      }
      else
        syntax_error(8);  /* invalid data operand */
    }

    s = skip(s);
    if (*s == ',') {
      s = skip(s+1);
    }
    else if (*s==commentchar)
      break;
    else if (*s) {
      syntax_error(9);  /* , expected */
      return;
    }
    else
      break;
  }

  eol(s);
}

static void handle_equ(char *s)
{
  char *labname;
  symbol *label;

  if(!(labname=parse_identifier(&s))){
    syntax_error(10);  /* identifier expected */
    return;
  }
  s=skip(s);
  if(*s!=',')
    syntax_error(9);
  else
    s=skip(s+1);
  label=new_abs(labname,parse_expr_tmplab(&s));
  myfree(labname);
  eol(s);
}

static char *get_bind_name(symbol *s)
{
  if(s->flags&EXPORT)
    return "global";
  else if(s->flags&WEAK)
    return "weak";
  else if(s->flags&LOCAL)
    return "local";
  return "unknown";
}

static void do_binding(char *s,int bind)
{
  symbol *sym;
  char *name;

  while(1){
    if(!(name=parse_identifier(&s))){
      syntax_error(10);  /* identifier expected */
      return;
    }
    sym=new_import(name);
    myfree(name);
    if(sym->flags&(EXPORT|WEAK|LOCAL)!=0 &&
       sym->flags&(EXPORT|WEAK|LOCAL)!=bind)
      syntax_error(20,sym->name,get_bind_name(sym));  /* binding already set */
    else
      sym->flags|=bind;
    s=skip(s);
    if(*s!=',')
      break;
    s=skip(s+1);
  }
  eol(s);
}

static void handle_global(char *s)
{
  do_binding(s,EXPORT);
}

static void handle_weak(char *s)
{
  do_binding(s,WEAK);
}

static void handle_local(char *s)
{
  do_binding(s,LOCAL);
}

static void do_align(taddr align,expr *fill,taddr max)
/* @@@ 'max' alignment is not really supported at the moment */
{
  atom *a = new_space_atom(number_expr(0),1,fill);

  a->align = align;
  add_atom(0,a);
}

static void alignment(char *s,int mode)
{
  int align,max=0;
  expr *fill=0;

  align = parse_constexpr(&s);
  s = skip(s);
  if (*s == ',') {
    s = skip(s+1);
    if (*s != ',')
      fill = parse_expr_tmplab(&s);
    s = skip(s);
    if (*s == ',') {
      s = skip(s+1);
      max = parse_constexpr(&s);
    }
  }
  if (!mode)
    mode = CPU_DEF_ALIGN;
  if (mode==2 && align>63)
    syntax_error(23);  /* alignment too big */
  do_align(mode==1?align:(1<<align),fill,max);
  eol(s);
}

static void handle_align(char *s)
{
  alignment(s,0);
}

static void handle_balign(char *s)
{
  alignment(s,1);
}

static void handle_p2align(char *s)
{
  alignment(s,2);
}

static void handle_space(char *s)
{
  expr *space = parse_expr_tmplab(&s);
  expr *fill = 0;

  s = skip(s);
  if (*s == ',') {
    s = skip(s+1);
    fill = parse_expr_tmplab(&s);
  }
  add_atom(0,new_space_atom(space,1,fill));
  eol(s);
}

static void handle_size(char *s)
{
  char *name;
  symbol *sym;

  if(!(name=parse_identifier(&s))){
    syntax_error(10);  /* identifier expected */
    return;
  }
  sym=new_import(name);
  myfree(name);
  s=skip(s);
  if(*s==',')
    s=skip(s+1);
  else
    syntax_error(9);
  sym->size=parse_expr_tmplab(&s);
  eol(s);
}

static void handle_type(char *s)
{
  char *name;
  symbol *sym;

  if(!(name=parse_identifier(&s))){
    syntax_error(10);  /* identifier expected */
    return;
  }
  sym=new_import(name);
  myfree(name);
  s=skip(s);
  if(*s==',')
    s=skip(s+1);
  else
    syntax_error(9);
  if(!strncmp(s,"@object",7)){
    sym->flags|=TYPE_OBJECT;
    s=skip(s+7);
  }else if(!strncmp(s,"@function",9)){
    sym->flags|=TYPE_FUNCTION;
    s=skip(s+9);
  }else
    sym->flags|=parse_constexpr(&s);
  eol(s);
}

static void new_bss(char *s,int global)
{
  char *name;
  symbol *sym;
  atom *a;
  taddr size;
  section *bss;

  if(!(name=parse_identifier(&s))){
    syntax_error(10);  /* identifier expected */
    return;
  }
  size=comma_constexpr(&s);
  if(size<=sdlimit){
    if(!(bss=find_section(sbssname,sbssattr)))
      bss=new_section(sbssname,sbssattr,1);
  }
  else{
    if(!(bss=find_section(bssname,bssattr)))
      bss=new_section(bssname,bssattr,1);
  }
  sym=new_labsym(bss,name);
  sym->flags|=TYPE_OBJECT;
  if(global) sym->flags|=EXPORT;
  sym->size=number_expr(size);
  myfree(name);
  s=skip(s);
  if(*s==','){
    s=skip(s+1);
    sym->align=parse_constexpr(&s);
  }
  else
    sym->align=(size>=8)?8:4;
  a=new_label_atom(sym);
  if(sym->align)
    a->align=sym->align;
  add_atom(bss,a);
  a=new_space_atom(number_expr(size),1,0);
  if(sym->align)
    a->align=sym->align;
  add_atom(bss,a);
  eol(s);
}

static void handle_comm(char *s)
{
  char *name;
  symbol *sym;

  if (alloccommon){
    new_bss(s,1);
    return;
  }
  if(!(name=parse_identifier(&s))){
    syntax_error(10);  /* identifier expected */
    return;
  }
  sym=new_import(name);
  myfree(name);
  s=skip(s);
  if(*s==',')
    s=skip(s+1);
  else
    syntax_error(9);
  if (!(sym->size=parse_expr(&s)))
    return;
  simplify_expr(sym->size);
  if(sym->size->type!=NUM){
    syntax_error(12);
    return;
  }
  sym->flags|=COMMON|TYPE_OBJECT;
  s=skip(s);
  if(*s==','){
    s=skip(s+1);
    sym->align=parse_constexpr(&s);
  }
  else
    sym->align=(sym->size->c.val>=8)?8:4;
  eol(s);
} 

static void handle_lcomm(char *s)
{
  new_bss(s,0);
} 

static taddr new_stabstr(char *name)
{
  section *str;
  taddr index;
  dblock *db;

  if (!(str = find_section(stabstrname,stabstrattr)))
    ierror(0);
  index = str->pc;
  db = new_dblock();
  db->size = strlen(name) + 1;
  db->data = name;
  add_atom(str,new_data_atom(db,1));
  return index;
}

static void stab_entry(char *name,int type,int othr,int desc,char *s)
{
  section *stabs;

  if (!(stabs = find_section(stabname,stabattr))) {
    section *str;
    dblock *db;

    stabs = new_section(stabname,stabattr,4);
    if (!(str = find_section(stabstrname,stabstrattr))) {
      str = new_section(stabstrname,stabstrattr,1);
    }
    else {
      if (str->pc != 0)
        ierror(0);
    }
    /* first byte of .stabstr is 0 */
    add_atom(str,new_space_atom(number_expr(1),1,0)); 
    /* compilation unit header has to be patched by output module */
    new_stabstr(getfilename());
    db = new_dblock();
    db->size = 12;
    db->data = mymalloc(12);
    add_atom(stabs,new_data_atom(db,1));
  }

  add_const_datadef(stabs,name?new_stabstr(name):0,32,1);
  add_const_datadef(stabs,type,8,1);
  add_const_datadef(stabs,othr,8,1);
  add_const_datadef(stabs,desc,16,1);
  if (s) {
    operand *op = new_operand();
    int len = oplen(skip_operand(s),s);

    if (parse_operand(s,len,op,DATA_OPERAND(32))) {
      atom *a = new_datadef_atom(32,op);

      a->align = 1;
      add_atom(stabs,a);
    }
    else
      syntax_error(8);
  }
  else
    add_atom(stabs,new_space_atom(number_expr(4),1,0));  /* no value */
}

static void handle_stabs(char *s)
{
  char *name;
  int t,o,d;

  if (*s++ == '\"') {
    name = s;
    while (*s && *s!='\"')
      s++;
    name = cnvstr(name,s-name);
  }
  else {
    syntax_error(7);  /* " expected */
    return;
  }
  s++;
  t = comma_constexpr(&s);
  o = comma_constexpr(&s);
  d = comma_constexpr(&s);
  s = skip(s);
  if (*s == ',') {
    s = skip(s+1);
    stab_entry(name,t,o,d,s);
    s = skip_operand(s);
  }
  else
    syntax_error(9);
  eol(s);
}

static void handle_stabn(char *s)
{
  int t,o,d;

  t = parse_constexpr(&s);
  o = comma_constexpr(&s);
  d = comma_constexpr(&s);
  s = skip(s);
  if (*s == ',') {
    s = skip(s+1);
    stab_entry(NULL,t,o,d,s);
    s = skip_operand(s);
  }
  else
    syntax_error(9);
  eol(s);
}

static void handle_stabd(char *s)
{
  int t,o,d;

  t = parse_constexpr(&s);
  o = comma_constexpr(&s);
  d = comma_constexpr(&s);
  stab_entry(NULL,t,o,d,NULL);
  eol(s);
}

static void handle_incdir(char *s)
{
  char *name;

  if (name = parse_name(&s))
    new_include_path(name);
  eol(s);
}

static void handle_include(char *s)
{
  char *name;

  if (name = parse_name(&s)) {
    eol(s);
    include_source(name);
  }
}

static void handle_incbin(char *s)
{
  char *name;

  if (name = parse_name(&s)) {
    eol(s);
    include_binary_file(name,0,0);
  }
}

static void handle_rept(char *s)
{
  taddr cnt = parse_constexpr(&s);

  eol(s);
  new_repeat((int)cnt,
             nodotneeded?rept_dirlist:drept_dirlist,
             nodotneeded?endr_dirlist:dendr_dirlist);
}

static void handle_endr(char *s)
{
  syntax_error(19);  /* unexpected endr without rept */
}

static void handle_macro(char *s)
{
  char *name;

  if (name = parse_identifier(&s)) {
    s=skip(s);
    if(*s==commentchar)
      s=NULL;
    new_macro(name,nodotneeded?endm_dirlist:dendm_dirlist,s);
    myfree(name);
  }
  else
    syntax_error(10);  /* identifier expected */
}

static void handle_endm(char *s)
{
  syntax_error(13);  /* unexpected endm without macro */
}

static void ifdef(char *s,int b)
{
  char *name;
  symbol *sym;
  int result;

  if (!(name = get_local_label(&s))) {
    if (!(name = parse_identifier(&s))) {
      syntax_error(10);  /* identifier expected */
      return;
    }
  }
  if (sym = find_symbol(name))
    result = sym->type != IMPORT;
  else
    result = 0;
  myfree(name);
  cond[++clev] = result == b;
  eol(s);
}

static void handle_ifd(char *s)
{
  ifdef(s,1);
}

static void handle_ifnd(char *s)
{
  ifdef(s,0);
}

static void handle_ifb(char *s)
{
  s = skip(s);
  cond[++clev] = (*s=='\0' || *s==commentchar);
}

static void handle_ifnb(char *s)
{
  s = skip(s);
  cond[++clev] = (*s!='\0' && *s!=commentchar);
}

static void ifexp(char *s,int c)
{
  expr *condexp = parse_expr_tmplab(&s);
  taddr val;
  int b;

  if (eval_expr(condexp,&val,NULL,0)) {
    switch (c) {
      case 0: b = val == 0; break;
      case 1: b = val != 0; break;
      case 2: b = val > 0; break;
      case 3: b = val >= 0; break;
      case 4: b = val < 0; break;
      case 5: b = val <= 0; break;
      default: ierror(0); break;
    }
  }
  else {
    syntax_error(12);  /* expression must be constant */
    b = 0;
  }
  cond[++clev] = b;
  free_expr(condexp);
  eol(s);
}

static void handle_ifeq(char *s)
{
  ifexp(s,0);
}

static void handle_ifne(char *s)
{
  ifexp(s,1);
}

static void handle_ifgt(char *s)
{
  ifexp(s,2);
}

static void handle_ifge(char *s)
{
  ifexp(s,3);
}

static void handle_iflt(char *s)
{
  ifexp(s,4);
}

static void handle_ifle(char *s)
{
  ifexp(s,5);
}

static void handle_else(char *s)
{
  eol(s);
  if (clev > 0)
    cond[clev] = 0;
  else
    syntax_error(17);  /* else without if */
}

static void handle_endif(char *s)
{
  eol(s);
  if (clev > 0)
    clev--;
  else
    syntax_error(14);  /* endif without if */
}

static void handle_bsss(char *s)
{
  s = skip(s);
  if (*s!=0 && *s!=commentchar)	{
		new_bss(s,0);
	}
	else {
	  handle_section(bssname);
  	eol(s);
	}
}

static void handle_8bit(char *s){ handle_data(s,8,0); }
static void handle_16bit(char *s){ handle_data(s,16,0); }
static void handle_32bit(char *s){ handle_data(s,32,0); }
static void handle_64bit(char *s){ handle_data(s,64,0); }
static void handle_16bit_noalign(char *s){ handle_data(s,16,1); }
static void handle_32bit_noalign(char *s){ handle_data(s,32,1); }
static void handle_64bit_noalign(char *s){ handle_data(s,64,1); }
#if VASM_CPU_OIL
static void handle_string(char *s){ handle_data(s,8,0); }
#else
static void handle_string(char *s)
{
  handle_data(s,8,0);
  add_atom(0,new_space_atom(number_expr(1),1,0));  /* terminating zero */
}
#endif
static void handle_texts(char *s){ handle_section(textname);eol(s);}
static void handle_datas(char *s){ handle_section(dataname);eol(s);}
static void handle_sdatas(char *s){ handle_section(sdataname);eol(s);}
static void handle_sdata2s(char *s){ handle_section(sdata2name);eol(s);}
static void handle_rodatas(char *s){ handle_section(rodataname);eol(s);}
static void handle_sbsss(char *s){ handle_section(sbssname);eol(s);}
static void handle_tocds(char *s){ handle_section(tocdname);eol(s);}

static void handle_err(char *s)
{
  fail(s);
}

static void handle_fail(char *s)
{
  expr *condexp = parse_expr_tmplab(&s);
  taddr val;

  if (eval_expr(condexp,&val,NULL,0)) {
    if (val >= 500)
      syntax_error(21,(long long)val);
    else
      syntax_error(22,(long long)val);
  }
  else
    syntax_error(12);  /* expression must be constant */
  eol(s);
}

static void handle_title(char *s)
{
  char *t;
  s=skip(s);
  if(*s!='\"')
    syntax_error(7);
  else
    s++;
  t=s;
  while(*s&&*s!='\"')
    s++;
  set_list_title(t,s-t);
  if(*s!='\"')
    syntax_error(7);
  else
    s++;
  eol(s);
}

static void handle_ident(char *s)
{
  char *name;

  if(name=parse_name(&s))
    setfilename(name);
  eol(s);
}

static void handle_list(char *s)
{
  set_listing(1);
}

static void handle_nolist(char *s)
{
  set_listing(0);
}

struct {
  char *name;
  void (*func)(char *);
} directives[]={
  "org",handle_org,
  "section",handle_section,
  "string",handle_string,
  "byte",handle_8bit,
  "ascii",handle_8bit,
  "asciz",handle_string,
  "short",handle_16bit,
  "half",handle_16bit,
  "word",handle_32bit,
  "int",handle_32bit,
  "long",handle_32bit,
  "quad",handle_64bit,
  "2byte",handle_16bit_noalign,
  "uahalf",handle_16bit_noalign,
  "4byte",handle_32bit_noalign,
  "uaword",handle_32bit_noalign,
  "ualong",handle_32bit_noalign,
  "8byte",handle_64bit_noalign,
  "uaquad",handle_64bit_noalign,
  "text",handle_texts,
  "data",handle_datas,
  "bss",handle_bsss,
  "rodata",handle_rodatas,
  "sdata",handle_sdatas,
  "sdata2",handle_sdata2s,
  "sbss",handle_sbsss,
  "tocd",handle_tocds,
  "equ",handle_equ,
  "set",handle_equ,
  "global",handle_global,
  "globl",handle_global,
  "extern",handle_global,
  "weak",handle_weak,
  "local",handle_local,
  "align",handle_align,
  "balign",handle_balign,
  "p2align",handle_p2align,
  "space",handle_space,
  "skip",handle_space,
  "comm",handle_comm,
  "lcomm",handle_lcomm,
  "size",handle_size,
  "type",handle_type,
  "file",handle_file,
  "stabs",handle_stabs,
  "stabn",handle_stabn,
  "stabd",handle_stabd,
  "incdir",handle_incdir,
  "include",handle_include,
  "incbin",handle_incbin,
  "rept",handle_rept,
  "endr",handle_endr,
  "macro",handle_macro,
  "endm",handle_endm,
  "ifdef",handle_ifd,
  "ifndef",handle_ifnd,
  "ifb",handle_ifb,
  "ifnb",handle_ifnb,
  "if",handle_ifne,
  "ifeq",handle_ifeq,
  "ifne",handle_ifne,
  "ifgt",handle_ifgt,
  "ifge",handle_ifge,
  "iflt",handle_iflt,
  "ifle",handle_ifle,
  "else",handle_else,
  "endif",handle_endif,
  "abort",handle_err,
  "err",handle_err,
  "fail",handle_fail,
  "title",handle_title,
  "ident",handle_ident,
  "list",handle_list,
  "nolist",handle_nolist,
};

int dir_cnt=sizeof(directives)/sizeof(directives[0]);

/* checks for a valid directive, and return index when found, -1 otherwise */
static int check_directive(char **line)
{
  char *s,*name;
  hashdata data;

  s = skip(*line);
  if (!ISIDSTART(*s))
    return -1;
  name = s++;
  while (ISIDCHAR(*s))
    s++;
  if (*name == '.')
    name++;
  else if (!nodotneeded)
    return -1;
  if (!find_namelen(dirhash,name,s-name,&data))
    return -1;
  *line = s;
  return data.idx;
}

/* Handles assembly directives; returns non-zero if the line
   was a directive. */
static int handle_directive(char *line)
{
  int idx = check_directive(&line);

  if (idx >= 0) {
    directives[idx].func(skip(line));
    return 1;
  }
  return 0;
}

void parse(void)
{
  char *s,*line,*ext[MAX_QUALIFIERS?MAX_QUALIFIERS:1],*op[MAX_OPERANDS];
  char *labname,*start;
  int inst_len,ext_len[MAX_QUALIFIERS?MAX_QUALIFIERS:1],op_len[MAX_OPERANDS];
  int ext_cnt,op_cnt;
  instruction *ip;

  while (line=read_next_line()){
    if (clev >= MAXCONDLEV)
      syntax_error(16,clev);  /* nesting depth exceeded */

    /* # is always allowed as a comment at the beginning of a line */
    s = skip(line);
    if (*s == '#')
      continue;

    if (!cond[clev]) {
      /* skip source until ELSE or ENDIF */
      int idx;

      s = line;
      if (labname = get_label(&s))  /* skip label field */
        myfree(labname);
      idx = check_directive(&s);
      if (idx >= 0) {
        if (!strncmp(directives[idx].name,"if",2)) {
          ifnesting++;
        }
        else if (ifnesting==0 && !strncmp(directives[idx].name,"else",4)) {
          cond[clev] = 1;
        }
        else if (directives[idx].func == handle_endif) {
          if (ifnesting == 0) {
            if (clev > 0)
              clev--;
            else
              syntax_error(14);  /* endif without if */
          }
          else
            ifnesting--;
        }
      }
      continue;
    }

    s=skip(line);

    if(handle_directive(s))
      continue;

    /* skip spaces */
    s=skip(s);
    if(!*s||*s==commentchar)
      continue;

    if(labname=get_label(&s)){
      /* we have found a valid global or local label */
      add_atom(0,new_label_atom(new_labsym(0,labname)));
      s=skip(s);
      myfree(labname);
    }

    if(!*s||*s==commentchar)
      continue;

    s=skip(parse_cpu_special(s));
    if(*s==0||*s==commentchar)
      continue;

    if(handle_directive(s))
      continue;

    /* read mnemonic name */
    start=s;
    ext_cnt=0;
    if(!ISIDSTART(*s)){
      syntax_error(10);
      continue;
    }
#if MAX_QUALIFIERS==0
    while(*s&&!isspace((unsigned char)*s))
      s++;
    inst_len=s-start;
#else
    s=parse_instruction(s,&inst_len,ext,ext_len,&ext_cnt);
#endif
    s=skip(s);

    if(execute_macro(start,inst_len,ext,ext_len,ext_cnt,s,clev))
      continue;

    /* read operands, terminated by comma (unless in parentheses)  */
    op_cnt=0;
    while(*s&&*s!=commentchar&&op_cnt<MAX_OPERANDS){
      op[op_cnt]=s;
      s=skip_operand(s);
      op_len[op_cnt]=oplen(s,op[op_cnt]);
#if !ALLOW_EMPTY_OPS
      if(op_len[op_cnt]<=0)
        syntax_error(5);
      else
#endif
        op_cnt++;
      s=skip(s);
      if(*s!=','){
        break;
      }else{
        s=skip(s+1);
      }
    }      
    s=skip(s);
    if(*s!=0&&*s!=commentchar) syntax_error(6);
    ip=new_inst(start,inst_len,op_cnt,op,op_len);
#if MAX_QUALIFIERS>0
    if(ip){
      int i;
      for(i=0;i<ext_cnt;i++)
        ip->qualifiers[i]=cnvstr(ext[i],ext_len[i]);
      for(;i<MAX_QUALIFIERS;i++)
        ip->qualifiers[i]=0;
    }
#endif
    if(ip){
      add_atom(0,new_inst_atom(ip));
    }else
      ;
  }

  if (clev > 0)
    syntax_error(15);  /* if without endif */
}

char *const_prefix(char *s,int *base)
{
  if(!isdigit((unsigned char)*s)){
    *base=0;
    return s;
  }
  if(*s=='0'){
    if(s[1]=='x'||s[1]=='X'){
      *base=16;
      return s+2;
    }
    if(s[1]=='b'||s[1]=='B'){
      *base=2;
      return s+2;
    }    
    *base=8;
    return s;
  }
  *base=10;
  return s;
}

char *get_local_label(char **start)
/* local labels start with a '.' or end with '$': "1234$", ".1" */
{
  char *s = *start;
  char *name = NULL;

  if (*s == '.') {
    s++;
    while (isdigit((unsigned char)*s) || *s=='_')  /* '_' needed for '\@' */
      s++;
    if (s > (*start+1)) {
      name = make_local_label(NULL,0,*start,s-*start);
      *start = skip(s);
    }
  }
  else {
    while (isalnum((unsigned char)*s) || *s=='_')  /* '_' needed for '\@' */
      s++;
    if (s!=*start && *s=='$') {
      name = make_local_label(NULL,0,*start,s-*start);
      *start = skip(++s);
    }
  }
  return name;
}

int init_syntax()
{
  size_t i;
  hashdata data;
  dirhash=new_hashtable(0x200); /*FIXME: */
  for(i=0;i<dir_cnt;i++){
    data.idx=i;
    add_hashentry(dirhash,directives[i].name,data);
  }

#if defined(VASM_CPU_X86)
  current_pc_char = '.';
#endif  
  cond[0] = 1;
  clev = ifnesting = 0;

  namedmacparams = 1;  /* enabled named macro arguments, like gas */
  return 1;
}

int syntax_args(char *p)
{
  int i;

  if (!strcmp(p,"-nodotneeded")) {
    nodotneeded = 1;
    return 1;
  }
  else if (!strcmp(p,"-ac")) {
    alloccommon = 1;
    return 1;
  }
  else if (!strncmp(p,"-sdlimit=",9)) {
    i = atoi(p+9);
    sdlimit = (i<=0) ? -1 : i;
    return 1;
  }

  return 0;
}
