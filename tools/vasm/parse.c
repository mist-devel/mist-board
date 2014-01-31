/* parse.c - global parser support functions */
/* (c) in 2009-2013 by Volker Barthelmann and Frank Wille */

#include "vasm.h"

int esc_sequences = 1;  /* handle escape sequences */
int nocase_macros = 0;  /* macro names are case-insensitive */
int maxmacparams = 10;  /* 10: \0..\9, 36: \0..\9+\a..\z */
int namedmacparams = 0; /* allow named macro arguments, like \argname */

#ifndef MACROHTABSIZE
#define MACROHTABSIZE 0x800
#endif
static hashtable *macrohash;

#ifndef STRUCTHTABSIZE
#define STRUCTHTABSIZE 0x800
#endif
static hashtable *structhash;

static macro *first_macro;
static macro *cur_macro;
static struct namelen *enddir_list;
static size_t enddir_minlen;
static struct namelen *reptdir_list;
static int rept_cnt = -1;
static char *rept_start;
static section *cur_struct;
static section *struct_prevsect;
#ifdef CARGSYM
static expr *carg1;
#endif

#define IDSTACKSIZE 100
static unsigned long id_stack[IDSTACKSIZE];
static int id_stack_index;


char *escape(char *s,char *code)
{
  if (*s++ != '\\')
    ierror(0);

  if (!esc_sequences) {
    *code='\\';
    return s;
  }

  switch (*s) {
    case 'b':
      *code='\b';
      return s+1;
    case 'f':
      *code='\f';
      return s+1;
    case 'n':
      *code='\n';
      return s+1;
    case 'r':
      *code='\r';
      return s+1;
    case 't':
      *code='\t';
      return s+1;
    case '\\':
      *code='\\';
      return s+1;
    case '\"':
      *code='\"';
      return s+1;
    case '\'':
      *code='\'';
      return s+1;
    case 'e':
      *code=27;
      return s+1;
    case '0': case '1': case '2': case '3': 
    case '4': case '5': case '6': case '7':
      *code = 0;
      while (*s>='0' && *s<='7') {
        *code = *code*8 + *s-'0';
        s++;
      }
      return s;
    case 'x': case 'X':
      *code=0;
      s++;
      while ((*s>='0' && *s<='9') ||
             (*s>='a' && *s<='f') || (*s>='A' && *s<='F')) {
        if (*s>='0' && *s<='9')
          *code = *code*16 + *s-'0';
        else if (*s>='a' && *s<='f')
          *code = *code*16 + *s-'a' + 10;
        else
          *code = *code*16 + *s -'A' + 10;
        s++;
      }    
      return s;
    default:
      general_error(35,*s);
      return s;
  }
}


char *parse_name(char **start)
/* parses a quoted or unquoted name-string and returns a pointer to it */
{
  char *s = *start;
  char c,*name;

  if (*s=='\"' || *s=='\'') {
    c = *s++;
    name = s;
    while (*s && *s!=c)
      s++;
    name = cnvstr(name,s-name);
    if (*s)
      s = skip(s+1);
  }
#ifdef VASM_CPU_M68K
  else if (*s=='<') {
    s++;
    name = s;
    while (*s && *s!='>')
      s++;
    name = cnvstr(name,s-name);
    if (*s)
      s = skip(s+1);
  }
#endif
  else {
    name = s;
    while (*s && !isspace((unsigned char)*s) && *s!=',' && *s!=commentchar)
      s++;
    if (s != name) {
      name = cnvstr(name,s-name);
      s = skip(s);
    }
    else
      name = NULL;  /* nothing read */
  }
  *start = s;
  return name;
}


static char *skip_eol(char *s,char *e)
{
  while (s<e && *s!='\0' && *s!='\n' && *s!='\r')
    s++;
  return s;
}


char *skip_identifier(char *s)
{
  char *name = s;

  if (ISIDSTART(*s)) {
    s++;
    while (ISIDCHAR(*s))
      s++;
    return CHKIDEND(name,s);
  }
  return NULL;
}


char *parse_identifier(char **s)
{
  char *name = *s;
  char *endname;

  if (endname = skip_identifier(*s)) {
    *s = endname;
    return cnvstr(name,endname-name);
  }
  return NULL;
}


