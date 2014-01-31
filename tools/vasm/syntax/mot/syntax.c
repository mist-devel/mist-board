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

char *syntax_copyright="vasm motorola syntax module 3.4a (c) 2002-2013 Frank Wille";
hashtable *dirhash;
char commentchar = ';';

static char code_name[] = "CODE";
static char data_name[] = "DATA";
static char bss_name[] = "BSS";
static char code_type[] = "acrx";
static char data_type[] = "adrw";
static char bss_type[] = "aurw";
static char rs_name[] = "__RS";
static char so_name[] = "__SO";
static char fo_name[] = "__FO";
char *defsectname = code_name;
char *defsecttype = code_type;

static struct namelen endm_dirlist[] = {
  { 4,"endm" }, { 0,0 }
};
static struct namelen rept_dirlist[] = {
  { 4,"rept" }, { 0,0 }
};
static struct namelen endr_dirlist[] = {
  { 4,"endr" }, { 0,0 }
};
static struct namelen erem_dirlist[] = {
  { 4,"erem" }, { 0,0 }
};

static int align_data = 0;
static int phxass_compat = 0;
static int allow_spaces = 0;
static int dot_idchar = 0;
static char local_char = '.';

static int parse_end = 0;

#define MAXCONDLEV 63
static char cond[MAXCONDLEV+1];
static char *condsrc[MAXCONDLEV+1];
static int condline[MAXCONDLEV+1];
static int clev,ifnesting;


char *skip(char *s)
{
  while (isspace((unsigned char )*s))
    s++;
  return s;
}


/* check for end of line, issue error, if not */
void eol(char *s)
{
  if (allow_spaces) {
    s = skip(s);
    if (*s!='\0' && *s!=commentchar)
      syntax_error(6);
  }
  else {
    if (*s!='\0' && *s!=commentchar && !isspace((unsigned char)*s))
      syntax_error(6);
  }
}


int isidchar(char c)
{
  if (isalnum((unsigned char)c) || c=='_' || c=='$' || c=='%')
    return 1;
  if (dot_idchar && c=='.')
    return 1;
  return 0;
}


char *chkidend(char *start,char *end)
{
  if (dot_idchar && (end-start)>2 && *(end-2)=='.') {
    char c = tolower((unsigned char)*(end-1));

    if (c=='b' || c=='w' || c=='l')
      return end - 2;	/* .b/.w/.l extension is not part of identifier */
  }
  return end;
}


char *exp_skip(char *s)
{
  if (allow_spaces && !phxass_compat) {
    return skip(s);
  }
  else {
    if (isspace((unsigned char)*s))
      *s = '\0';  /* rest of operand is ignored */
  }
  return s;
}


char *skip_operand(char *s)
{
  int par_cnt = 0;
  char c;

  for (;;) {
    s = exp_skip(s);
    c = *s;

    if (START_PARENTH(c)) {
      par_cnt++;
    }
    else if (END_PARENTH(c)) {
      if (par_cnt>0)
        par_cnt--;
      else
        syntax_error(3);  /* too many closing parentheses */
    }
    else if (c=='\'' || c=='\"')
      s = skip_string(s,c,NULL) - 1;
    else if (!c || (par_cnt==0 && (c==',' || c==commentchar)))
      break;

    s++;
  }

  if (par_cnt != 0)
    syntax_error(4);  /* missing closing parentheses */
  return s;
}


/* establish a new level of condititional assembly */
static void new_clev(char flag)
{
  if (++clev >= MAXCONDLEV)
    syntax_error(19,clev);  /* nesting depth exceeded */

  cond[clev] = flag;
  condsrc[clev] = cur_src->name;
  condline[clev] = cur_src->line;
}


static int check_sym_defined(char *symname)
{
  symbol *sym;

  if (sym = find_symbol(symname)) {
    if (sym->type != IMPORT) {
      syntax_error(14);  /* repeatedly defined symbol */
      return 1;
    }
  }
  return 0;
}


/* assign value of current struct- or frame-offset symbol to an abs-symbol,
   or just increment/decrement when equname is NULL */
