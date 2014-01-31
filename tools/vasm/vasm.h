/* vasm.h  main header file for vasm */
/* (c) in 2002-2013 by Volker Barthelmann */

#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <ctype.h>
#include <string.h>

typedef struct symbol symbol;
typedef struct section section;
typedef struct dblock dblock;
typedef struct sblock sblock;
typedef struct expr expr;
typedef struct macro macro;
typedef struct source source;
typedef struct listing listing;

#include "cpu.h"
#include "reloc.h"
#include "syntax.h"
#include "symtab.h"
#include "vmath.h"
#include "supp.h"
#include "error.h"
#include "expr.h"
#include "parse.h"
#include "atom.h"

#if defined(BIGENDIAN)&&!defined(LITTLEENDIAN)
#define LITTLEENDIAN (!BIGENDIAN)
#endif

#if !defined(BIGENDIAN)&&defined(LITTLEENDIAN)
#define BIGENDIAN (!LITTLEENDIAN)
#endif

#ifndef MNEMONIC_VALID
#define MNEMONIC_VALID(i) 1
#endif

#ifndef OPERAND_OPTIONAL
#define OPERAND_OPTIONAL(p,t) 0
#endif

#ifndef START_PARENTH
#define START_PARENTH(x) ((x)=='(')
#endif

#ifndef END_PARENTH
#define END_PARENTH(x) ((x)==')')
#endif

#ifndef CHKIDEND
#define CHKIDEND(s,e) (e)
#endif

#define MAXPATHLEN 1024

/* include paths */
struct include_path {
  struct include_path *next;
  char *path;
};

/* source texts (main file, include files or macros) */
struct source {
  struct source *parent;
  int parent_line;
  char *name;
  char *text;
  size_t size;
  unsigned long repeat;
  int cond_level;
  int num_params;
  char *param[MAXMACPARAMS];
  int param_len[MAXMACPARAMS];
  struct macarg *param_names;
  unsigned long id;
  char *srcptr;
  int line;
  char *linebuf;
#ifdef CARGSYM
  expr *cargexp;
#endif
#ifdef REPTNSYM
  long reptn;
#endif
};

/* symbol types */
#define LABSYM 1
#define IMPORT 2
#define EXPRESSION 3

/* symbol flags */
#define TYPE(sym) ((sym)->flags&7)
#define TYPE_UNKNOWN  0
#define TYPE_OBJECT   1
#define TYPE_FUNCTION 2
#define TYPE_SECTION  3
#define TYPE_FILE     4

#define EXPORT (1<<3)
#define INEVAL (1<<4)
#define COMMON (1<<5)
#define WEAK (1<<6)
#define VASMINTERN (1<<7)
#define RSRVD_S (1L<<24)    /* bits 24..27 are reserved for syntax modules */
#define RSRVD_O (1L<<28)    /* bits 28..31 are reserved for output modules */

struct symbol {
  struct symbol *next;
  int type;
  uint32_t flags;
  char *name;
  expr *expr;
  expr *size;
  section *sec;
  taddr pc;
  taddr align;
  uint32_t idx; /* usable by output module */
};

/* section flags */
#define HAS_SYMBOLS 1
#define RESOLVE_WARN 2
#define UNALLOCATED 4
#define LABELS_ARE_LOCAL 8

/* section description */
struct section {
  struct section *next;
  char *name;
  char *attr;
  atom *first;
  atom *last;
  taddr align;
  uint32_t flags;
  taddr org;
  taddr pc;
  uint32_t idx; /* usable by output module */
};

/* mnemonic description */
typedef struct mnemonic {
  char *name;
#if MAX_OPERANDS!=0
  int operand_type[MAX_OPERANDS];
#endif
  mnemonic_extension ext;
} mnemonic;

/* listing table */

#define MAXLISTSRC 120

struct listing {
  listing *next;
  source *src;
  int line;
  int error;
  atom *atom;
  section *sec;
  taddr pc;
  char txt[MAXLISTSRC];
};


