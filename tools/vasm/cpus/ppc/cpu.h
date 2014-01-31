/*
** cpu.h PowerPC cpu-description header-file
** (c) in 2002,2006,2011 by Frank Wille
*/

extern int ppc_endianess;
#define BIGENDIAN (ppc_endianess)
#define LITTLEENDIAN (!ppc_endianess)
#define VASM_CPU_PPC 1
#define MNEMOHTABSIZE 0x18000

/* maximum number of operands for one mnemonic */
#define MAX_OPERANDS 5

/* maximum number of mnemonic-qualifiers per mnemonic */
#define MAX_QUALIFIERS 0

/* data type to represent a target-address */
typedef int64_t taddr;

/* minimum instruction alignment */
#define INST_ALIGN 4

/* default alignment for n-bit data */
#define DATA_ALIGN(n) ppc_data_align(n)

/* operand class for n-bit data definitions */
#define DATA_OPERAND(n) ppc_data_operand(n)

/* returns true when instruction is valid for selected cpu */
#define MNEMONIC_VALID(i) ppc_available(i)

/* returns true when operand type is optional; may init default operand */
#define OPERAND_OPTIONAL(p,t) ppc_operand_optional(p,t)

/* special data operand types: */
#define OP_D8  0x1001
#define OP_D16 0x1002
#define OP_D32 0x1003
#define OP_D64 0x1004

/* PPC specific relocations */
#define REL_PPCEABI_SDA2 (LAST_STANDARD_RELOC+1)
#define REL_PPCEABI_SDA21 (LAST_STANDARD_RELOC+2)
#define REL_PPCEABI_SDAI16 (LAST_STANDARD_RELOC+3)
#define REL_PPCEABI_SDA2I16 (LAST_STANDARD_RELOC+4)
#define REL_MORPHOS_DREL (LAST_STANDARD_RELOC+5)
#define REL_AMIGAOS_BREL (LAST_STANDARD_RELOC+6)
#define LAST_PPC_RELOC (LAST_STANDARD_RELOC+6)


/* type to store each operand */
typedef struct {
  int16_t type;
  unsigned char attr;   /* reloc attribute != REL_NONE when present */
  unsigned char mode;   /* @l/h/ha */
  expr *value;
  expr *basereg;  /* only for d(Rn) load/store addressing mode */
} operand;

/* operand modifier */
#define OPM_NONE 0
#define OPM_LO 1  /* low 16 bits */
#define OPM_HI 2  /* high 16 bits */
#define OPM_HA 3  /* high 16 bits with addi compensation */


/* additional mnemonic data */
typedef struct {
  uint32_t available;
  uint32_t opcode;
} mnemonic_extension;

/* Values defined for the 'available' field of mnemonic_extension.  */
#define CPU_TYPE_PPC          (1)
#define CPU_TYPE_POWER        (2)
#define CPU_TYPE_POWER2       (4)
#define CPU_TYPE_601          (8)
#define CPU_TYPE_COMMON       (0x10)
#define CPU_TYPE_ALTIVEC      (0x20)
#define CPU_TYPE_ANY          (0x10000000)
#define CPU_TYPE_64_BRIDGE    (0x20000000)
#define CPU_TYPE_32           (0x40000000)
#define CPU_TYPE_64           (0x80000000)

/* Shortcuts for known PPC models */
#undef  PPC
#define PPC     (CPU_TYPE_PPC | CPU_TYPE_ANY)
#define PPCCOM  (CPU_TYPE_PPC | CPU_TYPE_COMMON | CPU_TYPE_ANY)
#define PPC32   (CPU_TYPE_PPC | CPU_TYPE_32 | CPU_TYPE_ANY)
#define PPC64   (CPU_TYPE_PPC | CPU_TYPE_64 | CPU_TYPE_ANY)
#define PPCONLY CPU_TYPE_PPC
#define PPC403  PPC
#define PPC405  PPC403
#define PPC750  PPC
#define PPC860  PPC
#define PPCVEC  (CPU_TYPE_ALTIVEC | CPU_TYPE_ANY)
#define POWER   (CPU_TYPE_POWER | CPU_TYPE_ANY)
#define POWER2  (CPU_TYPE_POWER | CPU_TYPE_POWER2 | CPU_TYPE_ANY)
#define PPCPWR2 (CPU_TYPE_PPC | CPU_TYPE_POWER | CPU_TYPE_POWER2 | CPU_TYPE_ANY)
#define POWER32 (CPU_TYPE_POWER | CPU_TYPE_ANY | CPU_TYPE_32)
#define COM     (CPU_TYPE_POWER | CPU_TYPE_PPC | CPU_TYPE_COMMON | CPU_TYPE_ANY)
#define COM32   (CPU_TYPE_POWER | CPU_TYPE_PPC | CPU_TYPE_COMMON | CPU_TYPE_ANY | CPU_TYPE_32)
#define M601    (CPU_TYPE_POWER | CPU_TYPE_601 | CPU_TYPE_ANY)
#define PWRCOM  (CPU_TYPE_POWER | CPU_TYPE_601 | CPU_TYPE_COMMON | CPU_TYPE_ANY)
#define MFDEC1  CPU_TYPE_POWER
#define MFDEC2  (CPU_TYPE_PPC | CPU_TYPE_601)


/* Macros used to form opcodes */
#define OP(x) ((((uint32_t)(x)) & 0x3f) << 26)
#define OPTO(x,to) (OP (x) | ((((uint32_t)(to)) & 0x1f) << 21))
#define OPL(x,l) (OP (x) | ((((uint32_t)(l)) & 1) << 21))
#define A(op, xop, rc) \
  (OP (op) | ((((uint32_t)(xop)) & 0x1f) << 1) | (((uint32_t)(rc)) & 1))
