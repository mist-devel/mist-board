/* supp.c miscellaneous support routines */
/* (c) in 2008-2010 by Frank Wille */

#include "vasm.h"
#include "supp.h"


void initlist(struct list *l)
/* initializes a list structure */
{
  l->first = (struct node *)&l->dummy;
  l->dummy = NULL;
  l->last = (struct node *)&l->first;
}


void addtail(struct list *l,struct node *n)
/* add node as last element of list */
{
  struct node *ln = l->last;

  n->next = ln->next;
  ln->next = n;
  n->pred = ln;
  l->last = n;
}


struct node *remnode(struct node *n)
/* remove a node from a list */
{
  n->next->pred = n->pred;
  n->pred->next = n->next;
  return n;
}


struct node *remhead(struct list *l)
/* remove first node in list and return a pointer to it */
{
  struct node *n = l->first;

  if (n->next) {
    l->first = n->next;
    n->next->pred = n->pred;
    return n;
  }
  return NULL;
}


void *mymalloc(size_t sz)
{
  size_t *p;

  if (debug) {
    p = malloc(sz+2*sizeof(size_t));
    if (!p)
      general_error(17);
    p++;
    *p++ = sz;
    memset(p,0xdd,sz);  /* make it crash, when using uninitialized memory */
  }
  else {
    p = malloc(sz);
    if(!p)
      general_error(17);
  }
  return p;
}


void *mycalloc(size_t sz)
{
  void *p = mymalloc(sz);

  memset(p,0,sz);
  return p;
}


void *myrealloc(void *old,size_t sz)
{
  size_t *p;

  if (debug) {
    p = realloc(old?((size_t *)old)-2:0,sz+2*sizeof(size_t));
    if (!p)
      general_error(17);
    p++;
    *p++ = sz;
  }
  else {
    p = realloc(old,sz);
    if (!p)
      general_error(17);
  }
  return p;
}


void myfree(void *p)
{
  if (p) {
    if (debug) {
      size_t *myp = (size_t *)p;
      size_t sz = *(--myp);
      memset(p,0xff,sz);  /* make it crash, when reusing deallocated memory */
      free(--myp);
    }
    else
      free(p);
  }
}


uint64_t readval(int be,void *src,size_t size)
/* read value with given endianess */
{
  unsigned char *s = src;
  uint64_t val = 0;

  if (size > sizeof(uint64_t))
    ierror(0);
  if (be) {
    while (size--) {
      val <<= 8;
      val += (uint64_t)*s++;
    }
  }
  else {
    s += size;
    while (size--) {
      val <<= 8;
      val += (uint64_t)*(--s);
    }
  }
  return val;
}


void *setval(int be,void *dest,size_t size,uint64_t val)
/* write value to destination with desired endianess */
{
  unsigned char *d = dest;

  if (size > sizeof(uint64_t))
    ierror(0);
  if (be) {
    d += size;
    dest = d;
    while (size--) {
      *(--d) = (unsigned char)val;
      val >>= 8;
    }
    d += size;
  }
  else {
    while (size--) {
      *d++ = (unsigned char)val;
      val >>= 8;
    }
    dest = d;
  }
  return dest;
}


uint64_t readbits(int be,void *p,unsigned bfsize,unsigned offset,unsigned size)
/* read value from a bitfield (max. 64 bits) */
{
  if ((bfsize&7)==0 && offset+size<=bfsize) {
    uint64_t mask = (1 << size) - 1;
    uint64_t val = readval(be,p,bfsize>>3);

    return be ? ((val >> (bfsize-(offset+size))) & mask)
              : ((val >> offset) & mask);
  }
  ierror(0);
  return 0;
}


void setbits(int be,void *p,unsigned bfsize,unsigned offset,unsigned size,
             uint64_t d)
/* write value to a bitfield (max. 64 bits) */
{
  if ((bfsize&7)==0 && offset+size<=bfsize) {
    uint64_t mask = MAKEMASK(size);
    uint64_t val = readval(be,p,bfsize>>3);
    int s = be ? bfsize - (offset + size) : offset;

    setval(be,p,bfsize>>3,(val & ~(mask<<s)) | ((d & mask) << s));
  }
  else
    ierror(0);
}


void copy_cpu_taddr(void *dest,taddr val,size_t bytes)
/* copy 'bytes' low-order bytes from val to dest in cpu's endianess */
{
  unsigned char *d = dest;
  int i;

  if (bytes > sizeof(taddr))
    ierror(0);
  if (BIGENDIAN) {
    for (i=bytes-1; i>=0; i--,val>>=8)
      d[i] = (unsigned char)val;
  }
  else if (LITTLEENDIAN) {
    for (i=0; i<(int)bytes; i++,val>>=8)
      d[i] = (unsigned char)val;
  }
  else
    ierror(0);
}


