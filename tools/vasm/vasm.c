/* vasm.c  main module for vasm */
/* (c) in 2002-2013 by Volker Barthelmann */

#include <stdlib.h>
#include <stdio.h>

#include "vasm.h"

#define _VER "vasm 1.6b"
char *copyright = _VER " (c) in 2002-2013 Volker Barthelmann";
#ifdef AMIGA
static const char *_ver = "$VER: " _VER " " __AMIGADATE__ "\r\n";
#endif

#define SRCREADINC (64*1024)  /* extend buffer in these steps when reading */
#define MAXPASSES 1000        /* break when MAXPASSES are reached */

source *cur_src=NULL;
char *filename,*debug_filename;
section *current_section;
char *inname,*outname,*listname;
int secname_attr;
int unnamed_sections;
int ignore_multinc;
int nocase;
int no_symbols;
int pic_check;
int done,final_pass,debug;
int listena,listformfeed=1,listlinesperpage=40,listnosyms;
listing *first_listing,*last_listing,*cur_listing;
char *output_format="test";
unsigned long long taddrmask;
char emptystr[]="";
char vasmsym_name[]="__VASM";

static int produce_listing;
static char **listtitles;
static int *listtitlelines;
static int listtitlecnt;

static FILE *outfile=NULL;

static section *first_section,*last_section;
static symbol *first_symbol=NULL;

static taddr rorg_pc=0;
static taddr org_pc;

/* MNEMOHTABSIZE should be defined by cpu module */
#ifndef MNEMOHTABSIZE
#define MNEMOHTABSIZE 0x1000
#endif
hashtable *mnemohash;

#ifndef SYMHTABSIZE
#define SYMHTABSIZE 0x10000
#endif
static hashtable *symhash;

static int verbose=1,auto_import=1;
static char *last_global_label=emptystr;
static struct include_path *first_incpath=NULL;
static struct include_path *first_source=NULL;

static char *output_copyright;
static void (*write_object)(FILE *,section *,symbol *);
static int (*output_args)(char *);


void leave(void)
{
  section *sec;
  symbol *sym;
  
  if(outfile){
    fclose(outfile);
    if (errors)
      remove(outname);
  }

  if(debug){
    fprintf(stdout,"Sections:\n");
    for(sec=first_section;sec;sec=sec->next)
      print_section(stdout,sec);

    fprintf(stdout,"Symbols:\n");
    for(sym=first_symbol;sym;sym=sym->next){
      print_symbol(stdout,sym);
      fprintf(stdout,"\n");
    }
  }

  if(errors)
    exit(EXIT_FAILURE);
  else
    exit(EXIT_SUCCESS);
}

void fail(char *msg)
{
  general_error(19,msg);
}

/* Removes all unallocated (offset) sections from the list and converts
   their label symbols into absolute expressions. */
static void remove_unalloc_sects(void)
{
  section *prev,*sec;
  symbol *sym;

  for (sym=first_symbol; sym; sym=sym->next) {
    if (sym->type==LABSYM && sym->sec!=NULL && (sym->sec->flags&UNALLOCATED)) {
      sym->type = EXPRESSION;
      sym->expr = number_expr(sym->pc);
      sym->sec = NULL;
    }
  }
  for (sec=first_section,prev=NULL; sec; sec=sec->next) {
    if (sec->flags&UNALLOCATED) {
      if (prev)
        prev->next = sec->next;
      else
        first_section = sec->next;
    }
    else
      prev = sec;
  }
}

static void resolve_section(section *sec)
{
  atom *p;
  int pass=0;
  taddr size;
  do{
    done=1;
    if(debug)
      printf("resolve_section(%s) pass %d\n",sec->name,pass);
    if (++pass>=MAXPASSES){
      general_error(7,sec->name);
      break;
    }else if (pass>=MAXPASSES/2){
      if(debug&&!(sec->flags&RESOLVE_WARN))
        printf("setting resolve-warning flag\n");
      sec->flags|=RESOLVE_WARN;
    }
    sec->pc=sec->org;
    for(p=sec->first;p;p=p->next){
      sec->pc=(sec->pc+p->align-1)/p->align*p->align;
      cur_src=p->src;
      cur_src->line=p->line;
#if HAVE_CPU_OPTS
      if(p->type==OPTS){
        cpu_opts(p->content.opts);
      }
      else
#endif
      if(p->type==RORG){
        if(rorg_pc!=0)
          general_error(43);  /* reloc org is already set */
        rorg_pc=*p->content.rorg;
        org_pc=sec->pc;
        sec->pc=rorg_pc;
      }
      else if(p->type==RORGEND&&rorg_pc!=0){
        sec->pc=org_pc+(sec->pc-rorg_pc);
        rorg_pc=0;
      }
      else if(p->type==LABEL){
        symbol *label=p->content.label;
        if(label->type!=LABSYM)
          ierror(0);
        if(label->pc!=sec->pc){
          if(debug)
            printf("changing label %s from %lu to %lu\n",label->name,
                   (unsigned long)label->pc,(unsigned long)sec->pc);
          done=0;
          label->pc=sec->pc;
        }
      }
      size=atom_size(p,sec,sec->pc);
#if CHECK_ATOMSIZE
      if(size!=p->lastsize){
        if(debug)
          printf("changed size of atom type %d at %lu from %ld to %ld\n",
                 p->type,(unsigned long)sec->pc,(long)p->lastsize,(long)size);
        done=0;
        p->lastsize=size;
      }
#endif
      sec->pc+=size;
    }
  }while(errors==0&&!done);
}