static symbol *new_setoffset_size(char *equname,char *symname,
                                  char **s,int dir,taddr size)
{
  symbol *sym,*equsym;
  expr *new;

  if (equname) {
    if (check_sym_defined(equname))
      return NULL;
  }

  /* get current offset symbol expression, then increment or decrement it */
  sym = internal_abs(symname);
  if (**s!='\0' && **s!=commentchar) {
    /* make a new expression out of the parsed expression multiplied by size
       and add to or subtract it from the current symbol's expression */
    new = make_expr(MUL,parse_expr_tmplab(s),number_expr(size));
    simplify_expr(new);
    new = make_expr(dir>0 ? ADD : SUB,sym->expr,new);
  }
  else
    new = sym->expr;

  /* assign expression to equ-symbol and change exp. of the offset-symbol */
  if (equname)
    equsym = new_abs(equname,dir>0 ? copy_tree(sym->expr) : copy_tree(new));
  else
    equsym = NULL;

  simplify_expr(new);
  sym->expr = new;
  return equsym;
}


/* assign value of current struct- or frame-offset symbol to an abs-symbol,
   determine operation size from directive extension first */
static symbol *new_setoffset(char *equname,char **s,char *symname,int dir)
{
  taddr size = 1;
  char *start = *s;
  char ext;

  /* get extension character and proceed to operand */
  if (*(start+2) == '.') {
    ext = tolower((unsigned char)*(start+3));
    *s = skip(start+4);
    switch (ext) {
      case 'b':
        break;
      case 'w':
        size = 2;
        break;
      case 'l':
      case 's':
        size = 4;
        break;
      case 'q':
      case 'd':
        size = 8;
        break;
      case 'x':
        size = 12;
        break;
      default:
        syntax_error(1);  /* invalid extension */
        break;
    }
  }
  else {
    size = 2;  /* defaults to 'w' extension when missing */
    *s = skip(start+2);
  }

  return new_setoffset_size(equname,symname,s,dir,size);
}


static void do_space(int size,expr *cnt,expr *fill)
{
  atom *a;

  a = new_space_atom(cnt,size>>3,fill);
  a->align = align_data ? DATA_ALIGN(size) : 1;
  add_atom(0,a);
}


static void handle_space(char *s,int size)
{
  do_space(size,parse_expr_tmplab(&s),0);
}


static char *read_sec_attr(char *attr,char *s)
{
  char *type = s;

  if (!(s = skip_identifier(s))) {
    syntax_error(10);  /* identifier expected */
    return NULL;
  }

  if ((s-type==3 || s-type==5) && !strnicmp(type,"bss",3))
    strcpy(attr,bss_type);
  else if ((s-type==4 || s-type==6) && !strnicmp(type,"data",4))
    strcpy(attr,data_type);
  else if ((s-type==4 || s-type==6) &&
           (!strnicmp(type,"code",4) || !strnicmp(type,"text",4)))
    strcpy(attr,code_type);
  else {
    syntax_error(13);  /* illegal section type */
    return NULL;
  }

  if (s-type==5 || s-type==6) {
    if (*(s-2) == '_') {
      switch (tolower((unsigned char)*(s-1))) {
        case 'c':
          strcat(attr,"C");
          break;
        case 'f':
          strcat(attr,"F");
          break;
        case 'p':
          break;
        default:
          syntax_error(13);
          return NULL;
      }
    }
    else {
      syntax_error(13);  /* illegal section type */
      return NULL;
    }
  }

  s = skip(s);
  if (*s == ',') {
    /* read memory type */
    s = skip(s+1);
    type = s;
    if (!(s = skip_identifier(s))) {
      syntax_error(10);  /* identifier expected */
      return NULL;
    }
    if (s-type==4 && !strnicmp(type,"chip",4))
      strcat(attr,"C");
    else if (s-type==4 && !strnicmp(type,"fast",4))
      strcat(attr,"F");
    else
      syntax_error(15);  /* illegal memory type */
    s = skip(s);
  }

  return s;
}


static void handle_section(char *s)
{
  char attr[32];
  char *name;

  strcpy(attr,code_type);

  /* read section name */
  if (!(name = parse_name(&s)))
    return;

  if (*s == ',') {
    /* read section type */
    s = read_sec_attr(attr,skip(s+1));
  }
  else if (!phxass_compat) {
    /* only name is given - treat name as type */
    if (!read_sec_attr(attr,name))
      s = NULL;
  }

  if (s) {
    new_section(name,attr,1);
    switch_section(name,attr);
  }
}


static void handle_offset(char *s)
{
  taddr offs;

  if (*s!='\0' && *s!=commentchar)
    offs = parse_constexpr(&s);
  else
    offs = -1;  /* use last offset */

  switch_offset_section(NULL,offs);
}


static void motsection(char *secname,char *sectype,char addattr)
/* switch to a section called secname, with attributes sectype+addaddr */
{
  char attr[8];

  sprintf(attr,"%s%c",sectype,addattr);
  new_section(secname,attr,1);
  switch_section(secname,attr);
}

static void handle_csec(char *s)
{
  motsection(code_name,code_type,0);
}