void fw8(FILE *f,unsigned char x)
{
  if (fputc(x,f) == EOF)
    output_error(2);  /* write error */
}


void fw32(FILE *f,unsigned long x,int be)
{
  if (be) {
    fw8(f,(x>>24) & 0xff);
    fw8(f,(x>>16) & 0xff);
    fw8(f,(x>>8) & 0xff);
    fw8(f,x & 0xff);
  }
  else {
    fw8(f,x & 0xff);
    fw8(f,(x>>8) & 0xff);
    fw8(f,(x>>16) & 0xff);
    fw8(f,(x>>24) & 0xff);
  }
}


void fwdata(FILE *f,void *d,size_t n)
{
  if (n) {
    if (!fwrite(d,1,n,f))
      output_error(2);  /* write error */
  }
}


void fwalign(FILE *f,taddr n,taddr align)
{
  taddr i;

  for (i=0,n=balign(n,align); i<n; i++)
    fw8(f,0);
}


int fwsblock(FILE *f,sblock *sb)
{
  taddr i;

  for(i=0;i<sb->space;i++){
    if(!fwrite(sb->fill,sb->size,1,f))
      return 0;
  }
  return 1;
}


size_t filesize(FILE *fp)
/* @@@ Warning! filesize() only works reliably on binary streams! @@@ */
{
  long oldpos,size;

  if ((oldpos = ftell(fp)) >= 0)
    if (fseek(fp,0,SEEK_END) >= 0)
      if ((size = ftell(fp)) >= 0)
        if (fseek(fp,oldpos,SEEK_SET) >= 0)
          return ((size_t)size);
  return -1;
}


char *convert_path(char *path)
{
  char *newpath;

#if defined(AMIGA)
  char *p = newpath = mymalloc(strlen(path)+1);

  while (*path) {
    if (*path=='.') {
      if (*(path+1)=='\0') {
        path++;
        continue;
      }
      else if (*(path+1)=='/') {
        path += 2;
        continue;
      }
      else if (*(path+1)=='.' && *(path+2)=='/')
        path += 2;
    }
    *p++ = *path++;
  }
  *p = '\0';

#elif defined(MSDOS) || defined(_WIN32)
  char *p;

  newpath = mystrdup(path);
  for (p=newpath; *p; p++) {
    if (*p == '/')
      *p = '\\';
  }

#else
  newpath = mystrdup(path);
#endif

  return newpath;
}


int stricmp(const char *str1,const char *str2)
{
  while (tolower((unsigned char)*str1) == tolower((unsigned char)*str2)) {
    if (!*str1) return 0;
    str1++; str2++;
  }
  return tolower(*(unsigned char *)str1) - tolower(*(unsigned char *)str2);
}


int strnicmp(const char *str1,const char *str2,size_t n)
{
  if (n==0) return 0;
  while (--n && tolower((unsigned char)*str1) == tolower((unsigned char)*str2)) {
    if (!*str1) return 0;
    str1++; str2++;
  }
  return tolower(*(unsigned char *)str1) - tolower(*(unsigned char *)str2);
}


char *mystrdup(char *name)
{
  char *p=mymalloc(strlen(name)+1);
  strcpy(p,name);
  return p;
}


char *cnvstr(char *name,int l)
/* converts a pair of pointer/length to a null-terminated string */
{
  char *p=mymalloc(l+1);
  memcpy(p,name,l);
  p[l]=0;
  return p;
}


char *strtolower(char *s)
/* convert a whole string to lower case */
{
  char *p;

  for (p=s; *p; p++)
    *p = tolower((unsigned char)*p);
  return s;
}


taddr balign(taddr addr,taddr a)
/* return number of bytes required to achieve alignment */
{
  return (((addr+a-1)&~(a-1)) - addr);
}


taddr palign(taddr addr,taddr a)
/* return number of bytes required to achieve alignment */
{
  return balign(addr,1<<a);
}


taddr get_sym_value(symbol *s)
/* determine symbol's value, returns alignment for common symbols */
{
  if (s->flags & COMMON) {
    return (taddr)s->align;
  }
  else if (s->type == LABSYM) {
    return s->pc;
  }
  else if (s->type == EXPRESSION) {
    if (s->expr) {
      taddr val;

      eval_expr(s->expr,&val,NULL,0);
      return val;
    }
    else
      ierror(0);
  }
  return 0;
}


taddr get_sym_size(symbol *s)
/* determine symbol's size */
{
  if (s->size) {
    taddr val;

    eval_expr(s->size,&val,NULL,0);
    return val;
  }
  return 0;
}


taddr get_sec_size(section *sec)
{
  /* section size is assumed to be in in (sec->pc - sec->org), otherwise
     we would have to calculate it from the atoms and store it there */
  return sec ? sec->pc - sec->org : 0;
}
