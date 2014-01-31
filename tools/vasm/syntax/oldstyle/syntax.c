/* syntax.c  syntax module for vasm */
/* (c) in 2002-2013 by Frank Wille */

#include "vasm.h"

/* The syntax module parses the input (read_next_line), handles
   assembly-directives (section, data-storage etc.) and parses
   mnemonics. Assembly instructions are split up in mnemonic name,
   qualifiers and operands. new_inst returns a matching instruction,
   if one exists.
   Routines for creating sections and adding atoms to sections will
   be provided by the main module.
*/

char *syntax_copyright="vasm oldstyle syntax module 0.11 (c) 2002-2013 Frank Wille";
hashtable *dirhash;

static char textname[]=".text",textattr[]="acrx";
static char dataname[]=".data",dataattr[]="adrw";
static char rodataname[]=".rodata",rodataattr[]="adr";
static char bssname[]=".bss",bssattr[]="aurw";

char commentchar=';';
char *defsectname = textname;
char *defsecttype = "acrwx";

static char endmname[] = ".endmacro";
static char endrname[] = ".endrepeat";
static char reptname[] = ".rept";
static char repeatname[] = ".repeat";
static struct namelen endm_dirlist[] = {
  { 4,&endmname[1] }, { 6,&endmname[1] }, { 8,&endmname[1] }, { 0,0 }
};
static struct namelen rept_dirlist[] = {
  { 4,&reptname[1] }, { 6,&repeatname[1] }, { 0,0 }
};
static struct namelen endr_dirlist[] = {
  { 4,&endrname[1] }, { 6,&endrname[1] }, { 9,&endrname[1] }, { 0,0 }
};
static struct namelen dendm_dirlist[] = {
  { 5,&endmname[0] }, { 7,&endmname[0] }, { 9,&endmname[0] }, { 0,0 }
};
static struct namelen drept_dirlist[] = {
  { 5,&reptname[0] }, { 7,&repeatname[0] }, { 0,0 }
};
static struct namelen dendr_dirlist[] = {
  { 5,&endrname[0] }, { 7,&endrname[0] }, { 10,&endrname[0] }, { 0,0 }
};

static int dotdirectives = 0;
static int autoexport = 0;
static int parse_end = 0;

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
  int par_cnt = 0;
  char c;

  for (;;) {
    c = *s;
    if (START_PARENTH(c))
      par_cnt++;
    if (END_PARENTH(c)) {
      if (par_cnt>0)
        par_cnt--;
      else
        syntax_error(3);  /* too many closing parentheses */
    }
    if(!c || c==commentchar || (c==',' && par_cnt==0))
      break;
    s++;
  }
  if(par_cnt != 0)
    syntax_error(4);  /* missing closing parentheses */
  return s;
}


#define handle_data(a,b) handle_data_offset(a,b,0)

static void handle_data_offset(char *s,int size,int offset)
{
  for (;;) {
    char *opstart = s;
    operand *op;
    dblock *db = NULL;

    if (size==8 && (*s=='\"' || *s=='\'')) {
      if (db = parse_string(&opstart,*s,8)) {
        if (offset != 0) {
          int i;

          for (i=0; i<db->size; i++)
            db->data[i] = db->data[i] + offset;
        }
        add_atom(0,new_data_atom(db,1));
        s = opstart;
      }
    }
    if (!db) {
      op = new_operand();
      s = skip_operand(s);
      if (parse_operand(opstart,s-opstart,op,DATA_OPERAND(size))) {
        atom *a;

        if (offset != 0)
          op->value = make_expr(ADD,number_expr(offset),op->value);
        a = new_datadef_atom(abs(size),op);
        a->align = 1;
        add_atom(0,a);
      }
      else
        syntax_error(8);  /* invalid data operand */
    }

    s = skip(s);
    if (*s == ',') {
      s = skip(s+1);
    }
    else if (*s == commentchar) {
      break;
    }
    else if (*s) {
      syntax_error(9);  /* , expected */
      return;
    }
    else
      break;
  }

  eol(s);
}