static void resolve(void)
{
  section *sec;
  final_pass=0;
  if(debug)
    printf("resolve()\n");
  for(sec=first_section;sec;sec=sec->next)
    resolve_section(sec);
}

static void assemble(void)
{
  section *sec;
  taddr oldpc;
  atom *p;
  char *attr;
  int bss;

  remove_unalloc_sects();
  final_pass=1;
  for(sec=first_section;sec;sec=sec->next){
    source *lasterrsrc=NULL;
    int lasterrline=0;
    sec->pc=sec->org;
    attr=sec->attr;
    bss=0;
    while(*attr){
      if(*attr++=='u'){
        bss=1;
        break;
      }
    }
    for(p=sec->first;p;p=p->next){
      oldpc=sec->pc;
      sec->pc=(sec->pc+p->align-1)/p->align*p->align;
      cur_src=p->src;
      cur_src->line=p->line;
      if(p->list&&p->list->atom==p){
        p->list->sec=sec;
        p->list->pc=sec->pc;
      }
      if(p->type==RORG&&rorg_pc==0){
        rorg_pc=*p->content.rorg;
        org_pc=sec->pc;
        sec->pc=rorg_pc;
      }
      else if(p->type==RORGEND){
        if(rorg_pc!=0){
          sec->pc=org_pc+(sec->pc-rorg_pc);
          rorg_pc=0;
        }
        else
          general_error(44);  /* reloc org was not set */
      }
      else if(p->type==INSTRUCTION){
        dblock *db;
        if(sec->pc!=oldpc)
          general_error(50);  /* instruction had been auto-aligned */
        cur_listing=p->list;
        db=eval_instruction(p->content.inst,sec,sec->pc);
        if(pic_check)
          do_pic_check(db->relocs);
        cur_listing=0;
        if(debug){
          if(db->size!=instruction_size(p->content.inst,sec,sec->pc))
            ierror(0);
        }
        /*FIXME: sauber freigeben */
        myfree(p->content.inst);
        p->content.db=db;
        p->type=DATA;
      }
      else if(p->type==DATADEF){
        dblock *db;
        cur_listing=p->list;
        db=eval_data(p->content.defb->op,p->content.defb->bitsize,sec,sec->pc);
        if(pic_check)
          do_pic_check(db->relocs);
        cur_listing=0;
        /*FIXME: sauber freigeben */
        myfree(p->content.defb);
        p->content.db=db;
        p->type=DATA;
      }
      else if(p->type==ROFFS){
        sblock *sb;
        taddr space;
        if(eval_expr(p->content.roffs,&space,sec,sec->pc)){
          space=sec->org+space-sec->pc;
          if (space>=0){
            sb=new_sblock(number_expr(space),1,0);
            p->content.sb=sb;
            p->type=SPACE;
          }
          else
            general_error(20);  /* rorg is lower than current pc */
        }
        else
          general_error(30);  /* expression must be constant */
      }
      else if(p->type==DATA&&bss){
        if(lasterrsrc!=p->src||lasterrline!=p->line){
          general_error(31);  /* initialized data in bss */
          lasterrsrc=p->src;
          lasterrline=p->line;
        }
      }
#if HAVE_CPU_OPTS
      else if(p->type==OPTS)
        cpu_opts(p->content.opts);
#endif
      else if(p->type==PRINTTEXT)
        printf("%s\n",p->content.ptext);
      else if(p->type==PRINTEXPR){
        taddr val;
        eval_expr(p->content.pexpr,&val,sec,sec->pc);
        printf("%ld (0x%lx)\n",(long)val,(unsigned long)val);
      }
      else if(p->type==ASSERT){
        assertion *ast=p->content.assert;
        taddr val;
        eval_expr(ast->assert_exp,&val,sec,sec->pc);
        if(val==0)
          general_error(47,ast->expstr,ast->msgstr?ast->msgstr:emptystr);
      }

      sec->pc+=atom_size(p,sec,sec->pc);
    }
  }
}

static void undef_syms(void)
{
  symbol *sym;

  for(sym=first_symbol;sym;sym=sym->next){
    if (sym->type==IMPORT&&!(sym->flags&(EXPORT|COMMON|WEAK)))
      general_error(22,sym->name);
  }
}

