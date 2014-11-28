	;; sm194drv.s
Trap_02 	equ	$88			; address of trap #2 vector (vdi/aes)
Trap_14 	equ	$B8			; address of trap #14 vector (xbios)

phystop		equ	$42e	                ; physical st memory top
_sshiftmd	equ	$44C			; shadow register for shifter mode
_longframe	equ	$59E			; 0=68000, else 68010/20/30

VDI		equ	$73			; VDI ID in TRAP #2
v_opnwk 	equ	  1			; Open Workstation ( VDI 1 )

;; gemdos calls
Ptermres	equ	$31			; terminate and stay resident

;;  xbios calls
Physbase	equ	 2			; 	
Getrez		equ	 4			; 
Setscreen	equ	 5			; 

VIDMEM          equ      $c00000 		; Viking/SM194 compatible video memory location
VIDMEM_HI       equ      $e80000		; MiST STEroids video memory location
PLANES          equ      1
WIDTH           equ      1280
HEIGHT          equ      1024
BPL		equ	 WIDTH/8
SHFTMD          equ      2
	
Xbra_ID         equ      'mvhi'
	
start:	
		bra	init
	
		dc.l 	'Xbra'
		dc.l 	Xbra_ID
old_trap2:	dc.l 	0

new_trap2:
		movem.l	a0/A1,-(sp) 		; save a0/a1
		cmp.w	#VDI,D0 		; VDI call?
		bne.s	do_trap2_orig 		; no -> original routine
		move.l	D1,a0 			; pointer to VDI parameter block
		move.l	(a0),A1 		; pointer to control array
		cmp.w	#v_opnwk,(A1)		; opcode is "open workstation"?
		beq.s	new_v_opnwk

do_trap2_orig:	
		movem.l	(sp)+,a0/A1 		; restore a0/a1
do_trap2_modified:	
		move.l	old_trap2(pc),-(sp) 	; call original routine
		RTS

new_v_opnwk:	
		move.l	4(a0),A1 		; pointer to intin array
		cmp.w	#9,(A1)			; is it a screen driver?
		bgt.s	do_trap2_orig           ; no, call original handler
		tst.w	_longframe.w
		beq.s	v_opnwk_000 		; runs in normal 68000
		clr.w	-(sp)			; extra word for 68010+
		move.l	#v_opnwk_postproc,-(sp)	; create modified return address
		move.w	14(sp),-(sp)		; keep status register
		bra.s	label72

v_opnwk_000:	
		move.l	#v_opnwk_postproc,-(sp)	; create modified return address
		move.w	12(sp),-(sp)		; keep status register
label72:	
		or.w	#$2000,(sp) 		; set supervisor in saved status
		bra.s	do_trap2_modified	; call original routine and our own afterwards
	
v_opnwk_postproc:				; do some post processing
		move.l	12(a0),A1
		move.w	#WIDTH-1,(A1)
		move.w	#HEIGHT-1,2(A1)
		movem.l	D0-D3,-(sp)
		move.l	linea_vec(PC),a0
		move.l	sys_font(PC),A1
		jsr	linea_update
		movem.l	(sp)+,D0-D3
		movem.l	(sp)+,a0/A1
		rte

linea_update:	
		moveq	#0,D2			; clear D2/D3
		move.l	D2,D3
		move.w	#WIDTH-1,D2 		; last pixel column
		move.w	D2,-$2b4(a0) 		; data returned by v_openwk
		move.w	#HEIGHT-1,D3		; last pixel row
		move.w	D3,-$2b4+2(a0)
		addq.w	#1,D2			; screen width
		addq.w	#1,D3			; screen height
		move.w	D2,-12(a0)		; screen width in pixels
		move.w	D3,-4(a0)		; screen height in pixels
		move.w	$52(A1),D0		; height of system font
		move.w	D0,-$2e(a0)		; character height
		move.w	#BPL,D1
		move.w	D1,2(a0) 		; bytes per line
		mulu.w	D0,D1			; character height * screen width
		move.w	D1,-$28(a0)		; size of character line in bytes
		divu.w	D0,D3			; screen height / character height
		subq.w	#1,D3			; last character row
		move.w	D3,-$2a(a0)		; max cursor row
		move.w	#BPL,-2(a0)		; bytes per line
		divu.w	$34(A1),D2		; screen width/character width
		subq.w	#1,D2			; last character column
		move.w	D2,-$2c(a0)		; max cursor column
		rts

		dc.l 	'Xbra'
		dc.l 	Xbra_ID
old_trap14:	
		dc.l 	0
new_trap14:
		move.l  USP,a0 			; assume user stack pointer is needed
		btst.b	#5,(sp)			; called while in supervisor mode?
		beq.s	trap14_do 		; no, start processing
		move.l	sp,a0 			; use supervisor stack pointer
		addq.w	#6,a0 			; skip saved return address and status register
		tst.w	_longframe.w 		; 68010 or higher?
		beq	trap14_do		; no, start processing
		addq.w	#2,a0 			; 68010+ has one word more on stack

trap14_do:	
		cmp.w	#Physbase,(a0)
		beq	new_physbase 		; call physbase() replacement
		cmp.w	#Getrez,(a0)
		beq	new_getrez 		; call getrez() replacement
		cmp.w	#Setscreen,(a0)
		beq	new_setscreen

do_trap14_orig:	
		move.l	old_trap14(PC),a0
		jmp	(a0)

new_physbase:	
		move.l	vidmem,D0 		; return screen base
		rte
	
new_getrez:
		move.w	#SHFTMD,D0 		; simply return "hirez"
		rte