static void handle_dsec(char *s)
{
  motsection(data_name,data_type,0);
}

static void handle_bss(char *s)
{
  motsection(bss_name,bss_type,0);
}

static void handle_codec(char *s)
{
  motsection("CODE_C",code_type,'C');
}

static void handle_codef(char *s)
{
  motsection("CODE_F",code_type,'F');
}

static void handle_datac(char *s)
{
  motsection("DATA_C",data_type,'C');
}

static void handle_dataf(char *s)
{
  motsection("DATA_F",data_type,'F');
}

static void handle_bssc(char *s)
{
  motsection("BSS_C",bss_type,'C');
}

static void handle_bssf(char *s)
{
  motsection("BSS_F",bss_type,'F');
}


static void handle_org(char *s)
{
  if (*s == '*') {    /*  "* = * + <expr>" reserves bytes */
    s = skip(s+1);
    if (*s == '+')
      handle_space(skip(s+1),8);
    else
      syntax_error(7);  /* syntax error */
  }
  else {
    new_org(parse_constexpr(&s));
  }
}


static void handle_rorg(char *s)
{
  add_atom(0,new_roffs_atom(parse_expr_tmplab(&s)));
}


static void handle_global(char *s)
{
  symbol *sym;
  char *name;

  do {
    s = skip(s);
    if (!(name=parse_identifier(&s))) {
      syntax_error(10);  /* identifier expected */
      return;
    }
    sym = new_import(name);
    sym->flags |= EXPORT;
    myfree(name);
    s = skip(s);
  }
  while (*s++ == ',');
}


static void handle_data(char *s,int size)
{
  /* size is negative for floating point data! */
  for (;;) {
    char *opstart = s;
    operand *op;
    dblock *db = NULL;

    if (size==8 && (*s=='\"' || *s=='\'')) {
      if (db = parse_string(&opstart,*s,8)) {
        add_atom(0,new_data_atom(db,1));
        s = opstart;
      }
    }
    if (!db) {
      op = new_operand();
      s = skip_operand(s);
      if (parse_operand(opstart,s-opstart,op,DATA_OPERAND(size))) {
        atom *a;

        a = new_datadef_atom(abs(size),op);
        if (!align_data)
          a->align = 1;
        add_atom(0,a);
      }
      else
        syntax_error(8);  /* invalid data operand */
    }

    s = skip(s);
    if (*s == ',')
      s = skip(s+1);
    else
      break;
  }
}


static void handle_d8(char *s)
{
  handle_data(s,8);
}


static void handle_d16(char *s)
{
  handle_data(s,16);
}


static void handle_d32(char *s)
{
  handle_data(s,32);
}


static void handle_d64(char *s)
{
  handle_data(s,64);
}


static void handle_f32(char *s)
{
  handle_data(s,-32);
}


static void handle_f64(char *s)
{
  handle_data(s,-64);
}


static void handle_f96(char *s)
{
  handle_data(s,-96);
}


static void do_alignment(taddr align,expr *offset)
{
  atom *a = new_space_atom(offset,1,0);

  a->align = align;
  add_atom(0,a);
}


static void handle_cnop(char *s)
{
  expr *offset;
  taddr align=1;

  offset = parse_expr_tmplab(&s);
  s = skip(s);
  if (*s == ',') {
    s = skip(s+1);
    align = parse_constexpr(&s);
  }
  else
    syntax_error(9);  /* , expected */

  do_alignment(align,offset);
}


static void handle_align(char *s)
{
  do_alignment(1<<parse_constexpr(&s),number_expr(0));
}


static void handle_even(char *s)
{
  do_alignment(2,number_expr(0));
}


static void handle_odd(char *s)
{
  do_alignment(2,number_expr(1));
}


static void handle_block(char *s,int size)
{
  expr *cnt,*fill=0;

  cnt = parse_expr_tmplab(&s);
  s = skip(s);
  if (*s == ',') {
    s = skip(s+1);
    fill = parse_expr_tmplab(&s);
  }
  do_space(size,cnt,fill);
}


static void handle_spc8(char *s)
{
  handle_space(s,8);
}


static void handle_spc16(char *s)
{
  handle_space(s,16);
}


static void handle_spc32(char *s)
{
  handle_space(s,32);
}


static void handle_spc64(char *s)
{
  handle_space(s,64);
}


static void handle_spc96(char *s)
{
  handle_space(s,96);
}


static void handle_blk8(char *s)
{
  handle_block(s,8);
}


static void handle_blk16(char *s)
{
  handle_block(s,16);
}


