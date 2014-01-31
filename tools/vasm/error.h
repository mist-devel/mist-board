/* error.h - error output and modification routines */
/* (c) in 2002-2009 by Volker Barthelmann and Frank Wille */

#ifndef ERROR_H
#define ERROR_H                                                                                

extern int errors;
extern int max_errors;
extern int no_warn;

#define FIRST_GENERAL_ERROR 1
#define FIRST_SYNTAX_ERROR 1001
#define FIRST_CPU_ERROR 2001
#define FIRST_OUTPUT_ERROR 3001

struct err_out {
  char *text;
  int flags;
};
/*  Flags for err_out.flags    */
#define ERROR       1
#define WARNING     2
#define INTERNAL    8
#define FATAL      16
#define MESSAGE    32
#define DONTWARN   64
#define NOLINE    256

#define ierror(x) general_error(4,(x),__LINE__,__FILE__)

void general_error(int n,...);
void syntax_error(int n,...);
void cpu_error(int n,...);
void output_error(int n,...);
void modify_syntax_err(int,...);
void modify_cpu_err(int,...);
void disable_warning(int);

#endif