/* All expressions which are based on a label are turned into a new label. */
static void label_expressions(void)
{
  symbol *sym,*base;
  taddr val;

  for(sym=first_symbol;sym;sym=sym->next){
    if(sym->type==EXPRESSION){
      if(!eval_expr(sym->expr,&val,NULL,0)){
        if(find_base(sym->expr,&base,NULL,0)==BASE_OK){
          /* turn into an offseted label symbol from the base's section */
          sym->type=LABSYM;
          sym->sec=base->sec;
          sym->pc=val;
          sym->align=1;
        }else
          general_error(53,sym->name);  /* non-relocatable expr. in equate */
      }
    }
  }
}

static void statistics(void)
{
  section *sec;
  unsigned long long size;

  printf("\n");
  for(sec=first_section;sec;sec=sec->next){
    size=UNS_TADDR(UNS_TADDR(sec->pc)-UNS_TADDR(sec->org));
    printf("%s(%s%lu):\t%12llu byte%c\n",sec->name,sec->attr,
           (unsigned long)sec->align,size,size==1?' ':'s');
  }
}

static int init_output(char *fmt)
{
  if(!strcmp(fmt,"test"))
    return init_output_test(&output_copyright,&write_object,&output_args);
  if(!strcmp(fmt,"elf"))
    return init_output_elf(&output_copyright,&write_object,&output_args);  
  if(!strcmp(fmt,"bin"))
    return init_output_bin(&output_copyright,&write_object,&output_args);
  if(!strcmp(fmt,"vobj"))
    return init_output_vobj(&output_copyright,&write_object,&output_args);  
  if(!strcmp(fmt,"hunk"))
    return init_output_hunk(&output_copyright,&write_object,&output_args);
  if(!strcmp(fmt,"hunkexe"))
    return init_output_hunkexe(&output_copyright,&write_object,&output_args);
  if(!strcmp(fmt,"aout"))
    return init_output_aout(&output_copyright,&write_object,&output_args);
  if(!strcmp(fmt,"tos"))
    return init_output_tos(&output_copyright,&write_object,&output_args);
  return 0;
}

static int init_main(void)
{
  size_t i;
  char *last;
  hashdata data;
  mnemohash=new_hashtable(MNEMOHTABSIZE);
  i=0;
  while(i<mnemonic_cnt){
    data.idx=i;
    last=mnemonics[i].name;
    add_hashentry(mnemohash,mnemonics[i].name,data);
    do{
      i++;
    }while(i<mnemonic_cnt&&!strcmp(last,mnemonics[i].name));
  }
  if(debug){
    if(mnemohash->collisions)
      printf("*** %d mnemonic collisions!!\n",mnemohash->collisions);
  }
  symhash=new_hashtable(SYMHTABSIZE);
  new_include_path(".");
  taddrmask=MAKEMASK(bytespertaddr<<3);
  return 1;
}

void set_default_output_format(char *fmt)
{
  output_format=fmt;
}

