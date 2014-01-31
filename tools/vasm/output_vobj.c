/* output_vasm.c vobj format output driver for vasm */
/* (c) in 2002-2013 by Volker Barthelmann */

#include "vasm.h"

static char *copyright="vasm vobj output module 0.7b (c) 2002-2013 Volker Barthelmann";

/*
  Format (WILL CHANGE!):

  .byte 0x56,0x4f,0x42,0x4a
  .byte flags
    1: BIGENDIAN
    2: LITTLENDIAN
  .number bitsperbyte
  .number bytespertaddr
  .string cpu
  .number nsections [1-based]
  .number nsymbols [1-based]
  
nsymbols
  .string name
  .number type
  .number flags
  .number secindex
  .number val
  .number size

nsections
  .string name
  .string attr
  .number flags
  .number align
  .number size
  .number nrelocs
  .number databytes
  .byte[databytes]

nrelocs [standard|special]
standard
   .number type
   .number byteoffset
   .number bitoffset
   .number size
   .number mask
   .number addend
   .number symbolindex | 0 (sectionbase)

special
    .number type
    .number size
    .byte[size]

.number:[taddr]
    .byte 0--127 [0--127]
    .byte 128-255 [x-0x80 bytes little-endian]

*/

static void write_number(FILE *f,taddr val)
{
  int i;
  if(val>=0&&val<=127){
    fw8(f,val);
    return;
  }
  fw8(f,0x80+bytespertaddr);
  for(i=bytespertaddr;i>0;i--){
    fw8(f,val&0xff);
    val>>=8;
  }
}

static int size_number(taddr val)
{
  if(val>=0&&val<=127)
    return 1;
  else
    return bytespertaddr+1;
}

static void write_string(FILE *f,char *p)
{
  while(p&&*p){
    fw8(f,*p);
    p++;
  }
  fw8(f,0);
}

static int sym_valid(symbol *symp)
{
/* To ignore tmp-symbols is dangerous, as some relocations depend on
   them (e.g. when using the * (current-pc) symbol, a *tmpNNNNNN* symbol
   will be generated). */
#if 0
  if(*symp->name==' ')
    return 0;  /* ignore internal/temporary symbols */
#endif
  if (symp->flags & VASMINTERN) {
    /* do not ignore current-pc symbol, which is needed for some relocs */
    if (strcmp(symp->name," *current pc dummy*") != 0)
      return 0;  /* ignore vasm-internal symbols */
  }
  return 1;
}

static int count_relocs(rlist *rl)
{
  int nrelocs;

  for (nrelocs=0; rl; rl=rl->next) {
    if(rl->type>=FIRST_STANDARD_RELOC && rl->type<=LAST_STANDARD_RELOC)
      nrelocs++;
    else
      unsupp_reloc_error(rl);
  }
  return nrelocs;
}

static void get_section_sizes(section *sec,taddr *rsize,taddr *rdata,taddr *rnrelocs)
{
  taddr data=0,nrelocs=0;
  atom *p;
  rlist *rl;
  int i;

  sec->pc=0;
  for(p=sec->first;p;p=p->next){
    sec->pc=(sec->pc+p->align-1)/p->align*p->align;
    sec->pc+=atom_size(p,sec,sec->pc);
    if(p->type==DATA){
      data=sec->pc;
      nrelocs+=count_relocs(p->content.db->relocs);
    }
    else if(p->type==SPACE){
      if(p->content.sb->relocs){
        nrelocs+=count_relocs(p->content.sb->relocs);
        data=sec->pc;
      }else{
        for(i=0;i<p->content.sb->size;i++)
          if(p->content.sb->fill[i]!=0)
            data=sec->pc;
      }
    }
  }
  *rdata=data;
  *rsize=sec->pc;
  *rnrelocs=nrelocs;
}

static void write_data(FILE *f,section *sec,taddr data)
{
  atom *p;
  sec->pc=0;
  for(p=sec->first;p;p=p->next){
    int old=sec->pc;
    sec->pc=(sec->pc+p->align-1)/p->align*p->align;
    if(sec->pc>=data)
      return;
    for(;old<sec->pc;old++)
      fw8(f,0);
    sec->pc+=atom_size(p,sec,sec->pc);
    if(p->type==DATA)
      fwdata(f,p->content.db->data,p->content.db->size);
    else if(p->type==SPACE)
      fwsblock(f,p->content.sb);
  }
}

static void write_rlist(FILE *f,section *sec,rlist *rl)
{
  for(;rl;rl=rl->next){
    if(rl->type>=FIRST_STANDARD_RELOC&&rl->type<=LAST_STANDARD_RELOC){
      nreloc *rel=rl->reloc;
      write_number(f,rl->type);
      write_number(f,sec->pc+rel->offset/bitsperbyte);
      write_number(f,rel->offset%bitsperbyte);
      write_number(f,rel->size);
      write_number(f,rel->mask);
      write_number(f,rel->addend);
      write_number(f,rel->sym->idx);
    }
  }
}

static void write_relocs(FILE *f,section *sec)
{
  atom *p;
  rlist *rl;
  sec->pc=0;
  for(p=sec->first;p;p=p->next){
    sec->pc=(sec->pc+p->align-1)/p->align*p->align;
    if(p->type==DATA)
      write_rlist(f,sec,p->content.db->relocs);
    else if(p->type==SPACE)
      write_rlist(f,sec,p->content.sb->relocs);
    sec->pc+=atom_size(p,sec,sec->pc);
  }
}

static void write_output(FILE *f,section *sec,symbol *sym)
{
  int nsyms,nsecs;
  section *secp;
  symbol *symp;
  taddr size,data,nrelocs;

  for(nsecs=1,secp=sec;secp;secp=secp->next)
    secp->idx=nsecs++;

  for(nsyms=1,symp=sym;symp;symp=symp->next){
    if(sym_valid(symp))
      symp->idx=nsyms++;
  }

  fw32(f,0x564f424a,1); /* "VOBJ" */
  if(BIGENDIAN)
    fw8(f,1);
  else if(LITTLEENDIAN)
    fw8(f,2);
  else
    ierror(0);
  write_number(f,bitsperbyte);
  write_number(f,bytespertaddr);
  write_string(f,cpuname);
  write_number(f,nsecs-1);
  write_number(f,nsyms-1);

  for(symp=sym;symp;symp=symp->next){
    if(!sym_valid(symp))
      continue;
    write_string(f,symp->name);
    write_number(f,symp->type);
    write_number(f,symp->flags);
    write_number(f,symp->sec?symp->sec->idx:0);
    write_number(f,get_sym_value(symp));
    write_number(f,get_sym_size(symp));
  }

  for(secp=sec;secp;secp=secp->next){
    write_string(f,secp->name);
    write_string(f,secp->attr);
    write_number(f,secp->flags);
    write_number(f,secp->align);
    get_section_sizes(secp,&size,&data,&nrelocs);
    write_number(f,size);
    write_number(f,nrelocs);
    write_number(f,data);
    write_data(f,secp,data);
    write_relocs(f,secp);
  }
}

static int output_args(char *p)
{
  return 0;
}

int init_output_vobj(char **cp,void (**wo)(FILE *,section *,symbol *),int (**oa)(char *))
{
  *cp=copyright;
  *wo=write_output;
  *oa=output_args;
  return 1;
}