extern listing *first_listing,*last_listing,*cur_listing;
extern int done,final_pass;
extern int listena,listformfeed,listlinesperpage,listnosyms;
extern int mnemonic_cnt;
extern int nocase,no_symbols,pic_check;
extern hashtable *mnemohash;
extern source *cur_src;
extern section *current_section;
extern char *filename;
extern char *debug_filename;  /* usually an absolute C source file name */
extern char *inname,*outname,*listname;
extern int secname_attr;
extern char *output_format;
extern char emptystr[];
extern char vasmsym_name[];

extern unsigned long long taddrmask;
#define UNS_TADDR(x) (((unsigned long long)x)&taddrmask)

/* provided by main assembler module */
extern int debug;

void leave(void);
void fail(char *);
void set_default_output_format(char *);
FILE *locate_file(char *,char *);
void include_source(char *);
symbol *new_abs(char *,expr *);
symbol *new_import(char *);
symbol *new_labsym(section *,char *);
symbol *new_tmplabel(section *);
symbol *internal_abs(char *);
expr *set_internal_abs(char *,taddr);
void add_symbol(symbol *);
symbol *find_symbol(char *);
char *make_local_label(char *,int,char *,int);
source *new_source(char *,char *,size_t);
section *new_section(char *,char *,int);
void new_org(taddr);
section *find_section(char *,char *);
void switch_section(char *,char *);
void switch_offset_section(char *,taddr);
void add_align(section *,taddr,expr *,int,unsigned char *);
section *default_section(void);
void print_section(FILE *,section *);
void print_symbol(FILE *,symbol *);
void new_include_path(char *);
void set_listing(int);
void set_list_title(char *,int);
void write_listing(char *);

#define setfilename(x) filename=(x)
#define getfilename() filename
#define setdebugname(x) debug_filename=(x)
#define getdebugname() debug_filename

/* provided by cpu.c */
extern int bitsperbyte;
extern int bytespertaddr;
extern mnemonic mnemonics[];
extern char *cpu_copyright;
extern char *cpuname;
extern int debug;

int init_cpu();
int cpu_args(char *);
char *parse_cpu_special(char *);
operand *new_operand();
int parse_operand(char *text,int len,operand *out,int requires);
#define PO_SKIP 2
#define PO_MATCH 1
#define PO_NOMATCH 0
#define PO_CORRUPT -1
taddr instruction_size(instruction *,section *,taddr);
dblock *eval_instruction(instruction *,section *,taddr);
dblock *eval_data(operand *,taddr,section *,taddr);
#if HAVE_INSTRUCTION_EXTENSION
void init_instruction_ext(instruction_ext *);
#endif
#if MAX_QUALIFIERS!=0
char *parse_instruction(char *,int *,char **,int *,int *);
int set_default_qualifiers(char **,int *);
#endif
#if HAVE_CPU_OPTS
void cpu_opts_init(section *);
void cpu_opts(void *);
void print_cpu_opts(FILE *,void *);
#endif

/* provided by syntax.c */
extern char *syntax_copyright;
extern char commentchar;
extern hashtable *dirhash;
extern char *defsectname;
extern char *defsecttype;

int init_syntax();
int syntax_args(char *);
void parse(void);
char *skip(char *);
char *skip_operand(char *);
void eol(char *);
char *const_prefix(char *,int *);
char *get_local_label(char **);

/* provided by output_xxx.c */
int init_output_test(char **,void (**)(FILE *,section *,symbol *),int (**)(char *));
int init_output_elf(char **,void (**)(FILE *,section *,symbol *),int (**)(char *));
int init_output_bin(char **,void (**)(FILE *,section *,symbol *),int (**)(char *));
int init_output_vobj(char **,void (**)(FILE *,section *,symbol *),int (**)(char *));
int init_output_hunk(char **,void (**)(FILE *,section *,symbol *),int (**)(char *));
int init_output_hunkexe(char **,void (**)(FILE *,section *,symbol *),int (**)(char *));
int init_output_aout(char **,void (**)(FILE *,section *,symbol *),int (**)(char *));
int init_output_tos(char **,void (**)(FILE *,section *,symbol *),int (**)(char *));