static void handle_text(char *s)
{
  char *opstart = s;
  operand *op;
  dblock *db = NULL;

  if (db = parse_string(&opstart,*s,8)) {
    add_atom(0,new_data_atom(db,1));
    s = opstart;
  }
  if (!db) {
    op = new_operand();
    s = skip_operand(s);
    if (parse_operand(opstart,s-opstart,op,DATA_OPERAND(8))) {
      atom *a;

      a = new_datadef_atom(8,op);
      a->align = 1;
      add_atom(0,a);
    }
    else
      syntax_error(8);  /* invalid data operand */
  }
  eol(s);
}


static void handle_d8(char *s)
{
  handle_data(s,8);
}


static void handle_d16(char *s)
{
  handle_data(s,16);
}


static void handle_d24(char *s)
{
  handle_data(s,24);
}


static void handle_d32(char *s)
{
  handle_data(s,32);
}


static void handle_d8_offset(char *s)
{
  taddr offs = parse_constexpr(&s);

  s = skip(s);
  if (*s == ',') {
    s = skip(s+1);
    handle_data_offset(s,8,offs);
  }
  else
    syntax_error(9);  /* , expected */
}


static void do_alignment(taddr align,expr *offset)
{
  atom *a = new_space_atom(offset,1,0);

  a->align = align;
  add_atom(0,a);
}


static void handle_align(char *s)
{
  taddr a = parse_constexpr(&s);

  if (a > 63)
    syntax_error(21);  /* bad alignment */
  do_alignment(1LL<<a,number_expr(0));
  eol(s);
}


static void handle_even(char *s)
{
  do_alignment(2,number_expr(0));
  eol(s);
}


static void do_space(int size,expr *cnt,expr *fill)
{
  add_atom(0,new_space_atom(cnt,size>>3,fill));
}


static void handle_space(char *s,int size)
{
  expr *cnt,*fill=0;

  cnt = parse_expr_tmplab(&s);
  s = skip(s);
  if (*s == ',') {
    s = skip(s+1);
    fill = parse_expr_tmplab(&s);
  }
  do_space(size,cnt,fill);
  eol(s);
}


static void handle_fixedspc1(char *s)
{
  do_space(8,number_expr(1),0);
  eol(s);
}


static void handle_fixedspc2(char *s)
{
  do_space(8,number_expr(2),0);
  eol(s);
}


static void handle_spc8(char *s)
{
  handle_space(s,8);
}


static void handle_spc16(char *s)
{
  handle_space(s,16);
}


#if 0
static void handle_spc24(char *s)
{
  handle_space(s,24);
}


static void handle_spc32(char *s)
{
  handle_space(s,32);
}
#endif


static void handle_string(char *s)
{
  handle_data(s,8);  
  add_atom(0,new_space_atom(number_expr(1),1,0));  /* terminating zero */
}


static void handle_end(char *s)
{
  parse_end = 1;
  eol(s);
}


static void handle_fail(char *s)
{
  fail(s);
}


static void handle_org(char *s)
{
  if (*s == current_pc_char) {
    char *s2 = skip(s+1);

    if (*s2++ == '+') {
      handle_space(skip(s2),8);  /*  "* = * + <expr>" to reserves bytes */
      return;
    }
  }
  new_org(parse_constexpr(&s));
  eol(s);
}


static void handle_rorg(char *s)
{
  add_atom(0,new_rorg_atom(parse_constexpr(&s)));
  eol(s);
}
  

static void handle_rend(char *s)
{
  add_atom(0,new_rorgend_atom());
  eol(s);
}
  

static void handle_section(char *s)
{
  char *name,*attr;

  if (!(name=parse_name(&s)))
    return;
  if (*s==',') {
    s = skip(s+1);
    attr = s;
    if (*s!= '\"')
      syntax_error(7,'\"');  /* " expected */
    else
      s++;
    attr = s;
    while (*s&&*s!='\"')
      s++;    
    attr = cnvstr(attr,s-attr);
    s = skip(s+1);
  }
  else {
    if (!strcmp(name,textname)) attr = textattr;
    if (!strcmp(name,dataname)) attr = dataattr;
    if (!strcmp(name,rodataname)) attr = rodataattr;
    if (!strcmp(name,bssname)) attr = bssattr;
    else attr = defsecttype;
  }

  new_section(name,attr,1);
  switch_section(name,attr);
  eol(s);
}