int main(int argc,char **argv)
{
  int i;
  for(i=1;i<argc;i++){
    if(argv[i][0]=='-'&&argv[i][1]=='F'){
      output_format=argv[i]+2;
      argv[i][0]=0;
    }
    if(!strcmp("-quiet",argv[i])){
      verbose=0;
      argv[i][0]=0;
    }
    if(!strcmp("-debug",argv[i])){
      debug=1;
      argv[i][0]=0;
    }
  }
  if(!init_output(output_format))
    general_error(16,output_format);
  if(!init_main())
    general_error(10,"main");
  if(verbose)
    printf("%s\n%s\n%s\n%s\n",copyright,cpu_copyright,syntax_copyright,output_copyright);
  for(i=1;i<argc;i++){
    if(argv[i][0]==0)
      continue;
    if(argv[i][0]!='-'){
      if(inname)
        general_error(11);
      inname=argv[i];
      continue;
    }
    if(!strcmp("-o",argv[i])&&i<argc-1){
      if(outname)
        general_error(28,'o');
      outname=argv[++i];
      continue;
    }
    if(!strcmp("-L",argv[i])&&i<argc-1){
      if(listname)
        general_error(28,'L');
      listname=argv[++i];
      produce_listing=1;
      continue;
    }
    if(!strcmp("-Lnf",argv[i])){
      listformfeed=0;
      continue;
    }
    if(!strcmp("-Lns",argv[i])){
      listnosyms=1;
      continue;
    }
    if(!strncmp("-Ll",argv[i],3)){
      sscanf(argv[i]+3,"%i",&listlinesperpage);
      continue;
    }
    if(!strncmp("-D",argv[i],2)){
      char *def=NULL;
      expr *val;
      if(argv[i][2])
        def=&argv[i][2];
      else if (i<argc-1)
        def=argv[++i];
      if(def){
        char *s=def;
        if(ISIDSTART(*s)){
          s++;
          while(ISIDCHAR(*s))
            s++;
          def=cnvstr(def,s-def);
          if(*s=='='){
            s++;
            val=parse_expr(&s);
          }
          else
            val=number_expr(1);
          if(*s)
            general_error(23,'D');  /* trailing garbage after option */
          new_abs(def,val);
          myfree(def);
          continue;
        }
      }
    }
    if(!strncmp("-I",argv[i],2)){
      char *path=NULL;
      if(argv[i][2])
        path=&argv[i][2];
      else if (i<argc-1)
        path=argv[++i];
      if(path){
        new_include_path(path);
        continue;
      }
    }
    if(!strcmp("-unnamed-sections",argv[i])){
      unnamed_sections=1;
      continue;
    }
    if(!strcmp("-ignore-mult-inc",argv[i])){
      ignore_multinc=1;
      continue;
    }
    if(!strcmp("-nocase",argv[i])){
      nocase=1;
      continue;
    }
    if(!strcmp("-noesc",argv[i])){
      esc_sequences=0;
      continue;
    }
    if(!strcmp("-nosym",argv[i])){
      no_symbols=1;
      continue;
    }
    if(!strncmp("-nowarn=",argv[i],8)){
      int wno;
      sscanf(argv[i]+8,"%i",&wno);
      disable_warning(wno);
      continue;
    }
    else if(!strcmp("-w",argv[i])){
      no_warn=1;
      continue;
    }
    if(!strncmp("-maxerrors=",argv[i],11)){
      sscanf(argv[i]+11,"%i",&max_errors);
      continue;
    }
    else if(!strcmp("-pic",argv[i])){
      pic_check=1;
      continue;
    }
    if(cpu_args(argv[i]))
      continue;
    if(syntax_args(argv[i]))
      continue;
    if(output_args(argv[i]))
      continue;
    if (!strncmp("-x",argv[i],2)){
      auto_import=0;
      continue;
    }
    general_error(14,argv[i]);
  }
  if(inname){
    setfilename(inname);
    setdebugname(inname);
    include_source(inname);
  }else
    general_error(15);
  internal_abs(vasmsym_name);
  if(!init_parse())
    general_error(10,"parse");
  if(!init_syntax())
    general_error(10,"syntax");
  if(!init_cpu())
    general_error(10,"cpu");
  parse();
  if(errors==0||produce_listing)
    resolve();
  if(errors==0||produce_listing)
    assemble();
  if(!auto_import)
    undef_syms();
  label_expressions();
  if(!listname)
    listname="a.lst";
  if(produce_listing)
    write_listing(listname);
  if(!outname)
    outname="a.out";
  if(errors==0){
    if(verbose)
      statistics();
    outfile=fopen(outname,"wb");
    if(!outfile)
      general_error(13,outname);
    write_object(outfile,first_section,first_symbol);
  }
  leave();
  return 0; /* not reached */
}

FILE *locate_file(char *filename,char *mode)
{
  char pathbuf[MAXPATHLEN];
  struct include_path *ipath;
  FILE *f;

  if (*filename=='.' || *filename=='/' || *filename=='\\' ||
      strchr(filename,':')!=NULL) {
    /* file name is absolute, then don't use any include paths */
    if (f = fopen(filename,mode))
      return f;
  }
  else {
    /* locate file name in all known include paths */
    for (ipath=first_incpath; ipath; ipath=ipath->next) {
      if (strlen(ipath->path) + strlen(filename) + 1 <= MAXPATHLEN) {
        strcpy(pathbuf,ipath->path);
        strcat(pathbuf,filename);
        if (f = fopen(pathbuf,mode))
          return f;
      }
    }
  }
  general_error(12,filename);
  return NULL;
}