new_setscreen:	
		tst.w	10(a0) 			; change shifter mode?
		bmi.s	do_setscreen_orig 	; no, simply call original routine
		btst.b	#1,11(a0) 		; hirez?
		bne.s	do_hirez
		move.b	11(a0),_sshiftmd.w	; set low/midrez in shadow register
		move.b	_sshiftmd.w,$ffff8260.w	; and in real register
do_hirez:	
		move.w	#-1,10(a0) 		; don't change resolution
do_setscreen_orig:	
		bra.s	do_trap14_orig

linea_vec:	dc.l	0
sys_font:	dc.l	0
vidmem:		dc.l	VIDMEM_HI 		; default: assume memory at e80000

init:		pea	message(pc) 		; show init message (still on old screen)
		move.w	#9,-(sp)		; CConws
		trap	#1 			; gemdos
		addq.l	#6,sp

		jsr	install
		tst.l	d0
		bne.s	quit
	
		move.l	4(sp),a0
		move.l	#init,D0
		SUB.l	a0,D0
		clr.w	-(sp)
		move.l	D0,-(sp)  		; number of bytes to keep resident
		move.w	#49,-(sp) 		; Ptermres
		trap	#1 			; gemdos
 
	
quit:
		move.l	d0,-(sp) 		; error message
		move.w	#9,-(sp)		; CConws
		trap	#1 			; gemdos
		addq.l	#6,sp

		move.l	#hitkey_msg,-(sp)	; "hit key to continue"
		move.w	#9,-(sp)		; CConws
		trap	#1 			; gemdos
		addq.l	#6,sp

		move.w  #1,-(sp)     		; CConin
		trap    #1           		; gemdos
		addq.l  #2,sp        		; Correct stack

		move.w  #0,-(sp)     		; Pterm0
		trap    #1           		; gemdos
		addq.l  #2,sp        		; Correct stack

install_new_traps:
		move.l	$8,d0			; save bus error trap
		move.l	sp,d1			; save current stack pointer

		move.l	#nohimem,$8
		clr.w	VIDMEM_HI 		; try to access video memory at e80000
		bra.s	vidmem_ok

nohimem:	move.l	d1,sp			; restore stack pointer
		move.l	#VIDMEM,vidmem 		; assume we have memory at $c00000
		move.l	#nomem,$8

		clr.w	VIDMEM		        ; cause an exception without sm194

		;; if this code is reached then there's memory at $c00000
		move.l	d0,$8			; restore bus error trap

		;; now check if it's not part of ST mem
		move.l	phystop,d0
		cmp.l	#VIDMEM,d0
		ble.s	vidmem_ok

		move.l	#toomuch_msg,d0
		rts

nomem:
		move.l	d1,sp			; restore stack pointer
		move.l	d0,$8			; restore bus error trap
		move.l	#nocard_msg,d0
		rts
	
vidmem_ok:	
		move.l	Trap_02.w,old_trap2 	; save old vdi trap #2 
		move.l	#new_trap2,Trap_02.w   	; set new one
	
		move.l	Trap_14.w,old_trap14 	; save old xbios trap #14
		move.l	#new_trap14,Trap_14.w	; set new one
	
		move.b	#SHFTMD,_sshiftmd.w
		clr.l	d0			; d0 = 0 -> success!
		rts

install:	
		pea	install_new_traps.l
		move.w	#38,-(sp) 		; Supexec	
		trap	#14			; xbios
		addq.l	#6,sp

		tst.l	d0
		bne	install_failed

		move.w	#-1,-(sp) 		; keep video mode
		move.l	#-1,-(sp) 		; keep physical address
		move.l	vidmem,-(sp)   		; new screen base as logical address
		move.w	#5,-(sp) 		; Setscreen
		trap	#14			; xbios
		lea	12(sp),sp
	
		dc.w	$a000			; get pointer to lineA variables
		move.l	a0,linea_vec		; save linea vector
		move.l	8(A1),A1		; get pointer to system font
		move.l	A1,sys_font		; save it
		move.l	76(A1),-22(a0)		; pointer to system font data
		move.w	38(A1),-18(a0) 		; ASCII value of last character in font
		move.w	36(A1),-16(a0) 		; ASCII value of first character in font
		move.w	80(A1),-14(a0)          ; width of font image
		move.l	72(A1),-10(a0) 		; pointer to character offset table
		jsr	linea_update
		move.l	vidmem,-34(a0)		; current cursor address
		clr.w	-30(a0)			; start of screen
		clr.l	-28(a0)			; clear cursor x and y position
		move.w	#PLANES,(a0)		; number of planes
	
		move.l	#messageClr,-(sp) 	; display init message on new screen
		move.w	#9,-(sp)
		trap	#1 			; gemdos	
		addq.l	#6,sp

		clr.l 	D0			; result ok
	
install_failed:	
		rts

messageClr:	dc.b $1b,'E'
message:   	dc.b $1b,'p'
		dc.b " MiST 1280x1024 Video Driver V1.1 ",$1b,'q',13,10
		dc.b " ",$bd," 2014 by Till Harbaum",13,10,0
	
nocard_msg:   	dc.b "ERROR: No video memory found. Please make sure",13,10
		dc.b "Viking support is enabled in the video settings!",13,10,0
	
toomuch_msg:   	dc.b "ERROR: Too much ST ram enabled. Please reduce",13,10
		dc.b "ST ram to 8MB or less in the system settings!",13,10,0

hitkey_msg:	dc.b "Hit a key to continue",13,10,0