static char *get_bind_name(symbol *s)
{
  if (s->flags&EXPORT)
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

  while (1) {
    if (!(name=parse_identifier(&s)))
      return;
    sym = new_import(name);
    myfree(name);
    if (sym->flags&(EXPORT|WEAK|LOCAL)!=0 &&
        sym->flags&(EXPORT|WEAK|LOCAL)!=bind)
      syntax_error(20,sym->name,get_bind_name(sym));  /* binding already set */
    else
      sym->flags |= bind;
    s = skip(s);
    if (*s != ',')
      break;
    s = skip(s+1);
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


static void ifused(char *s, int b)
{
  char *name;
  symbol *sym;
  int result;

  if (!(name = parse_identifier(&s))) {
      syntax_error(10);  /* identifier expected */
      return;
  }

  if (sym = find_symbol(name)) {
    if (sym->type != IMPORT) {
      syntax_error(22,name);
      result = 0;
    }
    else
      result = 1;
  }
  else
    result = 0;

  myfree(name);
  cond[++clev] = result == b;
  eol(s);
}


static void handle_ifused(char *s)
{
  ifused(s,1);
}


static void handle_ifnused(char *s)
{
  ifused(s,0);
}


static void handle_ifd(char *s)
{
  ifdef(s,1);
}


static void handle_ifnd(char *s)
{
  ifdef(s,0);
}


static char *ifexp(char *s,int c)
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
  return s;
}


static void handle_ifeq(char *s)
{
  eol(ifexp(s,0));
}


static void handle_ifne(char *s)
{
  eol(ifexp(s,1));
}


static void handle_ifgt(char *s)
{
  eol(ifexp(s,2));
}


static void handle_ifge(char *s)
{
  eol(ifexp(s,3));
}


static void handle_iflt(char *s)
{
  eol(ifexp(s,4));
}


static void handle_ifle(char *s)
{
  eol(ifexp(s,5));
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


static void handle_assert(char *s)
{
  char *expstr,*msgstr;
  size_t explen;
  expr *aexp;
  atom *a;

  expstr = skip(s);
  aexp = parse_expr(&s);
  explen = s - expstr;
  s = skip(s);
  if (*s == ',') {
    s = skip(s+1);
    msgstr = parse_name(&s);
  }
  else
    msgstr = NULL;

  a = new_assert_atom(aexp,cnvstr(expstr,explen),msgstr);
  add_atom(0,a);
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
  long delta = 0;
  unsigned long nbbytes = 0;

  if (name = parse_name(&s)) {
    s = skip(s);
    if (*s == ',') {
      s = skip(s+1);
      delta = parse_constexpr(&s);
      if (delta < 0)
        delta = 0;
      s = skip(s);
      if (*s == ',') {
        s = skip(s+1);
        nbbytes = parse_constexpr(&s);
      }
    }
    eol(s);
    include_binary_file(name,delta,nbbytes);
  }
}


static void handle_rept(char *s)
{
  taddr cnt = parse_constexpr(&s);

  eol(s);
  new_repeat((int)cnt,
             dotdirectives?drept_dirlist:rept_dirlist,
             dotdirectives?dendr_dirlist:endr_dirlist);
}


static void handle_endr(char *s)
{
  syntax_error(19);  /* unexpected endr without rept */
}


static void handle_macro(char *s)
{
  char *name;

  if (name = parse_identifier(&s)) {
    s = skip(s);
    if (*s == ',') {  /* named macro arguments are given? */
      s++;
    }
    else {
      eol(s);
      s = NULL;
    }
    new_macro(name,dotdirectives?dendm_dirlist:endm_dirlist,s);
    myfree(name);
  }
  else
    syntax_error(10);  /* identifier expected */
}


static void handle_endm(char *s)
{
  syntax_error(18);  /* unexpected endm without macro */
}


static void handle_defc(char *s)
{
  char *name;

  s = skip(s);
  name = parse_identifier(&s);
  if ( name != NULL ) {
    s = skip(s);
    if ( *s == '=' ) {
      s = skip(s+1);
      new_abs(name,parse_expr_tmplab(&s));
    }
    myfree(name);
  }
  else
    syntax_error(10);
}


static void handle_list(char *s)
{
  set_listing(1);
}


static void handle_nolist(char *s)
{
  set_listing(0);
}


static void handle_struct(char *s)
{
  char *name;

  if (name = parse_identifier(&s)) {
    s = skip(s);
    eol(s);
    if (new_structure(name))
      current_section->flags |= LABELS_ARE_LOCAL;
    myfree(name);
  }
  else
    syntax_error(10);  /* identifier expected */
}


static void handle_endstruct(char *s)
{
  section *prevsec;
  symbol *szlabel;

  if (end_structure(&prevsec)) {
    /* create the structure name as label defining the structure size */
    current_section->flags &= ~LABELS_ARE_LOCAL;
    szlabel = new_labsym(0,current_section->name);
    add_atom(0,new_label_atom(szlabel));
    /* end structure declaration by switching to previous section */
    current_section = prevsec;
  }
  eol(s);
}


struct {
  char *name;
  void (*func)(char *);
} directives[] = {
  "org",handle_org,
  "rorg",handle_rorg,
  "rend",handle_rend,
  "phase",handle_rorg,
  "dephase",handle_rend,
  "align",handle_align,
  "even",handle_even,
  "byte",handle_d8,
  "db",handle_d8,
  "dfb",handle_d8,
  "defb",handle_d8,
  "asc",handle_d8,
  "data",handle_d8,
  "defm",handle_text,
  "text",handle_text,
  "wor",handle_d16,
  "word",handle_d16,
  "addr",handle_d16,
  "dw",handle_d16,
  "dfw",handle_d16,
  "defw",handle_d16,
  "abyte",handle_d8_offset,
  "ds",handle_spc8,
  "dsb",handle_spc8,
  "fill",handle_spc8,
  "reserve",handle_spc8,
  "spc",handle_spc8,
  "dsw",handle_spc16,
  "blk",handle_spc8,
  "blkw",handle_spc16,
  "dc",handle_spc8,
  "byt",handle_fixedspc1,
  "wrd",handle_fixedspc2,
  "assert",handle_assert,
  "ifdef",handle_ifd,
  "ifndef",handle_ifnd,
  "if",handle_ifne,
  "ifeq",handle_ifeq,
  "ifne",handle_ifne,
  "ifgt",handle_ifgt,
  "ifge",handle_ifge,
  "iflt",handle_iflt,
  "ifle",handle_ifle,
  "ifused",handle_ifused,
  "ifnused",handle_ifnused,
  "else",handle_else,
  "el",handle_else,
  "endif",handle_endif,
#if !defined(VASM_CPU_Z80)
  "ei",handle_endif,  /* Clashes with z80 opcode */
#endif
  "incbin",handle_incbin,
  "mdat",handle_incbin,
  "incdir",handle_incdir,
  "include",handle_include,
  "rept",handle_rept,
  "repeat",handle_rept,
  "endr",handle_endr,
  "endrep",handle_endr,
  "endrepeat",handle_endr,
  "mac",handle_macro,
  "macro",handle_macro,
  "endm",handle_endm,
  "endmac",handle_endm,
  "endmacro",handle_endm,
  "end",handle_end,
  "fail",handle_fail,
  "section",handle_section,
  "binary",handle_incbin,
  "defs",handle_spc8,
  "defp",handle_d24,
  "defl",handle_d32,
  "defc",handle_defc,
  "xdef",handle_global,
  "xref",handle_global,
  "lib",handle_global,
  "xlib",handle_global,
  "global",handle_global,
  "extern",handle_global,
  "local",handle_local,
  "weak",handle_weak,
  "ascii",handle_string,
  "asciiz",handle_string,
  "string",handle_string,
  "list",handle_list,
  "nolist",handle_nolist,
  "struct",handle_struct,
  "structure",handle_struct,
  "endstruct",handle_endstruct,
  "endstructure",handle_endstruct,
};

int dir_cnt = sizeof(directives) / sizeof(directives[0]);


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
  if (*name=='.' && dotdirectives)
    name++;
  if (!find_namelen_nc(dirhash,name,s-name,&data))
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


static int oplen(char *e,char *s)
{
  while(s!=e&&isspace((unsigned char)e[-1]))
    e--;
  return e-s;
}


/* When a structure with this name exists, insert its atoms and either
   initialize with new values or accept its default values. */
static int execute_struct(char *name,int name_len,char *s)
{
  section *str;
  atom *p;

  str = find_structure(name,name_len);
  if (str == NULL)
    return 0;

  for (p=str->first; p; p=p->next) {
    atom *new;
    char *opp;
    int opl;

    if (p->type==DATA || p->type==SPACE || p->type==DATADEF) {
      opp = s = skip(s);
      s = skip_operand(s);
      opl = oplen(s,opp);

      if (opl > 0) {
        /* initialize this atom with a new expression */

        if (p->type == DATADEF) {
          /* parse a new data operand of the declared bitsize */
          operand *op;

          op = new_operand();
          if (parse_operand(opp,opl,op,
                            DATA_OPERAND(p->content.defb->bitsize))) {
            new = new_datadef_atom(p->content.defb->bitsize,op);
            new->align = p->align;
            add_atom(0,new);
          }
          else
            syntax_error(8);  /* invalid data operand */
        }
        else if (p->type == SPACE) {
          /* parse the fill expression for this space */
          new = clone_atom(p);
          new->content.sb = new_sblock(p->content.sb->space_exp,
                                       p->content.sb->size,
                                       parse_expr_tmplab(&opp));
          new->content.sb->space = p->content.sb->space;
          add_atom(0,new);
        }
        else {
          /* parse constant data - probably a string, or a single constant */
          dblock *db;

          db = new_dblock();
          db->size = p->content.db->size;
          db->data = db->size ? mycalloc(db->size) : NULL;
          if (db->data) {
            if (*opp=='\"' || *opp=='\'') {
              dblock *strdb;

              strdb = parse_string(&opp,*opp,8);
              if (strdb->size) {
                if (strdb->size > db->size)
                  syntax_error(24,strdb->size-db->size);  /* cut last chars */
                memcpy(db->data,strdb->data,
                       strdb->size > db->size ? db->size : strdb->size);
                myfree(strdb->data);
              }
              myfree(strdb);
            }
            else {
              taddr val = parse_constexpr(&opp);
              void *p;

              if (db->size > sizeof(taddr) && BIGENDIAN)
                p = db->data + db->size - sizeof(taddr);
              else
                p = db->data;
              setval(BIGENDIAN,p,sizeof(taddr),val);
            }
          }
          add_atom(0,new_data_atom(db,p->align));
        }
      }
      else {
        /* empty: use default values from original atom */
        add_atom(0,clone_atom(p));
      }

      s = skip(s);
      if (*s == ',')
        s++;
    }
    else if (p->type == INSTRUCTION)
      syntax_error(23);  /* skipping instruction in struct init */

    /* other atoms are silently ignored */
  }

  eol(s);
  return 1;
}


void parse(void)
{
  char *s,*line,*inst,*labname;
  char *ext[MAX_QUALIFIERS?MAX_QUALIFIERS:1];
  char *op[MAX_OPERANDS];
  int ext_len[MAX_QUALIFIERS?MAX_QUALIFIERS:1];
  int op_len[MAX_OPERANDS];
  int glob,ext_cnt,op_cnt,inst_len;
  instruction *ip;

  while (line = read_next_line()) {
    if (parse_end)
      continue;
    if (clev >= MAXCONDLEV)
      syntax_error(16,clev);  /* nesting depth exceeded */

    if (!cond[clev]) {
      /* skip source until ELSE or ENDIF */
      int idx;

      s = line;
      idx = check_directive(&s);
      if (idx >= 0) {
        if (!strncmp(directives[idx].name,"if",2)) {
          ifnesting++;
        }
        else if (ifnesting==0 && directives[idx].func == handle_else) {
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

    s = line;

    glob = 0;
    labname = get_local_label(&s); /* local label? */

    if (!labname && (ISIDSTART(*s) || *s==current_pc_char)) { /* global l.? */
      s++;
      while (ISIDCHAR(*s))
        s++;
      if (*line==current_pc_char && s-line!=1) {
        syntax_error(10);  /* identifier expected */
        continue;
      }
      labname = cnvstr(line,s-line);
      s = skip(s);
      glob = 1;
    }

    if (labname) {
      /* we have found a global or local label at first column */
      symbol *label,*labsym;
      int equlen = 0;

      if (!strnicmp(s,"equ",3) && isspace((unsigned char)*(s+3)))
        equlen = 3;
      else if (!strnicmp(s,"eq",2) && isspace((unsigned char)*(s+2)))
        equlen = 2;
      else if (*s == '=')
        equlen = 1;

      if (equlen) {
        /* found a kind of equate directive */
        if (*labname == current_pc_char) {
          handle_org(skip(s+equlen));
          continue;
        }
        else {
          if (labsym = find_symbol(labname)) {
            if (labsym->type != IMPORT)
              syntax_error(13);  /* repeatedly defined symbol */
          }
          s = skip(s+equlen);
          label = new_abs(labname,parse_expr_tmplab(&s));
        }
      }
      else if (!strnicmp(s,"set",3) && isspace((unsigned char)*(s+3))) {
        /* SET allows redefinitions */
        if (*labname == current_pc_char) {
          syntax_error(10);  /* identifier expected */
        }
        else {
          s = skip(s+3);
          label = new_abs(labname,parse_expr_tmplab(&s));
        }
      }
      else if (!strnicmp(s,"mac",3) &&
               (isspace((unsigned char)*(s+3)) || *(s+3)=='\0') ||
               !strnicmp(s,"macro",5) &&
               (isspace((unsigned char)*(s+5)) || *(s+5)=='\0')) {
        char *params = skip(s + (*(s+3)=='r'?5:3));

        s = line;
        myfree(labname);
        if (!(labname = parse_identifier(&s)))
          ierror(0);
        new_macro(labname,dotdirectives?dendm_dirlist:endm_dirlist,params);
        myfree(labname);
        continue;
      }
      else {
        /* it's just a label */
        label = new_labsym(0,labname);
        add_atom(0,new_label_atom(label));
        if (*s == ':')	/* optionally terminated by a colon */
          s = skip(s+1);
      }
      myfree(labname);

      if (glob && autoexport)
          label->flags |= EXPORT;
    }

    /* check for directives first */
    s = skip(s);
    if (*s==commentchar)
      continue;

    s = parse_cpu_special(s);
    if (*s=='\0' || *s==commentchar)
      continue;

    if (*s==current_pc_char && *(s+1)=='=') {   /* "*=" org directive */ 
      handle_org(skip(s+2));
      continue;
    }
    if (handle_directive(s))
      continue;

    s = skip(s);
    if (*s=='\0' || *s==commentchar)
      continue;

    /* read mnemonic name */
    inst = s;
    ext_cnt = 0;
    if (!ISIDSTART(*s)) {
      syntax_error(10);  /* identifier expected */
      continue;
    }
#if MAX_QUALIFIERS==0
    while (*s && !isspace((unsigned char)*s))
      s++;
    inst_len = s - inst;
#else
    s = parse_instruction(s,&inst_len,ext,ext_len,&ext_cnt);
#endif
    if (!isspace((unsigned char)*s) && *s!='\0')
      syntax_error(2);  /* no space before operands */
    s = skip(s);

    if (execute_macro(inst,inst_len,ext,ext_len,ext_cnt,s,clev))
      continue;
    if (execute_struct(inst,inst_len,s))
      continue;

    /* read operands, terminated by comma (unless in parentheses)  */
    op_cnt = 0;
    while (*s && *s!=commentchar && op_cnt<MAX_OPERANDS) {
      op[op_cnt] = s;
      s = skip_operand(s);
      op_len[op_cnt] = oplen(s,op[op_cnt]);
#if !ALLOW_EMPTY_OPS
      if (op_len[op_cnt] <= 0)
        syntax_error(5);  /* missing operand */
      else
#endif
        op_cnt++;
      s = skip(s);
      if (*s != ',')
        break;
      else
        s = skip(s+1);
    }      
    s = skip(s);
    if (*s!='\0' && *s!=commentchar)
      syntax_error(6);

    ip = new_inst(inst,inst_len,op_cnt,op,op_len);

#if MAX_QUALIFIERS>0
    if (ip) {
      int i;

      for (i=0; i<ext_cnt; i++)
        ip->qualifiers[i] = cnvstr(ext[i],ext_len[i]);
      for(; i<MAX_QUALIFIERS; i++)
        ip->qualifiers[i] = NULL;
    }
#endif

    if (ip)
      add_atom(0,new_inst_atom(ip));
  }

  if (clev > 0)
    syntax_error(15);  /* if without endif */
}


char *const_prefix(char *s,int *base)
{
  if (isdigit((unsigned char)*s)) {
    if (*s == '0') {
      if (s[1]=='x' || s[1]=='X'){
        *base = 16;
        return s+2;
      }
      if (s[1]=='b' || s[1]=='B'){
        *base = 2;
        return s+2;
      }    
      *base = 8;
      return s;
    } 
    else if (*(s+1)=='#' && *s>='2') {
      *base = *s & 0xf;
      return s+2;
    }
    else {
      *base = 10;
      return s;
    }
  }

  if (*s=='$' && isxdigit((unsigned char)s[1])) {
    *base = 16;
    return s+1;
  }
#if defined(VASM_CPU_Z80)
  if ((*s=='&' || *s=='#') && isxdigit((unsigned char)s[1])) {
    *base = 16;
    return s+1;
  }
#endif
  if (*s=='@') {
#if defined(VASM_CPU_Z80)
    *base = 2;
#else
    *base = 8;
#endif
    return s+1;
  }
  if (*s == '%') {
    *base = 2;
    return s+1;
  }
  *base = 0;
  return s;
}


static char *skip_local(char *p)
{
  char *s;

  if (ISIDSTART(*p) || isdigit((unsigned char)*p)) {  /* may start with digit */
    s = p++;
    while (ISIDCHAR(*p))
      p++;
  }
  else
    p = NULL;

  return p;
}


char *get_local_label(char **start)
/* Local labels start with a '.' or end with '$': "1234$", ".1" */
{
  char *s,*p,*name;

  name = NULL;
  s = *start;
  p = skip_local(s);

  if (p!=NULL && *p=='.' && ISIDCHAR(*(p+1)) &&
      ISIDSTART(*s) && *s!='.' && *(p-1)!='$') {
    /* skip local part of global.local label */
    s = p + 1;
    p = skip_local(p);
    name = make_local_label(*start,(s-1)-*start,s,p-s);
    *start = skip(p);
  }
  else if (p!=NULL && p>(s+1) && *s=='.') {  /* .label */
    s++;
    name = make_local_label(NULL,0,s,p-s);
    *start = skip(p);
  }
  else if (p!=NULL && p>s && *p=='$') { /* label$ */
    p++;
    name = make_local_label(NULL,0,s,p-s);
    *start = skip(p);
  }

  return name;
}


int init_syntax()
{
  size_t i;
  hashdata data;

  dirhash = new_hashtable(0x200); /* @@@ */
  for (i=0; i<dir_cnt; i++) {
    data.idx = i;
    add_hashentry(dirhash,directives[i].name,data);
  }
  
  current_pc_char = '*';
  cond[0] = 1;
  clev = ifnesting = 0;

  /* Allow up to 36 named macro arguments. Enabling named arguments */
  /* means that \a..\z are disabled. \1..\9 still work in parallel. */
  namedmacparams = 1;
  maxmacparams = 36;
  return 1;
}


int syntax_args(char *p)
{
  if (!strcmp(p,"-dotdir")) {
    dotdirectives = 1;
    return 1;
  }
  else if (!strcmp(p,"-autoexp")) {
    autoexport = 1;
    return 1;
  }
  return 0;
}