char *skip_string(char *s,char delim,taddr *size)
/* skip a string, optionally store the size in bytes in size, when not NULL */
{
  taddr n = 0;
  char c;

  if (*s != delim)
    general_error(6,delim);  /* " expected */
  else
    s++;

  while (*s) {
    if (*s == '\\') {
      s = escape(s,&c);
    }
    else {
      if (*s++ == delim) {
        if (*s == delim)
          s++;  /* allow """" to be recognized as " */
        else
          break;
      }
    }
    n++;
  }

  if (*(s-1) != delim)
    general_error(6,delim);  /* " expected */
  if (size)
    *size = n;
  return s;
}


dblock *parse_string(char **str,char delim,int width)
{
  taddr size;
  dblock *db;
  char *p,c;
  char *s = *str;

  if (width & 7)
    ierror(0);
  width >>= 3;

  /* how many bytes do we need for the string? */
  skip_string(s,delim,&size);
  if (size == 1)
    return NULL; /* it's just one char, so use eval_expr() on it */

  db = new_dblock();
  db->size = size * width;
  db->data = db->size ? mymalloc(db->size) : NULL;

  /* now copy the string for real into the dblock */
  if (*s == delim)
    s++;
  p = db->data;

  while (*s) {
    if (*s == '\\') {
      s = escape(s,&c);
    }
    else {
      c = *s++;
      if (c == delim) {
        if (*s == delim)
          s++;  /* allow """" to be recognized as " */
        else
          break;
      }
    }
    setval(BIGENDIAN,p,width,(unsigned char)c);
    p += width;
  }

  *str = s;
  return db;
}


int check_indir(char *p,char *q)
/* returns true when the whole sequence between p and q starts and ends with */
/* parentheses and there are no unbalanced parentheses within */
{
  char c;
  int n;

  p = skip(p);
  if (*p++ != '(')
    return 0;

  n = 1;
  while (n>0 && p<q) {
    c = *p++;
    if (c == '(')
      n++;
    else if (c == ')')
      n--;
  }
  if (p < q)
    p = skip(p);

  return n==0 && p>=q;
}


void include_binary_file(char *inname,long nbskip,unsigned long nbkeep)
/* locate a binary file and convert into a data atom */
{
  char *filename;
  FILE *f;

  filename = convert_path(inname);
  if (f = locate_file(filename,"rb")) {
    taddr size = filesize(f);

    if (size > 0) {
      if (nbskip>=0 && nbskip<=size) {
        dblock *db = new_dblock();

        if (nbkeep > (unsigned long)(size - nbskip) || nbkeep==0)
          db->size = size - nbskip;
        else
          db->size = nbkeep;

        db->data = mymalloc(size);
        if (nbskip > 0)
          fseek(f,nbskip,SEEK_SET);

        fread(db->data,1,db->size,f);
        add_atom(0,new_data_atom(db,1));
      }
      else
        general_error(46);  /* bad file-offset argument */
    }
    fclose(f);
  }
  myfree(filename);
}


static struct namelen *dirlist_match(char *s,char *e,struct namelen *list)
/* check if a directive from the list matches the current source location */
{
  size_t len;
  size_t maxlen = e - s;

  while (len = list->len) {
    if (len <= maxlen) {
      if (!strnicmp(s,list->name,len) && isspace((unsigned char)*(s + len)))
        return list;
    }
    list++;
  }
  return NULL;
}


static size_t dirlist_minlen(struct namelen *list)
{
  size_t minlen;

  if (list == NULL)
    ierror(0);
  for (minlen=list->len; list->len; list++) {
    if (list->len < minlen)
      minlen = list->len;
  }
  return minlen;
}


void new_repeat(int rcnt,struct namelen *reptlist,struct namelen *endrlist)
{
  if (cur_macro==NULL && cur_src!=NULL && enddir_list==NULL) {
    enddir_list = endrlist;
    enddir_minlen = dirlist_minlen(endrlist);
    reptdir_list = reptlist;
    rept_cnt = rcnt;
    rept_start = cur_src->srcptr;
  }
  else
    ierror(0);
}


static int find_param_name(char *name,int *param_len)
{
  struct macarg *ma;
  int idx,len;

  len = skip_identifier(name) - name;
  if (ma = cur_src->param_names) {
    idx = 1;
    while (ma) {
      /* @@@ case-sensitive comparison? */
      if (len==strlen(ma->argname) && strncmp(ma->argname,name,len)==0) {
        *param_len = len;
        return idx;
      }
      ma = ma->argnext;
      idx++;
    }
  }
  return -1;
}


