/* expr.c expression handling for vasm */
/* (c) in 2002-2012 by Volker Barthelmann */

enum {
  ADD,SUB,MUL,DIV,MOD,NEG,CPL,LAND,LOR,BAND,BOR,XOR,NOT,LSH,RSH,
  LT,GT,LEQ,GEQ,NEQ,EQ,NUM,SYM,CPC
};
#define LAST_EXP_TYPE CPC

struct expr {
  int type;
  struct expr *left;
  struct expr *right;
  union {
    taddr val;
    symbol *sym;
  } c;
};

/* Macros for extending the unary operation types (e.g. '<' and '>' for 6502).
   Cpu module has to define EXT_UNARY_EVAL(type,val,res,c) for evaluation. */
#ifndef EXT_UNARY_NAME
#define EXT_UNARY_NAME(s) 0
#endif
#ifndef EXT_UNARY_TYPE
#define EXT_UNARY_TYPE(s) NOT
#endif

/* global variables */
extern char current_pc_char;

/* functions */
expr *new_expr(void);
expr *make_expr(int,expr *,expr *);
expr *copy_tree(expr *);
expr *curpc_expr(void);
expr *parse_expr(char **);
expr *parse_expr_tmplab(char **);
taddr parse_constexpr(char **);
expr *number_expr(taddr);
void free_expr(expr *);
void simplify_expr(expr *);
int eval_expr(expr *,taddr *,section *,taddr);
void print_expr(FILE *,expr *);
int find_base(expr *,symbol **,section *,taddr);

/* find_base return codes */
#define BASE_ILLEGAL 0
#define BASE_OK 1
#define BASE_PCREL 2