#define B(op, aa, lk) (OP (op) | ((((uint32_t)(aa)) & 1) << 1) | ((lk) & 1))
#define BBO(op, bo, aa, lk) (B ((op), (aa), (lk)) | ((((uint32_t)(bo)) & 0x1f) << 21))
#define BBOCB(op, bo, cb, aa, lk) \
  (BBO ((op), (bo), (aa), (lk)) | ((((uint32_t)(cb)) & 0x3) << 16))
#define DSO(op, xop) (OP (op) | ((xop) & 0x3))
#define M(op, rc) (OP (op) | ((rc) & 1))
#define MME(op, me, rc) (M ((op), (rc)) | ((((uint32_t)(me)) & 0x1f) << 1))
#define MD(op, xop, rc) \
  (OP (op) | ((((uint32_t)(xop)) & 0x7) << 2) | ((rc) & 1))
#define MDS(op, xop, rc) \
  (OP (op) | ((((uint32_t)(xop)) & 0xf) << 1) | ((rc) & 1))
#define SC(op, sa, lk) (OP (op) | ((((uint32_t)(sa)) & 1) << 1) | ((lk) & 1))
#define VX(op, xop) (OP (op) | (((uint32_t)(xop)) & 0x7ff))
#define VXA(op, xop) (OP (op) | (((uint32_t)(xop)) & 0x07f))
#define VXR(op, xop, rc) \
  (OP (op) | (((rc) & 1) << 10) | (((uint32_t)(xop)) & 0x3ff))
#define X(op, xop) (OP (op) | ((((uint32_t)(xop)) & 0x3ff) << 1))
#define XRC(op, xop, rc) (X ((op), (xop)) | ((rc) & 1))
#define XCMPL(op, xop, l) (X ((op), (xop)) | ((((uint32_t)(l)) & 1) << 21))
#define XTO(op, xop, to) (X ((op), (xop)) | ((((uint32_t)(to)) & 0x1f) << 21))
#define XTLB(op, xop, sh) (X ((op), (xop)) | ((((uint32_t)(sh)) & 0x1f) << 11))
#define XFL(op, xop, rc) \
  (OP (op) | ((((uint32_t)(xop)) & 0x3ff) << 1) | (((uint32_t)(rc)) & 1))
#define XL(op, xop) (OP (op) | ((((uint32_t)(xop)) & 0x3ff) << 1))
#define XLLK(op, xop, lk) (XL ((op), (xop)) | ((lk) & 1))
#define XLO(op, bo, xop, lk) \
  (XLLK ((op), (xop), (lk)) | ((((uint32_t)(bo)) & 0x1f) << 21))
#define XLYLK(op, xop, y, lk) \
  (XLLK ((op), (xop), (lk)) | ((((uint32_t)(y)) & 1) << 21))
#define XLOCB(op, bo, cb, xop, lk) \
  (XLO ((op), (bo), (xop), (lk)) | ((((uint32_t)(cb)) & 3) << 16))
#define XO(op, xop, oe, rc) \
  (OP (op) | ((((uint32_t)(xop)) & 0x1ff) << 1) | \
   ((((uint32_t)(oe)) & 1) << 10) | (((uint32_t)(rc)) & 1))
#define XS(op, xop, rc) \
  (OP (op) | ((((uint32_t)(xop)) & 0x1ff) << 2) | (((uint32_t)(rc)) & 1))
#define XFXM(op, xop, fxm) \
  (X ((op), (xop)) | ((((uint32_t)(fxm)) & 0xff) << 12))
#define XSPR(op, xop, spr) \
  (X ((op), (xop)) | ((((uint32_t)(spr)) & 0x1f) << 16) | \
   ((((uint32_t)(spr)) & 0x3e0) << 6))
#define XDS(op, xop, at) \
  (X ((op), (xop)) | ((((uint32_t)(at)) & 1) << 25))

/* The BO encodings used in extended conditional branch mnemonics.  */
#define BODNZF  (0x0)
#define BODNZFP (0x1)
#define BODZF   (0x2)
#define BODZFP  (0x3)
#define BOF     (0x4)
#define BOFP    (0x5)
#define BODNZT  (0x8)
#define BODNZTP (0x9)
#define BODZT   (0xa)
#define BODZTP  (0xb)
#define BOT     (0xc)
#define BOTP    (0xd)
#define BODNZ   (0x10)
#define BODNZP  (0x11)
#define BODZ    (0x12)
#define BODZP   (0x13)
#define BOU     (0x14)

/* The BI condition bit encodings used in extended conditional branch
   mnemonics.  */
#define CBLT    (0)
#define CBGT    (1)
#define CBEQ    (2)
#define CBSO    (3)

/* The TO encodings used in extended trap mnemonics.  */
#define TOLGT   (0x1)
#define TOLLT   (0x2)
#define TOEQ    (0x4)
#define TOLGE   (0x5)
#define TOLNL   (0x5)
#define TOLLE   (0x6)
#define TOLNG   (0x6)
#define TOGT    (0x8)
#define TOGE    (0xc)
#define TONL    (0xc)
#define TOLT    (0x10)
#define TOLE    (0x14)
#define TONG    (0x14)
#define TONE    (0x18)
#define TOU     (0x1f)


/* Prototypes */
int ppc_data_align(int);
int ppc_data_operand(int);
int ppc_available(int);
int ppc_operand_optional(operand *,int);