static void named_macro_arg(macro *m,char *start,char *end)
{
  struct macarg *lastarg,*newarg;
  int cnt = 1;

  /* count arguments */
  if (lastarg = m->argnames) {
    cnt++;
    while (lastarg->argnext) {
      lastarg = lastarg->argnext;
      cnt++;
    }
  }
  if (cnt >= MAXMACPARAMS)
    general_error(27,MAXMACPARAMS-1);  /* number of args exceeded */

  cnt = end - start;
  newarg = mymalloc(sizeof(struct macarg) + cnt);
  newarg->argnext = NULL;
  memcpy(newarg->argname,start,cnt);
  newarg->argname[cnt] = '\0';
  if (lastarg)
    lastarg->argnext = newarg;
  else
    m->argnames = newarg;
}


macro *new_macro(char *name,struct namelen *endmlist,char *args)
{
  hashdata data;
  macro *m = NULL;

  if (cur_macro==NULL && cur_src!=NULL && enddir_list==NULL) {
    if (find_name_nc(mnemohash,name,&data))
      general_error(51);  /* name conflicts with mnemonic */
    if (find_name_nc(dirhash,name,&data))
      general_error(52);  /* name conflicts with directive */

    m = mymalloc(sizeof(macro));
    m->name = mystrdup(name);
    if (nocase_macros)
      strtolower(m->name);
    m->text = cur_src->srcptr;
    m->argnames = NULL;
    cur_macro = m;
    enddir_list = endmlist;
    enddir_minlen = dirlist_minlen(endmlist);
    rept_cnt = -1;
    rept_start = NULL;

    if (args) {
      /* named arguments have been given */
      char *end;

      args = skip(args);
      while (*args != '\0') {
        if (*args == '\\')
          args++;
        end = skip_identifier(args);
        if (end!=NULL && end-args!=0) {
          /* add another argument name */
          named_macro_arg(m,args,end);
          args = end;
        }
        else
          general_error(42);  /* illegal macro argument */
        args = skip(args);
        if (*args == ',')
          args = skip(args+1);
      }
    }
  }
  else
    ierror(0);

  return m;
}


/* check if 'name' is a known macro, then execute macro context */
int execute_macro(char *name,int name_len,char **q,int *q_len,int nq,
                  char *s,int clev)
{
  hashdata data;
  macro *m;
  source *src;
  int n;
#ifdef CARGSYM
  symbol *carg;
#endif
#if MAX_QUALIFIERS>0
  char *defq[MAX_QUALIFIERS];
  int defq_len[MAX_QUALIFIERS];
#endif

  if (nocase_macros) {
    if (!find_namelen_nc(macrohash,name,name_len,&data))
      return 0;
  }
  else {
    if (!find_namelen(macrohash,name,name_len,&data))
      return 0;
  }

  /* it's a macro: read arguments and execute it */
  m = data.ptr;
  src = new_source(m->name,m->text,m->size);

#if MAX_QUALIFIERS>0
  /* put first qualifier into argument \0 */
  /* FIXME: what about multiple qualifiers? */
  if (nq) {
    src->param[0] = q[0];
    src->param_len[0] = q_len[0];
  }
  else if (nq = set_default_qualifiers(defq,defq_len)) {
    src->param[0] = defq[0];
    src->param_len[0] = defq_len[0];
  }
#endif
    
  /* read macro arguments from operand field */
  for (n=0,s=skip(s); *s!='\0' && *s!=commentchar && n<maxmacparams; ) {
    n++;

    if (*s=='\"' || *s=='\'') {
      /* macro argument in quotes */
      char dummy,c;

      src->param[n] = s;
      c = *s++;
      while (*s != '\0') {
        if (*s=='\\' && *(s+1)!='\0') {
          s = escape(s,&dummy);
        }
        else {
          if (*s++ == c) {
            if (*s == c)
              s++;  /* allow """" to be recognized as " */
            else
              break;
          }
        }
      }
      src->param_len[n] = s - src->param[n];
    }

    else if (*s == '<') {
      /* macro argument enclosed in < ... > */
      src->param[n] = ++s;
      while (*s != '\0') {
        if (*s =='>') {
          if (*(s+1) == '>') {
            /* convert ">>" into a single ">" */
            char *p;

            for (p=s+1; *p!='\0'; p++)
              *(p-1) = *p;
            *(p-1) = '\0';
          }
          else
            break;
        }
        s++;
      }
      src->param_len[n] = s - src->param[n];
      if (*s == '>')
        s++;
    }

    else {
      src->param[n] = s;
      s = skip_operand(s);
      while (isspace((unsigned char)*(s-1)))  /* cut trailing blanks */
        s--;
      src->param_len[n] = s - src->param[n];
    }

    s = skip(s);
    if (*s != ',')
      break;
    else
      s = skip(s+1);
  }

#ifdef CARGSYM
  /* reset the CARG symbol to 1, selecting the first macro parameter */
  carg = internal_abs(CARGSYM);
  cur_src->cargexp = carg->expr;  /* remember last CARG expression */
  carg->expr = carg1;
#endif
  eol(s);
  if (n >= maxmacparams) {
    general_error(27,maxmacparams-1);  /* number of args exceeded */
    n = maxmacparams - 1;
  }
  src->num_params = n;      /* >=0 indicates macro source */
  src->param_names = m->argnames;
  src->cond_level = clev;   /* remember level of conditional nesting */
  cur_src = src;            /* execute! */
  return 1;
}