static void handle_blk32(char *s)
{
  handle_block(s,32);
}


static void handle_blk64(char *s)
{
  handle_block(s,64);
}


static void handle_blk96(char *s)
{
  handle_block(s,96);
}


#ifdef VASM_CPU_M68K
static void handle_reldata(char *s,int size)
{
  for (;;) {
    char *opstart = s;
    operand *op;

    op = new_operand();
    s = skip_operand(s);
    if (parse_operand(opstart,s-opstart,op,DATA_OPERAND(size))) {
      if (op->exp.value[0]) {
        expr *tmplab,*new;
        atom *a;

        tmplab = new_expr();
        tmplab->type = SYM;
        tmplab->c.sym = new_tmplabel(0);
        add_atom(0,new_label_atom(tmplab->c.sym));
        /* subtract the current pc value from all data expressions */
        new = make_expr(SUB,op->exp.value[0],tmplab);
        simplify_expr(new);
        op->exp.value[0] = new;
        a = new_datadef_atom(abs(size),op);
        if (!align_data)
          a->align = 1;
        add_atom(0,a);
      }
      else
        ierror(0);
    }
    else
      syntax_error(8);  /* invalid data operand */
    s = skip(s);
    if (*s == ',')
      s = skip(s+1);
    else
      break;
  }
}


static void handle_reldata8(char *s)
{
  handle_reldata(s,8);
}


static void handle_reldata16(char *s)
{
  handle_reldata(s,16);
}


static void handle_reldata32(char *s)
{
  handle_reldata(s,32);
}
#endif


static void handle_end(char *s)
{
  parse_end = 1;
}


static void handle_fail(char *s)   
{ 
  fail(s);
}


static void handle_idnt(char *s)
{
  char *name;

  if (name = parse_name(&s))
    setfilename(name);
}


static void handle_list(char *s)
{
  set_listing(1);
}


static void handle_nolist(char *s)
{
  set_listing(0);
}


static void handle_plen(char *s)
{
  int plen = (int)parse_constexpr(&s);

  listlinesperpage = plen > 12 ? plen : 12;
}


static void handle_page(char *s)
{
  /* @@@ we should also start a new page here! */
  listformfeed = 1;
}


static void handle_nopage(char *s)
{
  listformfeed = 0;
}


static void handle_output(char *s)
{
  char *name;

  if (name = parse_name(&s)) {
    if (*name=='.') {
      char *p;
      int outlen;

      if (!outname)
        outname = inname;
      if (p = strrchr(outname,'.'))
        outlen = p - outname;
      else
        outlen = strlen(outname);
      p = mymalloc(outlen+strlen(name)+1);
      memcpy(p,outname,outlen);
      strcpy(p+outlen,name);
      myfree(name);
      outname = p;
    }
    else if (!outname)
      outname = name;
  }
}


static void handle_dsource(char *s)
{
  char *name;

  if (name = parse_name(&s))
    setdebugname(name);
}


static void handle_debug(char *s)
{
  atom *a = new_srcline_atom((int)parse_constexpr(&s));

  add_atom(0,a);
}


static void handle_incdir(char *s)
{
  char *name;

  while (name = parse_name(&s)) {
    new_include_path(name);
    if (*s != ',') {
      return;
    }
    s = skip(s+1);
  }
  syntax_error(5);
}


static void handle_include(char *s)
{
  char *name;

  if (name = parse_name(&s)) {
    include_source(name);
  }
}


static void handle_incbin(char *s)
{
  char *name;

  if (name = parse_name(&s)) {
    include_binary_file(name,0,0);
  }
}


static void handle_rept(char *s)
{
  new_repeat((int)parse_constexpr(&s),rept_dirlist,endr_dirlist);
}


static void handle_endr(char *s)
{
  syntax_error(16,"endr","rept");  /* unexpected endr without rept */
}


static void handle_macro(char *s)
{
  char *name;

  if (name = parse_name(&s))
    new_macro(name,endm_dirlist,NULL);
}


static void handle_endm(char *s)
{
  syntax_error(16,"endm","macro");  /* unexpected endm without macro */
}


static void handle_mexit(char *s)
{
  int l = leave_macro();

  if (l >= 0) {  /* mexit successful? */
    clev = l;    /* restore clev from macro-entry */
  }
}


static void handle_rem(char *s)
{
  new_repeat(0,NULL,erem_dirlist);
}


static void handle_erem(char *s)
{
  syntax_error(16,"erem","rem");  /* unexpected erem without rem */
}


static void handle_ifb(char *s)
{
  new_clev(*s=='\0' || *s==commentchar);
}

