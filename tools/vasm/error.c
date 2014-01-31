/* error.c - error output and modification routines */
/* (c) in 2002-2009 by Volker Barthelmann and Frank Wille */

#include <stdarg.h>
#include "vasm.h"

struct err_out general_err_out[]={
#include "general_errors.h"
};
int general_errors=sizeof(general_err_out)/sizeof(general_err_out[0]);

struct err_out syntax_err_out[]={
#include "syntax_errors.h"
};
int syntax_errors=sizeof(syntax_err_out)/sizeof(syntax_err_out[0]);

struct err_out cpu_err_out[]={
#include "cpu_errors.h"
};
int cpu_errors=sizeof(cpu_err_out)/sizeof(cpu_err_out[0]);

struct err_out output_err_out[]={
#include "output_errors.h"
};
int output_errors=sizeof(output_err_out)/sizeof(output_err_out[0]);

int errors;
int max_errors=5;
int no_warn=0;


static void print_source_line(FILE *f)
{
  static char *buf = NULL;
  char c,*e,*p,*q;
  int l;

  /* get an error line buffer only once on demand */
  if (buf == NULL)
    buf = mymalloc(MAXLINELENGTH);

  p = cur_src->text;
  q = buf;
  e = buf + MAXLINELENGTH - 1;
  l = cur_src->line;

  do {
    c = *p++;
    if (c=='\n' || c=='\r') {
      if (*p == ((c=='\n') ? '\r' : '\n'))
        p++;
      if (--l == 0) {
        /* terminate error line in buffer and print it */
        *q = '\0';
        fprintf(f,">%s\n",buf);
        return;
      }
      q = buf;  /* next line, start to fill buffer from the beginning */
    }
    else if (q < e)
      *q++ = c;
  }
  while (*p);
  ierror(0);  /* line doesn't exist */
}


static void error(int n,va_list vl,struct err_out *errlist,int offset)
{
  static source *last_err_source = NULL;
  static int last_err_no;
  static int last_err_line;
  FILE *f;
  int flags=errlist[n].flags;

  if ((flags&DONTWARN) || ((flags&WARNING) && no_warn))
    return;

  if (last_err_source) {
    /* avoid printing the same error again and again, which might happen
       when a line is evaluated in multiple passes */
    if (cur_src!=NULL && cur_src==last_err_source &&
       cur_src->line==last_err_line &&
       n+offset==last_err_no)
      return;
  }

  if ((flags&MESSAGE) && !(flags&(WARNING|ERROR|FATAL)))
    f = stdout;  /* print messages to stdout */
  else
    f = stderr;  /* otherwise stderr */

  if (cur_src) {
    last_err_source = cur_src;
    last_err_line = cur_src->line;
    last_err_no = n + offset;
  }
  fprintf(f,"\n");

  if (cur_listing)
    cur_listing->error = n + offset;

  if (flags & FATAL)
    fprintf(f,"fatal ");

  if (flags & ERROR) {
    ++errors;
    if(max_errors!=0 && errors>max_errors){
      fprintf(f,"***maximum number of errors reached!***\n");
      leave();
    }
    fprintf(f,"error");
  }
  else if (flags & WARNING)
    fprintf(f,"warning");
  else if (flags & MESSAGE)
    fprintf(f,"message");
  fprintf(f," %d",n+offset);
  if (!(flags & NOLINE) && cur_src!=NULL)
    fprintf(f," in line %d of \"%s\"",cur_src->line,cur_src->name);
  fprintf(f,": ");
  vfprintf(f,errlist[n].text,vl);
  fprintf(f,"\n");

  if (!(flags & NOLINE) && cur_src!=NULL) {
    if (cur_src->parent != NULL) {
      source *parent,*child;
    
      child = cur_src;
      while (parent = child->parent) {
        if (child->num_params >= 0)
          fprintf(f,"\tcalled");    /* macro called from */
        else
          fprintf(f,"\tincluded");  /* included from */
        fprintf(f," from line %d of \"%s\"\n",child->parent_line,parent->name);
        child = parent;
      }
    }
    print_source_line(f);
  }

  if (flags & FATAL) {
    fprintf(f,"aborting...\n");
    leave();
  }
}


void general_error(int n,...)
{
  va_list vl;
  va_start(vl,n);
  error(n,vl,general_err_out,FIRST_GENERAL_ERROR);
}


void syntax_error(int n,...)
{
  va_list vl;
  va_start(vl,n);
  error(n,vl,syntax_err_out,FIRST_SYNTAX_ERROR);
}


void cpu_error(int n,...)
{
  va_list vl;
  va_start(vl,n);
  error(n,vl,cpu_err_out,FIRST_CPU_ERROR);
}


void output_error(int n,...)
{
  va_list vl;
  va_start(vl,n);
  error(n,vl,output_err_out,FIRST_OUTPUT_ERROR);
}


static void modify_errors(struct err_out *err,int flags,va_list vl)
{
  int n;

  while (n = va_arg(vl,int)) {
    err[n].flags = flags;
  }
  va_end(vl);
}


void modify_syntax_err(int flags,...)
{
  va_list vl;
  va_start(vl,flags);
  modify_errors(syntax_err_out,flags,vl);
}


void modify_cpu_err(int flags,...)
{
  va_list vl;
  va_start(vl,flags);
  modify_errors(cpu_err_out,flags,vl);
}


static void dontwarn(struct err_out *err,int errnum,int first,int max)
{
  int n = errnum-first;

  if (n>=0 && n<max) {
    if (err[n].flags & WARNING) {
      err[n].flags |= DONTWARN;
      return;
    }
  }
  general_error(33,errnum);
}


void disable_warning(int n)
{
  if (n >= FIRST_OUTPUT_ERROR)
    dontwarn(output_err_out,n,FIRST_OUTPUT_ERROR,output_errors);
  else if (n >= FIRST_CPU_ERROR)
    dontwarn(cpu_err_out,n,FIRST_CPU_ERROR,cpu_errors);
  else if (n >= FIRST_SYNTAX_ERROR)
    dontwarn(syntax_err_out,n,FIRST_SYNTAX_ERROR,syntax_errors);
  else if (n >= FIRST_GENERAL_ERROR)
    dontwarn(general_err_out,n,FIRST_GENERAL_ERROR,general_errors);
}
