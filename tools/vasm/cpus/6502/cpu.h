/*
** cpu.h 650x/651x cpu-description header-file
** (c) in 2002,2008,2009 by Frank Wille
*/

#define BIGENDIAN 0
#define LITTLEENDIAN 1
#define VASM_CPU_650X 1

/* maximum number of operands for one mnemonic */
#define MAX_OPERANDS 2

/* maximum number of mnemonic-qualifiers per mnemonic */
#define MAX_QUALIFIERS 0

/* data type to represent a target-address */
typedef int16_t taddr;

/* minimum instruction alignment */
#define INST_ALIGN 1

/* default alignment for n-bit data */
#define DATA_ALIGN(n) 1

/* operand class for n-bit data definitions */
#define DATA_OPERAND(n) DATAOP

/* returns true when instruction is valid for selected cpu */
#define MNEMONIC_VALID(i) cpu_available(i)

/* we define two additional unary operations, '<' and '>' */
int ext_unary_eval(int,taddr,taddr *,int);
int ext_find_base(symbol **,expr *,section *,taddr);
#define LOBYTE (LAST_EXP_TYPE+1)
#define HIBYTE (LAST_EXP_TYPE+2)
#define EXT_UNARY_NAME(s) (*s=='<'||*s=='>')
#define EXT_UNARY_TYPE(s) (*s=='<'?LOBYTE:HIBYTE)
#define EXT_UNARY_EVAL(t,v,r,c) ext_unary_eval(t,v,r,c)
#define EXT_FIND_BASE(b,e,s,p) ext_find_base(b,e,s,p)

/* type to store each operand */
typedef struct {
  int type;
  expr *value;
} operand;


/* additional mnemonic data */
typedef struct {
  unsigned char opcode;
  unsigned char zp_opcode;  /* !=0 means optimization to zero page allowed */
  uint16_t available;
} mnemonic_extension;

/* available */
#define M6502    1       /* standard 6502 instruction set */
#define ILL      2       /* illegal 6502 instructions */
#define DTV      4       /* C64 DTV instruction set extension */


/* adressing modes */
#define IMPLIED  0
#define ABS      1       /* $1234 */
#define ABSX     2       /* $1234,X */
#define ABSY     3       /* $1234,Y */
#define INDIR    4       /* ($1234) - JMP only */
#define INDX     5       /* ($12,X) */
#define INDY     6       /* ($12),Y */
#define ZPAGE    7       /* add ZPAGE-ABS to optimize ABS/ABSX/ABSY */
#define ZPAGEX   8
#define ZPAGEY   9
#define RELJMP   10      /* B!cc/JMP construction */
#define REL      11      /* $1234 - relative branch */
#define IMMED    12      /* #$12 */
#define DATAOP	 13	 /* data operand */
#define ACCU     14      /* A */
#define DUMX     15      /* dummy X as 'second' operand */
#define DUMY     16      /* dummy Y as 'second' operand */


/* exported by cpu.c */
int cpu_available(int);