void include_source(char *inname)
{
  char *filename;
  struct include_path **nptr = &first_source;
  struct include_path *name;
  FILE *f;

  filename = convert_path(inname);

  /* check whether this source was already included */
  while (name = *nptr) {
#if defined(AMIGA) || defined(MSDOS) || defined(_WIN32)
    if (!stricmp(name->path,filename)) {
#else
    if (!strcmp(name->path,filename)) {
#endif
      myfree(filename);
      if (!ignore_multinc) {
        filename = name->path;
        /* reuse already read file from cache? */
      }
      nptr = NULL;  /* ignore including this source */
      break;
    }
    nptr = &name->next;
  }
  if (nptr) {
    name = mymalloc(sizeof(struct include_path));
    name->next = NULL;
    name->path = filename;
    *nptr = name;
  }
  else if (ignore_multinc)
    return;  /* ignore multiple inclusion of this source completely */

  if (f = locate_file(filename,"r")) {
    char *text;
    size_t size;

    for (text=NULL,size=0; ; size+=SRCREADINC) {
      size_t nchar;
      text = myrealloc(text,size+SRCREADINC);
      nchar = fread(text+size,1,SRCREADINC,f);
      if (nchar < SRCREADINC) {
        size += nchar;
        break;
      }
    }
    if (feof(f)) {
      if (size > 0) {
        cur_src = new_source(filename,myrealloc(text,size+1),size+1);
        *(cur_src->text+size) = '\n';
      }
      else {
        myfree(text);
        cur_src = new_source(filename,"\n",1);
      }
    }
    else
      general_error(29,filename);
    fclose(f);
  }
}

/* searches a section by name and attr (if secname_attr set) */
section *find_section(char *name,char *attr)
{
  section *p;
  if(secname_attr){
    for(p=first_section;p;p=p->next){
      if(!strcmp(name,p->name) && !strcmp(attr,p->attr))
        return p;
    }
  }
  else{
    for(p=first_section;p;p=p->next){
      if(!strcmp(name,p->name))
        return p;
    }
  }
  return 0;
}

/* create a new source text instance, which has cur_src as parent */
source *new_source(char *filename,char *text,size_t size)
{
  static unsigned long id = 0;
  source *s = mymalloc(sizeof(source));

  s->parent = cur_src;
  s->parent_line = cur_src ? cur_src->line : 0;
  s->name = mystrdup(filename);
  s->text = text;
  s->size = size;
  s->repeat = 1;      /* read just once */
  s->num_params = -1; /* not a macro, no parameters */
  s->param[0] = emptystr;
  s->param_len[0] = 0;
  s->id = id++;	      /* every source has a unique id - important for macros */
  s->srcptr = text;
  s->line = 0;
  s->linebuf = mymalloc(MAXLINELENGTH);
#ifdef CARGSYM
  s->cargexp = NULL;
#endif
#ifdef REPTNSYM
  s->reptn = -1;      /* outside of a rept-endr block */
#endif
  return s;
}

/* creates a new section with given attributes and alignment;
   does not switch to this section automatically */
section *new_section(char *name,char *attr,int align)
{
  section *p;
  if(unnamed_sections)
    name=emptystr;
  if(p=find_section(name,attr))
    return p;
  p=mymalloc(sizeof(*p));
  p->next=0;
  p->name=mystrdup(name);
  p->attr=mystrdup(attr);
  p->first=p->last=0;
  p->align=align;
  p->org=p->pc=0;
  p->flags=0;
  if(last_section)
    last_section=last_section->next=p;
  else
    first_section=last_section=p;
  return p;
}

/* create a dummy code section for each new ORG directive and
   switches to it */
void new_org(taddr org)
{
  char buf[16];
  section *sec;

  sprintf(buf,"seg%llx",UNS_TADDR(org));
  sec = new_section(buf,"acrwx",1);
  sec->org = sec->pc = org;
  current_section = sec;
#if HAVE_CPU_OPTS
  cpu_opts_init(sec);  /* set initial cpu opts before the first atom */
#endif
}

/* switches current section to the section with the specified name */
void switch_section(char *name,char *attr)
{
  section *p;
  if(unnamed_sections)
    name=emptystr;
  p=find_section(name,attr);
  if(!p)
    general_error(2,name);
  else
    current_section=p;
#if HAVE_CPU_OPTS
  cpu_opts_init(p);  /* set initial cpu opts before the first atom */
#endif
}

/* Switches current section to an offset section. Create a new section when
   it doesn't exist yet or needs a different offset. */
void switch_offset_section(char *name,taddr offs)
{
  static unsigned long id;
  char unique_name[14];
  section *sec;

  if (!name) {
    if (offs != -1)
      ++id;
    sprintf(unique_name,"OFFSET%06lu",id);
    name = unique_name;
  }
  sec = new_section(name,"u",1);
  sec->flags |= UNALLOCATED;
  if (offs != -1)
    sec->org = sec->pc = offs;
  current_section = sec;
#if HAVE_CPU_OPTS
  cpu_opts_init(sec);  /* set initial cpu opts before the first atom */
#endif
}

/* returns current_section or the syntax module's default section,
   when undefined */
section *default_section(void)
{
  section *sec = current_section;

  if (!sec && defsectname && defsecttype) {
    sec = new_section(defsectname,defsecttype,1);
    switch_section(defsectname,defsecttype);
  }
  return sec;
}

void print_section(FILE *f,section *sec)
{
  atom *p;
  taddr pc=sec->org;
  fprintf(f,"section %s (attr=<%s> align=%llu):\n",
          sec->name,sec->attr,UNS_TADDR(sec->align));
  for(p=sec->first;p;p=p->next){
    pc=(pc+p->align-1)/p->align*p->align;
    fprintf(f,"%8llx: ",UNS_TADDR(pc));
    print_atom(f,p);
    fprintf(f,"\n");
    pc+=atom_size(p,sec,pc);
  }
}

static void print_type(FILE *f,symbol *p)
{
  static const char *typename[] = {"???","obj","func","sect","file"};
  if(p==NULL)
    ierror(0);
  fprintf(f,"type=%s ",typename[TYPE(p)]);
}

void print_symbol(FILE *f,symbol *p)
{
  if(p==NULL)
    ierror(0);	/* this is usually an error in a cpu-backend, don't crash! */
  fprintf(f,"%s ",p->name);
  if(p->type==LABSYM)
    fprintf(f,"LAB (0x%llx) ",UNS_TADDR(p->pc));
  if(p->type==IMPORT)
    fprintf(f,"IMP ");
  if(p->type==EXPRESSION){
    fprintf(f,"EXPR(");
    print_expr(f,p->expr);
    fprintf(f,") ");
  }
  if(p->flags&VASMINTERN)
    fprintf(f,"INTERNAL ");
  if(p->flags&EXPORT)
    fprintf(f,"EXPORT ");
  if(p->flags&COMMON)
    fprintf(f,"COMMON ");
  if(p->flags&WEAK)
    fprintf(f,"WEAK ");
  if(TYPE(p))
    print_type(f,p);
  if(p->size){
    fprintf(f,"size=");
    print_expr(f,p->size);
    fprintf(f," ");
  }
  if(p->align)
    fprintf(f,"align=%lu ",(unsigned long)p->align);
  if(p->sec)
    fprintf(f,"sec=%s ",p->sec->name);
}

void add_symbol(symbol *p)
{
  hashdata data;
  p->next=first_symbol;
  first_symbol=p;
  data.ptr=p;
  add_hashentry(symhash,p->name,data);
}

symbol *find_symbol(char *name)
{
  hashdata data;
  if(!find_name(symhash,name,&data))
    return 0;
  return data.ptr;
}

char *make_local_label(char *glob,int glen,char *loc,int llen)
/* construct a local label of the form:
   " " + global_label_name + " " + local_label_name */
{
  char *name,*p;

  if (glen == 0) {
    /* use the last defined global label */
    glob = last_global_label;
    glen = strlen(last_global_label);
  }
  p = name = mymalloc(llen+glen+3);
  *p++ = ' ';
  if (glen) {
    memcpy(p,glob,glen);
    p += glen;
  }
  *p++ = ' ';
  memcpy(p,loc,llen);
  *(p + llen) = '\0';
  return name;
}

symbol *new_abs(char *name,expr *tree)
{
  symbol *new=find_symbol(name);
  int add;
  if(new){
    if(new->type!=IMPORT&&new->type!=EXPRESSION)
      general_error(5,name);
    add=0;
  }else{
    new=mymalloc(sizeof(*new));
    new->name=mystrdup(name);
    add=1;
  }
  new->type=EXPRESSION;
  new->sec=0;
  new->expr=tree;
  if(add){
    add_symbol(new);
    new->flags=0;
    new->size=0;
    new->align=0;
  }
  return new;
}

symbol *new_import(char *name)
{
  symbol *new=find_symbol(name);
  if(new)
    return new;
  new=mymalloc(sizeof(*new));
  new->type=IMPORT;
  new->flags=0;
  new->name=mystrdup(name);
  new->sec=0;
  new->pc=0;
  new->size=0;
  new->align=0;
  add_symbol(new);
  return new;
}

symbol *new_labsym(section *sec,char *name)
{
  symbol *new;
  int add;

  if(!sec){
    sec=default_section();
    if(!sec){
      general_error(3);
      return new_import(name);
    }
  }
  sec->flags|=HAS_SYMBOLS;
  if(sec->flags&LABELS_ARE_LOCAL)
    name=make_local_label(sec->name,strlen(sec->name),name,strlen(name));
  if(new=find_symbol(name)){
    if(new->type!=IMPORT){
      symbol *old = new;
      new=mymalloc(sizeof(*new));
      *new = *old;
      general_error(5,name);
    }
    add=0;
  }else{
    new=mymalloc(sizeof(*new));
    if(sec->flags&LABELS_ARE_LOCAL)
      new->name=name;
    else
      new->name=mystrdup(name);
    add=1;
  }
  new->type=LABSYM;
  new->sec=sec;
  new->pc=sec->pc;
  if(add){
    add_symbol(new);
    new->flags=0;
    new->size=0;
    new->align=0;
  }
  if(*name!=' ')
    last_global_label=new->name;
  return new;
}

symbol *new_tmplabel(section *sec)
{
  static unsigned long tmplabcnt=0;
  char tmpnam[16];

  sprintf(tmpnam," *tmp%09lu*",tmplabcnt++);
  return new_labsym(sec,tmpnam);
}

symbol *internal_abs(char *name)
{
  symbol *new = find_symbol(name);

  if (new) {
    if (new->type!=EXPRESSION || (new->flags&(EXPORT|COMMON|WEAK)))
      general_error(37,name);  /* internal symbol redefined by user */
  }
  else {
    new = new_abs(name,number_expr(0));
    new->flags |= VASMINTERN;
  }
  return new;
}

expr *set_internal_abs(char *name,taddr newval)
{
  symbol *sym = internal_abs(name);
  expr *oldexpr = sym->expr;
  taddr oldval;

  if (oldexpr == NULL)
    ierror(0);
  eval_expr(oldexpr,&oldval,NULL,0);
  if (newval != oldval)
    sym->expr = number_expr(newval);
  return oldexpr;
}

void new_include_path(char *pathname)
{
  struct include_path *new = mymalloc(sizeof(struct include_path));
  struct include_path *ipath;
  char *newpath = convert_path(pathname);
  int len = strlen(newpath);

#if defined(AMIGA)
  if (len>0 && newpath[len-1]!='/' && newpath[len-1]!=':') {
    pathname = mymalloc(len+2);
    strcpy(pathname,newpath);
    pathname[len] = '/';
    pathname[len+1] = '\0';
  }
#elif defined(MSDOS) || defined(_WIN32)
  if (len>0 && newpath[len-1]!='\\' && newpath[len-1]!=':') {
    pathname = mymalloc(len+2);
    strcpy(pathname,newpath);
    pathname[len] = '\\';
    pathname[len+1] = '\0';
  }
#else
  if (len>0 && newpath[len-1] != '/') {
    pathname = mymalloc(len+2);
    strcpy(pathname,newpath);
    pathname[len] = '/';
    pathname[len+1] = '\0';
  }
#endif
  else
    pathname = mystrdup(newpath);
  myfree(newpath);
  new->next = NULL;
  new->path = pathname;

  if (ipath = first_incpath) {
    while (ipath->next)
      ipath = ipath->next;
    ipath->next = new;
  }
  else
    first_incpath = new;
}

void set_listing(int on)
{
  listena = on && produce_listing;
}

void set_list_title(char *p,int len)
{
  listtitlecnt++;
  listtitles=myrealloc(listtitles,listtitlecnt*sizeof(*listtitles));
  listtitles[listtitlecnt-1]=mymalloc(len+1);
  strncpy(listtitles[listtitlecnt-1],p,len);
  listtitles[listtitlecnt-1][len]=0;
  listtitlelines=myrealloc(listtitlelines,listtitlecnt*sizeof(*listtitlelines));
  listtitlelines[listtitlecnt-1]=cur_src->line;
}

static void print_list_header(FILE *f,int cnt)
{
  if(cnt%listlinesperpage==0){
    if(cnt!=0&&listformfeed)
      fprintf(f,"\f");
    if(listtitlecnt>0){
      int i,t;
      for(i=0,t=-1;i<listtitlecnt;i++){
        if(listtitlelines[i]<=cnt+listlinesperpage)
          t=i;
      }
      if(t>=0){
        int sp=(120-strlen(listtitles[t]))/2;
        while(--sp)
          fprintf(f," ");
        fprintf(f,"%s\n",listtitles[t]);
      }
      cnt++;
    }
    fprintf(f,"Err  Line Loc.  S Object1  Object2  M Source\n");
  }  
}

#if VASM_CPU_OIL
void write_listing(char *listname)
{
  FILE *f;
  int nsecs,i,cnt=0,nl;
  section *secp;
  listing *p;
  atom *a;
  symbol *sym;
  taddr pc;
  char rel;

  if(!(f=fopen(listname,"w"))){
    general_error(13,listname);
    return;
  }
  for(nsecs=0,secp=first_section;secp;secp=secp->next)
    secp->idx=nsecs++;
  for(p=first_listing;p;p=p->next){
    if(!p->src||p->src->id!=0)
      continue;
    print_list_header(f,cnt++);
    if(p->error!=0)
      fprintf(f,"%04d ",p->error);
    else
      fprintf(f,"     ");
    fprintf(f,"%4d ",p->line);
    a=p->atom;
    while(a&&a->type!=DATA&&a->next&&a->next->line==a->line&&a->next->src==a->src)
      a=a->next;
    if(a&&a->type==DATA){
      int size=a->content.db->size;
      char *dp=a->content.db->data;
      pc=p->pc;
      fprintf(f,"%05lX %d ",(unsigned long)pc,(int)(p->sec?p->sec->idx:0));
      for(i=0;i<8;i++){
        if(i==4)
          fprintf(f," ");
        if(i<size){
          fprintf(f,"%02X",(unsigned char)*dp++);
          pc++;
        }else
          fprintf(f,"  ");
        /* append following atoms with align 1 directly */
        if(i==size-1&&i<7&&a->next&&a->next->align<=a->align&&a->next->type==DATA&&a->next->line==a->line&&a->next->src==a->src){
          a=a->next;
          size+=a->content.db->size;
          dp=a->content.db->data;
        }
      }
      fprintf(f," ");
      if(a->content.db->relocs){
        symbol *s=((nreloc *)(a->content.db->relocs->reloc))->sym;
        if(s->type==IMPORT)
          rel='X';
        else
          rel='0'+p->sec->idx;
      }else
        rel='A';
      fprintf(f,"%c ",rel);
    }else
      fprintf(f,"                           ");
    
    fprintf(f," %-.77s",p->txt);

    /* bei laengeren Daten den Rest ueberspringen */
    /* Block entfernen, wenn alles ausgegeben werden soll */
    if(a&&a->type==DATA&&i<a->content.db->size){
      pc+=a->content.db->size-i;
      i=a->content.db->size;
    }

    /* restliche DATA-Zeilen, wenn noetig */
    while(a){
      if(a->type==DATA){
        int size=a->content.db->size;
        char *dp=a->content.db->data+i;

        if(i<size){
          for(;i<size;i++){
            if((i&7)==0){
              fprintf(f,"\n");
              print_list_header(f,cnt++);
              fprintf(f,"          %05lX %d ",(unsigned long)pc,(int)(p->sec?p->sec->idx:0));
            }else if((i&3)==0)
              fprintf(f," ");
            fprintf(f,"%02X",(unsigned char)*dp++);
            pc++;
            /* append following atoms with align 1 directly */
            if(i==size-1&&a->next&&a->next->align<=a->align&&a->next->type==DATA&&a->next->line==a->line&&a->next->src==a->src){
              a=a->next;
              size+=a->content.db->size;
              dp=a->content.db->data;
            }
          }
          i=8-(i&7);
          if(i>=4)
            fprintf(f," ");
          while(i--){
            fprintf(f,"  ");
          }
          fprintf(f," %c",rel);
        }
        i=0;
      }
      if(a->next&&a->next->line==a->line&&a->next->src==a->src){
        a=a->next;
        pc=(pc+a->align-1)/a->align*a->align;
        if(a->type==DATA&&a->content.db->relocs){
          symbol *s=((nreloc *)(a->content.db->relocs->reloc))->sym;
          if(s->type==IMPORT)
            rel='X';
          else
            rel='0'+p->sec->idx;
        }else
          rel='A';      
      }else
        a=0;
    }
    fprintf(f,"\n");
  }
  fprintf(f,"\n\nSections:\n");
  for(secp=first_section;secp;secp=secp->next)
    fprintf(f,"%d  %s\n",(int)secp->idx,secp->name);
  if(!listnosyms){
    fprintf(f,"\n\nSymbols:\n");
    {
      symbol *last=0,*cur,*symo;
      for(symo=first_symbol;symo;symo=symo->next){
        cur=0;
        for(sym=first_symbol;sym;sym=sym->next){
          if(!last||stricmp(sym->name,last->name)>0)
            if(!cur||stricmp(sym->name,cur->name)<0)
              cur=sym;
        }
        if(cur){
          print_symbol(f,cur);
          fprintf(f,"\n");
          last=cur;
        }
      }
    }
  }
  if(errors==0)
    fprintf(f,"\nThere have been no errors.\n");
  else
    fprintf(f,"\nThere have been %d errors!\n",errors);
  fclose(f);
  for(p=first_listing;p;){
    listing *m=p->next;
    myfree(p);
    p=m;
  }
}
#else
void write_listing(char *listname)
{
  FILE *f;
  int nsecs,i,maxsrc=0;
  section *secp;
  listing *p;
  atom *a;
  symbol *sym;
  taddr pc;

  if(!(f=fopen(listname,"w"))){
    general_error(13,listname);
    return;
  }
  for(nsecs=1,secp=first_section;secp;secp=secp->next)
    secp->idx=nsecs++;
  for(p=first_listing;p;p=p->next){
    char err[6];
    if(p->error!=0)
      sprintf(err,"E%04d",p->error);
    else
      sprintf(err,"     ");
    if(p->src&&p->src->id>maxsrc)
      maxsrc=p->src->id;
    fprintf(f,"F%02d:%04d %s %s",(int)(p->src?p->src->id:0),p->line,err,p->txt);
    a=p->atom;
    pc=p->pc;
    while(a){
      if(a->type==DATA){
        int size=a->content.db->size;
        for(i=0;i<size&&i<32;i++){
          if((i&15)==0)
            fprintf(f,"\n               S%02d:%08lX: ",(int)(p->sec?p->sec->idx:0),(unsigned long)(pc));
          fprintf(f," %02X",(unsigned char)a->content.db->data[i]);
          pc++;
        }
        if(a->content.db->relocs)
          fprintf(f," [R]");
      }
      if(a->next&&a->next->line==a->line&&a->next->src==a->src){
        a=a->next;
        pc=(pc+a->align-1)/a->align*a->align;
      }else
        a=0;
    }
    fprintf(f,"\n");
  }
  fprintf(f,"\n\nSections:\n");
  for(secp=first_section;secp;secp=secp->next)
    fprintf(f,"S%02d  %s\n",(int)secp->idx,secp->name);
  fprintf(f,"\n\nSources:\n");
  for(i=0;i<=maxsrc;i++){
    for(p=first_listing;p;p=p->next){
      if(p->src&&p->src->id==i){
        fprintf(f,"F%02d  %s\n",i,p->src->name);
        break;
      }
    }
  }
  fprintf(f,"\n\nSymbols:\n");
  for(sym=first_symbol;sym;sym=sym->next){
    print_symbol(f,sym);
    fprintf(f,"\n");
  }
  if(errors==0)
    fprintf(f,"\nThere have been no errors.\n");
  else
    fprintf(f,"\nThere have been %d errors!\n",errors);
  fclose(f);
  for(p=first_listing;p;){
    listing *m=p->next;
    myfree(p);
    p=m;
  }
}
#endif