int leave_macro(void)
{
  if (cur_src->num_params >= 0) {
    /* move srcptr to end of macro-source, effectively leaving the macro */
    cur_src->srcptr = cur_src->text + cur_src->size;
    return cur_src->cond_level;
  }
  general_error(36);  /* no current macro to exit */
  return -1;
}


static void start_repeat(char *rept_end)
{
  char buf[MAXPATHLEN];
  source *src;
  int i;

  reptdir_list = NULL;
  if (rept_cnt<0 || cur_src==NULL || strlen(cur_src->name) + 24 >= MAXPATHLEN)
    ierror(0);

  if (rept_cnt > 0) {
    sprintf(buf,"REPEAT:%s:line %d",cur_src->name,cur_src->line);
    src = new_source(mystrdup(buf),rept_start,rept_end-rept_start);
    src->repeat = (unsigned long)rept_cnt;
#ifdef REPTNSYM
    src->reptn = 0;
    set_internal_abs(REPTNSYM,0);
#endif

    if (cur_src->num_params > 0) {
      /* repetition in a macro: get parameters */
      src->num_params = cur_src->num_params;
      for (i=0; i<=src->num_params; i++) {
        src->param[i] = cur_src->param[i];
        src->param_len[i] = cur_src->param_len[i];
      }
      src->param_names = cur_src->param_names;
    }
    cur_src = src;  /* repeat it */
  }
}


static void add_macro(void)
{
  if (cur_macro!=NULL && cur_src!=NULL) {
    hashdata data;

    cur_macro->size = cur_src->srcptr - cur_macro->text;
    cur_macro->next = first_macro;
    first_macro = cur_macro;
    data.ptr = cur_macro;
    add_hashentry(macrohash,cur_macro->name,data);
    cur_macro = NULL;
  }
  else
    ierror(0);
}


static int copy_macro_param(int n,char *d,int len)
/* copy macro parameter n to line buffer */
{
  int i = 0;

  if (n<=cur_src->num_params && n<maxmacparams) {
    for (; i<cur_src->param_len[n] && len>0; i++,len--)
      *d++ = cur_src->param[n][i];
  }
  return i;
}


#ifdef CARGSYM
static int copy_macro_carg(int inc,char *d,int len)
/* copy macro parameter #CARG to line buffer, increment or decrement CARG */
{
  symbol *carg = internal_abs(CARGSYM);
  int nc;

  if (carg->type != EXPRESSION)
    return 0;
  simplify_expr(carg->expr);
  if (carg->expr->type != NUM) {
    general_error(30);  /* expression must be a constant */
    return 0;
  }
  nc = copy_macro_param(carg->expr->c.val,d,len);

  if (inc) {
    expr *new = make_expr(inc>0?ADD:SUB,copy_tree(carg->expr),number_expr(1));

    simplify_expr(new);
    carg->expr = new;
  }
  return nc;
}
#endif


/* Switch to a named offset section which defines the structure. */
int new_structure(char *name)
{
  hashdata data;

  if (cur_struct) {
    general_error(48);  /* cannot declare structure within structure */
    return 0;
  }

  struct_prevsect = current_section;
  switch_offset_section(name,-1);
  data.ptr = cur_struct = current_section;
  add_hashentry(structhash,cur_struct->name,data);
  return 1;
}

/* Finish the structure definition and return the previous section. */
int end_structure(section **prev)
{
  if (cur_struct) {
    *prev = struct_prevsect;
    cur_struct = struct_prevsect = NULL;
    return 1;
  }
  general_error(49);  /* no structure */
  return 0;
}


