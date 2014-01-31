/* output_bin.c binary output driver for vasm */
/* (c) in 2002-2009 by Volker Barthelmann */

#include "vasm.h"

static char *copyright="vasm binary output module 1.6 (c) 2002-2009 Volker Barthelmann";

#define BINFMT_RAW      0
#define BINFMT_CBMPRG   1   /* Commodore VIC-20/C-64 PRG format */
static int binfmt = BINFMT_RAW;


static void write_output(FILE *f,section *sec,symbol *sym)
{
  section *s,*s2;
  atom *p;
  taddr pc,npc,i;

  if (!sec)
    return;

  for (; sym; sym=sym->next) {
    if (sym->type == IMPORT)
      output_error(6,sym->name);  /* undefined symbol */
  }

  /* we don't support overlapping sections */
  for (s=sec; s; s=s->next) {
    for (s2=sec; s2; s2=s2->next) {
      if (s2!=s &&
          ((s2->org >= s->org && s2->org < s->pc) ||
           (s2->pc > s->org && s2->pc <= s->pc)))
        output_error(0);
    }
  }

  if (binfmt == BINFMT_CBMPRG) {
    /* Commodore PRG header:
     * 00: LSB of load address
     * 01: MSB of load address
     */
    fw8(f,sec->org&0xff);
    fw8(f,(sec->org>>8)&0xff);
  }

  for (s=sec; s; s=s->next) {
    if (s!=sec && s->org>pc) {
      /* fill gap between sections with zeros */
      for (; pc<s->org; pc++)
        fw8(f,0);
    }
    else
      pc = s->org;

    for (p=s->first; p; p=p->next) {
      npc = (pc + p->align - 1) / p->align * p->align;
      for (i=0; i<npc-pc; i++)
        fw8(f,0);

      if (p->type == DATA) {
        for (i=0; i<p->content.db->size; i++)
          fw8(f,(unsigned char)p->content.db->data[i]);
      }
      else if (p->type == SPACE) {
        fwsblock(f,p->content.sb);
      }
      pc = npc + atom_size(p,s,npc);
    }
  }
}


static int output_args(char *p)
{
  if (!strcmp(p,"-cbm-prg")) {
    binfmt = BINFMT_CBMPRG;
    return 1;
  }
  return 0;
}


int init_output_bin(char **cp,void (**wo)(FILE *,section *,symbol *),int (**oa)(char *))
{
  *cp = copyright;
  *wo = write_output;
  *oa = output_args;
  return 1;
}