static void handle_ifnb(char *s)
{
  new_clev(*s!='\0' && *s!=commentchar);
}

static void ifc(char *s,int b)
{
  char *str1,*str2;
  int result;

  str1 = parse_name(&s);
  if (str1!=NULL && *s==',') {
    s = skip(s+1);
    if (str2 = parse_name(&s)) {
      result = strcmp(str1,str2) == 0;
      new_clev(result == b);
      return;
    }
  }
  syntax_error(5);  /* missing operand */
}

static void handle_ifc(char *s)
{
  ifc(s,1);
}

static void handle_ifnc(char *s)
{
  ifc(s,0);
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
  new_clev(result == b);
}

static void handle_ifd(char *s)
{
  ifdef(s,1);
}

static void handle_ifnd(char *s)
{
  ifdef(s,0);
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
  new_clev(b);
  free_expr(condexp);
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
  if (clev > 0)
    cond[clev] = 0;
  else
    syntax_error(16,"else","if");  /* else without if */
}

static void handle_endif(char *s)
{
  if (clev > 0)
    clev--;
  else
    syntax_error(16,"endif","if");  /* unexpected endif without if */
}


static void handle_rsreset(char *s)
{
  new_abs(rs_name,number_expr(0));
}

static void handle_rsset(char *s)
{
  new_abs(rs_name,number_expr(parse_constexpr(&s)));
}

static void handle_clrso(char *s)
{
  new_abs(so_name,number_expr(0));
}

static void handle_setso(char *s)
{
  new_abs(so_name,number_expr(parse_constexpr(&s)));
}

static void handle_clrfo(char *s)
{
  new_abs(fo_name,number_expr(0));
}

static void handle_setfo(char *s)
{
  new_abs(fo_name,number_expr(parse_constexpr(&s)));
}

static void handle_rs8(char *s)
{
  new_setoffset_size(NULL,rs_name,&s,1,1);
}

static void handle_rs16(char *s)
{
  new_setoffset_size(NULL,rs_name,&s,1,2);
}

static void handle_rs32(char *s)
{
  new_setoffset_size(NULL,rs_name,&s,1,4);
}

static void handle_rs64(char *s)
{
  new_setoffset_size(NULL,rs_name,&s,1,8);
}

static void handle_rs96(char *s)
{
  new_setoffset_size(NULL,rs_name,&s,1,12);
}

static void handle_so8(char *s)
{
  new_setoffset_size(NULL,so_name,&s,1,1);
}

static void handle_so16(char *s)
{
  new_setoffset_size(NULL,so_name,&s,1,2);
}

static void handle_so32(char *s)
{
  new_setoffset_size(NULL,so_name,&s,1,4);
}

static void handle_so64(char *s)
{
  new_setoffset_size(NULL,so_name,&s,1,8);
}

static void handle_so96(char *s)
{
  new_setoffset_size(NULL,so_name,&s,1,12);
}

static void handle_fo8(char *s)
{
  new_setoffset_size(NULL,fo_name,&s,-1,1);
}

static void handle_fo16(char *s)
{
  new_setoffset_size(NULL,fo_name,&s,-1,2);
}

static void handle_fo32(char *s)
{
  new_setoffset_size(NULL,fo_name,&s,-1,4);
}

static void handle_fo64(char *s)
{
  new_setoffset_size(NULL,fo_name,&s,-1,8);
}

static void handle_fo96(char *s)
{
  new_setoffset_size(NULL,fo_name,&s,-1,12);
}

static void handle_cargs(char *s)
{
  char *name;
  expr *offs;
  taddr size;

  if (*s == '#') {
    /* offset given */
    ++s;
    offs = parse_expr_tmplab(&s);
    s = skip(s);
    if (*s != ',')
      syntax_error(9);  /* , expected */
    else
      s = skip(s+1);
  }
  else
    offs = number_expr(4);  /* default offset */

  for (;;) {

    if (!(name = get_local_label(&s)))
      name = parse_identifier(&s);
    if (!name) {
      syntax_error(10);  /* identifier expected */
      break;
    }

    if (!check_sym_defined(name)) {
      /* define new stack offset symbol */
      new_abs(name,copy_tree(offs));
    }
    myfree(name);

    /* increment offset by given size */
    if (*s == '.') {
      ++s;
      switch (tolower((unsigned char)*s)) {
        case 'b':
        case 'w':
          size = 2;
          ++s;
          break;
        case 'l':
          size = 4;
          ++s;
          break;
        default:
          size = 2;
          syntax_error(1);  /* invalid extension */
          break;
      }
    }
    else
      size = 2;

    s = skip(s);
    if (*s != ',')  /* define another offset symbol? */
      break;

    offs = make_expr(ADD,offs,number_expr(size));
    simplify_expr(offs);
    s = skip(s+1);
  }

  /* offset expression was copied, so we can free it now */
  if (offs)
    free_expr(offs);
}