section *find_structure(char *name,int name_len)
{
  hashdata data;
  section *s;

  if (find_namelen(structhash,name,name_len,&data))
    s = data.ptr;
  else
    s = NULL;
  return s;
}


/* reads the next input line */
char *read_next_line(void)
{
  char *s,*srcend,*d;
  int nparam;
  int len = MAXLINELENGTH-1;
  char *rept_end = NULL;

  /* check if end of source is reached */
  for (;;) {
    srcend = cur_src->text + cur_src->size;
    if (cur_src->srcptr >= srcend || *(cur_src->srcptr) == '\0') {
      if (--cur_src->repeat > 0) {
        cur_src->srcptr = cur_src->text;  /* back to start */
        cur_src->line = 0;
#ifdef REPTNSYM
        set_internal_abs(REPTNSYM,++cur_src->reptn);
#endif
      }
      else {
        myfree(cur_src->linebuf);  /* linebuf is no longer needed, saves memory */
        cur_src->linebuf = NULL;
        if (cur_src->parent == NULL)
          return NULL;  /* no parent source means end of assembly! */
        cur_src = cur_src->parent;  /* return to parent source */
#ifdef CARGSYM
        if (cur_src->cargexp) {
          symbol *carg = internal_abs(CARGSYM);
          carg->expr = cur_src->cargexp;  /* restore parent CARG */
        }
#endif
#ifdef REPTNSYM
        set_internal_abs(REPTNSYM,cur_src->reptn);  /* restore parent REPTN */
#endif
      }
    }
    else
      break;
  }

  cur_src->line++;
  s = cur_src->srcptr;
  d = cur_src->linebuf;
  nparam = cur_src->num_params;

  if (enddir_list!=NULL && (srcend-s)>enddir_minlen) {
    /* reading a definition, like a macro or a repeat-block, until an
       end directive is found */
    struct namelen *dir;
    int rept_nest = 1;

    if (nparam>=0 && cur_macro!=NULL)
        general_error(26,cur_src->name);  /* macro definition inside macro */

    while (s <= (srcend-enddir_minlen)) {
      if (dir = dirlist_match(s,srcend,enddir_list)) {
        if (cur_macro != NULL) {
          add_macro();  /* link macro-definition into hash-table */
          s += dir->len;
          enddir_list = NULL;
          break;
        }
        else if (--rept_nest == 0) {
          rept_end = s;
          s += dir->len;
          enddir_list = NULL;
          break;
        }
      }
      else if (cur_macro==NULL && reptdir_list!=NULL &&
               (dir = dirlist_match(s,srcend,reptdir_list)) != NULL) {
        s += dir->len;
        rept_nest++;
      }

      if (*s=='\"' || *s=='\'') {
        char c = *s++;

        while (s<=(srcend-enddir_minlen) && *s!=c && *s!='\n' && *s!='\r') {
          if (*s == '\\')
            s++;
          s++;
        }
      }

      if (*s == commentchar)
        s = skip_eol(s,srcend);

      if (*s == '\n') {
        cur_src->srcptr = s + 1;
        cur_src->line++;
      }
      else if (*s=='\r' && *(s-1)!='\n' && (s>=(srcend-1) || *(s+1)!='\n')) {
        cur_src->srcptr = s + 1;
        cur_src->line++;
      }
      s++;
    }

    if (enddir_list) {
      if (cur_macro)
        general_error(25,cur_macro->name);  /* missing ENDM directive */
      else
        general_error(32);  /* missing ENDR directive */
    }

    /* ignore rest of line, treat as comment */
    s = skip_eol(s,srcend);
  }

  /* copy next line to linebuf */
  while (s<srcend && *s!='\0' && *s!='\n') {

    if (nparam>=0 && *s=='\\') {
      /* insert macro parameters */
      struct macarg *ma;
      int ma_idx;
      int nc = -1;

      if (*(s+1) == '\\') {
      	*d++ = '\\';
        nc = 1;
        if (esc_sequences) {
        	*d++ = '\\';
          nc = 2;
        }
      	s += 2;
      }
      else if (*(s+1) == '@') {
        /* \@ : insert a unique id "_nnnnnn" */
        if (len >= 7) {
          unsigned long unique_id = cur_src->id;

          *d++ = '_';
          len--;
          s += 2;
          if (*s == '!') {
            /* push id onto stack */
            if (id_stack_index >= IDSTACKSIZE)
              general_error(39);  /* id stack overflow */
            else
              id_stack[id_stack_index++] = unique_id;
            ++s;              
          }
          else if (*s == '?') {
            /* push id below the top item on the stack */
            if (id_stack_index >= IDSTACKSIZE)
              general_error(39);  /* id stack overflow */
            else if (id_stack_index <= 0)
              general_error(45);  /* insert on empty id stack */
            else {
              id_stack[id_stack_index] = id_stack[id_stack_index-1];
              id_stack[id_stack_index-1] = unique_id;
              ++id_stack_index;
            }
            ++s;
          }
          else if (*s == '@') {
            /* pull id from stack */
            if (id_stack_index <= 0)
              general_error(40);  /* id pull without matching push */
            else
              unique_id = id_stack[--id_stack_index];
            ++s;
          }
          nc = sprintf(d, "%06lu", unique_id);
        }
      }
      else if (*(s+1) == '#') {
        /* \# : insert number of parameters */
        if (len >= 2) {
          nc = sprintf(d,"%d",cur_src->num_params);
          s += 2;
        }
      }
      else if (*(s+1)=='?' && isdigit((unsigned char)*(s+2))) {
        /* \?n : insert parameter n length */
        if (len >= 3) {
          nc = sprintf(d,"%d",cur_src->param_len[*(s+2)-'0']);
          s += 3;
        }
      }
#ifdef CARGSYM
      else if (*(s+1) == '.') {
        /* \. : insert parameter #CARG */
        nc = copy_macro_carg(0,d,len);
        s += 2;
      }
      else if (*(s+1) == '+') {
        /* \+ : insert parameter #CARG and increment CARG */
        nc = copy_macro_carg(1,d,len);
        s += 2;
      }
      else if (*(s+1) == '-') {
        /* \- : insert parameter #CARG and decrement CARG */
        nc = copy_macro_carg(-1,d,len);
        s += 2;
      }
#endif
      else if (isdigit((unsigned char)*(s+1))) {
        /* \0..\9 : insert macro parameter 0..9 */
        nc = copy_macro_param(*(s+1)-'0',d,len);
        s += 2;
      }
      else if (namedmacparams && ISIDSTART(*(s+1)) &&
               (ma_idx = find_param_name(s+1,&nc)) > 0) {
         /* \argname : insert named macro parameter ma_idx */
        s += nc + 1;
        nc = copy_macro_param(ma_idx,d,len);
      }
      else if (maxmacparams>10 && !namedmacparams &&
               tolower((unsigned char)*(s+1))>='a' &&
               tolower((unsigned char)*(s+1))<('a'+maxmacparams-10)) {
        /* \a..\z : insert macro parameter 10..36 */
        nc = copy_macro_param(tolower((unsigned char)*(s+1))-'a'+10,d,len);
        s += 2;
      }
      else if (*(s+1)=='(' && *(s+2)==')') {
        /* \() is just skipped, useful to terminate named macro parameters */
        nc = 0;
        s += 3;
      }
      if (nc >= 0) {
        len -= nc;
        d += nc;
        continue;
      }
    }

    else if (*s == '\r') {
      if ((s>cur_src->srcptr && *(s-1)=='\n') ||
          (s<(srcend-1) && *(s+1)=='\n')) {
        /* ignore \r in \r\n and \n\r combinations */
        s++;
        continue;
      }
      else {
        /* treat a single \r as \n */
        s++;
        break;
      }
    }

    if (len > 0) {
      *d++ = *s++;
      len--;
    }
    else
      s++;  /* line buffer is full, ignore additional characters */
  }

  *d = '\0';
  if (s<srcend && *s=='\n')
    s++;
  cur_src->srcptr = s;

  if (listena) {
    listing *new = mymalloc(sizeof(*new));

    new->next = 0;
    new->line = cur_src->line;
    new->error = 0;
    new->atom = 0;
    new->sec = 0;
    new->pc = 0;
    new->src = cur_src;
    strncpy(new->txt,cur_src->linebuf,MAXLISTSRC);
    if (first_listing) {
      last_listing->next = new;
      last_listing = new;
    }
    else {
      first_listing = last_listing = new;
    }
    cur_listing = new;
  }

  s = cur_src->linebuf;
  if (rept_end)
    start_repeat(rept_end);
  return s;
}


int init_parse(void)
{
  macrohash = new_hashtable(MACROHTABSIZE);
  structhash = new_hashtable(STRUCTHTABSIZE);
#ifdef CARGSYM
  carg1 = number_expr(1);
#endif
  return 1;
}