static void handle_printt(char *s)
{
  add_atom(0,new_text_atom(parse_name(&s)));
}

static void handle_printv(char *s)
{
  add_atom(0,new_expr_atom(parse_expr(&s)));
}

static void handle_dummy_expr(char *s)
{
  parse_expr(&s);
  syntax_error(11);  /* directive has no effect */
}

static void handle_dummy_cexpr(char *s)
{
  parse_constexpr(&s);
  syntax_error(11);  /* directive has no effect */
}

static void handle_noop(char *s)
{
  syntax_error(11);  /* directive has no effect */
}

static void handle_comment(char *s)
{
  /* handle Atari-specific "COMMENT HEAD=<expr>" to define the tos-flags */
  if (!strnicmp(s,"HEAD=",5)) {
    s += 5;
    new_abs(" TOSFLAGS",parse_expr_tmplab(&s));
  }
  /* otherwise it's just a comment to be ignored */
}


struct {
  char *name;
  void (*func)(char *);
} directives[] = {
  "org",handle_org,
  "rorg",handle_rorg,
  "section",handle_section,
  "offset",handle_offset,
  "code",handle_csec,
  "cseg",handle_csec,
  "text",handle_csec,
  "data",handle_dsec,
  "dseg",handle_dsec,
  "bss",handle_bss,
  "code_c",handle_codec,
  "code_f",handle_codef,
  "data_c",handle_datac,
  "data_f",handle_dataf,
  "bss_c",handle_bssc,
  "bss_f",handle_bssf,
  "public",handle_global,
  "xdef",handle_global,
  "xref",handle_global,  
  "nref",handle_global,
  "entry",handle_global,
  "extrn",handle_global,
  "global",handle_global,
  "load",handle_dummy_expr,
  "jumperr",handle_dummy_expr,
  "jumpptr",handle_dummy_expr,
  "mask2",eol,
  "cnop",handle_cnop,
  "align",handle_align,
  "even",handle_even,
  "odd",handle_odd,
  "dc",handle_d16,
  "dc.b",handle_d8,
  "dc.w",handle_d16,
  "dc.l",handle_d32,
  "dc.q",handle_d64,
  "dc.s",handle_f32,
  "dc.d",handle_f64,
  "dc.x",handle_f96,
  "ds",handle_spc16,
  "ds.b",handle_spc8,
  "ds.w",handle_spc16,
  "ds.l",handle_spc32,
  "ds.q",handle_spc64,
  "ds.s",handle_spc32,
  "ds.d",handle_spc64,
  "ds.x",handle_spc96,
  "dcb",handle_blk16,
  "dcb.b",handle_blk8,
  "dcb.w",handle_blk16,
  "dcb.l",handle_blk32,
  "dcb.q",handle_blk64,
  "dcb.s",handle_blk32,
  "dcb.d",handle_blk64,
  "dcb.x",handle_blk96,
  "blk",handle_blk16,
  "blk.b",handle_blk8,
  "blk.w",handle_blk16,
  "blk.l",handle_blk32,
  "blk.q",handle_blk64,
  "blk.s",handle_blk32,
  "blk.d",handle_blk64,
  "blk.x",handle_blk96,
#ifdef VASM_CPU_M68K
  "dr",handle_reldata16,
  "dr.b",handle_reldata8,
  "dr.w",handle_reldata16,
  "dr.l",handle_reldata32,
#endif
  "end",handle_end,
  "fail",handle_fail,
  "idnt",handle_idnt,
  "ttl",handle_idnt,
  "list",handle_list,
  "nolist",handle_nolist,
  "plen",handle_plen,
  "llen",handle_dummy_cexpr,
  "page",handle_page,
  "nopage",handle_nopage,
  "spc",handle_dummy_cexpr,
  "output",handle_output,
  "symdebug",eol,
  "dsource",handle_dsource,
  "debug",handle_debug,
  "comment",handle_comment,
  "incdir",handle_incdir,
  "include",handle_include,
  "incbin",handle_incbin,
  "image",handle_incbin,
  "rept",handle_rept,
  "endr",handle_endr,
  "macro",handle_macro,
  "endm",handle_endm,
  "mexit",handle_mexit,
  "rem",handle_rem,
  "erem",handle_erem,
  "ifb",handle_ifb,
  "ifnb",handle_ifnb,
  "ifc",handle_ifc,
  "ifnc",handle_ifnc,
  "ifd",handle_ifd,
  "ifnd",handle_ifnd,
  "ifeq",handle_ifeq,
  "ifne",handle_ifne,
  "ifgt",handle_ifgt,
  "ifge",handle_ifge,
  "iflt",handle_iflt,
  "ifle",handle_ifle,
  "if",handle_ifne,
  "else",handle_else,
  "elseif",handle_else,
  "endif",handle_endif,
  "endc",handle_endif,
  "rsreset",handle_rsreset,
  "rsset",handle_rsset,
  "clrso",handle_clrso,
  "setso",handle_setso,
  "clrfo",handle_clrfo,
  "setfo",handle_setfo,
  "rs",handle_rs16,
  "rs.b",handle_rs8,
  "rs.w",handle_rs16,
  "rs.l",handle_rs32,
  "rs.q",handle_rs64,
  "rs.s",handle_rs32,
  "rs.d",handle_rs64,
  "rs.x",handle_rs96,
  "rs",handle_rs16,
  "so.b",handle_so8,
  "so.w",handle_so16,
  "so.l",handle_so32,
  "so.q",handle_so64,
  "so.s",handle_so32,
  "so.d",handle_so64,
  "so.x",handle_so96,
  "fo",handle_fo16,
  "fo.b",handle_fo8,
  "fo.w",handle_fo16,
  "fo.l",handle_fo32,
  "fo.q",handle_fo64,
  "fo.s",handle_fo32,
  "fo.d",handle_fo64,
  "fo.x",handle_fo96,
  "cargs",handle_cargs,
  "echo",handle_printt,
  "printt",handle_printt,
  "printv",handle_printv,
  "auto",handle_noop,
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
  while (ISIDCHAR(*s) || *s=='.')
    s++;
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


static int offs_directive(char *s,char *name)
{
  int len = strlen(name);

  return !strnicmp(s,name,len) &&
         ((isspace((unsigned char)*(s+len)) ||
           *(s+len)=='\0' || *(s+len)==commentchar) ||
          (*(s+len)=='.' && isspace((unsigned char)*(s+len+2))));
}


static char *get_label(char **s)
{
  char *labname;

  labname = get_local_label(s);          /* local label? */
  if (!labname) {
    if (labname = parse_identifier(s))   /* global label? */
      *s = skip(*s);
  }
  return labname;
}


void parse(void)
{
  char *s,*line,*inst,*labname;
  char *ext[MAX_QUALIFIERS?MAX_QUALIFIERS:1];
  char *op[MAX_OPERANDS];
  int ext_len[MAX_QUALIFIERS?MAX_QUALIFIERS:1];
  int op_len[MAX_OPERANDS];
  int i,ext_cnt,op_cnt,inst_len;
  instruction *ip;

  while (line = read_next_line()) {
    if (parse_end)
      continue;
    s = line;

    if (!cond[clev]) {
      /* skip source until ELSE or ENDIF */
      int idx;

      /* skip label, when present */
      if (labname = get_label(&s)) {
        myfree(labname);
        if (*s == ':')    /* ':' is optional */
          s++;
      }
      /* advance to directive */
      s = skip(s);
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
              syntax_error(16,directives[idx].name,"if"); /*endif without if*/
          }
          else
            ifnesting--;
        }
      }
      continue;
    }

    if (labname = get_label(&s)) {
      /* we have found a global or local label at first column */
      symbol *label;
      int lablen = strlen(labname);

      if (*s == ':')    /* ':' is optional */
        s = skip(s+1);

      if (!strnicmp(s,"equ",3) && isspace((unsigned char)*(s+3))) {
        check_sym_defined(labname);
        s = skip(s+3);
        label = new_abs(labname,parse_expr_tmplab(&s));
      }
      else if (*s=='=') {
        check_sym_defined(labname);
        s = skip(s+1);
        label = new_abs(labname,parse_expr_tmplab(&s));
      }
      else if (!strnicmp(s,"set",3) && isspace((unsigned char)*(s+3))) {
        /* SET allows redefinitions */
        s = skip(s+3);
        label = new_abs(labname,parse_expr_tmplab(&s));
      }
      else if (offs_directive(s,"rs")) {
        label = new_setoffset(labname,&s,rs_name,1);
      }
      else if (offs_directive(s,"so")) {
        label = new_setoffset(labname,&s,so_name,1);
      }
      else if (offs_directive(s,"fo")) {
        label = new_setoffset(labname,&s,fo_name,-1);
      }
      else if (!strnicmp(s,"ttl",3) && isspace((unsigned char)*(s+3))) {
        s = skip(s+3);
        setfilename(labname);
      }
      else if (!strnicmp(s,"macro",5) &&
               (isspace((unsigned char)*(s+5)) || *(s+5)=='\0')) {
        /* reread original label field as macro name, no local macros */
        s = line;
        myfree(labname);
        if (!(labname = parse_identifier(&s)))
          ierror(0);
        new_macro(labname,endm_dirlist,NULL);
        myfree(labname);
        continue;
      }
#ifdef VASM_CPU_M68K
      else if (!parse_cpu_label(labname,&s)) {
#else
      else {
#endif
        label = new_labsym(0,labname);
        add_atom(0,new_label_atom(label));
      }
      myfree(labname);
    }

    /* check for directives first */
    s = skip(s);
    if (*s=='*' || *s==commentchar)
      continue;

    s = parse_cpu_special(s);
    if (*s=='\0' || *s==commentchar)
      continue;

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

    /* read operands, terminated by comma (unless in parentheses)  */
    op_cnt = 0;
    while (*s && *s!=commentchar && op_cnt<MAX_OPERANDS) {
      op[op_cnt] = s;
      s = skip_operand(s);
      op_len[op_cnt] = s - op[op_cnt];
#if 0
      /* This causes problems, when there is a comma in the comment field
         of an instructions without operands. */
      if (op_len[op_cnt] <= 0)
        syntax_error(5);  /* missing operand */
      else
#endif
        op_cnt++;

      if (allow_spaces) {
        s = skip(s);
        if (*s != ',')
          break;
        else
          s = skip(s+1);
      }
      else {
        if (*s == ',')
          s++;
        else
          break;
      }
    }      
    eol(s);

    ip = new_inst(inst,inst_len,op_cnt,op,op_len);

#if MAX_QUALIFIERS>0
    if (ip) {
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
    syntax_error(17,condsrc[clev],condline[clev]);  /* "endc/endif missing */
}


char *const_prefix(char *s,int *base)
{
  if (isdigit((unsigned char)*s)) {
    *base = 10;
    return s;
  }
  if (*s == '$') {
    *base = 16;
    return s+1;
  }
  if (*s=='@' && isdigit((unsigned char)*(s+1))) {
    *base = 8;
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
    p = CHKIDEND(s,p);
  }
  else
    p = NULL;

  return p;
}


char *get_local_label(char **start)
/* Motorola local labels start with a '.' or end with '$': "1234$", ".1" */
{
  char *s,*p,*name;
  int globlen = 0;

  name = NULL;
  s = *start;
  p = skip_local(s);

  if (p!=NULL && *p=='\\' && ISIDSTART(*s) && *s!=local_char && *(p-1)!='$') {
    /* skip local part of global\local label */
    globlen = p - s;
    s = p + 1;
    p = skip_local(s);
  }

  if (p!=NULL && p>(s+1)) {  /* identifier with at least 2 characters */
    if (*s == local_char) {
      /* .label */
      name = make_local_label(*start,globlen,s,p-s);
      *start = skip(p);
    }
    else if (*(p-1) == '$') {
      /* label$ */
      name = make_local_label(*start,globlen,s,(p-1)-s);
      *start = skip(p);
    }
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
  secname_attr = 1; /* attribute is used to differentiate between sections */
#ifdef REPTNSYM
  set_internal_abs(REPTNSYM,-1);  /* reserve the REPTN symbol */
#endif
  return 1;
}


int syntax_args(char *p)
{
  if (!strcmp(p,"-align")) {
    align_data = 1;
    return 1;
  }
  else if (!strcmp(p,"-devpac")) {
    align_data = 1;
    esc_sequences = 0;
    maxmacparams = 36;  /* allow \a..\z macro parameters */
    dot_idchar = 1;
    internal_abs(rs_name);
    internal_abs(fo_name);
    internal_abs(so_name);
    return 1;
  }
  else if (!strcmp(p,"-phxass")) {
    new_abs("_PHXASS_",number_expr(1));
    phxass_compat = 1;
    nocase_macros = 1;
    allow_spaces = 1;
    maxmacparams = 36;  /* allow \a..\z macro parameters */
    return 1;
  }
  else if (!strcmp(p,"-spaces")) {
    allow_spaces = 1;
    return 1;
  }
  else if (!strcmp(p,"-ldots")) {
    dot_idchar = 1;
    return 1;
  }
  else if (!strcmp(p,"-localu")) {
    local_char = '_';
    return 1;
  }
  return 0;
}
